//! Stellwerk admin API. Guarded by `x-admin-token` = `ADMIN_TOKEN` (default "stellwerk" in dev).
//! Dev and staging only: it changes the world the customers see.

use axum::{
    extract::{FromRequestParts, Path, Query, State},
    http::{request::Parts, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use chrono::{Duration, NaiveTime, TimeZone};
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::auth::internal;
use crate::clock;
use crate::flags;
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
        // The admin API is reachable from the internet in production; compare digests so the
        // comparison time does not depend on how many leading characters match.
        use sha2::{Digest, Sha256};
        if Sha256::digest(given.as_bytes()) == Sha256::digest(expected.as_bytes()) {
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
        "select c.* from customers c join devices d on d.id = c.id
         where c.id::text = $1 or c.id::text like $1 || '%' or lower(c.nickname) = lower($1) or lower(c.relay_address) = lower($1)
         order by d.last_seen_at desc limit 1",
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
        let sim_location: Option<String> = sqlx::query_scalar("select label from sim_customer_location where customer_id = $1").bind(c.id).fetch_optional(&s.pool).await.map_err(internal)?;
        let push_platform: Option<String> = sqlx::query_scalar("select push_platform from devices where id = $1 and push_token is not null").bind(c.id).fetch_optional(&s.pool).await.map_err(internal)?.flatten();
        let (open, incidents): (i64, i64) = sqlx::query_as("select count(*) filter (where status in ('gesammelt','bereit') and discarded_at is null)::bigint, count(*)::bigint from incidents where customer_id = $1")
            .bind(c.id)
            .fetch_one(&s.pool)
            .await
            .map_err(internal)?;
        out.push(json!({
            "id": c.id, "nickname": c.nickname, "relay_address": c.relay_address, "created_at": c.created_at, "last_seen_at": last_seen,
            "riding": ride.is_some(),
            "ride": ride.map(|r| json!({ "id": r.id, "line": r.line, "exit_station_name": r.exit_station_name, "live_delay_min": r.live_delay_min, "passed_stops": r.passed_stops, "checked_in_at": r.checked_in_at, "last_polled_at": r.last_polled_at })),
            "open_incidents": open, "incidents": incidents, "sim_location": sim_location, "push_platform": push_platform,
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
    let _ = crate::train::follower::poll_once(&s.pool, &s.train, &s.stations(), &tokio::sync::broadcast::channel(1).0).await;
    let r: RideRow = sqlx::query_as("select * from rides where id = $1").bind(r.id).fetch_one(&s.pool).await.map_err(internal)?;
    s.events.publish(c.id, "ride", json!({ "ride_id": r.id, "status": "riding", "live_delay_min": r.live_delay_min }));
    Ok(Json(json!({ "override": o, "ride": r })))
}

pub async fn cancel(State(s): State<AppState>, _a: Admin, Path(key): Path<String>) -> ApiResult {
    let c = resolve(&s, &key).await?;
    let Some(r) = current_ride(&s, c.id).await? else { return Err(err(StatusCode::CONFLICT, "customer is not riding")) };
    let mut o = s.train.get_override(&r.trip_id).unwrap_or(TripOverride { trip_id: r.trip_id.clone(), ..Default::default() });
    o.cancelled = true;
    s.train.set_override(&s.pool, o.clone()).await.map_err(internal)?;
    let _ = crate::train::follower::poll_once(&s.pool, &s.train, &s.stations(), &tokio::sync::broadcast::channel(1).0).await;
    let fin = handlers::on_ride_finalised(&s, r.id).await.map_err(internal)?;
    let r: RideRow = sqlx::query_as("select * from rides where id = $1").bind(r.id).fetch_one(&s.pool).await.map_err(internal)?;
    s.events.publish(c.id, "ride", json!({ "ride_id": r.id, "status": r.status, "cancelled": true, "silent": fin.silent_ride, "journey_id": r.journey_id }));
    Ok(Json(json!({ "override": o, "ride": r, "incident": fin.incident, "new_badge": fin.new_badge })))
}

/// Fast-forward: shift the trip so the exit stop lies in the past, then poll. The follower does the rest.
pub async fn fast_forward(State(s): State<AppState>, _a: Admin, Path(key): Path<String>) -> ApiResult {
    let c = resolve(&s, &key).await?;
    let Some(r) = current_ride(&s, c.id).await? else { return Err(err(StatusCode::CONFLICT, "customer is not riding")) };
    let t = s.train.trip(&r.trip_id).await.map_err(|e| err(StatusCode::BAD_GATEWAY, &format!("trip: {e}")))?;
    let exit = t.find_stop(&s.stations().candidate_ids(&r.exit_station_id), &r.exit_station_name).map(|(_, st)| st.clone());
    let arrival = exit.and_then(|st| st.live_arrival.or(st.scheduled_arrival)).unwrap_or(r.planned_arrival + Duration::minutes(r.live_delay_min as i64));
    let target = clock::now() - Duration::minutes(4); // past the 3-minute grace
    let mut o = s.train.get_override(&r.trip_id).unwrap_or(TripOverride { trip_id: r.trip_id.clone(), ..Default::default() });
    if arrival > target {
        o.time_shift_secs += (arrival - target).num_seconds();
    }
    s.train.set_override(&s.pool, o.clone()).await.map_err(internal)?;
    crate::train::follower::poll_once(&s.pool, &s.train, &s.stations(), &tokio::sync::broadcast::channel(1).0).await.map_err(internal)?;
    let r2: RideRow = sqlx::query_as("select * from rides where id = $1").bind(r.id).fetch_one(&s.pool).await.map_err(internal)?;
    if r2.status != RideStatus::Arrived {
        return Err(err(StatusCode::CONFLICT, "follower did not finalise the ride; check the exit stop"));
    }
    let fin = handlers::on_ride_finalised(&s, r.id).await.map_err(internal)?;
    s.events.publish(c.id, "ride", handlers::ride_arrived_payload(r2.id, r2.final_delay_min.unwrap_or(0) as i64, &fin));
    let journey = match &fin.journey {
        Some(j) => Some(crate::journeys::journey_json(&s.pool, j).await.map_err(internal)?),
        None => None,
    };
    Ok(Json(json!({ "ride": r2, "incident": fin.incident, "new_badge": fin.new_badge, "override": o, "journey": journey })))
}

pub async fn poll(State(s): State<AppState>, _a: Admin) -> ApiResult {
    let (tx, mut rx) = tokio::sync::broadcast::channel(64);
    crate::train::follower::poll_once(&s.pool, &s.train, &s.stations(), &tx).await.map_err(internal)?;
    let mut finalised = Vec::new();
    while let Ok(ev) = rx.try_recv() {
        let fin = handlers::on_ride_finalised(&s, ev.ride_id).await.map_err(internal)?;
        s.events.publish(ev.customer_id, "ride", handlers::ride_arrived_payload(ev.ride_id, ev.final_delay_min, &fin));
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
    let claim: Option<ClaimRow> = sqlx::query_as("select * from claims where customer_id = $1 and status in ('sent','question') order by sent_at desc limit 1").bind(c.id).fetch_optional(&s.pool).await.map_err(internal)?;
    let Some(claim) = claim else { return Err(err(StatusCode::CONFLICT, "no sent claim to answer")) };
    // The railway answers to the address the claim went out from (docs/18 §4); old claims without
    // one fall back to the customer's relay address.
    let relay = match claim.reply_address.clone().or_else(|| c.relay_address.clone()) {
        Some(r) => r,
        None => return Err(err(StatusCode::CONFLICT, "customer has no relay address yet")),
    };
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
            // .invalid is reserved by RFC 2606 and can never be delivered to. A rehearsal must not
            // put a real railway address anywhere, not even in a From that is only ever displayed:
            // that string used to be what "Antworten" in the app sent to.
            from: "Servicecenter Fahrgastrechte <fahrgastrechte@servicecenter.invalid>".into(),
            subject: format!("Ihr Antrag auf Entschädigung – Vorgang {}", &claim.id.simple().to_string()[..10]),
            body,
            message_id: Some(format!("<stellwerk-{}@servicecenter.invalid>", Uuid::new_v4())),
            in_reply_to: None,
            claim_id: Some(claim.id),
            attachments: vec![],
            // The Stellwerk plays the desk here; there is no sender to check.
            trusted: true,
            headers: vec![],
            headers_trusted: false,
            from_addresses: vec![],
        },
    )
    .await?;
    // process_inbound already published the mail and incident events (and the push).
    Ok(Json(result))
}

#[derive(Deserialize)]
pub struct ReadMailBody {
    #[serde(default)]
    pub from: Option<String>,
    #[serde(default)]
    pub subject: Option<String>,
    pub body: String,
    /// Read it as the answer to this claim: its rides, and its passenger taken out of the text.
    #[serde(default)]
    pub claim_id: Option<Uuid>,
    /// Or find the claim the way the webhook does, by the address the answer was sent to
    /// (`antrag-…@users.verspaetomat.de`).
    #[serde(default)]
    pub to: Option<String>,
    /// Without a claim: what was claimed for the single ride it is read against, in cents (150).
    #[serde(default)]
    pub claimed_cents: Option<i64>,
    /// Without a claim: that ride's date. A desk names the date, and a reader that cannot tie the
    /// answer to the ride rightly refuses to decide.
    #[serde(default)]
    pub ride_date: Option<chrono::NaiveDate>,
}

/// `POST /admin/read-mail`: how a desk's mail would be read, without it touching anything.
///
/// The same reader the inbound webhook uses — rules, model, gate — minus every write. It exists so
/// a real answer from a desk can be tried before one arrives for real, and so the model's reading
/// of a mail can be checked on the server that holds the key. Nothing is stored, no claim moves.
pub async fn read_mail(State(s): State<AppState>, _a: Admin, Json(b): Json<ReadMailBody>) -> ApiResult {
    let from = b.from.unwrap_or_else(|| "Servicecenter Fahrgastrechte <fahrgastrechte@servicecenter.invalid>".into());
    let subject = b.subject.unwrap_or_else(|| "Ihr Antrag auf Entschädigung".into());
    if b.claim_id.is_some() && b.to.is_some() {
        return Err(err(StatusCode::BAD_REQUEST, "either a claim id or an address, not both"));
    }
    // Who the answer belongs to: the claim named, or whatever the address finds.
    let (target, matched): (Option<(CustomerRow, Option<ClaimRow>)>, Value) = match (b.claim_id, b.to.as_deref()) {
        (Some(id), _) => {
            let claim: Option<ClaimRow> = sqlx::query_as("select * from claims where id = $1").bind(id).fetch_optional(&s.pool).await.map_err(internal)?;
            let Some(claim) = claim else { return Err(err(StatusCode::NOT_FOUND, "no such claim")) };
            let cust: CustomerRow = sqlx::query_as("select * from customers where id = $1").bind(claim.customer_id).fetch_one(&s.pool).await.map_err(internal)?;
            let matched = json!({ "how": "the claim named", "claim_id": claim.id, "customer": cust.nickname, "claim_status": claim.status });
            (Some((cust, Some(claim))), matched)
        }
        (None, Some(to)) => {
            let Some(routed) = handlers::route_inbound(&s.pool, to, None, None).await.map_err(internal)? else {
                return Err(err(StatusCode::NOT_FOUND, "no claim or customer for this address: the webhook would refuse this mail"));
            };
            let matched = json!({ "how": routed.how, "claim_id": routed.claim.as_ref().map(|c| c.id), "customer": routed.customer.nickname, "claim_status": routed.claim.as_ref().map(|c| c.status) });
            (Some((routed.customer, routed.claim)), matched)
        }
        (None, None) => (None, Value::Null),
    };
    let (claim, claimed, rides, known) = match target {
        Some((cust, Some(claim))) => {
            let rows = handlers::claim_rides(&s.pool, claim.id).await.map_err(internal)?;
            let (claimed, rides) = crate::reply::rides_of(&rows);
            let mut known = crate::reply::known_of(&cust, Some(&claim), None);
            known.sent = handlers::sent_by_passenger(&s.pool, cust.id).await.map_err(internal)?;
            (Some(claim), claimed, rides, known)
        }
        // The passenger, but no claim to answer: read like the webhook, where nothing can move.
        Some((cust, None)) => {
            let mut known = crate::reply::known_of(&cust, None, None);
            known.sent = handlers::sent_by_passenger(&s.pool, cust.id).await.map_err(internal)?;
            (None, vec![], vec![], known)
        }
        None => {
            let date = b.ride_date.unwrap_or_else(|| clock::now().date_naive());
            // A Deutschlandticket ride at the flat 1,50 EUR unless told otherwise: the cap on what a
            // ride may be paid is one of the checks worth seeing, and a generous default hides it.
            let claimed = vec![crate::reply::Claimed { incident_id: Uuid::nil(), reference: "F1".into(), claimed_cents: b.claimed_cents.unwrap_or(150) }];
            let rides = vec![crate::openai::Ride { reference: "F1".into(), date, line: "RE 1".into(), from: "Köln Hbf".into(), to: "Bonn Hbf".into(), delay_min: 70 }];
            (None, claimed, rides, crate::redact::Known::default())
        }
    };
    let mut decision = crate::reply::read(&crate::reply::Mail { from: &from, subject: &subject, body: &b.body }, &known, &claimed, &rides, true).await;
    // Against a real claim the sender check runs as it would on the webhook, with the verification
    // taken as passed — a pasted mail has no provider headers. Without a claim there is no route to
    // check against, and the dry run is about the reading.
    if claim.is_some() {
        handlers::guard_sender(&s.pool, claim.as_ref(), &from, false, &json!({ "aligned": true }), &mut decision).await?;
    }
    Ok(Json(json!({
        "model_configured": crate::openai::Config::from_env().map(|c| c.model),
        "matched": matched,
        "read_by": decision.read_by,
        "verdict": decision.verdict,
        "trace": decision.trace,
    })))
}

/// `GET /admin/replies`: the latest desk answers, with who read each and why — the list to go through
/// after the model was unavailable, or to see why a claim did not move.
pub async fn replies(State(s): State<AppState>, _a: Admin) -> ApiResult {
    let rows: Vec<MailRow> = sqlx::query_as("select * from mails where direction = 'inbound' order by occurred_at desc limit 50").fetch_all(&s.pool).await.map_err(internal)?;
    Ok(Json(json!(rows
        .into_iter()
        .map(|m| json!({
            "id": m.id, "claim_id": m.claim_id, "at": m.occurred_at, "from": m.from_addr, "subject": m.subject,
            "outcome": m.outcome, "amount_cents": m.amount_cents, "read_by": m.read_by,
            "because": m.reading.as_ref().and_then(|r| r["verdict"]["because"].as_str().map(str::to_string)),
            "sender_verified": m.sender_auth.as_ref().and_then(|a| a["how"].as_str().map(str::to_string)),
        }))
        .collect::<Vec<_>>())))
}

/// `POST /admin/mails/{id}/reread`: read a stored desk answer again and let it act.
pub async fn reread(State(s): State<AppState>, _a: Admin, Path(id): Path<Uuid>) -> ApiResult {
    Ok(Json(handlers::reread_mail(&s, id).await?))
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
    s.events.publish_all("clock", json!({ "now": clock::now(), "offset_secs": secs }));
    Ok(Json(json!({ "now": clock::now(), "offset_secs": secs })))
}

// ---------------------------------------------------------------------------
// Switches (#40): turn a shipped behaviour off from the server, without a new build.
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct SwitchesBody {
    #[serde(default)]
    pub stations_local: Option<bool>,
}

pub async fn switches(State(s): State<AppState>, _a: Admin) -> ApiResult {
    Ok(Json(read_switches(&s.pool).await.map_err(internal)?))
}

/// Every field is optional: a body that names one switch leaves the others alone, so a second
/// switch can never be cleared by a command that did not mention it.
pub async fn switch_set(State(s): State<AppState>, _a: Admin, Json(b): Json<SwitchesBody>) -> ApiResult {
    if let Some(v) = b.stations_local {
        sqlx::query("update app_switches set stations_local = $1, updated_at = now() where id = 1")
            .bind(v)
            .execute(&s.pool)
            .await
            .map_err(internal)?;
    }
    Ok(Json(read_switches(&s.pool).await.map_err(internal)?))
}

async fn read_switches(pool: &sqlx::PgPool) -> sqlx::Result<Value> {
    let (stations_local, updated_at): (bool, chrono::DateTime<chrono::Utc>) =
        sqlx::query_as("select stations_local, updated_at from app_switches where id = 1").fetch_one(pool).await?;
    Ok(json!({ "stations_local": stations_local, "updated_at": updated_at }))
}

// ---------------------------------------------------------------------------
// Feature flags (#41): the general form of the switch above.
// ---------------------------------------------------------------------------
//
// Every write here changes behaviour on every phone with no review and no build, so: an unknown
// key is a 404 and never an implicit create, every write records why in `flag_log`, every write
// can be asked what it would do without doing it, and a global write says how many people it
// reaches before it is allowed to happen (the CLI turns that into the --yes gate).

type FlagDbRow = (String, String, Value, Option<i32>, bool, chrono::DateTime<chrono::Utc>);

fn unknown_flag() -> (StatusCode, Json<Value>) {
    (StatusCode::NOT_FOUND, Json(json!({ "error": "unknown flag", "known": flags::keys() })))
}

/// How many people a global setting reaches. Two counts, no scan of ids: a rollout's share is
/// reported as the estimate it is rather than by hashing the whole table.
async fn reach(s: &AppState, key: &str, rollout_bp: Option<i32>) -> Result<Value, (StatusCode, Json<Value>)> {
    let total: i64 = sqlx::query_scalar("select count(*)::bigint from customers").fetch_one(&s.pool).await.map_err(internal)?;
    let overridden: i64 = sqlx::query_scalar("select count(*)::bigint from customers where jsonb_exists(flag_overrides, $1)")
        .bind(key)
        .fetch_one(&s.pool)
        .await
        .map_err(internal)?;
    let open = total - overridden;
    let reached = match rollout_bp {
        None => open,
        Some(bp) => ((open as f64) * (bp as f64) / 10_000.0).round() as i64,
    };
    Ok(json!({ "customers": total, "with_override": overridden, "reached": reached, "estimated": rollout_bp.is_some() }))
}

async fn flag_db_row(s: &AppState, key: &str) -> Result<Option<FlagDbRow>, (StatusCode, Json<Value>)> {
    sqlx::query_as("select key, kind, value, rollout_bp, orphan, updated_at from flags where key = $1")
        .bind(key)
        .fetch_optional(&s.pool)
        .await
        .map_err(internal)
}

/// One line of the listing: what the registry says, and what a human has said since.
fn flag_json(row: Option<&FlagDbRow>, overrides: i64, last: Option<&Value>) -> Value {
    let key = row.map(|r| r.0.clone()).unwrap_or_default();
    let spec = flags::spec(&key);
    let mut v = json!({
        "key": key,
        "kind": spec.map(flags::Spec::kind).map(Value::from).unwrap_or(row.map(|r| Value::from(r.1.clone())).unwrap_or(Value::Null)),
        "default": spec.map(flags::Spec::default_json).unwrap_or(Value::Null),
        "wire": spec.map(flags::Spec::wire).map(Value::from).unwrap_or(Value::Null),
        "note": spec.map(flags::Spec::note).map(Value::from).unwrap_or(Value::Null),
        // What is stored, raw — including a value of the wrong type, so a human can see the row
        // the warning in the deploy log is about. `default` beside it is what is actually served.
        "value": row.map(|r| r.2.clone()).unwrap_or(Value::Null),
        "rollout_bp": row.and_then(|r| r.3).map(Value::from).unwrap_or(Value::Null),
        "orphan": row.map(|r| r.4).unwrap_or(spec.is_none()),
        "updated_at": row.map(|r| json!(r.5)).unwrap_or(Value::Null),
        "overrides": overrides,
    });
    v["last_change"] = last.cloned().unwrap_or(Value::Null);
    v
}

/// `GET /admin/flags`: every flag the registry claims, plus every orphan row still on disk.
pub async fn flags_list(State(s): State<AppState>, _a: Admin) -> ApiResult {
    let rows: Vec<FlagDbRow> = sqlx::query_as("select key, kind, value, rollout_bp, orphan, updated_at from flags order by key")
        .fetch_all(&s.pool)
        .await
        .map_err(internal)?;
    let counts: Vec<(String, i64)> =
        sqlx::query_as("select k, count(*)::bigint from customers c, lateral jsonb_object_keys(c.flag_overrides) k group by k")
            .fetch_all(&s.pool)
            .await
            .map_err(internal)?;
    let last: Vec<(String, chrono::DateTime<chrono::Utc>, Option<String>, Option<Uuid>)> =
        sqlx::query_as("select distinct on (key) key, at, reason, customer_id from flag_log order by key, at desc")
            .fetch_all(&s.pool)
            .await
            .map_err(internal)?;

    let count_of = |key: &str| counts.iter().find(|(k, _)| k == key).map(|(_, n)| *n).unwrap_or(0);
    let last_of = |key: &str| {
        last.iter()
            .find(|(k, ..)| k == key)
            .map(|(_, at, reason, customer)| json!({ "at": at, "reason": reason, "customer": customer }))
    };

    let mut out = Vec::new();
    // Registry order first: that is the order a human reads them in the source.
    for spec in flags::ALL {
        let row = rows.iter().find(|r| r.0 == spec.key());
        let mut v = flag_json(row, count_of(spec.key()), last_of(spec.key()).as_ref());
        // A flag the reconcile has not reached yet still has a key and a default.
        v["key"] = json!(spec.key());
        v["kind"] = json!(spec.kind());
        v["default"] = spec.default_json();
        v["wire"] = json!(spec.wire());
        v["note"] = json!(spec.note());
        v["orphan"] = json!(false);
        out.push(v);
    }
    for row in rows.iter().filter(|r| flags::spec(&r.0).is_none()) {
        out.push(flag_json(Some(row), count_of(&row.0), last_of(&row.0).as_ref()));
    }
    Ok(Json(json!(out)))
}

/// `GET /admin/flags/{key}`: the flag, who has an override, and the last ten changes.
pub async fn flag_get(State(s): State<AppState>, _a: Admin, Path(key): Path<String>) -> ApiResult {
    let row = flag_db_row(&s, &key).await?;
    if row.is_none() && flags::spec(&key).is_none() {
        return Err(unknown_flag());
    }
    let overrides: Vec<(Uuid, String, Value)> = sqlx::query_as(
        "select id, nickname, flag_overrides -> $1 from customers where jsonb_exists(flag_overrides, $1) order by nickname",
    )
    .bind(&key)
    .fetch_all(&s.pool)
    .await
    .map_err(internal)?;
    let log: Vec<(chrono::DateTime<chrono::Utc>, Option<Uuid>, Option<Value>, Option<Value>, Option<String>)> =
        sqlx::query_as("select at, customer_id, from_value, to_value, reason from flag_log where key = $1 order by at desc limit 10")
            .bind(&key)
            .fetch_all(&s.pool)
            .await
            .map_err(internal)?;

    let mut v = flag_json(row.as_ref(), overrides.len() as i64, None);
    if let Some(spec) = flags::spec(&key) {
        v["key"] = json!(spec.key());
        v["kind"] = json!(spec.kind());
        v["default"] = spec.default_json();
        v["wire"] = json!(spec.wire());
        v["note"] = json!(spec.note());
        v["orphan"] = json!(false);
    }
    v["reach"] = reach(&s, &key, row.as_ref().and_then(|r| r.3)).await?;
    v["overrides_list"] = json!(overrides
        .iter()
        .map(|(id, nickname, value)| json!({ "customer": id, "nickname": nickname, "value": value }))
        .collect::<Vec<_>>());
    v["log"] = json!(log
        .iter()
        .map(|(at, customer, from, to, reason)| json!({ "at": at, "customer": customer, "from": from, "to": to, "reason": reason }))
        .collect::<Vec<_>>());
    Ok(Json(v))
}

#[derive(Deserialize)]
pub struct FlagBody {
    /// The global value, as JSON of the flag's kind. Absent leaves it alone.
    #[serde(default)]
    pub value: Option<Value>,
    /// Absent leaves the rollout alone; `null` hands the value to everybody.
    #[serde(default, deserialize_with = "crate::admin::double_option")]
    pub rollout_bp: Option<Option<i32>>,
    #[serde(default)]
    pub reason: Option<String>,
    /// Say what would change and write nothing.
    #[serde(default)]
    pub dry_run: bool,
}

/// `POST /admin/flags/{key}`: the global value and the rollout.
///
/// Partial, like `SwitchesBody`: a body that names one thing leaves the others alone, and an
/// unknown top-level field is ignored rather than rejected, so an older server survives a newer
/// stellwerk.
pub async fn flag_set(State(s): State<AppState>, _a: Admin, Path(key): Path<String>, Json(b): Json<FlagBody>) -> ApiResult {
    let Some(spec) = flags::spec(&key) else { return Err(unknown_flag()) };
    if let Some(v) = &b.value {
        if !spec.accepts(v) {
            return Err(err(StatusCode::BAD_REQUEST, &format!("value is not a {}", spec.kind())));
        }
    }
    if let Some(Some(bp)) = b.rollout_bp {
        if !(0..=10_000).contains(&bp) {
            return Err(err(StatusCode::BAD_REQUEST, "rollout_bp is basis points, 0..=10000"));
        }
    }
    let row = flag_db_row(&s, &key).await?;
    let was_value = row.as_ref().map(|r| r.2.clone()).unwrap_or_else(|| spec.default_json());
    let was_rollout = row.as_ref().and_then(|r| r.3);
    let value = b.value.clone().unwrap_or_else(|| was_value.clone());
    let rollout = match b.rollout_bp {
        Some(bp) => bp,
        None => was_rollout,
    };
    let reach = reach(&s, &key, rollout).await?;

    if !b.dry_run {
        let mut tx = s.pool.begin().await.map_err(internal)?;
        sqlx::query(
            "insert into flags (key, kind, value, rollout_bp) values ($1, $2, $3, $4)
             on conflict (key) do update set value = excluded.value, rollout_bp = excluded.rollout_bp,
                 kind = excluded.kind, orphan = false, updated_at = now()",
        )
        .bind(spec.key())
        .bind(spec.kind())
        .bind(&value)
        .bind(rollout)
        .execute(&mut *tx)
        .await
        .map_err(internal)?;
        // The whole setting, not just the value: ending a rollout changes nothing about the
        // value, and a history that records it as "true → true" hides what happened.
        sqlx::query("insert into flag_log (key, customer_id, from_value, to_value, reason) values ($1, null, $2, $3, $4)")
            .bind(spec.key())
            .bind(json!({ "value": was_value, "rollout_bp": was_rollout }))
            .bind(json!({ "value": value, "rollout_bp": rollout }))
            .bind(&b.reason)
            .execute(&mut *tx)
            .await
            .map_err(internal)?;
        tx.commit().await.map_err(internal)?;
        s.reload_flags().await.map_err(internal)?;
        // publish_all goes through `all_sender`, not `sender_for`, so it allocates nothing per
        // customer and leaks nothing (#42). No build that exists today reacts to a `flags` event
        // — events.dart classifies through a closed set of predicates and drops the rest — so
        // this is a convenience for the dev loop and never a delivery guarantee. A flag lands on
        // a phone at its next foreground fetch, and on a phone nobody opens, never.
        s.events.publish_all("flags", json!({ "etag": s.flags().etag() }));
    }

    let mut out = flag_get(State(s.clone()), Admin, Path(key.clone())).await?;
    out.0["dry_run"] = json!(b.dry_run);
    out.0["from"] = json!({ "value": was_value, "rollout_bp": was_rollout });
    out.0["to"] = json!({ "value": value, "rollout_bp": rollout });
    out.0["reach"] = reach;
    Ok(out)
}

#[derive(Deserialize)]
pub struct FlagClearQuery {
    #[serde(default)]
    pub reason: Option<String>,
    #[serde(default)]
    pub dry_run: bool,
}

/// `DELETE /admin/flags/{key}`: forget what a human said, back to the shipped default.
///
/// The row goes; the next startup's reconcile puts it back at the default. Deliberately not a
/// write of the default value: "nobody has said anything about this" and "somebody has said the
/// default" should not look the same in the log.
pub async fn flag_clear(State(s): State<AppState>, _a: Admin, Path(key): Path<String>, Query(q): Query<FlagClearQuery>) -> ApiResult {
    let Some(spec) = flags::spec(&key) else { return Err(unknown_flag()) };
    let row = flag_db_row(&s, &key).await?;
    let was_value = row.as_ref().map(|r| r.2.clone());
    let reach = reach(&s, &key, None).await?;
    if !q.dry_run {
        let mut tx = s.pool.begin().await.map_err(internal)?;
        sqlx::query("delete from flags where key = $1").bind(spec.key()).execute(&mut *tx).await.map_err(internal)?;
        sqlx::query("insert into flag_log (key, customer_id, from_value, to_value, reason) values ($1, null, $2, null, $3)")
            .bind(spec.key())
            .bind(was_value.clone().map(|v| json!({ "value": v, "rollout_bp": row.as_ref().and_then(|r| r.3) })))
            .bind(&q.reason)
            .execute(&mut *tx)
            .await
            .map_err(internal)?;
        tx.commit().await.map_err(internal)?;
        s.reload_flags().await.map_err(internal)?;
        s.events.publish_all("flags", json!({ "etag": s.flags().etag() }));
    }
    Ok(Json(json!({
        "key": spec.key(), "dry_run": q.dry_run,
        "from": { "value": was_value, "rollout_bp": row.as_ref().and_then(|r| r.3) },
        "to": { "value": spec.default_json(), "rollout_bp": Value::Null },
        "default": spec.default_json(), "reach": reach,
    })))
}

/// `GET /admin/customers/{key}/flags`: what this one phone is actually on, and where each answer
/// came from. The first question when something misbehaves in the field.
pub async fn customer_flags(State(s): State<AppState>, _a: Admin, Path(key): Path<String>) -> ApiResult {
    let c = resolve(&s, &key).await?;
    Ok(Json(json!({
        "customer": c.nickname, "id": c.id,
        "flags": s.flags().explain(Some((&c).into())),
        "overrides": c.flag_overrides,
    })))
}

#[derive(Deserialize)]
pub struct CustomerFlagBody {
    pub value: Value,
    #[serde(default)]
    pub reason: Option<String>,
    #[serde(default)]
    pub dry_run: bool,
}

/// `PUT /admin/customers/{who}/flags/{flag}`: this one person, whatever the rollout says.
///
/// Nothing is published: `EventHub::publish` allocates a permanent channel for a customer who
/// has never connected (#42), and a person who has just been targeted is almost certainly not
/// connected. The override arrives on their next authenticated fetch.
pub async fn customer_flag_set(
    State(s): State<AppState>,
    _a: Admin,
    Path((key, flag)): Path<(String, String)>,
    Json(b): Json<CustomerFlagBody>,
) -> ApiResult {
    let Some(spec) = flags::spec(&flag) else { return Err(unknown_flag()) };
    if !spec.accepts(&b.value) {
        return Err(err(StatusCode::BAD_REQUEST, &format!("value is not a {}", spec.kind())));
    }
    let c = resolve(&s, &key).await?;
    let was = c.flag_overrides.get(spec.key()).cloned();
    if !b.dry_run {
        let mut tx = s.pool.begin().await.map_err(internal)?;
        sqlx::query("update customers set flag_overrides = flag_overrides || jsonb_build_object($2::text, $3::jsonb) where id = $1")
            .bind(c.id)
            .bind(spec.key())
            .bind(&b.value)
            .execute(&mut *tx)
            .await
            .map_err(internal)?;
        sqlx::query("insert into flag_log (key, customer_id, from_value, to_value, reason) values ($1, $2, $3, $4, $5)")
            .bind(spec.key())
            .bind(c.id)
            .bind(&was)
            .bind(&b.value)
            .bind(&b.reason)
            .execute(&mut *tx)
            .await
            .map_err(internal)?;
        tx.commit().await.map_err(internal)?;
    }
    let after: CustomerRow = if b.dry_run { c.clone() } else { resolve(&s, &c.id.to_string()).await? };
    Ok(Json(json!({
        "customer": c.nickname, "id": c.id, "key": spec.key(), "dry_run": b.dry_run,
        "from": was, "to": b.value,
        "flags": s.flags().explain(Some((&after).into())),
    })))
}

/// `DELETE /admin/customers/{who}/flags/{flag}`: back to whatever everybody else gets.
pub async fn customer_flag_clear(
    State(s): State<AppState>,
    _a: Admin,
    Path((key, flag)): Path<(String, String)>,
    Query(q): Query<FlagClearQuery>,
) -> ApiResult {
    let Some(spec) = flags::spec(&flag) else { return Err(unknown_flag()) };
    let c = resolve(&s, &key).await?;
    let was = c.flag_overrides.get(spec.key()).cloned();
    if !q.dry_run {
        let mut tx = s.pool.begin().await.map_err(internal)?;
        sqlx::query("update customers set flag_overrides = flag_overrides - $2::text where id = $1")
            .bind(c.id)
            .bind(spec.key())
            .execute(&mut *tx)
            .await
            .map_err(internal)?;
        sqlx::query("insert into flag_log (key, customer_id, from_value, to_value, reason) values ($1, $2, $3, null, $4)")
            .bind(spec.key())
            .bind(c.id)
            .bind(&was)
            .bind(&q.reason)
            .execute(&mut *tx)
            .await
            .map_err(internal)?;
        tx.commit().await.map_err(internal)?;
    }
    let after: CustomerRow = if q.dry_run { c.clone() } else { resolve(&s, &c.id.to_string()).await? };
    Ok(Json(json!({
        "customer": c.nickname, "id": c.id, "key": spec.key(), "dry_run": q.dry_run,
        "from": was, "to": Value::Null,
        "flags": s.flags().explain(Some((&after).into())),
    })))
}

pub async fn reset(State(s): State<AppState>, _a: Admin, Path(key): Path<String>) -> ApiResult {
    let c = resolve(&s, &key).await?;
    let trips: Vec<String> = sqlx::query_scalar("select distinct trip_id from rides where customer_id = $1").bind(c.id).fetch_all(&s.pool).await.map_err(internal)?;
    for t in &trips {
        let _ = s.train.clear_override(&s.pool, t).await;
    }
    for table in ["mails", "claims", "incidents", "uploads", "rides", "journeys", "badge_awards", "sim_customer_location"] {
        sqlx::query(&format!("delete from {table} where customer_id = $1")).bind(c.id).execute(&s.pool).await.map_err(internal)?;
    }
    s.events.publish(c.id, "reset", json!({}));
    Ok(Json(json!({ "reset": c.nickname, "trip_overrides_cleared": trips.len() })))
}

pub async fn overrides(State(s): State<AppState>, _a: Admin) -> ApiResult {
    Ok(Json(json!(s.train.all_overrides())))
}

pub async fn clear_overrides(State(s): State<AppState>, _a: Admin) -> ApiResult {
    s.train.clear_all(&s.pool).await.map_err(internal)?;
    Ok(Json(json!({ "cleared": true })))
}

#[derive(Deserialize)]
pub struct LocateBody {
    #[serde(default)]
    pub lat: Option<f64>,
    #[serde(default)]
    pub lon: Option<f64>,
    /// A station name to geocode instead of coordinates, e.g. "Köln Hbf".
    #[serde(default)]
    pub station: Option<String>,
}

/// Put a customer somewhere. Overrides the phone's GPS for nearby stations until cleared.
pub async fn locate(State(s): State<AppState>, _a: Admin, Path(key): Path<String>, Json(b): Json<LocateBody>) -> ApiResult {
    let c = resolve(&s, &key).await?;
    let (lat, lon, label) = match (b.lat, b.lon, b.station) {
        (Some(lat), Some(lon), station) => (lat, lon, station.unwrap_or_default()),
        (_, _, Some(name)) => {
            // Our own table first (issue #37): it holds the coordinates and asking Transitous for
            // them is a request nobody needs. The geocoder stays as the fallback because this is
            // an admin path — no passenger's position is involved — and because `stellwerk locate`
            // has to keep working on a machine whose stations have not been imported yet.
            match s.stations().search(&name, 1).into_iter().next() {
                Some(h) => (h.lat, h.lon, h.name),
                None => {
                    let hits = s.train.search_stops(&name).await.map_err(internal)?;
                    let hit = hits.into_iter().next().ok_or_else(|| err(StatusCode::NOT_FOUND, "no station with that name"))?;
                    (hit.lat, hit.lon, hit.name)
                }
            }
        }
        _ => return Err(err(StatusCode::BAD_REQUEST, "give lat and lon, or a station name")),
    };
    sqlx::query("insert into sim_customer_location (customer_id, lat, lon, label) values ($1,$2,$3,$4) on conflict (customer_id) do update set lat = excluded.lat, lon = excluded.lon, label = excluded.label, updated_at = now()")
        .bind(c.id)
        .bind(lat)
        .bind(lon)
        .bind(&label)
        .execute(&s.pool)
        .await
        .map_err(internal)?;
    s.events.publish(c.id, "location", json!({ "lat": lat, "lon": lon, "label": label, "source": "stellwerk" }));
    Ok(Json(json!({ "customer": c.nickname, "lat": lat, "lon": lon, "label": label })))
}

pub async fn clear_location(State(s): State<AppState>, _a: Admin, Path(key): Path<String>) -> ApiResult {
    let c = resolve(&s, &key).await?;
    sqlx::query("delete from sim_customer_location where customer_id = $1").bind(c.id).execute(&s.pool).await.map_err(internal)?;
    s.events.publish(c.id, "location", json!({ "source": "gps" }));
    Ok(Json(json!({ "customer": c.nickname, "cleared": true })))
}

#[derive(Deserialize)]
pub struct ForgetQuery {
    #[serde(default)]
    pub force: bool,
}

/// `DELETE /admin/customers/{key}`: forget a customer. The device row goes, everything cascades.
/// A customer who already has a relay address and a sent claim is refused with 409 unless `?force=true`:
/// a railway may still answer to that address.
pub async fn forget(State(s): State<AppState>, _a: Admin, Path(key): Path<String>, Query(q): Query<ForgetQuery>) -> ApiResult {
    let c = resolve(&s, &key).await?;
    let sent: i64 = sqlx::query_scalar("select count(*) from claims where customer_id = $1 and status <> 'draft'").bind(c.id).fetch_one(&s.pool).await.map_err(internal)?;
    if !q.force && c.relay_address.is_some() && sent > 0 {
        return Err((
            StatusCode::CONFLICT,
            Json(json!({ "error": "customer has a relay address and sent claims; repeat with ?force=true", "relay_address": c.relay_address, "sent_claims": sent })),
        ));
    }
    let trips: Vec<String> = sqlx::query_scalar("select distinct trip_id from rides where customer_id = $1").bind(c.id).fetch_all(&s.pool).await.map_err(internal)?;
    for t in &trips {
        let _ = s.train.clear_override(&s.pool, t).await;
    }
    s.events.publish(c.id, "reset", json!({ "forgotten": true }));
    sqlx::query("delete from devices where id = $1").bind(c.id).execute(&s.pool).await.map_err(internal)?;
    Ok(Json(json!({ "forgotten": c.id, "nickname": c.nickname, "sent_claims": sent, "trip_overrides_cleared": trips.len() })))
}

#[derive(Deserialize)]
pub struct PushBody {
    #[serde(default)]
    pub text: Option<String>,
}

/// `POST /admin/customers/{key}/push`: a test notification to the customer's device.
/// Dry-run (logged only) when no APNs/FCM credentials are configured.
pub async fn push(State(s): State<AppState>, _a: Admin, Path(key): Path<String>, Json(b): Json<PushBody>) -> ApiResult {
    let c = resolve(&s, &key).await?;
    let (platform, token): (Option<String>, Option<String>) =
        sqlx::query_as("select push_platform, push_token from devices where id = $1").bind(c.id).fetch_one(&s.pool).await.map_err(internal)?;
    let n = crate::push::Notification {
        title: "Verspätomat".to_string(),
        body: b.text.filter(|t| !t.trim().is_empty()).unwrap_or_else(|| "Testnachricht vom Stellwerk.".to_string()),
        kind: "test",
        data: json!({}),
    };
    let result = crate::push::deliver(&s, c.id, &n).await.map_err(internal)?;
    Ok(Json(json!({
        "customer": c.id,
        "nickname": c.nickname,
        "platform": platform,
        "token": token.is_some(),
        "configured": platform.as_deref().map(|p| s.push.configured(p)).unwrap_or(false),
        "result": result,
        "title": n.title,
        "body": n.body,
    })))
}

/// `POST /admin/scan`: one deadline-scanner pass now (the loop runs hourly).
pub async fn scan(State(s): State<AppState>, _a: Admin) -> ApiResult {
    Ok(Json(crate::scanner::run_once(&s).await.map_err(internal)?))
}

// ---------------------------------------------------------------------------
// Rides that already happened
// ---------------------------------------------------------------------------

/// What a backdated case says about itself. A claim form must never dress up an invented ride
/// as live data, so the evidence names the Stellwerk and the case counts as self-entered.
const BACKDATE_SOURCE: &str = "Stellwerk: nachträglich eingetragene Testfahrt";

/// A finished ride to invent for a customer. No feed is asked: the times come from `days_ago`,
/// `departure` and `duration_minutes`, and the trip id is ours. The stations are named by the
/// caller — the server still does not guess a location (docs/14); it only looks their ids up.
#[derive(Deserialize)]
pub struct BackdateBody {
    pub from: String,
    pub to: String,
    /// Minutes late at the destination. 60 and up is what makes a claim.
    #[serde(default = "default_delay")]
    pub delay_minutes: i64,
    /// How many days back the ride departed.
    #[serde(default = "default_days_ago")]
    pub days_ago: i64,
    /// Departure in German local time, "08:12".
    #[serde(default)]
    pub departure: Option<String>,
    /// Scheduled travel time in minutes.
    #[serde(default = "default_duration")]
    pub duration_minutes: i64,
    #[serde(default)]
    pub line: Option<String>,
    /// s | rb | re | fern | bus
    #[serde(default)]
    pub category: Option<String>,
    #[serde(default)]
    pub operator: Option<String>,
    /// deutschlandticket | zeitkarte | einzelfahrkarte; the customer's own by default.
    #[serde(default)]
    pub ticket: Option<String>,
    #[serde(default)]
    pub cancelled: bool,
}

fn default_delay() -> i64 {
    70
}
fn default_days_ago() -> i64 {
    1
}
fn default_duration() -> i64 {
    52
}

fn parse_category(v: Option<&str>) -> Result<crate::train::TrainCategory, (StatusCode, Json<Value>)> {
    use crate::train::TrainCategory as C;
    Ok(match v.unwrap_or("re").trim().to_lowercase().as_str() {
        "s" | "s-bahn" => C::S,
        "rb" => C::Rb,
        "re" => C::Re,
        "fern" | "ice" | "ic" | "ec" => C::Fern,
        "bus" => C::Bus,
        other => return Err(err(StatusCode::BAD_REQUEST, &format!("category must be s|rb|re|fern|bus, got {other}"))),
    })
}

fn parse_ticket(v: &str) -> Result<TicketType, (StatusCode, Json<Value>)> {
    Ok(match v.trim().to_lowercase().as_str() {
        "deutschlandticket" | "dticket" | "d-ticket" => TicketType::Deutschlandticket,
        "zeitkarte" => TicketType::Zeitkarte,
        "einzelfahrkarte" | "einzel" => TicketType::Einzelfahrkarte,
        other => return Err(err(StatusCode::BAD_REQUEST, &format!("ticket must be deutschlandticket|zeitkarte|einzelfahrkarte, got {other}"))),
    })
}

/// The id for a station name: ours from the table, else the feed's, else an invented one.
///
/// Test data must not depend on Transitous being reachable — and since issue #37 it mostly does
/// not, because the table answers first and a backdated ride then carries the same kind of id a
/// real one does.
async fn station_ref(s: &AppState, name: &str) -> (String, String) {
    if let Some(h) = s.stations().search(name, 1).into_iter().next() {
        return (h.id, h.name);
    }
    if let Ok(hits) = s.train.search_stops(name).await {
        if let Some(h) = hits.into_iter().next() {
            return (h.id, h.name);
        }
    }
    let slug: String = name.chars().map(|c| if c.is_alphanumeric() { c.to_ascii_lowercase() } else { '-' }).collect();
    (format!("stellwerk:{}", slug.trim_matches('-')), name.to_string())
}

/// When a backdated ride departed, was due, and arrived. The departure is read in German local
/// time, because that is the clock the timetable and the three-month deadline are printed in;
/// the hour that a spring clock change skips has no ride in it, and None says so.
fn backdate_times(
    now: chrono::DateTime<chrono::Utc>,
    days_ago: i64,
    time: NaiveTime,
    duration_minutes: i64,
    delay_minutes: i64,
) -> Option<(chrono::DateTime<chrono::Utc>, chrono::DateTime<chrono::Utc>, chrono::DateTime<chrono::Utc>)> {
    let tz = chrono_tz::Europe::Berlin;
    let date = now.with_timezone(&tz).date_naive() - Duration::days(days_ago);
    let departure = tz.from_local_datetime(&date.and_time(time)).earliest()?.with_timezone(&chrono::Utc);
    let arrival = departure + Duration::minutes(duration_minutes);
    Some((departure, arrival, arrival + Duration::minutes(delay_minutes)))
}

/// `POST /admin/customers/{key}/backdate`: a ride that already happened, with the delay it had.
/// It writes what an arrival writes — journey, leg, case — so bundles, the monthly cap, deadlines
/// and the claim form see ordinary rows, and the case carries the Stellwerk in its evidence.
pub async fn backdate(State(s): State<AppState>, _a: Admin, Path(key): Path<String>, Json(b): Json<BackdateBody>) -> ApiResult {
    let c = resolve(&s, &key).await?;
    if b.days_ago < 0 {
        return Err(err(StatusCode::BAD_REQUEST, "days_ago must not be negative: the Stellwerk invents the past, not the future"));
    }
    if b.duration_minutes <= 0 {
        return Err(err(StatusCode::BAD_REQUEST, "duration_minutes must be positive"));
    }
    if b.delay_minutes < 0 {
        return Err(err(StatusCode::BAD_REQUEST, "delay_minutes must not be negative"));
    }
    if b.from.trim().is_empty() || b.to.trim().is_empty() {
        return Err(err(StatusCode::BAD_REQUEST, "name both stations: from and to"));
    }
    let category = parse_category(b.category.as_deref())?;
    let ticket = match &b.ticket {
        Some(t) => parse_ticket(t)?,
        None => c.ticket,
    };
    let time = match b.departure.as_deref() {
        Some(t) => NaiveTime::parse_from_str(t.trim(), "%H:%M").map_err(|_| err(StatusCode::BAD_REQUEST, "departure must read HH:MM"))?,
        None => NaiveTime::from_hms_opt(8, 12, 0).unwrap(),
    };
    let (planned_departure, planned_arrival, actual_arrival) = backdate_times(clock::now(), b.days_ago, time, b.duration_minutes, b.delay_minutes)
        .ok_or_else(|| err(StatusCode::BAD_REQUEST, "that local time does not exist on that day (clock change)"))?;
    if actual_arrival > clock::now() {
        return Err(err(StatusCode::BAD_REQUEST, "that ride would still be running; put it further back"));
    }

    let (from_id, from_name) = station_ref(&s, b.from.trim()).await;
    let (to_id, to_name) = station_ref(&s, b.to.trim()).await;
    let operator = b.operator.clone().unwrap_or_else(|| "DB Regio NRW".to_string());
    let operator_known: bool = sqlx::query_scalar("select exists(select 1 from operators where name = $1)").bind(&operator).fetch_one(&s.pool).await.map_err(internal)?;
    let line = b.line.clone().unwrap_or_else(|| "RE 5".to_string());
    let delay = b.delay_minutes;
    let points = crate::rules::points_for(delay, b.cancelled, false);
    let trip_id = format!("stellwerk:{}", Uuid::new_v4());

    let leg = crate::train::PlanLeg {
        trip_id: trip_id.clone(),
        line: line.clone(),
        train_number: None,
        headsign: to_name.clone(),
        agency_name: operator.clone(),
        operator: operator.clone(),
        category,
        mode: "RAIL".into(),
        from_station_id: from_id.clone(),
        from_station_name: from_name.clone(),
        to_station_id: to_id.clone(),
        to_station_name: to_name.clone(),
        planned_departure,
        planned_arrival,
        live_departure: Some(planned_departure),
        live_arrival: Some(actual_arrival),
        platform: None,
        cancelled: b.cancelled,
        realtime: false,
        delay_min: delay,
    };
    let plan = json!([leg]);

    // The journey is what the ledger reads; the ride is its only leg. Both arrive in the past,
    // and both are dismissed: nothing about a ride from last week belongs on the Bahnsteig.
    let j: JourneyRow = sqlx::query_as(
        "insert into journeys (id, customer_id, origin_station_id, origin_station_name, destination_station_id, destination_station_name,
            itinerary, plan, planned_departure, planned_arrival, status, current_leg, actual_arrival, final_delay_min, cancelled, points,
            ticket, created_at, finalised_at, dismissed_at)
         values ($1,$2,$3,$4,$5,$6,$7,$7,$8,$9,'arrived',1,$10,$11,$12,$13,$14,$8,$10,$10) returning *",
    )
    .bind(Uuid::new_v4())
    .bind(c.id)
    .bind(&from_id)
    .bind(&from_name)
    .bind(&to_id)
    .bind(&to_name)
    .bind(&plan)
    .bind(planned_departure)
    .bind(planned_arrival)
    .bind(actual_arrival)
    .bind(delay as i32)
    .bind(b.cancelled)
    .bind(points as i32)
    .bind(ticket)
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;

    let ride: RideRow = sqlx::query_as(
        "insert into rides (id, customer_id, trip_id, line, headsign, operator, category, from_station_id, from_station_name,
            exit_station_id, exit_station_name, planned_departure, planned_arrival, actual_arrival, ticket, status, live_delay_min,
            final_delay_min, cancelled, self_entered, points, checked_in_at, finalised_at, last_polled_at, dismissed_at, journey_id, leg_no)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,'arrived',$16,$16,$17,true,$18,$12,$14,$14,$14,$19,1) returning *",
    )
    .bind(Uuid::new_v4())
    .bind(c.id)
    .bind(&trip_id)
    .bind(&line)
    .bind(&to_name)
    .bind(&operator)
    .bind(crate::handlers::row_category(category))
    .bind(&from_id)
    .bind(&from_name)
    .bind(&to_id)
    .bind(&to_name)
    .bind(planned_departure)
    .bind(planned_arrival)
    .bind(actual_arrival)
    .bind(ticket)
    .bind(delay as i32)
    .bind(b.cancelled)
    .bind(points as i32)
    .bind(j.id)
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;

    crate::rules::audit(&s.pool, "journey", j.id, None, "arrived", "stellwerk backdate").await.map_err(internal)?;
    crate::rules::audit(&s.pool, "ride", ride.id, None, "arrived", "stellwerk backdate").await.map_err(internal)?;

    let rides = vec![ride.clone()];
    let incident = crate::journeys::create_journey_incident(
        &s.pool,
        &j,
        &c,
        &rides,
        rides.first(),
        actual_arrival,
        planned_arrival,
        delay,
        b.cancelled,
        false,
        BACKDATE_SOURCE,
        true,
    )
    .await
    .map_err(internal)?;
    let rows = crate::rules::refresh_statuses(&s.pool, c.id, clock::today()).await.map_err(internal)?;
    let incident = incident.and_then(|i| rows.into_iter().find(|x| x.id == i.id));
    let new_badge = crate::handlers::award_badges(&s.pool, c.id, ride.id, delay).await.map_err(internal)?;
    // A ride from the past has no news to announce: the phone reloads its lists, nothing pops up.
    s.events.publish(c.id, "resync", json!({ "reason": "backdate", "journey_id": j.id }));

    Ok(Json(json!({
        "customer": c.nickname, "journey": j, "ride": ride, "incident": incident, "new_badge": new_badge,
        "points": points, "operator_known": operator_known,
    })))
}



#[cfg(test)]
mod tests {
    use super::*;

    /// The departure is a German clock time, whatever the server's timezone is, and summer time
    /// moves it against UTC. The deadline hangs off that date, so an hour matters.
    #[test]
    fn backdated_rides_depart_on_the_german_clock() {
        let at = |h, m| NaiveTime::from_hms_opt(h, m, 0).unwrap();
        let now = |s: &str| chrono::DateTime::parse_from_rfc3339(s).unwrap().with_timezone(&chrono::Utc);

        // Summer time: 08:12 in Bonn is 06:12 UTC. 52 minutes planned, 70 late.
        let (dep, arr, actual) = backdate_times(now("2026-09-13T20:47:00Z"), 3, at(8, 12), 52, 70).unwrap();
        assert_eq!(dep.to_rfc3339(), "2026-09-10T06:12:00+00:00");
        assert_eq!(arr.to_rfc3339(), "2026-09-10T07:04:00+00:00");
        assert_eq!(actual.to_rfc3339(), "2026-09-10T08:14:00+00:00");

        // Winter time: the same clock time is an hour later in UTC.
        let (dep, _, _) = backdate_times(now("2026-12-01T10:00:00Z"), 1, at(8, 12), 52, 70).unwrap();
        assert_eq!(dep.to_rfc3339(), "2026-11-30T07:12:00+00:00");

        // The hour the spring clock change skips has no ride in it.
        assert!(backdate_times(now("2026-03-30T10:00:00Z"), 1, at(2, 30), 52, 70).is_none());
    }

    /// #40: the partial-update rule, at the level where it is actually decided. `switch_set`
    /// writes a column only for a field serde produced a `Some` for, so a body that does not
    /// name a switch cannot clear it — and a second switch added later inherits that for free.
    #[test]
    fn a_switch_body_names_only_what_it_sets() {
        let none: SwitchesBody = serde_json::from_str("{}").unwrap();
        assert_eq!(none.stations_local, None);
        let off: SwitchesBody = serde_json::from_str(r#"{"stations_local":false}"#).unwrap();
        assert_eq!(off.stations_local, Some(false));
        let on: SwitchesBody = serde_json::from_str(r#"{"stations_local":true}"#).unwrap();
        assert_eq!(on.stations_local, Some(true));
        // An unknown switch is ignored rather than rejected, so an older server survives a
        // newer stellwerk naming a switch it has never heard of.
        let other: SwitchesBody = serde_json::from_str(r#"{"something_else":true}"#).unwrap();
        assert_eq!(other.stations_local, None);
    }

    /// #41: the same rule for flags, plus the one serde trap that would break it. `rollout_bp`
    /// is a nested Option because "stop the rollout" (`null`) and "this body does not mention
    /// the rollout" (absent) are different instructions, and a plain `Option<i32>` reads both as
    /// `None`.
    #[test]
    fn a_flag_body_names_only_what_it_sets() {
        let none: FlagBody = serde_json::from_str("{}").unwrap();
        assert_eq!(none.value, None);
        assert_eq!(none.rollout_bp, None);
        assert!(!none.dry_run);

        let value_only: FlagBody = serde_json::from_str(r#"{"value":true}"#).unwrap();
        assert_eq!(value_only.value, Some(json!(true)));
        assert_eq!(value_only.rollout_bp, None, "a body that says nothing about the rollout must not end it");

        let stop: FlagBody = serde_json::from_str(r#"{"rollout_bp":null}"#).unwrap();
        assert_eq!(stop.rollout_bp, Some(None), "an explicit null is the instruction to hand the value to everybody");

        let tenth: FlagBody = serde_json::from_str(r#"{"rollout_bp":1000}"#).unwrap();
        assert_eq!(tenth.rollout_bp, Some(Some(1000)));

        // An unknown field is ignored rather than rejected, so an older server survives a newer
        // stellwerk.
        let other: FlagBody = serde_json::from_str(r#"{"something_else":true}"#).unwrap();
        assert_eq!(other.value, None);
    }

    /// An explicit `false` is a value, not an absence: it is how one person is taken back out of
    /// a rollout, and `CustomerFlagBody::value` is required precisely so that "clear" has to be
    /// a DELETE rather than a body serde cannot tell from `{}`.
    #[test]
    fn targeting_one_person_off_is_not_the_same_as_clearing() {
        let off: CustomerFlagBody = serde_json::from_str(r#"{"value":false}"#).unwrap();
        assert_eq!(off.value, json!(false));
        assert!(serde_json::from_str::<CustomerFlagBody>("{}").is_err(), "an empty body must not read as an instruction");
    }

    /// Needs Postgres (`DATABASE_URL`, default `postgres://localhost/verspaetomat`), like the
    /// station sweep in `stations::extract`. Run it with
    ///
    /// ```text
    /// cargo test --bin verspaetomat-api switches -- --ignored --nocapture
    /// ```
    ///
    /// It restores whatever the row held before, so running it against a dev database that has
    /// the switch flipped on does not silently flip it back.
    #[tokio::test]
    #[ignore]
    async fn switches_round_trip_and_default_to_the_old_path() {
        let url = std::env::var("DATABASE_URL").unwrap_or_else(|_| "postgres://localhost/verspaetomat".into());
        let pool = sqlx::postgres::PgPoolOptions::new().max_connections(2).connect(&url).await.expect("connect to postgres");

        // What a *fresh* database answers, independently of whatever this one has been set to:
        // the column's own default is the behaviour that already shipped, and migration 0037
        // inserts the single row without naming it.
        let default_clause: Option<String> = sqlx::query_scalar(
            "select column_default from information_schema.columns
             where table_name = 'app_switches' and column_name = 'stations_local'",
        )
        .fetch_one(&pool)
        .await
        .expect("the column exists");
        assert_eq!(default_clause.as_deref(), Some("false"));

        // What `handlers::geofence` does when the row is missing altogether: `fetch_optional`
        // gives `None` and the handler's `unwrap_or(false)` keeps the old path.
        let missing: Option<bool> = sqlx::query_scalar("select stations_local from app_switches where id = 2")
            .fetch_optional(&pool)
            .await
            .expect("query");
        assert_eq!(missing.unwrap_or(false), false);

        let before = read_switches(&pool).await.expect("read");
        let was = before["stations_local"].as_bool().expect("a boolean");

        let set = |v: bool| {
            let pool = pool.clone();
            async move {
                sqlx::query("update app_switches set stations_local = $1, updated_at = now() where id = 1")
                    .bind(v)
                    .execute(&pool)
                    .await
                    .expect("update");
                read_switches(&pool).await.expect("read")
            }
        };

        assert_eq!(set(true).await["stations_local"], json!(true));
        assert_eq!(set(false).await["stations_local"], json!(false));
        assert_eq!(set(true).await["stations_local"], json!(true));

        // A body that names nothing writes nothing: `switch_set`'s `if let Some(v)` never runs.
        let empty: SwitchesBody = serde_json::from_str("{}").unwrap();
        assert!(empty.stations_local.is_none());
        assert_eq!(read_switches(&pool).await.expect("read")["stations_local"], json!(true));

        set(was).await;
    }
}

// ---------------------------------------------------------------------------
// Journeys (docs/17): the Stellwerk's view and the confirmation the phone would send.
// ---------------------------------------------------------------------------

/// `GET /admin/customers/{key}/journey`: the current (or last) journey with legs and the proposal.
pub async fn journey(State(s): State<AppState>, _a: Admin, Path(key): Path<String>) -> ApiResult {
    let c = resolve(&s, &key).await?;
    let j: Option<JourneyRow> = sqlx::query_as("select * from journeys where customer_id = $1 order by (status in ('riding','transfer')) desc, created_at desc limit 1").bind(c.id).fetch_optional(&s.pool).await.map_err(internal)?;
    let Some(j) = j else { return Ok(Json(json!({ "customer": c.nickname, "journey": Value::Null }))) };
    let mut v = crate::journeys::current_payload(&s, &j, false).await.map_err(internal)?;
    v["customer"] = json!(c.nickname);
    v["now"] = json!(clock::now());
    Ok(Json(v))
}

#[derive(Deserialize, Default)]
pub struct ConfirmBody {
    #[serde(default)]
    pub trip_id: Option<String>,
}

/// `POST /admin/customers/{key}/confirm`: confirms the proposed next leg (or a given trip) as the phone would.
pub async fn confirm(State(s): State<AppState>, _a: Admin, Path(key): Path<String>, body: Option<Json<ConfirmBody>>) -> ApiResult {
    let c = resolve(&s, &key).await?;
    let j: Option<JourneyRow> = sqlx::query_as("select * from journeys where customer_id = $1 and status = 'transfer' order by created_at desc limit 1").bind(c.id).fetch_optional(&s.pool).await.map_err(internal)?;
    let Some(j) = j else { return Err(err(StatusCode::CONFLICT, "customer is not waiting at a transfer")) };
    let trip_id = body.and_then(|b| b.0.trip_id);
    let updated = crate::journeys::confirm(&s, &c, &j, trip_id.as_deref()).await?;
    let mut v = crate::journeys::current_payload(&s, &updated, false).await.map_err(internal)?;
    v["customer"] = json!(c.nickname);
    Ok(Json(v))
}

// ---------------------------------------------------------------------------
// NGOs: managed data. The fixture seeds an empty table once; from then on this API owns it.
// ---------------------------------------------------------------------------

#[derive(Deserialize, Default)]
pub struct NgoUpsert {
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub tagline: Option<String>,
    #[serde(default)]
    pub story: Option<Vec<String>>,
    #[serde(default)]
    pub account_holder: Option<String>,
    #[serde(default)]
    pub iban: Option<String>,
    #[serde(default)]
    pub donation_url: Option<String>,
    #[serde(default)]
    pub active: Option<bool>,
    #[serde(default)]
    pub consent_date: Option<chrono::NaiveDate>,
    #[serde(default)]
    pub last_report: Option<chrono::NaiveDate>,
    /// What this Verein had received before Verspätomat existed, in cents. It is added to the sums
    /// this system can actually account for, and it is the one figure on the Wir screen that does
    /// not come from our own rows — so it is entered by a person, deliberately, and never guessed.
    #[serde(default)]
    pub seed_confirmed_cents: Option<i64>,
    #[serde(default)]
    pub seed_submitted_cents: Option<i64>,
    /// docs/27 §5: the NGO's mark as a data URI. Explicit null removes it, which is why this is
    /// a nested Option — absent and null are different instructions.
    #[serde(default, deserialize_with = "crate::admin::double_option")]
    pub logo: Option<Option<String>>,
}

/// Distinguishes "field absent" from "field set to null" for a patch-style body.
///
/// serde reads both into a plain `Option<T>` as `None`, which would make "remove this" and "this
/// body does not mention it" the same request — the very rule the partial-update test pins. The
/// outer `Option` is presence, the inner one is the value.
pub fn double_option<'de, D, T>(d: D) -> Result<Option<Option<T>>, D::Error>
where
    D: serde::Deserializer<'de>,
    T: serde::Deserialize<'de>,
{
    serde::Deserialize::deserialize(d).map(Some)
}

/// IBAN normalised to groups of four, or an error. Checks length per country prefix loosely and the mod-97 checksum.
pub fn normalise_iban(raw: &str) -> Result<String, String> {
    let compact: String = raw.chars().filter(|c| !c.is_whitespace()).map(|c| c.to_ascii_uppercase()).collect();
    if compact.len() < 15 || compact.len() > 34 || !compact.chars().all(|c| c.is_ascii_alphanumeric()) {
        return Err("IBAN length or characters".into());
    }
    if compact.starts_with("DE") && compact.len() != 22 {
        return Err("a German IBAN has 22 characters".into());
    }
    let rearranged = format!("{}{}", &compact[4..], &compact[..4]);
    let mut rem: u32 = 0;
    for c in rearranged.chars() {
        let v = c.to_digit(36).ok_or("IBAN characters")?;
        rem = if v >= 10 { (rem * 100 + v) % 97 } else { (rem * 10 + v) % 97 };
    }
    if rem != 1 {
        return Err("IBAN checksum".into());
    }
    Ok(compact.as_bytes().chunks(4).map(|c| std::str::from_utf8(c).unwrap_or("")).collect::<Vec<_>>().join(" "))
}

async fn ngo_json(pool: &sqlx::PgPool, id: &str) -> Result<Value, (StatusCode, Json<Value>)> {
    let row: Option<(String, String, String, Value, String, String, String, Option<chrono::NaiveDate>, bool, Option<chrono::NaiveDate>, i64, i64, i64, i64, i64)> = sqlx::query_as(
        "select n.id, n.name, n.tagline, n.story, n.account_holder, n.iban, n.donation_url, n.last_report, n.active, n.consent_date,
                n.seed_confirmed_cents, n.seed_submitted_cents,
                coalesce((select sum(coalesce(i.confirmed_cents, i.amount_cents)) from incidents i where i.ngo_id = n.id and i.status = 'bestaetigt'), 0)::bigint,
                coalesce((select sum(amount_cents) from incidents i where i.ngo_id = n.id and i.status = 'eingereicht'), 0)::bigint,
                (select count(*) from customers c where c.ngo_id = n.id)::bigint
         from ngos n where n.id = $1",
    )
    .bind(id)
    .fetch_optional(pool)
    .await
    .map_err(internal)?;
    let Some((id, name, tagline, story, holder, iban, url, last_report, active, consent, sc, ss, c, sub, customers)) = row else {
        return Err(err(StatusCode::NOT_FOUND, "no such NGO"));
    };
    Ok(json!({
        "id": id, "name": name, "tagline": tagline, "story": story, "account_holder": holder, "iban": iban, "donation_url": url,
        "last_report": last_report, "active": active, "consent_date": consent,
        "confirmed_total_cents": sc + c, "submitted_total_cents": ss + sub, "customers": customers,
    }))
}

/// `GET /admin/ngos`: every NGO, inactive ones included, with totals and how many customers chose it.
pub async fn ngos_list(State(s): State<AppState>, _a: Admin) -> ApiResult {
    let ids: Vec<String> = sqlx::query_scalar("select id from ngos order by active desc, name").fetch_all(&s.pool).await.map_err(internal)?;
    let mut out = Vec::with_capacity(ids.len());
    for id in ids {
        out.push(ngo_json(&s.pool, &id).await?);
    }
    Ok(Json(json!(out)))
}

/// `PUT /admin/ngos/{id}`: create or update. A new NGO needs name, account_holder and iban; updates take any subset.
pub async fn ngo_upsert(State(s): State<AppState>, _a: Admin, Path(id): Path<String>, Json(b): Json<NgoUpsert>) -> ApiResult {
    let id = id.trim().to_lowercase();
    if id.is_empty() || !id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_') {
        return Err(err(StatusCode::BAD_REQUEST, "id: letters, digits, - and _"));
    }
    let iban = match &b.iban {
        Some(raw) => Some(normalise_iban(raw).map_err(|e| err(StatusCode::BAD_REQUEST, &e))?),
        None => None,
    };
    let exists: bool = sqlx::query_scalar("select exists(select 1 from ngos where id = $1)").bind(&id).fetch_one(&s.pool).await.map_err(internal)?;
    let story = b.story.as_ref().map(|v| serde_json::to_value(v).unwrap_or(json!([])));
    if exists {
        sqlx::query(
            "update ngos set name = coalesce($2, name), tagline = coalesce($3, tagline), story = coalesce($4, story),
                account_holder = coalesce($5, account_holder), iban = coalesce($6, iban), donation_url = coalesce($7, donation_url),
                active = coalesce($8, active), consent_date = coalesce($9, consent_date), last_report = coalesce($10, last_report),
                logo = case when $11 then $12 else logo end,
                seed_confirmed_cents = coalesce($13, seed_confirmed_cents),
                seed_submitted_cents = coalesce($14, seed_submitted_cents)
             where id = $1",
        )
        .bind(&id).bind(&b.name).bind(&b.tagline).bind(&story).bind(&b.account_holder).bind(&iban).bind(&b.donation_url)
        .bind(b.active).bind(b.consent_date).bind(b.last_report)
        .bind(b.logo.is_some()).bind(b.logo.clone().flatten())
        .bind(b.seed_confirmed_cents).bind(b.seed_submitted_cents)
        .execute(&s.pool).await.map_err(internal)?;
        crate::rules::audit(&s.pool, "ngo", Uuid::nil(), None, &id, "updated via admin").await.map_err(internal)?;
    } else {
        let (Some(name), Some(holder), Some(iban)) = (&b.name, &b.account_holder, &iban) else {
            return Err(err(StatusCode::BAD_REQUEST, "a new NGO needs name, account_holder and iban"));
        };
        sqlx::query(
            "insert into ngos (id, name, tagline, story, account_holder, iban, donation_url, last_report, active, consent_date, logo)
             values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
        )
        .bind(&id).bind(name).bind(b.tagline.clone().unwrap_or_default()).bind(story.unwrap_or(json!([]))).bind(holder).bind(iban)
        .bind(b.donation_url.clone().unwrap_or_default()).bind(b.last_report).bind(b.active.unwrap_or(true)).bind(b.consent_date)
        .bind(b.logo.clone().flatten())
        .execute(&s.pool).await.map_err(internal)?;
        crate::rules::audit(&s.pool, "ngo", Uuid::nil(), None, &id, "created via admin").await.map_err(internal)?;
    }
    Ok(Json(ngo_json(&s.pool, &id).await?))
}

/// `DELETE /admin/ngos/{id}`: deletes an NGO nobody references; otherwise deactivates it. The last active NGO stays.
pub async fn ngo_remove(State(s): State<AppState>, _a: Admin, Path(id): Path<String>) -> ApiResult {
    let active_others: i64 = sqlx::query_scalar("select count(*) from ngos where active and id <> $1").bind(&id).fetch_one(&s.pool).await.map_err(internal)?;
    if active_others == 0 {
        return Err(err(StatusCode::CONFLICT, "the last active NGO cannot be removed; add another first"));
    }
    let referenced: bool = sqlx::query_scalar(
        "select exists(select 1 from incidents where ngo_id = $1) or exists(select 1 from customers where ngo_id = $1)",
    )
    .bind(&id)
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    if referenced {
        let n = sqlx::query("update ngos set active = false where id = $1").bind(&id).execute(&s.pool).await.map_err(internal)?.rows_affected();
        if n == 0 {
            return Err(err(StatusCode::NOT_FOUND, "no such NGO"));
        }
        crate::rules::audit(&s.pool, "ngo", Uuid::nil(), Some("active"), &id, "deactivated via admin").await.map_err(internal)?;
        return Ok(Json(json!({ "id": id, "deactivated": true, "deleted": false })));
    }
    let n = sqlx::query("delete from ngos where id = $1").bind(&id).execute(&s.pool).await.map_err(internal)?.rows_affected();
    if n == 0 {
        return Err(err(StatusCode::NOT_FOUND, "no such NGO"));
    }
    crate::rules::audit(&s.pool, "ngo", Uuid::nil(), None, &id, "deleted via admin").await.map_err(internal)?;
    Ok(Json(json!({ "id": id, "deactivated": false, "deleted": true })))
}

#[cfg(test)]
mod ngo_tests {
    use super::normalise_iban;

    #[test]
    fn iban() {
        assert_eq!(normalise_iban("DE89 3704 0044 0532 0130 00").unwrap(), "DE89 3704 0044 0532 0130 00");
        assert_eq!(normalise_iban("de89370400440532013000").unwrap(), "DE89 3704 0044 0532 0130 00");
        assert!(normalise_iban("DE12 3456 7890 0000 4711 00").is_err()); // the fixture placeholder
        assert!(normalise_iban("DE89 3704 0044 0532 0130").is_err());
    }
}

// ---------------------------------------------------------------------------
// Mail test: one real message through the relay, from the customer's relay address.
// A reply to it exercises the inbound path (Postmark webhook → mails table → forward).
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct MailTestBody {
    pub to: String,
    /// Claim id or id prefix: send from that claim's `antrag-…` address instead of the customer's.
    #[serde(default)]
    pub claim: Option<String>,
}

/// `POST /admin/customers/{key}/mail-test {to}`: assigns the relay address if the customer has none yet,
/// sends a test mail from it, records it as an outbound mail without a claim.
pub async fn mail_test(State(s): State<AppState>, _a: Admin, Path(key): Path<String>, Json(b): Json<MailTestBody>) -> ApiResult {
    let c = resolve(&s, &key).await?;
    let to = b.to.trim().to_string();
    if !to.contains('@') {
        return Err(err(StatusCode::BAD_REQUEST, "to must be an e-mail address"));
    }
    // Only an address a route already points at. This command used to take any address at all and
    // send to it, which made it the third way a real railway could be reached by accident.
    let known: bool = sqlx::query_scalar("select exists(select 1 from mail_routes where lower(to_address) = lower($1))")
        .bind(&to)
        .fetch_one(&s.pool)
        .await
        .map_err(internal)?;
    if !known {
        return Err(err(
            StatusCode::PRECONDITION_FAILED,
            &format!("{to} is not the target of any mail route; add it with `stellwerk route set` first"),
        ));
    }
    let claim: Option<ClaimRow> = match b.claim.as_deref().map(str::trim).filter(|x| !x.is_empty()) {
        Some(key) => {
            let cl: Option<ClaimRow> = sqlx::query_as("select * from claims where customer_id = $1 and (id::text = $2 or id::text like $2 || '%') order by created_at desc limit 1")
                .bind(c.id).bind(key.to_lowercase()).fetch_optional(&s.pool).await.map_err(internal)?;
            Some(cl.ok_or_else(|| err(StatusCode::NOT_FOUND, "no such claim for this customer"))?)
        }
        None => None,
    };
    let relay = match &claim {
        Some(cl) => handlers::ensure_claim_address(&s.pool, cl).await.map_err(internal)?,
        None => match c.relay_address.clone() {
            Some(r) => r,
            None => {
                let r = handlers::relay_address_for(c.id);
                sqlx::query("update customers set relay_address = $2 where id = $1").bind(c.id).bind(&r).execute(&s.pool).await.map_err(internal)?;
                r
            }
        },
    };
    let message_id = handlers::new_message_id();
    let subject = "Verspätomat: Testmail";
    let body = format!(
        "Hallo,\n\ndas ist eine Testmail des Verspätomat-Relays, gesendet von {relay}.\n\nWenn du auf diese Mail antwortest, landet die Antwort bei genau dieser Adresse und wird als eingehende Post verarbeitet. Das prüft den Rückweg.\n\nVerspätomat\n"
    );
    let result = crate::mail::send(crate::mail::OutgoingMail {
        from: &relay,
        to: &to,
        bcc: None,
        subject,
        body: &body,
        message_id: &message_id,
        in_reply_to: None,
        attachments: vec![],
    })
    .await
    .map_err(|e| err(StatusCode::BAD_GATEWAY, &format!("mail: {e:#}")))?;
    let dry_run = matches!(result, crate::mail::SendResult::DryRun);
    sqlx::query(
        "insert into mails (id, customer_id, claim_id, direction, message_id, in_reply_to, from_addr, to_addr, bcc_addr, subject, body, dry_run)
         values ($1,$2,$3,'out',$4,null,$5,$6,null,$7,$8,$9)",
    )
    .bind(Uuid::new_v4()).bind(c.id).bind(claim.as_ref().map(|cl| cl.id)).bind(&message_id).bind(&relay).bind(&to).bind(subject).bind(&body).bind(dry_run)
    .execute(&s.pool).await.map_err(internal)?;
    Ok(Json(json!({ "from": relay, "to": to, "message_id": message_id, "dry_run": dry_run, "claim_id": claim.map(|cl| cl.id) })))
}

// ---------------------------------------------------------------------------
// Mail routes
// ---------------------------------------------------------------------------

/// Every route, so the question "where does a claim for this desk actually go" has an answer that
/// can be read rather than reasoned about.
pub async fn routes(State(s): State<AppState>, _a: Admin) -> ApiResult {
    // `known` answers the question a route list must answer: will this ever fire? A route is keyed
    // on the desk string frozen onto a claim, which comes from the operator directory — so a desk
    // nobody is filed under is a route that silently never matches, and the claim is refused for
    // "no mail route" while a route sits right there looking correct.
    let rows: Vec<(String, String, String, Option<String>, Option<String>, bool, Option<String>)> = sqlx::query_as(
        "select r.desk, r.to_address, r.label, r.note, r.postal_address,
                exists(select 1 from operators o where o.desk = r.desk) or r.desk = '*' as known, r.reply_from
         from mail_routes r order by r.desk",
    )
    .fetch_all(&s.pool)
    .await
    .map_err(internal)?;
    Ok(Json(json!(rows
        .into_iter()
        .map(|(desk, to_address, label, note, postal_address, known, reply_from)| {
            let answer_domains = crate::reply::answer_domains(&to_address, reply_from.as_deref());
            let free_mail: Vec<&String> = answer_domains.iter().filter(|d| crate::reply::is_free_mail(d)).collect();
            json!({
                "desk": desk, "to_address": to_address, "label": label, "note": note,
                "postal_address": postal_address, "matches_a_desk": known,
                "answer_domains": answer_domains, "free_mail_answer_domains": free_mail,
            })
        })
        .collect::<Vec<_>>())))
}

#[derive(Deserialize)]
pub struct RouteBody {
    pub desk: String,
    pub to_address: Option<String>,
    pub label: Option<String>,
    pub postal_address: Option<String>,
    pub note: Option<String>,
}

/// Create or change one route. This is the only way a destination comes to exist.
pub async fn route_set(State(s): State<AppState>, _a: Admin, Json(b): Json<RouteBody>) -> ApiResult {
    let desk = b.desk.trim().to_string();
    if desk.is_empty() {
        return Err(err(StatusCode::BAD_REQUEST, "desk is required"));
    }
    let Some(to) = b.to_address.as_deref().map(str::trim).filter(|t| t.contains('@') && !t.starts_with('@') && !t.ends_with('@')) else {
        return Err(err(StatusCode::BAD_REQUEST, "to_address must be an e-mail address"));
    };
    let label = b.label.unwrap_or_else(|| "Fahrgastrechte-Stelle".into());
    let row: (String, String, String, Option<String>) = sqlx::query_as(
        "insert into mail_routes (desk, to_address, label, note, postal_address) values ($1,$2,$3,$4,$5)
         on conflict (desk) do update set to_address = excluded.to_address, label = excluded.label,
           note = excluded.note,
           postal_address = coalesce(excluded.postal_address, mail_routes.postal_address), updated_at = now()
         returning desk, to_address, label, reply_from",
    )
    .bind(&desk)
    .bind(to)
    .bind(&label)
    .bind(&b.note)
    .bind(&b.postal_address)
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    // An address that decides where a stranger's legal claim lands belongs in the audit trail.
    // Who may answer for the desk decides who can confirm money, so it is in the line too.
    crate::rules::audit(&s.pool, "route", Uuid::nil(), None, "route-set", &format!("{} → {} ({})", row.0, row.1, row.2))
        .await
        .map_err(internal)?;
    Ok(Json(json!({ "desk": row.0, "to_address": row.1, "label": row.2, "answer_domains": crate::reply::answer_domains(&row.1, row.3.as_deref()) })))
}

#[derive(Deserialize)]
pub struct AnswerDomainsBody {
    pub desk: String,
    #[serde(default)]
    pub add: Vec<String>,
    #[serde(default)]
    pub remove: Vec<String>,
    /// Drop every extra domain; the route's own destination domain stays.
    #[serde(default)]
    pub clear: bool,
    /// Allow a free-mail domain anyway.
    #[serde(default)]
    pub force: bool,
}

/// `POST /admin/routes/answers`: the domains a desk's answers may come from, besides the domain its
/// mail goes to.
///
/// A desk is written to at one address and answers from another — the Servicecenter's inbox at
/// deutschebahn.com, its replies from deutschebahn.de — and an answer from a domain not on this list
/// is recorded but cannot accept, refuse or ask (`handlers::guard_sender`). Free-mail providers are
/// refused without `force`: every user of gmail.com can DKIM-sign a "wir überweisen".
pub async fn route_answers(State(s): State<AppState>, _a: Admin, Json(b): Json<AnswerDomainsBody>) -> ApiResult {
    let row: Option<(String, Option<String>)> = sqlx::query_as("select to_address, reply_from from mail_routes where desk = $1").bind(b.desk.trim()).fetch_optional(&s.pool).await.map_err(internal)?;
    let Some((to_address, current)) = row else { return Err(err(StatusCode::NOT_FOUND, "no route for this desk: set one first with `stellwerk route set`")) };
    let normalise = |list: &[String]| -> Result<Vec<String>, (StatusCode, Json<Value>)> {
        list.iter().flat_map(|x| x.split(',')).filter(|x| !x.trim().is_empty()).map(|x| crate::reply::normalise_domain(x).map_err(|e| err(StatusCode::BAD_REQUEST, &e))).collect()
    };
    let add = normalise(&b.add)?;
    let remove = normalise(&b.remove)?;
    // Only looking: nothing written, nothing in the audit trail.
    if add.is_empty() && remove.is_empty() && !b.clear {
        let extra: Vec<String> = current.as_deref().unwrap_or("").split(',').filter_map(|d| crate::reply::normalise_domain(d).ok()).collect();
        return Ok(Json(json!({ "desk": b.desk.trim(), "to_address": to_address, "answer_domains": crate::reply::answer_domains(&to_address, current.as_deref()), "extra": extra })));
    }
    if let Some(free) = add.iter().find(|d| crate::reply::is_free_mail(d)) {
        if !b.force {
            return Err(err(StatusCode::BAD_REQUEST, &format!("{free} is a free-mail provider: anybody with an account there could confirm money. Add it with force only for a test inbox")));
        }
    }
    let mut extra: Vec<String> = if b.clear { vec![] } else { current.as_deref().unwrap_or("").split(',').filter_map(|d| crate::reply::normalise_domain(d).ok()).collect() };
    extra.retain(|d| !remove.contains(d));
    for d in add {
        if !extra.contains(&d) {
            extra.push(d);
        }
    }
    let stored = if extra.is_empty() { None } else { Some(extra.join(",")) };
    sqlx::query("update mail_routes set reply_from = $2, updated_at = now() where desk = $1").bind(b.desk.trim()).bind(&stored).execute(&s.pool).await.map_err(internal)?;
    let effective = crate::reply::answer_domains(&to_address, stored.as_deref());
    // Who may answer for a desk decides who can confirm money: that belongs in the audit trail.
    crate::rules::audit(&s.pool, "route", Uuid::nil(), None, "route-answers", &format!("{}: answers from {}", b.desk.trim(), effective.join(", "))).await.map_err(internal)?;
    Ok(Json(json!({ "desk": b.desk.trim(), "to_address": to_address, "answer_domains": effective, "extra": extra })))
}

#[derive(Deserialize)]
pub struct RouteRemoveBody {
    pub desk: String,
}

/// Remove a route. Nothing can be sent to that desk afterwards, which is the point.
pub async fn route_remove(State(s): State<AppState>, _a: Admin, Json(b): Json<RouteRemoveBody>) -> ApiResult {
    let n = sqlx::query("delete from mail_routes where desk = $1").bind(b.desk.trim()).execute(&s.pool).await.map_err(internal)?.rows_affected();
    if n == 0 {
        return Err(err(StatusCode::NOT_FOUND, "no such route"));
    }
    crate::rules::audit(&s.pool, "route", Uuid::nil(), None, "route-removed", b.desk.trim()).await.map_err(internal)?;
    Ok(Json(json!({ "removed": b.desk.trim() })))
}

/// `GET /admin/desks` — every desk a claim can be filed under, so a route can be pointed at one
/// that exists rather than at a name somebody typed.
pub async fn desks(State(s): State<AppState>, _a: Admin) -> ApiResult {
    let rows: Vec<(String,)> = sqlx::query_as("select distinct desk from operators order by desk").fetch_all(&s.pool).await.map_err(internal)?;
    Ok(Json(json!(rows.into_iter().map(|(d,)| d).collect::<Vec<_>>())))
}

// ---------------------------------------------------------------------------
// Stations (issue #37)
// ---------------------------------------------------------------------------

#[derive(Deserialize, Default)]
pub struct ImportQ {
    /// Skip the guards. Needed for the very first import, which would otherwise be refused for
    /// retiring nothing against nothing, and for the day an upstream change really does move a
    /// thousand stations and a human has decided that is fine.
    #[serde(default)]
    pub force: bool,
    /// Say what would happen and write none of it.
    #[serde(default)]
    pub dry_run: bool,
}

/// `POST /admin/stations/import` — take a candidate set built on a laptop and make it the table.
///
/// The heavy half of this job (a 338 MB download and a pass over 2.8 GB of stop times) happens in
/// `stellwerk`, the same way the website is built on a laptop and not on the server. What arrives
/// here is a list of stations with no ids on it, and the only thing that cannot be done anywhere
/// else is deciding which of them are stations we have already named — because those ids are on
/// phones, in ride rows and in muted-station lists, and they have to keep meaning what they meant.
pub async fn stations_import(
    State(s): State<AppState>,
    _a: Admin,
    Query(q): Query<ImportQ>,
    Json(set): Json<crate::stations::CandidateSet>,
) -> ApiResult {
    let report = crate::stations::commit(&s.pool, &set, q.force, q.dry_run).await.map_err(internal)?;
    if report.committed {
        let n = s.reload_stations().await.map_err(internal)?;
        tracing::info!(stations = n, added = report.added, retired = report.retired, "stations imported");
    }
    Ok(Json(json!(report)))
}

/// `GET /admin/stations` — what is in the table and how it got there.
pub async fn stations_status(State(s): State<AppState>, _a: Admin) -> ApiResult {
    let ix = s.stations();
    let runs: Vec<(i32, Option<String>, i32, i32, i32, i32, i32, bool, Option<String>, chrono::DateTime<chrono::Utc>)> = sqlx::query_as(
        "select id, feed_version, added, retired, moved, renamed, total, committed, note, started_at \
         from station_imports order by id desc limit 5",
    )
    .fetch_all(&s.pool)
    .await
    .map_err(internal)?;
    let retired: (i64,) = sqlx::query_as("select count(*) from stations where retired_at is not null").fetch_one(&s.pool).await.map_err(internal)?;
    let latest: Option<(i32, Option<String>)> =
        sqlx::query_as("select id, feed_version from station_imports where committed order by id desc limit 1")
            .fetch_optional(&s.pool)
            .await
            .map_err(internal)?;
    Ok(Json(json!({
        "live": ix.len(),
        "retired": retired.0,
        // Which extract the table would render as, and the Fahrplanstand behind it (issue #39), so
        // `stellwerk stations extract` can write latest.json without a second source of truth.
        // `feed_version` is an opaque string straight from the feed — today it is
        // "2026-09-12T15:06:17". Nobody parses it. Both fields are additive; nothing is renamed.
        "version": latest.as_ref().map(|(id, _)| *id).unwrap_or(0),
        "feed_version": latest.as_ref().and_then(|(_, f)| f.clone()),
        "imports": runs.iter().map(|r| json!({
            "id": r.0, "feed_version": r.1, "added": r.2, "retired": r.3, "moved": r.4,
            "renamed": r.5, "total": r.6, "committed": r.7, "note": r.8, "started_at": r.9,
        })).collect::<Vec<_>>(),
    })))
}

/// `GET /admin/stations/extract` — the table as the bytes a phone will read (issue #39).
///
/// Rendered from the same in-memory index `/v1/stations/nearby` answers from, so the file and the
/// server cannot disagree about a station: one `Index`, two ways of reading it.
///
/// The bytes are not stored here and are not served to passengers from here. `stellwerk stations
/// extract` writes them into `site/static/stations/` and Caddy serves them from the website vhost,
/// which carries no bearer token and gets a `log_skip`. This route is behind the admin token for
/// the same reason `/admin/stations/import` is: it hands over the whole table in one request and
/// it is a build step, not something a passenger's phone ever calls.
pub async fn stations_extract(State(s): State<AppState>, _a: Admin) -> Result<Response, (StatusCode, Json<Value>)> {
    let ix = s.stations();
    if ix.is_empty() {
        return Err(err(StatusCode::CONFLICT, "no stations in the table: nothing to extract"));
    }
    // The version and the timestamp are the import's, not `now()`. The extract has to be a
    // function of the table: rendering the same table twice must give the same bytes, or every
    // render is a commit in site/dist and a 280 KB diff nobody can read.
    let run: Option<(i32, chrono::DateTime<chrono::Utc>)> = sqlx::query_as(
        "select id, coalesce(finished_at, started_at) from station_imports where committed order by id desc limit 1",
    )
    .fetch_optional(&s.pool)
    .await
    .map_err(internal)?;
    // No committed import means no version, and a version-0 extract must never be published. The
    // CLI refuses too; the two have to agree about what a valid extract is.
    let (version, generated) = match run {
        Some((id, at)) => (id as u32, at),
        None => {
            return Err(err(
                StatusCode::CONFLICT,
                "no committed import in station_imports: run `stellwerk stations import` first",
            ))
        }
    };
    let bytes = crate::stations::extract::render(&ix, crate::stations::extract::Meta { version, generated }).map_err(internal)?;
    tracing::info!(stations = ix.len(), version, bytes = bytes.len(), "stations extract rendered");
    // Raw bytes, not base64: the only client writes the body straight to a file. Errors stay JSON,
    // so a failure reads like every other stellwerk command's.
    Ok(([(axum::http::header::CONTENT_TYPE, "application/octet-stream")], bytes).into_response())
}
