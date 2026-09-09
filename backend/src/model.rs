//! Domain types. Mirrors docs/21-data-requirements.md. Amounts are euro cents.

use chrono::{NaiveDate, NaiveDateTime};
use serde::{Deserialize, Serialize};

pub type Cents = i64;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TicketType {
    Deutschlandticket,
    Zeitkarte,
    Einzelfahrkarte,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TrainCategory {
    S,
    Rb,
    Re,
    Fern,
    Bus,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Station {
    pub id: String,
    pub name: String,
    pub eva: Option<String>,
    pub lat: f64,
    pub lon: f64,
    #[serde(default)]
    pub distance_m: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Stop {
    pub name: String,
    /// "HH:MM"
    pub planned: String,
    #[serde(default)]
    pub delay_minutes: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Departure {
    pub id: String,
    pub station_id: String,
    pub line: String,
    pub destination: String,
    pub planned: String,
    pub platform: String,
    pub category: TrainCategory,
    pub operator: String,
    #[serde(default)]
    pub delay_minutes: i64,
    #[serde(default)]
    pub cancelled: bool,
    #[serde(default)]
    pub cause: Option<String>,
    pub stops: Vec<Stop>,
}

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
    pub confirmed_total_cents: Cents,
    #[serde(default)]
    pub submitted_total_cents: Cents,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Badge {
    pub id: String,
    pub name: String,
    pub rule: String,
    #[serde(default)]
    pub earned_on: Option<NaiveDate>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RideStatus {
    Riding,
    Arrived,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Ride {
    pub id: String,
    pub departure_id: String,
    pub line: String,
    pub operator: String,
    pub category: TrainCategory,
    pub from_station: String,
    pub exit_stop: String,
    pub planned_arrival: String,
    pub ticket: TicketType,
    pub checked_in_at: NaiveDateTime,
    pub location_verified: bool,
    pub status: RideStatus,
    pub passed_stops: usize,
    pub live_delay_minutes: i64,
    #[serde(default)]
    pub cause: Option<String>,
    #[serde(default)]
    pub final_delay_minutes: Option<i64>,
    #[serde(default)]
    pub cancelled: bool,
    #[serde(default)]
    pub self_entered: bool,
    #[serde(default)]
    pub nachtrag: bool,
    #[serde(default)]
    pub points: i64,
    pub date: NaiveDate,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum IncidentStatus {
    Gesammelt,
    Bereit,
    Eingereicht,
    Bestaetigt,
    Abgelehnt,
    Verfallen,
    Gedeckelt,
}

impl IncidentStatus {
    pub fn is_open(self) -> bool {
        matches!(self, IncidentStatus::Gesammelt | IncidentStatus::Bereit)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Evidence {
    pub planned_arrival: Option<String>,
    pub actual_arrival: Option<String>,
    pub source: String,
    pub fetched_at: NaiveDateTime,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Incident {
    pub id: String,
    pub ride_id: Option<String>,
    pub date: NaiveDate,
    pub line: String,
    pub from: String,
    pub to: String,
    pub delay_minutes: i64,
    pub amount_cents: Cents,
    pub ticket: TicketType,
    pub operator: String,
    pub desk: String,
    pub status: IncidentStatus,
    #[serde(default)]
    pub cancelled: bool,
    #[serde(default)]
    pub self_entered: bool,
    pub ngo_id: String,
    #[serde(default)]
    pub claim_id: Option<String>,
    #[serde(default)]
    pub fare_cents: Option<Cents>,
    pub legal_deadline: NaiveDate,
    #[serde(default)]
    pub evidence: Option<Evidence>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ClaimStatus {
    Draft,
    Sent,
    Question,
    Accepted,
    Rejected,
    Bounced,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claim {
    pub id: String,
    pub desk: String,
    pub incident_ids: Vec<String>,
    pub ngo_id: String,
    pub account_holder: String,
    pub iban: String,
    pub ticket_months: Vec<String>,
    #[serde(default)]
    pub attachments: Vec<String>,
    #[serde(default)]
    pub signed_by: Option<String>,
    pub status: ClaimStatus,
    #[serde(default)]
    pub sent_at: Option<NaiveDateTime>,
    #[serde(default)]
    pub expected_reply_by: Option<NaiveDate>,
    pub amount_claimed_cents: Cents,
    #[serde(default)]
    pub amount_confirmed_cents: Option<Cents>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MailDirection {
    Out,
    Inbound,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MailOutcome {
    Accepted,
    Question,
    Rejected,
    Bounce,
    Other,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Mail {
    pub id: String,
    #[serde(default)]
    pub claim_id: Option<String>,
    pub incident_ids: Vec<String>,
    pub direction: MailDirection,
    pub from: String,
    pub to: String,
    #[serde(default)]
    pub bcc: Option<String>,
    pub subject: String,
    pub body: String,
    pub date: NaiveDateTime,
    #[serde(default)]
    pub attachments: Vec<String>,
    #[serde(default)]
    pub amount_cents: Option<Cents>,
    #[serde(default)]
    pub outcome: Option<MailOutcome>,
    #[serde(default)]
    pub forwarded_at: Option<NaiveDateTime>,
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
pub struct Team {
    pub id: String,
    pub name: String,
    pub members: Vec<String>,
    pub minutes: i64,
    pub euros_cents: Cents,
    #[serde(default)]
    pub top_member: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Community {
    pub minutes: i64,
    pub submitted_cents: Cents,
    pub confirmed_cents: Cents,
    pub users: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LocationMode {
    Never,
    WhileUsing,
    Always,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PersonalData {
    pub name: String,
    pub address: String,
    pub email: String,
    #[serde(default)]
    pub ticket_number: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    pub ticket: TicketType,
    pub ngo_id: String,
    pub location_mode: LocationMode,
    pub notifications: bool,
    pub show_on_boards: bool,
    pub keep_correspondence: bool,
    #[serde(default)]
    pub traewelling_linked: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Customer {
    pub id: String,
    pub nickname: String,
    #[serde(default)]
    pub relay_address: Option<String>,
    #[serde(default)]
    pub personal_data: Option<PersonalData>,
    pub settings: Settings,
    pub points_total: i64,
    pub points_this_week: i64,
    pub level_name: String,
    pub next_level_name: String,
    pub next_level_at: i64,
    pub home_station: String,
}
