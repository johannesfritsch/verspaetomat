//! The fare catalogue (docs/49 §5, issue #66): what each kind of ticket is owed when a train is
//! late. `fixtures/fares.toml` holds the values — tariffs, products, and a product's rule from a
//! date on — and this module the kinds of rule, the inheritance that resolves a product's rule, and
//! the checks that make a broken catalogue stop the server instead of paying the wrong amount.
//!
//! Everything here is pure. What a set of cases is worth is [`evaluate::evaluate`].

pub mod evaluate;

use std::collections::BTreeMap;
use std::sync::LazyLock;

use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

pub type Cents = i64;

/// Keys of a tariff or product table that are about the entry, not part of its rule.
const META: &[&str] = &["extends", "name", "tariff", "family", "rule_line", "sources", "prices", "versions"];

/// The product families the app asks about first ("Welche Fahrkarte?"). A product outside these is
/// a typo in the catalogue.
pub const FAMILIES: &[&str] = &["deutschlandticket", "bahncard100", "zeitkarte", "streckenzeitkarte", "einzelfahrkarte", "laender_ticket"];

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ByClass<T> {
    pub second: T,
    pub first: T,
}

impl<T: Copy> ByClass<T> {
    pub fn get(&self, first_class: bool) -> T {
        if first_class {
            self.first
        } else {
            self.second
        }
    }
}

/// Which trains a ticket can be delayed on. A ride on a train the ticket does not cover is not
/// that ticket's case.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ValidOn {
    pub regional: bool,
    pub long_distance: bool,
    /// Long-distance sections the ticket is valid on anyway (the D-Ticket on IC Bremen–Norddeich).
    #[serde(default)]
    pub extra_routes: Vec<String>,
    /// Only this operator's trains (FlixTrain).
    #[serde(default)]
    pub operator: Option<String>,
}

/// The three ways a delay turns into money (docs/49 §2.1), and the one way it does not.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum Compensation {
    /// A share of the price paid, stepped by minutes: `[(60, 2500), (120, 5000)]` is 25 % from an
    /// hour, 50 % from two.
    ShareOfPrice { steps: Vec<(u32, u32)> },
    /// A fixed sum per case, stepped by minutes and by class.
    PerCase { steps: Vec<(u32, ByClass<Cents>)> },
    /// Cases from `counts_from` minutes are added up; each full `unit` minutes earns `per_unit`.
    MinutePool { counts_from: u32, unit: u32, per_unit: ByClass<Cents> },
    /// Paid in something that cannot reach the Verein (BahnBonus points).
    NotMoney,
}

impl Compensation {
    /// The fewest minutes of delay that make a case at all.
    pub fn threshold(&self) -> u32 {
        match self {
            Compensation::ShareOfPrice { steps } => steps.first().map(|s| s.0).unwrap_or(60),
            Compensation::PerCase { steps } => steps.first().map(|s| s.0).unwrap_or(60),
            Compensation::MinutePool { counts_from, .. } => *counts_from,
            Compensation::NotMoney => 60,
        }
    }
}

/// What is summed, capped and held against the threshold together.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Window {
    /// One ticket, one journey: a single ticket.
    Ticket,
    /// The day the ticket is valid (Länder-Ticket).
    ValidityDay,
    /// The ticket's own validity, from `valid_from` to `valid_until`.
    Validity,
    CalendarMonth,
    Semester,
    /// An open-ended subscription: as long as the ticket runs (the D-Ticket, docs/49 §9).
    Subscription,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Cap {
    /// Basis points of the price paid for the window (2500 = 25 %).
    #[serde(default)]
    pub share: Option<u32>,
    /// A fixed ceiling (the hvv Semesterticket's 4,50 €).
    #[serde(default)]
    pub fixed: Option<Cents>,
    pub per: Window,
}

/// The Bagatellgrenze and which side of it the amount has to be on: DB pays "4 € and more"
/// (`inclusive`), the Deutschlandtarif's season tickets and FlixTrain only what "exceeds 4 €".
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Threshold {
    pub cents: Cents,
    pub inclusive: bool,
}

impl Threshold {
    pub fn met(&self, amount: Cents) -> bool {
        if self.inclusive {
            amount >= self.cents
        } else {
            amount > self.cents
        }
    }

    /// The smallest amount that meets it.
    pub fn smallest(&self) -> Cents {
        if self.inclusive {
            self.cents
        } else {
            self.cents + 1
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Rounding {
    /// Commercial rounding to the cent (DB, BB 9.2.1).
    Cent,
    /// Up to a multiple of 5 cents (Deutschlandtarif, most Verbünde).
    #[serde(rename = "up_to_5_cents")]
    UpTo5Cents,
}

impl Rounding {
    /// `price × share` in basis points, rounded the tariff's way.
    pub fn share(&self, price: Cents, basis_points: u32) -> Cents {
        let exact = price * basis_points as Cents; // in 1/10000 cent
        match self {
            Rounding::Cent => (exact + 5_000) / 10_000,
            Rounding::UpTo5Cents => (exact + 49_999) / 50_000 * 5,
        }
    }
}

/// When a pot may leave the house.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Submit {
    Immediately,
    /// Only once the window is over (a Wochen- or Monatskarte, a Länder-Ticket's day).
    AfterWindow,
    /// After the window for tickets valid a month or less, as soon as payable for longer ones.
    AfterShortWindow,
    WhenPayable,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DeadlineFrom {
    Ride,
    ValidityEnd,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Deadline {
    pub from: DeadlineFrom,
    /// The hard limit.
    pub months: u32,
    /// What we aim for: "reich ein, solange es frisch ist".
    pub aim_months: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Payout {
    Money,
    Points,
    CashInPerson,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Claimant {
    Passenger,
    HolderOnly,
    SchoolAuthority,
}

/// Which number identifies the ticket on the form (EU form 3.2.7).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NumberKind {
    Booking,
    Abo,
    Zeitkarte,
    Bahncard,
    None,
}

/// What a claim for this ticket has to carry.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Form {
    /// The EU form's "wiederholte Verspätungen … Zeitfahrkarte" box.
    pub season_box: bool,
    pub number: NumberKind,
    pub price_proof: bool,
    /// A copy of the ticket.
    pub copy: bool,
    /// The BahnCard 100 is identified by number and date of birth instead of a copy.
    pub birth_date: bool,
}

/// Whether the app offers the product, and with what warning. A value we could not verify is a
/// caveat the passenger reads, never a promise.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Offer {
    Offered,
    WithCaveat,
    Hidden,
}

/// Everything a product promises from one date on. Every field is required after inheritance: a
/// catalogue that leaves one open does not load.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Rule {
    pub valid_on: ValidOn,
    pub compensation: Compensation,
    pub window: Window,
    /// Fewest cases a pot needs (NRW: 3). 0 = no minimum.
    pub min_cases: u32,
    pub caps: Vec<Cap>,
    pub payout_min: Threshold,
    pub rounding: Rounding,
    pub submit: Submit,
    pub deadline: Deadline,
    pub payout: Payout,
    pub claimant: Claimant,
    /// "operator" = whoever ran the late train (docs/04); anything else is a fixed desk.
    pub desk: String,
    /// "erheblich ermäßigt" (EVO § 3 Abs. 4): no switching to a higher train.
    pub reduced_fare: bool,
    /// Minutes of expected delay from which the Zugbindung is released; 0 = never.
    pub release_after_min: u32,
    pub form: Form,
    pub offer: Offer,
    pub caveat: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Grade {
    Verified,
    Secondary,
    Inferred,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Source {
    pub field: String,
    pub doc: String,
    pub quote: String,
    pub grade: Grade,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Price {
    pub valid_from: NaiveDate,
    pub cents: Cents,
    #[serde(default)]
    pub first_cents: Option<Cents>,
}

/// A product with its rule resolved through its tariff chain.
#[derive(Debug, Clone, Serialize)]
pub struct Product {
    pub id: String,
    pub tariff: String,
    pub tariff_name: String,
    pub family: String,
    pub name: String,
    pub rule_line: String,
    /// List prices by date: the cap's basis when the passenger has not entered what they paid.
    pub prices: Vec<Price>,
    /// The sources of the tariff chain and of the product, tariff first.
    pub sources: Vec<Source>,
    /// The rule from each date on, oldest first; the first is valid from the beginning of time.
    pub versions: Vec<(NaiveDate, Rule)>,
}

impl Product {
    /// The rule in force on `date`.
    pub fn rule_on(&self, date: NaiveDate) -> &Rule {
        self.versions.iter().rev().find(|(from, _)| *from <= date).map(|(_, r)| r).unwrap_or(&self.versions[0].1)
    }

    /// The newest rule, for callers that have no date (the legacy per-case amounts).
    pub fn latest(&self) -> &Rule {
        &self.versions[self.versions.len() - 1].1
    }

    /// The list price on `date` in that class, if the catalogue knows one.
    pub fn price_on(&self, date: NaiveDate, first_class: bool) -> Option<Cents> {
        let p = self.prices.iter().rev().find(|p| p.valid_from <= date)?;
        if first_class {
            p.first_cents
        } else {
            Some(p.cents)
        }
    }
}

#[derive(Debug)]
pub struct Catalogue {
    pub products: BTreeMap<String, Product>,
}

static CATALOGUE: LazyLock<Catalogue> = LazyLock::new(|| Catalogue::parse(include_str!("../../fixtures/fares.toml")).unwrap_or_else(|e| panic!("fixtures/fares.toml: {e}")));

/// The embedded catalogue. The server touches it at start (`main.rs`), so a broken file stops the
/// boot rather than the first claim.
pub fn catalogue() -> &'static Catalogue {
    &CATALOGUE
}

impl Catalogue {
    pub fn get(&self, id: &str) -> Option<&Product> {
        self.products.get(id)
    }

    /// A product that must exist: the legacy mapping and tests name them by id.
    pub fn product(&self, id: &str) -> &Product {
        self.get(id).unwrap_or_else(|| panic!("fare product {id} is not in the catalogue"))
    }

    pub fn parse(raw: &str) -> anyhow::Result<Catalogue> {
        let doc: toml::Value = toml::from_str(raw)?;
        let doc = to_json(doc);
        let tariffs = doc.get("tariffs").and_then(Value::as_object).cloned().unwrap_or_default();
        let products = doc.get("products").and_then(Value::as_object).cloned().unwrap_or_default();
        if !tariffs.contains_key("eu_minimum") {
            anyhow::bail!("the root tariff eu_minimum is missing");
        }
        let mut out = BTreeMap::new();
        for id in products.keys() {
            out.insert(id.clone(), resolve_product(id, &tariffs, &products)?);
        }
        Ok(Catalogue { products: out })
    }
}

/// TOML dates become ISO strings, so the rest can be plain serde_json.
fn to_json(v: toml::Value) -> Value {
    match v {
        toml::Value::String(s) => Value::String(s),
        toml::Value::Integer(i) => Value::from(i),
        toml::Value::Float(f) => Value::from(f),
        toml::Value::Boolean(b) => Value::Bool(b),
        toml::Value::Datetime(d) => Value::String(d.to_string()),
        toml::Value::Array(a) => Value::Array(a.into_iter().map(to_json).collect()),
        toml::Value::Table(t) => Value::Object(t.into_iter().map(|(k, v)| (k, to_json(v))).collect()),
    }
}

/// `over` wins; tables are replaced whole, not merged, so a product that sets `caps` or
/// `valid_on` says all of it.
fn overlay(base: &mut Map<String, Value>, over: &Map<String, Value>) {
    for (k, v) in over {
        base.insert(k.clone(), v.clone());
    }
}

fn sources_of(entry: &Map<String, Value>) -> anyhow::Result<Vec<Source>> {
    match entry.get("sources") {
        Some(v) => Ok(serde_json::from_value(v.clone())?),
        None => Ok(Vec::new()),
    }
}

/// A tariff's fields with everything it inherits, root first; and its sources in the same order.
fn resolve_tariff(id: &str, tariffs: &Map<String, Value>, seen: &mut Vec<String>) -> anyhow::Result<(Map<String, Value>, Vec<Source>)> {
    if seen.iter().any(|s| s == id) {
        anyhow::bail!("tariff {id} extends itself");
    }
    seen.push(id.to_string());
    let entry = tariffs.get(id).and_then(Value::as_object).ok_or_else(|| anyhow::anyhow!("unknown tariff {id}"))?;
    let (mut fields, mut sources) = match entry.get("extends").and_then(Value::as_str) {
        Some(parent) => resolve_tariff(parent, tariffs, seen)?,
        None => (Map::new(), Vec::new()),
    };
    overlay(&mut fields, entry);
    sources.extend(sources_of(entry)?);
    Ok((fields, sources))
}

/// A product's own fields with those of the products it extends, parent first.
fn product_chain(id: &str, products: &Map<String, Value>, seen: &mut Vec<String>) -> anyhow::Result<(Map<String, Value>, Vec<Source>)> {
    if seen.iter().any(|s| s == id) {
        anyhow::bail!("product {id} extends itself");
    }
    seen.push(id.to_string());
    let entry = products.get(id).and_then(Value::as_object).ok_or_else(|| anyhow::anyhow!("unknown product {id}"))?;
    let (mut fields, mut sources) = match entry.get("extends").and_then(Value::as_str) {
        Some(parent) => product_chain(parent, products, seen)?,
        None => (Map::new(), Vec::new()),
    };
    overlay(&mut fields, entry);
    sources.extend(sources_of(entry)?);
    Ok((fields, sources))
}

fn rule_from(fields: &Map<String, Value>) -> anyhow::Result<Rule> {
    let mut rule = fields.clone();
    for k in META {
        rule.remove(*k);
    }
    rule.remove("valid_from");
    let rule: Rule = serde_json::from_value(Value::Object(rule))?;
    check_rule(&rule)?;
    Ok(rule)
}

fn check_rule(r: &Rule) -> anyhow::Result<()> {
    fn ascending<T>(steps: &[(u32, T)]) -> bool {
        !steps.is_empty() && steps.windows(2).all(|w| w[0].0 < w[1].0)
    }
    match &r.compensation {
        Compensation::ShareOfPrice { steps } if !ascending(steps) || steps.iter().any(|s| s.1 > 10_000) => anyhow::bail!("share steps must ascend and stay at or below 100 %"),
        Compensation::PerCase { steps } if !ascending(steps) => anyhow::bail!("per-case steps must ascend"),
        Compensation::MinutePool { unit: 0, .. } => anyhow::bail!("a minute pool needs a unit"),
        _ => {}
    }
    for c in &r.caps {
        if c.share.is_some() == c.fixed.is_some() {
            anyhow::bail!("a cap is either a share or a fixed sum");
        }
    }
    if r.offer == Offer::WithCaveat && r.caveat.trim().is_empty() {
        anyhow::bail!("offer with_caveat needs the caveat");
    }
    Ok(())
}

fn resolve_product(id: &str, tariffs: &Map<String, Value>, products: &Map<String, Value>) -> anyhow::Result<Product> {
    let ctx = |e: anyhow::Error| anyhow::anyhow!("product {id}: {e}");
    let (own, own_sources) = product_chain(id, products, &mut Vec::new()).map_err(ctx)?;
    let tariff = own.get("tariff").and_then(Value::as_str).ok_or_else(|| anyhow::anyhow!("product {id} names no tariff"))?.to_string();
    let (mut fields, mut sources) = resolve_tariff(&tariff, tariffs, &mut Vec::new()).map_err(ctx)?;
    let tariff_name = fields.get("name").and_then(Value::as_str).unwrap_or(&tariff).to_string();
    overlay(&mut fields, &own);
    sources.extend(own_sources);

    let text = |k: &str| fields.get(k).and_then(Value::as_str).map(str::to_string).ok_or_else(|| anyhow::anyhow!("product {id} has no {k}"));
    let family = text("family")?;
    if !FAMILIES.contains(&family.as_str()) {
        anyhow::bail!("product {id}: unknown family {family}");
    }
    let prices: Vec<Price> = match fields.get("prices") {
        Some(v) => serde_json::from_value(v.clone()).map_err(|e| ctx(e.into()))?,
        None => Vec::new(),
    };
    if !prices.windows(2).all(|w| w[0].valid_from < w[1].valid_from) {
        anyhow::bail!("product {id}: prices must be in date order");
    }

    let mut versions = vec![(NaiveDate::MIN, rule_from(&fields).map_err(ctx)?)];
    if let Some(list) = fields.get("versions").and_then(Value::as_array) {
        let mut current = fields.clone();
        for v in list {
            let v = v.as_object().ok_or_else(|| anyhow::anyhow!("product {id}: a version is a table"))?;
            let from: NaiveDate = serde_json::from_value(v.get("valid_from").cloned().unwrap_or(Value::Null)).map_err(|e| anyhow::anyhow!("product {id}: version without valid_from: {e}"))?;
            if versions.last().is_some_and(|(last, _)| *last >= from) {
                anyhow::bail!("product {id}: versions must be in date order");
            }
            overlay(&mut current, v);
            versions.push((from, rule_from(&current).map_err(ctx)?));
        }
    }
    for s in &sources {
        if s.quote.trim().is_empty() || s.doc.trim().is_empty() {
            anyhow::bail!("product {id}: a source on {} has no document or quote", s.field);
        }
    }

    Ok(Product { id: id.to_string(), tariff, tariff_name, family, name: text("name")?, rule_line: text("rule_line")?, prices, sources, versions })
}

/// The per-case amount the ledger has booked since before the catalogue (`rules::claim_amount_cents`):
/// one case, its own amount, nothing pooled. A minute pool counts a lone case as one unit from an
/// hour, which is what every incident was worth before pots (phase 2 of docs/50) replace it.
pub fn legacy_case_cents(product: &Product, delay_minutes: i64, first_class: bool, fare_cents: Option<Cents>) -> Option<Cents> {
    let rule = product.latest();
    let delay = delay_minutes.max(0) as u32;
    match &rule.compensation {
        Compensation::MinutePool { per_unit, .. } => (delay >= 60).then(|| per_unit.get(first_class)),
        Compensation::PerCase { steps } => steps.iter().rev().find(|s| s.0 <= delay).map(|s| s.1.get(first_class)),
        Compensation::ShareOfPrice { steps } => {
            let share = steps.iter().rev().find(|s| s.0 <= delay)?.1;
            Some(rule.rounding.share(fare_cents?, share))
        }
        Compensation::NotMoney => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(y: i32, m: u32, day: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(y, m, day).unwrap()
    }

    #[test]
    fn the_catalogue_loads_and_every_family_has_a_product() {
        let c = catalogue();
        for f in FAMILIES {
            assert!(c.products.values().any(|p| p.family == *f), "no product in family {f}");
        }
        for p in c.products.values() {
            assert!(!p.sources.is_empty(), "{} has no source at all", p.id);
        }
    }

    #[test]
    fn products_inherit_from_their_tariff_and_their_parent() {
        let c = catalogue();
        // The Deutschlandtarif rounds up to 5 cents; DB rounds commercially.
        assert_eq!(c.product("deutschlandticket").latest().rounding, Rounding::UpTo5Cents);
        assert_eq!(c.product("einzel_db").latest().rounding, Rounding::Cent);
        // NRW extends the standard Verbund product and sets only what differs.
        let nrw = c.product("zeitkarte_vrr_nrw").latest();
        let std = c.product("zeitkarte_spnv").latest();
        assert_eq!(nrw.min_cases, 3);
        assert_eq!(std.min_cases, 0);
        assert_eq!(nrw.compensation, std.compensation);
        assert_eq!(nrw.valid_on, std.valid_on);
        // A tariff's deadline reaches its products: MVV three months after the ticket ends.
        assert_eq!(c.product("zeitkarte_mvv").latest().deadline.from, DeadlineFrom::ValidityEnd);
        assert_eq!(c.product("einzel_flixtrain").latest().desk, "FlixTrain");
        assert_eq!(c.product("einzel_db").latest().desk, "operator");
    }

    #[test]
    fn prices_by_date() {
        let dt = catalogue().product("deutschlandticket");
        assert_eq!(dt.price_on(d(2025, 6, 1), false), Some(5800));
        assert_eq!(dt.price_on(d(2026, 1, 1), false), Some(6300));
        assert_eq!(dt.price_on(d(2024, 12, 31), false), None, "before the first price the catalogue knows none");
        assert_eq!(catalogue().product("bahncard100").price_on(d(2026, 9, 1), true), Some(799900));
    }

    #[test]
    fn versions_apply_from_their_date() {
        let raw = r#"
            [tariffs.eu_minimum]
            name = "EU"
            valid_on = { regional = true, long_distance = true }
            compensation = { kind = "share_of_price", steps = [[60, 2500], [120, 5000]] }
            window = "ticket"
            min_cases = 0
            caps = []
            payout_min = { cents = 400, inclusive = true }
            rounding = "cent"
            submit = "immediately"
            deadline = { from = "ride", months = 12, aim_months = 3 }
            payout = "money"
            claimant = "passenger"
            desk = "operator"
            reduced_fare = false
            release_after_min = 0
            form = { season_box = false, number = "booking", price_proof = false, copy = true, birth_date = false }
            offer = "offered"
            caveat = ""
            [tariffs.eu_minimum.sources]
            [products.x]
            tariff = "eu_minimum"
            family = "einzelfahrkarte"
            name = "X"
            rule_line = "x"
            sources = [{ field = "compensation", doc = "d", quote = "q", grade = "verified" }]
            versions = [{ valid_from = 2026-11-01, rounding = "up_to_5_cents" }]
        "#;
        // `[tariffs.eu_minimum.sources]` above is an empty table, which is not a list of sources.
        assert!(Catalogue::parse(raw).is_err(), "a malformed source list does not load");
        let raw = raw.replace("[tariffs.eu_minimum.sources]\n", "");
        let c = Catalogue::parse(&raw).unwrap();
        let x = c.product("x");
        assert_eq!(x.rule_on(d(2026, 10, 31)).rounding, Rounding::Cent);
        assert_eq!(x.rule_on(d(2026, 11, 1)).rounding, Rounding::UpTo5Cents);
    }

    #[test]
    fn a_catalogue_with_a_hole_does_not_load() {
        let raw = include_str!("../../fixtures/fares.toml").replacen("rounding = \"cent\"\n", "", 1);
        assert!(Catalogue::parse(&raw).is_err(), "eu_minimum without rounding leaves every product without one");
        let raw = include_str!("../../fixtures/fares.toml").replacen("window = \"subscription\"", "window = \"forever\"", 1);
        assert!(Catalogue::parse(&raw).is_err(), "an unknown window is a typo, not a default");
    }

    #[test]
    fn rounding() {
        assert_eq!(Rounding::Cent.share(3990, 2500), 998, "997,5 rounds up commercially");
        assert_eq!(Rounding::Cent.share(1299, 2500), 325);
        assert_eq!(Rounding::UpTo5Cents.share(1730, 2500), 435, "4,325 € up to 4,35 €");
        assert_eq!(Rounding::UpTo5Cents.share(1600, 2500), 400, "already a multiple of 5");
    }

    #[test]
    fn legacy_amounts_are_what_the_ledger_booked() {
        let c = catalogue();
        assert_eq!(legacy_case_cents(c.product("deutschlandticket"), 68, false, None), Some(150));
        assert_eq!(legacy_case_cents(c.product("deutschlandticket"), 59, false, None), None);
        assert_eq!(legacy_case_cents(c.product("deutschlandticket"), 60, true, None), Some(225));
        assert_eq!(legacy_case_cents(c.product("zeitkarte_spnv"), 70, false, None), Some(150));
        assert_eq!(legacy_case_cents(c.product("streckenzeitkarte"), 70, false, None), Some(500));
        assert_eq!(legacy_case_cents(c.product("bahncard100"), 61, false, None), Some(1000));
        assert_eq!(legacy_case_cents(c.product("einzel_db"), 124, false, Some(3990)), Some(1995));
        assert_eq!(legacy_case_cents(c.product("einzel_db"), 70, false, None), None, "no fare, no amount");
    }
}
