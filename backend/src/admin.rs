//! Stellwerk admin API. Guarded by `x-admin-token` = `ADMIN_TOKEN` (default "stellwerk" in dev).
//! Dev and staging only: it changes the world the customers see.

use axum::{
    extract::{FromRequestParts, Path, State},
    http::{request::Parts, StatusCode},
    Json,
};
use chrono::Duration;
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::auth::internal;
use crate::clock;
use crate::db::rows::*;
use crate::handlers::{self, InboundMail};
use crate::train::sim::TripOverride;
use crate::AppState;

type ApiResult = Result<Json<Value>, (StatusCode, Json<Value>)>;

fn err(status: StatusCode, msg: &str) -> (StatusCode, Json<Value>) {
    (status, Json(json!({ "error": msg })))
}

pub struct Admin;

impl FromRequestParts<AppState> for Admin {
    type Rejection = (StatusCode, Json<Value>);
    async fn from_request_parts(parts: &mut Parts, _s: &AppState) -> Result<Self, Self::Rejection> {
        let expected = std::env::var("ADMIN_TOKEN").unwrap_or_else(|_| "stellwerk".into());
        let given = parts.headers.get("x-admin-token").and_then(|v| v.to_str().ok()).unwrap_or("");
        if given == expected {
            Ok(Admin)
        } else {
            Err(err(StatusCode::UNAUTHORIZED, "bad admin token"))
        }
    }
}

/// Find a customer by id, id prefix, nickname (case-insensitive) or relay address.
async fn resolve(s: &AppState, key: &str) -> Result<CustomerRow, (StatusCode, Json<Value>)> {
    let key = key.trim();
    let row: Option<CustomerRow> = sqlx::query_as(
        "select * from customers where id::text = $1 or id::text like $1 || '%' or lower(nickname) = lower($1) or lower(relay_address) = lower($1)
         order by created_at desc limit 1",
    )
    .bind(key)
    .fetch_optional(&s.pool)
    .await
    .map_err(internal)?;
    row.ok_or_else(|| err(StatusCode::NOT_FOUND, "no such customer"))
}

async fn current_ride(s: &AppState, customer: Uuid) -> Result<Option<RideRow>, (StatusCode, Json<Value>)> {
    sqlx::query_as("select * from rides where customer_id = $1 and status = 'riding' order by checked_in_at desc limit 1")
        .bind(customer)
        .fetch_optional(&s.pool)
        .await
        .map_err(internal)
}

pub async fn customers(State(s): State<AppState>, _a: Admin) -> ApiResult {
    let rows: Vec<CustomerRow> = sqlx::query_as("select c.* from customers c join devices d on d.id = c.id order by d.last_seen_at desc limit 100").fetch_all(&s.pool).await.map_err(internal)?;
    let mut out = Vec::new();
    for c in rows {
        let last_seen: Option<chrono::DateTime<chrono::Utc>> = sqlx::query_scalar("select last_seen_at from devices where id = $1").bind(c.id).fetch_optional(&s.pool).await.map_err(internal)?;
        let ride = current_ride(&s, c.id).await?;
        let (open, incidents): (i64, i64) = sqlx::query_as("select count(*) filter (where status in ('gesammelt','bereit'))::bigint, count(*)::bigint from incidents where customer_id = $1")
            .bind(c.id)
            .fetch_one(&s.pool)
            .await
            .map_err(internal)?;
        out.push(json!({
            "id": c.id, "nickname": c.nickname, "relay_address": c.relay_address, "created_at": c.created_at, "last_seen_at": last_seen,
            "riding": ride.is_some(),
            "ride": ride.map(|r| json!({ "id": r.id, "line": r.line, "exit_station_name": r.exit_station_name, "live_delay_min": r.live_delay_min, "passed_stops": r.passed_stops, "checked_in_at": r.checked_in_at, "last_polled_at": r.last_polled_at })),
            "open_incidents": open, "incidents": incidents,
        }));
    }
    Ok(Json(json!(out)))
}

pub async fn ride(State(s): State<AppState>, _a: Admin, Path(key): Path<String>) -> ApiResult {
    let c = resolve(&s, &key).await?;
    let Some(r) = current_ride(&s, c.id).await? else {
        let last: Option<RideRow> = sqlx::query_as("select * from rides where customer_id = $1 order by checked_in_at desc limit 1").bind(c.id).fetch_optional(&s.pool).await.map_err(internal)?;
        return Ok(Json(json!({ "customer": c.nickname, "riding": false, "last": last })));
    };
    let trip = s.train.trip(&r.trip_id).await.ok();
    let o = s.train.get_override(&r.trip_id);
    Ok(Json(json!({
        "customer": c.nickname, "riding": true, "ride": r,
        "stops": trip.as_ref().map(|t| json!(t.stops)).unwrap_or(json!([])),
        "trip_cancelled": trip.as_ref().map(|t| t.cancelled).unwrap_or(false),
        "override": o, "now": clock::now(), "clock_offset_secs": clock::offset_secs(),
    })))
}

#[derive(Deserialize)]
pub struct DelayBody {
    pub minutes: i32,
}

pub async fn delay(State(s): State<AppState>, _a: Admin, Path(key): Path<String>, Json(b): Json<DelayBody>) -> ApiResult {
    let c = resolve(&s, &key).await?;
    let Some(r) = current_ride(&s, c.id).await? else { return Err(err(StatusCode::CONFLICT, "customer is not riding")) };
    let mut o = s.train.get_override(&r.trip_id).unwrap_or(TripOverride { trip_id: r.trip_id.clone(), ..Default::default() });
    o.extra_delay_min += b.minutes;
    s.train.set_override(&s.pool, o.clone()).await.map_err(internal)?;
    let _ = crate::train::follower::poll_once(&s.pool, &s.train, &tokio::sync::broadcast::channel(1).0).await;
    let r: RideRow = sqlx::query_as("select * from rides where id = $1").bind(r.id).fetch_one(&s.pool).await.map_err(internal)?;
    Ok(Json(json!({ "override": o, "ride": r })))
}

pub async fn cancel(State(s): State<AppState>, _a: Admin, Path(key): Path<String>) -> ApiResult {
    let c = resolve(&s, &key).await?;
    let Some(r) = current_ride(&s, c.id).await? else { return Err(err(StatusCode::CONFLICT, "customer is not riding")) };
    let mut o = s.train.get_override(&r.trip_id).unwrap_or(TripOverride { trip_id: r.trip_id.clone(), ..Default::default() });
    o.cancelled = true;
    s.train.set_override(&s.pool, o.clone()).await.map_err(internal)?;
    let _ = crate::train::follower::poll_once(&s.pool, &s.train, &tokio::sync::broadcast::channel(1).0).await;
    let fin = handlers::on_ride_finalised(&s.pool, r.id).await.map_err(internal)?;
    let r: RideRow = sqlx::query_as("select * from rides where id = $1").bind(r.id).fetch_one(&s.pool).await.map_err(internal)?;
    Ok(Json(json!({ "override": o, "ride": r, "incident": fin.incident, "new_badge": fin.new_badge })))
}

/// Fast-forward: shift the trip so the exit stop lies in the past, then poll. The follower does the rest.
pub async fn fast_forward(State(s): State<AppState>, _a: Admin, Path(key): Path<String>) -> ApiResult {
    let c = resolve(&s, &key).await?;
    let Some(r) = current_ride(&s, c.id).await? else { return Err(err(StatusCode::CONFLICT, "customer is not riding")) };
    let t = s.train.trip(&r.trip_id).await.map_err(|e| err(StatusCode::BAD_GATEWAY, &format!("trip: {e}")))?;
    let exit = t.find_stop(Some(r.exit_station_id.as_str()), &r.exit_station_name).map(|(_, st)| st.clone());
    let arrival = exit.and_then(|st| st.live_arrival.or(st.scheduled_arrival)).unwrap_or(r.planned_arrival + Duration::minutes(r.live_delay_min as i64));
    let target = clock::now() - Duration::minutes(4); // past the 3-minute grace
    let mut o = s.train.get_override(&r.trip_id).unwrap_or(TripOverride { trip_id: r.trip_id.clone(), ..Default::default() });
    if arrival > target {
        o.time_shift_secs += (arrival - target).num_seconds();
    }
    s.train.set_override(&s.pool, o.clone()).await.map_err(internal)?;
    crate::train::follower::poll_once(&s.pool, &s.train, &tokio::sync::broadcast::channel(1).0).await.map_err(internal)?;
    let r2: RideRow = sqlx::query_as("select * from rides where id = $1").bind(r.id).fetch_one(&s.pool).await.map_err(internal)?;
    if r2.status != RideStatus::Arrived {
        return Err(err(StatusCode::CONFLICT, "follower did not finalise the ride; check the exit stop"));
    }
    let fin = handlers::on_ride_finalised(&s.pool, r.id).await.map_err(internal)?;
    Ok(Json(json!({ "ride": r2, "incident": fin.incident, "new_badge": fin.new_badge, "override": o })))
}

pub async fn poll(State(s): State<AppState>, _a: Admin) -> ApiResult {
    let (tx, mut rx) = tokio::sync::broadcast::channel(64);
    crate::train::follower::poll_once(&s.pool, &s.train, &tx).await.map_err(internal)?;
    let mut finalised = Vec::new();
    while let Ok(ev) = rx.try_recv() {
        let fin = handlers::on_ride_finalised(&s.pool, ev.ride_id).await.map_err(internal)?;
        finalised.push(json!({ "ride_id": ev.ride_id, "delay": ev.final_delay_min, "incident": fin.incident.map(|i| i.id) }));
    }
    Ok(Json(json!({ "finalised": finalised, "now": clock::now() })))
}

#[derive(Deserialize)]
pub struct ReplyBody {
    pub outcome: String,
    #[serde(default)]
    pub amount_cents: Option<i64>,
}

pub async fn reply(State(s): State<AppState>, _a: Admin, Path(key): Path<String>, Json(b): Json<ReplyBody>) -> ApiResult {
    let c = resolve(&s, &key).await?;
    let Some(relay) = c.relay_address.clone() else { return Err(err(StatusCode::CONFLICT, "customer has no relay address yet")) };
    let claim: Option<ClaimRow> = sqlx::query_as("select * from claims where customer_id = $1 and status in ('sent','question') order by sent_at desc limit 1").bind(c.id).fetch_optional(&s.pool).await.map_err(internal)?;
    let Some(claim) = claim else { return Err(err(StatusCode::CONFLICT, "no sent claim to answer")) };
    let name = c.full_name.clone().unwrap_or(c.nickname.clone());
    let amount = b.amount_cents.unwrap_or(claim.amount_claimed_cents);
    let eur = format!("{},{:02} EUR", amount / 100, amount % 100);
    let body = match b.outcome.as_str() {
        "accepted" => format!("Sehr geehrte/r {name},\n\nvielen Dank für Ihren Antrag. Wir haben die angegebenen Fahrten geprüft und eine Entschädigung von insgesamt {eur} festgestellt.\n\nDer Betrag wird auf das angegebene Konto überwiesen:\nKontoinhaber: {}\n\nMit freundlichen Grüßen\nIhr Servicecenter Fahrgastrechte", claim.account_holder),
        "question" => format!("Sehr geehrte/r {name},\n\nzur Bearbeitung Ihres Antrags benötigen wir noch eine Kopie Ihres Tickets für den betroffenen Monat. Bitte senden Sie diese als Antwort auf diese E-Mail.\n\nMit freundlichen Grüßen\nIhr Servicecenter Fahrgastrechte"),
        "rejected" => format!("Sehr geehrte/r {name},\n\nleider können wir Ihrem Antrag nicht entsprechen. Die Verspätung beruhte auf außergewöhnlichen Umständen (Unwetter), für die nach VO (EU) 2021/782 Art. 19 Abs. 10 keine Entschädigung geleistet wird.\n\nMit freundlichen Grüßen\nIhr Servicecenter Fahrgastrechte"),
        other => return Err(err(StatusCode::BAD_REQUEST, &format!("outcome must be accepted|question|rejected, got {other}"))),
    };
    let result = handlers::process_inbound(
        &s,
        InboundMail {
            to: relay,
            from: "Servicecenter Fahrgastrechte <fahrgastrechte@deutschebahn.com>".into(),
            subject: format!("Ihr Antrag auf Entschädigung – Vorgang {}", &claim.id.simple().to_string()[..10]),
            body,
            message_id: Some(format!("<stellwerk-{}@deutschebahn.com>", Uuid::new_v4())),
            in_reply_to: None,
            claim_id: Some(claim.id),
        },
    )
    .await?;
    Ok(Json(result))
}

#[derive(Deserialize)]
pub struct ClockBody {
    #[serde(default)]
    pub shift: Option<String>,
    #[serde(default)]
    pub offset_secs: Option<i64>,
}

pub async fn get_clock(State(_s): State<AppState>, _a: Admin) -> ApiResult {
    Ok(Json(json!({ "now": clock::now(), "real_now": chrono::Utc::now(), "offset_secs": clock::offset_secs() })))
}

pub async fn set_clock(State(s): State<AppState>, _a: Admin, Json(b): Json<ClockBody>) -> ApiResult {
    let secs = match (b.offset_secs, b.shift.as_deref()) {
        (Some(o), _) => o,
        (None, Some(sh)) => clock::offset_secs() + clock::parse_shift(sh).ok_or_else(|| err(StatusCode::BAD_REQUEST, "bad shift, e.g. +100d, -2h, 90m"))?,
        (None, None) => 0,
    };
    clock::set_offset(&s.pool, secs).await.map_err(internal)?;
    Ok(Json(json!({ "now": clock::now(), "offset_secs": secs })))
}

pub async fn reset(State(s): State<AppState>, _a: Admin, Path(key): Path<String>) -> ApiResult {
    let c = resolve(&s, &key).await?;
    let trips: Vec<String> = sqlx::query_scalar("select distinct trip_id from rides where customer_id = $1").bind(c.id).fetch_all(&s.pool).await.map_err(internal)?;
    for t in &trips {
        let _ = s.train.clear_override(&s.pool, t).await;
    }
    for table in ["mails", "claims", "incidents", "uploads", "rides", "badge_awards"] {
        sqlx::query(&format!("delete from {table} where customer_id = $1")).bind(c.id).execute(&s.pool).await.map_err(internal)?;
    }
    Ok(Json(json!({ "reset": c.nickname, "trip_overrides_cleared": trips.len() })))
}

pub async fn overrides(State(s): State<AppState>, _a: Admin) -> ApiResult {
    Ok(Json(json!(s.train.all_overrides())))
}

pub async fn clear_overrides(State(s): State<AppState>, _a: Admin) -> ApiResult {
    s.train.clear_all(&s.pool).await.map_err(internal)?;
    Ok(Json(json!({ "cleared": true })))
}
