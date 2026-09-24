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
    crate::db::seed(&pool).await.expect("seed");
    let client = TransitousClient::with_base(transitous.unwrap_or_else(|| "http://127.0.0.1:9".into()));
    let state = AppState {
        pool,
        train: Arc::new(TrainSource::new(client)),
        events: Arc::new(crate::events::EventHub::default()),
        push: Arc::new(crate::push::PushSender::from_env().expect("push sender")),
        stations: Arc::new(std::sync::RwLock::new(Arc::new(crate::stations::Index::default()))),
        flags: Arc::new(std::sync::RwLock::new(Arc::new(crate::flags::Table::default()))),
    };
    crate::router(state)
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

/// A claimable case at the Servicecenter, worth [cents], from [ride].
async fn incident(pool: &PgPool, customer: Uuid, ride: Option<Uuid>, cents: i64, status: &str) -> Uuid {
    let id = Uuid::new_v4();
    let ngo: String = sqlx::query_scalar("select id from ngos order by id limit 1").fetch_one(pool).await.expect("an ngo from the fixtures");
    sqlx::query(
        "insert into incidents (id, customer_id, ride_id, ride_date, line, from_name, to_name, delay_min, amount_cents, ticket, operator, desk,
                                ngo_id, legal_deadline, status)
         values ($1, $2, $3, current_date - 2, 'RE 1', 'Köln Hbf', 'Düsseldorf Hbf', 68, $4, 'deutschlandticket', 'DB Regio',
                 'Servicecenter Fahrgastrechte', $5, current_date + 300, $6::incident_status)",
    )
    .bind(id)
    .bind(customer)
    .bind(ride)
    .bind(cents)
    .bind(ngo)
    .bind(status)
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
