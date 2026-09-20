import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/api/client.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/api/token_store.dart';
import 'package:verspaetomat/repo/http_repository.dart';
import 'package:verspaetomat/stations/station_download.dart';
import 'package:verspaetomat/stations/station_store.dart';

import 'support/vst_fixture.dart';

/// The ladder, from the outside: what `nearbyStations` and `searchStations` answer now.
///
/// The `ApiClient` here points at `http://127.0.0.1:1`, where nothing listens. Any rung that
/// reached the server would fail loudly instead of passing quietly.
class _NoDownload extends StationDownload {
  @override
  Future<StationPointerResult> fetchPointer({String? etag}) async => const StationDownloadFailed('no network in a unit test');
  @override
  Future<StationDownloadResult> fetchExtract(String url) async => const StationDownloadFailed('no network in a unit test');
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('vst_repo_'));
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  // Köln Hbf, a stop next to it, and a station far enough away to be its own answer.
  final table = <VstStation>[
    ...plausibleTable(count: 1200, startId: 100),
    const VstStation(2049, 'Köln Hbf', 50.9430, 6.9586, 3),
    const VstStation(2052, 'Köln Hansaring', 50.9480, 6.9500, 2),
    const VstStation(4495, 'Kißlegg Bahnhof', 47.7914, 9.8921, 2),
  ]..sort((a, b) => a.id.compareTo(b.id));

  HttpRepository repo({Uint8List? asset}) => HttpRepository(
        client: ApiClient(baseUrl: 'http://127.0.0.1:1', tokens: TokenStore()),
        tokens: TokenStore(),
        stations: StationStore(
          download: _NoDownload(),
          directory: () async => tmp,
          asset: () async => asset ?? buildVst(table, version: 12),
        ),
      );

  test('the default is closed: no define, no server rung', () {
    // This is also the proof that a release build cannot reach the endpoints — the constant is
    // `!kReleaseMode && (…)`, and under `flutter test` neither define is set.
    expect(HttpRepository.allowServerStations, isFalse);
  });

  test('with a fix, the answer is local and says gps', () async {
    final r = repo();
    final near = await r.nearbyStations(lat: 50.9430, lon: 6.9586);
    expect(near.source, 'gps');
    expect(near.stations.first.id, 'vs:2049');
    expect(near.stations.first.name, 'Köln Hbf');
    expect(near.stations.first.distanceM, 0);
    expect(near.complete, isTrue);
    expect(near.searchRadiusM, greaterThan(0));
  });

  test('no fix and no override is the nothing the server answered (handlers.rs:73)', () async {
    final near = await repo().nearbyStations();
    expect(near.source, 'none');
    expect(near.stations, isEmpty);
    expect(near.none, isTrue);
    expect(near.complete, isFalse);
  });

  test('a Stellwerk override answers without a fix, and names the station', () async {
    final r = repo();
    r.setSimLocation(const ApiSimLocation(lat: 50.9430, lon: 6.9586, label: 'Köln Hbf'));
    final near = await r.nearbyStations();
    expect(near.source, 'stellwerk');
    expect(near.label, 'Köln Hbf');
    expect(near.simulated, isTrue);
    expect(near.independentOfFix, isTrue);
    expect(near.stations.first.id, 'vs:2049');
    expect(near.stations.first.distanceM, 0);
  });

  test('the override wins over the phone’s own fix, as the server did', () async {
    final r = repo();
    r.setSimLocation(const ApiSimLocation(lat: 47.7914, lon: 9.8921, label: 'Kißlegg Bahnhof'));
    final near = await r.nearbyStations(lat: 50.9430, lon: 6.9586);
    expect(near.source, 'stellwerk');
    expect(near.stations.first.name, 'Kißlegg Bahnhof');
  });

  test('clearing the override goes back to the phone', () async {
    final r = repo();
    r.setSimLocation(const ApiSimLocation(lat: 47.7914, lon: 9.8921, label: 'Kißlegg Bahnhof'));
    expect((await r.nearbyStations()).source, 'stellwerk');
    r.setSimLocation(null);
    final near = await r.nearbyStations();
    expect(near.source, 'none');
    expect(near.stations, isEmpty);
  });

  test('a search is answered from the phone', () async {
    final hits = await repo().searchStations('köln');
    expect(hits, isNotEmpty);
    expect(hits.first.name, 'Köln Hbf');
    expect(hits.first.id, 'vs:2049');
    expect(hits.first.railRank, isNull);
  });

  test('a search that finds nothing is an empty list, not a request', () async {
    expect(await repo().searchStations('zzzzzzz'), isEmpty);
  });

  group('the Stellwerk payload, as the SSE delivers it', () {
    test('a location event with coordinates becomes an override', () {
      final at = ApiSimLocation.fromJson({'lat': 50.9430, 'lon': 6.9586, 'label': 'Köln Hbf', 'source': 'stellwerk'});
      expect(at, isNotNull);
      expect(at!.lat, 50.9430);
      expect(at.lon, 6.9586);
      expect(at.label, 'Köln Hbf');
    });

    test('the clear carries no coordinates and folds to null (admin.rs:432)', () {
      expect(ApiSimLocation.fromJson({'source': 'gps'}), isNull);
      expect(ApiSimLocation.fromJson(null), isNull);
      expect(ApiSimLocation.fromJson({}), isNull);
      expect(ApiSimLocation.fromJson('nonsense'), isNull);
      expect(ApiSimLocation.fromJson({'lat': 'fifty', 'lon': 7}), isNull);
    });

    test('bare coordinates with no label are still an override', () {
      // `stellwerk locate <who> --lat … --lon …` leaves the label empty (admin.rs:399), and the
      // app names the station its own table found.
      final at = ApiSimLocation.fromJson({'lat': 47.7914, 'lon': 9.8921});
      expect(at, isNotNull);
      expect(at!.label, '');
    });
  });

  test('with no extract at all, the answers are empty rather than a server call', () async {
    final r = HttpRepository(
      client: ApiClient(baseUrl: 'http://127.0.0.1:1', tokens: TokenStore()),
      tokens: TokenStore(),
      stations: StationStore(
        download: _NoDownload(),
        directory: () async => tmp,
        asset: () async => throw const FileSystemException('no asset in this build'),
      ),
    );
    final near = await r.nearbyStations(lat: 50.9430, lon: 6.9586);
    expect(near.source, 'none');
    expect(near.stations, isEmpty);
    expect(await r.searchStations('köln'), isEmpty);
  });
}
