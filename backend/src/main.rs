mod fixtures;
mod handlers;
mod model;
mod rules;

use std::sync::{Arc, RwLock};

use axum::{
    routing::{get, patch, post},
    Router,
};
use chrono::NaiveDate;
use tower_http::{cors::CorsLayer, trace::TraceLayer};

use crate::fixtures::Fixtures;
use crate::model::*;

/// Everything the skeleton holds. In-memory, one customer. Postgres later.
pub struct AppState {
    pub today: NaiveDate,
    pub stations: Vec<Station>,
    pub departures: Vec<Departure>,
    pub operators: Vec<Operator>,
    pub ngos: Vec<Ngo>,
    pub badges: Vec<Badge>,
    pub boards: Boards,
    pub community: Community,
    pub teams: Vec<Team>,
    pub me: Customer,
    pub rides: Vec<Ride>,
    pub incidents: Vec<Incident>,
    pub claims: Vec<Claim>,
    pub mails: Vec<Mail>,
}

impl AppState {
    pub fn from_fixtures(f: Fixtures) -> Self {
        let mut s = Self {
            today: NaiveDate::from_ymd_opt(2026, 9, 9).unwrap(),
            stations: f.stations,
            departures: f.departures,
            operators: f.operators,
            ngos: f.ngos,
            badges: f.badges,
            boards: f.boards,
            community: f.community,
            teams: f.teams,
            me: f.me,
            rides: f.rides,
            incidents: f.incidents,
            claims: Vec::new(),
            mails: f.mails,
        };
        rules::refresh_statuses(&mut s.incidents, s.today);
        s
    }

    pub fn desk_for(&self, operator: &str) -> String {
        self.operators
            .iter()
            .find(|o| o.name == operator)
            .map(|o| o.desk.clone())
            .unwrap_or_else(|| "Unbekannt".to_string())
    }
}

pub type Shared = Arc<RwLock<AppState>>;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info,tower_http=info".into()))
        .init();

    let state: Shared = Arc::new(RwLock::new(AppState::from_fixtures(Fixtures::embedded())));

    let app = Router::new()
        .route("/health", get(handlers::health))
        // reference data
        .route("/v1/stations/nearby", get(handlers::stations_nearby))
        .route("/v1/stations/{id}/departures", get(handlers::departures))
        .route("/v1/trips/{id}", get(handlers::trip))
        .route("/v1/operators", get(handlers::operators))
        .route("/v1/ngos", get(handlers::ngos))
        .route("/v1/badges", get(handlers::badges))
        // customer
        .route("/v1/me", get(handlers::me).patch(handlers::patch_me))
        .route("/v1/me/personal-data", axum::routing::put(handlers::put_personal_data))
        // rides
        .route("/v1/rides", get(handlers::rides).post(handlers::check_in))
        .route("/v1/rides/current", get(handlers::current_ride))
        .route("/v1/rides/current/tick", post(handlers::tick_ride))
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
        .route("/v1/mails", get(handlers::mails))
        .route("/internal/inbound-mail", post(handlers::inbound_mail))
        // community
        .route("/v1/community", get(handlers::community))
        .route("/v1/boards", get(handlers::boards))
        .route("/v1/teams", get(handlers::teams))
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let addr = std::env::var("BIND").unwrap_or_else(|_| "127.0.0.1:8080".to_string());
    let listener = tokio::net::TcpListener::bind(&addr).await.expect("bind");
    tracing::info!("verspaetomat-api listening on http://{addr}");
    axum::serve(listener, app).await.expect("serve");
}
