//! Building the station candidate set from the Transitous GTFS feeds (issue #37).
//!
//! `https://api.transitous.org/gtfs/` is an open index of the **processed** feeds the live MOTIS
//! instance imports, and Transitous' usage policy asks for exactly this — download the dataset
//! rather than query the API in bulk. Two of those feeds carry German rail:
//!
//! | File | MOTIS dataset key | Licence |
//! |---|---|---|
//! | `de_DELFI.gtfs.zip` | `de-DELFI` | CC-BY-4.0 |
//! | `de_VBB.gtfs.zip` | `de-VBB` | CC-BY-4.0 |
//!
//! VBB is not optional: the Transitous import drops 39 agencies from DELFI, `S-Bahn Berlin GmbH`
//! among them, so Berlin's S-Bahn is only in VBB.
//!
//! The ids this produces are the ids the live API accepts **by construction**: MOTIS prefixes the
//! dataset key onto the feed's own `stop_id`, so `de-DELFI_de:05315:11201` is literally
//! `<key>_<stops.txt stop_id>`. Nothing here invents an id — every one it emits was read verbatim
//! out of that feed's `stops.txt`, and [`fold`] refuses the build if one was not.
//!
//! The shape of the work, and why it is a laptop's job rather than the server's: `routes.txt` has
//! about 1,100 rail routes, which name about 123,000 rail trips, which are found by streaming the
//! 2.8 GB of `stop_times.txt` — that member is never held in memory and never lands on disk
//! uncompressed. What comes out the other end is on the order of 13,000 rail-served quays, folded
//! to something like 8,000 stations.
//!
//! This module is compiled into the server as well, because it sits under `stations`, but the
//! server never calls it — only `stellwerk stations import` does, through the library target. Same
//! reason `train` carries the same line.
#![allow(dead_code)]

use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Seek, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{bail, Context, Result};
use chrono::Utc;

use super::{Candidate, CandidateSet, SAME_STATION_M};
use crate::train::{display_station_name, haversine_m, normalise_station_name, station_names_match};

/// Where the processed feeds live.
const INDEX_URL: &str = "https://api.transitous.org/gtfs/";
/// The live API, used only to ask whether a handful of the ids we are about to hand over are ids
/// it answers to.
const API_URL: &str = "https://api.transitous.org/api/v1";

/// A feed we read, and the key MOTIS prefixes onto its stop ids. Note that the file name spells
/// the dataset with an underscore and the key with a hyphen; they are not the same string.
#[derive(Debug, Clone, Copy)]
struct Feed {
    key: &'static str,
    file: &'static str,
}

/// DELFI first, and that order is load-bearing: where both feeds have a station, the DELFI id is
/// the one departures are asked for.
const FEEDS: [Feed; 2] =
    [Feed { key: "de-DELFI", file: "de_DELFI.gtfs.zip" }, Feed { key: "de-VBB", file: "de_VBB.gtfs.zip" }];

/// A station called plain "Hauptbahnhof" this close to a "… Hbf" is that Hauptbahnhof.
///
/// DELFI names München's S-Bahn level `Hauptbahnhof (U, Tram)` and puts it 81 m from
/// `München Hbf`. It is not a tram stop — S1 to S8 call there — so a fold that keeps it apart ends
/// with two München Hbf, one of them under a name no passenger would recognise. The distance is
/// the same 300 m as `train::transitous`'s rank band, inside which the nearby answer already
/// treats two stops as one place.
const HBF_LEVEL_M: f64 = 300.0;

/// How many same-named stations within [`SAME_STATION_M`] the build will tolerate before it
/// refuses to hand the set over, as a share of all stations.
///
/// [`merge`] folds every such pair by construction, so a survivor is not a fact about Germany — it
/// is a bug in the fold, and the last one of those put **1,204 duplicate stations (14 %)** into a
/// build artefact: the docs/30 "Ab Kißlegg Bahnhof, twice on Home" bug, baked in. The bar is
/// therefore "as good as none" rather than a tolerance; it is not zero only so that a pair sitting
/// on the 1,000 m edge, where two runs can round differently, is a warning and not an outage.
const MAX_DUPLICATE_RATE: f64 = 0.002;

// ---------------------------------------------------------------------------
// Rail-ness, straight out of the feed
// ---------------------------------------------------------------------------

/// The rail modes as bits, so a station's modes and its rank are one byte.
type Modes = u8;

const HIGHSPEED_RAIL: Modes = 1 << 0;
const LONG_DISTANCE: Modes = 1 << 1;
const NIGHT_RAIL: Modes = 1 << 2;
const RAIL: Modes = 1 << 3;
const REGIONAL_RAIL: Modes = 1 << 4;
const SUBURBAN: Modes = 1 << 5;

/// Each mode's name — the same vocabulary `train::is_rail_mode` speaks — and the docs/23 rank it
/// earns a station: 3 long distance, 2 regional, 1 S-Bahn only.
const MODES: [(Modes, &str, i16); 6] = [
    (HIGHSPEED_RAIL, "HIGHSPEED_RAIL", 3),
    (LONG_DISTANCE, "LONG_DISTANCE", 3),
    (NIGHT_RAIL, "NIGHT_RAIL", 3),
    (RAIL, "RAIL", 2),
    (REGIONAL_RAIL, "REGIONAL_RAIL", 2),
    (SUBURBAN, "SUBURBAN", 1),
];

/// A GTFS `route_type` that is railway service, as the mode it is.
///
/// This is the whole reason the table is built from the feed rather than from sampled departures.
/// DELFI uses the extended route types, so S-Bahn (`109`) and U-Bahn (`1`, `400..405`) are
/// **different numbers**. The live path cannot see that: MOTIS reports both as `METRO`, so
/// `train::transitous::is_s_bahn_line` has to read the line name and hope that `S1` is a railway
/// and `U1` is not (`transitous.rs:467`). Here it is a fact in the data, and this is strictly
/// better — no name is parsed, no `^S\d` is assumed, and a line whose name happens to start with
/// an S cannot sneak in.
fn rail_service(route_type: u16) -> Option<Modes> {
    Some(match route_type {
        // 2 is plain "Rail" from the base spec; 100 is its extended twin.
        2 | 100 => RAIL,
        101 => HIGHSPEED_RAIL,
        // 102 Long Distance, 103 Inter Regional — both long distance to a passenger.
        102 | 103 => LONG_DISTANCE,
        // 105 is Sleeper Rail. Issue #37 lists it under rank 2; it is ranked 3 here because
        // `train::transitous::mode_rank` already ranks `NIGHT_RAIL` with long distance and the app
        // has been shipping that ladder. The feed currently has no 105 route at all, so this is a
        // question of keeping the two ladders the same rather than of any station's rank.
        105 => NIGHT_RAIL,
        106 => REGIONAL_RAIL,
        109 => SUBURBAN,
        // 104 car transport, 107 tourist, 108 rail shuttle, 110..117 the remaining rail services.
        // All railway, none of them long distance.
        104 | 107 | 108 | 110..=117 => RAIL,
        _ => return None,
    })
}

fn rank_of(modes: Modes) -> i16 {
    MODES.iter().filter(|(b, _, _)| modes & b != 0).map(|(_, _, r)| *r).max().unwrap_or(0)
}

fn names_of(modes: Modes) -> Vec<String> {
    MODES.iter().filter(|(b, _, _)| modes & b != 0).map(|(_, n, _)| n.to_string()).collect()
}

// ---------------------------------------------------------------------------
// The build
// ---------------------------------------------------------------------------

/// Somewhere to put a running commentary — the build takes minutes and should say so out loud.
pub type Progress = Option<Arc<dyn Fn(&str) + Send + Sync>>;

#[derive(Default, Clone)]
pub struct BuildOptions {
    /// Read `de_DELFI.gtfs.zip` and `de_VBB.gtfs.zip` from this directory instead of downloading
    /// them. 400 MB is not worth fetching twice while something is being worked on.
    pub from: Option<PathBuf>,
    pub progress: Progress,
}

impl BuildOptions {
    fn say(&self, line: impl AsRef<str>) {
        if let Some(p) = &self.progress {
            p(line.as_ref());
        }
    }
}

/// Everything one feed contributed, before the two are merged.
struct Extracted {
    records: Vec<Record>,
    feed_version: Option<String>,
}

/// One station as a single feed sees it.
#[derive(Debug, Clone)]
struct Record {
    /// Index into [`FEEDS`]: DELFI sorts before VBB, and that decides which id is preferred.
    feed: usize,
    name: String,
    lat: f64,
    lon: f64,
    modes: Modes,
    /// Full MOTIS ids, preferred first.
    sources: Vec<String>,
}

/// Build the candidate set: fetch or read the two feeds, extract, fold, merge, check.
pub async fn build(opts: BuildOptions) -> Result<CandidateSet> {
    let started = std::time::Instant::now();
    let scratch = match &opts.from {
        Some(_) => None,
        None => Some(Scratch::new()?),
    };

    let mut records: Vec<Record> = Vec::new();
    let mut feed_version = None;
    for (index, feed) in FEEDS.iter().enumerate() {
        let path = match (&opts.from, &scratch) {
            (Some(dir), _) => {
                let p = dir.join(feed.file);
                if !p.exists() {
                    bail!("{} is not in {}", feed.file, dir.display());
                }
                p
            }
            (None, Some(s)) => {
                let p = s.path().join(feed.file);
                opts.say(format!("{}: lade {INDEX_URL}{} …", feed.key, feed.file));
                let bytes = download(&format!("{INDEX_URL}{}", feed.file), &p).await?;
                opts.say(format!("{}: {} MB geladen", feed.key, bytes / 1_000_000));
                p
            }
            (None, None) => unreachable!("a download without a scratch directory"),
        };

        // The heavy pass is minutes of decompressing and parsing and nothing else, so it does not
        // belong on the async runtime's shoulders.
        let (feed, o) = (*feed, opts.clone());
        let extracted = tokio::task::spawn_blocking(move || extract(index, feed, &path, &o)).await??;
        feed_version = feed_version.or(extracted.feed_version);
        records.extend(extracted.records);
    }

    let before = records.len();
    let records = merge(records);
    opts.say(format!("zusammengelegt: {before} → {} Stationen", records.len()));

    check(&records, &opts)?;

    let mut stations: Vec<Candidate> = records
        .into_iter()
        .map(|r| Candidate {
            name: r.name,
            lat: r.lat,
            lon: r.lon,
            rank: rank_of(r.modes),
            modes: names_of(r.modes),
            sources: r.sources,
        })
        .collect();
    // #60: „Hauptbahnhof (oben)" becomes „Stuttgart, Hauptbahnhof (oben)".
    let named = super::cities::qualify_names(&mut stations);
    opts.say(format!("{named} Namen um ihre Stadt ergänzt"));
    check_findable(&stations)?;
    opts.say(format!("Suche geprüft: {} Hauptbahnhöfe unter ihrem Stadtnamen gefunden", FINDABLE.len()));

    opts.say(format!("fertig in {} s", started.elapsed().as_secs()));
    Ok(CandidateSet { generated: Utc::now(), feed_version, stations })
}

/// Main stations a passenger must find by typing the city's name, in the first page of results.
///
/// #60 shipped a table in which „Stuttgart" found nothing: VVS names its stops without the city,
/// and every other check here passed, because a table can be complete, well folded and free of
/// duplicates and still not answer the question passengers ask. This asks it. The list is the
/// biggest cities plus the ones whose feed names have caught us out; a miss refuses the build.
const FINDABLE: &[(&str, &str)] = &[
    ("Berlin", "Berlin Hbf"),
    ("Hamburg", "Hamburg Hbf"),
    ("München", "München Hbf"),
    ("Köln", "Köln Hbf"),
    ("Frankfurt", "Frankfurt (Main) Hbf"),
    ("Stuttgart", "Stuttgart Hbf"),
    ("Düsseldorf", "Düsseldorf Hbf"),
    ("Leipzig", "Leipzig Hbf"),
    ("Dortmund", "Dortmund Hbf"),
    ("Essen", "Essen Hbf"),
    ("Bremen", "Bremen Hbf"),
    ("Dresden", "Dresden Hbf"),
    ("Hannover", "Hannover Hbf"),
    ("Nürnberg", "Nürnberg Hbf"),
    ("Duisburg", "Duisburg Hbf"),
    ("Bochum", "Bochum Hbf"),
    ("Wuppertal", "Wuppertal Hbf"),
    ("Bielefeld", "Bielefeld Hbf"),
    ("Bonn", "Bonn Hbf"),
    ("Münster", "Münster Hbf"),
    ("Karlsruhe", "Karlsruhe Hbf"),
    ("Mannheim", "Mannheim Hbf"),
    ("Augsburg", "Augsburg Hbf"),
    ("Wiesbaden", "Wiesbaden Hbf"),
    ("Kiel", "Kiel Hbf"),
    ("Freiburg", "Freiburg Hbf"),
    ("Mainz", "Mainz Hbf"),
    ("Kassel", "Kassel Hbf"),
    ("Rostock", "Rostock Hbf"),
    ("Erfurt", "Erfurt Hbf"),
    ("Magdeburg", "Magdeburg Hbf"),
    ("Saarbrücken", "Saarbrücken Hbf"),
    ("Ulm", "Ulm Hbf"),
    ("Regensburg", "Regensburg Hbf"),
    ("Würzburg", "Würzburg Hbf"),
];

/// How far down the results the station may be. The app shows this many without scrolling.
const FINDABLE_WITHIN: usize = 10;

/// Every [`FINDABLE`] station on the first page of a search for its city — the same search the
/// server and the phone run (`Index::search`, `station_index.dart`), on the set about to be written.
/// Names are compared through the search's own fold, so „Frankfurt (Main) Hauptbahnhof" and
/// „Mannheim, Hauptbahnhof" count as what they are.
pub fn check_findable(set: &[Candidate]) -> Result<()> {
    check_findable_in(set, FINDABLE)
}

fn check_findable_in(set: &[Candidate], list: &[(&str, &str)]) -> Result<()> {
    let index = super::Index::from_candidates(set);
    let mut missing = Vec::new();
    for (query, station) in list {
        let want = normalise_station_name(station);
        let hits = index.search(query, FINDABLE_WITHIN);
        if !hits.iter().any(|h| normalise_station_name(&h.name) == want) {
            let seen: Vec<&str> = hits.iter().take(3).map(|h| h.name.as_str()).collect();
            missing.push(format!("„{query}\" findet {station} nicht (sondern {seen:?})"));
        }
    }
    if !missing.is_empty() {
        bail!(
            "{} Hauptbahnhof/-höfe sind unter ihrem Stadtnamen nicht zu finden — so ginge die Tabelle nicht raus: {}",
            missing.len(),
            missing.join("; ")
        );
    }
    Ok(())
}

/// The rank histogram of a built set, for the human about to commit it.
pub fn ranks(set: &CandidateSet) -> [usize; 4] {
    let mut out = [0usize; 4];
    for c in &set.stations {
        let r = c.rank.clamp(0, 3) as usize;
        out[r] += 1;
    }
    out
}

/// A few of the preferred ids, asked of the live API.
///
/// The one check the feed cannot do for itself: an id that is verbatim in `stops.txt` is still
/// only a guess about what MOTIS answers to until MOTIS has answered to it. Returns
/// `(ok, tried, failures)`, a failure being the id and what went wrong with it.
pub async fn sample_upstream(set: &CandidateSet, n: usize) -> Result<(usize, usize, Vec<String>)> {
    let http = reqwest::Client::builder()
        .user_agent(crate::train::transitous::USER_AGENT)
        .timeout(std::time::Duration::from_secs(20))
        .build()?;
    // Spread over the whole set rather than over its beginning: the ids are grouped by feed and
    // by region, so the first twenty would all be one Bundesland's.
    let step = (set.stations.len() / n.max(1)).max(1);
    let (mut ok, mut tried) = (0usize, 0usize);
    let mut failures = Vec::new();
    for c in set.stations.iter().step_by(step).take(n) {
        let Some(id) = c.sources.first() else { continue };
        tried += 1;
        match http.get(format!("{API_URL}/stoptimes?stopId={}&n=1", urlencode(id))).send().await {
            Ok(r) if r.status().is_success() => match r.text().await {
                Ok(body) if body.contains("\"stopTimes\"") => ok += 1,
                Ok(_) => failures.push(format!("{id}: 200 ohne stopTimes")),
                Err(e) => failures.push(format!("{id}: {e}")),
            },
            Ok(r) => failures.push(format!("{id}: HTTP {}", r.status().as_u16())),
            Err(e) => failures.push(format!("{id}: {e}")),
        }
    }
    Ok((ok, tried, failures))
}

fn urlencode(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

// ---------------------------------------------------------------------------
// One feed
// ---------------------------------------------------------------------------

/// One row of `stops.txt`, kept for every stop in the feed — not only the rail ones.
///
/// All of them, because an id may only be emitted if it is verbatim in this file, and because a
/// quay's station is found by following `parent_station` through rows that are not themselves
/// served by anything.
#[derive(Debug, Clone)]
struct Stop {
    name: String,
    lat: f64,
    lon: f64,
    parent: Option<String>,
    /// `location_type = 1`, a station rather than a quay.
    station: bool,
}

fn extract(index: usize, feed: Feed, zip: &Path, opts: &BuildOptions) -> Result<Extracted> {
    let file = File::open(zip).with_context(|| format!("opening {}", zip.display()))?;
    let mut archive = zip::ZipArchive::new(file).with_context(|| format!("reading {}", zip.display()))?;

    // 1. routes.txt → the rail routes, and what kind of rail each is.
    let mut routes: HashMap<String, Modes> = HashMap::new();
    {
        let member = archive.by_name("routes.txt").context("routes.txt is missing from the feed")?;
        let mut table = Table::open(member)?;
        let (id, kind) = (table.column("route_id")?, table.column("route_type")?);
        while table.next_row()? {
            let Ok(t) = table.text(kind).parse::<u16>() else { continue };
            if let Some(m) = rail_service(t) {
                routes.insert(table.text(id).to_string(), m);
            }
        }
    }
    opts.say(format!("{}: {} Bahn-Linien", feed.key, routes.len()));

    // 2. trips.txt → the trips those routes run.
    let mut trips: HashMap<String, Modes> = HashMap::new();
    {
        let member = archive.by_name("trips.txt").context("trips.txt is missing from the feed")?;
        let mut table = Table::open(member)?;
        let (trip, route) = (table.column("trip_id")?, table.column("route_id")?);
        while table.next_row()? {
            if let Some(m) = routes.get(table.text(route)).copied() {
                trips.insert(table.text(trip).to_string(), m);
            }
        }
    }
    opts.say(format!("{}: {} Bahn-Fahrten", feed.key, trips.len()));

    // 3. stop_times.txt → the stops those trips call at. This member is 2.8 GB in DELFI: it is
    //    read through the zip a row at a time, and nothing of it is kept but the stop ids.
    let mut served: HashMap<String, Modes> = HashMap::new();
    let mut rows: u64 = 0;
    {
        let member = archive.by_name("stop_times.txt").context("stop_times.txt is missing from the feed")?;
        let mut table = Table::open(member)?;
        let (trip, stop) = (table.column("trip_id")?, table.column("stop_id")?);
        // The rows come grouped by trip, so the map is asked once per trip rather than once per
        // call: fifty million lookups become a million and a byte comparison.
        let mut last: Vec<u8> = Vec::new();
        let mut modes: Modes = 0;
        while table.next_row()? {
            rows += 1;
            if rows.is_multiple_of(10_000_000) {
                opts.say(format!("{}: {} Mio. Halte gelesen …", feed.key, rows / 1_000_000));
            }
            if table.bytes(trip) != last.as_slice() {
                last.clear();
                last.extend_from_slice(table.bytes(trip));
                modes = trips.get(table.text(trip)).copied().unwrap_or(0);
            }
            if modes == 0 {
                continue;
            }
            match served.get_mut(table.text(stop)) {
                Some(m) => *m |= modes,
                None => {
                    served.insert(table.text(stop).to_string(), modes);
                }
            }
        }
    }
    opts.say(format!("{}: {} Bahnsteige aus {} Halten", feed.key, served.len(), rows));

    // 4. stops.txt → every row, because the fold needs parents and the check needs the id set.
    let mut stops: HashMap<String, Stop> = HashMap::new();
    {
        let member = archive.by_name("stops.txt").context("stops.txt is missing from the feed")?;
        let mut table = Table::open(member)?;
        let (id, name) = (table.column("stop_id")?, table.column("stop_name")?);
        let (lat, lon) = (table.column("stop_lat")?, table.column("stop_lon")?);
        let (parent, kind) = (table.column("parent_station")?, table.column("location_type")?);
        while table.next_row()? {
            let (Ok(lat), Ok(lon)) = (table.text(lat).parse::<f64>(), table.text(lon).parse::<f64>()) else {
                continue;
            };
            let p = table.text(parent);
            let stop = Stop {
                // Feed names carry country suffixes the customer never needs; taking them off here
                // means the fold, the merge and the duplicate check all see the name that will be
                // in the table.
                name: display_station_name(table.text(name)),
                lat,
                lon,
                parent: (!p.is_empty()).then(|| p.to_string()),
                station: table.text(kind) == "1",
            };
            stops.insert(table.text(id).to_string(), stop);
        }
    }

    let feed_version = read_feed_version(&mut archive);
    let records = fold(index, feed.key, &stops, &served, opts)?;
    opts.say(format!("{}: {} Stationen", feed.key, records.len()));
    Ok(Extracted { records, feed_version })
}

fn read_feed_version<R: Read + Seek>(archive: &mut zip::ZipArchive<R>) -> Option<String> {
    let member = archive.by_name("feed_info.txt").ok()?;
    let mut table = Table::open(member).ok()?;
    let column = table.column("feed_version").ok()?;
    if !table.next_row().ok()? {
        return None;
    }
    let v = table.text(column).to_string();
    (!v.is_empty()).then_some(v)
}

// ---------------------------------------------------------------------------
// The fold: quays to stations
// ---------------------------------------------------------------------------

/// Fold the rail-served quays of one feed into stations.
///
/// Two stops belong to the same station when they share a **grouping key**, and the key is found
/// structurally: follow `parent_station` as far as it goes, then take the station part of the DHID
/// that lands on. The string surgery is deliberate and it is only ever a *key* — the id that comes
/// out is looked up in `stops.txt` and emitted verbatim, never assembled. A prototype that
/// assembled ids by truncating DHIDs invented ids that do not exist, and only 157 of 200 sampled
/// resolved against MOTIS.
///
/// The key has to do this much work because `parent_station` alone does not fold Köln: there,
/// `de:05315:11201`, its ten `…:7:7x` quays and `de:05315:11201_G` all carry an **empty** parent,
/// so a parent-only fold leaves Köln Hbf in the list twice, once under each id.
fn fold(
    index: usize,
    key: &str,
    stops: &HashMap<String, Stop>,
    served: &HashMap<String, Modes>,
    opts: &BuildOptions,
) -> Result<Vec<Record>> {
    let mut groups: HashMap<String, (Modes, Vec<&str>)> = HashMap::new();
    let mut missing = 0usize;
    for (id, modes) in served {
        if !stops.contains_key(id) {
            // A stop_times row naming a stop the feed itself does not have. Not ours to fix, and
            // not something to fold either.
            missing += 1;
            continue;
        }
        let group = groups.entry(group_key(id, stops)).or_insert((0, Vec::new()));
        group.0 |= modes;
        group.1.push(id.as_str());
    }
    if missing > 0 {
        opts.say(format!("{key}: {missing} Halt(e) nennen eine Haltestelle, die es in stops.txt nicht gibt"));
        tracing::warn!(feed = key, missing, "stop ids in stop_times.txt that stops.txt does not have");
    }

    let mut out = Vec::with_capacity(groups.len());
    for (group, (modes, mut members)) in groups {
        // Sorted so that two runs of the importer produce the same set in the same order.
        members.sort_unstable();
        let preferred = preferred_id(&group, &members, stops);
        let mut sources = vec![preferred.clone()];
        sources.extend(members.iter().filter(|m| ***m != *preferred).map(|m| m.to_string()));
        for source in &sources {
            // The check issue #37 asks for, while it can still name the feed and the id.
            if !stops.contains_key(source) {
                bail!("{key}: {source} is not a stop_id in stops.txt — the fold invented an id");
            }
        }
        let stop = &stops[&preferred];
        out.push(Record {
            feed: index,
            name: stop.name.clone(),
            lat: stop.lat,
            lon: stop.lon,
            modes,
            sources: sources.into_iter().map(|s| format!("{key}_{s}")).collect(),
        });
    }
    out.sort_by(|a, b| a.sources[0].cmp(&b.sources[0]));
    Ok(out)
}

/// Which station a stop belongs to, as a key. Not necessarily an id.
fn group_key(id: &str, stops: &HashMap<String, Stop>) -> String {
    let mut current = id;
    // Bounded, because a feed with a parent cycle should produce a bad key rather than a hung
    // import.
    for _ in 0..8 {
        match stops.get(current).and_then(|s| s.parent.as_deref()) {
            Some(p) if p != current && stops.contains_key(p) => current = p,
            _ => break,
        }
    }
    dhid_station(current)
}

/// The station part of a DHID: `de:08436:1159:2:1` and `de:08436:1159_G_G` are both
/// `de:08436:1159`. Anything that is not a DHID is its own key.
///
/// The third field has to be a number, and that is not pedantry. Switzerland's ids in this feed
/// are SLOIDs — `ch:1:sloid:10`, `ch:1:sloid:1605` — where the station is the *fourth* field, so
/// cutting after the third would make one key out of every Swiss stop in the feed. It did: a first
/// run put 134 Swiss stop ids under a single station called "Basel SBB". Every German id in the
/// feed has a numeric station field (checked: no exceptions in 551,291 rows), so the rule costs
/// nothing here and an id it does not recognise simply becomes its own key, which over-merges
/// nothing and leaves the name-and-distance pass to fold what belongs together.
fn dhid_station(id: &str) -> String {
    let base = strip_g(id);
    let mut parts = base.split(':');
    match (parts.next(), parts.next(), parts.next()) {
        (Some(country), Some(region), Some(stop))
            if country.len() == 2
                && country.chars().all(|c| c.is_ascii_lowercase())
                && !strip_g(stop).is_empty()
                && strip_g(stop).chars().all(|c| c.is_ascii_digit()) =>
        {
            format!("{country}:{region}:{}", strip_g(stop))
        }
        _ => base.to_string(),
    }
}

/// MOTIS and DELFI both hang `_G` off an id to mean "the whole stop rather than this platform",
/// and DELFI carries rows for `…_G` and `…_G_G` beside the plain id. They are the same place.
fn strip_g(id: &str) -> &str {
    let mut s = id;
    while let Some(t) = s.strip_suffix("_G") {
        s = t;
    }
    s
}

/// The id to put first, which is the one departures will be asked for.
///
/// It has to exist in `stops.txt`, and the best one is the station's own row: that is the id under
/// the name a passenger reads on the building, and the one that does not change when a platform is
/// renumbered.
fn preferred_id(key: &str, members: &[&str], stops: &HashMap<String, Stop>) -> String {
    if stops.contains_key(key) {
        return key.to_string();
    }
    let twin = format!("{key}_G");
    if stops.contains_key(&twin) {
        return twin;
    }
    // Nothing station-shaped: take a served quay — the station-typed one first, then the shortest
    // id, then alphabetically. Anything, as long as two runs agree on it.
    members
        .iter()
        .min_by_key(|m| (!stops[**m].station, m.len(), **m))
        .map(|m| (*m).to_string())
        .unwrap_or_else(|| key.to_string())
}

// ---------------------------------------------------------------------------
// Merging the feeds
// ---------------------------------------------------------------------------

/// Two records are one station when their names normalise the same and they are within
/// [`SAME_STATION_M`], whichever feed each came from.
///
/// This is what puts Berlin's S-Bahn (VBB) and Berlin's regional platforms (DELFI) on one station
/// with two source ids, and it is also what folds DELFI's own `de:11000:900003200` and `…3201` —
/// one name, two DHIDs, 145 m apart — into one Berlin Hbf.
fn merge(mut records: Vec<Record>) -> Vec<Record> {
    // DELFI before VBB, then by id, so a cluster's primary is deterministic and the DELFI id is
    // the one that ends up first in `sources`.
    records.sort_by(|a, b| (a.feed, &a.sources[0]).cmp(&(b.feed, &b.sources[0])));
    let names: Vec<String> = records.iter().map(|r| normalise_station_name(&r.name)).collect();

    let mut parent: Vec<usize> = (0..records.len()).collect();
    let mut by_name: HashMap<&str, Vec<usize>> = HashMap::new();
    for (i, n) in names.iter().enumerate() {
        by_name.entry(n.as_str()).or_default().push(i);
    }
    for group in by_name.values() {
        for (n, &i) in group.iter().enumerate() {
            for &j in &group[n + 1..] {
                let (a, b) = (&records[i], &records[j]);
                if haversine_m(a.lat, a.lon, b.lat, b.lon) <= SAME_STATION_M {
                    union(&mut parent, i, j);
                }
            }
        }
    }

    // A bare "Hauptbahnhof" beside a "… Hbf" is that Hauptbahnhof's other level, not a station of
    // its own. Nothing gets in here that a rail route does not call at, so a stop under this name
    // is by construction a railway platform; the only question is whose.
    let hauptbahnhoefe: Vec<usize> = (0..records.len()).filter(|&i| names[i].ends_with("hbf")).collect();
    for &i in &hauptbahnhoefe {
        if names[i] != "hbf" {
            continue;
        }
        let mut best: Option<(f64, usize)> = None;
        for &j in &hauptbahnhoefe {
            if names[j] == "hbf" {
                continue;
            }
            let d = haversine_m(records[i].lat, records[i].lon, records[j].lat, records[j].lon);
            if d <= HBF_LEVEL_M && best.map(|(bd, _)| d < bd).unwrap_or(true) {
                best = Some((d, j));
            }
        }
        if let Some((_, j)) = best {
            union(&mut parent, j, i);
        }
    }

    // Collect each cluster onto its lowest member, which after the sort is its DELFI record.
    let mut out: Vec<Record> = Vec::new();
    let mut at: HashMap<usize, usize> = HashMap::new();
    for (i, record) in records.iter().enumerate() {
        let root = find(&mut parent, i);
        match at.get(&root) {
            None => {
                at.insert(root, out.len());
                out.push(record.clone());
            }
            Some(&k) => {
                out[k].modes |= record.modes;
                for s in &record.sources {
                    if !out[k].sources.contains(s) {
                        out[k].sources.push(s.clone());
                    }
                }
            }
        }
    }
    out
}

fn find(parent: &mut [usize], mut i: usize) -> usize {
    while parent[i] != i {
        parent[i] = parent[parent[i]];
        i = parent[i];
    }
    i
}

fn union(parent: &mut [usize], a: usize, b: usize) {
    let (ra, rb) = (find(parent, a), find(parent, b));
    if ra != rb {
        // The lower index wins, so a cluster's primary is its earliest record: DELFI, lowest id.
        let (keep, gone) = if ra < rb { (ra, rb) } else { (rb, ra) };
        parent[gone] = keep;
    }
}

// ---------------------------------------------------------------------------
// The check that has to hold before anything leaves the laptop
// ---------------------------------------------------------------------------

/// Every pair of stations within [`SAME_STATION_M`] of each other.
///
/// By way of a latitude window rather than every station against every other one: eight thousand
/// stations is thirty-two million pairs, and only the ones in the same narrow band of latitude can
/// possibly be close.
fn near_pairs(records: &[Record]) -> Vec<(usize, usize)> {
    let mut order: Vec<usize> = (0..records.len()).collect();
    order.sort_by(|&a, &b| records[a].lat.total_cmp(&records[b].lat));
    // A kilometre is 0.009° of latitude anywhere on earth; the margin is for the rounding.
    let band = SAME_STATION_M / 110_000.0;
    let mut out = Vec::new();
    for (n, &i) in order.iter().enumerate() {
        for &j in &order[n + 1..] {
            if records[j].lat - records[i].lat > band {
                break;
            }
            let (a, b) = (&records[i], &records[j]);
            if haversine_m(a.lat, a.lon, b.lat, b.lon) <= SAME_STATION_M {
                out.push((i, j));
            }
        }
    }
    out
}

fn check(records: &[Record], opts: &BuildOptions) -> Result<()> {
    let names: Vec<String> = records.iter().map(|r| normalise_station_name(&r.name)).collect();
    let mut duplicates: Vec<String> = Vec::new();
    let mut similar: Vec<String> = Vec::new();
    for (i, j) in near_pairs(records) {
        let (a, b) = (&records[i], &records[j]);
        if names[i] == names[j] {
            duplicates.push(format!("{} ({}) / {} ({})", a.name, a.sources[0], b.name, b.sources[0]));
        } else if station_names_match(&a.name, &b.name) {
            // The same station under names that merely start the same — "Kißlegg" and "Kißlegg
            // Bahnhof". Not refused, because two real stations can be named this way, but printed,
            // because this is where the next duplicate will come from.
            similar.push(format!("{} / {}", a.name, b.name));
        }
    }

    if !similar.is_empty() {
        let head: Vec<&String> = similar.iter().take(5).collect();
        opts.say(format!("Hinweis: {} Paar(e) mit verwandten Namen im selben Kilometer, z. B. {head:?}", similar.len()));
        tracing::warn!(pairs = similar.len(), examples = ?head, "stations with related names within a kilometre");
    }

    let rate = duplicates.len() as f64 / records.len().max(1) as f64;
    if !duplicates.is_empty() {
        let head: Vec<&String> = duplicates.iter().take(5).collect();
        opts.say(format!("{} doppelte Station(en), {:.2} %, z. B. {head:?}", duplicates.len(), rate * 100.0));
        tracing::warn!(duplicates = duplicates.len(), rate, examples = ?head, "same name within a kilometre after the fold");
    }
    if rate > MAX_DUPLICATE_RATE {
        bail!(
            "{} of {} stations are the same station twice ({:.2} %, more than {:.2} %) — that is the fold being wrong, not Germany: {:?}",
            duplicates.len(),
            records.len(),
            rate * 100.0,
            MAX_DUPLICATE_RATE * 100.0,
            duplicates.iter().take(10).collect::<Vec<_>>()
        );
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Reading a GTFS table
// ---------------------------------------------------------------------------

/// A CSV member of the zip, read a row at a time by column name.
///
/// By name because these feeds do not use the column order the spec's examples do: DELFI's
/// `stops.txt` begins `stop_name,parent_station,stop_id`, and VBB's puts `stop_code` and `zone_id`
/// in the middle of that.
struct Table<R: Read> {
    reader: csv::Reader<R>,
    headers: Vec<String>,
    row: csv::ByteRecord,
}

impl<R: Read> Table<R> {
    fn open(source: R) -> Result<Self> {
        // Flexible, because a feed this size has rows with a field too few and they are worth
        // reading anyway; a short row reads as empty in the columns it does not reach.
        // A megabyte at a time, because every refill of this buffer is a call into the zip's
        // decompressor and the biggest member is 2.8 GB of it.
        let mut reader = csv::ReaderBuilder::new().flexible(true).buffer_capacity(1 << 20).from_reader(source);
        let headers = reader.headers()?.iter().map(|h| h.trim_start_matches('\u{feff}').trim().to_string()).collect();
        Ok(Self { reader, headers, row: csv::ByteRecord::new() })
    }

    fn column(&self, name: &str) -> Result<usize> {
        self.headers.iter().position(|h| h == name).with_context(|| format!("the feed has no {name} column"))
    }

    fn next_row(&mut self) -> Result<bool> {
        Ok(self.reader.read_byte_record(&mut self.row)?)
    }

    fn bytes(&self, column: usize) -> &[u8] {
        self.row.get(column).unwrap_or_default()
    }

    fn text(&self, column: usize) -> &str {
        std::str::from_utf8(self.bytes(column)).unwrap_or_default()
    }
}

// ---------------------------------------------------------------------------
// Getting the feeds
// ---------------------------------------------------------------------------

/// A directory the downloads live in for the length of one build.
struct Scratch(PathBuf);

impl Scratch {
    fn new() -> Result<Self> {
        let dir = std::env::temp_dir().join(format!("verspaetomat-gtfs-{}", std::process::id()));
        std::fs::create_dir_all(&dir)?;
        Ok(Self(dir))
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        // 400 MB is not something to leave lying in /tmp because a build went wrong.
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// Stream a feed to a file. 338 MB does not go through memory, and Transitous answers 403 without
/// a User-Agent, so it gets the same one the rest of our traffic carries.
async fn download(url: &str, to: &Path) -> Result<u64> {
    let http = reqwest::Client::builder()
        .user_agent(crate::train::transitous::USER_AGENT)
        .timeout(std::time::Duration::from_secs(1800))
        .build()?;
    let mut response = http.get(url).send().await?.error_for_status()?;
    let mut file = std::io::BufWriter::new(File::create(to)?);
    let mut total = 0u64;
    while let Some(chunk) = response.chunk().await? {
        total += chunk.len() as u64;
        file.write_all(&chunk)?;
    }
    file.flush()?;
    Ok(total)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn stop(name: &str, parent: &str, lat: f64, lon: f64, station: bool) -> Stop {
        Stop { name: name.into(), lat, lon, parent: (!parent.is_empty()).then(|| parent.to_string()), station }
    }

    /// Kißlegg, exactly as `de_DELFI.gtfs.zip/stops.txt` has it: a station row, three rail quays
    /// under it, two bus quays that are *not* under it, and the `_G` and `_G_G` twins that no
    /// parent points at and that the rail trips actually call at. Folding this wrongly is the
    /// docs/30 "Ab Kißlegg Bahnhof, twice on Home" bug.
    fn kisslegg() -> HashMap<String, Stop> {
        let rows: &[(&str, &str, f64, f64, bool)] = &[
            ("de:08436:1159", "", 47.793507, 9.881845, true),
            ("de:08436:1159:1:1", "", 47.79324, 9.882878, false),
            ("de:08436:1159:1:2", "", 47.79325, 9.88154, false),
            ("de:08436:1159_G", "", 47.793533, 9.881921, false),
            ("de:08436:1159_G_G", "", 47.793243, 9.8821, false),
            ("000010115901", "de:08436:1159", 47.79324, 9.882878, false),
            ("de:08436:1159:2:1", "de:08436:1159", 47.79354, 9.881621, false),
            ("de:08436:1159:2:2", "de:08436:1159", 47.79356, 9.882025, false),
            ("de:08436:1159:2:3", "de:08436:1159", 47.793667, 9.882034, false),
        ];
        rows.iter()
            .map(|(id, parent, lat, lon, station)| ((*id).to_string(), stop("Kißlegg Bahnhof", parent, *lat, *lon, *station)))
            .collect()
    }

    fn served(ids: &[(&str, Modes)]) -> HashMap<String, Modes> {
        ids.iter().map(|(id, m)| ((*id).to_string(), *m)).collect()
    }

    #[test]
    fn the_rank_ladder_comes_out_of_the_route_type() {
        assert_eq!(rail_service(101).map(rank_of), Some(3), "High Speed");
        assert_eq!(rail_service(102).map(rank_of), Some(3), "Long Distance");
        assert_eq!(rail_service(103).map(rank_of), Some(3), "Inter Regional");
        assert_eq!(rail_service(106).map(rank_of), Some(2), "Regional");
        assert_eq!(rail_service(2).map(rank_of), Some(2), "Rail");
        assert_eq!(rail_service(100).map(rank_of), Some(2), "Railway Service");
        assert_eq!(rail_service(109).map(rank_of), Some(1), "S-Bahn");
        // The whole point: the S-Bahn is a number, and the U-Bahn is a different number. Nothing
        // here has to read "S1" to decide that it is a railway.
        assert_eq!(rail_service(1), None, "U-Bahn");
        assert_eq!(rail_service(400), None, "U-Bahn, extended");
        assert_eq!(rail_service(402), None, "U-Bahn, extended");
        assert_eq!(rail_service(3), None, "bus");
        assert_eq!(rail_service(700), None, "bus, extended");
        assert_eq!(rail_service(900), None, "tram");
        assert_eq!(rail_service(0), None, "tram");
        assert_eq!(rail_service(1501), None, "shared taxi");
    }

    #[test]
    fn a_station_carries_every_mode_that_calls_there() {
        let modes = HIGHSPEED_RAIL | REGIONAL_RAIL | SUBURBAN;
        assert_eq!(rank_of(modes), 3);
        assert_eq!(names_of(modes), vec!["HIGHSPEED_RAIL", "REGIONAL_RAIL", "SUBURBAN"]);
        assert_eq!(rank_of(0), 0);
    }

    #[test]
    fn kisslegg_is_one_station() {
        let stops = kisslegg();
        let served = served(&[
            ("de:08436:1159:2:1", REGIONAL_RAIL),
            ("de:08436:1159:2:2", REGIONAL_RAIL),
            ("de:08436:1159:2:3", REGIONAL_RAIL),
            ("de:08436:1159_G", REGIONAL_RAIL),
            ("de:08436:1159_G_G", REGIONAL_RAIL),
        ]);

        let out = fold(0, "de-DELFI", &stops, &served, &BuildOptions::default()).unwrap();
        assert_eq!(out.len(), 1, "one Bahnhof, not five: {out:#?}");
        // The station's own row, not a platform and not a `_G` twin.
        assert_eq!(out[0].sources[0], "de-DELFI_de:08436:1159");
        assert_eq!(out[0].sources.len(), 6, "the preferred id plus the five that are served");
        // Every id verbatim from stops.txt, every one of them ours to ask MOTIS about.
        for source in &out[0].sources {
            let bare = source.strip_prefix("de-DELFI_").unwrap();
            assert!(stops.contains_key(bare), "{source} is not a stop_id");
        }
        assert_eq!(rank_of(out[0].modes), 2);
        assert_eq!(out[0].name, "Kißlegg Bahnhof");
    }

    /// The bus quays are in the feed under the same name and the same DHID, and they are not the
    /// railway station: a bus stop that no train calls at never enters the fold at all.
    #[test]
    fn a_bus_quay_that_no_train_calls_at_is_not_a_station() {
        let stops = kisslegg();
        let served = served(&[("de:08436:1159:2:1", REGIONAL_RAIL)]);
        let out = fold(0, "de-DELFI", &stops, &served, &BuildOptions::default()).unwrap();
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].sources, vec!["de-DELFI_de:08436:1159", "de-DELFI_de:08436:1159:2:1"]);
    }

    /// Köln is the case `parent_station` cannot do on its own: the station row, the platform quays
    /// and the `_G` twin all have an empty parent.
    #[test]
    fn koeln_folds_without_a_parent_station() {
        let mut stops: HashMap<String, Stop> = HashMap::new();
        let mut rail: Vec<(&str, Modes)> = Vec::new();
        stops.insert("de:05315:11201".into(), stop("Köln Hbf", "", 50.94303, 6.958729, false));
        stops.insert("de:05315:11201_G".into(), stop("Köln Hbf", "", 50.94321, 6.958598, false));
        for (id, lat) in [
            ("de:05315:11201:7:71", 50.943077),
            ("de:05315:11201:7:72", 50.942574),
            ("de:05315:11201:7:73", 50.94319),
        ] {
            stops.insert(id.into(), stop("Köln Hbf", "", lat, 6.958, false));
            rail.push((id, HIGHSPEED_RAIL | REGIONAL_RAIL));
        }
        rail.push(("de:05315:11201_G", SUBURBAN));

        let out = fold(0, "de-DELFI", &stops, &served(&rail), &BuildOptions::default()).unwrap();
        assert_eq!(out.len(), 1, "Köln Hbf once: {out:#?}");
        assert_eq!(out[0].sources[0], "de-DELFI_de:05315:11201");
        assert_eq!(rank_of(out[0].modes), 3, "the ICE platforms count for the whole station");
    }

    #[test]
    fn the_station_part_of_a_dhid() {
        assert_eq!(dhid_station("de:08436:1159:2:1"), "de:08436:1159");
        assert_eq!(dhid_station("de:08436:1159_G_G"), "de:08436:1159");
        assert_eq!(dhid_station("de:11000:900003201::4_G"), "de:11000:900003201");
        assert_eq!(dhid_station("de:09162:100"), "de:09162:100");
        assert_eq!(dhid_station("de:05315:11201"), "de:05315:11201");
        assert_eq!(dhid_station("cz:55206:30749:1:1"), "cz:55206:30749");
        // Not a DHID: a bare IFOPT number is its own key, and nothing is chopped off it.
        assert_eq!(dhid_station("000170018901"), "000170018901");
        // A Swiss SLOID keeps its station number, which is one field further along. Cutting after
        // the third field would make Basel SBB out of every stop in Switzerland.
        assert_eq!(dhid_station("ch:1:sloid:10"), "ch:1:sloid:10");
        assert_ne!(dhid_station("ch:1:sloid:10"), dhid_station("ch:1:sloid:1605"));
        // Nor is a Polish EVA number a station number.
        assert_eq!(dhid_station("pl:51:EVANR-510008"), "pl:51:EVANR-510008");
    }

    fn record(feed: usize, name: &str, lat: f64, lon: f64, modes: Modes, id: &str) -> Record {
        Record { feed, name: name.into(), lat, lon, modes, sources: vec![id.into()] }
    }

    /// Berlin Hbf is in DELFI for the regional platforms and in VBB for the S-Bahn, and the DELFI
    /// id has to come first: that is the one `departures()` will ask for.
    #[test]
    fn two_feeds_make_one_station_with_two_sources() {
        let out = merge(vec![
            record(1, "S+U Berlin Hauptbahnhof", 52.5256, 13.3690, SUBURBAN, "de-VBB_de:11000:900003201"),
            record(0, "S+U Berlin Hauptbahnhof", 52.5268, 13.3685, HIGHSPEED_RAIL, "de-DELFI_de:11000:900003200"),
        ]);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].sources, vec!["de-DELFI_de:11000:900003200", "de-VBB_de:11000:900003201"]);
        assert_eq!(rank_of(out[0].modes), 3, "the long-distance platforms count for the whole station");
    }

    /// Two towns, one station name. Nothing merges them.
    #[test]
    fn the_same_name_far_apart_stays_two_stations() {
        let out = merge(vec![
            record(0, "Neustadt", 54.1080, 10.8160, REGIONAL_RAIL, "de-DELFI_a"),
            record(0, "Neustadt", 49.3500, 8.1400, REGIONAL_RAIL, "de-DELFI_b"),
        ]);
        assert_eq!(out.len(), 2);
    }

    /// DELFI calls München Hbf's S-Bahn level "Hauptbahnhof (U, Tram)" and puts it 81 m away. It
    /// is not a tram stop and it is not a station of its own.
    #[test]
    fn a_bare_hauptbahnhof_is_the_hauptbahnhof_next_to_it() {
        let out = merge(vec![
            record(0, "München Hbf", 48.14029, 11.559602, HIGHSPEED_RAIL, "de-DELFI_de:09162:100"),
            record(0, "Hauptbahnhof (U, Tram)", 48.140026, 11.561066, SUBURBAN, "de-DELFI_de:09162:6"),
        ]);
        assert_eq!(out.len(), 1, "one München Hbf: {out:#?}");
        assert_eq!(out[0].name, "München Hbf", "under the name on the building");
        assert_eq!(out[0].sources, vec!["de-DELFI_de:09162:100", "de-DELFI_de:09162:6"]);

        // A Hauptbahnhof with no Hbf near it is left alone rather than attached to the nearest one
        // in the country.
        let out = merge(vec![
            record(0, "Köln Hbf", 50.9430, 6.9586, HIGHSPEED_RAIL, "de-DELFI_a"),
            record(0, "Hauptbahnhof", 48.140026, 11.561066, SUBURBAN, "de-DELFI_b"),
        ]);
        assert_eq!(out.len(), 2);
    }

    /// The guard, on the shape of the thing it guards against.
    #[test]
    fn the_same_station_twice_is_refused() {
        let opts = BuildOptions::default();
        let twice: Vec<Record> = (0..100)
            .map(|i| {
                record(0, "Kißlegg Bahnhof", 47.7935 + i as f64 * 1e-5, 9.8818, REGIONAL_RAIL, &format!("de-DELFI_{i}"))
            })
            .collect();
        assert!(check(&twice, &opts).is_err());
        let once = vec![record(0, "Kißlegg Bahnhof", 47.7935, 9.8818, REGIONAL_RAIL, "de-DELFI_a")];
        assert!(check(&once, &opts).is_ok());
    }

    /// The duplicate check has to find a pair whichever order the two are in, which is what the
    /// latitude window is most likely to get wrong.
    #[test]
    fn the_duplicate_check_looks_both_ways() {
        let north = record(0, "Aulendorf", 47.9560, 9.6380, REGIONAL_RAIL, "de-DELFI_a");
        let south = record(0, "Aulendorf", 47.9520, 9.6380, REGIONAL_RAIL, "de-DELFI_b");
        assert_eq!(near_pairs(&[north.clone(), south.clone()]).len(), 1);
        assert_eq!(near_pairs(&[south, north]).len(), 1);
    }
}

#[cfg(test)]
mod findable_tests {
    use super::*;

    fn c(name: &str, rank: i16, source: &str) -> Candidate {
        Candidate { name: name.into(), lat: 48.78, lon: 9.18, rank, modes: vec![], sources: vec![source.into()] }
    }

    fn set(stuttgart_hbf: &str) -> Vec<Candidate> {
        let mut v = vec![c(stuttgart_hbf, 3, "de-DELFI_de:08111:6115")];
        // Plenty of other „Stuttgart…" stations, so the Hbf has to earn its place on the first page.
        for i in 0..20 {
            v.push(c(&format!("Stuttgart, Halt {i}"), 1, &format!("de-DELFI_de:08111:{i}")));
        }
        v.push(c("Frankfurt (Main) Hauptbahnhof", 3, "de-DELFI_de:06412:10"));
        v.push(c("Mannheim, Hauptbahnhof", 3, "de-DELFI_de:08222:1"));
        v
    }

    const LIST: &[(&str, &str)] = &[("Stuttgart", "Stuttgart Hbf"), ("Frankfurt", "Frankfurt (Main) Hbf"), ("Mannheim", "Mannheim Hbf")];

    #[test]
    fn the_table_before_60_is_refused() {
        let e = check_findable_in(&set("Hauptbahnhof (oben)"), LIST).unwrap_err().to_string();
        assert!(e.contains("Stuttgart"), "{e}");
        assert!(!e.contains("Frankfurt"), "Frankfurt was always findable: {e}");
    }

    #[test]
    fn the_qualified_table_passes_and_spellings_fold() {
        let mut v = set("Hauptbahnhof (oben)");
        crate::stations::cities::qualify_names(&mut v);
        check_findable_in(&v, LIST).expect("Stuttgart, Hauptbahnhof (oben) is Stuttgart Hbf to a search");
    }

    #[test]
    fn the_whole_list_names_each_city_once() {
        let mut seen = std::collections::HashSet::new();
        for (q, _) in FINDABLE {
            assert!(seen.insert(*q), "{q} twice");
        }
    }
}
