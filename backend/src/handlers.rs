//! HTTP handlers on Postgres. Thin: parse, call rules, write rows, answer.

use std::collections::BTreeMap;

use axum::{
    extract::{Multipart, Path, Query, State},
    http::{header, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use chrono::{DateTime, Duration, NaiveDate, Utc};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

use base64::Engine;

use crate::auth::{internal, sha256, Customer};
use crate::db::rows::*;
use crate::rules::{self, Cents};
use crate::train::{agency_to_operator, normalise_station_name, TripInfo};

fn row_category(c: crate::train::TrainCategory) -> TrainCategory {
    match c.as_str() {
        "s" => TrainCategory::S,
        "rb" => TrainCategory::Rb,
        "re" => TrainCategory::Re,
        "fern" => TrainCategory::Fern,
        _ => TrainCategory::Bus,
    }
}
use crate::AppState;

type ApiResult = Result<Json<Value>, (StatusCode, Json<Value>)>;

fn err(status: StatusCode, msg: &str) -> (StatusCode, Json<Value>) {
    (status, Json(json!({ "error": msg })))
}

fn today() -> NaiveDate {
    crate::clock::today()
}

pub async fn health(State(s): State<AppState>) -> Json<Value> {
    let db_ok = sqlx::query_scalar::<_, i32>("select 1").fetch_one(&s.pool).await.is_ok();
    Json(json!({ "ok": db_ok, "service": "verspaetomat-api", "db": db_ok }))
}

// ---------------------------------------------------------------------------
// Reference data
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct LatLon {
    pub lat: Option<f64>,
    pub lon: Option<f64>,
}

/// Nearby stations. The phone's position decides; a Stellwerk override per customer wins.
/// Without either there is nothing to answer: the app shows the search field instead.
pub async fn stations_nearby(State(s): State<AppState>, c: Customer, Query(q): Query<LatLon>) -> ApiResult {
    let sim: Option<(f64, f64, String)> = sqlx::query_as("select lat, lon, label from sim_customer_location where customer_id = $1")
        .bind(c.0.id)
        .fetch_optional(&s.pool)
        .await
        .map_err(internal)?;
    let (lat, lon, source, label) = match (sim, q.lat, q.lon) {
        (Some((lat, lon, label)), _, _) => (lat, lon, "stellwerk", Some(label)),
        (None, Some(lat), Some(lon)) => (lat, lon, "gps", None),
        _ => return Ok(Json(json!({ "stations": [], "source": "none", "label": null }))),
    };
    let stops = s.train.nearby_stops(lat, lon).await.map_err(internal)?;
    Ok(Json(json!({ "stations": stops, "source": source, "label": label, "lat": lat, "lon": lon })))
}

#[derive(Deserialize)]
pub struct SearchQ {
    pub q: String,
}

pub async fn stations_search(State(s): State<AppState>, _c: Customer, Query(q): Query<SearchQ>) -> ApiResult {
    let stops = s.train.search_stops(&q.q).await.map_err(internal)?;
    Ok(Json(json!(stops)))
}

pub async fn departures(State(s): State<AppState>, _c: Customer, Path(id): Path<String>) -> ApiResult {
    let deps = s.train.departures(&id, 150).await.map_err(internal)?;
    let ops: Vec<OperatorRow> = sqlx::query_as("select * from operators").fetch_all(&s.pool).await.map_err(internal)?;
    let out: Vec<Value> = deps
        .into_iter()
        .map(|d| {
            let operator = map_operator(&ops, &d.agency_name);
            let desk = ops.iter().find(|o| o.name == operator).map(|o| o.desk.clone()).unwrap_or_else(|| "Unbekannt".into());
            let mut v = json!(d);
            v["operator"] = json!(operator);
            v["desk"] = json!(desk);
            v
        })
        .collect();
    Ok(Json(json!(out)))
}

#[derive(Deserialize)]
pub struct TripQ {
    pub trip_id: String,
}

pub async fn trip(State(s): State<AppState>, _c: Customer, Query(q): Query<TripQ>) -> ApiResult {
    let t = s.train.trip(&q.trip_id).await.map_err(|e| err(StatusCode::NOT_FOUND, &format!("trip: {e}")))?;
    Ok(Json(json!(t)))
}

pub async fn operators(State(s): State<AppState>) -> ApiResult {
    let ops: Vec<OperatorRow> = sqlx::query_as("select * from operators order by name").fetch_all(&s.pool).await.map_err(internal)?;
    Ok(Json(json!(ops)))
}

pub async fn ngos(State(s): State<AppState>) -> ApiResult {
    Ok(Json(json!(ngo_totals(&s.pool).await.map_err(internal)?)))
}

async fn ngo_totals(pool: &PgPool) -> anyhow::Result<Vec<Value>> {
    let rows: Vec<(String, String, String, Value, String, String, String, Option<NaiveDate>, i64, i64, i64, i64)> = sqlx::query_as(
        "select n.id, n.name, n.tagline, n.story, n.account_holder, n.iban, n.donation_url, n.last_report,
                n.seed_confirmed_cents, n.seed_submitted_cents,
                coalesce((select sum(amount_cents) from incidents i where i.ngo_id = n.id and i.status = 'bestaetigt'), 0)::bigint,
                coalesce((select sum(amount_cents) from incidents i where i.ngo_id = n.id and i.status = 'eingereicht'), 0)::bigint
         from ngos n where n.active order by n.name",
    )
    .fetch_all(pool)
    .await?;
    Ok(rows
        .into_iter()
        .map(|(id, name, tagline, story, holder, iban, url, last_report, sc, ss, c, sub)| {
            json!({
                "id": id, "name": name, "tagline": tagline, "story": story, "account_holder": holder, "iban": iban,
                "donation_url": url, "last_report": last_report,
                "confirmed_total_cents": sc + c, "submitted_total_cents": ss + sub,
            })
        })
        .collect())
}

pub async fn badges(State(s): State<AppState>, c: Customer) -> ApiResult {
    let rows: Vec<(String, String, String, Option<DateTime<Utc>>)> = sqlx::query_as(
        "select b.id, b.name, b.rule, a.awarded_at from badges b left join badge_awards a on a.badge_id = b.id and a.customer_id = $1 order by b.id",
    )
    .bind(c.0.id)
    .fetch_all(&s.pool)
    .await
    .map_err(internal)?;
    Ok(Json(json!(rows
        .into_iter()
        .map(|(id, name, rule, at)| json!({ "id": id, "name": name, "rule": rule, "earned_on": at.map(|t| t.date_naive()) }))
        .collect::<Vec<_>>())))
}

// ---------------------------------------------------------------------------
// Customer
// ---------------------------------------------------------------------------

async fn customer_json(pool: &PgPool, c: &CustomerRow) -> anyhow::Result<Value> {
    let week_ago = crate::clock::now() - Duration::days(7);
    let (points_total, points_week): (i64, i64) = sqlx::query_as(
        // docs/22 §1: an abandoned leg keeps the patience it earned, so points count it too.
        // Money and bundles never do — those stay on 'arrived' (see rules.rs and the ledger).
        "select coalesce(sum(points),0)::bigint, coalesce(sum(points) filter (where finalised_at >= $2),0)::bigint from rides where customer_id = $1 and status in ('arrived','abandoned')",
    )
    .bind(c.id)
    .bind(week_ago)
    .fetch_one(pool)
    .await?;
    let (level, next, next_at) = level_for(points_total);
    Ok(json!({
        "id": c.id,
        "nickname": c.nickname,
        "relay_address": c.relay_address,
        "personal_data": c.full_name.as_ref().map(|n| json!({
            "name": n, "address": c.postal_address, "email": c.email, "ticket_number": c.ticket_number, "first_class": c.first_class
        })),
        "settings": {
            "ticket": c.ticket, "ngo_id": c.ngo_id, "location_mode": c.loc_mode, "notifications": c.notifications,
            "show_on_boards": c.show_on_boards, "keep_correspondence": c.keep_correspondence,
            "traewelling_linked": c.traewelling_linked, "onboarding_done": c.onboarding_done,
            "muted_stations": c.muted_stations,
            "nudge_enabled": c.nudge_enabled,
            "quiet_from": c.quiet_from.map(|t| t.format("%H:%M").to_string()),
            "quiet_to": c.quiet_to.map(|t| t.format("%H:%M").to_string()),
        },
        "points_total": points_total,
        "points_this_week": points_week,
        "level_name": level,
        "next_level_name": next,
        "next_level_at": next_at,
        "home_station": c.home_station_name,
        "home_station_id": c.home_station_id,
    }))
}

fn level_for(points: i64) -> (&'static str, &'static str, i64) {
    const LEVELS: [(&str, i64); 6] = [
        ("Frischer Fahrgast", 0),
        ("Bahnsteigkante", 60),
        ("Wartehäuschen", 240),
        ("Gleis 7", 600),
        ("Bahnhofsmission", 1500),
        ("Bahnsteig-Buddha", 4000),
    ];
    let idx = LEVELS.iter().rposition(|(_, at)| points >= *at).unwrap_or(0);
    let next = LEVELS.get(idx + 1).unwrap_or(&LEVELS[idx]);
    (LEVELS[idx].0, next.0, next.1)
}

pub async fn me(State(s): State<AppState>, c: Customer) -> ApiResult {
    Ok(Json(customer_json(&s.pool, &c.0).await.map_err(internal)?))
}

#[derive(Deserialize)]
pub struct MePatch {
    pub nickname: Option<String>,
    pub ticket: Option<TicketType>,
    pub ngo_id: Option<String>,
    pub location_mode: Option<LocationMode>,
    pub notifications: Option<bool>,
    pub show_on_boards: Option<bool>,
    pub keep_correspondence: Option<bool>,
    pub traewelling_linked: Option<bool>,
    pub onboarding_done: Option<bool>,
    pub home_station_id: Option<String>,
    pub home_station_name: Option<String>,
    /// Full replacement: [{id, name}]
    pub muted_stations: Option<Vec<MutedStation>>,
    pub nudge_enabled: Option<bool>,
    /// "HH:MM"; an empty string clears the quiet window.
    pub quiet_from: Option<String>,
    pub quiet_to: Option<String>,
}

fn parse_quiet(s: &Option<String>) -> Result<Option<Option<chrono::NaiveTime>>, (StatusCode, Json<Value>)> {
    match s.as_deref() {
        None => Ok(None),
        Some("") => Ok(Some(None)),
        Some(v) => chrono::NaiveTime::parse_from_str(v, "%H:%M")
            .map(|t| Some(Some(t)))
            .map_err(|_| err(StatusCode::BAD_REQUEST, "quiet time must be HH:MM")),
    }
}

#[derive(Deserialize, serde::Serialize)]
pub struct MutedStation {
    pub id: String,
    pub name: String,
}

pub async fn patch_me(State(s): State<AppState>, c: Customer, Json(p): Json<MePatch>) -> ApiResult {
    let quiet_from = parse_quiet(&p.quiet_from)?;
    let quiet_to = parse_quiet(&p.quiet_to)?;
    if let Some(n) = &p.ngo_id {
        let exists: bool = sqlx::query_scalar("select exists(select 1 from ngos where id = $1 and active)").bind(n).fetch_one(&s.pool).await.map_err(internal)?;
        if !exists {
            return Err(err(StatusCode::BAD_REQUEST, "unknown ngo"));
        }
    }
    let row: CustomerRow = sqlx::query_as(
        "update customers set
            nickname = coalesce($2, nickname), ticket = coalesce($3, ticket), ngo_id = coalesce($4, ngo_id),
            loc_mode = coalesce($5, loc_mode), notifications = coalesce($6, notifications),
            show_on_boards = coalesce($7, show_on_boards), keep_correspondence = coalesce($8, keep_correspondence),
            traewelling_linked = coalesce($9, traewelling_linked), onboarding_done = coalesce($10, onboarding_done),
            home_station_id = coalesce($11, home_station_id), home_station_name = coalesce($12, home_station_name),
            muted_stations = coalesce($13, muted_stations),
            nudge_enabled = coalesce($14, nudge_enabled),
            quiet_from = case when $15 then $16 else quiet_from end,
            quiet_to = case when $17 then $18 else quiet_to end
         where id = $1 returning *",
    )
    .bind(c.0.id)
    .bind(p.nickname)
    .bind(p.ticket)
    .bind(p.ngo_id)
    .bind(p.location_mode)
    .bind(p.notifications)
    .bind(p.show_on_boards)
    .bind(p.keep_correspondence)
    .bind(p.traewelling_linked)
    .bind(p.onboarding_done)
    .bind(p.home_station_id)
    .bind(p.home_station_name)
    .bind(p.muted_stations.map(|m| serde_json::to_value(m).unwrap_or(serde_json::json!([]))))
    .bind(p.nudge_enabled)
    .bind(quiet_from.is_some())
    .bind(quiet_from.flatten())
    .bind(quiet_to.is_some())
    .bind(quiet_to.flatten())
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    Ok(Json(customer_json(&s.pool, &row).await.map_err(internal)?))
}

/// The customer's geofence set (docs/15): frequent check-in stations of the last 30 days,
/// home station always, muted stations never, at most 15. Coordinates are the ones the app
/// sent at check-in, so the set is empty until the first ride with coordinates.
pub async fn geofence(State(s): State<AppState>, c: Customer) -> ApiResult {
    let since = crate::clock::now() - Duration::days(30);
    let rows: Vec<(String, String, f64, f64, i64)> = sqlx::query_as(
        "select from_station_id, from_station_name,
                (array_agg(from_lat order by checked_in_at desc))[1],
                (array_agg(from_lon order by checked_in_at desc))[1],
                count(*)::bigint
         from rides where customer_id = $1 and from_lat is not null and from_lon is not null and checked_in_at >= $2
         group by from_station_id, from_station_name order by count(*) desc, max(checked_in_at) desc",
    )
    .bind(c.0.id)
    .bind(since)
    .fetch_all(&s.pool)
    .await
    .map_err(internal)?;
    let home: Option<(String, String, f64, f64)> = match &c.0.home_station_id {
        Some(hid) => sqlx::query_as(
            "select from_station_id, from_station_name, from_lat, from_lon from rides
             where customer_id = $1 and from_station_id = $2 and from_lat is not null order by checked_in_at desc limit 1",
        )
        .bind(c.0.id)
        .bind(hid)
        .fetch_optional(&s.pool)
        .await
        .map_err(internal)?,
        None => None,
    };
    let muted: Vec<MutedStation> = serde_json::from_value(c.0.muted_stations.clone()).unwrap_or_default();
    let stations = geofence_set(rows, home, &muted, 15);
    Ok(Json(json!({
        "enabled": c.0.loc_mode == LocationMode::Always && c.0.nudge_enabled,
        "stations": stations,
        "quiet_from": c.0.quiet_from.map(|t| t.format("%H:%M").to_string()),
        "quiet_to": c.0.quiet_to.map(|t| t.format("%H:%M").to_string()),
    })))
}

#[derive(Debug, PartialEq, serde::Serialize)]
pub struct GeofenceStation {
    pub id: String,
    pub name: String,
    pub lat: f64,
    pub lon: f64,
    pub checkins: i64,
}

/// Pure part of [geofence]: rows are (id, name, lat, lon, checkins) in frequency order.
pub fn geofence_set(rows: Vec<(String, String, f64, f64, i64)>, home: Option<(String, String, f64, f64)>, muted: &[MutedStation], cap: usize) -> Vec<GeofenceStation> {
    let is_muted = |id: &str| muted.iter().any(|m| m.id == id);
    let mut out: Vec<GeofenceStation> = Vec::new();
    if let Some((id, name, lat, lon)) = home {
        if !is_muted(&id) {
            let checkins = rows.iter().find(|r| r.0 == id).map(|r| r.4).unwrap_or(0);
            out.push(GeofenceStation { id, name, lat, lon, checkins });
        }
    }
    for (id, name, lat, lon, checkins) in rows {
        if out.len() >= cap {
            break;
        }
        if is_muted(&id) || out.iter().any(|o| o.id == id) {
            continue;
        }
        out.push(GeofenceStation { id, name, lat, lon, checkins });
    }
    out.truncate(cap);
    out
}

#[derive(Deserialize)]
pub struct PersonalData {
    pub name: String,
    pub address: String,
    pub email: String,
    #[serde(default)]
    pub ticket_number: Option<String>,
    #[serde(default)]
    pub first_class: bool,
}

/// Domain of the per-customer relay addresses (`fahrgast-XXXX@…`). A subdomain, so the apex keeps
/// its own mail. Set `RELAY_DOMAIN` to change it.
pub fn relay_domain() -> String {
    std::env::var("RELAY_DOMAIN").unwrap_or_else(|_| "users.verspaetomat.de".to_string())
}

pub fn relay_address_for(customer_id: Uuid) -> String {
    let short = customer_id.simple().to_string();
    format!("fahrgast-{}@{}", &short[..8], relay_domain())
}

/// Every claim answers on its own address (docs/18 §4): `antrag-<8 hex of the claim id>@RELAY_DOMAIN`.
/// The word is "Antrag", not "Fahrgast": it identifies the case, not the person.
pub fn claim_address_for(claim_id: Uuid) -> String {
    let short = claim_id.simple().to_string();
    format!("antrag-{}@{}", &short[..8], relay_domain())
}

/// The claim's reply address, assigned on first use and persisted.
pub async fn ensure_claim_address(pool: &PgPool, claim: &ClaimRow) -> anyhow::Result<String> {
    if let Some(a) = &claim.reply_address {
        return Ok(a.clone());
    }
    let a = claim_address_for(claim.id);
    sqlx::query("update claims set reply_address = $2 where id = $1 and reply_address is null").bind(claim.id).bind(&a).execute(pool).await?;
    Ok(a)
}

pub fn new_message_id() -> String {
    format!("<{}@{}>", Uuid::new_v4(), relay_domain())
}

/// Asked at the first claim. Assigns the relay address the first time.
pub async fn put_personal_data(State(s): State<AppState>, c: Customer, Json(p): Json<PersonalData>) -> ApiResult {
    let relay = c.0.relay_address.clone().unwrap_or_else(|| relay_address_for(c.0.id));
    let row: CustomerRow = sqlx::query_as(
        "update customers set full_name = $2, postal_address = $3, email = $4, ticket_number = $5, first_class = $6, relay_address = $7 where id = $1 returning *",
    )
    .bind(c.0.id)
    .bind(p.name)
    .bind(p.address)
    .bind(p.email)
    .bind(p.ticket_number)
    .bind(p.first_class)
    .bind(relay)
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    Ok(Json(customer_json(&s.pool, &row).await.map_err(internal)?))
}

/// Issues a new recovery code (the previous one stops working). Shown once in the app.
pub async fn recovery_code(State(s): State<AppState>, c: Customer) -> ApiResult {
    let code = crate::auth::recovery_code();
    sqlx::query("update devices set recovery_hash = $2 where id = $1").bind(c.0.id).bind(sha256(&code)).execute(&s.pool).await.map_err(internal)?;
    Ok(Json(json!({ "recovery_code": code })))
}

pub async fn export_me(State(s): State<AppState>, c: Customer) -> ApiResult {
    let rides: Vec<RideRow> = sqlx::query_as("select * from rides where customer_id = $1 order by checked_in_at desc").bind(c.0.id).fetch_all(&s.pool).await.map_err(internal)?;
    let incidents: Vec<IncidentRow> = sqlx::query_as("select * from incidents where customer_id = $1 order by ride_date desc").bind(c.0.id).fetch_all(&s.pool).await.map_err(internal)?;
    let claims: Vec<ClaimRow> = sqlx::query_as("select * from claims where customer_id = $1 order by created_at desc").bind(c.0.id).fetch_all(&s.pool).await.map_err(internal)?;
    let mails: Vec<MailRow> = sqlx::query_as("select * from mails where customer_id = $1 order by occurred_at desc").bind(c.0.id).fetch_all(&s.pool).await.map_err(internal)?;
    Ok(Json(json!({ "customer": c.0, "rides": rides, "incidents": incidents, "claims": claims, "mails": mails, "exported_at": crate::clock::now() })))
}

pub async fn delete_me(State(s): State<AppState>, c: Customer) -> ApiResult {
    sqlx::query("delete from devices where id = $1").bind(c.0.id).execute(&s.pool).await.map_err(internal)?;
    Ok(Json(json!({ "deleted": true })))
}

#[derive(Deserialize)]
pub struct PushToken {
    pub platform: String,
    pub token: String,
}

/// `PUT /v1/me/push-token`: stored on the device row. Delivery (APNs/FCM) is not wired yet.
pub async fn put_push_token(State(s): State<AppState>, c: Customer, Json(p): Json<PushToken>) -> ApiResult {
    if !matches!(p.platform.as_str(), "ios" | "android") {
        return Err(err(StatusCode::BAD_REQUEST, "platform must be ios or android"));
    }
    let token = p.token.trim();
    if token.is_empty() || token.len() > 4096 {
        return Err(err(StatusCode::BAD_REQUEST, "token missing or too long"));
    }
    sqlx::query("update devices set push_platform = $2, push_token = $3, push_updated_at = now() where id = $1").bind(c.0.id).bind(&p.platform).bind(token).execute(&s.pool).await.map_err(internal)?;
    Ok(Json(json!({ "stored": true, "platform": p.platform })))
}

pub async fn delete_push_token(State(s): State<AppState>, c: Customer) -> ApiResult {
    sqlx::query("update devices set push_platform = null, push_token = null, push_updated_at = now() where id = $1").bind(c.0.id).execute(&s.pool).await.map_err(internal)?;
    Ok(Json(json!({ "stored": false })))
}

// ---------------------------------------------------------------------------
// Rides
// ---------------------------------------------------------------------------

pub fn map_operator(ops: &[OperatorRow], agency: &str) -> String {
    let a = agency_to_operator(agency);
    if let Some(o) = ops.iter().find(|o| o.name == a || o.aliases.iter().any(|x| x == agency || x == &a)) {
        return o.name.clone();
    }
    a
}

pub async fn rides(State(s): State<AppState>, c: Customer) -> ApiResult {
    let rows: Vec<RideRow> = sqlx::query_as("select * from rides where customer_id = $1 order by checked_in_at desc limit 200").bind(c.0.id).fetch_all(&s.pool).await.map_err(internal)?;
    Ok(Json(json!(rows)))
}

#[derive(Deserialize)]
#[allow(dead_code)]
pub struct LocationFix {
    pub lat: f64,
    pub lon: f64,
    #[serde(default)]
    pub accuracy_m: Option<f64>,
}

#[derive(Deserialize)]
pub struct CheckIn {
    pub trip_id: String,
    pub from_station_id: String,
    pub from_station_name: String,
    pub exit_station_id: String,
    pub exit_station_name: String,
    #[serde(default)]
    pub ticket: Option<TicketType>,
    #[serde(default)]
    pub location: Option<LocationFix>,
    /// Coordinates of the from-station (the app has them from nearby/search); feed the geofence set.
    #[serde(default)]
    pub from_lat: Option<f64>,
    #[serde(default)]
    pub from_lon: Option<f64>,
}

fn find_stop<'a>(t: &'a TripInfo, id: &str, name: &str) -> Option<&'a crate::train::TripStop> {
    let n = normalise_station_name(name);
    t.stops
        .iter()
        .find(|st| st.stop_id.as_deref() == Some(id))
        .or_else(|| t.stops.iter().find(|st| normalise_station_name(&st.name) == n))
        .or_else(|| t.stops.iter().find(|st| {
            let a = normalise_station_name(&st.name);
            a.starts_with(&n) || n.starts_with(&a)
        }))
}

pub async fn check_in(State(s): State<AppState>, c: Customer, Json(ci): Json<CheckIn>) -> ApiResult {
    let riding: bool = sqlx::query_scalar("select exists(select 1 from rides where customer_id = $1 and status = 'riding')").bind(c.0.id).fetch_one(&s.pool).await.map_err(internal)?;
    if riding {
        return Err(err(StatusCode::CONFLICT, "already riding; arrive or dismiss first"));
    }
    let t = s.train.trip(&ci.trip_id).await.map_err(|e| err(StatusCode::NOT_FOUND, &format!("trip: {e}")))?;
    let from = find_stop(&t, &ci.from_station_id, &ci.from_station_name).ok_or_else(|| err(StatusCode::BAD_REQUEST, "from station not on this trip"))?;
    let exit = find_stop(&t, &ci.exit_station_id, &ci.exit_station_name).ok_or_else(|| err(StatusCode::BAD_REQUEST, "exit stop not on this trip"))?;
    let planned_departure = from.scheduled_departure.or(from.scheduled_arrival).ok_or_else(|| err(StatusCode::BAD_REQUEST, "no scheduled departure"))?;
    let planned_arrival = exit.scheduled_arrival.or(exit.scheduled_departure).ok_or_else(|| err(StatusCode::BAD_REQUEST, "no scheduled arrival"))?;
    let ops: Vec<OperatorRow> = sqlx::query_as("select * from operators").fetch_all(&s.pool).await.map_err(internal)?;
    let operator = map_operator(&ops, &t.agency_name);
    let live_delay = exit.live_arrival.zip(exit.scheduled_arrival).map(|(l, p)| (l - p).num_minutes()).unwrap_or(0);
    let id = Uuid::new_v4();
    let row: RideRow = sqlx::query_as(
        "insert into rides (id, customer_id, trip_id, line, headsign, operator, category, from_station_id, from_station_name,
            exit_station_id, exit_station_name, planned_departure, planned_arrival, ticket, live_delay_min, cancelled,
            location_verified, location_lat, location_lon, from_lat, from_lon)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21) returning *",
    )
    .bind(id)
    .bind(c.0.id)
    .bind(&t.trip_id)
    .bind(&t.line)
    .bind(&t.headsign)
    .bind(&operator)
    .bind(row_category(t.category))
    .bind(&ci.from_station_id)
    .bind(&ci.from_station_name)
    .bind(exit.stop_id.clone().unwrap_or_else(|| ci.exit_station_id.clone()))
    .bind(&exit.name)
    .bind(planned_departure)
    .bind(planned_arrival)
    .bind(ci.ticket.unwrap_or(c.0.ticket))
    .bind(live_delay as i32)
    .bind(t.cancelled || exit.cancelled)
    .bind(ci.location.is_some())
    .bind(ci.location.as_ref().map(|l| l.lat))
    .bind(ci.location.as_ref().map(|l| l.lon))
    .bind(ci.from_lat)
    .bind(ci.from_lon)
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    let _ = sqlx::query("insert into ride_snapshots (ride_id, source, payload) values ($1, 'transitous', $2)").bind(id).bind(json!(t)).execute(&s.pool).await;
    rules::audit(&s.pool, "ride", id, None, "riding", "check-in").await.map_err(internal)?;
    // Every ride is a leg of a journey (docs/17); the single-train check-in is a one-leg journey.
    let journey = crate::journeys::create_single_leg(&s.pool, &row, &t).await.map_err(internal)?;
    let row: RideRow = sqlx::query_as("select * from rides where id = $1").bind(id).fetch_one(&s.pool).await.map_err(internal)?;
    Ok(Json(json!({ "ride": row, "stops": t.stops, "journey_id": journey.id })))
}

pub async fn current_ride(State(s): State<AppState>, c: Customer) -> ApiResult {
    let ride: Option<RideRow> = sqlx::query_as("select * from rides where customer_id = $1 and status = 'riding' order by checked_in_at desc limit 1").bind(c.0.id).fetch_optional(&s.pool).await.map_err(internal)?;
    let Some(r) = ride else {
        // The most recent arrival, so the app can show the summary after a restart.
        let last: Option<RideRow> = sqlx::query_as("select * from rides where customer_id = $1 and status = 'arrived' and dismissed_at is null and finalised_at > now() - interval '2 hours' order by finalised_at desc limit 1").bind(c.0.id).fetch_optional(&s.pool).await.map_err(internal)?;
        return match last {
            Some(l) => Ok(Json(json!({ "ride": l, "stops": [], "eta": l.actual_arrival, "just_arrived": true }))),
            None => Err(err(StatusCode::NOT_FOUND, "no ride in progress")),
        };
    };
    let stops = match s.train.trip(&r.trip_id).await {
        Ok(t) => json!(t.stops),
        Err(_) => {
            let snap: Option<Value> = sqlx::query_scalar("select payload from ride_snapshots where ride_id = $1 order by fetched_at desc limit 1").bind(r.id).fetch_optional(&s.pool).await.map_err(internal)?;
            snap.and_then(|p| p.get("stops").cloned()).unwrap_or(json!([]))
        }
    };
    let eta = r.planned_arrival + Duration::minutes(r.live_delay_min as i64);
    Ok(Json(json!({ "ride": r, "stops": stops, "eta": eta, "claim_from_minute": 60, "last_polled_at": r.last_polled_at })))
}

#[derive(Deserialize)]
pub struct Arrival {
    #[serde(default)]
    pub delay_minutes: Option<i64>,
    #[serde(default)]
    pub actual_arrival: Option<DateTime<Utc>>,
    #[serde(default)]
    pub cancelled: bool,
    #[serde(default)]
    pub self_entered: bool,
}

/// Manual arrival (no data, E3) or the showcase's "Ankunft simulieren".
pub async fn arrival(State(s): State<AppState>, c: Customer, Json(a): Json<Arrival>) -> ApiResult {
    let ride: Option<RideRow> = sqlx::query_as("select * from rides where customer_id = $1 and status = 'riding' order by checked_in_at desc limit 1").bind(c.0.id).fetch_optional(&s.pool).await.map_err(internal)?;
    let Some(r) = ride else { return Err(err(StatusCode::NOT_FOUND, "no ride in progress")) };
    let delay = match (a.delay_minutes, a.actual_arrival) {
        (Some(d), _) => d,
        (None, Some(t)) => (t - r.planned_arrival).num_minutes().max(0),
        (None, None) => r.live_delay_min as i64,
    };
    let actual = a.actual_arrival.unwrap_or(r.planned_arrival + Duration::minutes(delay));
    crate::train::follower::finalise_ride(&s.pool, r.id, delay, a.cancelled || r.cancelled, Some(actual), a.self_entered).await.map_err(internal)?;
    let created = on_ride_finalised(&s, r.id).await.map_err(internal)?;
    let ride: RideRow = sqlx::query_as("select * from rides where id = $1").bind(r.id).fetch_one(&s.pool).await.map_err(internal)?;
    Ok(Json(json!({
        "ride": ride,
        "incident": created.incident,
        "bundle_ready": created.incident.as_ref().map(|i| i.status == IncidentStatus::Bereit).unwrap_or(false),
        "new_badge": created.new_badge,
    })))
}

pub struct Finalised {
    pub incident: Option<IncidentRow>,
    pub new_badge: Option<BadgeRow>,
    /// The journey this ride was a leg of, after the transition.
    pub journey: Option<JourneyRow>,
    /// True when the ride's own arrival push should stay silent because the journey speaks.
    pub silent_ride: bool,
}

/// Called after a ride is finalised (by the follower or manually). A leg of a journey moves the
/// journey on (transfer or arrival, docs/17); a ride without a journey (Nachtrag, old rows) gets
/// its incident directly.
pub async fn on_ride_finalised(s: &AppState, ride_id: Uuid) -> anyhow::Result<Finalised> {
    let pool = &s.pool;
    let r: RideRow = sqlx::query_as("select * from rides where id = $1").bind(ride_id).fetch_one(pool).await?;
    if r.journey_id.is_some() {
        let out = crate::journeys::on_leg_finalised(s, &r).await?;
        return Ok(Finalised { incident: out.incident, new_badge: out.new_badge, journey: Some(out.journey), silent_ride: out.silent_ride });
    }
    let c: CustomerRow = sqlx::query_as("select * from customers where id = $1").bind(r.customer_id).fetch_one(pool).await?;
    let delay = r.final_delay_min.unwrap_or(0) as i64;
    let existing: Option<IncidentRow> = sqlx::query_as("select * from incidents where ride_id = $1").bind(ride_id).fetch_optional(pool).await?;
    let mut incident = existing;
    if incident.is_none() {
        let fare = if r.ticket == TicketType::Einzelfahrkarte { Some(rules::DEFAULT_FARE_CENTS) } else { None };
        if let Some(amount) = rules::claim_amount_cents(r.ticket, r.category, delay, c.first_class, fare) {
            let desk: String = sqlx::query_scalar("select desk from operators where name = $1").bind(&r.operator).fetch_optional(pool).await?.unwrap_or_else(|| "Unbekannt".into());
            let evidence = json!({
                "planned_arrival": r.planned_arrival, "actual_arrival": r.actual_arrival,
                "source": if r.self_entered { "selbst eingetragen" } else { "Live-Daten Transitous" },
                "fetched_at": r.finalised_at,
            });
            let id = Uuid::new_v4();
            let row: IncidentRow = sqlx::query_as(
                "insert into incidents (id, customer_id, ride_id, ride_date, line, from_name, to_name, delay_min, amount_cents, ticket, operator, desk, cancelled, self_entered, ngo_id, fare_cents, legal_deadline, evidence)
                 values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18) returning *",
            )
            .bind(id)
            .bind(r.customer_id)
            .bind(r.id)
            .bind(r.planned_arrival.date_naive())
            .bind(&r.line)
            .bind(&r.from_station_name)
            .bind(&r.exit_station_name)
            .bind(delay as i32)
            .bind(amount)
            .bind(r.ticket)
            .bind(&r.operator)
            .bind(&desk)
            .bind(r.cancelled)
            .bind(r.self_entered)
            .bind(&c.ngo_id)
            .bind(fare)
            .bind(rules::legal_deadline(r.planned_arrival.date_naive()))
            .bind(evidence)
            .fetch_one(pool)
            .await?;
            rules::audit(pool, "incident", id, None, "gesammelt", "ride finalised").await?;
            incident = Some(row);
        }
    }
    let rows = rules::refresh_statuses(pool, r.customer_id, today()).await?;
    let incident = incident.and_then(|i| rows.into_iter().find(|x| x.id == i.id));
    let new_badge = award_badges(pool, r.customer_id, r.id, delay).await?;
    Ok(Finalised { incident, new_badge, journey: None, silent_ride: false })
}

/// The `ride` event after an arrival. `silent` keeps the leg's push quiet when the journey speaks.
pub fn ride_arrived_payload(ride_id: Uuid, final_delay_min: i64, fin: &Finalised) -> Value {
    json!({
        "ride_id": ride_id, "status": "arrived", "final_delay_min": final_delay_min,
        "incident": fin.incident.as_ref().map(|i| i.id), "silent": fin.silent_ride,
        "journey_id": fin.journey.as_ref().map(|j| j.id),
    })
}

/// Badges: first hour, short delays, first delay, and the minute milestones (1.000, 2.000, …
/// 64.000 minutes waited in total, doubling). Returns the first badge newly awarded.
pub async fn award_badges(pool: &PgPool, customer_id: Uuid, ride_id: Uuid, delay: i64) -> anyhow::Result<Option<BadgeRow>> {
    let mut new_badge = None;
    let mut candidates: Vec<String> = if delay >= 60 { vec!["stunde".into(), "erste".into()] } else if (1..10).contains(&delay) { vec!["gegenzug".into(), "erste".into()] } else if delay > 0 { vec!["erste".into()] } else { vec![] };
    let (total,): (i64,) = sqlx::query_as("select coalesce(sum(points),0)::bigint from rides where customer_id = $1 and status in ('arrived','abandoned')")
        .bind(customer_id)
        .fetch_one(pool)
        .await?;
    candidates.extend(minute_milestones(total).into_iter().map(|m| format!("minuten-{m}")));
    for b in candidates {
        let b = b.as_str();
        let inserted: Option<(String,)> = sqlx::query_as("insert into badge_awards (customer_id, badge_id, ride_id) values ($1, $2, $3) on conflict do nothing returning badge_id")
            .bind(customer_id)
            .bind(b)
            .bind(ride_id)
            .fetch_optional(pool)
            .await?;
        if inserted.is_some() && new_badge.is_none() {
            new_badge = sqlx::query_as::<_, BadgeRow>("select * from badges where id = $1").bind(b).fetch_optional(pool).await?;
        }
    }
    Ok(new_badge)
}

/// The minute milestones reached with `total` points: 1.000 · 2.000 · … · 64.000.
fn minute_milestones(total: i64) -> Vec<i64> {
    (0..7).map(|i| 1000_i64 << i).filter(|m| total >= *m).collect()
}

pub async fn dismiss(State(s): State<AppState>, c: Customer) -> ApiResult {
    // Acknowledge the arrival summary; abandon a stale ride if any.
    sqlx::query("update rides set dismissed_at = now() where customer_id = $1 and status = 'arrived' and dismissed_at is null").bind(c.0.id).execute(&s.pool).await.map_err(internal)?;
    sqlx::query("update journeys set dismissed_at = now() where customer_id = $1 and status = 'arrived' and dismissed_at is null").bind(c.0.id).execute(&s.pool).await.map_err(internal)?;
    sqlx::query("update rides set status = 'abandoned' where customer_id = $1 and status = 'riding' and checked_in_at < now() - interval '12 hours'").bind(c.0.id).execute(&s.pool).await.map_err(internal)?;
    Ok(Json(json!({ "ok": true })))
}

#[derive(Deserialize)]
pub struct Nachtrag {
    pub trip_id: String,
    pub from_station_id: String,
    pub from_station_name: String,
    pub exit_station_id: String,
    pub exit_station_name: String,
}

pub async fn nachtrag(State(s): State<AppState>, c: Customer, Json(n): Json<Nachtrag>) -> ApiResult {
    let t = s.train.trip(&n.trip_id).await.map_err(|e| err(StatusCode::NOT_FOUND, &format!("trip: {e}")))?;
    let from = find_stop(&t, &n.from_station_id, &n.from_station_name).ok_or_else(|| err(StatusCode::BAD_REQUEST, "from station not on this trip"))?;
    let exit = find_stop(&t, &n.exit_station_id, &n.exit_station_name).ok_or_else(|| err(StatusCode::BAD_REQUEST, "exit stop not on this trip"))?;
    let planned_departure = from.scheduled_departure.or(from.scheduled_arrival).ok_or_else(|| err(StatusCode::BAD_REQUEST, "no scheduled departure"))?;
    let planned_arrival = exit.scheduled_arrival.ok_or_else(|| err(StatusCode::BAD_REQUEST, "no scheduled arrival"))?;
    let actual = exit.live_arrival.unwrap_or(planned_arrival);
    let delay = (actual - planned_arrival).num_minutes().max(0);
    let ops: Vec<OperatorRow> = sqlx::query_as("select * from operators").fetch_all(&s.pool).await.map_err(internal)?;
    let operator = map_operator(&ops, &t.agency_name);
    let id = Uuid::new_v4();
    let row: RideRow = sqlx::query_as(
        "insert into rides (id, customer_id, trip_id, line, headsign, operator, category, from_station_id, from_station_name, exit_station_id, exit_station_name,
            planned_departure, planned_arrival, actual_arrival, ticket, status, live_delay_min, final_delay_min, cancelled, nachtrag, points, finalised_at)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,'arrived',$16,$16,$17,true,$18,now()) returning *",
    )
    .bind(id)
    .bind(c.0.id)
    .bind(&t.trip_id)
    .bind(&t.line)
    .bind(&t.headsign)
    .bind(&operator)
    .bind(row_category(t.category))
    .bind(&n.from_station_id)
    .bind(&n.from_station_name)
    .bind(exit.stop_id.clone().unwrap_or_else(|| n.exit_station_id.clone()))
    .bind(&exit.name)
    .bind(planned_departure)
    .bind(planned_arrival)
    .bind(actual)
    .bind(c.0.ticket)
    .bind(delay as i32)
    .bind(t.cancelled || exit.cancelled)
    .bind(rules::points_for(delay, t.cancelled, true) as i32)
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    rules::audit(&s.pool, "ride", id, None, "arrived", "nachtrag").await.map_err(internal)?;
    let created = on_ride_finalised(&s, id).await.map_err(internal)?;
    Ok(Json(json!({ "ride": row, "incident": created.incident })))
}

// ---------------------------------------------------------------------------
// Ledger and claims
// ---------------------------------------------------------------------------

pub async fn incidents(State(s): State<AppState>, c: Customer) -> ApiResult {
    let today = today();
    let rows = rules::refresh_statuses(&s.pool, c.0.id, today).await.map_err(internal)?;
    let mut by_desk: BTreeMap<String, Vec<&IncidentRow>> = BTreeMap::new();
    for i in rows.iter().filter(|i| i.open()) {
        by_desk.entry(i.desk.clone()).or_default().push(i);
    }
    let desks: Vec<Value> = by_desk
        .iter()
        .map(|(desk, list)| {
            let open: Cents = list.iter().map(|i| i.amount_cents).sum();
            json!({ "desk": desk, "open_cents": open, "ready": rules::bundle_ready(list), "missing_cents": (rules::MIN_PAYOUT_CENTS - open).max(0), "incident_ids": list.iter().map(|i| i.id).collect::<Vec<_>>() })
        })
        .collect();
    let ready_desk = by_desk.iter().find(|(_, l)| rules::bundle_ready(l)).map(|(d, _)| d.clone());
    let oldest = rows.iter().filter(|i| i.open()).min_by_key(|i| i.ride_date);
    let confirmed: Cents = rows.iter().filter(|i| i.status == IncidentStatus::Bestaetigt).map(|i| i.amount_cents).sum();
    let submitted: Cents = rows.iter().filter(|i| i.status == IncidentStatus::Eingereicht).map(|i| i.amount_cents).sum();
    let capped: Cents = rows.iter().filter(|i| i.status == IncidentStatus::Gedeckelt).map(|i| i.amount_cents).sum();
    let claims: Vec<ClaimRow> = sqlx::query_as("select * from claims where customer_id = $1 and status <> 'draft' order by sent_at desc nulls last").bind(c.0.id).fetch_all(&s.pool).await.map_err(internal)?;
    let discarded: Vec<&IncidentRow> = rows.iter().filter(|i| i.discarded_at.is_some()).collect();
    Ok(Json(json!({
        "incidents": rows,
        "claims": claims,
        "discarded_ids": discarded.iter().map(|i| i.id).collect::<Vec<_>>(),
        "summary": {
            "desks": desks,
            "ready_desk": ready_desk,
            "confirmed_cents": confirmed,
            "submitted_cents": submitted,
            "capped_cents": capped,
            "oldest_open": oldest.map(|i| json!({ "id": i.id, "line": i.line, "date": i.ride_date, "deadline": i.legal_deadline, "days_left": rules::days_until(i.legal_deadline, today), "warn_from": rules::warn_from(i.legal_deadline) })),
            "min_payout_cents": rules::MIN_PAYOUT_CENTS,
            "dticket_monthly_cap_cents": rules::dticket_monthly_cap_cents(),
        }
    })))
}

#[derive(Deserialize)]
pub struct DiscardBody {
    /// `nicht_gefahren` | `doppelt` | `sonst` (docs/21 §4).
    #[serde(default)]
    pub reason: Option<String>,
}

/// `POST /v1/incidents/{id}/discard` — the passenger takes a case out of the bundle (docs/21 §4).
/// It keeps its row and its evidence, counts nowhere, and can be restored. Refused once the
/// case has left the house in a claim that is no longer a draft.
pub async fn incident_discard(State(s): State<AppState>, c: Customer, Path(id): Path<Uuid>, Json(b): Json<DiscardBody>) -> ApiResult {
    let reason = match b.reason.as_deref() {
        None | Some("sonst") => "sonst",
        Some("nicht_gefahren") => "nicht_gefahren",
        Some("doppelt") => "doppelt",
        Some(other) => return Err(err(StatusCode::BAD_REQUEST, &format!("reason must be nicht_gefahren, doppelt or sonst, got {other}"))),
    };
    let inc: Option<IncidentRow> = sqlx::query_as("select * from incidents where id = $1 and customer_id = $2").bind(id).bind(c.0.id).fetch_optional(&s.pool).await.map_err(internal)?;
    let Some(inc) = inc else { return Err(err(StatusCode::NOT_FOUND, "incident not found")) };
    if inc.discarded_at.is_some() {
        return Ok(Json(json!({ "incident": inc, "claim_deleted": false })));
    }
    // Which claims hold it? A sent one is final; a draft can still be corrected.
    let claims: Vec<ClaimRow> = sqlx::query_as("select c.* from claims c join claim_incidents ci on ci.claim_id = c.id where ci.incident_id = $1").bind(id).fetch_all(&s.pool).await.map_err(internal)?;
    if claims.iter().any(|cl| cl.status != ClaimStatus::Draft) {
        return Err(err(StatusCode::CONFLICT, "der Fall ist schon eingereicht; Änderungen nur noch über eine Antwort an das Unternehmen"));
    }
    sqlx::query("update incidents set discarded_at = now(), discard_reason = $2, claim_id = null where id = $1").bind(id).bind(reason).execute(&s.pool).await.map_err(internal)?;
    sqlx::query("delete from claim_incidents where incident_id = $1").bind(id).execute(&s.pool).await.map_err(internal)?;
    rules::audit(&s.pool, "incident", id, Some(rules::from_label(inc.status)), "verworfen", reason).await.map_err(internal)?;

    // A draft that held it is recomputed; if what is left no longer reaches the minimum, it goes.
    let mut claim_deleted = false;
    for cl in &claims {
        let rest: Vec<IncidentRow> = sqlx::query_as("select i.* from incidents i join claim_incidents ci on ci.incident_id = i.id where ci.claim_id = $1").bind(cl.id).fetch_all(&s.pool).await.map_err(internal)?;
        let refs: Vec<&IncidentRow> = rest.iter().collect();
        if rules::draft_after_removal(&refs) == rules::DraftAfterRemoval::Dropped {
            sqlx::query("delete from claim_attachments where claim_id = $1").bind(cl.id).execute(&s.pool).await.map_err(internal)?;
            sqlx::query("delete from claim_incidents where claim_id = $1").bind(cl.id).execute(&s.pool).await.map_err(internal)?;
            sqlx::query("update incidents set claim_id = null where claim_id = $1").bind(cl.id).execute(&s.pool).await.map_err(internal)?;
            sqlx::query("delete from claims where id = $1").bind(cl.id).execute(&s.pool).await.map_err(internal)?;
            rules::audit(&s.pool, "claim", cl.id, Some("draft"), "deleted", "below the minimum after a case was taken out").await.map_err(internal)?;
            claim_deleted = true;
        } else {
            let amount: Cents = rest.iter().map(|i| i.amount_cents).sum();
            sqlx::query("update claims set amount_claimed_cents = $2 where id = $1").bind(cl.id).bind(amount).execute(&s.pool).await.map_err(internal)?;
        }
    }
    let _ = rules::refresh_statuses(&s.pool, c.0.id, today()).await.map_err(internal)?;
    let inc: IncidentRow = sqlx::query_as("select * from incidents where id = $1").bind(id).fetch_one(&s.pool).await.map_err(internal)?;
    s.events.publish(c.0.id, "incident", json!({ "incident_id": id, "discarded": true }));
    Ok(Json(json!({ "incident": inc, "claim_deleted": claim_deleted })))
}

/// `POST /v1/incidents/{id}/restore` — back into the bundle.
pub async fn incident_restore(State(s): State<AppState>, c: Customer, Path(id): Path<Uuid>) -> ApiResult {
    let inc: Option<IncidentRow> = sqlx::query_as("select * from incidents where id = $1 and customer_id = $2").bind(id).bind(c.0.id).fetch_optional(&s.pool).await.map_err(internal)?;
    let Some(inc) = inc else { return Err(err(StatusCode::NOT_FOUND, "incident not found")) };
    if inc.discarded_at.is_none() {
        return Ok(Json(json!({ "incident": inc, "claim_deleted": false })));
    }
    sqlx::query("update incidents set discarded_at = null, discard_reason = null where id = $1").bind(id).execute(&s.pool).await.map_err(internal)?;
    rules::audit(&s.pool, "incident", id, Some("verworfen"), rules::from_label(inc.status), "restored").await.map_err(internal)?;
    let _ = rules::refresh_statuses(&s.pool, c.0.id, today()).await.map_err(internal)?;
    let inc: IncidentRow = sqlx::query_as("select * from incidents where id = $1").bind(id).fetch_one(&s.pool).await.map_err(internal)?;
    s.events.publish(c.0.id, "incident", json!({ "incident_id": id, "discarded": false }));
    Ok(Json(json!({ "incident": inc, "claim_deleted": false })))
}

pub async fn claims(State(s): State<AppState>, c: Customer) -> ApiResult {
    let rows: Vec<ClaimRow> = sqlx::query_as("select * from claims where customer_id = $1 order by created_at desc").bind(c.0.id).fetch_all(&s.pool).await.map_err(internal)?;
    Ok(Json(json!(rows)))
}

#[derive(Deserialize)]
pub struct DraftRequest {
    pub desk: String,
    #[serde(default)]
    pub incident_ids: Option<Vec<Uuid>>,
}

async fn claim_with_incidents(pool: &PgPool, claim: &ClaimRow) -> anyhow::Result<Value> {
    let incidents: Vec<IncidentRow> = sqlx::query_as("select i.* from incidents i join claim_incidents ci on ci.incident_id = i.id where ci.claim_id = $1 order by i.ride_date").bind(claim.id).fetch_all(pool).await?;
    let attachments: Vec<(Uuid, String)> = sqlx::query_as("select upload_id, label from claim_attachments where claim_id = $1").bind(claim.id).fetch_all(pool).await?;
    let mut v = json!(claim);
    v["incidents"] = json!(incidents);
    v["attachments"] = json!(attachments.into_iter().map(|(id, label)| json!({ "upload_id": id, "label": label })).collect::<Vec<_>>());
    v["pdf_url"] = json!(format!("/v1/claims/{}/pdf", claim.id));
    Ok(v)
}

/// Loads everything the form needs and renders it. Shared by the preview route and the send path.
async fn render_claim_pdf(pool: &PgPool, claim: &ClaimRow, customer: &CustomerRow) -> anyhow::Result<Vec<u8>> {
    let incidents: Vec<IncidentRow> = sqlx::query_as("select i.* from incidents i join claim_incidents ci on ci.incident_id = i.id where ci.claim_id = $1 order by i.ride_date").bind(claim.id).fetch_all(pool).await?;
    let signature_png: Option<Vec<u8>> = sqlx::query_scalar(
        "select u.bytes from claim_attachments ca join uploads u on u.id = ca.upload_id where ca.claim_id = $1 and ca.label = 'Unterschrift' and u.content_type = 'image/png' limit 1",
    )
    .bind(claim.id)
    .fetch_optional(pool)
    .await?;
    let claim = claim.clone();
    let customer = customer.clone();
    tokio::task::spawn_blocking(move || crate::pdf::render(&crate::pdf::ClaimDocument { claim: &claim, incidents: &incidents, customer: &customer, signature_png })).await?
}

/// `GET /v1/claims/{id}/pdf` — the filled EU form as it stands right now (draft or sent).
pub async fn claim_pdf(State(s): State<AppState>, c: Customer, Path(id): Path<Uuid>) -> Result<Response, (StatusCode, Json<Value>)> {
    let claim: Option<ClaimRow> = sqlx::query_as("select * from claims where id = $1 and customer_id = $2").bind(id).bind(c.0.id).fetch_optional(&s.pool).await.map_err(internal)?;
    let Some(claim) = claim else { return Err(err(StatusCode::NOT_FOUND, "claim not found")) };
    let pdf = render_claim_pdf(&s.pool, &claim, &c.0).await.map_err(internal)?;
    Ok((
        [(header::CONTENT_TYPE, "application/pdf".to_string()), (header::CONTENT_DISPOSITION, format!("inline; filename=\"EU-Antrag-{}.pdf\"", claim.id))],
        pdf,
    )
        .into_response())
}

pub async fn claim_draft(State(s): State<AppState>, c: Customer, Json(d): Json<DraftRequest>) -> ApiResult {
    let today = today();
    let rows = rules::refresh_statuses(&s.pool, c.0.id, today).await.map_err(internal)?;
    let selected: Vec<&IncidentRow> = rows
        .iter()
        .filter(|i| i.open() && i.desk == d.desk && d.incident_ids.as_ref().map(|ids| ids.contains(&i.id)).unwrap_or(true))
        .collect();
    if selected.is_empty() {
        return Err(err(StatusCode::BAD_REQUEST, "no open incidents for this desk"));
    }
    if !rules::bundle_ready(&selected) {
        return Err(err(StatusCode::PRECONDITION_FAILED, "bundle below the 4 € minimum; keep collecting"));
    }
    let ngo: NgoRow = sqlx::query_as("select * from ngos where id = $1").bind(&c.0.ngo_id).fetch_one(&s.pool).await.map_err(internal)?;
    let amount: Cents = selected.iter().map(|i| i.amount_cents).sum();
    let mut months: Vec<String> = selected.iter().map(|i| i.ride_date.format("%Y-%m").to_string()).collect();
    months.sort();
    months.dedup();
    let id = Uuid::new_v4();
    let claim: ClaimRow = sqlx::query_as(
        "insert into claims (id, customer_id, desk, ngo_id, account_holder, iban, ticket_months, amount_claimed_cents) values ($1,$2,$3,$4,$5,$6,$7,$8) returning *",
    )
    .bind(id)
    .bind(c.0.id)
    .bind(&d.desk)
    .bind(&ngo.id)
    .bind(&ngo.account_holder)
    .bind(&ngo.iban)
    .bind(&months)
    .bind(amount)
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    for i in &selected {
        sqlx::query("insert into claim_incidents (claim_id, incident_id) values ($1, $2)").bind(id).bind(i.id).execute(&s.pool).await.map_err(internal)?;
    }
    let op: Option<OperatorRow> = sqlx::query_as("select * from operators where desk = $1 limit 1").bind(&d.desk).fetch_optional(&s.pool).await.map_err(internal)?;
    let mut v = claim_with_incidents(&s.pool, &claim).await.map_err(internal)?;
    v["desk_address"] = json!(op.as_ref().map(|o| o.postal_address.clone()));
    v["desk_email"] = json!(op.as_ref().and_then(|o| o.email.clone()));
    v["desk_accepts_email"] = json!(op.as_ref().map(|o| o.accepts_email).unwrap_or(false));
    v["personal_data_required"] = json!(c.0.full_name.is_none());
    v["relay_address"] = json!(c.0.relay_address);
    v["needs_recovery_code"] = json!(sqlx::query_scalar::<_, bool>("select recovery_hash is null from devices where id = $1").bind(c.0.id).fetch_one(&s.pool).await.map_err(internal)?);
    Ok(Json(v))
}

#[derive(Deserialize)]
pub struct ClaimPatch {
    pub ngo_id: Option<String>,
    pub attachments: Option<Vec<AttachmentRef>>,
}

#[derive(Deserialize)]
pub struct AttachmentRef {
    pub upload_id: Uuid,
    pub label: String,
}

pub async fn claim_patch(State(s): State<AppState>, c: Customer, Path(id): Path<Uuid>, Json(p): Json<ClaimPatch>) -> ApiResult {
    let claim: Option<ClaimRow> = sqlx::query_as("select * from claims where id = $1 and customer_id = $2").bind(id).bind(c.0.id).fetch_optional(&s.pool).await.map_err(internal)?;
    let Some(claim) = claim else { return Err(err(StatusCode::NOT_FOUND, "claim not found")) };
    if claim.status != ClaimStatus::Draft {
        return Err(err(StatusCode::CONFLICT, "claim already sent"));
    }
    if let Some(n) = &p.ngo_id {
        let ngo: Option<NgoRow> = sqlx::query_as("select * from ngos where id = $1 and active").bind(n).fetch_optional(&s.pool).await.map_err(internal)?;
        let Some(ngo) = ngo else { return Err(err(StatusCode::BAD_REQUEST, "unknown ngo")) };
        sqlx::query("update claims set ngo_id = $2, account_holder = $3, iban = $4 where id = $1").bind(id).bind(&ngo.id).bind(&ngo.account_holder).bind(&ngo.iban).execute(&s.pool).await.map_err(internal)?;
        sqlx::query("update incidents set ngo_id = $2 where claim_id = $1 or id in (select incident_id from claim_incidents where claim_id = $1)").bind(id).bind(&ngo.id).execute(&s.pool).await.map_err(internal)?;
    }
    if let Some(atts) = p.attachments {
        sqlx::query("delete from claim_attachments where claim_id = $1").bind(id).execute(&s.pool).await.map_err(internal)?;
        for a in atts {
            sqlx::query("insert into claim_attachments (claim_id, upload_id, label) select $1, $2, $3 where exists (select 1 from uploads where id = $2 and customer_id = $4)")
                .bind(id)
                .bind(a.upload_id)
                .bind(a.label)
                .bind(c.0.id)
                .execute(&s.pool)
                .await
                .map_err(internal)?;
        }
    }
    let claim: ClaimRow = sqlx::query_as("select * from claims where id = $1").bind(id).fetch_one(&s.pool).await.map_err(internal)?;
    Ok(Json(claim_with_incidents(&s.pool, &claim).await.map_err(internal)?))
}

/// Multipart: fields `kind` (ticket|signature|postal_reply) and `file`.
pub async fn upload(State(s): State<AppState>, c: Customer, mut mp: Multipart) -> ApiResult {
    let mut kind = "ticket".to_string();
    let mut bytes: Option<(String, Vec<u8>)> = None;
    while let Some(field) = mp.next_field().await.map_err(|e| err(StatusCode::BAD_REQUEST, &e.to_string()))? {
        match field.name().unwrap_or("") {
            "kind" => kind = field.text().await.unwrap_or_default(),
            "file" => {
                let ct = field.content_type().unwrap_or("application/octet-stream").to_string();
                let data = field.bytes().await.map_err(|e| err(StatusCode::BAD_REQUEST, &e.to_string()))?;
                bytes = Some((ct, data.to_vec()));
            }
            _ => {}
        }
    }
    let Some((ct, data)) = bytes else { return Err(err(StatusCode::BAD_REQUEST, "file missing")) };
    if data.len() > 8 * 1024 * 1024 {
        return Err(err(StatusCode::PAYLOAD_TOO_LARGE, "max 8 MB"));
    }
    let id = Uuid::new_v4();
    sqlx::query("insert into uploads (id, customer_id, kind, content_type, bytes) values ($1,$2,$3,$4,$5)").bind(id).bind(c.0.id).bind(&kind).bind(&ct).bind(&data).execute(&s.pool).await.map_err(internal)?;
    Ok(Json(json!({ "upload_id": id, "kind": kind, "content_type": ct, "size": data.len() })))
}

#[derive(Deserialize)]
pub struct Sign {
    pub typed_name: String,
    #[serde(default)]
    pub signature_upload_id: Option<Uuid>,
}

pub async fn claim_sign(State(s): State<AppState>, c: Customer, Path(id): Path<Uuid>, Json(p): Json<Sign>) -> ApiResult {
    let claim: Option<ClaimRow> = sqlx::query_as("update claims set signed_by = $3, signed_at = now() where id = $1 and customer_id = $2 and status = 'draft' returning *")
        .bind(id)
        .bind(c.0.id)
        .bind(p.typed_name.trim())
        .fetch_optional(&s.pool)
        .await
        .map_err(internal)?;
    let Some(claim) = claim else { return Err(err(StatusCode::NOT_FOUND, "claim not found or already sent")) };
    if let Some(u) = p.signature_upload_id {
        sqlx::query("insert into claim_attachments (claim_id, upload_id, label) select $1, $2, 'Unterschrift' where exists (select 1 from uploads where id = $2 and customer_id = $3) on conflict do nothing").bind(id).bind(u).bind(c.0.id).execute(&s.pool).await.map_err(internal)?;
    }
    Ok(Json(claim_with_incidents(&s.pool, &claim).await.map_err(internal)?))
}

fn claim_summary_text(claim: &ClaimRow, incidents: &[IncidentRow], name: &str) -> String {
    let mut s = String::new();
    s.push_str("ANTRAGSFORMULAR FÜR ERSTATTUNGEN UND ENTSCHÄDIGUNGEN (VO (EU) 2021/782)\n\n");
    s.push_str("1. Grund: Verspätung / Ausfall\n4. Entschädigung: wiederholte Verspätungen oder Ausfälle, Inhaber einer Zeitfahrkarte\n\n");
    s.push_str("6. Einzelfälle:\n");
    for i in incidents {
        s.push_str(&format!(
            "- {} {} {} → {}: {} Minuten{}; Anspruch {},{:02} EUR\n",
            i.ride_date.format("%d.%m.%Y"),
            i.line,
            i.from_name,
            i.to_name,
            i.delay_min,
            if i.cancelled { " (Ausfall)" } else { "" },
            i.amount_cents / 100,
            i.amount_cents % 100
        ));
    }
    s.push_str(&format!("\nSumme: {},{:02} EUR\n", claim.amount_claimed_cents / 100, claim.amount_claimed_cents % 100));
    s.push_str(&format!("Kontoinhaber: {}\nIBAN: {}\n\nName des Fahrgastes: {}\n", claim.account_holder, claim.iban, name));
    s
}

/// The relay: nothing leaves without a signature and this explicit call.
pub async fn claim_send(State(s): State<AppState>, c: Customer, Path(id): Path<Uuid>) -> ApiResult {
    let claim: Option<ClaimRow> = sqlx::query_as("select * from claims where id = $1 and customer_id = $2").bind(id).bind(c.0.id).fetch_optional(&s.pool).await.map_err(internal)?;
    let Some(claim) = claim else { return Err(err(StatusCode::NOT_FOUND, "claim not found")) };
    if claim.status != ClaimStatus::Draft {
        return Err(err(StatusCode::CONFLICT, "claim already sent"));
    }
    if claim.signed_by.is_none() {
        return Err(err(StatusCode::PRECONDITION_FAILED, "claim not signed"));
    }
    let (Some(name), Some(email)) = (c.0.full_name.clone(), c.0.email.clone()) else {
        return Err(err(StatusCode::PRECONDITION_FAILED, "personal data required"));
    };
    // The mail leaves from the claim's own address; the railway's reply comes back to it.
    let relay = ensure_claim_address(&s.pool, &claim).await.map_err(internal)?;
    let sent_today: i64 = sqlx::query_scalar("select count(*) from claims where customer_id = $1 and sent_at > now() - interval '1 day'").bind(c.0.id).fetch_one(&s.pool).await.map_err(internal)?;
    if sent_today >= 5 {
        return Err(err(StatusCode::TOO_MANY_REQUESTS, "max 5 claims per day"));
    }
    let op: Option<OperatorRow> = sqlx::query_as("select * from operators where desk = $1 limit 1").bind(&claim.desk).fetch_optional(&s.pool).await.map_err(internal)?;
    let Some(to) = op.as_ref().and_then(|o| if o.accepts_email { o.email.clone() } else { None }) else {
        return Err(err(StatusCode::PRECONDITION_FAILED, "this desk takes no e-mail; use the paper route"));
    };
    let incidents: Vec<IncidentRow> = sqlx::query_as("select i.* from incidents i join claim_incidents ci on ci.incident_id = i.id where ci.claim_id = $1 order by i.ride_date").bind(id).fetch_all(&s.pool).await.map_err(internal)?;
    let body = format!(
        "Sehr geehrte Damen und Herren,\n\nanbei mein gesammelter Antrag auf Entschädigung nach VO (EU) 2021/782 (wiederholte Verspätungen, Zeitfahrkarte). Die Einzelfälle sind im Formular unter Punkt 6 aufgeführt.\n\nKontoinhaber: {}\n\nDiese E-Mail wurde über Verspätomat übermittelt, eine Ausfüll- und Weiterleitungshilfe. Antragsteller ist {}.\n\nMit freundlichen Grüßen\n{}",
        claim.account_holder, name, name
    );
    let attachments = json!([
        { "name": "EU-Antrag.pdf", "content_type": "application/pdf", "url": format!("/v1/claims/{}/pdf", claim.id) },
        { "name": "EU-Antrag.txt", "content_type": "text/plain", "text": claim_summary_text(&claim, &incidents, &name) },
    ]);
    let message_id = new_message_id();
    let summary = claim_summary_text(&claim, &incidents, &name);
    let mut uploads: Vec<(String, String, Vec<u8>)> = sqlx::query_as::<_, (String, String, Vec<u8>)>(
        "select ca.label || case when u.content_type like 'image/png' then '.png' when u.content_type like 'image/jpeg' then '.jpg' else '' end, u.content_type, u.bytes from claim_attachments ca join uploads u on u.id = ca.upload_id where ca.claim_id = $1",
    )
    .bind(id)
    .fetch_all(&s.pool)
    .await
    .map_err(internal)?;
    uploads.insert(0, ("EU-Antrag.txt".into(), "text/plain".into(), summary.into_bytes()));
    let pdf = render_claim_pdf(&s.pool, &claim, &c.0).await.map_err(|e| err(StatusCode::INTERNAL_SERVER_ERROR, &format!("pdf: {e}")))?;
    uploads.insert(0, ("EU-Antrag.pdf".into(), "application/pdf".into(), pdf));
    let sent = crate::mail::send(crate::mail::OutgoingMail {
        from: &format!("{name} <{relay}>"),
        to: &to,
        bcc: Some(&email),
        subject: "Fahrgastrechte: EU-Antragsformular",
        body: &body,
        message_id: &message_id,
        in_reply_to: None,
        attachments: uploads,
    })
    .await
    .map_err(|e| err(StatusCode::BAD_GATEWAY, &format!("mail: {e}")))?;
    let dry_run = matches!(sent, crate::mail::SendResult::DryRun);
    let mail_id = Uuid::new_v4();
    let mail: MailRow = sqlx::query_as(
        "insert into mails (id, customer_id, claim_id, direction, message_id, from_addr, to_addr, bcc_addr, subject, body, attachments, dry_run)
         values ($1,$2,$3,'out',$4,$5,$6,$7,$8,$9,$10,$11) returning *",
    )
    .bind(mail_id)
    .bind(c.0.id)
    .bind(id)
    .bind(&message_id)
    .bind(format!("{name} <{relay}>"))
    .bind(&to)
    .bind(&email)
    .bind("Fahrgastrechte: EU-Antragsformular")
    .bind(&body)
    .bind(attachments)
    .bind(dry_run)
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    sqlx::query("update incidents set status = 'eingereicht', claim_id = $1 where id in (select incident_id from claim_incidents where claim_id = $1)").bind(id).execute(&s.pool).await.map_err(internal)?;
    let claim: ClaimRow = sqlx::query_as("update claims set status = 'sent', sent_at = now(), expected_reply_by = $2 where id = $1 returning *")
        .bind(id)
        .bind(today() + Duration::days(rules::REPLY_EXPECTED_DAYS))
        .fetch_one(&s.pool)
        .await
        .map_err(internal)?;
    rules::audit(&s.pool, "claim", id, Some("draft"), "sent", if dry_run { "dry-run" } else { "smtp" }).await.map_err(internal)?;
    for i in &incidents {
        rules::audit(&s.pool, "incident", i.id, Some(rules::from_label(i.status)), "eingereicht", "claim sent").await.map_err(internal)?;
    }
    let _ = sqlx::query("insert into badge_awards (customer_id, badge_id) values ($1, 'abgeschickt') on conflict do nothing").bind(c.0.id).execute(&s.pool).await;
    s.events.publish(c.0.id, "claim", json!({ "claim_id": claim.id, "status": "sent" }));
    Ok(Json(json!({ "claim": claim_with_incidents(&s.pool, &claim).await.map_err(internal)?, "mail": mail })))
}

pub async fn mails(State(s): State<AppState>, c: Customer) -> ApiResult {
    let rows: Vec<MailRow> = sqlx::query_as("select * from mails where customer_id = $1 order by occurred_at desc").bind(c.0.id).fetch_all(&s.pool).await.map_err(internal)?;
    Ok(Json(json!(rows)))
}

#[derive(Deserialize)]
pub struct Reply {
    pub body: String,
    /// Attach the claim's ticket uploads (the same images the claim mail carried).
    #[serde(default)]
    pub attach_ticket: bool,
    /// Any of this customer's uploads (e.g. a fresh photo via POST /v1/uploads).
    #[serde(default)]
    pub upload_ids: Vec<Uuid>,
}

/// File name for an upload: the claim's label when it has one, else the kind, plus the extension.
fn attachment_filename(label: &str, content_type: &str) -> String {
    let ext = match content_type {
        ct if ct.starts_with("image/png") => ".png",
        ct if ct.starts_with("image/jpeg") => ".jpg",
        ct if ct.starts_with("image/heic") => ".heic",
        ct if ct.starts_with("application/pdf") => ".pdf",
        _ => "",
    };
    let stem: String = label.chars().map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '_' }).collect();
    format!("{}{}", if stem.is_empty() { "Anhang" } else { &stem }, ext)
}

/// The customer answers a railway's question, through their own relay address.
pub async fn mail_reply(State(s): State<AppState>, c: Customer, Path(id): Path<Uuid>, Json(r): Json<Reply>) -> ApiResult {
    let original: Option<MailRow> = sqlx::query_as("select * from mails where id = $1 and customer_id = $2 and direction = 'inbound'").bind(id).bind(c.0.id).fetch_optional(&s.pool).await.map_err(internal)?;
    let Some(orig) = original else { return Err(err(StatusCode::NOT_FOUND, "inbound mail not found")) };
    let (Some(name), Some(email)) = (c.0.full_name.clone(), c.0.email.clone()) else {
        return Err(err(StatusCode::PRECONDITION_FAILED, "personal data required"));
    };
    // Answer from the address the thread belongs to: the claim's, or the customer's for old mail.
    let relay = match orig.claim_id {
        Some(cid) => {
            let claim: Option<ClaimRow> = sqlx::query_as("select * from claims where id = $1").bind(cid).fetch_optional(&s.pool).await.map_err(internal)?;
            match claim {
                Some(cl) => ensure_claim_address(&s.pool, &cl).await.map_err(internal)?,
                None => c.0.relay_address.clone().unwrap_or_else(|| relay_address_for(c.0.id)),
            }
        }
        None => c.0.relay_address.clone().unwrap_or_else(|| relay_address_for(c.0.id)),
    };
    // Attachments: the claim's ticket uploads on request, plus any of the customer's own uploads.
    let mut files: Vec<(String, String, Vec<u8>, Uuid)> = Vec::new();
    if r.attach_ticket {
        if let Some(cid) = orig.claim_id {
            let rows: Vec<(Uuid, String, String, Vec<u8>)> = sqlx::query_as(
                "select u.id, ca.label, u.content_type, u.bytes from claim_attachments ca join uploads u on u.id = ca.upload_id where ca.claim_id = $1 and u.customer_id = $2 and u.kind = 'ticket' and length(u.bytes) > 0 order by ca.label",
            )
            .bind(cid)
            .bind(c.0.id)
            .fetch_all(&s.pool)
            .await
            .map_err(internal)?;
            for (uid, label, ct, bytes) in rows {
                files.push((attachment_filename(&label, &ct), ct, bytes, uid));
            }
        }
    }
    for uid in &r.upload_ids {
        if files.iter().any(|f| &f.3 == uid) {
            continue;
        }
        let row: Option<(String, String, Vec<u8>)> = sqlx::query_as("select kind, content_type, bytes from uploads where id = $1 and customer_id = $2").bind(uid).bind(c.0.id).fetch_optional(&s.pool).await.map_err(internal)?;
        let Some((kind, ct, bytes)) = row else { return Err(err(StatusCode::NOT_FOUND, &format!("upload {uid} not found"))) };
        if bytes.is_empty() {
            return Err(err(StatusCode::GONE, &format!("upload {uid} was deleted by retention")));
        }
        files.push((attachment_filename(&kind, &ct), ct, bytes, *uid));
    }
    let total: usize = files.iter().map(|f| f.2.len()).sum();
    if total > 20 * 1024 * 1024 {
        return Err(err(StatusCode::PAYLOAD_TOO_LARGE, "attachments exceed 20 MB"));
    }
    let attachments_json = json!(files.iter().map(|(name, ct, bytes, uid)| json!({ "name": name, "content_type": ct, "size": bytes.len(), "upload_id": uid })).collect::<Vec<_>>());
    let message_id = new_message_id();
    let sent = crate::mail::send(crate::mail::OutgoingMail {
        from: &format!("{name} <{relay}>"),
        to: &orig.from_addr,
        bcc: Some(&email),
        subject: &format!("Re: {}", orig.subject),
        body: &r.body,
        message_id: &message_id,
        in_reply_to: orig.message_id.as_deref(),
        attachments: files.iter().map(|(name, ct, bytes, _)| (name.clone(), ct.clone(), bytes.clone())).collect(),
    })
    .await
    .map_err(|e| err(StatusCode::BAD_GATEWAY, &format!("mail: {e}")))?;
    let dry_run = matches!(sent, crate::mail::SendResult::DryRun);
    let mail: MailRow = sqlx::query_as(
        "insert into mails (id, customer_id, claim_id, direction, message_id, in_reply_to, from_addr, to_addr, bcc_addr, subject, body, attachments, dry_run)
         values ($1,$2,$3,'out',$4,$5,$6,$7,$8,$9,$10,$11,$12) returning *",
    )
    .bind(Uuid::new_v4())
    .bind(c.0.id)
    .bind(orig.claim_id)
    .bind(&message_id)
    .bind(orig.message_id)
    .bind(format!("{name} <{relay}>"))
    .bind(orig.from_addr)
    .bind(&email)
    .bind(format!("Re: {}", orig.subject))
    .bind(r.body)
    .bind(attachments_json)
    .bind(dry_run)
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    Ok(Json(json!(mail)))
}

#[derive(Deserialize)]
pub struct InboundMail {
    pub to: String,
    pub from: String,
    pub subject: String,
    pub body: String,
    #[serde(default)]
    pub message_id: Option<String>,
    #[serde(default)]
    pub in_reply_to: Option<String>,
    #[serde(default)]
    pub claim_id: Option<Uuid>,
    /// (file name, content type, bytes). Only the raw-MIME route fills this; the JSON webhook carries none.
    #[serde(skip)]
    pub attachments: Vec<(String, String, Vec<u8>)>,
}

fn inbound_secret_ok(q: &BTreeMap<String, String>) -> Result<(), (StatusCode, Json<Value>)> {
    if let Ok(secret) = std::env::var("INBOUND_SECRET") {
        if q.get("secret") != Some(&secret) {
            return Err(err(StatusCode::UNAUTHORIZED, "bad secret"));
        }
    }
    Ok(())
}

/// Mail-provider webhook (and the showcase's "Antwort simulieren"). Match by relay
/// address and claim reference, classify, forward, update statuses.
pub async fn inbound_mail(State(s): State<AppState>, axum::extract::Query(q): axum::extract::Query<BTreeMap<String, String>>, Json(v): Json<Value>) -> ApiResult {
    inbound_secret_ok(&q)?;
    let m = inbound_from_json(v).ok_or_else(|| err(StatusCode::BAD_REQUEST, "unrecognised inbound payload"))?;
    Ok(Json(process_inbound(&s, m).await?))
}

/// Accepts our own shape (`to`, `from`, `subject`, `body`, …) and Postmark's inbound
/// webhook (`To`, `From`/`FromFull`, `Subject`, `TextBody`, `MessageID`, `Headers`,
/// base64 `Attachments`; with "include raw email" on, `RawEmail` wins and is parsed as MIME).
pub fn inbound_from_json(v: Value) -> Option<InboundMail> {
    if let Some(raw) = v.get("RawEmail").and_then(|r| r.as_str()) {
        return parse_raw_mail(raw.as_bytes());
    }
    if v.get("To").is_some() || v.get("ToFull").is_some() {
        let str_of = |k: &str| v.get(k).and_then(|x| x.as_str()).map(|x| x.to_string());
        let to = v.get("ToFull").and_then(|t| t.as_array()).and_then(|a| a.first()).and_then(|t| t.get("Email")).and_then(|e| e.as_str()).map(|e| e.to_string()).or_else(|| str_of("To"))?;
        let from = str_of("From").or_else(|| v.get("FromFull").and_then(|f| f.get("Email")).and_then(|e| e.as_str()).map(|e| e.to_string()))?;
        let body = str_of("TextBody").or_else(|| str_of("StrippedTextReply")).or_else(|| str_of("HtmlBody")).unwrap_or_default();
        let header = |name: &str| {
            v.get("Headers")
                .and_then(|h| h.as_array())
                .and_then(|h| h.iter().find(|x| x.get("Name").and_then(|n| n.as_str()).map(|n| n.eq_ignore_ascii_case(name)).unwrap_or(false)))
                .and_then(|x| x.get("Value"))
                .and_then(|x| x.as_str())
                .map(|x| x.to_string())
        };
        let message_id = str_of("MessageID").map(|id| if id.starts_with('<') { id } else { format!("<{id}>") });
        let attachments = v
            .get("Attachments")
            .and_then(|a| a.as_array())
            .map(|a| {
                a.iter()
                    .filter_map(|x| {
                        let name = x.get("Name")?.as_str()?.to_string();
                        let ct = x.get("ContentType").and_then(|c| c.as_str()).unwrap_or("application/octet-stream").to_string();
                        let bytes = base64::engine::general_purpose::STANDARD.decode(x.get("Content")?.as_str()?).ok()?;
                        Some((name, ct, bytes))
                    })
                    .collect()
            })
            .unwrap_or_default();
        return Some(InboundMail { to, from, subject: str_of("Subject").unwrap_or_default(), body, message_id, in_reply_to: header("In-Reply-To"), claim_id: None, attachments });
    }
    serde_json::from_value(v).ok()
}

/// `POST /internal/inbound-mail/raw`: the RFC 822 message as the body, for providers that
/// hand over the original mail. Parsed with mail-parser, then the same path as the JSON webhook.
pub async fn inbound_mail_raw(State(s): State<AppState>, axum::extract::Query(q): axum::extract::Query<BTreeMap<String, String>>, body: axum::body::Bytes) -> ApiResult {
    inbound_secret_ok(&q)?;
    let m = parse_raw_mail(&body).ok_or_else(|| err(StatusCode::BAD_REQUEST, "not a parseable RFC 822 message"))?;
    Ok(Json(process_inbound(&s, m).await?))
}

/// Raw MIME → InboundMail. The relay address is the To: entry on our domain when there is one.
pub fn parse_raw_mail(raw: &[u8]) -> Option<InboundMail> {
    use mail_parser::{MessageParser, MimeHeaders};
    let msg = MessageParser::default().parse(raw)?;
    let mailbox = |a: &mail_parser::Addr| match (a.name(), a.address()) {
        (Some(n), Some(ad)) => format!("{n} <{ad}>"),
        (None, Some(ad)) => ad.to_string(),
        (Some(n), None) => n.to_string(),
        (None, None) => String::new(),
    };
    let from = msg.from().or_else(|| msg.sender()).and_then(|a| a.first()).map(mailbox).unwrap_or_default();
    let to = msg
        .to()
        .and_then(|a| {
            a.iter().find(|x| x.address().map(|ad| ad.to_lowercase().ends_with(&format!("@{}", relay_domain()))).unwrap_or(false)).or_else(|| a.first()).and_then(|x| x.address().map(|s| s.to_string()))
        })
        .unwrap_or_default();
    let body = msg
        .body_text(0)
        .map(|t| t.to_string())
        .or_else(|| msg.body_html(0).map(|h| strip_html(&h)))
        .unwrap_or_default();
    let attachments = msg
        .attachments()
        .map(|p| {
            let ct = p.content_type().map(|c| match c.subtype() { Some(sub) => format!("{}/{}", c.ctype(), sub), None => c.ctype().to_string() }).unwrap_or_else(|| "application/octet-stream".into());
            (p.attachment_name().unwrap_or("Anhang").to_string(), ct, p.contents().to_vec())
        })
        .collect();
    Some(InboundMail {
        to,
        from,
        subject: msg.subject().unwrap_or("").to_string(),
        body,
        message_id: msg.message_id().map(|id| format!("<{id}>")),
        in_reply_to: msg.in_reply_to().as_text().map(|id| format!("<{id}>")),
        claim_id: None,
        attachments,
    })
}

/// Enough for classification: drop tags, decode the common entities.
fn strip_html(h: &str) -> String {
    let mut out = String::with_capacity(h.len());
    let mut in_tag = false;
    for ch in h.chars() {
        match ch {
            '<' => in_tag = true,
            '>' => in_tag = false,
            c if !in_tag => out.push(c),
            _ => {}
        }
    }
    out.replace("&nbsp;", " ").replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"")
}

/// Shared by the provider webhook and the Stellwerk.
/// The bare, lower-cased address out of a To header value ("Name <x@y>" or "x@y").
pub fn inbound_address(to: &str) -> String {
    let t = to.trim();
    let inner = match (t.rfind('<'), t.rfind('>')) {
        (Some(a), Some(b)) if b > a => &t[a + 1..b],
        _ => t,
    };
    inner.trim().to_lowercase()
}

/// `POST /v1/claims/{id}/seen`: the customer opened the claim's thread; its inbound mail is read now.
pub async fn claim_seen(State(s): State<AppState>, c: Customer, Path(id): Path<Uuid>) -> ApiResult {
    let n = sqlx::query("update mails set seen_at = now() where claim_id = $1 and customer_id = $2 and direction = 'inbound' and seen_at is null")
        .bind(id)
        .bind(c.0.id)
        .execute(&s.pool)
        .await
        .map_err(internal)?
        .rows_affected();
    let unread: i64 = unread_mails(&s.pool, c.0.id).await.map_err(internal)?;
    Ok(Json(json!({ "seen": n, "unread_mails": unread })))
}

pub async fn unread_mails(pool: &PgPool, customer_id: Uuid) -> anyhow::Result<i64> {
    Ok(sqlx::query_scalar("select count(*) from mails where customer_id = $1 and direction = 'inbound' and seen_at is null").bind(customer_id).fetch_one(pool).await?)
}

pub async fn process_inbound(s: &AppState, m: InboundMail) -> Result<Value, (StatusCode, Json<Value>)> {
    let relay = inbound_address(&m.to);
    // Routing order (docs/18 §4): the claim's own address names customer and claim in one step;
    // the customer's old per-customer address falls back to threading and "newest open claim".
    let by_claim: Option<ClaimRow> = sqlx::query_as("select * from claims where lower(reply_address) = $1").bind(&relay).fetch_optional(&s.pool).await.map_err(internal)?;
    let (cust, claim): (CustomerRow, Option<ClaimRow>) = match by_claim {
        Some(cl) => {
            let cust: CustomerRow = sqlx::query_as("select * from customers where id = $1").bind(cl.customer_id).fetch_one(&s.pool).await.map_err(internal)?;
            (cust, Some(cl))
        }
        None => {
            let cust: Option<CustomerRow> = sqlx::query_as("select * from customers where lower(relay_address) = $1").bind(&relay).fetch_optional(&s.pool).await.map_err(internal)?;
            let Some(cust) = cust else { return Err(err(StatusCode::NOT_FOUND, "no claim or customer for this address")) };
            let claim: Option<ClaimRow> = match m.claim_id {
                Some(id) => sqlx::query_as("select * from claims where id = $1 and customer_id = $2").bind(id).bind(cust.id).fetch_optional(&s.pool).await.map_err(internal)?,
                None => match &m.in_reply_to {
                    Some(mid) => sqlx::query_as("select c.* from claims c join mails ml on ml.claim_id = c.id where ml.message_id = $1 and c.customer_id = $2").bind(mid).bind(cust.id).fetch_optional(&s.pool).await.map_err(internal)?,
                    None => sqlx::query_as("select * from claims where customer_id = $1 and status in ('sent','question') order by sent_at desc limit 1").bind(cust.id).fetch_optional(&s.pool).await.map_err(internal)?,
                },
            };
            (cust, claim)
        }
    };
    let lower = m.body.to_lowercase();
    let outcome = if lower.contains("nicht entsprechen") || lower.contains("abgelehnt") || lower.contains("keine entschädigung") {
        MailOutcome::Rejected
    } else if lower.contains("benötigen wir") || lower.contains("rückfrage") || lower.contains("bitte senden sie") {
        MailOutcome::Question
    } else if lower.contains("überwiesen") || lower.contains("entschädigung von") || lower.contains("wird ausgezahlt") {
        MailOutcome::Accepted
    } else if lower.contains("undeliverable") || lower.contains("unzustellbar") || lower.contains("mailer-daemon") {
        MailOutcome::Bounce
    } else {
        MailOutcome::Other
    };
    let amount = extract_amount_cents(&m.body).or_else(|| if outcome == MailOutcome::Accepted { claim.as_ref().map(|c| c.amount_claimed_cents) } else { None });
    // Attachments become uploads of kind 'inbound'; retention deletes them when the claim closes.
    let mut stored: Vec<Value> = Vec::new();
    for (name, ct, bytes) in &m.attachments {
        if bytes.len() > 8 * 1024 * 1024 {
            stored.push(json!({ "name": name, "content_type": ct, "size": bytes.len(), "upload_id": null, "skipped": "max 8 MB" }));
            continue;
        }
        let uid = Uuid::new_v4();
        sqlx::query("insert into uploads (id, customer_id, kind, content_type, bytes) values ($1,$2,'inbound',$3,$4)").bind(uid).bind(cust.id).bind(ct).bind(bytes).execute(&s.pool).await.map_err(internal)?;
        stored.push(json!({ "name": name, "content_type": ct, "size": bytes.len(), "upload_id": uid }));
    }
    let mail: MailRow = sqlx::query_as(
        "insert into mails (id, customer_id, claim_id, direction, message_id, in_reply_to, from_addr, to_addr, subject, body, attachments, outcome, amount_cents, forwarded_at)
         values ($1,$2,$3,'inbound',$4,$5,$6,$7,$8,$9,$10,$11,$12,now()) returning *",
    )
    .bind(Uuid::new_v4())
    .bind(cust.id)
    .bind(claim.as_ref().map(|c| c.id))
    .bind(m.message_id)
    .bind(m.in_reply_to)
    .bind(&m.from)
    .bind(&m.to)
    .bind(&m.subject)
    .bind(&m.body)
    .bind(json!(stored))
    .bind(outcome)
    .bind(if outcome == MailOutcome::Accepted { amount } else { None })
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    if let Some(claim) = &claim {
        let (claim_status, inc_status): (ClaimStatus, Option<IncidentStatus>) = match outcome {
            MailOutcome::Accepted => (ClaimStatus::Accepted, Some(IncidentStatus::Bestaetigt)),
            MailOutcome::Rejected => (ClaimStatus::Rejected, Some(IncidentStatus::Abgelehnt)),
            MailOutcome::Question => (ClaimStatus::Question, None),
            MailOutcome::Bounce => (ClaimStatus::Bounced, None),
            MailOutcome::Other => (claim.status, None),
        };
        sqlx::query("update claims set status = $2, amount_confirmed_cents = coalesce($3, amount_confirmed_cents), closed_at = case when $2 in ('accepted','rejected') then now() else closed_at end where id = $1")
            .bind(claim.id)
            .bind(claim_status)
            .bind(if outcome == MailOutcome::Accepted { amount } else { None })
            .execute(&s.pool)
            .await
            .map_err(internal)?;
        if let Some(st) = inc_status {
            sqlx::query("update incidents set status = $2 where id in (select incident_id from claim_incidents where claim_id = $1)").bind(claim.id).bind(st).execute(&s.pool).await.map_err(internal)?;
            if st == IncidentStatus::Bestaetigt {
                let _ = sqlx::query("insert into badge_awards (customer_id, badge_id) values ($1, 'bestaetigt') on conflict do nothing").bind(cust.id).execute(&s.pool).await;
            }
        }
        rules::audit(&s.pool, "claim", claim.id, Some("sent"), &format!("{:?}", claim_status).to_lowercase(), "inbound mail").await.map_err(internal)?;
        if matches!(claim_status, ClaimStatus::Accepted | ClaimStatus::Rejected) {
            crate::scanner::retain_closed_claim(&s.pool, claim.id).await.map_err(internal)?;
        }
    }
    if let Some(email) = cust.email.as_deref() {
        let fwd_body = format!("Weitergeleitet von deiner Verspätomat-Adresse {}.\nVon: {}\nBetreff: {}\n\n{}", relay, m.from, m.subject, m.body);
        let _ = crate::mail::send(crate::mail::OutgoingMail {
            from: &format!("Verspätomat <{}>", relay),
            to: email,
            bcc: None,
            subject: &format!("Fwd: {}", m.subject),
            body: &fwd_body,
            message_id: &new_message_id(),
            in_reply_to: None,
            attachments: vec![],
        })
        .await;
    }
    s.events.publish(cust.id, "mail", json!({ "claim_id": claim.as_ref().map(|c| c.id), "outcome": outcome }));
    s.events.publish(cust.id, "incident", json!({}));
    Ok(json!({ "mail": mail, "outcome": outcome, "claim_id": claim.map(|c| c.id) }))
}

/// "4,50 EUR" / "19,95 €" → cents.
fn extract_amount_cents(text: &str) -> Option<Cents> {
    let bytes: Vec<char> = text.chars().collect();
    let mut best: Option<Cents> = None;
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i].is_ascii_digit() {
            let start = i;
            while i < bytes.len() && (bytes[i].is_ascii_digit() || bytes[i] == '.') {
                i += 1;
            }
            if i < bytes.len() && bytes[i] == ',' && i + 2 < bytes.len() && bytes[i + 1].is_ascii_digit() && bytes[i + 2].is_ascii_digit() {
                let whole: String = bytes[start..i].iter().filter(|c| c.is_ascii_digit()).collect();
                let frac: String = bytes[i + 1..i + 3].iter().collect();
                let rest: String = bytes[i + 3..(i + 8).min(bytes.len())].iter().collect();
                if rest.contains("EUR") || rest.contains('€') {
                    let v = whole.parse::<i64>().unwrap_or(0) * 100 + frac.parse::<i64>().unwrap_or(0);
                    best = Some(best.map_or(v, |b| b.max(v)));
                }
                i += 3;
            }
        } else {
            i += 1;
        }
    }
    best
}

// ---------------------------------------------------------------------------
// Community
// ---------------------------------------------------------------------------

pub async fn community(State(s): State<AppState>, _c: Customer) -> ApiResult {
    let (minutes, users): (i64, i64) = sqlx::query_as("select coalesce(sum(final_delay_min),0)::bigint, (select count(*) from customers)::bigint from rides where status = 'arrived'").fetch_one(&s.pool).await.map_err(internal)?;
    let (submitted, confirmed): (i64, i64) = sqlx::query_as(
        "select coalesce(sum(amount_cents) filter (where status = 'eingereicht'),0)::bigint, coalesce(sum(amount_cents) filter (where status = 'bestaetigt'),0)::bigint from incidents",
    )
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    let seed = crate::fixtures::Fixtures::embedded().community;
    let ngos = ngo_totals(&s.pool).await.map_err(internal)?;
    Ok(Json(json!({
        "minutes": seed.minutes + minutes,
        "submitted_cents": seed.submitted_cents + submitted,
        "confirmed_cents": seed.confirmed_cents + confirmed,
        "users": seed.users + users,
        "ngos": ngos.into_iter().map(|n| json!({ "id": n["id"], "name": n["name"], "confirmed_cents": n["confirmed_total_cents"], "submitted_cents": n["submitted_total_cents"] })).collect::<Vec<_>>(),
    })))
}

#[derive(Deserialize)]
pub struct BoardQuery {
    #[serde(default)]
    pub scope: Option<String>,
}

/// Seven-day boards: points of location-verified rides finalised in the last seven days, per customer,
/// only customers with `show_on_boards`. Scope `line` = rides on my most frequent line of the last 30 days,
/// `city` = rides starting at a station that shares the first word with my home station, `germany` = all;
/// a scope with nothing to narrow on falls back to all. The list is filled from `board_seed` (marked `seed`)
/// until it holds at least ten entries, and I always appear with `is_me`.
pub async fn boards(State(s): State<AppState>, c: Customer, Query(q): Query<BoardQuery>) -> ApiResult {
    let scope = match q.scope.as_deref() {
        Some("city") => "city",
        Some("germany") => "germany",
        _ => "line",
    };
    let entries = board_entries(&s.pool, &c.0, scope).await.map_err(internal)?;
    let out: Vec<Value> = entries.into_iter().enumerate().map(|(k, (name, points, is_me, seed))| json!({ "rank": k + 1, "name": name, "points": points, "is_me": is_me, "seed": seed })).collect();
    Ok(Json(json!(out)))
}

/// The seven-day board for a scope, sorted: (name, points, is_me, seeded). The customer is always on it;
/// real customers first, seeded rows fill up to ten. `scope` is "line", "city" or "germany".
pub async fn board_entries(pool: &PgPool, c: &CustomerRow, scope: &str) -> anyhow::Result<Vec<(String, i64, bool, bool)>> {
    let now = crate::clock::now();
    let week_ago = now - Duration::days(7);
    let ride_filter = "r.location_verified and r.finalised_at > $1";
    let base = |extra: &str| {
        format!(
            "select c.id, c.nickname, sum(r.points)::bigint as points
             from rides r join customers c on c.id = r.customer_id
             where c.show_on_boards and {ride_filter} {extra}
             group by c.id, c.nickname, c.created_at order by points desc, c.created_at limit 100"
        )
    };
    let mut real: Vec<(Uuid, String, i64)> = Vec::new();
    match scope {
        "line" => {
            if let Some(line) = most_ridden_line(pool, c.id, now).await? {
                real = sqlx::query_as(&base("and r.line = $2")).bind(week_ago).bind(line).fetch_all(pool).await?;
            }
        }
        "city" => {
            let city = c.home_station_name.as_deref().and_then(|n| n.split_whitespace().next()).map(|w| w.to_string());
            if let Some(city) = city {
                real = sqlx::query_as(&base("and split_part(r.from_station_name, ' ', 1) = $2")).bind(week_ago).bind(city).fetch_all(pool).await?;
            }
        }
        _ => {}
    }
    if real.is_empty() {
        real = sqlx::query_as(&base("")).bind(week_ago).fetch_all(pool).await?;
    }
    if !real.iter().any(|(id, _, _)| *id == c.id) {
        let my_points: i64 = sqlx::query_scalar("select coalesce(sum(points),0)::bigint from rides r where r.customer_id = $2 and r.location_verified and r.finalised_at > $1").bind(week_ago).bind(c.id).fetch_one(pool).await?;
        real.push((c.id, c.nickname.clone(), my_points));
    }
    let mut entries: Vec<(String, i64, bool, bool)> = real.into_iter().map(|(id, name, points)| (name, points, id == c.id, false)).collect();
    if entries.len() < 10 {
        let seed: Vec<BoardSeedRow> = sqlx::query_as("select * from board_seed where scope = $1 order by rank").bind(scope).fetch_all(pool).await?;
        for e in seed.iter().take(10 - entries.len()) {
            entries.push((e.name.clone(), e.points as i64, false, true));
        }
    }
    entries.sort_by(|a, b| b.1.cmp(&a.1).then(b.2.cmp(&a.2)));
    Ok(entries)
}

/// The line the customer rode most in the last 30 days.
async fn most_ridden_line(pool: &PgPool, customer_id: Uuid, now: DateTime<Utc>) -> anyhow::Result<Option<String>> {
    Ok(sqlx::query_scalar(
        "select line from rides where customer_id = $1 and finalised_at > $2 group by line order by count(*) desc, max(finalised_at) desc limit 1",
    )
    .bind(customer_id)
    .bind(now - Duration::days(30))
    .fetch_optional(pool)
    .await?)
}

// ---------------------------------------------------------------------------
// Standing: everything the Bahnsteig shows above the fold, in one call (docs/16)
// ---------------------------------------------------------------------------

/// Monday 00:00 Europe/Berlin of the week containing `now`, and the same for the following week.
pub fn week_bounds(now: DateTime<Utc>) -> (DateTime<Utc>, DateTime<Utc>) {
    use chrono::{Datelike, TimeZone};
    let local = now.with_timezone(&chrono_tz::Europe::Berlin);
    let monday = local.date_naive() - Duration::days(local.weekday().num_days_from_monday() as i64);
    let start = chrono_tz::Europe::Berlin.from_local_datetime(&monday.and_hms_opt(0, 0, 0).unwrap()).single().unwrap_or_else(|| chrono_tz::Europe::Berlin.from_utc_datetime(&monday.and_hms_opt(0, 0, 0).unwrap()));
    let next = chrono_tz::Europe::Berlin.from_local_datetime(&(monday + Duration::days(7)).and_hms_opt(0, 0, 0).unwrap()).single().unwrap_or_else(|| chrono_tz::Europe::Berlin.from_utc_datetime(&(monday + Duration::days(7)).and_hms_opt(0, 0, 0).unwrap()));
    (start.with_timezone(&Utc), next.with_timezone(&Utc))
}

/// Level name, next level, points still missing, and progress 0..1 within the current band.
pub fn level_progress(points: i64) -> (&'static str, &'static str, i64, f64) {
    const LEVELS: [(&str, i64); 6] = [
        ("Frischer Fahrgast", 0),
        ("Bahnsteigkante", 60),
        ("Wartehäuschen", 240),
        ("Gleis 7", 600),
        ("Bahnhofsmission", 1500),
        ("Bahnsteig-Buddha", 4000),
    ];
    let idx = LEVELS.iter().rposition(|(_, at)| points >= *at).unwrap_or(0);
    let (name, at) = LEVELS[idx];
    match LEVELS.get(idx + 1) {
        Some((next, next_at)) => {
            let band = (next_at - at).max(1) as f64;
            (name, next, (next_at - points).max(0), ((points - at) as f64 / band).clamp(0.0, 1.0))
        }
        None => (name, name, 0, 1.0),
    }
}

/// One thing the Bahnsteig may point at. Priority: mail, deadline, nachtrag, badge.
#[derive(Debug, Clone, PartialEq)]
pub enum NextThing {
    Mail { claim_id: Option<Uuid>, body: String },
    Deadline { incident_id: Uuid, days_left: i64, body: String },
    Nachtrag,
    Badge { badge_id: String, name: String },
}

impl NextThing {
    fn priority(&self) -> u8 {
        match self {
            NextThing::Mail { .. } => 0,
            NextThing::Deadline { .. } => 1,
            NextThing::Nachtrag => 2,
            NextThing::Badge { .. } => 3,
        }
    }
    pub fn pick(candidates: Vec<NextThing>) -> Option<NextThing> {
        candidates.into_iter().min_by_key(NextThing::priority)
    }
    fn to_json(&self) -> Value {
        match self {
            NextThing::Mail { claim_id, body } => json!({ "kind": "mail", "title": "Post von der Bahn", "body": body, "claim_id": claim_id }),
            NextThing::Deadline { incident_id, days_left, body } => json!({ "kind": "deadline", "title": "Verfällt bald", "body": body, "incident_id": incident_id, "days_left": days_left }),
            NextThing::Nachtrag => json!({ "kind": "nachtrag", "title": "Gestern vergessen einzuchecken?", "body": "Fahrt nachtragen, Punkte gibt es trotzdem." }),
            NextThing::Badge { badge_id, name } => json!({ "kind": "badge", "title": "Neues Abzeichen", "body": name, "badge_id": badge_id }),
        }
    }
}

fn euro_short(cents: i64) -> String {
    format!("{},{:02} €", cents / 100, cents % 100)
}

pub async fn standing(State(s): State<AppState>, c: Customer) -> ApiResult {
    let pool = &s.pool;
    let now = crate::clock::now();
    let today = today();
    let (week_start, next_week) = week_bounds(now);
    let last_week_start = week_start - Duration::days(7);

    // Momentum.
    let (points_total, points_this_week, points_last_week, rides_this_week): (i64, i64, i64, i64) = sqlx::query_as(
        "select coalesce(sum(points),0)::bigint,
                coalesce(sum(points) filter (where finalised_at >= $2 and finalised_at < $3),0)::bigint,
                coalesce(sum(points) filter (where finalised_at >= $4 and finalised_at < $2),0)::bigint,
                count(*) filter (where finalised_at >= $2 and finalised_at < $3)::bigint
         from rides where customer_id = $1 and status in ('arrived','abandoned')",
    )
    .bind(c.0.id)
    .bind(week_start)
    .bind(next_week)
    .bind(last_week_start)
    .fetch_one(pool)
    .await
    .map_err(internal)?;
    let (level_name, next_name, points_to_next, progress) = level_progress(points_total);

    // Money: the desk that is ready, else the one closest to the minimum payout.
    let rows = rules::refresh_statuses(pool, c.0.id, today).await.map_err(internal)?;
    let mut by_desk: BTreeMap<String, Vec<&IncidentRow>> = BTreeMap::new();
    for i in rows.iter().filter(|i| i.open()) {
        by_desk.entry(i.desk.clone()).or_default().push(i);
    }
    let desks: Vec<(String, Cents, bool)> = by_desk.iter().map(|(d, l)| (d.clone(), l.iter().map(|i| i.amount_cents).sum(), rules::bundle_ready(l))).collect();
    let chosen = desks.iter().find(|(_, _, ready)| *ready).or_else(|| desks.iter().max_by_key(|(_, open, _)| *open));
    let (open_cents, ready, ready_desk) = match chosen {
        Some((d, open, ready)) => (*open, *ready, if *ready { Some(d.clone()) } else { None }),
        None => (0, false, None),
    };
    let missing_cents = if ready { 0 } else { (rules::MIN_PAYOUT_CENTS - open_cents).max(0) };
    let ngo_name: Option<String> = sqlx::query_scalar("select name from ngos where id = $1").bind(&c.0.ngo_id).fetch_optional(pool).await.map_err(internal)?;

    // Standing: line board if it has at least five real riders and me on it, else city, else none.
    let mut board = Value::Null;
    for scope in ["line", "city"] {
        let entries = board_entries(pool, &c.0, scope).await.map_err(internal)?;
        let real = entries.iter().filter(|e| !e.3).count();
        let me = entries.iter().position(|e| e.2);
        if let (true, Some(pos)) = (real >= 5, me) {
            let key = match scope {
                "line" => most_ridden_line(pool, c.0.id, now).await.map_err(internal)?.unwrap_or_default(),
                _ => c.0.home_station_name.as_deref().and_then(|n| n.split_whitespace().next()).unwrap_or("").to_string(),
            };
            let gap = if pos == 0 { None } else { Some(entries[pos - 1].1 - entries[pos].1) };
            board = json!({ "scope": scope, "key": key, "rank": pos + 1, "size": entries.len(), "points": entries[pos].1, "gap_to_next": gap });
            break;
        }
    }

    // Community with my share.
    let (minutes, my_confirmed): (i64, i64) = sqlx::query_as(
        "select (select coalesce(sum(final_delay_min),0)::bigint from rides where status = 'arrived'),
                (select coalesce(sum(amount_cents),0)::bigint from incidents where customer_id = $1 and status = 'bestaetigt')",
    )
    .bind(c.0.id)
    .fetch_one(pool)
    .await
    .map_err(internal)?;
    let confirmed_all: i64 = sqlx::query_scalar("select coalesce(sum(amount_cents),0)::bigint from incidents where status = 'bestaetigt'").fetch_one(pool).await.map_err(internal)?;
    let seed = crate::fixtures::Fixtures::embedded().community;

    // Next thing.
    let mut candidates = Vec::new();
    let mail: Option<(Option<Uuid>, Option<String>, Option<i64>)> = sqlx::query_as(
        "select claim_id, outcome::text, amount_cents from mails where customer_id = $1 and direction = 'inbound' and occurred_at >= $2 order by occurred_at desc limit 1",
    )
    .bind(c.0.id)
    .bind(now - Duration::days(7))
    .fetch_optional(pool)
    .await
    .map_err(internal)?;
    let question_claim: Option<Uuid> = sqlx::query_scalar("select id from claims where customer_id = $1 and status = 'question' order by sent_at desc nulls last limit 1").bind(c.0.id).fetch_optional(pool).await.map_err(internal)?;
    if let Some((claim_id, outcome, amount)) = mail {
        let body = match (outcome.as_deref(), amount) {
            (Some("accepted"), Some(cents)) => format!("{} bestätigt", euro_short(cents)),
            (Some("accepted"), None) => "Antrag bestätigt".to_string(),
            (Some("question"), _) => "Rückfrage zum Antrag".to_string(),
            (Some("rejected"), _) => "Antrag abgelehnt".to_string(),
            (Some("bounce"), _) => "Die Mail kam zurück".to_string(),
            _ => "Neue Nachricht an deine Verspätomat-Adresse".to_string(),
        };
        candidates.push(NextThing::Mail { claim_id: claim_id.or(question_claim), body });
    } else if let Some(id) = question_claim {
        candidates.push(NextThing::Mail { claim_id: Some(id), body: "Rückfrage zum Antrag".to_string() });
    }
    if let Some(i) = rows.iter().filter(|i| i.open()).min_by_key(|i| i.ride_date) {
        let days_left = rules::days_until(i.legal_deadline, today);
        if days_left <= rules::WARN_DAYS_BEFORE_DEADLINE {
            candidates.push(NextThing::Deadline { incident_id: i.id, days_left, body: format!("{} vom {} · noch {} Tage", i.line, i.ride_date.format("%d.%m."), days_left.max(0)) });
        }
    }
    let (days_with_rides, rode_yesterday): (i64, bool) = sqlx::query_as(
        "select count(distinct (checked_in_at at time zone 'Europe/Berlin')::date)::bigint,
                bool_or((checked_in_at at time zone 'Europe/Berlin')::date = $3)
         from rides where customer_id = $1 and checked_in_at >= $2",
    )
    .bind(c.0.id)
    .bind(now - Duration::days(14))
    .bind(now.with_timezone(&chrono_tz::Europe::Berlin).date_naive() - Duration::days(1))
    .fetch_one(pool)
    .await
    .map(|(d, y): (i64, Option<bool>)| (d, y.unwrap_or(false)))
    .map_err(internal)?;
    if days_with_rides >= 3 && !rode_yesterday {
        candidates.push(NextThing::Nachtrag);
    }
    let badge: Option<(String, String)> = sqlx::query_as(
        "select b.id, b.name from badge_awards a join badges b on b.id = a.badge_id where a.customer_id = $1 and a.awarded_at >= $2 order by a.awarded_at desc limit 1",
    )
    .bind(c.0.id)
    .bind(now - Duration::days(3))
    .fetch_optional(pool)
    .await
    .map_err(internal)?;
    if let Some((id, name)) = badge {
        candidates.push(NextThing::Badge { badge_id: id, name });
    }
    let next = NextThing::pick(candidates).map(|n| n.to_json()).unwrap_or(Value::Null);

    Ok(Json(json!({
        "points_this_week": points_this_week,
        "points_last_week": points_last_week,
        "unread_mails": unread_mails(pool, c.0.id).await.map_err(internal)?,
        "rides_this_week": rides_this_week,
        "level": { "name": level_name, "next_name": next_name, "points_to_next": points_to_next, "progress": progress },
        "money": { "open_cents": open_cents, "missing_cents": missing_cents, "ready": ready, "ready_desk": ready_desk, "ngo_name": ngo_name },
        "board": board,
        "community": { "minutes_total": seed.minutes + minutes, "my_minutes": points_total, "confirmed_cents": seed.confirmed_cents + confirmed_all, "my_confirmed_cents": my_confirmed },
        "next": next,
    })))
}

#[cfg(test)]
mod standing_tests {
    use super::*;
    use chrono::TimeZone;

    #[test]
    fn week_is_monday_to_monday_in_berlin() {
        // Thursday 10 September 2026 12:00 Berlin (CEST, UTC+2).
        let now = Utc.with_ymd_and_hms(2026, 9, 10, 10, 0, 0).unwrap();
        let (start, next) = week_bounds(now);
        assert_eq!(start, Utc.with_ymd_and_hms(2026, 9, 6, 22, 0, 0).unwrap()); // Mon 7 Sept 00:00 CEST
        assert_eq!(next, Utc.with_ymd_and_hms(2026, 9, 13, 22, 0, 0).unwrap());
        // Sunday 23:30 Berlin still belongs to the same week; Monday 00:30 to the next.
        let (s2, _) = week_bounds(Utc.with_ymd_and_hms(2026, 9, 13, 21, 30, 0).unwrap());
        assert_eq!(s2, start);
        let (s3, _) = week_bounds(Utc.with_ymd_and_hms(2026, 9, 13, 22, 30, 0).unwrap());
        assert_eq!(s3, next);
    }

    #[test]
    fn level_progress_bands() {
        assert_eq!(level_progress(0), ("Frischer Fahrgast", "Bahnsteigkante", 60, 0.0));
        assert_eq!(minute_milestones(999), Vec::<i64>::new());
        assert_eq!(minute_milestones(1000), vec![1000]);
        assert_eq!(minute_milestones(70000), vec![1000, 2000, 4000, 8000, 16000, 32000, 64000]);
        let (name, next, missing, p) = level_progress(1372);
        assert_eq!((name, next, missing), ("Gleis 7", "Bahnhofsmission", 128));
        assert!((p - (772.0 / 900.0)).abs() < 1e-9);
        assert_eq!(level_progress(4000), ("Bahnsteig-Buddha", "Bahnsteig-Buddha", 0, 1.0));
    }

    #[test]
    fn next_thing_priority() {
        let id = Uuid::nil();
        let picked = NextThing::pick(vec![
            NextThing::Badge { badge_id: "x".into(), name: "X".into() },
            NextThing::Nachtrag,
            NextThing::Deadline { incident_id: id, days_left: 3, body: String::new() },
            NextThing::Mail { claim_id: None, body: String::new() },
        ]);
        assert!(matches!(picked, Some(NextThing::Mail { .. })));
        let picked = NextThing::pick(vec![NextThing::Badge { badge_id: "x".into(), name: "X".into() }, NextThing::Nachtrag]);
        assert_eq!(picked, Some(NextThing::Nachtrag));
        assert_eq!(NextThing::pick(vec![]), None);
    }
}

#[cfg(test)]
mod inbound_tests {
    use super::*;

    #[test]
    fn geofence_set_home_first_muted_out_capped() {
        let rows = vec![
            ("a".into(), "A".into(), 50.0, 7.0, 9),
            ("b".into(), "B".into(), 50.1, 7.1, 5),
            ("m".into(), "Muted".into(), 50.2, 7.2, 4),
            ("c".into(), "C".into(), 50.3, 7.3, 1),
        ];
        let home = Some(("b".into(), "B".into(), 50.1, 7.1));
        let muted = vec![MutedStation { id: "m".into(), name: "Muted".into() }];
        let set = geofence_set(rows, home, &muted, 3);
        let ids: Vec<&str> = set.iter().map(|s| s.id.as_str()).collect();
        assert_eq!(ids, vec!["b", "a", "c"]);
        assert_eq!(set[0].checkins, 5);
        let set = geofence_set(vec![("a".into(), "A".into(), 1.0, 2.0, 1)], None, &[], 15);
        assert_eq!(set.len(), 1);
    }

    #[test]
    fn postmark_payload_maps_to_inbound_mail() {
        let v = json!({
            "FromFull": {"Email": "fahrgastrechte@deutschebahn.com", "Name": "Servicecenter Fahrgastrechte"},
            "From": "Servicecenter Fahrgastrechte <fahrgastrechte@deutschebahn.com>",
            "To": "fahrgast-0d8cffc4@users.verspaetomat.de",
            "ToFull": [{"Email": "fahrgast-0d8cffc4@users.verspaetomat.de", "Name": ""}],
            "Subject": "Ihr Antrag",
            "TextBody": "Sehr geehrter Herr Test,\n\n4,50 EUR werden überwiesen.",
            "HtmlBody": "<p>ignored when TextBody exists</p>",
            "MessageID": "73e6d360-66eb-11e1-8e72-a8904824019b",
            "Headers": [{"Name": "In-Reply-To", "Value": "<abc@users.verspaetomat.de>"}, {"Name": "X-Spam-Status", "Value": "No"}],
            "Attachments": [{"Name": "Bescheid.pdf", "ContentType": "application/pdf", "ContentLength": 4, "Content": "JVBERg=="}]
        });
        let m = inbound_from_json(v).unwrap();
        assert_eq!(m.to, "fahrgast-0d8cffc4@users.verspaetomat.de");
        assert!(m.from.contains("deutschebahn.com"));
        assert_eq!(m.subject, "Ihr Antrag");
        assert!(m.body.starts_with("Sehr geehrter"));
        assert_eq!(m.message_id.as_deref(), Some("<73e6d360-66eb-11e1-8e72-a8904824019b>"));
        assert_eq!(m.in_reply_to.as_deref(), Some("<abc@users.verspaetomat.de>"));
        assert_eq!(m.attachments.len(), 1);
        assert_eq!(m.attachments[0].0, "Bescheid.pdf");
        assert_eq!(m.attachments[0].2, b"%PDF");
    }

    #[test]
    fn own_shape_and_raw_email_still_work() {
        let m = inbound_from_json(json!({ "to": "fahrgast-1@users.verspaetomat.de", "from": "a@b.de", "subject": "s", "body": "b" })).unwrap();
        assert_eq!(m.to, "fahrgast-1@users.verspaetomat.de");
        let raw = "From: a@b.de\r\nTo: fahrgast-2@users.verspaetomat.de\r\nSubject: Hallo\r\nMessage-ID: <x@b.de>\r\n\r\nText\r\n";
        let m = inbound_from_json(json!({ "RawEmail": raw, "To": "ignored" })).unwrap();
        assert_eq!(m.to, "fahrgast-2@users.verspaetomat.de");
        assert_eq!(m.subject, "Hallo");
        assert!(inbound_from_json(json!({ "unrelated": 1 })).is_none());
    }
}

#[cfg(test)]
mod claim_address_tests {
    use super::*;

    #[test]
    fn address_names_the_claim_not_the_person() {
        let id = Uuid::parse_str("3d09a883-1111-2222-3333-444444444444").unwrap();
        let a = claim_address_for(id);
        assert!(a.starts_with("antrag-3d09a883@"), "{a}");
        assert!(a.ends_with(&format!("@{}", relay_domain())));
        assert!(!a.contains("fahrgast"));
        assert_ne!(a, relay_address_for(id), "the claim address must not look like a customer address");
    }

    #[test]
    fn inbound_address_is_bare_and_lowercase() {
        assert_eq!(inbound_address("Antrag <Antrag-3D09A883@users.verspaetomat.de>"), "antrag-3d09a883@users.verspaetomat.de");
        assert_eq!(inbound_address("  antrag-1@x.de "), "antrag-1@x.de");
        assert_eq!(inbound_address("<a@b.de>"), "a@b.de");
    }

    /// The routing order of `process_inbound`, as a pure decision: a claim address wins, the
    /// customer address only routes when no claim owns the address.
    fn route(to: &str, claim_addresses: &[&str], customer_addresses: &[&str]) -> &'static str {
        let a = inbound_address(to);
        if claim_addresses.iter().any(|c| c.to_lowercase() == a) {
            "claim"
        } else if customer_addresses.iter().any(|c| c.to_lowercase() == a) {
            "customer"
        } else {
            "unknown"
        }
    }

    #[test]
    fn routing_prefers_the_claim_address() {
        let claims = ["antrag-3d09a883@users.verspaetomat.de"];
        let customers = ["fahrgast-264c454b@users.verspaetomat.de"];
        assert_eq!(route("Antrag <antrag-3d09a883@users.verspaetomat.de>", &claims, &customers), "claim");
        assert_eq!(route("fahrgast-264c454b@users.verspaetomat.de", &claims, &customers), "customer");
        assert_eq!(route("someone@else.de", &claims, &customers), "unknown");
    }
}
