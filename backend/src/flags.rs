//! Feature flags (#41): behaviour the server can turn on without a new build — for everybody,
//! for a fraction, or for one person.
//!
//! A flag is a `&'static` item in this file. Call sites name the item, never the string, so a
//! typo is a compile error and deleting a flag breaks every reader — which is how a flag is
//! retired without forgetting one. The `flags` table only holds what a human has said since.
//!
//! The rule from #40 survives in the type: **false is the behaviour that already shipped.**
//! [`BoolFlag`] has no `default` field. A flag whose default ought to be on is named wrong —
//! invert the name, the way `stations_local` is named rather than `use_server_stations`. `int`
//! and `string` have no such zero, so the rule is restated instead of quietly dropped: the
//! default is what already shipped, it is written here beside the client constant it mirrors,
//! and **the server never sends a value equal to its default**. "The field is absent" is then
//! the path every build takes on every request every day, and cannot rot the way an untested
//! fallback does.
//!
//! The whole set lives in memory and is reloaded on change, so reading a flag is a function call
//! and this system adds **no database query to any request path**, at any number of flags.
//!
//! A flag never governs money: `rules.rs` owns every amount, every readiness and every payee.

use std::collections::HashMap;
use std::sync::Arc;

use axum::{
    extract::State,
    http::{header, HeaderMap, StatusCode},
    response::{IntoResponse, Response},
};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use uuid::Uuid;

use crate::db::rows::CustomerRow;
use crate::AppState;

// ---------------------------------------------------------------------------
// The registry
// ---------------------------------------------------------------------------

/// No `default` field, on purpose: a bool flag is false until somebody says otherwise (#40).
pub struct BoolFlag {
    pub key: &'static str,
    /// Whether this flag goes to the app. Backend-only flags never leave the server.
    pub wire: bool,
    pub note: &'static str,
}

pub struct IntFlag {
    pub key: &'static str,
    /// What already shipped, beside the client constant it mirrors.
    pub default: i64,
    pub wire: bool,
    pub note: &'static str,
}

pub struct StringFlag {
    pub key: &'static str,
    /// What already shipped, beside the client constant it mirrors.
    pub default: &'static str,
    pub wire: bool,
    pub note: &'static str,
}

pub static STATIONS_LOCAL: BoolFlag = BoolFlag {
    key: "stations_local",
    wire: true,
    note: "#40. Whether the NATIVE background layer answers \"which stations are near me\" from \
           the .vst extract on disk (docs/45) instead of GET /v1/stations/nearby. \
           NOT READ BY ANYTHING YET: handlers::geofence still reads app_switches (0037) and the \
           `stations_local` field on GET /v1/me/geofence still comes from there, byte for byte, \
           for the builds in TestFlight. Setting this flag changes no behaviour until that call \
           site moves — the last step of #41. May not be retired while build 64 or later is \
           installable.",
};

pub enum Spec {
    Bool(&'static BoolFlag),
    Int(&'static IntFlag),
    Str(&'static StringFlag),
}

/// Every flag that exists. A key not in here is an orphan: it is never loaded, never served, and
/// an admin write naming it is a 404 rather than an implicit create.
pub static ALL: &[Spec] = &[Spec::Bool(&STATIONS_LOCAL)];

impl Spec {
    pub fn key(&self) -> &'static str {
        match self {
            Spec::Bool(f) => f.key,
            Spec::Int(f) => f.key,
            Spec::Str(f) => f.key,
        }
    }

    /// Matches the `kind` check constraint in migration 0038.
    pub fn kind(&self) -> &'static str {
        match self {
            Spec::Bool(_) => "bool",
            Spec::Int(_) => "int",
            Spec::Str(_) => "string",
        }
    }

    /// The behaviour that already shipped, as JSON.
    pub fn default_json(&self) -> Value {
        match self {
            Spec::Bool(_) => json!(false),
            Spec::Int(f) => json!(f.default),
            Spec::Str(f) => json!(f.default),
        }
    }

    pub fn wire(&self) -> bool {
        match self {
            Spec::Bool(f) => f.wire,
            Spec::Int(f) => f.wire,
            Spec::Str(f) => f.wire,
        }
    }

    pub fn note(&self) -> &'static str {
        match self {
            Spec::Bool(f) => f.note,
            Spec::Int(f) => f.note,
            Spec::Str(f) => f.note,
        }
    }

    /// Whether a stored value is of this flag's type. A value that is not gets one warning and
    /// is then ignored by the evaluator, which falls back to the default.
    pub fn accepts(&self, v: &Value) -> bool {
        match self {
            Spec::Bool(_) => v.is_boolean(),
            Spec::Int(_) => v.is_i64(),
            Spec::Str(_) => v.is_string(),
        }
    }
}

/// The descriptor for a key from the wire, or nothing at all.
pub fn spec(key: &str) -> Option<&'static Spec> {
    ALL.iter().find(|s| s.key() == key)
}

pub fn keys() -> Vec<&'static str> {
    ALL.iter().map(Spec::key).collect()
}

// ---------------------------------------------------------------------------
// The bucket
// ---------------------------------------------------------------------------

/// Stable per (flag, customer), stored nowhere. Basis points, 0..=9999.
///
/// The flag key is in the salt, and that is the whole point: hashing the customer id alone would
/// make every flag pick the SAME tenth of the userbase — the same people would be the permanent
/// guinea pigs on every axis at once, and two flags at 10 % would overlap 100 % instead of the
/// 1 % that lets you attribute anything.
///
/// The uuid goes in as its 16 raw bytes, not its text form: a uuid has three spellings and one
/// byte form, and a formatting change must never reshuffle a live rollout. Both inputs are
/// immutable, so a bucket survives restarts, deploys, pg_dump/restore and a move to another
/// machine, and `bucket < p` is monotone in `p` — widening 9 % to 11 % only adds people.
///
/// Modulo bias: 2^64 / 10000 leaves a remainder of 1616, a relative excess of 5.4e-16.
pub fn bucket(key: &str, customer: Uuid) -> u32 {
    let mut buf = Vec::with_capacity(key.len() + 17);
    buf.extend_from_slice(key.as_bytes());
    buf.push(b':');
    buf.extend_from_slice(customer.as_bytes());
    let d = Sha256::digest(&buf);
    (u64::from_be_bytes(d[..8].try_into().expect("8 bytes")) % 10_000) as u32
}

// ---------------------------------------------------------------------------
// The snapshot
// ---------------------------------------------------------------------------

/// What a human has said about one flag.
#[derive(Debug, Clone)]
pub struct Row {
    pub value: Value,
    /// Null: `value` applies to everybody. Set: to the customers whose bucket falls below it.
    pub rollout_bp: Option<i32>,
}

/// Who is being asked about: the id that buckets a rollout, and this customer's overrides.
///
/// A borrow of the customer row every authenticated request has already loaded, so evaluating a
/// targeted flag costs no query.
#[derive(Clone, Copy)]
pub struct Who<'a> {
    pub id: Uuid,
    pub overrides: &'a Value,
}

impl<'a> Who<'a> {
    pub fn new(id: Uuid, overrides: &'a Value) -> Self {
        Who { id, overrides }
    }
}

impl<'a> From<&'a CustomerRow> for Who<'a> {
    fn from(c: &'a CustomerRow) -> Self {
        Who { id: c.id, overrides: &c.flag_overrides }
    }
}

/// Where an answer came from. The admin view prints it; nothing on a request path branches on it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Source {
    Override,
    Rollout,
    Global,
    Default,
}

impl Source {
    pub fn as_str(self) -> &'static str {
        match self {
            Source::Override => "override",
            Source::Rollout => "rollout",
            Source::Global => "global",
            Source::Default => "default",
        }
    }
}

/// Every live flag, in memory, plus the public document rendered once.
///
/// Rebuilt from Postgres at startup and after every admin write. Nothing mutates it in place: a
/// reader holds an `Arc` and the writer swaps a new one in — the `stations` pattern.
pub struct Table {
    rows: HashMap<&'static str, Row>,
    doc: Arc<str>,
    etag: String,
}

pub type Shared = Arc<std::sync::RwLock<Arc<Table>>>;

impl Default for Table {
    fn default() -> Self {
        Table::new(HashMap::new())
    }
}

impl Table {
    /// Keyed by the registry's `&'static str`, so an orphan cannot be in here at all.
    pub fn new(rows: HashMap<&'static str, Row>) -> Table {
        let mut t = Table { rows, doc: Arc::from("{}"), etag: String::new() };
        let body = json!({ "flags": t.wire_map(None) }).to_string();
        // A strong ETag over the bytes we serve: two snapshots that look the same to a phone get
        // the same ETag, which is exactly when a 304 is the right answer.
        t.etag = format!("\"{}\"", hex::encode(&Sha256::digest(body.as_bytes())[..8]));
        t.doc = Arc::from(body.as_str());
        t
    }

    pub fn len(&self) -> usize {
        self.rows.len()
    }

    pub fn is_empty(&self) -> bool {
        self.rows.is_empty()
    }

    pub fn row(&self, key: &str) -> Option<&Row> {
        self.rows.get(key)
    }

    pub fn etag(&self) -> &str {
        &self.etag
    }

    /// The raw JSON somebody has set for this customer, or nothing — in which case the caller
    /// falls back to the default.
    ///
    /// Order, first match wins: **the individual, then the rollout, then the global value.** The
    /// individual beats the rollout on purpose: forcing a flag off for one person while a
    /// rollout runs is what targeting is for.
    pub fn raw(&self, key: &str, who: Option<Who<'_>>) -> Option<Value> {
        if let Some(w) = who {
            if let Some(v) = w.overrides.get(key) {
                if !v.is_null() {
                    return Some(v.clone());
                }
            }
        }
        let row = self.rows.get(key)?;
        match row.rollout_bp {
            None => Some(row.value.clone()),
            // A rollout has nobody to bucket when there is no customer in front of it, so the
            // answer is the default — which is why a flag under a rollout is never in the public
            // document.
            Some(bp) => (bucket(key, who?.id) < bp as u32).then(|| row.value.clone()),
        }
    }

    /// Where [`raw`](Self::raw) got its answer. Same order, for the admin view.
    pub fn source(&self, key: &str, who: Option<Who<'_>>) -> Source {
        if let Some(w) = who {
            if w.overrides.get(key).is_some_and(|v| !v.is_null()) {
                return Source::Override;
            }
        }
        match self.rows.get(key).map(|r| r.rollout_bp) {
            None => Source::Default,
            Some(None) => Source::Global,
            Some(Some(bp)) => match who {
                Some(w) if bucket(key, w.id) < bp as u32 => Source::Rollout,
                _ => Source::Default,
            },
        }
    }

    /// #40, in the last line: a value that is missing, orphaned or of the wrong type is false.
    pub fn bool(&self, f: &BoolFlag, who: Option<Who<'_>>) -> bool {
        self.raw(f.key, who).and_then(|v| v.as_bool()).unwrap_or(false)
    }

    pub fn int(&self, f: &IntFlag, who: Option<Who<'_>>) -> i64 {
        self.raw(f.key, who).and_then(|v| v.as_i64()).unwrap_or(f.default)
    }

    pub fn string(&self, f: &StringFlag, who: Option<Who<'_>>) -> String {
        self.raw(f.key, who)
            .and_then(|v| v.as_str().map(str::to_owned))
            .unwrap_or_else(|| f.default.to_owned())
    }

    /// What one flag evaluates to, typed — so a wrong-typed row is coerced back to the default
    /// here rather than travelling any further.
    pub fn value_of(&self, spec: &Spec, who: Option<Who<'_>>) -> Value {
        match spec {
            Spec::Bool(f) => json!(self.bool(f, who)),
            Spec::Int(f) => json!(self.int(f, who)),
            Spec::Str(f) => json!(self.string(f, who)),
        }
    }

    /// What goes to the app: only `wire` flags, and only those whose value differs from the
    /// default. For booleans that means only the true ones, so the normal payload is `{}` — the
    /// path every build takes every day.
    pub fn wire_map(&self, who: Option<Who<'_>>) -> Value {
        let mut out = serde_json::Map::new();
        for spec in ALL.iter().filter(|s| s.wire()) {
            let v = self.value_of(spec, who);
            if v != spec.default_json() {
                out.insert(spec.key().to_string(), v);
            }
        }
        Value::Object(out)
    }

    /// Every flag with its value and where it came from. The admin view, never the wire.
    pub fn explain(&self, who: Option<Who<'_>>) -> Value {
        let mut out = serde_json::Map::new();
        for spec in ALL {
            out.insert(
                spec.key().to_string(),
                json!({ "value": self.value_of(spec, who), "source": self.source(spec.key(), who).as_str() }),
            );
        }
        Value::Object(out)
    }
}

// ---------------------------------------------------------------------------
// Birth and death
// ---------------------------------------------------------------------------

/// Give every flag in the registry a row, and mark every row the registry has stopped claiming.
///
/// Called once at startup. There is deliberately **no third statement repairing a wrong-typed
/// value**: the obvious one, `where jsonb_typeof(value) <> $kind`, is a trap — `jsonb_typeof`
/// answers 'boolean' and 'number', never 'bool' or 'int', so it matches every bool and int flag
/// and would reset every one of them to its default on every container start, at exactly the
/// moment a kill switch has to hold. A wrong-typed row gets a warning and the evaluator's
/// fallback, which is the behaviour that already shipped.
pub async fn reconcile(pool: &PgPool) -> anyhow::Result<()> {
    for spec in ALL {
        sqlx::query(
            "insert into flags (key, kind, value) values ($1, $2, $3)
             on conflict (key) do update set
                 kind = excluded.kind,
                 orphan = false,
                 updated_at = case when flags.kind <> excluded.kind or flags.orphan then now() else flags.updated_at end",
        )
        .bind(spec.key())
        .bind(spec.kind())
        .bind(spec.default_json())
        .execute(pool)
        .await?;
    }
    let known: Vec<String> = keys().iter().map(|k| k.to_string()).collect();
    let orphaned: Vec<String> =
        sqlx::query_scalar("update flags set orphan = true, updated_at = now() where not orphan and key <> all($1::text[]) returning key")
            .bind(&known)
            .fetch_all(pool)
            .await?;
    for key in &orphaned {
        tracing::warn!(flag = %key, "no descriptor claims this flag any more: it is an orphan and is no longer served");
    }
    Ok(())
}

/// Read the table back into the snapshot. Called at startup and after every admin write.
pub async fn load(pool: &PgPool) -> anyhow::Result<Table> {
    let rows: Vec<(String, String, Value, Option<i32>)> =
        sqlx::query_as("select key, kind, value, rollout_bp from flags where not orphan order by key")
            .fetch_all(pool)
            .await?;
    let mut map: HashMap<&'static str, Row> = HashMap::new();
    for (key, kind, value, rollout_bp) in rows {
        // A key no descriptor claims is never served, whatever the orphan column says.
        let Some(spec) = spec(&key) else { continue };
        if spec.kind() != kind {
            tracing::warn!(flag = %key, stored = %kind, expected = spec.kind(), "flag row has the wrong kind; the default applies");
        }
        if !spec.accepts(&value) {
            tracing::warn!(flag = %key, value = %value, "flag value is not of the flag's type; the default applies");
        }
        map.insert(spec.key(), Row { value, rollout_bp });
    }
    Ok(Table::new(map))
}

// ---------------------------------------------------------------------------
// Delivery
// ---------------------------------------------------------------------------

/// `GET /v1/flags.json` — the public document, unauthenticated, out of memory.
///
/// Unauthenticated on purpose. The `Customer` extractor runs `update devices set last_seen_at =
/// now()` on every authenticated request, so an authenticated flag read is a Postgres write per
/// read, through a pool of eight. This handler is zero queries and zero writes: a clone of an
/// `Arc<str>` rendered when the snapshot was built.
///
/// It carries what is true for **everybody**: `wire` flags whose global value differs from their
/// default. A flag under a rollout and a per-customer override are personal and are never in
/// here — that would publish customer ids and make the document uncacheable.
///
/// Nothing secret belongs in it. It is public, and the repository is going open source: it will
/// name flags before their feature is announced, which is fine, and must never carry a
/// threshold, an address or a key, which is not.
pub async fn document(State(s): State<AppState>, headers: HeaderMap) -> Response {
    let table = s.flags();
    let etag = table.etag();
    let fresh = headers
        .get(header::IF_NONE_MATCH)
        .and_then(|v| v.to_str().ok())
        .is_some_and(|v| v.split(',').any(|t| t.trim() == etag || t.trim() == "*"));
    // `no-cache` means "revalidate", not "do not store": the phone keeps the body and spends one
    // conditional request per session, which is what makes a 304 the common answer.
    let base = [
        (header::ETAG, etag.to_string()),
        (header::CACHE_CONTROL, "no-cache".to_string()),
    ];
    if fresh {
        return (StatusCode::NOT_MODIFIED, base).into_response();
    }
    (StatusCode::OK, base, [(header::CONTENT_TYPE, "application/json")], table.doc.to_string()).into_response()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn table(key: &'static str, value: Value, rollout_bp: Option<i32>) -> Table {
        Table::new(HashMap::from([(key, Row { value, rollout_bp })]))
    }

    #[test]
    fn no_duplicate_keys_in_the_registry() {
        let mut seen = std::collections::HashSet::new();
        for spec in ALL {
            assert!(seen.insert(spec.key()), "two descriptors claim {:?}", spec.key());
        }
    }

    /// #40 as an assertion: there is no way to declare a bool flag whose absence turns something
    /// new on.
    #[test]
    fn every_bool_flag_defaults_to_false() {
        let empty = Table::default();
        for spec in ALL {
            if let Spec::Bool(f) = spec {
                assert!(!empty.bool(f, None), "{} is not false on an empty table", f.key);
            }
            assert_eq!(spec.default_json(), empty.value_of(spec, None), "{} does not default to itself", spec.key());
        }
    }

    #[test]
    fn a_wrong_typed_value_falls_back_to_the_default() {
        let t = table(STATIONS_LOCAL.key, json!("yes"), None);
        assert!(!t.bool(&STATIONS_LOCAL, None));
        assert_eq!(t.wire_map(None), json!({}));
    }

    #[test]
    fn an_orphan_is_not_served() {
        // `load` drops a key no descriptor claims, so it cannot reach the table at all — and a
        // table that does not know a key answers with the default.
        let t = Table::default();
        assert_eq!(t.raw("a_flag_nobody_claims", None), None);
        assert!(!t.bool(&STATIONS_LOCAL, None));
    }

    /// The test that fails when somebody switches to `customer.to_string()`, to little-endian, or
    /// changes the separator — the three changes the doc comment says must never happen. A
    /// distribution test catches none of them.
    #[test]
    fn the_bucket_is_a_golden_vector() {
        let customer = Uuid::parse_str("11111111-2222-3333-4444-555555555555").expect("a uuid");
        assert_eq!(bucket("stations_local", customer), 2075);
        assert_eq!(bucket("a", customer), 128);
        assert_eq!(bucket("b", customer), 3742);
    }

    fn fixtures() -> Vec<Uuid> {
        // Ten thousand fixed uuids: the low 64 bits count, so the set is the same on every run.
        (0..10_000u64).map(|i| Uuid::from_u64_pair(0x5665_7273_7061_6574, i)).collect()
    }

    #[test]
    fn two_flags_do_not_pick_the_same_tenth() {
        let ids = fixtures();
        let a: std::collections::HashSet<Uuid> = ids.iter().copied().filter(|&c| bucket("a", c) < 1000).collect();
        let b: std::collections::HashSet<Uuid> = ids.iter().copied().filter(|&c| bucket("b", c) < 1000).collect();
        // σ = √(10000 · 0.1 · 0.9) = 30, so 3σ = 90.
        assert!((910..=1090).contains(&a.len()), "a is {} of 10000, not ~1000", a.len());
        assert!((910..=1090).contains(&b.len()), "b is {} of 10000, not ~1000", b.len());
        // Two independent tenths overlap in a hundredth: σ = √(10000 · 0.01 · 0.99) ≈ 9.95, 3σ ≈ 30.
        // This is what fails if somebody drops the key from the salt — the overlap would be 100 %.
        let overlap = a.intersection(&b).count();
        assert!((70..=130).contains(&overlap), "the two tenths overlap {overlap} times, not ~100");
    }

    #[test]
    fn the_individual_beats_the_rollout() {
        let t = table(STATIONS_LOCAL.key, json!(true), Some(10_000));
        let customer = Uuid::new_v4();
        let none = json!({});
        assert!(t.bool(&STATIONS_LOCAL, Some(Who::new(customer, &none))), "a 100 % rollout reaches everybody");

        let off = json!({ "stations_local": false });
        assert!(!t.bool(&STATIONS_LOCAL, Some(Who::new(customer, &off))), "the override did not win");
        assert_eq!(t.source(STATIONS_LOCAL.key, Some(Who::new(customer, &off))), Source::Override);
    }

    #[test]
    fn a_rollout_has_nobody_to_bucket_without_a_customer() {
        let t = table(STATIONS_LOCAL.key, json!(true), Some(10_000));
        assert!(!t.bool(&STATIONS_LOCAL, None), "a rollout answered without a customer");
        assert_eq!(t.source(STATIONS_LOCAL.key, None), Source::Default);
        // And so it is never in the public document, which has no customer.
        assert_eq!(t.wire_map(None), json!({}));
    }

    #[test]
    fn the_document_omits_a_flag_at_its_default() {
        let off = table(STATIONS_LOCAL.key, json!(false), None);
        assert_eq!(off.wire_map(None), json!({}));
        assert!(off.doc.contains(r#""flags":{}"#), "the document is {}", off.doc);

        let on = table(STATIONS_LOCAL.key, json!(true), None);
        assert_eq!(on.wire_map(None), json!({ "stations_local": true }));
        assert_ne!(off.etag(), on.etag(), "two different documents share an ETag");
    }

    #[test]
    fn an_override_of_null_is_no_override() {
        // `flag_overrides - key` is how an override is cleared; a literal null left behind by
        // anything else must not read as "somebody said false".
        let t = table(STATIONS_LOCAL.key, json!(true), None);
        let null = json!({ "stations_local": null });
        assert!(t.bool(&STATIONS_LOCAL, Some(Who::new(Uuid::new_v4(), &null))));
        assert_eq!(t.source(STATIONS_LOCAL.key, Some(Who::new(Uuid::new_v4(), &null))), Source::Global);
    }
}
