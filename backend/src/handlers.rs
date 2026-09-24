//! HTTP handlers on Postgres. Thin: parse, call rules, write rows, answer.

use std::collections::{BTreeMap, HashSet};

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
use crate::train::{agency_to_operator, normalise_station_name, same_platform, StationRef, TripInfo};

pub(crate) fn row_category(c: crate::train::TrainCategory) -> TrainCategory {
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
    // The stage and the commit, so a promotion can check that staging runs what it is about to ship.
    Json(json!({ "ok": db_ok, "service": "verspaetomat-api", "db": db_ok, "stage": crate::stage::current().name(), "commit": crate::stage::commit() }))
}

// ---------------------------------------------------------------------------
// Reference data
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct LatLon {
    pub lat: Option<f64>,
    pub lon: Option<f64>,
    /// How many stations to return. Absent means three, which is what every caller before issue
    /// #31 wanted and still gets.
    #[serde(default)]
    pub limit: Option<usize>,
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
    // `limit` is opt-in and defaults to today's three (issue #31). The Bahnsteig re-resolves as
    // the phone moves; the geofence layer, which asks once per umbrella exit, asks for the wider
    // list it needs to size its umbrella. Both are now the same scan and neither costs a request.
    let limit = q.limit.unwrap_or(3).clamp(1, 25);
    // Answered from our own table (issue #37), with no fallback to the live lookup. A fallback
    // would fire hardest in exactly the places a sparse answer is the correct one — Kißlegg,
    // Wangen — and would quietly put the passenger's coordinates back on the wire for the people
    // least able to notice. An empty answer here means the table is wrong, and the table is ours
    // to fix.
    let answer = s.stations().nearby(lat, lon, limit);
    Ok(Json(json!({
        "stations": answer.stations,
        "source": source,
        "label": label,
        "lat": lat,
        "lon": lon,
        // How far this answer looked, and whether it is the whole truth within that distance. The
        // phone sizes its umbrella from the nearest station it did *not* register, so it has to be
        // able to tell "there is nothing further out" from "you only asked for three".
        "search_radius_m": answer.searched_radius_m,
        "complete": answer.complete,
    })))
}

#[derive(Deserialize)]
pub struct SearchQ {
    pub q: String,
}

/// The search field's answer, from our own table (issue #37).
///
/// This had to move with `nearby` rather than after it: the two lists feed the same `Von` row, so
/// a search that still answered with MOTIS ids would put two id namespaces on one screen and the
/// station a passenger picked by hand would be written into the ride under a different kind of id
/// than the one they tapped. It also takes a free-text station name off the wire, which was a
/// small leak nobody had asked for.
pub async fn stations_search(State(s): State<AppState>, _c: Customer, Query(q): Query<SearchQ>) -> ApiResult {
    Ok(Json(json!(s.stations().search(&q.q, SEARCH_RESULTS))))
}

/// How many stations a search offers. The `Von` row shows a short list; more than this is a
/// scroll nobody reads.
const SEARCH_RESULTS: usize = 12;

pub async fn departures(State(s): State<AppState>, _c: Customer, Path(id): Path<String>) -> ApiResult {
    // Ours on the wire, MOTIS' on the way out. An id from a build older than the table is not one
    // of ours and passes through unchanged.
    let deps = s.train.departures(&s.stations().upstream_id(&id), 150).await.map_err(internal)?;
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

/// The public operator directory, each desk carrying the address a claim filed under it really
/// goes to.
///
/// `operators.email` is a column nobody has written since migration 0028 nulled it, and it was
/// serialized here as a permanent null. It answers a question now, and the answer is the routing
/// table's — resolved exactly the way the Senden step and the sender resolve it, catch-all
/// included, so there is still one place that knows a destination. Null where no route exists at
/// all, because then nothing can be sent and there is nothing to name.
pub async fn operators(State(s): State<AppState>) -> ApiResult {
    let mut ops: Vec<OperatorRow> = sqlx::query_as("select * from operators order by name").fetch_all(&s.pool).await.map_err(internal)?;
    // One read of a table that holds a row per desk plus the catch-all, rather than a resolve per
    // row of a six-row directory.
    let routes: Vec<(String, String)> = sqlx::query_as("select desk, to_address from mail_routes").fetch_all(&s.pool).await.map_err(internal)?;
    let fallback = routes.iter().find(|(d, _)| d == DEFAULT_DESK).map(|(_, a)| a.clone());
    for o in &mut ops {
        o.email = routes.iter().find(|(d, _)| *d == o.desk).map(|(_, a)| a.clone()).or_else(|| fallback.clone());
    }
    Ok(Json(json!(ops)))
}

pub async fn ngos(State(s): State<AppState>) -> ApiResult {
    Ok(Json(json!(ngo_totals(&s.pool).await.map_err(internal)?)))
}

async fn ngo_totals(pool: &PgPool) -> anyhow::Result<Vec<Value>> {
    let rows: Vec<(String, String, String, Value, String, String, String, Option<NaiveDate>, i64, i64, i64, i64, Option<String>)> = sqlx::query_as(
        "select n.id, n.name, n.tagline, n.story, n.account_holder, n.iban, n.donation_url, n.last_report,
                n.seed_confirmed_cents, n.seed_submitted_cents,
                coalesce((select sum(coalesce(i.confirmed_cents, i.amount_cents)) from incidents i where i.ngo_id = n.id and i.status = 'bestaetigt'), 0)::bigint,
                coalesce((select sum(amount_cents) from incidents i where i.ngo_id = n.id and i.status = 'eingereicht'), 0)::bigint,
                n.logo
         from ngos n where n.active order by n.name",
    )
    .fetch_all(pool)
    .await?;
    Ok(rows
        .into_iter()
        .map(|(id, name, tagline, story, holder, iban, url, last_report, sc, ss, c, sub, logo)| {
            json!({
                "id": id, "name": name, "tagline": tagline, "story": story, "account_holder": holder, "iban": iban,
                "donation_url": url, "last_report": last_report, "logo": logo,
                "confirmed_total_cents": sc + c, "submitted_total_cents": ss + sub,
            })
        })
        .collect())
}

pub async fn badges(State(s): State<AppState>, c: Customer) -> ApiResult {
    let rows: Vec<(String, String, String, Option<DateTime<Utc>>)> = sqlx::query_as(
        "select b.id, b.name, b.rule, a.awarded_at from badges b left join badge_awards a on a.badge_id = b.id and a.customer_id = $1 order by b.position, b.id",
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

async fn customer_json(pool: &PgPool, flags: &crate::flags::Table, c: &CustomerRow) -> anyhow::Result<Value> {
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
        // #41: the cold-start copy. `/v1/me` is fetched before the geofence config exists, so a
        // phone that has just been installed and targeted gets its overrides here rather than
        // waiting for its first resume. Same map, same replace-not-merge rule.
        "flags": flags.wire_map(Some(c.into())),
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
            "nudge_snooze_until": c.nudge_snooze_until,
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
    Ok(Json(customer_json(&s.pool, &s.flags(), &c.0).await.map_err(internal)?))
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
    /// docs/24 §3: nudges off until this moment, RFC 3339. An empty string lifts the snooze,
    /// the same convention the quiet window uses.
    pub nudge_snooze_until: Option<String>,
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
    /// docs/25 §4: a mute that runs out. Set when three nudges in a row went ignored, so an
    /// app nobody is using stops nudging without anyone having to say so. Null is the
    /// deliberate mute a passenger set by hand, which never expires.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub until: Option<DateTime<Utc>>,
}

impl MutedStation {
    /// Still silent now. An expired automatic mute is no mute at all.
    pub fn active(&self, now: DateTime<Utc>) -> bool {
        match self.until {
            Some(t) => t > now,
            None => true,
        }
    }
}

/// "" clears the snooze; anything else must be an RFC 3339 instant.
fn parse_snooze(s: &Option<String>) -> Result<Option<Option<DateTime<Utc>>>, (StatusCode, Json<Value>)> {
    match s.as_deref() {
        None => Ok(None),
        Some("") => Ok(Some(None)),
        Some(v) => DateTime::parse_from_rfc3339(v)
            .map(|t| Some(Some(t.with_timezone(&Utc))))
            .map_err(|_| err(StatusCode::BAD_REQUEST, "nudge_snooze_until must be RFC 3339")),
    }
}

pub async fn patch_me(State(s): State<AppState>, c: Customer, Json(p): Json<MePatch>) -> ApiResult {
    let quiet_from = parse_quiet(&p.quiet_from)?;
    let quiet_to = parse_quiet(&p.quiet_to)?;
    let snooze = parse_snooze(&p.nudge_snooze_until)?;
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
            quiet_to = case when $17 then $18 else quiet_to end,
            nudge_snooze_until = case when $19 then $20 else nudge_snooze_until end
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
    .bind(snooze.is_some())
    .bind(snooze.flatten())
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    Ok(Json(customer_json(&s.pool, &s.flags(), &row).await.map_err(internal)?))
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
    let all_muted: Vec<MutedStation> = serde_json::from_value(c.0.muted_stations.clone()).unwrap_or_default();
    // An automatic mute that has run out stops hiding its station (docs/25 §4).
    let now = crate::clock::now();
    let muted: Vec<MutedStation> = all_muted.into_iter().filter(|m| m.active(now)).collect();
    let stations = geofence_set(rows, home, &muted, 15);
    // docs/25 §4: nobody should be nudged forever by an app they stopped using.
    let last_checkin: Option<DateTime<Utc>> = sqlx::query_scalar("select max(checked_in_at) from rides where customer_id = $1")
        .bind(c.0.id)
        .fetch_one(&s.pool)
        .await
        .map_err(internal)?;
    let idle = went_idle(last_checkin, c.0.created_at, now);
    // #40's kill switch, now an ordinary flag (#41, migration 0039). The snapshot is in memory
    // and every admin write reloads it, so the one thing that has to work in seconds still does,
    // and the query this used to run is gone — which was the point: at a million installs this
    // handler runs about once per app resume per phone.
    //
    // `Some(…)` rather than `None`: this caller is authenticated, so a rollout buckets on their
    // id and an override for them wins. Reading it globally would hand the wrong answer to
    // exactly the person somebody was targeting.
    let flags = s.flags();
    let stations_local = flags.bool(&crate::flags::STATIONS_LOCAL, Some((&c.0).into()));
    Ok(Json(json!({
        "enabled": nudges_enabled(&c.0) && !idle,
        "idle": idle,
        "last_checkin": last_checkin,
        "stations": stations,
        // #40: false is what builds 64 and 65 do — the native background layer asks
        // /v1/stations/nearby. True arms the .vst on disk (docs/45). Absent means false.
        //
        // It is also in `flags` below, and that is not a mistake: a build that has never heard of
        // the flag map reads this field, and the field is what the native layer is configured
        // from. It stays until no build that reads it is installable.
        "stations_local": stations_local,
        // #41, and the reason it is here rather than only on the public document: the public one
        // is unauthenticated and cacheable, so it can carry nothing that depends on who is
        // asking — which is every per-customer override and every rollout. Without this, both
        // reach the admin view and no phone at all.
        //
        // It is free: `s.flags()` is the in-memory snapshot and `c.0` is the row this request has
        // already loaded, so no query is added to a handler called once per app resume.
        //
        // The client REPLACES its document with this map, never merges key by key. A merge
        // silently loses an override that forces a flag *off* while the global value is on, which
        // is exactly the „take this one person back out of the rollout" case targeting exists for.
        "flags": flags.wire_map(Some((&c.0).into())),
        "quiet_from": c.0.quiet_from.map(|t| t.format("%H:%M").to_string()),
        "quiet_to": c.0.quiet_to.map(|t| t.format("%H:%M").to_string()),
        "snooze_until": c.0.nudge_snooze_until,
    })))
}

/// docs/25 §4: has this account gone quiet for long enough to switch background scanning off?
/// Measured from the last check-in, or from the account's own age when there has never been one
/// — a fresh account gets its thirty days before anything is switched off. Nothing is deleted
/// and no permission is revoked; the app offers it back the next time it is opened.
pub fn went_idle(last_checkin: Option<DateTime<Utc>>, created_at: DateTime<Utc>, now: DateTime<Utc>) -> bool {
    let since = last_checkin.unwrap_or(created_at);
    now - since > Duration::days(IDLE_DAYS_BEFORE_OFF)
}

/// Matches `GeofenceRules.idleDaysBeforeOff` on the phone.
pub const IDLE_DAYS_BEFORE_OFF: i64 = 30;

/// May a station nudge be scheduled at all? Background location and the switch, and no
/// snooze running (docs/24 §3). While a snooze runs the layer is configured `enabled: false`,
/// so nothing is scheduled and no notification can fire.
pub fn nudges_enabled(c: &CustomerRow) -> bool {
    if c.loc_mode != LocationMode::Always || !c.nudge_enabled {
        return false;
    }
    match c.nudge_snooze_until {
        Some(t) => t <= crate::clock::now(),
        None => true,
    }
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
///
/// One platform is one station, even where the feeds give it two ids (`same_platform`): the rows
/// are merged first, so the phone registers one region for Kißlegg instead of two of its twenty,
/// and the check-ins that decide the order are counted together.
pub fn geofence_set(rows: Vec<(String, String, f64, f64, i64)>, home: Option<(String, String, f64, f64)>, muted: &[MutedStation], cap: usize) -> Vec<GeofenceStation> {
    let is_muted = |id: &str| muted.iter().any(|m| m.id == id);
    let merged = merge_platforms(rows);
    let mut out: Vec<GeofenceStation> = Vec::new();
    if let Some((id, name, lat, lon)) = home {
        if !is_muted(&id) {
            // The home station's own row may have been merged into a differently spelled one, so
            // its count is looked up by platform and not by id.
            let checkins = merged
                .iter()
                .find(|r| same_platform(StationRef::at(&r.0, &r.1, r.2, r.3), StationRef::at(&id, &name, lat, lon)))
                .map(|r| r.4)
                .unwrap_or(0);
            out.push(GeofenceStation { id, name, lat, lon, checkins });
        }
    }
    for (id, name, lat, lon, checkins) in merged {
        if out.len() >= cap {
            break;
        }
        // Also by platform: otherwise the home station, listed under the id the customer set,
        // comes back a second time under the id the merge happened to keep.
        if is_muted(&id) || out.iter().any(|o| same_platform(StationRef::at(&o.id, &o.name, o.lat, o.lon), StationRef::at(&id, &name, lat, lon))) {
            continue;
        }
        out.push(GeofenceStation { id, name, lat, lon, checkins });
    }
    out.truncate(cap);
    out
}

/// Fold the rows of one platform into one row: the first spelling wins, because the rows arrive
/// in frequency order and that is the one this customer met most often; the check-ins add up.
fn merge_platforms(rows: Vec<(String, String, f64, f64, i64)>) -> Vec<(String, String, f64, f64, i64)> {
    let mut out: Vec<(String, String, f64, f64, i64)> = Vec::new();
    for (id, name, lat, lon, checkins) in rows {
        match out
            .iter_mut()
            .find(|o| same_platform(StationRef::at(&o.0, &o.1, o.2, o.3), StationRef::at(&id, &name, lat, lon)))
        {
            Some(o) => o.4 += checkins,
            None => out.push((id, name, lat, lon, checkins)),
        }
    }
    // Adding up can change the order: a merged platform may now outrank one that was above it.
    // A stable sort keeps the feed's recency order among equal counts.
    out.sort_by(|a, b| b.4.cmp(&a.4));
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
    Ok(Json(customer_json(&s.pool, &s.flags(), &row).await.map_err(internal)?))
}

/// The device's recovery code. Minted on first ask and then kept.
///
/// This used to mint a new one on every call, which quietly broke the feature it exists for: the
/// twelve words are shown once and written on paper, and opening Einstellungen → Wiederherstellungs-
/// code a month later to check them revoked the words on the paper. The code is the account, so it
/// changes only when somebody asks for it to change (`?rotate=true`), and that answer says plainly
/// that the old words stop working.
pub async fn recovery_code(State(s): State<AppState>, c: Customer, Query(q): Query<RotateQuery>) -> ApiResult {
    // The plaintext is never stored, so an existing code cannot be shown again — only replaced.
    // `has_code` lets the app tell "you already have one, it is on your paper" from "you have none".
    let has: bool = sqlx::query_scalar("select recovery_hash is not null from devices where id = $1")
        .bind(c.0.id)
        .fetch_one(&s.pool)
        .await
        .map_err(internal)?;
    if has && !q.rotate {
        return Ok(Json(json!({ "recovery_code": null, "has_code": true })));
    }
    let code = crate::auth::recovery_code();
    sqlx::query("update devices set recovery_hash = $2 where id = $1").bind(c.0.id).bind(sha256(&code)).execute(&s.pool).await.map_err(internal)?;
    Ok(Json(json!({ "recovery_code": code, "has_code": true, "replaced": has })))
}

#[derive(Deserialize, Default)]
pub struct RotateQuery {
    #[serde(default)]
    pub rotate: bool,
}

pub async fn export_me(State(s): State<AppState>, c: Customer) -> ApiResult {
    Ok(Json(export_json(&s.pool, &c.0).await.map_err(internal)?))
}

/// Everything we hold about one customer, as one document. The app's own export and
/// `stellwerk export` (an access request by mail, legal.dart) both answer with this.
pub async fn export_json(pool: &PgPool, c: &CustomerRow) -> anyhow::Result<Value> {
    let rides: Vec<RideRow> = sqlx::query_as("select * from rides where customer_id = $1 order by checked_in_at desc").bind(c.id).fetch_all(pool).await?;
    let incidents: Vec<IncidentRow> = sqlx::query_as("select * from incidents where customer_id = $1 order by ride_date desc").bind(c.id).fetch_all(pool).await?;
    let claims: Vec<ClaimRow> = sqlx::query_as("select * from claims where customer_id = $1 order by created_at desc").bind(c.id).fetch_all(pool).await?;
    let rows: Vec<MailRow> = sqlx::query_as("select * from mails where customer_id = $1 order by occurred_at desc").bind(c.id).fetch_all(pool).await?;
    // The export is the passenger's right to see what was done with their mail (Art. 15), so it
    // carries what the mail list leaves out: who read each answer, what a model was shown, and
    // what the receiving side verified about the sender.
    let mails: Vec<Value> = rows
        .into_iter()
        .map(|m| {
            let (read_by, reading, sender_auth) = (m.read_by.clone(), m.reading.clone(), m.sender_auth.clone());
            let mut v = json!(m);
            v["read_by"] = json!(read_by);
            v["reading"] = json!(reading);
            v["sender_auth"] = json!(sender_auth);
            v
        })
        .collect();
    Ok(json!({ "customer": c, "rides": rides, "incidents": incidents, "claims": claims, "mails": mails, "exported_at": crate::clock::now() }))
}

/// „Alles löschen": the account and everything that hangs off it, files included (`account.rs`).
pub async fn delete_me(State(s): State<AppState>, c: Customer) -> ApiResult {
    let d = crate::account::delete_customer(&s.pool, c.0.id).await.map_err(internal)?;
    tracing::info!(customer = %c.0.id, rides = d.rides, claims = d.claims, files = d.files, "account deleted by its owner");
    Ok(Json(json!({ "deleted": true, "counts": d })))
}

/// `DELETE /v1/me/personal-data`: name, address, private e-mail and ticket number go. The relay
/// address stays — it is on forms already sent, and the railway's answers still arrive there and
/// show in the app; only the forwarding to a private address stops, because there is none.
pub async fn delete_personal_data(State(s): State<AppState>, c: Customer) -> ApiResult {
    let row: CustomerRow = sqlx::query_as(
        "update customers set full_name = null, postal_address = null, email = null, ticket_number = null where id = $1 returning *",
    )
    .bind(c.0.id)
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    Ok(Json(customer_json(&s.pool, &s.flags(), &row).await.map_err(internal)?))
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


/// The stop on this trip that a station id names — our own id, or a MOTIS id from a build older
/// than the station table (issue #37). The index knows every id the station answers to, because
/// the trip names its stops under whichever feed ran the train.
fn find_stop<'a>(t: &'a TripInfo, ix: &crate::stations::Index, id: &str, name: &str) -> Option<&'a crate::train::TripStop> {
    let n = normalise_station_name(name);
    let ids = ix.candidate_ids(id);
    t.stops
        .iter()
        .find(|st| st.stop_id.as_ref().is_some_and(|sid| ids.iter().any(|i| i == sid)))
        .or_else(|| t.stops.iter().find(|st| normalise_station_name(&st.name) == n))
        .or_else(|| t.stops.iter().find(|st| {
            let a = normalise_station_name(&st.name);
            a.starts_with(&n) || n.starts_with(&a)
        }))
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
    let from = find_stop(&t, &s.stations(), &n.from_station_id, &n.from_station_name).ok_or_else(|| err(StatusCode::BAD_REQUEST, "from station not on this trip"))?;
    let exit = find_stop(&t, &s.stations(), &n.exit_station_id, &n.exit_station_name).ok_or_else(|| err(StatusCode::BAD_REQUEST, "exit stop not on this trip"))?;
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
    let confirmed: Cents = rows.iter().filter(|i| i.status == IncidentStatus::Bestaetigt).map(|i| i.confirmed_cents.unwrap_or(i.amount_cents)).sum();
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
            // What one qualifying journey earns with this customer's ticket, when that is a fixed
            // number at all (issue #30). Null for a Zeitkarte or a single ticket, where it depends
            // on the train or the fare; the app then says it without a number.
            "flat_claim_cents": rules::flat_claim_cents(c.0.ticket, c.0.first_class),
            "delay_minutes_threshold": rules::MIN_DELAY_MINUTES,
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
    // By the PNG magic bytes, not by the declared type: an older app build uploads its
    // signature as application/octet-stream, and that signature still belongs on the form.
    let sig: Option<(Option<String>, Option<Vec<u8>>)> = sqlx::query_as(
        // Newest first: signing again leaves the old attachment in place, and without an order the
        // form could be stamped with the signature that was replaced.
        "select u.path, u.bytes from claim_attachments ca join uploads u on u.id = ca.upload_id
         where ca.claim_id = $1 and ca.label = 'Unterschrift'
         order by u.created_at desc limit 1",
    )
    .bind(claim.id)
    .fetch_optional(pool)
    .await?;
    // The magic bytes are checked here rather than in SQL, because the bytes are a file now. The
    // check itself stays: an older app build uploads its signature as application/octet-stream,
    // and that signature still belongs on the form.
    let signature_png = match sig {
        Some((path, bytes)) => {
            let data = crate::storage::load(path.as_deref(), bytes).await;
            crate::storage::is_png(&data).then_some(data)
        }
        None => None,
    };
    let claim = claim.clone();
    let customer = customer.clone();
    tokio::task::spawn_blocking(move || crate::pdf::render(&crate::pdf::ClaimDocument { claim: &claim, incidents: &incidents, customer: &customer, signature_png })).await?
}

/// `GET /v1/claims/{id}/pdf` — the filled EU form as it stands right now (draft or sent).
pub async fn claim_pdf(State(s): State<AppState>, c: Customer, Path(id): Path<Uuid>) -> Result<Response, (StatusCode, Json<Value>)> {
    let claim: Option<ClaimRow> = sqlx::query_as("select * from claims where id = $1 and customer_id = $2").bind(id).bind(c.0.id).fetch_optional(&s.pool).await.map_err(internal)?;
    let Some(mut claim) = claim else { return Err(err(StatusCode::NOT_FOUND, "claim not found")) };
    // The form names the claim's own address as the one to answer to, so the address has to exist
    // before it is printed. On the paper route this is the only place it ever gets assigned: that
    // claim never goes through `claim_send`, and an address on a printed form that no table knows
    // would drop the railway's answer on the floor.
    claim.reply_address = Some(ensure_claim_address(&s.pool, &claim).await.map_err(internal)?);
    let pdf = render_claim_pdf(&s.pool, &claim, &c.0).await.map_err(internal)?;
    Ok((
        [(header::CONTENT_TYPE, "application/pdf".to_string()), (header::CONTENT_DISPOSITION, format!("inline; filename=\"EU-Antrag-{}.pdf\"", claim.id))],
        pdf,
    )
        .into_response())
}

/// What happens to the draft that is already open at a desk. Coming back to the Antrag names
/// no cases and means "the form I left lying here"; a named selection means exactly those cases,
/// and a different selection is a different form, which wants signing again.
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum DraftAction {
    Resume,
    Rebuild,
}

pub(crate) fn draft_action(held: &[Uuid], wanted: Option<&[Uuid]>, still_open: &HashSet<Uuid>) -> DraftAction {
    // A draft whose cases have meanwhile been discarded or run out of time is no form to return to.
    if held.is_empty() || !held.iter().all(|id| still_open.contains(id)) {
        return DraftAction::Rebuild;
    }
    match wanted {
        None => DraftAction::Resume,
        Some(w) => {
            let mut held: Vec<Uuid> = held.to_vec();
            let mut want: Vec<Uuid> = w.to_vec();
            held.sort();
            held.dedup();
            want.sort();
            want.dedup();
            if held == want {
                DraftAction::Resume
            } else {
                DraftAction::Rebuild
            }
        }
    }
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
    // One open draft per desk. Coming back to the Antrag finds the draft as it was left —
    // with its ticket and its signature — and only a changed selection of cases replaces it,
    // because a form whose cases changed is a different form and wants signing again.
    let existing: Option<ClaimRow> = sqlx::query_as("select * from claims where customer_id = $1 and desk = $2 and status = 'draft' order by created_at desc limit 1")
        .bind(c.0.id)
        .bind(&d.desk)
        .fetch_optional(&s.pool)
        .await
        .map_err(internal)?;
    if let Some(old) = existing {
        let held: Vec<Uuid> = sqlx::query_scalar("select incident_id from claim_incidents where claim_id = $1").bind(old.id).fetch_all(&s.pool).await.map_err(internal)?;
        let still_open: HashSet<Uuid> = rows.iter().filter(|i| i.open() && i.desk == d.desk).map(|i| i.id).collect();
        if draft_action(&held, d.incident_ids.as_deref(), &still_open) == DraftAction::Resume {
            return Ok(Json(draft_json(&s, &c.0, &old, &d.desk).await?));
        }
        sqlx::query("delete from claim_attachments where claim_id = $1").bind(old.id).execute(&s.pool).await.map_err(internal)?;
        sqlx::query("delete from claim_incidents where claim_id = $1").bind(old.id).execute(&s.pool).await.map_err(internal)?;
        sqlx::query("update incidents set claim_id = null where claim_id = $1").bind(old.id).execute(&s.pool).await.map_err(internal)?;
        sqlx::query("delete from claims where id = $1").bind(old.id).execute(&s.pool).await.map_err(internal)?;
        rules::audit(&s.pool, "claim", old.id, Some("draft"), "deleted", "another selection of cases").await.map_err(internal)?;
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
    Ok(Json(draft_json(&s, &c.0, &claim, &d.desk).await?))
}

/// A draft with everything the Antrag screen needs around it: the desk, the passenger's own
/// state, the relay address.
async fn draft_json(s: &AppState, c: &CustomerRow, claim: &ClaimRow, desk: &str) -> Result<Value, (StatusCode, Json<Value>)> {
    let op: Option<OperatorRow> = sqlx::query_as("select * from operators where desk = $1 limit 1").bind(desk).fetch_optional(&s.pool).await.map_err(internal)?;
    let mut v = claim_with_incidents(&s.pool, claim).await.map_err(internal)?;
    v["desk_address"] = json!(op.as_ref().map(|o| o.postal_address.clone()));
    // The address the passenger sees on the Senden step is the address the mail will really go to,
    // read from the same table the sender reads. Not the railway's published desk, not a label —
    // the actual destination. If there is no route, there is no address and nothing can be sent,
    // and the screen says so rather than offering a button that would fail.
    let route = mail_route(&s.pool, desk).await?;
    v["desk_email"] = json!(route.as_ref().map(|r| r.to_address.clone()));
    v["desk_route_label"] = json!(route.as_ref().map(|r| r.label.clone()));
    // `desk_route_live` is deliberately NOT sent, although builds up to (48) read it.
    //
    // I put it back for one deploy on the theory that a missing key reads as false there and makes
    // those builds claim nothing was sent. It does not. In (48) the post-send line comes from
    // `_looksDryRun`, which returns `… || true`, so it says „Testlauf" after every send whatever
    // this server does. What the key really gates there are two warnings *before* sending — „diese
    // Adresse ist eine von uns, nicht die des Eisenbahnunternehmens" — and with the route pointing
    // at our own inbox those are true. Sending `true` deleted two true warnings and, per
    // migration 0028, asserted that the address is the railway's real desk, which it is not.
    // The way to stop (48) lying is to expire it in App Store Connect, not to feed it a constant.
    // True when this desk has no address of its own and the catch-all answered. The app says so on
    // the step that shows the destination, so "nobody set one for this desk yet" is visible rather
    // than silently absorbed (#25). Additive: an older build ignores it.
    v["desk_route_via_default"] = json!(route.as_ref().map(|r| r.via_default).unwrap_or(false));
    // A rehearsal's paper goes where the rehearsal says, not to the railway's published address.
    if let Some(p) = route.as_ref().and_then(|r| r.postal_address.clone()) {
        v["desk_address"] = json!(p);
    }
    v["desk_accepts_email"] = json!(op.as_ref().map(|o| o.accepts_email).unwrap_or(false) && route.is_some());
    v["personal_data_required"] = json!(c.full_name.is_none());
    v["relay_address"] = json!(c.relay_address);
    // The address this one claim answers on — what the mail really leaves from, and what stands in
    // field 5.3.1 of the form. Additive: an older build ignores it and keeps showing the
    // passenger's own relay address, which is the address it has always shown.
    v["claim_reply_address"] = json!(claim.reply_address.clone().unwrap_or_else(|| claim_address_for(claim.id)));
    v["needs_recovery_code"] = json!(sqlx::query_scalar::<_, bool>("select recovery_hash is null from devices where id = $1").bind(c.id).fetch_one(&s.pool).await.map_err(internal)?);
    Ok(v)
}

#[derive(Deserialize)]
pub struct ClaimPatch {
    pub ngo_id: Option<String>,
    pub attachments: Option<Vec<AttachmentRef>>,
}

/// A file on a claim: the upload, and the name it carries on the form and as the file name in
/// the mail to the railway (docs/18).
pub struct AttachmentRef {
    pub upload_id: Uuid,
    pub label: String,
}

/// What an attachment may look like on the wire. Builds up to 1.0.0 (9) send a bare upload id
/// and mean a ticket by it; since then the label travels with it. Both are read, because an
/// older build in TestFlight has to keep working against this server.
impl<'de> Deserialize<'de> for AttachmentRef {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        #[derive(Deserialize)]
        #[serde(untagged)]
        enum Wire {
            Id(Uuid),
            Named {
                upload_id: Uuid,
                #[serde(default)]
                label: Option<String>,
            },
        }
        let (upload_id, label) = match Wire::deserialize(d)? {
            Wire::Id(upload_id) => (upload_id, None),
            Wire::Named { upload_id, label } => (upload_id, label),
        };
        Ok(AttachmentRef {
            upload_id,
            label: label.filter(|l| !l.trim().is_empty()).unwrap_or_else(|| "Ticket".to_string()),
        })
    }
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
        // The tickets are replaced, the signature is not one of them. An app that attaches a
        // ticket after signing — or after coming back to a draft it left — must not take the
        // signature off the form on its way past.
        sqlx::query("delete from claim_attachments where claim_id = $1 and label <> 'Unterschrift'").bind(id).execute(&s.pool).await.map_err(internal)?;
        for a in atts {
            sqlx::query("insert into claim_attachments (claim_id, upload_id, label) select $1, $2, $3 where exists (select 1 from uploads where id = $2 and customer_id = $4) on conflict do nothing")
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

/// What an upload really is. Clients that send no part content type (or the generic
/// `application/octet-stream`) used to land as bytes of unknown kind, and an unknown kind is
/// not a signature the form can print — so the file name and the first bytes get a say.
pub(crate) fn image_content_type(declared: &str, filename: &str, bytes: &[u8]) -> String {
    let declared = declared.trim();
    if declared.starts_with("image/") || declared == "application/pdf" {
        return declared.to_string();
    }
    if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        return "image/png".to_string();
    }
    if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        return "image/jpeg".to_string();
    }
    let lower = filename.to_lowercase();
    if lower.ends_with(".png") {
        return "image/png".to_string();
    }
    if lower.ends_with(".jpg") || lower.ends_with(".jpeg") {
        return "image/jpeg".to_string();
    }
    if declared.is_empty() {
        "application/octet-stream".to_string()
    } else {
        declared.to_string()
    }
}

/// Multipart: fields `kind` (ticket|signature|postal_reply) and `file`.
pub async fn upload(State(s): State<AppState>, c: Customer, mut mp: Multipart) -> ApiResult {
    let mut kind = "ticket".to_string();
    let mut bytes: Option<(String, Vec<u8>)> = None;
    while let Some(field) = mp.next_field().await.map_err(|e| err(StatusCode::BAD_REQUEST, &e.to_string()))? {
        match field.name().unwrap_or("") {
            "kind" => kind = field.text().await.unwrap_or_default(),
            "file" => {
                let ct = field.content_type().unwrap_or("").to_string();
                let filename = field.file_name().unwrap_or("").to_string();
                let data = field.bytes().await.map_err(|e| err(StatusCode::BAD_REQUEST, &e.to_string()))?;
                bytes = Some((image_content_type(&ct, &filename, &data), data.to_vec()));
            }
            _ => {}
        }
    }
    let Some((ct, data)) = bytes else { return Err(err(StatusCode::BAD_REQUEST, "file missing")) };
    if data.len() > MAX_UPLOAD {
        return Err(err(StatusCode::PAYLOAD_TOO_LARGE, "max 8 MB"));
    }
    // Only the kinds the app actually sends. The column had no constraint and the value is
    // load-bearing downstream — attach_ticket selects on kind='ticket', retention on
    // kind='inbound' — so a typo used to store a file that could never be attached to anything.
    if !matches!(kind.as_str(), "ticket" | "signature" | "postal_reply") {
        return Err(err(StatusCode::BAD_REQUEST, "kind must be ticket, signature or postal_reply"));
    }
    let id = Uuid::new_v4();
    let path = crate::storage::put(id, &data).await.map_err(|e| err(StatusCode::INTERNAL_SERVER_ERROR, &format!("storage: {e}")))?;
    sqlx::query("insert into uploads (id, customer_id, kind, content_type, path) values ($1,$2,$3,$4,$5)")
        .bind(id)
        .bind(c.0.id)
        .bind(&kind)
        .bind(&ct)
        .bind(&path)
        .execute(&s.pool)
        .await
        .map_err(|e| {
            // The row is the index; a file without one is unreachable, so do not leave it behind.
            let p = path.clone();
            tokio::spawn(async move { crate::storage::remove(&p).await });
            internal(e)
        })?;
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
    if !op.as_ref().map(|o| o.accepts_email).unwrap_or(false) {
        return Err(err(StatusCode::PRECONDITION_FAILED, "this desk takes no e-mail; use the paper route"));
    }
    // The destination comes from mail_routes and from nowhere else. No fixture seeds that table,
    // no migration inserts into it, and nothing in this repository knows a railway's address — so
    // an address exists only because somebody typed it on this machine (`stellwerk route set`).
    // An empty table means nothing can be sent, which is the correct state for a system that has
    // never been told where to send. This replaces CLAIM_MAIL_REDIRECT, which had to be remembered
    // to be safe and failed open when it was not.
    let Some(route) = mail_route(&s.pool, &claim.desk).await? else {
        return Err(err(
            StatusCode::PRECONDITION_FAILED,
            &format!("no mail route for desk '{}': set one with `stellwerk route set`", claim.desk),
        ));
    };
    let to = route.to_address.clone();
    let incidents: Vec<IncidentRow> = sqlx::query_as("select i.* from incidents i join claim_incidents ci on ci.incident_id = i.id where ci.claim_id = $1 order by i.ride_date").bind(id).fetch_all(&s.pool).await.map_err(internal)?;
    // No rehearsal marker on the face of the mail. There used to be one, because a route could be
    // a stand-in and a stand-in's mail landing in a real inbox must not pass for a claim. Routing
    // has no stand-ins any more: a desk has an address and the mail goes there (#25). What is left
    // is the mail exactly as the Senden step showed it.
    let body = format!(
        "Sehr geehrte Damen und Herren,\n\nanbei mein gesammelter Antrag auf Entschädigung nach VO (EU) 2021/782 (wiederholte Verspätungen, Zeitfahrkarte). Die Einzelfälle sind im Formular unter Punkt 6 aufgeführt.\n\nKontoinhaber: {}\n\nDiese E-Mail wurde über Verspätomat übermittelt, eine Ausfüll- und Weiterleitungshilfe. Antragsteller ist {}.\n\nMit freundlichen Grüßen\n{}",
        claim.account_holder, name, name
    );
    let attachments = json!([
        { "name": "EU-Antrag.pdf", "content_type": "application/pdf", "url": format!("/v1/claims/{}/pdf", claim.id) },
        { "name": "EU-Antrag.txt", "content_type": "text/plain", "text": claim_summary_text(&claim, &incidents, &name) },
    ]);
    let message_id = new_message_id();
    let subject = "Fahrgastrechte: EU-Antragsformular".to_string();
    let summary = claim_summary_text(&claim, &incidents, &name);
    let rows: Vec<(String, String, Option<String>, Option<Vec<u8>>)> = sqlx::query_as(
        "select ca.label, u.content_type, u.path, u.bytes from claim_attachments ca join uploads u on u.id = ca.upload_id where ca.claim_id = $1",
    )
    .bind(id)
    .fetch_all(&s.pool)
    .await
    .map_err(internal)?;
    let mut uploads: Vec<(String, String, Vec<u8>)> = Vec::new();
    for (label, ct, path, bytes) in rows {
        let data = crate::storage::load(path.as_deref(), bytes).await;
        // A file cleared by retention, or one whose volume is not mounted, is skipped rather than
        // mailed as a nameless nothing. The old query had no such guard.
        if data.is_empty() {
            continue;
        }
        uploads.push((attachment_filename(&label, &ct), ct, data));
    }
    uploads.insert(0, ("EU-Antrag.txt".into(), "text/plain".into(), summary.into_bytes()));
    let pdf = render_claim_pdf(&s.pool, &claim, &c.0).await.map_err(|e| err(StatusCode::INTERNAL_SERVER_ERROR, &format!("pdf: {e}")))?;
    uploads.insert(0, ("EU-Antrag.pdf".into(), "application/pdf".into(), pdf));
    // Postmark refuses a message over 10 MB, and every attachment is base64-encoded on the way out,
    // which adds a third. Refusing here costs the passenger a message they can act on; letting it
    // through costs them a 502 after the claim has already been marked sent.
    let total: usize = uploads.iter().map(|(_, _, b)| b.len()).sum();
    if total * 4 / 3 > 9 * 1024 * 1024 {
        return Err(err(StatusCode::PAYLOAD_TOO_LARGE, "attachments too large for one mail"));
    }
    // One behaviour: the claim goes to the address the route names, which is the address the app
    // showed on the Senden step. Nothing here knows about a rehearsal — a walkthrough is something
    // the app does, and it never reaches this handler (#25).
    let sent = crate::mail::send(crate::mail::OutgoingMail {
        from: &format!("{name} <{relay}>"),
        to: &to,
        bcc: Some(&email),
        subject: &subject,
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
    .bind(&subject)
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
/// The largest single upload. A phone photo sanitised by the app lands well under this; the cap is
/// here for everything else. `DefaultBodyLimit` in main.rs is set from it, because axum's own
/// default is 2 MiB and would otherwise reject the request long before this check ran.
/// One row of [`mail_routes`]: where mail for a desk is allowed to go.
pub struct MailRoute {
    pub to_address: String,
    pub label: String,
    pub postal_address: Option<String>,

    /// True when this desk has no route of its own and the catch-all answered instead.
    pub via_default: bool,
}

/// The desk key of the catch-all route: the one every desk without its own falls back to.
///
/// Safe as a reserved value because `mail_routes.desk` is matched against the desk string frozen
/// onto a claim, which comes from `operators.desk`, and no operator can be filed under `*`.
pub const DEFAULT_DESK: &str = "*";

/// The destination for a desk: its own route first, the catch-all second, None if neither exists.
///
/// Every outbound path that could reach a railway goes through here. There is still no environment
/// variable and no address in this repository: a route exists because a person typed it into this
/// database with `stellwerk route set`. What changed is that a desk nobody has thought about yet
/// lands on the catch-all instead of on nothing (#25) — which is one row, in the same table, in the
/// same listing, so the answer to "where does this go" is still one command away.
pub async fn mail_route(pool: &PgPool, desk: &str) -> Result<Option<MailRoute>, (StatusCode, Json<Value>)> {
    // `order by (desk = $2)`: false sorts before true, so the desk's own row wins over the
    // catch-all whenever both exist.
    let row: Option<(String, String, Option<String>, bool)> = sqlx::query_as(
        "select to_address, label, postal_address, desk = $2 as via_default
           from mail_routes where desk = $1 or desk = $2
          order by (desk = $2) limit 1",
    )
    .bind(desk)
    .bind(DEFAULT_DESK)
    .fetch_optional(pool)
    .await
    .map_err(internal)?;
    Ok(row.map(|(to_address, label, postal_address, via_default)| MailRoute {
        to_address,
        label,
        postal_address,
        via_default,
    }))
}

pub const MAX_UPLOAD: usize = 8 * 1024 * 1024;

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
    // And answer TO the desk's route, never to the inbound mail's own From.
    //
    // That From is attacker-controlled in the ordinary case and fabricated in the rehearsal case:
    // `stellwerk reply` plants a simulated railway answer whose From was a real DB address, so
    // pressing "Antworten" in the app used to send a real mail to a real railway, with no redirect
    // consulted on this path at all. Reading the destination from mail_routes closes that by
    // construction — this path can only reach an address somebody put in the table.
    let (relay, to) = match orig.claim_id {
        Some(cid) => {
            let claim: Option<ClaimRow> = sqlx::query_as("select * from claims where id = $1").bind(cid).fetch_optional(&s.pool).await.map_err(internal)?;
            match claim {
                Some(cl) => {
                    let Some(route) = mail_route(&s.pool, &cl.desk).await? else {
                        return Err(err(
                            StatusCode::PRECONDITION_FAILED,
                            &format!("no mail route for desk '{}': set one with `stellwerk route set`", cl.desk),
                        ));
                    };
                    (ensure_claim_address(&s.pool, &cl).await.map_err(internal)?, route.to_address)
                }
                None => return Err(err(StatusCode::PRECONDITION_FAILED, "the claim behind this thread is gone; nothing to answer")),
            }
        }
        // A mail with no claim has no desk, so there is no route and no destination. Before this
        // it would have been answered straight back to whatever From it carried.
        None => return Err(err(StatusCode::PRECONDITION_FAILED, "this thread has no claim; there is no route to answer on")),
    };
    // Attachments: the claim's ticket uploads on request, plus any of the customer's own uploads.
    let mut files: Vec<(String, String, Vec<u8>, Uuid)> = Vec::new();
    if r.attach_ticket {
        if let Some(cid) = orig.claim_id {
            let rows: Vec<(Uuid, String, String, Option<String>, Option<Vec<u8>>)> = sqlx::query_as(
                "select u.id, ca.label, u.content_type, u.path, u.bytes from claim_attachments ca join uploads u on u.id = ca.upload_id
                 where ca.claim_id = $1 and u.customer_id = $2 and u.kind = 'ticket'
                   and (u.path is not null or octet_length(coalesce(u.bytes, ''::bytea)) > 0) order by ca.label",
            )
            .bind(cid)
            .bind(c.0.id)
            .fetch_all(&s.pool)
            .await
            .map_err(internal)?;
            for (uid, label, ct, path, bytes) in rows {
                let data = crate::storage::load(path.as_deref(), bytes).await;
                if data.is_empty() {
                    continue;
                }
                files.push((attachment_filename(&label, &ct), ct, data, uid));
            }
        }
    }
    for uid in &r.upload_ids {
        if files.iter().any(|f| &f.3 == uid) {
            continue;
        }
        let row: Option<(String, String, Option<String>, Option<Vec<u8>>)> = sqlx::query_as("select kind, content_type, path, bytes from uploads where id = $1 and customer_id = $2").bind(uid).bind(c.0.id).fetch_optional(&s.pool).await.map_err(internal)?;
        let Some((kind, ct, path, raw)) = row else { return Err(err(StatusCode::NOT_FOUND, &format!("upload {uid} not found"))) };
        let bytes = crate::storage::load(path.as_deref(), raw).await;
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
        to: &to,
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
    /// Planted by the Stellwerk, not received: skips the check that the sender is the desk. Never set
    /// from a request body.
    #[serde(skip)]
    pub trusted: bool,
    /// The provider's verdict headers (`X-Spam-Tests`), every copy in order. Only the provider
    /// routes fill these.
    #[serde(skip)]
    pub headers: Vec<(String, String)>,
    /// Whether `headers` can be believed at all: a webhook guarded by its secret, from a provider
    /// known to write them. Everything else — no secret configured, a raw MIME post from an unknown
    /// upstream, our own JSON shape — cannot verify a sender.
    #[serde(skip)]
    pub headers_trusted: bool,
    /// Every mailbox in the From header(s), parsed. A From with two mailboxes names two authors, and
    /// a DKIM pass for one says nothing about the other.
    #[serde(skip)]
    pub from_addresses: Vec<String>,
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
    let mut m = inbound_from_json(v).ok_or_else(|| err(StatusCode::BAD_REQUEST, "unrecognised inbound payload"))?;
    // Postmark's verdicts count only on a webhook nobody else can call.
    m.headers_trusted = std::env::var("INBOUND_SECRET").is_ok_and(|v| !v.is_empty());
    Ok(Json(process_detached(s, m).await?))
}

/// Run `process_inbound` in its own task. A provider that gives up waiting drops the request, and
/// with it everything the request was still doing — between writing an attachment and committing
/// the transaction, or between committing and forwarding. Detached, the work finishes either way.
async fn process_detached(s: AppState, m: InboundMail) -> Result<Value, (StatusCode, Json<Value>)> {
    match tokio::spawn(async move { process_inbound(&s, m).await }).await {
        Ok(result) => result,
        Err(e) => Err(internal(e)),
    }
}

/// Accepts our own shape (`to`, `from`, `subject`, `body`, …) and Postmark's inbound
/// webhook (`To`, `From`/`FromFull`, `Subject`, `TextBody`, `MessageID`, `Headers`,
/// base64 `Attachments`; with "include raw email" on, `RawEmail` wins and is parsed as MIME).
pub fn inbound_from_json(v: Value) -> Option<InboundMail> {
    // Postmark's own verdicts live in the JSON `Headers`, not in the raw message it received.
    let provider_headers: Vec<(String, String)> = v
        .get("Headers")
        .and_then(|h| h.as_array())
        .map(|h| {
            h.iter()
                .filter_map(|x| Some((x.get("Name")?.as_str()?.to_string(), x.get("Value")?.as_str()?.to_string())))
                .filter(|(n, _)| AUTH_HEADERS.iter().any(|a| a.eq_ignore_ascii_case(n)))
                .collect()
        })
        .unwrap_or_default();
    if let Some(raw) = v.get("RawEmail").and_then(|r| r.as_str()) {
        return parse_raw_mail(raw.as_bytes()).map(|mut m| {
            m.headers = provider_headers;
            m
        });
    }
    if v.get("To").is_some() || v.get("ToFull").is_some() {
        let str_of = |k: &str| v.get(k).and_then(|x| x.as_str()).map(|x| x.to_string());
        let to = v.get("ToFull").and_then(|t| t.as_array()).and_then(|a| a.first()).and_then(|t| t.get("Email")).and_then(|e| e.as_str()).map(|e| e.to_string()).or_else(|| str_of("To"))?;
        let from = str_of("From").or_else(|| v.get("FromFull").and_then(|f| f.get("Email")).and_then(|e| e.as_str()).map(|e| e.to_string()))?;
        // HTML only as a last resort, and as text: entities like "M&uuml;ller" would slip past
        // redaction, and a blockquote past the cut above the quoted claim.
        let text = |k: &str| str_of(k).filter(|t| !t.trim().is_empty());
        let body = text("TextBody").or_else(|| text("StrippedTextReply")).or_else(|| text("HtmlBody").map(|h| mail_parser::decoders::html::html_to_text(&h))).unwrap_or_default();
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
        let from_addresses = v.get("FromFull").and_then(|f| f.get("Email")).and_then(|e| e.as_str()).map(|e| vec![e.to_lowercase()]).unwrap_or_else(|| vec![inbound_address(&from)]);
        return Some(InboundMail { to, from, subject: str_of("Subject").unwrap_or_default(), body, message_id, in_reply_to: header("In-Reply-To"), claim_id: None, attachments, trusted: false, headers: provider_headers, headers_trusted: false, from_addresses });
    }
    serde_json::from_value(v).ok()
}

/// `POST /internal/inbound-mail/raw`: the RFC 822 message as the body, for providers that
/// hand over the original mail. Parsed with mail-parser, then the same path as the JSON webhook.
pub async fn inbound_mail_raw(State(s): State<AppState>, axum::extract::Query(q): axum::extract::Query<BTreeMap<String, String>>, body: axum::body::Bytes) -> ApiResult {
    inbound_secret_ok(&q)?;
    let mut m = parse_raw_mail(&body).ok_or_else(|| err(StatusCode::BAD_REQUEST, "not a parseable RFC 822 message"))?;
    // A bare message carries whatever headers its sender wrote. Only an upstream known to write
    // X-Spam-Tests itself, and to drop copies that arrived with the mail, makes them a verdict.
    m.headers_trusted = std::env::var("INBOUND_SECRET").is_ok_and(|v| !v.is_empty()) && std::env::var("INBOUND_RAW_TRUSTS_SPAM_TESTS").is_ok_and(|v| v == "1");
    Ok(Json(process_detached(s, m).await?))
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
    // Every mailbox of every From header: mail_parser keeps only the last header, so count them too.
    let from_headers = msg.headers().iter().filter(|h| h.name().eq_ignore_ascii_case("From")).count();
    let mut from_addresses: Vec<String> = msg.from().map(|a| a.iter().filter_map(|x| x.address().map(|ad| ad.to_lowercase())).collect()).unwrap_or_default();
    if from_headers > 1 {
        from_addresses.push("(more than one From header)".into());
    }
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
        trusted: false,
        headers_trusted: false,
        from_addresses,
        // Every copy, in order: `header_raw` would return the lowest one, which the sender wrote.
        headers: msg
            .headers()
            .iter()
            .filter(|h| AUTH_HEADERS.iter().any(|a| a.eq_ignore_ascii_case(h.name())))
            .filter_map(|h| Some((h.name().to_string(), msg.raw_message().get(h.offset_start() as usize..h.offset_end() as usize).map(|b| String::from_utf8_lossy(b).trim().to_string())?)))
            .collect(),
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

/// Whom an inbound mail belongs to, found by the address it was sent to.
pub struct Routed {
    pub customer: CustomerRow,
    pub claim: Option<ClaimRow>,
    /// How it was found, for the dry run to say.
    pub how: &'static str,
}

/// Routing order (docs/18 §4): the claim's own address (`antrag-<hex>@RELAY_DOMAIN`) names customer
/// and claim in one step; the customer's older per-customer address (`fahrgast-<hex>@…`) names only
/// the customer, and the claim is the one named, the one whose mail this answers, or the newest open
/// one. None: the address belongs to nobody. Shared by the webhook and `stellwerk read-mail --to`, so
/// the dry run finds what the webhook would.
pub async fn route_inbound(pool: &PgPool, to: &str, claim_id: Option<Uuid>, in_reply_to: Option<&str>) -> Result<Option<Routed>, sqlx::Error> {
    let address = inbound_address(to);
    let by_claim: Option<ClaimRow> = sqlx::query_as("select * from claims where lower(reply_address) = $1").bind(&address).fetch_optional(pool).await?;
    if let Some(claim) = by_claim {
        let customer: CustomerRow = sqlx::query_as("select * from customers where id = $1").bind(claim.customer_id).fetch_one(pool).await?;
        return Ok(Some(Routed { customer, claim: Some(claim), how: "the claim's own address" }));
    }
    let customer: Option<CustomerRow> = sqlx::query_as("select * from customers where lower(relay_address) = $1").bind(&address).fetch_optional(pool).await?;
    let Some(customer) = customer else { return Ok(None) };
    let (claim, how): (Option<ClaimRow>, &'static str) = match (claim_id, in_reply_to) {
        (Some(id), _) => (sqlx::query_as("select * from claims where id = $1 and customer_id = $2").bind(id).bind(customer.id).fetch_optional(pool).await?, "the passenger's address, claim named"),
        (None, Some(mid)) => (
            sqlx::query_as("select c.* from claims c join mails ml on ml.claim_id = c.id where ml.message_id = $1 and c.customer_id = $2").bind(mid).bind(customer.id).fetch_optional(pool).await?,
            "the passenger's address, answering our mail",
        ),
        (None, None) => (
            sqlx::query_as("select * from claims where customer_id = $1 and status in ('sent','question') order by sent_at desc limit 1").bind(customer.id).fetch_optional(pool).await?,
            "the passenger's address, newest open claim",
        ),
    };
    Ok(Some(Routed { customer, claim, how }))
}

/// A claim's rides in the order a reader numbers them (F1, F2, …). One query for the webhook and the
/// dry run, so `stellwerk read-mail --claim` shows what the webhook will do.
pub async fn claim_rides(pool: &PgPool, claim_id: Uuid) -> Result<Vec<IncidentRow>, sqlx::Error> {
    sqlx::query_as("select i.* from incidents i join claim_incidents ci on ci.incident_id = i.id where ci.claim_id = $1 order by i.ride_date, i.created_at, i.id").bind(claim_id).fetch_all(pool).await
}

/// The header in which the receiving provider records what it verified about a sender.
const AUTH_HEADERS: &[&str] = &["X-Spam-Tests"];

/// Whether the receiving side verified the From domain.
///
/// One verdict counts: SpamAssassin's `DKIM_VALID_AU` — a valid DKIM signature from the author's own
/// domain — in the `X-Spam-Tests` header Postmark documents for inbound mail. Not `Received-SPF` or
/// `Authentication-Results`: nothing says the provider writes those, so a copy there may well be the
/// sender's. And only when `X-Spam-Tests` occurs exactly once: a sender can put the header into the
/// mail too, and a second copy means nobody can say which one the provider wrote.
///
/// What is recorded is every copy as received, so the first real answers show whether the
/// provider's format is what this expects.
pub fn sender_auth(headers: &[(String, String)], trusted: bool, from: &str, from_addresses: &[String]) -> Value {
    let tests: Vec<&str> = headers.iter().filter(|(n, _)| n.eq_ignore_ascii_case("X-Spam-Tests")).map(|(_, v)| v.as_str()).collect();
    let dkim_author = trusted && tests.len() == 1 && tests[0].split([',', ' ', '\t', '\n']).any(|t| t.trim() == "DKIM_VALID_AU");
    let from_domain = inbound_address(from).rsplit_once('@').map(|(_, d)| d.to_string()).unwrap_or_default();
    json!({
        "aligned": dkim_author,
        "how": if dkim_author { Some("dkim (DKIM_VALID_AU)") } else { None },
        "headers_trusted": trusted,
        "from_domain": from_domain,
        "from_addresses": from_addresses,
        "x_spam_tests": tests,
    })
}

/// Only the desk can move a claim. Everybody who holds the claim's reply address — including the
/// passenger, who gets a copy of every claim — could otherwise write "wir überweisen 1,50 EUR" and
/// confirm money. Two things have to hold for a mail to accept, refuse or ask: it is from one of
/// the route's answer domains (the domain it is sent to, plus `stellwerk route answers`; see
/// `reply::answer_domains`), and the receiving side verified that domain ([`sender_auth`]). A mail that fails keeps its reading on record and
/// moves nothing. Bounces are exempt: they come from mail servers, not from the desk.
pub async fn guard_sender(pool: &PgPool, claim: Option<&ClaimRow>, from: &str, trusted: bool, auth: &Value, decision: &mut crate::reply::Decision) -> Result<(), (StatusCode, Json<Value>)> {
    if trusted || !matches!(decision.verdict.outcome, MailOutcome::Accepted | MailOutcome::Rejected | MailOutcome::Question) {
        return Ok(());
    }
    // Through the same resolver the send used, catch-all included: a claim that went out on the
    // fallback route has to be allowed to be answered on it too. Looked up by desk alone, a claim
    // on the catch-all had no answer domains at all, so every reply was downgraded to "other" and
    // no money could ever move (#25).
    let row: Option<(String, Option<String>)> = match claim {
        Some(c) => sqlx::query_as(
            "select to_address, reply_from from mail_routes where desk = $1 or desk = $2 order by (desk = $2) limit 1",
        )
        .bind(&c.desk)
        .bind(DEFAULT_DESK)
        .fetch_optional(pool)
        .await
        .map_err(internal)?,
        None => None,
    };
    let allowed: Vec<String> = match row {
        Some((to, extra)) => crate::reply::answer_domains(&to, extra.as_deref()),
        None => vec![],
    };
    let sender = inbound_address(from);
    // One mailbox. A second author ("From: Desk <antwort@desk.test>, x@evil.test", signed by
    // evil.test) or a comment ("x@evil.test (<antwort@desk.test>)") would otherwise be judged by
    // whichever address a parser picks. Parsed addresses decide when the provider gave them; a
    // display name with parentheses is then no problem.
    let parsed: Vec<&str> = auth["from_addresses"].as_array().map(|a| a.iter().filter_map(|x| x.as_str()).collect()).unwrap_or_default();
    let plain = if parsed.is_empty() { !from.contains('(') && from.matches('<').count() <= 1 && from.matches('@').count() == 1 } else { parsed.len() == 1 && parsed[0] == sender };
    let why = if !plain || !crate::reply::sender_matches(&sender, &allowed) {
        Some(if allowed.is_empty() { "no route says who answers for this desk".to_string() } else { format!("sender is not the desk ({})", allowed.join(", ")) })
    } else if !auth["aligned"].as_bool().unwrap_or(false) {
        Some("the sender's domain is not verified (no aligned DKIM or SPF pass)".to_string())
    } else {
        None
    };
    if let Some(why) = why {
        decision.verdict = crate::reply::Verdict::other(format!("{why}; read as {:?}: {}", decision.verdict.outcome, decision.verdict.because).to_lowercase());
        decision.trace["verdict"] = json!(decision.verdict);
        decision.trace["sender_check"] = json!({ "sender": sender, "allowed": allowed });
    }
    Ok(())
}

/// A claim that is already accepted or refused is not re-decided by a later mail, and the mail must
/// not say otherwise: its outcome is what the app labels it with and what the push announces, so a
/// reply to an objection would tell a paid passenger "abgelehnt". The reading stays in the trace.
pub fn guard_closed(claim: Option<&ClaimRow>, decision: &mut crate::reply::Decision) {
    let closed = claim.is_some_and(|c| matches!(c.status, ClaimStatus::Accepted | ClaimStatus::Rejected));
    if closed && decision.verdict.outcome != MailOutcome::Other {
        decision.verdict = crate::reply::Verdict::other(format!("the claim was already closed; read as {:?}: {}", decision.verdict.outcome, decision.verdict.because).to_lowercase());
        decision.trace["verdict"] = json!(decision.verdict);
    }
}

/// What a reading does to its claim, inside the caller's transaction. Returns the status the claim
/// moved to, if it moved.
///
/// A claim that is already accepted or refused is not re-decided by a later mail: a reply to an
/// objection would otherwise refuse rides that were paid, and a second partial award overwrite the
/// first. The reading is kept on the mail and in the audit line; a human takes it from there.
/// `claim` must be the row as locked in this transaction (see [`lock_claim`]): a reading takes
/// seconds, and a claim closed by another mail meanwhile must not be re-decided from a stale copy.
pub async fn settle_claim(tx: &mut sqlx::PgConnection, customer_id: Uuid, claim: &ClaimRow, decision: &crate::reply::Decision) -> anyhow::Result<Option<ClaimStatus>> {
    let verdict = &decision.verdict;
    let closed = matches!(claim.status, ClaimStatus::Accepted | ClaimStatus::Rejected);
    let amount = if verdict.outcome == MailOutcome::Accepted { verdict.amount_cents } else { None };
    let next = match verdict.outcome {
        _ if closed => None,
        MailOutcome::Accepted => Some(ClaimStatus::Accepted),
        MailOutcome::Rejected => Some(ClaimStatus::Rejected),
        MailOutcome::Question => Some(ClaimStatus::Question),
        MailOutcome::Bounce => Some(ClaimStatus::Bounced),
        // Nothing decided: the claim keeps whatever status it has now, not the one read before the
        // model was asked.
        MailOutcome::Other => None,
    };
    if let Some(next) = next {
        sqlx::query("update claims set status = $2, amount_confirmed_cents = coalesce($3, amount_confirmed_cents), closed_at = case when $2 in ('accepted','rejected') then now() else closed_at end where id = $1")
            .bind(claim.id)
            .bind(next)
            .bind(amount)
            .execute(&mut *tx)
            .await?;
        // Ride by ride: a partial award confirms some and refuses the others, and a confirmed ride
        // carries the figure the desk wrote rather than the one we claimed. A ride already confirmed
        // is never taken back by a mail.
        let mut confirmed_any = false;
        for ride in &verdict.rides {
            match ride.outcome {
                crate::reply::RideOutcome::Paid { cents } => {
                    confirmed_any = true;
                    sqlx::query("update incidents set status = 'bestaetigt', confirmed_cents = $2 where id = $1 and status <> 'bestaetigt'").bind(ride.incident_id).bind(cents).execute(&mut *tx).await?;
                }
                crate::reply::RideOutcome::Refused => {
                    sqlx::query("update incidents set status = 'abgelehnt' where id = $1 and status <> 'bestaetigt'").bind(ride.incident_id).execute(&mut *tx).await?;
                }
            }
        }
        if confirmed_any {
            sqlx::query("insert into badge_awards (customer_id, badge_id) values ($1, 'bestaetigt') on conflict do nothing").bind(customer_id).execute(&mut *tx).await?;
        }
    }
    let reason = if closed {
        format!("inbound mail on a closed claim, recorded only; read by {}: {}", decision.read_by, verdict.because)
    } else {
        format!("inbound mail, read by {}: {}", decision.read_by, verdict.because)
    };
    sqlx::query("insert into audit_log (entity, entity_id, from_status, to_status, reason) values ('claim', $1, $2, $3, $4)")
        .bind(claim.id)
        .bind(format!("{:?}", claim.status).to_lowercase())
        .bind(format!("{:?}", next.unwrap_or(claim.status)).to_lowercase())
        .bind(&reason)
        .execute(&mut *tx)
        .await?;
    Ok(next)
}

/// What we sent for a passenger: the claims and the replies written in the app. An answer is read
/// without these words (`redact::without_ours`).
pub async fn sent_by_passenger(pool: &PgPool, customer_id: Uuid) -> Result<Vec<String>, sqlx::Error> {
    sqlx::query_scalar("select body from mails where customer_id = $1 and direction = 'out' order by occurred_at desc limit 20").bind(customer_id).fetch_all(pool).await
}

/// The claim, re-read and locked inside the transaction that will change it.
pub async fn lock_claim(tx: &mut sqlx::PgConnection, claim_id: Uuid) -> anyhow::Result<Option<ClaimRow>> {
    Ok(sqlx::query_as("select * from claims where id = $1 for update").bind(claim_id).fetch_optional(&mut *tx).await?)
}

/// After the transaction: the event that says money was confirmed, and retention for a closed claim.
/// Both are past the point of no return, so a failure is logged rather than answered with an error
/// the provider would retry — the retry finds the mail and stops (the scanner's sweep retains later).
async fn after_settle(s: &AppState, customer_id: Uuid, claim_id: Uuid, moved: Option<ClaimStatus>, amount: Option<i64>) {
    // It carries the amount the desk named, so the push and the app both report what the railway
    // actually wrote rather than what we asked.
    if moved == Some(ClaimStatus::Accepted) {
        s.events.publish(customer_id, "claim", json!({ "claim_id": claim_id, "status": "accepted", "amount_confirmed_cents": amount, "source": "railway_reply" }));
    }
    if matches!(moved, Some(ClaimStatus::Accepted | ClaimStatus::Rejected)) {
        if let Err(e) = crate::scanner::retain_closed_claim(&s.pool, claim_id).await {
            tracing::warn!(error = %e, claim = %claim_id, "retention after a closing answer failed; the scanner's sweep will retry");
        }
    }
}

/// Forward a desk's answer to the passenger's own inbox, and mark it forwarded only once it went.
async fn forward_to_passenger(pool: &PgPool, cust: &CustomerRow, relay: &str, mail: &MailRow) {
    let Some(email) = cust.email.as_deref() else { return };
    // Claimed before sending, so two deliveries of one message racing here forward it once.
    let claimed: Option<(Uuid,)> = match sqlx::query_as("update mails set forwarded_at = now() where id = $1 and forwarded_at is null returning id").bind(mail.id).fetch_optional(pool).await {
        Ok(row) => row,
        Err(e) => {
            tracing::warn!(error = %e, mail = %mail.id, "could not claim the forward of a desk answer");
            return;
        }
    };
    if claimed.is_none() {
        return;
    }
    let fwd_body = format!("Weitergeleitet von deiner Verspätomat-Adresse {}.\nVon: {}\nBetreff: {}\n\n{}", relay, mail.from_addr, mail.subject, mail.body);
    let sent = crate::mail::send(crate::mail::OutgoingMail {
        from: &format!("Verspätomat <{}>", relay),
        to: email,
        bcc: None,
        subject: &format!("Fwd: {}", mail.subject),
        body: &fwd_body,
        message_id: &new_message_id(),
        in_reply_to: None,
        attachments: vec![],
    })
    .await;
    if let Err(e) = sent {
        tracing::warn!(error = %e, mail = %mail.id, "forwarding a desk answer failed; a repeated delivery tries again");
        let _ = sqlx::query("update mails set forwarded_at = null where id = $1").bind(mail.id).execute(pool).await;
    }
}

/// The same message delivered again: nothing is read or moved twice, but a forward that did not go
/// out the first time is tried once more.
async fn delivered_before(s: &AppState, message_id: &str) -> Result<Option<Value>, (StatusCode, Json<Value>)> {
    let seen: Option<MailRow> = sqlx::query_as("select * from mails where direction = 'inbound' and message_id = $1").bind(message_id).fetch_optional(&s.pool).await.map_err(internal)?;
    let Some(mail) = seen else { return Ok(None) };
    if mail.forwarded_at.is_none() {
        let cust: CustomerRow = sqlx::query_as("select * from customers where id = $1").bind(mail.customer_id).fetch_one(&s.pool).await.map_err(internal)?;
        forward_to_passenger(&s.pool, &cust, &inbound_address(&mail.to_addr), &mail).await;
    }
    Ok(Some(json!({ "mail": mail, "outcome": mail.outcome, "claim_id": mail.claim_id, "duplicate": true })))
}

/// Read a stored desk answer again and let it act, as if it had just arrived.
///
/// For the mail that came in while the model could not be asked: the rules alone neither confirm
/// nor refuse, so it was recorded as "a human should read this" and waits here. The same checks run
/// — the sender and its verification as recorded on arrival, the gate — and nothing is forwarded
/// again. A mail whose claim is closed or gone is read but not changed: its stored outcome may be
/// the one that closed the claim.
pub async fn reread_mail(s: &AppState, mail_id: Uuid) -> Result<Value, (StatusCode, Json<Value>)> {
    let mail: Option<MailRow> = sqlx::query_as("select * from mails where id = $1 and direction = 'inbound'").bind(mail_id).fetch_optional(&s.pool).await.map_err(internal)?;
    let Some(mail) = mail else { return Err(err(StatusCode::NOT_FOUND, "no inbound mail with this id")) };
    let cust: CustomerRow = sqlx::query_as("select * from customers where id = $1").bind(mail.customer_id).fetch_one(&s.pool).await.map_err(internal)?;
    let claim: Option<ClaimRow> = match mail.claim_id {
        Some(id) => sqlx::query_as("select * from claims where id = $1").bind(id).fetch_optional(&s.pool).await.map_err(internal)?,
        None => None,
    };
    let rows = match &claim {
        Some(c) => claim_rides(&s.pool, c.id).await.map_err(internal)?,
        None => vec![],
    };
    let (claimed, rides) = crate::reply::rides_of(&rows);
    let relay = inbound_address(&mail.to_addr);
    let mut known = crate::reply::known_of(&cust, claim.as_ref(), Some(&relay));
    known.sent = sent_by_passenger(&s.pool, cust.id).await.map_err(internal)?;
    let mut decision = crate::reply::read(&crate::reply::Mail { from: &mail.from_addr, subject: &mail.subject, body: &mail.body }, &known, &claimed, &rides, true).await;
    let auth = mail.sender_auth.clone().unwrap_or_else(|| json!({ "aligned": false }));
    guard_sender(&s.pool, claim.as_ref(), &mail.from_addr, false, &auth, &mut decision).await?;
    let before = json!({ "outcome": mail.outcome, "amount_cents": mail.amount_cents, "read_by": mail.read_by, "because": mail.reading.as_ref().and_then(|r| r["verdict"]["because"].as_str().map(str::to_string)) });

    let mut tx = s.pool.begin().await.map_err(internal)?;
    let current = match mail.claim_id {
        Some(id) => lock_claim(&mut tx, id).await.map_err(internal)?,
        None => None,
    };
    let open = current.as_ref().is_some_and(|c| !matches!(c.status, ClaimStatus::Accepted | ClaimStatus::Rejected));
    if !open {
        tx.rollback().await.map_err(internal)?;
        return Ok(json!({
            "mail_id": mail.id, "claim_id": mail.claim_id, "before": before, "changed": false,
            "after": { "outcome": decision.verdict.outcome, "amount_cents": decision.verdict.amount_cents, "read_by": decision.read_by, "because": decision.verdict.because },
            "why_unchanged": if current.is_none() { "the claim is gone" } else { "the claim is already closed" },
        }));
    }
    let amount = if decision.verdict.outcome == MailOutcome::Accepted { decision.verdict.amount_cents } else { None };
    sqlx::query("update mails set outcome = $2, amount_cents = $3, read_by = $4, reading = $5 where id = $1")
        .bind(mail.id)
        .bind(decision.verdict.outcome)
        .bind(amount)
        .bind(&decision.read_by)
        .bind(&decision.trace)
        .execute(&mut *tx)
        .await
        .map_err(internal)?;
    let moved = match &current {
        Some(c) => settle_claim(&mut tx, cust.id, c, &decision).await.map_err(internal)?,
        None => None,
    };
    tx.commit().await.map_err(internal)?;
    if let Some(c) = &current {
        after_settle(s, cust.id, c.id, moved, amount).await;
    }
    s.events.publish(cust.id, "incident", json!({}));
    Ok(json!({
        "mail_id": mail.id, "claim_id": mail.claim_id, "before": before, "changed": true,
        "after": { "outcome": decision.verdict.outcome, "amount_cents": amount, "read_by": decision.read_by, "because": decision.verdict.because },
        "claim_moved_to": moved,
    }))
}

pub async fn process_inbound(s: &AppState, mut m: InboundMail) -> Result<Value, (StatusCode, Json<Value>)> {
    // A message without a Message-ID gets one from its content, so a repeated delivery is still
    // recognised as one.
    if m.message_id.as_deref().is_none_or(|id| id.trim().is_empty()) {
        use sha2::Digest;
        let digest = sha2::Sha256::digest(format!("{}\u{0}{}\u{0}{}\u{0}{}", m.from, m.to, m.subject, m.body).as_bytes());
        m.message_id = Some(format!("<derived-{}@verspaetomat.invalid>", hex::encode(&digest[..12])));
    }
    // Delivered before: answer with what was recorded then, and read nothing again.
    if let Some(mid) = &m.message_id {
        if let Some(done) = delivered_before(s, mid).await? {
            return Ok(done);
        }
    }
    let relay = inbound_address(&m.to);
    let Some(routed) = route_inbound(&s.pool, &relay, m.claim_id, m.in_reply_to.as_deref()).await.map_err(internal)? else {
        return Err(err(StatusCode::NOT_FOUND, "no claim or customer for this address"));
    };
    let (cust, claim) = (routed.customer, routed.claim);
    // The desk's own words are the only confirmation this system has. `reply.rs` reads them — the
    // rules always, a model when one is configured — and checks every answer against the mail
    // before anything moves; each check that fails ends as "a human should read this", because a
    // wrong `accepted` tells somebody their delay became money that never arrived and adds it to a
    // Verein's public total.
    let claimed_rows: Vec<IncidentRow> = match &claim {
        Some(cl) => claim_rides(&s.pool, cl.id).await.map_err(internal)?,
        None => vec![],
    };
    let (claimed, rides) = crate::reply::rides_of(&claimed_rows);
    let mut known = crate::reply::known_of(&cust, claim.as_ref(), Some(&relay));
    known.sent = sent_by_passenger(&s.pool, cust.id).await.map_err(internal)?;
    let auth = sender_auth(&m.headers, m.headers_trusted, &m.from, &m.from_addresses);
    let mut decision = crate::reply::read(&crate::reply::Mail { from: &m.from, subject: &m.subject, body: &m.body }, &known, &claimed, &rides, !m.trusted).await;
    guard_sender(&s.pool, claim.as_ref(), &m.from, m.trusted, &auth, &mut decision).await?;
    // Attachments are written to disk first; their rows go into the transaction, and the files are
    // removed again if it does not commit. Retention deletes them when the claim closes.
    let mut files: Vec<(Uuid, String, String)> = Vec::new();
    let mut stored: Vec<Value> = Vec::new();
    for (name, ct, bytes) in &m.attachments {
        if bytes.len() > MAX_UPLOAD {
            stored.push(json!({ "name": name, "content_type": ct, "size": bytes.len(), "upload_id": null, "skipped": "max 8 MB" }));
            continue;
        }
        let uid = Uuid::new_v4();
        let path = match crate::storage::put(uid, bytes).await {
            Ok(p) => p,
            Err(e) => {
                for (_, _, written) in &files {
                    crate::storage::remove(written).await;
                }
                return Err(err(StatusCode::INTERNAL_SERVER_ERROR, &format!("storage: {e}")));
            }
        };
        files.push((uid, ct.clone(), path));
        stored.push(json!({ "name": name, "content_type": ct, "size": bytes.len(), "upload_id": uid }));
    }
    // The mail, its uploads, the claim, its rides and the audit line land together or not at all: a
    // failure halfway would leave the mail stored and the claim unmoved, and the provider's retry
    // would then find the mail and never move it.
    let written: anyhow::Result<(MailRow, Option<ClaimStatus>)> = async {
        let mut tx = s.pool.begin().await?;
        // The claim as it is now, locked: a reading takes seconds, and another answer may have
        // closed it meanwhile.
        let current = match &claim {
            Some(c) => lock_claim(&mut tx, c.id).await?,
            None => None,
        };
        guard_closed(current.as_ref(), &mut decision);
        for (uid, ct, path) in &files {
            sqlx::query("insert into uploads (id, customer_id, kind, content_type, path) values ($1,$2,'inbound',$3,$4)").bind(uid).bind(cust.id).bind(ct).bind(path).execute(&mut *tx).await?;
        }
        let amount = if decision.verdict.outcome == MailOutcome::Accepted { decision.verdict.amount_cents } else { None };
        let mail: MailRow = sqlx::query_as(
            "insert into mails (id, customer_id, claim_id, direction, message_id, in_reply_to, from_addr, to_addr, subject, body, attachments, outcome, amount_cents, read_by, reading, sender_auth)
             values ($1,$2,$3,'inbound',$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15) returning *",
        )
        .bind(Uuid::new_v4())
        .bind(cust.id)
        .bind(claim.as_ref().map(|c| c.id))
        .bind(&m.message_id)
        .bind(&m.in_reply_to)
        .bind(&m.from)
        .bind(&m.to)
        .bind(&m.subject)
        .bind(&m.body)
        .bind(json!(stored))
        .bind(decision.verdict.outcome)
        .bind(amount)
        .bind(&decision.read_by)
        .bind(&decision.trace)
        .bind(&auth)
        .fetch_one(&mut *tx)
        .await?;
        let moved = match &current {
            Some(c) => settle_claim(&mut tx, cust.id, c, &decision).await?,
            None => None,
        };
        tx.commit().await?;
        Ok((mail, moved))
    }
    .await;
    let (mail, moved) = match written {
        Ok(done) => done,
        Err(e) => {
            for (_, _, path) in &files {
                crate::storage::remove(path).await;
            }
            // Two deliveries of one message at once: the second loses the race on the unique index
            // and answers like any repeated delivery.
            let raced = e.downcast_ref::<sqlx::Error>().and_then(|x| x.as_database_error()).and_then(|d| d.constraint()) == Some("mails_inbound_message_id");
            if raced {
                if let Some(done) = delivered_before(s, m.message_id.as_deref().unwrap_or_default()).await? {
                    return Ok(done);
                }
            }
            return Err(internal(e));
        }
    };
    let outcome = decision.verdict.outcome;
    let amount = mail.amount_cents;
    // Forward first: it is what the passenger was promised, and nothing after it may prevent it.
    forward_to_passenger(&s.pool, &cust, &relay, &mail).await;
    if let Some(c) = &claim {
        after_settle(s, cust.id, c.id, moved, amount).await;
    }
    s.events.publish(cust.id, "mail", json!({ "claim_id": claim.as_ref().map(|c| c.id), "outcome": outcome }));
    s.events.publish(cust.id, "incident", json!({}));
    Ok(json!({ "mail": mail, "outcome": outcome, "claim_id": claim.map(|c| c.id) }))
}


// ---------------------------------------------------------------------------
// Community
// ---------------------------------------------------------------------------

/// `GET /v1/community/pulse` — the three shared figures, and nothing else.
///
/// The app used to make these move by adding a random number to them every second, on two screens.
/// That is not a slow number, it is a made-up one: it climbed whether or not a single train was
/// late, and a product whose whole argument is "we do not invent figures" cannot print an invented
/// one on its front page.
///
/// So the number moves when the number moves, and the app asks. This is the endpoint it asks: two
/// aggregates over indexed columns and a row count, no joins, no per-NGO breakdown — the expensive
/// half of `/v1/community`. It is small enough to poll on a timer without caching, which is the
/// point; when that stops being true, it gets a cache here rather than a lie in the client.
pub async fn community_pulse(State(s): State<AppState>, _c: Customer) -> ApiResult {
    let (minutes, users): (i64, i64) = sqlx::query_as(
        "select coalesce(sum(final_delay_min),0)::bigint, (select count(*) from customers)::bigint from rides where status = 'arrived'",
    )
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    let (submitted, confirmed): (i64, i64) = sqlx::query_as(
        "select coalesce(sum(amount_cents) filter (where status = 'eingereicht'),0)::bigint, coalesce(sum(coalesce(confirmed_cents, amount_cents)) filter (where status = 'bestaetigt'),0)::bigint from incidents",
    )
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    Ok(Json(json!({ "minutes": minutes, "users": users, "submitted_cents": submitted, "confirmed_cents": confirmed })))
}

pub async fn community(State(s): State<AppState>, _c: Customer) -> ApiResult {
    let (minutes, users): (i64, i64) = sqlx::query_as("select coalesce(sum(final_delay_min),0)::bigint, (select count(*) from customers)::bigint from rides where status = 'arrived'").fetch_one(&s.pool).await.map_err(internal)?;
    let (submitted, confirmed): (i64, i64) = sqlx::query_as(
        "select coalesce(sum(amount_cents) filter (where status = 'eingereicht'),0)::bigint, coalesce(sum(coalesce(confirmed_cents, amount_cents)) filter (where status = 'bestaetigt'),0)::bigint from incidents",
    )
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    let ngos = ngo_totals(&s.pool).await.map_err(internal)?;
    // Counted, not padded. These four used to have a fixture added to them — 1 208 311 minutes and
    // 18 420 people who do not exist — so Home announced a crowd on a system with none. A figure
    // this app prints about itself has to be one it can defend, and the honest early number is
    // small. The per-NGO seeds stay: those record real donations a Verein received before this
    // existed, and an operator enters them deliberately.
    Ok(Json(json!({
        "minutes": minutes,
        "submitted_cents": submitted,
        "confirmed_cents": confirmed,
        "users": users,
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

/// Postgres' `isodow - 1` buckets laid out Monday-first, with the days nobody rode as zero.
///
/// Separate from the query because this is the off-by-one that would never show up as an error —
/// a week shifted by one day still draws seven plausible bars (issue #33).
pub fn week_buckets(rows: &[(i32, i64)]) -> [i64; 7] {
    let mut out = [0i64; 7];
    for &(day, points) in rows {
        if (0..7).contains(&day) {
            out[day as usize] = points;
        }
    }
    out
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

    // One value per weekday of the running week, Monday first (issue #33). The home screen used to
    // draw two columns — this week against last — and the redesign wants Mo–So, which nothing has
    // ever computed. Days with no ride are a real zero here, not a gap: the week is bounded and
    // every one of its days has already happened or is still to come, so a zero means "nothing was
    // late", which is exactly what the bar should say.
    let day_rows: Vec<(i32, i64)> = sqlx::query_as(
        "select (extract(isodow from finalised_at at time zone 'Europe/Berlin')::int - 1) as day,
                coalesce(sum(points),0)::bigint
         from rides
         where customer_id = $1 and status in ('arrived','abandoned')
           and finalised_at >= $2 and finalised_at < $3
         group by day",
    )
    .bind(c.0.id)
    .bind(week_start)
    .bind(next_week)
    .fetch_all(pool)
    .await
    .map_err(internal)?;
    let points_by_day = week_buckets(&day_rows);
    let today_index = {
        use chrono::Datelike;
        now.with_timezone(&chrono_tz::Europe::Berlin).weekday().num_days_from_monday() as i64
    };

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

    // Community with my share. `my_minutes` is minutes, out of the same column and the same set of
    // rides as the total it is a share of — it used to be the Geduldspunkte total, so Home's dark
    // board said „N davon deine" under a label that says minutes and the two numbers were counted
    // by different rules (a ride given up carries points but no final delay).
    let (minutes, my_minutes, my_confirmed): (i64, i64, i64) = sqlx::query_as(
        "select (select coalesce(sum(final_delay_min),0)::bigint from rides where status = 'arrived'),
                (select coalesce(sum(final_delay_min),0)::bigint from rides where customer_id = $1 and status = 'arrived'),
                (select coalesce(sum(coalesce(confirmed_cents, amount_cents)),0)::bigint from incidents where customer_id = $1 and status = 'bestaetigt')",
    )
    .bind(c.0.id)
    .fetch_one(pool)
    .await
    .map_err(internal)?;
    let confirmed_all: i64 = sqlx::query_scalar("select coalesce(sum(coalesce(confirmed_cents, amount_cents)),0)::bigint from incidents where status = 'bestaetigt'").fetch_one(pool).await.map_err(internal)?;

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
        // Monday first, seven entries, always present (issue #33).
        "points_by_day": points_by_day.to_vec(),
        // Which of those seven is today, in Europe/Berlin — the same clock the buckets were cut
        // with. The app must not work this out from the device: a phone in another timezone, or
        // one still showing a standing fetched before midnight, would light a bar whose value
        // belongs to another day.
        "today_index": today_index,
        "unread_mails": unread_mails(pool, c.0.id).await.map_err(internal)?,
        "rides_this_week": rides_this_week,
        "level": { "name": level_name, "next_name": next_name, "points_to_next": points_to_next, "progress": progress },
        "money": { "open_cents": open_cents, "missing_cents": missing_cents, "ready": ready, "ready_desk": ready_desk, "ngo_name": ngo_name },
        "board": board,
        "community": { "minutes_total": minutes, "my_minutes": my_minutes, "confirmed_cents": confirmed_all, "my_confirmed_cents": my_confirmed },
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
mod draft_tests {
    use super::*;

    fn ids(n: usize) -> Vec<Uuid> {
        (0..n).map(|_| Uuid::new_v4()).collect()
    }

    /// Coming back to the Antrag names no cases. That is not "build me a form out of everything
    /// open", it is "the form I left lying here", and it still carries its ticket.
    #[test]
    fn coming_back_without_a_selection_finds_the_draft_again() {
        let i = ids(3);
        let open: HashSet<Uuid> = i.iter().copied().collect();
        assert_eq!(draft_action(&i[..2], None, &open), DraftAction::Resume);
        // Even though a third case is open and waiting: it shows up unticked, it does not
        // silently rewrite the form.
        assert_eq!(draft_action(&i[..2], Some(&i), &open), DraftAction::Rebuild);
    }

    /// The same cases in another order are the same form; one case more or less is not.
    #[test]
    fn the_selection_decides_not_its_order() {
        let i = ids(3);
        let open: HashSet<Uuid> = i.iter().copied().collect();
        let shuffled = vec![i[2], i[0], i[1]];
        assert_eq!(draft_action(&i, Some(&shuffled), &open), DraftAction::Resume);
        assert_eq!(draft_action(&i, Some(&i[..2]), &open), DraftAction::Rebuild);
    }

    /// A draft whose cases were discarded or ran out of time is no form to return to.
    #[test]
    fn a_draft_over_closed_cases_is_rebuilt() {
        let i = ids(3);
        let open: HashSet<Uuid> = i[..2].iter().copied().collect();
        assert_eq!(draft_action(&i, None, &open), DraftAction::Rebuild);
        assert_eq!(draft_action(&[], None, &open), DraftAction::Rebuild);
        assert_eq!(draft_action(&i[..2], None, &open), DraftAction::Resume);
    }
}

#[cfg(test)]
mod attachment_tests {
    use super::*;

    /// The app up to build 9 sends `"attachments": ["<uuid>"]` and means a ticket by it. That
    /// build is in TestFlight, so the server still reads it — and a nameless attachment gets
    /// the name the mail needs.
    #[test]
    fn an_attachment_may_arrive_as_a_bare_id() {
        let id = Uuid::new_v4();
        let old: Vec<AttachmentRef> = serde_json::from_value(json!([id])).unwrap();
        assert_eq!(old[0].upload_id, id);
        assert_eq!(old[0].label, "Ticket");

        let new: Vec<AttachmentRef> = serde_json::from_value(json!([{ "upload_id": id, "label": "Ticket August 2026" }])).unwrap();
        assert_eq!(new[0].upload_id, id);
        assert_eq!(new[0].label, "Ticket August 2026");

        // An empty name is no name.
        let blank: Vec<AttachmentRef> = serde_json::from_value(json!([{ "upload_id": id, "label": "  " }])).unwrap();
        assert_eq!(blank[0].label, "Ticket");

        assert!(serde_json::from_value::<Vec<AttachmentRef>>(json!(["not-a-uuid"])).is_err());
    }
}

#[cfg(test)]
mod upload_tests {
    use super::*;

    /// The app used to upload its signature without a part content type. The bytes said PNG all
    /// along, and the form prints the signature only if the row says so too.
    #[test]
    fn a_png_is_a_png_whatever_the_client_called_it() {
        let png = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR".to_vec();
        assert_eq!(image_content_type("application/octet-stream", "Unterschrift.png", &png), "image/png");
        assert_eq!(image_content_type("", "", &png), "image/png");
        assert_eq!(image_content_type("image/png", "Unterschrift.png", &png), "image/png");

        // A JPEG photo of a ticket, and a name to go by when the bytes are unfamiliar.
        assert_eq!(image_content_type("", "Ticket.jpg", &[0xFF, 0xD8, 0xFF, 0x00]), "image/jpeg");
        assert_eq!(image_content_type("application/octet-stream", "Ticket.JPEG", b"whatever"), "image/jpeg");

        // Nothing to go by stays unknown, and a type the client did declare is kept.
        assert_eq!(image_content_type("", "notes", b"whatever"), "application/octet-stream");
        assert_eq!(image_content_type("application/pdf", "Antrag.pdf", b"%PDF-1.7"), "application/pdf");
    }
}

#[cfg(test)]
mod inbound_tests {
    use super::*;

    #[test]
    fn a_sender_counts_as_verified_only_with_the_providers_single_dkim_verdict() {
        let h = |pairs: &[(&str, &str)]| pairs.iter().map(|(n, v)| (n.to_string(), v.to_string())).collect::<Vec<_>>();
        let from = "Servicecenter <antwort@bahn.test>";
        assert_eq!(sender_auth(&h(&[("X-Spam-Tests", "DKIM_SIGNED,DKIM_VALID,DKIM_VALID_AU,SPF_PASS")]), true, from, &[])["aligned"], true);
        // Signed, but not by the author's domain.
        assert_eq!(sender_auth(&h(&[("X-Spam-Tests", "DKIM_SIGNED,DKIM_VALID,SPF_PASS")]), true, from, &[])["aligned"], false);
        // A second copy: one of them is the sender's, and nobody can tell which.
        assert_eq!(sender_auth(&h(&[("X-Spam-Tests", "SPF_FAIL"), ("X-Spam-Tests", "DKIM_VALID_AU")]), true, from, &[])["aligned"], false);
        // Headers Postmark does not write prove nothing.
        assert_eq!(sender_auth(&h(&[("Authentication-Results", "mx; dkim=pass header.d=bahn.test")]), true, from, &[])["aligned"], false);
        assert_eq!(sender_auth(&[], true, from, &[])["aligned"], false);
        // No secret on the webhook, or a raw post from an unknown upstream: nothing is a verdict.
        assert_eq!(sender_auth(&h(&[("X-Spam-Tests", "DKIM_VALID_AU")]), false, from, &[])["aligned"], false);
    }

    #[test]
    fn a_from_with_two_mailboxes_is_not_one_sender() {
        let raw = parse_raw_mail(b"From: Desk <antwort@bahn.test>, x@evil.test\r\nTo: antrag-1@users.verspaetomat.de\r\nSubject: x\r\n\r\nbody").unwrap();
        assert_eq!(raw.from_addresses.len(), 2);
        let twice = parse_raw_mail(b"From: x@evil.test\r\nFrom: Desk <antwort@bahn.test>\r\nTo: antrag-1@users.verspaetomat.de\r\nSubject: x\r\n\r\nbody").unwrap();
        assert!(twice.from_addresses.len() >= 2);
        let named = parse_raw_mail(b"From: \"DB Vertrieb (Fahrgastrechte)\" <antwort@bahn.test>\r\nTo: a@b.test\r\nSubject: x\r\n\r\nbody").unwrap();
        assert_eq!(named.from_addresses, vec!["antwort@bahn.test".to_string()]);
    }

    #[test]
    fn postmark_json_keeps_its_verdict_even_with_the_raw_message() {
        let v = json!({
            "RawEmail": "From: Desk <antwort@bahn.test>\r\nTo: antrag-1@users.verspaetomat.de\r\nX-Spam-Tests: DKIM_VALID_AU\r\nSubject: x\r\n\r\nWir zahlen.",
            "Headers": [{ "Name": "X-Spam-Tests", "Value": "DKIM_SIGNED,SPF_PASS" }],
        });
        let m = inbound_from_json(v).unwrap();
        assert_eq!(m.headers, vec![("X-Spam-Tests".to_string(), "DKIM_SIGNED,SPF_PASS".to_string())]);
        let raw = parse_raw_mail(b"X-Spam-Tests: SPF_FAIL\r\nFrom: a@b.test\r\nX-Spam-Tests: DKIM_VALID_AU\r\nSubject: x\r\n\r\nbody").unwrap();
        assert_eq!(raw.headers, vec![("X-Spam-Tests".to_string(), "SPF_FAIL".to_string()), ("X-Spam-Tests".to_string(), "DKIM_VALID_AU".to_string())]);
    }

    /// docs/25 §4: an automatic mute runs out on its own; a mute a passenger set by hand does
    /// not. That is the whole difference between the two, and the geofence set reads it.
    #[test]
    fn an_automatic_mute_expires_and_a_deliberate_one_does_not() {
        let now = crate::clock::now();
        let by_hand = MutedStation { id: "a".into(), name: "A".into(), until: None };
        assert!(by_hand.active(now), "a mute set by hand has no end");

        let running = MutedStation { id: "b".into(), name: "B".into(), until: Some(now + Duration::days(5)) };
        assert!(running.active(now));

        let over = MutedStation { id: "c".into(), name: "C".into(), until: Some(now - Duration::hours(1)) };
        assert!(!over.active(now), "an expired mute stops hiding its station");
    }

    /// docs/25 §4: thirty quiet days switch background scanning off. A fresh account is measured
    /// from when it was made, so it gets its thirty days before anything is taken away.
    #[test]
    fn thirty_quiet_days_switch_the_scanning_off() {
        let now = crate::clock::now();
        let long_ago = now - Duration::days(40);
        let recently = now - Duration::days(3);

        assert!(went_idle(Some(long_ago), long_ago, now), "no check-in for forty days");
        assert!(!went_idle(Some(recently), long_ago, now), "rode three days ago");
        // Never checked in: measured from the account's age, not treated as idle at once.
        assert!(!went_idle(None, recently, now), "a three-day-old account is not idle");
        assert!(went_idle(None, long_ago, now), "a forty-day-old account that never rode is");
        // Exactly on the boundary is not yet over it.
        assert!(!went_idle(Some(now - Duration::days(30)), long_ago, now));
    }

    /// docs/24 §3: while a snooze runs the layer is configured `enabled: false`, so nothing
    /// is scheduled and no notification can fire. A snooze in the past is no snooze.
    #[test]
    fn a_running_snooze_switches_the_nudges_off() {
        let mut c = crate::pdf::test_customer();
        c.loc_mode = LocationMode::Always;
        c.nudge_enabled = true;
        assert!(nudges_enabled(&c), "background location and the switch: nudges are on");

        c.nudge_snooze_until = Some(crate::clock::now() + Duration::hours(2));
        assert!(!nudges_enabled(&c), "a snooze two hours out silences them");

        c.nudge_snooze_until = Some(crate::clock::now() - Duration::minutes(1));
        assert!(nudges_enabled(&c), "an expired snooze is no snooze");

        c.nudge_snooze_until = None;
        c.nudge_enabled = false;
        assert!(!nudges_enabled(&c), "the switch still wins on its own");
    }

    /// docs/30: two feeds, one platform. Before the merge this produced two regions on the phone
    /// and two „Ab Kißlegg Bahnhof" on Home, each with half the check-ins.
    #[test]
    fn geofence_set_merges_one_platform_from_two_feeds() {
        let rows = vec![
            ("de:08436:12345".to_string(), "Kißlegg Bahnhof".to_string(), 47.7931, 9.8869, 2),
            ("muenchen".to_string(), "München Hbf".to_string(), 48.1402, 11.5586, 2),
            ("amarillo-bw:kisslegg".to_string(), "Kißlegg".to_string(), 47.7935, 9.8871, 2),
        ];
        let set = geofence_set(rows, None, &[], 15);
        assert_eq!(set.len(), 2, "one Kißlegg, one München: {set:?}");
        assert_eq!(set[0].name, "Kißlegg Bahnhof", "the spelling met most often, and now the most frequent station");
        assert_eq!(set[0].checkins, 4, "the check-ins add up");
        assert_eq!(set[1].name, "München Hbf");
    }

    /// The home station is listed under the id the customer set, which may not be the id the
    /// merge kept — and then it used to come back a second time.
    #[test]
    fn geofence_set_home_is_not_listed_twice_under_the_other_id() {
        let rows = vec![
            ("amarillo-bw:kisslegg".to_string(), "Kißlegg".to_string(), 47.7935, 9.8871, 3),
            ("de:08436:12345".to_string(), "Kißlegg Bahnhof".to_string(), 47.7931, 9.8869, 1),
        ];
        let home = Some(("de:08436:12345".to_string(), "Kißlegg Bahnhof".to_string(), 47.7931, 9.8869));
        let set = geofence_set(rows, home, &[], 15);
        assert_eq!(set.len(), 1, "{set:?}");
        assert_eq!(set[0].id, "de:08436:12345", "the home station keeps its own id");
        assert_eq!(set[0].checkins, 4, "with the whole platform's count");
    }

    /// The duplicated `#[test]` above used to swallow this one's attribute, so it never ran.
    #[test]
    fn geofence_set_home_first_muted_out_capped() {
        let rows = vec![
            ("a".into(), "A".into(), 50.0, 7.0, 9),
            ("b".into(), "B".into(), 50.1, 7.1, 5),
            ("m".into(), "Muted".into(), 50.2, 7.2, 4),
            ("c".into(), "C".into(), 50.3, 7.3, 1),
        ];
        let home = Some(("b".into(), "B".into(), 50.1, 7.1));
        let muted = vec![MutedStation { id: "m".into(), name: "Muted".into(), until: None }];
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
            "FromFull": {"Email": "fahrgastrechte@servicecenter.invalid", "Name": "Servicecenter Fahrgastrechte"},
            "From": "Servicecenter Fahrgastrechte <fahrgastrechte@servicecenter.invalid>",
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
        assert!(m.from.contains("servicecenter.invalid"));
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

    /// issue #33: seven bars, Monday first. Postgres' isodow is 1..7 with Monday at 1, so the
    /// query subtracts one — and if that ever drifted, the home screen would still draw seven
    /// plausible bars against the wrong days and nobody would notice.
    #[test]
    fn a_week_of_buckets_starts_on_monday() {
        // Monday 3, Wednesday 40, Sunday 7 — nothing on the other four days.
        let rows = vec![(0i32, 3i64), (2, 40), (6, 7)];
        assert_eq!(week_buckets(&rows), [3, 0, 40, 0, 0, 0, 7]);

        // A quiet week is seven real zeroes, not an empty array the screen has to guess at.
        assert_eq!(week_buckets(&[]), [0; 7]);

        // Out-of-range days are dropped rather than panicking on an index.
        assert_eq!(week_buckets(&[(7, 99), (-1, 99), (3, 5)]), [0, 0, 0, 5, 0, 0, 0]);

        // The bars have to add up to the week total the same query computes separately, or the
        // chart and the number beside it would disagree on the same screen.
        let rows = vec![(0i32, 12i64), (1, 30), (4, 8)];
        assert_eq!(week_buckets(&rows).iter().sum::<i64>(), 50);
    }
}
