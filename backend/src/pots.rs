//! Pots (docs/49 §5.5, docs/50 phase 2, #66): a passenger's open cases, grouped by the ticket they
//! were made with, the window that ticket's rule sums over and the desk that answers them, and
//! evaluated with [`crate::fares::evaluate`]. A pot is what a claim becomes; a claim is a pot as it
//! was when it left the house.
//!
//! The grouping and evaluation are pure ([`evaluate_all`]); the functions around them read the
//! tickets and write what changed.

use std::collections::{BTreeMap, HashMap};

use chrono::{Datelike, NaiveDate};
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

use crate::db::rows::*;
use crate::fares::evaluate::{evaluate, Blocker, CaseFacts, Pot, TicketFacts};
use crate::fares::{Product, Rule, Window};
use crate::tickets;

/// A case belongs in a pot while it can still be claimed: collected, ready, or over a cap (which
/// an earlier case dropping out can lift again).
pub fn in_pot(i: &IncidentRow) -> bool {
    i.discarded_at.is_none() && matches!(i.status, IncidentStatus::Gesammelt | IncidentStatus::Bereit | IncidentStatus::Gedeckelt)
}

/// A case that has gone out and counts against its ticket's caps.
fn claimed(i: &IncidentRow) -> bool {
    i.discarded_at.is_none() && matches!(i.status, IncidentStatus::Eingereicht | IncidentStatus::Bestaetigt)
}

/// The window a case falls in under its ticket's rule.
pub fn window_key(rule: &Rule, ride_date: NaiveDate) -> String {
    match rule.window {
        Window::Ticket => "ticket".into(),
        Window::Subscription => "abo".into(),
        Window::Validity => "validity".into(),
        Window::Semester => "semester".into(),
        Window::CalendarMonth => format!("{}-{:02}", ride_date.year(), ride_date.month()),
        Window::ValidityDay => ride_date.to_string(),
    }
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct PotKey {
    pub ticket_id: Uuid,
    pub window_key: String,
    pub desk: String,
}

impl PotKey {
    /// The pot's id on the wire: `<ticket>|<window>|<desk>`.
    pub fn id(&self) -> String {
        format!("{}|{}|{}", self.ticket_id, self.window_key, self.desk)
    }

    pub fn parse(s: &str) -> Option<PotKey> {
        let mut it = s.splitn(3, '|');
        let ticket_id = it.next()?.parse().ok()?;
        let window_key = it.next()?.to_string();
        let desk = it.next()?.to_string();
        Some(PotKey { ticket_id, window_key, desk })
    }
}

/// One evaluated pot.
#[derive(Debug, Clone)]
pub struct LivePot {
    pub key: PotKey,
    pub ticket: TicketRow,
    pub product: &'static Product,
    pub pot: Pot,
    /// Oldest ride first.
    pub incident_ids: Vec<Uuid>,
    pub oldest: NaiveDate,
}

pub fn ticket_facts(t: &TicketRow, claimed_before: Vec<(NaiveDate, i64)>) -> TicketFacts {
    TicketFacts { first_class: t.first_class, price_cents: t.price_cents, valid_from: t.valid_from, valid_until: t.valid_until, claimed_before }
}

pub fn case_facts(i: &IncidentRow) -> CaseFacts {
    CaseFacts { id: i.id, ride_date: i.ride_date, delay_min: i.delay_min as i64 }
}

/// Every pot among `rows` whose ticket is in `tickets`. Cases without a ticket (none after
/// migration 0046) are left alone.
pub fn evaluate_all(rows: &[IncidentRow], tickets: &HashMap<Uuid, TicketRow>, today: NaiveDate) -> Vec<LivePot> {
    let mut groups: BTreeMap<PotKey, Vec<&IncidentRow>> = BTreeMap::new();
    for i in rows.iter().filter(|i| in_pot(i)) {
        let Some(t) = i.ticket_id.and_then(|id| tickets.get(&id)) else { continue };
        let rule = tickets::product_of(t).rule_on(i.ride_date);
        let key = PotKey { ticket_id: t.id, window_key: window_key(rule, i.ride_date), desk: i.desk.clone() };
        groups.entry(key).or_default().push(i);
    }
    groups
        .into_iter()
        .map(|(key, mut cases)| {
            cases.sort_by_key(|i| (i.ride_date, i.created_at));
            let ticket = tickets[&key.ticket_id].clone();
            let before: Vec<(NaiveDate, i64)> = rows.iter().filter(|i| claimed(i) && i.ticket_id == Some(ticket.id)).map(|i| (i.ride_date, i.confirmed_cents.unwrap_or(i.amount_cents))).collect();
            let product = tickets::product_of(&ticket);
            let facts: Vec<CaseFacts> = cases.iter().map(|i| case_facts(i)).collect();
            let pot = evaluate(product, &ticket_facts(&ticket, before), &facts, today);
            LivePot { oldest: cases[0].ride_date, incident_ids: cases.iter().map(|i| i.id).collect(), key, ticket, product, pot }
        })
        .collect()
}

pub async fn customer_tickets(pool: &PgPool, customer: Uuid) -> anyhow::Result<HashMap<Uuid, TicketRow>> {
    let rows: Vec<TicketRow> = sqlx::query_as("select * from tickets where customer_id = $1").bind(customer).fetch_all(pool).await?;
    Ok(rows.into_iter().map(|t| (t.id, t)).collect())
}

/// What a case's status should be, given its share of its pot.
pub fn status_for(pot: &Pot, id: Uuid) -> IncidentStatus {
    let share = pot.cases.iter().find(|c| c.id == id);
    match share {
        Some(s) if s.capped && s.cents == 0 => IncidentStatus::Gedeckelt,
        _ if pot.payable => IncidentStatus::Bereit,
        _ => IncidentStatus::Gesammelt,
    }
}

/// The pot as the app reads it (`summary.pots`).
pub fn pot_json(p: &LivePot) -> Value {
    json!({
        "id": p.key.id(),
        "ticket_id": p.ticket.id,
        "ticket_name": tickets::ticket_json(&p.ticket)["name"],
        "product": p.product.id,
        "family": p.product.family,
        "window_key": p.key.window_key,
        "desk": p.key.desk,
        "minutes": p.pot.minutes,
        "next_unit_minutes": p.pot.next_unit_minutes,
        "amount_cents": p.pot.amount,
        "gross_cents": p.pot.gross,
        "capped": p.pot.capped,
        "payable": p.pot.payable,
        "blockers": p.pot.blockers,
        "ready_from": p.pot.ready_from,
        "aim": p.pot.aim,
        "deadline": p.pot.deadline,
        "incident_ids": p.incident_ids,
    })
}

/// The sentence a pot that cannot go out yet is refused with. `desk`-based requests from builds
/// before pots get the words they know for the 4 € floor.
pub fn refusal(pot: &Pot) -> String {
    match pot.blockers.first() {
        Some(Blocker::BelowMinimum { .. }) | None => "bundle below the 4 € minimum; keep collecting".into(),
        Some(Blocker::TooFewCases { missing }) => format!("too few cases: {missing} more needed"),
        Some(Blocker::WindowOpen { until }) => format!("the ticket's period is still running; ready from {until}"),
        Some(Blocker::PriceMissing) => "the fare is missing; enter what the ticket cost".into(),
        Some(Blocker::NotMoney) => "this ticket is compensated in points, not money".into(),
        Some(Blocker::Empty) => "no case in this pot counts".into(),
    }
}

/// What a ticket has already claimed, by ride date: sent cases use up its caps.
pub async fn claimed_before(pool: &PgPool, t: &TicketRow) -> anyhow::Result<Vec<(NaiveDate, i64)>> {
    Ok(sqlx::query_as(
        "select ride_date, coalesce(confirmed_cents, amount_cents) from incidents
          where ticket_id = $1 and discarded_at is null and status in ('eingereicht', 'bestaetigt')",
    )
    .bind(t.id)
    .fetch_all(pool)
    .await?)
}

/// What the caps took from the open pots: gross minus what is left. Was the sum of the capped
/// cases' amounts before pots, which is the same money.
pub fn capped_cents(pots: &[LivePot]) -> i64 {
    pots.iter().map(|p| p.pot.gross - p.pot.amount).sum()
}

/// A draft claim after some of its cases left it (a discard, a deleted ride, a changed ticket):
/// re-evaluated on what is left. Dropped when that no longer can go out, else reduced to its new
/// amount. Returns whether the draft was deleted.
pub async fn shrink_draft(pool: &PgPool, claim: &ClaimRow, reason: &str, today: NaiveDate) -> anyhow::Result<bool> {
    let rest: Vec<IncidentRow> = sqlx::query_as("select i.* from incidents i join claim_incidents ci on ci.incident_id = i.id where ci.claim_id = $1").bind(claim.id).fetch_all(pool).await?;
    let tickets = customer_tickets(pool, claim.customer_id).await?;
    let pot = match rest.first().and_then(|i| i.ticket_id).and_then(|id| tickets.get(&id)) {
        Some(t) => {
            let facts: Vec<CaseFacts> = rest.iter().map(case_facts).collect();
            Some(evaluate(tickets::product_of(t), &ticket_facts(t, claimed_before(pool, t).await?), &facts, today))
        }
        None => None,
    };
    match pot {
        Some(p) if p.payable => {
            sqlx::query("update claims set amount_claimed_cents = $2, breakdown = $3 where id = $1").bind(claim.id).bind(p.amount).bind(json!(p)).execute(pool).await?;
            Ok(false)
        }
        _ => {
            sqlx::query("delete from claim_attachments where claim_id = $1").bind(claim.id).execute(pool).await?;
            sqlx::query("delete from claim_incidents where claim_id = $1").bind(claim.id).execute(pool).await?;
            sqlx::query("update incidents set claim_id = null where claim_id = $1").bind(claim.id).execute(pool).await?;
            sqlx::query("delete from claims where id = $1").bind(claim.id).execute(pool).await?;
            crate::rules::audit(pool, "claim", claim.id, Some("draft"), "deleted", reason).await?;
            Ok(true)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;

    fn d(m: u32, day: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(2026, m, day).unwrap()
    }

    fn ticket(product: &str) -> TicketRow {
        TicketRow {
            id: Uuid::new_v4(), customer_id: Uuid::nil(), product: product.into(), product_unsure: false, first_class: false, label: None, number: None,
            booking_ref: None, birth_date: None, price_cents: None, valid_from: None, valid_until: None, origin_station_id: None, origin_station_name: None,
            destination_station_id: None, destination_station_name: None, created_at: Utc::now(), archived_at: None,
        }
    }

    fn case(t: &TicketRow, date: NaiveDate, delay: i32, desk: &str) -> IncidentRow {
        IncidentRow {
            id: Uuid::new_v4(), customer_id: Uuid::nil(), ride_id: None, ride_date: date, line: "RE 1".into(), from_name: "A".into(), to_name: "B".into(),
            delay_min: delay, amount_cents: 0, ticket: tickets::legacy_type(&t.product), operator: "DB Regio".into(), desk: desk.into(),
            status: IncidentStatus::Gesammelt, cancelled: false, self_entered: false, ngo_id: "x".into(), claim_id: None, fare_cents: None,
            legal_deadline: date + chrono::Months::new(12), evidence: None, created_at: Utc::now(), journey_id: None, discarded_at: None,
            discard_reason: None, confirmed_cents: None, ticket_id: Some(t.id), first_class: Some(false), window_key: None,
        }
    }

    #[test]
    fn cases_pool_by_ticket_window_and_desk() {
        let dt = ticket("deutschlandticket");
        let bc = ticket("bahncard100");
        let rows = vec![
            case(&dt, d(8, 31), 40, "SC"),
            case(&dt, d(9, 1), 40, "SC"),
            case(&dt, d(9, 2), 100, "SC"),
            case(&dt, d(9, 3), 70, "NordWestBahn"),
            case(&bc, d(9, 4), 65, "SC"),
        ];
        let tickets: HashMap<Uuid, TicketRow> = [(dt.id, dt.clone()), (bc.id, bc.clone())].into_iter().collect();
        let pots = evaluate_all(&rows, &tickets, d(10, 5));
        assert_eq!(pots.len(), 3, "the D-Ticket at two desks, and the BahnCard");
        let dt_sc = pots.iter().find(|p| p.key.ticket_id == dt.id && p.key.desk == "SC").unwrap();
        assert_eq!(dt_sc.key.window_key, "abo", "across the month boundary");
        assert_eq!((dt_sc.pot.minutes, dt_sc.pot.amount, dt_sc.pot.payable), (180, 450, true));
        assert_eq!(dt_sc.oldest, d(8, 31));
        let bcp = pots.iter().find(|p| p.key.ticket_id == bc.id).unwrap();
        assert_eq!(bcp.pot.amount, 1000);
        assert!(bcp.pot.payable);
        let nwb = pots.iter().find(|p| p.key.desk == "NordWestBahn").unwrap();
        assert!(!nwb.pot.payable, "70 minutes at another desk: 1,50 €, not yet");
    }

    #[test]
    fn a_sent_claim_uses_up_the_cap_of_its_month() {
        let dt = ticket("deutschlandticket");
        let mut rows: Vec<IncidentRow> = (1..=8).map(|day| case(&dt, d(9, day), 60, "SC")).collect();
        for r in rows.iter_mut().take(8) {
            r.status = IncidentStatus::Eingereicht;
            r.amount_cents = 150;
        }
        rows.extend((10..=14).map(|day| case(&dt, d(9, day), 60, "SC")));
        let tickets: HashMap<Uuid, TicketRow> = [(dt.id, dt.clone())].into_iter().collect();
        let pots = evaluate_all(&rows, &tickets, d(10, 5));
        assert_eq!(pots.len(), 1);
        assert_eq!(pots[0].pot.amount, 1575 - 1200, "12 € of September's 15,75 € went out already");
        let capped = pots[0].pot.cases.iter().filter(|c| status_for(&pots[0].pot, c.id) == IncidentStatus::Gedeckelt).count();
        assert_eq!(capped, 2, "two of the five get nothing");
    }

    #[test]
    fn pot_ids_round_trip() {
        let k = PotKey { ticket_id: Uuid::new_v4(), window_key: "2026-09".into(), desk: "Servicecenter Fahrgastrechte".into() };
        assert_eq!(PotKey::parse(&k.id()), Some(k));
        assert_eq!(PotKey::parse("nonsense"), None);
    }
}
