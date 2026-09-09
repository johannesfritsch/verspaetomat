//! The rules the backend owns. Single source of truth for amounts, readiness,
//! deadlines and status refresh. See docs/20-backend.md.

use chrono::{Duration, Months, NaiveDate};
use sqlx::PgPool;
use uuid::Uuid;

use crate::db::rows::{IncidentRow, IncidentStatus, TicketType, TrainCategory};

pub type Cents = i64;

pub const MIN_PAYOUT_CENTS: Cents = 400;
pub const DTICKET_MONTHLY_PRICE_CENTS: Cents = 6300;
pub const LEGAL_DEADLINE_MONTHS: u32 = 3;
pub const WARN_DAYS_BEFORE_DEADLINE: i64 = 21;
pub const REPLY_EXPECTED_DAYS: i64 = 28;
pub const DEFAULT_FARE_CENTS: Cents = 3990;

/// Compensation for one delayed journey. None when nothing is owed.
pub fn claim_amount_cents(ticket: TicketType, category: TrainCategory, delay_minutes: i64, first_class: bool, fare_cents: Option<Cents>) -> Option<Cents> {
    if delay_minutes < 60 {
        return None;
    }
    let amount = match ticket {
        TicketType::Deutschlandticket => {
            if first_class {
                225
            } else {
                150
            }
        }
        TicketType::Zeitkarte => match (category, first_class) {
            (TrainCategory::Fern, false) => 500,
            (TrainCategory::Fern, true) => 750,
            (_, false) => 150,
            (_, true) => 225,
        },
        TicketType::Einzelfahrkarte => {
            let fare = fare_cents?;
            if delay_minutes >= 120 {
                fare / 2
            } else {
                fare / 4
            }
        }
    };
    Some(amount)
}

/// Points for a ride: one per minute late from minute 1; a cancellation is 60; a Nachtrag is 1.
pub fn points_for(delay_minutes: i64, cancelled: bool, nachtrag: bool) -> i64 {
    if nachtrag {
        return 1;
    }
    if cancelled {
        return 60.max(delay_minutes);
    }
    delay_minutes.max(0)
}

pub fn legal_deadline(ride_date: NaiveDate) -> NaiveDate {
    ride_date.checked_add_months(Months::new(LEGAL_DEADLINE_MONTHS)).unwrap_or(ride_date)
}

pub fn days_until(deadline: NaiveDate, today: NaiveDate) -> i64 {
    (deadline - today).num_days()
}

pub fn warn_from(deadline: NaiveDate) -> NaiveDate {
    deadline - Duration::days(WARN_DAYS_BEFORE_DEADLINE)
}

pub fn dticket_monthly_cap_cents() -> Cents {
    DTICKET_MONTHLY_PRICE_CENTS / 4
}

/// Is the open bundle for a desk sendable? Ordinary-ticket incidents always are;
/// season-ticket incidents need the desk's open sum to reach the minimum payout.
pub fn bundle_ready(open_for_desk: &[&IncidentRow]) -> bool {
    if open_for_desk.is_empty() {
        return false;
    }
    if open_for_desk.iter().any(|i| i.ticket == TicketType::Einzelfahrkarte) {
        return true;
    }
    open_for_desk.iter().map(|i| i.amount_cents).sum::<Cents>() >= MIN_PAYOUT_CENTS
}

/// Recompute `gesammelt` / `bereit` for a customer's open incidents and expire what is
/// past its deadline. Writes only rows whose status changed, with an audit entry.
pub async fn refresh_statuses(pool: &PgPool, customer_id: Uuid, today: NaiveDate) -> anyhow::Result<Vec<IncidentRow>> {
    let mut rows: Vec<IncidentRow> = sqlx::query_as("select * from incidents where customer_id = $1 order by ride_date desc, created_at desc")
        .bind(customer_id)
        .fetch_all(pool)
        .await?;

    let mut changes: Vec<(Uuid, IncidentStatus, IncidentStatus)> = Vec::new();
    for i in rows.iter_mut() {
        if i.status.is_open() && i.legal_deadline < today {
            changes.push((i.id, i.status, IncidentStatus::Verfallen));
            i.status = IncidentStatus::Verfallen;
        }
    }
    let mut desks: Vec<String> = rows.iter().filter(|i| i.status.is_open()).map(|i| i.desk.clone()).collect();
    desks.sort();
    desks.dedup();
    for desk in desks {
        let open: Vec<&IncidentRow> = rows.iter().filter(|i| i.status.is_open() && i.desk == desk).collect();
        let target = if bundle_ready(&open) { IncidentStatus::Bereit } else { IncidentStatus::Gesammelt };
        for i in rows.iter_mut().filter(|i| i.status.is_open() && i.desk == desk) {
            if i.status != target {
                changes.push((i.id, i.status, target));
                i.status = target;
            }
        }
    }
    for (id, from, to) in changes {
        sqlx::query("update incidents set status = $2 where id = $1").bind(id).bind(to).execute(pool).await?;
        audit(pool, "incident", id, Some(from_label(from)), from_label(to), "refresh").await?;
    }
    Ok(rows)
}

pub fn from_label(s: IncidentStatus) -> &'static str {
    match s {
        IncidentStatus::Gesammelt => "gesammelt",
        IncidentStatus::Bereit => "bereit",
        IncidentStatus::Eingereicht => "eingereicht",
        IncidentStatus::Bestaetigt => "bestaetigt",
        IncidentStatus::Abgelehnt => "abgelehnt",
        IncidentStatus::Verfallen => "verfallen",
        IncidentStatus::Gedeckelt => "gedeckelt",
    }
}

pub async fn audit(pool: &PgPool, entity: &str, id: Uuid, from: Option<&str>, to: &str, reason: &str) -> anyhow::Result<()> {
    sqlx::query("insert into audit_log (entity, entity_id, from_status, to_status, reason) values ($1, $2, $3, $4, $5)")
        .bind(entity)
        .bind(id)
        .bind(from)
        .bind(to)
        .bind(reason)
        .execute(pool)
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn amounts() {
        assert_eq!(claim_amount_cents(TicketType::Deutschlandticket, TrainCategory::Re, 68, false, None), Some(150));
        assert_eq!(claim_amount_cents(TicketType::Deutschlandticket, TrainCategory::Re, 59, false, None), None);
        assert_eq!(claim_amount_cents(TicketType::Deutschlandticket, TrainCategory::Re, 60, true, None), Some(225));
        assert_eq!(claim_amount_cents(TicketType::Zeitkarte, TrainCategory::Fern, 70, false, None), Some(500));
        assert_eq!(claim_amount_cents(TicketType::Einzelfahrkarte, TrainCategory::Fern, 124, false, Some(3990)), Some(1995));
        assert_eq!(claim_amount_cents(TicketType::Einzelfahrkarte, TrainCategory::Fern, 70, false, Some(3990)), Some(997));
    }

    #[test]
    fn deadline() {
        let d = legal_deadline(NaiveDate::from_ymd_opt(2026, 9, 9).unwrap());
        assert_eq!(d, NaiveDate::from_ymd_opt(2026, 12, 9).unwrap());
    }

    #[test]
    fn points() {
        assert_eq!(points_for(14, false, false), 14);
        assert_eq!(points_for(0, true, false), 60);
        assert_eq!(points_for(90, false, true), 1);
    }
}
