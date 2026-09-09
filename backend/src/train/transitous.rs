//! Transitous (MOTIS v1) client. Verified shapes as of 9 September 2026.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::{anyhow, Context, Result};
use chrono::{DateTime, Utc};
use serde::Deserialize;
use tokio::task::JoinSet;

use super::{agency_to_operator, category_for, haversine_m, is_rail_mode, parse_line, DepartureInfo, StopInfo, TripInfo, TripStop};

const DEFAULT_BASE: &str = "https://api.transitous.org";
const USER_AGENT: &str = "verspaetomat-api/0.1 (+https://verspaetomat.de)";
const DEPARTURE_CACHE_TTL: Duration = Duration::from_secs(30);
const NEARBY_CANDIDATES: usize = 8;

#[derive(Clone)]
pub struct TransitousClient {
    http: reqwest::Client,
    base: String,
    departure_cache: Arc<Mutex<HashMap<String, (Instant, Vec<DepartureInfo>)>>>,
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
        Self { http, base: base.into(), departure_cache: Arc::new(Mutex::new(HashMap::new())) }
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

    /// Railway stations near a point, nearest first. Cheap filter: a candidate stays when it has
    /// at least one rail departure coming up, or its name says it is a station.
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
                name: p.name,
                lat: p.lat,
                lon: p.lon,
            })
            .collect();
        candidates.sort_by_key(|s| s.distance_m.unwrap_or(i64::MAX));
        candidates.truncate(NEARBY_CANDIDATES);

        let mut set = JoinSet::new();
        for (idx, stop) in candidates.iter().enumerate() {
            let client = self.clone();
            let id = stop.id.clone();
            set.spawn(async move { (idx, client.departures(&id, 5).await.map(|d| !d.is_empty()).unwrap_or(false)) });
        }
        let mut has_rail = vec![false; candidates.len()];
        while let Some(res) = set.join_next().await {
            if let Ok((idx, rail)) = res {
                has_rail[idx] = rail;
            }
        }
        let kept: Vec<StopInfo> = candidates
            .into_iter()
            .zip(has_rail)
            .filter(|(s, rail)| *rail || looks_like_station(&s.name))
            .map(|(s, _)| s)
            .collect();
        Ok(kept)
    }

    /// Station search by name.
    pub async fn search_stops(&self, text: &str) -> Result<Vec<StopInfo>> {
        let places: Vec<GeoPlace> = self
            .get_json("/api/v1/geocode", &[("text", text.to_string()), ("language", "de".into())])
            .await?;
        Ok(places
            .into_iter()
            .filter(|p| p.r#type.as_deref() == Some("STOP"))
            .map(|p| StopInfo { id: p.id, name: p.name, lat: p.lat, lon: p.lon, distance_m: None })
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
        let found = c.search_stops("Münster Hbf").await.unwrap();
        assert!(!found.is_empty());
    }
}
