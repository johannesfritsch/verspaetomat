#![allow(clippy::type_complexity)]
mod admin;
mod auth;
mod clock;
mod db;
mod events;
mod fixtures;
mod handlers;
mod mail;
mod model;
mod pdf;
mod push;
mod rules;
mod scanner;
mod train;

use std::sync::Arc;
use std::time::Duration;

use axum::{
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
    let state = AppState { pool: pool.clone(), train: train.clone(), events: events.clone(), push: push_sender };
    // Pushes: the sender taps the event bus before anything publishes.
    push::spawn(state.clone());

    // The trip follower finalises rides; we turn finalised rides into incidents.
    let mut finalised = train::follower::spawn(pool.clone(), train.clone(), Duration::from_secs(45));
    let pool_for_incidents = pool.clone();
    let events_for_follower = events.clone();
    tokio::spawn(async move {
        while let Ok(ev) = finalised.recv().await {
            match handlers::on_ride_finalised(&pool_for_incidents, ev.ride_id).await {
                Ok(fin) => events_for_follower.publish(ev.customer_id, "ride", serde_json::json!({ "ride_id": ev.ride_id, "status": "arrived", "final_delay_min": ev.final_delay_min, "incident": fin.incident.map(|i| i.id) })),
                Err(e) => tracing::error!("incident creation for ride {}: {e}", ev.ride_id),
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
        // customer
        .route("/v1/events", get(events::stream))
        .route("/v1/me", get(handlers::me).patch(handlers::patch_me).delete(handlers::delete_me))
        .route("/v1/me/personal-data", put(handlers::put_personal_data))
        .route("/v1/me/recovery-code", get(handlers::recovery_code))
        .route("/v1/me/export", get(handlers::export_me))
        .route("/v1/me/push-token", put(handlers::put_push_token).delete(handlers::delete_push_token))
        .route("/v1/me/geofence", get(handlers::geofence))
        // rides
        .route("/v1/rides", get(handlers::rides).post(handlers::check_in))
        .route("/v1/rides/current", get(handlers::current_ride))
        .route("/v1/rides/current/arrival", post(handlers::arrival))
        .route("/v1/rides/current/dismiss", post(handlers::dismiss))
        .route("/v1/rides/nachtrag", post(handlers::nachtrag))
        // ledger and claims
        .route("/v1/incidents", get(handlers::incidents))
        .route("/v1/claims", get(handlers::claims))
        .route("/v1/claims/draft", post(handlers::claim_draft))
        .route("/v1/claims/{id}", patch(handlers::claim_patch))
        .route("/v1/claims/{id}/pdf", get(handlers::claim_pdf))
        .route("/v1/claims/{id}/sign", post(handlers::claim_sign))
        .route("/v1/claims/{id}/send", post(handlers::claim_send))
        .route("/v1/uploads", post(handlers::upload))
        .route("/v1/mails", get(handlers::mails))
        .route("/v1/mails/{id}/reply", post(handlers::mail_reply))
        .route("/internal/inbound-mail", post(handlers::inbound_mail))
        .route("/internal/inbound-mail/raw", post(handlers::inbound_mail_raw))
        // community
        .route("/v1/community", get(handlers::community))
        .route("/v1/boards", get(handlers::boards))
        // Stellwerk (admin)
        .route("/admin/customers", get(admin::customers))
        .route("/admin/customers/{key}", delete(admin::forget))
        .route("/admin/customers/{key}/ride", get(admin::ride))
        .route("/admin/customers/{key}/delay", post(admin::delay))
        .route("/admin/customers/{key}/cancel", post(admin::cancel))
        .route("/admin/customers/{key}/ff", post(admin::fast_forward))
        .route("/admin/customers/{key}/reply", post(admin::reply))
        .route("/admin/customers/{key}/reset", post(admin::reset))
        .route("/admin/customers/{key}/locate", post(admin::locate).delete(admin::clear_location))
        .route("/admin/customers/{key}/push", post(admin::push))
        .route("/admin/poll", post(admin::poll))
        .route("/admin/scan", post(admin::scan))
        .route("/admin/customers/{key}/mail-test", post(admin::mail_test))
        .route("/admin/ngos", get(admin::ngos_list))
        .route("/admin/ngos/{id}", put(admin::ngo_upsert).delete(admin::ngo_remove))
        .route("/admin/ngos/{id}/report", post(admin::ngo_report))
        .route("/admin/clock", get(admin::get_clock).post(admin::set_clock))
        .route("/admin/overrides", get(admin::overrides).delete(admin::clear_overrides))
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let addr = std::env::var("BIND").unwrap_or_else(|_| "127.0.0.1:8080".to_string());
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    if std::env::var("ADMIN_TOKEN").map(|t| t == "stellwerk").unwrap_or(true) && !addr.starts_with("127.0.0.1") && !addr.starts_with("localhost") {
        tracing::warn!("ADMIN_TOKEN is the dev default while listening on {addr}: set a long random ADMIN_TOKEN before exposing /admin");
    }
    tracing::info!("verspaetomat-api listening on http://{addr}");
    axum::serve(listener, app).await?;
    Ok(())
}
