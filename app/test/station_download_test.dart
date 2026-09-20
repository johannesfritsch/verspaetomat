import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:verspaetomat/stations/station_download.dart';

import 'support/vst_fixture.dart';

/// What the phone puts on the wire when it asks the website for a newer table.
///
/// The whole point of publishing the extract on the site vhost is that the request carries no
/// identity — so these assertions are about the *absence* of headers, not about the answer.
void main() {
  const pointerJson = {
    'version': 13,
    'format': 1,
    'count': 7604,
    'bytes': 280244,
    'crc32': 2431586217,
    'generated': '2026-09-12T15:06:17Z',
    'feed_version': '2026-09-12T15:06:17',
    'url': '/stations/stations-13.vst',
  };

  late List<http.Request> seen;

  http.Client clientThat(http.Response Function(http.Request r) answer) {
    seen = [];
    return MockClient((r) async {
      seen.add(r);
      return answer(r);
    });
  }

  test('the pointer request goes to the website and carries nothing about the phone', () async {
    final d = StationDownload(
      inner: clientThat((_) => http.Response(jsonEncode(pointerJson), 200, headers: {'etag': '"abc-gzip"'})),
    );
    final res = await d.fetchPointer();
    expect(res, isA<StationPointerFresh>());

    final r = seen.single;
    expect(r.url.toString(), '${StationDownload.siteUrl}/stations/latest.json');
    expect(r.url.host, Uri.parse(StationDownload.siteUrl).host);
    expect(r.url.query, isEmpty, reason: 'no query string at all: not a version, not a coordinate');
    final keys = r.headers.keys.map((k) => k.toLowerCase()).toSet();
    expect(keys, isNot(contains('authorization')));
    expect(keys, isNot(contains('cookie')));
    expect(keys.any((k) => k.contains('token') || k.contains('device')), isFalse);
    expect(r.url.queryParameters, isEmpty, reason: 'no lat, no lon, no version, nothing');
  });

  test('the pointer is read as the CLI writes it', () async {
    final d = StationDownload(inner: clientThat((_) => http.Response(jsonEncode(pointerJson), 200, headers: {'etag': '"xyz"'})));
    final res = await d.fetchPointer() as StationPointerFresh;
    expect(res.pointer.version, 13);
    expect(res.pointer.format, 1);
    expect(res.pointer.count, 7604);
    expect(res.pointer.bytes, 280244);
    expect(res.pointer.crc32, 2431586217);
    expect(res.pointer.url, '/stations/stations-13.vst');
    expect(res.pointer.feedVersion, '2026-09-12T15:06:17');
    expect(res.etag, '"xyz"');
  });

  test('the stored etag is replayed exactly as it was received', () async {
    // Caddy suffixes its ETag with the encoder it used, so „"abc"" and „"abc-gzip"" are different
    // strings and only the one we were given comes back as a 304.
    final d = StationDownload(inner: clientThat((_) => http.Response('', 304)));
    final res = await d.fetchPointer(etag: '"abc-gzip"');
    expect(res, isA<StationPointerNotModified>());
    expect(seen.single.headers['if-none-match'], '"abc-gzip"');
  });

  test('no etag means no if-none-match', () async {
    final d = StationDownload(inner: clientThat((_) => http.Response(jsonEncode(pointerJson), 200)));
    await d.fetchPointer();
    expect(seen.single.headers.keys.map((k) => k.toLowerCase()), isNot(contains('if-none-match')));
  });

  test('a pointer that is not a pointer is a failure, not a crash', () async {
    for (final body in ['', 'not json', '{}', '{"version":13}', '[]']) {
      final d = StationDownload(inner: clientThat((_) => http.Response(body, 200)));
      expect(await d.fetchPointer(), isA<StationDownloadFailed>(), reason: 'for „$body"');
    }
  });

  test('a pointer whose url leaves the site is refused', () async {
    final d = StationDownload(inner: clientThat((_) => http.Response(
          jsonEncode({...pointerJson, 'url': 'https://example.invalid/stations.vst'}),
          200,
        )));
    expect(await d.fetchPointer(), isA<StationDownloadFailed>());
  });

  test('a 500 is a failure and says so', () async {
    final d = StationDownload(inner: clientThat((_) => http.Response('nope', 500)));
    final res = await d.fetchPointer();
    expect((res as StationDownloadFailed).reason, '500');
  });

  test('a network error is a failure and throws nothing', () async {
    final d = StationDownload(inner: MockClient((_) => throw const SocketException('no route to host')));
    expect(await d.fetchPointer(), isA<StationDownloadFailed>());
    expect(await d.fetchExtract('/stations/stations-13.vst'), isA<StationDownloadFailed>());
  });

  test('a timeout is a failure named timeout', () async {
    final d = StationDownload(inner: MockClient((_) => throw TimeoutException('slow')));
    expect(((await d.fetchPointer()) as StationDownloadFailed).reason, 'timeout');
  });

  test('the extract request is the pointer url on the site host, and also carries nothing', () async {
    final bytes = buildVst(kSampleStations, version: 13);
    final d = StationDownload(inner: clientThat((_) => http.Response.bytes(bytes, 200)));
    final got = await d.fetchExtract('/stations/stations-13.vst');
    expect((got as StationDownloadFresh).bytes, isA<Uint8List>());
    expect(got.bytes.length, bytes.length);

    final r = seen.single;
    expect(r.url.toString(), '${StationDownload.siteUrl}/stations/stations-13.vst');
    expect(r.url.query, isEmpty);
    expect(r.headers['accept'], 'application/octet-stream');
    expect(r.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
  });

  test('a 206 is the real server answering, not a partial download', () async {
    // Measured against the deployed Caddy 2.10.2: a request with no `Range` header comes back
    // `206 Partial Content` with `Content-Range: bytes 0-147231/147232` whenever `precompressed`
    // serves the `.gz` sibling, which is the default path because `dart:io` asks for gzip. A
    // client that insisted on 200 would reject every real download for ever.
    final bytes = buildVst(kSampleStations, version: 13);
    final d = StationDownload(inner: clientThat((_) => http.Response.bytes(bytes, 206, headers: {
          'content-range': 'bytes 0-${bytes.length - 1}/${bytes.length}',
          'content-encoding': 'gzip',
        })));
    final got = await d.fetchExtract('/stations/stations-13.vst');
    expect(got, isA<StationDownloadFresh>());
    expect((got as StationDownloadFresh).bytes.length, bytes.length);
  });

  test('a pointer may arrive as a 206 too', () async {
    final d = StationDownload(inner: clientThat((_) => http.Response(jsonEncode(pointerJson), 206)));
    expect(await d.fetchPointer(), isA<StationPointerFresh>());
  });

  test('anything else is still a failure', () async {
    for (final status in [204, 301, 400, 403, 404, 500, 503]) {
      final d = StationDownload(inner: clientThat((_) => http.Response('', status)));
      expect(await d.fetchExtract('/stations/stations-13.vst'), isA<StationDownloadFailed>(),
          reason: 'status $status');
    }
  });

  test('nothing sets Accept-Encoding, so the etag and its encoding stay a matched pair', () async {
    // An ETag belongs to an encoding: with `precompressed` there are two files and two ETags, and
    // replaying one under the other encoding gets a 200 with the whole file instead of a 304.
    // Leaving the header to the platform is what keeps every request consistent.
    final d = StationDownload(inner: clientThat((_) => http.Response(jsonEncode(pointerJson), 200)));
    await d.fetchPointer(etag: '"dlketfybpe2t35ls"');
    expect(seen.single.headers.keys.map((k) => k.toLowerCase()), isNot(contains('accept-encoding')));
    await d.fetchExtract('/stations/stations-13.vst');
    expect(seen.last.headers.keys.map((k) => k.toLowerCase()), isNot(contains('accept-encoding')));
  });

  test('SITE_URL is the website and not API_URL', () async {
    // Dev passes neither, and then the default is the production website — one unauthenticated
    // conditional GET a week, to a host that has a log_skip for the path.
    expect(StationDownload.siteUrl, isNot(contains('api.')));
    expect(StationDownload.siteUrl, startsWith('http'));
  });
}
