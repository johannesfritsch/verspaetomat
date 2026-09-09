//! Fixtures embedded at compile time. Same invented data as the showcase app.

use crate::model::*;

fn load<T: serde::de::DeserializeOwned>(name: &str, raw: &str) -> T {
    serde_json::from_str(raw).unwrap_or_else(|e| panic!("fixture {name}: {e}"))
}

pub struct Fixtures {
    pub operators: Vec<Operator>,
    pub ngos: Vec<Ngo>,
    pub badges: Vec<Badge>,
    pub community: Community,
    pub boards: Boards,
}

impl Fixtures {
    pub fn embedded() -> Self {
        Self {
            operators: load("operators", include_str!("../fixtures/operators.json")),
            ngos: load("ngos", include_str!("../fixtures/ngos.json")),
            badges: load("badges", include_str!("../fixtures/badges.json")),
            community: load("community", include_str!("../fixtures/community.json")),
            boards: load("boards", include_str!("../fixtures/boards.json")),
        }
    }
}
