//! Live train data: the Transitous (MOTIS) adapter and the trip follower.
//!
//! Public surface used by main.rs and handlers:
//! - `transitous::TransitousClient::new()` then `nearby_stops`, `search_stops`, `departures`, `trip`
//! - `follower::spawn(pool, client, interval)` returns a broadcast sender of `RideFinalised`
//! - `follower::finalise_ride(...)` for manual arrivals (E3) and demo controls
//! - `agency_to_operator`, `normalise_station_name`, `station_names_match`

#![allow(dead_code)]

pub mod follower;
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
