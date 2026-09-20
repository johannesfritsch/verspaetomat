//! The table as the bytes a phone will read (issue #39).
//!
//! Issue #37 put the stations in Postgres and stopped the coordinate going to Transitous. It did
//! not stop the coordinate going to *us*: docs/25 line 109 counted fourteen nearby calls in
//! fifty-nine minutes on one journey, against a documented budget of "a day crossing Germany:
//! under 10". This module renders the other half — the same table, built once on a laptop and
//! published as a static file. Reading it on the phone is the next step (#39, Dart half); the
//! native background scan is the one after that, and until it lands `Geofence.swift:1208` and
//! `GeofenceManager.kt:294` still ask the server.
//!
//! The layout is documented byte by byte in docs/45. The short version: a 32-byte header, then
//! `count` records of 20 bytes sorted by id, then a blob of UTF-8 names, all little-endian. A
//! nearby answer reads the first fourteen bytes of each record and never touches the blob, which
//! is the property the native layer needs: a scan in a background wake that allocates nothing.

use std::collections::HashMap;

use chrono::{DateTime, Utc};

use super::Index;

pub const MAGIC: [u8; 4] = *b"VSST";
/// Bumped only when an existing byte changes meaning. A field added to the end of a record bumps
/// [`RECORD_LEN`] instead and a format-1 reader keeps working — the same rule the wire has.
pub const FORMAT: u16 = 1;
pub const HEADER_LEN: u16 = 32;
pub const RECORD_LEN: u32 = 20;
/// Record byte 13, bit 0: `train::transitous::looks_like_station` of this station's name. Baked in
/// because `nearby_order` reads it to break a 300 m band tie, and the native scan must rank
/// without decoding a string.
pub const FLAG_LOOKS_LIKE_STATION: u8 = 1 << 0;
/// The name field is one byte. The longest name in the live table is 51 bytes.
pub const MAX_NAME_LEN: usize = 255;

/// What the table cannot say about itself: which import it is, and when that import finished.
/// Both come from `station_imports` rather than from the clock, so rendering the same table twice
/// produces the same bytes — otherwise every render would be a 280 KB commit in site/dist.
///
/// Neither field orders two extracts from *different* databases. `version` is a serial of its own
/// database (production stands at 1 where this laptop stands at 7) and `generated` is an accident
/// of when each one happened to run its import. A reader decides freshness by whether a download
/// validated, never by comparing these against a bundled copy — docs/45, "Drei Zahlen, die keine
/// Reihenfolge sind".
pub struct Meta {
    pub version: u32,
    pub generated: DateTime<Utc>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ExtractStation {
    pub id: u32,
    pub name: String,
    pub lat: f64,
    pub lon: f64,
    pub rank: u8,
    pub flags: u8,
}

/// A parsed extract. Carries `header_len` and `record_len` so a caller can tell a grown file from
/// a format-1 one.
#[derive(Debug, Clone)]
pub struct Parsed {
    pub format: u16,
    pub header_len: u16,
    pub record_len: u32,
    pub version: u32,
    pub generated: u32,
    pub crc32: u32,
    pub stations: Vec<ExtractStation>,
}

/// Render the whole live index. Refuses rather than writing something a reader would have to guess
/// about: every guard here is a thing that would otherwise be a silently wrong station on a phone.
///
/// Pure: it does not call `Utc::now()`, does not read the database and does not sort. An unsorted
/// index is a bug in [`super::load`], not something to paper over here.
pub fn render(index: &Index, meta: Meta) -> anyhow::Result<Vec<u8>> {
    let n = index.all.len();
    anyhow::ensure!(n > 0, "an extract of nothing is not an extract");
    let count = u32::try_from(n).map_err(|_| anyhow::anyhow!("{n} stations is more than the format's u32 count"))?;

    let mut recs: Vec<u8> = Vec::with_capacity(n * RECORD_LEN as usize);
    let mut blob: Vec<u8> = Vec::with_capacity(n * 20);
    let mut shared: HashMap<&str, u32> = HashMap::with_capacity(n);
    let mut last_id: i64 = -1;

    for s in &index.all {
        anyhow::ensure!(s.id > 0, "station id {} is not a u32 the format can carry", s.id);
        anyhow::ensure!(i64::from(s.id) > last_id, "the index is not sorted by id: {} came after {last_id}", s.id);
        last_id = i64::from(s.id);
        anyhow::ensure!(
            (-90.0..=90.0).contains(&s.lat) && (-180.0..=180.0).contains(&s.lon),
            "{} is at {}, {}, which is not on this planet",
            s.name,
            s.lat,
            s.lon
        );
        anyhow::ensure!((0..=255).contains(&s.rank), "{} has rank {}, which is not a byte", s.name, s.rank);

        let name = s.name.as_bytes();
        anyhow::ensure!(!name.is_empty(), "station {} has no name", s.id);
        anyhow::ensure!(
            name.len() <= MAX_NAME_LEN,
            "the name of station {} is {} bytes; the format stores at most {MAX_NAME_LEN}",
            s.id,
            name.len()
        );

        // Two records with the same name share one slice, first in record order wins, so the file
        // is a function of the table and nothing else.
        //
        // `.copied()` ends the borrow of `shared` before the match arms: `match shared.get(..) {
        // Some(&o) => .., None => { shared.insert(..) } }` is E0502 on edition 2021.
        let existing = shared.get(s.name.as_str()).copied();
        let off = match existing {
            Some(o) => o,
            None => {
                let o = u32::try_from(blob.len())?;
                blob.extend_from_slice(name);
                shared.insert(s.name.as_str(), o);
                o
            }
        };

        let flags = if crate::train::transitous::looks_like_station(&s.name) { FLAG_LOOKS_LIKE_STATION } else { 0 };
        recs.extend_from_slice(&(s.id as u32).to_le_bytes());
        recs.extend_from_slice(&((s.lat * 1_000_000.0).round() as i32).to_le_bytes());
        recs.extend_from_slice(&((s.lon * 1_000_000.0).round() as i32).to_le_bytes());
        recs.push(s.rank as u8);
        recs.push(flags);
        recs.push(name.len() as u8);
        recs.push(0); // reserved: a format-1 reader ignores it, so it can become a field later
        recs.extend_from_slice(&off.to_le_bytes());
    }

    let mut h = crc32fast::Hasher::new();
    h.update(&recs);
    h.update(&blob);
    let crc = h.finalize();

    let mut out = Vec::with_capacity(HEADER_LEN as usize + recs.len() + blob.len());
    out.extend_from_slice(&MAGIC);
    out.extend_from_slice(&FORMAT.to_le_bytes());
    out.extend_from_slice(&HEADER_LEN.to_le_bytes());
    out.extend_from_slice(&count.to_le_bytes());
    out.extend_from_slice(&RECORD_LEN.to_le_bytes());
    out.extend_from_slice(&u32::try_from(blob.len())?.to_le_bytes());
    out.extend_from_slice(&(meta.generated.timestamp().clamp(0, u32::MAX as i64) as u32).to_le_bytes());
    out.extend_from_slice(&meta.version.to_le_bytes());
    out.extend_from_slice(&crc.to_le_bytes());
    debug_assert_eq!(out.len(), HEADER_LEN as usize);
    out.extend_from_slice(&recs);
    out.extend_from_slice(&blob);
    Ok(out)
}

/// The reader the phone will have, in Rust, run on the laptop before a byte is written into the
/// working tree. The checks are docs/45 §"Was ein Leser prüft" in order; anything that fails
/// refuses the whole file, because there is no partial read.
pub fn parse(bytes: &[u8]) -> anyhow::Result<Parsed> {
    anyhow::ensure!(bytes.len() >= HEADER_LEN as usize, "{} bytes is shorter than the header", bytes.len());
    anyhow::ensure!(bytes[0..4] == MAGIC, "not a station extract: the magic is {:02x?}", &bytes[0..4]);
    let format = u16::from_le_bytes(bytes[4..6].try_into()?);
    anyhow::ensure!(format == FORMAT, "extract format {format}, this reader knows {FORMAT}");
    let header_len = u16::from_le_bytes(bytes[6..8].try_into()?);
    anyhow::ensure!(header_len >= HEADER_LEN, "header_len {header_len} is shorter than {HEADER_LEN}");
    let count = u32::from_le_bytes(bytes[8..12].try_into()?) as usize;
    anyhow::ensure!(count > 0, "an extract of nothing");
    let record_len = u32::from_le_bytes(bytes[12..16].try_into()?);
    anyhow::ensure!(record_len >= RECORD_LEN, "record_len {record_len} is shorter than {RECORD_LEN}");
    let blob_len = u32::from_le_bytes(bytes[16..20].try_into()?) as usize;
    let generated = u32::from_le_bytes(bytes[20..24].try_into()?);
    let version = u32::from_le_bytes(bytes[24..28].try_into()?);
    let crc32 = u32::from_le_bytes(bytes[28..32].try_into()?);

    let (hl, rl) = (header_len as usize, record_len as usize);
    let want = hl as u64 + rl as u64 * count as u64 + blob_len as u64;
    anyhow::ensure!(want == bytes.len() as u64, "the file says {want} bytes and is {}", bytes.len());

    // `header_len`, never a literal 32: a later format-1 file may carry a longer header, and a
    // reader that hardcoded the number would refuse it for being damaged.
    let mut h = crc32fast::Hasher::new();
    h.update(&bytes[hl..]);
    anyhow::ensure!(h.finalize() == crc32, "the checksum does not match: the file is damaged");

    let blob = &bytes[hl + rl * count..];
    let mut stations = Vec::with_capacity(count);
    for i in 0..count {
        let r = &bytes[hl + i * rl..][..RECORD_LEN as usize];
        let name_len = r[14] as usize;
        let name_off = u32::from_le_bytes(r[16..20].try_into()?) as usize;
        anyhow::ensure!(name_len > 0, "record {i} has no name");
        anyhow::ensure!(name_off + name_len <= blob.len(), "record {i} names bytes outside the blob");
        stations.push(ExtractStation {
            id: u32::from_le_bytes(r[0..4].try_into()?),
            lat: i32::from_le_bytes(r[4..8].try_into()?) as f64 / 1_000_000.0,
            lon: i32::from_le_bytes(r[8..12].try_into()?) as f64 / 1_000_000.0,
            rank: r[12],
            flags: r[13],
            name: std::str::from_utf8(&blob[name_off..name_off + name_len])?.to_string(),
        });
    }
    Ok(Parsed { format, header_len, record_len, version, generated, crc32, stations })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::stations::{parse_wire_id, Station};
    use crate::train::normalise_station_name;

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

    fn at(secs: i64) -> DateTime<Utc> {
        DateTime::from_timestamp(secs, 0).unwrap()
    }

    fn five() -> Index {
        index(vec![
            station(3, "Köln Hbf", 50.9430, 6.9586, 3),
            station(11, "Kißlegg Bahnhof", 47.7914, 9.8921, 1),
            station(12, "Wangen im Allgäu", 47.6817, 9.8331, 1),
            station(20, "Neustadt", 54.1080, 10.8160, 1),
            station(21, "Neustadt", 49.3500, 8.1400, 2),
        ])
    }

    #[test]
    fn an_extract_reads_back_as_the_stations_it_was_written_from() {
        let ix = five();
        let bytes = render(&ix, Meta { version: 12, generated: at(1_757_689_577) }).unwrap();

        // The header, field by field, so a change to the layout fails here and not on a phone.
        assert_eq!(&bytes[0..4], &MAGIC);
        assert_eq!(u16::from_le_bytes(bytes[4..6].try_into().unwrap()), FORMAT);
        assert_eq!(u16::from_le_bytes(bytes[6..8].try_into().unwrap()), HEADER_LEN);
        assert_eq!(u32::from_le_bytes(bytes[8..12].try_into().unwrap()), 5);
        assert_eq!(u32::from_le_bytes(bytes[12..16].try_into().unwrap()), RECORD_LEN);
        let blob_len = u32::from_le_bytes(bytes[16..20].try_into().unwrap()) as usize;
        assert_eq!(u32::from_le_bytes(bytes[20..24].try_into().unwrap()), 1_757_689_577);
        assert_eq!(u32::from_le_bytes(bytes[24..28].try_into().unwrap()), 12);

        // „Neustadt" is written once, not twice: the blob is the distinct names and nothing else.
        let distinct: usize = ["Köln Hbf", "Kißlegg Bahnhof", "Wangen im Allgäu", "Neustadt"].iter().map(|n| n.len()).sum();
        assert_eq!(blob_len, distinct, "the blob is not the four distinct names");
        assert_eq!(bytes.len(), HEADER_LEN as usize + 5 * RECORD_LEN as usize + blob_len);

        let read = parse(&bytes).unwrap();
        assert_eq!(read.format, FORMAT);
        assert_eq!(read.header_len, HEADER_LEN);
        assert_eq!(read.record_len, RECORD_LEN);
        assert_eq!(read.version, 12);
        assert_eq!(read.generated, 1_757_689_577);
        assert_eq!(read.stations.len(), 5);
        for (want, got) in ix.all.iter().zip(&read.stations) {
            assert_eq!(got.id, want.id as u32);
            assert_eq!(got.name, want.name);
            assert_eq!(got.rank, want.rank as u8);
            assert!((got.lat - want.lat).abs() < 5e-7, "{} moved in latitude", want.name);
            assert!((got.lon - want.lon).abs() < 5e-7, "{} moved in longitude", want.name);
            let looks = crate::train::transitous::looks_like_station(&want.name);
            assert_eq!(got.flags & FLAG_LOOKS_LIKE_STATION != 0, looks, "{} carries the wrong flag", want.name);
            assert_eq!(got.flags & !FLAG_LOOKS_LIKE_STATION, 0, "bits 1–7 are reserved and stay 0");
        }
        // The flag is not trivially constant: Kißlegg Bahnhof carries it, Wangen im Allgäu does not.
        assert_ne!(read.stations[1].flags, read.stations[2].flags);

        // Records ascend by id, which is what lets a reader binary-search without an index.
        assert!(read.stations.windows(2).all(|w| w[0].id < w[1].id), "the records do not ascend by id");

        // Pure: the same table and the same meta are the same bytes, or every render is a commit.
        assert_eq!(bytes, render(&ix, Meta { version: 12, generated: at(1_757_689_577) }).unwrap());

        // A damaged file is refused whole, not read in part.
        let mut flipped = bytes.clone();
        flipped[HEADER_LEN as usize + 4] ^= 0x01;
        assert!(parse(&flipped).is_err(), "a flipped byte parsed");
        assert!(parse(&bytes[..bytes.len() - 1]).is_err(), "a truncated file parsed");
    }

    #[test]
    fn a_name_longer_than_the_field_is_refused_rather_than_cut() {
        // 128 × „ä" is 256 bytes, one past what `name_len` can say.
        let ix = index(vec![station(1, &"ä".repeat(128), 50.0, 8.0, 3)]);
        let e = render(&ix, Meta { version: 1, generated: at(0) }).unwrap_err().to_string();
        assert!(e.contains("256 bytes"), "{e}");
    }

    #[test]
    fn an_extract_of_nothing_is_refused() {
        assert!(render(&Index::default(), Meta { version: 1, generated: at(0) }).is_err());
    }

    /// Deterministic, so a failure is reproducible and a passing run means the same thing twice.
    struct Xorshift(u64);

    impl Xorshift {
        fn next_u64(&mut self) -> u64 {
            let mut x = self.0;
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            self.0 = x;
            x
        }
        /// A float in [0, 1).
        fn unit(&mut self) -> f64 {
            (self.next_u64() >> 11) as f64 / (1u64 << 53) as f64
        }
        fn between(&mut self, lo: f64, hi: f64) -> f64 {
            lo + self.unit() * (hi - lo)
        }
        /// On the micro-degree grid, which is where the live table already is: *measured* on the
        /// 7,604 live rows, 0 carry more than six decimal places and the round trip moves nothing
        /// by more than 0.0 m. A scatter with seventeen significant digits would test the
        /// rounding rather than the format, and would flip a pair of stations that sit on the
        /// same 300 m band edge a few centimetres apart — see
        /// [`what_a_coordinate_loses_on_the_way_into_the_format`].
        fn grid(&mut self, lo: f64, hi: f64) -> f64 {
            (self.between(lo, hi) * 1_000_000.0).round() / 1_000_000.0
        }
    }

    /// What the format costs a coordinate, so the number is written down rather than assumed.
    ///
    /// A station already on the grid comes back bit for bit. A feed that one day ships more
    /// precision loses at most half a micro-degree — 5.6 cm in latitude, 3.5 cm in longitude at
    /// 51° N — against a 300 m ranking band. That is only ever visible as two stations swapping
    /// places when they sit within centimetres of the same band edge.
    #[test]
    fn what_a_coordinate_loses_on_the_way_into_the_format() {
        let mut rng = Xorshift(0x6772_6964);
        let (mut worst_on_grid, mut worst_off_grid) = (0.0_f64, 0.0_f64);
        for _ in 0..10_000 {
            let on = rng.grid(47.2, 55.1);
            let off = rng.between(47.2, 55.1);
            for (v, worst) in [(on, &mut worst_on_grid), (off, &mut worst_off_grid)] {
                let back = ((v * 1_000_000.0).round() as i32) as f64 / 1_000_000.0;
                // Metres of latitude per degree, near enough for a bound.
                let m = (back - v).abs() * 111_320.0;
                if m > *worst {
                    *worst = m;
                }
            }
        }
        assert_eq!(worst_on_grid, 0.0, "a coordinate already on the grid must survive untouched");
        assert!(worst_off_grid < 0.06, "the round trip moved a coordinate {worst_off_grid} m");
    }

    /// Great-circle distance in metres, R = 6 371 000 — the same formula as `train::haversine_m`,
    /// written out again because this scan is what the Dart, Swift and Kotlin readers will each
    /// be. Sharing it would prove the extract agrees with itself and nothing else.
    fn haversine(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
        let r = 6_371_000.0_f64;
        let (p1, p2) = (lat1.to_radians(), lat2.to_radians());
        let dp = (lat2 - lat1).to_radians();
        let dl = (lon2 - lon1).to_radians();
        let a = (dp / 2.0).sin().powi(2) + p1.cos() * p2.cos() * (dl / 2.0).sin().powi(2);
        2.0 * r * a.sqrt().atan2((1.0 - a).sqrt())
    }

    /// The reference scan a reader implements: nearest first for the cut, then the docs/23 ladder
    /// for the answer. Both sorts are stable, which is how `Index::nearby` breaks an exact tie by
    /// id — a reader that sorts unstably diverges on the first pair of stations at equal distance.
    fn nearby_over(stations: &[ExtractStation], lat: f64, lon: f64, limit: usize) -> (Vec<u32>, i64, bool) {
        let mut hits: Vec<(i64, &ExtractStation)> = stations
            .iter()
            .filter_map(|s| {
                let d = haversine(lat, lon, s.lat, s.lon);
                (d <= 50_000.0).then(|| (d.round() as i64, s))
            })
            .collect();
        hits.sort_by_key(|(d, _)| *d);
        hits.truncate(limit);
        let searched_radius_m = hits.last().map(|(d, _)| *d).unwrap_or(0);
        hits.sort_by_key(|(d, s)| {
            (*d / 300, -(s.rank as i32), i32::from(s.flags & FLAG_LOOKS_LIKE_STATION == 0), *d)
        });
        (hits.iter().map(|(_, s)| s.id).collect(), searched_radius_m, !hits.is_empty())
    }

    /// The whole point: a reader that has only the file gives the answer the server gives.
    ///
    /// The stations sit on the micro-degree grid, which is where the live table sits — *measured*
    /// on the 7,604 live rows: 0 carry more than six decimal places. So the two sides see the same
    /// coordinates and the assertion is exact equality, not a tolerance.
    /// Where two answers differ, with enough detail to decide which side is wrong.
    #[derive(Debug)]
    struct Disagreement {
        probe: String,
        limit: usize,
        want: Vec<u32>,
        got: Vec<u32>,
        cause: String,
    }

    fn index_station(ix: &Index, id: u32) -> Option<&Station> {
        ix.by_id.get(&(id as i32)).map(|&i| &ix.all[i])
    }

    fn extract_station(ex: &[ExtractStation], id: u32) -> Option<&ExtractStation> {
        ex.iter().find(|s| s.id == id)
    }

    /// Everything that decides where a station lands in a nearby list, from both sides: the
    /// distance each one computes (the index from the f64 column, the extract from the
    /// micro-degree integer), the rank, and the name flag. With all six numbers in the message a
    /// human can tell a coordinate problem from a rank problem without re-running anything.
    struct Facts {
        name: String,
        index_m: i64,
        extract_m: i64,
        index_rank: i16,
        extract_rank: u8,
        index_named: bool,
        extract_named: bool,
    }

    impl std::fmt::Display for Facts {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            write!(
                f,
                "\"{}\" index {} m/rank {}/named {} · extract {} m/rank {}/named {}",
                self.name, self.index_m, self.index_rank, self.index_named, self.extract_m, self.extract_rank, self.extract_named
            )
        }
    }

    fn facts(ix: &Index, ex: &[ExtractStation], id: u32, lat: f64, lon: f64) -> Facts {
        let a = index_station(ix, id);
        let b = extract_station(ex, id);
        Facts {
            name: a.map(|s| s.name.clone()).or_else(|| b.map(|s| s.name.clone())).unwrap_or_else(|| "?".into()),
            index_m: a.map(|s| haversine(lat, lon, s.lat, s.lon).round() as i64).unwrap_or(-1),
            extract_m: b.map(|s| haversine(lat, lon, s.lat, s.lon).round() as i64).unwrap_or(-1),
            index_rank: a.map(|s| s.rank).unwrap_or(-1),
            extract_rank: b.map(|s| s.rank).unwrap_or(0),
            index_named: a.map(|s| crate::train::transitous::looks_like_station(&s.name)).unwrap_or(false),
            extract_named: b.map(|s| s.flags & FLAG_LOOKS_LIKE_STATION != 0).unwrap_or(false),
        }
    }

    /// Work out *why* two lists differ rather than guessing. Three causes are possible in
    /// principle: the micro-degree rounding moved a station across a ranking boundary, two
    /// stations are an exact tie whose order is decided by input order, or the same place is in
    /// the table twice under one name. Anything else is a real defect and says so.
    fn classify(ix: &Index, ex: &[ExtractStation], lat: f64, lon: f64, want: &[u32], got: &[u32]) -> String {
        use std::collections::BTreeSet;
        let w: BTreeSet<u32> = want.iter().copied().collect();
        let g: BTreeSet<u32> = got.iter().copied().collect();
        if w == g {
            let at = want.iter().zip(got.iter()).position(|(a, b)| a != b).unwrap_or(0);
            let (a, b) = (want[at], got[at]);
            let (fa, fb) = (facts(ix, ex, a, lat, lon), facts(ix, ex, b, lat, lon));
            let moved = (fa.index_m - fa.extract_m).abs().max((fb.index_m - fb.extract_m).abs());
            // The decisive discrimination: if neither distance moved, the coordinates are innocent
            // and the difference is in the rank or the name flag — a defect, not a rounding cost.
            // The micro-degree grid can shift a distance by at most ~0.06 m (see
            // `what_a_coordinate_loses_on_the_way_into_the_format`), so anything past a metre is
            // not rounding — it is a coordinate the extract got wrong, and saying "rounding" would
            // send the next reader looking in the wrong place.
            let blame = if moved > 1 {
                format!(
                    "the two sides put this station {moved} m apart, far past the ~0.06 m the \
                     micro-degree grid can cost: the extract's coordinate is wrong"
                )
            } else if moved > 0 {
                format!("the micro-degree rounding moved a distance by {moved} m: a band edge, the one cost the format has")
            } else if fa.index_rank as u8 != fa.extract_rank || fb.index_rank as u8 != fb.extract_rank {
                "the distances are identical and a rank differs: the extract carries the wrong rank".into()
            } else if fa.index_named != fa.extract_named || fb.index_named != fb.extract_named {
                "the distances are identical and the name flag differs: bit 0 is wrong".into()
            } else if fa.name == fb.name {
                "the distances are identical and so are the names: one place in the table twice".into()
            } else {
                "the distances, ranks and flags all agree: the two sort steps disagree, which is a real defect".into()
            };
            format!("same stations, different order at position {at}: index {a} {fa} before {b} {fb}; {blame}")
        } else {
            let only_index: Vec<u32> = w.difference(&g).copied().collect();
            let only_extract: Vec<u32> = g.difference(&w).copied().collect();
            let mut notes = Vec::new();
            for id in &only_index {
                notes.push(format!("only the index has {id} {}", facts(ix, ex, *id, lat, lon)));
            }
            for id in &only_extract {
                notes.push(format!("only the extract has {id} {}", facts(ix, ex, *id, lat, lon)));
            }
            let names = |ids: &[u32]| -> Vec<String> { ids.iter().map(|i| facts(ix, ex, *i, lat, lon).name).collect() };
            if !only_index.is_empty() && names(&only_index) == names(&only_extract) {
                notes.push("the differing ids carry the same names: one place in the table twice".into());
            }
            format!("different stations at the truncation boundary. {}", notes.join("; "))
        }
    }

    /// `Index::search` as a reader holding only the file has to implement it: both folds
    /// recomputed from the display name, the ordering from `(class, -rank, flags bit 0, name)`.
    /// The folds are deliberately not in the file (docs/45) — this is the code that proves the
    /// file still carries enough to reproduce the server's list.
    fn search_over(stations: &[ExtractStation], q: &str, limit: usize) -> Vec<u32> {
        let plain = q.trim().to_lowercase();
        let normal = normalise_station_name(q);
        if plain.is_empty() {
            return Vec::new();
        }
        let mut hits: Vec<(u8, i16, u8, &ExtractStation)> = stations
            .iter()
            .filter_map(|s| {
                let s_plain = s.name.to_lowercase();
                let s_normal = normalise_station_name(&s.name);
                let starts = s_plain.starts_with(&plain) || (!normal.is_empty() && s_normal.starts_with(&normal));
                let holds = s_plain.contains(&plain) || (!normal.is_empty() && s_normal.contains(&normal));
                let class = if starts {
                    0
                } else if holds {
                    1
                } else {
                    return None;
                };
                let named = u8::from(s.flags & FLAG_LOOKS_LIKE_STATION == 0);
                Some((class, -(s.rank as i16), named, s))
            })
            .collect();
        hits.sort_by(|a, b| (a.0, a.1, a.2, &a.3.name).cmp(&(b.0, b.1, b.2, &b.3.name)));
        hits.truncate(limit);
        hits.iter().map(|(_, _, _, s)| s.id).collect()
    }

    /// The whole live table, at scale: does a reader holding only the file answer what the server
    /// answers? Not five probe points — every station's own doorstep, a grid over the country, and
    /// a few hundred queries drawn from real names.
    ///
    /// Needs Postgres (`DATABASE_URL`, default `postgres://localhost/verspaetomat`). Run it with
    ///
    /// ```text
    /// cargo test --lib the_extract_agrees_with_the_whole_table -- --ignored --nocapture
    /// ```
    ///
    /// and add `--release` if you are impatient: it is ~30,000 full scans of the table twice over.
    /// Seeds are fixed (`0x5653_5354_4e45_4152` for the jitter, `0x5653_5354_5345_4152` for the
    /// query sample), so two runs compare the same points and a failure is reproducible.
    #[tokio::test]
    #[ignore]
    async fn the_extract_agrees_with_the_whole_table() {
        // The pool directly rather than `db::connect`: that one lives in the binary crate and runs
        // migrations, and this module is the library half.
        let url = std::env::var("DATABASE_URL").unwrap_or_else(|_| "postgres://localhost/verspaetomat".into());
        let pool = sqlx::postgres::PgPoolOptions::new()
            .max_connections(4)
            .connect(&url)
            .await
            .expect("connect to postgres");
        let ix = crate::stations::load(&pool).await.expect("load the table");
        let bytes = render(&ix, Meta { version: 1, generated: at(0) }).expect("render");
        let read = parse(&bytes).expect("parse");
        let ex = &read.stations[..];
        eprintln!("table: {} stations, extract: {} bytes, {} records", ix.all.len(), bytes.len(), ex.len());

        // 1. Every station's own coordinate, jittered: a passenger standing near a station.
        //    Uniform bearing, uniform distance in [0, 1500] m.
        let mut rng = Xorshift(0x5653_5354_4e45_4152);
        let mut probes: Vec<(String, f64, f64)> = Vec::with_capacity(ix.all.len());
        for s in &ix.all {
            let bearing = rng.between(0.0, std::f64::consts::TAU);
            let d = rng.between(0.0, 1500.0);
            let dlat = d * bearing.cos() / 111_320.0;
            let dlon = d * bearing.sin() / (111_320.0 * s.lat.to_radians().cos());
            probes.push((format!("near {} ({})", s.name, s.id), s.lat + dlat, s.lon + dlon));
        }
        let jittered = probes.len();

        // 2. A uniform grid over Germany's bounding box at 0.1°, ~11 km apart. Not
        //    population-weighted: there is no population raster in this repo and downloading one
        //    for a test would be a dependency nobody asked for. The jittered sample above is the
        //    population-weighted one in the way that matters — it is weighted by where stations
        //    are, which is where passengers stand.
        for i in 0..=79 {
            for j in 0..=93 {
                let (lat, lon) = (47.2 + i as f64 * 0.1, 5.8 + j as f64 * 0.1);
                probes.push((format!("grid {lat:.1},{lon:.1}"), lat, lon));
            }
        }
        eprintln!("probes: {jittered} jittered + {} grid = {}", probes.len() - jittered, probes.len());

        let mut bad: Vec<Disagreement> = Vec::new();
        for limit in [3usize, 25] {
            let (mut top1, mut lists, mut radius, mut complete, mut worst) = (0usize, 0usize, 0usize, 0usize, 0i64);
            for (label, lat, lon) in &probes {
                let (lat, lon) = (*lat, *lon);
                let want = ix.nearby(lat, lon, limit);
                let want_ids: Vec<u32> =
                    want.stations.iter().filter_map(|s| parse_wire_id(&s.id)).map(|n| n as u32).collect();
                let (got_ids, got_radius, got_complete) = nearby_over(ex, lat, lon, limit);

                if want_ids.first() != got_ids.first() {
                    top1 += 1;
                }
                if want_ids != got_ids {
                    lists += 1;
                    bad.push(Disagreement {
                        probe: format!("{label} at {lat:.6},{lon:.6}"),
                        limit,
                        want: want_ids.clone(),
                        got: got_ids.clone(),
                        cause: classify(&ix, ex, lat, lon, &want_ids, &got_ids),
                    });
                }
                let d = (want.searched_radius_m - got_radius).abs();
                if d > 0 {
                    radius += 1;
                    worst = worst.max(d);
                }
                if want.complete != got_complete {
                    complete += 1;
                }
            }
            eprintln!(
                "nearby, limit {limit}: {} probes · top-1 differences {top1} · list differences {lists} \
                 · radius differences {radius} (worst {worst} m) · complete differences {complete}",
                probes.len()
            );
        }

        // 3. Search, from real names: the full name, its first word, half-typed prefixes (the
        //    „Berlin Haupt" class that broke on the server earlier), and case variants.
        let mut qrng = Xorshift(0x5653_5354_5345_4152);
        let mut queries: Vec<String> = Vec::new();
        for _ in 0..300 {
            let s = &ix.all[(qrng.next_u64() % ix.all.len() as u64) as usize];
            let n = &s.name;
            queries.push(n.clone());
            queries.push(n.to_lowercase());
            queries.push(n.to_uppercase());
            if let Some(w) = n.split_whitespace().next() {
                queries.push(w.to_string());
            }
            // Half a word, on a character boundary, not a byte one.
            let chars: Vec<char> = n.chars().collect();
            for take in [3usize, 6, 10] {
                if chars.len() > take {
                    queries.push(chars[..take].iter().collect());
                }
            }
            // The „Berlin Haupt" class: a prefix that stops inside a word `normalise_station_name`
            // rewrites whole.
            if let Some(at) = n.find("Hauptbahnhof") {
                queries.push(n[..at + "Haupt".len()].to_string());
            }
        }
        queries.sort();
        queries.dedup();
        let mut search_bad = 0usize;
        for q in &queries {
            let want: Vec<u32> =
                ix.search(q, 12).iter().filter_map(|s| parse_wire_id(&s.id)).map(|n| n as u32).collect();
            let got = search_over(ex, q, 12);
            if want != got {
                search_bad += 1;
                bad.push(Disagreement {
                    probe: format!("search {q:?}"),
                    limit: 12,
                    want: want.clone(),
                    got: got.clone(),
                    cause: {
                        use std::collections::BTreeSet;
                        let w: BTreeSet<u32> = want.iter().copied().collect();
                        let g: BTreeSet<u32> = got.iter().copied().collect();
                        if w == g {
                            "same stations, different order: the two sort keys disagree".into()
                        } else {
                            format!(
                                "different stations: only the index has {:?}, only the extract has {:?}",
                                w.difference(&g).collect::<Vec<_>>(),
                                g.difference(&w).collect::<Vec<_>>()
                            )
                        }
                    },
                });
            }
        }
        eprintln!("search: {} distinct queries · list differences {search_bad}", queries.len());

        for d in bad.iter().take(200) {
            eprintln!(
                "DISAGREE {} (limit {})\n  index:   {:?}\n  extract: {:?}\n  cause:   {}",
                d.probe, d.limit, d.want, d.got, d.cause
            );
        }
        if bad.len() > 200 {
            eprintln!("... and {} more", bad.len() - 200);
        }
        assert!(bad.is_empty(), "{} disagreements between the extract and the table", bad.len());
    }

    #[test]
    fn the_extract_answers_nearby_the_way_the_index_does() {
        let mut rng = Xorshift(0x5333_5453_5654); // "VSST" with a tail, so the seed says where it came from
        let mut stations = Vec::with_capacity(2_000);
        for i in 1..=2_000i32 {
            // Names that make `looks_like_station` a live tiebreak rather than a constant.
            let name = match i % 3 {
                0 => format!("Ort {i} Bahnhof"),
                1 => format!("Ort {i} Hbf"),
                _ => format!("Ort {i}, Schulstraße"),
            };
            let lat = rng.grid(47.2, 55.1);
            let lon = rng.grid(5.8, 15.1);
            stations.push(station(i, &name, lat, lon, (i % 3) as i16 + 1));
        }
        let ix = index(stations);
        let bytes = render(&ix, Meta { version: 7, generated: at(1_757_689_577) }).unwrap();
        let read = parse(&bytes).unwrap();

        for limit in [3usize, 25] {
            for _ in 0..500 {
                let (lat, lon) = (rng.between(47.0, 55.3), rng.between(5.5, 15.4));
                let want = ix.nearby(lat, lon, limit);
                let want_ids: Vec<u32> =
                    want.stations.iter().filter_map(|s| parse_wire_id(&s.id)).map(|n| n as u32).collect();
                let (got_ids, got_radius, got_complete) = nearby_over(&read.stations, lat, lon, limit);
                assert_eq!(
                    want_ids, got_ids,
                    "at {lat}, {lon} with limit {limit} the extract and the index disagree about which stations are near"
                );
                assert_eq!(want.complete, got_complete, "at {lat}, {lon} the two disagree about `complete`");
                assert!(
                    (want.searched_radius_m - got_radius).abs() <= 2,
                    "at {lat}, {lon} the searched radius is {} against {got_radius}",
                    want.searched_radius_m
                );
            }
        }
    }
}
