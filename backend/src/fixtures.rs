//! Fixtures embedded at compile time. Same invented data as the showcase app.

use crate::model::*;

fn load<T: serde::de::DeserializeOwned>(name: &str, raw: &str) -> T {
    serde_json::from_str(raw).unwrap_or_else(|e| panic!("fixture {name}: {e}"))
}

pub struct Fixtures {
    pub stations: Vec<Station>,
    pub departures: Vec<Departure>,
    pub operators: Vec<Operator>,
    pub ngos: Vec<Ngo>,
    pub badges: Vec<Badge>,
    pub incidents: Vec<Incident>,
    pub mails: Vec<Mail>,
    pub community: Community,
    pub boards: Boards,
    pub teams: Vec<Team>,
    pub me: Customer,
    pub rides: Vec<Ride>,
}

impl Fixtures {
    pub fn embedded() -> Self {
        Self {
            stations: load("stations", include_str!("../fixtures/stations.json")),
            departures: load("departures", include_str!("../fixtures/departures.json")),
            operators: load("operators", include_str!("../fixtures/operators.json")),
            ngos: load("ngos", include_str!("../fixtures/ngos.json")),
            badges: load("badges", include_str!("../fixtures/badges.json")),
            incidents: load("incidents", include_str!("../fixtures/incidents.json")),
            mails: load("mails", include_str!("../fixtures/mails.json")),
            community: load("community", include_str!("../fixtures/community.json")),
            boards: load("boards", include_str!("../fixtures/boards.json")),
            teams: load("teams", include_str!("../fixtures/teams.json")),
            me: load("me", include_str!("../fixtures/me.json")),
            rides: load("rides", include_str!("../fixtures/rides.json")),
        }
    }
}
