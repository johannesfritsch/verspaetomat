//! Row types. They serialise straight to the API; column names are the API field names.

use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "ticket_type", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum TicketType {
    Deutschlandticket,
    Zeitkarte,
    Einzelfahrkarte,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "location_mode", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum LocationMode {
    Never,
    WhileUsing,
    Always,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "train_category", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum TrainCategory {
    S,
    Rb,
    Re,
    Fern,
    Bus,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "ride_status", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum RideStatus {
    Riding,
    Arrived,
    Abandoned,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "journey_status", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum JourneyStatus {
    Riding,
    Transfer,
    Arrived,
    Abandoned,
}

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct JourneyRow {
    pub id: Uuid,
    pub customer_id: Uuid,
    pub origin_station_id: String,
    pub origin_station_name: String,
    pub destination_station_id: String,
    pub destination_station_name: String,
    /// The itinerary as planned at check-in (evidence).
    pub itinerary: serde_json::Value,
    /// The effective plan: original legs, replaced from the transfer on after a re-plan.
    pub plan: serde_json::Value,
    pub planned_departure: DateTime<Utc>,
    pub planned_arrival: DateTime<Utc>,
    pub status: JourneyStatus,
    pub current_leg: i32,
    pub next_leg: Option<serde_json::Value>,
    pub transfer_deadline: Option<DateTime<Utc>>,
    pub actual_arrival: Option<DateTime<Utc>>,
    pub final_delay_min: Option<i32>,
    pub missed_connection: bool,
    pub incomplete: bool,
    pub cancelled: bool,
    pub points: i32,
    pub ticket: TicketType,
    pub created_at: DateTime<Utc>,
    pub finalised_at: Option<DateTime<Utc>>,
    pub dismissed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "incident_status", rename_all = "snake_case")]
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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "claim_status", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum ClaimStatus {
    Draft,
    Sent,
    Question,
    Accepted,
    Rejected,
    Bounced,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "mail_direction", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum MailDirection {
    Out,
    Inbound,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "mail_outcome", rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum MailOutcome {
    Accepted,
    Question,
    Rejected,
    Bounce,
    Other,
}

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct CustomerRow {
    pub id: Uuid,
    pub nickname: String,
    pub relay_address: Option<String>,
    pub full_name: Option<String>,
    pub postal_address: Option<String>,
    pub email: Option<String>,
    pub ticket_number: Option<String>,
    pub first_class: bool,
    pub ticket: TicketType,
    pub ngo_id: String,
    pub loc_mode: LocationMode,
    pub notifications: bool,
    pub show_on_boards: bool,
    pub keep_correspondence: bool,
    pub traewelling_linked: bool,
    pub onboarding_done: bool,
    pub home_station_id: Option<String>,
    pub home_station_name: Option<String>,
    pub muted_stations: serde_json::Value,
    #[serde(default)]
    pub nudge_enabled: bool,
    #[serde(default)]
    pub quiet_from: Option<chrono::NaiveTime>,
    #[serde(default)]
    pub quiet_to: Option<chrono::NaiveTime>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct OperatorRow {
    pub name: String,
    pub aliases: Vec<String>,
    pub desk: String,
    pub postal_address: String,
    pub email: Option<String>,
    pub accepts_email: bool,
    pub last_verified: Option<NaiveDate>,
    pub notes: Option<String>,
}

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct NgoRow {
    pub id: String,
    pub name: String,
    pub tagline: String,
    pub story: serde_json::Value,
    pub account_holder: String,
    pub iban: String,
    pub donation_url: String,
    pub last_report: Option<NaiveDate>,
    pub active: bool,
    pub seed_confirmed_cents: i64,
    pub seed_submitted_cents: i64,
}

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct BadgeRow {
    pub id: String,
    pub name: String,
    pub rule: String,
}

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct RideRow {
    pub id: Uuid,
    pub customer_id: Uuid,
    pub trip_id: String,
    pub line: String,
    pub headsign: String,
    pub operator: String,
    pub category: TrainCategory,
    pub from_station_id: String,
    pub from_station_name: String,
    pub exit_station_id: String,
    pub exit_station_name: String,
    pub planned_departure: DateTime<Utc>,
    pub planned_arrival: DateTime<Utc>,
    pub actual_arrival: Option<DateTime<Utc>>,
    pub ticket: TicketType,
    pub status: RideStatus,
    pub live_delay_min: i32,
    pub passed_stops: i32,
    pub cause: Option<String>,
    pub final_delay_min: Option<i32>,
    pub cancelled: bool,
    pub self_entered: bool,
    pub nachtrag: bool,
    pub location_verified: bool,
    pub points: i32,
    pub checked_in_at: DateTime<Utc>,
    pub finalised_at: Option<DateTime<Utc>>,
    pub last_polled_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub dismissed_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub from_lat: Option<f64>,
    #[serde(default)]
    pub from_lon: Option<f64>,
    #[serde(default)]
    pub journey_id: Option<Uuid>,
    #[serde(default)]
    pub leg_no: Option<i32>,
    #[serde(default)]
    pub transfer_station_id: Option<String>,
    #[serde(default)]
    pub transfer_station_name: Option<String>,
}

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct IncidentRow {
    pub id: Uuid,
    pub customer_id: Uuid,
    pub ride_id: Option<Uuid>,
    pub ride_date: NaiveDate,
    pub line: String,
    pub from_name: String,
    pub to_name: String,
    pub delay_min: i32,
    pub amount_cents: i64,
    pub ticket: TicketType,
    pub operator: String,
    pub desk: String,
    pub status: IncidentStatus,
    pub cancelled: bool,
    pub self_entered: bool,
    pub ngo_id: String,
    pub claim_id: Option<Uuid>,
    pub fare_cents: Option<i64>,
    pub legal_deadline: NaiveDate,
    pub evidence: Option<serde_json::Value>,
    pub created_at: DateTime<Utc>,
    #[serde(default)]
    pub journey_id: Option<Uuid>,
}

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct ClaimRow {
    pub id: Uuid,
    pub customer_id: Uuid,
    pub desk: String,
    pub ngo_id: String,
    pub account_holder: String,
    pub iban: String,
    pub ticket_months: Vec<String>,
    pub status: ClaimStatus,
    pub signed_by: Option<String>,
    pub signed_at: Option<DateTime<Utc>>,
    pub sent_at: Option<DateTime<Utc>>,
    pub expected_reply_by: Option<NaiveDate>,
    pub amount_claimed_cents: i64,
    pub amount_confirmed_cents: Option<i64>,
    pub closed_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    /// `antrag-<8 hex>@RELAY_DOMAIN`, assigned at send time (docs/18 §4).
    pub reply_address: Option<String>,
}

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct MailRow {
    pub id: Uuid,
    pub customer_id: Uuid,
    pub claim_id: Option<Uuid>,
    pub direction: MailDirection,
    pub message_id: Option<String>,
    pub in_reply_to: Option<String>,
    pub from_addr: String,
    pub to_addr: String,
    pub bcc_addr: Option<String>,
    pub subject: String,
    pub body: String,
    pub attachments: serde_json::Value,
    pub outcome: Option<MailOutcome>,
    pub amount_cents: Option<i64>,
    pub dry_run: bool,
    pub forwarded_at: Option<DateTime<Utc>>,
    pub occurred_at: DateTime<Utc>,
    /// Null = unread (inbound only; outbound mail is written by the customer).
    pub seen_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct BoardSeedRow {
    pub scope: String,
    pub rank: i32,
    pub name: String,
    pub points: i32,
}
