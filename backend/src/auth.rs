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

/// Twelve short words out of 64, easy to screenshot, hard to guess (64^12 = 2^72).
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

/// What a typed or pasted code is compared as: lower case, single spaces, nothing around it. The
/// words are minted in exactly this form, so a code copied out of the app hashes to what is stored.
fn normalize_recovery_code(raw: &str) -> String {
    raw.trim().to_lowercase().split_whitespace().collect::<Vec<_>>().join(" ")
}

/// `POST /v1/devices/recover` → a fresh token for the same customer.
pub async fn recover_device(State(s): State<AppState>, Json(r): Json<Recover>) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    let code = normalize_recovery_code(&r.recovery_code);
    let id: Option<Uuid> = sqlx::query_scalar("select id from devices where recovery_hash = $1")
        .bind(sha256(&code))
        .fetch_optional(&s.pool)
        .await
        .map_err(internal)?;
    let Some(id) = id else {
        // Twelve words out of 64 is 2^72, so blind guessing is hopeless — but a
        // wrong answer should still cost something, and a burst of them should be visible rather
        // than silent. The sleep is short enough that a person who mistyped one word does not
        // notice and long enough that a script cannot run flat out.
        tracing::warn!("recovery attempt with an unknown code");
        tokio::time::sleep(std::time::Duration::from_millis(600)).await;
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

#[cfg(test)]
mod tests {
    use super::*;

    /// Issue #46: the words shown are the words that work. Whatever the app shows is the minted
    /// string itself, so what matters is that it survives the trip back — typed with capitals, with
    /// a line break from the notes app, with spaces around it — and still hashes to what is stored.
    #[test]
    fn a_minted_code_survives_being_typed_back() {
        for _ in 0..200 {
            let code = recovery_code();
            let words: Vec<_> = code.split(' ').collect();
            assert_eq!(words.len(), 12, "{code}");
            assert!(words.iter().all(|w| !w.is_empty() && w.chars().all(|c| c.is_lowercase())), "{code}");
            assert_eq!(normalize_recovery_code(&code), code, "minted form is the compared form");
            let sloppy = format!("  {}\n", code.to_uppercase().replacen(' ', "\n", 3).replacen(' ', "   ", 2));
            assert_eq!(sha256(&normalize_recovery_code(&sloppy)), sha256(&code), "{sloppy:?}");
        }
    }

    /// The app's word boxes accept `a-z äöüß` and nothing else (`wiederherstellen_screen.dart`), so a
    /// minted word with any other letter could be shown but never typed back in.
    #[test]
    fn every_word_can_be_typed_into_the_restore_screen() {
        for _ in 0..200 {
            for w in recovery_code().split(' ') {
                assert!(w.chars().all(|c| c.is_ascii_lowercase() || "äöüß".contains(c)), "{w}");
            }
        }
    }

    #[test]
    fn two_codes_differ() {
        assert_ne!(recovery_code(), recovery_code());
    }
}
