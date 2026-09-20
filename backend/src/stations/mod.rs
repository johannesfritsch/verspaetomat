//! Stations of our own (issue #37).
//!
//! Before this, "which stations are near me" was a live question: the phone sent its coordinates,
//! we forwarded them to Transitous, and up to five more queries went out behind that to work out
//! which of the stops around the passenger were railway stations at all. It answered well and it
//! cost a coordinate leaving the phone, several requests against somebody else's volunteer
//! service, and a round trip — every time anybody moved five hundred metres.
//!
//! Stations do not move. A couple are built each year and a couple close. So we hold them.
//!
//! What this module owns:
//!
//! * the **id namespace**. `stations.id` is ours, it is permanent, and it reaches the app as the
//!   string `vs:4711`. The ids Transitous answers to are kept beside it and never travel further
//!   than the next MOTIS call.
//! * the **index**: the whole table, in memory, because eight thousand stations is a megabyte and
//!   a linear scan over it is faster than asking Postgres. [`Index::nearby`] is the same answer
//!   `/v1/stations/nearby` used to fetch, computed here.
//! * **committing an import**: matching a freshly built [`CandidateSet`] against the ids we have
//!   already given out, and refusing the whole thing when it looks wrong.
//!
//! Building that candidate set from the GTFS feeds is [`gtfs`], and it runs on a laptop rather
//! than on the server: it is a 338 MB download and a pass over 2.8 GB of stop times, and the VPS
//! has an API to serve.

pub mod extract;
pub mod gtfs;

use std::collections::HashMap;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Postgres, Transaction};

use crate::train::{display_station_name, haversine_m, normalise_station_name, StopInfo};

/// How far the nearby answer looks before it gives up.
///
/// The live path grew a radius through `NEARBY_RADII` and stopped at fifty kilometres; a scan has
/// no reason to stop anywhere, so it has to be told. Without this, a passenger in Paris is offered
/// Saarbrücken and the Bahnsteig claims a station is nearby when none is.
pub const NEARBY_MAX_M: f64 = 50_000.0;

/// Two stations this close with the same normalised name are one station listed twice.
///
/// The same number as `train::SAME_PLATFORM_M`, and for the same reason: two feeds put one
/// platform a few hundred metres apart at most.
pub const SAME_STATION_M: f64 = 1_000.0;

/// The prefix that says "this id is ours".
///
/// It is on the wire rather than a bare number so that a handler taking a station id can tell one
/// of ours from a MOTIS id without guessing, and so a log line says which namespace it is reading.
/// Old builds hold MOTIS ids and keep sending them; everything here passes those through.
const WIRE_PREFIX: &str = "vs:";

pub fn wire_id(id: i32) -> String {
    format!("{WIRE_PREFIX}{id}")
}

pub fn parse_wire_id(s: &str) -> Option<i32> {
    s.strip_prefix(WIRE_PREFIX)?.parse().ok()
}

/// A station as the rest of the system sees it.
#[derive(Debug, Clone)]
pub struct Station {
    pub id: i32,
    pub name: String,
    pub lat: f64,
    pub lon: f64,
    /// The docs/23 ladder: 3 long distance, 2 regional, 1 S-Bahn only.
    pub rank: i16,
    /// The MOTIS ids for this station, the preferred one first. Never empty.
    pub sources: Vec<String>,
    /// The name lowercased, and the name through `normalise_station_name`. Both, because a search
    /// has to match a half-typed word as well as a fully spelled one, and the two want different
    /// folds — see [`Index::search`]. Precomputed because the alternative is folding eight
    /// thousand names on every keystroke.
    plain: String,
    normal: String,
}

impl Station {
    /// The id to hand Transitous. Never `None` in practice — a station without a source could not
    /// have been imported — but the caller decides what an impossible station means.
    pub fn upstream(&self) -> Option<&str> {
        self.sources.first().map(String::as_str)
    }

    fn stop_info(&self, distance_m: Option<i64>) -> StopInfo {
        StopInfo {
            id: wire_id(self.id),
            name: self.name.clone(),
            lat: self.lat,
            lon: self.lon,
            distance_m,
            rail_rank: Some(self.rank as i32),
        }
    }
}

/// One station as a fresh import proposes it, before it is matched to an id we already gave out.
///
/// This is the wire format between `stellwerk stations import` (which builds it on a laptop from
/// the GTFS feeds) and `POST /admin/stations/import` (which decides what it means for ids we have
/// already handed to phones). It deliberately carries no id: choosing one is the server's job.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Candidate {
    pub name: String,
    pub lat: f64,
    pub lon: f64,
    pub rank: i16,
    #[serde(default)]
    pub modes: Vec<String>,
    /// Full MOTIS ids, preferred first, every one of them verbatim from the feed's `stops.txt`.
    pub sources: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CandidateSet {
    pub generated: DateTime<Utc>,
    #[serde(default)]
    pub feed_version: Option<String>,
    pub stations: Vec<Candidate>,
}

/// What an import did, or would have done. Written to `station_imports` either way.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ImportReport {
    pub added: i64,
    pub retired: i64,
    pub moved: i64,
    pub renamed: i64,
    pub total: i64,
    pub committed: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub feed_version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
}

/// The index as everything that is not a request handler holds it: the trip follower ticks on its
/// own and still has to turn a ride's station id into something a trip's stops can be matched
/// against, so it gets the same handle the state does rather than a copy that goes stale.
pub type Shared = std::sync::Arc<std::sync::RwLock<std::sync::Arc<Index>>>;

pub fn snapshot(shared: &Shared) -> std::sync::Arc<Index> {
    shared.read().expect("stations lock").clone()
}

/// Every live station, in memory.
///
/// Rebuilt from Postgres at startup and after an import. Nothing mutates it in place: a reader
/// holds an `Arc` and the writer swaps a new one in, so a lookup never waits for an import.
#[derive(Debug, Default)]
pub struct Index {
    all: Vec<Station>,
    by_id: HashMap<i32, usize>,
    by_source: HashMap<String, usize>,
}

impl Index {
    pub fn len(&self) -> usize {
        self.all.len()
    }

    pub fn is_empty(&self) -> bool {
        self.all.is_empty()
    }

    /// The station an id from the wire names, whether it is one of ours or a MOTIS id an older
    /// build is still holding.
    pub fn get(&self, id: &str) -> Option<&Station> {
        let idx = match parse_wire_id(id) {
            Some(n) => self.by_id.get(&n),
            None => self.by_source.get(id),
        };
        idx.map(|&i| &self.all[i])
    }

    /// The id to put on a MOTIS call for a station id from the wire.
    ///
    /// An id we do not know passes through unchanged. That is how a build from before this change
    /// keeps working: it holds MOTIS ids, it sends them, and they are still the ids MOTIS wants.
    pub fn upstream_id(&self, id: &str) -> String {
        self.get(id).and_then(Station::upstream).unwrap_or(id).to_string()
    }

    /// Every id a trip's stops might carry for this station, for matching a stored station against
    /// a trip that came back from MOTIS under whichever feed served it.
    pub fn candidate_ids(&self, id: &str) -> Vec<String> {
        match self.get(id) {
            Some(s) => s.sources.clone(),
            None => vec![id.to_string()],
        }
    }

    /// The nearest stations, ranked the way the live path ranked them (docs/23 §1).
    ///
    /// The answer carries its own scope like the live one did (issue #31): `searched_radius_m` is
    /// how far this answer reaches, and `complete` says nothing nearer is missing. A local table
    /// can always say that honestly, which the gazetteer path never could — it is the one place
    /// this change makes the phone's umbrella sizing better rather than merely cheaper.
    pub fn nearby(&self, lat: f64, lon: f64, limit: usize) -> Nearby {
        let mut hits: Vec<(i64, &Station)> = self
            .all
            .iter()
            .filter_map(|s| {
                let d = haversine_m(lat, lon, s.lat, s.lon);
                (d <= NEARBY_MAX_M).then(|| (d.round() as i64, s))
            })
            .collect();
        hits.sort_by_key(|(d, _)| *d);
        hits.truncate(limit);
        let searched_radius_m = hits.last().map(|(d, _)| *d).unwrap_or(0);
        // Nearest first for the cut, best-ranked first for the answer — the same two-step the live
        // path used, and for the same reason: truncating after the rank sort could drop a nearer
        // station in favour of a better one further out, and then the first station the phone did
        // not register is no longer the nearest one it did not register.
        hits.sort_by(|(da, a), (db, b)| {
            crate::train::transitous::nearby_order(*da, a.rank as i32, &a.name)
                .cmp(&crate::train::transitous::nearby_order(*db, b.rank as i32, &b.name))
        });
        Nearby {
            stations: hits.iter().map(|(d, s)| s.stop_info(Some(*d))).collect(),
            searched_radius_m,
            complete: !hits.is_empty(),
        }
    }

    /// Stations whose name matches what was typed.
    ///
    /// A station whose name begins with the query comes before one that merely contains it, and a
    /// better station before a lesser one — so "köln" offers Köln Hbf before Köln Süd and before
    /// "Bergisch Gladbach, Kölner Straße".
    pub fn search(&self, q: &str, limit: usize) -> Vec<StopInfo> {
        // Two needles for two folds. `normalise_station_name` exists to decide whether two
        // *complete* station names are the same place, and on the way it rewrites whole words —
        // „Hauptbahnhof" becomes „Hbf", a trailing „Bahnhof" disappears. That is right for what it
        // was built for and wrong for a half-typed query: „Berlin Haupt" folds to itself while
        // „Berlin Hauptbahnhof" folds to „berlin hbf", and the search found nothing while the
        // station sat there. So a station matches on either fold — the plain lowercase name, which
        // keeps every prefix a passenger can type, or the normalised one, which is what makes
        // „Berlin Hbf" find a station the feed spells out in full.
        let plain = q.trim().to_lowercase();
        let normal = normalise_station_name(q);
        if plain.is_empty() {
            return Vec::new();
        }
        let mut hits: Vec<(u8, i16, u8, &Station)> = self
            .all
            .iter()
            .filter_map(|s| {
                let starts = s.plain.starts_with(&plain) || (!normal.is_empty() && s.normal.starts_with(&normal));
                let holds = s.plain.contains(&plain) || (!normal.is_empty() && s.normal.contains(&normal));
                let class = if starts {
                    0
                } else if holds {
                    1
                } else {
                    return None;
                };
                // The same tiebreaker the nearby list uses (docs/23 §1): among stations that match
                // equally well and rank equally, the one whose name says „Bahnhof" is the one the
                // passenger meant. Without it „köln" offered „Köln Ehrenfeld Bf Ehrenfeld" above
                // Köln Hbf, because alphabetical order does not know what a Hauptbahnhof is.
                let named = if crate::train::transitous::looks_like_station(&s.name) { 0 } else { 1 };
                Some((class, -s.rank, named, s))
            })
            .collect();
        hits.sort_by(|a, b| (a.0, a.1, a.2, &a.3.name).cmp(&(b.0, b.1, b.2, &b.3.name)));
        hits.truncate(limit);
        // A searched station carries no rank: the list is not a ranking, and the app's `Von` row
        // shows it as a plain name. Same as the live path did.
        hits.iter()
            .map(|(_, _, _, s)| StopInfo { rail_rank: None, ..s.stop_info(None) })
            .collect()
    }
}

/// Read the whole live table into an index.
pub async fn load(pool: &PgPool) -> anyhow::Result<Index> {
    let rows: Vec<(i32, String, f64, f64, i16)> =
        sqlx::query_as("select id, name, lat, lon, rank from stations where retired_at is null order by id")
            .fetch_all(pool)
            .await?;
    // `preferred` first, then by id so two runs of the importer produce the same order.
    let sources: Vec<(i32, String, bool)> =
        sqlx::query_as("select station_id, source_id, preferred from station_sources order by station_id, preferred desc, source_id")
            .fetch_all(pool)
            .await?;

    let mut by_station: HashMap<i32, Vec<String>> = HashMap::new();
    for (station_id, source_id, _) in sources {
        by_station.entry(station_id).or_default().push(source_id);
    }

    let mut index = Index::default();
    for (id, name, lat, lon, rank) in rows {
        let Some(srcs) = by_station.remove(&id) else {
            // A station with no source id cannot be asked about, so it has no business being
            // offered. This should be impossible; say so rather than serving a dead station.
            tracing::warn!(station = id, %name, "station has no source id and was left out of the index");
            continue;
        };
        let at = index.all.len();
        for s in &srcs {
            index.by_source.insert(s.clone(), at);
        }
        index.by_id.insert(id, at);
        let (plain, normal) = (name.to_lowercase(), normalise_station_name(&name));
        index.all.push(Station { id, name, lat, lon, rank, sources: srcs, plain, normal });
    }
    Ok(index)
}

/// What an import is allowed to do before somebody has to look at it.
///
/// Every one of these is a failure a prototype actually produced while this was being designed, so
/// they are not hypothetical: a fold that emitted one station per platform, a run that would have
/// retired most of Germany because a feed had moved, a name-only fold that left the same station
/// in the list twice.
mod guard {
    /// Germany has on the order of eight thousand railway stations. Outside this, something other
    /// than "a few stations opened" has happened.
    pub const MIN_TOTAL: usize = 6_000;
    pub const MAX_TOTAL: usize = 12_000;

    /// Stations do not close fifty at a time.
    pub const MAX_RETIRED: i64 = 50;

    /// A station that moved further than this did not move; it was matched to the wrong one.
    pub const MAX_MOVE_M: f64 = 2_000.0;
}

/// Match a freshly built set against the ids we have already given out, and commit it.
///
/// The matching rule, in order, is the whole reason this runs on the server: an id that has been
/// on a phone, in a ride row or in a muted-stations list has to keep naming the same station.
///
///  1. any source id we already know → that station keeps its id;
///  2. else the same normalised name within [`SAME_STATION_M`] → that station keeps its id;
///  3. else it is new and gets a new id.
///
/// A station that is in the table and in neither of those is retired — the row stays, so the id
/// stays spoken for and a ride that names it still reads back.
///
/// `force` skips the guards. It exists because the first import necessarily fails the retirement
/// guard against an empty table, and because a real upstream change will one day need a human to
/// say "yes, that really happened".
pub async fn commit(pool: &PgPool, set: &CandidateSet, force: bool, dry_run: bool) -> anyhow::Result<ImportReport> {
    let mut report = ImportReport { feed_version: set.feed_version.clone(), total: set.stations.len() as i64, ..Default::default() };

    let mut tx = pool.begin().await?;
    let run_id: (i32,) = sqlx::query_as("insert into station_imports (feed_version, total) values ($1, $2) returning id")
        .bind(&set.feed_version)
        .bind(set.stations.len() as i32)
        .fetch_one(&mut *tx)
        .await?;

    let outcome = apply(&mut tx, set, &mut report).await;
    let refusal = match outcome {
        Err(e) => Some(format!("import failed: {e}")),
        Ok(()) => refuse(&report, force),
    };

    report.committed = refusal.is_none() && !dry_run;
    report.note = refusal.clone().or_else(|| dry_run.then(|| "dry run: nothing was written".to_string()));

    sqlx::query(
        "update station_imports set finished_at = now(), added = $2, retired = $3, moved = $4, renamed = $5, total = $6, committed = $7, note = $8 where id = $1",
    )
    .bind(run_id.0)
    .bind(report.added as i32)
    .bind(report.retired as i32)
    .bind(report.moved as i32)
    .bind(report.renamed as i32)
    .bind(report.total as i32)
    .bind(report.committed)
    .bind(&report.note)
    .execute(&mut *tx)
    .await?;

    if report.committed {
        tx.commit().await?;
    } else {
        // The run row is the one thing worth keeping from a refused import, so it is written again
        // outside the transaction that is about to be thrown away.
        tx.rollback().await?;
        sqlx::query(
            "insert into station_imports (feed_version, started_at, finished_at, added, retired, moved, renamed, total, committed, note) values ($1, now(), now(), $2, $3, $4, $5, $6, false, $7)",
        )
        .bind(&set.feed_version)
        .bind(report.added as i32)
        .bind(report.retired as i32)
        .bind(report.moved as i32)
        .bind(report.renamed as i32)
        .bind(report.total as i32)
        .bind(&report.note)
        .execute(pool)
        .await?;
    }
    Ok(report)
}

/// The guards, as one sentence each. `None` means the import may commit.
fn refuse(r: &ImportReport, force: bool) -> Option<String> {
    if force {
        return None;
    }
    let total = r.total as usize;
    if !(guard::MIN_TOTAL..=guard::MAX_TOTAL).contains(&total) {
        return Some(format!(
            "refused: {total} stations is outside {}..{}, which is not a country gaining a Haltepunkt",
            guard::MIN_TOTAL,
            guard::MAX_TOTAL
        ));
    }
    if r.retired > guard::MAX_RETIRED {
        return Some(format!("refused: {} stations would be retired at once, more than {}", r.retired, guard::MAX_RETIRED));
    }
    None
}

async fn apply(tx: &mut Transaction<'_, Postgres>, set: &CandidateSet, report: &mut ImportReport) -> anyhow::Result<()> {
    // Everything we already hold, live and retired alike: a station that comes back after a
    // seasonal closure must get its old id, not a new one.
    let existing: Vec<(i32, String, f64, f64)> = sqlx::query_as("select id, name, lat, lon from stations").fetch_all(&mut **tx).await?;
    let sources: Vec<(String, i32)> = sqlx::query_as("select source_id, station_id from station_sources").fetch_all(&mut **tx).await?;

    let by_source: HashMap<&str, i32> = sources.iter().map(|(s, id)| (s.as_str(), *id)).collect();
    let mut by_name: HashMap<String, Vec<(i32, f64, f64)>> = HashMap::new();
    for (id, name, lat, lon) in &existing {
        by_name.entry(normalise_station_name(name)).or_default().push((*id, *lat, *lon));
    }
    let known: HashMap<i32, (String, f64, f64)> = existing.into_iter().map(|(id, n, lat, lon)| (id, (n, lat, lon))).collect();

    let mut seen: Vec<i32> = Vec::with_capacity(set.stations.len());
    for c in &set.stations {
        let name = display_station_name(&c.name);
        let matched = c
            .sources
            .iter()
            .find_map(|s| by_source.get(s.as_str()).copied())
            .or_else(|| nearest_by_name(&by_name, &name, c.lat, c.lon));

        let id = match matched {
            Some(id) => {
                if let Some((old_name, old_lat, old_lon)) = known.get(&id) {
                    if haversine_m(*old_lat, *old_lon, c.lat, c.lon) > 1.0 {
                        report.moved += 1;
                    }
                    if old_name != &name {
                        report.renamed += 1;
                    }
                }
                sqlx::query("update stations set name = $2, lat = $3, lon = $4, rank = $5, modes = $6, last_seen = now(), retired_at = null where id = $1")
                    .bind(id)
                    .bind(&name)
                    .bind(c.lat)
                    .bind(c.lon)
                    .bind(c.rank)
                    .bind(&c.modes)
                    .execute(&mut **tx)
                    .await?;
                id
            }
            None => {
                report.added += 1;
                let row: (i32,) =
                    sqlx::query_as("insert into stations (name, lat, lon, rank, modes) values ($1, $2, $3, $4, $5) returning id")
                        .bind(&name)
                        .bind(c.lat)
                        .bind(c.lon)
                        .bind(c.rank)
                        .bind(&c.modes)
                        .fetch_one(&mut **tx)
                        .await?;
                row.0
            }
        };
        seen.push(id);

        // The preferred source is the first one the builder listed. Clearing the flag first keeps
        // the "exactly one preferred" index honest while the rows are being rewritten.
        sqlx::query("update station_sources set preferred = false where station_id = $1").bind(id).execute(&mut **tx).await?;
        for (n, source) in c.sources.iter().enumerate() {
            let feed = source.split_once('_').map(|(f, _)| f).unwrap_or("");
            sqlx::query(
                "insert into station_sources (source_id, station_id, feed, preferred, last_seen) values ($1, $2, $3, $4, now())
                 on conflict (source_id) do update set station_id = excluded.station_id, feed = excluded.feed, preferred = excluded.preferred, last_seen = now()",
            )
            .bind(source)
            .bind(id)
            .bind(feed)
            .bind(n == 0)
            .execute(&mut **tx)
            .await?;
        }
    }

    let retired: (i64,) = sqlx::query_as("select count(*) from stations where retired_at is null and id <> all($1)")
        .bind(&seen)
        .fetch_one(&mut **tx)
        .await?;
    report.retired = retired.0;
    sqlx::query("update stations set retired_at = now() where retired_at is null and id <> all($1)")
        .bind(&seen)
        .execute(&mut **tx)
        .await?;
    Ok(())
}

/// Rule 2 of the matching: the same name, near enough to be the same building.
///
/// Near enough is the point. Two towns do have stations of the same name, and matching "Neustadt"
/// in Holstein to "Neustadt" an der Weinstraße would hand one town's id to the other's station and
/// quietly move every ride that named it.
fn nearest_by_name(by_name: &HashMap<String, Vec<(i32, f64, f64)>>, name: &str, lat: f64, lon: f64) -> Option<i32> {
    let mut best: Option<(f64, i32)> = None;
    for (id, elat, elon) in by_name.get(&normalise_station_name(name))? {
        let d = haversine_m(lat, lon, *elat, *elon);
        if d <= SAME_STATION_M && best.map(|(bd, _)| d < bd).unwrap_or(true) {
            best = Some((d, *id));
        }
    }
    best.filter(|(d, _)| *d <= guard::MAX_MOVE_M).map(|(_, id)| id)
}

/// The answer `/v1/stations/nearby` gives, computed from the table.
///
/// Deliberately the same three fields `train::transitous::NearbyAnswer` carried, so the handler
/// and the app see no difference at all.
pub struct Nearby {
    pub stations: Vec<StopInfo>,
    pub searched_radius_m: i64,
    pub complete: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn station(id: i32, name: &str, lat: f64, lon: f64, rank: i16) -> Station {
        Station {
            id,
            name: name.into(),
            lat,
            lon,
            rank,
            sources: vec![format!("de-DELFI_test:{id}")],
            plain: name.to_lowercase(),
            normal: normalise_station_name(name),
        }
    }

    fn index(stations: Vec<Station>) -> Index {
        let mut ix = Index::default();
        for s in stations {
            let at = ix.all.len();
            ix.by_id.insert(s.id, at);
            for src in &s.sources {
                ix.by_source.insert(src.clone(), at);
            }
            ix.all.push(s);
        }
        ix
    }

    /// docs/23 §1: standing at the entrance of München Hbf, the Hauptbahnhof is offered, not the
    /// tram stop sixty metres away. The band does it: both are inside 300 m, so rank decides.
    #[test]
    fn the_hauptbahnhof_wins_its_own_forecourt() {
        let ix = index(vec![
            station(1, "München Hbf", 48.1402, 11.5600, 3),
            // Rank 1 is as high as a stop that is not rail ever gets into this table.
            station(2, "München, Hauptbahnhof Nord", 48.1407, 11.5602, 1),
        ]);
        let near = ix.nearby(48.1404, 11.5601, 3);
        assert_eq!(near.stations[0].name, "München Hbf");
        assert!(near.complete);
    }

    /// Fifty kilometres is the edge of the answer, as it was for the radius ladder. Beyond it the
    /// honest answer is "no station near you", not the nearest one in the country.
    #[test]
    fn nothing_is_nearby_from_far_enough_away() {
        let ix = index(vec![station(1, "Köln Hbf", 50.9430, 6.9586, 3)]);
        // Paris, which is a long way from Köln and has no business seeing it.
        let near = ix.nearby(48.8566, 2.3522, 3);
        assert!(near.stations.is_empty());
        assert!(!near.complete, "an empty answer is never complete");
        assert_eq!(near.searched_radius_m, 0);
    }

    /// The radius is what the answer actually reaches, so the phone can size its umbrella from the
    /// first station it did not get.
    #[test]
    fn the_radius_is_the_last_station_returned() {
        let ix = index(vec![
            station(1, "Kißlegg", 47.7914, 9.8921, 2),
            station(2, "Wangen im Allgäu", 47.6874, 9.8255, 2),
        ]);
        let near = ix.nearby(47.7914, 9.8921, 2);
        assert_eq!(near.stations.len(), 2);
        assert!(near.searched_radius_m > 10_000 && near.searched_radius_m < 15_000, "{}", near.searched_radius_m);
    }

    /// An id from a build that predates this table is a MOTIS id, and it still has to work.
    #[test]
    fn an_old_builds_id_still_finds_its_station() {
        let ix = index(vec![station(7, "Köln Hbf", 50.9430, 6.9586, 3)]);
        assert_eq!(ix.get("de-DELFI_test:7").map(|s| s.id), Some(7));
        assert_eq!(ix.get("vs:7").map(|s| s.id), Some(7));
        assert_eq!(ix.upstream_id("vs:7"), "de-DELFI_test:7");
        // An id we have never seen is not ours to rewrite.
        assert_eq!(ix.upstream_id("de-VBB_something"), "de-VBB_something");
    }

    #[test]
    fn a_search_prefers_the_name_that_starts_with_what_was_typed() {
        let ix = index(vec![
            station(1, "Bergisch Gladbach, Kölner Straße", 50.99, 7.13, 1),
            station(2, "Köln Süd", 50.9230, 6.9430, 2),
            station(3, "Köln Hbf", 50.9430, 6.9586, 3),
        ]);
        let hits = ix.search("köln", 5);
        assert_eq!(hits[0].name, "Köln Hbf");
        assert_eq!(hits[1].name, "Köln Süd");
        assert_eq!(hits[2].name, "Bergisch Gladbach, Kölner Straße");
        assert!(hits[0].rail_rank.is_none(), "a searched station is not a ranking");
    }

    /// The live import turned this up: „köln" offered „Köln Ehrenfeld Bf Ehrenfeld" before Köln
    /// Hbf, because both are prefix matches of the same rank and E comes before H.
    #[test]
    fn a_hauptbahnhof_beats_a_stop_that_merely_sorts_earlier() {
        let ix = index(vec![
            station(1, "Köln Ehrenfeld Bf Ehrenfeld", 50.9500, 6.9200, 3),
            station(2, "Köln Hbf", 50.9430, 6.9586, 3),
        ]);
        assert_eq!(ix.search("köln", 5)[0].name, "Köln Hbf");
    }

    /// Found on the deployed server: „Berlin" offered Berlin Hauptbahnhof and „Berlin Haupt"
    /// offered nothing at all, because `normalise_station_name` rewrites the whole word
    /// „Hauptbahnhof" to „Hbf" and half a word is not a word. Both spellings have to find it, and
    /// so does the one the feed does not use.
    #[test]
    fn a_half_typed_hauptbahnhof_still_finds_it() {
        let ix = index(vec![station(1, "Berlin Hauptbahnhof", 52.5251, 13.3694, 3)]);
        for q in ["Berlin", "Berlin Haupt", "Berlin Hauptbahnhof", "berlin hbf", "Berlin Hbf"] {
            assert_eq!(ix.search(q, 5).len(), 1, "{q} found nothing");
        }
        // And a station the feed spells short is still found when it is typed out in full.
        let ix = index(vec![station(1, "Köln Hbf", 50.9430, 6.9586, 3)]);
        for q in ["Köln Hbf", "Köln Hauptbahnhof", "köln h"] {
            assert_eq!(ix.search(q, 5).len(), 1, "{q} found nothing");
        }
    }

    /// Two towns, one station name. Matching them to each other would hand one town's id to the
    /// other and move every ride that named it.
    #[test]
    fn the_same_name_in_another_town_is_another_station() {
        let mut by_name: HashMap<String, Vec<(i32, f64, f64)>> = HashMap::new();
        by_name.insert(normalise_station_name("Neustadt"), vec![(1, 54.1080, 10.8160)]);
        assert_eq!(nearest_by_name(&by_name, "Neustadt", 54.1081, 10.8161), Some(1));
        assert_eq!(nearest_by_name(&by_name, "Neustadt", 49.3500, 8.1400), None);
    }
}
