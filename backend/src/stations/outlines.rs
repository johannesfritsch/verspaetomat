//! Station premises from OpenStreetMap (issue #64, docs/48). A dry run for now: it reads a PBF
//! extract, builds each station's premise, its ring and its touch points, and writes a report,
//! a GeoJSON and drawings — nothing reaches a database or a phone yet.
//!
//! The words are docs/48's. The **premise** (Gelände) is everything a passenger stands on while at
//! the station: platforms, the station building, the station area — the convex hull of those,
//! 20 m wider. The **ring** is the circle that tells the phone it has arrived at a station and,
//! later, that it has left it. The **touch points** (Tastpunkte) are the circles, at least 120 m
//! each, that roughly cover the premise; entering one is the nudge.
//!
//! OSM data is ODbL. What this module produces is a derived database and is published as such
//! (docs/48, „Veröffentlichung und Namensnennung").

use std::collections::{HashMap, HashSet};
use std::path::Path;

use anyhow::{Context, Result};
use osmpbf::{Element, ElementReader, RelMemberType};

use super::extract::ExtractStation;
use crate::train::{haversine_m, normalise_station_name, station_names_match};

/// A platform must be at most this far from its station's OSM anchor to belong to it.
const MEMBER_REACH_M: f64 = 500.0;
/// Our station and an OSM anchor are the same place only this close.
const ANCHOR_REACH_M: f64 = 400.0;
/// No OSM station this close means the station lies outside the extract.
const OUTSIDE_M: f64 = 5_000.0;
/// The premise is the hull of its members, this much wider (docs/48).
const BUFFER_M: f64 = 20.0;
/// Corners of a premise after simplification.
const MAX_CORNERS: usize = 24;
/// Plausibility: a premise larger than this is an assignment error, not a station.
const MAX_AREA_M2: f64 = 50.0 * 10_000.0;
/// Ring: the premise's enclosing circle plus this, clamped.
const RING_MARGIN_M: f64 = 100.0;
const RING_MIN_M: f64 = 300.0;
const RING_MAX_M: f64 = 1_000.0;
/// Touch points: at least this big (iOS reports smaller circles late or not at all, Android asks
/// for 100–150 m), as few as cover the premise with circles no bigger than [TOUCH_TARGET_M].
const TOUCH_MIN_M: f64 = 120.0;
const TOUCH_TARGET_M: f64 = 150.0;
const TOUCH_MAX: usize = 6;

// -- what OSM gives us --------------------------------------------------------------------------

/// An OSM station: a `railway=station|halt` node, or the centre of such an area.
#[derive(Debug, Clone)]
pub struct Anchor {
    pub osm: String,
    pub name: String,
    pub lat: f64,
    pub lon: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    /// A train platform.
    Platform,
    /// A station building or station area.
    Building,
}

#[derive(Debug, Clone)]
pub struct Feature {
    pub osm: String,
    pub kind: Kind,
    /// Every vertex, (lat, lon).
    pub pts: Vec<(f64, f64)>,
}

#[derive(Debug, Default)]
pub struct Osm {
    pub anchors: Vec<Anchor>,
    pub features: Vec<Feature>,
}

fn tag<'a>(tags: &'a [(String, String)], k: &str) -> Option<&'a str> {
    tags.iter().find(|(a, _)| a == k).map(|(_, v)| v.as_str())
}

/// The keys any of the rules below look at. Everything else is dropped while reading, so a
/// 4 GB extract never becomes 4 GB of strings.
const KEYS: &[&str] = &[
    "railway", "public_transport", "building", "train", "tram", "bus", "subway", "light_rail", "trolleybus", "station", "usage", "name",
    "type",
];

fn kept<'a>(it: impl Iterator<Item = (&'a str, &'a str)>) -> Vec<(String, String)> {
    it.filter(|(k, _)| KEYS.contains(k)).map(|(k, v)| (k.to_string(), v.to_string())).collect()
}

/// A station a train stops at — not a U-Bahn, monorail or museum railway stop. `light_rail`
/// stays in: OSM tags the S-Bahn of Hamburg and Berlin that way, and our table holds only rail
/// stations, so a tram stop has nothing of ours to attach to.
pub fn is_anchor(t: &[(String, String)]) -> bool {
    matches!(tag(t, "railway"), Some("station" | "halt"))
        && !matches!(tag(t, "station"), Some("subway" | "monorail" | "funicular" | "miniature"))
        && tag(t, "usage") != Some("tourism")
        && tag(t, "train") != Some("no")
}

/// A platform a train stops at. Tram, bus and U-Bahn platforms are often, not always, tagged so.
pub fn is_train_platform(t: &[(String, String)]) -> bool {
    let platform = tag(t, "railway") == Some("platform") || (tag(t, "public_transport") == Some("platform") && tag(t, "train") == Some("yes"));
    // `light_rail=yes` alone does not rule a platform out, for the same reason as above.
    let other = ["tram", "bus", "subway", "trolleybus"].iter().any(|k| tag(t, k) == Some("yes"));
    platform && !other && tag(t, "train") != Some("no")
}

/// The station building, or an area mapped as the station.
pub fn is_building(t: &[(String, String)]) -> bool {
    tag(t, "building") == Some("train_station")
        || (tag(t, "public_transport") == Some("station")
            && tag(t, "train") != Some("no")
            && tag(t, "station") != Some("subway"))
        || is_anchor(t)
}

enum Seen {
    Anchor(Anchor),
    PointPlatform(Feature),
    Way { id: i64, kind: Option<Kind>, anchor: Option<String>, refs: Vec<i64> },
    Relation { id: i64, kind: Kind, ways: Vec<i64> },
}

/// Three passes over the extract: the tagged objects; the untagged ways the relations are made of;
/// the coordinates of every node those ways use.
pub fn read(path: &Path, progress: &dyn Fn(&str)) -> Result<Osm> {
    progress("OSM, Durchgang 1: Bahnhöfe, Bahnsteige, Gebäude …");
    let seen: Vec<Seen> = ElementReader::from_path(path)
        .with_context(|| format!("{} lässt sich nicht lesen", path.display()))?
        .par_map_reduce(
            |e| {
                let mut out = Vec::new();
                match e {
                    Element::Node(n) => {
                        let t = kept(n.tags());
                        node_seen(n.id(), n.lat(), n.lon(), &t, &mut out);
                    }
                    Element::DenseNode(n) => {
                        let t = kept(n.tags());
                        if !t.is_empty() {
                            node_seen(n.id(), n.lat(), n.lon(), &t, &mut out);
                        }
                    }
                    Element::Way(w) => {
                        let t = kept(w.tags());
                        let kind = if is_train_platform(&t) {
                            Some(Kind::Platform)
                        } else if is_building(&t) {
                            Some(Kind::Building)
                        } else {
                            None
                        };
                        let anchor = is_anchor(&t).then(|| tag(&t, "name").unwrap_or("").to_string());
                        if kind.is_some() || anchor.is_some() {
                            out.push(Seen::Way { id: w.id(), kind, anchor, refs: w.refs().collect() });
                        }
                    }
                    Element::Relation(r) => {
                        let t = kept(r.tags());
                        let kind = if is_train_platform(&t) {
                            Some(Kind::Platform)
                        } else if is_building(&t) && tag(&t, "type") == Some("multipolygon") {
                            Some(Kind::Building)
                        } else {
                            None
                        };
                        if let Some(kind) = kind {
                            let ways = r
                                .members()
                                .filter(|m| m.member_type == RelMemberType::Way && m.role().map(|x| x != "inner").unwrap_or(true))
                                .map(|m| m.member_id)
                                .collect();
                            out.push(Seen::Relation { id: r.id(), kind, ways });
                        }
                    }
                }
                out
            },
            Vec::new,
            |mut a, mut b| {
                if a.len() < b.len() {
                    std::mem::swap(&mut a, &mut b);
                }
                a.extend(b);
                a
            },
        )?;

    let mut osm = Osm::default();
    let mut ways: HashMap<i64, Vec<i64>> = HashMap::new();
    let mut tagged_ways: Vec<(i64, Option<Kind>, Option<String>)> = Vec::new();
    let mut relations: Vec<(i64, Kind, Vec<i64>)> = Vec::new();
    for s in seen {
        match s {
            Seen::Anchor(a) => osm.anchors.push(a),
            Seen::PointPlatform(f) => osm.features.push(f),
            Seen::Way { id, kind, anchor, refs } => {
                ways.insert(id, refs);
                tagged_ways.push((id, kind, anchor));
            }
            Seen::Relation { id, kind, ways } => relations.push((id, kind, ways)),
        }
    }

    progress(&format!(
        "  {} Bahnhofsknoten, {} Wege, {} Relationen; Durchgang 2: Wege der Relationen …",
        osm.anchors.len(),
        tagged_ways.len(),
        relations.len()
    ));
    let missing: HashSet<i64> = relations.iter().flat_map(|(_, _, w)| w.iter().copied()).filter(|w| !ways.contains_key(w)).collect();
    if !missing.is_empty() {
        let found: Vec<(i64, Vec<i64>)> = ElementReader::from_path(path)?.par_map_reduce(
            |e| match e {
                Element::Way(w) if missing.contains(&w.id()) => vec![(w.id(), w.refs().collect())],
                _ => Vec::new(),
            },
            Vec::new,
            |mut a, b| {
                a.extend(b);
                a
            },
        )?;
        ways.extend(found);
    }

    progress("  Durchgang 3: Koordinaten …");
    let needed: HashSet<i64> = ways.values().flatten().copied().collect();
    let coords: HashMap<i64, (f64, f64)> = ElementReader::from_path(path)?
        .par_map_reduce(
            |e| match e {
                Element::Node(n) if needed.contains(&n.id()) => vec![(n.id(), (n.lat(), n.lon()))],
                Element::DenseNode(n) if needed.contains(&n.id()) => vec![(n.id(), (n.lat(), n.lon()))],
                _ => Vec::new(),
            },
            Vec::new,
            |mut a, b| {
                a.extend(b);
                a
            },
        )?
        .into_iter()
        .collect();
    let pts_of = |refs: &[i64]| -> Vec<(f64, f64)> { refs.iter().filter_map(|r| coords.get(r).copied()).collect() };

    for (id, kind, anchor) in tagged_ways {
        let pts = pts_of(&ways[&id]);
        if pts.is_empty() {
            continue;
        }
        if let Some(name) = anchor {
            let (lat, lon) = centroid(&pts);
            osm.anchors.push(Anchor { osm: format!("w{id}"), name, lat, lon });
        }
        if let Some(kind) = kind {
            osm.features.push(Feature { osm: format!("w{id}"), kind, pts });
        }
    }
    for (id, kind, members) in relations {
        let pts: Vec<(f64, f64)> = members.iter().filter_map(|w| ways.get(w)).flat_map(|r| pts_of(r)).collect();
        if !pts.is_empty() {
            osm.features.push(Feature { osm: format!("r{id}"), kind, pts });
        }
    }
    progress(&format!("  {} OSM-Bahnhöfe, {} Bahnsteige und Gebäude", osm.anchors.len(), osm.features.len()));
    Ok(osm)
}

fn node_seen(id: i64, lat: f64, lon: f64, t: &[(String, String)], out: &mut Vec<Seen>) {
    if is_anchor(t) {
        out.push(Seen::Anchor(Anchor { osm: format!("n{id}"), name: tag(t, "name").unwrap_or("").to_string(), lat, lon }));
    }
    if is_train_platform(t) {
        out.push(Seen::PointPlatform(Feature { osm: format!("n{id}"), kind: Kind::Platform, pts: vec![(lat, lon)] }));
    }
}

fn centroid(pts: &[(f64, f64)]) -> (f64, f64) {
    let n = pts.len() as f64;
    (pts.iter().map(|p| p.0).sum::<f64>() / n, pts.iter().map(|p| p.1).sum::<f64>() / n)
}

// -- geometry, in metres around a local origin --------------------------------------------------

/// Equirectangular metres around (lat0, lon0) — exact enough over the kilometre a station spans.
#[derive(Debug, Clone, Copy)]
pub struct Local {
    lat0: f64,
    lon0: f64,
    kx: f64,
}

const KY: f64 = 111_132.0;

impl Local {
    pub fn new(lat0: f64, lon0: f64) -> Self {
        Self { lat0, lon0, kx: KY * lat0.to_radians().cos() }
    }
    pub fn xy(&self, (lat, lon): (f64, f64)) -> (f64, f64) {
        ((lon - self.lon0) * self.kx, (lat - self.lat0) * KY)
    }
    pub fn ll(&self, (x, y): (f64, f64)) -> (f64, f64) {
        (self.lat0 + y / KY, self.lon0 + x / self.kx)
    }
}

type P = (f64, f64);

fn cross(o: P, a: P, b: P) -> f64 {
    (a.0 - o.0) * (b.1 - o.1) - (a.1 - o.1) * (b.0 - o.0)
}

/// Counter-clockwise convex hull (Andrew's monotone chain).
pub fn hull(points: &[P]) -> Vec<P> {
    let mut ps: Vec<P> = points.to_vec();
    ps.sort_by(|a, b| a.partial_cmp(b).unwrap());
    ps.dedup_by(|a, b| (a.0 - b.0).abs() < 0.01 && (a.1 - b.1).abs() < 0.01);
    if ps.len() < 3 {
        return ps;
    }
    let mut lower: Vec<P> = Vec::new();
    for &p in &ps {
        while lower.len() >= 2 && cross(lower[lower.len() - 2], lower[lower.len() - 1], p) <= 0.0 {
            lower.pop();
        }
        lower.push(p);
    }
    let mut upper: Vec<P> = Vec::new();
    for &p in ps.iter().rev() {
        while upper.len() >= 2 && cross(upper[upper.len() - 2], upper[upper.len() - 1], p) <= 0.0 {
            upper.pop();
        }
        upper.push(p);
    }
    lower.pop();
    upper.pop();
    lower.extend(upper);
    lower
}

pub fn area(poly: &[P]) -> f64 {
    let n = poly.len();
    if n < 3 {
        return 0.0;
    }
    (0..n).map(|i| cross((0.0, 0.0), poly[i], poly[(i + 1) % n])).sum::<f64>().abs() / 2.0
}

/// The hull of `points`, `by` metres wider: every point stands in for a small circle around it.
pub fn buffered_hull(points: &[P], by: f64) -> Vec<P> {
    let mut ps = Vec::with_capacity(points.len() * 12);
    for &(x, y) in &hull(points) {
        for k in 0..12 {
            let a = k as f64 * std::f64::consts::TAU / 12.0;
            ps.push((x + by * a.cos(), y + by * a.sin()));
        }
    }
    if ps.is_empty() {
        for &(x, y) in points {
            for k in 0..12 {
                let a = k as f64 * std::f64::consts::TAU / 12.0;
                ps.push((x + by * a.cos(), y + by * a.sin()));
            }
        }
    }
    hull(&ps)
}

/// At most `max` corners: drop, one at a time, the corner whose removal loses the least area.
/// Removing a corner of a convex polygon only ever shrinks it, by at most a few metres here.
pub fn simplify(mut poly: Vec<P>, max: usize) -> Vec<P> {
    while poly.len() > max {
        let n = poly.len();
        let (i, _) = (0..n)
            .map(|i| (i, cross(poly[(i + n - 1) % n], poly[i], poly[(i + 1) % n]).abs()))
            .min_by(|a, b| a.1.partial_cmp(&b.1).unwrap())
            .unwrap();
        poly.remove(i);
    }
    poly
}

pub fn contains(poly: &[P], p: P) -> bool {
    let n = poly.len();
    n >= 3 && (0..n).all(|i| cross(poly[i], poly[(i + 1) % n], p) >= -1e-6)
}

fn seg_dist(p: P, a: P, b: P) -> f64 {
    let (dx, dy) = (b.0 - a.0, b.1 - a.1);
    let l = dx * dx + dy * dy;
    let t = if l == 0.0 { 0.0 } else { (((p.0 - a.0) * dx + (p.1 - a.1) * dy) / l).clamp(0.0, 1.0) };
    ((p.0 - a.0 - t * dx).powi(2) + (p.1 - a.1 - t * dy).powi(2)).sqrt()
}

/// Metres from `p` to the polygon, 0 inside.
pub fn distance_to(poly: &[P], p: P) -> f64 {
    if contains(poly, p) {
        return 0.0;
    }
    let n = poly.len();
    (0..n).map(|i| seg_dist(p, poly[i], poly[(i + 1) % n])).fold(f64::INFINITY, f64::min)
}

fn dist(a: P, b: P) -> f64 {
    ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt()
}

/// The smallest circle holding every point. Exhaustive over pairs and triples, which is fine for
/// the two dozen corners of a premise.
pub fn enclosing_circle(ps: &[P]) -> (P, f64) {
    if ps.len() == 1 {
        return (ps[0], 0.0);
    }
    let holds = |c: P, r: f64| ps.iter().all(|&p| dist(c, p) <= r + 1e-6);
    let mut best: Option<(P, f64)> = None;
    let mut offer = |c: P, r: f64| {
        if best.is_none_or(|(_, br)| r < br) && holds(c, r) {
            best = Some((c, r));
        }
    };
    for i in 0..ps.len() {
        for j in i + 1..ps.len() {
            let c = ((ps[i].0 + ps[j].0) / 2.0, (ps[i].1 + ps[j].1) / 2.0);
            offer(c, dist(c, ps[i]));
            for k in j + 1..ps.len() {
                if let Some(c) = circumcentre(ps[i], ps[j], ps[k]) {
                    offer(c, dist(c, ps[i]));
                }
            }
        }
    }
    best.unwrap_or((ps[0], 0.0))
}

fn circumcentre(a: P, b: P, c: P) -> Option<P> {
    let d = 2.0 * (a.0 * (b.1 - c.1) + b.0 * (c.1 - a.1) + c.0 * (a.1 - b.1));
    if d.abs() < 1e-9 {
        return None;
    }
    let (a2, b2, c2) = (a.0 * a.0 + a.1 * a.1, b.0 * b.0 + b.1 * b.1, c.0 * c.0 + c.1 * c.1);
    Some(((a2 * (b.1 - c.1) + b2 * (c.1 - a.1) + c2 * (a.1 - b.1)) / d, (a2 * (c.0 - b.0) + b2 * (a.0 - c.0) + c2 * (b.0 - a.0)) / d))
}

/// As few circles as cover the premise with none larger than [TOUCH_TARGET_M] (at most
/// [TOUCH_MAX]), each at least [TOUCH_MIN_M]. The premise is sampled on a 15 m grid, the samples
/// clustered (k-means from a farthest-point start, so the result does not depend on chance), and
/// each circle reaches its farthest sample.
pub fn touch_points(poly: &[P]) -> Vec<(P, f64)> {
    let (min_x, max_x) = poly.iter().fold((f64::MAX, f64::MIN), |(a, b), p| (a.min(p.0), b.max(p.0)));
    let (min_y, max_y) = poly.iter().fold((f64::MAX, f64::MIN), |(a, b), p| (a.min(p.1), b.max(p.1)));
    let mut samples = Vec::new();
    let mut y = min_y;
    while y <= max_y {
        let mut x = min_x;
        while x <= max_x {
            if contains(poly, (x, y)) {
                samples.push((x, y));
            }
            x += 15.0;
        }
        y += 15.0;
    }
    samples.extend_from_slice(poly);
    let mut last = Vec::new();
    for k in 1..=TOUCH_MAX {
        let circles = kmeans(&samples, k);
        let worst = circles.iter().map(|c| c.1).fold(0.0, f64::max);
        last = circles;
        if worst <= TOUCH_TARGET_M {
            break;
        }
    }
    last.into_iter().map(|(c, r)| (c, r.max(TOUCH_MIN_M))).collect()
}

fn kmeans(samples: &[P], k: usize) -> Vec<(P, f64)> {
    let mut centres = vec![centroid(samples)];
    while centres.len() < k {
        let far = samples
            .iter()
            .max_by(|a, b| {
                let da = centres.iter().map(|c| dist(**a, *c)).fold(f64::MAX, f64::min);
                let db = centres.iter().map(|c| dist(**b, *c)).fold(f64::MAX, f64::min);
                da.partial_cmp(&db).unwrap()
            })
            .copied()
            .unwrap();
        centres.push(far);
    }
    let mut owner = vec![0usize; samples.len()];
    for _ in 0..20 {
        for (i, s) in samples.iter().enumerate() {
            owner[i] = (0..k).min_by(|&a, &b| dist(*s, centres[a]).partial_cmp(&dist(*s, centres[b])).unwrap()).unwrap();
        }
        for (c, centre) in centres.iter_mut().enumerate() {
            let mine: Vec<P> = samples.iter().zip(&owner).filter(|(_, o)| **o == c).map(|(s, _)| *s).collect();
            if !mine.is_empty() {
                *centre = centroid(&mine);
            }
        }
    }
    (0..k)
        .filter_map(|c| {
            let mine: Vec<P> = samples.iter().zip(&owner).filter(|(_, o)| **o == c).map(|(s, _)| *s).collect();
            (!mine.is_empty()).then(|| {
                let (centre, r) = enclosing_circle(&hull(&mine));
                (centre, r)
            })
        })
        .collect()
}

// -- per station --------------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
pub enum Outcome {
    Premise,
    /// No OSM station within [ANCHOR_REACH_M].
    NoAnchor,
    /// No OSM station within [OUTSIDE_M] either: outside the extract (the table carries stations
    /// abroad that trains from Germany reach), not a gap in OSM.
    Outside,
    /// An OSM station, but no train platform belongs to it.
    NoPlatform,
    /// Its OSM station belongs to another of ours (Frankfurt Hbf „tief"): part of that premise.
    PartOf(u32),
    /// Built, then thrown out; the reason says why.
    Rejected(String),
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq)]
pub struct Circle {
    pub lat: f64,
    pub lon: f64,
    pub r: f64,
}

#[derive(Debug, Clone)]
pub struct Premise {
    pub station: ExtractStation,
    pub outcome: Outcome,
    /// The premise, (lat, lon), counter-clockwise; empty unless [Outcome::Premise].
    pub outline: Vec<(f64, f64)>,
    pub ring: Circle,
    pub touch: Vec<Circle>,
    /// The members, for the drawing.
    pub members: Vec<Feature>,
    pub anchors: Vec<String>,
    pub area_m2: f64,
    /// Farthest point of the premise from our station point.
    pub reach_m: f64,
}

fn group_key(name: &str) -> String {
    let n = normalise_station_name(name);
    n.split_whitespace().filter(|w| !matches!(*w, "tief" | "hoch" | "oben" | "unten")).collect::<Vec<_>>().join(" ")
}

/// Cells of about 1.1 km × 0.7 km for the neighbourhood lookups.
fn cell(lat: f64, lon: f64) -> (i32, i32) {
    ((lat * 100.0).floor() as i32, (lon * 100.0).floor() as i32)
}

struct Grid<T> {
    cells: HashMap<(i32, i32), Vec<T>>,
}

impl<T: Copy> Grid<T> {
    fn new() -> Self {
        Self { cells: HashMap::new() }
    }
    fn put(&mut self, lat: f64, lon: f64, v: T) {
        self.cells.entry(cell(lat, lon)).or_default().push(v);
    }
    fn near(&self, lat: f64, lon: f64) -> impl Iterator<Item = T> + '_ {
        let (cy, cx) = cell(lat, lon);
        (-1..=1).flat_map(move |dy| (-1..=1).map(move |dx| (cy + dy, cx + dx))).flat_map(move |c| self.cells.get(&c).into_iter().flatten().copied())
    }
}

/// Every station's premise, ring and touch points.
pub fn build(stations: &[ExtractStation], osm: &Osm) -> Vec<Premise> {
    // Anchors that are one station under two OSM objects (Köln Messe/Deutz „hoch" and „tief")
    // form one group: the same name without the level word, and close.
    let mut agrid = Grid::new();
    for (i, a) in osm.anchors.iter().enumerate() {
        agrid.put(a.lat, a.lon, i);
    }
    let mut group: Vec<usize> = (0..osm.anchors.len()).collect();
    fn root(g: &mut [usize], mut i: usize) -> usize {
        while g[i] != i {
            g[i] = g[g[i]];
            i = g[i];
        }
        i
    }
    for (i, a) in osm.anchors.iter().enumerate() {
        let key = group_key(&a.name);
        if key.is_empty() {
            continue;
        }
        for j in agrid.near(a.lat, a.lon) {
            if j > i && haversine_m(a.lat, a.lon, osm.anchors[j].lat, osm.anchors[j].lon) <= ANCHOR_REACH_M && group_key(&osm.anchors[j].name) == key {
                let (ri, rj) = (root(&mut group, i), root(&mut group, j));
                group[ri] = rj;
            }
        }
    }
    let groups: Vec<usize> = (0..osm.anchors.len()).map(|i| root(&mut group, i)).collect();

    // Each group belongs to exactly one of our stations: one whose name matches, the higher rank
    // among those, else the nearest. The others near it are part of that station's premise.
    let mut sgrid = Grid::new();
    for (i, s) in stations.iter().enumerate() {
        sgrid.put(s.lat, s.lon, i);
    }
    let mut owner: HashMap<usize, usize> = HashMap::new();
    let mut members_of_group: HashMap<usize, Vec<usize>> = HashMap::new();
    for (i, g) in groups.iter().enumerate() {
        members_of_group.entry(*g).or_default().push(i);
    }
    for (g, anchors) in &members_of_group {
        let mut best: Option<(usize, (u8, i32, i64))> = None;
        for &ai in anchors {
            let a = &osm.anchors[ai];
            for si in sgrid.near(a.lat, a.lon) {
                let s = &stations[si];
                let d = haversine_m(a.lat, a.lon, s.lat, s.lon);
                if d > ANCHOR_REACH_M {
                    continue;
                }
                // Rank decides only between stations that both carry the name (Frankfurt Hbf and
                // „… tief"). Without a name match the nearest one wins: DELFI's short names
                // („D-Volksgarten S") rarely match OSM's, and a rank rule then let one station
                // collect its neighbours' anchors.
                let matches = station_names_match(&s.name, &a.name);
                let score = (u8::from(!matches), if matches { -(s.rank as i32) } else { 0 }, d.round() as i64);
                if best.as_ref().is_none_or(|(_, b)| score < *b) {
                    best = Some((si, score));
                }
            }
        }
        if let Some((si, _)) = best {
            owner.insert(*g, si);
        }
    }

    // Each feature belongs to the nearest anchor group within reach.
    let mut feature_group: Vec<Option<usize>> = Vec::with_capacity(osm.features.len());
    for f in &osm.features {
        let (lat, lon) = centroid(&f.pts);
        let mut best: Option<(usize, f64)> = None;
        for ai in agrid.near(lat, lon) {
            let a = &osm.anchors[ai];
            let d = haversine_m(lat, lon, a.lat, a.lon);
            if d <= MEMBER_REACH_M && best.is_none_or(|(_, bd)| d < bd) {
                best = Some((groups[ai], d));
            }
        }
        feature_group.push(best.map(|b| b.0));
    }
    let mut features_of_station: HashMap<usize, Vec<usize>> = HashMap::new();
    let mut groups_of_station: HashMap<usize, Vec<usize>> = HashMap::new();
    for (g, si) in &owner {
        groups_of_station.entry(*si).or_default().push(*g);
    }
    for (fi, g) in feature_group.iter().enumerate() {
        if let Some(si) = g.and_then(|g| owner.get(&g)) {
            features_of_station.entry(*si).or_default().push(fi);
        }
    }

    stations
        .iter()
        .enumerate()
        .map(|(si, s)| {
            let local = Local::new(s.lat, s.lon);
            let fallback = |outcome: Outcome| Premise {
                station: s.clone(),
                outcome,
                outline: Vec::new(),
                ring: Circle { lat: s.lat, lon: s.lon, r: RING_MIN_M },
                touch: Vec::new(),
                members: Vec::new(),
                anchors: Vec::new(),
                area_m2: 0.0,
                reach_m: 0.0,
            };
            let Some(my_groups) = groups_of_station.get(&si) else {
                // Near an OSM station that is somebody else's: part of that premise.
                let near = agrid
                    .near(s.lat, s.lon)
                    .filter(|&ai| haversine_m(s.lat, s.lon, osm.anchors[ai].lat, osm.anchors[ai].lon) <= ANCHOR_REACH_M)
                    .filter_map(|ai| owner.get(&groups[ai]).copied())
                    .find(|&o| o != si);
                return fallback(match near {
                    Some(o) => Outcome::PartOf(stations[o].id),
                    None if osm.anchors.iter().any(|a| haversine_m(s.lat, s.lon, a.lat, a.lon) <= OUTSIDE_M) => Outcome::NoAnchor,
                    None => Outcome::Outside,
                });
            };
            let anchors: Vec<String> = (0..osm.anchors.len()).filter(|ai| my_groups.contains(&groups[*ai])).map(|ai| osm.anchors[ai].osm.clone()).collect();
            let members: Vec<Feature> = features_of_station.get(&si).into_iter().flatten().map(|fi| osm.features[*fi].clone()).collect();
            if !members.iter().any(|f| f.kind == Kind::Platform) {
                return Premise { anchors, ..fallback(Outcome::NoPlatform) };
            }
            let pts: Vec<P> = members.iter().flat_map(|f| f.pts.iter().map(|p| local.xy(*p))).collect();
            let poly = simplify(buffered_hull(&pts, BUFFER_M), MAX_CORNERS);
            let a = area(&poly);
            let reach = poly.iter().map(|p| dist(*p, (0.0, 0.0))).fold(0.0, f64::max);
            let off = distance_to(&poly, (0.0, 0.0));
            let reject = if a > MAX_AREA_M2 {
                Some(format!("Fläche {:.0} ha", a / 10_000.0))
            } else if off > ANCHOR_REACH_M {
                Some(format!("unser Punkt {off:.0} m neben dem Gelände"))
            } else {
                None
            };
            if let Some(why) = reject {
                return Premise { anchors, members, area_m2: a, reach_m: reach, ..fallback(Outcome::Rejected(why)) };
            }
            let (centre, r) = enclosing_circle(&poly);
            let ring_ll = local.ll(centre);
            let touch = touch_points(&poly)
                .into_iter()
                .map(|(c, r)| {
                    let (lat, lon) = local.ll(c);
                    Circle { lat, lon, r }
                })
                .collect();
            Premise {
                station: s.clone(),
                outcome: Outcome::Premise,
                outline: poly.iter().map(|p| local.ll(*p)).collect(),
                ring: Circle { lat: ring_ll.0, lon: ring_ll.1, r: (r + RING_MARGIN_M).clamp(RING_MIN_M, RING_MAX_M) },
                touch,
                members,
                anchors,
                area_m2: a,
                reach_m: reach,
            }
        })
        .collect()
}

// -- what goes to the server ----------------------------------------------------------------

/// The body of `POST /admin/stations/outlines`: every premise of one run. The server replaces its
/// table with exactly this, so a run is always whole.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct OutlineSet {
    /// The day of the OSM extract, `YYYY-MM-DD`.
    pub osm_timestamp: Option<String>,
    pub outlines: Vec<OutlineRow>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct OutlineRow {
    /// Our station id, the number behind `vs:`.
    pub station: u32,
    /// `[lat, lon]`, counter-clockwise.
    pub outline: Vec<[f64; 2]>,
    pub ring: Circle,
    pub touch: Vec<Circle>,
    /// The OSM objects it is built from.
    pub osm: Vec<String>,
}

pub fn to_set(ps: &[Premise], osm_timestamp: Option<String>) -> OutlineSet {
    OutlineSet {
        osm_timestamp,
        outlines: ps
            .iter()
            .filter(|p| p.outcome == Outcome::Premise)
            .map(|p| OutlineRow {
                station: p.station.id,
                outline: p.outline.iter().map(|(la, lo)| [round6(*la), round6(*lo)]).collect(),
                ring: Circle { lat: round6(p.ring.lat), lon: round6(p.ring.lon), r: p.ring.r.round() },
                touch: p.touch.iter().map(|t| Circle { lat: round6(t.lat), lon: round6(t.lon), r: t.r.round() }).collect(),
                osm: p.anchors.iter().cloned().chain(p.members.iter().map(|m| m.osm.clone())).collect(),
            })
            .collect(),
    }
}

/// What the server refuses, whoever sent it: the shape docs/48 promises the phone.
pub fn check_row(r: &OutlineRow) -> Result<(), String> {
    let ok = |c: &Circle| (-90.0..=90.0).contains(&c.lat) && (-180.0..=180.0).contains(&c.lon);
    if r.outline.len() < 3 || r.outline.len() > MAX_CORNERS {
        return Err(format!("vs:{}: {} Ecken", r.station, r.outline.len()));
    }
    if !ok(&r.ring) || !(RING_MIN_M..=RING_MAX_M).contains(&r.ring.r) {
        return Err(format!("vs:{}: Ring {:.0} m", r.station, r.ring.r));
    }
    if r.touch.is_empty() || r.touch.len() > TOUCH_MAX || r.touch.iter().any(|t| !ok(t) || t.r < TOUCH_MIN_M) {
        return Err(format!("vs:{}: Tastpunkte {:?}", r.station, r.touch.iter().map(|t| t.r).collect::<Vec<_>>()));
    }
    Ok(())
}

// -- report -------------------------------------------------------------------------------------

/// How many other stations' rings reach into this one's — what iOS has to keep registered next to
/// the station's own ring and touch points while the phone is there (docs/48, 20 regions).
pub fn neighbours(ps: &[Premise]) -> Vec<usize> {
    let mut grid = Grid::new();
    for (i, p) in ps.iter().enumerate() {
        grid.put(p.ring.lat, p.ring.lon, i);
    }
    ps.iter()
        .enumerate()
        .map(|(i, p)| {
            // Rings reach up to 1 km, so look three cells out rather than one.
            let (cy, cx) = cell(p.ring.lat, p.ring.lon);
            (-2..=2)
                .flat_map(|dy| (-2..=2).map(move |dx| (cy + dy, cx + dx)))
                .flat_map(|c| grid.cells.get(&c).into_iter().flatten().copied())
                .filter(|&j| j != i && haversine_m(p.ring.lat, p.ring.lon, ps[j].ring.lat, ps[j].ring.lon) < p.ring.r + ps[j].ring.r)
                .count()
        })
        .collect()
}

fn outcome_label(o: &Outcome) -> &'static str {
    match o {
        Outcome::Premise => "Gelände",
        Outcome::NoAnchor => "kein OSM-Bahnhof in 400 m",
        Outcome::Outside => "außerhalb des Auszugs (Ausland)",
        Outcome::NoPlatform => "OSM-Bahnhof ohne Zug-Bahnsteig",
        Outcome::PartOf(_) => "Teil eines anderen Geländes",
        Outcome::Rejected(_) => "verworfen",
    }
}

pub fn report(ps: &[Premise]) -> String {
    use std::fmt::Write;
    let mut out = String::new();
    let nb = neighbours(ps);
    let _ = writeln!(out, "{} Stationen", ps.len());
    for (rank, label) in [(3u8, "Fernverkehr"), (2, "Nahverkehr"), (1, "nur S-Bahn")] {
        let mine: Vec<&Premise> = ps.iter().filter(|p| p.station.rank == rank).collect();
        if mine.is_empty() {
            continue;
        }
        let n = mine.len();
        let _ = writeln!(out, "\nRang {rank}, {label}: {n}");
        let mut by: Vec<(&str, usize)> = Vec::new();
        for p in &mine {
            let l = outcome_label(&p.outcome);
            match by.iter_mut().find(|(k, _)| *k == l) {
                Some(e) => e.1 += 1,
                None => by.push((l, 1)),
            }
        }
        by.sort_by_key(|(_, c)| std::cmp::Reverse(*c));
        for (l, c) in by {
            let _ = writeln!(out, "  {:<34} {:>5}  ({:>3} %)", l, c, c * 100 / n);
        }
        let mut rings: Vec<f64> = mine.iter().filter(|p| p.outcome == Outcome::Premise).map(|p| p.ring.r).collect();
        if !rings.is_empty() {
            rings.sort_by(|a, b| a.partial_cmp(b).unwrap());
            let q = |f: f64| rings[((rings.len() - 1) as f64 * f) as usize];
            let touch: Vec<usize> = mine.iter().filter(|p| p.outcome == Outcome::Premise).map(|p| p.touch.len()).collect();
            let mut hist = [0usize; TOUCH_MAX + 1];
            for t in &touch {
                hist[*t] += 1;
            }
            let _ = writeln!(out, "  Ring: Median {:.0} m, 90 % {:.0} m, größter {:.0} m; über 300 m: {} %", q(0.5), q(0.9), q(1.0), rings.iter().filter(|r| **r > RING_MIN_M).count() * 100 / rings.len());
            let _ = writeln!(
                out,
                "  Tastpunkte: {}",
                (1..=TOUCH_MAX).filter(|k| hist[*k] > 0).map(|k| format!("{k}× {}", hist[k])).collect::<Vec<_>>().join(", ")
            );
        }
    }
    // iOS, at a station: umbrella + this ring + its touch points + the neighbours' rings.
    let mut worst: Vec<(usize, &Premise)> = ps.iter().zip(&nb).filter(|(p, _)| p.outcome == Outcome::Premise).map(|(p, n)| (*n, p)).collect();
    worst.sort_by_key(|(n, _)| std::cmp::Reverse(*n));
    let over = worst.iter().filter(|(n, p)| 1 + 1 + p.touch.len() + n > 20).count();
    let _ = writeln!(out, "\niOS am Bahnhof (Regenschirm + Ring + Tastpunkte + Ringe der Nachbarn, 20 Plätze):");
    let _ = writeln!(out, "  über 20: {over} Bahnhöfe. Die meisten Nachbarn:");
    for (n, p) in worst.iter().take(8) {
        let _ = writeln!(out, "    {:<40} {n} Nachbarringe, {} Tastpunkte → {} Plätze", p.station.name, p.touch.len(), 2 + p.touch.len() + n);
    }
    let rejected: Vec<&Premise> = ps.iter().filter(|p| matches!(p.outcome, Outcome::Rejected(_))).collect();
    let _ = writeln!(out, "\nVerworfen: {}", rejected.len());
    for p in rejected.iter().take(40) {
        if let Outcome::Rejected(why) = &p.outcome {
            let _ = writeln!(out, "  {:<40} {why}", p.station.name);
        }
    }
    let part: Vec<&Premise> = ps.iter().filter(|p| matches!(p.outcome, Outcome::PartOf(_))).collect();
    let _ = writeln!(out, "\nTeil eines anderen Geländes: {} (erste 20)", part.len());
    for p in part.iter().take(20) {
        if let Outcome::PartOf(o) = &p.outcome {
            let of = ps.iter().find(|q| q.station.id == *o).map(|q| q.station.name.as_str()).unwrap_or("?");
            let _ = writeln!(out, "  {:<40} → {of}", p.station.name);
        }
    }
    out
}

// -- GeoJSON and drawings -----------------------------------------------------------------------

fn circle_ring(c: &Circle, n: usize) -> Vec<(f64, f64)> {
    let l = Local::new(c.lat, c.lon);
    (0..=n)
        .map(|k| {
            let a = k as f64 * std::f64::consts::TAU / n as f64;
            l.ll((c.r * a.cos(), c.r * a.sin()))
        })
        .collect()
}

fn coords_json(ring: &[(f64, f64)]) -> serde_json::Value {
    let mut v: Vec<serde_json::Value> = ring.iter().map(|(la, lo)| serde_json::json!([round6(*lo), round6(*la)])).collect();
    if let (Some(f), Some(l)) = (ring.first(), ring.last()) {
        if f != l {
            v.push(serde_json::json!([round6(f.1), round6(f.0)]));
        }
    }
    serde_json::Value::Array(v)
}

fn round6(x: f64) -> f64 {
    (x * 1e6).round() / 1e6
}

/// One FeatureCollection: per station its point, and where there is one its premise, ring and
/// touch points. Carries the ODbL notice, because it is OSM-derived.
pub fn geojson(ps: &[Premise], osm_timestamp: Option<&str>) -> serde_json::Value {
    use serde_json::json;
    let mut features = Vec::new();
    for p in ps {
        let id = format!("vs:{}", p.station.id);
        let outcome = outcome_label(&p.outcome);
        features.push(json!({"type":"Feature","geometry":{"type":"Point","coordinates":[round6(p.station.lon),round6(p.station.lat)]},
            "properties":{"id":id,"name":p.station.name,"rank":p.station.rank,"role":"station","outcome":outcome}}));
        if p.outcome != Outcome::Premise {
            continue;
        }
        features.push(json!({"type":"Feature","geometry":{"type":"Polygon","coordinates":[coords_json(&p.outline)]},
            "properties":{"id":id,"name":p.station.name,"role":"premise","area_ha":(p.area_m2/1000.0).round()/10.0,"osm":p.members.iter().map(|m| m.osm.clone()).chain(p.anchors.iter().cloned()).collect::<Vec<_>>()}}));
        features.push(json!({"type":"Feature","geometry":{"type":"Polygon","coordinates":[coords_json(&circle_ring(&p.ring, 48))]},
            "properties":{"id":id,"role":"ring","radius_m":p.ring.r.round()}}));
        for (i, t) in p.touch.iter().enumerate() {
            features.push(json!({"type":"Feature","geometry":{"type":"Polygon","coordinates":[coords_json(&circle_ring(t, 32))]},
                "properties":{"id":id,"role":"touch","n":i+1,"radius_m":t.r.round()}}));
        }
    }
    json!({"type":"FeatureCollection",
        "license":"ODbL-1.0","attribution":"© OpenStreetMap-Mitwirkende, https://www.openstreetmap.org/copyright",
        "osm_timestamp":osm_timestamp,"features":features})
}

fn esc(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;")
}

/// One station drawn to scale: its platforms and buildings, the premise, the ring, the touch
/// points and our point. No map tiles — the shapes are the point.
pub fn svg(p: &Premise) -> String {
    let local = Local::new(p.station.lat, p.station.lon);
    let ring_c = local.xy((p.ring.lat, p.ring.lon));
    let half = (dist(ring_c, (0.0, 0.0)) + p.ring.r) * 1.08;
    let (w, h) = (640.0, 640.0);
    let s = w / (2.0 * half);
    let tx = |q: P| (w / 2.0 + q.0 * s, h / 2.0 - q.1 * s);
    let mut o = String::new();
    use std::fmt::Write;
    let _ = write!(o, r##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" font-family="Archivo, Helvetica, Arial, sans-serif"><rect width="100%" height="100%" fill="#fbfaf7"/>"##);
    let circle = |o: &mut String, c: &Circle, stroke: &str, fill: &str, dash: &str| {
        let (x, y) = tx(local.xy((c.lat, c.lon)));
        let _ = write!(o, r#"<circle cx="{x:.1}" cy="{y:.1}" r="{:.1}" fill="{fill}" stroke="{stroke}" stroke-width="1.5" stroke-dasharray="{dash}"/>"#, c.r * s);
    };
    circle(&mut o, &p.ring, "#111", "none", "6 4");
    for t in &p.touch {
        circle(&mut o, t, "#d0021b", "#d0021b\" fill-opacity=\"0.07", "");
    }
    let path = |pts: &[(f64, f64)]| pts.iter().map(|q| { let (x, y) = tx(local.xy(*q)); format!("{x:.1},{y:.1}") }).collect::<Vec<_>>().join(" ");
    if !p.outline.is_empty() {
        let _ = write!(o, r##"<polygon points="{}" fill="#111" fill-opacity="0.08" stroke="#111" stroke-width="2"/>"##, path(&p.outline));
    }
    for f in &p.members {
        let colour = if f.kind == Kind::Platform { "#555" } else { "#999" };
        if f.pts.len() == 1 {
            let (x, y) = tx(local.xy(f.pts[0]));
            let _ = write!(o, r#"<circle cx="{x:.1}" cy="{y:.1}" r="2.5" fill="{colour}"/>"#);
        } else {
            let _ = write!(o, r#"<polyline points="{}" fill="none" stroke="{colour}" stroke-width="2"/>"#, path(&f.pts));
        }
    }
    let (x, y) = tx((0.0, 0.0));
    let _ = write!(o, r##"<circle cx="{x:.1}" cy="{y:.1}" r="5" fill="#d0021b" stroke="#fff" stroke-width="1.5"/>"##);
    // Scale bar: 100 m.
    let bar = 100.0 * s;
    let _ = write!(o, r##"<line x1="20" y1="{y0}" x2="{x1:.1}" y2="{y0}" stroke="#111" stroke-width="3"/><text x="20" y="{yt}" font-size="12" fill="#111">100 m</text>"##, y0 = h - 20.0, x1 = 20.0 + bar, yt = h - 28.0);
    let head = match &p.outcome {
        Outcome::Premise => format!("Ring {:.0} m · {} Tastpunkte ({}) · {:.1} ha", p.ring.r, p.touch.len(), p.touch.iter().map(|t| format!("{:.0}", t.r)).collect::<Vec<_>>().join("/"), p.area_m2 / 10_000.0),
        other => format!("{} — 300-m-Wächter", outcome_label(other)),
    };
    let _ = write!(o, r##"<text x="20" y="30" font-size="18" font-weight="700" fill="#111">{}</text><text x="20" y="50" font-size="13" fill="#333">{}</text>"##, esc(&p.station.name), esc(&head));
    let _ = write!(o, r##"<text x="{}" y="{}" font-size="10" fill="#666" text-anchor="end">Gelände © OpenStreetMap-Mitwirkende, ODbL</text></svg>"##, w - 12.0, h - 12.0);
    o
}

/// Every station as a dot on one map of Germany, coloured by outcome — where OSM is thin shows
/// as a region, which a table cannot.
pub fn coverage_svg(ps: &[Premise]) -> String {
    let (w, h) = (700.0, 900.0);
    let (lat0, lat1, lon0, lon1) = (47.2, 55.1, 5.8, 15.1);
    let kx = (lat0 + lat1) / 2.0_f64;
    let kx = kx.to_radians().cos();
    let sx = w / ((lon1 - lon0) * kx);
    let sy = h / (lat1 - lat0);
    let s = sx.min(sy);
    let mut o = format!(r##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" font-family="Archivo, Helvetica, Arial, sans-serif"><rect width="100%" height="100%" fill="#fbfaf7"/>"##);
    let mut draw = |want: fn(&Outcome) -> bool, colour: &str, r: f64| {
        for p in ps.iter().filter(|p| want(&p.outcome)) {
            let (lat, lon) = (p.station.lat, p.station.lon);
            if !(lat0..lat1).contains(&lat) || !(lon0..lon1).contains(&lon) {
                continue;
            }
            let x = (lon - lon0) * kx * s;
            let y = (lat1 - lat) * s;
            o.push_str(&format!(r#"<circle cx="{x:.1}" cy="{y:.1}" r="{r}" fill="{colour}"/>"#));
        }
    };
    draw(|o| *o == Outcome::Premise, "#9a9a9a", 1.2);
    draw(|o| matches!(o, Outcome::PartOf(_)), "#4a90d9", 1.6);
    draw(|o| matches!(o, Outcome::NoAnchor | Outcome::NoPlatform | Outcome::Rejected(_)), "#d0021b", 2.0);
    o.push_str(r##"<text x="16" y="28" font-size="16" font-weight="700" fill="#111">Bahnhofsgelände aus OSM</text><text x="16" y="48" font-size="12" fill="#333">grau: Gelände · blau: Teil eines anderen · rot: 300-m-Wächter</text>"##);
    o.push_str(&format!(r##"<text x="{}" y="{}" font-size="10" fill="#666" text-anchor="end">© OpenStreetMap-Mitwirkende, ODbL</text></svg>"##, w - 10.0, h - 10.0));
    o
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_square_has_four_corners_and_its_area() {
        let h = hull(&[(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0), (5.0, 5.0)]);
        assert_eq!(h.len(), 4);
        assert!((area(&h) - 100.0).abs() < 1e-9);
        assert!(contains(&h, (5.0, 5.0)) && !contains(&h, (11.0, 5.0)));
        assert!((distance_to(&h, (13.0, 5.0)) - 3.0).abs() < 1e-9);
    }

    #[test]
    fn the_buffer_widens_by_its_distance() {
        let h = buffered_hull(&[(0.0, 0.0), (100.0, 0.0)], 20.0);
        let xs = h.iter().map(|p| p.0).fold((f64::MAX, f64::MIN), |(a, b), x| (a.min(x), b.max(x)));
        assert!((xs.0 + 20.0).abs() < 0.1 && (xs.1 - 120.0).abs() < 0.1, "{xs:?}");
        assert!(simplify(h, 8).len() <= 8);
    }

    #[test]
    fn the_enclosing_circle_of_a_rectangle_is_its_diagonal() {
        let (c, r) = enclosing_circle(&[(0.0, 0.0), (300.0, 0.0), (300.0, 400.0), (0.0, 400.0)]);
        assert!((c.0 - 150.0).abs() < 1e-6 && (c.1 - 200.0).abs() < 1e-6);
        assert!((r - 250.0).abs() < 1e-6);
    }

    /// A 60 × 40 m halt gets one touch point of the minimum size; a 400 × 300 m Hauptbahnhof gets
    /// several, each within the target, and together they cover every corner.
    #[test]
    fn touch_points_cover_the_premise() {
        let small = hull(&[(0.0, 0.0), (60.0, 0.0), (60.0, 40.0), (0.0, 40.0)]);
        let t = touch_points(&small);
        assert_eq!(t.len(), 1);
        assert_eq!(t[0].1, TOUCH_MIN_M);
        let big = hull(&[(0.0, 0.0), (400.0, 0.0), (400.0, 300.0), (0.0, 300.0)]);
        let t = touch_points(&big);
        assert!((2..=TOUCH_MAX).contains(&t.len()), "{}", t.len());
        assert!(t.iter().all(|(_, r)| *r >= TOUCH_MIN_M && *r <= TOUCH_TARGET_M + 1.0));
        for corner in &big {
            assert!(t.iter().any(|(c, r)| dist(*c, *corner) <= r + 1e-6), "corner {corner:?} not covered");
        }
    }

    #[test]
    fn the_level_word_does_not_split_a_station() {
        assert_eq!(group_key("Köln Messe/Deutz (tief)"), group_key("Köln Messe/Deutz"));
        assert_eq!(group_key("Frankfurt (Main) Hauptbahnhof tief"), group_key("Frankfurt (Main) Hbf"));
    }

    fn st(id: u32, name: &str, lat: f64, lon: f64, rank: u8) -> ExtractStation {
        ExtractStation { id, name: name.into(), lat, lon, rank, flags: 0 }
    }

    /// Two S-Bahn stations a kilometre apart, neither name matching OSM's spelling: each keeps
    /// its own OSM station, whatever their ranks.
    #[test]
    fn without_a_name_match_the_nearest_station_owns_the_anchor() {
        let l = Local::new(51.2, 6.78);
        let plat = |x: f64| Feature { osm: format!("w{x}"), kind: Kind::Platform, pts: vec![l.ll((x - 60.0, 0.0)), l.ll((x + 60.0, 0.0))] };
        let osm = Osm {
            anchors: vec![
                Anchor { osm: "n1".into(), name: "Düsseldorf-Volksgarten".into(), lat: l.ll((0.0, 0.0)).0, lon: l.ll((0.0, 0.0)).1 },
                Anchor { osm: "n2".into(), name: "Düsseldorf-Oberbilk".into(), lat: l.ll((350.0, 0.0)).0, lon: l.ll((350.0, 0.0)).1 },
            ],
            features: vec![plat(0.0), plat(350.0)],
        };
        let a = l.ll((10.0, 0.0));
        let b = l.ll((340.0, 0.0));
        let ps = build(&[st(1, "Düsseldorf, D-Volksgarten S", a.0, a.1, 1), st(2, "Düsseldorf, D-Oberbilk Bf", b.0, b.1, 3)], &osm);
        assert_eq!(ps[0].outcome, Outcome::Premise, "{:?}", ps[0].outcome);
        assert_eq!(ps[1].outcome, Outcome::Premise);
        assert_eq!(ps[0].anchors, vec!["n1".to_string()]);
        assert_eq!(ps[1].anchors, vec!["n2".to_string()]);
    }

    /// Frankfurt Hbf and „tief" are two of ours under one OSM station: the Hauptbahnhof owns the
    /// premise, „tief" is part of it. A station nowhere near OSM gets the 300 m guard.
    #[test]
    fn one_osm_station_belongs_to_one_of_ours() {
        let l = Local::new(50.107, 8.663);
        let plat = |x0: f64| Feature { osm: format!("w{x0}"), kind: Kind::Platform, pts: vec![l.ll((x0, -150.0)), l.ll((x0, 150.0))] };
        let osm = Osm {
            anchors: vec![
                Anchor { osm: "n1".into(), name: "Frankfurt (Main) Hauptbahnhof".into(), lat: 50.107, lon: 8.663 },
                Anchor { osm: "n2".into(), name: "Frankfurt (Main) Hauptbahnhof tief".into(), lat: 50.1072, lon: 8.6632 },
            ],
            features: vec![plat(-100.0), plat(0.0), plat(100.0)],
        };
        let stations = vec![
            st(1, "Frankfurt (Main) Hauptbahnhof", 50.1071, 8.6631, 3),
            st(2, "Frankfurt (Main) Hauptbahnhof tief", 50.1071, 8.6632, 1),
            st(3, "Irgendwo", 52.0, 10.0, 2),
        ];
        let ps = build(&stations, &osm);
        assert_eq!(ps[0].outcome, Outcome::Premise);
        assert_eq!(ps[1].outcome, Outcome::PartOf(1));
        assert_eq!(ps[2].outcome, Outcome::Outside);
        assert_eq!(ps[2].ring.r, RING_MIN_M);
        assert!(ps[0].ring.r >= RING_MIN_M && !ps[0].touch.is_empty());
        let local = Local::new(ps[0].station.lat, ps[0].station.lon);
        let outline: Vec<P> = ps[0].outline.iter().map(|q| local.xy(*q)).collect();
        assert!(contains(&outline, local.xy(l.ll((0.0, 0.0)))));
    }
}
