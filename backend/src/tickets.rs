//! The passenger's tickets (docs/49 §5.3, docs/50 phase 2, #66): a ticket is one contract of one
//! product of the fare catalogue. Journeys, rides, cases and claims point at the ticket they were
//! made with. The old `ticket` enum stays on the wire and in the tables, derived from the product,
//! for builds that know nothing else; and a request from such a build still finds or makes the
//! ticket it means ([`for_legacy`]).

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    Json,
};
use chrono::NaiveDate;
use serde::Deserialize;
use serde_json::{json, Map, Value};
use sqlx::PgPool;
use uuid::Uuid;

use crate::auth::{internal, Customer};
use crate::db::rows::*;
use crate::fares::{self, Offer, Product, Window};
use crate::AppState;

type ApiResult = Result<Json<Value>, (StatusCode, Json<Value>)>;

fn err(status: StatusCode, msg: &str) -> (StatusCode, Json<Value>) {
    (status, Json(json!({ "error": msg })))
}

/// The three types a build before tickets knows, for a catalogue product.
pub fn legacy_type(product: &str) -> TicketType {
    match fares::catalogue().get(product).map(|p| p.family.as_str()) {
        Some("deutschlandticket") => TicketType::Deutschlandticket,
        Some("einzelfahrkarte") => TicketType::Einzelfahrkarte,
        _ => TicketType::Zeitkarte,
    }
}

/// The catalogue product of a ticket. A product id the catalogue no longer has is a bug in the
/// catalogue (ids are never removed), so this falls back to the legacy mapping rather than fail a
/// ride.
pub fn product_of(t: &TicketRow) -> &'static Product {
    fares::catalogue().get(&t.product).unwrap_or_else(|| crate::rules::legacy_product(legacy_type(&t.product), TrainCategory::Re))
}

/// What the app asks for when a passenger adds a ticket of this product. Derived from the rule,
/// so a new product in the catalogue needs no app build.
fn fields_of(p: &Product) -> Value {
    let rule = p.latest();
    let validity = match (p.family.as_str(), rule.window) {
        (_, Window::Subscription) | (_, Window::Ticket) => "none",
        (_, Window::ValidityDay) => "day",
        _ => "range",
    };
    json!({
        "number": rule.form.number,
        // A single ticket's price is its amount; a season ticket's only sets its cap (docs/49 §9, 4).
        "price": if p.family == "einzelfahrkarte" { "required" } else { "optional" },
        "validity": validity,
        "birth_date": rule.form.birth_date,
        "route": p.family == "streckenzeitkarte",
        "first_class": true,
    })
}

/// A product as the app shows it (`GET /v1/fares`).
pub fn fare_json(p: &Product, today: NaiveDate) -> Value {
    let rule = p.rule_on(today);
    json!({
        "id": p.id, "family": p.family, "name": p.name, "tariff": p.tariff_name, "rule_line": p.rule_line,
        "offer": rule.offer, "caveat": if rule.caveat.is_empty() { Value::Null } else { json!(rule.caveat) },
        "valid_on": { "regional": rule.valid_on.regional, "long_distance": rule.valid_on.long_distance, "extra_routes": rule.valid_on.extra_routes },
        "threshold_min": rule.compensation.threshold(),
        "list_price_cents": p.price_on(today, false),
        "list_price_first_cents": p.price_on(today, true),
        "reduced_fare": rule.reduced_fare,
        "release_after_min": rule.release_after_min,
        "fields": fields_of(p),
        "ticket": legacy_type(&p.id),
    })
}

/// `GET /v1/fares`: the catalogue, without the products it hides. Public: it is the tariff, not
/// anybody's data.
pub async fn fares_public(State(_s): State<AppState>) -> ApiResult {
    let today = crate::clock::today();
    let list: Vec<Value> = fares::catalogue().products.values().filter(|p| p.rule_on(today).offer != Offer::Hidden).map(|p| fare_json(p, today)).collect();
    Ok(Json(json!({ "families": fares::FAMILIES, "fares": list })))
}

/// A ticket as the app reads it: the row, what it is, and the legacy type.
pub fn ticket_json(t: &TicketRow) -> Value {
    let p = product_of(t);
    let mut v = json!(t);
    if let Some(o) = v.as_object_mut() {
        o.insert("name".into(), json!(t.label.clone().filter(|l| !l.trim().is_empty()).unwrap_or_else(|| p.name.clone())));
        o.insert("family".into(), json!(p.family));
        o.insert("rule_line".into(), json!(p.rule_line));
        o.insert("ticket".into(), json!(legacy_type(&t.product)));
    }
    v
}

#[derive(Deserialize, Default, Clone)]
pub struct NewTicket {
    pub product: String,
    #[serde(default)]
    pub first_class: bool,
    pub label: Option<String>,
    pub number: Option<String>,
    pub booking_ref: Option<String>,
    pub birth_date: Option<NaiveDate>,
    pub price_cents: Option<i64>,
    pub valid_from: Option<NaiveDate>,
    pub valid_until: Option<NaiveDate>,
    pub origin_station_id: Option<String>,
    pub origin_station_name: Option<String>,
    pub destination_station_id: Option<String>,
    pub destination_station_name: Option<String>,
}

fn check_new(n: &NewTicket) -> Result<(), (StatusCode, Json<Value>)> {
    let Some(p) = fares::catalogue().get(&n.product) else { return Err(err(StatusCode::BAD_REQUEST, "unknown fare product")) };
    if p.latest().offer == Offer::Hidden {
        return Err(err(StatusCode::BAD_REQUEST, "this fare product is not offered"));
    }
    if n.price_cents.is_some_and(|c| c < 0) {
        return Err(err(StatusCode::BAD_REQUEST, "price must not be negative"));
    }
    if let (Some(a), Some(b)) = (n.valid_from, n.valid_until) {
        if b < a {
            return Err(err(StatusCode::BAD_REQUEST, "valid_until is before valid_from"));
        }
    }
    Ok(())
}

fn blank_to_none(s: Option<String>) -> Option<String> {
    s.map(|s| s.trim().to_string()).filter(|s| !s.is_empty())
}

pub async fn insert(pool: &PgPool, customer: Uuid, n: &NewTicket, unsure: bool) -> anyhow::Result<TicketRow> {
    let t: TicketRow = sqlx::query_as(
        "insert into tickets (id, customer_id, product, product_unsure, first_class, label, number, booking_ref, birth_date, price_cents,
            valid_from, valid_until, origin_station_id, origin_station_name, destination_station_id, destination_station_name)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16) returning *",
    )
    .bind(Uuid::new_v4())
    .bind(customer)
    .bind(&n.product)
    .bind(unsure)
    .bind(n.first_class)
    .bind(blank_to_none(n.label.clone()))
    .bind(blank_to_none(n.number.clone()))
    .bind(blank_to_none(n.booking_ref.clone()))
    .bind(n.birth_date)
    .bind(n.price_cents)
    .bind(n.valid_from)
    .bind(n.valid_until)
    .bind(blank_to_none(n.origin_station_id.clone()))
    .bind(blank_to_none(n.origin_station_name.clone()))
    .bind(blank_to_none(n.destination_station_id.clone()))
    .bind(blank_to_none(n.destination_station_name.clone()))
    .fetch_one(pool)
    .await?;
    sync_dticket_number(pool, &t).await?;
    Ok(t)
}

/// The D-Ticket's number lives on the ticket now; builds before tickets read and write it as
/// `personal_data.ticket_number`. Both stay the same number.
async fn sync_dticket_number(pool: &PgPool, t: &TicketRow) -> anyhow::Result<()> {
    if t.product == "deutschlandticket" && t.archived_at.is_none() {
        if let Some(n) = &t.number {
            sqlx::query("update customers set ticket_number = $2 where id = $1").bind(t.customer_id).bind(n).execute(pool).await?;
        }
    }
    Ok(())
}

/// The other direction: personal data written by an older build updates the D-Ticket in use.
pub async fn number_from_personal_data(pool: &PgPool, customer: Uuid, number: Option<&str>) -> anyhow::Result<()> {
    sqlx::query("update tickets set number = $2 where customer_id = $1 and product = 'deutschlandticket' and archived_at is null")
        .bind(customer)
        .bind(number.map(str::trim).filter(|n| !n.is_empty()))
        .execute(pool)
        .await?;
    Ok(())
}

/// The ticket a request from a build before tickets means. The D-Ticket and a Zeitkarte are the
/// passenger's own, found or made once; a Zeitkarte on a long-distance journey is the
/// Streckenzeitkarte, as the old rate had it; a single ticket is new every time.
pub async fn for_legacy(pool: &PgPool, c: &CustomerRow, ticket: TicketType, long_distance: bool) -> anyhow::Result<TicketRow> {
    let (product, pattern, unsure) = match (ticket, long_distance) {
        (TicketType::Deutschlandticket, _) => ("deutschlandticket", "deutschlandticket", false),
        (TicketType::Zeitkarte, true) => ("streckenzeitkarte", "streckenzeitkarte", true),
        (TicketType::Zeitkarte, false) => ("zeitkarte_spnv", "zeitkarte\\_%", true),
        (TicketType::Einzelfahrkarte, _) => ("einzel_db", "", false),
    };
    if !pattern.is_empty() {
        let found: Option<TicketRow> = sqlx::query_as("select * from tickets where customer_id = $1 and product like $2 and archived_at is null order by created_at desc limit 1")
            .bind(c.id)
            .bind(pattern)
            .fetch_optional(pool)
            .await?;
        if let Some(t) = found {
            return Ok(t);
        }
    }
    let number = if ticket == TicketType::Deutschlandticket { c.ticket_number.clone() } else { None };
    insert(pool, c.id, &NewTicket { product: product.into(), first_class: c.first_class, number, ..Default::default() }, unsure).await
}

/// How a new build names the ticket of a journey: one it has, or one it adds now.
#[derive(Deserialize, Clone)]
pub struct TicketChoice {
    pub ticket_id: Option<Uuid>,
    pub new_ticket: Option<NewTicket>,
}

/// The ticket for a check-in. `choice` from a new build, else `legacy` (or the setting) from an old
/// one. One ticket per journey for now; the tables carry more (docs/50 phase 3).
pub async fn for_journey(pool: &PgPool, c: &CustomerRow, choice: Option<&[TicketChoice]>, legacy: Option<TicketType>, long_distance: bool) -> Result<TicketRow, (StatusCode, Json<Value>)> {
    match choice {
        Some([one]) => match (&one.ticket_id, &one.new_ticket) {
            (Some(id), _) => owned(pool, c.id, *id).await?.filter(|t| t.archived_at.is_none()).ok_or_else(|| err(StatusCode::BAD_REQUEST, "no such ticket")),
            (None, Some(n)) => {
                check_new(n)?;
                insert(pool, c.id, n, false).await.map_err(internal)
            }
            (None, None) => Err(err(StatusCode::BAD_REQUEST, "a ticket needs ticket_id or new_ticket")),
        },
        Some([]) | None => for_legacy(pool, c, legacy.unwrap_or(c.ticket), long_distance).await.map_err(internal),
        Some(_) => Err(err(StatusCode::BAD_REQUEST, "one ticket per journey for now")),
    }
}

pub async fn owned(pool: &PgPool, customer: Uuid, id: Uuid) -> Result<Option<TicketRow>, (StatusCode, Json<Value>)> {
    sqlx::query_as("select * from tickets where id = $1 and customer_id = $2").bind(id).bind(customer).fetch_optional(pool).await.map_err(internal)
}

/// The ticket of a case, a journey or a ride, whichever is known.
pub async fn of_incident(pool: &PgPool, i: &IncidentRow) -> anyhow::Result<Option<TicketRow>> {
    match i.ticket_id {
        Some(id) => Ok(sqlx::query_as("select * from tickets where id = $1").bind(id).fetch_optional(pool).await?),
        None => Ok(None),
    }
}

#[derive(Deserialize)]
pub struct ListQuery {
    #[serde(default)]
    all: bool,
}

/// `GET /v1/me/tickets`: the passenger's tickets, the one used last first; archived ones only
/// with `?all=true`.
pub async fn list(State(s): State<AppState>, c: Customer, Query(q): Query<ListQuery>) -> ApiResult {
    let rows: Vec<TicketRow> = sqlx::query_as(
        "select t.* from tickets t
          where t.customer_id = $1 and ($2 or t.archived_at is null)
          order by (select max(j.created_at) from journey_tickets jt join journeys j on j.id = jt.journey_id where jt.ticket_id = t.id) desc nulls last, t.created_at desc",
    )
    .bind(c.0.id)
    .bind(q.all)
    .fetch_all(&s.pool)
    .await
    .map_err(internal)?;
    Ok(Json(json!({ "tickets": rows.iter().map(ticket_json).collect::<Vec<_>>() })))
}

/// `POST /v1/me/tickets`
pub async fn create(State(s): State<AppState>, c: Customer, Json(n): Json<NewTicket>) -> ApiResult {
    check_new(&n)?;
    let t = insert(&s.pool, c.0.id, &n, false).await.map_err(internal)?;
    Ok(Json(ticket_json(&t)))
}

/// `PATCH /v1/me/tickets/{id}`: any field; `null` clears it. Naming the product settles a ticket a
/// migration could only guess (`product_unsure`).
pub async fn patch(State(s): State<AppState>, c: Customer, Path(id): Path<Uuid>, Json(p): Json<Map<String, Value>>) -> ApiResult {
    let Some(mut t) = owned(&s.pool, c.0.id, id).await? else { return Err(err(StatusCode::NOT_FOUND, "no such ticket")) };
    let bad = |k: &str| err(StatusCode::BAD_REQUEST, &format!("bad value for {k}"));
    let text = |k: &str| -> Result<Option<Option<String>>, _> {
        match p.get(k) {
            None => Ok(None),
            Some(Value::Null) => Ok(Some(None)),
            Some(Value::String(v)) => Ok(Some(blank_to_none(Some(v.clone())))),
            Some(_) => Err(bad(k)),
        }
    };
    let date = |k: &str| -> Result<Option<Option<NaiveDate>>, _> {
        match p.get(k) {
            None => Ok(None),
            Some(Value::Null) => Ok(Some(None)),
            Some(v) => serde_json::from_value(v.clone()).map(|d| Some(Some(d))).map_err(|_| bad(k)),
        }
    };
    if let Some(v) = p.get("product") {
        let product = v.as_str().ok_or_else(|| bad("product"))?.to_string();
        check_new(&NewTicket { product: product.clone(), ..Default::default() })?;
        t.product = product;
        t.product_unsure = false;
    }
    if let Some(v) = p.get("first_class") {
        t.first_class = v.as_bool().ok_or_else(|| bad("first_class"))?;
    }
    if let Some(v) = p.get("price_cents") {
        t.price_cents = match v {
            Value::Null => None,
            v => Some(v.as_i64().filter(|c| *c >= 0).ok_or_else(|| bad("price_cents"))?),
        };
    }
    if let Some(v) = text("label")? { t.label = v; }
    if let Some(v) = text("number")? { t.number = v; }
    if let Some(v) = text("booking_ref")? { t.booking_ref = v; }
    if let Some(v) = text("origin_station_id")? { t.origin_station_id = v; }
    if let Some(v) = text("origin_station_name")? { t.origin_station_name = v; }
    if let Some(v) = text("destination_station_id")? { t.destination_station_id = v; }
    if let Some(v) = text("destination_station_name")? { t.destination_station_name = v; }
    if let Some(v) = date("birth_date")? { t.birth_date = v; }
    if let Some(v) = date("valid_from")? { t.valid_from = v; }
    if let Some(v) = date("valid_until")? { t.valid_until = v; }
    if let (Some(a), Some(b)) = (t.valid_from, t.valid_until) {
        if b < a {
            return Err(err(StatusCode::BAD_REQUEST, "valid_until is before valid_from"));
        }
    }
    let t: TicketRow = sqlx::query_as(
        "update tickets set product = $2, product_unsure = $3, first_class = $4, label = $5, number = $6, booking_ref = $7, birth_date = $8,
            price_cents = $9, valid_from = $10, valid_until = $11, origin_station_id = $12, origin_station_name = $13,
            destination_station_id = $14, destination_station_name = $15
         where id = $1 returning *",
    )
    .bind(t.id)
    .bind(&t.product)
    .bind(t.product_unsure)
    .bind(t.first_class)
    .bind(&t.label)
    .bind(&t.number)
    .bind(&t.booking_ref)
    .bind(t.birth_date)
    .bind(t.price_cents)
    .bind(t.valid_from)
    .bind(t.valid_until)
    .bind(&t.origin_station_id)
    .bind(&t.origin_station_name)
    .bind(&t.destination_station_id)
    .bind(&t.destination_station_name)
    .fetch_one(&s.pool)
    .await
    .map_err(internal)?;
    sync_dticket_number(&s.pool, &t).await.map_err(internal)?;
    Ok(Json(ticket_json(&t)))
}

/// `DELETE /v1/me/tickets/{id}`: a ticket someone no longer has. It is archived, not deleted: its
/// journeys and cases keep saying what they were made with.
pub async fn archive(State(s): State<AppState>, c: Customer, Path(id): Path<Uuid>) -> ApiResult {
    let done = sqlx::query("update tickets set archived_at = coalesce(archived_at, now()) where id = $1 and customer_id = $2")
        .bind(id)
        .bind(c.0.id)
        .execute(&s.pool)
        .await
        .map_err(internal)?
        .rows_affected();
    if done == 0 {
        return Err(err(StatusCode::NOT_FOUND, "no such ticket"));
    }
    Ok(Json(json!({ "archived": true })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn legacy_types_follow_the_family() {
        assert_eq!(legacy_type("deutschlandticket"), TicketType::Deutschlandticket);
        assert_eq!(legacy_type("bahncard100"), TicketType::Zeitkarte);
        assert_eq!(legacy_type("zeitkarte_vrr_nrw"), TicketType::Zeitkarte);
        assert_eq!(legacy_type("streckenzeitkarte"), TicketType::Zeitkarte);
        assert_eq!(legacy_type("laender_ticket"), TicketType::Zeitkarte);
        assert_eq!(legacy_type("einzel_flixtrain"), TicketType::Einzelfahrkarte);
    }

    #[test]
    fn the_app_is_told_which_fields_a_product_needs() {
        let c = fares::catalogue();
        let f = fields_of(c.product("einzel_db"));
        assert_eq!((f["price"].as_str(), f["validity"].as_str()), (Some("required"), Some("none")));
        let f = fields_of(c.product("deutschlandticket"));
        assert_eq!((f["price"].as_str(), f["validity"].as_str(), f["number"].as_str()), (Some("optional"), Some("none"), Some("abo")));
        let f = fields_of(c.product("bahncard100"));
        assert_eq!((f["validity"].as_str(), f["birth_date"].as_bool()), (Some("range"), Some(true)));
        assert_eq!(fields_of(c.product("laender_ticket"))["validity"], "day");
        assert_eq!(fields_of(c.product("streckenzeitkarte"))["route"], true);
    }
}
