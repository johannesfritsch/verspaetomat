//! Journeys (docs/17): a destination, a planned itinerary and legs confirmed one at a time.
//! Passenger rights compensate the delay at the final destination, so the incident is created
//! from the journey when its last leg arrives, not from a leg. The follower keeps finalising
//! legs (rides); `on_leg_finalised` moves the journey on: into `transfer` with a proposal for
//! the next leg (re-planned when the connection was missed), or into `arrived`.

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    Json,
};
use chrono::{DateTime, Duration, Timelike, Utc};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

use crate::auth::{internal, Customer};
use crate::db::rows::*;
use crate::rules;
use crate::train::{Itinerary, PlanLeg, TripInfo};
use crate::AppState;

type ApiResult = Result<Json<Value>, (StatusCode, Json<Value>)>;

fn err(status: StatusCode, msg: &str) -> (StatusCode, Json<Value>) {
    (status, Json(json!({ "error": msg })))
}

/// How long a transfer waits for a confirmation after the proposed leg should have arrived.
pub const TRANSFER_TIMEOUT: Duration = Duration::hours(2);
/// Arrivals in the app are counted with a few minutes of grace; a connection is "missed" when
/// the phone reaches the transfer stop after the next train has (live or planned) left.
pub const CONNECTION_GRACE: Duration = Duration::minutes(0);

// ---------------------------------------------------------------------------
// Pure rules
// ---------------------------------------------------------------------------

/// The connection is missed when the next leg is cancelled or the actual arrival at the transfer
/// stop is later than the next leg's departure (live when known, else planned).
pub fn connection_missed(actual_arrival: DateTime<Utc>, next_departure: DateTime<Utc>, next_cancelled: bool) -> bool {
    next_cancelled || actual_arrival + CONNECTION_GRACE > next_departure
}

/// The delay that counts: actual arrival at the destination against the planned one.
/// A cancelled leg counts as at least 60 minutes.
pub fn journey_delay_min(actual: DateTime<Utc>, planned: DateTime<Utc>, cancelled: bool) -> i64 {
    let d = (actual - planned).num_minutes().max(0);
    if cancelled {
        d.max(60)
    } else {
        d
    }
}

#[derive(Debug, Clone)]
pub struct DestHistory {
    pub station_id: String,
    pub station_name: String,
    pub origin_id: String,
    pub hour: u32,
    pub at: DateTime<Utc>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Predicted {
    pub station_id: String,
    pub station_name: String,
    pub count: i64,
    pub score: f64,
}

/// Rank destinations by frequency, doubled for the same hour (±2 h) and doubled again for the
/// same origin. The current station is never a destination.
pub fn rank_destinations(history: &[DestHistory], from: Option<&str>, hour: u32) -> Vec<Predicted> {
    let mut acc: std::collections::HashMap<&str, Predicted> = std::collections::HashMap::new();
    for h in history {
        if Some(h.station_id.as_str()) == from {
            continue;
        }
        let dh = (h.hour as i64 - hour as i64).rem_euclid(24).min(24 - (h.hour as i64 - hour as i64).rem_euclid(24));
        let mut w = 1.0;
        if dh <= 2 {
            w *= 2.0;
        }
        if from.is_some() && Some(h.origin_id.as_str()) == from {
            w *= 2.0;
        }
        let e = acc.entry(h.station_id.as_str()).or_insert(Predicted { station_id: h.station_id.clone(), station_name: h.station_name.clone(), count: 0, score: 0.0 });
        e.count += 1;
        e.score += w;
    }
    let mut out: Vec<Predicted> = acc.into_values().collect();
    out.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal).then(b.count.cmp(&a.count)).then(a.station_name.cmp(&b.station_name)));
    out
}

// ---------------------------------------------------------------------------
// JSON shapes (docs/17 "JSON")
// ---------------------------------------------------------------------------

pub fn leg_json(l: &PlanLeg) -> Value {
    json!({
        "trip_id": l.trip_id, "line": l.line, "headsign": l.headsign, "operator": l.operator, "category": l.category,
        "from_station_id": l.from_station_id, "from_station_name": l.from_station_name,
        "to_station_id": l.to_station_id, "to_station_name": l.to_station_name,
        "planned_departure": l.planned_departure, "planned_arrival": l.planned_arrival,
        "live_departure": l.live_departure, "live_arrival": l.live_arrival,
        "platform": l.platform, "cancelled": l.cancelled, "delay_min": l.delay_min,
    })
}

fn itinerary_json(it: &Itinerary, preferred: bool) -> Value {
    json!({
        "id": it.id, "preferred": preferred, "transfers": it.transfers, "transfer_stations": it.transfer_stations(),
        "planned_departure": it.planned_departure, "planned_arrival": it.planned_arrival, "live_arrival": it.live_arrival,
        "duration_min": it.duration_min, "legs": it.legs.iter().map(leg_json).collect::<Vec<_>>(),
    })
}

pub fn plan_legs(j: &JourneyRow) -> Vec<PlanLeg> {
    serde_json::from_value(j.plan.clone()).unwrap_or_default()
}

fn next_leg_of(j: &JourneyRow) -> Option<PlanLeg> {
    j.next_leg.as_ref().and_then(|v| serde_json::from_value(v.clone()).ok())
}

/// The journey with its legs merged with the rides that confirmed them.
pub async fn journey_json(pool: &PgPool, j: &JourneyRow) -> anyhow::Result<Value> {
    let rides: Vec<RideRow> = sqlx::query_as("select * from rides where journey_id = $1 order by leg_no").bind(j.id).fetch_all(pool).await?;
    let legs: Vec<Value> = plan_legs(j)
        .iter()
        .enumerate()
        .map(|(i, l)| {
            let leg_no = i as i32 + 1;
            let mut v = leg_json(l);
            let ride = rides.iter().find(|r| r.leg_no == Some(leg_no));
            let status = match ride {
                Some(r) if r.cancelled => "cancelled",
                Some(r) => match r.status {
                    RideStatus::Riding => "riding",
                    RideStatus::Arrived => "arrived",
                    RideStatus::Abandoned => "skipped",
                },
                None if leg_no < j.current_leg => "skipped",
                None => "planned",
            };
            let o = v.as_object_mut().unwrap();
            o.insert("leg_no".into(), json!(leg_no));
            o.insert("ride_id".into(), json!(ride.map(|r| r.id)));
            o.insert("status".into(), json!(status));
            o.insert("actual_arrival".into(), json!(ride.and_then(|r| r.actual_arrival)));
            o.insert("final_delay_min".into(), json!(ride.and_then(|r| r.final_delay_min)));
            if let Some(r) = ride {
                if r.status == RideStatus::Riding {
                    o.insert("delay_min".into(), json!(r.live_delay_min));
                }
            }
            v
        })
        .collect();
    let next = j.next_leg.clone();
    let transfer_station_name = if j.status == JourneyStatus::Transfer {
        rides.iter().filter(|r| r.status == RideStatus::Arrived).max_by_key(|r| r.leg_no).map(|r| if r.cancelled { r.from_station_name.clone() } else { r.exit_station_name.clone() })
    } else {
        None
    };
    Ok(json!({
        "id": j.id, "status": j.status,
        "origin_station_id": j.origin_station_id, "origin_station_name": j.origin_station_name,
        "destination_station_id": j.destination_station_id, "destination_station_name": j.destination_station_name,
        "planned_departure": j.planned_departure, "planned_arrival": j.planned_arrival,
        "actual_arrival": j.actual_arrival, "final_delay_min": j.final_delay_min,
        "missed_connection": j.missed_connection, "incomplete": j.incomplete, "cancelled": j.cancelled, "points": j.points, "ticket": j.ticket,
        "current_leg": j.current_leg, "legs": legs, "next_leg": next,
        "transfer_station_name": transfer_station_name, "transfer_deadline": j.transfer_deadline,
        "created_at": j.created_at, "finalised_at": j.finalised_at,
    }))
}

/// A legacy ride (before journeys existed) shown as a single-leg journey in the history.
fn legacy_ride_as_journey(r: &RideRow) -> Value {
    let leg = json!({
        "trip_id": r.trip_id, "line": r.line, "headsign": r.headsign, "operator": r.operator, "category": r.category,
        "from_station_id": r.from_station_id, "from_station_name": r.from_station_name,
        "to_station_id": r.exit_station_id, "to_station_name": r.exit_station_name,
        "planned_departure": r.planned_departure, "planned_arrival": r.planned_arrival,
        "live_departure": Value::Null, "live_arrival": r.actual_arrival, "platform": Value::Null,
        "cancelled": r.cancelled, "delay_min": r.final_delay_min.unwrap_or(r.live_delay_min),
        "leg_no": 1, "ride_id": r.id, "status": match r.status { RideStatus::Riding => "riding", RideStatus::Arrived => "arrived", RideStatus::Abandoned => "skipped" },
        "actual_arrival": r.actual_arrival, "final_delay_min": r.final_delay_min,
    });
    json!({
        "id": r.id, "status": match r.status { RideStatus::Riding => "riding", RideStatus::Arrived => "arrived", RideStatus::Abandoned => "abandoned" },
        "origin_station_id": r.from_station_id, "origin_station_name": r.from_station_name,
        "destination_station_id": r.exit_station_id, "destination_station_name": r.exit_station_name,
        "planned_departure": r.planned_departure, "planned_arrival": r.planned_arrival,
        "actual_arrival": r.actual_arrival, "final_delay_min": r.final_delay_min,
        "missed_connection": false, "incomplete": false, "cancelled": r.cancelled, "points": r.points, "ticket": r.ticket,
        "current_leg": 1, "legs": [leg], "next_leg": Value::Null, "transfer_station_name": Value::Null, "transfer_deadline": Value::Null,
        "created_at": r.checked_in_at, "finalised_at": r.finalised_at, "legacy": true,
    })
}

/// `journeys/current` payload: the journey, the current (or last) leg with its stops, the proposal.
pub async fn current_payload(s: &AppState, j: &JourneyRow, just_arrived: bool) -> anyhow::Result<Value> {
    let ride: Option<RideRow> = sqlx::query_as("select * from rides where journey_id = $1 order by leg_no desc limit 1").bind(j.id).fetch_optional(&s.pool).await?;
    let mut stops = json!([]);
    let mut eta = None;
    if let Some(r) = &ride {
        if r.status == RideStatus::Riding {
            stops = match s.train.trip(&r.trip_id).await {
                Ok(t) => json!(t.stops),
                Err(_) => {
                    let snap: Option<Value> = sqlx::query_scalar("select payload from ride_snapshots where ride_id = $1 order by fetched_at desc limit 1").bind(r.id).fetch_optional(&s.pool).await?;
                    snap.and_then(|p| p.get("stops").cloned()).unwrap_or(json!([]))
                }
            };
            eta = Some(r.planned_arrival + Duration::minutes(r.live_delay_min as i64));
        } else {
            eta = r.actual_arrival;
        }
    }
    Ok(json!({
        "journey": journey_json(&s.pool, j).await?,
        "ride": ride,
        "stops": stops,
        "eta": eta,
        "next_leg": j.next_leg,
        "just_arrived": just_arrived,
        "claim_from_minute": 60,
    }))
}

// ---------------------------------------------------------------------------
// Creating journeys and legs
// ---------------------------------------------------------------------------

fn find_stop<'a>(t: &'a TripInfo, id: &str, name: &str) -> Option<(usize, &'a crate::train::TripStop)> {
    t.find_stop(Some(id), name)
}

/// A leg description from a live trip and its two stops (both must be on the trip, in order).
fn leg_from_trip(t: &TripInfo, ops: &[OperatorRow], from_id: &str, from_name: &str, to_id: &str, to_name: &str) -> Result<PlanLeg, String> {
    let (fi, from) = find_stop(t, from_id, from_name).ok_or_else(|| format!("{from_name} liegt nicht auf diesem Zug"))?;
    let (ti, to) = find_stop(t, to_id, to_name).ok_or_else(|| format!("{to_name} liegt nicht auf diesem Zug"))?;
    if ti <= fi {
        return Err(format!("{to_name} liegt vor {from_name}"));
    }
    let planned_departure = from.scheduled_departure.or(from.scheduled_arrival).ok_or("keine Abfahrtszeit")?;
    let planned_arrival = to.scheduled_arrival.or(to.scheduled_departure).ok_or("keine Ankunftszeit")?;
    let live_arrival = to.live_arrival;
    Ok(PlanLeg {
        trip_id: t.trip_id.clone(),
        line: t.line.clone(),
        train_number: t.train_number.clone(),
        headsign: t.headsign.clone(),
        agency_name: t.agency_name.clone(),
        operator: crate::handlers::map_operator(ops, &t.agency_name),
        category: t.category,
        mode: t.mode.clone(),
        from_station_id: from.stop_id.clone().unwrap_or_else(|| from_id.to_string()),
        from_station_name: from.name.clone(),
        to_station_id: to.stop_id.clone().unwrap_or_else(|| to_id.to_string()),
        to_station_name: to.name.clone(),
        planned_departure,
        planned_arrival,
        live_departure: from.live_departure,
        live_arrival,
        platform: None,
        cancelled: t.cancelled || to.cancelled || from.cancelled,
        realtime: t.realtime,
        delay_min: live_arrival.map(|a| (a - planned_arrival).num_minutes()).unwrap_or(0),
    })
}

fn row_category(c: crate::train::TrainCategory) -> TrainCategory {
    match c {
        crate::train::TrainCategory::S => TrainCategory::S,
        crate::train::TrainCategory::Rb => TrainCategory::Rb,
        crate::train::TrainCategory::Re => TrainCategory::Re,
        crate::train::TrainCategory::Fern => TrainCategory::Fern,
        crate::train::TrainCategory::Bus => TrainCategory::Bus,
    }
}

#[derive(Deserialize)]
pub struct LegRef {
    pub trip_id: String,
    pub from_station_id: String,
    pub to_station_id: String,
    #[serde(default)]
    pub from_station_name: Option<String>,
    #[serde(default)]
    pub to_station_name: Option<String>,
}

#[derive(Deserialize)]
pub struct CreateJourney {
    pub from_station_id: String,
    pub from_station_name: String,
    pub to_station_id: String,
    pub to_station_name: String,
    pub legs: Vec<LegRef>,
    #[serde(default)]
    pub ticket: Option<TicketType>,
    #[serde(default)]
    pub location: Option<crate::handlers::LocationFix>,
    #[serde(default)]
    pub from_lat: Option<f64>,
    #[serde(default)]
    pub from_lon: Option<f64>,
}

/// Insert the ride row for one leg of a journey.
#[allow(clippy::too_many_arguments)]
async fn insert_leg_ride(
    pool: &PgPool,
    customer: &CustomerRow,
    journey: &JourneyRow,
    leg: &PlanLeg,
    leg_no: i32,
    is_last: bool,
    trip: &TripInfo,
    location: Option<&crate::handlers::LocationFix>,
    from_lat: Option<f64>,
    from_lon: Option<f64>,
) -> anyhow::Result<RideRow> {
    let id = Uuid::new_v4();
    let row: RideRow = sqlx::query_as(
        "insert into rides (id, customer_id, trip_id, line, headsign, operator, category, from_station_id, from_station_name,
            exit_station_id, exit_station_name, planned_departure, planned_arrival, ticket, live_delay_min, cancelled,
            location_verified, location_lat, location_lon, from_lat, from_lon, journey_id, leg_no, transfer_station_id, transfer_station_name)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25) returning *",
    )
    .bind(id)
    .bind(customer.id)
    .bind(&leg.trip_id)
    .bind(&leg.line)
    .bind(&leg.headsign)
    .bind(&leg.operator)
    .bind(row_category(leg.category))
    .bind(&leg.from_station_id)
    .bind(&leg.from_station_name)
    .bind(&leg.to_station_id)
    .bind(&leg.to_station_name)
    .bind(leg.planned_departure)
    .bind(leg.planned_arrival)
    .bind(journey.ticket)
    .bind(leg.delay_min as i32)
    .bind(leg.cancelled)
    .bind(location.is_some())
    .bind(location.map(|l| l.lat))
    .bind(location.map(|l| l.lon))
    .bind(from_lat)
    .bind(from_lon)
    .bind(journey.id)
    .bind(leg_no)
    .bind(if is_last { None } else { Some(&leg.to_station_id) })
    .bind(if is_last { None } else { Some(&leg.to_station_name) })
    .fetch_one(pool)
    .await?;
    let _ = sqlx::query("insert into ride_snapshots (ride_id, source, payload) values ($1, 'transitous', $2)").bind(id).bind(json!(trip)).execute(pool).await;
    rules::audit(pool, "ride", id, None, "riding", if leg_no == 1 { "check-in" } else { "leg confirmed" }).await?;
    Ok(row)
}

/// The legacy single-train check-in creates a journey around its ride, so the ledger has one path.
pub async fn create_single_leg(pool: &PgPool, ride: &RideRow, trip: &TripInfo) -> anyhow::Result<JourneyRow> {
    let leg = PlanLeg {
        trip_id: ride.trip_id.clone(),
        line: ride.line.clone(),
        train_number: trip.train_number.clone(),
        headsign: ride.headsign.clone(),
        agency_name: trip.agency_name.clone(),
        operator: ride.operator.clone(),
        category: trip.category,
        mode: trip.mode.clone(),
        from_station_id: ride.from_station_id.clone(),
        from_station_name: ride.from_station_name.clone(),
        to_station_id: ride.exit_station_id.clone(),
        to_station_name: ride.exit_station_name.clone(),
        planned_departure: ride.planned_departure,
        planned_arrival: ride.planned_arrival,
        live_departure: None,
        live_arrival: None,
        platform: None,
        cancelled: ride.cancelled,
        realtime: trip.realtime,
        delay_min: ride.live_delay_min as i64,
    };
    let legs = json!([leg]);
    let j: JourneyRow = sqlx::query_as(
        "insert into journeys (id, customer_id, origin_station_id, origin_station_name, destination_station_id, destination_station_name,
            itinerary, plan, planned_departure, planned_arrival, ticket)
         values ($1,$2,$3,$4,$5,$6,$7,$7,$8,$9,$10) returning *",
    )
    .bind(Uuid::new_v4())
    .bind(ride.customer_id)
    .bind(&ride.from_station_id)
    .bind(&ride.from_station_name)
    .bind(&ride.exit_station_id)
    .bind(&ride.exit_station_name)
    .bind(&legs)
    .bind(ride.planned_departure)
    .bind(ride.planned_arrival)
    .bind(ride.ticket)
    .fetch_one(pool)
    .await?;
    sqlx::query("update rides set journey_id = $2, leg_no = 1 where id = $1").bind(ride.id).bind(j.id).execute(pool).await?;
    Ok(j)
}

async fn open_journey(pool: &PgPool, customer: Uuid) -> anyhow::Result<Option<JourneyRow>> {
    Ok(sqlx::query_as("select * from journeys where customer_id = $1 and status in ('riding','transfer') order by created_at desc limit 1").bind(customer).fetch_optional(pool).await?)
}

/// `POST /v1/journeys`
pub async fn create(State(s): State<AppState>, c: Customer, Json(b): Json<CreateJourney>) -> ApiResult {
    if b.legs.is_empty() {
        return Err(err(StatusCode::BAD_REQUEST, "legs must not be empty"));
    }
    if open_journey(&s.pool, c.0.id).await.map_err(internal)?.is_some() {
        return Err(err(StatusCode::CONFLICT, "already on a journey; finish it first"));
    }
    let riding: bool = sqlx::query_scalar("select exists(select 1 from rides where customer_id = $1 and status = 'riding')").bind(c.0.id).fetch_one(&s.pool).await.map_err(internal)?;
    if riding {
        return Err(err(StatusCode::CONFLICT, "already riding; arrive or dismiss first"));
    }
    let ops: Vec<OperatorRow> = sqlx::query_as("select * from operators").fetch_all(&s.pool).await.map_err(internal)?;
    // Re-read every trip: the snapshot is what the timetable promises now, not what the app cached.
    let mut legs: Vec<PlanLeg> = Vec::with_capacity(b.legs.len());
    let mut trips: Vec<TripInfo> = Vec::with_capacity(b.legs.len());
    for (i, l) in b.legs.iter().enumerate() {
        let t = s.train.trip(&l.trip_id).await.map_err(|e| err(StatusCode::NOT_FOUND, &format!("trip {}: {e}", l.trip_id)))?;
        let from_name = if i == 0 { b.from_station_name.as_str() } else { l.from_station_name.as_deref().unwrap_or("") };
        let to_name = if i == b.legs.len() - 1 { b.to_station_name.as_str() } else { l.to_station_name.as_deref().unwrap_or("") };
        let leg = leg_from_trip(&t, &ops, &l.from_station_id, from_name, &l.to_station_id, to_name).map_err(|m| err(StatusCode::BAD_REQUEST, &m))?;
        legs.push(leg);
        trips.push(t);
    }
    let first = legs.first().unwrap();
    let last = legs.last().unwrap();
    let ticket = b.ticket.unwrap_or(c.0.ticket);
    let itinerary = json!(legs);
    let j: JourneyRow = sqlx::query_as(
        "insert into journeys (id, customer_id, origin_station_id, origin_station_name, destination_station_id, destination_station_name,
            itinerary, plan, planned_departure, planned_arrival, ticket)
         values ($1,$2,$3,$4,$5,$6,$7,$7,$8,$9,$10) returning *",
    )
    .bind(Uuid::new_v4())
    .bind(c.0.id)
    // The chosen stations (station-level ids), not the legs' platform-level stop ids.
    .bind(&b.from_station_id)
    .bind(if b.from_station_name.is_empty() { &first.from_station_name } else { &b.from_station_name })
    .bind(&b.to_station_id)
    .bind(if b.to_station_name.is_empty() { &last.to_station_name } else { &b.to_station_name })
    .bind(&itinerary)
    .bind(first.planned_departure)
    .bind(last.planned_arrival)
    .bind(ticket)
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    insert_leg_ride(&s.pool, &c.0, &j, first, 1, legs.len() == 1, &trips[0], b.location.as_ref(), b.from_lat, b.from_lon).await.map_err(internal)?;
    rules::audit(&s.pool, "journey", j.id, None, "riding", "check-in").await.map_err(internal)?;
    s.events.publish(c.0.id, "journey", json!({ "journey_id": j.id, "status": "riding", "transfer": false, "arrived": false, "finished": false, "missed_connection": false, "final_delay_min": Value::Null, "incident": Value::Null, "next_leg": Value::Null }));
    Ok(Json(current_payload(&s, &j, false).await.map_err(internal)?))
}

/// `GET /v1/journeys/current`
pub async fn current(State(s): State<AppState>, c: Customer) -> ApiResult {
    if let Some(j) = open_journey(&s.pool, c.0.id).await.map_err(internal)? {
        return Ok(Json(current_payload(&s, &j, false).await.map_err(internal)?));
    }
    let last: Option<JourneyRow> = sqlx::query_as("select * from journeys where customer_id = $1 and status = 'arrived' and dismissed_at is null and finalised_at > now() - interval '2 hours' order by finalised_at desc limit 1")
        .bind(c.0.id)
        .fetch_optional(&s.pool)
        .await
        .map_err(internal)?;
    match last {
        Some(j) => Ok(Json(current_payload(&s, &j, true).await.map_err(internal)?)),
        None => Err(err(StatusCode::NOT_FOUND, "no journey in progress")),
    }
}

/// `GET /v1/journeys`: newest first; rides from before journeys existed appear as single-leg journeys.
pub async fn list(State(s): State<AppState>, c: Customer) -> ApiResult {
    let rows: Vec<JourneyRow> = sqlx::query_as("select * from journeys where customer_id = $1 order by created_at desc limit 200").bind(c.0.id).fetch_all(&s.pool).await.map_err(internal)?;
    let mut out = Vec::with_capacity(rows.len());
    for j in &rows {
        out.push((j.created_at, journey_json(&s.pool, j).await.map_err(internal)?));
    }
    let legacy: Vec<RideRow> = sqlx::query_as("select * from rides where customer_id = $1 and journey_id is null and nachtrag = false order by checked_in_at desc limit 200").bind(c.0.id).fetch_all(&s.pool).await.map_err(internal)?;
    for r in &legacy {
        out.push((r.checked_in_at, legacy_ride_as_journey(r)));
    }
    out.sort_by(|a, b| b.0.cmp(&a.0));
    Ok(Json(json!(out.into_iter().map(|(_, v)| v).collect::<Vec<_>>())))
}

#[derive(Deserialize)]
pub struct PlanQuery {
    pub from: String,
    pub to: String,
    #[serde(default)]
    pub time: Option<DateTime<Utc>>,
    #[serde(default)]
    pub first_trip: Option<String>,
}

/// `GET /v1/journeys/plan`
pub async fn plan(State(s): State<AppState>, _c: Customer, Query(q): Query<PlanQuery>) -> ApiResult {
    let time = q.time.unwrap_or_else(crate::clock::now);
    let mut its = s.train.plan(&q.from, &q.to, time, 4).await.map_err(|e| err(StatusCode::BAD_GATEWAY, &format!("plan: {e}")))?;
    if let Some(ft) = &q.first_trip {
        its.retain(|it| it.legs.first().map(|l| &l.trip_id == ft).unwrap_or(false));
    }
    let now = crate::clock::now();
    let preferred = its.iter().position(|it| it.legs.first().map(|l| l.live_departure.unwrap_or(l.planned_departure) >= now).unwrap_or(false)).or(if its.is_empty() { None } else { Some(0) });
    let from_name = its.first().and_then(|it| it.legs.first()).map(|l| l.from_station_name.clone()).unwrap_or_default();
    let to_name = its.first().and_then(|it| it.legs.last()).map(|l| l.to_station_name.clone()).unwrap_or_default();
    Ok(Json(json!({
        "from": { "id": q.from, "name": from_name },
        "to": { "id": q.to, "name": to_name },
        "itineraries": its.iter().enumerate().map(|(i, it)| itinerary_json(it, Some(i) == preferred)).collect::<Vec<_>>(),
    })))
}

#[derive(Deserialize)]
pub struct DestQuery {
    #[serde(default)]
    pub from: Option<String>,
}

/// `GET /v1/me/destinations`
pub async fn destinations(State(s): State<AppState>, c: Customer, Query(q): Query<DestQuery>) -> ApiResult {
    let rows: Vec<(String, String, String, DateTime<Utc>)> = sqlx::query_as(
        "select destination_station_id, destination_station_name, origin_station_id, created_at from journeys where customer_id = $1 and status <> 'abandoned'
         union all
         select exit_station_id, exit_station_name, from_station_id, checked_in_at from rides where customer_id = $1 and journey_id is null and nachtrag = false
         order by 4 desc limit 500",
    )
    .bind(c.0.id)
    .fetch_all(&s.pool)
    .await
    .map_err(internal)?;
    let history: Vec<DestHistory> = rows
        .iter()
        .map(|(id, name, origin, at)| DestHistory { station_id: id.clone(), station_name: name.clone(), origin_id: origin.clone(), hour: at.with_timezone(&chrono_tz::Europe::Berlin).hour(), at: *at })
        .collect();
    let now_hour = crate::clock::now().with_timezone(&chrono_tz::Europe::Berlin).hour();
    let ranked = rank_destinations(&history, q.from.as_deref(), now_hour);
    let home = c.0.home_station_id.clone().zip(c.0.home_station_name.clone());
    let away_from_home = match (&home, &q.from) {
        (Some((hid, _)), Some(from)) => hid != from,
        (Some(_), None) => true,
        _ => false,
    };
    let predicted: Vec<Value> = ranked
        .iter()
        .take(3)
        .map(|p| {
            let label = if away_from_home && home.as_ref().map(|(hid, _)| hid == &p.station_id).unwrap_or(false) { Some("Nach Hause") } else { None };
            json!({ "station_id": p.station_id, "station_name": p.station_name, "label": label, "count": p.count })
        })
        .collect();
    let mut recent: Vec<Value> = Vec::new();
    for h in &history {
        if Some(h.station_id.as_str()) == q.from.as_deref() || recent.iter().any(|r| r["station_id"] == h.station_id) {
            continue;
        }
        recent.push(json!({ "station_id": h.station_id, "station_name": h.station_name, "last_at": h.at }));
        if recent.len() == 5 {
            break;
        }
    }
    Ok(Json(json!({
        "home": home.map(|(id, name)| json!({ "station_id": id, "station_name": name })),
        "predicted": predicted,
        "recent": recent,
    })))
}

#[derive(Deserialize)]
pub struct ConfirmLeg {
    #[serde(default)]
    pub trip_id: Option<String>,
}

async fn journey_of(pool: &PgPool, customer: Uuid, id: Uuid) -> Result<JourneyRow, (StatusCode, Json<Value>)> {
    let j: Option<JourneyRow> = sqlx::query_as("select * from journeys where id = $1 and customer_id = $2").bind(id).bind(customer).fetch_optional(pool).await.map_err(internal)?;
    j.ok_or_else(|| err(StatusCode::NOT_FOUND, "no such journey"))
}

/// Confirms the next leg: the proposal, or any trip from the transfer stop that reaches the destination
/// or the next planned transfer. Shared by `POST /v1/journeys/{id}/legs` and `stellwerk confirm`.
pub async fn confirm(s: &AppState, customer: &CustomerRow, j: &JourneyRow, trip_id: Option<&str>) -> Result<JourneyRow, (StatusCode, Json<Value>)> {
    if j.status != JourneyStatus::Transfer {
        return Err(err(StatusCode::CONFLICT, "journey is not waiting at a transfer"));
    }
    let proposal = next_leg_of(j);
    let trip_id = match (trip_id, &proposal) {
        (Some(t), _) => t.to_string(),
        (None, Some(p)) => p.trip_id.clone(),
        (None, None) => return Err(err(StatusCode::BAD_REQUEST, "no proposed leg; give a trip_id")),
    };
    let ops: Vec<OperatorRow> = sqlx::query_as("select * from operators").fetch_all(&s.pool).await.map_err(internal)?;
    let t = s.train.trip(&trip_id).await.map_err(|e| err(StatusCode::NOT_FOUND, &format!("trip: {e}")))?;
    let mut legs = plan_legs(j);
    let idx = j.current_leg as usize; // 0-based index of the next leg in the plan
    let last_ride: Option<RideRow> = sqlx::query_as("select * from rides where journey_id = $1 order by leg_no desc limit 1").bind(j.id).fetch_optional(&s.pool).await.map_err(internal)?;
    let (from_id, from_name) = match &last_ride {
        Some(r) if r.cancelled => (r.from_station_id.clone(), r.from_station_name.clone()),
        Some(r) => (r.exit_station_id.clone(), r.exit_station_name.clone()),
        None => (j.origin_station_id.clone(), j.origin_station_name.clone()),
    };
    let leg = match &proposal {
        Some(p) if p.trip_id == trip_id => leg_from_trip(&t, &ops, &p.from_station_id, &p.from_station_name, &p.to_station_id, &p.to_station_name)
            .or_else(|_| leg_from_trip(&t, &ops, &from_id, &from_name, &p.to_station_id, &p.to_station_name))
            .map_err(|m| err(StatusCode::BAD_REQUEST, &m))?,
        _ => {
            // Any train from here: to the destination if it gets there, else to the next planned transfer.
            let dest = leg_from_trip(&t, &ops, &from_id, &from_name, &j.destination_station_id, &j.destination_station_name);
            match dest {
                Ok(l) => l,
                Err(_) => {
                    let next_transfer = legs.get(idx + 1).map(|n| (n.from_station_id.clone(), n.from_station_name.clone()));
                    match next_transfer {
                        Some((tid, tname)) => leg_from_trip(&t, &ops, &from_id, &from_name, &tid, &tname).map_err(|m| err(StatusCode::BAD_REQUEST, &m))?,
                        None => return Err(err(StatusCode::BAD_REQUEST, "dieser Zug fährt nicht zum Ziel")),
                    }
                }
            }
        }
    };
    // The effective plan: this leg replaces the planned one at this position.
    if idx < legs.len() {
        legs[idx] = leg.clone();
    } else {
        legs.push(leg.clone());
    }
    // A leg that reaches the destination ends the plan there.
    let reaches_destination = leg.to_station_id == j.destination_station_id || crate::train::station_names_match(&leg.to_station_name, &j.destination_station_name);
    if reaches_destination {
        legs.truncate(idx + 1);
    }
    let is_last = idx + 1 == legs.len();
    let leg_no = j.current_leg + 1;
    let updated: JourneyRow = sqlx::query_as(
        "update journeys set status = 'riding', current_leg = $2, next_leg = null, transfer_deadline = null, plan = $3 where id = $1 returning *",
    )
    .bind(j.id)
    .bind(leg_no)
    .bind(json!(legs))
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    let ride = insert_leg_ride(&s.pool, customer, &updated, &leg, leg_no, is_last, &t, None, None, None).await.map_err(internal)?;
    rules::audit(&s.pool, "journey", j.id, Some("transfer"), "riding", "leg confirmed").await.map_err(internal)?;
    s.events.publish(customer.id, "ride", json!({ "ride_id": ride.id, "status": "riding", "live_delay_min": ride.live_delay_min, "journey_id": j.id, "leg_no": leg_no }));
    s.events.publish(customer.id, "journey", json!({ "journey_id": j.id, "status": "riding", "transfer": false, "arrived": false, "finished": false, "missed_connection": updated.missed_connection, "final_delay_min": Value::Null, "incident": Value::Null, "next_leg": Value::Null }));
    Ok(updated)
}

/// `POST /v1/journeys/{id}/legs`
pub async fn confirm_leg(State(s): State<AppState>, c: Customer, Path(id): Path<Uuid>, Json(b): Json<ConfirmLeg>) -> ApiResult {
    let j = journey_of(&s.pool, c.0.id, id).await?;
    let updated = confirm(&s, &c.0, &j, b.trip_id.as_deref()).await?;
    Ok(Json(current_payload(&s, &updated, false).await.map_err(internal)?))
}

#[derive(Deserialize)]
pub struct FinishBody {
    #[serde(default = "default_true")]
    pub arrived: bool,
}

fn default_true() -> bool {
    true
}

/// `POST /v1/journeys/{id}/finish`: "Ich bin da" (arrived) or abort.
pub async fn finish(State(s): State<AppState>, c: Customer, Path(id): Path<Uuid>, Json(b): Json<FinishBody>) -> ApiResult {
    let j = journey_of(&s.pool, c.0.id, id).await?;
    if !matches!(j.status, JourneyStatus::Riding | JourneyStatus::Transfer) {
        return Err(err(StatusCode::CONFLICT, "journey already finished"));
    }
    let riding: Option<RideRow> = sqlx::query_as("select * from rides where journey_id = $1 and status = 'riding' order by leg_no desc limit 1").bind(j.id).fetch_optional(&s.pool).await.map_err(internal)?;
    let now = crate::clock::now();
    let (updated, fin) = if b.arrived {
        if let Some(r) = &riding {
            let delay = r.live_delay_min as i64;
            crate::train::follower::finalise_ride(&s.pool, r.id, delay, r.cancelled, Some(r.planned_arrival + Duration::minutes(delay)), true).await.map_err(internal)?;
        }
        let actual = now;
        finalise_journey(s.clone(), &j, actual, j.planned_arrival, false, false, "finished by the passenger").await.map_err(internal)?
    } else {
        if let Some(r) = &riding {
            sqlx::query("update rides set status = 'abandoned' where id = $1").bind(r.id).execute(&s.pool).await.map_err(internal)?;
        }
        let u: JourneyRow = sqlx::query_as("update journeys set status = 'abandoned', next_leg = null, transfer_deadline = null, finalised_at = now() where id = $1 returning *").bind(j.id).fetch_one(&s.pool).await.map_err(internal)?;
        rules::audit(&s.pool, "journey", j.id, Some("riding"), "abandoned", "aborted by the passenger").await.map_err(internal)?;
        s.events.publish(c.0.id, "journey", json!({ "journey_id": j.id, "status": "abandoned", "transfer": false, "arrived": false, "finished": true, "missed_connection": u.missed_connection, "final_delay_min": Value::Null, "incident": Value::Null, "next_leg": Value::Null }));
        (u, None)
    };
    let _ = fin;
    Ok(Json(journey_json(&s.pool, &updated).await.map_err(internal)?))
}

// ---------------------------------------------------------------------------
// Transitions driven by the follower
// ---------------------------------------------------------------------------

pub struct LegOutcome {
    pub journey: JourneyRow,
    pub incident: Option<IncidentRow>,
    pub new_badge: Option<BadgeRow>,
    /// True when the leg's own arrival push should stay silent (the journey speaks instead).
    pub silent_ride: bool,
}

/// Called after a leg (ride) was finalised. Moves the journey into `transfer` or finalises it.
pub async fn on_leg_finalised(s: &AppState, ride: &RideRow) -> anyhow::Result<LegOutcome> {
    let jid = ride.journey_id.ok_or_else(|| anyhow::anyhow!("ride has no journey"))?;
    let j: JourneyRow = sqlx::query_as("select * from journeys where id = $1").bind(jid).fetch_one(&s.pool).await?;
    if j.status != JourneyStatus::Riding {
        // Already moved on (idempotent callers).
        let inc: Option<IncidentRow> = sqlx::query_as("select * from incidents where journey_id = $1").bind(j.id).fetch_optional(&s.pool).await?;
        return Ok(LegOutcome { silent_ride: plan_legs(&j).len() > 1, journey: j, incident: inc, new_badge: None });
    }
    let legs = plan_legs(&j);
    let leg_no = ride.leg_no.unwrap_or(j.current_leg) as usize;
    let multi = legs.len() > 1;
    let now = crate::clock::now();
    if leg_no < legs.len() {
        // More legs planned: the transfer.
        let planned_next = legs[leg_no].clone();
        let actual = ride.actual_arrival.unwrap_or(now);
        let (transfer_id, transfer_name) = if ride.cancelled { (ride.from_station_id.clone(), ride.from_station_name.clone()) } else { (ride.exit_station_id.clone(), ride.exit_station_name.clone()) };
        // Live view of the planned connection.
        let (next_departure, next_cancelled) = match s.train.trip(&planned_next.trip_id).await {
            Ok(t) => {
                let stop = t.find_stop(Some(planned_next.from_station_id.as_str()), &planned_next.from_station_name).map(|(_, st)| st.clone());
                let dep = stop.as_ref().and_then(|st| st.live_departure.or(st.scheduled_departure)).unwrap_or(planned_next.planned_departure);
                (dep, t.cancelled || stop.map(|st| st.cancelled).unwrap_or(false))
            }
            Err(_) => (planned_next.live_departure.unwrap_or(planned_next.planned_departure), planned_next.cancelled),
        };
        let missed = ride.cancelled || connection_missed(actual, next_departure, next_cancelled);
        let mut proposal = planned_next.clone();
        let mut new_plan = legs.clone();
        let mut reason: Option<&str> = None;
        let mut replanned = false;
        if missed {
            reason = Some(if next_cancelled { "ausfall" } else { "verpasst" });
            match s.train.plan(&transfer_id, &j.destination_station_id, actual + Duration::minutes(1), 3).await {
                Ok(its) if !its.is_empty() => {
                    let it = &its[0];
                    proposal = it.legs[0].clone();
                    new_plan.truncate(leg_no);
                    new_plan.extend(it.legs.iter().cloned());
                    replanned = true;
                }
                Ok(_) => tracing::warn!(journey = %j.id, "transfer: no re-plan found, keeping the planned connection"),
                Err(e) => tracing::warn!(journey = %j.id, error = %e, "transfer: re-plan failed, keeping the planned connection"),
            }
        }
        let mut next_json = leg_json(&proposal);
        next_json["replanned"] = json!(replanned);
        next_json["reason"] = json!(reason);
        let deadline = proposal.live_arrival.unwrap_or(proposal.planned_arrival).max(now) + TRANSFER_TIMEOUT;
        let updated: JourneyRow = sqlx::query_as(
            "update journeys set status = 'transfer', next_leg = $2, transfer_deadline = $3, missed_connection = missed_connection or $4, plan = $5 where id = $1 returning *",
        )
        .bind(j.id)
        .bind(&next_json)
        .bind(deadline)
        .bind(missed)
        .bind(json!(new_plan))
        .fetch_one(&s.pool)
        .await?;
        rules::audit(&s.pool, "journey", j.id, Some("riding"), "transfer", if missed { "connection missed" } else { "at the transfer" }).await?;
        s.events.publish(j.customer_id, "journey", json!({
            "journey_id": j.id, "status": "transfer", "transfer": true, "arrived": false, "finished": false,
            "missed_connection": updated.missed_connection, "final_delay_min": Value::Null, "incident": Value::Null,
            "next_leg": next_json, "transfer_station_name": transfer_name,
        }));
        return Ok(LegOutcome { journey: updated, incident: None, new_badge: None, silent_ride: true });
    }
    // Last leg: the journey arrives.
    let actual = ride.actual_arrival.unwrap_or(now);
    let (updated, fin) = finalise_journey(s.clone(), &j, actual, j.planned_arrival, ride.cancelled, false, if ride.cancelled { "last leg cancelled" } else { "arrived at the destination" }).await?;
    Ok(LegOutcome { journey: updated, incident: fin.as_ref().and_then(|f| f.0.clone()), new_badge: fin.and_then(|f| f.1), silent_ride: multi })
}

/// Journeys waiting at a transfer past their deadline are finalised `incomplete` with what is known.
pub async fn expire_transfers(s: &AppState) -> anyhow::Result<usize> {
    let now = crate::clock::now();
    let due: Vec<JourneyRow> = sqlx::query_as("select * from journeys where status = 'transfer' and transfer_deadline < $1").bind(now).fetch_all(&s.pool).await?;
    let mut n = 0;
    for j in due {
        let last: Option<RideRow> = sqlx::query_as("select * from rides where journey_id = $1 and status = 'arrived' order by leg_no desc limit 1").bind(j.id).fetch_optional(&s.pool).await?;
        let (actual, planned, cancelled) = match &last {
            Some(r) => (r.actual_arrival.unwrap_or(r.planned_arrival), r.planned_arrival, r.cancelled),
            None => (now, j.planned_arrival, false),
        };
        finalise_journey(s.clone(), &j, actual, planned, cancelled, true, "transfer timed out").await?;
        n += 1;
    }
    Ok(n)
}

/// Finalises the journey and creates the incident from its delay. `planned` is the planned arrival
/// the delay is measured against: the destination's, or the last stop's when `incomplete`.
#[allow(clippy::too_many_arguments)]
pub async fn finalise_journey(
    s: AppState,
    j: &JourneyRow,
    actual: DateTime<Utc>,
    planned: DateTime<Utc>,
    cancelled: bool,
    incomplete: bool,
    reason: &str,
) -> anyhow::Result<(JourneyRow, Option<(Option<IncidentRow>, Option<BadgeRow>)>)> {
    let delay = journey_delay_min(actual, planned, cancelled);
    let points = rules::points_for(delay, cancelled, false);
    let updated: JourneyRow = sqlx::query_as(
        "update journeys set status = 'arrived', actual_arrival = $2, final_delay_min = $3, cancelled = cancelled or $4, incomplete = $5, points = $6,
            next_leg = null, transfer_deadline = null, finalised_at = now() where id = $1 and status in ('riding','transfer') returning *",
    )
    .bind(j.id)
    .bind(actual)
    .bind(delay as i32)
    .bind(cancelled)
    .bind(incomplete)
    .bind(points as i32)
    .fetch_one(&s.pool)
    .await?;
    rules::audit(&s.pool, "journey", j.id, Some(if j.status == JourneyStatus::Transfer { "transfer" } else { "riding" }), "arrived", reason).await?;
    // Points live on the last leg's ride so boards and levels keep summing rides; the journey's
    // delay replaces the leg's own points.
    let rides: Vec<RideRow> = sqlx::query_as("select * from rides where journey_id = $1 order by leg_no").bind(j.id).fetch_all(&s.pool).await?;
    let last_ride = rides.iter().filter(|r| r.status == RideStatus::Arrived).max_by_key(|r| r.leg_no).cloned();
    if rides.len() > 1 {
        for r in &rides {
            let p = if Some(r.id) == last_ride.as_ref().map(|l| l.id) { points as i32 } else { 0 };
            sqlx::query("update rides set points = $2 where id = $1").bind(r.id).bind(p).execute(&s.pool).await?;
        }
    }
    let customer: CustomerRow = sqlx::query_as("select * from customers where id = $1").bind(j.customer_id).fetch_one(&s.pool).await?;
    let incident = create_journey_incident(&s.pool, &updated, &customer, &rides, last_ride.as_ref(), actual, planned, delay, cancelled, incomplete).await?;
    let new_badge = match &last_ride {
        Some(r) => crate::handlers::award_badges(&s.pool, j.customer_id, r.id, delay).await?,
        None => None,
    };
    let rows = rules::refresh_statuses(&s.pool, j.customer_id, crate::clock::today()).await?;
    let incident = incident.and_then(|i| rows.into_iter().find(|x| x.id == i.id));
    // A one-leg journey is announced by its ride's push (same words); only multi-leg journeys speak here.
    let silent = plan_legs(&updated).len() <= 1 && !incomplete;
    s.events.publish(j.customer_id, "journey", json!({
        "journey_id": j.id, "status": "arrived", "transfer": false, "arrived": !incomplete, "finished": true,
        "missed_connection": updated.missed_connection, "final_delay_min": delay, "incident": incident.as_ref().map(|i| i.id),
        "next_leg": Value::Null, "incomplete": incomplete, "cancelled": updated.cancelled, "silent": silent,
    }));
    Ok((updated, Some((incident, new_badge))))
}

#[allow(clippy::too_many_arguments)]
async fn create_journey_incident(
    pool: &PgPool,
    j: &JourneyRow,
    c: &CustomerRow,
    rides: &[RideRow],
    last_ride: Option<&RideRow>,
    actual: DateTime<Utc>,
    planned: DateTime<Utc>,
    delay: i64,
    cancelled: bool,
    incomplete: bool,
) -> anyhow::Result<Option<IncidentRow>> {
    let existing: Option<IncidentRow> = sqlx::query_as("select * from incidents where journey_id = $1").bind(j.id).fetch_optional(pool).await?;
    if existing.is_some() {
        return Ok(existing);
    }
    let legs = plan_legs(j);
    // The highest category on the journey decides the season-ticket rate; the operator is the one
    // whose leg was late most (the carrier of the delay), else the first one.
    let category = if rides.iter().any(|r| r.category == TrainCategory::Fern) || legs.iter().any(|l| l.category == crate::train::TrainCategory::Fern) { TrainCategory::Fern } else { rides.first().map(|r| r.category).unwrap_or(TrainCategory::Re) };
    let operator = rides.iter().max_by_key(|r| r.final_delay_min.unwrap_or(0)).or(rides.first()).map(|r| r.operator.clone()).unwrap_or_else(|| legs.first().map(|l| l.operator.clone()).unwrap_or_default());
    let fare = if j.ticket == TicketType::Einzelfahrkarte { Some(rules::DEFAULT_FARE_CENTS) } else { None };
    let Some(amount) = rules::claim_amount_cents(j.ticket, category, delay, c.first_class, fare) else { return Ok(None) };
    let desk: String = sqlx::query_scalar("select desk from operators where name = $1").bind(&operator).fetch_optional(pool).await?.unwrap_or_else(|| "Unbekannt".into());
    let line = rides.iter().map(|r| r.line.clone()).collect::<Vec<_>>().join(" + ");
    let line = if line.is_empty() { legs.first().map(|l| l.line.clone()).unwrap_or_default() } else { line };
    let to_name = match (incomplete, last_ride) {
        (true, Some(r)) => if r.cancelled { r.from_station_name.clone() } else { r.exit_station_name.clone() },
        _ => j.destination_station_name.clone(),
    };
    let legs_ev: Vec<Value> = legs
        .iter()
        .enumerate()
        .map(|(i, l)| {
            let r = rides.iter().find(|r| r.leg_no == Some(i as i32 + 1));
            json!({
                "line": l.line, "from": l.from_station_name, "to": l.to_station_name,
                "planned_departure": l.planned_departure, "planned_arrival": l.planned_arrival,
                "actual_arrival": r.and_then(|r| r.actual_arrival), "delay_min": r.and_then(|r| r.final_delay_min),
                "cancelled": r.map(|r| r.cancelled).unwrap_or(false), "confirmed": r.is_some(),
            })
        })
        .collect();
    let evidence = json!({
        "planned_arrival": planned, "actual_arrival": if cancelled && last_ride.map(|r| r.cancelled).unwrap_or(false) { Value::Null } else { json!(actual) },
        "source": "Live-Daten Transitous", "fetched_at": crate::clock::now(),
        "journey": {
            "id": j.id, "origin": j.origin_station_name, "destination": j.destination_station_name,
            "planned_departure": j.planned_departure, "planned_arrival": j.planned_arrival, "actual_arrival": actual,
            "missed_connection": j.missed_connection, "incomplete": incomplete, "legs": legs_ev,
        },
    });
    let id = Uuid::new_v4();
    let row: IncidentRow = sqlx::query_as(
        "insert into incidents (id, customer_id, ride_id, journey_id, ride_date, line, from_name, to_name, delay_min, amount_cents, ticket, operator, desk, cancelled, self_entered, ngo_id, fare_cents, legal_deadline, evidence)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19) returning *",
    )
    .bind(id)
    .bind(j.customer_id)
    .bind(last_ride.map(|r| r.id))
    .bind(j.id)
    .bind(j.planned_departure.with_timezone(&chrono_tz::Europe::Berlin).date_naive())
    .bind(&line)
    .bind(&j.origin_station_name)
    .bind(&to_name)
    .bind(delay as i32)
    .bind(amount)
    .bind(j.ticket)
    .bind(&operator)
    .bind(&desk)
    .bind(cancelled)
    .bind(false)
    .bind(&c.ngo_id)
    .bind(fare)
    .bind(rules::legal_deadline(j.planned_departure.with_timezone(&chrono_tz::Europe::Berlin).date_naive()))
    .bind(evidence)
    .fetch_one(pool)
    .await?;
    rules::audit(pool, "incident", id, None, "gesammelt", "journey finalised").await?;
    Ok(Some(row))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn t(s: &str) -> DateTime<Utc> {
        s.parse().unwrap()
    }

    #[test]
    fn missed_connection_rule() {
        let dep = t("2026-09-10T16:38:00Z");
        assert!(!connection_missed(t("2026-09-10T16:30:00Z"), dep, false));
        assert!(!connection_missed(dep, dep, false), "arriving as it leaves is not missed by the rule; the follower's grace handles the rest");
        assert!(connection_missed(t("2026-09-10T16:39:00Z"), dep, false));
        assert!(connection_missed(t("2026-09-10T16:00:00Z"), dep, true), "a cancelled connection is missed however early you are");
    }

    #[test]
    fn delay_at_destination() {
        let planned = t("2026-09-10T18:05:00Z");
        assert_eq!(journey_delay_min(t("2026-09-10T19:15:00Z"), planned, false), 70);
        assert_eq!(journey_delay_min(t("2026-09-10T18:00:00Z"), planned, false), 0, "early is not negative");
        assert_eq!(journey_delay_min(t("2026-09-10T18:10:00Z"), planned, true), 60, "a cancellation counts as at least 60");
        assert_eq!(journey_delay_min(t("2026-09-10T19:30:00Z"), planned, true), 85);
    }

    #[test]
    fn leg_json_round_trips() {
        let l = PlanLeg {
            trip_id: "t".into(), line: "RE 10".into(), train_number: None, headsign: "Kleve".into(), agency_name: "NWB".into(), operator: "NordWestBahn".into(),
            category: crate::train::TrainCategory::Re, mode: "REGIONAL_RAIL".into(), from_station_id: "a".into(), from_station_name: "Düsseldorf Hbf".into(),
            to_station_id: "b".into(), to_station_name: "Kleve".into(), planned_departure: t("2026-09-10T16:38:00Z"), planned_arrival: t("2026-09-10T18:05:00Z"),
            live_departure: None, live_arrival: None, platform: Some("3".into()), cancelled: false, realtime: false, delay_min: 0,
        };
        let mut v = leg_json(&l);
        v["replanned"] = json!(true);
        let back: PlanLeg = serde_json::from_value(v).expect("the API leg shape reads back as a PlanLeg");
        assert_eq!(back.trip_id, "t");
        assert_eq!(back.platform.as_deref(), Some("3"));
    }

    #[test]
    fn destination_ranking() {
        let h = |id: &str, origin: &str, hour: u32| DestHistory { station_id: id.into(), station_name: id.to_uppercase(), origin_id: origin.into(), hour, at: Utc::now() };
        let history = vec![
            h("bonn", "koeln", 17), h("bonn", "koeln", 18), h("bonn", "koeln", 17),
            h("ddorf", "koeln", 8), h("ddorf", "koeln", 8), h("ddorf", "koeln", 9), h("ddorf", "bonn", 8),
            h("koeln", "bonn", 7),
        ];
        // Evening from Köln: Bonn wins although Düsseldorf is more frequent overall.
        let r = rank_destinations(&history, Some("koeln"), 17);
        assert_eq!(r[0].station_id, "bonn");
        assert_eq!(r[0].count, 3);
        // Morning from Köln: Düsseldorf wins.
        let r = rank_destinations(&history, Some("koeln"), 8);
        assert_eq!(r[0].station_id, "ddorf");
        // The current station never predicts itself.
        assert!(rank_destinations(&history, Some("bonn"), 17).iter().all(|p| p.station_id != "bonn"));
    }
}
