//! Push delivery. One task taps the event bus (`events::EventHub::tap`) and turns the
//! events a person should hear about into a notification: arrival, post from the
//! railway, a deadline warning, a reply nudge, an NGO confirmation.
//!
//! Providers: APNs over HTTP/2 with token auth (`a2`) and FCM HTTP v1 (service
//! account, OAuth2 JWT bearer). Without credentials the sender is a dry-run that
//! logs one line per push, like the SMTP dry-run. A token the provider reports as
//! gone (APNs 410 / `BadDeviceToken` / `Unregistered`, FCM `UNREGISTERED`) is
//! deleted from the device row.
//!
//! Env: `APNS_KEY_P8` (path) or `APNS_KEY_P8_BASE64`, `APNS_KEY_ID`, `APNS_TEAM_ID`,
//! `APNS_TOPIC` (bundle id), `APNS_SANDBOX=1`; `FCM_SERVICE_ACCOUNT_JSON` (path).

use std::io::Cursor;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use a2::{DefaultNotificationBuilder, NotificationBuilder, NotificationOptions, PushType};
use base64::Engine;
use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

use crate::events::AppEvent;
use crate::AppState;

// ---------------------------------------------------------------------------
// What a push says
// ---------------------------------------------------------------------------

/// A notification, provider-agnostic.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Notification {
    pub title: String,
    pub body: String,
    /// What the app should open: `ride`, `mail`, `incident`, `claim`, `test`.
    pub kind: &'static str,
    /// Small string map the app receives alongside (ids).
    pub data: Value,
}

/// The rows a notification is composed from, fetched once per event.
#[derive(Debug, Default, Clone)]
pub struct Facts {
    pub ride: Option<RideFacts>,
    pub claim: Option<ClaimFacts>,
    pub incident: Option<IncidentFacts>,
    pub ngo_name: Option<String>,
}

#[derive(Debug, Clone)]
pub struct RideFacts {
    pub line: String,
    pub exit_station: String,
    pub delay_min: i64,
    pub points: i64,
    pub cancelled: bool,
    pub claim_cents: Option<i64>,
}

#[derive(Debug, Clone)]
pub struct ClaimFacts {
    pub desk: String,
    pub sent_on: Option<NaiveDate>,
    pub amount_claimed_cents: i64,
    pub amount_confirmed_cents: Option<i64>,
}

#[derive(Debug, Clone)]
pub struct IncidentFacts {
    pub line: String,
    pub ride_date: NaiveDate,
}

/// "Servicecenter Fahrgastrechte" is long for a lock screen.
fn desk_short_name(desk: &str) -> String {
    if desk == "Servicecenter Fahrgastrechte" {
        "das Servicecenter".to_string()
    } else {
        desk.to_string()
    }
}

fn euro(cents: i64) -> String {
    format!("{},{:02} €", cents / 100, cents % 100)
}

fn short_date(d: NaiveDate) -> String {
    d.format("%d.%m.").to_string()
}

/// Pure: event + facts → notification, or None when the event is nothing to say out loud.
pub fn compose(kind: &str, payload: &Value, facts: &Facts) -> Option<Notification> {
    let s = |k: &str| payload.get(k).and_then(|v| v.as_str()).map(|v| v.to_string());
    let b = |k: &str| payload.get(k).and_then(|v| v.as_bool()).unwrap_or(false);
    let ngo = facts.ngo_name.clone().unwrap_or_else(|| "deinen Verein".to_string());
    match kind {
        "ride" if s("status").as_deref() == Some("arrived") => {
            let r = facts.ride.as_ref()?;
            let (title, body) = if r.cancelled {
                (format!("Ausfall · {}", r.line), format!("{} Geduldspunkte. {}", r.points, claim_line(r.claim_cents, &ngo)))
            } else if r.delay_min <= 0 {
                (format!("Pünktlich · {}", r.line), format!("Angekommen in {}. Kein Punkt heute, dafür kein Ärger.", r.exit_station))
            } else {
                (format!("+{} · {}", r.delay_min, r.line), format!("{} Geduldspunkte. {}", r.points, claim_line(r.claim_cents, &ngo)))
            };
            Some(Notification { title, body: body.trim().to_string(), kind: "ride", data: json!({ "ride_id": s("ride_id") }) })
        }
        "mail" => {
            let c = facts.claim.as_ref();
            let body = match s("outcome").as_deref() {
                Some("accepted") => {
                    let cents = c.and_then(|c| c.amount_confirmed_cents).or(c.map(|c| c.amount_claimed_cents));
                    match cents {
                        Some(cents) => format!("{} bestätigt. Geht an {ngo}.", euro(cents)),
                        None => format!("Antrag bestätigt. Das Geld geht an {ngo}."),
                    }
                }
                Some("question") => "Rückfrage zum Antrag. Antworten kannst du in der App.".to_string(),
                Some("rejected") => "Antrag abgelehnt. Die Begründung steht in der App.".to_string(),
                Some("bounce") => "Die Mail kam zurück. Bitte in der App prüfen.".to_string(),
                _ if c.is_some() => "Neue Nachricht zu deinem Antrag.".to_string(),
                // No claim behind it: not the railway, just mail to the relay address.
                _ => "Eine Nachricht an deine Verspätomat-Adresse. Du findest sie in der App.".to_string(),
            };
            let title = if c.is_some() { "Post von der Bahn" } else { "Neue Post" };
            Some(Notification { title: title.to_string(), body, kind: "mail", data: json!({ "claim_id": s("claim_id") }) })
        }
        "incident" if b("warning") => {
            let i = facts.incident.as_ref()?;
            let days = payload.get("days_left").and_then(|v| v.as_i64()).unwrap_or(0);
            let when = match days {
                0 => "heute".to_string(),
                1 => "morgen".to_string(),
                n => format!("in {n} Tagen"),
            };
            Some(Notification {
                title: "Verfällt bald".to_string(),
                body: format!("{} vom {} verfällt {when}. Antrag vorbereiten?", i.line, short_date(i.ride_date)),
                kind: "incident",
                data: json!({ "incident_id": s("incident_id") }),
            })
        }
        "claim" if b("nudge") => {
            let c = facts.claim.as_ref()?;
            let sent = c.sent_on.map(|d| format!(" vom {}", short_date(d))).unwrap_or_default();
            Some(Notification {
                title: "Noch keine Antwort".to_string(),
                body: format!("Dein Antrag{sent} an {} ist über die erwartete Frist. Nachhaken kannst du in der App.", c.desk),
                kind: "claim",
                data: json!({ "claim_id": s("claim_id") }),
            })
        }
        "claim" if s("source").as_deref() == Some("ngo_report") && s("status").as_deref() == Some("accepted") => {
            let cents = payload.get("amount_confirmed_cents").and_then(|v| v.as_i64()).or(facts.claim.as_ref().and_then(|c| c.amount_confirmed_cents));
            let body = match cents {
                Some(cents) => format!("{ngo} hat {} erhalten. Das warst du.", euro(cents)),
                None => format!("{ngo} hat dein Geld erhalten. Das warst du."),
            };
            Some(Notification { title: "Angekommen beim Verein".to_string(), body, kind: "claim", data: json!({ "claim_id": s("claim_id") }) })
        }
        _ => None,
    }
}

fn claim_line(cents: Option<i64>, ngo: &str) -> String {
    match cents {
        Some(c) => format!("Anspruch entstanden: {} für {ngo}.", euro(c)),
        None => String::new(),
    }
}

/// Fetch what `compose` needs for this event.
pub async fn facts(pool: &PgPool, customer: Uuid, kind: &str, payload: &Value) -> anyhow::Result<Facts> {
    let mut f = Facts::default();
    let id = |k: &str| payload.get(k).and_then(|v| v.as_str()).and_then(|v| Uuid::parse_str(v).ok());
    f.ngo_name = sqlx::query_scalar("select n.name from customers c join ngos n on n.id = c.ngo_id where c.id = $1").bind(customer).fetch_optional(pool).await?;
    if kind == "ride" {
        if let Some(ride_id) = id("ride_id") {
            let row: Option<(String, String, Option<i32>, i32, bool, Option<i64>)> = sqlx::query_as(
                "select r.line, r.exit_station_name, r.final_delay_min, r.points, r.cancelled, i.amount_cents
                 from rides r left join incidents i on i.ride_id = r.id where r.id = $1",
            )
            .bind(ride_id)
            .fetch_optional(pool)
            .await?;
            f.ride = row.map(|(line, exit_station, delay, points, cancelled, cents)| RideFacts {
                line,
                exit_station,
                delay_min: delay.unwrap_or(0) as i64,
                points: points as i64,
                cancelled,
                claim_cents: cents,
            });
        }
    }
    if let Some(claim_id) = id("claim_id") {
        let row: Option<(String, Option<chrono::DateTime<chrono::Utc>>, i64, Option<i64>)> =
            sqlx::query_as("select desk, sent_at, amount_claimed_cents, amount_confirmed_cents from claims where id = $1").bind(claim_id).fetch_optional(pool).await?;
        f.claim = row.map(|(desk, sent_at, claimed, confirmed)| ClaimFacts {
            desk: desk_short_name(&desk),
            sent_on: sent_at.map(|t| t.with_timezone(&chrono_tz::Europe::Berlin).date_naive()),
            amount_claimed_cents: claimed,
            amount_confirmed_cents: confirmed,
        });
    }
    if let Some(incident_id) = id("incident_id") {
        let row: Option<(String, NaiveDate)> = sqlx::query_as("select line, ride_date from incidents where id = $1").bind(incident_id).fetch_optional(pool).await?;
        f.incident = row.map(|(line, ride_date)| IncidentFacts { line, ride_date });
    }
    Ok(f)
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Delivery {
    Sent,
    DryRun,
    /// The provider says this token is dead; the caller deletes it.
    Unregistered,
}

struct Apns {
    client: a2::Client,
    topic: String,
}

struct Fcm {
    project_id: String,
    client_email: String,
    private_key: String,
    token_uri: String,
    cached: Mutex<Option<(String, Instant)>>,
}

#[derive(Deserialize)]
struct ServiceAccount {
    project_id: String,
    client_email: String,
    private_key: String,
    #[serde(default = "default_token_uri")]
    token_uri: String,
}

fn default_token_uri() -> String {
    "https://oauth2.googleapis.com/token".to_string()
}

pub struct PushSender {
    apns: Option<Apns>,
    fcm: Option<Fcm>,
    http: reqwest::Client,
}

impl PushSender {
    /// Read the environment. Missing credentials mean dry-run for that platform.
    pub fn from_env() -> anyhow::Result<Self> {
        let apns = match apns_from_env() {
            Ok(Some(a)) => {
                tracing::info!(topic = %a.topic, "push: APNs configured");
                Some(a)
            }
            Ok(None) => None,
            Err(e) => {
                tracing::error!("push: APNs configuration ignored: {e}");
                None
            }
        };
        let fcm = match fcm_from_env() {
            Ok(Some(f)) => {
                tracing::info!(project = %f.project_id, "push: FCM configured");
                Some(f)
            }
            Ok(None) => None,
            Err(e) => {
                tracing::error!("push: FCM configuration ignored: {e}");
                None
            }
        };
        if apns.is_none() && fcm.is_none() {
            tracing::info!("push: no APNS_*/FCM_* credentials, pushes are logged (dry-run)");
        }
        Ok(Self { apns, fcm, http: reqwest::Client::builder().timeout(Duration::from_secs(15)).build()? })
    }

    pub fn configured(&self, platform: &str) -> bool {
        match platform {
            "ios" => self.apns.is_some(),
            "android" => self.fcm.is_some(),
            _ => false,
        }
    }

    pub async fn send(&self, platform: &str, token: &str, n: &Notification) -> anyhow::Result<Delivery> {
        match platform {
            "ios" => match &self.apns {
                Some(a) => send_apns(a, token, n).await,
                None => Ok(Delivery::DryRun),
            },
            "android" => match &self.fcm {
                Some(f) => send_fcm(&self.http, f, token, n).await,
                None => Ok(Delivery::DryRun),
            },
            other => anyhow::bail!("unknown push platform {other}"),
        }
    }
}

fn apns_from_env() -> anyhow::Result<Option<Apns>> {
    let key_id = std::env::var("APNS_KEY_ID").ok();
    let team_id = std::env::var("APNS_TEAM_ID").ok();
    let topic = std::env::var("APNS_TOPIC").ok();
    let pem: Option<Vec<u8>> = if let Ok(b64) = std::env::var("APNS_KEY_P8_BASE64") {
        Some(base64::engine::general_purpose::STANDARD.decode(b64.trim())?)
    } else if let Ok(path) = std::env::var("APNS_KEY_P8") {
        Some(std::fs::read(path)?)
    } else {
        None
    };
    let (Some(key_id), Some(team_id), Some(topic), Some(pem)) = (key_id, team_id, topic, pem) else {
        if std::env::var("APNS_KEY_ID").is_ok() || std::env::var("APNS_KEY_P8").is_ok() || std::env::var("APNS_KEY_P8_BASE64").is_ok() {
            anyhow::bail!("APNs needs APNS_KEY_P8 (or _BASE64), APNS_KEY_ID, APNS_TEAM_ID and APNS_TOPIC together");
        }
        return Ok(None);
    };
    let sandbox = std::env::var("APNS_SANDBOX").map(|v| v == "1" || v == "true").unwrap_or(false);
    let endpoint = if sandbox { a2::Endpoint::Sandbox } else { a2::Endpoint::Production };
    let client = a2::Client::token(Cursor::new(pem), key_id, team_id, a2::ClientConfig::new(endpoint))?;
    Ok(Some(Apns { client, topic }))
}

fn fcm_from_env() -> anyhow::Result<Option<Fcm>> {
    let Ok(path) = std::env::var("FCM_SERVICE_ACCOUNT_JSON") else { return Ok(None) };
    let sa: ServiceAccount = serde_json::from_slice(&std::fs::read(&path)?)?;
    Ok(Some(Fcm { project_id: sa.project_id, client_email: sa.client_email, private_key: sa.private_key, token_uri: sa.token_uri, cached: Mutex::new(None) }))
}

async fn send_apns(a: &Apns, token: &str, n: &Notification) -> anyhow::Result<Delivery> {
    let builder = DefaultNotificationBuilder::new().set_title(&n.title).set_body(&n.body).set_sound("default");
    let options = NotificationOptions { apns_topic: Some(&a.topic), apns_push_type: Some(PushType::Alert), ..Default::default() };
    let mut payload = builder.build(token, options);
    payload.add_custom_data("verspaetomat", &json!({ "kind": n.kind, "data": n.data }))?;
    match a.client.send(payload).await {
        Ok(_) => Ok(Delivery::Sent),
        Err(a2::Error::ResponseError(r)) => {
            let reason = r.error.as_ref().map(|e| &e.reason);
            if r.code == 410 || matches!(reason, Some(a2::ErrorReason::BadDeviceToken) | Some(a2::ErrorReason::Unregistered)) {
                Ok(Delivery::Unregistered)
            } else {
                anyhow::bail!("APNs {}: {:?}", r.code, reason)
            }
        }
        Err(e) => Err(e.into()),
    }
}

#[derive(Serialize)]
struct JwtClaims<'a> {
    iss: &'a str,
    scope: &'a str,
    aud: &'a str,
    iat: u64,
    exp: u64,
}

async fn fcm_access_token(http: &reqwest::Client, f: &Fcm) -> anyhow::Result<String> {
    if let Some((tok, until)) = f.cached.lock().unwrap().as_ref() {
        if Instant::now() < *until {
            return Ok(tok.clone());
        }
    }
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_secs();
    let claims = JwtClaims { iss: &f.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: &f.token_uri, iat: now, exp: now + 3600 };
    let key = jsonwebtoken::EncodingKey::from_rsa_pem(f.private_key.as_bytes())?;
    let assertion = jsonwebtoken::encode(&jsonwebtoken::Header::new(jsonwebtoken::Algorithm::RS256), &claims, &key)?;
    #[derive(Deserialize)]
    struct TokenResponse {
        access_token: String,
        #[serde(default)]
        expires_in: u64,
    }
    let r = http.post(&f.token_uri).form(&[("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"), ("assertion", assertion.as_str())]).send().await?;
    let status = r.status();
    let text = r.text().await?;
    if !status.is_success() {
        anyhow::bail!("FCM token endpoint {status}: {text}");
    }
    let t: TokenResponse = serde_json::from_str(&text)?;
    let ttl = t.expires_in.max(60).saturating_sub(60);
    *f.cached.lock().unwrap() = Some((t.access_token.clone(), Instant::now() + Duration::from_secs(ttl)));
    Ok(t.access_token)
}

/// The FCM v1 message body. Data values must be strings.
pub fn fcm_message(token: &str, n: &Notification) -> Value {
    let mut data = serde_json::Map::new();
    data.insert("kind".into(), Value::String(n.kind.to_string()));
    if let Some(obj) = n.data.as_object() {
        for (k, v) in obj {
            let s = match v {
                Value::String(s) => s.clone(),
                Value::Null => continue,
                other => other.to_string(),
            };
            data.insert(k.clone(), Value::String(s));
        }
    }
    json!({
        "message": {
            "token": token,
            "notification": { "title": n.title, "body": n.body },
            "data": data,
            "android": { "priority": "high", "notification": { "sound": "default" } },
            "apns": { "payload": { "aps": { "sound": "default" } } }
        }
    })
}

async fn send_fcm(http: &reqwest::Client, f: &Fcm, token: &str, n: &Notification) -> anyhow::Result<Delivery> {
    let access = fcm_access_token(http, f).await?;
    let url = format!("https://fcm.googleapis.com/v1/projects/{}/messages:send", f.project_id);
    let r = http.post(url).bearer_auth(access).json(&fcm_message(token, n)).send().await?;
    let status = r.status();
    if status.is_success() {
        return Ok(Delivery::Sent);
    }
    let text = r.text().await.unwrap_or_default();
    if status.as_u16() == 404 && text.contains("UNREGISTERED") {
        return Ok(Delivery::Unregistered);
    }
    anyhow::bail!("FCM {status}: {text}")
}

// ---------------------------------------------------------------------------
// The loop
// ---------------------------------------------------------------------------

/// Deliver one notification to a customer's device, honouring the notifications
/// setting. Returns what happened, for logs and the admin test route.
pub async fn deliver(s: &AppState, customer: Uuid, n: &Notification) -> anyhow::Result<&'static str> {
    let row: Option<(bool, Option<String>, Option<String>)> =
        sqlx::query_as("select c.notifications, d.push_platform, d.push_token from customers c join devices d on d.id = c.id where c.id = $1").bind(customer).fetch_optional(&s.pool).await?;
    let Some((wants, platform, token)) = row else { return Ok("no-customer") };
    if !wants {
        return Ok("muted");
    }
    let (Some(platform), Some(token)) = (platform, token) else {
        if !s.push.configured("ios") && !s.push.configured("android") {
            tracing::info!(customer = %customer, kind = n.kind, title = %n.title, body = %n.body, token = "none", "push (dry-run)");
            return Ok("dry-run");
        }
        return Ok("no-token");
    };
    match s.push.send(&platform, &token, n).await? {
        Delivery::Sent => {
            tracing::info!(customer = %customer, platform = %platform, kind = n.kind, title = %n.title, "push sent");
            Ok("sent")
        }
        Delivery::DryRun => {
            tracing::info!(customer = %customer, platform = %platform, kind = n.kind, title = %n.title, body = %n.body, token = "present", "push (dry-run)");
            Ok("dry-run")
        }
        Delivery::Unregistered => {
            sqlx::query("update devices set push_platform = null, push_token = null, push_updated_at = now() where id = $1").bind(customer).execute(&s.pool).await?;
            tracing::warn!(customer = %customer, platform = %platform, "push token rejected by the provider, removed");
            Ok("unregistered")
        }
    }
}

/// Start the sender: every event on the bus is considered, the ones with a voice are sent.
pub fn spawn(state: AppState) {
    let mut rx = state.events.tap();
    tokio::spawn(async move {
        loop {
            let (customer, AppEvent { kind, payload }) = match rx.recv().await {
                Ok(ev) => ev,
                Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                    tracing::warn!("push: lagged {n} events");
                    continue;
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
            };
            let f = match facts(&state.pool, customer, kind, &payload).await {
                Ok(f) => f,
                Err(e) => {
                    tracing::error!("push facts for {kind}: {e}");
                    continue;
                }
            };
            let Some(n) = compose(kind, &payload, &f) else { continue };
            if let Err(e) = deliver(&state, customer, &n).await {
                tracing::error!(customer = %customer, kind, "push failed: {e}");
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn facts_with(ngo: &str) -> Facts {
        Facts { ngo_name: Some(ngo.to_string()), ..Default::default() }
    }

    #[test]
    fn arrival_with_claim() {
        let mut f = facts_with("Bahnhofsmission Köln");
        f.ride = Some(RideFacts { line: "RE 7".into(), exit_station: "Münster".into(), delay_min: 68, points: 68, cancelled: false, claim_cents: Some(150) });
        let n = compose("ride", &json!({ "ride_id": "r1", "status": "arrived" }), &f).unwrap();
        assert_eq!(n.title, "+68 · RE 7");
        assert_eq!(n.body, "68 Geduldspunkte. Anspruch entstanden: 1,50 € für Bahnhofsmission Köln.");
        assert_eq!(n.kind, "ride");
        assert_eq!(n.data["ride_id"], "r1");
    }

    #[test]
    fn arrival_variants() {
        let mut f = facts_with("X");
        f.ride = Some(RideFacts { line: "S 6".into(), exit_station: "".into(), delay_min: 14, points: 14, cancelled: false, claim_cents: None });
        let n = compose("ride", &json!({ "status": "arrived" }), &f).unwrap();
        assert_eq!((n.title.as_str(), n.body.as_str()), ("+14 · S 6", "14 Geduldspunkte."));
        f.ride = Some(RideFacts { line: "RB 48".into(), exit_station: "".into(), delay_min: 0, points: 60, cancelled: true, claim_cents: Some(150) });
        let n = compose("ride", &json!({ "status": "arrived" }), &f).unwrap();
        assert!(n.title.starts_with("Ausfall"));
        f.ride = Some(RideFacts { line: "RE 1".into(), exit_station: "Aachen Hbf".into(), delay_min: 0, points: 0, cancelled: false, claim_cents: None });
        let n = compose("ride", &json!({ "status": "arrived" }), &f).unwrap();
        assert_eq!(n.title, "Pünktlich · RE 1");
        assert!(n.body.starts_with("Angekommen in Aachen Hbf."));
        // A ride that is merely riding is silent.
        assert!(compose("ride", &json!({ "status": "riding" }), &f).is_none());
    }

    #[test]
    fn post_from_the_railway() {
        let mut f = facts_with("Bahnhofsmission Köln");
        f.claim = Some(ClaimFacts { desk: "Servicecenter".into(), sent_on: None, amount_claimed_cents: 450, amount_confirmed_cents: Some(450) });
        let n = compose("mail", &json!({ "claim_id": "c1", "outcome": "accepted" }), &f).unwrap();
        assert_eq!(n.title, "Post von der Bahn");
        assert_eq!(n.body, "4,50 € bestätigt. Geht an Bahnhofsmission Köln.");
        let n = compose("mail", &json!({ "outcome": "question" }), &f).unwrap();
        assert!(n.body.starts_with("Rückfrage"));
        let n = compose("mail", &json!({ "outcome": "rejected" }), &f).unwrap();
        assert!(n.body.starts_with("Antrag abgelehnt"));
    }

    #[test]
    fn warning_nudge_and_ngo() {
        let mut f = facts_with("Wald für morgen e.V.");
        f.incident = Some(IncidentFacts { line: "RE 10".into(), ride_date: NaiveDate::from_ymd_opt(2026, 8, 21).unwrap() });
        let n = compose("incident", &json!({ "incident_id": "i1", "warning": true, "days_left": 21 }), &f).unwrap();
        assert_eq!(n.body, "RE 10 vom 21.08. verfällt in 21 Tagen. Antrag vorbereiten?");
        assert!(compose("incident", &json!({ "expired": ["i1"] }), &f).is_none());

        f.claim = Some(ClaimFacts { desk: "Servicecenter".into(), sent_on: NaiveDate::from_ymd_opt(2026, 8, 15), amount_claimed_cents: 450, amount_confirmed_cents: None });
        let n = compose("claim", &json!({ "claim_id": "c1", "nudge": true }), &f).unwrap();
        assert_eq!(n.title, "Noch keine Antwort");
        assert!(n.body.contains("vom 15.08. an Servicecenter"), "{}", n.body);
        assert!(compose("claim", &json!({ "claim_id": "c1", "status": "sent" }), &f).is_none());

        let n = compose("claim", &json!({ "claim_id": "c1", "status": "accepted", "amount_confirmed_cents": 450, "source": "ngo_report" }), &f).unwrap();
        assert_eq!(n.body, "Wald für morgen e.V. hat 4,50 € erhalten. Das warst du.");
    }

    #[test]
    fn silent_kinds() {
        let f = Facts::default();
        for (k, p) in [("location", json!({})), ("clock", json!({})), ("reset", json!({})), ("mail", json!({}))] {
            let n = compose(k, &p, &f);
            if k == "mail" {
                assert!(n.is_some());
            } else {
                assert!(n.is_none(), "{k} should be silent");
            }
        }
    }

    #[test]
    fn fcm_body_is_v1_shaped_with_string_data() {
        let n = Notification { title: "T".into(), body: "B".into(), kind: "ride", data: json!({ "ride_id": "r1", "n": 5, "nothing": null }) };
        let m = fcm_message("tok", &n);
        assert_eq!(m["message"]["token"], "tok");
        assert_eq!(m["message"]["notification"]["title"], "T");
        assert_eq!(m["message"]["data"]["kind"], "ride");
        assert_eq!(m["message"]["data"]["ride_id"], "r1");
        assert_eq!(m["message"]["data"]["n"], "5");
        assert!(m["message"]["data"].get("nothing").is_none());
    }
}
