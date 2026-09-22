//! `GET /v1/me/share`: the facts the share cards are made of (issue #49).
//!
//! One passenger's own numbers, never anybody else's: what they waited, their longest delay, the
//! line that cost them most this month, last month in one card, and the claims the railway has
//! confirmed. The card is still drawn on the phone and nothing is published; this endpoint only
//! saves the app from recomputing figures the server already owns. Money comes from the same
//! columns as everywhere else, and only from claims and cases the railway has confirmed: the
//! confirmed amount where the answer named one, else the amount claimed for that confirmed case
//! (`coalesce(confirmed_cents, amount_cents)`, as on Ich and in the standing).
//!
//! Months are Berlin calendar months, cut with the server clock (`clock::now`, so the Stellwerk's
//! simulated time moves them too).

use axum::{extract::State, Json};
use chrono::{DateTime, Utc};
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

use crate::auth::{internal, Customer};
use crate::AppState;

type ApiResult = Result<Json<Value>, (axum::http::StatusCode, Json<Value>)>;

pub async fn share_facts(State(s): State<AppState>, c: Customer) -> ApiResult {
    Ok(Json(facts(&s.pool, c.0.id, crate::clock::now()).await.map_err(internal)?))
}

pub async fn facts(pool: &PgPool, id: Uuid, now: DateTime<Utc>) -> anyhow::Result<Value> {
    let (minutes, rides): (i64, i64) = sqlx::query_as(
        "select coalesce(sum(final_delay_min),0)::bigint, count(*) from rides where customer_id = $1 and status = 'arrived'",
    )
    .bind(id)
    .fetch_one(pool)
    .await?;
    let confirmed: i64 = sqlx::query_scalar(
        "select coalesce(sum(coalesce(confirmed_cents, amount_cents)),0)::bigint from incidents where customer_id = $1 and status = 'bestaetigt'",
    )
    .bind(id)
    .fetch_one(pool)
    .await?;

    // The longest delay so far. The ride id lets the phone tell a new record from one it has shown.
    let record: Option<(Uuid, String, Option<String>, i32, Option<DateTime<Utc>>)> = sqlx::query_as(
        "select id, line, exit_station_name, final_delay_min, coalesce(actual_arrival, planned_arrival)
         from rides where customer_id = $1 and status = 'arrived' and final_delay_min > 0
         order by final_delay_min desc, planned_arrival asc limit 1",
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;

    // The line that cost the most minutes in the running month.
    let line: Option<(String, i64, i64, String)> = sqlx::query_as(
        "select line, sum(final_delay_min)::bigint, count(*), to_char(date_trunc('month', $2 at time zone 'Europe/Berlin'), 'YYYY-MM')
         from rides
         where customer_id = $1 and status = 'arrived' and final_delay_min > 0
           and date_trunc('month', checked_in_at at time zone 'Europe/Berlin') = date_trunc('month', $2 at time zone 'Europe/Berlin')
         group by line order by 2 desc, 3 desc limit 1",
    )
    .bind(id)
    .bind(now)
    .fetch_optional(pool)
    .await?;

    // Last calendar month, whole. Null when nothing was late in it: an empty month gets no card.
    let month: (String, i64, i64, i64, i64) = sqlx::query_as(
        "select to_char(date_trunc('month', $2 at time zone 'Europe/Berlin') - interval '1 month', 'YYYY-MM'),
                coalesce(sum(final_delay_min),0)::bigint, count(*), coalesce(max(final_delay_min),0)::bigint, coalesce(sum(points),0)::bigint
         from rides
         where customer_id = $1 and status = 'arrived'
           and date_trunc('month', checked_in_at at time zone 'Europe/Berlin') = date_trunc('month', $2 at time zone 'Europe/Berlin') - interval '1 month'",
    )
    .bind(id)
    .bind(now)
    .fetch_one(pool)
    .await?;
    let month_confirmed: i64 = sqlx::query_scalar(
        "select coalesce(sum(coalesce(confirmed_cents, amount_cents)),0)::bigint from incidents
         where customer_id = $1 and status = 'bestaetigt' and to_char(ride_date, 'YYYY-MM') = $2",
    )
    .bind(id)
    .bind(&month.0)
    .fetch_one(pool)
    .await?;

    // Claims the railway has confirmed, newest first, for the moment that is worth a card.
    let confirmed_claims: Vec<(Uuid, i64, String, i64, i64, Option<DateTime<Utc>>)> = sqlx::query_as(
        "select c.id, coalesce(c.amount_confirmed_cents, c.amount_claimed_cents)::bigint, n.name,
                (select count(*) from claim_incidents ci where ci.claim_id = c.id),
                (select coalesce(sum(i.delay_min),0)::bigint from claim_incidents ci join incidents i on i.id = ci.incident_id where ci.claim_id = c.id),
                c.closed_at
         from claims c join ngos n on n.id = c.ngo_id
         where c.customer_id = $1 and c.status = 'accepted' and coalesce(c.closed_at, c.created_at) > $2 - interval '60 days'
         order by c.closed_at desc nulls last limit 5",
    )
    .bind(id)
    .bind(now)
    .fetch_all(pool)
    .await?;

    Ok(json!({
        "minutes_total": minutes,
        "rides_total": rides,
        "confirmed_cents": confirmed,
        "record": record.map(|(ride_id, line, to, min, at)| json!({ "ride_id": ride_id, "line": line, "to": to, "minutes": min, "at": at })),
        "top_line": line.map(|(line, min, n, month)| json!({ "line": line, "minutes": min, "rides": n, "month": month })),
        "last_month": (month.1 > 0).then(|| json!({
            "month": month.0, "minutes": month.1, "rides": month.2, "worst_minutes": month.3, "points": month.4, "confirmed_cents": month_confirmed,
        })),
        "confirmed_claims": confirmed_claims.into_iter().map(|(id, cents, ngo, cases, min, at)| json!({
            "claim_id": id, "cents": cents, "ngo": ngo, "cases": cases, "minutes": min, "confirmed_at": at,
        })).collect::<Vec<_>>(),
    }))
}
