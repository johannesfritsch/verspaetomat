//! The claim document: the EU standard form (Implementing Regulation (EU) 2024/949),
//! rebuilt as a Typst template and filled from the ledger. One engine, compiled per claim.

use std::sync::OnceLock;

use chrono::{DateTime, Utc};
use serde_json::{json, Value};
use typst::foundations::{Bytes, Dict, IntoValue, Value as TValue};
use typst_as_lib::typst_kit_options::TypstKitFontOptions;
use typst_as_lib::TypstEngine;

use crate::db::rows::*;

static TEMPLATE: &str = include_str!("../templates/eu_form.typ");

fn engine() -> &'static TypstEngine<typst_as_lib::TypstTemplateMainFile> {
    static ENGINE: OnceLock<TypstEngine<typst_as_lib::TypstTemplateMainFile>> = OnceLock::new();
    ENGINE.get_or_init(|| {
        TypstEngine::builder()
            .main_file(TEMPLATE)
            .search_fonts_with(TypstKitFontOptions::default().include_system_fonts(true).include_embedded_fonts(true))
            .build()
    })
}

pub struct ClaimDocument<'a> {
    pub claim: &'a ClaimRow,
    pub incidents: &'a [IncidentRow],
    pub customer: &'a CustomerRow,
    /// PNG bytes of the drawn signature, if the customer signed by hand.
    pub signature_png: Option<Vec<u8>>,
}

fn euro(cents: i64) -> String {
    format!("{},{:02} €", cents / 100, cents % 100)
}

fn berlin(t: DateTime<Utc>) -> chrono::DateTime<chrono_tz::Tz> {
    t.with_timezone(&chrono_tz::Europe::Berlin)
}

fn hhmm(v: Option<&Value>) -> String {
    v.and_then(|x| x.as_str())
        .and_then(|s| s.parse::<DateTime<Utc>>().ok())
        .map(|t| berlin(t).format("%H:%M").to_string())
        .unwrap_or_else(|| "–".into())
}

fn incident_json(i: &IncidentRow) -> Value {
    let ev = i.evidence.as_ref();
    let journey = ev.and_then(|e| e.get("journey"));
    let legs: Vec<Value> = journey
        .and_then(|j| j.get("legs"))
        .and_then(|l| l.as_array())
        .map(|legs| {
            legs.iter()
                .map(|l| {
                    json!({
                        "line": l.get("line").and_then(|v| v.as_str()).unwrap_or(""),
                        "from": l.get("from").and_then(|v| v.as_str()).unwrap_or(""),
                        "to": l.get("to").and_then(|v| v.as_str()).unwrap_or(""),
                        "planned_departure": hhmm(l.get("planned_departure")),
                        "planned": hhmm(l.get("planned_arrival")),
                        "actual": if l.get("cancelled").and_then(|v| v.as_bool()).unwrap_or(false) { "Ausfall".to_string() } else { hhmm(l.get("actual_arrival")) },
                        "confirmed": l.get("confirmed").and_then(|v| v.as_bool()).unwrap_or(false),
                    })
                })
                .collect()
        })
        .unwrap_or_default();
    let missed = journey.and_then(|j| j.get("missed_connection")).and_then(|v| v.as_bool()).unwrap_or(false);
    json!({
        "legs": legs,
        "missed": missed,
        "date": i.ride_date.format("%d.%m.%Y").to_string(),
        "line": i.line,
        "from": i.from_name,
        "to": i.to_name,
        "planned": hhmm(ev.and_then(|e| e.get("planned_arrival"))),
        "actual": if i.cancelled { "Ausfall".to_string() } else { hhmm(ev.and_then(|e| e.get("actual_arrival"))) },
        "delay": i.delay_min,
        "cancelled": i.cancelled,
        "self_entered": i.self_entered,
        "amount": euro(i.amount_cents),
    })
}

/// The data the template reads under `inputs.claim`.
pub fn claim_inputs(doc: &ClaimDocument<'_>) -> Value {
    let c = doc.customer;
    let claim = doc.claim;
    let first = doc.incidents.first().map(incident_json).unwrap_or_else(|| json!({
        "date": "–", "line": "–", "from": "–", "to": "–", "planned": "–", "actual": "–", "delay": 0, "cancelled": false, "self_entered": false, "amount": "–"
    }));
    let season = matches!(c.ticket, TicketType::Deutschlandticket | TicketType::Zeitkarte);
    let kind = if season {
        "season"
    } else if doc.incidents.iter().any(|i| i.delay_min >= 120 || i.cancelled) {
        "120"
    } else {
        "60"
    };
    let ticket_type = match c.ticket {
        TicketType::Deutschlandticket => "Deutschlandticket",
        TicketType::Zeitkarte => "Zeitkarte",
        TicketType::Einzelfahrkarte => "Einzelfahrkarte",
    };
    let fare = doc.incidents.first().and_then(|i| i.fare_cents).map(euro).unwrap_or_else(|| "–".into());
    let signed_on = claim.signed_at.map(|t| berlin(t).format("%d.%m.%Y").to_string()).unwrap_or_default();
    let place = c.postal_address.as_deref().and_then(|a| a.lines().last()).map(|l| l.trim().to_string()).unwrap_or_default();
    let mut notes = String::new();
    if c.ticket == TicketType::Deutschlandticket {
        notes.push_str("Deutschlandticket: Entschädigung 1,50 € je Fall ab 60 Minuten Verspätung, Auszahlung ab 4,00 € (Art. 19 VO (EU) 2021/782, § 8 EVO). ");
    }
    if let Some(n) = claim.signed_by.as_deref() {
        if doc.signature_png.is_none() && !n.is_empty() {
            notes.push_str("Elektronisch unterzeichnet durch Eingabe des Namens.");
        }
    }
    json!({
        "claim_id": claim.id.to_string().split('-').next().unwrap_or("").to_uppercase(),
        "created": berlin(claim.created_at).format("%d.%m.%Y").to_string(),
        "delay": doc.incidents.iter().any(|i| !i.cancelled),
        "cancellation": doc.incidents.iter().any(|i| i.cancelled),
        "missed": doc.incidents.iter().any(|i| i.evidence.as_ref().and_then(|e| e.get("journey")).and_then(|j| j.get("missed_connection")).and_then(|v| v.as_bool()).unwrap_or(false)),
        "operator": doc.incidents.first().map(|i| i.operator.clone()).unwrap_or_default(),
        "kind": kind,
        "ticket_type": ticket_type,
        "ticket_number": c.ticket_number.clone().unwrap_or_else(|| "–".into()),
        "first": first,
        "incidents": doc.incidents.iter().map(incident_json).collect::<Vec<_>>(),
        "person": {
            "name": c.full_name.clone().unwrap_or_default(),
            "email": c.email.clone().unwrap_or_default(),
            "address": c.postal_address.clone().unwrap_or_default().replace('\n', ", "),
        },
        "payee": { "iban": claim.iban, "holder": claim.account_holder },
        "fare": fare,
        "total": euro(claim.amount_claimed_cents),
        "notes": notes.trim(),
        "signed_on": signed_on,
        "place": place,
        "signature": Value::Null,
    })
}

/// Renders the PDF. CPU-bound: call from `spawn_blocking`.
pub fn render(doc: &ClaimDocument<'_>) -> anyhow::Result<Vec<u8>> {
    let document = compile(doc)?;
    let pdf = typst_pdf::pdf(&document, &typst_pdf::PdfOptions::default()).map_err(|e| anyhow::anyhow!("typst pdf: {e:?}"))?;
    Ok(pdf)
}

/// Compiles the template into a laid-out document (pages, no PDF bytes yet).
pub fn compile(doc: &ClaimDocument<'_>) -> anyhow::Result<typst_layout::PagedDocument> {
    let inputs = claim_inputs(doc);
    let mut claim: Dict = match serde_json::from_value::<TValue>(inputs)? {
        TValue::Dict(d) => d,
        _ => anyhow::bail!("claim inputs must be a dict"),
    };
    if let Some(png) = &doc.signature_png {
        claim.insert("signature".into(), TValue::Bytes(Bytes::new(png.clone())));
    }
    let mut root = Dict::new();
    root.insert("claim".into(), claim.into_value());
    let compiled = engine().compile_with_input::<Dict, typst_layout::PagedDocument>(root);
    for w in &compiled.warnings {
        tracing::debug!("typst: {}", w.message);
    }
    compiled.output.map_err(|e| anyhow::anyhow!("typst compile: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::NaiveDate;
    use uuid::Uuid;

    #[test]
    fn renders_a_pdf() {
        let cid = Uuid::new_v4();
        let customer = CustomerRow {
            id: cid,
            nickname: "Test".into(),
            relay_address: Some("fahrgast-0000@users.verspaetomat.de".into()),
            full_name: Some("Erika Mustermann".into()),
            postal_address: Some("Musterstraße 1\n50667 Köln".into()),
            email: Some("erika@example.org".into()),
            ticket_number: Some("D-123456".into()),
            first_class: false,
            ticket: TicketType::Deutschlandticket,
            ngo_id: "seenotrettung".into(),
            loc_mode: LocationMode::WhileUsing,
            notifications: true,
            show_on_boards: true,
            keep_correspondence: false,
            traewelling_linked: false,
            onboarding_done: true,
            home_station_id: None,
            home_station_name: None,
            muted_stations: json!([]),
            nudge_enabled: true,
            quiet_from: None,
            quiet_to: None,
            created_at: Utc::now(),
        };
        let claim = ClaimRow {
            id: Uuid::new_v4(),
            customer_id: cid,
            desk: "Servicecenter Fahrgastrechte".into(),
            ngo_id: "seenotrettung".into(),
            account_holder: "Sea-Watch e.V.".into(),
            iban: "DE12 3456 7890 1234 5678 90".into(),
            ticket_months: vec!["2026-09".into()],
            status: ClaimStatus::Draft,
            signed_by: Some("Erika Mustermann".into()),
            signed_at: Some(Utc::now()),
            sent_at: None,
            expected_reply_by: None,
            amount_claimed_cents: 450,
            amount_confirmed_cents: None,
            closed_at: None,
            created_at: Utc::now(),
            reply_address: Some("antrag-3d09a883@users.verspaetomat.de".into()),
        };
        let incident = |d: u32, delay: i32| IncidentRow {
            id: Uuid::new_v4(),
            customer_id: cid,
            ride_id: None,
            ride_date: NaiveDate::from_ymd_opt(2026, 9, d).unwrap(),
            line: "RE 22".into(),
            from_name: "Köln Hbf".into(),
            to_name: "Trier Hbf".into(),
            delay_min: delay,
            amount_cents: 150,
            ticket: TicketType::Deutschlandticket,
            operator: "DB Regio".into(),
            desk: "Servicecenter Fahrgastrechte".into(),
            status: IncidentStatus::Bereit,
            cancelled: false,
            self_entered: false,
            ngo_id: "seenotrettung".into(),
            claim_id: None,
            fare_cents: None,
            legal_deadline: NaiveDate::from_ymd_opt(2026, 12, d).unwrap(),
            evidence: Some(json!({ "planned_arrival": "2026-09-01T10:00:00Z", "actual_arrival": "2026-09-01T11:08:00Z" })),
            created_at: Utc::now(),
            journey_id: None,
        };
        let incidents = vec![incident(1, 68), incident(3, 75), incident(5, 130)];
        let pdf = render(&ClaimDocument { claim: &claim, incidents: &incidents, customer: &customer, signature_png: None }).expect("render");
        assert!(pdf.starts_with(b"%PDF"));
        // a drawn signature, 300x90 PNG with transparency
        let png = signature_png();
        let signed_doc = ClaimDocument { claim: &claim, incidents: &incidents, customer: &customer, signature_png: Some(png) };
        assert_eq!(compile(&signed_doc).expect("compile with signature").pages().len(), 1, "the signed form must fit on one page");
        let signed = render(&signed_doc).expect("render with signature");
        assert!(signed.starts_with(b"%PDF"));
        std::fs::write(std::env::temp_dir().join("verspaetomat-test.pdf"), &signed).ok();

        // A journey with a missed connection: the reason is ticked, the legs are listed, one page.
        let mut j = incident(7, 70);
        j.line = "IC 2006 + RE 10".into();
        j.to_name = "Kleve".into();
        j.evidence = Some(json!({
            "planned_arrival": "2026-09-07T16:05:00Z", "actual_arrival": "2026-09-07T17:15:00Z",
            "journey": { "origin": "Köln Hbf", "destination": "Kleve", "missed_connection": true, "incomplete": false, "legs": [
                { "line": "IC 2006", "from": "Köln Hbf", "to": "Düsseldorf Hbf", "planned_departure": "2026-09-07T13:46:00Z", "planned_arrival": "2026-09-07T14:08:00Z", "actual_arrival": "2026-09-07T14:40:00Z", "delay_min": 32, "cancelled": false, "confirmed": true },
                { "line": "RE 10", "from": "Düsseldorf Hbf", "to": "Kleve", "planned_departure": "2026-09-07T14:38:00Z", "planned_arrival": "2026-09-07T16:05:00Z", "actual_arrival": "2026-09-07T17:15:00Z", "delay_min": 70, "cancelled": false, "confirmed": true }
            ] }
        }));
        let with_connection = vec![j];
        let doc = ClaimDocument { claim: &claim, incidents: &with_connection, customer: &customer, signature_png: None };
        let inputs = claim_inputs(&doc);
        assert_eq!(inputs["missed"], json!(true));
        assert_eq!(inputs["first"]["legs"].as_array().unwrap().len(), 2);
        assert_eq!(compile(&doc).expect("compile journey").pages().len(), 1, "a journey claim fits on one page");
        let pdf = render(&doc).expect("render journey");
        std::fs::write(std::env::temp_dir().join("verspaetomat-journey.pdf"), &pdf).ok();
    }

    fn signature_png() -> Vec<u8> {
        include_bytes!("../tests/fixtures/signature.png").to_vec()
    }
}
