//! Reading a railway's answer.
//!
//! This is now the only way money is ever confirmed. There used to be a second one — importing a
//! Verein's bank statement and matching transfers to claims — and it was never going to happen:
//! these are large organisations, we cannot ask them for their statements, and a product that
//! needs a monthly CSV from a charity to tell a passenger whether they were paid has not solved
//! the problem. So the desk's own words are the confirmation. If the desk says it pays or has
//! paid, the claim is confirmed, the cases go to `bestätigt`, and the sums move.
//!
//! Which makes being wrong expensive in a specific direction. A false **accepted** tells somebody
//! their delay turned into money that never arrived, and adds that money to a Verein's public
//! total. A false **other** costs a person one look at their inbox. So every rule here is built to
//! fail towards [`MailOutcome::Other`]: ambiguity, negation, a missing amount, two signals at once
//! — all of them mean "a human should read this", never "paid".
//!
//! The order below is the whole design and it is not alphabetical:
//!
//! 1. **Bounce first.** A delivery failure quotes the message it could not deliver, so the quoted
//!    text contains our own words and, often, the desk's. Classify the envelope before the content
//!    or a bounce reads as whatever it is bouncing.
//! 2. **Automatic mail next.** An acknowledgement of receipt or an out-of-office is not an answer,
//!    and several of them contain "Ihr Antrag" and a figure.
//! 3. **Refusal before payment**, because a refusal routinely explains what would have been paid
//!    ("eine Entschädigung von 4,50 EUR kommt nicht in Betracht").
//! 4. **Payment**, then **question**, then nothing.

use crate::db::rows::MailOutcome;

/// What reading one mail produced.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Reading {
    pub outcome: MailOutcome,
    /// Cents the desk named, when it named one in the same breath as the payment.
    pub amount_cents: Option<i64>,
    /// Why, in one short phrase. Goes into the audit trail, so a wrong call can be traced to the
    /// rule that made it rather than guessed at.
    pub because: &'static str,
}

/// True if `needle` occurs in `hay` without a negation in the few words before it.
///
/// "Ihr Antrag wurde nicht abgelehnt" and "sofern nicht abgelehnt wird" both contain the word a
/// refusal is recognised by. German puts the negation ahead of the participle, so a short lookback
/// is enough and does not need a parser.
fn says(hay: &str, needle: &str) -> bool {
    let mut from = 0;
    while let Some(at) = hay[from..].find(needle) {
        let at = from + at;
        let back = &hay[at.saturating_sub(40)..at];
        let negated = back.contains("nicht ") || back.contains("keine ") || back.contains("kein ") || back.contains("weder ");
        if !negated {
            return true;
        }
        from = at + needle.len();
    }
    false
}

fn any(hay: &str, needles: &[&str]) -> bool {
    needles.iter().any(|n| says(hay, n))
}

/// Phrases a desk uses when it will not pay. Each is a whole statement, not a single word:
/// "abgelehnt" on its own appears in boilerplate about appeals.
const REFUSED: &[&str] = &[
    "nicht entsprechen",
    "antrag abgelehnt",
    "antrag wird abgelehnt",
    "antrag wurde abgelehnt",
    "abgelehnt werden",
    "keine entschädigung",
    "kein anspruch",
    "besteht kein",
    "nicht stattgegeben",
    "nicht erstattet",
    "außergewöhnliche umstände",
    "höhere gewalt",
];

/// Phrases a desk uses when it pays or has paid. This is the list that moves money, so every entry
/// has to be a commitment and not a possibility: "können wir erstatten" is not here.
const PAID: &[&str] = &[
    // German splits the verb: "wird in den nächsten Tagen überwiesen" puts six words between the
    // auxiliary and the participle, so the participle alone has to count. That is safe here only
    // because `says` refuses a negated occurrence and because a mail that also refuses is sent to
    // a human instead — "keine Entschädigung wird überwiesen" reaches neither branch.
    "überwiesen",
    "überweisen wir",
    "ausgezahlt",
    "gutgeschrieben",
    "erstatten wir",
    "wird erstattet",
    "zahlen wir",
    "stattgegeben",
    "entschädigung von",
    "entschädigung in höhe von",
    "erhalten sie eine entschädigung",
    "auf das angegebene konto",
];

/// The desk needs something from the passenger before it can decide.
const ASKED: &[&str] = &[
    "benötigen wir",
    "bitte senden sie",
    "bitte übersenden",
    "bitte teilen sie",
    "rückfrage",
    "fehlen uns",
    "nicht beigefügt",
    "konnten wir nicht zuordnen",
];

/// Machine mail: a receipt, an interim notice, an absence. Not an answer.
const AUTOMATIC: &[&str] = &[
    "eingangsbestätigung",
    "zwischenbescheid",
    "automatische antwort",
    "automatische eingangs",
    "out of office",
    "abwesenheitsnotiz",
    "nicht im hause",
    "bitte antworten sie nicht auf diese",
    "in bearbeitung",
    "wir bearbeiten ihren antrag",
];

/// A delivery failure, judged on the envelope rather than the text it carries.
const BOUNCED: &[&str] = &[
    "mailer-daemon",
    "postmaster@",
    "undeliverable",
    "delivery status notification",
    "unzustellbar",
    "nicht zustellbar",
    "returned mail",
    "failure notice",
];

/// Read one mail.
///
/// `from` and `subject` are separate arguments because the bounce test belongs to the envelope:
/// the body of a bounce is somebody else's mail.
pub fn read(from: &str, subject: &str, body: &str) -> Reading {
    let envelope = format!("{} {}", from.to_lowercase(), subject.to_lowercase());
    let text = body.to_lowercase();

    // 1. Never gone out at all.
    if BOUNCED.iter().any(|n| envelope.contains(n)) || BOUNCED.iter().any(|n| text.contains(n)) {
        return Reading { outcome: MailOutcome::Bounce, amount_cents: None, because: "delivery failure" };
    }

    // 2. A machine, not a decision.
    if any(&text, AUTOMATIC) || AUTOMATIC.iter().any(|n| envelope.contains(n)) {
        return Reading { outcome: MailOutcome::Other, amount_cents: None, because: "automatic or interim reply" };
    }

    let refused = any(&text, REFUSED);
    let paid = any(&text, PAID);

    // 3. Both at once is not a decision we may make. It happens: a partial award that refuses one
    //    of several cases, or a refusal quoting the rule it would have paid under.
    if refused && paid {
        return Reading { outcome: MailOutcome::Other, amount_cents: None, because: "says both paid and refused" };
    }
    if refused {
        return Reading { outcome: MailOutcome::Rejected, amount_cents: None, because: "refused" };
    }

    // 4. Paid — but only with a figure. A payment with no amount anywhere is either a promise
    //    without a number or our own misreading, and confirming money without knowing how much
    //    would put a figure we invented onto a Verein's public total.
    if paid {
        return match amount_cents(body) {
            Some(cents) => Reading { outcome: MailOutcome::Accepted, amount_cents: Some(cents), because: "paid, with an amount" },
            None => Reading { outcome: MailOutcome::Other, amount_cents: None, because: "sounds paid but names no amount" },
        };
    }

    if any(&text, ASKED) {
        return Reading { outcome: MailOutcome::Question, amount_cents: None, because: "asks for something" };
    }

    Reading { outcome: MailOutcome::Other, amount_cents: None, because: "nothing recognised" }
}

/// The euro amount a German mail names, in cents.
///
/// Takes the **largest** figure, not the first. A desk's letter carries a footer, a case reference
/// and sometimes the fare; the sum being paid is the biggest number that is written as money in
/// nearly every one of them. Requires a currency right after the digits, so "4,50 Uhr" and a
/// customer number are not money.
pub fn amount_cents(text: &str) -> Option<i64> {
    let c: Vec<char> = text.chars().collect();
    let mut best: Option<i64> = None;
    let mut i = 0;
    while i < c.len() {
        if !c[i].is_ascii_digit() {
            i += 1;
            continue;
        }
        let start = i;
        while i < c.len() && (c[i].is_ascii_digit() || c[i] == '.') {
            i += 1;
        }
        // German writes cents after a comma, always two digits.
        if i + 2 < c.len() && c[i] == ',' && c[i + 1].is_ascii_digit() && c[i + 2].is_ascii_digit() {
            let whole: String = c[start..i].iter().filter(|x| x.is_ascii_digit()).collect();
            let frac: String = c[i + 1..i + 3].iter().collect();
            let after: String = c[i + 3..(i + 10).min(c.len())].iter().collect();
            let after = after.trim_start();
            if after.starts_with("EUR") || after.starts_with('€') || after.starts_with("Euro") {
                let v = whole.parse::<i64>().unwrap_or(0) * 100 + frac.parse::<i64>().unwrap_or(0);
                best = Some(best.map_or(v, |b: i64| b.max(v)));
            }
            i += 3;
        }
    }
    best
}

#[cfg(test)]
mod tests {
    use super::*;

    fn out(body: &str) -> MailOutcome {
        read("Servicecenter <a@b.invalid>", "Ihr Antrag", body).outcome
    }

    #[test]
    fn a_plain_payment_is_accepted_with_its_amount() {
        let r = read("a@b.invalid", "Ihr Antrag", "Wir haben eine Entschädigung von 4,50 EUR festgestellt. Der Betrag wird auf das angegebene Konto überwiesen.");
        assert_eq!(r.outcome, MailOutcome::Accepted);
        assert_eq!(r.amount_cents, Some(450));
    }

    #[test]
    fn a_plain_refusal_is_rejected() {
        assert_eq!(out("Leider können wir Ihrem Antrag nicht entsprechen."), MailOutcome::Rejected);
    }

    #[test]
    fn a_negated_refusal_is_not_a_refusal() {
        // The single most dangerous false positive: the word that means "refused" inside a
        // sentence saying the opposite.
        assert_ne!(out("Ihr Antrag wurde nicht abgelehnt. Die Entschädigung von 4,50 EUR wird überwiesen."), MailOutcome::Rejected);
    }

    #[test]
    fn a_bounce_quoting_our_own_mail_is_a_bounce_not_a_payment() {
        // The bounce carries the whole original, and the original says "Entschädigung".
        let body = "Delivery Status Notification (Failure)\n\n--- Original message ---\nanbei mein Antrag auf Entschädigung von 4,50 EUR, bitte überweisen wir an den Verein.";
        assert_eq!(read("MAILER-DAEMON@bahn.invalid", "Undeliverable", body).outcome, MailOutcome::Bounce);
    }

    #[test]
    fn an_acknowledgement_is_not_an_answer() {
        assert_eq!(out("Eingangsbestätigung: Wir bearbeiten Ihren Antrag. Dies kann bis zu vier Wochen dauern."), MailOutcome::Other);
    }

    #[test]
    fn out_of_office_is_not_an_answer() {
        assert_eq!(out("Automatische Antwort: Ich bin bis zum 30.09. nicht im Hause."), MailOutcome::Other);
    }

    #[test]
    fn a_payment_without_an_amount_waits_for_a_human() {
        // Better to ask somebody to look than to confirm a number we do not have.
        let r = read("a@b.invalid", "Ihr Antrag", "Der Betrag wird in den nächsten Tagen überwiesen.");
        assert_eq!(r.outcome, MailOutcome::Other);
        assert_eq!(r.because, "sounds paid but names no amount");
    }

    #[test]
    fn both_signals_at_once_waits_for_a_human() {
        let r = read("a@b.invalid", "Ihr Antrag", "Für die Fahrt am 1.9. überweisen wir 1,50 EUR. Dem Antrag für den 2.9. können wir nicht entsprechen.");
        assert_eq!(r.outcome, MailOutcome::Other);
        assert_eq!(r.because, "says both paid and refused");
    }

    #[test]
    fn a_question_is_a_question() {
        assert_eq!(out("Zur Bearbeitung benötigen wir noch eine Kopie Ihres Tickets."), MailOutcome::Question);
    }

    #[test]
    fn the_largest_money_figure_wins_over_a_footer() {
        assert_eq!(amount_cents("Vorgang 2026-09-4723683. Entschädigung von 19,95 EUR. Gebühr 0,00 EUR."), Some(1995));
    }

    #[test]
    fn a_time_is_not_money() {
        assert_eq!(amount_cents("Ankunft 12,30 Uhr, Zug RE 5"), None);
    }

    #[test]
    fn nothing_recognised_stays_other() {
        assert_eq!(out("Guten Tag, wie besprochen. Mit freundlichen Grüßen"), MailOutcome::Other);
    }
}
