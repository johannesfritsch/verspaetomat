//! Transitous (MOTIS v1) client. Verified shapes as of 9 September 2026.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::{anyhow, Context, Result};
use chrono::{DateTime, Utc};
use serde::Deserialize;
use tokio::task::JoinSet;

use super::{agency_to_operator, category_for, haversine_m, is_rail_mode, parse_line, DepartureInfo, Itinerary, PlanLeg, StopInfo, TripInfo, TripStop};

const DEFAULT_BASE: &str = "https://api.transitous.org";
const USER_AGENT: &str = "verspaetomat-api/0.1 (+https://verspaetomat.de)";
const DEPARTURE_CACHE_TTL: Duration = Duration::from_secs(30);
const PLAN_CACHE_TTL: Duration = Duration::from_secs(60);
const NEARBY_CANDIDATES: usize = 8;
/// How many stations the Bahnsteig is offered: the best one and two alternatives (docs/23 §1).
const NEARBY_RESULTS: usize = 3;
/// Inside one band the better station wins; beyond it distance decides again (docs/23 §1).
const RANK_BAND_M: i64 = 300;
/// Departures read per candidate when ranking it: enough to see past a burst of one mode.
const RANK_DEPARTURES: usize = 20;
/// A stop's rank changes with the timetable, not with the minute: cached for five minutes.
const RANK_CACHE_TTL: Duration = Duration::from_secs(300);
/// The modes a ranking query asks for (docs/23 §1): the rail modes, plus the two the German
/// S-Bahn arrives as in this feed. Tram, bus and ferry never reach the classifier; METRO and
/// SUBWAY do, because only the line name can tell an S-Bahn from a U-Bahn.
const RANK_MODES: &str = "RAIL,REGIONAL_RAIL,REGIONAL_FAST_RAIL,HIGHSPEED_RAIL,LONG_DISTANCE,NIGHT_RAIL,SUBURBAN,METRO,SUBWAY";
/// MOTIS transit modes that are railway service (docs/17); the plan never proposes bus or tram legs.
const RAIL_MODES: &str = "RAIL,REGIONAL_RAIL,REGIONAL_FAST_RAIL,HIGHSPEED_RAIL,LONG_DISTANCE,NIGHT_RAIL,SUBURBAN";

/// What we ask the planner for. `BUS` is in here only so a Schienenersatzverkehr can be found;
/// `itinerary_from` throws away every bus that is not standing in for a train, so an ordinary
/// city bus never becomes a leg of a journey (docs/28).
const PLAN_MODES: &str = "RAIL,REGIONAL_RAIL,REGIONAL_FAST_RAIL,HIGHSPEED_RAIL,LONG_DISTANCE,NIGHT_RAIL,SUBURBAN,BUS,COACH";

#[derive(Clone)]
pub struct TransitousClient {
    http: reqwest::Client,
    base: String,
    departure_cache: Arc<Mutex<HashMap<String, (Instant, Vec<DepartureInfo>)>>>,
    plan_cache: Arc<Mutex<HashMap<String, (Instant, Vec<Itinerary>)>>>,
    /// What kind of station a stop is (docs/23 §1), per stop id.
    rank_cache: Arc<Mutex<HashMap<String, (Instant, i32)>>>,
}

impl Default for TransitousClient {
    fn default() -> Self {
        Self::new()
    }
}

impl TransitousClient {
    pub fn new() -> Self {
        Self::with_base(std::env::var("TRANSITOUS_URL").unwrap_or_else(|_| DEFAULT_BASE.to_string()))
    }

    pub fn with_base(base: impl Into<String>) -> Self {
        let http = reqwest::Client::builder()
            .user_agent(USER_AGENT)
            .timeout(Duration::from_secs(10))
            .build()
            .expect("reqwest client");
        Self {
            http,
            base: base.into(),
            departure_cache: Arc::new(Mutex::new(HashMap::new())),
            plan_cache: Arc::new(Mutex::new(HashMap::new())),
            rank_cache: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    async fn get_json<T: serde::de::DeserializeOwned>(&self, path: &str, query: &[(&str, String)]) -> Result<T> {
        let url = format!("{}{}", self.base, path);
        let resp = self
            .http
            .get(&url)
            .query(query)
            .send()
            .await
            .with_context(|| format!("GET {url}"))?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            return Err(anyhow!("GET {url} -> {status}: {}", body.chars().take(200).collect::<String>()));
        }
        resp.json::<T>().await.with_context(|| format!("decode {url}"))
    }

    /// The best railway stations near a point (docs/23 §1). The eight nearest candidates are
    /// classified by what actually departs there; a stop that is only tram, bus or subway is
    /// dropped, and the rest are ordered so that inside a 300 m band the better station wins.
    /// At most three come back: the one the card offers and two alternatives.
    pub async fn nearby_stops(&self, lat: f64, lon: f64) -> Result<Vec<StopInfo>> {
        let places: Vec<GeoPlace> = self
            .get_json("/api/v1/reverse-geocode", &[("place", format!("{lat},{lon}")), ("type", "STOP".into())])
            .await?;
        let mut candidates: Vec<StopInfo> = places
            .into_iter()
            .filter(|p| p.r#type.as_deref() == Some("STOP"))
            .map(|p| StopInfo {
                distance_m: Some(haversine_m(lat, lon, p.lat, p.lon).round() as i64),
                id: p.id,
                name: crate::train::display_station_name(&p.name),
                lat: p.lat,
                lon: p.lon,
                rail_rank: None,
            })
            .collect();
        candidates.sort_by_key(|s| s.distance_m.unwrap_or(i64::MAX));
        candidates.truncate(NEARBY_CANDIDATES);

        let mut set = JoinSet::new();
        for (idx, stop) in candidates.iter().enumerate() {
            let client = self.clone();
            let (id, name) = (stop.id.clone(), stop.name.clone());
            set.spawn(async move { (idx, client.rank_of(&id, &name).await) });
        }
        let mut ranks: Vec<i32> = vec![0; candidates.len()];
        while let Some(res) = set.join_next().await {
            if let Ok((idx, rank)) = res {
                ranks[idx] = rank;
            }
        }
        let mut kept: Vec<StopInfo> = candidates
            .into_iter()
            .zip(ranks)
            .filter_map(|(mut s, rank)| {
                if rank == 0 {
                    return None;
                }
                s.rail_rank = Some(rank);
                Some(s)
            })
            .collect();
        kept.sort_by(|a, b| {
            nearby_order(a.distance_m.unwrap_or(i64::MAX), a.rail_rank.unwrap_or(0), &a.name)
                .cmp(&nearby_order(b.distance_m.unwrap_or(i64::MAX), b.rail_rank.unwrap_or(0), &b.name))
        });
        kept.truncate(NEARBY_RESULTS);
        Ok(kept)
    }

    /// What kind of station this stop is (docs/23 §1), from what really departs there.
    ///
    /// Deliberately **not** `departures`: that call passes `radius=300`, so every stop within
    /// 300 m inherits its neighbours' departures — which is precisely how a tram stop at the
    /// entrance of München Hbf passed for a railway station. Here the stop answers for itself.
    /// A query that fails leaves the name to decide and is not cached.
    async fn rank_of(&self, stop_id: &str, name: &str) -> i32 {
        if let Some((at, rank)) = self.rank_cache.lock().unwrap().get(stop_id) {
            if at.elapsed() < RANK_CACHE_TTL {
                return *rank;
            }
        }
        let resp: Result<StopTimesResponse> = self
            .get_json(
                "/api/v1/stoptimes",
                &[("stopId", stop_id.to_string()), ("n", RANK_DEPARTURES.to_string()), ("mode", RANK_MODES.to_string())],
            )
            .await;
        let Ok(resp) = resp else {
            tracing::debug!(stop = stop_id, "ranking query failed; falling back to the name");
            return rail_rank(&[], name);
        };
        let deps: Vec<(String, String)> = resp
            .stop_times
            .into_iter()
            .map(|st| (st.mode, st.route_short_name.unwrap_or_default()))
            .collect();
        let pairs: Vec<(&str, &str)> = deps.iter().map(|(m, l)| (m.as_str(), l.as_str())).collect();
        let rank = rail_rank(&pairs, name);
        self.rank_cache.lock().unwrap().insert(stop_id.to_string(), (Instant::now(), rank));
        rank
    }

    /// Station search by name.
    pub async fn search_stops(&self, text: &str) -> Result<Vec<StopInfo>> {
        let places: Vec<GeoPlace> = self
            .get_json("/api/v1/geocode", &[("text", text.to_string()), ("language", "de".into())])
            .await?;
        Ok(places
            .into_iter()
            .filter(|p| p.r#type.as_deref() == Some("STOP"))
            .map(|p| StopInfo { id: p.id, name: crate::train::display_station_name(&p.name), lat: p.lat, lon: p.lon, distance_m: None, rail_rank: None })
            .collect())
    }

    /// Rail departures at a stop, soonest first. Cached for 30 s per stop.
    pub async fn departures(&self, stop_id: &str, n: usize) -> Result<Vec<DepartureInfo>> {
        if let Some(hit) = self.cached(stop_id) {
            return Ok(hit.into_iter().take(n).collect());
        }
        let fetch_n = n.max(20);
        let resp: StopTimesResponse = self
            .get_json(
                "/api/v1/stoptimes",
                &[("stopId", stop_id.to_string()), ("n", fetch_n.to_string()), ("radius", "300".into())],
            )
            .await?;
        let mut out: Vec<DepartureInfo> = resp
            .stop_times
            .into_iter()
            .filter(|st| is_rail_mode(&st.mode))
            .filter_map(departure_from)
            .collect();
        out.sort_by_key(|d| d.planned_departure);
        out.dedup_by(|a, b| a.trip_id == b.trip_id);
        self.departure_cache
            .lock()
            .unwrap()
            .insert(stop_id.to_string(), (Instant::now(), out.clone()));
        Ok(out.into_iter().take(n).collect())
    }

    fn cached(&self, stop_id: &str) -> Option<Vec<DepartureInfo>> {
        let cache = self.departure_cache.lock().unwrap();
        cache
            .get(stop_id)
            .filter(|(at, _)| at.elapsed() < DEPARTURE_CACHE_TTL)
            .map(|(_, v)| v.clone())
    }

    /// Rail itineraries from one stop to another at (or after) `time`. Walks between platforms
    /// are folded into the transfer; an itinerary with a bus or tram leg is dropped. Cached for
    /// 60 s per (from, to, minute) so a burst of app requests is one call to Transitous.
    pub async fn plan(&self, from: &str, to: &str, time: DateTime<Utc>, n: usize) -> Result<Vec<Itinerary>> {
        let key = format!("{from}|{to}|{}", time.format("%Y-%m-%dT%H:%M"));
        if let Some((at, v)) = self.plan_cache.lock().unwrap().get(&key) {
            if at.elapsed() < PLAN_CACHE_TTL {
                return Ok(v.clone());
            }
        }
        let resp: PlanResponse = self
            .get_json(
                "/api/v1/plan",
                &[
                    ("fromPlace", from.to_string()),
                    ("toPlace", to.to_string()),
                    ("time", time.to_rfc3339_opts(chrono::SecondsFormat::Secs, true)),
                    ("numItineraries", n.max(1).to_string()),
                    ("transitModes", PLAN_MODES.to_string()),
                ],
            )
            .await?;
        let mut out: Vec<Itinerary> = resp.itineraries.into_iter().filter_map(itinerary_from).collect();
        out.sort_by_key(|i| i.planned_departure);
        out.dedup_by(|a, b| a.legs.iter().map(|l| l.trip_id.as_str()).eq(b.legs.iter().map(|l| l.trip_id.as_str())));
        self.plan_cache.lock().unwrap().insert(key, (Instant::now(), out.clone()));
        Ok(out)
    }

    /// One trip with all its stops and live times.
    pub async fn trip(&self, trip_id: &str) -> Result<TripInfo> {
        let resp: TripResponse = self.get_json("/api/v1/trip", &[("tripId", trip_id.to_string())]).await?;
        let leg = resp
            .legs
            .iter()
            .find(|l| l.trip_id.as_deref() == Some(trip_id))
            .or_else(|| resp.legs.iter().find(|l| is_rail_mode(&l.mode)))
            .or_else(|| resp.legs.first())
            .ok_or_else(|| anyhow!("trip {trip_id}: no legs"))?;
        let (line, train_number) = parse_line(leg.route_short_name.as_deref().unwrap_or(""));
        let agency_name = leg.agency_name.clone().unwrap_or_default();
        let mut stops = Vec::with_capacity(leg.intermediate_stops.len() + 2);
        stops.push(trip_stop_from(&leg.from));
        stops.extend(leg.intermediate_stops.iter().map(trip_stop_from));
        stops.push(trip_stop_from(&leg.to));
        Ok(TripInfo {
            trip_id: leg.trip_id.clone().unwrap_or_else(|| trip_id.to_string()),
            category: category_for(&leg.mode, &line),
            operator: agency_to_operator(&agency_name),
            line,
            train_number,
            headsign: leg.headsign.clone().unwrap_or_default(),
            agency_name,
            mode: leg.mode.clone(),
            realtime: leg.real_time.unwrap_or(false),
            cancelled: leg.cancelled.unwrap_or(false),
            stops,
        })
    }
}

/// What one departure says about the stop it leaves from (docs/23 §1).
///
/// The S-Bahn keeps a place: German S-Bahnen are Schienenpersonennahverkehr, their delays are
/// claimable like a regional train's, and ranked lowest they can never beat a Hauptbahnhof in
/// the same band. This feed reports them as `METRO`, which is also what the U-Bahn arrives as,
/// so the line name decides: `S1` is rail, `U1` is not.
pub fn mode_rank(mode: &str, line: &str) -> i32 {
    match mode {
        "LONG_DISTANCE" | "HIGHSPEED_RAIL" | "NIGHT_RAIL" => 3,
        "RAIL" | "REGIONAL_RAIL" | "REGIONAL_FAST_RAIL" => 2,
        "SUBURBAN" => 1,
        "METRO" | "SUBWAY" => {
            if is_s_bahn_line(line) {
                1
            } else {
                0
            }
        }
        _ => 0,
    }
}

/// "S1", "S 8" — an S-Bahn line; "U2", "18", "X30" are not.
fn is_s_bahn_line(line: &str) -> bool {
    let mut cs = line.trim().chars();
    matches!(cs.next(), Some('S') | Some('s')) && cs.find(|c| !c.is_whitespace()).is_some_and(|c| c.is_ascii_digit())
}

/// How much of a railway station a stop is, from what departs there (docs/23 §1), as
/// `(mode, line)` pairs. A stop with no rail departure in the window still counts as a small
/// station when its name says so — a Hauptbahnhof at midnight must not disappear.
pub fn rail_rank(departures: &[(&str, &str)], name: &str) -> i32 {
    let best = departures.iter().map(|(m, l)| mode_rank(m, l)).max().unwrap_or(0);
    if best == 0 && looks_like_station(name) {
        1
    } else {
        best
    }
}

/// The order the nearby stations come back in (docs/23 §1): the 300 m band first, the better
/// station inside it, then the one that carries a station's name, then distance. So a
/// Hauptbahnhof at 250 m beats a stop at 60 m, and beyond the band distance decides again.
///
/// The name is a tiebreaker because feeds carry the same station under several ids: at München
/// Hbf, Transitous also has an SNCF stop called plain "Munich", 90 m from the entrance and just
/// as long-distance. Two stops of the same rank inside one 300 m band are in practice one
/// station, and then the passenger should read the name they see on the building.
pub fn nearby_order(distance_m: i64, rail_rank: i32, name: &str) -> (i64, i32, i32, i64) {
    (distance_m / RANK_BAND_M, -rail_rank, if looks_like_station(name) { 0 } else { 1 }, distance_m)
}

fn looks_like_station(name: &str) -> bool {
    let n = name.trim_end_matches(')').trim();
    n.ends_with("Hbf") || n.ends_with("Hauptbahnhof") || n.ends_with("Bahnhof") || n.ends_with(" Bf") || n.contains(" Hbf")
}

fn departure_from(st: StopTime) -> Option<DepartureInfo> {
    let planned = st.place.scheduled_departure.or(st.place.departure)?;
    let live = if st.real_time.unwrap_or(false) { st.place.departure } else { None };
    let delay_min = live.map(|l| (l - planned).num_minutes()).unwrap_or(0);
    let (line, train_number) = parse_line(st.route_short_name.as_deref().unwrap_or(""));
    let agency_name = st.agency_name.unwrap_or_default();
    Some(DepartureInfo {
        trip_id: st.trip_id?,
        category: category_for(&st.mode, &line),
        operator: agency_to_operator(&agency_name),
        line,
        train_number,
        headsign: st.headsign.unwrap_or_default(),
        agency_name,
        mode: st.mode,
        planned_departure: planned,
        live_departure: live,
        delay_min,
        platform: st.place.track.or(st.place.scheduled_track),
        cancelled: st.cancelled.unwrap_or(false) || st.trip_cancelled.unwrap_or(false) || st.place.cancelled.unwrap_or(false),
        realtime: st.real_time.unwrap_or(false),
    })
}

/// A MOTIS itinerary → ours, or None when a leg is not railway service.
fn itinerary_from(it: PlanItinerary) -> Option<Itinerary> {
    let mut legs = Vec::new();
    for l in it.legs.into_iter().filter(|l| l.mode != "WALK") {
        let (line, train_number) = parse_line(l.route_short_name.as_deref().unwrap_or(""));
        // A bus under a train's line number is a replacement and belongs to the journey; any
        // other bus means this itinerary is not a rail journey at all (docs/28).
        if !crate::train::is_journey_mode(&l.mode, &line) {
            return None;
        }
        let agency_name = l.agency_name.clone().unwrap_or_default();
        let planned_departure = l.from.scheduled_departure.or(l.scheduled_start_time).or(l.from.departure)?;
        let planned_arrival = l.to.scheduled_arrival.or(l.scheduled_end_time).or(l.to.arrival)?;
        let realtime = l.real_time.unwrap_or(false);
        let live_departure = if realtime { l.from.departure.or(l.start_time) } else { None };
        let live_arrival = if realtime { l.to.arrival.or(l.end_time) } else { None };
        let cancelled = l.cancelled.unwrap_or(false) || l.from.cancelled.unwrap_or(false) || l.to.cancelled.unwrap_or(false);
        legs.push(PlanLeg {
            trip_id: l.trip_id.clone()?,
            category: category_for(&l.mode, &line),
            operator: agency_to_operator(&agency_name),
            line,
            train_number,
            headsign: l.headsign.clone().unwrap_or_default(),
            agency_name,
            mode: l.mode.clone(),
            from_station_id: l.from.stop_id.clone()?,
            from_station_name: crate::train::display_station_name(l.from.name.as_deref().unwrap_or("")),
            to_station_id: l.to.stop_id.clone()?,
            to_station_name: crate::train::display_station_name(l.to.name.as_deref().unwrap_or("")),
            planned_departure,
            planned_arrival,
            live_departure,
            live_arrival,
            platform: l.from.track.clone().or(l.from.scheduled_track.clone()),
            cancelled,
            realtime,
            delay_min: live_arrival.map(|a| (a - planned_arrival).num_minutes()).unwrap_or(0),
        });
    }
    let first = legs.first()?;
    let last = legs.last()?;
    Some(Itinerary {
        id: it.id.unwrap_or_default(),
        transfers: (legs.len() as i64 - 1).max(0),
        planned_departure: first.planned_departure,
        planned_arrival: last.planned_arrival,
        live_arrival: last.live_arrival,
        duration_min: (last.planned_arrival - first.planned_departure).num_minutes(),
        legs,
    })
}

fn trip_stop_from(p: &TripPlace) -> TripStop {
    TripStop {
        stop_id: p.stop_id.clone(),
        name: p.name.clone().unwrap_or_default(),
        scheduled_arrival: p.scheduled_arrival,
        live_arrival: p.arrival,
        scheduled_departure: p.scheduled_departure,
        live_departure: p.departure,
        cancelled: p.cancelled.unwrap_or(false),
    }
}

// ---------------------------------------------------------------------------
// Wire shapes (only the fields we read)
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
struct GeoPlace {
    id: String,
    name: String,
    lat: f64,
    lon: f64,
    #[serde(rename = "type")]
    r#type: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StopTimesResponse {
    #[serde(default)]
    stop_times: Vec<StopTime>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StopTime {
    place: TripPlace,
    mode: String,
    real_time: Option<bool>,
    headsign: Option<String>,
    agency_name: Option<String>,
    route_short_name: Option<String>,
    trip_id: Option<String>,
    cancelled: Option<bool>,
    trip_cancelled: Option<bool>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TripPlace {
    name: Option<String>,
    stop_id: Option<String>,
    scheduled_departure: Option<DateTime<Utc>>,
    departure: Option<DateTime<Utc>>,
    scheduled_arrival: Option<DateTime<Utc>>,
    arrival: Option<DateTime<Utc>>,
    track: Option<String>,
    scheduled_track: Option<String>,
    cancelled: Option<bool>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PlanResponse {
    #[serde(default)]
    itineraries: Vec<PlanItinerary>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PlanItinerary {
    id: Option<String>,
    #[serde(default)]
    legs: Vec<Leg>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TripResponse {
    #[serde(default)]
    legs: Vec<Leg>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Leg {
    mode: String,
    from: TripPlace,
    to: TripPlace,
    #[serde(default)]
    intermediate_stops: Vec<TripPlace>,
    real_time: Option<bool>,
    cancelled: Option<bool>,
    headsign: Option<String>,
    agency_name: Option<String>,
    trip_id: Option<String>,
    route_short_name: Option<String>,
    scheduled_start_time: Option<DateTime<Utc>>,
    scheduled_end_time: Option<DateTime<Utc>>,
    start_time: Option<DateTime<Utc>>,
    end_time: Option<DateTime<Utc>>,
}

#[cfg(test)]
mod tests {
    use super::*;

    const KOELN_HBF: &str = "be-sncb_8015458";

    #[test]
    fn stoptime_shape_parses() {
        let raw = r#"{"stopTimes":[{"place":{"name":"Köln Hbf","stopId":"be-sncb_8015458","scheduledDeparture":"2026-09-09T18:11:00Z","departure":"2026-09-09T18:31:00Z","track":"7"},"mode":"HIGHSPEED_RAIL","realTime":true,"headsign":"Dortmund Hbf","agencyName":"DB Fernverkehr AG","routeShortName":"ICE 26","tripId":"t1","cancelled":false,"tripCancelled":false},{"place":{"name":"Köln Hbf","scheduledDeparture":"2026-09-09T18:30:00Z","departure":"2026-09-09T18:31:00Z"},"mode":"TRAM","realTime":true,"routeShortName":"18","tripId":"t2"}]}"#;
        let resp: StopTimesResponse = serde_json::from_str(raw).unwrap();
        let deps: Vec<DepartureInfo> = resp.stop_times.into_iter().filter(|s| is_rail_mode(&s.mode)).filter_map(departure_from).collect();
        assert_eq!(deps.len(), 1);
        assert_eq!(deps[0].line, "ICE 26");
        assert_eq!(deps[0].delay_min, 20);
        assert_eq!(deps[0].platform.as_deref(), Some("7"));
        assert_eq!(deps[0].operator, "DB Fernverkehr");
        assert_eq!(deps[0].category, super::super::TrainCategory::Fern);
    }

    #[test]
    fn trip_shape_parses() {
        let raw = r#"{"legs":[{"mode":"REGIONAL_RAIL","from":{"name":"Rheine, Bahnhof","stopId":"a","scheduledDeparture":"2026-09-09T15:08:00Z","departure":"2026-09-09T15:35:00Z"},"to":{"name":"Krefeld Hbf","stopId":"z","scheduledArrival":"2026-09-09T18:24:00Z","arrival":"2026-09-09T19:48:00Z"},"intermediateStops":[{"name":"Münster Hauptbahnhof","stopId":"m","scheduledArrival":"2026-09-09T15:33:00Z","arrival":"2026-09-09T16:06:00Z","cancelled":false}],"realTime":true,"cancelled":false,"headsign":"Krefeld Hbf","agencyName":"National Express","tripId":"t","routeShortName":"RE7 (17429)"}]}"#;
        let resp: TripResponse = serde_json::from_str(raw).unwrap();
        assert_eq!(resp.legs[0].intermediate_stops.len(), 1);
        let leg = &resp.legs[0];
        let stop = trip_stop_from(&leg.intermediate_stops[0]);
        assert_eq!((stop.live_arrival.unwrap() - stop.scheduled_arrival.unwrap()).num_minutes(), 33);
    }

    #[test]
    fn plan_shape_parses_and_folds_walks() {
        let raw = r#"{"itineraries":[{"id":"it1","transfers":1,"legs":[
          {"mode":"LONG_DISTANCE","from":{"name":"Köln Hbf","stopId":"a","scheduledDeparture":"2026-09-10T15:46:00Z","departure":"2026-09-10T16:01:00Z","track":"4"},"to":{"name":"Düsseldorf Hbf","stopId":"b","scheduledArrival":"2026-09-10T16:08:00Z","arrival":"2026-09-10T16:23:00Z"},"realTime":true,"agencyName":"DB Fernverkehr AG","routeShortName":"IC 2006","headsign":"Emden","tripId":"t1"},
          {"mode":"WALK","from":{"name":"Düsseldorf Hbf","stopId":"b"},"to":{"name":"Düsseldorf Hbf","stopId":"b2"}},
          {"mode":"REGIONAL_RAIL","from":{"name":"Düsseldorf Hbf","stopId":"b2","scheduledDeparture":"2026-09-10T16:38:00Z"},"to":{"name":"Kleve Bahnhof","stopId":"c","scheduledArrival":"2026-09-10T18:05:00Z"},"realTime":false,"agencyName":"NordWestBahn GmbH","routeShortName":"RE10 (82294)","headsign":"Kleve","tripId":"t2"}]},
          {"id":"it2","transfers":0,"legs":[{"mode":"BUS","from":{"name":"x","stopId":"x","scheduledDeparture":"2026-09-10T16:00:00Z"},"to":{"name":"y","stopId":"y","scheduledArrival":"2026-09-10T17:00:00Z"},"tripId":"t3"}]}]}"#;
        let resp: PlanResponse = serde_json::from_str(raw).unwrap();
        let its: Vec<Itinerary> = resp.itineraries.into_iter().filter_map(itinerary_from).collect();
        assert_eq!(its.len(), 1, "the bus itinerary is dropped");
        let it = &its[0];
        assert_eq!(it.legs.len(), 2, "the walk is folded");
        assert_eq!(it.transfers, 1);
        assert_eq!(it.transfer_stations(), vec!["Düsseldorf Hbf".to_string()]);
        assert_eq!(it.legs[0].line, "IC 2006");
        assert_eq!(it.legs[0].delay_min, 15);
        assert_eq!(it.legs[0].platform.as_deref(), Some("4"));
        assert_eq!(it.legs[1].line, "RE 10");
        assert_eq!(it.legs[1].operator, "NordWestBahn");
        assert_eq!(it.duration_min, 139);
    }

    /// docs/23 §1: München Hbf, not the Seidlstraße stop 60 m from the entrance.
    #[test]
    fn the_hauptbahnhof_wins_the_band() {
        // What departs decides the rank. The modes and lines are the ones Transitous really
        // returned for these stations on 11 September 2026.
        let muenchen_hbf = [("METRO", "S2"), ("SUBWAY", "U5"), ("HIGHSPEED_RAIL", "ICE 880"), ("LONG_DISTANCE", "EC 113")];
        assert_eq!(rail_rank(&muenchen_hbf, "München Hauptbahnhof"), 3);
        assert_eq!(rail_rank(&[("REGIONAL_RAIL", "RB 58")], "Deisenhofen"), 2);
        assert_eq!(rail_rank(&[("REGIONAL_FAST_RAIL", "RE 7")], "Rheine"), 2);

        // The S-Bahn keeps its place, whichever mode the feed calls it by; the U-Bahn does not.
        assert_eq!(rail_rank(&[("METRO", "S7"), ("METRO", "S2")], "Köln Hansaring"), 1, "an S-Bahn station is a station");
        assert_eq!(rail_rank(&[("SUBURBAN", "S 12")], "Köln Hansaring"), 1, "other feeds say SUBURBAN for the same thing");
        assert_eq!(rail_rank(&[("SUBWAY", "U2"), ("SUBWAY", "U5")], "Königsplatz"), 0, "a U-Bahn station is not a railway station");
        assert_eq!(rail_rank(&[("TRAM", "18"), ("BUS", "X30")], "Elisenstraße"), 0);

        // Seidlstraße, asked without a radius, has no rail departure and no station name: dropped.
        assert_eq!(rail_rank(&[], "Seidlstraße"), 0, "the stop Johannes was offered disappears");
        assert_eq!(rail_rank(&[], "München Hbf"), 1, "a station by name keeps a place when nothing departs in the window");

        // Inside the same 300 m band the better station wins.
        let hbf = nearby_order(250, 3, "München Hauptbahnhof");
        let tram = nearby_order(60, 1, "Hackerbrücke");
        assert!(hbf < tram, "München Hbf at 250 m beats an S-Bahn-only stop at 60 m");

        // Beyond the band distance decides again.
        let far_hbf = nearby_order(1200, 3, "München Hauptbahnhof");
        let near_halt = nearby_order(280, 2, "Deisenhofen");
        assert!(near_halt < far_hbf, "a regional station 280 m away beats a Hauptbahnhof 1,2 km away");

        // Same band, same rank: the one that carries the station's name, then the nearer one.
        assert!(nearby_order(190, 3, "München Hauptbahnhof") < nearby_order(97, 3, "Munich"), "the same station under two ids: the name on the building wins");
        assert!(nearby_order(120, 3, "Köln Hbf") < nearby_order(280, 3, "Köln Hbf"));
    }

    /// Live API. Run with `cargo test -- --ignored`.
    #[tokio::test]
    #[ignore]
    async fn live_koeln_hbf() {
        let c = TransitousClient::new();
        let deps = c.departures(KOELN_HBF, 10).await.unwrap();
        assert!(!deps.is_empty());
        let trip = c.trip(&deps[0].trip_id).await.unwrap();
        assert!(trip.stops.len() >= 2, "{trip:?}");
        let near = c.nearby_stops(50.9430, 6.9586).await.unwrap();
        assert!(near.iter().any(|s| s.name.contains("Köln")), "{near:?}");
        // docs/23 §1: at the Munich main station's entrance, the Hauptbahnhof is offered, not
        // the tram stop 60 m away. Three at most, best first.
        let munich = c.nearby_stops(48.1402, 11.5600).await.unwrap();
        assert!(munich.len() <= 3, "{munich:?}");
        assert!(munich[0].name.contains("Hauptbahnhof") || munich[0].name.contains("Hbf"), "{munich:?}");
        assert_eq!(munich[0].rail_rank, Some(3), "{munich:?}");
        assert!(!munich.iter().any(|s| s.name.contains("Seidlstraße")), "the tram stop is gone: {munich:?}");
        let found = c.search_stops("Münster Hbf").await.unwrap();
        assert!(!found.is_empty());
    }
}
