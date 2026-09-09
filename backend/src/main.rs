#![allow(clippy::type_complexity)]
mod auth;
mod db;
mod fixtures;
mod handlers;
mod mail;
mod model;
mod rules;
mod train;

use std::sync::Arc;
use std::time::Duration;

use axum::{
    routing::{get, patch, post, put},
    Router,
};
use sqlx::PgPool;
use tower_http::{cors::CorsLayer, trace::TraceLayer};

use crate::train::transitous::TransitousClient;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub train: Arc<TransitousClient>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info,tower_http=info,sqlx=warn".into()))
        .init();

    let pool = db::connect().await?;
    db::seed(&pool).await?;
    let train = Arc::new(TransitousClient::new());
    let state = AppState { pool: pool.clone(), train: train.clone() };

    // The trip follower finalises rides; we turn finalised rides into incidents.
    let mut finalised = train::follower::spawn(pool.clone(), train.clone(), Duration::from_secs(45));
    let pool_for_incidents = pool.clone();
    tokio::spawn(async move {
        while let Ok(ev) = finalised.recv().await {
            if let Err(e) = handlers::on_ride_finalised(&pool_for_incidents, ev.ride_id).await {
                tracing::error!("incident creation for ride {}: {e}", ev.ride_id);
            }
        }
    });

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
        .route("/v1/me", get(handlers::me).patch(handlers::patch_me).delete(handlers::delete_me))
        .route("/v1/me/personal-data", put(handlers::put_personal_data))
        .route("/v1/me/recovery-code", get(handlers::recovery_code))
        .route("/v1/me/export", get(handlers::export_me))
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
        .route("/v1/claims/{id}/sign", post(handlers::claim_sign))
        .route("/v1/claims/{id}/send", post(handlers::claim_send))
        .route("/v1/uploads", post(handlers::upload))
        .route("/v1/mails", get(handlers::mails))
        .route("/v1/mails/{id}/reply", post(handlers::mail_reply))
        .route("/internal/inbound-mail", post(handlers::inbound_mail))
        // community
        .route("/v1/community", get(handlers::community))
        .route("/v1/boards", get(handlers::boards))
        .route("/v1/teams", get(handlers::teams).post(handlers::create_team))
        .route("/v1/teams/join", post(handlers::join_team))
        .route("/v1/teams/{id}", get(handlers::team).delete(handlers::leave_team))
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let addr = std::env::var("BIND").unwrap_or_else(|_| "127.0.0.1:8080".to_string());
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!("verspaetomat-api listening on http://{addr}");
    axum::serve(listener, app).await?;
    Ok(())
}
