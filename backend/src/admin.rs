//! Stellwerk admin API. Guarded by `x-admin-token` = `ADMIN_TOKEN` (default "stellwerk" in dev).
//! Dev and staging only: it changes the world the customers see.

use axum::{
    extract::{FromRequestParts, Path, Query, State},
    http::{header, request::Parts, HeaderMap, StatusCode},
    Json,
};
use chrono::{Duration, NaiveDate};
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
        let (open, incidents): (i64, i64) = sqlx::query_as("select count(*) filter (where status in ('gesammelt','bereit'))::bigint, count(*)::bigint from incidents where customer_id = $1")
            .bind(c.id)
            .fetch_one(&s.pool)
            .await
            .map_err(internal)?;
        out.push(json!({
            "id": c.id, "nickname": c.nickname, "relay_address": c.relay_address, "created_at": c.created_at, "last_seen_at": last_seen,
            "riding": ride.is_some(),
            "ride": ride.map(|r| json!({ "id": r.id, "line": r.line, "exit_station_name": r.exit_station_name, "live_delay_min": r.live_delay_min, "passed_stops": r.passed_stops, "checked_in_at": r.checked_in_at, "last_polled_at": r.last_polled_at })),
            "open_incidents": open, "incidents": incidents, "sim_location": sim_location,
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
    s.events.publish(c.id, "ride", json!({ "ride_id": r.id, "status": "riding", "live_delay_min": r.live_delay_min }));
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
    s.events.publish(c.id, "ride", json!({ "ride_id": r.id, "status": r.status, "cancelled": true }));
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
    s.events.publish(c.id, "ride", json!({ "ride_id": r2.id, "status": "arrived", "final_delay_min": r2.final_delay_min, "incident": fin.incident.as_ref().map(|i| i.id) }));
    Ok(Json(json!({ "ride": r2, "incident": fin.incident, "new_badge": fin.new_badge, "override": o })))
}

pub async fn poll(State(s): State<AppState>, _a: Admin) -> ApiResult {
    let (tx, mut rx) = tokio::sync::broadcast::channel(64);
    crate::train::follower::poll_once(&s.pool, &s.train, &tx).await.map_err(internal)?;
    let mut finalised = Vec::new();
    while let Ok(ev) = rx.try_recv() {
        let fin = handlers::on_ride_finalised(&s.pool, ev.ride_id).await.map_err(internal)?;
        s.events.publish(ev.customer_id, "ride", json!({ "ride_id": ev.ride_id, "status": "arrived", "final_delay_min": ev.final_delay_min, "incident": fin.incident.as_ref().map(|i| i.id) }));
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
            attachments: vec![],
        },
    )
    .await?;
    s.events.publish(c.id, "mail", json!({ "claim_id": claim.id, "outcome": b.outcome }));
    s.events.publish(c.id, "incident", json!({ "claim_id": claim.id }));
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
    s.events.publish_all("clock", json!({ "now": clock::now(), "offset_secs": secs }));
    Ok(Json(json!({ "now": clock::now(), "offset_secs": secs })))
}

pub async fn reset(State(s): State<AppState>, _a: Admin, Path(key): Path<String>) -> ApiResult {
    let c = resolve(&s, &key).await?;
    let trips: Vec<String> = sqlx::query_scalar("select distinct trip_id from rides where customer_id = $1").bind(c.id).fetch_all(&s.pool).await.map_err(internal)?;
    for t in &trips {
        let _ = s.train.clear_override(&s.pool, t).await;
    }
    for table in ["mails", "claims", "incidents", "uploads", "rides", "badge_awards", "sim_customer_location"] {
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
            let hits = s.train.search_stops(&name).await.map_err(internal)?;
            let hit = hits.into_iter().next().ok_or_else(|| err(StatusCode::NOT_FOUND, "no station with that name"))?;
            (hit.lat, hit.lon, hit.name)
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

/// `POST /admin/scan`: one deadline-scanner pass now (the loop runs hourly).
pub async fn scan(State(s): State<AppState>, _a: Admin) -> ApiResult {
    Ok(Json(crate::scanner::run_once(&s).await.map_err(internal)?))
}

/// One transfer on the NGO's statement. `amount_cents` or a printed `amount` ("4,50", "4.50").
#[derive(Deserialize, Clone)]
pub struct Transfer {
    pub date: NaiveDate,
    #[serde(default)]
    pub amount_cents: Option<i64>,
    #[serde(default)]
    pub amount: Option<String>,
    #[serde(default)]
    pub reference: String,
    #[serde(default)]
    pub counterparty: String,
}

impl Transfer {
    fn cents(&self) -> Option<i64> {
        self.amount_cents.or_else(|| self.amount.as_deref().and_then(parse_report_amount))
    }
    fn json(&self, cents: Option<i64>) -> Value {
        json!({ "date": self.date, "amount_cents": cents, "reference": self.reference, "counterparty": self.counterparty })
    }
}

#[derive(Deserialize)]
pub struct ReportBody {
    #[serde(default, alias = "rows")]
    pub transfers: Vec<Transfer>,
}

fn parse_report_date(s: &str) -> Option<NaiveDate> {
    let s = s.trim();
    NaiveDate::parse_from_str(s, "%Y-%m-%d").or_else(|_| NaiveDate::parse_from_str(s, "%d.%m.%Y")).ok()
}

/// "4,50" / "4.50" / "1.234,56" / "4" → cents (euros, as bank statements print them).
pub fn parse_report_amount(s: &str) -> Option<i64> {
    let s = s.trim().replace(['€', ' '], "").replace("EUR", "");
    let (whole, frac) = match (s.rfind(','), s.rfind('.')) {
        (Some(c), Some(d)) if c > d => (s[..c].replace('.', ""), s[c + 1..].to_string()),
        (Some(_), Some(d)) => (s[..d].replace(',', ""), s[d + 1..].to_string()),
        (Some(c), None) => (s[..c].to_string(), s[c + 1..].to_string()),
        (None, Some(d)) => (s[..d].to_string(), s[d + 1..].to_string()),
        (None, None) => (s.clone(), String::new()),
    };
    let whole: i64 = if whole.is_empty() { 0 } else { whole.parse().ok()? };
    let frac: i64 = match frac.len() {
        0 => 0,
        1 => frac.parse::<i64>().ok()? * 10,
        2 => frac.parse().ok()?,
        _ => return None,
    };
    Some(whole * 100 + frac)
}

/// CSV `date,amount,reference,counterparty` (comma or semicolon separated; a header line and `#` lines are skipped).
/// Shared with the CLI, which converts the file to JSON before posting.
pub fn parse_report_csv(text: &str) -> Vec<Transfer> {
    text.lines()
        .filter_map(|line| {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                return None;
            }
            let sep = if line.matches(';').count() >= line.matches(',').count() { ';' } else { ',' };
            let mut f = line.splitn(4, sep).map(|x| x.trim().trim_matches('"'));
            let date = parse_report_date(f.next()?)?;
            let amount_cents = parse_report_amount(f.next()?)?;
            let reference = f.next().unwrap_or("").to_string();
            let counterparty = f.next().unwrap_or("").to_string();
            Some(Transfer { date, amount_cents: Some(amount_cents), amount: None, reference, counterparty })
        })
        .collect()
}

/// `POST /admin/ngos/{id}/report`: the NGO's monthly statement as JSON `{transfers:[{date, amount_cents|amount, reference, counterparty}]}`
/// (CSV text `date,amount,reference,counterparty` is accepted too). Each transfer is matched to a `sent` or `question`
/// claim of that NGO with exactly that amount, sent within the 60 days before the transfer, oldest unmatched first;
/// a claim whose claimant or id prefix appears in the reference or counterparty wins over an older one. A match sets the
/// claim `accepted` with the confirmed amount, its incidents `bestaetigt`, awards the badge and notifies the customer.
pub async fn ngo_report(State(s): State<AppState>, _a: Admin, Path(ngo_id): Path<String>, headers: HeaderMap, body: String) -> ApiResult {
    let exists: bool = sqlx::query_scalar("select exists(select 1 from ngos where id = $1)").bind(&ngo_id).fetch_one(&s.pool).await.map_err(internal)?;
    if !exists {
        return Err(err(StatusCode::NOT_FOUND, "no such ngo"));
    }
    let ct = headers.get(header::CONTENT_TYPE).and_then(|v| v.to_str().ok()).unwrap_or("").to_ascii_lowercase();
    let transfers: Vec<Transfer> = if ct.starts_with("application/json") || (ct.is_empty() && body.trim_start().starts_with('{')) {
        serde_json::from_str::<ReportBody>(&body).map_err(|e| err(StatusCode::BAD_REQUEST, &format!("json: {e}")))?.transfers
    } else {
        parse_report_csv(&body)
    };
    if transfers.is_empty() {
        return Err(err(StatusCode::BAD_REQUEST, "no transfers: send {transfers:[{date, amount_cents, reference, counterparty}]} as JSON or date,amount,reference,counterparty lines as CSV"));
    }
    let mut used: Vec<Uuid> = Vec::new();
    let mut matched: Vec<Value> = Vec::new();
    let mut unmatched: Vec<Value> = Vec::new();
    for t in &transfers {
        let Some(cents) = t.cents() else {
            unmatched.push(t.json(None));
            continue;
        };
        let from = t.date - Duration::days(60);
        let candidates: Vec<ClaimRow> = sqlx::query_as(
            "select c.* from claims c where c.ngo_id = $1 and c.status in ('sent','question') and c.amount_claimed_cents = $2
               and c.sent_at is not null and c.sent_at::date between $3 and $4 order by c.sent_at",
        )
        .bind(&ngo_id)
        .bind(cents)
        .bind(from)
        .bind(t.date)
        .fetch_all(&s.pool)
        .await
        .map_err(internal)?;
        let text = format!("{} {}", t.reference, t.counterparty).to_lowercase();
        let mut hit: Option<(ClaimRow, CustomerRow)> = None;
        for claim in candidates.into_iter().filter(|c| !used.contains(&c.id)) {
            let cust: CustomerRow = sqlx::query_as("select * from customers where id = $1").bind(claim.customer_id).fetch_one(&s.pool).await.map_err(internal)?;
            let by_name = cust.full_name.as_deref().map(|n| !n.trim().is_empty() && text.contains(&n.trim().to_lowercase())).unwrap_or(false);
            let by_id = text.contains(&claim.id.simple().to_string()[..8]);
            if by_name || by_id {
                hit = Some((claim, cust));
                break;
            }
            if hit.is_none() {
                hit = Some((claim, cust));
            }
        }
        let Some((claim, cust)) = hit else {
            unmatched.push(t.json(Some(cents)));
            continue;
        };
        used.push(claim.id);
        sqlx::query("update claims set status = 'accepted', amount_confirmed_cents = $2, closed_at = $3 where id = $1").bind(claim.id).bind(cents).bind(clock::now()).execute(&s.pool).await.map_err(internal)?;
        let incidents: Vec<(Uuid, IncidentStatus)> = sqlx::query_as("update incidents set status = 'bestaetigt' where id in (select incident_id from claim_incidents where claim_id = $1) returning id, 'eingereicht'::incident_status").bind(claim.id).fetch_all(&s.pool).await.map_err(internal)?;
        for (id, from_status) in &incidents {
            crate::rules::audit(&s.pool, "incident", *id, Some(crate::rules::from_label(*from_status)), "bestaetigt", "ngo report").await.map_err(internal)?;
        }
        crate::rules::audit(&s.pool, "claim", claim.id, Some(&format!("{:?}", claim.status).to_lowercase()), "accepted", "ngo report").await.map_err(internal)?;
        let _ = sqlx::query("insert into badge_awards (customer_id, badge_id) values ($1, 'bestaetigt') on conflict do nothing").bind(cust.id).execute(&s.pool).await;
        crate::scanner::retain_closed_claim(&s.pool, claim.id).await.map_err(internal)?;
        s.events.publish(cust.id, "claim", json!({ "claim_id": claim.id, "status": "accepted", "amount_confirmed_cents": cents, "source": "ngo_report" }));
        s.events.publish(cust.id, "incident", json!({ "claim_id": claim.id, "status": "bestaetigt", "source": "ngo_report" }));
        matched.push(json!(claim.id));
    }
    let report_id = Uuid::new_v4();
    sqlx::query("insert into ngo_reports (id, ngo_id, rows, matched) values ($1, $2, $3, $4)").bind(report_id).bind(&ngo_id).bind(transfers.len() as i32).bind(matched.len() as i32).execute(&s.pool).await.map_err(internal)?;
    sqlx::query("update ngos set last_report = $2 where id = $1").bind(&ngo_id).bind(transfers.iter().map(|t| t.date).max()).execute(&s.pool).await.map_err(internal)?;
    Ok(Json(json!({ "report_id": report_id, "ngo_id": ngo_id, "rows": transfers.len(), "matched": matched, "unmatched": unmatched })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn report_csv() {
        let rows = parse_report_csv("date,amount,reference,counterparty\n2026-09-03,4.50,Erstattung Fahrgastrechte Anna Beispiel,DB Fernverkehr AG\n03.09.2026;19,95;\"Vorgang 1a2b3c4d\"\n# comment\n\n2026-09-04;1.234,56;x;y\n");
        assert_eq!(rows.len(), 3);
        assert_eq!(rows[0].amount_cents, Some(450));
        assert_eq!(rows[0].reference, "Erstattung Fahrgastrechte Anna Beispiel");
        assert_eq!(rows[0].counterparty, "DB Fernverkehr AG");
        assert_eq!(rows[1].date, NaiveDate::from_ymd_opt(2026, 9, 3).unwrap());
        assert_eq!(rows[1].amount_cents, Some(1995));
        assert_eq!(rows[1].reference, "Vorgang 1a2b3c4d");
        assert_eq!(rows[2].amount_cents, Some(123456));
        let j: ReportBody = serde_json::from_str(r#"{"transfers":[{"date":"2026-09-03","amount":"4,50","reference":"r","counterparty":"c"}]}"#).unwrap();
        assert_eq!(j.transfers[0].cents(), Some(450));
        assert_eq!(parse_report_amount("4"), Some(400));
        assert_eq!(parse_report_amount("4,5 €"), Some(450));
        assert_eq!(parse_report_amount("4,505"), None);
    }
}
