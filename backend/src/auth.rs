//! Device identity. No accounts: one random token per installation, hashed at rest,
//! plus a recovery code issued at the first claim.

use axum::{
    extract::{FromRequestParts, State},
    http::{request::Parts, StatusCode},
    Json,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::db::rows::CustomerRow;
use crate::AppState;

pub fn sha256(s: &str) -> Vec<u8> {
    Sha256::digest(s.as_bytes()).to_vec()
}

fn random_token() -> String {
    let b: [u8; 32] = rand::random();
    hex::encode(b)
}

/// Twelve short words, easy to screenshot, hard to guess (~ 2^66).
pub fn recovery_code() -> String {
    const WORDS: [&str; 64] = [
        "gleis", "bahnsteig", "signal", "weiche", "uhr", "minute", "ampel", "tunnel", "brücke", "kurve", "halt", "ziel",
        "abfahrt", "ankunft", "wagen", "sitz", "fenster", "schaffner", "fahrplan", "takt", "regio", "express", "strecke",
        "knoten", "bahnhof", "ticket", "koffer", "kaffee", "zeitung", "durchsage", "gepäck", "schiene", "oberleitung",
        "lok", "abteil", "nacht", "morgen", "mittag", "abend", "sonne", "regen", "nebel", "schnee", "wind", "stern",
        "mond", "fluss", "berg", "tal", "wald", "wiese", "stadt", "dorf", "hafen", "insel", "küste", "ufer", "turm",
        "platz", "markt", "park", "garten", "brunnen", "tor",
    ];
    let b: [u8; 12] = rand::random();
    b.iter().map(|x| WORDS[(*x as usize) % WORDS.len()]).collect::<Vec<_>>().join(" ")
}

/// `POST /v1/devices` → `{device_id, token}`. Creates the device and its customer row.
pub async fn create_device(State(s): State<AppState>) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    let id = Uuid::new_v4();
    let token = random_token();
    let mut tx = s.pool.begin().await.map_err(internal)?;
    sqlx::query("insert into devices (id, token_hash) values ($1, $2)")
        .bind(id)
        .bind(sha256(&token))
        .execute(&mut *tx)
        .await
        .map_err(internal)?;
    sqlx::query("insert into customers (id) values ($1)").bind(id).execute(&mut *tx).await.map_err(internal)?;
    tx.commit().await.map_err(internal)?;
    Ok(Json(json!({ "device_id": id, "token": token })))
}

#[derive(Deserialize)]
pub struct Recover {
    pub recovery_code: String,
}

/// `POST /v1/devices/recover` → a fresh token for the same customer.
pub async fn recover_device(State(s): State<AppState>, Json(r): Json<Recover>) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    let code = r.recovery_code.trim().to_lowercase().split_whitespace().collect::<Vec<_>>().join(" ");
    let id: Option<Uuid> = sqlx::query_scalar("select id from devices where recovery_hash = $1")
        .bind(sha256(&code))
        .fetch_optional(&s.pool)
        .await
        .map_err(internal)?;
    let Some(id) = id else {
        return Err((StatusCode::NOT_FOUND, Json(json!({ "error": "unknown recovery code" }))));
    };
    let token = random_token();
    sqlx::query("update devices set token_hash = $2, last_seen_at = now() where id = $1")
        .bind(id)
        .bind(sha256(&token))
        .execute(&s.pool)
        .await
        .map_err(internal)?;
    Ok(Json(json!({ "device_id": id, "token": token })))
}

/// Extractor: the authenticated customer. Reads `Authorization: Bearer <token>`.
pub struct Customer(pub CustomerRow);

impl FromRequestParts<AppState> for Customer {
    type Rejection = (StatusCode, Json<Value>);

    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> Result<Self, Self::Rejection> {
        let header = parts
            .headers
            .get(axum::http::header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .unwrap_or("");
        let token = header.strip_prefix("Bearer ").unwrap_or("").trim();
        if token.is_empty() {
            return Err((StatusCode::UNAUTHORIZED, Json(json!({ "error": "missing bearer token" }))));
        }
        let row: Option<CustomerRow> = sqlx::query_as(
            "select c.* from customers c join devices d on d.id = c.id where d.token_hash = $1",
        )
        .bind(sha256(token))
        .fetch_optional(&state.pool)
        .await
        .map_err(internal)?;
        match row {
            Some(c) => {
                let _ = sqlx::query("update devices set last_seen_at = now() where id = $1").bind(c.id).execute(&state.pool).await;
                Ok(Customer(c))
            }
            None => Err((StatusCode::UNAUTHORIZED, Json(json!({ "error": "unknown token" })))),
        }
    }
}

pub fn internal<E: std::fmt::Display>(e: E) -> (StatusCode, Json<Value>) {
    tracing::error!("internal: {e}");
    (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({ "error": "internal" })))
}
