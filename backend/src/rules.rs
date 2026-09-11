//! The rules the backend owns. Single source of truth for amounts, readiness,
//! deadlines and status refresh. See docs/20-backend.md.

use chrono::{Duration, Months, NaiveDate};
use sqlx::PgPool;
use uuid::Uuid;

use crate::db::rows::{ClaimStatus, IncidentRow, IncidentStatus, TicketType, TrainCategory};

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

/// What a draft claim becomes when one of its cases leaves it — discarded (docs/21 §4) or
/// deleted with its ride (docs/23 §2). Below the minimum the draft has nothing left to ask for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DraftAfterRemoval {
    /// Nothing sendable is left: the draft goes, and its cases are free again.
    Dropped,
    /// The draft stays and asks for this much.
    Reduced(Cents),
}

/// The rule both the discard and the delete apply to a draft claim (docs/23 §2).
pub fn draft_after_removal(rest: &[&IncidentRow]) -> DraftAfterRemoval {
    if rest.is_empty() || !bundle_ready(rest) {
        return DraftAfterRemoval::Dropped;
    }
    DraftAfterRemoval::Reduced(rest.iter().map(|i| i.amount_cents).sum())
}

/// What the passenger is told when a ride cannot be deleted (docs/23 §2).
pub const DELETE_IN_SENT_CLAIM: &str = "Diese Fahrt steckt in einem eingereichten Antrag.";

/// May this ride be deleted? Once its case has left the house — in a claim that is no longer a
/// draft, or with a status that says it was submitted — the ride is evidence and stays.
pub fn delete_refusal(claims: &[ClaimStatus], incidents: &[IncidentStatus]) -> Option<&'static str> {
    let gone = claims.iter().any(|s| *s != ClaimStatus::Draft)
        || incidents.iter().any(|s| matches!(s, IncidentStatus::Eingereicht | IncidentStatus::Bestaetigt));
    if gone {
        Some(DELETE_IN_SENT_CLAIM)
    } else {
        None
    }
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
        if i.open() && i.legal_deadline < today {
            changes.push((i.id, i.status, IncidentStatus::Verfallen));
            i.status = IncidentStatus::Verfallen;
        }
    }
    changes.extend(apply_monthly_cap(&mut rows));
    let mut desks: Vec<String> = rows.iter().filter(|i| i.open()).map(|i| i.desk.clone()).collect();
    desks.sort();
    desks.dedup();
    for desk in desks {
        let open: Vec<&IncidentRow> = rows.iter().filter(|i| i.open() && i.desk == desk).collect();
        let target = if bundle_ready(&open) { IncidentStatus::Bereit } else { IncidentStatus::Gesammelt };
        for i in rows.iter_mut().filter(|i| i.open() && i.desk == desk) {
            if i.status != target {
                changes.push((i.id, i.status, target));
                i.status = target;
            }
        }
    }
    for (id, from, to) in changes {
        sqlx::query("update incidents set status = $2 where id = $1").bind(id).bind(to).execute(pool).await?;
        let reason = match (from, to) {
            (_, IncidentStatus::Gedeckelt) => "monthly cap",
            (IncidentStatus::Gedeckelt, _) => "cap released",
            _ => "refresh",
        };
        audit(pool, "incident", id, Some(from_label(from)), from_label(to), reason).await?;
    }
    Ok(rows)
}

/// The 25 % monthly cap for the Deutschlandticket. Per calendar month of the ride, incidents
/// are summed in ride order (rejected and expired ones do not count); from the incident that
/// pushes the month over the cap on, open ones become `gedeckelt`. A `gedeckelt` incident
/// that fits again (an earlier one was rejected or expired) returns to `gesammelt`.
/// Mutates the rows and returns the transitions; the caller writes and audits them.
pub fn apply_monthly_cap(rows: &mut [IncidentRow]) -> Vec<(Uuid, IncidentStatus, IncidentStatus)> {
    let cap = dticket_monthly_cap_cents();
    let mut order: Vec<usize> = (0..rows.len()).filter(|&k| rows[k].ticket == TicketType::Deutschlandticket).collect();
    order.sort_by_key(|&k| (rows[k].ride_date, rows[k].created_at));
    let mut sums: std::collections::BTreeMap<(i32, u32), Cents> = std::collections::BTreeMap::new();
    let mut changes = Vec::new();
    for k in order {
        let i = &mut rows[k];
        // Rejected, expired and discarded incidents never consume the month's cap.
        if matches!(i.status, IncidentStatus::Abgelehnt | IncidentStatus::Verfallen) || i.discarded_at.is_some() {
            continue;
        }
        use chrono::Datelike;
        let sum = sums.entry((i.ride_date.year(), i.ride_date.month())).or_insert(0);
        *sum += i.amount_cents;
        let over = *sum > cap;
        let target = match (i.status, over) {
            (s, true) if s.is_open() => Some(IncidentStatus::Gedeckelt),
            (IncidentStatus::Gedeckelt, false) => Some(IncidentStatus::Gesammelt),
            _ => None,
        };
        if let Some(t) = target {
            changes.push((i.id, i.status, t));
            i.status = t;
        }
    }
    changes
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

    fn incident(day: u32, status: IncidentStatus, amount: Cents) -> IncidentRow {
        IncidentRow {
            id: Uuid::new_v4(),
            customer_id: Uuid::nil(),
            ride_id: None,
            ride_date: NaiveDate::from_ymd_opt(2026, 9, day).unwrap(),
            line: "RE 1".into(),
            from_name: "A".into(),
            to_name: "B".into(),
            delay_min: 70,
            amount_cents: amount,
            ticket: TicketType::Deutschlandticket,
            operator: "DB Regio NRW".into(),
            desk: "DB".into(),
            status,
            cancelled: false,
            self_entered: false,
            ngo_id: "bahnhofsmission".into(),
            claim_id: None,
            fare_cents: None,
            legal_deadline: NaiveDate::from_ymd_opt(2026, 12, day).unwrap(),
            evidence: None,
            created_at: chrono::Utc::now(),
            journey_id: None,
            discarded_at: None,
            discard_reason: None,
        }
    }

    /// docs/21 §4: a discarded case counts nowhere — not in a bundle, not against the cap.
    #[test]
    fn discarded_incidents_count_nowhere() {
        let mut i = incident(3, IncidentStatus::Gesammelt, 150);
        assert!(i.open());
        i.discarded_at = Some(chrono::Utc::now());
        assert!(!i.open(), "discarded is never open, whatever the status says");

        // The month's cap: eleven of twelve fit (1575 / 150). Discarding two early ones frees
        // the two that were capped.
        let mut rows: Vec<IncidentRow> = (1..=12).map(|d| incident(d, IncidentStatus::Gesammelt, 150)).collect();
        apply_monthly_cap(&mut rows);
        assert_eq!(rows.iter().filter(|i| i.status == IncidentStatus::Gedeckelt).count(), 2);
        rows[0].discarded_at = Some(chrono::Utc::now());
        rows[1].discarded_at = Some(chrono::Utc::now());
        apply_monthly_cap(&mut rows);
        assert_eq!(rows.iter().filter(|i| i.status == IncidentStatus::Gedeckelt).count(), 0, "two discarded cases free the two that were over the cap");
    }

    /// The rule a discard applies to a draft claim: what is left must still reach the minimum.
    #[test]
    fn draft_survives_a_discard_only_above_the_minimum() {
        let three: Vec<IncidentRow> = (1..=3).map(|d| incident(d, IncidentStatus::Bereit, 150)).collect();
        let refs: Vec<&IncidentRow> = three.iter().collect();
        assert!(bundle_ready(&refs), "3 × 1,50 € = 4,50 € is above the 4 € minimum");
        let refs: Vec<&IncidentRow> = three.iter().take(2).collect();
        assert!(!bundle_ready(&refs), "taking one out drops the rest to 3,00 €: the draft goes");
        let refs: Vec<&IncidentRow> = Vec::new();
        assert!(!bundle_ready(&refs), "an empty remainder is never ready");
    }

    /// docs/23 §2: a ride logged by accident can go — unless it is already out of the house.
    #[test]
    fn deleting_a_ride() {
        // Nothing holds it: the incident goes with the ride.
        assert_eq!(delete_refusal(&[], &[IncidentStatus::Gesammelt]), None);
        assert_eq!(delete_refusal(&[ClaimStatus::Draft], &[IncidentStatus::Bereit]), None, "a draft can still be corrected");

        // A claim that left the house refuses, whatever else is true.
        assert_eq!(delete_refusal(&[ClaimStatus::Sent], &[IncidentStatus::Eingereicht]), Some(DELETE_IN_SENT_CLAIM));
        assert_eq!(delete_refusal(&[ClaimStatus::Accepted], &[IncidentStatus::Bestaetigt]), Some(DELETE_IN_SENT_CLAIM));
        assert_eq!(delete_refusal(&[ClaimStatus::Draft, ClaimStatus::Sent], &[]), Some(DELETE_IN_SENT_CLAIM), "one sent bundle is enough");
        assert_eq!(delete_refusal(&[], &[IncidentStatus::Eingereicht]), Some(DELETE_IN_SENT_CLAIM), "submitted without a claim row we can see: still evidence");
        // A rejected or expired case is over, not out: deleting it takes nothing back from anyone.
        assert_eq!(delete_refusal(&[], &[IncidentStatus::Abgelehnt]), None);
        assert_eq!(delete_refusal(&[], &[IncidentStatus::Verfallen]), None);

        // The draft is recomputed exactly as a discard does it: 3 × 1,50 € stays, 2 × 1,50 € goes.
        let three: Vec<IncidentRow> = (1..=3).map(|d| incident(d, IncidentStatus::Bereit, 150)).collect();
        let rest: Vec<&IncidentRow> = three.iter().take(2).collect();
        assert_eq!(draft_after_removal(&rest), DraftAfterRemoval::Dropped, "3,00 € is below the 4 € minimum: the draft goes with it");
        let four: Vec<IncidentRow> = (1..=4).map(|d| incident(d, IncidentStatus::Bereit, 150)).collect();
        let rest: Vec<&IncidentRow> = four.iter().take(3).collect();
        assert_eq!(draft_after_removal(&rest), DraftAfterRemoval::Reduced(450), "what is left still reaches the minimum and asks for less");
        assert_eq!(draft_after_removal(&[]), DraftAfterRemoval::Dropped, "the last case out empties the draft");
    }

    #[test]
    fn monthly_cap() {
        // 6300 / 4 = 1575: ten incidents of 150 fit, the eleventh is capped.
        let mut rows: Vec<IncidentRow> = (1..=12).map(|d| incident(d, IncidentStatus::Gesammelt, 150)).collect();
        let changes = apply_monthly_cap(&mut rows);
        assert_eq!(changes.len(), 2);
        assert_eq!(rows.iter().filter(|i| i.status == IncidentStatus::Gedeckelt).count(), 2);
        assert_eq!(rows[10].status, IncidentStatus::Gedeckelt);
        assert_eq!(rows[9].status, IncidentStatus::Gesammelt);
        // A rejection earlier in the month releases one capped incident.
        rows[0].status = IncidentStatus::Abgelehnt;
        let changes = apply_monthly_cap(&mut rows);
        assert_eq!(changes, vec![(rows[10].id, IncidentStatus::Gedeckelt, IncidentStatus::Gesammelt)]);
        // Other months and other tickets are untouched.
        let mut other = vec![incident(3, IncidentStatus::Gesammelt, 5000)];
        other[0].ticket = TicketType::Zeitkarte;
        assert!(apply_monthly_cap(&mut other).is_empty());
    }

    #[test]
    fn points() {
        assert_eq!(points_for(14, false, false), 14);
        assert_eq!(points_for(0, true, false), 60);
        assert_eq!(points_for(90, false, true), 1);
    }
}
