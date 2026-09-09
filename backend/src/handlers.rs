//! HTTP handlers. Thin: parse, call rules, mutate state, answer.

use std::collections::BTreeMap;

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    Json,
};
use chrono::{Duration, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::model::*;
use crate::rules;
use crate::Shared;

type ApiResult = Result<Json<Value>, (StatusCode, Json<Value>)>;

fn err(status: StatusCode, msg: &str) -> (StatusCode, Json<Value>) {
    (status, Json(json!({ "error": msg })))
}

fn now() -> chrono::NaiveDateTime {
    Utc::now().naive_utc()
}

fn add_minutes(hhmm: &str, minutes: i64) -> String {
    let (h, m) = hhmm.split_once(':').unwrap_or(("0", "0"));
    let total = (h.parse::<i64>().unwrap_or(0) * 60 + m.parse::<i64>().unwrap_or(0) + minutes).rem_euclid(24 * 60);
    format!("{:02}:{:02}", total / 60, total % 60)
}

pub async fn health() -> Json<Value> {
    Json(json!({ "ok": true, "service": "verspaetomat-api" }))
}

// ---------------------------------------------------------------------------
// Reference data
// ---------------------------------------------------------------------------

pub async fn stations_nearby(State(s): State<Shared>) -> Json<Vec<Station>> {
    Json(s.read().unwrap().stations.clone())
}

pub async fn departures(State(s): State<Shared>, Path(id): Path<String>) -> Json<Vec<Departure>> {
    let s = s.read().unwrap();
    Json(s.departures.iter().filter(|d| d.station_id == id).cloned().collect())
}

pub async fn trip(State(s): State<Shared>, Path(id): Path<String>) -> ApiResult {
    let s = s.read().unwrap();
    s.departures
        .iter()
        .find(|d| d.id == id)
        .map(|d| Json(json!(d)))
        .ok_or_else(|| err(StatusCode::NOT_FOUND, "trip not found"))
}

pub async fn operators(State(s): State<Shared>) -> Json<Vec<Operator>> {
    Json(s.read().unwrap().operators.clone())
}

pub async fn ngos(State(s): State<Shared>) -> Json<Vec<Ngo>> {
    let s = s.read().unwrap();
    let mut ngos = s.ngos.clone();
    for n in ngos.iter_mut() {
        n.confirmed_total_cents += s
            .incidents
            .iter()
            .filter(|i| i.ngo_id == n.id && i.status == IncidentStatus::Bestaetigt)
            .map(|i| i.amount_cents)
            .sum::<Cents>();
        n.submitted_total_cents += s
            .incidents
            .iter()
            .filter(|i| i.ngo_id == n.id && i.status == IncidentStatus::Eingereicht)
            .map(|i| i.amount_cents)
            .sum::<Cents>();
    }
    Json(ngos)
}

pub async fn badges(State(s): State<Shared>) -> Json<Vec<Badge>> {
    Json(s.read().unwrap().badges.clone())
}

// ---------------------------------------------------------------------------
// Customer
// ---------------------------------------------------------------------------

pub async fn me(State(s): State<Shared>) -> Json<Customer> {
    let s = s.read().unwrap();
    let mut me = s.me.clone();
    me.points_this_week += s.rides.iter().filter(|r| r.nachtrag).map(|r| r.points).sum::<i64>();
    Json(me)
}

#[derive(Deserialize)]
pub struct MePatch {
    pub ticket: Option<TicketType>,
    pub ngo_id: Option<String>,
    pub location_mode: Option<LocationMode>,
    pub notifications: Option<bool>,
    pub show_on_boards: Option<bool>,
    pub keep_correspondence: Option<bool>,
    pub traewelling_linked: Option<bool>,
}

pub async fn patch_me(State(s): State<Shared>, Json(p): Json<MePatch>) -> ApiResult {
    let mut s = s.write().unwrap();
    if let Some(n) = &p.ngo_id {
        if !s.ngos.iter().any(|x| &x.id == n) {
            return Err(err(StatusCode::BAD_REQUEST, "unknown ngo"));
        }
    }
    let st = &mut s.me.settings;
    if let Some(v) = p.ticket {
        st.ticket = v;
    }
    if let Some(v) = p.ngo_id {
        st.ngo_id = v;
    }
    if let Some(v) = p.location_mode {
        st.location_mode = v;
    }
    if let Some(v) = p.notifications {
        st.notifications = v;
    }
    if let Some(v) = p.show_on_boards {
        st.show_on_boards = v;
    }
    if let Some(v) = p.keep_correspondence {
        st.keep_correspondence = v;
    }
    if let Some(v) = p.traewelling_linked {
        st.traewelling_linked = v;
    }
    Ok(Json(json!(s.me)))
}

pub async fn put_personal_data(State(s): State<Shared>, Json(p): Json<PersonalData>) -> Json<Customer> {
    let mut s = s.write().unwrap();
    s.me.personal_data = Some(p);
    if s.me.relay_address.is_none() {
        s.me.relay_address = Some(format!("fahrgast-{}@verspaetomat.de", &s.me.id[..4]));
    }
    Json(s.me.clone())
}

// ---------------------------------------------------------------------------
// Rides
// ---------------------------------------------------------------------------

pub async fn rides(State(s): State<Shared>) -> Json<Vec<Ride>> {
    Json(s.read().unwrap().rides.clone())
}

#[derive(Deserialize)]
pub struct CheckIn {
    pub departure_id: String,
    pub from_station: String,
    pub exit_stop: String,
    #[serde(default)]
    pub ticket: Option<TicketType>,
    #[serde(default)]
    pub location_verified: bool,
}

pub async fn check_in(State(s): State<Shared>, Json(c): Json<CheckIn>) -> ApiResult {
    let mut s = s.write().unwrap();
    if s.rides.iter().any(|r| r.status == RideStatus::Riding) {
        return Err(err(StatusCode::CONFLICT, "already riding; dismiss or arrive first"));
    }
    let dep = s
        .departures
        .iter()
        .find(|d| d.id == c.departure_id)
        .cloned()
        .ok_or_else(|| err(StatusCode::NOT_FOUND, "departure not found"))?;
    let stop = dep
        .stops
        .iter()
        .find(|st| st.name == c.exit_stop)
        .cloned()
        .ok_or_else(|| err(StatusCode::BAD_REQUEST, "exit stop not on this trip"))?;
    let ride = Ride {
        id: uuid::Uuid::new_v4().to_string(),
        departure_id: dep.id.clone(),
        line: dep.line.clone(),
        operator: dep.operator.clone(),
        category: dep.category,
        from_station: c.from_station,
        exit_stop: stop.name,
        planned_arrival: stop.planned,
        ticket: c.ticket.unwrap_or(s.me.settings.ticket),
        checked_in_at: now(),
        location_verified: c.location_verified,
        status: RideStatus::Riding,
        passed_stops: 0,
        live_delay_minutes: dep.delay_minutes,
        cause: dep.cause.clone(),
        final_delay_minutes: None,
        cancelled: dep.cancelled,
        self_entered: false,
        nachtrag: false,
        points: 0,
        date: s.today,
    };
    s.rides.insert(0, ride.clone());
    Ok(Json(json!(ride)))
}

pub async fn current_ride(State(s): State<Shared>) -> ApiResult {
    let s = s.read().unwrap();
    let ride = s.rides.iter().find(|r| r.status == RideStatus::Riding);
    match ride {
        Some(r) => {
            let dep = s.departures.iter().find(|d| d.id == r.departure_id);
            Ok(Json(json!({
                "ride": r,
                "stops": dep.map(|d| d.stops.clone()).unwrap_or_default(),
                "eta": add_minutes(&r.planned_arrival, r.live_delay_minutes),
                "claim_from_minute": 60,
            })))
        }
        None => Err(err(StatusCode::NOT_FOUND, "no ride in progress")),
    }
}

/// Stand-in for the trip follower: advance one stop, grow the delay a little.
pub async fn tick_ride(State(s): State<Shared>) -> ApiResult {
    let mut s = s.write().unwrap();
    let today = s.today;
    let departures = s.departures.clone();
    let Some(r) = s.rides.iter_mut().find(|r| r.status == RideStatus::Riding) else {
        return Err(err(StatusCode::NOT_FOUND, "no ride in progress"));
    };
    let _ = today;
    if let Some(dep) = departures.iter().find(|d| d.id == r.departure_id) {
        let exit_index = dep.stops.iter().position(|st| st.name == r.exit_stop).unwrap_or(0);
        if r.passed_stops < exit_index {
            r.passed_stops += 1;
            r.live_delay_minutes += [3, 5, 9, 14, 21, 12, 4][r.passed_stops % 7];
            if r.live_delay_minutes >= 20 && r.cause.is_none() {
                r.cause = Some("Stellwerksstörung".into());
            }
        }
    }
    Ok(Json(json!(r)))
}

#[derive(Deserialize)]
pub struct Arrival {
    #[serde(default)]
    pub delay_minutes: Option<i64>,
    #[serde(default)]
    pub actual_arrival: Option<String>,
    #[serde(default)]
    pub cancelled: bool,
    #[serde(default)]
    pub self_entered: bool,
}

/// Finalise the current ride. The trip follower will call this from live data;
/// the app calls it with a time when there is no data (E3).
pub async fn arrival(State(s): State<Shared>, Json(a): Json<Arrival>) -> ApiResult {
    let mut s = s.write().unwrap();
    let today = s.today;
    let idx = s
        .rides
        .iter()
        .position(|r| r.status == RideStatus::Riding)
        .ok_or_else(|| err(StatusCode::NOT_FOUND, "no ride in progress"))?;
    let (ride, incident) = {
        let r = &mut s.rides[idx];
        let delay = match (a.delay_minutes, &a.actual_arrival) {
            (Some(d), _) => d,
            (None, Some(t)) => minutes_between(&r.planned_arrival, t),
            (None, None) => r.live_delay_minutes,
        };
        r.final_delay_minutes = Some(delay);
        r.cancelled = a.cancelled || r.cancelled;
        r.self_entered = a.self_entered;
        r.status = RideStatus::Arrived;
        r.points = rules::points_for(delay, r.cancelled, false);
        let amount = rules::claim_amount_cents(r.ticket, r.category, delay, false, if r.ticket == TicketType::Einzelfahrkarte { Some(3990) } else { None });
        let incident = amount.map(|amount_cents| Incident {
            id: uuid::Uuid::new_v4().to_string(),
            ride_id: Some(r.id.clone()),
            date: r.date,
            line: r.line.clone(),
            from: r.from_station.clone(),
            to: r.exit_stop.clone(),
            delay_minutes: delay,
            amount_cents,
            ticket: r.ticket,
            operator: r.operator.clone(),
            desk: String::new(),
            status: IncidentStatus::Gesammelt,
            cancelled: r.cancelled,
            self_entered: r.self_entered,
            ngo_id: String::new(),
            claim_id: None,
            fare_cents: if r.ticket == TicketType::Einzelfahrkarte { Some(3990) } else { None },
            legal_deadline: rules::legal_deadline(r.date),
            evidence: Some(Evidence {
                planned_arrival: Some(r.planned_arrival.clone()),
                actual_arrival: Some(add_minutes(&r.planned_arrival, delay)),
                source: if r.self_entered { "selbst eingetragen".into() } else { "Live-Daten Transitous".into() },
                fetched_at: now(),
            }),
        });
        (r.clone(), incident)
    };
    let mut created = None;
    if let Some(mut inc) = incident {
        inc.desk = s.desk_for(&inc.operator);
        inc.ngo_id = s.me.settings.ngo_id.clone();
        s.incidents.insert(0, inc.clone());
        rules::refresh_statuses(&mut s.incidents, today);
        created = s.incidents.iter().find(|i| i.id == inc.id).cloned();
    }
    let new_badge = match ride.final_delay_minutes {
        Some(d) if d >= 60 => s.badges.iter().find(|b| b.id == "stunde").cloned(),
        Some(d) if (1..10).contains(&d) => s.badges.iter().find(|b| b.id == "gegenzug").cloned(),
        _ => None,
    };
    let desk_ready = created.as_ref().map(|i| i.status == IncidentStatus::Bereit).unwrap_or(false);
    Ok(Json(json!({
        "ride": ride,
        "incident": created,
        "bundle_ready": desk_ready,
        "new_badge": new_badge,
    })))
}

fn minutes_between(planned: &str, actual: &str) -> i64 {
    let to_min = |t: &str| {
        let (h, m) = t.split_once(':').unwrap_or(("0", "0"));
        h.parse::<i64>().unwrap_or(0) * 60 + m.parse::<i64>().unwrap_or(0)
    };
    (to_min(actual) - to_min(planned)).rem_euclid(24 * 60)
}

pub async fn dismiss(State(s): State<Shared>) -> Json<Value> {
    let s = s.read().unwrap();
    Json(json!({ "ok": true, "rides": s.rides.len() }))
}

#[derive(Deserialize)]
pub struct Nachtrag {
    pub departure_id: String,
    pub from_station: String,
    pub exit_stop: String,
    pub date: chrono::NaiveDate,
}

pub async fn nachtrag(State(s): State<Shared>, Json(n): Json<Nachtrag>) -> ApiResult {
    let mut s = s.write().unwrap();
    let today = s.today;
    let dep = s
        .departures
        .iter()
        .find(|d| d.id == n.departure_id)
        .cloned()
        .ok_or_else(|| err(StatusCode::NOT_FOUND, "departure not found"))?;
    let stop = dep
        .stops
        .iter()
        .find(|st| st.name == n.exit_stop)
        .cloned()
        .ok_or_else(|| err(StatusCode::BAD_REQUEST, "exit stop not on this trip"))?;
    let delay = dep.delay_minutes;
    let ride = Ride {
        id: uuid::Uuid::new_v4().to_string(),
        departure_id: dep.id.clone(),
        line: dep.line.clone(),
        operator: dep.operator.clone(),
        category: dep.category,
        from_station: n.from_station.clone(),
        exit_stop: stop.name.clone(),
        planned_arrival: stop.planned.clone(),
        ticket: s.me.settings.ticket,
        checked_in_at: now(),
        location_verified: false,
        status: RideStatus::Arrived,
        passed_stops: dep.stops.len(),
        live_delay_minutes: delay,
        cause: dep.cause.clone(),
        final_delay_minutes: Some(delay),
        cancelled: dep.cancelled,
        self_entered: false,
        nachtrag: true,
        points: rules::points_for(delay, dep.cancelled, true),
        date: n.date,
    };
    let mut incident = None;
    if let Some(amount) = rules::claim_amount_cents(ride.ticket, ride.category, delay, false, None) {
        let inc = Incident {
            id: uuid::Uuid::new_v4().to_string(),
            ride_id: Some(ride.id.clone()),
            date: n.date,
            line: ride.line.clone(),
            from: ride.from_station.clone(),
            to: ride.exit_stop.clone(),
            delay_minutes: delay,
            amount_cents: amount,
            ticket: ride.ticket,
            operator: ride.operator.clone(),
            desk: s.desk_for(&ride.operator),
            status: IncidentStatus::Gesammelt,
            cancelled: ride.cancelled,
            self_entered: false,
            ngo_id: s.me.settings.ngo_id.clone(),
            claim_id: None,
            fare_cents: None,
            legal_deadline: rules::legal_deadline(n.date),
            evidence: None,
        };
        s.incidents.insert(0, inc.clone());
        rules::refresh_statuses(&mut s.incidents, today);
        incident = Some(inc);
    }
    s.rides.insert(0, ride.clone());
    Ok(Json(json!({ "ride": ride, "incident": incident })))
}

// ---------------------------------------------------------------------------
// Ledger and claims
// ---------------------------------------------------------------------------

#[derive(Serialize)]
struct DeskSummary {
    desk: String,
    open_cents: Cents,
    ready: bool,
    missing_cents: Cents,
    incident_ids: Vec<String>,
}

pub async fn incidents(State(s): State<Shared>) -> Json<Value> {
    let mut s = s.write().unwrap();
    let today = s.today;
    rules::refresh_statuses(&mut s.incidents, today);
    let mut by_desk: BTreeMap<String, Vec<&Incident>> = BTreeMap::new();
    for i in s.incidents.iter().filter(|i| i.status.is_open()) {
        by_desk.entry(i.desk.clone()).or_default().push(i);
    }
    let desks: Vec<DeskSummary> = by_desk
        .iter()
        .map(|(desk, list)| {
            let open: Cents = list.iter().map(|i| i.amount_cents).sum();
            DeskSummary {
                desk: desk.clone(),
                open_cents: open,
                ready: rules::bundle_ready(list),
                missing_cents: (rules::MIN_PAYOUT_CENTS - open).max(0),
                incident_ids: list.iter().map(|i| i.id.clone()).collect(),
            }
        })
        .collect();
    let oldest_open = s.incidents.iter().filter(|i| i.status.is_open()).min_by_key(|i| i.date).cloned();
    let confirmed: Cents = s.incidents.iter().filter(|i| i.status == IncidentStatus::Bestaetigt).map(|i| i.amount_cents).sum();
    let submitted: Cents = s.incidents.iter().filter(|i| i.status == IncidentStatus::Eingereicht).map(|i| i.amount_cents).sum();
    Json(json!({
        "incidents": s.incidents,
        "summary": {
            "desks": desks,
            "ready_desk": desks.iter().find(|d| d.ready).map(|d| d.desk.clone()),
            "confirmed_cents": confirmed,
            "submitted_cents": submitted,
            "oldest_open": oldest_open.as_ref().map(|i| json!({
                "id": i.id,
                "line": i.line,
                "date": i.date,
                "deadline": i.legal_deadline,
                "days_left": rules::days_until(i.legal_deadline, today),
                "warn_from": rules::warn_from(i.legal_deadline),
            })),
            "min_payout_cents": rules::MIN_PAYOUT_CENTS,
            "dticket_monthly_cap_cents": rules::dticket_monthly_cap_cents(),
        }
    }))
}

pub async fn claims(State(s): State<Shared>) -> Json<Vec<Claim>> {
    Json(s.read().unwrap().claims.clone())
}

#[derive(Deserialize)]
pub struct DraftRequest {
    pub desk: String,
    #[serde(default)]
    pub incident_ids: Option<Vec<String>>,
}

pub async fn claim_draft(State(s): State<Shared>, Json(d): Json<DraftRequest>) -> ApiResult {
    let mut s = s.write().unwrap();
    let ids: Vec<String> = match d.incident_ids {
        Some(ids) => ids,
        None => s.incidents.iter().filter(|i| i.status.is_open() && i.desk == d.desk).map(|i| i.id.clone()).collect(),
    };
    if ids.is_empty() {
        return Err(err(StatusCode::BAD_REQUEST, "no open incidents for this desk"));
    }
    let ngo_id = s.me.settings.ngo_id.clone();
    let ngo = s.ngos.iter().find(|n| n.id == ngo_id).cloned().ok_or_else(|| err(StatusCode::BAD_REQUEST, "unknown ngo"))?;
    let selected: Vec<&Incident> = s.incidents.iter().filter(|i| ids.contains(&i.id)).collect();
    let amount: Cents = selected.iter().map(|i| i.amount_cents).sum();
    let mut months: Vec<String> = selected.iter().map(|i| i.date.format("%Y-%m").to_string()).collect();
    months.sort();
    months.dedup();
    let operator = s.operators.iter().find(|o| o.desk == d.desk).cloned();
    let claim = Claim {
        id: uuid::Uuid::new_v4().to_string(),
        desk: d.desk.clone(),
        incident_ids: ids,
        ngo_id: ngo.id.clone(),
        account_holder: ngo.account_holder.clone(),
        iban: ngo.iban.clone(),
        ticket_months: months,
        attachments: vec![],
        signed_by: None,
        status: ClaimStatus::Draft,
        sent_at: None,
        expected_reply_by: None,
        amount_claimed_cents: amount,
        amount_confirmed_cents: None,
    };
    s.claims.insert(0, claim.clone());
    Ok(Json(json!({
        "claim": claim,
        "desk_address": operator.as_ref().map(|o| o.postal_address.clone()),
        "desk_email": operator.as_ref().and_then(|o| o.email.clone()),
        "personal_data_required": s.me.personal_data.is_none(),
        "relay_address": s.me.relay_address,
    })))
}

#[derive(Deserialize)]
pub struct ClaimPatch {
    pub ngo_id: Option<String>,
    pub attachments: Option<Vec<String>>,
}

pub async fn claim_patch(State(s): State<Shared>, Path(id): Path<String>, Json(p): Json<ClaimPatch>) -> ApiResult {
    let mut s = s.write().unwrap();
    let ngo = p.ngo_id.as_ref().and_then(|n| s.ngos.iter().find(|x| &x.id == n).cloned());
    let c = s.claims.iter_mut().find(|c| c.id == id).ok_or_else(|| err(StatusCode::NOT_FOUND, "claim not found"))?;
    if let Some(n) = ngo {
        c.ngo_id = n.id;
        c.account_holder = n.account_holder;
        c.iban = n.iban;
    }
    if let Some(a) = p.attachments {
        c.attachments = a;
    }
    Ok(Json(json!(c)))
}

#[derive(Deserialize)]
pub struct Sign {
    pub typed_name: String,
}

pub async fn claim_sign(State(s): State<Shared>, Path(id): Path<String>, Json(p): Json<Sign>) -> ApiResult {
    let mut s = s.write().unwrap();
    let c = s.claims.iter_mut().find(|c| c.id == id).ok_or_else(|| err(StatusCode::NOT_FOUND, "claim not found"))?;
    c.signed_by = Some(p.typed_name);
    Ok(Json(json!(c)))
}

/// The relay: nothing leaves without a signature and this explicit call.
pub async fn claim_send(State(s): State<Shared>, Path(id): Path<String>) -> ApiResult {
    let mut s = s.write().unwrap();
    let today = s.today;
    let me_name = s.me.personal_data.as_ref().map(|p| p.name.clone()).unwrap_or_else(|| s.me.nickname.clone());
    let me_email = s.me.personal_data.as_ref().map(|p| p.email.clone());
    let relay = s.me.relay_address.clone();
    let claim = s.claims.iter().find(|c| c.id == id).cloned().ok_or_else(|| err(StatusCode::NOT_FOUND, "claim not found"))?;
    if claim.signed_by.is_none() {
        return Err(err(StatusCode::PRECONDITION_FAILED, "claim not signed"));
    }
    let (Some(relay), Some(me_email)) = (relay, me_email) else {
        return Err(err(StatusCode::PRECONDITION_FAILED, "personal data and relay address required"));
    };
    let to = s
        .operators
        .iter()
        .find(|o| o.desk == claim.desk)
        .and_then(|o| o.email.clone())
        .ok_or_else(|| err(StatusCode::PRECONDITION_FAILED, "this desk has no e-mail address; use the paper route"))?;
    let body = format!(
        "Sehr geehrte Damen und Herren,\n\nanbei mein gesammelter Antrag auf Entschädigung nach VO (EU) 2021/782 (wiederholte Verspätungen, Zeitfahrkarte). Die Einzelfälle sind im Formular unter Punkt 6 aufgeführt.\n\nKontoinhaber: {}\n\nDiese E-Mail wurde über Verspätomat übermittelt, eine Ausfüll- und Weiterleitungshilfe. Antragsteller ist {}.\n\nMit freundlichen Grüßen\n{}",
        claim.account_holder, me_name, me_name
    );
    let mail = Mail {
        id: uuid::Uuid::new_v4().to_string(),
        claim_id: Some(claim.id.clone()),
        incident_ids: claim.incident_ids.clone(),
        direction: MailDirection::Out,
        from: format!("{me_name} <{relay}>"),
        to,
        bcc: Some(me_email),
        subject: "Fahrgastrechte: EU-Antragsformular".into(),
        body,
        date: now(),
        attachments: vec!["EU-Antrag.pdf".into()],
        amount_cents: None,
        outcome: None,
        forwarded_at: None,
    };
    s.mails.insert(0, mail.clone());
    for i in s.incidents.iter_mut().filter(|i| claim.incident_ids.contains(&i.id)) {
        i.status = IncidentStatus::Eingereicht;
        i.claim_id = Some(claim.id.clone());
    }
    let c = s.claims.iter_mut().find(|c| c.id == id).unwrap();
    c.status = ClaimStatus::Sent;
    c.sent_at = Some(now());
    c.expected_reply_by = Some(today + Duration::days(rules::REPLY_EXPECTED_DAYS));
    let claim = c.clone();
    rules::refresh_statuses(&mut s.incidents, today);
    Ok(Json(json!({ "claim": claim, "mail": mail })))
}

pub async fn mails(State(s): State<Shared>) -> Json<Vec<Mail>> {
    Json(s.read().unwrap().mails.clone())
}

#[derive(Deserialize)]
pub struct InboundMail {
    pub to: String,
    pub from: String,
    pub subject: String,
    pub body: String,
    #[serde(default)]
    pub claim_id: Option<String>,
}

/// What the mail provider's webhook will deliver. Classification is a stub:
/// a real implementation parses the reply for amount and outcome.
pub async fn inbound_mail(State(s): State<Shared>, Json(m): Json<InboundMail>) -> ApiResult {
    let mut s = s.write().unwrap();
    let today = s.today;
    let claim = match &m.claim_id {
        Some(id) => s.claims.iter().find(|c| &c.id == id).cloned(),
        None => s.claims.iter().find(|c| c.status == ClaimStatus::Sent).cloned(),
    }
    .ok_or_else(|| err(StatusCode::NOT_FOUND, "no sent claim to match"))?;
    let lower = m.body.to_lowercase();
    let outcome = if lower.contains("nicht entsprechen") || lower.contains("abgelehnt") {
        MailOutcome::Rejected
    } else if lower.contains("benötigen wir") || lower.contains("rückfrage") {
        MailOutcome::Question
    } else if lower.contains("überwiesen") || lower.contains("entschädigung von") {
        MailOutcome::Accepted
    } else {
        MailOutcome::Other
    };
    let amount = if outcome == MailOutcome::Accepted { Some(claim.amount_claimed_cents) } else { None };
    let mail = Mail {
        id: uuid::Uuid::new_v4().to_string(),
        claim_id: Some(claim.id.clone()),
        incident_ids: claim.incident_ids.clone(),
        direction: MailDirection::Inbound,
        from: m.from,
        to: m.to,
        bcc: None,
        subject: m.subject,
        body: m.body,
        date: now(),
        attachments: vec![],
        amount_cents: amount,
        outcome: Some(outcome),
        forwarded_at: Some(now()),
    };
    s.mails.insert(0, mail.clone());
    let new_status = match outcome {
        MailOutcome::Accepted => Some(IncidentStatus::Bestaetigt),
        MailOutcome::Rejected => Some(IncidentStatus::Abgelehnt),
        _ => None,
    };
    if let Some(ns) = new_status {
        for i in s.incidents.iter_mut().filter(|i| claim.incident_ids.contains(&i.id)) {
            i.status = ns;
        }
    }
    if let Some(c) = s.claims.iter_mut().find(|c| c.id == claim.id) {
        c.status = match outcome {
            MailOutcome::Accepted => ClaimStatus::Accepted,
            MailOutcome::Rejected => ClaimStatus::Rejected,
            MailOutcome::Question => ClaimStatus::Question,
            MailOutcome::Bounce => ClaimStatus::Bounced,
            MailOutcome::Other => c.status,
        };
        c.amount_confirmed_cents = amount;
    }
    rules::refresh_statuses(&mut s.incidents, today);
    Ok(Json(json!({ "mail": mail, "outcome": outcome })))
}

// ---------------------------------------------------------------------------
// Community
// ---------------------------------------------------------------------------

pub async fn community(State(s): State<Shared>) -> Json<Value> {
    let s = s.read().unwrap();
    let confirmed_here: Cents = s.incidents.iter().filter(|i| i.status == IncidentStatus::Bestaetigt).map(|i| i.amount_cents).sum();
    let submitted_here: Cents = s.incidents.iter().filter(|i| i.status == IncidentStatus::Eingereicht).map(|i| i.amount_cents).sum();
    let per_ngo: Vec<Value> = s
        .ngos
        .iter()
        .map(|n| {
            json!({
                "id": n.id,
                "name": n.name,
                "confirmed_cents": n.confirmed_total_cents + s.incidents.iter().filter(|i| i.ngo_id == n.id && i.status == IncidentStatus::Bestaetigt).map(|i| i.amount_cents).sum::<Cents>(),
                "submitted_cents": n.submitted_total_cents + s.incidents.iter().filter(|i| i.ngo_id == n.id && i.status == IncidentStatus::Eingereicht).map(|i| i.amount_cents).sum::<Cents>(),
            })
        })
        .collect();
    Json(json!({
        "minutes": s.community.minutes + s.rides.iter().filter_map(|r| r.final_delay_minutes).sum::<i64>(),
        "submitted_cents": s.community.submitted_cents + submitted_here,
        "confirmed_cents": s.community.confirmed_cents + confirmed_here,
        "users": s.community.users,
        "ngos": per_ngo,
    }))
}

#[derive(Deserialize)]
pub struct BoardQuery {
    #[serde(default)]
    pub scope: Option<String>,
}

pub async fn boards(State(s): State<Shared>, Query(q): Query<BoardQuery>) -> Json<Vec<BoardEntry>> {
    let s = s.read().unwrap();
    let list = match q.scope.as_deref() {
        Some("city") => &s.boards.city,
        Some("germany") => &s.boards.germany,
        _ => &s.boards.line,
    };
    let list = if s.me.settings.show_on_boards { list.clone() } else { list.iter().filter(|e| !e.is_me).cloned().collect() };
    Json(list)
}

pub async fn teams(State(s): State<Shared>) -> Json<Vec<Team>> {
    Json(s.read().unwrap().teams.clone())
}
