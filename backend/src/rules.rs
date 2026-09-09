//! The rules the backend owns. Single source of truth for amounts, readiness,
//! deadlines and status refresh. See docs/20-backend.md.

use chrono::{Duration, Months, NaiveDate};

use crate::model::{Cents, Incident, IncidentStatus, TicketType, TrainCategory};

pub const MIN_PAYOUT_CENTS: Cents = 400;
pub const DTICKET_MONTHLY_PRICE_CENTS: Cents = 6300;
pub const LEGAL_DEADLINE_MONTHS: u32 = 3;
pub const WARN_DAYS_BEFORE_DEADLINE: i64 = 21;
pub const REPLY_EXPECTED_DAYS: i64 = 28;

/// Compensation for one delayed journey. None when nothing is owed.
pub fn claim_amount_cents(
    ticket: TicketType,
    category: TrainCategory,
    delay_minutes: i64,
    first_class: bool,
    fare_cents: Option<Cents>,
) -> Option<Cents> {
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

/// Points for a ride: one per minute late from minute 1; a cancellation is 60.
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
    ride_date
        .checked_add_months(Months::new(LEGAL_DEADLINE_MONTHS))
        .unwrap_or(ride_date)
}

pub fn days_until(deadline: NaiveDate, today: NaiveDate) -> i64 {
    (deadline - today).num_days()
}

pub fn warn_from(deadline: NaiveDate) -> NaiveDate {
    deadline - Duration::days(WARN_DAYS_BEFORE_DEADLINE)
}

/// Is the open bundle for a desk sendable? Ordinary-ticket incidents always are;
/// season-ticket incidents need the desk's open sum to reach the minimum payout.
pub fn bundle_ready(open_for_desk: &[&Incident]) -> bool {
    if open_for_desk.is_empty() {
        return false;
    }
    if open_for_desk.iter().any(|i| i.ticket == TicketType::Einzelfahrkarte) {
        return true;
    }
    open_for_desk.iter().map(|i| i.amount_cents).sum::<Cents>() >= MIN_PAYOUT_CENTS
}

/// Recompute `gesammelt` / `bereit` for every open incident, and expire what is past its deadline.
pub fn refresh_statuses(incidents: &mut [Incident], today: NaiveDate) {
    // Expire first.
    for i in incidents.iter_mut() {
        if i.status.is_open() && i.legal_deadline < today {
            i.status = IncidentStatus::Verfallen;
        }
    }
    // Then readiness per desk.
    let desks: Vec<String> = {
        let mut d: Vec<String> = incidents
            .iter()
            .filter(|i| i.status.is_open())
            .map(|i| i.desk.clone())
            .collect();
        d.sort();
        d.dedup();
        d
    };
    for desk in desks {
        let open: Vec<&Incident> = incidents
            .iter()
            .filter(|i| i.status.is_open() && i.desk == desk)
            .collect();
        let ready = bundle_ready(&open);
        for i in incidents.iter_mut().filter(|i| i.status.is_open() && i.desk == desk) {
            i.status = if ready {
                IncidentStatus::Bereit
            } else {
                IncidentStatus::Gesammelt
            };
        }
    }
}

/// Monthly cap for the Deutschlandticket: 25 % of the ticket price.
pub fn dticket_monthly_cap_cents() -> Cents {
    DTICKET_MONTHLY_PRICE_CENTS / 4
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn amounts() {
        assert_eq!(claim_amount_cents(TicketType::Deutschlandticket, TrainCategory::Re, 68, false, None), Some(150));
        assert_eq!(claim_amount_cents(TicketType::Deutschlandticket, TrainCategory::Re, 59, false, None), None);
        assert_eq!(claim_amount_cents(TicketType::Zeitkarte, TrainCategory::Fern, 70, false, None), Some(500));
        assert_eq!(claim_amount_cents(TicketType::Einzelfahrkarte, TrainCategory::Fern, 124, false, Some(3990)), Some(1995));
        assert_eq!(claim_amount_cents(TicketType::Einzelfahrkarte, TrainCategory::Fern, 70, false, Some(3990)), Some(997));
    }

    #[test]
    fn deadline() {
        let d = legal_deadline(NaiveDate::from_ymd_opt(2026, 9, 9).unwrap());
        assert_eq!(d, NaiveDate::from_ymd_opt(2026, 12, 9).unwrap());
    }
}
