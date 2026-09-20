import CoreLocation
import Foundation

// The station table as bytes on disk, read in a background wake-up (issue #40).
//
// Until this file existed, `refreshNearest` answered „welcher Bahnhof ist hier?" with a GET to
// `/v1/stations/nearby` — a position leaving a phone whose owner is not using it, fourteen times
// in fifty-nine minutes on the journey docs/25 measured. The same table now ships as a file
// (docs/45) and the answer is a file read and a scan.
//
// **The answer has to equal the server's.** Three implementations now compute it: Rust
// (`backend/src/stations/mod.rs` `Index::nearby`, `backend/src/stations/extract.rs`), Dart
// (`app/lib/stations/station_index.dart`, `station_extract.dart`) and this one. Every constant,
// every comparison and every rounding step below names the line it mirrors, because a phone that
// ranks stations slightly differently from the server does not crash — it nudges at the wrong
// platform, on somebody else's phone, days later.

/// Where the two copies of the extract live.
///
/// Dart owns both files; nothing here ever writes in this directory.
enum StationPaths {
  /// `<Application Support>/stations/`, the directory `station_store.dart` creates.
  ///
  /// The same call `path_provider_foundation` makes for `getApplicationSupportDirectory()`:
  /// `NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)
  /// .first`, with no bundle-id subdirectory on iOS — its `PathProviderPlugin.swift` appends one
  /// only inside `#if os(macOS)`. Using the identical call removes the question of whether the
  /// two sides mean the same directory.
  ///
  /// No App Group and none is needed: region monitoring wakes the app's own process, and
  /// `Runner.entitlements` holds only `aps-environment`.
  static var stationsDirectory: URL? {
    guard
      let base = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first
    else { return nil }
    return URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent("stations", isDirectory: true)
  }

  /// The copy the phone downloaded (`station_store.dart`, `fileName`).
  static let downloadedName = "stations.vst"

  /// The copy of the bundled asset Dart mirrors for us (`station_store.dart`, `bundledName`).
  ///
  /// Deliberately not the same file as the download: that name means „die Kopie, die wir
  /// heruntergeladen haben", and only its serial may be compared with the website's pointer.
  static let bundledName = "bundled.vst"
}

/// CRC-32/ISO-HDLC: reflected polynomial `0xEDB88320`, init and final XOR `0xFFFFFFFF`.
///
/// The ordinary zlib/PNG CRC — the number `crc32fast` produces on the server
/// (`extract.rs`, `render`/`parse`), `crc32Of` produces in Dart (`station_extract.dart`) and
/// `java.util.zip.CRC32` produces on Android.
enum CRC32 {
  private static let table: [UInt32] = {
    var t = [UInt32](repeating: 0, count: 256)
    for n in 0..<256 {
      var c = UInt32(n)
      for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
      t[n] = c
    }
    return t
  }()

  /// Over `p[from..<p.count]`. Measured over the live extract's 280,212 checked bytes: 0.9 ms at
  /// `-O`, which is why it runs on every open and nothing is cached.
  static func over(_ p: UnsafeRawBufferPointer, from: Int) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    table.withUnsafeBufferPointer { t in
      var i = from
      while i < p.count {
        crc = t[Int((crc ^ UInt32(p[i])) & 0xFF)] ^ (crc >> 8)
        i += 1
      }
    }
    return crc ^ 0xFFFF_FFFF
  }
}

/// One `.vst` file, validated whole.
///
/// The layout is the contract with `extract.rs` and `station_extract.dart`, written out in
/// docs/45. A 32-byte header, then `count` records of `record_len` bytes sorted ascending by id,
/// then a blob of UTF-8 names. All integers little-endian, always, never the host's — which is
/// why every read below goes through [u16le]/[u32le] rather than through a typed load.
struct StationExtract {

  /// `"VSST"`, the four bytes a station extract starts with (`extract.rs`, `MAGIC`).
  static let magic: [UInt8] = [0x56, 0x53, 0x53, 0x54]

  /// The only format this reader knows (`extract.rs`, `FORMAT`). A file that says anything else
  /// is refused whole: the extract in hand is better than a file whose bytes mean something we
  /// can only guess at.
  static let supportedFormat: UInt16 = 1

  /// The header this reader needs (`extract.rs`, `HEADER_LEN`). A longer one is fine — the bytes
  /// `[minHeaderLen, headerLen)` are a future field and are skipped, which is how the format
  /// grows without breaking a phone already in the field.
  static let minHeaderLen = 32

  /// The bytes of a record this reader reads (`extract.rs`, `RECORD_LEN`). A longer record is
  /// fine and is strided over.
  static let minRecordLen = 20

  /// Record byte 13, bit 0 (`extract.rs`, `FLAG_LOOKS_LIKE_STATION`): `looks_like_station` of
  /// this station's name, decided at import time. Never re-derived from the name here — that is
  /// the whole point of baking it in.
  static let flagLooksLikeStation: UInt8 = 1 << 0

  /// Every way a file can fail to be an extract, one case per check, in the order the checks run.
  enum Failure: Error, Equatable {
    case tooShort(Int)
    case magic
    case format(UInt16)
    case headerLen(Int)
    case emptyCount
    case recordLen(UInt32)
    case length(want: UInt64, is: Int)
    case checksum
    case name(record: Int)
  }

  let data: Data
  let headerLen: Int
  let recordLen: Int
  let count: Int
  let blobLen: Int
  /// `headerLen + recordLen * count`: where the name blob starts.
  let blobAt: Int
  let format: UInt16
  /// Unix seconds UTC of the import this extract was cut from.
  let generated: UInt32
  /// The id of the `station_imports` row. It means something only inside its own database —
  /// production stands at 1 where a laptop stands at 7 — so it never orders two extracts
  /// (docs/45, „Drei Zahlen, die keine Reihenfolge sind").
  let tableVersion: UInt32
  let crc32: UInt32

  /// Read and validate a whole file.
  ///
  /// A plain read rather than `.mappedIfSafe`: the CRC pass touches every one of the 280 KB
  /// anyway, so a mapping would be fully faulted in before the first record is read and buys
  /// 0.02 ms of a 30-second wake budget. What it would cost is a `SIGBUS` if the file were ever
  /// truncated under the mapping — an uncatchable crash in a background wake, which is the one
  /// failure this module can least afford.
  static func open(_ url: URL) throws -> StationExtract {
    try StationExtract(data: try Data(contentsOf: url))
  }

  /// The checks run in the order `extract.rs`'s `parse` and `station_extract.dart`'s `decode` run
  /// them: magic → format → header_len → **count** → record_len → total length → CRC → per-record
  /// names.
  ///
  /// Both of those check `count` before `record_len`; only docs/45's prose list has them the other
  /// way round. It never changes accept/reject, but a file that is bad in both ways would be
  /// reported under a different `Failure` here than on the other two, and the refusal tests assert
  /// a specific case.
  init(data: Data) throws {
    self.data = data
    let n = data.count
    guard n >= Self.minHeaderLen else { throw Failure.tooShort(n) }

    // The header, read once. Everything after this is arithmetic.
    let head: (UInt16, UInt16, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32) = try data.withUnsafeBytes { raw in
      for i in 0..<4 where raw[i] != Self.magic[i] { throw Failure.magic }
      return (
        Self.u16le(raw, 4),   // format
        Self.u16le(raw, 6),   // header_len
        Self.u32le(raw, 8),   // count
        Self.u32le(raw, 12),  // record_len
        Self.u32le(raw, 16),  // blob_len
        Self.u32le(raw, 20),  // generated
        Self.u32le(raw, 24),  // version
        Self.u32le(raw, 28)   // crc32
      )
    }
    let (format, hl16, count32, rl32, blob32, gen, ver, crc) = head

    guard format == Self.supportedFormat else { throw Failure.format(format) }
    guard Int(hl16) >= Self.minHeaderLen else { throw Failure.headerLen(Int(hl16)) }
    guard count32 >= 1 else { throw Failure.emptyCount }
    guard rl32 >= UInt32(Self.minRecordLen) else { throw Failure.recordLen(rl32) }

    // As UInt64 and with the overflow reported rather than trapped: `record_len` and `count` are
    // both u32 on the wire, and a hostile file can make their product overflow a 64-bit Int.
    let (records, overflow) = UInt64(rl32).multipliedReportingOverflow(by: UInt64(count32))
    guard !overflow else { throw Failure.length(want: .max, is: n) }
    let want = UInt64(hl16) &+ records &+ UInt64(blob32)
    guard want == UInt64(n) else { throw Failure.length(want: want, is: n) }

    self.format = format
    self.headerLen = Int(hl16)
    self.recordLen = Int(rl32)
    self.count = Int(count32)
    self.blobLen = Int(blob32)
    self.blobAt = Int(hl16) + Int(rl32) * Int(count32)
    self.generated = gen
    self.tableVersion = ver
    self.crc32 = crc

    // From `headerLen`, never from a literal 32: a later format-1 file may carry a longer header,
    // and a reader that hardcoded the number would refuse it for being damaged.
    let actual = data.withUnsafeBytes { CRC32.over($0, from: self.headerLen) }
    guard actual == crc else { throw Failure.checksum }

    // Every record, not only the ones an answer returns. Rust and Dart check them all, and a
    // reader that checked fewer would accept a file the other two refuse — one phone, two
    // answers. Measured: the whole validated open is under a millisecond.
    try data.withUnsafeBytes { raw in
      for i in 0..<self.count {
        let at = self.headerLen + i * self.recordLen
        let nameLen = Int(raw[at + 14])
        let nameOff = Int(Self.u32le(raw, at + 16))
        guard nameLen >= 1, nameOff + nameLen <= self.blobLen else { throw Failure.name(record: i) }
      }
    }
  }

  // MARK: - Record accessors
  //
  // Record layout, `base = headerLen + i * recordLen` (`extract.rs`, `render`):
  // `id` u32 at +0, `lat_e6` i32 at +4, `lon_e6` i32 at +8, `rank` u8 at +12, `flags` u8 at +13,
  // `name_len` u8 at +14, `reserved` u8 at +15, `name_off` u32 at +16.
  //
  // Byte 15 is ignored and never checked for zero: that is where the next field goes, and a
  // reader that asserts it is 0 refuses the first grown file. `station_extract.dart` says the same.

  private func base(_ i: Int) -> Int { headerLen + i * recordLen }

  func id(at i: Int) -> UInt32 { data.withUnsafeBytes { Self.u32le($0, base(i)) } }
  func lat(at i: Int) -> Double { Double(data.withUnsafeBytes { Self.i32le($0, base(i) + 4) }) / 1_000_000.0 }
  func lon(at i: Int) -> Double { Double(data.withUnsafeBytes { Self.i32le($0, base(i) + 8) }) / 1_000_000.0 }
  func rank(at i: Int) -> UInt8 { data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in raw[base(i) + 12] } }
  func flags(at i: Int) -> UInt8 { data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in raw[base(i) + 13] } }

  /// `flags` bit 0, as the import decided it — never `looks_like_station` of the name.
  ///
  /// 2,732 of the live table's 7,604 records carry it. Re-deriving it here would mean porting
  /// `train::transitous::looks_like_station` into a third language and keeping it in step; the
  /// byte exists so the ranking never has to decode a string in a background wake.
  func looksLikeStation(at i: Int) -> Bool { flags(at: i) & Self.flagLooksLikeStation != 0 }

  /// The display name out of the blob.
  ///
  /// Read through `withUnsafeBytes` rather than through `data[a..<b]`. `Data`'s integer subscript
  /// is **absolute, not zero-based**, so `data[blobAt + off]` is correct only while `data` came
  /// straight from `Data(contentsOf:)`; hand this struct a `Data` slice and the same expression
  /// would silently read the wrong bytes or trap. `withUnsafeBytes` is zero-based over the slice
  /// itself, so every offset in this file means the same thing either way.
  func name(at i: Int) -> String {
    let at = base(i)
    return data.withUnsafeBytes { raw -> String in
      let len = Int(raw[at + 14])
      let off = Int(Self.u32le(raw, at + 16))
      return String(decoding: UnsafeRawBufferPointer(rebasing: raw[(blobAt + off)..<(blobAt + off + len)]), as: UTF8.self)
    }
  }

  /// The record index of an id, or nil. Records are strictly ascending by id (`extract.rs`'s
  /// `render` refuses an unsorted index), so this is a binary search.
  func index(ofId wanted: UInt32) -> Int? {
    var lo = 0, hi = count - 1
    while lo <= hi {
      let mid = (lo + hi) / 2
      let v = id(at: mid)
      if v == wanted { return mid }
      if v < wanted { lo = mid + 1 } else { hi = mid - 1 }
    }
    return nil
  }

  // MARK: - Little-endian reads
  //
  // Assembled byte by byte rather than with `loadUnaligned`, which is iOS 16 and this app deploys
  // to iOS 15. Being explicit costs nothing measurable and says the byte order out loud.

  @inline(__always) static func u16le(_ p: UnsafeRawBufferPointer, _ at: Int) -> UInt16 {
    UInt16(p[at]) | (UInt16(p[at + 1]) << 8)
  }

  @inline(__always) static func u32le(_ p: UnsafeRawBufferPointer, _ at: Int) -> UInt32 {
    UInt32(p[at]) | (UInt32(p[at + 1]) << 8) | (UInt32(p[at + 2]) << 16) | (UInt32(p[at + 3]) << 24)
  }

  @inline(__always) static func i32le(_ p: UnsafeRawBufferPointer, _ at: Int) -> Int32 {
    Int32(bitPattern: u32le(p, at))
  }
}

/// One station the scan kept: its record index and its **rounded** distance in metres.
struct NearbyHit: Equatable {
  let index: Int
  let distanceM: Int
}

extension GeofenceRules {
  /// `stations::NEARBY_MAX_M` (backend/src/stations/mod.rs). Beyond this the answer is empty
  /// rather than a station in the next Bundesland.
  static let nearbyMaxM: Double = 50_000

  /// `train::transitous::RANK_BAND_M` (backend/src/train/transitous.rs), which `nearby_order`
  /// divides the rounded distance by. Two stations inside one band are ranked by what kind of
  /// station they are, not by which is nearer.
  static let rankBandM = 300

  /// `train::haversine_m` (backend/src/train/mod.rs), ported line for line. R = 6_371_000,
  /// `atan2(sqrt(a), sqrt(1-a))`.
  ///
  /// **Never `CLLocation.distance(from:)`.** That is a geodesic on an ellipsoid and this is a
  /// sphere; over the live table they differ by up to about 0.5 %. Measured over the whole
  /// extract, swapping one for the other changes the returned list on hundreds of probes and
  /// `search_radius_m` by as much as two kilometres — and `search_radius_m` goes straight into
  /// `umbrellaRadius`, which is issue #31's mechanism.
  ///
  /// Degrees are multiplied by a precomputed constant, exactly as Rust's `f64::to_radians` and
  /// Dart's `_degToRad` do: `x * (pi / 180)` and `x * pi / 180` are not the same double.
  static func haversineM(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    let r = 6_371_000.0
    let p1 = lat1 * degToRad
    let p2 = lat2 * degToRad
    let dp = (lat2 - lat1) * degToRad
    let dl = (lon2 - lon1) * degToRad
    let sdp = sin(dp / 2.0)
    let sdl = sin(dl / 2.0)
    // Grouped as the Rust groups it: `p1.cos() * p2.cos() * (dl/2).sin().powi(2)` multiplies the
    // squared sine as one term. Dart writes `cos(p1) * cos(p2) * sdl * sdl`, which associates
    // left and can land an ulp away. Measured over every probe in the table that ulp never
    // survives the round to whole metres, but the server is the authority and this follows it.
    let a = sdp * sdp + cos(p1) * cos(p2) * (sdl * sdl)
    return 2.0 * r * atan2(a.squareRoot(), (1.0 - a).squareRoot())
  }

  static let degToRad = Double.pi / 180.0

  /// The same `NearbyAnswer` the server produced, out of the file.
  ///
  /// Including the re-sort by distance that `parseNearby` applies to the server's ranked list, so
  /// the three callers of `refreshNearest` see exactly what they see today: `regionSet` takes the
  /// first N of `stations` and `umbrellaRadius` takes a `.min()` over them; neither has ever seen
  /// `nearby_order`. One improvement over `parseNearby`: equal distances fall back to the record
  /// index instead of whatever Swift's unstable `sorted` happens to leave.
  ///
  /// The wire id is `"vs:\(id)"` (`stations::wire_id`, `station_rules.dart`'s `wireStationId`).
  /// The region identifier, the ignore key and the nudge payload all key on that string, so it is
  /// not cosmetic.
  static func nearbyAnswer(from t: StationExtract, lat: Double, lon: Double, limit: Int) -> NearbyAnswer {
    let scan = t.nearby(lat: lat, lon: lon, limit: limit)
    let byDistance = scan.hits.sorted {
      $0.distanceM != $1.distanceM ? $0.distanceM < $1.distanceM : $0.index < $1.index
    }
    return NearbyAnswer(
      stations: byDistance.map {
        GeofenceStation(
          id: "vs:\(t.id(at: $0.index))",
          name: t.name(at: $0.index),
          lat: t.lat(at: $0.index),
          lon: t.lon(at: $0.index))
      },
      searchedRadius: Double(scan.searchedRadiusM),
      complete: scan.complete)
  }
}

extension StationExtract {
  /// `stations::Index::nearby` (backend/src/stations/mod.rs) over the file. The reference readers
  /// are `extract.rs`'s `nearby_over` and `StationIndex.nearby`
  /// (app/lib/stations/station_index.dart).
  ///
  /// Returns the hits in **`nearby_order`** — the order the server puts on the wire — together
  /// with `searched_radius_m` and `complete`.
  ///
  /// Nearest first for the cut, best-ranked first for the answer: truncating after the rank sort
  /// could drop a nearer station in favour of a better one further out, and then the first station
  /// the phone did *not* register is no longer the nearest one it did not register — which is the
  /// number `umbrellaRadius` sizes from.
  ///
  /// **Where the three implementations would diverge if somebody got a step wrong:**
  ///
  /// 1. *The metric.* `CLLocation.distance(from:)` instead of this haversine: a different
  ///    `search_radius_m` on most probes, a different nearest station on a few, and an umbrella
  ///    sized from a number the server never computed.
  /// 2. *The 50 km cut on the rounded distance* instead of the raw one: Rust filters on
  ///    `d <= NEARBY_MAX_M` before `d.round()`, so a station at 50,000.4 m is out on the server
  ///    and in here — one extra station at the far edge, which moves `search_radius_m`.
  /// 3. *Rounding after banding* instead of before: Rust stores `d.round() as i64` and
  ///    `nearby_order` divides *that*, so 299.6 m is in the first band on all three sides.
  ///    Dividing the unrounded distance puts it in band 0 here and band 0 there only by luck.
  /// 4. *Cutting by rank instead of by distance*: a nearer station dropped for a better one
  ///    further out, so `firstUnregistered` names the wrong station.
  /// 5. *The tiebreaker.* Rust's `sort_by_key` and `sort_by` are stable over an id-ordered array,
  ///    Dart's `List.sort` and Swift's `sort` are not. Both ports therefore write the record index
  ///    out as a final key. Leave it out and two stations at the same rounded distance come back
  ///    in whichever order the sort happens to leave — a different answer on the same bytes.
  /// 6. *`looks_like_station` re-derived from the name* instead of read from `flags` bit 0: a
  ///    third copy of a string rule to keep in step, and a silent tie broken the other way.
  /// 7. *`searched_radius_m` taken after the rank re-sort*: it is the farthest station actually
  ///    **returned**, which is `best.last` only while the list is still in distance order.
  ///
  /// One shared quirk reproduced rather than fixed: if station 26 sits at the same *rounded*
  /// distance as station 25, the answer claims `complete` within `search_radius_m` while omitting
  /// it. Rust does it, so the phone does. It cannot bite, because `umbrellaRadius` subtracts
  /// `GeofenceRules.margin` = 1,000 m.
  ///
  /// The scan allocates once, for `limit` slots, and never touches the blob.
  func nearby(lat: Double, lon: Double, limit: Int)
    -> (hits: [NearbyHit], searchedRadiusM: Int, complete: Bool)
  {
    // A caller asking for nothing gets nothing. Without this the bounded insertion below indexes
    // `best[-1]` and traps: iOS passes 25 and Android's server default is 3, so nothing hits it
    // today, but this is the shared reader and a trap here is a crashed background wake.
    guard limit > 0 else { return ([], 0, false) }

    var best: [NearbyHit] = []
    best.reserveCapacity(limit)
    data.withUnsafeBytes { raw in
      for i in 0..<count {
        let at = headerLen + i * recordLen
        let la = Double(Self.i32le(raw, at + 4)) / 1_000_000.0
        let lo = Double(Self.i32le(raw, at + 8)) / 1_000_000.0
        // The 50 km cut is on the UNROUNDED distance, as in Rust and Dart.
        let d = GeofenceRules.haversineM(lat, lon, la, lo)
        guard d <= GeofenceRules.nearbyMaxM else { continue }
        // Rounded before anything else.
        let hit = NearbyHit(index: i, distanceM: Int(d.rounded()))
        // The bounded insertion keeps the best `limit` by `(distanceM, index)`, which is exactly
        // what sorting every hit by that key and truncating produces.
        if best.count == limit, !Self.nearerThan(hit, best[limit - 1]) { continue }
        if best.count == limit { best.removeLast() }
        var slot = best.count
        while slot > 0 && Self.nearerThan(hit, best[slot - 1]) { slot -= 1 }
        best.insert(hit, at: slot)
      }
    }

    // After the cut and before the re-sort: how far this answer actually reaches.
    let searchedRadiusM = best.last?.distanceM ?? 0

    // `train::transitous::nearby_order`: the 300 m band, then the better station inside it, then
    // the one whose name says „Bahnhof", then distance. The fifth key is the record index, which
    // is exactly what Rust's stable `sort_by` over an id-ordered array leaves behind: `distanceM`
    // is already the fourth key, so entries equal on all four are equal in distance too, and the
    // preserved order is ascending index, which is ascending id.
    best.sort { a, b in
      let ka = (
        a.distanceM / GeofenceRules.rankBandM, -Int(rank(at: a.index)),
        looksLikeStation(at: a.index) ? 0 : 1, a.distanceM, a.index)
      let kb = (
        b.distanceM / GeofenceRules.rankBandM, -Int(rank(at: b.index)),
        looksLikeStation(at: b.index) ? 0 : 1, b.distanceM, b.index)
      return ka < kb
    }

    // `complete` is „this list is not empty", even when it was truncated — the same thing
    // `Index::nearby` puts on the wire as `!hits.is_empty()`. It is what lets `umbrellaRadius`
    // grow past the cautious default, so it is never optimistic about an absence.
    return (best, searchedRadiusM, !best.isEmpty)
  }

  /// The cut's comparator: rounded distance, then the record index.
  ///
  /// Swift's `sort` is **not** stable, so the index is written out rather than relied on.
  private static func nearerThan(_ a: NearbyHit, _ b: NearbyHit) -> Bool {
    a.distanceM != b.distanceM ? a.distanceM < b.distanceM : a.index < b.index
  }
}

/// The extract on disk, opened per lookup (issue #40).
///
/// Reopened every time rather than held: the whole validated open is under a millisecond, and a
/// held mapping would have to be invalidated when Dart renames a new download into place — the
/// process survives across background wakes, so a stale mapping would keep answering from the
/// previous table until the next launch.
final class StationTable {

  /// The production instance. Tests build their own against a scratch directory, which is why the
  /// directory is stored rather than read out of `StationPaths` inside `answer`.
  static let shared = StationTable(directory: StationPaths.stationsDirectory)

  init(directory: URL?) { self.directory = directory }
  private let directory: URL?

  /// A truncated-but-structurally-valid extract is not an extract: the table has held over 7,000
  /// stations since issue #37. The same floor as `station_store.dart`'s, or one phone gives two
  /// answers.
  static let minPlausibleCount = 1000

  /// What the last lookup read, for the debug page: `"downloaded"`, `"bundled"` or nil.
  private(set) var lastSource: String?
  private(set) var lastVersion: UInt32 = 0
  private(set) var lastCount: Int = 0

  /// The nearby answer, or `nil` when there is no readable table.
  ///
  /// **`nil` is not an empty answer, and the difference is the whole of issue #31.**
  ///
  /// `nil` says „ich konnte nicht nachsehen": `refreshNearest`'s `finish` takes its `else` branch,
  /// keeps the registered set and the computed radius, and only re-centres the umbrella on the
  /// new fix. An empty-but-non-nil answer says „ich habe nachgesehen und hier ist nichts": it
  /// takes the other branch, so `nearest` becomes `[]`, `stopAllRegions()` runs, and because an
  /// empty answer is never `complete`, `umbrellaRadius` falls to the cautious default. A missing
  /// file answered that way would leave the phone with no region at all and an umbrella that
  /// re-fires every few kilometres for ever, with no server left to correct it — the docs/25
  /// storm made permanent.
  ///
  /// So all three of these are `nil`, deliberately:
  ///
  /// - **No file at all** (a fresh install before Dart has mirrored the asset, or a directory the
  ///   app cannot resolve). We learned nothing about geography; the old set is still the best
  ///   guess we have.
  /// - **A file that does not validate** (a bad CRC, a name outside the blob, a count below
  ///   [minPlausibleCount]). Same reason, and it is transient in the same way: Dart discards an
  ///   unreadable download itself on the next weekly check.
  /// - **A device not unlocked since boot.** Files in the app container default to
  ///   `NSFileProtectionCompleteUntilFirstUserAuthentication`, so `Data(contentsOf:)` throws
  ///   Cocoa 257 in that window. It is transient by construction, and the layer is already inert
  ///   there for an unrelated reason: `config`, `nearest` and the region set all live in
  ///   `UserDefaults`, whose backing plist carries the same protection class, and `didExitRegion`
  ///   bails on a nil config. Nothing is set to `NSFileProtectionNone`: the station table is
  ///   public data published unauthenticated, so there is nothing to protect, and unprotecting it
  ///   would not make the layer work before first unlock anyway.
  ///
  /// An empty `NearbyAnswer` is returned only when a good table was read and genuinely holds no
  /// station within 50 km — a passenger 300 km off Rügen, and nowhere in Germany.
  func answer(lat: Double, lon: Double, limit: Int) -> GeofenceRules.NearbyAnswer? {
    guard let dir = directory else {
      lastSource = nil
      lastVersion = 0
      lastCount = 0
      return nil
    }
    // The download first, the mirrored asset second: the download is the newer table whenever it
    // exists, and the mirror is what a fresh install has before the first weekly check.
    for name in [StationPaths.downloadedName, StationPaths.bundledName] {
      do {
        let t = try StationExtract.open(dir.appendingPathComponent(name))
        guard t.count >= Self.minPlausibleCount else { continue }
        lastSource = name == StationPaths.downloadedName ? "downloaded" : "bundled"
        lastVersion = t.tableVersion
        lastCount = t.count
        return GeofenceRules.nearbyAnswer(from: t, lat: lat, lon: lon, limit: limit)
      } catch {
        // Nothing is deleted here. Native never writes in this directory: a delete would race
        // Dart's `.part` rename, and Dart already discards an unreadable download itself.
        continue
      }
    }
    lastSource = nil
    lastVersion = 0
    lastCount = 0
    return nil
  }
}
