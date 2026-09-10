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
        "select coalesce(sum(points),0)::bigint, coalesce(sum(points) filter (where finalised_at >= $2),0)::bigint from rides where customer_id = $1 and status = 'arrived'",
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
}

#[derive(Deserialize, serde::Serialize)]
pub struct MutedStation {
    pub id: String,
    pub name: String,
}

pub async fn patch_me(State(s): State<AppState>, c: Customer, Json(p): Json<MePatch>) -> ApiResult {
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
            muted_stations = coalesce($13, muted_stations)
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
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    Ok(Json(customer_json(&s.pool, &row).await.map_err(internal)?))
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

/// Asked at the first claim. Assigns the relay address the first time.
pub async fn put_personal_data(State(s): State<AppState>, c: Customer, Json(p): Json<PersonalData>) -> ApiResult {
    let relay = c.0.relay_address.clone().unwrap_or_else(|| {
        let short = c.0.id.simple().to_string();
        format!("fahrgast-{}@verspaetomat.de", &short[..8])
    });
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

fn map_operator(ops: &[OperatorRow], agency: &str) -> String {
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
            location_verified, location_lat, location_lon)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19) returning *",
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
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    let _ = sqlx::query("insert into ride_snapshots (ride_id, source, payload) values ($1, 'transitous', $2)").bind(id).bind(json!(t)).execute(&s.pool).await;
    rules::audit(&s.pool, "ride", id, None, "riding", "check-in").await.map_err(internal)?;
    Ok(Json(json!({ "ride": row, "stops": t.stops })))
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
    let created = on_ride_finalised(&s.pool, r.id).await.map_err(internal)?;
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
}

/// Called after a ride is finalised (by the follower or manually): incident, badges.
pub async fn on_ride_finalised(pool: &PgPool, ride_id: Uuid) -> anyhow::Result<Finalised> {
    let r: RideRow = sqlx::query_as("select * from rides where id = $1").bind(ride_id).fetch_one(pool).await?;
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

    // Badges: first hour, short delays, first delay.
    let mut new_badge = None;
    let candidates: Vec<&str> = if delay >= 60 { vec!["stunde", "erste"] } else if (1..10).contains(&delay) { vec!["gegenzug", "erste"] } else if delay > 0 { vec!["erste"] } else { vec![] };
    for b in candidates {
        let inserted: Option<(String,)> = sqlx::query_as("insert into badge_awards (customer_id, badge_id, ride_id) values ($1, $2, $3) on conflict do nothing returning badge_id")
            .bind(r.customer_id)
            .bind(b)
            .bind(r.id)
            .fetch_optional(pool)
            .await?;
        if inserted.is_some() && new_badge.is_none() {
            new_badge = sqlx::query_as::<_, BadgeRow>("select * from badges where id = $1").bind(b).fetch_optional(pool).await?;
        }
    }
    Ok(Finalised { incident, new_badge })
}

pub async fn dismiss(State(s): State<AppState>, c: Customer) -> ApiResult {
    // Acknowledge the arrival summary; abandon a stale ride if any.
    sqlx::query("update rides set dismissed_at = now() where customer_id = $1 and status = 'arrived' and dismissed_at is null").bind(c.0.id).execute(&s.pool).await.map_err(internal)?;
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
    let created = on_ride_finalised(&s.pool, id).await.map_err(internal)?;
    Ok(Json(json!({ "ride": row, "incident": created.incident })))
}

// ---------------------------------------------------------------------------
// Ledger and claims
// ---------------------------------------------------------------------------

pub async fn incidents(State(s): State<AppState>, c: Customer) -> ApiResult {
    let today = today();
    let rows = rules::refresh_statuses(&s.pool, c.0.id, today).await.map_err(internal)?;
    let mut by_desk: BTreeMap<String, Vec<&IncidentRow>> = BTreeMap::new();
    for i in rows.iter().filter(|i| i.status.is_open()) {
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
    let oldest = rows.iter().filter(|i| i.status.is_open()).min_by_key(|i| i.ride_date);
    let confirmed: Cents = rows.iter().filter(|i| i.status == IncidentStatus::Bestaetigt).map(|i| i.amount_cents).sum();
    let submitted: Cents = rows.iter().filter(|i| i.status == IncidentStatus::Eingereicht).map(|i| i.amount_cents).sum();
    let capped: Cents = rows.iter().filter(|i| i.status == IncidentStatus::Gedeckelt).map(|i| i.amount_cents).sum();
    let claims: Vec<ClaimRow> = sqlx::query_as("select * from claims where customer_id = $1 and status <> 'draft' order by sent_at desc nulls last").bind(c.0.id).fetch_all(&s.pool).await.map_err(internal)?;
    Ok(Json(json!({
        "incidents": rows,
        "claims": claims,
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
        .filter(|i| i.status.is_open() && i.desk == d.desk && d.incident_ids.as_ref().map(|ids| ids.contains(&i.id)).unwrap_or(true))
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
    let (Some(name), Some(email), Some(relay)) = (c.0.full_name.clone(), c.0.email.clone(), c.0.relay_address.clone()) else {
        return Err(err(StatusCode::PRECONDITION_FAILED, "personal data required"));
    };
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
    let message_id = format!("<{}@verspaetomat.de>", Uuid::new_v4());
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
}

/// The customer answers a railway's question, through their own relay address.
pub async fn mail_reply(State(s): State<AppState>, c: Customer, Path(id): Path<Uuid>, Json(r): Json<Reply>) -> ApiResult {
    let original: Option<MailRow> = sqlx::query_as("select * from mails where id = $1 and customer_id = $2 and direction = 'inbound'").bind(id).bind(c.0.id).fetch_optional(&s.pool).await.map_err(internal)?;
    let Some(orig) = original else { return Err(err(StatusCode::NOT_FOUND, "inbound mail not found")) };
    let (Some(name), Some(email), Some(relay)) = (c.0.full_name.clone(), c.0.email.clone(), c.0.relay_address.clone()) else {
        return Err(err(StatusCode::PRECONDITION_FAILED, "personal data required"));
    };
    let message_id = format!("<{}@verspaetomat.de>", Uuid::new_v4());
    let sent = crate::mail::send(crate::mail::OutgoingMail {
        from: &format!("{name} <{relay}>"),
        to: &orig.from_addr,
        bcc: Some(&email),
        subject: &format!("Re: {}", orig.subject),
        body: &r.body,
        message_id: &message_id,
        in_reply_to: orig.message_id.as_deref(),
        attachments: vec![],
    })
    .await
    .map_err(|e| err(StatusCode::BAD_GATEWAY, &format!("mail: {e}")))?;
    let dry_run = matches!(sent, crate::mail::SendResult::DryRun);
    let mail: MailRow = sqlx::query_as(
        "insert into mails (id, customer_id, claim_id, direction, message_id, in_reply_to, from_addr, to_addr, bcc_addr, subject, body, dry_run)
         values ($1,$2,$3,'out',$4,$5,$6,$7,$8,$9,$10,$11) returning *",
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
            a.iter().find(|x| x.address().map(|ad| ad.to_lowercase().ends_with("@verspaetomat.de")).unwrap_or(false)).or_else(|| a.first()).and_then(|x| x.address().map(|s| s.to_string()))
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
pub async fn process_inbound(s: &AppState, m: InboundMail) -> Result<Value, (StatusCode, Json<Value>)> {
    let relay = m.to.trim().trim_matches(|ch| ch == '<' || ch == '>').to_lowercase();
    let cust: Option<CustomerRow> = sqlx::query_as("select * from customers where lower(relay_address) = $1").bind(&relay).fetch_optional(&s.pool).await.map_err(internal)?;
    let Some(cust) = cust else { return Err(err(StatusCode::NOT_FOUND, "no customer for this relay address")) };
    let claim: Option<ClaimRow> = match m.claim_id {
        Some(id) => sqlx::query_as("select * from claims where id = $1 and customer_id = $2").bind(id).bind(cust.id).fetch_optional(&s.pool).await.map_err(internal)?,
        None => match &m.in_reply_to {
            Some(mid) => sqlx::query_as("select c.* from claims c join mails ml on ml.claim_id = c.id where ml.message_id = $1 and c.customer_id = $2").bind(mid).bind(cust.id).fetch_optional(&s.pool).await.map_err(internal)?,
            None => sqlx::query_as("select * from claims where customer_id = $1 and status in ('sent','question') order by sent_at desc limit 1").bind(cust.id).fetch_optional(&s.pool).await.map_err(internal)?,
        },
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
            message_id: &format!("<{}@verspaetomat.de>", Uuid::new_v4()),
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
            let line: Option<String> = sqlx::query_scalar(
                "select line from rides where customer_id = $1 and finalised_at > $2 group by line order by count(*) desc, max(finalised_at) desc limit 1",
            )
            .bind(c.0.id)
            .bind(now - Duration::days(30))
            .fetch_optional(&s.pool)
            .await
            .map_err(internal)?;
            if let Some(line) = line {
                real = sqlx::query_as(&base("and r.line = $2")).bind(week_ago).bind(line).fetch_all(&s.pool).await.map_err(internal)?;
            }
        }
        "city" => {
            let city = c.0.home_station_name.as_deref().and_then(|n| n.split_whitespace().next()).map(|w| w.to_string());
            if let Some(city) = city {
                real = sqlx::query_as(&base("and split_part(r.from_station_name, ' ', 1) = $2")).bind(week_ago).bind(city).fetch_all(&s.pool).await.map_err(internal)?;
            }
        }
        _ => {}
    }
    if real.is_empty() {
        real = sqlx::query_as(&base("")).bind(week_ago).fetch_all(&s.pool).await.map_err(internal)?;
    }
    if !real.iter().any(|(id, _, _)| *id == c.0.id) {
        let my_points: i64 = sqlx::query_scalar("select coalesce(sum(points),0)::bigint from rides r where r.customer_id = $2 and r.location_verified and r.finalised_at > $1").bind(week_ago).bind(c.0.id).fetch_one(&s.pool).await.map_err(internal)?;
        real.push((c.0.id, c.0.nickname.clone(), my_points));
    }
    let mut entries: Vec<(String, i64, bool, bool)> = real.into_iter().map(|(id, name, points)| (name, points, id == c.0.id, false)).collect();
    if entries.len() < 10 {
        let seed: Vec<BoardSeedRow> = sqlx::query_as("select * from board_seed where scope = $1 order by rank").bind(scope).fetch_all(&s.pool).await.map_err(internal)?;
        for e in seed.iter().take(10 - entries.len()) {
            entries.push((e.name.clone(), e.points as i64, false, true));
        }
    }
    entries.sort_by(|a, b| b.1.cmp(&a.1).then(b.2.cmp(&a.2)));
    let out: Vec<Value> = entries.into_iter().enumerate().map(|(k, (name, points, is_me, seed))| json!({ "rank": k + 1, "name": name, "points": points, "is_me": is_me, "seed": seed })).collect();
    Ok(Json(json!(out)))
}

#[cfg(test)]
mod inbound_tests {
    use super::*;

    #[test]
    fn postmark_payload_maps_to_inbound_mail() {
        let v = json!({
            "FromFull": {"Email": "fahrgastrechte@deutschebahn.com", "Name": "Servicecenter Fahrgastrechte"},
            "From": "Servicecenter Fahrgastrechte <fahrgastrechte@deutschebahn.com>",
            "To": "fahrgast-0d8cffc4@verspaetomat.de",
            "ToFull": [{"Email": "fahrgast-0d8cffc4@verspaetomat.de", "Name": ""}],
            "Subject": "Ihr Antrag",
            "TextBody": "Sehr geehrter Herr Test,\n\n4,50 EUR werden überwiesen.",
            "HtmlBody": "<p>ignored when TextBody exists</p>",
            "MessageID": "73e6d360-66eb-11e1-8e72-a8904824019b",
            "Headers": [{"Name": "In-Reply-To", "Value": "<abc@verspaetomat.de>"}, {"Name": "X-Spam-Status", "Value": "No"}],
            "Attachments": [{"Name": "Bescheid.pdf", "ContentType": "application/pdf", "ContentLength": 4, "Content": "JVBERg=="}]
        });
        let m = inbound_from_json(v).unwrap();
        assert_eq!(m.to, "fahrgast-0d8cffc4@verspaetomat.de");
        assert!(m.from.contains("deutschebahn.com"));
        assert_eq!(m.subject, "Ihr Antrag");
        assert!(m.body.starts_with("Sehr geehrter"));
        assert_eq!(m.message_id.as_deref(), Some("<73e6d360-66eb-11e1-8e72-a8904824019b>"));
        assert_eq!(m.in_reply_to.as_deref(), Some("<abc@verspaetomat.de>"));
        assert_eq!(m.attachments.len(), 1);
        assert_eq!(m.attachments[0].0, "Bescheid.pdf");
        assert_eq!(m.attachments[0].2, b"%PDF");
    }

    #[test]
    fn own_shape_and_raw_email_still_work() {
        let m = inbound_from_json(json!({ "to": "fahrgast-1@verspaetomat.de", "from": "a@b.de", "subject": "s", "body": "b" })).unwrap();
        assert_eq!(m.to, "fahrgast-1@verspaetomat.de");
        let raw = "From: a@b.de\r\nTo: fahrgast-2@verspaetomat.de\r\nSubject: Hallo\r\nMessage-ID: <x@b.de>\r\n\r\nText\r\n";
        let m = inbound_from_json(json!({ "RawEmail": raw, "To": "ignored" })).unwrap();
        assert_eq!(m.to, "fahrgast-2@verspaetomat.de");
        assert_eq!(m.subject, "Hallo");
        assert!(inbound_from_json(json!({ "unrelated": 1 })).is_none());
    }
}
