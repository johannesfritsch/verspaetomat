//! What leaves the server when a model reads a desk's reply.
//!
//! The reply is a passenger's correspondence with a railway. To decide whether the desk pays, a
//! reader needs the desk's sentences and nothing about the person: not their name, not where they
//! live, not their e-mail address or ticket number. So before any text goes to a model it loses:
//!
//! 1. **The quoted history.** A desk answers on top of our claim mail, which carries the
//!    passenger's name, address and every ride. The history is also the wrong text to read: it is
//!    our words, not the desk's decision.
//! 2. **Everything we know belongs to the passenger**, straight from their customer row — matched
//!    exactly, and the name also word by word, because a desk writes "Sehr geehrter Herr Fritsch".
//! 3. **Anything shaped like contact or bank data**: e-mail addresses, IBANs, phone numbers.
//!
//! Money and dates stay: they are what the decision is made of, and neither identifies anybody.
//! Placeholders are in German brackets so the model can see that something was there.

use regex::Regex;
use std::sync::LazyLock;

/// Personal data this passenger has given us.
#[derive(Debug, Default, Clone)]
pub struct Known {
    pub name: Option<String>,
    pub postal_address: Option<String>,
    pub email: Option<String>,
    pub ticket_number: Option<String>,
    /// The relay and reply addresses mail to this passenger goes through.
    pub addresses: Vec<String>,
    /// The mails we sent for this passenger — the claim and any reply written in the app. Their
    /// words are removed from an answer before anything reads it (see [`without_ours`]).
    pub sent: Vec<String>,
    /// The payee named in the claim: the Verein's account holder. Not personal data, and not
    /// redacted — a reader has to recognise it as the one who is meant to be paid.
    pub payee: Option<String>,
}

/// Longest text a model is shown. A desk's decision fits in a few lines; anything this long is a
/// newsletter or a pasted attachment. A cut text is marked with [`CUT`] and can never pay.
pub const MAX_CHARS: usize = 8_000;

/// Put at the end of a text that was cut at [`MAX_CHARS`]. `reply.rs` never lets a cut text pay:
/// the sentence that makes a payment conditional may be the one that was cut.
pub const CUT: &str = "[gekürzt]";

static EMAIL: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)[\p{L}\p{N}._%+\-]+\s*(?:@|[\(\[]\s*at\s*[\)\]])\s*[\p{L}\p{N}\-]+(?:(?:\.|\s*[\(\[]\s*dot\s*[\)\]]\s*)[\p{L}\p{N}\-]+)+").unwrap()
});
/// "jw1980 at gmx dot de": both words, or it is English prose.
static EMAIL_WORDS: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)\b[\p{L}\p{N}._%+\-]+\s+at\s+[\p{L}\p{N}\-]+\s+dot\s+\p{L}{2,}\b").unwrap());
/// Two letters, two digits, then groups of four — in any case, separated by spaces, dashes or a line
/// break, as a plain-text mail wraps it. Replaced only as far as it checks out (see [`iban_ok`]).
static IBAN: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\b[a-z]{2}\d{2}(?:[ \t\u{a0}\u{202f}\-]*(?:\r?\n)?[ \t\u{a0}\u{202f}]*[a-z0-9]{4}){2,7}(?:[ \t\u{a0}\u{202f}\-]*[a-z0-9]{1,4})?\b").unwrap()
});
static PHONE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?:\(\s*)?(?:\+|\b0)\d[\d ./()\-\u{2013}\u{a0}\u{202f}]{6,}\d").unwrap());
/// A date anywhere inside a would-be phone number: "03.09.2026 1,50 EUR" is a date and an amount.
static DATE_INSIDE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\d{1,2}\.\d{1,2}\.\d{2,4}").unwrap());
static BIRTH_DATE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\b(geb\.|geboren(?:\s+am)?|geburtsdatum:?)\s*\d{1,2}\.\s*(?:\d{1,2}\.|\p{L}+)\s*\d{2,4}").unwrap()
});
static BAHNCARD: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\b7081[ \-\u{a0}]?\d{4}[ \-\u{a0}]?\d{4}[ \-\u{a0}]?\d{4}\b").unwrap());
static CUSTOMER_NO: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\b(kunden-?nummer|kundennr\.?|kd\.?-?nr\.?|abo-?nr\.?|abonummer|vertragsnummer|bahncard-?nummer)(\s*:?\s*)[a-z0-9][a-z0-9 \-]{3,20}[a-z0-9]\b").unwrap()
});
/// "Am 3. September 2026 um 12:00 schrieb …:" / "On … wrote:" — the line a mail client puts above a
/// quote, sometimes wrapped so the colon lands on the next line.
static QUOTE_INTRO: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)^(am|on)\s.{4,200}\s(schrieb|wrote)\b.{0,120}:\s*$").unwrap());
static QUOTE_INTRO_START: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)^(am|on)\s.{4,200}\s(schrieb|wrote)\b").unwrap());
/// Where a ticket system echoes what the passenger wrote: "Ihre Nachricht an uns:", "Ihre Anfrage:",
/// "----- Ihre Nachricht -----".
static ECHO: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)^[\-_=\s]*(ihre (nachricht|anfrage|e-mail|mail)|ihr anliegen|nachricht des kunden|kundennachricht|your (message|request))\b(\s+(vom|an uns|from)\b.{0,40})?\s*(:|[\-_=]{3,})?\s*$").unwrap()
});
/// A name after a title, found by its shape: "Herr Fritsch", "Sehr geehrte*r Johannes Fritsch",
/// "Frau Prof. Dr. med. von der Heide", "Dear Mr Fritsch", "HERR FRITSCH". The customer row covers
/// the name we know; this covers the one we do not, or know spelt differently. Lead words match in
/// any case; the name starts with a capital. Only "Herr"/"Frau" may have the name on the next line,
/// as an address block does.
static SALUTATION: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?P<lead>(?i:\b(?:herrn?|frau)\s+)|(?i:\b(?:mr\.?|mrs\.?|ms\.?)[ \t]+)|(?i:\bsehr[ \t]+geehrte(?:/r|\*r|:r|_r|\(r\)|r)?[ \t]+(?:(?:herrn?|frau)[ \t]+)?))(?P<title>(?i:(?:prof|dr|med|dent|rer\.?[ \t]*nat|ing|mag|dipl\.?-?\p{L}+)\.?[ \t]+)*)(?P<particles>(?:(?:von|van|de|der|den|zu|zur|vom|dem|di|da|du|le|la)[ \t]+)*)(?P<name>\p{Lu}[\p{L}'’\-]+(?:[ \t]+\p{Lu}[\p{L}'’\-]+){0,2})",
    )
    .unwrap()
});
/// A name after a plain greeting — "Hallo Johannes Fritsch," — only when the line ends or a comma
/// follows it. Without that, "Guten Tag Keinerlei Entschädigung überweisen wir" loses its negation
/// and "Guten Tag Unter Vorbehalt …" its condition, and a refusal reads as a payment.
static GREETING: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?m)(?P<lead>(?i:\b(?:guten[ \t]+tag|hallo|liebe[rs]?|dear))[ \t]+)(?P<name>\p{Lu}[\p{L}'’\-]+(?:[ \t]+\p{Lu}[\p{L}'’\-]+){0,2})(?P<end>[ \t]*(?:[,!:\u{2013}\u{2014}\-]|$))").unwrap()
});
/// Words that look like a name in a salutation and are not one: titles, and the capitalised words a
/// German sentence starts with.
const NOT_A_NAME: &[&str] = &[
    "Herr", "Herrn", "Frau", "Damen", "Dr", "Prof", "Mr", "Mrs", "Ms", "Kunde", "Kundin", "Fahrgast", "Fahrgäste", "Sir", "Madam", "Ihre", "Ihr", "Ihren", "Ihrem",
    "Keine", "Kein", "Leider", "Wir", "Für", "Die", "Der", "Das", "Nicht", "Nach", "Sofern", "Falls", "Wenn", "Bitte", "Vielen", "Danke", "Anbei", "Zu", "Zur", "Im", "In", "Am",
    "Mit", "Eine", "Ein", "Es", "Sie", "Auf", "Aus", "Bei", "Da", "Dass", "Gerne", "Unser", "Unsere", "Hiermit", "Aufgrund", "Wie", "Vom", "Zum",
];
/// Name particles: part of a full name, never replaced on their own ("eine Entschädigung von 1,50 EUR").
const PARTICLES: &[&str] = &["von", "van", "de", "der", "den", "zu", "zur", "vom", "dem", "di", "da", "du", "le", "la", "und"];
/// Lines of an Outlook header block after "Von:". Not "An:" or "Datum:" alone: a ride table has those.
static HEADER_LINE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)^(gesendet|sent|betreff|subject)\s*:").unwrap());
static POSTCODE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\b\d{5}\b").unwrap());
static STREET: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)^(?P<stem>.+?)(?:straße|strasse|str\.?)\s*(?P<no>\d+\s*[a-z]?)?$").unwrap());

/// An answer without the words we sent.
///
/// Every line of the answer that is text from a mail we sent — the claim, or a reply the passenger
/// wrote in the app — is dropped, however the desk's system quoted, echoed, re-wrapped or retyped
/// it. Nothing the desk wrote itself is lost, because nothing the desk wrote itself is in our mail;
/// and nothing the passenger wrote can pass for the desk's decision, because everything the
/// passenger sends through us is in our mail.
///
/// Compared after normalising (case, umlauts, "€"/"EUR", punctuation, hyphenation), and by word
/// overlap rather than equality: a line counts as ours when most of its three-word runs are ours, so
/// changing a word or a currency sign does not bring our text back as the desk's. Short lines count
/// when they are ours as a whole. Greetings stay: they are in every mail and mark where a decision
/// ends.
///
/// This only ever removes text a reader would otherwise believe. The vetoes read the original.
pub fn without_ours(body: &str, sent: &[String]) -> String {
    if sent.is_empty() {
        return body.to_string();
    }
    let ours_text = sent.iter().map(|m| normalise_words(m)).collect::<Vec<_>>().join(" | ");
    let ours_words: Vec<&str> = ours_text.split(' ').filter(|w| !w.is_empty()).collect();
    let ours_grams: std::collections::HashSet<String> = ours_words.windows(3).map(|w| w.join(" ")).collect();
    body.lines()
        .filter(|line| {
            let stripped = line.trim_start_matches(|c: char| c == '>' || c.is_whitespace());
            if GREETING_LINE.is_match(stripped) {
                return true;
            }
            let norm = normalise_words(stripped);
            let words: Vec<&str> = norm.split(' ').filter(|w| !w.is_empty()).collect();
            if words.len() >= 6 {
                let grams: Vec<String> = words.windows(3).map(|w| w.join(" ")).collect();
                let shared = grams.iter().filter(|g| ours_grams.contains(*g)).count();
                shared * 10 < grams.len() * 6
            } else {
                norm.chars().count() < 12 || !ours_text.contains(&norm)
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

/// Lower case, umlauts and ß spelled out, "€" as "eur", everything but letters and digits a space.
fn normalise_words(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars().flat_map(|c| c.to_lowercase()) {
        match c {
            'ä' => out.push_str("ae"),
            'ö' => out.push_str("oe"),
            'ü' => out.push_str("ue"),
            'ß' => out.push_str("ss"),
            '€' => out.push_str(" eur "),
            // "Ausfüll-\nund" and "Ausfüll- und" are the same words.
            '-' | '\u{2010}' | '\u{00ad}' => {}
            c if c.is_alphanumeric() => out.push(c),
            _ => out.push(' '),
        }
    }
    format!(" {out} ").replace(" euro ", " eur ").split_whitespace().collect::<Vec<_>>().join(" ")
}

static GREETING_LINE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)^\s*(mit freundlichen grü(ß|ss)en|mit freundlichem gru(ß|ss)|freundliche grü(ß|ss)e|viele grü(ß|ss)e|beste grü(ß|ss)e|sehr geehrte|guten tag|hallo|kind regards|best regards)").unwrap()
});

/// A line naming the passenger as the one who is paid: "Zahlungsempfänger: Jürgen Weiß",
/// "Kontoinhaber: J. Weiss". Read before redaction, because after it the model sees "[Name]" and
/// cannot tell the passenger from the Verein.
pub fn names_passenger_as_payee(text: &str, known: &Known) -> bool {
    let Some(name) = &known.name else { return false };
    let words: Vec<String> = name
        .split(|c: char| !c.is_alphabetic() && c != '\'' && c != '’')
        .filter(|w| w.chars().count() >= 3 && !PARTICLES.contains(&w.to_lowercase().as_str()))
        .map(|w| format!(r"(?i)(^|[^\p{{L}}]){}([^\p{{L}}]|$)", spelling(w)))
        .collect();
    let patterns: Vec<Regex> = words.iter().filter_map(|w| Regex::new(w).ok()).collect();
    text.lines().any(|line| PAYEE_LINE.is_match(line) && patterns.iter().any(|p| p.is_match(line)))
}

static PAYEE_LINE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\b(zahlungsempfänger(in)?|empfänger(in)?|kontoinhaber(in)?|begünstigte[rn]?|auszahlung an|überweisung an|zahlung an)\b").unwrap()
});

/// The part of a mail its sender wrote now: everything above the quoted history.
///
/// Cuts at the first separator a mail client writes above a quote, and drops "> " lines wherever
/// they are. A desk that answers *below* the quote loses its answer here, and the model then reads
/// nothing decisive — which ends as "a human should read this", the safe way to be wrong.
///
/// This is what the vetoes read (stops, conditions): our own quoted claim is not the desk's word,
/// but everything else the desk sent is, wherever in the mail it stands.
pub fn unquoted(body: &str) -> String {
    cut(body, false)
}

/// What a reader decides on: [`unquoted`], and also without a ticket system's echo of the
/// passenger's own message ("Ihre Nachricht an uns:") — text the passenger wrote, however much it
/// reads like the desk paying.
pub fn latest(body: &str) -> String {
    cut(body, true)
}

fn cut(body: &str, echoes: bool) -> String {
    let lines: Vec<&str> = body.lines().collect();
    let mut kept = Vec::new();
    for (n, line) in lines.iter().enumerate() {
        let t = line.trim();
        let lower = t.to_lowercase();
        if lower.contains("ursprüngliche nachricht") || lower.contains("original message") || lower.contains("weitergeleitete nachricht") || lower.contains("forwarded message") {
            break;
        }
        if QUOTE_INTRO.is_match(t) || (QUOTE_INTRO_START.is_match(t) && lines.get(n + 1).is_some_and(|next| next.trim().ends_with(':'))) {
            break;
        }
        if echoes && ECHO.is_match(t) {
            break;
        }
        // An Outlook-style block: "Von: …" followed by "Gesendet: …" / "Betreff: …".
        if (lower.starts_with("von:") || lower.starts_with("from:")) && lines.iter().skip(n + 1).take(4).any(|l| HEADER_LINE.is_match(l.trim())) {
            break;
        }
        if t.starts_with('>') {
            continue;
        }
        kept.push(*line);
    }
    kept.join("\n").trim().to_string()
}

/// The text a model is shown: subject and the sender's own part of the body, with the passenger
/// taken out.
pub fn for_model(subject: &str, body: &str, known: &Known) -> String {
    let text = format!("Betreff: {}\n\n{}", subject.trim(), latest(body));
    let mut text = scrub(&text, known);
    if let Some((cut, _)) = text.char_indices().nth(MAX_CHARS) {
        text.truncate(cut);
        text.push('\n');
        text.push_str(CUT);
    }
    text
}

/// A regex for one word as a desk might spell it: umlauts or their two-letter forms, ß or ss, either
/// apostrophe, any case.
fn spelling(word: &str) -> String {
    let chars: Vec<char> = word.chars().flat_map(|c| c.to_lowercase()).collect();
    let mut out = String::new();
    let mut i = 0;
    while i < chars.len() {
        let pair: String = chars[i..(i + 2).min(chars.len())].iter().collect();
        let (piece, used) = match (chars[i], pair.as_str()) {
            (_, "ae") => ("(?:ae|ä)".to_string(), 2),
            (_, "oe") => ("(?:oe|ö)".to_string(), 2),
            (_, "ue") => ("(?:ue|ü)".to_string(), 2),
            (_, "ss") => ("(?:ss|ß)".to_string(), 2),
            // "Jürgen" also reaches a desk's system as "Juergen" and as "Jurgen".
            ('ä', _) => ("(?:ä|ae|a)".to_string(), 1),
            ('ö', _) => ("(?:ö|oe|o)".to_string(), 1),
            ('ü', _) => ("(?:ü|ue|u)".to_string(), 1),
            ('ß', _) => ("(?:ß|ss|sz)".to_string(), 1),
            ('\'' | '’', _) => ("['’]".to_string(), 1),
            (c, _) if c.is_whitespace() => (r"\s+".to_string(), 1),
            (c, _) => (regex::escape(&c.to_string()), 1),
        };
        out.push_str(&piece);
        i += used;
    }
    out
}

fn replace_pattern(hay: &str, pattern: &str, with: &str) -> String {
    match Regex::new(pattern) {
        Ok(re) => re.replace_all(hay, regex::NoExpand(with)).into_owned(),
        Err(_) => hay.to_string(),
    }
}

/// The longest start of `raw` that checks out as an IBAN, replaced; the rest kept. The pattern is
/// greedy — "AT61 1904 3002 3457 3201 Bitte" takes "Bitt" as a fifth group — so the checksum decides
/// where the IBAN ends.
fn iban_prefix(raw: &str) -> String {
    let alnum: Vec<(usize, char)> = raw.char_indices().filter(|(_, c)| c.is_ascii_alphanumeric()).collect();
    for len in (15..=alnum.len().min(34)).rev() {
        let (last_at, last) = alnum[len - 1];
        let end = last_at + last.len_utf8();
        if iban_ok(&raw[..end]) {
            return format!("[IBAN]{}", &raw[end..]);
        }
    }
    raw.to_string()
}

/// Mod-97 over the compacted value, as banks check it.
fn iban_ok(raw: &str) -> bool {
    let compact: String = raw.chars().filter(|c| c.is_ascii_alphanumeric()).collect::<String>().to_uppercase();
    if !(15..=34).contains(&compact.len()) {
        return false;
    }
    let rotated = format!("{}{}", &compact[4..], &compact[..4]);
    let mut rem: u32 = 0;
    for c in rotated.chars() {
        let v = if c.is_ascii_digit() { c as u32 - '0' as u32 } else { c as u32 - 'A' as u32 + 10 };
        rem = if v >= 10 { (rem * 100 + v) % 97 } else { (rem * 10 + v) % 97 };
    }
    rem == 1
}

fn scrub(text: &str, known: &Known) -> String {
    let mut out = text.to_string();
    // Whole known values first, longest first, so a full address goes before its parts.
    let mut whole: Vec<(String, &str)> = Vec::new();
    for a in known.addresses.iter().chain(&known.email) {
        whole.push((regex::escape(a.trim()), "[E-Mail]"));
    }
    if let Some(t) = &known.ticket_number {
        // Letters and digits only, joined by whatever separator the desk's system prints — and the
        // digits alone, which is how an "Abo-Nr." often shows it.
        let sep = r"[\s\-\u{2013}_./]*";
        let core: Vec<String> = t.chars().filter(|c| c.is_alphanumeric()).map(|c| regex::escape(&c.to_string())).collect();
        if core.len() >= 6 {
            whole.push((core.join(sep), "[Ticketnummer]"));
        }
        let digits: Vec<String> = t.chars().filter(|c| c.is_ascii_digit()).map(|c| c.to_string()).collect();
        if digits.len() >= 6 && digits.len() < core.len() {
            whole.push((format!(r"\b{}\b", digits.join(sep)), "[Ticketnummer]"));
        }
    }
    if let Some(a) = &known.postal_address {
        // Split at line breaks, commas and the postcode, so "Musterstraße 12 50667 Köln" typed on one
        // line still yields its street. Only parts with a house number are taken: the city stays,
        // because it is also every station in it ("Köln Hbf") and identifies nobody.
        let marked = POSTCODE.replace_all(a, "\n$0\n");
        for part in marked.split([',', '\n', ';']).map(str::trim).filter(|p| p.chars().count() >= 4 && p.chars().any(|c| c.is_ascii_digit()) && !POSTCODE.is_match(p)) {
            match STREET.captures(part) {
                Some(c) => {
                    let stem = spelling(c["stem"].trim_end());
                    whole.push((format!(r"{stem}(?:straße|strasse|str\.?)\s*{}", c.name("no").map(|n| spelling(n.as_str().trim())).unwrap_or_default()), "[Anschrift]"));
                    // The street on its own, as a form with a separate house-number field prints it.
                    if c["stem"].chars().filter(|ch| ch.is_alphabetic()).count() >= 4 {
                        whole.push((format!(r"{stem}(?:straße|strasse|str\.?)"), "[Anschrift]"));
                    }
                }
                None => whole.push((spelling(part), "[Anschrift]")),
            }
        }
    }
    if let Some(n) = &known.name {
        let words: Vec<&str> = n.split(|c: char| !c.is_alphabetic() && c != '\'' && c != '’').filter(|w| !w.is_empty()).collect();
        if words.len() >= 2 {
            // "Johannes Fritsch" and "Fritsch, Johannes".
            whole.push((words.iter().map(|w| spelling(w)).collect::<Vec<_>>().join(r"[\s,]+"), "[Name]"));
            let (last, first) = words.split_last().unwrap();
            whole.push((format!(r"{}\s*,?\s*{}", spelling(last), first.iter().map(|w| spelling(w)).collect::<Vec<_>>().join(r"\s+")), "[Name]"));
        }
    }
    whole.sort_by_key(|(v, _)| std::cmp::Reverse(v.len()));
    for (pattern, placeholder) in whole {
        out = replace_pattern(&out, &format!("(?i){pattern}"), placeholder);
    }
    // The name and the postcode word by word: a desk writes "Herr Fritsch", not the full name. The
    // edges are "not a letter" rather than a word boundary, so "Bescheid_WEISS_JUERGEN.pdf" and
    // "?name=Juergen%20Weiss" lose it too; twice, because neighbours share an edge.
    if let Some(n) = &known.name {
        for word in n.split(|c: char| !c.is_alphabetic() && c != '\'' && c != '’') {
            if word.chars().filter(|c| c.is_alphabetic()).count() >= 3 && !PARTICLES.contains(&word.to_lowercase().as_str()) {
                let pattern = format!(r"(?i)(?P<pre>^|[^\p{{L}}]){}(?P<post>[^\p{{L}}]|$)", spelling(word));
                if let Ok(re) = Regex::new(&pattern) {
                    for _ in 0..2 {
                        out = re.replace_all(&out, "${pre}[Name]${post}").into_owned();
                    }
                }
            }
        }
    }
    if let Some(a) = &known.postal_address {
        for code in POSTCODE.find_iter(a) {
            out = replace_pattern(&out, &format!(r"\b{}\b", code.as_str()), "[Anschrift]");
        }
    }
    let not_a_name = |name: &str| {
        let first = name.split(|ch: char| !ch.is_alphabetic()).next().unwrap_or("");
        NOT_A_NAME.iter().any(|n| n.eq_ignore_ascii_case(first))
    };
    out = SALUTATION
        .replace_all(&out, |c: &regex::Captures| if not_a_name(&c["name"]) { c[0].to_string() } else { format!("{}{}[Name]", &c["lead"], &c["title"]) })
        .into_owned();
    out = GREETING
        .replace_all(&out, |c: &regex::Captures| if not_a_name(&c["name"]) { c[0].to_string() } else { format!("{}[Name]{}", &c["lead"], &c["end"]) })
        .into_owned();
    out = EMAIL.replace_all(&out, "[E-Mail]").into_owned();
    out = EMAIL_WORDS.replace_all(&out, "[E-Mail]").into_owned();
    out = BIRTH_DATE.replace_all(&out, "$1 [Geburtsdatum]").into_owned();
    out = BAHNCARD.replace_all(&out, "[BahnCard]").into_owned();
    out = CUSTOMER_NO.replace_all(&out, "$1$2[Kundennummer]").into_owned();
    out = IBAN.replace_all(&out, |c: &regex::Captures| iban_prefix(&c[0])).into_owned();
    // A phone number has at least eight digits and does not continue something else: the "09-…"
    // inside the case number "2026-09-4723683" looks like a number starting with 0 on its own. A
    // dot before it continues a number only after a digit ("1.0221…"), not after "Tel.".
    let mut phoned = String::with_capacity(out.len());
    let mut last = 0;
    for m in PHONE.find_iter(&out) {
        let mut before = out[..m.start()].chars().rev();
        let continues = match before.next() {
            Some(ch) if ch.is_ascii_digit() || matches!(ch, '-' | ',' | '/') => true,
            Some('.') => before.next().is_some_and(|ch| ch.is_ascii_digit()),
            _ => false,
        };
        if !continues && !DATE_INSIDE.is_match(m.as_str()) && m.as_str().chars().filter(|ch| ch.is_ascii_digit()).count() >= 8 {
            phoned.push_str(&out[last..m.start()]);
            phoned.push_str("[Telefon]");
            last = m.end();
        }
    }
    phoned.push_str(&out[last..]);
    phoned
}

#[cfg(test)]
mod tests {
    use super::*;

    fn johannes() -> Known {
        Known {
            name: Some("Johannes Fritsch".into()),
            postal_address: Some("Musterstraße 12, 50667 Köln".into()),
            email: Some("j@example.org".into()),
            ticket_number: Some("DT-4711-0815".into()),
            addresses: vec!["antrag-1a2b3c4d@users.verspaetomat.de".into()],
            sent: vec![],
            payee: None,
        }
    }

    #[test]
    fn the_passenger_is_taken_out_and_the_money_stays() {
        let body = "Sehr geehrter Herr Fritsch,\n\nfür Ihre Fahrt am 3.9. überweisen wir 4,50 EUR auf das Konto DE89 3704 0044 0532 0130 00.\nRückfragen unter 0221 12345678 oder j@example.org.\nIhre Ticketnummer DT-4711-0815, Anschrift Musterstraße 12, 50667 Köln.";
        let shown = for_model("Ihr Antrag, Johannes Fritsch", body, &johannes());
        for gone in ["Fritsch", "Johannes", "DE89", "12345678", "j@example.org", "DT-4711", "Musterstraße", "50667"] {
            assert!(!shown.contains(gone), "{gone} leaked into: {shown}");
        }
        assert!(shown.contains("4,50 EUR"));
        assert!(shown.contains("3.9."));
        assert!(shown.contains("Herr [Name]"));
    }

    #[test]
    fn the_quoted_claim_is_not_shown() {
        let body = "Wir überweisen 4,50 EUR.\n\nAm 3. September 2026 um 12:00 schrieb Verspätomat <antrag-1a2b3c4d@users.verspaetomat.de>:\n> Name: Johannes Fritsch\n> Anschrift: Musterstraße 12";
        assert_eq!(latest(body), "Wir überweisen 4,50 EUR.");
    }

    #[test]
    fn an_outlook_header_block_ends_the_answer() {
        let body = "Leider können wir nicht entsprechen.\n\nVon: Verspätomat\nGesendet: Mittwoch, 3. September 2026\nAn: Servicecenter\nBetreff: Antrag";
        assert_eq!(latest(body), "Leider können wir nicht entsprechen.");
    }

    #[test]
    fn a_greeting_line_starting_with_von_is_not_a_header() {
        let body = "Von uns erhalten Sie 4,50 EUR.\nMit freundlichen Grüßen";
        assert_eq!(latest(body), body);
    }

    #[test]
    fn a_name_we_do_not_know_is_taken_out_of_the_salutation() {
        let k = Known::default();
        assert_eq!(scrub("Sehr geehrter Herr Fritsch,", &k), "Sehr geehrter Herr [Name],");
        assert_eq!(scrub("Sehr geehrte Frau Dr. Meyer-Lüdenscheid,", &k), "Sehr geehrte Frau Dr. [Name],");
        assert_eq!(scrub("Sehr geehrte/r Johannes Fritsch,", &k), "Sehr geehrte/r [Name],");
        assert_eq!(scrub("Sehr geehrte Damen und Herren,", &k), "Sehr geehrte Damen und Herren,");
    }

    #[test]
    fn salutations_in_every_shape_lose_the_name() {
        let k = Known::default();
        for (input, want) in [
            ("Sehr geehrter Herr Prof. Dr. Klein,", "Sehr geehrter Herr Prof. Dr. [Name],"),
            ("Sehr geehrter Herr Dr. med. Klein,", "Sehr geehrter Herr Dr. med. [Name],"),
            ("Sehr geehrte Frau von Bülow,", "Sehr geehrte Frau [Name],"),
            ("Liebe Frau von der Heide,", "Liebe Frau [Name],"),
            ("Sehr geehrte*r Johannes Fritsch,", "Sehr geehrte*r [Name],"),
            ("Sehr geehrte:r Johannes Fritsch,", "Sehr geehrte:r [Name],"),
            ("SEHR GEEHRTER HERR FRITSCH,", "SEHR GEEHRTER HERR [Name],"),
            ("Guten Tag Johannes Fritsch,", "Guten Tag [Name],"),
            ("Hallo Johannes Fritsch,", "Hallo [Name],"),
            ("Dear Mr Fritsch,", "Dear Mr [Name],"),
            ("Herrn\nJürgen Müller\n", "Herrn\n[Name]\n"),
            ("Guten Tag,\n\nwir haben Ihren Antrag geprüft.", "Guten Tag,\n\nwir haben Ihren Antrag geprüft."),
            ("Sehr geehrte Damen und Herren,", "Sehr geehrte Damen und Herren,"),
        ] {
            assert_eq!(scrub(input, &k), want, "input: {input}");
        }
    }

    #[test]
    fn a_known_name_is_found_in_other_spellings() {
        let k = Known { name: Some("Jürgen Weiß-Müller".into()), ..Known::default() };
        let shown = scrub("Antragsteller: Juergen Weiss-Mueller. Verwendungszweck MUELLER JUERGEN. Weiss, Juergen", &k);
        for gone in ["Juergen", "JUERGEN", "Weiss", "Mueller", "MUELLER"] {
            assert!(!shown.contains(gone), "{gone} leaked: {shown}");
        }
    }

    #[test]
    fn a_name_particle_is_not_replaced_on_its_own() {
        let k = Known { name: Some("Anna von der Heide".into()), ..Known::default() };
        assert_eq!(scrub("eine Entschädigung von 1,50 EUR für die Fahrt der Linie RE 1", &k), "eine Entschädigung von 1,50 EUR für die Fahrt der Linie RE 1");
    }

    #[test]
    fn a_known_address_is_found_in_other_spellings() {
        let k = Known { postal_address: Some("Weißenburgstraße 12\n50670 Köln".into()), ..Known::default() };
        for letter in ["Weißenburgstr. 12", "Weissenburgstrasse 12", "WEISSENBURGSTRASSE 12"] {
            assert!(!scrub(letter, &k).contains("12"), "{letter} leaked");
        }
        let one_line = Known { postal_address: Some("Musterstraße 12 50667 Köln".into()), ..Known::default() };
        assert!(!scrub("Anschrift: Musterstraße 12", &one_line).contains("Muster"));
    }

    #[test]
    fn dates_and_the_city_survive_because_rides_are_matched_by_them() {
        let k = Known { name: Some("Jürgen Weiß".into()), postal_address: Some("Weißenburgstraße 12, 50670 Köln".into()), ..Known::default() };
        assert_eq!(scrub("Ihre Fahrt am 03.09.2026 von Köln Hbf, Rückfahrt am 5.9.26", &k), "Ihre Fahrt am 03.09.2026 von Köln Hbf, Rückfahrt am 5.9.26");
        assert_eq!(scrub("Anschrift: Weißenburgstraße 12, 50670 Köln", &k), "Anschrift: [Anschrift], [Anschrift] Köln");
    }

    #[test]
    fn a_greeting_never_swallows_the_next_sentence() {
        let k = Known::default();
        for body in [
            "Guten Tag,\n\nKeine Entschädigung in Höhe von 1,50 EUR wird überwiesen.",
            "Hallo,\nder Betrag von 3,00 EUR geht an den Zahlungsempfänger.",
            "Guten Tag,\n\nSofern Ihr Ticket gültig war, überweisen wir 1,50 EUR.",
            "Guten Tag,\n\nNicht erstattungsfähig: Fahrt am 05.09.2026, 1,50 EUR",
            "Guten Tag, Ihre Entschädigung von insgesamt 3,00 EUR wird überwiesen.",
            "Guten Tag Unter Vorbehalt überweisen wir Ihnen 1,50 EUR.",
            "Guten Tag Keinerlei Entschädigung überweisen wir Ihnen.",
            "Hallo Wegen der Verspätung zahlen wir 1,50 EUR.",
        ] {
            assert_eq!(scrub(body, &k), body);
        }
    }

    #[test]
    fn our_words_retyped_or_rewrapped_are_still_ours() {
        let sent = vec!["Sehr geehrte Damen und Herren,\n\nBitte überweisen Sie die Entschädigung von insgesamt 3,00 EUR auf das Konto der Bahnhofsmission Köln.\n\nDiese E-Mail wurde über Verspätomat übermittelt, eine Ausfüll- und Weiterleitungshilfe. Antragsteller ist Jürgen Weiß.\n\nMit freundlichen Grüßen\nJürgen Weiß".to_string()];
        let answer = "Wir überweisen die beantragte Entschädigung.\n\nIhr Antrag lautete:\nBitte ueberweisen Sie die Entschaedigung von insgesamt 3,00 € auf das Konto der Bahnhofsmission Koeln.\nDiese E-Mail wurde über\nVerspätomat übermittelt, eine Ausfüll-\nund Weiterleitungshilfe.\n\nMit freundlichen Grüßen\nServicecenter";
        let left = without_ours(answer, &sent);
        assert!(!left.contains("3,00"), "{left}");
        assert!(!left.contains("Weiterleitungshilfe"), "{left}");
        assert!(left.contains("Wir überweisen die beantragte Entschädigung."));
        assert!(left.contains("Mit freundlichen Grüßen"));
        // The desk's own sentence about the same ride is not ours.
        let desk = "Für die Fahrt mit dem RE 5 am 03.09.2026 von Köln Hbf nach Bonn Hbf überweisen wir 1,50 EUR auf das Konto der Bahnhofsmission.";
        assert_eq!(without_ours(desk, &sent), desk);
    }

    #[test]
    fn our_own_words_are_gone_however_they_come_back() {
        let sent = vec!["Sehr geehrte Damen und Herren,\nfür beide Fahrten überweisen wir eine Entschädigung von insgesamt 3,00 EUR auf das angegebene Konto.\nAntragsteller ist Jürgen Weiß.".to_string()];
        let answer = "Wir haben Ihre Nachricht erhalten.\n______________\nIhre Nachricht vom 12.09.2026, 09:14 Uhr\nfür beide Fahrten überweisen wir eine Entschädigung von\ninsgesamt 3,00 EUR auf das angegebene Konto.\n> Antragsteller ist Jürgen Weiß.";
        let left = without_ours(answer, &sent);
        assert!(!left.contains("überweisen"), "{left}");
        assert!(!left.contains("Antragsteller"), "{left}");
        assert!(left.contains("Wir haben Ihre Nachricht erhalten."));
        assert_eq!(latest("Danke.\nIhre Nachricht vom 12.09.2026, 09:14 Uhr\nWir überweisen 3,00 EUR."), "Danke.");
        // A desk's own intro that happens to start the same way is not an echo.
        let own = "Ihre E-Mail vom 06.09.2026 haben wir wie folgt beantwortet:\nWir überweisen 3,00 EUR.";
        assert_eq!(latest(own), own);
    }

    #[test]
    fn a_payee_line_naming_the_passenger_is_seen_before_redaction() {
        let k = Known { name: Some("Jürgen Weiß".into()), ..Known::default() };
        assert!(names_passenger_as_payee("Zahlungsempfänger: Jürgen Weiß", &k));
        assert!(names_passenger_as_payee("Kontoinhaber: WEISS, JUERGEN", &k));
        assert!(!names_passenger_as_payee("Zahlungsempfänger: Bahnhofsmission Köln", &k));
        assert!(!names_passenger_as_payee("Sehr geehrter Herr Weiß,", &k));
    }

    #[test]
    fn a_ticket_system_echo_and_a_rule_line_end_the_answer() {
        assert_eq!(latest("Wir haben Ihre Nachricht erhalten.\n\nIhre Nachricht an uns:\nWir überweisen 1,50 EUR."), "Wir haben Ihre Nachricht erhalten.");
        assert_eq!(latest("Danke.\n----- Ihre Nachricht -----\nWir überweisen 1,50 EUR."), "Danke.");
        // A line of dashes is a section in the desk's own letter, not a quote.
        assert_eq!(latest("Wir zahlen 3,00 EUR.\n----------\nFahrt 2: abgelehnt"), "Wir zahlen 3,00 EUR.\n----------\nFahrt 2: abgelehnt");
        // The vetoes still read an echo; the reader does not.
        assert_eq!(unquoted("Eingegangen.\nIhre Nachricht an uns:\nsofern gültig"), "Eingegangen.\nIhre Nachricht an uns:\nsofern gültig");
        assert_eq!(latest("Wir überweisen 1,50 EUR.\n\nAm 04.09.2026 um 18:12 schrieb Verspätomat\n<antrag-1a2b@users.verspaetomat.de>:\nName: X"), "Wir überweisen 1,50 EUR.");
        // A ride table is not a mail header.
        let table = "Fahrt 1\nVon: Köln Hbf\nNach: Bonn Hbf\nDatum: 03.09.2026\nBetrag: 1,50 EUR";
        assert_eq!(latest(table), table);
    }

    #[test]
    fn identifiers_a_desk_prints_in_other_places() {
        let k = Known { name: Some("Jürgen Weiß".into()), ticket_number: Some("DT-4711-0815".into()), postal_address: Some("Weißenburgstraße 12, 50670 Köln".into()), ..Known::default() };
        let shown = scrub("Vorname: JURGEN\nStraße: Weißenburgstraße\nHausnummer: 12\nAnlage: Bescheid_WEISS_JUERGEN.pdf\nLink: ?name=Juergen%20Weiss\nTicket DT–4711–0815, DT_4711_0815, Abo-Nr. 4711 0815\ngeb. 01.02.1980\nBahnCard 7081 4123 4567 8901\nKundennummer: 99887766", &k);
        for gone in ["JURGEN", "WEISS", "Juergen", "Weiss", "Weißenburg", "4711", "1980", "7081", "99887766"] {
            assert!(!shown.contains(gone), "{gone} leaked: {shown}");
        }
    }

    #[test]
    fn dates_next_to_amounts_and_ibans_of_any_length() {
        let k = Known::default();
        assert_eq!(scrub("am 03.09.2026 1,50 EUR und 03.09.2026 - 05.09.2026", &k), "am 03.09.2026 1,50 EUR und 03.09.2026 - 05.09.2026");
        assert_eq!(scrub("Konto AT61 1904 3002 3457 3201 Bitte beachten", &k), "Konto [IBAN] Bitte beachten");
        assert_eq!(scrub("im Altvertrag DE02\u{a0}1203\u{a0}0000\u{a0}0000\u{a0}2020\u{a0}51", &k), "im Altvertrag [IBAN]");
        assert_eq!(scrub("Tel. 0170–1234567 oder 0221\u{a0}9876543", &k), "Tel. [Telefon] oder [Telefon]");
        assert_eq!(scrub("an jw1980 (at) gmx (dot) de und jw1980 at gmx dot de", &k), "an [E-Mail] und [E-Mail]");
    }

    #[test]
    fn a_known_ticket_number_is_found_with_any_separator() {
        let k = Known { ticket_number: Some("DT-4711-0815".into()), ..Known::default() };
        assert_eq!(scrub("Ticket DT 4711 0815 / DT47110815", &k), "Ticket [Ticketnummer] / [Ticketnummer]");
    }

    #[test]
    fn ibans_emails_and_phones_in_their_other_shapes() {
        let k = Known::default();
        assert_eq!(scrub("Konto de89370400440532013000", &k), "Konto [IBAN]");
        assert_eq!(scrub("Konto de89 3704 0044 0532 0130 00", &k), "Konto [IBAN]");
        assert_eq!(scrub("Konto DE89 3704 0044\n0532 0130 00", &k), "Konto [IBAN]");
        assert_eq!(scrub("Vorgang AB12 3456 7890 1234", &k), "Vorgang AB12 3456 7890 1234");
        assert_eq!(scrub("an jürgen.müller@web.de", &k), "an [E-Mail]");
        assert_eq!(scrub("an juergen.mueller [at] example.org", &k), "an [E-Mail]");
        assert_eq!(scrub("Tel.0221 12345678 oder 0221.1234567", &k), "Tel.[Telefon] oder [Telefon]");
        assert_eq!(scrub("+49 221 1234567 und (0221) 123 45 67", &k), "[Telefon] und [Telefon]");
    }

    #[test]
    fn short_name_parts_do_not_eat_ordinary_words() {
        let k = Known { name: Some("Li An".into()), ..Known::default() };
        assert_eq!(scrub("An Sie überweisen wir", &k), "An Sie überweisen wir");
    }

    #[test]
    fn amounts_and_case_numbers_survive_the_phone_pattern() {
        let shown = scrub("Vorgang 2026-09-4723683: 0,50 EUR und 12,00 EUR", &Known::default());
        assert_eq!(shown, "Vorgang 2026-09-4723683: 0,50 EUR und 12,00 EUR");
    }
}
