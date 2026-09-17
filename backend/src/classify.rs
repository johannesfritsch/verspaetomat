//! The rules that read a railway's answer.
//!
//! One of two readers; `reply.rs` decides what a reading does to a claim. Without a model
//! configured these rules decide alone. With one, they still short-circuit bounces and act as a
//! veto: a model reading that the rules flatly contradict does not move money. So a wrong
//! **accepted** here is dangerous in both setups, and every rule is built to fail towards
//! [`MailOutcome::Other`]: ambiguity, negation, a condition, a missing amount, two signals at once
//! — all of them mean "a human should read this", never "paid".
//!
//! A false **accepted** tells somebody their delay turned into money that never arrived, and adds
//! that money to a Verein's public total. A false **other** costs a person one look at their inbox.
//!
//! The order below is the whole design and it is not alphabetical:
//!
//! 1. **Bounce first.** A delivery failure quotes the message it could not deliver, so the quoted
//!    text contains our own words and, often, the desk's. Classify it before the content or a
//!    bounce reads as whatever it is bouncing. (Bounce words in the body count too.)
//! 2. **Automatic mail next.** An acknowledgement of receipt or an out-of-office is not an answer,
//!    and several of them contain "Ihr Antrag" and a figure.
//! 3. **Stops**: a claim passed to another desk, a voucher instead of money, money paid before or
//!    under another claim. Each reads like a decision and is not one for this claim.
//! 4. **Refusal before payment**, because a refusal routinely explains what would have been paid
//!    ("eine Entschädigung von 4,50 EUR kommt nicht in Betracht").
//! 5. **Question before payment**, because a question routinely promises what follows
//!    ("nach Eingang überweisen wir Ihnen 1,50 EUR").
//! 6. **Payment**, only in a sentence without a condition and only with a figure in that sentence.

use std::sync::LazyLock;

use regex::Regex;

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
    /// A sentence where the desk talks about paying under a condition ("sofern Ihr Ticket gültig
    /// war, überweisen wir …"). Whatever else the mail says, a model reading it as paid is vetoed:
    /// redaction or a model can lose the condition, the rules read the raw text.
    pub conditional_payment: bool,
    /// A stop found anywhere the desk wrote (see [`stop`]), with its reason: a voucher, a payment
    /// made before or to someone else, a claim passed on. Vetoes a model's payment or refusal.
    pub stop: Option<&'static str>,
    /// Set by `reply::settle` when a refusal stands in a part of the mail the reader left out (a
    /// ticket system's echo block): a payment for every ride is then not believable.
    pub refusal_elsewhere: bool,
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
        if !negated_before(hay, at) {
            return true;
        }
        from = at + needle.len();
    }
    false
}

/// A negation in the forty bytes before `at`. Only this occurrence's own lookback: scanning from the
/// start for every occurrence made a mail of repeated negated phrases quadratic.
fn negated_before(hay: &str, at: usize) -> bool {
    // Moved to a character boundary: German text is full of two-byte letters, and slicing inside
    // one panicked the inbound webhook on ordinary replies.
    let mut start = at.saturating_sub(40);
    while !hay.is_char_boundary(start) {
        start -= 1;
    }
    let back = &hay[start..at];
    NEGATION.is_match(back)
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
    "nicht in betracht",
    "nicht ausgezahlt",
    "zahlen wir nicht",
    "zahlen wir leider nicht",
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
    "wir überweisen",
    "wir zahlen",
    "ausgezahlt",
    "gutgeschrieben",
    "erstatten wir",
    "wird erstattet",
    "zahlen wir",
    "stattgegeben",
    // Not "Entschädigung von 4,50 EUR" on its own: that names a figure, often the one claimed, and
    // commits to nothing.
    "erhalten sie eine entschädigung",
    "auf das angegebene konto",
];

/// The desk needs something from the passenger before it can decide.
const ASKED: &[&str] = &[
    "benötigen wir",
    "bitte senden sie",
    "bitte übersenden",
    "bitte teilen sie",
    // Not "Rückfrage" alone: "Für Rückfragen stehen wir gerne zur Verfügung" closes paying mails.
    "haben wir eine rückfrage",
    "rückfrage zu ihrem antrag",
    "fehlen uns",
    "nicht beigefügt",
    "konnten wir nicht zuordnen",
];

/// The sentence a stop phrase stands in has to be about the thing the stop is about, or footers and
/// signatures stop real payments: "nicht an Dritte weitergegeben" (privacy), "DB Gutscheine im Wert
/// von 10 bis 250 Euro" (marketing), "Nutzen Sie unser Kundenportal" (advice).
#[derive(Clone, Copy)]
enum Ctx {
    /// Money moving: a payment verb, an amount's noun, an account.
    Paying,
    /// The claim itself: an Antrag, an Anliegen, compensation.
    Claim,
}

static PAYING: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\b(entschädigung\w*|erstatt\w*|überweis\w*|überwiesen|auszahl\w*|ausgezahlt|zahlung\w*|zahlen|zahlt|gezahlt|betrag|beträge|geld|konto|bankverbindung|gutschrift\w*|gewähr\w*|erhalten sie)\b").unwrap()
});
static ABOUT_CLAIM: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\b(antrag\w*|anträge\w*|anliegen|entschädigung\w*|fahrgastrecht\w*|erstattung\w*)\b").unwrap());

/// Reads like a decision, and is not one about this claim's money — wherever it stands, in a
/// sentence about the right thing (see [`Ctx`]).
const STOPS: &[(&str, &str, Ctx)] = &[
    // Another desk: the claim moves, it is not refused.
    ("nicht zuständig", "passed to another desk", Ctx::Claim),
    ("zuständigkeitshalber", "passed to another desk", Ctx::Claim),
    ("zuständige stelle", "passed to another desk", Ctx::Claim),
    ("zuständigen stelle", "passed to another desk", Ctx::Claim),
    ("zuständige unternehmen", "passed to another desk", Ctx::Claim),
    ("zuständigen unternehmen", "passed to another desk", Ctx::Claim),
    ("zuständige eisenbahn", "passed to another desk", Ctx::Claim),
    ("zuständigen eisenbahn", "passed to another desk", Ctx::Claim),
    // A voucher goes to the passenger, never to the Verein's account.
    ("gutschein", "a voucher, not money", Ctx::Paying),
    ("voucher", "a voucher, not money", Ctx::Paying),
    // Paid before, or under another claim: nothing new reaches the Verein.
    ("bereits ein antrag", "paid or filed before", Ctx::Paying),
    ("bereits einen antrag", "paid or filed before", Ctx::Paying),
    ("bereits bearbeitet", "paid or filed before", Ctx::Paying),
    ("bereits entschädigt", "paid or filed before", Ctx::Paying),
    ("erneute zahlung", "paid or filed before", Ctx::Paying),
    ("erneute auszahlung", "paid or filed before", Ctx::Paying),
    ("erneute entschädigung", "paid or filed before", Ctx::Paying),
    ("erneute erstattung", "paid or filed before", Ctx::Paying),
    ("nochmalige zahlung", "paid or filed before", Ctx::Paying),
    ("nochmalige auszahlung", "paid or filed before", Ctx::Paying),
    ("nochmalige entschädigung", "paid or filed before", Ctx::Paying),
    ("doppelte zahlung", "paid or filed before", Ctx::Paying),
    ("doppelt beantragt", "paid or filed before", Ctx::Paying),
    ("doppelt eingereicht", "paid or filed before", Ctx::Paying),
    ("doppelte einreichung", "paid or filed before", Ctx::Paying),
    ("kundenportal", "paid or filed before", Ctx::Paying),
    // Paid to the passenger or anybody else: the form names the Verein's account, and money that
    // goes elsewhere never reaches its total. "Auf Ihr Konto" alone is how desks write to the
    // account on the form, and stays a payment.
    ("antragsteller", "paid to someone other than the Verein", Ctx::Paying),
    ("kundenkonto", "paid to someone other than the Verein", Ctx::Paying),
    ("hinterlegte bankverbindung", "paid to someone other than the Verein", Ctx::Paying),
    ("hinterlegten bankverbindung", "paid to someone other than the Verein", Ctx::Paying),
    ("hinterlegtes konto", "paid to someone other than the Verein", Ctx::Paying),
    ("hinterlegte konto", "paid to someone other than the Verein", Ctx::Paying),
    ("an sie ausgezahlt", "paid to someone other than the Verein", Ctx::Paying),
    ("an sie überwiesen", "paid to someone other than the Verein", Ctx::Paying),
    ("girokonto", "paid to someone other than the Verein", Ctx::Paying),
    ("ihr persönliches", "paid to someone other than the Verein", Ctx::Paying),
    ("ihr eigenes", "paid to someone other than the Verein", Ctx::Paying),
    ("an dritte", "paid to someone other than the Verein", Ctx::Paying),
    ("an dritten", "paid to someone other than the Verein", Ctx::Paying),
    ("zugunsten dritter", "paid to someone other than the Verein", Ctx::Paying),
    ("an einen dritten", "paid to someone other than the Verein", Ctx::Paying),
    ("eigenes konto", "paid to someone other than the Verein", Ctx::Paying),
    ("persönliches konto", "paid to someone other than the Verein", Ctx::Paying),
    ("an sie persönlich", "paid to someone other than the Verein", Ctx::Paying),
    ("abweichend vom angegebenen konto", "paid to someone other than the Verein", Ctx::Paying),
];

/// "bereits … ausgezahlt": a payment in the past tense is one made before this answer, under this
/// claim or another; either way this mail is not the one that pays.
static PAID_BEFORE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\bbereits\b.*\b(ausgezahlt|überwiesen|erstattet|gutgeschrieben|gezahlt|entschädigt)\b|\b(ausgezahlt|überwiesen|erstattet|gutgeschrieben|gezahlt)\b.*\bbereits\b").unwrap());
/// "wurde bereits angewiesen und wird … überwiesen" is this payment on its way, not an earlier one.
static FUTURE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\b(wird|werden)\b").unwrap());
static NEGATION: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\b(nicht|keine|kein|keinen|keinerlei|nichts|weder)\s").unwrap());

/// Words that make a sentence a condition or a hypothesis rather than a commitment. Whole words:
/// "ebenfalls" and "jedenfalls" contain "falls" and commit to paying all the same.
static CONDITIONS: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\b(sofern|falls|sobald|wenn|vorausgesetzt|voraussetzung|vorbehaltlich|vorbehalt|sollte|sollten|hätten|hätte|wären|wäre|würden|würde|könnten)\b|\bim falle\b").unwrap()
});
/// "Nach Eingang Ihrer Kopie überweisen wir" waits; "Nach Eingang Ihres Antrags haben wir geprüft" does not.
static AFTER_RECEIPT: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\bnach (eingang|erhalt|vorlage|zusendung|übersendung|einreichung|nachreichung|abschluss)\b").unwrap());
static PAST: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\b(haben wir|hat|wurde|wurden|ist|sind)\b").unwrap());
/// A negation after a phrase, anywhere before the sentence ends: "zahlen wir … nicht aus",
/// "überweisen wir Ihnen, anders als erwartet, nicht", "benötigen wir keine weiteren Unterlagen".
static NEGATED_AFTER: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^(?:\d+\.\d+|[^.!?\n])*?\b(nicht|keine|keinen|keiner|keinerlei|nichts)\b").unwrap());
/// How much of a mail the rules read. A desk's decision fits in a few lines; the cap keeps a crafted
/// megabyte of text from holding a worker.
pub const MAX_RULES_CHARS: usize = 30_000;
/// Where the deciding text ends: the closing greeting, above signature and footer.
static CLOSING: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?im)^\s*(mit freundlichen grü(ß|ss)en|mit freundlichem gru(ß|ss)|freundliche grü(ß|ss)e|viele grü(ß|ss)e|beste grü(ß|ss)e|herzliche grü(ß|ss)e|kind regards|best regards|sincerely)\b").unwrap());

/// The part of a mail that decides: everything above the closing greeting.
pub fn deciding(text: &str) -> &str {
    match CLOSING.find(text) {
        Some(m) if m.start() > 0 => &text[..m.start()],
        _ => text,
    }
}

/// The first stop in `text`, with its reason — in any sentence that talks about money or the claim,
/// wherever it stands. Position is not a safe signal: a notice below a cover note's signature or
/// below a line of dashes is still the desk's word, while a footer's "nicht an Dritte" is not about
/// money at all.
pub fn stop(text: &str) -> Option<&'static str> {
    let text = unwrap(&text.to_lowercase());
    for s in sentences(&text) {
        let about = |ctx: Ctx| match ctx {
            Ctx::Paying => PAYING.is_match(s),
            Ctx::Claim => ABOUT_CLAIM.is_match(s),
        };
        if let Some((_, why, _)) = STOPS.iter().find(|(needle, _, ctx)| s.contains(needle) && about(*ctx)) {
            return Some(why);
        }
        if PAID_BEFORE.is_match(s) && !FUTURE.is_match(s) {
            return Some("paid or filed before");
        }
    }
    None
}

/// Plain-text mail is wrapped at about 72 columns, and a line break in the middle of a sentence would
/// split "sofern … gültig war,\nüberweisen wir" into a condition and a payment. A single line break
/// becomes a space unless the next line starts something of its own: a blank line, a list item, a
/// "Label:" line.
fn unwrap(text: &str) -> String {
    let lines: Vec<&str> = text.lines().collect();
    let mut out = String::with_capacity(text.len());
    for (n, line) in lines.iter().enumerate() {
        out.push_str(line);
        let Some(next) = lines.get(n + 1) else { break };
        let next = next.trim_start();
        let starts_own = next.is_empty()
            || line.trim().is_empty()
            || line.trim_end().ends_with(':')
            || next.starts_with(['-', '*', '•', '>'])
            || LABEL_LINE.is_match(next);
        out.push(if starts_own { '\n' } else { ' ' });
    }
    out
}

static LABEL_LINE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[\p{L}][\p{L}\d .\-/]{0,30}:").unwrap());

/// True if the passage states something conditional or hypothetical.
pub fn conditional(text: &str) -> bool {
    let text = unwrap(&text.to_lowercase());
    CONDITIONS.is_match(&text) || sentences(&text).into_iter().any(|s| AFTER_RECEIPT.is_match(s) && !PAST.is_match(s))
}

/// True if `needle` occurs in `hay` negated neither before nor right after it.
fn says_plainly(hay: &str, needle: &str) -> bool {
    let mut from = 0;
    while let Some(at) = hay[from..].find(needle) {
        let at = from + at;
        let end = at + needle.len();
        if !negated_before(hay, at) && !NEGATED_AFTER.is_match(&hay[end..]) {
            return true;
        }
        from = end;
    }
    false
}

/// The sentences of a lower-cased text. A dot ends a sentence only after a letter, so "am 03.09.
/// überweisen wir" and "1.234,56" stay whole; a line break always ends one.
fn sentences(text: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let mut start = 0;
    let mut prev: Option<char> = None;
    for (i, ch) in text.char_indices() {
        let end = ch == '\n' || ch == '!' || ch == '?' || (ch == '.' && prev.is_some_and(|p| p.is_alphabetic()));
        if end {
            out.push(&text[start..i + ch.len_utf8()]);
            start = i + ch.len_utf8();
        }
        prev = Some(ch);
    }
    out.push(&text[start..]);
    out.into_iter().filter(|s| !s.trim().is_empty()).collect()
}

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
    let body = match body.char_indices().nth(MAX_RULES_CHARS) {
        Some((cut, _)) => &body[..cut],
        None => body,
    };
    let whole = unwrap(&body.to_lowercase());
    // Everything but the bounce test reads above the closing greeting: a footer's "Bitte antworten
    // Sie nicht auf diese E-Mail" or "Für Rückfragen …" is not what the desk decided.
    let text = deciding(&whole);
    let all = sentences(text);
    let payment_phrase = |s: &str| PAID.iter().any(|n| says_plainly(s, n));
    // Read in the whole text, like the stops: a condition below the greeting still holds the money.
    let conditional_payment = sentences(&whole).iter().any(|s| payment_phrase(s) && conditional(s));
    // Stops are read in the whole text, not just above the greeting (see `stop`).
    let stopped = stop(&whole);
    let r = |outcome, amount_cents, because| Reading { outcome, amount_cents, because, conditional_payment, stop: stopped, refusal_elsewhere: false };

    // 1. Never gone out at all.
    if BOUNCED.iter().any(|n| envelope.contains(n)) || BOUNCED.iter().any(|n| whole.contains(n)) {
        return r(MailOutcome::Bounce, None, "delivery failure");
    }

    // 2. A machine, not a decision.
    if any(text, AUTOMATIC) || AUTOMATIC.iter().any(|n| envelope.contains(n)) {
        return r(MailOutcome::Other, None, "automatic or interim reply");
    }

    // 3. Not a decision about this claim's money, however much it sounds like one.
    if let Some(why) = stopped {
        return r(MailOutcome::Other, None, why);
    }

    // A payment phrase negated after the verb ("zahlen wir … nicht aus") is no payment.
    let refused = any(text, REFUSED);
    // Payment counts only in a sentence that states it without a condition. Its figure may stand in
    // that sentence or in the one right before ("… eine Entschädigung von 4,50 EUR festgestellt. Der
    // Betrag wird überwiesen."), unless that one is restating what was claimed.
    let paying: Vec<usize> = (0..all.len()).filter(|&n| payment_phrase(all[n]) && !conditional(all[n])).collect();
    let paid = !paying.is_empty();
    let restates = |s: &str| ["beantragt", "geltend gemacht", "gefordert", "verlangt", "ihr antrag über"].iter().any(|w| s.contains(w));
    let paid_figure = paying
        .iter()
        .filter_map(|&n| amount_cents(all[n]).or_else(|| n.checked_sub(1).filter(|&p| !restates(all[p]) && !conditional(all[p])).and_then(|p| amount_cents(all[p]))))
        .max();
    let asked = ASKED.iter().any(|n| says_plainly(text, n));

    // 4. Both at once is not a decision we may make. It happens: a partial award that refuses one
    //    of several cases, or a refusal quoting the rule it would have paid under.
    if refused && paid {
        return r(MailOutcome::Other, None, "says both paid and refused");
    }
    if refused {
        return r(MailOutcome::Rejected, None, "refused");
    }

    // 5. A question that also talks about paying is a question: the payment waits for the answer.
    if asked {
        return r(MailOutcome::Question, None, "asks for something");
    }

    // 6. Paid — but only with a figure in the sentence that pays. A payment with no amount there is
    //    a promise without a number, or the number belongs to something else (the claim, the fare,
    //    a threshold); confirming it would put a figure we invented onto a Verein's public total.
    if paid {
        return match paid_figure {
            Some(cents) => r(MailOutcome::Accepted, Some(cents), "paid, with an amount"),
            None => r(MailOutcome::Other, None, "sounds paid but names no amount"),
        };
    }

    r(MailOutcome::Other, None, "nothing recognised")
}

/// The euro amount a German mail names, in cents.
///
/// Takes the **largest** figure, not the first. A desk's letter carries a footer, a case reference
/// and sometimes the fare; the sum being paid is the biggest number that is written as money in
/// nearly every one of them. What counts as money is [`money_figures`]'s business.
pub fn amount_cents(text: &str) -> Option<i64> {
    money_figures(text).into_iter().max()
}

/// Every figure a German mail writes as money, in cents, in the order they appear.
///
/// A figure is money only with a currency right next to it — after it ("4,50 EUR", "4,50 €",
/// "4 Euro", "4,- €") or before it ("EUR 4,50", "€4,50") — so "12,30 Uhr", a date and a customer
/// number are not. Dots group thousands ("1.234,56 EUR"); a dot run that is not thousands groups is
/// a date and is skipped.
///
/// This is also the check a model's answer has to pass: an amount the model names is believed only
/// if it is one of these, because a model can copy a figure from the fare, from the ride list, or
/// from nowhere.
pub fn money_figures(text: &str) -> Vec<i64> {
    let c: Vec<char> = text.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i < c.len() {
        if !c[i].is_ascii_digit() {
            i += 1;
            continue;
        }
        let start = i;
        while i < c.len() && (c[i].is_ascii_digit() || (c[i] == '.' && i + 1 < c.len() && c[i + 1].is_ascii_digit())) {
            i += 1;
        }
        let mut run: String = c[start..i].iter().collect();
        let mut end = i;
        let mut frac = 0;
        // "EUR 2.20" in an English reply: one dot, exactly two digits after it, no comma following.
        let dots = run.matches('.').count();
        if dots == 1 && run.rsplit('.').next().is_some_and(|g| g.len() == 2) && !(i < c.len() && c[i] == ',') {
            let (whole, cents) = run.split_once('.').unwrap_or_default();
            frac = cents.parse::<i64>().unwrap_or(0);
            run = whole.to_string();
        }
        if frac == 0 && i < c.len() && c[i] == ',' {
            if i + 2 < c.len() && c[i + 1].is_ascii_digit() && c[i + 2].is_ascii_digit() && !(i + 3 < c.len() && c[i + 3].is_ascii_digit()) {
                frac = (c[i + 1] as i64 - '0' as i64) * 10 + (c[i + 2] as i64 - '0' as i64);
                end = i + 3;
            } else if i + 1 < c.len() && (c[i + 1] == '-' || c[i + 1] == '\u{2013}') {
                end = i + 2;
            }
        }
        // A letter or digit glued to the front ("RE5", "Nr.2026") is not the start of an amount.
        let glued = start > 0 && (c[start - 1].is_alphanumeric() || c[start - 1] == ',');
        let grouped = run.split('.').skip(1).all(|g| g.len() == 3);
        if !glued && grouped && (currency_after(&c, end) || currency_before(&c, start)) {
            let whole: String = run.chars().filter(|x| x.is_ascii_digit()).collect();
            // Nine digits is ten million euros; anything longer is not a compensation and would
            // overflow into a small, believable figure in a release build.
            if whole.len() <= 9 {
                if let Ok(w) = whole.parse::<i64>() {
                    out.push(w * 100 + frac);
                }
            }
        }
        i = end.max(i);
    }
    out
}

fn is_space(ch: char) -> bool {
    ch != '\n' && ch.is_whitespace()
}

/// "EUR", "Euro" or "€" starting at `at`, after any spaces, and not the front of a longer word.
fn currency_after(c: &[char], mut at: usize) -> bool {
    while at < c.len() && is_space(c[at]) {
        at += 1;
    }
    if at < c.len() && c[at] == '€' {
        return true;
    }
    let word: String = c[at..(at + 5).min(c.len())].iter().collect::<String>().to_lowercase();
    let len = if word.starts_with("euro") {
        4
    } else if word.starts_with("eur") {
        3
    } else {
        return false;
    };
    !(at + len < c.len() && c[at + len].is_alphabetic())
}

/// "EUR", "Euro" or "€" ending right before `at`, across spaces, and not the tail of a longer word.
fn currency_before(c: &[char], at: usize) -> bool {
    let mut end = at;
    while end > 0 && is_space(c[end - 1]) {
        end -= 1;
    }
    if end > 0 && c[end - 1] == '€' {
        return true;
    }
    for word in ["eur", "euro"] {
        let n = word.chars().count();
        if end >= n {
            let tail: String = c[end - n..end].iter().collect::<String>().to_lowercase();
            if tail == word && !(end > n && c[end - n - 1].is_alphabetic()) {
                return true;
            }
        }
    }
    false
}

/// An amount as a model copied it out of a mail ("4,50 EUR", "4,50 €", "4,50"), in cents.
///
/// Parsing only. Whether the mail really says it is [`money_figures`]'s question, asked separately.
pub fn parse_amount(s: &str) -> Option<i64> {
    if let Some(first) = money_figures(s).into_iter().next() {
        return Some(first);
    }
    let t = s.trim();
    let (whole, frac) = match t.find([',', '.']) {
        Some(at) => (&t[..at], &t[at + 1..]),
        None => (t, "00"),
    };
    if whole.is_empty() || whole.len() > 9 || !whole.chars().all(|x| x.is_ascii_digit()) || frac.len() != 2 || !frac.chars().all(|x| x.is_ascii_digit()) {
        return None;
    }
    Some(whole.parse::<i64>().ok()? * 100 + frac.parse::<i64>().ok()?)
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
    fn an_umlaut_before_a_phrase_does_not_panic() {
        // Byte 40 before "überweisen" lands inside the "ü" of "Müller" for some padding lengths.
        for pad in 0..60 {
            let body = format!("Sehr geehrte Frau Müller,{} überweisen wir Ihnen 1,50 EUR.", "x".repeat(pad));
            let _ = read("a@b.invalid", "Ihr Antrag", &body);
        }
        let _ = read("a@b.invalid", "Ihr Antrag", "Guten Tag,\n\nvielen Dank für Ihr Schreiben. Der Betrag wird Ihnen gutgeschrieben: 1,50 EUR.");
    }

    #[test]
    fn a_question_that_promises_payment_is_a_question() {
        assert_eq!(out("Zur Bearbeitung benötigen wir noch eine Kopie Ihres Tickets. Nach Eingang überweisen wir Ihnen 1,50 EUR."), MailOutcome::Question);
    }

    #[test]
    fn a_conditional_or_hypothetical_payment_is_not_paid() {
        assert_ne!(out("Sofern Ihr Ticket gültig war, überweisen wir Ihnen 1,50 EUR."), MailOutcome::Accepted);
        assert_ne!(out("Hätte die Verspätung 60 Minuten betragen, hätten wir Ihnen 1,50 EUR überwiesen."), MailOutcome::Accepted);
    }

    #[test]
    fn a_minimum_payout_refusal_is_not_a_payment_of_the_threshold() {
        assert_ne!(out("Ihre Entschädigung beträgt 1,50 EUR. Beträge unter 4,00 EUR zahlen wir nicht aus."), MailOutcome::Accepted);
        assert_ne!(out("Eine Entschädigung von 1,50 EUR kommt daher nicht in Betracht."), MailOutcome::Accepted);
    }

    #[test]
    fn footers_and_whole_words_do_not_block_a_payment() {
        let pay = "Wir haben eine Entschädigung von 1,50 EUR festgestellt. Der Betrag wird auf das angegebene Konto überwiesen. Für die Rückfahrt überweisen wir ebenfalls nichts Weiteres.";
        let footer = "\n\nFür Rückfragen stehen wir Ihnen gerne zur Verfügung.\n\nMit freundlichen Grüßen\nIhr Servicecenter\n\nMit dem DB Gutschein schenken Sie Reisezeit. Ihre Daten werden nicht an Dritte weitergeleitet. Bitte antworten Sie nicht auf diese E-Mail.";
        let r = read("a@b.invalid", "x", &format!("{}{footer}", &pay[..pay.find(" Für die Rückfahrt").unwrap()]));
        assert_eq!((r.outcome, r.amount_cents), (MailOutcome::Accepted, Some(150)));
        assert!(!conditional("Für die Rückfahrt überweisen wir ebenfalls 1,50 EUR."));
        assert!(!conditional("Nach Eingang Ihres Antrags haben wir die Fahrten geprüft und überweisen 3,00 EUR."));
        assert!(conditional("Nach Eingang Ihrer Kopie überweisen wir 1,50 EUR."));
        assert_eq!(out("Nach erneuter Prüfung überweisen wir Ihnen 1,50 EUR auf das angegebene Konto."), MailOutcome::Accepted);
        assert_eq!(out("Wir überweisen Ihnen 1,50 EUR. Hierfür benötigen wir keine weiteren Unterlagen."), MailOutcome::Accepted);
    }

    /// The three answers `stellwerk reply` plants (admin.rs). They are read by the rules alone, and
    /// the end-to-end test waits for exactly these outcomes.
    #[test]
    fn the_stellwerk_answers_read_as_they_say() {
        let name = "Johannes Fritsch";
        let accepted = format!("Sehr geehrte/r {name},\n\nvielen Dank für Ihren Antrag. Wir haben die angegebenen Fahrten geprüft und eine Entschädigung von insgesamt 4,50 EUR festgestellt.\n\nDer Betrag wird auf das angegebene Konto überwiesen:\nKontoinhaber: Bahnhofsmission Köln\n\nMit freundlichen Grüßen\nIhr Servicecenter Fahrgastrechte");
        let question = format!("Sehr geehrte/r {name},\n\nzur Bearbeitung Ihres Antrags benötigen wir noch eine Kopie Ihres Tickets für den betroffenen Monat. Bitte senden Sie diese als Antwort auf diese E-Mail.\n\nMit freundlichen Grüßen\nIhr Servicecenter Fahrgastrechte");
        let rejected = format!("Sehr geehrte/r {name},\n\nleider können wir Ihrem Antrag nicht entsprechen. Die Verspätung beruhte auf außergewöhnlichen Umständen (Unwetter), für die nach VO (EU) 2021/782 Art. 19 Abs. 10 keine Entschädigung geleistet wird.\n\nMit freundlichen Grüßen\nIhr Servicecenter Fahrgastrechte");
        let r = read("x@servicecenter.invalid", "Ihr Antrag", &accepted);
        assert_eq!((r.outcome, r.amount_cents, r.stop, r.conditional_payment), (MailOutcome::Accepted, Some(450), None, false));
        assert_eq!(read("x@servicecenter.invalid", "Ihr Antrag", &question).outcome, MailOutcome::Question);
        assert_eq!(read("x@servicecenter.invalid", "Ihr Antrag", &rejected).outcome, MailOutcome::Rejected);
    }

    #[test]
    fn footers_advice_and_salutations_stop_nothing() {
        for footer in [
            "Ihre personenbezogenen Daten werden ausschließlich zur Bearbeitung Ihres Antrags verwendet und nicht an Dritte weitergegeben.",
            "Tipp: Fahrgastrechte-Anträge können Sie künftig auch online in Ihrem Kundenkonto auf bahn.de stellen.",
            "DB Gutscheine im Wert von 10 bis 250 Euro.",
            "Nutzen Sie für Ihre nächsten Anträge unser Kundenportal.",
            "Sehr geehrte Antragstellerin, sehr geehrter Antragsteller,",
            "Die Entschädigung von insgesamt 3,00 EUR wurde bereits angewiesen und wird in den nächsten Tagen auf das angegebene Konto überwiesen.",
        ] {
            assert_eq!(stop(footer), None, "{footer}");
        }
    }

    #[test]
    fn a_wrapped_line_keeps_its_condition_negation_and_voucher() {
        assert!(read("a@b.invalid", "x", "Sofern die Prüfung ergibt, dass Ihr Ticket gültig war,\nüberweisen wir Ihnen insgesamt 3,00 EUR.").conditional_payment);
        assert_ne!(out("Vorbehaltlich\neiner abschließenden Prüfung überweisen wir eine\nEntschädigung von insgesamt 3,00 EUR."), MailOutcome::Accepted);
        assert_ne!(out("Den Betrag von 3,00 EUR haben wir nicht\nüberwiesen."), MailOutcome::Accepted);
        assert_eq!(stop("Wir gewähren 3,00 EUR, die wir Ihnen als\nGutschein zusenden."), Some("a voucher, not money"));
        assert_eq!(stop("Wir überweisen Ihnen 1,50 EUR auf die bei uns\nhinterlegte Bankverbindung."), Some("paid to someone other than the Verein"));
        assert!(read("a@b.invalid", "x", "Wir überweisen 3,00 EUR.\n\nMit freundlichen Grüßen\nX\n\nHinweis zur Auszahlung: Wir überweisen den Betrag erst, sobald die Bankverbindung bestätigt ist.").conditional_payment);
        assert!(conditional("Nach Vorlage des Originaltickets überweisen wir Ihnen 3,00 EUR."));
        assert!(conditional("Ihrer Bitte wird nach Abschluss der Prüfung Ihrer Fahrtdaten entsprochen."));
        assert!(!conditional("Nach Abschluss der Prüfung haben wir Ihnen 3,00 EUR überwiesen."));
    }

    #[test]
    fn stops_count_wherever_they_stand_but_only_where_money_is_talked_about() {
        // Below a cover note's signature: still the desk's word.
        assert_eq!(stop("Anbei unser Bescheid.\n\nMit freundlichen Grüßen\nIhr Servicecenter\n\nBescheid: Eine Auszahlung an Dritte ist ausgeschlossen."), Some("paid to someone other than the Verein"));
        // A privacy footer and a marketing line: not about this claim's money.
        assert_eq!(stop("Ihre Daten werden nicht an Dritte weitergegeben.\n\nMit dem DB Gutschein schenken Sie Reisezeit."), None);
        assert_eq!(stop("Wir überweisen Ihnen insgesamt 3,00 EUR. Das Geld geht an Sie persönlich."), Some("paid to someone other than the Verein"));
        assert_eq!(stop("Die Entschädigung überweisen wir auf das Konto des Antragstellers."), Some("paid to someone other than the Verein"));
        assert_eq!(stop("Die Überweisung erfolgt auf Ihre Bankverbindung laut Kundenkonto."), Some("paid to someone other than the Verein"));
        assert!(conditional("Unter Vorbehalt überweisen wir Ihnen 1,50 EUR."));
        assert!(conditional("Sollte Ihr Ticket gültig sein, überweisen wir 1,50 EUR."));
    }

    #[test]
    fn many_negated_phrases_read_in_linear_time() {
        let body = "keine überwiesen ".repeat(20_000);
        let started = std::time::Instant::now();
        let _ = read("a@b.invalid", "x", &body);
        assert!(started.elapsed() < std::time::Duration::from_secs(3), "took {:?}", started.elapsed());
    }

    #[test]
    fn a_payment_negated_after_the_verb_is_not_one() {
        assert_ne!(out("In Höhe von insgesamt 3,00 EUR überweisen wir Ihnen, anders als erwartet, nicht."), MailOutcome::Accepted);
        assert_ne!(out("Keinerlei Entschädigung überweisen wir Ihnen."), MailOutcome::Accepted);
        assert_ne!(out("Die Beträge von 1,50 EUR überweisen wir Ihnen nicht."), MailOutcome::Accepted);
        assert_eq!(out("Beträge unter 4,00 EUR zahlen wir nicht aus."), MailOutcome::Rejected);
    }

    #[test]
    fn money_paid_before_or_to_the_passenger_is_not_this_claims() {
        assert_eq!(read("a@b.invalid", "x", "Die Fahrpreisentschädigung von 1,50 EUR wurde bereits am 10.09.2026 auf Ihr Konto ausgezahlt.").because, "paid or filed before");
        assert_eq!(read("a@b.invalid", "x", "Eine Auszahlung an Dritte ist nicht möglich. Wir haben 1,50 EUR auf Ihr Girokonto überwiesen.").because, "paid to someone other than the Verein");
        assert!(read("a@b.invalid", "x", "Sofern Ihr Ticket gültig war, überweisen wir Ihnen 1,50 EUR.").conditional_payment);
    }

    #[test]
    fn vouchers_duplicates_and_forwarding_are_not_decisions() {
        assert_eq!(read("a@b.invalid", "x", "Wir gewähren eine Entschädigung in Höhe von 10,00 EUR in Form eines Reisegutscheins.").because, "a voucher, not money");
        assert_eq!(read("a@b.invalid", "x", "Die Entschädigung von 1,50 EUR wurde bereits ausgezahlt. Eine erneute Entschädigung ist nicht möglich.").because, "paid or filed before");
        assert_eq!(read("a@b.invalid", "x", "Leider können wir Ihrem Antrag nicht entsprechen, da wir nicht zuständig sind. Wir haben ihn weitergeleitet.").because, "passed to another desk");
        // Forwarding inside the company is not passing the claim on.
        assert_eq!(out("Ihre Bankverbindung haben wir an die Buchhaltung weitergeleitet. Wir überweisen Ihnen 1,50 EUR."), MailOutcome::Accepted);
    }

    #[test]
    fn the_amount_comes_from_the_sentence_that_pays() {
        // The claimed figure restated in another sentence is not what is paid.
        let r = read("a@b.invalid", "x", "Beantragt wurde eine Entschädigung in Höhe von 4,50 EUR. Den Betrag überweisen wir Ihnen in Kürze.");
        assert_eq!(r.outcome, MailOutcome::Other);
    }

    #[test]
    fn huge_figures_are_not_money_and_do_not_overflow() {
        assert_eq!(money_figures("184467440737095518 EUR"), Vec::<i64>::new());
        assert_eq!(parse_amount("184467440737095518,00"), None);
    }

    #[test]
    fn english_decimals_and_thin_spaces_are_money() {
        assert_eq!(money_figures("compensation of EUR 2.20 will be transferred"), vec![220]);
        assert_eq!(money_figures("1,50\u{2009}EUR"), vec![150]);
        assert_eq!(money_figures("2.200 EUR"), vec![220000]);
    }

    #[test]
    fn money_is_recognised_with_the_currency_on_either_side() {
        assert_eq!(money_figures("4,50 EUR und EUR 1,50 und €2,00 und 3 Euro und 5,- € und 1.234,56 EUR"), vec![450, 150, 200, 300, 500, 123456]);
    }

    #[test]
    fn dates_case_numbers_and_words_are_not_money() {
        assert_eq!(money_figures("am 3.9.2026 um 12,30 Uhr, Vorgang 2026-09-4723683, RE5 Europa 4 Europäer"), Vec::<i64>::new());
    }

    #[test]
    fn a_model_amount_parses_with_or_without_currency() {
        assert_eq!(parse_amount("7,25 EUR"), Some(725));
        assert_eq!(parse_amount("7,25"), Some(725));
        assert_eq!(parse_amount("7.25"), Some(725));
        assert_eq!(parse_amount("12"), Some(1200));
        assert_eq!(parse_amount("ungefähr sieben"), None);
    }

    #[test]
    fn nothing_recognised_stays_other() {
        assert_eq!(out("Guten Tag, wie besprochen. Mit freundlichen Grüßen"), MailOutcome::Other);
    }
}
