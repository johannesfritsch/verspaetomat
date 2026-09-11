//! Live train data: the Transitous (MOTIS) adapter and the trip follower.
//!
//! Public surface used by main.rs and handlers:
//! - `transitous::TransitousClient::new()` then `nearby_stops`, `search_stops`, `departures`, `trip`, `plan`
//! - `follower::spawn(pool, client, interval)` returns a broadcast sender of `RideFinalised`
//! - `follower::finalise_ride(...)` for manual arrivals (E3) and demo controls
//! - `agency_to_operator`, `normalise_station_name`, `station_names_match`

#![allow(dead_code)]

pub mod follower;
pub mod sim;
pub mod transitous;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Same values as the app and the database enum `train_category`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TrainCategory {
    S,
    Rb,
    Re,
    Fern,
    Bus,
}

impl TrainCategory {
    pub fn as_str(self) -> &'static str {
        match self {
            TrainCategory::S => "s",
            TrainCategory::Rb => "rb",
            TrainCategory::Re => "re",
            TrainCategory::Fern => "fern",
            TrainCategory::Bus => "bus",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StopInfo {
    pub id: String,
    pub name: String,
    pub lat: f64,
    pub lon: f64,
    pub distance_m: Option<i64>,
    /// How much of a railway station this stop is (docs/23 §1): 3 long distance, 2 rail or
    /// regional, 1 suburban only or a station by its name, 0 nothing rail-like. Only the
    /// nearby list ranks; a searched station carries None.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rail_rank: Option<i32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DepartureInfo {
    pub trip_id: String,
    /// "RE 7", "S 12", "ICE 26"
    pub line: String,
    /// The parenthesised train number from the feed, e.g. "17429".
    pub train_number: Option<String>,
    pub headsign: String,
    pub agency_name: String,
    /// Our operator name (mapped from the agency name).
    pub operator: String,
    pub category: TrainCategory,
    pub mode: String,
    pub planned_departure: DateTime<Utc>,
    pub live_departure: Option<DateTime<Utc>>,
    pub delay_min: i64,
    pub platform: Option<String>,
    pub cancelled: bool,
    pub realtime: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TripStop {
    pub stop_id: Option<String>,
    pub name: String,
    pub scheduled_arrival: Option<DateTime<Utc>>,
    pub live_arrival: Option<DateTime<Utc>>,
    pub scheduled_departure: Option<DateTime<Utc>>,
    pub live_departure: Option<DateTime<Utc>>,
    pub cancelled: bool,
}

/// One rail leg of a planned itinerary (docs/17 "Leg").
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanLeg {
    pub trip_id: String,
    pub line: String,
    #[serde(default)]
    pub train_number: Option<String>,
    pub headsign: String,
    #[serde(default)]
    pub agency_name: String,
    pub operator: String,
    pub category: TrainCategory,
    #[serde(default)]
    pub mode: String,
    pub from_station_id: String,
    pub from_station_name: String,
    pub to_station_id: String,
    pub to_station_name: String,
    pub planned_departure: DateTime<Utc>,
    pub planned_arrival: DateTime<Utc>,
    pub live_departure: Option<DateTime<Utc>>,
    pub live_arrival: Option<DateTime<Utc>>,
    #[serde(default)]
    pub platform: Option<String>,
    #[serde(default)]
    pub cancelled: bool,
    #[serde(default)]
    pub realtime: bool,
    /// Live arrival delay at the leg's exit stop, minutes.
    #[serde(default)]
    pub delay_min: i64,
}

/// A planned journey from A to B: rail legs only, walks between platforms folded away.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Itinerary {
    pub id: String,
    pub transfers: i64,
    pub planned_departure: DateTime<Utc>,
    pub planned_arrival: DateTime<Utc>,
    pub live_arrival: Option<DateTime<Utc>>,
    pub duration_min: i64,
    pub legs: Vec<PlanLeg>,
}

impl Itinerary {
    pub fn transfer_stations(&self) -> Vec<String> {
        self.legs.iter().take(self.legs.len().saturating_sub(1)).map(|l| l.to_station_name.clone()).collect()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TripInfo {
    pub trip_id: String,
    pub line: String,
    pub train_number: Option<String>,
    pub headsign: String,
    pub agency_name: String,
    pub operator: String,
    pub category: TrainCategory,
    pub mode: String,
    pub realtime: bool,
    pub cancelled: bool,
    pub stops: Vec<TripStop>,
}

impl TripInfo {
    /// Find the exit stop by id first, then by (normalised) name.
    pub fn find_stop(&self, stop_id: Option<&str>, name: &str) -> Option<(usize, &TripStop)> {
        if let Some(id) = stop_id {
            if let Some(hit) = self.stops.iter().enumerate().find(|(_, s)| s.stop_id.as_deref() == Some(id)) {
                return Some(hit);
            }
        }
        self.stops.iter().enumerate().find(|(_, s)| station_names_match(&s.name, name))
    }
}

/// MOTIS modes that count as railway service under the passenger-rights rules
/// (S-Bahn up to ICE). Metro, tram and bus are out.
pub fn is_rail_mode(mode: &str) -> bool {
    matches!(
        mode,
        "HIGHSPEED_RAIL" | "LONG_DISTANCE" | "NIGHT_RAIL" | "REGIONAL_FAST_RAIL" | "REGIONAL_RAIL" | "RAIL" | "SUBURBAN"
    )
}

/// Schienenersatzverkehr: a bus doing a train's job (docs/28).
///
/// When a line is closed, the replacement runs under the **line's own number** — Kißlegg to
/// Aulendorf on a Friday evening is `BUS` with `routeShortName: "RB53"`, operated by DB ZugBus
/// Alb-Bodensee. A city bus is numbered `7`, `X41`, `N3`; a train is `RB 53`, `RE 96`, `S 12`.
/// The prefix is what tells them apart, and it is the only honest signal in the feed.
///
/// This matters beyond convenience: a replacement bus is part of the rail contract, so the
/// delay on it is claimable like any other — and the app has carried a `Schienenersatzverkehr`
/// badge since docs/12 for exactly this. Leaving these out meant the one journey most likely to
/// go wrong was the one journey the app could not plan.
pub fn is_rail_replacement(mode: &str, line: &str) -> bool {
    if mode != "BUS" && mode != "COACH" {
        return false;
    }
    let prefix: String = line.chars().take_while(|c| c.is_alphabetic()).collect::<String>().to_uppercase();
    let has_number = line.chars().any(|c| c.is_ascii_digit());
    has_number
        && matches!(
            prefix.as_str(),
            "ICE" | "IC" | "EC" | "ECE" | "RJ" | "RJX" | "NJ" | "FLX" | "TGV" | "EN" | "IR" | "RE" | "IRE" | "MEX" | "RRX" | "REX" | "RB" | "RS" | "S"
        )
}

/// A leg the app will carry: a train, or a bus standing in for one.
pub fn is_journey_mode(mode: &str, line: &str) -> bool {
    is_rail_mode(mode) || is_rail_replacement(mode, line)
}

/// **The one gate every row from the feed passes through** (docs/29).
///
/// Takes the raw shape — a mode and whatever the feed calls the line — so no caller has to
/// remember to parse the line first. Four places used to do that dance separately, and the fifth
/// would have forgotten: the departures board went a whole release without the rule the planner
/// already had, which is how a replacement bus showed up in one check-in path and not another.
pub fn feed_row_belongs(mode: &str, route_short_name: Option<&str>) -> bool {
    let (line, _) = parse_line(route_short_name.unwrap_or(""));
    is_journey_mode(mode, &line)
}

/// "RE7 (17429)" -> ("RE 7", Some("17429")); "S12" -> ("S 12", None); "ICE 26" -> ("ICE 26", None); "18" -> ("18", None)
pub fn parse_line(route_short_name: &str) -> (String, Option<String>) {
    let raw = route_short_name.trim();
    let (head, number) = match (raw.find('('), raw.rfind(')')) {
        (Some(a), Some(b)) if b > a => {
            let n = raw[a + 1..b].trim();
            (raw[..a].trim(), if n.is_empty() { None } else { Some(n.to_string()) })
        }
        _ => (raw, None),
    };
    // Insert one space between a leading letter block and the digits that follow it.
    let mut out = String::new();
    let mut prev_alpha = false;
    for (i, c) in head.chars().enumerate() {
        if i > 0 && prev_alpha && c.is_ascii_digit() {
            out.push(' ');
        }
        out.push(c);
        prev_alpha = c.is_alphabetic();
    }
    let out = out.split_whitespace().collect::<Vec<_>>().join(" ");
    (out, number)
}

/// Category from the line prefix first, then from the MOTIS mode.
pub fn category_for(mode: &str, line: &str) -> TrainCategory {
    let prefix: String = line.chars().take_while(|c| c.is_alphabetic()).collect::<String>().to_uppercase();
    match prefix.as_str() {
        "ICE" | "IC" | "EC" | "ECE" | "RJ" | "RJX" | "NJ" | "FLX" | "TGV" | "D" | "EN" | "IR" => return TrainCategory::Fern,
        "RE" | "IRE" | "MEX" | "RRX" | "REX" => return TrainCategory::Re,
        "RB" => return TrainCategory::Rb,
        "S" => return TrainCategory::S,
        _ => {}
    }
    match mode {
        "HIGHSPEED_RAIL" | "LONG_DISTANCE" | "NIGHT_RAIL" => TrainCategory::Fern,
        "REGIONAL_FAST_RAIL" => TrainCategory::Re,
        "REGIONAL_RAIL" | "RAIL" => TrainCategory::Rb,
        "SUBURBAN" => TrainCategory::S,
        "BUS" | "COACH" => TrainCategory::Bus,
        _ => TrainCategory::Rb,
    }
}

/// Feed agency names -> our operator names (docs/04-operators.md). Unknown names pass through.
pub fn agency_to_operator(agency: &str) -> String {
    let a = agency.trim();
    let mapped = match a {
        "DB Regio AG NRW" | "DB Regio AG" | "DB Regio NRW" | "DB Regio AG Region NRW" => "DB Regio NRW",
        "DB Fernverkehr AG" | "DB Fernverkehr" => "DB Fernverkehr",
        "National Express" | "National Express Rail GmbH" => "National Express",
        "NordWestBahn GmbH" | "NordWestBahn" => "NordWestBahn",
        "Ostdeutsche Eisenbahn GmbH" | "ODEG" => "ODEG",
        "eurobahn" | "eurobahn GmbH & Co. KG" => "eurobahn",
        _ => a,
    };
    mapped.to_string()
}

/// "Münster (Westf) Hbf" -> "münster hbf"; "Münster Hauptbahnhof" -> "münster hbf"; "Rheine, Bahnhof" -> "rheine"
pub fn normalise_station_name(name: &str) -> String {
    let mut s = String::with_capacity(name.len());
    let mut depth = 0usize;
    for c in name.chars() {
        match c {
            '(' => depth += 1,
            ')' => depth = depth.saturating_sub(1),
            _ if depth == 0 => s.push(c),
            _ => {}
        }
    }
    let s = s.replace("Hauptbahnhof", "Hbf").replace("hauptbahnhof", "hbf");
    let s = s.replace(", Bahnhof", "").replace(" Bahnhof", "").replace(", Bf", "").replace(" Bf", "");
    let s = s.replace(',', " ");
    s.split_whitespace().collect::<Vec<_>>().join(" ").to_lowercase()
}

/// Names match when equal after normalisation, or when one is a word-prefix of the other.
pub fn station_names_match(a: &str, b: &str) -> bool {
    let (na, nb) = (normalise_station_name(a), normalise_station_name(b));
    if na.is_empty() || nb.is_empty() {
        return false;
    }
    if na == nb {
        return true;
    }
    let (short, long) = if na.len() <= nb.len() { (&na, &nb) } else { (&nb, &na) };
    long.starts_with(short.as_str()) && long[short.len()..].starts_with(' ')
}

/// One record of a platform, as our lists carry it.
#[derive(Debug, Clone, Copy)]
pub struct StationRef<'a> {
    pub id: &'a str,
    pub name: &'a str,
    /// Where the platform is, when the list knows. The destination lists do not store it.
    pub at: Option<(f64, f64)>,
}

impl<'a> StationRef<'a> {
    pub fn at(id: &'a str, name: &'a str, lat: f64, lon: f64) -> Self {
        Self { id, name, at: Some((lat, lon)) }
    }
    pub fn named(id: &'a str, name: &'a str) -> Self {
        Self { id, name, at: None }
    }
}

/// **The one gate that decides whether two records are the same platform.** Every list of
/// stations we hand out passes through it.
///
/// One station has many stop ids. The rides behind the duplicate „Ab Kißlegg Bahnhof" on Home
/// carried `de-DELFI_de:08436:1159_G` and `de-DELFI_de:08436:1159:2:3` — the station node and one
/// of its quays, same feed, same name, same coordinates. So the customer got two chips, two of the
/// phone's twenty geofence regions for one station (docs/25 §2), and their check-ins split across
/// two rows, which also put the Stammbahnhof in the wrong place.
///
/// Two criteria, in order of how much they know:
///
/// 1. The id itself, where it is a German DHID (`de-DELFI_de:08436:1159:2:3` = country, regional
///    key, stop, quay, section): equal down to the stop is the same station, and the quay is not
///    our business. `_G` marks the station node and is not part of the number.
/// 2. Otherwise the name after [normalise_station_name], plus proximity where the list has
///    coordinates — which is what catches two feeds spelling one platform differently.
///
/// Deliberately stricter than [station_names_match]: that one accepts a word-prefix, and „Wangen"
/// is a word-prefix of „Wangen im Allgäu Nord" while being a different stop.
pub fn same_platform(a: StationRef<'_>, b: StationRef<'_>) -> bool {
    if a.id == b.id {
        return true;
    }
    if let (Some(x), Some(y)) = (dhid_station(a.id), dhid_station(b.id)) {
        if x == y {
            return true;
        }
    }
    let (na, nb) = (normalise_station_name(a.name), normalise_station_name(b.name));
    if na.is_empty() || na != nb {
        return false;
    }
    match (a.at, b.at) {
        (Some((alat, alon)), Some((blat, blon))) => haversine_m(alat, alon, blat, blon) <= SAME_PLATFORM_M,
        // Without coordinates the name is all there is. Two towns with the same station name do
        // exist; one shortcut for both is a smaller fault than the same name listed twice, and
        // the other station is still one search away.
        _ => true,
    }
}

/// Two feeds put the same platform a few hundred metres apart at most. A kilometre is generous
/// and still nowhere near the next town's station.
pub const SAME_PLATFORM_M: f64 = 1_000.0;

/// The station part of a German stop id: country, regional key and stop, without quay and section.
/// `None` for anything that is not shaped like one, which then falls back to name and distance.
fn dhid_station(id: &str) -> Option<String> {
    let mut parts = id.split(':');
    let (country, region, stop) = (parts.next()?, parts.next()?, parts.next()?);
    if country.is_empty() || region.is_empty() || stop.is_empty() {
        return None;
    }
    // `1159_G` is the same stop as `1159`.
    let stop = stop.split('_').next().unwrap_or(stop);
    Some(format!("{country}:{region}:{stop}"))
}

/// Great-circle distance in metres.
pub fn haversine_m(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let r = 6_371_000.0_f64;
    let (p1, p2) = (lat1.to_radians(), lat2.to_radians());
    let dp = (lat2 - lat1).to_radians();
    let dl = (lon2 - lon1).to_radians();
    let a = (dp / 2.0).sin().powi(2) + p1.cos() * p2.cos() * (dl / 2.0).sin().powi(2);
    2.0 * r * a.sqrt().atan2((1.0 - a).sqrt())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// docs/30: Home showed „Ab Kißlegg Bahnhof" twice. These are the two ids the production
    /// database actually held — the station node and one of its quays, one feed.
    #[test]
    fn the_station_node_and_its_quay_are_one_station() {
        let a = StationRef::at("de-DELFI_de:08436:1159_G", "Kißlegg Bahnhof", 47.7935, 9.8818);
        let b = StationRef::at("de-DELFI_de:08436:1159:2:3", "Kißlegg Bahnhof", 47.7935, 9.8818);
        assert!(same_platform(a, b));
        assert!(same_platform(b, a), "and the other way round");
        // The quay decides nothing, but the stop does.
        let other = StationRef::at("de-DELFI_de:08436:1160:1:1", "Kißlegg Nord", 47.7990, 9.8820);
        assert!(!same_platform(a, other));
    }

    /// And the case the id cannot answer: two feeds, two id shapes, one platform.
    #[test]
    fn one_platform_under_two_feed_ids() {
        let a = StationRef::at("de-DELFI_de:08436:1159_G", "Kißlegg Bahnhof", 47.7931, 9.8869);
        let b = StationRef::at("amarillo-bw:kisslegg", "Kißlegg", 47.7935, 9.8871);
        assert!(same_platform(a, b), "same name after normalisation, 40 m apart");
        assert!(same_platform(b, a), "and the other way round");
    }

    #[test]
    fn a_word_prefix_is_not_the_same_platform() {
        let a = StationRef::at("a", "Wangen", 47.6833, 9.8333);
        let b = StationRef::at("b", "Wangen im Allgäu Nord", 47.6900, 9.8400);
        assert!(!same_platform(a, b), "station_names_match would accept this; we must not");
    }

    #[test]
    fn the_same_name_in_another_town_stays_another_station() {
        let a = StationRef::at("a", "Neustadt", 49.3500, 8.1400);
        let b = StationRef::at("b", "Neustadt", 51.0300, 13.8100);
        assert!(!same_platform(a, b), "400 km apart");
        // Without coordinates the name is all we have, and one shortcut is better than two rows.
        assert!(same_platform(StationRef::named("a", "Neustadt"), StationRef::named("b", "Neustadt")));
    }

    #[test]
    fn an_empty_name_matches_only_its_own_id() {
        assert!(same_platform(StationRef::named("a", ""), StationRef::named("a", "Köln Hbf")));
        assert!(!same_platform(StationRef::named("a", ""), StationRef::named("b", "")));
    }

    /// docs/28: Kißlegg → Aulendorf on a Friday evening is a bus called RB53. Without this the
    /// app offered three changes through Memmingen for a journey that is one direct ride.
    #[test]
    fn a_bus_under_a_train_number_is_rail_replacement() {
        assert!(is_rail_replacement("BUS", "RB 53"));
        assert!(is_rail_replacement("BUS", "RB53"));
        assert!(is_rail_replacement("BUS", "RE 96"));
        assert!(is_rail_replacement("COACH", "IC 2013"));
        assert!(is_rail_replacement("BUS", "S 6"));

        // An ordinary bus is not a train, whatever it is called.
        assert!(!is_rail_replacement("BUS", "7"));
        assert!(!is_rail_replacement("BUS", "X41"));
        assert!(!is_rail_replacement("BUS", "N3"));
        assert!(!is_rail_replacement("BUS", "SEV"), "a line with no number tells us nothing");
        // A train is not a replacement; it is the thing being replaced.
        assert!(!is_rail_replacement("REGIONAL_RAIL", "RB 53"));
    }

    #[test]
    fn a_journey_is_trains_and_the_buses_stood_in_for_them() {
        assert!(is_journey_mode("REGIONAL_RAIL", "RB 53"));
        assert!(is_journey_mode("BUS", "RB 53"));
        assert!(!is_journey_mode("BUS", "7"));
        assert!(!is_journey_mode("TRAM", "1"));
    }

    use super::*;

    #[test]
    fn line_parsing() {
        assert_eq!(parse_line("RE7 (17429)"), ("RE 7".to_string(), Some("17429".to_string())));
        assert_eq!(parse_line("S12"), ("S 12".to_string(), None));
        assert_eq!(parse_line("ICE 26"), ("ICE 26".to_string(), None));
        assert_eq!(parse_line("RB38 (10282)"), ("RB 38".to_string(), Some("10282".to_string())));
        assert_eq!(parse_line("18"), ("18".to_string(), None));
        assert_eq!(parse_line("RE 5 (28532)"), ("RE 5".to_string(), Some("28532".to_string())));
    }

    #[test]
    fn categories() {
        assert_eq!(category_for("HIGHSPEED_RAIL", "ICE 26"), TrainCategory::Fern);
        assert_eq!(category_for("REGIONAL_RAIL", "RE 7"), TrainCategory::Re);
        assert_eq!(category_for("REGIONAL_RAIL", "RB 38"), TrainCategory::Rb);
        assert_eq!(category_for("SUBURBAN", "S 12"), TrainCategory::S);
        assert_eq!(category_for("REGIONAL_FAST_RAIL", "MEX 16"), TrainCategory::Re);
        assert_eq!(category_for("RAIL", "18"), TrainCategory::Rb);
        assert_eq!(category_for("BUS", "SEV"), TrainCategory::Bus);
    }

    #[test]
    fn rail_modes() {
        assert!(is_rail_mode("SUBURBAN"));
        assert!(is_rail_mode("HIGHSPEED_RAIL"));
        assert!(!is_rail_mode("TRAM"));
        assert!(!is_rail_mode("METRO"));
        assert!(!is_rail_mode("BUS"));
    }

    #[test]
    fn names() {
        assert_eq!(normalise_station_name("Münster (Westf) Hbf"), "münster hbf");
        assert_eq!(normalise_station_name("Münster Hauptbahnhof"), "münster hbf");
        assert_eq!(normalise_station_name("Rheine, Bahnhof"), "rheine");
        assert!(station_names_match("Münster Hauptbahnhof", "Münster (Westf) Hbf"));
        assert!(station_names_match("Rheine", "Rheine, Bahnhof"));
        assert!(station_names_match("Köln Hbf (DE)", "Köln Hbf"));
        assert!(!station_names_match("Köln Hbf", "Köln Messe/Deutz"));
        assert!(!station_names_match("Hamm (Westf) Hbf", "Hamburg Hbf"));
    }

    #[test]
    fn agencies() {
        assert_eq!(agency_to_operator("DB Regio AG NRW"), "DB Regio NRW");
        assert_eq!(agency_to_operator("DB Fernverkehr AG"), "DB Fernverkehr");
        assert_eq!(agency_to_operator("Kölner VB"), "Kölner VB");
    }

    #[test]
    fn distance() {
        let d = haversine_m(50.9430, 6.9586, 50.9410, 6.9750);
        assert!((1100.0..1300.0).contains(&d), "{d}");
    }
}

/// Feed names carry country suffixes like "Köln Hbf (DE)". The customer never needs them.
pub fn display_station_name(name: &str) -> String {
    let n = name.trim();
    let n = n.strip_suffix(" (DE)").unwrap_or(n);
    n.to_string()
}
