//! Reading a railway's answer, and deciding what it does to the claim.
//!
//! Two readers exist. The rules in `classify.rs` read every mail, always. A model (`openai.rs`)
//! reads it too when one is configured, because a desk's German is more varied than any list of
//! phrases, and a partial award — one ride paid, one refused — is a sentence a keyword list cannot
//! take apart.
//!
//! **The model proposes; this file decides.** Its answer is a claim about the mail, and money moves
//! only if the mail itself backs the claim up ([`gate_model`]):
//!
//! - the sentence it quotes as evidence is really in the text it was shown;
//! - every amount it names is written in that text as money (`classify::money_figures`), so it
//!   cannot take a figure from the fare, from the ride list or from nowhere;
//! - the per-ride amounts add up to the total it names, and no ride gets more than we claimed for
//!   it — the one misreading that would inflate a public total;
//! - it does not flatly contradict the rules (paid where they read a refusal, and back).
//!
//! Every failed check ends as [`MailOutcome::Other`] — "a human should read this" — never as a
//! guess. When the model cannot be asked (no key, timeout, an error), the rules decide alone, as
//! they did before the model existed.
//!
//! Either way the result is per ride: which rides are confirmed, at what figure, and which are
//! refused. A confirmed ride carries the figure the desk wrote (`incidents.confirmed_cents`), so a
//! Verein's total counts what was paid rather than what was asked for.

use serde::Serialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::classify;
use crate::db::rows::{ClaimRow, CustomerRow, IncidentRow, MailOutcome};
use crate::openai::{self, Outcome, RideCall};
use crate::redact::{self, Known};

/// One ride of the claim being answered, in the order the model sees them.
#[derive(Debug, Clone)]
pub struct Claimed {
    pub incident_id: Uuid,
    pub reference: String,
    pub claimed_cents: i64,
}

/// A claim's rides as the gate needs them and as the model is shown them, in one order.
pub fn rides_of(incidents: &[IncidentRow]) -> (Vec<Claimed>, Vec<openai::Ride>) {
    incidents
        .iter()
        .enumerate()
        .map(|(n, i)| {
            let reference = format!("F{}", n + 1);
            (
                Claimed { incident_id: i.id, reference: reference.clone(), claimed_cents: i.amount_cents },
                openai::Ride { reference, date: i.ride_date, line: i.line.clone(), from: i.from_name.clone(), to: i.to_name.clone(), delay_min: i.delay_min },
            )
        })
        .unzip()
}

/// Everything we hold that identifies the passenger a mail is about, for `redact.rs` to take out.
pub fn known_of(cust: &CustomerRow, claim: Option<&ClaimRow>, relay: Option<&str>) -> Known {
    Known {
        name: cust.full_name.clone(),
        postal_address: cust.postal_address.clone(),
        email: cust.email.clone(),
        ticket_number: cust.ticket_number.clone(),
        addresses: [relay.map(str::to_string), cust.relay_address.clone(), claim.and_then(|c| c.reply_address.clone())].into_iter().flatten().collect(),
        sent: vec![],
        payee: claim.map(|c| c.account_holder.clone()),
    }
}

/// What happens to one ride.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(tag = "decision", rename_all = "snake_case")]
pub enum RideOutcome {
    Paid { cents: i64 },
    Refused,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct RideVerdict {
    pub incident_id: Uuid,
    #[serde(flatten)]
    pub outcome: RideOutcome,
}

/// The decision a reader's answer survived into.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Verdict {
    pub outcome: MailOutcome,
    /// One per claimed ride for `Accepted` and `Rejected`; empty otherwise.
    pub rides: Vec<RideVerdict>,
    /// The sum confirmed, for `Accepted`.
    pub amount_cents: Option<i64>,
    pub because: String,
}

impl Verdict {
    pub fn other(because: impl Into<String>) -> Self {
        Self { outcome: MailOutcome::Other, rides: vec![], amount_cents: None, because: because.into() }
    }
    fn plain(outcome: MailOutcome, because: impl Into<String>) -> Self {
        Self { outcome, rides: vec![], amount_cents: None, because: because.into() }
    }
    fn refused(claimed: &[Claimed], because: impl Into<String>) -> Self {
        Self {
            outcome: MailOutcome::Rejected,
            rides: claimed.iter().map(|c| RideVerdict { incident_id: c.incident_id, outcome: RideOutcome::Refused }).collect(),
            amount_cents: None,
            because: because.into(),
        }
    }
}

/// A reading, with who made it and what they saw.
#[derive(Debug, Clone)]
pub struct Decision {
    pub verdict: Verdict,
    /// `rules` or `model:<snapshot>`.
    pub read_by: String,
    /// Stored with the mail: the verdict, and for a model the text it was shown and its raw answer.
    pub trace: Value,
}

/// The rules' reading, turned into rides.
///
/// A payment names one figure. With one ride, that ride gets it, if it is not more than we claimed.
/// With several, the figure has to be exactly what we claimed for all of them — anything else is a
/// partial award or a different calculation, and splitting it across rides would be inventing.
pub fn gate_rules(r: &classify::Reading, claimed: &[Claimed]) -> Verdict {
    // A stop or a condition found anywhere the desk wrote holds, even where the rules' own outcome
    // was read from less of the mail.
    if matches!(r.outcome, MailOutcome::Accepted | MailOutcome::Rejected) {
        if let Some(why) = r.stop {
            return Verdict::other(format!("not a decision about this claim's money: {why}"));
        }
    }
    if r.outcome == MailOutcome::Accepted && r.conditional_payment {
        return Verdict::other("the payment is conditional or hypothetical");
    }
    if r.outcome == MailOutcome::Accepted && r.refusal_elsewhere && claimed.len() > 1 {
        return Verdict::other("every ride paid, but a refusal stands in a part of the mail the reader did not read");
    }
    match r.outcome {
        MailOutcome::Rejected => Verdict::refused(claimed, r.because),
        MailOutcome::Accepted => {
            let Some(amount) = r.amount_cents else { return Verdict::other("sounds paid but names no amount") };
            let asked: i64 = claimed.iter().map(|c| c.claimed_cents).sum();
            let rides = match claimed {
                // A payment with no ride under it confirms nothing: it would still read as
                // "accepted" on the mail and in the push, with a figure nobody can check.
                [] => return Verdict::other("no claimed rides to confirm"),
                [one] if amount <= one.claimed_cents => vec![RideVerdict { incident_id: one.incident_id, outcome: RideOutcome::Paid { cents: amount } }],
                [_] => return Verdict::other("names more than was claimed"),
                many if amount == asked => many.iter().map(|c| RideVerdict { incident_id: c.incident_id, outcome: RideOutcome::Paid { cents: c.claimed_cents } }).collect(),
                _ => return Verdict::other("names an amount that does not match the claimed rides"),
            };
            Verdict { outcome: MailOutcome::Accepted, rides, amount_cents: Some(amount), because: r.because.into() }
        }
        outcome => Verdict::plain(outcome, r.because),
    }
}

/// True if `sender` (a bare, lower-cased address) writes from one of `domains` or a subdomain of one.
pub fn sender_matches(sender: &str, domains: &[String]) -> bool {
    // One plain address or nothing: "x@gmail.com <antwort@desk" without its closing bracket would
    // otherwise be judged by whatever follows its last "@".
    if sender.matches('@').count() != 1 || sender.chars().any(|c| c.is_whitespace() || c == '<' || c == '>' || c == ',' || c == ';') {
        return false;
    }
    let Some((_, domain)) = sender.rsplit_once('@') else { return false };
    let domain = domain.trim().to_lowercase();
    domains.iter().any(|d| domain == *d || domain.ends_with(&format!(".{d}")))
}

/// Collapse whitespace and drop quotation marks and case, so a quote the model re-wrapped still
/// matches while a quote it rephrased does not.
fn normalise(s: &str) -> String {
    s.chars()
        .filter(|c| !matches!(c, '"' | '\'' | '„' | '“' | '”' | '‚' | '‘' | '’' | '«' | '»'))
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}

/// The body of what the model was shown, without the "Betreff:" line: evidence has to come from
/// what the desk wrote, not from a subject line that repeats our own claim.
fn shown_body(shown: &str) -> &str {
    shown.split_once("\n\n").map_or(shown, |(_, body)| body)
}

/// The model's reading, checked against the text it was shown. See the module comment.
pub fn gate_model(m: &openai::Reading, shown: &str, claimed: &[Claimed], rules: &classify::Reading) -> Verdict {
    let decisive = matches!(m.outcome, Outcome::Paid | Outcome::PartlyPaid | Outcome::Refused | Outcome::Question);
    if decisive {
        let evidence = normalise(&m.evidence);
        if evidence.chars().count() < 8 || !normalise(shown_body(shown)).contains(&evidence) {
            // A question moves no money; when the rules read the same question, the model's missing
            // quote is no reason to lose it.
            if m.outcome == Outcome::Question && rules.outcome == MailOutcome::Question {
                return Verdict::plain(MailOutcome::Question, "asks for something (the rules; the model gave no quote)");
            }
            return Verdict::other("the model's evidence is not in the mail");
        }
    }
    match m.outcome {
        Outcome::Automatic => Verdict::other(format!("automatic or interim reply: {}", m.reason)),
        Outcome::Other => Verdict::other(format!("model found no decision: {}", m.reason)),
        Outcome::Question => Verdict::plain(MailOutcome::Question, format!("asks for something: {}", m.reason)),
        Outcome::Refused => {
            if let Some(why) = rules.stop {
                return Verdict::other(format!("not a refusal of this claim: {why}"));
            }
            if rules.outcome == MailOutcome::Accepted {
                return Verdict::other("the model reads a refusal, the rules read a payment");
            }
            if !rides_match(m, claimed) || m.rides.iter().any(|r| r.decision != RideCall::Refused) {
                return Verdict::other("a refusal that does not cover every ride");
            }
            Verdict::refused(claimed, format!("refused: {}", m.reason))
        }
        Outcome::Paid | Outcome::PartlyPaid => paid(m, shown, claimed, rules),
    }
}

fn rides_match(m: &openai::Reading, claimed: &[Claimed]) -> bool {
    m.rides.len() == claimed.len() && m.rides.iter().zip(claimed).all(|(r, c)| r.reference == c.reference)
}

fn paid(m: &openai::Reading, shown: &str, claimed: &[Claimed], rules: &classify::Reading) -> Verdict {
    let partial = m.outcome == Outcome::PartlyPaid;
    // A mail cut off at the length limit may lose the condition that follows the payment
    // ("…überweisen wir 1,50 EUR, sobald Sie uns eine Kopie senden").
    if shown.ends_with(redact::CUT) {
        return Verdict::other("the mail was cut off before the end");
    }
    if let Some(why) = rules.stop {
        return Verdict::other(format!("not a payment for this claim: {why}"));
    }
    if rules.outcome == MailOutcome::Rejected {
        return Verdict::other("the model reads a payment, the rules read a refusal");
    }
    if rules.refusal_elsewhere && !partial {
        return Verdict::other("every ride paid, but a refusal stands in a part of the mail the model did not read");
    }
    // The rules read the raw text; redaction or the model can lose the "sofern" in front.
    if rules.conditional_payment {
        return Verdict::other("the payment is conditional or hypothetical");
    }
    // The rules saw a payment and a refusal. That is a partial award at best, and on one ride it is
    // also a refusal with a goodwill payment ("kein Anspruch … aus Kulanz überweisen wir"), which is
    // money. Several rides all paid against it is not believable.
    if rules.because == "says both paid and refused" && !partial && claimed.len() > 1 {
        return Verdict::other("the model reads every ride paid, the rules read a refusal as well");
    }
    if classify::conditional(&m.evidence) {
        return Verdict::other("the payment is conditional or hypothetical");
    }
    if !rides_match(m, claimed) {
        return Verdict::other("the model's rides do not match the claim");
    }
    if let Some(r) = m.rides.iter().find(|r| r.decision == RideCall::Unclear) {
        return Verdict::other(format!("unclear what happens to {}", r.reference));
    }
    let paid: Vec<usize> = m.rides.iter().enumerate().filter(|(_, r)| r.decision == RideCall::Paid).map(|(n, _)| n).collect();
    if paid.is_empty() {
        return Verdict::other("a payment with no paid ride");
    }
    // "paid" that refuses a ride, or "partly paid" that pays them all, contradicts itself.
    if partial == (paid.len() == claimed.len()) {
        return Verdict::other("the outcome and the rides disagree");
    }

    // Every figure has to stand in the evidence — the passage that carries the decision — not just
    // somewhere in the mail, where the claimed amount or the fare is usually written too. And each
    // place a figure is written can back one amount only: "1,50 EUR" written once does not pay
    // three rides.
    let figures = classify::money_figures(&m.evidence);
    let mut unused = figures.clone();
    let mut take = |cents: i64| match unused.iter().position(|&c| c == cents) {
        Some(at) => {
            unused.remove(at);
            true
        }
        None => false,
    };
    let asked: i64 = claimed.iter().map(|c| c.claimed_cents).sum();
    let mut amounts: Vec<Option<i64>> = vec![None; claimed.len()];
    let mut unbacked: Option<String> = None;
    // A model that writes the one total as every ride's amount ("3,00 EUR" for F1 and for F2) means
    // the total, not twice the money: read the rides as unnamed and let the total split them.
    // Written as often as there are rides, the same figure is each ride's own ("1,50 EUR … 1,50 EUR")
    // and the model copied one of them into the total instead.
    let total_cents = m.total_amount.as_deref().and_then(classify::parse_amount);
    let written_times = figures.iter().filter(|&&c| Some(c) == total_cents).count();
    let total_as_every_ride = paid.len() > 1
        && !partial
        && total_cents.is_some()
        && written_times < paid.len()
        && paid.iter().all(|&n| m.rides[n].amount.as_deref().and_then(classify::parse_amount) == total_cents);
    for &n in paid.iter().filter(|_| !total_as_every_ride) {
        if let Some(s) = &m.rides[n].amount {
            match classify::parse_amount(s) {
                Some(c) if take(c) => amounts[n] = Some(c),
                _ => {
                    unbacked = Some(format!("the amount {s} for {} is not written as money where the mail decides", claimed[n].reference));
                    break;
                }
            }
        }
    }
    let named = paid.iter().filter(|&&n| amounts[n].is_some()).count();
    let sum_named: i64 = paid.iter().filter_map(|&n| amounts[n]).sum();
    let all_named = unbacked.is_none() && named == paid.len();
    let total = match &m.total_amount {
        None => None,
        Some(s) => match classify::parse_amount(s) {
            // The rides' own figures add up to it: nothing more to find.
            Some(c) if all_named && c == sum_named => Some(c),
            // Written in a place of its own ("insgesamt 3,00 EUR").
            Some(c) if take(c) => Some(c),
            // One paid ride: its figure is the total.
            Some(c) if paid.len() == 1 && figures.contains(&c) => Some(c),
            // Every paid ride is backed by its own figure and this "total" is not written anywhere
            // of its own — a model copying one ride's amount. The rides stand without it.
            Some(_) if all_named && paid.len() > 1 => None,
            _ => return Verdict::other(format!("the total {s} is not written as money where the mail decides")),
        },
    };
    if let Some(why) = unbacked {
        // "je 1,50 EUR, insgesamt 3,00 EUR": one figure for several rides, and a written total that
        // is exactly the claim. Each ride gets what was claimed for it.
        if !partial && paid.len() == claimed.len() && total == Some(asked) {
            for n in &paid {
                amounts[*n] = Some(claimed[*n].claimed_cents);
            }
        } else {
            return Verdict::other(why);
        }
    } else if named < paid.len() {
        if paid.len() == 1 && total.is_some() {
            amounts[paid[0]] = total;
        } else if named == 0 && !partial && total == Some(asked) {
            for n in &paid {
                amounts[*n] = Some(claimed[*n].claimed_cents);
            }
        } else {
            return Verdict::other("cannot tell how much each ride was paid");
        }
    }
    let sum: i64 = paid.iter().filter_map(|&n| amounts[n]).sum();
    if total.is_some_and(|t| t != sum) {
        return Verdict::other("the ride amounts do not add up to the total");
    }
    if sum <= 0 {
        return Verdict::other("a payment of nothing");
    }
    if let Some(&n) = paid.iter().find(|&&n| amounts[n].unwrap_or(0) > claimed[n].claimed_cents) {
        return Verdict::other(format!("names more for {} than was claimed", claimed[n].reference));
    }
    let rides = claimed
        .iter()
        .enumerate()
        .map(|(n, c)| RideVerdict { incident_id: c.incident_id, outcome: match amounts[n] { Some(cents) if paid.contains(&n) => RideOutcome::Paid { cents }, _ => RideOutcome::Refused } })
        .collect();
    Verdict { outcome: MailOutcome::Accepted, rides, amount_cents: Some(sum), because: format!("{}: {}", if partial { "partly paid" } else { "paid" }, m.reason) }
}

/// What asking the model came to.
// One of these exists per mail, briefly; boxing the readings would buy nothing.
#[allow(clippy::large_enum_variant)]
#[derive(Debug, Clone)]
pub enum Asked {
    /// No key: the rules decide alone.
    NotConfigured,
    Answered {
        model: String,
        shown: String,
        answer: openai::Reading,
        /// The second reading, asked when the first would accept or refuse. None: turned off.
        confirm: Option<Result<(String, openai::Reading), (String, String)>>,
    },
    Failed { model: String, error: String },
}

/// Everything about one inbound mail that decides its verdict, without any I/O.
pub struct Mail<'a> {
    pub from: &'a str,
    pub subject: &'a str,
    pub body: &'a str,
}

/// Turn a mail, the claim and whatever the model said into a decision.
///
/// Split from [`read`] so every path — bounce, own sender, nothing above the quote, no key, model
/// failure, model answer — is testable without a network.
pub fn settle(mail: &Mail, known: &Known, claimed: &[Claimed], asked: Asked) -> Decision {
    let rules_decision = |rules: &classify::Reading, extra: Value| {
        let verdict = gate_rules(rules, claimed);
        let trace = json!({ "verdict": verdict, "extra": extra });
        Decision { verdict, read_by: "rules".into(), trace }
    };
    let fixed = |verdict: Verdict| {
        let trace = json!({ "verdict": verdict });
        Decision { verdict, read_by: "rules".into(), trace }
    };

    // A delivery failure, judged on the whole mail: its body is somebody else's.
    let whole = classify::read(mail.from, mail.subject, mail.body);
    if whole.outcome == MailOutcome::Bounce {
        return rules_decision(&whole, Value::Null);
    }
    // The passenger's own mail is never the desk's answer, whatever it quotes. A reply-all from
    // their inbox carries the desk's words ("wir überweisen 1,50 EUR") and would otherwise confirm
    // money on the passenger's own say-so.
    let sender = crate::handlers::inbound_address(mail.from);
    if known.email.iter().chain(&known.addresses).any(|a| a.trim().eq_ignore_ascii_case(&sender)) {
        return fixed(Verdict::other("sent from the passenger's own address"));
    }
    // Our own words out first: the claim and the passenger's replies, however the desk's system
    // echoes them, are not the desk's decision.
    let body = redact::without_ours(mail.body, &known.sent);
    // Everything else reads only what the sender wrote now. A desk that answers below the quoted
    // claim leaves nothing above it; reading the quote instead would read our own words.
    let latest = redact::latest(&body);
    if latest.trim().is_empty() {
        return fixed(Verdict::other("nothing above the quoted text; the answer may be below it"));
    }
    let mut rules = classify::read(mail.from, mail.subject, &latest);
    // Vetoes read everything the desk wrote, including what the reader leaves out (an echo block, and
    // anything that looked like our own words): a stop, a condition or a refusal there still means
    // money must not move. Reading more can only block money, never move it.
    let unquoted = redact::unquoted(mail.body);
    let everything = classify::read(mail.from, mail.subject, &unquoted);
    rules.stop = rules.stop.or(everything.stop);
    if redact::names_passenger_as_payee(&unquoted, known) {
        rules.stop = rules.stop.or(Some("paid to someone other than the Verein"));
    }
    rules.conditional_payment |= everything.conditional_payment;
    let refuses = |r: &classify::Reading| r.outcome == MailOutcome::Rejected || r.because == "says both paid and refused";
    rules.refusal_elsewhere = refuses(&everything) && !refuses(&rules);

    match asked {
        Asked::NotConfigured => rules_decision(&rules, Value::Null),
        Asked::Failed { model, error } => {
            // The rules alone have known ways to misread a decision — a partial award read as a
            // refusal, a threshold read as a payment — so without the model they may ask or pass a
            // mail on, but neither confirm nor refuse. `stellwerk reread` reads it again later.
            let mut d = rules_decision(&rules, json!({ "model": model, "error": error }));
            if matches!(d.verdict.outcome, MailOutcome::Accepted | MailOutcome::Rejected) {
                d.verdict = Verdict::other("the model was unavailable, and the rules alone do not accept or refuse");
            }
            d.verdict.because = format!("{} (model unavailable: {error})", d.verdict.because);
            d.trace["verdict"] = json!(d.verdict);
            d
        }
        Asked::Answered { model, shown, answer, confirm } => {
            let first = gate_model(&answer, &shown, claimed, &rules);
            let mut trace = json!({ "model": model, "shown": shown, "answer": answer, "first": first, "rules": rules.because });
            let verdict = match (first.outcome, confirm) {
                (MailOutcome::Accepted | MailOutcome::Rejected, Some(Ok((second_model, second_answer)))) => {
                    let second = gate_model(&second_answer, &shown, claimed, &rules);
                    trace["confirm"] = json!({ "model": second_model, "answer": second_answer, "verdict": second });
                    // The same outcome, the same rides, the same figures — or a human reads it.
                    if second.outcome == first.outcome && second.rides == first.rides && second.amount_cents == first.amount_cents {
                        Verdict { because: format!("{}; confirmed by {second_model}", first.because), ..first }
                    } else {
                        Verdict::other(format!("the second reading ({second_model}) disagrees: {:?}, {}", second.outcome, second.because))
                    }
                }
                (MailOutcome::Accepted | MailOutcome::Rejected, Some(Err((second_model, error)))) => {
                    trace["confirm"] = json!({ "model": second_model, "error": error });
                    Verdict::other(format!("the second reading ({second_model}) was unavailable: {error}"))
                }
                _ => first,
            };
            trace["verdict"] = json!(verdict);
            Decision { verdict, read_by: format!("model:{model}"), trace }
        }
    }
}

/// Read one inbound mail for a claim.
///
/// `claimed` and `rides` are the claim's rides in the same order; both empty when the mail belongs
/// to no claim, in which case nothing can move and the model is not asked.
///
/// `use_model` is false for replies the Stellwerk plants: their text is fixed, and an end-to-end test
/// should not depend on a network and a model's mood.
pub async fn read(mail: &Mail<'_>, known: &Known, claimed: &[Claimed], rides: &[openai::Ride], use_model: bool) -> Decision {
    let cfg = openai::Config::from_env().filter(|_| use_model);
    let body = redact::without_ours(mail.body, &known.sent);
    let worth_asking = !claimed.is_empty() && !redact::latest(&body).trim().is_empty() && classify::read(mail.from, mail.subject, mail.body).outcome != MailOutcome::Bounce;
    let asked = match cfg {
        Some(cfg) if worth_asking => {
            let shown = redact::for_model(mail.subject, &body, known);
            let payee = known.payee.as_deref();
            match openai::read(&cfg, &cfg.model, "low", openai::BUDGET, &shown, rides, payee).await {
                Ok(answer) => {
                    // Would the first reading move the claim? Only then is a second one worth asking.
                    let first = settle(mail, known, claimed, Asked::Answered { model: cfg.model.clone(), shown: shown.clone(), answer: answer.clone(), confirm: None });
                    let confirm = match (&cfg.confirm_model, first.verdict.outcome) {
                        (Some(second), MailOutcome::Accepted | MailOutcome::Rejected) => Some(match openai::read(&cfg, second, "medium", openai::CONFIRM_BUDGET, &shown, rides, payee).await {
                            Ok(a) => Ok((second.clone(), a)),
                            Err(e) => Err((second.clone(), e.to_string())),
                        }),
                        _ => None,
                    };
                    Asked::Answered { model: cfg.model.clone(), shown, answer, confirm }
                }
                Err(error) => {
                    tracing::warn!(error = %error, "model reader unavailable; the rules read this mail and cannot accept or refuse");
                    Asked::Failed { model: cfg.model.clone(), error: error.to_string() }
                }
            }
        }
        _ => Asked::NotConfigured,
    };
    settle(mail, known, claimed, asked)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::openai::RideReading;

    fn claim(amounts: &[i64]) -> Vec<Claimed> {
        amounts.iter().enumerate().map(|(n, &a)| Claimed { incident_id: Uuid::from_u128(n as u128 + 1), reference: format!("F{}", n + 1), claimed_cents: a }).collect()
    }

    fn ride(n: usize, decision: RideCall, amount: Option<&str>) -> RideReading {
        RideReading { reference: format!("F{n}"), decision, amount: amount.map(Into::into) }
    }

    fn model(outcome: Outcome, total: Option<&str>, rides: Vec<RideReading>, evidence: &str) -> openai::Reading {
        openai::Reading { outcome, total_amount: total.map(Into::into), rides, evidence: evidence.into(), reason: "test".into() }
    }

    fn rules(outcome: MailOutcome) -> classify::Reading {
        classify::Reading { outcome, amount_cents: None, because: "test", conditional_payment: false, stop: None, refusal_elsewhere: false }
    }

    fn shown(body: &str) -> String {
        format!("Betreff: Ihr Antrag\n\n{body}")
    }

    const PAY_ONE: &str = "Für Ihre Fahrt am 03.09. überweisen wir Ihnen eine Entschädigung von 1,50 EUR.";

    /// One case per way the gate can end, with the reason it has to give.
    #[test]
    fn every_gate_outcome_with_its_reason() {
        struct Case {
            name: &'static str,
            body: &'static str,
            claimed: Vec<i64>,
            rules: MailOutcome,
            rules_because: &'static str,
            model: openai::Reading,
            outcome: MailOutcome,
            because: &'static str,
        }
        let paid1 = |total: Option<&str>, amount: Option<&str>, ev: &str| model(Outcome::Paid, total, vec![ride(1, RideCall::Paid, amount)], ev);
        let cases = vec![
            Case { name: "backed-up payment", body: PAY_ONE, claimed: vec![150], rules: MailOutcome::Accepted, rules_because: "x", model: paid1(Some("1,50 EUR"), None, PAY_ONE), outcome: MailOutcome::Accepted, because: "paid: test" },
            Case { name: "re-wrapped quotes", body: PAY_ONE, claimed: vec![150], rules: MailOutcome::Accepted, rules_because: "x", model: paid1(Some("1,50 EUR"), Some("1,50 EUR"), "„Für Ihre Fahrt am 03.09. überweisen wir Ihnen eine Entschädigung von 1,50 EUR.“"), outcome: MailOutcome::Accepted, because: "paid: test" },
            Case { name: "invented evidence", body: PAY_ONE, claimed: vec![150], rules: MailOutcome::Accepted, rules_because: "x", model: paid1(Some("1,50 EUR"), None, "Wir zahlen Ihnen 1,50 EUR."), outcome: MailOutcome::Other, because: "the model's evidence is not in the mail" },
            Case { name: "evidence too short", body: PAY_ONE, claimed: vec![150], rules: MailOutcome::Accepted, rules_because: "x", model: paid1(Some("1,50 EUR"), None, "1,50"), outcome: MailOutcome::Other, because: "the model's evidence is not in the mail" },
            Case { name: "evidence only in the subject", body: "Wir melden uns.", claimed: vec![150], rules: MailOutcome::Other, rules_because: "x", model: paid1(Some("1,50 EUR"), None, "Betreff: Ihr Antrag"), outcome: MailOutcome::Other, because: "the model's evidence is not in the mail" },
            Case {
                name: "claimed figure restated outside the evidence",
                body: "Beantragt wurden 4,50 EUR. Den Betrag überweisen wir Ihnen in Kürze.",
                claimed: vec![450], rules: MailOutcome::Other, rules_because: "x",
                model: paid1(Some("4,50 EUR"), None, "Den Betrag überweisen wir Ihnen in Kürze."),
                outcome: MailOutcome::Other, because: "the total 4,50 EUR is not written as money where the mail decides",
            },
            Case {
                name: "the fare is not the payment",
                body: "Ihr Deutschlandticket kostet 58,00 EUR. Wir überweisen Ihnen 58,00 EUR für die Fahrt.",
                claimed: vec![150], rules: MailOutcome::Accepted, rules_because: "x",
                model: paid1(Some("58,00 EUR"), None, "Wir überweisen Ihnen 58,00 EUR für die Fahrt."),
                outcome: MailOutcome::Other, because: "names more for F1 than was claimed",
            },
            Case {
                name: "the total written as every ride's amount",
                body: "Für beide Fahrten zahlen wir Ihnen eine Entschädigung von insgesamt 3,00 EUR.",
                claimed: vec![150, 150], rules: MailOutcome::Accepted, rules_because: "x",
                model: model(Outcome::Paid, Some("3,00 EUR"), vec![ride(1, RideCall::Paid, Some("3,00 EUR")), ride(2, RideCall::Paid, Some("3,00 EUR"))], "Für beide Fahrten zahlen wir Ihnen eine Entschädigung von insgesamt 3,00 EUR."),
                outcome: MailOutcome::Accepted, because: "paid: test",
            },

            Case { name: "rules read a refusal", body: PAY_ONE, claimed: vec![150], rules: MailOutcome::Rejected, rules_because: "refused", model: paid1(Some("1,50 EUR"), None, PAY_ONE), outcome: MailOutcome::Other, because: "the model reads a payment, the rules read a refusal" },
            Case {
                name: "conditional payment",
                body: "Sobald Sie uns eine Kopie senden, überweisen wir Ihnen 1,50 EUR.",
                claimed: vec![150], rules: MailOutcome::Other, rules_because: "x",
                model: paid1(Some("1,50 EUR"), None, "Sobald Sie uns eine Kopie senden, überweisen wir Ihnen 1,50 EUR."),
                outcome: MailOutcome::Other, because: "the payment is conditional or hypothetical",
            },
            Case {
                name: "one figure cannot pay three rides",
                body: "Für die Fahrt am 03.09. überweisen wir Ihnen 1,50 EUR.",
                claimed: vec![150, 150, 150], rules: MailOutcome::Accepted, rules_because: "x",
                model: model(Outcome::Paid, None, vec![ride(1, RideCall::Paid, Some("1,50 EUR")), ride(2, RideCall::Paid, Some("1,50 EUR")), ride(3, RideCall::Paid, Some("1,50 EUR"))], "Für die Fahrt am 03.09. überweisen wir Ihnen 1,50 EUR."),
                outcome: MailOutcome::Other, because: "the amount 1,50 EUR for F2 is not written as money where the mail decides",
            },
            Case {
                name: "three figures pay three rides",
                body: "Wir überweisen für F1 1,50 EUR, für F2 1,50 EUR und für F3 1,50 EUR.",
                claimed: vec![150, 150, 150], rules: MailOutcome::Accepted, rules_because: "x",
                model: model(Outcome::Paid, None, vec![ride(1, RideCall::Paid, Some("1,50 EUR")), ride(2, RideCall::Paid, Some("1,50 EUR")), ride(3, RideCall::Paid, Some("1,50 EUR"))], "Wir überweisen für F1 1,50 EUR, für F2 1,50 EUR und für F3 1,50 EUR."),
                outcome: MailOutcome::Accepted, because: "paid: test",
            },
            Case {
                name: "a total that is the claim pays each ride its claim",
                body: "Wir überweisen für beide Fahrten zusammen 3,00 EUR.",
                claimed: vec![150, 150], rules: MailOutcome::Accepted, rules_because: "x",
                model: model(Outcome::Paid, Some("3,00 EUR"), vec![ride(1, RideCall::Paid, None), ride(2, RideCall::Paid, None)], "Wir überweisen für beide Fahrten zusammen 3,00 EUR."),
                outcome: MailOutcome::Accepted, because: "paid: test",
            },
            Case {
                name: "a total that is not the claim cannot be split",
                body: "Wir überweisen für beide Fahrten zusammen 3,00 EUR.",
                claimed: vec![150, 250], rules: MailOutcome::Accepted, rules_because: "x",
                model: model(Outcome::Paid, Some("3,00 EUR"), vec![ride(1, RideCall::Paid, None), ride(2, RideCall::Paid, None)], "Wir überweisen für beide Fahrten zusammen 3,00 EUR."),
                outcome: MailOutcome::Other, because: "cannot tell how much each ride was paid",
            },
            Case {
                name: "ride amounts must add up",
                body: "Für F1 zahlen wir 1,50 EUR, für F2 zahlen wir 1,50 EUR, insgesamt 4,00 EUR.",
                claimed: vec![400, 400], rules: MailOutcome::Accepted, rules_because: "x",
                model: model(Outcome::Paid, Some("4,00 EUR"), vec![ride(1, RideCall::Paid, Some("1,50 EUR")), ride(2, RideCall::Paid, Some("1,50 EUR"))], "Für F1 zahlen wir 1,50 EUR, für F2 zahlen wir 1,50 EUR, insgesamt 4,00 EUR."),
                outcome: MailOutcome::Other, because: "the ride amounts do not add up to the total",
            },
            Case {
                name: "partial award",
                body: "Für die Fahrt am 03.09. überweisen wir 7,25 EUR. Für die Fahrt am 05.09. gewähren wir leider keine Entschädigung.",
                claimed: vec![800, 800], rules: MailOutcome::Other, rules_because: "says both paid and refused",
                model: model(Outcome::PartlyPaid, Some("7,25 EUR"), vec![ride(1, RideCall::Paid, None), ride(2, RideCall::Refused, None)], "Für die Fahrt am 03.09. überweisen wir 7,25 EUR. Für die Fahrt am 05.09. gewähren wir leider keine Entschädigung."),
                outcome: MailOutcome::Accepted, because: "partly paid: test",
            },
            Case {
                name: "partial award against a rules refusal",
                body: "Für die Fahrt am 03.09. wären 4,50 EUR zu zahlen gewesen; es besteht jedoch kein Anspruch.",
                claimed: vec![450, 450], rules: MailOutcome::Rejected, rules_because: "refused",
                model: model(Outcome::PartlyPaid, Some("4,50 EUR"), vec![ride(1, RideCall::Paid, None), ride(2, RideCall::Refused, None)], "Für die Fahrt am 03.09. wären 4,50 EUR zu zahlen gewesen"),
                outcome: MailOutcome::Other, because: "the model reads a payment, the rules read a refusal",
            },
            Case {
                name: "every ride paid against paid-and-refused rules",
                body: "Für die Fahrt am 01.09. überweisen wir 1,50 EUR. Für die Fahrt am 02.09. können wir nicht entsprechen.",
                claimed: vec![150, 150], rules: MailOutcome::Other, rules_because: "says both paid and refused",
                model: model(Outcome::Paid, Some("3,00 EUR"), vec![ride(1, RideCall::Paid, None), ride(2, RideCall::Paid, None)], "Für die Fahrt am 01.09. überweisen wir 1,50 EUR."),
                outcome: MailOutcome::Other, because: "the model reads every ride paid, the rules read a refusal as well",
            },
            Case {
                name: "goodwill payment on one ride",
                body: "Ein Anspruch besteht nicht. Aus Kulanz überweisen wir Ihnen 1,50 EUR.",
                claimed: vec![150], rules: MailOutcome::Other, rules_because: "says both paid and refused",
                model: paid1(Some("1,50 EUR"), None, "Aus Kulanz überweisen wir Ihnen 1,50 EUR."),
                outcome: MailOutcome::Accepted, because: "paid: test",
            },
            Case { name: "invented ride", body: PAY_ONE, claimed: vec![150], rules: MailOutcome::Accepted, rules_because: "x", model: model(Outcome::Paid, Some("1,50 EUR"), vec![ride(1, RideCall::Paid, None), ride(2, RideCall::Paid, None)], PAY_ONE), outcome: MailOutcome::Other, because: "the model's rides do not match the claim" },
            Case { name: "rides out of order", body: PAY_ONE, claimed: vec![150, 150], rules: MailOutcome::Accepted, rules_because: "x", model: model(Outcome::Paid, Some("3,00 EUR"), vec![ride(2, RideCall::Paid, None), ride(1, RideCall::Paid, None)], PAY_ONE), outcome: MailOutcome::Other, because: "the model's rides do not match the claim" },
            Case { name: "unclear ride", body: PAY_ONE, claimed: vec![150], rules: MailOutcome::Accepted, rules_because: "x", model: model(Outcome::Paid, Some("1,50 EUR"), vec![ride(1, RideCall::Unclear, None)], PAY_ONE), outcome: MailOutcome::Other, because: "unclear what happens to F1" },
            Case { name: "no paid ride", body: PAY_ONE, claimed: vec![150], rules: MailOutcome::Accepted, rules_because: "x", model: model(Outcome::Paid, Some("1,50 EUR"), vec![ride(1, RideCall::Refused, None)], PAY_ONE), outcome: MailOutcome::Other, because: "a payment with no paid ride" },
            Case { name: "partly paid that pays all", body: PAY_ONE, claimed: vec![150], rules: MailOutcome::Accepted, rules_because: "x", model: model(Outcome::PartlyPaid, Some("1,50 EUR"), vec![ride(1, RideCall::Paid, None)], PAY_ONE), outcome: MailOutcome::Other, because: "the outcome and the rides disagree" },
            Case { name: "payment of nothing", body: "Wir überweisen Ihnen 0,00 EUR.", claimed: vec![150], rules: MailOutcome::Accepted, rules_because: "x", model: paid1(Some("0,00 EUR"), None, "Wir überweisen Ihnen 0,00 EUR."), outcome: MailOutcome::Other, because: "a payment of nothing" },
            Case { name: "no amount at all", body: "Den Betrag überweisen wir Ihnen in Kürze.", claimed: vec![150, 150], rules: MailOutcome::Other, rules_because: "x", model: model(Outcome::Paid, None, vec![ride(1, RideCall::Paid, None), ride(2, RideCall::Paid, None)], "Den Betrag überweisen wir Ihnen in Kürze."), outcome: MailOutcome::Other, because: "cannot tell how much each ride was paid" },
            Case { name: "refusal", body: "Leider können wir Ihrem Antrag nicht entsprechen.", claimed: vec![150, 150], rules: MailOutcome::Rejected, rules_because: "refused", model: model(Outcome::Refused, None, vec![ride(1, RideCall::Refused, None), ride(2, RideCall::Refused, None)], "Leider können wir Ihrem Antrag nicht entsprechen."), outcome: MailOutcome::Rejected, because: "refused: test" },
            Case { name: "refusal against a rules payment", body: "Leider können wir Ihrem Antrag nicht entsprechen.", claimed: vec![150], rules: MailOutcome::Accepted, rules_because: "x", model: model(Outcome::Refused, None, vec![ride(1, RideCall::Refused, None)], "Leider können wir Ihrem Antrag nicht entsprechen."), outcome: MailOutcome::Other, because: "the model reads a refusal, the rules read a payment" },
            Case { name: "refusal that pays a ride", body: "Leider können wir Ihrem Antrag nicht entsprechen.", claimed: vec![150, 150], rules: MailOutcome::Rejected, rules_because: "refused", model: model(Outcome::Refused, None, vec![ride(1, RideCall::Refused, None), ride(2, RideCall::Paid, None)], "Leider können wir Ihrem Antrag nicht entsprechen."), outcome: MailOutcome::Other, because: "a refusal that does not cover every ride" },

            Case { name: "question", body: "Bitte senden Sie uns eine Kopie Ihres Tickets.", claimed: vec![150], rules: MailOutcome::Question, rules_because: "x", model: model(Outcome::Question, None, vec![ride(1, RideCall::Unclear, None)], "Bitte senden Sie uns eine Kopie Ihres Tickets."), outcome: MailOutcome::Question, because: "asks for something: test" },
            Case { name: "question with invented evidence", body: "Wir melden uns.", claimed: vec![150], rules: MailOutcome::Other, rules_because: "x", model: model(Outcome::Question, None, vec![], "Bitte senden Sie uns Ihr Ticket."), outcome: MailOutcome::Other, because: "the model's evidence is not in the mail" },
            Case { name: "question without a quote, read by the rules too", body: "Bitte senden Sie uns eine Kopie.", claimed: vec![150], rules: MailOutcome::Question, rules_because: "asks for something", model: model(Outcome::Question, None, vec![], ""), outcome: MailOutcome::Question, because: "asks for something (the rules; the model gave no quote)" },
            Case {
                name: "je and insgesamt equal to the claim",
                body: "Wir gewähren eine Entschädigung von je 1,50 EUR, insgesamt also 3,00 EUR.",
                claimed: vec![150, 150], rules: MailOutcome::Accepted, rules_because: "x",
                model: model(Outcome::Paid, Some("3,00 EUR"), vec![ride(1, RideCall::Paid, Some("1,50 EUR")), ride(2, RideCall::Paid, Some("1,50 EUR"))], "Wir gewähren eine Entschädigung von je 1,50 EUR, insgesamt also 3,00 EUR."),
                outcome: MailOutcome::Accepted, because: "paid: test",
            },
            Case {
                name: "a single ride's figure copied into the total",
                body: "Für die Fahrt am 03.09. überweisen wir 1,50 EUR. Für die Fahrt am 05.09. überweisen wir 1,50 EUR.",
                claimed: vec![150, 150], rules: MailOutcome::Accepted, rules_because: "x",
                model: model(Outcome::Paid, Some("1,50 EUR"), vec![ride(1, RideCall::Paid, Some("1,50 EUR")), ride(2, RideCall::Paid, Some("1,50 EUR"))], "Für die Fahrt am 03.09. überweisen wir 1,50 EUR. Für die Fahrt am 05.09. überweisen wir 1,50 EUR."),
                outcome: MailOutcome::Accepted, because: "paid: test",
            },
            Case { name: "automatic", body: PAY_ONE, claimed: vec![150], rules: MailOutcome::Accepted, rules_because: "x", model: model(Outcome::Automatic, Some("1,50 EUR"), vec![ride(1, RideCall::Paid, None)], ""), outcome: MailOutcome::Other, because: "automatic or interim reply: test" },
            Case { name: "other", body: PAY_ONE, claimed: vec![150], rules: MailOutcome::Accepted, rules_because: "x", model: model(Outcome::Other, Some("1,50 EUR"), vec![ride(1, RideCall::Paid, None)], ""), outcome: MailOutcome::Other, because: "model found no decision: test" },
        ];
        for c in cases {
            let r = classify::Reading { outcome: c.rules, amount_cents: None, because: c.rules_because, conditional_payment: false, stop: None, refusal_elsewhere: false };
            let v = gate_model(&c.model, &shown(c.body), &claim(&c.claimed), &r);
            assert_eq!((v.outcome, v.because.as_str()), (c.outcome, c.because), "case: {}", c.name);
        }
    }

    #[test]
    fn a_partial_award_confirms_one_ride_at_its_figure_and_refuses_the_other() {
        let body = "Für die Fahrt am 03.09. überweisen wir 7,25 EUR. Für die Fahrt am 05.09. gewähren wir leider keine Entschädigung.";
        let m = model(Outcome::PartlyPaid, Some("7,25 EUR"), vec![ride(1, RideCall::Paid, None), ride(2, RideCall::Refused, None)], body);
        let v = gate_model(&m, &shown(body), &claim(&[800, 800]), &rules(MailOutcome::Other));
        assert_eq!(v.amount_cents, Some(725));
        assert_eq!(v.rides[0].outcome, RideOutcome::Paid { cents: 725 });
        assert_eq!(v.rides[1].outcome, RideOutcome::Refused);
    }

    #[test]
    fn a_cut_off_mail_never_pays() {
        let body = format!("{PAY_ONE}\n{}", redact::CUT);
        let m = model(Outcome::Paid, Some("1,50 EUR"), vec![ride(1, RideCall::Paid, None)], PAY_ONE);
        assert_eq!(gate_model(&m, &shown(&body), &claim(&[150]), &rules(MailOutcome::Accepted)).because, "the mail was cut off before the end");
    }

    #[test]
    fn the_rules_split_a_payment_only_when_it_is_unambiguous() {
        let r = classify::Reading { outcome: MailOutcome::Accepted, amount_cents: Some(300), because: "paid, with an amount", conditional_payment: false, stop: None, refusal_elsewhere: false };
        assert_eq!(gate_rules(&r, &claim(&[150, 150])).rides.len(), 2);
        assert_eq!(gate_rules(&r, &claim(&[150, 250])).outcome, MailOutcome::Other);
        assert_eq!(gate_rules(&r, &claim(&[450])).rides[0].outcome, RideOutcome::Paid { cents: 300 });
        assert_eq!(gate_rules(&r, &claim(&[150])).outcome, MailOutcome::Other);
        assert_eq!(gate_rules(&r, &[]).because, "no claimed rides to confirm");
        let refused = classify::Reading { outcome: MailOutcome::Rejected, amount_cents: None, because: "refused", conditional_payment: false, stop: None, refusal_elsewhere: false };
        assert!(gate_rules(&refused, &claim(&[150, 150])).rides.iter().all(|r| r.outcome == RideOutcome::Refused));
    }

    fn mail<'a>(from: &'a str, body: &'a str) -> Mail<'a> {
        Mail { from, subject: "Ihr Antrag", body }
    }

    #[test]
    fn a_stop_the_rules_saw_vetoes_payments_and_refusals() {
        let pays = "Sie erhalten eine Entschädigung von 10,00 EUR.";
        let m = model(Outcome::Paid, Some("10,00 EUR"), vec![ride(1, RideCall::Paid, None)], pays);
        let r = classify::Reading { outcome: MailOutcome::Other, amount_cents: None, because: "x", conditional_payment: false, stop: Some("a voucher, not money"), refusal_elsewhere: false };
        assert_eq!(gate_model(&m, &shown(pays), &claim(&[1000]), &r).because, "not a payment for this claim: a voucher, not money");
        let refuses = "Leider können wir Ihrem Antrag nicht entsprechen.";
        let m = model(Outcome::Refused, None, vec![ride(1, RideCall::Refused, None)], refuses);
        let r = classify::Reading { outcome: MailOutcome::Rejected, amount_cents: None, because: "refused", conditional_payment: false, stop: Some("passed to another desk"), refusal_elsewhere: false };
        assert_eq!(gate_model(&m, &shown(refuses), &claim(&[150]), &r).because, "not a refusal of this claim: passed to another desk");
        let rules_only = classify::Reading { outcome: MailOutcome::Accepted, amount_cents: Some(150), because: "paid, with an amount", conditional_payment: false, stop: Some("paid or filed before"), refusal_elsewhere: false };
        assert_eq!(gate_rules(&rules_only, &claim(&[150])).outcome, MailOutcome::Other);
    }

    #[test]
    fn a_stop_in_a_passenger_echo_still_vetoes_through_settle() {
        let known = Known::default();
        let body = "Wir überweisen Ihnen eine Entschädigung von 1,50 EUR.\nIhre Nachricht an uns:\nDie Auszahlung soll an Dritte gehen.";
        let answer = model(Outcome::Paid, Some("1,50 EUR"), vec![ride(1, RideCall::Paid, None)], "Wir überweisen Ihnen eine Entschädigung von 1,50 EUR.");
        let d = settle(&mail("Desk <desk@bahn.invalid>", body), &known, &claim(&[150]), Asked::Answered { model: "m".into(), shown: shown("Wir überweisen Ihnen eine Entschädigung von 1,50 EUR."), answer, confirm: None });
        assert_eq!(d.verdict.because, "not a payment for this claim: paid to someone other than the Verein");
    }

    #[test]
    fn a_condition_the_rules_saw_vetoes_a_payment() {
        let body = "[Name] für beide Fahrten gültig war, überweisen wir Ihnen 1,50 EUR.";
        let m = model(Outcome::Paid, Some("1,50 EUR"), vec![ride(1, RideCall::Paid, None)], body);
        let r = classify::Reading { outcome: MailOutcome::Other, amount_cents: None, because: "x", conditional_payment: true, stop: None, refusal_elsewhere: false };
        assert_eq!(gate_model(&m, &shown(body), &claim(&[150]), &r).because, "the payment is conditional or hypothetical");
    }

    #[test]
    fn money_moves_only_when_the_second_reading_agrees() {
        let known = Known::default();
        let c = claim(&[150]);
        let desk = "Servicecenter <desk@bahn.invalid>";
        let pays = "Wir haben eine Entschädigung von 1,50 EUR festgestellt. Der Betrag wird auf das angegebene Konto überwiesen.";
        let reading = |outcome| model(outcome, Some("1,50 EUR"), vec![ride(1, if outcome == Outcome::Paid { RideCall::Paid } else { RideCall::Unclear }, None)], "Wir haben eine Entschädigung von 1,50 EUR festgestellt.");
        let with = |confirm| settle(&mail(desk, pays), &known, &c, Asked::Answered { model: "m".into(), shown: shown(pays), answer: reading(Outcome::Paid), confirm });
        let agreed = with(Some(Ok(("big".into(), reading(Outcome::Paid)))));
        assert_eq!(agreed.verdict.outcome, MailOutcome::Accepted);
        assert!(agreed.verdict.because.ends_with("confirmed by big"));
        let disagreed = with(Some(Ok(("big".into(), reading(Outcome::Other)))));
        assert_eq!(disagreed.verdict.outcome, MailOutcome::Other);
        let unavailable = with(Some(Err(("big".into(), "timeout".into()))));
        assert_eq!(unavailable.verdict.outcome, MailOutcome::Other);
        assert_eq!(with(None).verdict.outcome, MailOutcome::Accepted);
    }

    #[test]
    fn a_refusal_in_the_left_out_echo_vetoes_paying_every_ride() {
        let known = Known::default();
        let body = "Wir überweisen Ihnen für beide Fahrten insgesamt 3,00 EUR auf das angegebene Konto.\nIhre Anfrage vom 06.09.2026:\nFür die Fahrt am 05.09. können wir Ihrem Antrag nicht entsprechen.";
        let first = "Wir überweisen Ihnen für beide Fahrten insgesamt 3,00 EUR auf das angegebene Konto.";
        let answer = model(Outcome::Paid, Some("3,00 EUR"), vec![ride(1, RideCall::Paid, None), ride(2, RideCall::Paid, None)], first);
        let d = settle(&mail("Desk <desk@bahn.invalid>", body), &known, &claim(&[150, 150]), Asked::Answered { model: "m".into(), shown: shown(first), answer, confirm: None });
        assert_eq!(d.verdict.because, "every ride paid, but a refusal stands in a part of the mail the model did not read");
    }

    #[test]
    fn only_the_desk_domain_answers() {
        let desk = vec!["bahn.de".to_string()];
        assert!(sender_matches("fahrgastrechte@bahn.de", &desk));
        assert!(sender_matches("noreply@service.bahn.de", &desk));
        assert!(!sender_matches("fahrgastrechte@bahn.de.evil.org", &desk));
        assert!(!sender_matches("someone@notbahn.de", &desk));
        assert!(!sender_matches("someone@gmail.com", &[]));
        assert!(!sender_matches("x@gmail.com <antwort@bahn.de", &desk));
        assert!(!sender_matches("x@gmail.com,antwort@bahn.de", &desk));
    }

    #[test]
    fn settle_paths() {
        let known = Known { email: Some("fahrgast@example.org".into()), ..Known::default() };
        let c = claim(&[150]);
        let desk = "Servicecenter <desk@bahn.invalid>";
        let pays = "Wir haben eine Entschädigung von 1,50 EUR festgestellt. Der Betrag wird auf das angegebene Konto überwiesen.";

        let bounce = settle(&mail("MAILER-DAEMON@x.invalid", pays), &known, &c, Asked::NotConfigured);
        assert_eq!(bounce.verdict.outcome, MailOutcome::Bounce);

        let own = settle(&mail("Fahrgast <FAHRGAST@example.org>", pays), &known, &c, Asked::NotConfigured);
        assert_eq!(own.verdict.because, "sent from the passenger's own address");

        let below = settle(&mail(desk, "Am 3. September 2026 um 12:00 schrieb Verspätomat <a@b.de>:\n> Antrag\n\nWir überweisen 1,50 EUR."), &known, &c, Asked::NotConfigured);
        assert_eq!(below.verdict.because, "nothing above the quoted text; the answer may be below it");

        let no_key = settle(&mail(desk, pays), &known, &c, Asked::NotConfigured);
        assert_eq!((no_key.verdict.outcome, no_key.read_by.as_str()), (MailOutcome::Accepted, "rules"));

        let failed = settle(&mail(desk, pays), &known, &c, Asked::Failed { model: "m".into(), error: "timeout".into() });
        assert_eq!(failed.verdict.outcome, MailOutcome::Other);
        assert!(failed.verdict.because.ends_with("(model unavailable: timeout)"));

        let refused = settle(&mail(desk, "Leider können wir Ihrem Antrag nicht entsprechen."), &known, &c, Asked::Failed { model: "m".into(), error: "http 500".into() });
        assert_eq!(refused.verdict.outcome, MailOutcome::Other);
        let asks = settle(&mail(desk, "Bitte senden Sie uns eine Kopie Ihres Tickets."), &known, &c, Asked::Failed { model: "m".into(), error: "http 500".into() });
        assert_eq!(asks.verdict.outcome, MailOutcome::Question);

        let answer = model(Outcome::Paid, Some("1,50 EUR"), vec![ride(1, RideCall::Paid, None)], "Wir haben eine Entschädigung von 1,50 EUR festgestellt.");
        let by_model = settle(&mail(desk, pays), &known, &c, Asked::Answered { model: "m".into(), shown: shown(pays), answer, confirm: None });
        assert_eq!((by_model.verdict.outcome, by_model.read_by.as_str()), (MailOutcome::Accepted, "model:m"));
    }
}
