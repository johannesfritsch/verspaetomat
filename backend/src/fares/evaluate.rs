//! What a pot is worth (docs/49 §5.5): one ticket's cases in one window, evaluated against that
//! ticket's rule. Pure — no database, no clock but the `today` it is handed — so every rule in the
//! catalogue can be tested with plain numbers.

use chrono::{Datelike, Months, NaiveDate};
use serde::Serialize;
use uuid::Uuid;

use super::{Cents, Compensation, DeadlineFrom, Payout, Product, Rule, Submit, Window};

/// What the evaluation needs to know about the ticket.
#[derive(Debug, Clone, Default)]
pub struct TicketFacts {
    pub first_class: bool,
    /// What the passenger paid: for a single ticket the fare of this direction, for a season
    /// ticket the price of the window its cap is counted in (the month, for the D-Ticket). None =
    /// not entered: a single ticket then has no amount, a season ticket falls back to the list
    /// price, and without one it has no cap (docs/49 §9, decision 4).
    pub price_cents: Option<Cents>,
    pub valid_from: Option<NaiveDate>,
    pub valid_until: Option<NaiveDate>,
}

#[derive(Debug, Clone)]
pub struct CaseFacts {
    pub id: Uuid,
    pub ride_date: NaiveDate,
    /// Arrival delay at this ticket's destination, in minutes.
    pub delay_min: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Excluded {
    BelowThreshold,
    Expired,
}

/// One case's part of the pot.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct CaseShare {
    pub id: Uuid,
    /// Minutes that count (0 when excluded).
    pub minutes: i64,
    /// Cents this case brings, after caps. The shares add up to the pot's amount, which is what
    /// the ledger books per ride.
    pub cents: Cents,
    pub capped: bool,
    pub excluded: Option<Excluded>,
    pub deadline: NaiveDate,
}

/// Why a pot cannot leave the house yet. The app turns these into sentences; it never computes
/// them itself.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Blocker {
    Empty,
    PriceMissing,
    NotMoney,
    BelowMinimum { missing_cents: Cents, missing_minutes: Option<i64> },
    TooFewCases { missing: u32 },
    WindowOpen { until: NaiveDate },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Pot {
    pub cases: Vec<CaseShare>,
    /// Counted minutes (all kinds; for a minute pool this is what the money is made of).
    pub minutes: i64,
    /// Minute pools: minutes until the next full unit.
    pub next_unit_minutes: Option<i64>,
    /// Before caps.
    pub gross: Cents,
    pub capped: bool,
    pub amount: Cents,
    pub payable: bool,
    /// The first day it may be sent, when that is not today already.
    pub ready_from: Option<NaiveDate>,
    /// The earliest hard deadline among the counted cases.
    pub deadline: Option<NaiveDate>,
    /// The earliest date we aim to have sent it by.
    pub aim: Option<NaiveDate>,
    pub blockers: Vec<Blocker>,
}

fn plus_months(d: NaiveDate, months: u32) -> NaiveDate {
    d.checked_add_months(Months::new(months)).unwrap_or(d)
}

fn month_end(d: NaiveDate) -> NaiveDate {
    plus_months(d.with_day(1).unwrap_or(d), 1).pred_opt().unwrap_or(d)
}

/// The hard deadline of one case.
pub fn case_deadline(rule: &Rule, ticket: &TicketFacts, ride_date: NaiveDate) -> NaiveDate {
    let from = match rule.deadline.from {
        DeadlineFrom::Ride => ride_date,
        // Unknown end of validity: the ride itself, which is never later than the real limit.
        DeadlineFrom::ValidityEnd => ticket.valid_until.unwrap_or(ride_date).max(ride_date),
    };
    plus_months(from, rule.deadline.months)
}

pub fn case_aim(rule: &Rule, ride_date: NaiveDate) -> NaiveDate {
    plus_months(ride_date, rule.deadline.aim_months)
}

/// The key cases share a cap under.
fn cap_key(per: Window, date: NaiveDate) -> (i32, u32, u32) {
    match per {
        Window::CalendarMonth => (date.year(), date.month(), 0),
        Window::ValidityDay => (date.year(), date.month(), date.day()),
        Window::Ticket | Window::Validity | Window::Semester | Window::Subscription => (0, 0, 0),
    }
}

/// Evaluate one pot. The rule is the product's rule on the date of the latest case (a pot's cases
/// normally share one), `today` decides deadlines and windows.
pub fn evaluate(product: &Product, ticket: &TicketFacts, cases: &[CaseFacts], today: NaiveDate) -> Pot {
    let latest = cases.iter().map(|c| c.ride_date).max().unwrap_or(today);
    let rule = product.rule_on(latest);
    let mut order: Vec<&CaseFacts> = cases.iter().collect();
    order.sort_by_key(|c| c.ride_date);

    let threshold = rule.compensation.threshold() as i64;
    let mut blockers = Vec::new();
    let mut shares: Vec<CaseShare> = Vec::with_capacity(order.len());
    let mut pooled = 0i64;
    for c in &order {
        let deadline = case_deadline(rule, ticket, c.ride_date);
        let excluded = if deadline < today {
            Some(Excluded::Expired)
        } else if c.delay_min < threshold {
            Some(Excluded::BelowThreshold)
        } else {
            None
        };
        let minutes = if excluded.is_some() { 0 } else { c.delay_min };
        let cents = if excluded.is_some() {
            0
        } else {
            match &rule.compensation {
                Compensation::ShareOfPrice { steps } => {
                    let share = steps.iter().rev().find(|s| s.0 as i64 <= c.delay_min).map(|s| s.1).unwrap_or(0);
                    ticket.price_cents.map(|p| rule.rounding.share(p, share)).unwrap_or(0)
                }
                Compensation::PerCase { steps } => steps.iter().rev().find(|s| s.0 as i64 <= c.delay_min).map(|s| s.1.get(ticket.first_class)).unwrap_or(0),
                // Each case is credited with the full units its minutes complete, so the shares
                // add up to the pot and the order of rides decides who carries the remainder.
                Compensation::MinutePool { unit, per_unit, .. } => {
                    let before = pooled / *unit as i64;
                    pooled += minutes;
                    (pooled / *unit as i64 - before) * per_unit.get(ticket.first_class)
                }
                Compensation::NotMoney => 0,
            }
        };
        shares.push(CaseShare { id: c.id, minutes, cents, capped: false, excluded, deadline });
    }
    let gross: Cents = shares.iter().map(|s| s.cents).sum();

    // Caps, in ride order: whatever pushes a window over its limit is cut to what still fits.
    let mut capped = false;
    for cap in &rule.caps {
        let mut used: std::collections::BTreeMap<(i32, u32, u32), Cents> = Default::default();
        for (s, c) in shares.iter_mut().zip(&order) {
            if s.cents == 0 {
                continue;
            }
            let limit = match (cap.share, cap.fixed) {
                (Some(bp), _) => match ticket.price_cents.or_else(|| product.price_on(c.ride_date, ticket.first_class)) {
                    // Cut down to the cent: the cap is a ceiling, never a rounding up.
                    Some(price) => price * bp as Cents / 10_000,
                    None => continue,
                },
                (None, Some(fixed)) => fixed,
                (None, None) => continue,
            };
            let key = cap_key(cap.per, c.ride_date);
            let so_far = used.entry(key).or_insert(0);
            let fits = (limit - *so_far).max(0);
            if s.cents > fits {
                s.cents = fits;
                s.capped = true;
                capped = true;
            }
            *so_far += s.cents;
        }
    }
    let amount: Cents = shares.iter().map(|s| s.cents).sum();
    let counted: Vec<&CaseShare> = shares.iter().filter(|s| s.excluded.is_none()).collect();
    let minutes: i64 = counted.iter().map(|s| s.minutes).sum();

    let next_unit_minutes = match &rule.compensation {
        Compensation::MinutePool { unit, .. } if !counted.is_empty() => Some(*unit as i64 - minutes % *unit as i64),
        _ => None,
    };

    if counted.is_empty() {
        blockers.push(Blocker::Empty);
    }
    if rule.payout != Payout::Money || matches!(rule.compensation, Compensation::NotMoney) {
        blockers.push(Blocker::NotMoney);
    }
    if matches!(rule.compensation, Compensation::ShareOfPrice { .. }) && ticket.price_cents.is_none() && !counted.is_empty() {
        blockers.push(Blocker::PriceMissing);
    }
    if (counted.len() as u32) < rule.min_cases && !counted.is_empty() {
        blockers.push(Blocker::TooFewCases { missing: rule.min_cases - counted.len() as u32 });
    }
    let price_missing = blockers.contains(&Blocker::PriceMissing);
    if !counted.is_empty() && !price_missing && !rule.payout_min.met(amount) {
        let missing_cents = rule.payout_min.smallest() - amount;
        // For a pool, how many more minutes reach the first payable unit (caps aside).
        let missing_minutes = match &rule.compensation {
            Compensation::MinutePool { unit, per_unit, .. } => {
                let per = per_unit.get(ticket.first_class).max(1);
                let units = (rule.payout_min.smallest() + per - 1) / per;
                Some((units * *unit as i64 - minutes).max(0))
            }
            _ => None,
        };
        blockers.push(Blocker::BelowMinimum { missing_cents, missing_minutes });
    }

    let window_end = match rule.window {
        Window::Validity => ticket.valid_until,
        Window::ValidityDay => Some(latest),
        Window::CalendarMonth => Some(month_end(latest)),
        Window::Ticket | Window::Semester | Window::Subscription => None,
    };
    let short = match (ticket.valid_from, ticket.valid_until) {
        (Some(from), Some(until)) => (until - from).num_days() <= 31,
        // A Wochen- or Monatskarte whose dates we do not know: wait for the end of the month.
        _ => true,
    };
    let ready_from = match rule.submit {
        Submit::Immediately | Submit::WhenPayable => None,
        Submit::AfterWindow => window_end.or(Some(month_end(latest))).and_then(|d| d.succ_opt()),
        Submit::AfterShortWindow if short => window_end.or(Some(month_end(latest))).and_then(|d| d.succ_opt()),
        Submit::AfterShortWindow => None,
    }
    .filter(|d| *d > today);
    if let Some(d) = ready_from {
        if !counted.is_empty() {
            blockers.push(Blocker::WindowOpen { until: d });
        }
    }

    let deadline = counted.iter().map(|s| s.deadline).min();
    let aim = order.iter().zip(&shares).filter(|(_, s)| s.excluded.is_none()).map(|(c, _)| case_aim(rule, c.ride_date)).min();
    Pot { payable: blockers.is_empty(), cases: shares, minutes, next_unit_minutes, gross, capped, amount, ready_from, deadline, aim, blockers }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fares::catalogue;

    fn d(y: i32, m: u32, day: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(y, m, day).unwrap()
    }

    fn cases(list: &[(NaiveDate, i64)]) -> Vec<CaseFacts> {
        list.iter().map(|(date, delay)| CaseFacts { id: Uuid::new_v4(), ride_date: *date, delay_min: *delay }).collect()
    }

    fn eval(product: &str, ticket: TicketFacts, list: &[(NaiveDate, i64)], today: NaiveDate) -> Pot {
        evaluate(catalogue().product(product), &ticket, &cases(list), today)
    }

    const TODAY: (i32, u32, u32) = (2026, 10, 5);
    fn today() -> NaiveDate {
        d(TODAY.0, TODAY.1, TODAY.2)
    }

    // ── The examples of docs/49 §5.5 ────────────────────────────────────────────────────────────

    #[test]
    fn dticket_six_half_hours_make_three_hours() {
        let p = eval("deutschlandticket", TicketFacts::default(), &[(d(2026, 9, 1), 30); 6], today());
        assert_eq!((p.minutes, p.amount), (180, 450));
        assert!(p.payable, "{:?}", p.blockers);
        assert_eq!(p.cases.iter().map(|c| c.cents).sum::<Cents>(), p.amount, "the shares add up to the pot");
    }

    #[test]
    fn dticket_below_the_minimum_says_how_many_minutes_are_missing() {
        let p = eval("deutschlandticket", TicketFacts::default(), &[(d(2026, 9, 1), 70), (d(2026, 9, 2), 45), (d(2026, 9, 3), 25)], today());
        assert_eq!((p.minutes, p.amount), (140, 300));
        assert!(!p.payable);
        assert!(p.blockers.contains(&Blocker::BelowMinimum { missing_cents: 101, missing_minutes: Some(40) }), "{:?}", p.blockers);
        assert_eq!(p.next_unit_minutes, Some(40));
    }

    #[test]
    fn dticket_cap_per_month() {
        let p = eval("deutschlandticket", TicketFacts::default(), &[(d(2026, 9, 1), 60); 14], today());
        assert_eq!(p.gross, 2100);
        assert_eq!(p.amount, 1575, "25 % of 63 €");
        assert!(p.capped);
    }

    #[test]
    fn dticket_pools_across_months_and_caps_each_month_on_its_own() {
        // Johannes' case: the 31st and the 1st belong together.
        let p = eval("deutschlandticket", TicketFacts::default(), &[(d(2026, 8, 31), 40), (d(2026, 9, 1), 40), (d(2026, 9, 2), 100)], today());
        assert_eq!((p.minutes, p.amount), (180, 450));
        assert!(p.payable);

        // Two hours in August, twelve in September: August pays 3,00 €, September is cut to 15,75 €.
        let mut list = vec![(d(2026, 8, 10), 60), (d(2026, 8, 11), 60)];
        list.extend([(d(2026, 9, 1), 60); 12]);
        let p = eval("deutschlandticket", TicketFacts::default(), &list, today());
        assert_eq!(p.amount, 300 + 1575);
    }

    #[test]
    fn dticket_cap_follows_the_price_of_the_month() {
        // 2025 cost 58 €: 25 % is 14,50 €.
        let p = eval("deutschlandticket", TicketFacts::default(), &[(d(2025, 11, 3), 60); 12], d(2026, 1, 5));
        assert_eq!(p.amount, 1450);
        // A Jobticket at 59,85 €: the cap is cut to the cent below 14,9625 €.
        let job = TicketFacts { price_cents: Some(5985), ..Default::default() };
        let p = eval("deutschlandticket", job, &[(d(2026, 9, 3), 60); 12], today());
        assert_eq!(p.amount, 1496);
    }

    #[test]
    fn nrw_needs_three_cases() {
        let month = TicketFacts { price_cents: Some(9000), valid_from: Some(d(2026, 9, 1)), valid_until: Some(d(2026, 9, 30)), ..Default::default() };
        let p = eval("zeitkarte_vrr_nrw", month.clone(), &[(d(2026, 9, 3), 70), (d(2026, 9, 4), 70)], today());
        assert_eq!(p.amount, 300);
        assert!(p.blockers.contains(&Blocker::TooFewCases { missing: 1 }));

        let three = [(d(2026, 9, 3), 65), (d(2026, 9, 4), 65), (d(2026, 9, 5), 65)];
        let p = eval("zeitkarte_vrr_nrw", month.clone(), &three, d(2026, 9, 20));
        assert_eq!(p.amount, 450);
        assert_eq!(p.blockers, vec![Blocker::WindowOpen { until: d(2026, 10, 1) }], "a Monatskarte waits for the end of its month");
        assert!(eval("zeitkarte_vrr_nrw", month, &three, d(2026, 10, 1)).payable);
    }

    #[test]
    fn a_verbund_annual_ticket_is_sent_as_soon_as_it_pays() {
        let year = TicketFacts { price_cents: Some(90000), valid_from: Some(d(2026, 1, 1)), valid_until: Some(d(2026, 12, 31)), ..Default::default() };
        let p = eval("zeitkarte_spnv", year, &[(d(2026, 9, 3), 70), (d(2026, 9, 4), 70), (d(2026, 9, 5), 70)], today());
        assert!(p.payable, "{:?}", p.blockers);
        assert_eq!(p.amount, 450);
    }

    #[test]
    fn niedersachsen_counts_a_case_from_twenty_minutes() {
        let year = TicketFacts { valid_from: Some(d(2026, 1, 1)), valid_until: Some(d(2026, 12, 31)), ..Default::default() };
        let p = eval("zeitkarte_niedersachsen", year, &[(d(2026, 9, 3), 25), (d(2026, 9, 4), 25), (d(2026, 9, 5), 25)], today());
        assert_eq!(p.amount, 450);
    }

    #[test]
    fn bahncard100_pays_per_case_and_never_adds_up() {
        let bc = TicketFacts { valid_from: Some(d(2026, 3, 1)), valid_until: Some(d(2027, 2, 28)), ..Default::default() };
        let p = eval("bahncard100", bc.clone(), &[(d(2026, 9, 3), 61)], today());
        assert_eq!(p.amount, 1000);
        assert!(p.payable);
        let p = eval("bahncard100", bc.clone(), &[(d(2026, 9, 3), 50), (d(2026, 9, 4), 50)], today());
        assert_eq!(p.amount, 0);
        assert_eq!(p.blockers, vec![Blocker::Empty]);
        let first = TicketFacts { first_class: true, ..bc };
        assert_eq!(eval("bahncard100", first, &[(d(2026, 9, 3), 61)], today()).amount, 1500);
    }

    #[test]
    fn single_tickets_are_a_share_of_their_price() {
        let fare = |cents| TicketFacts { price_cents: Some(cents), ..Default::default() };
        let p = eval("einzel_db", fare(3990), &[(d(2026, 9, 3), 125)], today());
        assert_eq!(p.amount, 1995);
        assert!(p.payable);

        // A Super Sparpreis: 3,25 € is under the minimum.
        let p = eval("einzel_db", fare(1299), &[(d(2026, 9, 3), 75)], today());
        assert_eq!(p.amount, 325);
        assert!(matches!(p.blockers[..], [Blocker::BelowMinimum { missing_cents: 75, missing_minutes: None }]));

        // Deutschlandtarif: up to 5 cents.
        assert_eq!(eval("einzel_nah", fare(1730), &[(d(2026, 9, 3), 62)], today()).amount, 435);

        // FlixTrain pays only what is higher than 4 €, DB from 4 € on.
        let p = eval("einzel_flixtrain", fare(1600), &[(d(2026, 9, 3), 60)], today());
        assert_eq!(p.amount, 400);
        assert!(!p.payable);
        assert!(eval("einzel_db", fare(1600), &[(d(2026, 9, 3), 60)], today()).payable);
    }

    #[test]
    fn a_single_ticket_without_a_price_has_no_amount() {
        let p = eval("einzel_db", TicketFacts::default(), &[(d(2026, 9, 3), 90)], today());
        assert_eq!(p.amount, 0);
        assert_eq!(p.blockers, vec![Blocker::PriceMissing]);
    }

    #[test]
    fn laender_ticket_pools_one_day_and_waits_for_it_to_end() {
        let t = TicketFacts { price_cents: Some(2700), ..Default::default() };
        let p = eval("laender_ticket", t.clone(), &[(d(2026, 10, 5), 90), (d(2026, 10, 5), 90)], today());
        assert_eq!(p.amount, 450);
        assert_eq!(p.blockers, vec![Blocker::WindowOpen { until: d(2026, 10, 6) }]);
        assert!(eval("laender_ticket", t, &[(d(2026, 10, 5), 90), (d(2026, 10, 5), 90)], d(2026, 10, 6)).payable);
    }

    // ── Deadlines ──────────────────────────────────────────────────────────────────────────────

    #[test]
    fn twelve_months_hard_three_to_aim_for() {
        let p = eval("deutschlandticket", TicketFacts::default(), &[(d(2026, 9, 9), 70), (d(2026, 9, 20), 70), (d(2026, 9, 21), 70)], today());
        assert_eq!(p.deadline, Some(d(2027, 9, 9)));
        assert_eq!(p.aim, Some(d(2026, 12, 9)));
    }

    #[test]
    fn expired_cases_count_nowhere() {
        let p = eval("deutschlandticket", TicketFacts::default(), &[(d(2025, 9, 1), 200), (d(2026, 9, 1), 70)], today());
        assert_eq!(p.cases[0].excluded, Some(Excluded::Expired));
        assert_eq!((p.minutes, p.amount), (70, 150));
    }

    #[test]
    fn mvv_counts_three_months_from_the_end_of_the_ticket() {
        let month = TicketFacts { valid_from: Some(d(2026, 6, 1)), valid_until: Some(d(2026, 6, 30)), ..Default::default() };
        let p = eval("zeitkarte_mvv", month, &[(d(2026, 6, 3), 70), (d(2026, 6, 4), 70), (d(2026, 6, 5), 70)], d(2026, 9, 29));
        assert_eq!(p.deadline, Some(d(2026, 9, 30)));
        assert!(p.payable);
    }
}
