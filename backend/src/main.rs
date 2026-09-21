#![allow(clippy::type_complexity)]
// `clock`, `stations` and `train` live in the library half of this crate, because
// `stellwerk stations import` needs them too (see src/lib.rs). They are re-exported at the binary's
// root so that every `crate::train::…` in the modules below keeps resolving, and so that exactly
// one copy of them is compiled rather than one per target.
pub use verspaetomat_api::{clock, stations, train};

mod admin;
mod auth;
mod classify;
mod db;
mod events;
mod fixtures;
mod flags;
mod handlers;
mod journeys;
mod mail;
mod model;
mod openai;
mod pdf;
mod push;
mod redact;
mod reply;
mod rules;
mod scanner;
mod storage;

use std::sync::Arc;
use std::time::Duration;

use axum::{
    extract::DefaultBodyLimit,
    routing::{delete, get, patch, post, put},
    Router,
};
use sqlx::PgPool;
use tower_http::{cors::CorsLayer, trace::TraceLayer};

use crate::train::sim::TrainSource;
use crate::train::transitous::TransitousClient;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub train: Arc<TrainSource>,
    pub events: Arc<events::EventHub>,
    pub push: Arc<push::PushSender>,
    /// Every station we know, in memory (issue #37). Read on every nearby lookup and every time a
    /// station id has to be turned into something MOTIS answers to, so it is behind a lock that is
    /// only ever taken to clone the `Arc` out of it — an import swaps a whole new index in and no
    /// reader waits for it.
    pub stations: stations::Shared,
    /// Every feature flag a human has set (issue #41), in memory. Read wherever a flag is read
    /// and rendered once into the public document, so the whole system adds no query to any
    /// request path. Behind the same lock as `stations`, and for the same reason: an admin write
    /// swaps a whole new table in and no reader waits for it.
    pub flags: flags::Shared,
}

impl AppState {
    pub fn stations(&self) -> Arc<stations::Index> {
        self.stations.read().expect("stations lock").clone()
    }

    /// Read the table back into the index. Called at startup and after an import commits.
    pub async fn reload_stations(&self) -> anyhow::Result<usize> {
        let index = stations::load(&self.pool).await?;
        let n = index.len();
        *self.stations.write().expect("stations lock") = Arc::new(index);
        Ok(n)
    }

    pub fn flags(&self) -> Arc<flags::Table> {
        self.flags.read().expect("flags lock").clone()
    }

    /// Read the flags back into the snapshot. Called at startup and after every admin write, so
    /// a flip is in force on the next request and no handler ever queries for one.
    pub async fn reload_flags(&self) -> anyhow::Result<usize> {
        let table = flags::load(&self.pool).await?;
        let n = table.len();
        *self.flags.write().expect("flags lock") = Arc::new(table);
        Ok(n)
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info,tower_http=info,sqlx=warn".into()))
        .init();

    let pool = db::connect().await?;
    db::seed(&pool).await?;
    clock::load(&pool).await?;
    let train = Arc::new(TrainSource::new(TransitousClient::new()));
    train.load_overrides(&pool).await?;
    let events = Arc::new(events::EventHub::default());
    let push_sender = Arc::new(push::PushSender::from_env()?);
    let state = AppState {
        pool: pool.clone(),
        train: train.clone(),
        events: events.clone(),
        push: push_sender,
        stations: Arc::new(std::sync::RwLock::new(Arc::new(stations::Index::default()))),
        flags: Arc::new(std::sync::RwLock::new(Arc::new(flags::Table::default()))),
    };
    // The stations are the only reference data the app cannot be served without: with an empty
    // table the Bahnsteig has nothing to offer and the search finds nothing. Say so loudly at
    // startup rather than letting it look like a quiet day at the station.
    match state.reload_stations().await {
        Ok(0) => tracing::warn!("no stations in the table — run `stellwerk stations import` (issue #37)"),
        Ok(n) => tracing::info!(stations = n, "stations loaded"),
        Err(e) => tracing::error!(error = %e, "stations could not be loaded"),
    }
    // Flags (#41): give every descriptor in `flags.rs` a row, mark every row the registry has
    // stopped claiming, then read the lot into memory. A failure here is not fatal — an empty
    // snapshot answers every flag with the behaviour that already shipped, which is the whole
    // point of the default.
    if let Err(e) = flags::reconcile(&pool).await {
        tracing::error!(error = %e, "flags could not be reconciled");
    }
    match state.reload_flags().await {
        Ok(n) => tracing::info!(flags = n, "flags loaded"),
        Err(e) => tracing::error!(error = %e, "flags could not be loaded — every flag answers with its default"),
    }

    // Pushes: the sender taps the event bus before anything publishes.
    push::spawn(state.clone());

    // The trip follower finalises rides; we turn finalised rides into incidents.
    let mut finalised = train::follower::spawn(pool.clone(), train.clone(), state.stations.clone(), Duration::from_secs(45));
    let state_for_follower = state.clone();
    tokio::spawn(async move {
        while let Ok(ev) = finalised.recv().await {
            match handlers::on_ride_finalised(&state_for_follower, ev.ride_id).await {
                Ok(fin) => state_for_follower.events.publish(ev.customer_id, "ride", handlers::ride_arrived_payload(ev.ride_id, ev.final_delay_min, &fin)),
                Err(e) => tracing::error!("incident creation for ride {}: {e}", ev.ride_id),
            }
        }
    });
    // Journeys waiting at a transfer past their deadline are finalised `incomplete`.
    let state_for_transfers = state.clone();
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval(Duration::from_secs(60));
        loop {
            ticker.tick().await;
            match journeys::expire_transfers(&state_for_transfers).await {
                Ok(n) if n > 0 => tracing::info!(journeys = n, "transfer timeout: journeys finalised incomplete"),
                Ok(_) => {}
                Err(e) => tracing::warn!(error = %e, "transfer timeout pass failed"),
            }
            // The same minute asks about journeys that are long overdue (docs/23 §3); the
            // hourly scanner repeats the pass, and both are idempotent through `stale_asked_at`.
            match scanner::ask_stale(&state_for_transfers).await {
                Ok(n) if n > 0 => tracing::info!(journeys = n, "stale journeys: asked whether they arrived"),
                Ok(_) => {}
                Err(e) => tracing::warn!(error = %e, "stale journey pass failed"),
            }
        }
    });

    // Deadlines, reply nudges, retention: hourly on the simulated clock.
    scanner::spawn(state.clone());

    let app = Router::new()
        .route("/health", get(handlers::health))
        // identity
        .route("/v1/devices", post(auth::create_device))
        .route("/v1/devices/recover", post(auth::recover_device))
        // reference data
        .route("/v1/stations/nearby", get(handlers::stations_nearby))
        .route("/v1/stations/search", get(handlers::stations_search))
        .route("/v1/stations/{id}/departures", get(handlers::departures))
        .route("/v1/trips", get(handlers::trip))
        .route("/v1/operators", get(handlers::operators))
        .route("/v1/ngos", get(handlers::ngos))
        .route("/v1/badges", get(handlers::badges))
        // The public flag document (#41): unauthenticated, out of memory, ETag and 304. An
        // authenticated read would be a Postgres write per read (auth.rs: `update devices set
        // last_seen_at`), which is the one thing this box cannot have at any interval worth
        // having.
        .route("/v1/flags.json", get(flags::document))
        // customer
        .route("/v1/events", get(events::stream))
        .route("/v1/me", get(handlers::me).patch(handlers::patch_me).delete(handlers::delete_me))
        .route("/v1/me/standing", get(handlers::standing))
        .route("/v1/me/personal-data", put(handlers::put_personal_data))
        .route("/v1/me/recovery-code", get(handlers::recovery_code))
        .route("/v1/me/export", get(handlers::export_me))
        .route("/v1/me/push-token", put(handlers::put_push_token).delete(handlers::delete_push_token))
        .route("/v1/me/geofence", get(handlers::geofence))
        .route("/v1/me/destinations", get(journeys::destinations))
        // journeys (docs/17)
        .route("/v1/journeys", get(journeys::list).post(journeys::create))
        .route("/v1/journeys/plan", get(journeys::plan))
        .route("/v1/journeys/current", get(journeys::current))
        .route("/v1/journeys/{id}", delete(journeys::delete))
        .route("/v1/journeys/{id}/legs", post(journeys::confirm_leg))
        .route("/v1/journeys/{id}/finish", post(journeys::finish))
        .route("/v1/journeys/{id}/replan", post(journeys::replan))
        .route("/v1/journeys/{id}/change-train", post(journeys::change_train))
        // rides
        .route("/v1/rides", get(handlers::rides))
        .route("/v1/rides/current", get(handlers::current_ride))
        .route("/v1/rides/current/arrival", post(handlers::arrival))
        .route("/v1/rides/current/dismiss", post(handlers::dismiss))
        .route("/v1/rides/nachtrag", post(handlers::nachtrag))
        .route("/v1/rides/{id}", delete(journeys::delete_ride))
        // ledger and claims
        .route("/v1/incidents", get(handlers::incidents))
        .route("/v1/incidents/{id}/discard", post(handlers::incident_discard))
        .route("/v1/incidents/{id}/restore", post(handlers::incident_restore))
        .route("/v1/claims", get(handlers::claims))
        .route("/v1/claims/draft", post(handlers::claim_draft))
        .route("/v1/claims/{id}", patch(handlers::claim_patch))
        .route("/v1/claims/{id}/pdf", get(handlers::claim_pdf))
        .route("/v1/claims/{id}/sign", post(handlers::claim_sign))
        .route("/v1/claims/{id}/send", post(handlers::claim_send))
        .route("/v1/claims/{id}/seen", post(handlers::claim_seen))
        // axum's own default body limit is 2 MiB, which would reject a ticket photo long before
        // the handler's 8 MB check could run. The route that takes files gets its own limit; every
        // other route keeps the small default, which is the right cap for JSON. The layer is set
        // to twice the handler's cap on purpose: the handler then answers an oversize file with
        // 413 and the words "max 8 MB", where the layer would answer with an opaque parse error.
        .route("/v1/uploads", post(handlers::upload).layer(DefaultBodyLimit::max(handlers::MAX_UPLOAD * 2)))
        .route("/v1/mails", get(handlers::mails))
        .route("/v1/mails/{id}/reply", post(handlers::mail_reply))
        .route("/internal/inbound-mail", post(handlers::inbound_mail))
        .route("/internal/inbound-mail/raw", post(handlers::inbound_mail_raw))
        // community
        .route("/v1/community", get(handlers::community))
        .route("/v1/community/pulse", get(handlers::community_pulse))
        .route("/v1/boards", get(handlers::boards))
        // Stellwerk (admin)
        .route("/admin/customers", get(admin::customers))
        .route("/admin/customers/{key}", delete(admin::forget))
        .route("/admin/customers/{key}/ride", get(admin::ride))
        .route("/admin/customers/{key}/journey", get(admin::journey))
        .route("/admin/customers/{key}/confirm", post(admin::confirm))
        .route("/admin/customers/{key}/delay", post(admin::delay))
        .route("/admin/customers/{key}/cancel", post(admin::cancel))
        .route("/admin/customers/{key}/ff", post(admin::fast_forward))
        .route("/admin/customers/{key}/reply", post(admin::reply))
        .route("/admin/customers/{key}/reset", post(admin::reset))
        .route("/admin/customers/{key}/locate", post(admin::locate).delete(admin::clear_location))
        .route("/admin/customers/{key}/push", post(admin::push))
        .route("/admin/customers/{key}/backdate", post(admin::backdate))
        .route("/admin/poll", post(admin::poll))
        .route("/admin/scan", post(admin::scan))
        .route("/admin/customers/{key}/mail-test", post(admin::mail_test))
        .route("/admin/read-mail", post(admin::read_mail))
        .route("/admin/replies", get(admin::replies))
        .route("/admin/mails/{id}/reread", post(admin::reread))
        .route("/admin/ngos", get(admin::ngos_list))
        .route("/admin/ngos/{id}", put(admin::ngo_upsert).delete(admin::ngo_remove))
        .route("/admin/desks", get(admin::desks))
        .route("/admin/routes", get(admin::routes).put(admin::route_set))
        .route("/admin/routes/remove", post(admin::route_remove))
        .route("/admin/routes/answers", post(admin::route_answers))
        .route("/admin/clock", get(admin::get_clock).post(admin::set_clock))
        .route("/admin/switches", get(admin::switches).post(admin::switch_set))
        .route("/admin/flags", get(admin::flags_list))
        .route("/admin/flags/{key}", get(admin::flag_get).post(admin::flag_set).delete(admin::flag_clear))
        .route("/admin/customers/{key}/flags", get(admin::customer_flags))
        .route("/admin/customers/{key}/flags/{flag}", put(admin::customer_flag_set).delete(admin::customer_flag_clear))
        .route("/admin/overrides", get(admin::overrides).delete(admin::clear_overrides))
        .route("/admin/stations", get(admin::stations_status))
        .route("/admin/stations/extract", get(admin::stations_extract))
        // Eight thousand stations is a couple of megabytes of JSON, which is well past the
        // default body limit — and it arrives in one piece because the matching has to see the
        // whole country at once to know what is missing from it.
        .route("/admin/stations/import", post(admin::stations_import).layer(DefaultBodyLimit::max(32 * 1024 * 1024)))
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    // Fail here rather than on the first passenger's ticket if the volume is not mounted.
    let uploads = storage::init()?;
    tracing::info!("uploads in {}", uploads.display());

    let addr = std::env::var("BIND").unwrap_or_else(|_| "127.0.0.1:8080".to_string());
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    if std::env::var("ADMIN_TOKEN").map(|t| t == "stellwerk").unwrap_or(true) && !addr.starts_with("127.0.0.1") && !addr.starts_with("localhost") {
        tracing::warn!("ADMIN_TOKEN is the dev default while listening on {addr}: set a long random ADMIN_TOKEN before exposing /admin");
    }
    tracing::info!("verspaetomat-api listening on http://{addr}");
    axum::serve(listener, app).await?;
    Ok(())
}
