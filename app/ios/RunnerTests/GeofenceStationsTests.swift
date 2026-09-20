import CoreLocation
import XCTest

@testable import Runner

/// The extract reader and the scan (issue #40).
///
/// The phone answers „welcher Bahnhof ist hier?" from a file now, in a background wake, with no
/// server to correct it. So the bar is the one #39 met: **the native answer must equal the
/// server's, at scale.** `testTheAnswerAgreesWithTheServerOverEveryProbe` replays a fixture of
/// every station's doorstep at both limits, and `testTheComparisonCanFail` mutates the table five
/// ways and proves the comparison notices — a check that cannot fail reports success just as
/// happily as a correct one.
///
/// Everything is read off the repository's own files through `#filePath`: a simulator test sees
/// the Mac's filesystem, so no bundle resource is copied and these run against exactly the asset
/// that ships.
final class GeofenceStationsTests: XCTestCase {

  // MARK: - The files under test

  /// `…/app`, three directories up from this file.
  private static let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // RunnerTests
    .deletingLastPathComponent()  // ios
    .deletingLastPathComponent()  // app

  private static let extractURL = repo.appendingPathComponent("assets/stations/stations.vst")

  /// `testdata/stations/nearby-probes.tsv`, the one fixture all four readers assert against.
  ///
  /// Top-level rather than under `app/`, because Rust, Dart, Swift and Kotlin all read it and it
  /// belongs to none of them. `VERSPAETOMAT_PROBES` overrides the path for local work — the same
  /// seam Kotlin has as `-Dverspaetomat.probes`. A normal run needs no override.
  private static let fixtureURL: URL = {
    let environment = ProcessInfo.processInfo.environment
    // `xcodebuild` forwards a host variable into the test process under a `TEST_RUNNER_` prefix;
    // the bare name is what a scheme or a direct run sets. Both, so the override works from
    // wherever somebody reaches for it.
    for name in ["TEST_RUNNER_VERSPAETOMAT_PROBES", "VERSPAETOMAT_PROBES"] {
      if let path = environment[name], !path.isEmpty { return URL(fileURLWithPath: path) }
    }
    return repo.deletingLastPathComponent().appendingPathComponent("testdata/stations/nearby-probes.tsv")
  }()

  private static let liveBytes: Data = {
    guard let d = try? Data(contentsOf: extractURL) else {
      fatalError("the bundled extract is missing: \(extractURL.path)")
    }
    return d
  }()

  private func live() throws -> StationExtract { try StationExtract(data: Self.liveBytes) }

  // MARK: - 1. The reader

  /// Every header field of the live extract, as the file holds them today. If a re-cut table
  /// changes one of these, that is a deliberate act and this test is where it gets noticed.
  func testTheLiveExtractOpens() throws {
    let t = try live()
    XCTAssertEqual(t.format, 1)
    XCTAssertEqual(t.headerLen, 32)
    XCTAssertEqual(t.recordLen, 20)
    XCTAssertEqual(t.count, 7604)
    XCTAssertEqual(t.blobLen, 128_132)
    XCTAssertEqual(t.data.count, 280_244)
    XCTAssertEqual(t.crc32, 0xb04a_dd01)
    XCTAssertEqual(t.blobAt, 32 + 20 * 7604)
    XCTAssertEqual(t.tableVersion, 1, "production's newest import")
  }

  /// `header_len` is read from the header and never assumed to be 32. A format-1 file may grow a
  /// header; a reader that hardcoded the number would refuse it for being damaged, and the CRC —
  /// which starts at `header_len` — would be computed over the wrong bytes.
  func testHeaderLenIsReadAndNotAssumed() throws {
    let t = try live()
    let bytes = Extracts.respin(Self.liveBytes, headerLen: 40)
    let grown = try StationExtract(data: bytes)
    XCTAssertEqual(grown.headerLen, 40)
    XCTAssertEqual(grown.count, t.count)
    XCTAssertEqual(grown.data.count, 40 + 20 * 7604 + 128_132)

    // The eight added header bytes are 0xA5, not zero, and they are outside the checked span — so
    // the checksum is the live file's, unchanged, and a reader that started at a literal 32 would
    // compute a different number and refuse the file for being damaged. That this opens at all is
    // the proof; these two assertions are why it is proof.
    XCTAssertEqual(grown.crc32, t.crc32, "the header is outside the span the CRC covers")
    XCTAssertNotEqual(bytes.withUnsafeBytes { CRC32.over($0, from: 32) }, grown.crc32,
                      "a reader that assumed 32 would refuse this file")

    assertAnswersMatch(t, grown, probes: Extracts.sampleProbes(t, every: 211))
  }

  /// `record_len` is strided over, not assumed. Four pad bytes per record is what a fifth field
  /// would look like to this build.
  func testRecordLenIsStridedOver() throws {
    let t = try live()
    let grown = try StationExtract(data: Extracts.respin(Self.liveBytes, recordLen: 24))
    XCTAssertEqual(grown.recordLen, 24)
    XCTAssertEqual(grown.data.count, 32 + 24 * 7604 + 128_132)
    XCTAssertEqual(grown.blobAt, 32 + 24 * 7604)
    assertAnswersMatch(t, grown, probes: Extracts.sampleProbes(t, every: 211))
  }

  /// One case per check, each file wrong in exactly one way, asserting the specific `Failure`.
  ///
  /// The order matters as much as the outcome: `extract.rs`'s `parse` and `station_extract.dart`'s
  /// `decode` both check `count` before `record_len`, so a file that is bad in both ways must be
  /// reported the same way here as there. (docs/45's prose list has those two the other way round
  /// and is the thing to correct, not the two working readers.)
  func testEveryRefusal() throws {
    func refuses(_ bytes: Data, _ want: StationExtract.Failure, _ what: String) {
      XCTAssertThrowsError(try StationExtract(data: bytes), what) { error in
        XCTAssertEqual(error as? StationExtract.Failure, want, what)
      }
    }
    var b: [UInt8]

    refuses(Self.liveBytes.prefix(31), .tooShort(31), "shorter than the header")

    b = [UInt8](Self.liveBytes); b[2] = 0x00
    refuses(Data(b), .magic, "not a station extract")

    b = [UInt8](Self.liveBytes); Extracts.put16(&b, 4, 2)
    refuses(Data(b), .format(2), "a format this reader does not know")

    b = [UInt8](Self.liveBytes); Extracts.put16(&b, 6, 31)
    refuses(Data(b), .headerLen(31), "a header shorter than the fields it must carry")

    b = [UInt8](Self.liveBytes); Extracts.put32(&b, 8, 0)
    refuses(Data(b), .emptyCount, "an extract of nothing")

    b = [UInt8](Self.liveBytes); Extracts.put32(&b, 12, 19)
    refuses(Data(b), .recordLen(19), "a record shorter than the fields it must carry")

    b = [UInt8](Self.liveBytes); Extracts.put32(&b, 16, 128_133)
    refuses(Data(b), .length(want: 280_245, is: 280_244), "the file says one length and is another")

    b = [UInt8](Self.liveBytes); b[b.count - 1] ^= 0x01
    refuses(Data(b), .checksum, "a damaged file")

    // The last two are structurally fine, so the CRC is recomputed — otherwise they would be
    // caught by the checksum and the name checks would never run.
    b = [UInt8](Self.liveBytes); b[32 + 14] = 0
    Extracts.recrc(&b)
    refuses(Data(b), .name(record: 0), "a record with no name")

    b = [UInt8](Self.liveBytes); Extracts.put32(&b, 32 + 16, 128_132)
    Extracts.recrc(&b)
    refuses(Data(b), .name(record: 0), "a name that starts at the end of the blob")
  }

  /// Record byte 15 is `reserved` and is ignored rather than checked for zero: that is where the
  /// next field goes, and a reader that asserts it is 0 refuses the first grown file.
  func testReservedIsIgnored() throws {
    let t = try live()
    var b = [UInt8](Self.liveBytes)
    for i in 0..<t.count { b[32 + i * 20 + 15] = 0xFF }
    Extracts.recrc(&b)
    let loud = try StationExtract(data: Data(b))
    assertAnswersMatch(t, loud, probes: Extracts.sampleProbes(t, every: 211))
  }

  /// Names come out of the blob, and two records with the same name share one slice — first in
  /// record order wins, so the file is a function of the table and nothing else. The live table
  /// has exactly four such pairs.
  func testNamesAndSharedSlices() throws {
    let t = try live()
    for (id, name) in [
      (UInt32(1), "Magdeburgerforth (Kleinbahn)"),
      (UInt32(2049), "Köln Hbf"),
      (UInt32(2053), "Köln Messe/Deutz Bf"),
      (UInt32(5950), "Wiesenburg, Bahnhof"),
      (UInt32(7604), "Lutherstadt Wittenberg, Bhf Labetz"),
    ] {
      let i = try XCTUnwrap(t.index(ofId: id), "id \(id) is in the table")
      XCTAssertEqual(t.name(at: i), name)
    }

    // Group the records by the blob slice they point at; the ones sharing a slice are the
    // duplicates the renderer folded together.
    var bySlice: [String: [Int]] = [:]
    for i in 0..<t.count {
      let at = 32 + i * 20
      let key = Self.liveBytes.withUnsafeBytes { "\(StationExtract.u32le($0, at + 16)):\($0[at + 14])" }
      bySlice[key, default: []].append(i)
    }
    let shared = bySlice.values.filter { $0.count > 1 }
    XCTAssertEqual(shared.count, 4, "four names appear twice in the live table")
    XCTAssertEqual(
      Set(shared.map { t.name(at: $0[0]) }),
      ["Wissembourg, Bahnhof", "Oelsnitz, Bahnhof", "Zimmern, Bahnhof", "Wiesenburg, Bahnhof"])
    for group in shared {
      XCTAssertEqual(Set(group.map { t.name(at: $0) }).count, 1, "one slice, one name")
    }
  }

  /// Records are strictly ascending by id — `render` refuses an unsorted index — so the lookup is
  /// a binary search.
  func testBinarySearchById() throws {
    let t = try live()
    var previous: UInt32 = 0
    for i in 0..<t.count {
      let id = t.id(at: i)
      XCTAssertGreaterThan(id, previous, "record \(i) breaks the ascending order")
      previous = id
    }
    for i in stride(from: 0, to: t.count, by: 97) {
      XCTAssertEqual(t.index(ofId: t.id(at: i)), i)
    }
    XCTAssertNil(t.index(ofId: 0))
    XCTAssertNil(t.index(ofId: .max))
  }

  /// CRC-32/ISO-HDLC, against two numbers computed elsewhere: the check value every
  /// implementation of this CRC publishes, and the live file's own header field.
  func testCRCMatchesTheKnownNumber() throws {
    let check = Data("123456789".utf8)
    XCTAssertEqual(check.withUnsafeBytes { CRC32.over($0, from: 0) }, 0xCBF4_3926)
    let t = try live()
    XCTAssertEqual(Self.liveBytes.withUnsafeBytes { CRC32.over($0, from: t.headerLen) }, 0xb04a_dd01)
    // Not over the whole file: the header is outside the checked span, which is what lets the
    // renderer write the CRC into it.
    XCTAssertNotEqual(Self.liveBytes.withUnsafeBytes { CRC32.over($0, from: 0) }, 0xb04a_dd01)
  }

  // MARK: - 2. Ordering and parity

  /// **The acceptance test.** Every row of `testdata/stations/nearby-probes.tsv`: the same ids in
  /// the same order, the same `search_radius_m`, the same `complete`.
  ///
  /// The rows are what **`Index::nearby` itself** answered — generated by
  /// `cargo test --release --lib write_the_nearby_probe_fixture -- --ignored`, not by any reader —
  /// so this is Swift against the server directly, with nothing in between. The same file is what
  /// the Dart and Kotlin suites assert against; four readings of one ordering is four chances to
  /// drift, and one file is how that stays at zero.
  ///
  /// Exact, with no tolerance and no lenient ties. Ties look like they would need one, but both of
  /// `Index::nearby`'s sorts are stable and the extract's records ascend by id, so two stations at
  /// the same rounded metre resolve the same way in every language — argued from the Rust and
  /// measured from the other side, by perturbing every distance by ±1 ulp and finding no row whose
  /// answer moved. A forgiving comparison would pass an unstable sort, which is the one bug this
  /// file exists to catch.
  func testTheAnswerAgreesWithTheServerOverEveryProbe() throws {
    let t = try live()
    let fixture = try Probes.load(Self.fixtureURL, against: t)

    // Against the file's own header, never a formula: the fixture chooses its probes for the hard
    // cases — band edges, exact ties, truncation photo-finishes — and how many there are is its
    // business, not this test's.
    XCTAssertEqual(fixture.stationCount, t.count, "the fixture was cut from a different table")
    XCTAssertGreaterThan(fixture.rows.count, 0)
    XCTAssertEqual(Set(fixture.rows.map(\.limit)), [3, 25], "both the Android and the iOS limit")

    var disagreements = 0
    var reported: [String] = []
    for row in fixture.rows {
      let scan = t.nearby(lat: row.lat, lon: row.lon, limit: row.limit)
      let ids = scan.hits.map { t.id(at: $0.index) }
      guard ids != row.ids || scan.searchedRadiusM != row.radius || scan.complete != row.complete else { continue }
      disagreements += 1
      if reported.count < 10 { reported.append(row.describe(got: ids, scan.searchedRadiusM, scan.complete)) }
    }
    XCTAssertEqual(disagreements, 0,
                   "\(disagreements) of \(fixture.rows.count) rows disagree:\n" + reported.joined(separator: "\n"))

    // The rows that are easiest to lose in a parser rather than in a reader. An empty answer is a
    // real answer — `refreshNearest` drops the registered set on it — and a row whose `ids` column
    // is empty is exactly where a naive split silently produces one field too few.
    let empties = fixture.rows.filter { $0.ids.isEmpty }
    XCTAssertGreaterThanOrEqual(empties.count, 2, "Madrid and the North Sea are in the file")
    for row in empties {
      XCTAssertFalse(row.complete)
      XCTAssertEqual(row.radius, 0)
    }
    // And the table is not German-only: a reader that assumed it was disagrees here.
    XCTAssertTrue(fixture.rows.contains { $0.lat > 48.8 && $0.lat < 48.9 && $0.lon > 2.3 && $0.lon < 2.4 },
                  "Paris answers positively")
  }

  /// `looks_like_station` is baked into `flags` bit 0 at import time and never re-derived from the
  /// name on the phone. This is the one place that checks the byte still means what the server
  /// means by it — a port of `train::transitous::looks_like_station`, run over all 7,604 names.
  func testFlagsAgreeWithLooksLikeStation() throws {
    let t = try live()
    var flagged = 0
    for i in 0..<t.count {
      let byName = Self.looksLikeStationByName(t.name(at: i))
      XCTAssertEqual(t.looksLikeStation(at: i), byName, "record \(i), „\(t.name(at: i))\"")
      if t.looksLikeStation(at: i) { flagged += 1 }
    }
    XCTAssertEqual(flagged, 2732, "how many of the live table's names say „Bahnhof\"")
  }

  /// `train::transitous::looks_like_station`: every trailing `)` goes first, then both ends are
  /// trimmed, and only then the suffix tests run. Deliberately a test-only copy — the reader must
  /// never need it.
  private static func looksLikeStationByName(_ name: String) -> Bool {
    var s = Substring(name)
    while s.hasSuffix(")") { s = s.dropLast() }
    let n = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return n.hasSuffix("Hbf") || n.hasSuffix("Hauptbahnhof") || n.hasSuffix("Bahnhof")
      || n.hasSuffix(" Bf") || n.contains(" Hbf")
  }

  /// Swift's `sort` is not stable, so the record index is written out as the last key everywhere.
  /// Two stations at one coordinate would otherwise come back in whichever order the sort happens
  /// to leave — run a hundred times, because passing once proves nothing about an unstable sort.
  func testTiesBreakByAscendingId() throws {
    let t = try StationExtract(data: Extracts.build([
      .init(id: 10, latE6: 50_000_000, lonE6: 8_000_000, rank: 2, flags: 1, name: "Zwilling A"),
      .init(id: 11, latE6: 50_000_000, lonE6: 8_000_000, rank: 2, flags: 1, name: "Zwilling B"),
      .init(id: 12, latE6: 50_010_000, lonE6: 8_000_000, rank: 2, flags: 1, name: "Nachbar"),
    ]))
    for _ in 0..<100 {
      let scan = t.nearby(lat: 50.0, lon: 8.0, limit: 3)
      XCTAssertEqual(scan.hits.map { t.id(at: $0.index) }, [10, 11, 12])
      let answer = GeofenceRules.nearbyAnswer(from: t, lat: 50.0, lon: 8.0, limit: 3)
      XCTAssertEqual(answer.stations.map(\.id), ["vs:10", "vs:11", "vs:12"])
    }
  }

  /// Nearest first for the cut, best-ranked first for the answer — and never the other way.
  ///
  /// A Hauptbahnhof at 250 m beats a bus stop at 60 m inside the 300 m band, but at `limit` 1 the
  /// answer is still the bus stop: the cut is by distance. Cutting by rank instead would drop a
  /// nearer station in favour of a better one further out, and then the nearest station the phone
  /// did not register is not the one `umbrellaRadius` sizes from.
  func testTheCutIsByDistanceAndTheOrderByRank() throws {
    // ~60 m north, ~250 m north, ~500 m north: inside the band, inside the band, outside it.
    let t = try StationExtract(data: Extracts.build([
      .init(id: 1, latE6: 50_000_540, lonE6: 8_000_000, rank: 0, flags: 0, name: "Am Markt"),
      .init(id: 2, latE6: 50_002_250, lonE6: 8_000_000, rank: 5, flags: 1, name: "Musterstadt Hbf"),
      .init(id: 3, latE6: 50_004_500, lonE6: 8_000_000, rank: 9, flags: 1, name: "Fernstadt Hbf"),
    ]))
    let scan = t.nearby(lat: 50.0, lon: 8.0, limit: 3)
    XCTAssertEqual(scan.hits.map { $0.distanceM / GeofenceRules.rankBandM }, [0, 0, 1],
                   "the first two share the 300 m band, the third does not")
    XCTAssertEqual(scan.hits.map { t.id(at: $0.index) }, [2, 1, 3],
                   "inside the band the better station wins; beyond it distance decides again")
    // The cut, at each limit: by distance, so the nearest survives even though it ranks worst.
    XCTAssertEqual(t.nearby(lat: 50.0, lon: 8.0, limit: 1).hits.map { t.id(at: $0.index) }, [1])
    XCTAssertEqual(t.nearby(lat: 50.0, lon: 8.0, limit: 2).hits.map { t.id(at: $0.index) }, [2, 1])
    // A caller asking for nothing gets nothing rather than a trap on `best[-1]`.
    XCTAssertEqual(t.nearby(lat: 50.0, lon: 8.0, limit: 0).hits.count, 0)
    XCTAssertFalse(t.nearby(lat: 50.0, lon: 8.0, limit: 0).complete)
  }

  /// `search_radius_m` is the distance of the farthest station actually **returned** — taken after
  /// the cut and before the rank re-sort, which is the only moment the list is still in distance
  /// order. `umbrellaRadius` sizes the umbrella from it, so reading it a step later would quietly
  /// resize the disc on every phone.
  func testSearchedRadiusIsTheFarthestReturned() throws {
    let t = try live()
    for (lat, lon) in Extracts.sampleProbes(t, every: 811) {
      for limit in [1, 3, 25] {
        let scan = t.nearby(lat: lat, lon: lon, limit: limit)
        let farthest = scan.hits.map(\.distanceM).max() ?? 0
        XCTAssertEqual(scan.searchedRadiusM, farthest)
        XCTAssertEqual(scan.complete, !scan.hits.isEmpty)
        XCTAssertLessThanOrEqual(scan.hits.count, limit)
        let answer = GeofenceRules.nearbyAnswer(from: t, lat: lat, lon: lon, limit: limit)
        XCTAssertEqual(answer.searchedRadius, Double(farthest))
        // What `regionSet` and `umbrellaRadius` see is distance order, as `parseNearby` gave them.
        let distances = scan.hits.sorted { $0.distanceM < $1.distanceM }.map(\.distanceM)
        XCTAssertEqual(
          answer.stations.map { GeofenceRules.haversineM(lat, lon, $0.lat, $0.lon).rounded() },
          distances.map(Double.init))
      }
    }
  }

  /// Out at sea there is genuinely nothing, and the answer says so: empty, radius 0, and **not**
  /// complete — so `umbrellaRadius` refuses to widen on it and falls back to the cautious radius.
  /// This is the answer a missing file must never give; see `testAMissingFileIsNilAndNotAnEmptyAnswer`.
  func testAnEmptyAnswerIsNotComplete() throws {
    let t = try live()
    let answer = GeofenceRules.nearbyAnswer(from: t, lat: 57.1, lon: 13.4, limit: 25)  // ~300 km N of Rügen
    XCTAssertTrue(answer.stations.isEmpty)
    XCTAssertEqual(answer.searchedRadius, 0)
    XCTAssertFalse(answer.complete)

    let sized = GeofenceRules.umbrellaRadius(
      registered: [], answer: answer, here: CLLocation(latitude: 57.1, longitude: 13.4),
      stationRadius: 300, cautious: 8_000, deviceMax: 0)
    XCTAssertEqual(sized.radius, 8_000, "an absence never widens the umbrella")
    XCTAssertEqual(sized.why, "server did not claim a complete answer")
  }

  /// The metric is `train::haversine_m` on a sphere of 6,371 km, never `CLLocation.distance(from:)`
  /// on an ellipsoid. Five values computed outside Swift, and a difference from CoreLocation big
  /// enough that nobody can quietly swap them back.
  func testHaversineIsNotCLLocationDistance() {
    let cases: [(Double, Double, Double, Double, Double)] = [
      (50.9413, 6.9583, 51.2198, 6.7942, 33021.356198),  // Köln Hbf → Düsseldorf Hbf
      (0.0, 0.0, 0.0, 1.0, 111194.926645),  // one degree on the equator
      (52.5200, 13.4050, 48.1372, 11.5756, 504305.403131),  // Berlin → München
      (50.0, 8.0, 50.0, 8.001, 71.474721),  // a platform's length
      (50.9413, 6.9583, 50.9413, 6.9583, 0.0),  // standing still
    ]
    for (a, b, c, d, want) in cases {
      XCTAssertEqual(GeofenceRules.haversineM(a, b, c, d), want, accuracy: 0.5, "\(a),\(b) → \(c),\(d)")
    }
    // ~24.4 km apart: CoreLocation says 43 m more. The 50 km cut, the 300 m band and
    // `search_radius_m` all move if this is swapped.
    let h = GeofenceRules.haversineM(50.9413, 6.9583, 51.1, 7.2)
    let cl = CLLocation(latitude: 50.9413, longitude: 6.9583)
      .distance(from: CLLocation(latitude: 51.1, longitude: 7.2))
    XCTAssertGreaterThan(abs(h - cl), 1.0, "the two metrics are not interchangeable")
    XCTAssertGreaterThan(h, 24_000)
  }

  // MARK: - 3. The seam: nil is not empty

  /// **The assertion that keeps issue #31 shut.**
  ///
  /// `nil` means „ich konnte nicht nachsehen" and `refreshNearest` keeps the registered set. An
  /// empty answer means „ich habe nachgesehen und hier ist nichts" and it drops the set, stops
  /// every region and falls back to the cautious umbrella. A missing file teaches us nothing about
  /// geography, so it must be the first and never the second — otherwise a phone that loses its
  /// file is left with no region at all and an umbrella that re-fires for ever, with no server to
  /// correct it.
  func testAMissingFileIsNilAndNotAnEmptyAnswer() throws {
    let dir = try scratchDirectory()

    // Nothing there at all.
    let empty = StationTable(directory: dir)
    XCTAssertNil(empty.answer(lat: 50.9413, lon: 6.9583, limit: 25))
    XCTAssertNil(empty.lastSource)
    XCTAssertEqual(empty.lastCount, 0)

    // A directory the app cannot resolve at all.
    XCTAssertNil(StationTable(directory: nil).answer(lat: 50.9413, lon: 6.9583, limit: 25))

    // A file that is there but damaged: one flipped blob byte, CRC left alone.
    var bad = [UInt8](Self.liveBytes)
    bad[bad.count - 1] ^= 0x01
    try Data(bad).write(to: dir.appendingPathComponent(StationPaths.downloadedName))
    let damaged = StationTable(directory: dir)
    XCTAssertNil(damaged.answer(lat: 50.9413, lon: 6.9583, limit: 25))
    XCTAssertNil(damaged.lastSource)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: dir.appendingPathComponent(StationPaths.downloadedName).path),
      "native never writes in this directory, so it never deletes either")

    // And a good file in the same place does answer, so the nil above is about the file and not
    // about the plumbing.
    try Self.liveBytes.write(to: dir.appendingPathComponent(StationPaths.downloadedName))
    let good = StationTable(directory: dir)
    let answer = try XCTUnwrap(good.answer(lat: 50.9413, lon: 6.9583, limit: 25))
    XCTAssertEqual(answer.stations.first?.name, "Köln Hbf")
    XCTAssertTrue(answer.complete)
    XCTAssertEqual(good.lastSource, "downloaded")
    XCTAssertEqual(good.lastCount, 7604)
  }

  /// The downloaded copy is the newer table whenever it exists; the mirrored asset is what a fresh
  /// install has before the first weekly check has ever succeeded. When the download is unreadable
  /// the mirror answers — and **both files are still on disk afterwards**, because native never
  /// writes in this directory and a delete would race Dart's `.part` rename.
  func testTheDownloadedCopyWinsOverTheBundledOne() throws {
    let dir = try scratchDirectory()
    let downloaded = dir.appendingPathComponent(StationPaths.downloadedName)
    let bundled = dir.appendingPathComponent(StationPaths.bundledName)

    // `version` lives in the header, which is outside the CRC's span, so it can be changed
    // without touching the checksum — the same property that lets the renderer write the CRC.
    var seven = [UInt8](Self.liveBytes)
    Extracts.put32(&seven, 24, 7)
    try Data(seven).write(to: downloaded)
    try Self.liveBytes.write(to: bundled)

    let table = StationTable(directory: dir)
    XCTAssertNotNil(table.answer(lat: 50.9413, lon: 6.9583, limit: 25))
    XCTAssertEqual(table.lastSource, "downloaded")
    XCTAssertEqual(table.lastVersion, 7)

    var damaged = seven
    damaged[damaged.count - 1] ^= 0x01
    try Data(damaged).write(to: downloaded)
    let fallback = StationTable(directory: dir)
    XCTAssertNotNil(fallback.answer(lat: 50.9413, lon: 6.9583, limit: 25))
    XCTAssertEqual(fallback.lastSource, "bundled")
    XCTAssertEqual(fallback.lastVersion, 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: downloaded.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: bundled.path))
  }

  /// A truncated-but-structurally-valid extract is not an extract: the table has held over 7,000
  /// stations since issue #37. The same floor as `station_store.dart`'s, or one phone gives two
  /// answers.
  func testTheImplausibleCountFloor() throws {
    let dir = try scratchDirectory()
    let downloaded = dir.appendingPathComponent(StationPaths.downloadedName)

    func table(of n: Int) -> Data {
      Extracts.build((0..<n).map {
        .init(id: UInt32($0 + 1), latE6: Int32(50_000_000 + $0 * 100), lonE6: 8_000_000,
              rank: 2, flags: 1, name: "Bahnhof \($0)")
      })
    }

    try table(of: 999).write(to: downloaded)
    let tooFew = StationTable(directory: dir)
    XCTAssertNil(tooFew.answer(lat: 50.0, lon: 8.0, limit: 25), "999 stations is a truncated table")
    XCTAssertNil(tooFew.lastSource)

    try table(of: 1000).write(to: downloaded)
    let enough = StationTable(directory: dir)
    XCTAssertNotNil(enough.answer(lat: 50.0, lon: 8.0, limit: 25))
    XCTAssertEqual(enough.lastCount, 1000)

    // And the floor is a *skip*, not a refusal: a plausible mirror still answers behind an
    // implausible download.
    try table(of: 999).write(to: downloaded)
    try Self.liveBytes.write(to: dir.appendingPathComponent(StationPaths.bundledName))
    let mirrored = StationTable(directory: dir)
    XCTAssertNotNil(mirrored.answer(lat: 50.9413, lon: 6.9583, limit: 25))
    XCTAssertEqual(mirrored.lastSource, "bundled")
  }

  // MARK: - 4. Proof the comparison can fail

  /// A check that cannot fail reports success just as happily as a correct one.
  ///
  /// Two kinds of fault, because they prove different things. **A wrong table** shows the
  /// comparison is reading the records it claims to; **a wrong comparator** shows the fixture's
  /// own rows discriminate — it was chosen for band edges, exact ties and truncation
  /// photo-finishes, and a file of easy probes would pass every ordering bug there is.
  ///
  /// The comparator counts are asserted exactly, and they are the numbers the Kotlin reader
  /// measured independently against the same file. Four implementations agreeing on how many rows
  /// a given bug moves is worth more than four implementations agreeing that it moves some.
  func testTheComparisonCanFail() throws {
    let t = try live()
    let rows = try Probes.load(Self.fixtureURL, against: t).rows

    func disagreements(_ table: StationExtract) -> Int {
      rows.reduce(into: 0) { total, row in
        let scan = table.nearby(lat: row.lat, lon: row.lon, limit: row.limit)
        if scan.hits.map({ table.id(at: $0.index) }) != row.ids
          || scan.searchedRadiusM != row.radius || scan.complete != row.complete { total += 1 }
      }
    }
    XCTAssertEqual(disagreements(t), 0, "the unmutated table is the baseline every count below is against")

    func record(_ id: UInt32) throws -> Int { 32 + (try XCTUnwrap(t.index(ofId: id))) * 20 }

    // Each target is a station the fixture's own rows actually name, so the mutation has somewhere
    // to show up. Asserted rather than assumed: a re-cut table that broke the setup fails here
    // instead of silently testing nothing.
    XCTAssertEqual(t.rank(at: try XCTUnwrap(t.index(ofId: 4565))), 1)
    XCTAssertTrue(t.looksLikeStation(at: try XCTUnwrap(t.index(ofId: 4493))))

    var mutations: [(String, Data)] = []

    // (a) a rank raised, on a station sharing a 300 m band with its neighbour.
    var a = [UInt8](Self.liveBytes)
    a[try record(4565) + 12] = 3
    Extracts.recrc(&a)
    mutations.append(("rank of id 4565 raised 1 → 3", Data(a)))

    // (b) `flags` bit 0 cleared on a station that wins a tie by it.
    var b = [UInt8](Self.liveBytes)
    b[try record(4493) + 13] &= ~StationExtract.flagLooksLikeStation
    Extracts.recrc(&b)
    mutations.append(("flags bit 0 cleared on id 4493", Data(b)))

    // (c) a coordinate moved by +3,000 e6 (≈ 334 m), on the farthest station of a limit-25 answer,
    // so `search_radius_m` moves whether or not the order does.
    var c = [UInt8](Self.liveBytes)
    let latAt = try record(4568) + 4
    Extracts.put32(&c, latAt, UInt32(bitPattern: Int32(bitPattern: Extracts.get32(c, latAt)) + 3000))
    Extracts.recrc(&c)
    mutations.append(("lat_e6 of id 4568 moved +334 m", Data(c)))

    // (d) two adjacent records' ids swapped. The reader does not verify the ascending order —
    // `render` does, on the server — so this opens and answers with the wrong ids.
    var d = [UInt8](Self.liveBytes)
    let (p, q) = (try record(1), try record(2))
    for k in 0..<4 { d.swapAt(p + k, q + k) }
    Extracts.recrc(&d)
    mutations.append(("ids of records 0/1 swapped", Data(d)))

    for (what, bytes) in mutations {
      XCTAssertGreaterThan(disagreements(try StationExtract(data: bytes)), 0, "\(what): the comparison did not notice")
    }

    // (e) a flipped blob byte with the CRC left alone never gets as far as a comparison.
    var e = [UInt8](Self.liveBytes)
    e[e.count - 1] ^= 0x01
    XCTAssertThrowsError(try StationExtract(data: Data(e))) {
      XCTAssertEqual($0 as? StationExtract.Failure, .checksum)
    }

    // And the comparator faults, against the Kotlin reader's independently measured counts.
    for (fault, want) in [(Ordering.Fault.none, 0), (.band250, 201), (.rankInverted, 257),
                          (.nameFlagIgnored, 166), (.tieBreakReversed, 56)] {
      let bad = rows.reduce(into: 0) { total, row in
        let got = Ordering.answer(t, fault, lat: row.lat, lon: row.lon, limit: row.limit)
        if got.ids != row.ids || got.radius != row.radius || got.complete != row.complete { total += 1 }
      }
      XCTAssertEqual(bad, want, "comparator fault \(fault)")
    }
  }

  // MARK: - Helpers

  private func scratchDirectory() throws -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("stations-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
    return dir
  }

  private func assertAnswersMatch(
    _ a: StationExtract, _ b: StationExtract, probes: [(Double, Double)],
    limit: Int = 25, file: StaticString = #filePath, line: UInt = #line
  ) {
    for (lat, lon) in probes {
      let x = a.nearby(lat: lat, lon: lon, limit: limit)
      let y = b.nearby(lat: lat, lon: lon, limit: limit)
      XCTAssertEqual(x.hits.map { a.id(at: $0.index) }, y.hits.map { b.id(at: $0.index) },
                     "at \(lat),\(lon)", file: file, line: line)
      XCTAssertEqual(x.searchedRadiusM, y.searchedRadiusM, "at \(lat),\(lon)", file: file, line: line)
      XCTAssertEqual(x.complete, y.complete, "at \(lat),\(lon)", file: file, line: line)
    }
  }
}

// MARK: - Building extracts to read

/// Extract surgery for the tests: little-endian writes, a CRC refresh, whole files respun with a
/// different `header_len` or `record_len`, and synthetic tables built from scratch.
enum Extracts {
  struct Station {
    var id: UInt32
    var latE6: Int32
    var lonE6: Int32
    var rank: UInt8
    var flags: UInt8
    var name: String
  }

  static func get32(_ b: [UInt8], _ at: Int) -> UInt32 {
    UInt32(b[at]) | (UInt32(b[at + 1]) << 8) | (UInt32(b[at + 2]) << 16) | (UInt32(b[at + 3]) << 24)
  }

  static func put16(_ b: inout [UInt8], _ at: Int, _ v: UInt16) {
    b[at] = UInt8(v & 0xFF)
    b[at + 1] = UInt8((v >> 8) & 0xFF)
  }

  static func put32(_ b: inout [UInt8], _ at: Int, _ v: UInt32) {
    b[at] = UInt8(v & 0xFF)
    b[at + 1] = UInt8((v >> 8) & 0xFF)
    b[at + 2] = UInt8((v >> 16) & 0xFF)
    b[at + 3] = UInt8((v >> 24) & 0xFF)
  }

  /// Recompute the checksum over `[header_len, EOF)` and write it into the header.
  static func recrc(_ b: inout [UInt8]) {
    let hl = Int(UInt16(b[6]) | (UInt16(b[7]) << 8))
    let crc = b.withUnsafeBytes { CRC32.over($0, from: hl) }
    put32(&b, 28, crc)
  }

  /// The same table with a longer header or longer records: the records are copied field for
  /// field and padded, the blob is copied verbatim so the shared slices survive, and the checksum
  /// is recomputed over the new span.
  static func respin(_ live: Data, headerLen: Int = 32, recordLen: Int = 20) -> Data {
    let src = [UInt8](live)
    let hl0 = Int(UInt16(src[6]) | (UInt16(src[7]) << 8))
    let rl0 = Int(get32(src, 12))
    let count = Int(get32(src, 8))
    precondition(headerLen >= hl0 && recordLen >= rl0, "respin only grows a file")

    // The header extension is filled with a value that is not zero, so that a CRC taken from the
    // wrong offset is visibly wrong rather than accidentally right.
    var out = [UInt8](src[0..<hl0])
    out.append(contentsOf: [UInt8](repeating: 0xA5, count: headerLen - hl0))
    for i in 0..<count {
      let at = hl0 + i * rl0
      out.append(contentsOf: src[at..<(at + rl0)])
      out.append(contentsOf: [UInt8](repeating: 0, count: recordLen - rl0))
    }
    out.append(contentsOf: src[(hl0 + rl0 * count)...])

    put16(&out, 6, UInt16(headerLen))
    put32(&out, 12, UInt32(recordLen))
    recrc(&out)
    return Data(out)
  }

  /// A whole extract from a handful of stations, the way `extract.rs`'s `render` writes one:
  /// records ascending by id, two records with the same name sharing one blob slice.
  static func build(_ stations: [Station], headerLen: Int = 32, recordLen: Int = 20) -> Data {
    var records: [UInt8] = []
    var blob: [UInt8] = []
    var shared: [String: UInt32] = [:]
    for s in stations {
      let name = [UInt8](s.name.utf8)
      precondition(!name.isEmpty && name.count <= 255)
      let off: UInt32
      if let seen = shared[s.name] {
        off = seen
      } else {
        off = UInt32(blob.count)
        blob.append(contentsOf: name)
        shared[s.name] = off
      }
      var rec = [UInt8](repeating: 0, count: recordLen)
      put32(&rec, 0, s.id)
      put32(&rec, 4, UInt32(bitPattern: s.latE6))
      put32(&rec, 8, UInt32(bitPattern: s.lonE6))
      rec[12] = s.rank
      rec[13] = s.flags
      rec[14] = UInt8(name.count)
      rec[15] = 0  // reserved
      put32(&rec, 16, off)
      records.append(contentsOf: rec)
    }

    var out = [UInt8](repeating: 0, count: headerLen)
    out[0] = 0x56; out[1] = 0x53; out[2] = 0x53; out[3] = 0x54  // "VSST"
    put16(&out, 4, 1)
    put16(&out, 6, UInt16(headerLen))
    put32(&out, 8, UInt32(stations.count))
    put32(&out, 12, UInt32(recordLen))
    put32(&out, 16, UInt32(blob.count))
    put32(&out, 20, 1_789_924_059)  // generated
    put32(&out, 24, 1)  // version
    out.append(contentsOf: records)
    out.append(contentsOf: blob)
    recrc(&out)
    return Data(out)
  }

  /// Every `every`-th station's doorstep: its own coordinate, 0.004 degrees north-east. About
  /// 500 m off the platform and inside the same town, which is the case the ranking has to get
  /// right — and the same offset the fixture uses.
  static func sampleProbes(_ t: StationExtract, every: Int) -> [(Double, Double)] {
    stride(from: 0, to: t.count, by: every).map { i in
      (((t.lat(at: i) * 1_000_000).rounded() + 4000) / 1_000_000,
       ((t.lon(at: i) * 1_000_000).rounded() + 4000) / 1_000_000)
    }
  }
}

// MARK: - The fixture

/// `testdata/stations/nearby-probes.tsv` — what `Index::nearby` answers, for every reader of the
/// extract to check itself against.
///
///     # ... prose ...
///     #   lat  lon  limit  search_radius_m  complete  ids  label
///     # crc32=0xb04add01 count=7604
///     48.140200<TAB>11.560000<TAB>3<TAB>881<TAB>1<TAB>4543,4541,4572<TAB>München Hbf entrance
///
/// **Parsed by column name, never by position.** The generator is allowed to append columns, and
/// it has already removed one: a positional parser that read the departed `n` column would have
/// taken a count for a search radius and asserted on it — a wrong answer rather than an error.
/// The Kotlin reader lost two runs to exactly that. It is the same instinct as reading `header_len`
/// out of the extract instead of assuming 32, one level up.
enum Probes {

  /// The column names this test needs. `label` is read when present and never asserted on: it is
  /// for whoever reads a failure.
  static let required = ["lat", "lon", "limit", "search_radius_m", "complete", "ids"]

  struct Row {
    let lat: Double
    let lon: Double
    let limit: Int
    let radius: Int
    let complete: Bool
    let ids: [UInt32]
    let label: String

    func describe(got: [UInt32], _ radius: Int, _ complete: Bool) -> String {
      "  \(lat),\(lon) limit \(limit) — \(label)\n    want \(ids) r=\(self.radius) c=\(self.complete)"
        + "\n    got  \(got) r=\(radius) c=\(complete)"
    }
  }

  struct File {
    /// The extract these answers belong to. A pure function of the table — the CRC covers
    /// `[header_len, EOF)` — so it survives a re-render and only moves when the table does.
    let crc32: UInt32
    /// The extract's station count, from the same line.
    let stationCount: Int
    let rows: [Row]
  }

  enum Failure: Error, CustomStringConvertible {
    case missing(String)
    case noColumnHeader(String)
    case noExtractLine(String)
    case column(String, line: Int, value: String)
    case stale(fixture: UInt32, extract: UInt32)

    var description: String {
      switch self {
      case .missing(let path):
        return "the probe fixture is missing: \(path)\nIt is committed at"
          + " testdata/stations/nearby-probes.tsv; regenerate it with"
          + "\n  cd backend && cargo test --release --lib write_the_nearby_probe_fixture -- --ignored"
      case .noColumnHeader(let path):
        return "\(path) has no `#  lat  lon  limit ...` line naming its columns"
      case .noExtractLine(let path):
        return "\(path) has no `# crc32=... count=...` line saying which extract it belongs to"
      case .column(let name, let line, let value):
        return "line \(line): column `\(name)` is not readable: „\(value)\""
      case .stale(let f, let e):
        return "the fixture belongs to extract 0x\(String(f, radix: 16)) and the asset is"
          + " 0x\(String(e, radix: 16)) — after an import both must be regenerated in one commit:"
          + "\n  cd backend && cargo test --release --lib write_the_nearby_probe_fixture -- --ignored"
      }
    }
  }

  static func load(_ url: URL, against t: StationExtract) throws -> File {
    // Asserted, never skipped. A parity test that skips when its fixture is absent is one nobody
    // notices has stopped running — which is the failure this whole suite exists to end.
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw Failure.missing(url.path) }

    var columns: [String: Int] = [:]
    var crc: UInt32?
    var stationCount: Int?
    var rows: [Row] = []

    for (n, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
      let line = String(raw)
      if line.isEmpty { continue }
      guard !line.hasPrefix("#") else {
        if columns.isEmpty, let named = columnNames(line) {
          for (i, name) in named.enumerated() { columns[name] = i }
        }
        if let (c, count) = extractLine(line) {
          crc = c
          stationCount = count
        }
        continue
      }
      guard !columns.isEmpty else { throw Failure.noColumnHeader(url.path) }

      let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
      func field(_ name: String) throws -> String {
        guard let i = columns[name], i < f.count else { throw Failure.column(name, line: n + 1, value: line) }
        return f[i]
      }
      func number<T: LosslessStringConvertible>(_ name: String, _ type: T.Type) throws -> T {
        let raw = try field(name)
        guard let v = T(raw) else { throw Failure.column(name, line: n + 1, value: raw) }
        return v
      }

      let ids = try field("ids")
      let complete = try field("complete").lowercased()
      // `1`/`0` today, `true`/`false` in an earlier revision of the generator. Both, so a
      // regeneration in the other spelling cannot break this run.
      guard ["1", "0", "true", "false"].contains(complete) else {
        throw Failure.column("complete", line: n + 1, value: complete)
      }
      rows.append(Row(
        lat: try number("lat", Double.self),
        lon: try number("lon", Double.self),
        limit: try number("limit", Int.self),
        radius: try number("search_radius_m", Int.self),
        complete: complete == "1" || complete == "true",
        // Empty when nothing is near, which is a real answer and not a missing field.
        ids: ids.isEmpty ? [] : try ids.split(separator: ",").map { piece in
          guard let v = UInt32(piece) else { throw Failure.column("ids", line: n + 1, value: ids) }
          return v
        },
        label: columns["label"].flatMap { $0 < f.count ? f[$0] : nil } ?? ""))
    }

    guard !columns.isEmpty else { throw Failure.noColumnHeader(url.path) }
    guard let crc = crc, let stationCount = stationCount else { throw Failure.noExtractLine(url.path) }
    guard crc == t.crc32 else { throw Failure.stale(fixture: crc, extract: t.crc32) }
    return File(crc32: crc, stationCount: stationCount, rows: rows)
  }

  /// The column line, found by what it contains rather than by where it sits — it is neither the
  /// first comment nor the last. A prose line that happens to mention a column name is rejected by
  /// the identifier test: prose carries backticks, commas and capitals, and a name line does not.
  private static func columnNames(_ line: String) -> [String]? {
    let tokens = line.dropFirst().split(whereSeparator: \.isWhitespace).map(String.init)
    guard tokens.allSatisfy({ token in
      token.allSatisfy { $0.isLowercase && $0.isASCII || $0 == "_" || $0.isNumber }
    }) else { return nil }
    guard required.allSatisfy(tokens.contains) else { return nil }
    return tokens
  }

  /// `# crc32=0xb04add01 count=7604`. The radix comes from the prefix, so either spelling parses
  /// and the assertion is on the value — `stellwerk` prints hex for a human and `latest.json`
  /// carries decimal for a program, and this file has been written both ways.
  private static func extractLine(_ line: String) -> (UInt32, Int)? {
    var crc: UInt32?
    var count: Int?
    for token in line.dropFirst().split(whereSeparator: \.isWhitespace) {
      let parts = token.split(separator: "=", maxSplits: 1)
      guard parts.count == 2 else { continue }
      let value = parts[1]
      switch parts[0] {
      case "crc32":
        crc = value.hasPrefix("0x") || value.hasPrefix("0X")
          ? UInt32(value.dropFirst(2), radix: 16)
          : UInt32(value, radix: 10)
      case "count":
        count = Int(value)
      default:
        continue
      }
    }
    guard let crc = crc, let count = count else { return nil }
    return (crc, count)
  }
}

// MARK: - A comparator that can be broken on purpose

/// `Index::nearby`'s ordering, reimplemented so one step at a time can be got wrong.
///
/// It exists to measure the **fixture**, not the reader: with `.none` it must agree with
/// `StationExtract.nearby` on every row, and each fault then says how many rows that bug moves. A
/// fixture of easy probes would pass every ordering bug there is, and the counts are what proves
/// this one does not.
enum Ordering {
  enum Fault { case none, band250, rankInverted, nameFlagIgnored, tieBreakReversed }

  static func answer(_ t: StationExtract, _ fault: Fault, lat: Double, lon: Double, limit: Int)
    -> (ids: [UInt32], radius: Int, complete: Bool)
  {
    var hits: [(i: Int, d: Int)] = []
    for i in 0..<t.count {
      let d = GeofenceRules.haversineM(lat, lon, t.lat(at: i), t.lon(at: i))
      if d <= GeofenceRules.nearbyMaxM { hits.append((i, Int(d.rounded()))) }
    }
    hits.sort { $0.d != $1.d ? $0.d < $1.d : $0.i < $1.i }
    if hits.count > limit { hits.removeSubrange(limit...) }
    let radius = hits.last?.d ?? 0

    let band = fault == .band250 ? 250 : GeofenceRules.rankBandM
    func key(_ h: (i: Int, d: Int)) -> (Int, Int, Int, Int, Int) {
      (h.d / band,
       fault == .rankInverted ? Int(t.rank(at: h.i)) : -Int(t.rank(at: h.i)),
       fault == .nameFlagIgnored ? 0 : (t.looksLikeStation(at: h.i) ? 0 : 1),
       h.d,
       fault == .tieBreakReversed ? -h.i : h.i)
    }
    hits.sort { key($0) < key($1) }
    return (hits.map { t.id(at: $0.i) }, radius, !hits.isEmpty)
  }
}
