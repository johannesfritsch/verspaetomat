//! Fixture types: the seed data shapes (operators, NGOs, badges, seeded boards, community baseline).
//! Live data uses `db::rows` and `train::*`.

use chrono::NaiveDate;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Operator {
    pub name: String,
    pub desk: String,
    pub postal_address: String,
    #[serde(default)]
    pub email: Option<String>,
    #[serde(default)]
    pub accepts_email: bool,
    #[serde(default)]
    pub last_verified: Option<NaiveDate>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Ngo {
    pub id: String,
    pub name: String,
    pub tagline: String,
    pub story: Vec<String>,
    pub account_holder: String,
    pub iban: String,
    pub donation_url: String,
    pub last_report: Option<NaiveDate>,
    #[serde(default)]
    pub confirmed_total_cents: i64,
    #[serde(default)]
    pub submitted_total_cents: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Badge {
    pub id: String,
    pub name: String,
    pub rule: String,
    #[serde(default)]
    pub earned_on: Option<NaiveDate>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BoardEntry {
    pub rank: i64,
    pub name: String,
    pub points: i64,
    #[serde(default)]
    pub is_me: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Boards {
    pub line: Vec<BoardEntry>,
    pub city: Vec<BoardEntry>,
    pub germany: Vec<BoardEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Community {
    pub minutes: i64,
    pub submitted_cents: i64,
    pub confirmed_cents: i64,
    pub users: i64,
}
