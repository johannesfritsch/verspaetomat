//! API tests against a real Postgres: each test gets a fresh database with every migration applied
//! (`#[sqlx::test]`), the fixtures seeded, and the same router `main` serves. They cover what
//! otherwise only a hand-run script or a simulator run would: deleting an account, the share
//! figures, a missed connection, the claim draft's rules.
//!
//! Needs a Postgres the current user can create databases on — the one `dev.sh` starts.
//! `DATABASE_URL` names it (`.cargo/config.toml` sets the local default); sqlx creates and drops
//! a `_sqlx_test_…` database per test and never touches the one named.
//!
//! Nothing here reaches the network. Where a handler asks Transitous, the test starts a small
//! stand-in on a local port and hands its address to the client.

use std::sync::Arc;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use axum::routing::get;
use axum::Router;
use chrono::{Duration, Utc};
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

use crate::train::sim::TrainSource;
use crate::train::transitous::TransitousClient;
use crate::AppState;

/// The app over [pool], with Transitous at [transitous] (a stand-in's address) or nowhere.
async fn app(pool: PgPool, transitous: Option<String>) -> Router {
    app_and_events(pool, transitous).await.0
}

/// The app and its event hub, for a test that has to know what was published. Every push the
/// server sends starts as one of these events (`push.rs` hangs on the same tap), so an event that
/// never happened is a push that never went out.
async fn app_and_events(pool: PgPool, transitous: Option<String>) -> (Router, Arc<crate::events::EventHub>) {
    crate::db::seed(&pool).await.expect("seed");
    let client = TransitousClient::with_base(transitous.unwrap_or_else(|| "http://127.0.0.1:9".into()));
    let stations: crate::stations::Shared = Arc::new(std::sync::RwLock::new(Arc::new(crate::stations::Index::default())));
    let events = Arc::new(crate::events::EventHub::default());
    let state = AppState {
        pool,
        train: Arc::new(TrainSource::new(client, stations.clone())),
        events: events.clone(),
        push: Arc::new(crate::push::PushSender::from_env().expect("push sender")),
        stations,
        flags: Arc::new(std::sync::RwLock::new(Arc::new(crate::flags::Table::default()))),
        outline_files: Arc::new(std::sync::RwLock::new(None)),
    };
    (crate::router(state), events)
}

/// One request; the answer's status and JSON body (Null when there is none).
async fn call(app: &Router, method: &str, path: &str, token: Option<&str>, body: Option<Value>) -> (StatusCode, Value) {
    let mut req = Request::builder().method(method).uri(path);
    if let Some(t) = token {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    let req = match body {
        Some(b) => req.header("content-type", "application/json").body(Body::from(b.to_string())),
        None => req.body(Body::empty()),
    }
    .unwrap();
    let res = app.clone().oneshot(req).await.expect("response");
    let status = res.status();
    let bytes = axum::body::to_bytes(res.into_body(), 16 * 1024 * 1024).await.unwrap();
    (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
}

/// A fresh device, as the app makes one: `(customer id, token)`.
async fn device(app: &Router) -> (Uuid, String) {
    let (s, v) = call(app, "POST", "/v1/devices", None, Some(json!({}))).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let id: Uuid = v["device_id"].as_str().unwrap().parse().unwrap();
    let token = v["token"].as_str().unwrap().to_string();
    let (s, _) = call(app, "GET", "/v1/me", Some(&token), None).await;
    assert_eq!(s, StatusCode::OK);
    (id, token)
}

/// An arrived ride, `days_ago` back, `delay` minutes late on `line`.
async fn ride(pool: &PgPool, customer: Uuid, line: &str, delay: i32, days_ago: i64) -> Uuid {
    let id = Uuid::new_v4();
    let at = Utc::now() - Duration::days(days_ago);
    sqlx::query(
        "insert into rides (id, customer_id, trip_id, line, operator, category, from_station_id, from_station_name, exit_station_id,
                            exit_station_name, planned_departure, planned_arrival, actual_arrival, ticket, status, final_delay_min, points,
                            checked_in_at, finalised_at)
         values ($1, $2, $3, $4, 'DB Regio', 're', 'vs:1', 'Köln Hbf', 'vs:2', 'Düsseldorf Hbf', $5, $6, $7, 'deutschlandticket', 'arrived', $8, $8, $5, $7)",
    )
    .bind(id)
    .bind(customer)
    .bind(format!("trip-{id}"))
    .bind(line)
    .bind(at)
    .bind(at + Duration::minutes(30))
    .bind(at + Duration::minutes(30 + delay as i64))
    .bind(delay)
    .execute(pool)
    .await
    .expect("ride");
    id
}

/// A claimable case at the Servicecenter on the customer's D-Ticket, worth [cents] as the ledger
/// had it, from [ride]. The pots recompute the amount from its 68 minutes (#66).
async fn incident(pool: &PgPool, customer: Uuid, ride: Option<Uuid>, cents: i64, status: &str) -> Uuid {
    let id = Uuid::new_v4();
    let ngo: String = sqlx::query_scalar("select id from ngos order by id limit 1").fetch_one(pool).await.expect("an ngo from the fixtures");
    let ticket: Uuid = match sqlx::query_scalar("select id from tickets where customer_id = $1 and product = 'deutschlandticket'").bind(customer).fetch_optional(pool).await.unwrap() {
        Some(t) => t,
        None => sqlx::query_scalar("insert into tickets (id, customer_id, product) values ($1, $2, 'deutschlandticket') returning id").bind(Uuid::new_v4()).bind(customer).fetch_one(pool).await.unwrap(),
    };
    sqlx::query(
        "insert into incidents (id, customer_id, ride_id, ride_date, line, from_name, to_name, delay_min, amount_cents, ticket, operator, desk,
                                ngo_id, legal_deadline, status, ticket_id)
         values ($1, $2, $3, current_date - 2, 'RE 1', 'Köln Hbf', 'Düsseldorf Hbf', 68, $4, 'deutschlandticket', 'DB Regio',
                 'Servicecenter Fahrgastrechte', $5, current_date + 300, $6::incident_status, $7)",
    )
    .bind(id)
    .bind(customer)
    .bind(ride)
    .bind(cents)
    .bind(ngo)
    .bind(status)
    .bind(ticket)
    .execute(pool)
    .await
    .expect("incident");
    id
}

async fn count(pool: &PgPool, sql: &str, id: Uuid) -> i64 {
    sqlx::query_scalar(sql).bind(id).fetch_one(pool).await.unwrap()
}

// ---------------------------------------------------------------------------
// „Alles löschen" and „Daten löschen"
// ---------------------------------------------------------------------------

#[sqlx::test(migrations = "./migrations")]
async fn deleting_an_account_leaves_nothing_behind(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let (id, token) = device(&app).await;
    let (s, _) = call(&app, "PUT", "/v1/me/personal-data", Some(&token), Some(json!({"name": "Lösch Test", "address": "Weg 1, 50667 Köln", "email": "l@example.org"}))).await;
    assert_eq!(s, StatusCode::OK);
    call(&app, "GET", "/v1/me/recovery-code", Some(&token), None).await;

    // Rides, cases, a claim with a ticket picture on disk, and the audit rows they leave.
    let r = ride(&pool, id, "RE 1", 68, 2).await;
    let i = incident(&pool, id, Some(r), 150, "gesammelt").await;
    let claim = Uuid::new_v4();
    sqlx::query("insert into claims (id, customer_id, desk, ngo_id, account_holder, iban) select $1, $2, 'Servicecenter Fahrgastrechte', id, account_holder, iban from ngos order by id limit 1")
        .bind(claim)
        .bind(id)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("insert into claim_incidents (claim_id, incident_id) values ($1, $2)").bind(claim).bind(i).execute(&pool).await.unwrap();
    let upload = Uuid::new_v4();
    let path = crate::storage::put(upload, b"\x89PNG\r\n\x1a\nticket").await.expect("file");
    sqlx::query("insert into uploads (id, customer_id, kind, content_type, path) values ($1, $2, 'ticket', 'image/png', $3)")
        .bind(upload)
        .bind(id)
        .bind(&path)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("insert into claim_attachments (claim_id, upload_id, label) values ($1, $2, 'Ticket')").bind(claim).bind(upload).execute(&pool).await.unwrap();
    crate::rules::audit(&pool, "claim", claim, None, "draft", "test").await.unwrap();
    crate::rules::audit(&pool, "incident", i, None, "gesammelt", "test").await.unwrap();
    assert!(crate::storage::dir().join(&path).exists());

    let (s, v) = call(&app, "DELETE", "/v1/me", Some(&token), None).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(v["deleted"], true);

    for (table, sql) in [
        ("devices", "select count(*) from devices where id = $1"),
        ("customers", "select count(*) from customers where id = $1"),
        ("rides", "select count(*) from rides where customer_id = $1"),
        ("incidents", "select count(*) from incidents where customer_id = $1"),
        ("claims", "select count(*) from claims where customer_id = $1"),
        ("uploads", "select count(*) from uploads where customer_id = $1"),
        ("mails", "select count(*) from mails where customer_id = $1"),
    ] {
        assert_eq!(count(&pool, sql, id).await, 0, "{table} still holds rows of the deleted customer");
    }
    assert_eq!(count(&pool, "select count(*) from audit_log where entity_id = $1", claim).await, 0, "audit rows of the claim");
    assert_eq!(count(&pool, "select count(*) from audit_log where entity_id = $1", i).await, 0, "audit rows of the case");
    assert!(!crate::storage::dir().join(&path).exists(), "the ticket picture must go from the disk too");

    let (s, _) = call(&app, "GET", "/v1/me", Some(&token), None).await;
    assert_eq!(s, StatusCode::UNAUTHORIZED, "the old token opens nothing");
}

#[sqlx::test(migrations = "./migrations")]
async fn deleting_personal_data_clears_the_four_fields_and_keeps_the_address(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let (id, token) = device(&app).await;
    let (s, v) = call(&app, "PUT", "/v1/me/personal-data", Some(&token), Some(json!({"name": "A B", "address": "Weg 1", "email": "a@example.org", "ticket_number": "T-1"}))).await;
    assert_eq!(s, StatusCode::OK);
    let relay = v["relay_address"].as_str().expect("a relay address after the first save").to_string();

    let (s, v) = call(&app, "DELETE", "/v1/me/personal-data", Some(&token), None).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let (name, addr, email, ticket, relay_after): (Option<String>, Option<String>, Option<String>, Option<String>, Option<String>) =
        sqlx::query_as("select full_name, postal_address, email, ticket_number, relay_address from customers where id = $1").bind(id).fetch_one(&pool).await.unwrap();
    assert_eq!((name, addr, email, ticket), (None, None, None, None));
    assert_eq!(relay_after.as_deref(), Some(relay.as_str()), "answers to sent claims still arrive there");
}

#[sqlx::test(migrations = "./migrations")]
async fn saving_personal_data_without_a_number_keeps_the_d_tickets(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let (id, token) = device(&app).await;
    let (s, v) = call(&app, "POST", "/v1/me/tickets", Some(&token), Some(json!({"product": "deutschlandticket", "number": "D-77"}))).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let t = v["id"].as_str().unwrap().to_string();

    // A build since #66 sends three fields.
    let (s, _) = call(&app, "PUT", "/v1/me/personal-data", Some(&token), Some(json!({"name": "A B", "address": "Weg 1", "email": "a@example.org"}))).await;
    assert_eq!(s, StatusCode::OK);
    let number: Option<String> = sqlx::query_scalar("select number from tickets where id = $1::uuid").bind(&t).fetch_one(&pool).await.unwrap();
    assert_eq!(number.as_deref(), Some("D-77"), "the ticket keeps its number");

    // An older build still writes the number through.
    let (s, _) = call(&app, "PUT", "/v1/me/personal-data", Some(&token), Some(json!({"name": "A B", "address": "Weg 1", "email": "a@example.org", "ticket_number": "D-88"}))).await;
    assert_eq!(s, StatusCode::OK);
    let number: Option<String> = sqlx::query_scalar("select number from tickets where id = $1::uuid").bind(&t).fetch_one(&pool).await.unwrap();
    assert_eq!(number.as_deref(), Some("D-88"));
    let stored: Option<String> = sqlx::query_scalar("select ticket_number from customers where id = $1").bind(id).fetch_one(&pool).await.unwrap();
    assert_eq!(stored.as_deref(), Some("D-88"));
}

// ---------------------------------------------------------------------------
// GET /v1/me/share (#49)
// ---------------------------------------------------------------------------

#[sqlx::test(migrations = "./migrations")]
async fn the_share_figures_are_one_passengers_own(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let (me, token) = device(&app).await;
    let (other, _) = device(&app).await;

    ride(&pool, me, "RE 5", 30, 1).await;
    let longest = ride(&pool, me, "RE 5", 94, 2).await;
    ride(&pool, me, "S 12", 7, 3).await;
    // Somebody else's longer delay must not become my record.
    ride(&pool, other, "RE 1", 180, 1).await;
    incident(&pool, me, Some(longest), 150, "bestaetigt").await;

    let (s, v) = call(&app, "GET", "/v1/me/share", Some(&token), None).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(v["minutes_total"], 131);
    assert_eq!(v["rides_total"], 3);
    assert_eq!(v["confirmed_cents"], 150);
    assert_eq!(v["record"]["minutes"], 94);
    assert_eq!(v["record"]["ride_id"], longest.to_string());
    assert_eq!(v["record"]["line"], "RE 5");
    // All three rides are within the last three days; the month they share is either this one or,
    // on the first days of a month, partly the last. The line that cost the most is RE 5 either way
    // unless the month turned between them, so only assert it when all three are in this month.
    let this_month = Utc::now().format("%Y-%m").to_string();
    if v["top_line"]["month"] == this_month && (Utc::now() - Duration::days(3)).format("%Y-%m").to_string() == this_month {
        assert_eq!(v["top_line"]["line"], "RE 5");
        assert_eq!(v["top_line"]["minutes"], 124);
    }
    assert_eq!(v["confirmed_claims"], json!([]), "no accepted claim yet");
}

#[sqlx::test(migrations = "./migrations")]
async fn minutes_count_where_the_points_do(pool: PgPool) {
    // #71: Home said 158 minutes, Ich 146 points. The minutes were summed per train.
    let app = app(pool.clone(), None).await;
    let (me, token) = device(&app).await;

    // A journey with a change: the RE 7 was 12 late at Hagen, the RB 52 came in 68 late. The
    // journey counts 68 — at the destination (docs/17), as its points do.
    let j = Uuid::new_v4();
    let now = Utc::now();
    sqlx::query(
        "insert into journeys (id, customer_id, origin_station_id, origin_station_name, destination_station_id, destination_station_name,
                               itinerary, plan, planned_departure, planned_arrival, ticket, status, current_leg, final_delay_min, points, finalised_at)
         values ($1, $2, 'vs:1', 'Köln Hbf', 'vs:3', 'Lüdenscheid', '{}'::jsonb, '[]'::jsonb, $3, $4, 'deutschlandticket', 'arrived', 2, 68, 68, $4)",
    )
    .bind(j)
    .bind(me)
    .bind(now - Duration::hours(3))
    .bind(now - Duration::hours(1))
    .execute(&pool)
    .await
    .expect("journey");
    let first = ride(&pool, me, "RE 7", 12, 0).await;
    let second = ride(&pool, me, "RB 52", 68, 0).await;
    for (r, leg, points) in [(first, 1, 0), (second, 2, 68)] {
        sqlx::query("update rides set journey_id = $2, leg_no = $3, points = $4 where id = $1")
            .bind(r)
            .bind(j)
            .bind(leg)
            .bind(points)
            .execute(&pool)
            .await
            .expect("leg");
    }
    // Given up after 20 minutes on the platform-side train: the waiting counts (docs/22 §1).
    let gave_up = ride(&pool, me, "S 12", 20, 1).await;
    sqlx::query("update rides set status = 'abandoned' where id = $1").bind(gave_up).execute(&pool).await.expect("abandon");
    // A ride of its own, from before journeys.
    ride(&pool, me, "RE 5", 10, 2).await;

    let (_, share) = call(&app, "GET", "/v1/me/share", Some(&token), None).await;
    let (_, me_json) = call(&app, "GET", "/v1/me", Some(&token), None).await;
    assert_eq!(share["minutes_total"], 68 + 20 + 10, "per journey, not per train: {share}");
    assert_eq!(me_json["points_total"], share["minutes_total"], "the two screens agree");
}

#[sqlx::test(migrations = "./migrations")]
async fn an_empty_account_has_no_record_and_no_month(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let (_, token) = device(&app).await;
    let (s, v) = call(&app, "GET", "/v1/me/share", Some(&token), None).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(v["minutes_total"], 0);
    assert_eq!(v["record"], Value::Null);
    assert_eq!(v["top_line"], Value::Null);
    assert_eq!(v["last_month"], Value::Null, "an empty month gets no card");
}

#[sqlx::test(migrations = "./migrations")]
async fn badges_come_in_the_order_of_the_fixture(pool: PgPool) {
    // #61: by id, "minuten-16000" sorted before "minuten-2000".
    let app = app(pool.clone(), None).await;
    let (_, token) = device(&app).await;
    let (s, v) = call(&app, "GET", "/v1/badges", Some(&token), None).await;
    assert_eq!(s, StatusCode::OK);
    let ids: Vec<&str> = v.as_array().unwrap().iter().map(|b| b["id"].as_str().unwrap()).collect();
    let fixture: Vec<Value> = serde_json::from_str(include_str!("../fixtures/badges.json")).unwrap();
    let expected: Vec<&str> = fixture.iter().map(|b| b["id"].as_str().unwrap()).collect();
    assert_eq!(ids, expected);
    let minutes: Vec<&str> = ids.into_iter().filter(|i| i.starts_with("minuten-")).collect();
    assert_eq!(minutes, ["minuten-1000", "minuten-2000", "minuten-4000", "minuten-8000", "minuten-16000", "minuten-32000", "minuten-64000"]);
}

// ---------------------------------------------------------------------------
// POST /v1/journeys/{id}/missed (#57)
// ---------------------------------------------------------------------------

fn leg(trip: &str, line: &str, from: (&str, &str), to: (&str, &str), dep: chrono::DateTime<Utc>, mins: i64) -> Value {
    json!({
        "trip_id": trip, "line": line, "headsign": to.1, "operator": "DB Regio", "category": "re",
        "from_station_id": from.0, "from_station_name": from.1, "to_station_id": to.0, "to_station_name": to.1,
        "planned_departure": dep, "planned_arrival": dep + Duration::minutes(mins),
        "live_departure": null, "live_arrival": null, "platform": "6", "arrival_platform": "2", "cancelled": false, "delay_min": 0,
    })
}

/// A journey standing at its change in Hagen, the RB 52 still ahead.
async fn journey_at_transfer(pool: &PgPool, customer: Uuid) -> (Uuid, Value) {
    let now = Utc::now();
    let first = leg("re7", "RE 7", ("vs:1", "Köln Hbf"), ("vs:2", "Hagen Hbf"), now - Duration::minutes(60), 50);
    let second = leg("rb52", "RB 52", ("vs:2", "Hagen Hbf"), ("vs:3", "Lüdenscheid"), now - Duration::minutes(5), 43);
    let id = Uuid::new_v4();
    sqlx::query(
        "insert into journeys (id, customer_id, origin_station_id, origin_station_name, destination_station_id, destination_station_name,
                               itinerary, plan, planned_departure, planned_arrival, ticket, status, current_leg, next_leg, transfer_deadline)
         values ($1, $2, 'vs:1', 'Köln Hbf', 'vs:3', 'Lüdenscheid', '{}'::jsonb, $3, $4, $5, 'deutschlandticket', 'transfer', 1, $6, $7)",
    )
    .bind(id)
    .bind(customer)
    .bind(json!([first, second]))
    .bind(now - Duration::minutes(60))
    .bind(now + Duration::minutes(38))
    .bind(&second)
    .bind(now + Duration::hours(2))
    .execute(pool)
    .await
    .expect("journey");
    (id, second)
}

/// A stand-in for Transitous' `/api/v1/plan`, answering [body] to every question.
async fn transitous_with_plan(body: Value) -> String {
    let body = Arc::new(body.to_string());
    let app = Router::new().route(
        "/api/v1/plan",
        get(move || {
            let b = body.clone();
            async move { ([("content-type", "application/json")], (*b).clone()) }
        }),
    );
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    format!("http://{addr}")
}

/// One MOTIS itinerary with one rail leg Hagen → Lüdenscheid on [trip], leaving in [in_min].
fn motis_itinerary(trip: &str, line: &str, in_min: i64) -> Value {
    let dep = Utc::now() + Duration::minutes(in_min);
    let arr = dep + Duration::minutes(43);
    json!({"id": trip, "transfers": 0, "legs": [{
        "mode": "REGIONAL_RAIL", "tripId": trip, "routeShortName": line, "headsign": "Lüdenscheid", "agencyName": "DB Regio AG",
        "realTime": false,
        "from": {"name": "Hagen Hbf", "stopId": "de-DELFI_de:05914:1", "scheduledDeparture": dep, "track": "7"},
        "to": {"name": "Lüdenscheid", "stopId": "de-DELFI_de:05962:1", "scheduledArrival": arr, "track": "1"},
    }]})
}

#[sqlx::test(migrations = "./migrations")]
async fn a_missed_connection_proposes_the_next_one_and_keeps_the_plan_straight(pool: PgPool) {
    // Transitous answers with the missed train first — it is still the earliest in its data — and
    // the next one after it. The proposal must be the next one.
    let base = transitous_with_plan(json!({"itineraries": [motis_itinerary("rb52", "RB 52", -5), motis_itinerary("rb52-next", "RB 52", 55)]})).await;
    let app = app(pool.clone(), Some(base)).await;
    let (me, token) = device(&app).await;
    let (journey, _) = journey_at_transfer(&pool, me).await;

    let (s, v) = call(&app, "POST", &format!("/v1/journeys/{journey}/missed"), Some(&token), None).await;
    assert_eq!(s, StatusCode::OK, "{v}");

    let (next, plan, missed, earliest): (Value, Value, bool, Option<chrono::DateTime<Utc>>) =
        sqlx::query_as("select next_leg, plan, missed_connection, earliest_onward_arrival from journeys where id = $1").bind(journey).fetch_one(&pool).await.unwrap();
    assert_eq!(next["trip_id"], "rb52-next", "not the train that just left");
    assert_eq!(next["replanned"], true);
    assert_eq!(next["reason"], "verpasst");
    assert_eq!(next["platform"], "7", "the new train's own track");
    assert_eq!(next["arrival_platform"], "1");
    assert!(missed, "the journey records the missed connection");
    assert!(earliest.is_some(), "the earliest onward arrival caps what counts (docs/21 §2)");
    let trips: Vec<&str> = plan.as_array().unwrap().iter().map(|l| l["trip_id"].as_str().unwrap()).collect();
    assert_eq!(trips, vec!["re7", "rb52-next"], "the done leg stays, the missed one is replaced");
}

#[sqlx::test(migrations = "./migrations")]
async fn missed_without_a_later_train_says_so_and_changes_nothing(pool: PgPool) {
    let base = transitous_with_plan(json!({"itineraries": [motis_itinerary("rb52", "RB 52", -5)]})).await;
    let app = app(pool.clone(), Some(base)).await;
    let (me, token) = device(&app).await;
    let (journey, before) = journey_at_transfer(&pool, me).await;

    let (s, _) = call(&app, "POST", &format!("/v1/journeys/{journey}/missed"), Some(&token), None).await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let next: Value = sqlx::query_scalar("select next_leg from journeys where id = $1").bind(journey).fetch_one(&pool).await.unwrap();
    assert_eq!(next, before, "no answer, no change");
}

#[sqlx::test(migrations = "./migrations")]
async fn missed_is_only_for_a_journey_at_a_change_and_only_for_its_owner(pool: PgPool) {
    let base = transitous_with_plan(json!({"itineraries": [motis_itinerary("rb52-next", "RB 52", 55)]})).await;
    let app = app(pool.clone(), Some(base)).await;
    let (me, token) = device(&app).await;
    let (_, stranger) = device(&app).await;
    let (journey, _) = journey_at_transfer(&pool, me).await;

    let (s, _) = call(&app, "POST", &format!("/v1/journeys/{journey}/missed"), Some(&stranger), None).await;
    assert!(s == StatusCode::NOT_FOUND || s == StatusCode::FORBIDDEN, "another account's journey: {s}");

    sqlx::query("update journeys set status = 'riding' where id = $1").bind(journey).execute(&pool).await.unwrap();
    let (s, _) = call(&app, "POST", &format!("/v1/journeys/{journey}/missed"), Some(&token), None).await;
    assert_eq!(s, StatusCode::CONFLICT, "riding is not a change");
}

#[sqlx::test(migrations = "./migrations")]
async fn missed_never_offers_a_train_that_has_left(pool: PgPool) {
    // The feed still lists a train that left two minutes ago. A train that was due three minutes
    // ago and is running seven late has not left: that one is the next way on.
    let late = {
        let mut it = motis_itinerary("rb52-late", "RB 52", -3);
        it["legs"][0]["realTime"] = json!(true);
        it["legs"][0]["from"]["departure"] = json!(Utc::now() + Duration::minutes(4));
        it["legs"][0]["to"]["arrival"] = json!(Utc::now() + Duration::minutes(47));
        it
    };
    let base = transitous_with_plan(json!({"itineraries": [
        motis_itinerary("rb52", "RB 52", -5),
        motis_itinerary("rb52-gone", "RB 52", -4),
        late,
        motis_itinerary("rb52-next", "RB 52", 55),
    ]}))
    .await;
    let app = app(pool.clone(), Some(base)).await;
    let (me, token) = device(&app).await;
    let (journey, _) = journey_at_transfer(&pool, me).await;

    let (s, v) = call(&app, "POST", &format!("/v1/journeys/{journey}/missed"), Some(&token), None).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let next: Value = sqlx::query_scalar("select next_leg from journeys where id = $1").bind(journey).fetch_one(&pool).await.unwrap();
    assert_eq!(next["trip_id"], "rb52-late", "not the one that has gone, and not the one an hour later");
}

// ---------------------------------------------------------------------------
// The way on after a missed connection (#81, #82)
// ---------------------------------------------------------------------------
//
// Memmingen, 2 October 2026: the RE 96 came in late and the RE 75 at 09:04 to Ulm had gone. The
// next train that gets anyone on is the RS 7 at 09:32 to Ulm, which reaches the same ICE there as
// the RE 75 at 10:04. Asked for the destination, MOTIS answers only with connections nothing else
// beats, and an earlier train that catches the same onward train as a later one is not among
// them — on the day, all it had left was the RE 75 at 11:02. Asked for Ulm, every train is there.
// Times below are minutes from now.

const LINDAU: (&str, &str) = ("vs:1", "Lindau-Reutin");
const MEMMINGEN: (&str, &str) = ("vs:2", "Memmingen");
const ULM: (&str, &str) = ("vs:4", "Ulm Hbf");
const SAARBRUECKEN: (&str, &str) = ("vs:3", "Saarbrücken Hbf");

/// One MOTIS leg on [trip] from one stop to another, leaving [dep] minutes from now, [mins] long.
fn motis_leg(trip: &str, line: &str, from: (&str, &str), to: (&str, &str), dep: i64, mins: i64) -> Value {
    let d = Utc::now() + Duration::minutes(dep);
    json!({
        "mode": "REGIONAL_RAIL", "tripId": trip, "routeShortName": line, "headsign": to.1, "agencyName": "DB Regio AG", "realTime": false,
        "from": {"name": from.1, "stopId": from.0, "scheduledDeparture": d, "track": "4"},
        "to": {"name": to.1, "stopId": to.0, "scheduledArrival": d + Duration::minutes(mins), "track": "1"},
    })
}

/// A MOTIS itinerary of [legs].
fn motis_route(legs: Vec<Value>) -> Value {
    json!({"id": legs[0]["tripId"], "transfers": legs.len() - 1, "legs": legs})
}

fn rs7() -> Value {
    motis_leg("rs7", "RS 7", MEMMINGEN, ULM, 20, 51)
}
fn re75_1004() -> Value {
    motis_leg("re75-1004", "RE 75", MEMMINGEN, ULM, 52, 34)
}
fn re75_1102() -> Value {
    motis_leg("re75-1102", "RE 75", MEMMINGEN, ULM, 110, 35)
}
fn ice610() -> Value {
    motis_leg("ice610", "ICE 610", ULM, SAARBRUECKEN, 95, 205)
}
fn ice1247() -> Value {
    motis_leg("ice1247", "ICE 1247", ULM, SAARBRUECKEN, 215, 205)
}

/// A stand-in for Transitous that answers the way MOTIS does: each `/api/v1/plan` by where it is
/// asked to go from and to, with what leaves from the time asked for on; `/api/v1/trip` with any
/// leg it knows. A question it has no route for gets no itineraries.
async fn transitous_routes(routes: Vec<(&'static str, &'static str, Vec<Value>)>) -> String {
    use axum::extract::Query;
    use std::collections::HashMap;
    let routes = Arc::new(routes);
    let trips = routes.clone();
    let app = Router::new()
        .route(
            "/api/v1/plan",
            get(move |Query(q): Query<HashMap<String, String>>| {
                let routes = routes.clone();
                async move {
                    let at = |v: &Value| v.as_str().and_then(|t| t.parse::<chrono::DateTime<Utc>>().ok());
                    let time = q.get("time").and_then(|t| t.parse::<chrono::DateTime<Utc>>().ok());
                    let (from, to) = (q.get("fromPlace").cloned().unwrap_or_default(), q.get("toPlace").cloned().unwrap_or_default());
                    let its: Vec<Value> = routes
                        .iter()
                        .filter(|(f, t, _)| *f == from && *t == to)
                        .flat_map(|(_, _, its)| its.iter().cloned())
                        .filter(|it| match (time, at(&it["legs"][0]["from"]["scheduledDeparture"])) {
                            (Some(t), Some(d)) => d >= t,
                            _ => true,
                        })
                        .collect();
                    axum::Json(json!({ "itineraries": its }))
                }
            }),
        )
        .route(
            "/api/v1/trip",
            get(move |Query(q): Query<HashMap<String, String>>| {
                let routes = trips.clone();
                async move {
                    let id = q.get("tripId").cloned().unwrap_or_default();
                    let leg = routes
                        .iter()
                        .flat_map(|(_, _, its)| its.iter())
                        .flat_map(|it| it["legs"].as_array().cloned().unwrap_or_default())
                        .find(|l| l["tripId"] == id.as_str());
                    match leg {
                        Some(l) => Ok(axum::Json(json!({ "legs": [l] }))),
                        None => Err(StatusCode::NOT_FOUND),
                    }
                }
            }),
        );
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    format!("http://{addr}")
}

/// Memmingen as Transitous saw it: toward Ulm [to_ulm], toward Saarbrücken [to_saarbruecken],
/// and from Ulm the two ICEs on.
async fn memmingen_planner(to_ulm: Vec<Value>, to_saarbruecken: Vec<Value>) -> String {
    transitous_routes(vec![
        (MEMMINGEN.0, ULM.0, to_ulm.into_iter().map(|l| motis_route(vec![l])).collect()),
        (MEMMINGEN.0, SAARBRUECKEN.0, to_saarbruecken),
        (ULM.0, SAARBRUECKEN.0, vec![motis_route(vec![ice610()]), motis_route(vec![ice1247()])]),
    ])
    .await
}

/// What MOTIS answers for Memmingen → Saarbrücken that morning: the RE 75 at 11:02 and nothing earlier.
fn only_the_1102() -> Vec<Value> {
    vec![motis_route(vec![re75_1102(), ice1247()])]
}

/// Our legs of the journey as booked: the RE 96 into Memmingen, the RE 75 at 09:04 to Ulm (it
/// left eight minutes ago), the ICE on to Saarbrücken.
fn booked() -> Vec<Value> {
    let now = Utc::now();
    vec![
        leg("re96", "RE 96", LINDAU, MEMMINGEN, now - Duration::minutes(60), 55),
        leg("re75-0904", "RE 75", MEMMINGEN, ULM, now - Duration::minutes(8), 34),
        leg("ice690", "ICE 690", ULM, SAARBRUECKEN, now + Duration::minutes(50), 180),
    ]
}

/// One of our plan legs from a MOTIS one, as the server stores them after a re-plan.
fn planned(motis: &Value) -> Value {
    let at = |v: &Value| v.as_str().unwrap().parse::<chrono::DateTime<Utc>>().unwrap();
    let (dep, arr) = (at(&motis["from"]["scheduledDeparture"]), at(&motis["to"]["scheduledArrival"]));
    leg(
        motis["tripId"].as_str().unwrap(),
        motis["routeShortName"].as_str().unwrap(),
        (motis["from"]["stopId"].as_str().unwrap(), motis["from"]["name"].as_str().unwrap()),
        (motis["to"]["stopId"].as_str().unwrap(), motis["to"]["name"].as_str().unwrap()),
        dep,
        (arr - dep).num_minutes(),
    )
}

/// A plan leg as the proposal after a missed connection: `next_leg` carries why.
fn as_proposal(l: &Value) -> Value {
    let mut n = l.clone();
    n["replanned"] = json!(true);
    n["reason"] = json!("verpasst");
    n
}

/// Lindau → Saarbrücken with [plan], the RE 96 into Memmingen done ([riding]: still on it).
/// At the change, [next] is the proposal.
async fn memmingen_journey(pool: &PgPool, customer: Uuid, plan: Vec<Value>, next: Option<Value>) -> Uuid {
    let now = Utc::now();
    let id = Uuid::new_v4();
    let riding = next.is_none();
    sqlx::query(
        "insert into journeys (id, customer_id, origin_station_id, origin_station_name, destination_station_id, destination_station_name,
                               itinerary, plan, planned_departure, planned_arrival, ticket, status, current_leg, next_leg, transfer_deadline)
         values ($1, $2, $3, $4, $5, $6, $7, $7, $8, $9, 'deutschlandticket', $10::journey_status, 1, $11, $12)",
    )
    .bind(id)
    .bind(customer)
    .bind(LINDAU.0)
    .bind(LINDAU.1)
    .bind(SAARBRUECKEN.0)
    .bind(SAARBRUECKEN.1)
    .bind(json!(plan))
    .bind(now - Duration::minutes(60))
    .bind(now + Duration::minutes(230))
    .bind(if riding { "riding" } else { "transfer" })
    .bind(&next)
    .bind(if riding { None } else { Some(now + Duration::hours(2)) })
    .execute(pool)
    .await
    .expect("journey");
    sqlx::query(
        "insert into rides (id, customer_id, trip_id, line, operator, category, from_station_id, from_station_name, exit_station_id, exit_station_name,
                            planned_departure, planned_arrival, actual_arrival, ticket, status, final_delay_min, journey_id, leg_no,
                            transfer_station_id, transfer_station_name, finalised_at)
         values ($1, $2, 're96', 'RE 96', 'DB Regio', 're', $3, $4, $5, $6, $7, $8, $9, 'deutschlandticket', $10::ride_status, $11, $12, 1, $5, $6, $9)",
    )
    .bind(Uuid::new_v4())
    .bind(customer)
    .bind(LINDAU.0)
    .bind(LINDAU.1)
    .bind(MEMMINGEN.0)
    .bind(MEMMINGEN.1)
    .bind(now - Duration::minutes(60))
    .bind(now - Duration::minutes(5))
    .bind(if riding { None } else { Some(now - Duration::minutes(2)) })
    .bind(if riding { "riding" } else { "arrived" })
    .bind(if riding { None } else { Some(3) })
    .bind(id)
    .execute(pool)
    .await
    .expect("leg 1");
    id
}

fn trips_of(plan: &Value) -> Vec<String> {
    plan.as_array().unwrap().iter().map(|l| l["trip_id"].as_str().unwrap().to_string()).collect()
}

async fn journey_row(pool: &PgPool, id: Uuid) -> (String, Value, Value, bool, Option<chrono::DateTime<Utc>>) {
    sqlx::query_as("select status::text, coalesce(next_leg, 'null'::jsonb), plan, missed_connection, earliest_onward_arrival from journeys where id = $1")
        .bind(id)
        .fetch_one(pool)
        .await
        .unwrap()
}

#[sqlx::test(migrations = "./migrations")]
async fn a_missed_connection_proposes_the_next_train_onward_not_the_next_best_arrival(pool: PgPool) {
    let to_saarbruecken = only_the_1102();
    let cap: chrono::DateTime<Utc> = to_saarbruecken[0]["legs"][1]["to"]["scheduledArrival"].as_str().unwrap().parse().unwrap();
    let base = memmingen_planner(vec![rs7(), re75_1102()], to_saarbruecken).await;
    let app = app(pool.clone(), Some(base)).await;
    let (me, token) = device(&app).await;
    let journey = memmingen_journey(&pool, me, booked(), None).await;

    // The RE 96 reaches Memmingen a minute ago; the RE 75 at 09:04 left seven minutes before that.
    let (s, v) = call(&app, "POST", "/v1/rides/current/arrival", Some(&token), Some(json!({"actual_arrival": Utc::now() - Duration::minutes(1)}))).await;
    assert_eq!(s, StatusCode::OK, "{v}");

    let (status, next, plan, missed, earliest) = journey_row(&pool, journey).await;
    assert_eq!(status, "transfer");
    assert!(missed, "the connection was missed");
    assert_eq!(next["trip_id"], "rs7", "the next train that gets the passenger on, not the next best arrival");
    assert_eq!(next["replanned"], true);
    assert_eq!(next["reason"], "verpasst");
    assert_eq!(trips_of(&plan), ["re96", "rs7", "ice610"], "on from where the RS 7 arrives");
    // The cap is what it always was: the earliest arrival the destination plan knows (docs/21 §2).
    let earliest = earliest.expect("the earliest onward arrival is recorded");
    assert!((earliest - cap).num_seconds().abs() < 1, "cap {earliest} is not the destination plan's {cap}");
}

#[sqlx::test(migrations = "./migrations")]
async fn missed_proposes_the_next_train_onward_too(pool: PgPool) {
    let base = memmingen_planner(vec![rs7(), re75_1102()], only_the_1102()).await;
    let app = app(pool.clone(), Some(base)).await;
    let (me, token) = device(&app).await;
    // The RE 75 at 09:04 was still there when the RE 96 came in, and left without the passenger.
    let mut plan = booked();
    plan[1] = leg("re75-0904", "RE 75", MEMMINGEN, ULM, Utc::now() - Duration::minutes(2), 34);
    let journey = memmingen_journey(&pool, me, plan.clone(), Some(plan[1].clone())).await;

    let (s, v) = call(&app, "POST", &format!("/v1/journeys/{journey}/missed"), Some(&token), None).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let (_, next, plan, missed, _) = journey_row(&pool, journey).await;
    assert_eq!(next["trip_id"], "rs7", "the next train toward Ulm, not the next best arrival in Saarbrücken");
    assert_eq!(next["missed_trip_ids"], json!(["re75-0904"]), "the server remembers what was missed here");
    assert_eq!(trips_of(&plan), ["re96", "rs7", "ice610"]);
    assert!(missed);
}

#[sqlx::test(migrations = "./migrations")]
async fn a_second_missed_does_not_bring_back_the_first(pool: PgPool) {
    // #82: two taps on „Leider verpasst" swapped the RS 7 and the RE 75 back and forth, and
    // every tap sent a push.
    let base = memmingen_planner(
        vec![rs7(), re75_1004(), re75_1102()],
        vec![motis_route(vec![rs7(), ice610()]), motis_route(vec![re75_1004(), ice610()]), motis_route(vec![re75_1102(), ice1247()])],
    )
    .await;
    let (app, events) = app_and_events(pool.clone(), Some(base)).await;
    let (me, token) = device(&app).await;
    let mut plan = booked();
    plan[1] = planned(&rs7());
    plan[2] = planned(&ice610());
    let journey = memmingen_journey(&pool, me, plan.clone(), Some(as_proposal(&plan[1]))).await;
    let mut tap = events.tap();

    let (s, v) = call(&app, "POST", &format!("/v1/journeys/{journey}/missed"), Some(&token), None).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let (_, next, _, _, _) = journey_row(&pool, journey).await;
    assert_eq!(next["trip_id"], "re75-1004");
    assert_eq!(tap.try_recv().map(|(_, e)| e.kind).ok(), Some("journey"), "a new proposal is news");

    let (s, v) = call(&app, "POST", &format!("/v1/journeys/{journey}/missed"), Some(&token), None).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let (_, next, plan, _, _) = journey_row(&pool, journey).await;
    assert_ne!(next["trip_id"], "rs7", "the RS 7 was missed once already");
    assert_eq!(next["trip_id"], "re75-1102");
    assert_eq!(next["missed_trip_ids"], json!(["rs7", "re75-1004"]));
    assert_eq!(trips_of(&plan), ["re96", "re75-1102", "ice1247"], "and the ICE that one reaches");
}

#[sqlx::test(migrations = "./migrations")]
async fn missed_with_no_new_train_changes_nothing_and_sends_nothing(pool: PgPool) {
    let base = memmingen_planner(
        vec![rs7(), re75_1004(), re75_1102()],
        vec![motis_route(vec![rs7(), ice610()]), motis_route(vec![re75_1102(), ice1247()])],
    )
    .await;
    let (app, events) = app_and_events(pool.clone(), Some(base)).await;
    let (me, token) = device(&app).await;
    // Two taps before this one: the RS 7 and the RE 75 at 10:04 are missed, the 11:02 is proposed.
    let mut plan = booked();
    plan[1] = planned(&re75_1102());
    plan[2] = planned(&ice1247());
    let mut next = as_proposal(&plan[1]);
    next["missed_trip_ids"] = json!(["rs7", "re75-1004"]);
    let journey = memmingen_journey(&pool, me, plan, Some(next)).await;
    let (_, before, plan_before, _, earliest_before) = journey_row(&pool, journey).await;
    let mut tap = events.tap();

    let (s, _) = call(&app, "POST", &format!("/v1/journeys/{journey}/missed"), Some(&token), None).await;
    assert_eq!(s, StatusCode::NOT_FOUND, "nothing new to offer");
    let (_, next, plan, _, earliest) = journey_row(&pool, journey).await;
    assert_eq!(next, before, "the proposal stays");
    assert_eq!(plan, plan_before);
    assert_eq!(earliest, earliest_before);
    assert!(tap.try_recv().is_err(), "nothing published, so nothing pushed");
}

// ---------------------------------------------------------------------------
// POST /v1/claims/draft
// ---------------------------------------------------------------------------

#[sqlx::test(migrations = "./migrations")]
async fn a_draft_needs_four_euros_and_is_picked_up_again(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let (me, token) = device(&app).await;
    let desk = json!({"desk": "Servicecenter Fahrgastrechte"});

    let a = incident(&pool, me, None, 150, "gesammelt").await;
    let b = incident(&pool, me, None, 150, "gesammelt").await;
    let (s, v) = call(&app, "POST", "/v1/claims/draft", Some(&token), Some(desk.clone())).await;
    assert_eq!(s, StatusCode::PRECONDITION_FAILED, "3,00 € is below the payout floor: {v}");

    let c = incident(&pool, me, None, 150, "gesammelt").await;
    let (s, v) = call(&app, "POST", "/v1/claims/draft", Some(&token), Some(desk.clone())).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let first = v["claim"]["id"].as_str().or(v["id"].as_str()).expect("a claim id").to_string();

    // Coming back finds the same form.
    let (s, v) = call(&app, "POST", "/v1/claims/draft", Some(&token), Some(desk.clone())).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(v["claim"]["id"].as_str().or(v["id"].as_str()), Some(first.as_str()), "the draft was picked up, not built again");

    // Taking a case out drops the bundle under the floor again: refused, and the draft stands.
    let (s, _) = call(&app, "POST", "/v1/claims/draft", Some(&token), Some(json!({"desk": "Servicecenter Fahrgastrechte", "incident_ids": [a, b]}))).await;
    assert_eq!(s, StatusCode::PRECONDITION_FAILED);
    assert_eq!(count(&pool, "select count(*) from claims where customer_id = $1 and status = 'draft'", me).await, 1);
    let _ = c;
}

// ---------------------------------------------------------------------------
// Sending a claim, and the railway's answer
// ---------------------------------------------------------------------------
//
// Nothing leaves: without POSTMARK_TOKEN or SMTP_URL every send is a recorded dry run
// (`mail.rs`). The answer comes in through the same `process_inbound` the Postmark webhook uses —
// either planted by the Stellwerk (`/admin/customers/{id}/reply`, which plays the desk and is
// trusted) or as a raw message on `/internal/inbound-mail/raw`, which is not.

async fn admin(app: &Router, method: &str, path: &str, body: Value) -> (StatusCode, Value) {
    let req = Request::builder()
        .method(method)
        .uri(path)
        .header("x-admin-token", std::env::var("ADMIN_TOKEN").unwrap_or_else(|_| "stellwerk".into()))
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))
        .unwrap();
    let res = app.clone().oneshot(req).await.expect("response");
    let status = res.status();
    let bytes = axum::body::to_bytes(res.into_body(), 16 * 1024 * 1024).await.unwrap();
    (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
}

/// A raw RFC 822 message on the inbound webhook, as the relay would hand it over.
async fn raw_mail(app: &Router, from: &str, to: &str, subject: &str, body: &str) -> (StatusCode, Value) {
    let msg = format!(
        "From: {from}\r\nTo: {to}\r\nSubject: {subject}\r\nMessage-ID: <{}@test.invalid>\r\nDate: Wed, 24 Sep 2026 10:00:00 +0200\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n{body}\r\n",
        Uuid::new_v4()
    );
    let res = app.clone().oneshot(Request::builder().method("POST").uri("/internal/inbound-mail/raw").body(Body::from(msg)).unwrap()).await.unwrap();
    let status = res.status();
    let bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024).await.unwrap();
    (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
}

struct Sent {
    customer: Uuid,
    token: String,
    claim: Uuid,
    /// The address the claim went out from; the desk answers to it.
    reply_to: String,
    email: String,
}

/// A customer with three cases at the Servicecenter, the route to the rehearsal address, and the
/// claim drafted, signed and sent — through the API, the way the app does it.
async fn sent_claim(app: &Router, pool: &PgPool) -> Sent {
    let (s, v) = admin(app, "PUT", "/admin/routes", json!({"desk": "Servicecenter Fahrgastrechte", "to_address": "probelauf@verspaetomat.de", "label": "Test"})).await;
    assert_eq!(s, StatusCode::OK, "route: {v}");
    let (customer, token) = device(app).await;
    let email = format!("fahrgast-{}@example.org", &customer.simple().to_string()[..6]);
    let (s, _) = call(app, "PUT", "/v1/me/personal-data", Some(&token), Some(json!({"name": "Test Fahrgast", "address": "Weg 1, 50667 Köln", "email": email}))).await;
    assert_eq!(s, StatusCode::OK);
    for _ in 0..3 {
        incident(pool, customer, None, 150, "gesammelt").await;
    }
    let (s, v) = call(app, "POST", "/v1/claims/draft", Some(&token), Some(json!({"desk": "Servicecenter Fahrgastrechte"}))).await;
    assert_eq!(s, StatusCode::OK, "draft: {v}");
    let claim: Uuid = v["claim"]["id"].as_str().or(v["id"].as_str()).unwrap().parse().unwrap();

    let (s, _) = call(app, "POST", &format!("/v1/claims/{claim}/send"), Some(&token), None).await;
    assert_eq!(s, StatusCode::PRECONDITION_FAILED, "nothing leaves without a signature");

    let (s, _) = call(app, "POST", &format!("/v1/claims/{claim}/sign"), Some(&token), Some(json!({"typed_name": "Test Fahrgast"}))).await;
    assert_eq!(s, StatusCode::OK);
    let (s, v) = call(app, "POST", &format!("/v1/claims/{claim}/send"), Some(&token), None).await;
    assert_eq!(s, StatusCode::OK, "send: {v}");
    let reply_to: String = sqlx::query_scalar("select reply_address from claims where id = $1").bind(claim).fetch_one(pool).await.unwrap();
    Sent { customer, token, claim, reply_to, email }
}

async fn claim_status(pool: &PgPool, claim: Uuid) -> String {
    sqlx::query_scalar("select status::text from claims where id = $1").bind(claim).fetch_one(pool).await.unwrap()
}

async fn incident_statuses(pool: &PgPool, claim: Uuid) -> Vec<String> {
    sqlx::query_scalar("select distinct i.status::text from incidents i join claim_incidents ci on ci.incident_id = i.id where ci.claim_id = $1 order by 1")
        .bind(claim)
        .fetch_all(pool)
        .await
        .unwrap()
}

#[sqlx::test(migrations = "./migrations")]
async fn sending_records_one_mail_to_the_route_from_the_claims_own_address(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let sent = sent_claim(&app, &pool).await;

    assert_eq!(claim_status(&pool, sent.claim).await, "sent");
    assert_eq!(incident_statuses(&pool, sent.claim).await, vec!["eingereicht"]);
    let (to, from, bcc, dry_run, direction): (String, String, Option<String>, bool, String) =
        sqlx::query_as("select to_addr, from_addr, bcc_addr, dry_run, direction::text from mails where claim_id = $1").bind(sent.claim).fetch_one(&pool).await.unwrap();
    assert_eq!(direction, "out");
    assert_eq!(to, "probelauf@verspaetomat.de", "the route's address and nothing else");
    assert!(from.contains(&sent.reply_to), "from the claim's own address: {from}");
    assert_eq!(bcc.as_deref(), Some(sent.email.as_str()), "a copy to the passenger");
    assert!(dry_run, "no mail credentials in a test: recorded, not sent");

    let (s, _) = call(&app, "POST", &format!("/v1/claims/{}/send", sent.claim), Some(&sent.token), None).await;
    assert_eq!(s, StatusCode::CONFLICT, "a claim goes out once");
}

#[sqlx::test(migrations = "./migrations")]
async fn an_accepted_answer_confirms_the_money_and_shows_in_the_share_figures(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let sent = sent_claim(&app, &pool).await;

    let (s, v) = admin(&app, "POST", &format!("/admin/customers/{}/reply", sent.customer), json!({"outcome": "accepted"})).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(claim_status(&pool, sent.claim).await, "accepted");
    assert_eq!(incident_statuses(&pool, sent.claim).await, vec!["bestaetigt"]);
    let confirmed: Option<i64> = sqlx::query_scalar("select amount_confirmed_cents from claims where id = $1").bind(sent.claim).fetch_one(&pool).await.unwrap();
    assert_eq!(confirmed, Some(450), "the amount the answer names");

    // #49: the moment worth a card.
    let (_, share) = call(&app, "GET", "/v1/me/share", Some(&sent.token), None).await;
    assert_eq!(share["confirmed_cents"], 450);
    assert_eq!(share["confirmed_claims"][0]["claim_id"], sent.claim.to_string());
    assert_eq!(share["confirmed_claims"][0]["cents"], 450);
    assert_eq!(share["confirmed_claims"][0]["cases"], 3);

    // The inbound mail is on the claim, and it was forwarded (dry run) to the passenger.
    let inbound: i64 = sqlx::query_scalar("select count(*) from mails where claim_id = $1 and direction = 'inbound'").bind(sent.claim).fetch_one(&pool).await.unwrap();
    assert_eq!(inbound, 1);
}

#[sqlx::test(migrations = "./migrations")]
async fn a_question_asks_and_a_refusal_refuses(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let sent = sent_claim(&app, &pool).await;
    let (s, _) = admin(&app, "POST", &format!("/admin/customers/{}/reply", sent.customer), json!({"outcome": "question"})).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(claim_status(&pool, sent.claim).await, "question");
    assert_eq!(incident_statuses(&pool, sent.claim).await, vec!["eingereicht"], "a question decides nothing");

    let (s, _) = admin(&app, "POST", &format!("/admin/customers/{}/reply", sent.customer), json!({"outcome": "rejected"})).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(claim_status(&pool, sent.claim).await, "rejected");
    assert_eq!(incident_statuses(&pool, sent.claim).await, vec!["abgelehnt"]);
    let (_, share) = call(&app, "GET", "/v1/me/share", Some(&sent.token), None).await;
    assert_eq!(share["confirmed_cents"], 0, "a refusal pays nobody");
}

#[sqlx::test(migrations = "./migrations")]
async fn only_the_desk_can_confirm_money(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let sent = sent_claim(&app, &pool).await;
    let paid = "Sehr geehrte Damen und Herren,\n\nwir haben Ihren Antrag geprüft und eine Entschädigung von insgesamt 4,50 EUR festgestellt. Der Betrag wird überwiesen.\n\nMit freundlichen Grüßen\nIhr Servicecenter Fahrgastrechte";

    // The passenger holds the reply address — they get a copy of every claim — and could write
    // this themselves. The reading has its own rule for that („sent from the passenger's own
    // address"), ahead of the sender check.
    let (s, v) = raw_mail(&app, &format!("Test Fahrgast <{}>", sent.email), &sent.reply_to, "Re: Fahrgastrechte: EU-Antragsformular", paid).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(claim_status(&pool, sent.claim).await, "sent", "the passenger cannot pay themselves");

    // Anybody else who learnt the address: not one of the route's answer domains (`guard_sender`).
    let (s, _) = raw_mail(&app, "Servicecenter Fahrgastrechte <service@fahrgastrechte-erstattung.example>", &sent.reply_to, "Ihr Antrag", paid).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(claim_status(&pool, sent.claim).await, "sent", "not the desk's domain: nothing moves");

    // From the desk's domain, but nothing on the receiving side verified it (no DKIM or SPF verdict
    // the server may trust): still nothing.
    let (s, _) = raw_mail(&app, "Servicecenter <antwort@verspaetomat.de>", &sent.reply_to, "Ihr Antrag", paid).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(claim_status(&pool, sent.claim).await, "sent", "an unverified sender moves nothing");
    assert_eq!(incident_statuses(&pool, sent.claim).await, vec!["eingereicht"]);

    // All three are kept, read, and on the claim — only without consequence.
    let inbound: i64 = sqlx::query_scalar("select count(*) from mails where claim_id = $1 and direction = 'inbound'").bind(sent.claim).fetch_one(&pool).await.unwrap();
    assert_eq!(inbound, 3);
}

#[sqlx::test(migrations = "./migrations")]
async fn an_acknowledgement_and_an_absence_note_decide_nothing(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let sent = sent_claim(&app, &pool).await;
    for (subject, body) in [
        ("Eingangsbestätigung Ihres Antrags", "Sehr geehrte Damen und Herren,\n\nvielen Dank für Ihre Nachricht. Ihr Antrag ist bei uns eingegangen und wird bearbeitet. Bitte sehen Sie von Rückfragen ab.\n\nIhr Servicecenter Fahrgastrechte"),
        ("Abwesenheitsnotiz", "Ich bin bis zum 30.09. nicht im Büro und habe keinen Zugriff auf meine E-Mails. In dringenden Fällen wenden Sie sich bitte an das Servicecenter."),
    ] {
        let (s, v) = raw_mail(&app, "Servicecenter <antwort@verspaetomat.de>", &sent.reply_to, subject, body).await;
        assert_eq!(s, StatusCode::OK, "{subject}: {v}");
        assert_eq!(claim_status(&pool, sent.claim).await, "sent", "{subject}");
    }
}

#[sqlx::test(migrations = "./migrations")]
async fn a_bounce_marks_the_claim_whoever_sends_it(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let sent = sent_claim(&app, &pool).await;
    let (s, v) = raw_mail(
        &app,
        "Mail Delivery System <MAILER-DAEMON@mx.example.net>",
        &sent.reply_to,
        "Undelivered Mail Returned to Sender",
        "This is the mail system at host mx.example.net.\n\nI'm sorry to have to inform you that your message could not be delivered to one or more recipients.\n\n<probelauf@verspaetomat.de>: host mx.example.net said: 550 5.1.1 User unknown",
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{v}");
    // Bounces come from mail servers, not the desk, so the sender check does not apply to them
    // (`guard_sender`): the claim did not arrive, and the passenger has to hear that.
    assert_eq!(claim_status(&pool, sent.claim).await, "bounced");
}

// ---------------------------------------------------------------------------
// Station premises (#64, docs/48)
// ---------------------------------------------------------------------------

/// A GET with extra headers; status, headers and the raw body.
async fn raw_get(app: &Router, path: &str, headers: &[(&str, &str)]) -> (StatusCode, axum::http::HeaderMap, Vec<u8>) {
    let mut b = Request::builder().method("GET").uri(path);
    for (k, v) in headers {
        b = b.header(*k, *v);
    }
    let res = app.clone().oneshot(b.body(Body::empty()).unwrap()).await.unwrap();
    let (status, h) = (res.status(), res.headers().clone());
    (status, h, axum::body::to_bytes(res.into_body(), 64 * 1024 * 1024).await.unwrap().to_vec())
}

async fn outline_count(pool: &PgPool) -> i64 {
    sqlx::query_scalar("select count(*) from station_outlines").fetch_one(pool).await.unwrap()
}

fn outline_row(station: i64) -> Value {
    json!({"station": station, "outline": [[50.9425, 6.9575], [50.9425, 6.9595], [50.9440, 6.9595]],
           "ring": {"lat": 50.943, "lon": 6.9587, "r": 420.0}, "touch": [{"lat": 50.943, "lon": 6.9587, "r": 150.0}], "osm": ["n1", "w2"]})
}

/// A run replaces the table whole; a broken row refuses all of it; a run that shrinks the table
/// below 80 % waits for `force`; the status says what is there.
#[sqlx::test]
async fn outlines_replace_the_table_whole_or_not_at_all(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let mut ids = Vec::new();
    for (i, name) in ["Köln Hbf", "Köln Messe/Deutz Bf", "Köln Süd", "Köln West", "Köln-Ehrenfeld"].iter().enumerate() {
        let id: i32 = sqlx::query_scalar("insert into stations (name, lat, lon, rank) values ($1, $2, 6.95, 2) returning id")
            .bind(name)
            .bind(50.94 + i as f64 * 0.01)
            .fetch_one(&pool)
            .await
            .unwrap();
        ids.push(id as i64);
    }
    let set = |rows: Vec<Value>| json!({"osm_timestamp": "2026-09-29", "outlines": rows});

    let (st, v) = admin(&app, "POST", "/admin/stations/outlines", set(ids.iter().map(|i| outline_row(*i)).collect())).await;
    assert_eq!(st, StatusCode::OK, "{v}");
    assert_eq!(v["committed"], true);
    assert_eq!(outline_count(&pool).await, 5);
    let osm: Vec<String> = sqlx::query_scalar("select unnest(osm_ids) from station_outlines where station_id = $1").bind(ids[0] as i32).fetch_all(&pool).await.unwrap();
    assert_eq!(osm, vec!["n1", "w2"]);

    // One touch point too small: nothing changes.
    let mut rows: Vec<Value> = ids.iter().map(|i| outline_row(*i)).collect();
    rows[1]["touch"][0]["r"] = json!(50.0);
    rows.truncate(4);
    let (st, _) = admin(&app, "POST", "/admin/stations/outlines", set(rows)).await;
    assert_eq!(st, StatusCode::BAD_REQUEST);
    assert_eq!(outline_count(&pool).await, 5);

    // An unknown station: nothing changes either.
    let (st, _) = admin(&app, "POST", "/admin/stations/outlines", set(vec![outline_row(999_999)])).await;
    assert_eq!(st, StatusCode::BAD_REQUEST);

    // Three of five is under 80 %: refused, then taken with force.
    let three = || set(ids[..3].iter().map(|i| outline_row(*i)).collect());
    let (_, v) = admin(&app, "POST", "/admin/stations/outlines", three()).await;
    assert_eq!(v["committed"], false, "{v}");
    assert!(v["note"].as_str().unwrap().contains("80 %"));
    let (_, v) = admin(&app, "POST", "/admin/stations/outlines?force=true", three()).await;
    assert_eq!(v["committed"], true);
    assert_eq!(outline_count(&pool).await, 3);

    let (_, v) = admin(&app, "GET", "/admin/stations", Value::Null).await;
    assert_eq!(v["outlines"]["count"], 3);
    assert_eq!(v["outlines"]["osm_timestamp"], "2026-09-29");

    // The files, from memory, on the public paths the website passes through (docs/48).
    let (st, h, body) = raw_get(&app, "/stations/umrisse-latest.json", &[]).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(h["cache-control"], "public, max-age=3600");
    let pointer: Value = serde_json::from_slice(&body).unwrap();
    // The pointer has no gzip copy: asked for gzip, it still comes plain and says so.
    let (_, h2, body2) = raw_get(&app, "/stations/umrisse-latest.json", &[("accept-encoding", "gzip")]).await;
    assert!(h2.get("content-encoding").is_none());
    // The CORS layer adds its own `vary: origin, …`; what must not be there is Accept-Encoding.
    assert!(!h2.get_all("vary").iter().any(|v| v.to_str().unwrap().to_lowercase().contains("accept-encoding")));
    assert_eq!(body2, body);
    assert_eq!(pointer["count"], 3);
    assert_eq!(pointer["license"], "ODbL-1.0");
    let url = pointer["url"].as_str().unwrap().to_string();
    let (st, h, body) = raw_get(&app, &url, &[]).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(h["content-type"], "application/octet-stream");
    assert!(h["cache-control"].to_str().unwrap().contains("immutable"));
    let read = crate::stations::outlines::parse_file(&body).unwrap();
    assert_eq!(read.rows.len(), 3);
    assert_eq!(read.version, pointer["version"].as_u64().unwrap() as u32);
    // The same ETag is a 304; another version is a 404, so a phone reads the pointer again.
    let etag = h["etag"].to_str().unwrap().to_string();
    let (st, _, _) = raw_get(&app, &url, &[("if-none-match", &etag)]).await;
    assert_eq!(st, StatusCode::NOT_MODIFIED);
    let (st, _, _) = raw_get(&app, "/stations/umrisse-1.bin", &[]).await;
    assert_eq!(st, StatusCode::NOT_FOUND);

    let (st, h, body) = raw_get(&app, "/daten/bahnhofsumrisse.geojson", &[]).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(h["content-type"], "application/geo+json");
    let g: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(g["license"], "ODbL-1.0");
    assert_eq!(g["features"].as_array().unwrap().len(), 3);
    assert_eq!(g["features"][0]["properties"]["name"], "Köln Hbf");
    let (_, h, gz) = raw_get(&app, "/daten/bahnhofsumrisse.geojson", &[("accept-encoding", "gzip, br")]).await;
    assert_eq!(h["content-encoding"], "gzip");
    let mut plain = Vec::new();
    std::io::Read::read_to_end(&mut flate2::read::GzDecoder::new(&gz[..]), &mut plain).unwrap();
    assert_eq!(plain, body);
}

// ---------------------------------------------------------------------------
// The aim reminder (#66, docs/49 §1): three months is what we aim for, twelve the hard limit
// ---------------------------------------------------------------------------

/// 21 days before the aim, once, and only for a case that can go out: a bundle below its minimum
/// gets no push towards a claim it cannot send yet.
#[sqlx::test(migrations = "./migrations")]
async fn the_aim_reminder_comes_once_and_only_when_ready(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let (customer, _) = device(&app).await;
    let today = crate::clock::today();
    let due = incident(&pool, customer, None, 450, "bereit").await;
    let fresh = incident(&pool, customer, None, 450, "bereit").await;
    let collecting = incident(&pool, customer, None, 150, "gesammelt").await;
    for (id, days_ago) in [(due, 80), (fresh, 10), (collecting, 80)] {
        let ride = today - chrono::Duration::days(days_ago);
        sqlx::query("update incidents set ride_date = $2, legal_deadline = $3 where id = $1")
            .bind(id)
            .bind(ride)
            .bind(crate::rules::legal_deadline(ride))
            .execute(&pool)
            .await
            .unwrap();
    }

    let (s, v) = admin(&app, "POST", "/admin/scan", json!({})).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(v["aimed"], 1, "only the ready case near its aim: {v}");
    assert_eq!(count(&pool, "select count(*) from incidents where id = $1 and aim_nudged_at is not null", due).await, 1);
    assert_eq!(v["warned"], 0, "the hard deadline is eleven months away");

    let (_, v) = admin(&app, "POST", "/admin/scan", json!({})).await;
    assert_eq!(v["aimed"], 0, "once per case");
}

// ---------------------------------------------------------------------------
// Tickets (#66, docs/49 §5.3, docs/50 phase 2)
// ---------------------------------------------------------------------------

/// The catalogue is public, a ticket is the passenger's own, and archiving keeps it for its cases.
#[sqlx::test(migrations = "./migrations")]
async fn tickets_are_made_changed_and_archived(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let (s, v) = call(&app, "GET", "/v1/fares", None, None).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let ids: Vec<&str> = v["fares"].as_array().unwrap().iter().filter_map(|f| f["id"].as_str()).collect();
    assert!(ids.contains(&"deutschlandticket") && ids.contains(&"bahncard100") && ids.contains(&"einzel_db"), "{ids:?}");
    let dt = v["fares"].as_array().unwrap().iter().find(|f| f["id"] == "deutschlandticket").unwrap();
    assert_eq!(dt["threshold_min"], 20);
    assert_eq!(dt["valid_on"]["long_distance"], false);
    assert_eq!(dt["ticket"], "deutschlandticket", "the legacy type an older build understands");

    let (customer, token) = device(&app).await;
    let (s, v) = call(&app, "POST", "/v1/me/tickets", Some(&token), Some(json!({ "product": "nope" }))).await;
    assert_eq!(s, StatusCode::BAD_REQUEST, "{v}");
    let (s, bc) = call(&app, "POST", "/v1/me/tickets", Some(&token), Some(json!({ "product": "bahncard100", "first_class": true, "number": "7081 4101 2345 6789" }))).await;
    assert_eq!(s, StatusCode::OK, "{bc}");
    assert_eq!((bc["name"].as_str(), bc["family"].as_str(), bc["ticket"].as_str()), (Some("BahnCard 100"), Some("bahncard100"), Some("zeitkarte")));
    let id = bc["id"].as_str().unwrap().to_string();

    let (s, v) = call(&app, "PATCH", &format!("/v1/me/tickets/{id}"), Some(&token), Some(json!({ "price_cents": 799900, "label": "Meine BahnCard" }))).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!((v["price_cents"].as_i64(), v["name"].as_str()), (Some(799900), Some("Meine BahnCard")));
    let (_, v) = call(&app, "PATCH", &format!("/v1/me/tickets/{id}"), Some(&token), Some(json!({ "price_cents": null }))).await;
    assert!(v["price_cents"].is_null(), "null clears: {v}");

    // Someone else's ticket is nobody's business.
    let (_, other) = device(&app).await;
    let (s, _) = call(&app, "PATCH", &format!("/v1/me/tickets/{id}"), Some(&other), Some(json!({ "label": "x" }))).await;
    assert_eq!(s, StatusCode::NOT_FOUND);

    let (s, _) = call(&app, "DELETE", &format!("/v1/me/tickets/{id}"), Some(&token), None).await;
    assert_eq!(s, StatusCode::OK);
    let (_, v) = call(&app, "GET", "/v1/me/tickets", Some(&token), None).await;
    assert_eq!(v["tickets"].as_array().unwrap().len(), 0);
    let (_, v) = call(&app, "GET", "/v1/me/tickets?all=true", Some(&token), None).await;
    assert_eq!(v["tickets"].as_array().unwrap().len(), 1, "archived, not gone");

    // The D-Ticket's number is the one an older build reads as personal data.
    call(&app, "POST", "/v1/me/tickets", Some(&token), Some(json!({ "product": "deutschlandticket", "number": "D-2026-1" }))).await;
    assert_eq!(count(&pool, "select count(*) from customers where id = $1 and ticket_number = 'D-2026-1'", customer).await, 1);
}

/// The rate follows the ticket, not the train (docs/49 §2.2): a BahnCard 100 is 10 € where a
/// "Zeitkarte" used to book 1,50 €, and a single ticket is a share of its own fare.
#[sqlx::test(migrations = "./migrations")]
async fn a_case_is_worth_what_its_ticket_is_owed(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let (customer, _) = device(&app).await;
    let backdate = |ticket: Option<&str>, delay: i64, price: Option<i64>| {
        json!({ "from": "Köln Hbf", "to": "Düsseldorf Hbf", "delay_minutes": delay, "days_ago": 2, "ticket": ticket, "price_cents": price })
    };
    let path = format!("/admin/customers/{customer}/backdate");

    let (s, v) = admin(&app, "POST", &path, backdate(Some("bahncard100"), 65, None)).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(v["incident"]["amount_cents"], 1000, "{v}");
    assert_eq!(v["incident"]["ticket"], "zeitkarte", "older builds still read a type they know");
    let bc = v["incident"]["ticket_id"].as_str().unwrap().to_string();
    // The second ride on it is the same ticket, not a new one.
    let (_, v) = admin(&app, "POST", &path, backdate(Some("bahncard100"), 61, None)).await;
    assert_eq!(v["incident"]["ticket_id"].as_str(), Some(bc.as_str()));

    let (_, v) = admin(&app, "POST", &path, backdate(Some("einzel_db"), 125, Some(3990))).await;
    assert_eq!(v["incident"]["amount_cents"], 1995, "{v}");
    let (_, v) = admin(&app, "POST", &path, backdate(Some("einzel_db"), 70, Some(3990))).await;
    assert_eq!(v["incident"]["amount_cents"], 998, "25 % of 39,90 € rounds commercially: {v}");

    // No ticket named: the customer's setting, as an older build meant it.
    let (_, v) = admin(&app, "POST", &path, backdate(None, 70, None)).await;
    assert_eq!(v["incident"]["amount_cents"], 150, "{v}");
    assert_eq!(count(&pool, "select count(*) from tickets where customer_id = $1 and product = 'deutschlandticket'", customer).await, 1);
    assert_eq!(count(&pool, "select count(*) from journey_tickets jt join journeys j on j.id = jt.journey_id where j.customer_id = $1", customer).await, 5, "every journey names its ticket");
}

/// Migration 0046 on rows as they were before tickets: each type becomes the ticket it meant.
#[sqlx::test(migrations = "./migrations")]
async fn old_rows_become_tickets(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let (dt_customer, _) = device(&app).await;
    let (zk_customer, _) = device(&app).await;
    sqlx::query("update customers set ticket = 'zeitkarte' where id = $1").bind(zk_customer).execute(&pool).await.unwrap();
    sqlx::query("update customers set ticket_number = 'D-77' where id = $1").bind(dt_customer).execute(&pool).await.unwrap();
    let dt_case = incident(&pool, dt_customer, None, 150, "gesammelt").await;
    let zk_case = incident(&pool, zk_customer, None, 150, "gesammelt").await;
    let zk_fern_case = incident(&pool, zk_customer, None, 500, "gesammelt").await;
    let single = incident(&pool, dt_customer, None, 997, "bereit").await;
    sqlx::query("update incidents set ticket = 'zeitkarte' where id = any($1)").bind(vec![zk_case, zk_fern_case]).execute(&pool).await.unwrap();
    sqlx::query("update incidents set ticket = 'einzelfahrkarte' where id = $1").bind(single).execute(&pool).await.unwrap();
    // A long-distance Zeitkarte ride: the migration makes a Streckenzeitkarte for it.
    let r = ride(&pool, zk_customer, "ICE 5", 70, 3).await;
    sqlx::query("update rides set ticket = 'zeitkarte', category = 'fern' where id = $1").bind(r).execute(&pool).await.unwrap();

    // As they were before tickets: no ticket anywhere.
    sqlx::query("update incidents set ticket_id = null").execute(&pool).await.unwrap();
    sqlx::query("update rides set ticket_id = null").execute(&pool).await.unwrap();
    sqlx::query("delete from journey_tickets").execute(&pool).await.unwrap();
    sqlx::query("delete from tickets").execute(&pool).await.unwrap();
    sqlx::raw_sql(include_str!("../migrations/0046_tickets_from_customers.sql")).execute(&pool).await.expect("migration 0046");

    let product = |id: Uuid| {
        let pool = pool.clone();
        async move { sqlx::query_scalar::<_, String>("select t.product from incidents i join tickets t on t.id = i.ticket_id where i.id = $1").bind(id).fetch_one(&pool).await.unwrap() }
    };
    assert_eq!(product(dt_case).await, "deutschlandticket");
    assert_eq!(product(zk_case).await, "zeitkarte_spnv");
    assert_eq!(product(zk_fern_case).await, "streckenzeitkarte", "5 € was the long-distance rate");
    assert_eq!(product(single).await, "einzel_db");
    assert_eq!(count(&pool, "select count(*) from tickets where id = $1 and price_cents is null", single).await, 1, "the assumed 39,90 € was nobody's fare");
    assert_eq!(count(&pool, "select count(*) from tickets where customer_id = $1 and product = 'deutschlandticket' and number = 'D-77'", dt_customer).await, 1);
    assert_eq!(count(&pool, "select count(*) from tickets where customer_id = $1 and product_unsure", zk_customer).await, 2, "nobody was asked which Verbund");
    assert_eq!(count(&pool, "select count(*) from rides where id = $1 and ticket_id is not null", r).await, 1);
}

// ---------------------------------------------------------------------------
// Pots (#66, docs/49 §5.5)
// ---------------------------------------------------------------------------

async fn backdated(app: &Router, customer: Uuid, ticket: &str, delay: i64, days_ago: i64, price: Option<i64>) -> Value {
    let body = json!({ "from": "Köln Hbf", "to": "Düsseldorf Hbf", "delay_minutes": delay, "days_ago": days_ago, "ticket": ticket, "price_cents": price });
    let (s, v) = admin(app, "POST", &format!("/admin/customers/{customer}/backdate"), body).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    v
}

/// Minutes from 20 on pool across days and months; the pot goes out once it is above 4 €.
#[sqlx::test(migrations = "./migrations")]
async fn a_dticket_pot_collects_minutes_and_goes_out_above_four_euros(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let (customer, token) = device(&app).await;
    let v = backdated(&app, customer, "deutschlandticket", 40, 40, None).await;
    assert!(v["incident"].is_object(), "40 minutes on a D-Ticket make a case now: {v}");
    backdated(&app, customer, "deutschlandticket", 40, 30, None).await;
    let v = backdated(&app, customer, "deutschlandticket", 15, 20, None).await;
    assert!(v["incident"].is_null(), "under 20 minutes: nothing");

    let (_, v) = call(&app, "GET", "/v1/incidents", Some(&token), None).await;
    let pots = v["summary"]["pots"].as_array().unwrap().clone();
    assert_eq!(pots.len(), 1, "{v}");
    assert_eq!((pots[0]["minutes"].as_i64(), pots[0]["amount_cents"].as_i64(), pots[0]["payable"].as_bool()), (Some(80), Some(150), Some(false)));
    assert_eq!(pots[0]["blockers"][0]["missing_minutes"], 100, "three full hours are the first amount above 4 €");
    assert_eq!(v["summary"]["desks"][0]["ready"], false, "older builds see the same through desks");
    let (s, e) = call(&app, "POST", "/v1/claims/draft", Some(&token), Some(json!({ "pot": pots[0]["id"] }))).await;
    assert_eq!(s, StatusCode::PRECONDITION_FAILED, "{e}");

    backdated(&app, customer, "deutschlandticket", 100, 10, None).await;
    let (_, v) = call(&app, "GET", "/v1/incidents", Some(&token), None).await;
    let pot = &v["summary"]["pots"][0];
    assert_eq!((pot["minutes"].as_i64(), pot["amount_cents"].as_i64(), pot["payable"].as_bool()), (Some(180), Some(450), Some(true)), "{pot}");
    let open: i64 = v["incidents"].as_array().unwrap().iter().filter(|i| i["status"] == "bereit").map(|i| i["amount_cents"].as_i64().unwrap()).sum();
    assert_eq!(open, 450, "the cases' shares add up to the pot");

    // A build before pots names the desk and gets the same claim.
    let (s, d) = call(&app, "POST", "/v1/claims/draft", Some(&token), Some(json!({ "desk": pot["desk"] }))).await;
    assert_eq!(s, StatusCode::OK, "{d}");
    assert_eq!(d["amount_claimed_cents"], 450);
    assert_eq!(d["incidents"].as_array().unwrap().len(), 3);
    assert_eq!(d["breakdown"]["minutes"], 180);
}

/// What the E2E of the build in the store checks against this server (deploy/compat.sh): four
/// hours make 6,00 €, three still go out, two fall under the floor and are refused.
#[sqlx::test(migrations = "./migrations")]
async fn a_selection_is_its_own_pot(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let (customer, token) = device(&app).await;
    let mut ids = Vec::new();
    for days in 2..=5 {
        let v = backdated(&app, customer, "deutschlandticket", 70, days, None).await;
        ids.push(v["incident"]["id"].as_str().unwrap().to_string());
    }
    let (_, v) = call(&app, "GET", "/v1/incidents", Some(&token), None).await;
    let desk = v["summary"]["pots"][0]["desk"].clone();
    let (s, d) = call(&app, "POST", "/v1/claims/draft", Some(&token), Some(json!({ "desk": desk }))).await;
    assert_eq!((s, d["amount_claimed_cents"].as_i64()), (StatusCode::OK, Some(600)), "{d}");
    let (s, d) = call(&app, "POST", "/v1/claims/draft", Some(&token), Some(json!({ "desk": desk, "incident_ids": &ids[..3] }))).await;
    assert_eq!((s, d["amount_claimed_cents"].as_i64()), (StatusCode::OK, Some(450)), "{d}");
    let (s, e) = call(&app, "POST", "/v1/claims/draft", Some(&token), Some(json!({ "desk": desk, "incident_ids": &ids[..2] }))).await;
    assert_eq!(s, StatusCode::PRECONDITION_FAILED, "{e}");
    assert_eq!(e["error"], "bundle below the 4 € minimum; keep collecting", "the words older builds know");

    // Picked up again with no selection named, the draft keeps its three cases and their 4,50 €,
    // not the four of the pot (the E2E of the build in the store does exactly this).
    let (s, d) = call(&app, "POST", "/v1/claims/draft", Some(&token), Some(json!({ "desk": desk }))).await;
    assert_eq!(s, StatusCode::OK, "{d}");
    assert_eq!((d["incidents"].as_array().unwrap().len(), d["amount_claimed_cents"].as_i64()), (3, Some(450)), "{d}");
}

/// A case moved to another ticket leaves the draft that held it and joins its new ticket's pot.
#[sqlx::test(migrations = "./migrations")]
async fn a_case_can_move_to_another_ticket(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let (customer, token) = device(&app).await;
    let mut ids = Vec::new();
    for days in 2..=4 {
        let v = backdated(&app, customer, "deutschlandticket", 70, days, None).await;
        ids.push(v["incident"]["id"].as_str().unwrap().to_string());
    }
    let (_, v) = call(&app, "GET", "/v1/incidents", Some(&token), None).await;
    let desk = v["summary"]["pots"][0]["desk"].clone();
    let (s, _) = call(&app, "POST", "/v1/claims/draft", Some(&token), Some(json!({ "desk": desk }))).await;
    assert_eq!(s, StatusCode::OK);

    let (_, bc) = call(&app, "POST", "/v1/me/tickets", Some(&token), Some(json!({ "product": "bahncard100" }))).await;
    let (s, v) = call(&app, "PATCH", &format!("/v1/incidents/{}", ids[0]), Some(&token), Some(json!({ "ticket_id": bc["id"] }))).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(v["claim_deleted"], true, "two D-Ticket hours are 3,00 €: the draft has nothing left to ask for");
    assert_eq!(v["incident"]["amount_cents"], 1000, "70 minutes on a BahnCard 100: {v}");
    assert_eq!(v["incident"]["status"], "bereit");

    let (_, v) = call(&app, "GET", "/v1/incidents", Some(&token), None).await;
    assert_eq!(v["summary"]["pots"].as_array().unwrap().len(), 2);
    let (s, _) = call(&app, "PATCH", &format!("/v1/incidents/{}", ids[1]), Some(&token), Some(json!({ "ticket_id": Uuid::new_v4() }))).await;
    assert_eq!(s, StatusCode::BAD_REQUEST, "only a ticket of one's own");
}

/// A single ticket without a price has no amount and says so; entering the price makes it one.
#[sqlx::test(migrations = "./migrations")]
async fn a_single_ticket_waits_for_its_price(pool: PgPool) {
    let app = app(pool.clone(), None).await;
    let (customer, token) = device(&app).await;
    let v = backdated(&app, customer, "einzel_db", 95, 3, None).await;
    let ticket = v["incident"]["ticket_id"].as_str().unwrap().to_string();
    let (_, v) = call(&app, "GET", "/v1/incidents", Some(&token), None).await;
    let pot = &v["summary"]["pots"][0];
    assert_eq!((pot["amount_cents"].as_i64(), pot["payable"].as_bool()), (Some(0), Some(false)), "{pot}");
    assert_eq!(pot["blockers"][0]["kind"], "price_missing");

    call(&app, "PATCH", &format!("/v1/me/tickets/{ticket}"), Some(&token), Some(json!({ "price_cents": 5990 }))).await;
    let (_, v) = call(&app, "GET", "/v1/incidents", Some(&token), None).await;
    let pot = &v["summary"]["pots"][0];
    assert_eq!((pot["amount_cents"].as_i64(), pot["payable"].as_bool()), (Some(1498), Some(true)), "25 % of 59,90 €: {pot}");
}
