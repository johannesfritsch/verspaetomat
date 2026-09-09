//! The deadline scanner: one tokio task, hourly (first pass 30 s after start), on the
//! simulated clock. It warns 21 days before an incident's legal deadline, expires open
//! incidents at the deadline for every customer, nudges when a sent claim passed its
//! expected reply date without an answer, and sweeps attachments of closed claims.
//! Every pass is idempotent: `warned_at` and `nudged_at` mark what already went out.

use std::time::Duration;

use chrono::{DateTime, NaiveDate, Utc};
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

use crate::clock;
use crate::rules;
use crate::AppState;

const FIRST_RUN_AFTER: Duration = Duration::from_secs(30);
const INTERVAL: Duration = Duration::from_secs(3600);

pub fn spawn(state: AppState) {
    tokio::spawn(async move {
        tokio::time::sleep(FIRST_RUN_AFTER).await;
        loop {
            match run_once(&state).await {
                Ok(v) => tracing::info!(warned = %v["warned"], expired = %v["expired"], nudged = %v["nudged"], retained = %v["retained"], "deadline scanner pass"),
                Err(e) => tracing::error!("deadline scanner: {e}"),
            }
            tokio::time::sleep(INTERVAL).await;
        }
    });
}

/// One pass. Public so the admin API can trigger it (`POST /admin/scan`) and a test can drive it.
pub async fn run_once(s: &AppState) -> anyhow::Result<Value> {
    let today = clock::today();
    let expired = expire(s, today).await?;
    let warned = warn(s, today).await?;
    let nudged = nudge(s, today).await?;
    let retained = sweep_retention(&s.pool).await?;
    Ok(json!({ "today": today, "expired": expired, "warned": warned, "nudged": nudged, "retained": retained }))
}

/// (b) Open incidents past their deadline become `verfallen`, for every customer that has one.
/// `rules::refresh_statuses` does the transition and the audit per customer.
async fn expire(s: &AppState, today: NaiveDate) -> anyhow::Result<usize> {
    let customers: Vec<Uuid> = sqlx::query_scalar("select distinct customer_id from incidents where status in ('gesammelt','bereit') and legal_deadline < $1").bind(today).fetch_all(&s.pool).await?;
    let mut n = 0;
    for customer in customers {
        let rows = rules::refresh_statuses(&s.pool, customer, today).await?;
        let expired: Vec<Uuid> = rows.iter().filter(|i| i.status == crate::db::rows::IncidentStatus::Verfallen && i.legal_deadline < today).map(|i| i.id).collect();
        n += expired.len();
        s.events.publish(customer, "incident", json!({ "expired": expired }));
    }
    Ok(n)
}

/// (a) 21 days before the legal deadline, once per incident.
async fn warn(s: &AppState, today: NaiveDate) -> anyhow::Result<usize> {
    let due: Vec<(Uuid, Uuid, NaiveDate)> = sqlx::query_as(
        "update incidents set warned_at = now()
         where status in ('gesammelt','bereit') and warned_at is null and legal_deadline >= $1 and legal_deadline - $2::int <= $1
         returning id, customer_id, legal_deadline",
    )
    .bind(today)
    .bind(rules::WARN_DAYS_BEFORE_DEADLINE as i32)
    .fetch_all(&s.pool)
    .await?;
    for (id, customer, deadline) in &due {
        s.events.publish(*customer, "incident", json!({ "incident_id": id, "warning": true, "legal_deadline": deadline, "days_left": rules::days_until(*deadline, today) }));
    }
    Ok(due.len())
}

/// (c) A sent claim past `expected_reply_by` with no inbound mail: nudge once.
async fn nudge(s: &AppState, today: NaiveDate) -> anyhow::Result<usize> {
    let due: Vec<(Uuid, Uuid, Option<NaiveDate>)> = sqlx::query_as(
        "update claims set nudged_at = now()
         where status = 'sent' and nudged_at is null and expected_reply_by < $1
           and not exists (select 1 from mails m where m.claim_id = claims.id and m.direction = 'inbound')
         returning id, customer_id, expected_reply_by",
    )
    .bind(today)
    .fetch_all(&s.pool)
    .await?;
    for (id, customer, expected) in &due {
        s.events.publish(*customer, "claim", json!({ "claim_id": id, "nudge": true, "expected_reply_by": expected }));
    }
    Ok(due.len())
}

/// (d) Retention for one closed claim (accepted or rejected): the bytes of its attachments and of
/// the inbound mails' attachments are deleted unless the customer keeps correspondence. Ledger,
/// claim, mail and audit rows stay. An upload still attached to another open claim is kept.
pub async fn retain_closed_claim(pool: &PgPool, claim_id: Uuid) -> anyhow::Result<bool> {
    let keep: Option<(bool, Option<DateTime<Utc>>)> = sqlx::query_as("select cu.keep_correspondence, c.closed_at from claims c join customers cu on cu.id = c.customer_id where c.id = $1").bind(claim_id).fetch_optional(pool).await?;
    let Some((keep_correspondence, closed_at)) = keep else { return Ok(false) };
    if keep_correspondence || closed_at.is_none() {
        return Ok(false);
    }
    let blanked = sqlx::query(
        "update uploads u set bytes = ''::bytea
         where octet_length(u.bytes) > 0
           and u.id in (select upload_id from claim_attachments where claim_id = $1)
           and not exists (select 1 from claim_attachments ca2 join claims c2 on c2.id = ca2.claim_id
                           where ca2.upload_id = u.id and c2.id <> $1 and c2.status not in ('accepted','rejected'))",
    )
    .bind(claim_id)
    .execute(pool)
    .await?
    .rows_affected();
    let inbound = sqlx::query(
        "delete from uploads u using mails m
         where m.claim_id = $1 and m.direction = 'inbound' and u.kind = 'inbound'
           and u.id::text in (select a->>'upload_id' from jsonb_array_elements(m.attachments) a)",
    )
    .bind(claim_id)
    .execute(pool)
    .await?
    .rows_affected();
    if blanked + inbound > 0 {
        rules::audit(pool, "claim", claim_id, None, "attachments-deleted", &format!("retention: {blanked} claim uploads blanked, {inbound} inbound attachments deleted")).await?;
    }
    Ok(blanked + inbound > 0)
}

/// Backstop for claims that closed before retention existed, or where the close path failed.
async fn sweep_retention(pool: &PgPool) -> anyhow::Result<usize> {
    let closed: Vec<Uuid> = sqlx::query_scalar(
        "select distinct c.id from claims c join customers cu on cu.id = c.customer_id
         where c.status in ('accepted','rejected') and c.closed_at is not null and not cu.keep_correspondence
           and (exists (select 1 from claim_attachments ca join uploads u on u.id = ca.upload_id where ca.claim_id = c.id and octet_length(u.bytes) > 0)
             or exists (select 1 from mails m join uploads u on u.kind = 'inbound' and u.id::text in (select a->>'upload_id' from jsonb_array_elements(m.attachments) a) where m.claim_id = c.id and m.direction = 'inbound'))",
    )
    .fetch_all(pool)
    .await?;
    let mut n = 0;
    for id in closed {
        if retain_closed_claim(pool, id).await? {
            n += 1;
        }
    }
    Ok(n)
}
