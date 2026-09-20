import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// The extract on the website (issue #39).
///
/// No token, no coordinates, no query string, and deliberately not `ApiClient`: publishing the
/// file on the site vhost only means anything if the request carries no identity, and
/// `ApiClient._headers` (app/lib/api/client.dart:39) attaches a bearer to everything it sends.
/// The site vhost has a `log_skip` for this path; the API vhost logs every request with its IP.
///
/// Two requests, at most once a week: the pointer, then — only when it names a version this phone
/// does not hold — the extract itself.
class StationDownload {
  StationDownload({http.Client? inner}) : _inner = inner ?? http.Client();

  final http.Client _inner;

  /// `--dart-define=SITE_URL`. The website host, not `API_URL`. Dev passes nothing: the default
  /// is the production website, which costs one unauthenticated conditional GET a week.
  static const String siteUrl = String.fromEnvironment('SITE_URL', defaultValue: 'https://verspaetomat.de');

  /// What a phone reads to find out whether it is holding the newest extract, without downloading
  /// 274 kB to find out.
  static const String pointerPath = '/stations/latest.json';

  static const Duration timeout = Duration(seconds: 30);

  /// The pointer, or why there is none.
  ///
  /// [etag] is replayed **exactly as it was received**, and with the same `Accept-Encoding` it was
  /// received under. An ETag belongs to an encoding, not to a file: Caddy hands out a different
  /// one for the compressed and the plain body, and replaying one under the wrong encoding gets a
  /// 200 with the whole file instead of a 304 with nothing. Nothing here sets `Accept-Encoding`,
  /// so every request this class makes carries the platform's default and the pair stays
  /// consistent — which is the reason not to start setting it.
  Future<StationPointerResult> fetchPointer({String? etag}) async {
    try {
      final res = await _inner.get(
        Uri.parse('$siteUrl$pointerPath'),
        headers: {
          'accept': 'application/json',
          if (etag != null) 'if-none-match': etag,
        },
      ).timeout(timeout);
      if (res.statusCode == 304) return const StationPointerNotModified();
      if (!_isOk(res.statusCode)) return StationDownloadFailed('${res.statusCode}');
      final pointer = StationPointer.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
      if (pointer == null) return const StationDownloadFailed('latest.json is not a pointer');
      return StationPointerFresh(pointer: pointer, etag: res.headers['etag']);
    } catch (e) {
      return StationDownloadFailed(_short(e));
    }
  }

  /// The extract named by a pointer. [url] is site-root-relative, so the host stays the app's
  /// business and a staging site works unchanged.
  ///
  /// The bytes are returned as they arrived. They may still be gzipped — Caddy's
  /// `precompressed gzip` serves the `.vst.gz` sibling — or already decoded by the HTTP client,
  /// and `StationExtract.decode` sniffs for that rather than trusting a header.
  ///
  /// Nothing here checks `Content-Length` against the pointer's `bytes`: measured against the
  /// deployed Caddy, `Content-Length` is 147,232 for the compressed body and 280,244 for the
  /// plain one, so the two are not comparable. The size is checked after decompression, in
  /// [StationStore], together with the checksum.
  Future<StationDownloadResult> fetchExtract(String url) async {
    try {
      final res = await _inner.get(
        Uri.parse('$siteUrl$url'),
        headers: const {'accept': 'application/octet-stream'},
      ).timeout(timeout);
      if (!_isOk(res.statusCode)) return StationDownloadFailed('${res.statusCode}');
      return StationDownloadFresh(res.bodyBytes);
    } catch (e) {
      return StationDownloadFailed(_short(e));
    }
  }

  /// 200, and 206 because the real server answers with one.
  ///
  /// Measured against the deployed Caddy 2.10.2: a request with no `Range` header at all comes
  /// back `206 Partial Content` with `Content-Range: bytes 0-147231/147232` — the whole file —
  /// because that is what `file_server`'s `precompressed` does when it serves the `.gz` sibling.
  /// `dart:io` sends `Accept-Encoding: gzip` by default, so this is the **default** path and not
  /// an edge case: a client that insisted on 200 would reject every real download and fall back
  /// to the bundled asset forever.
  ///
  /// Taking the body on trust is safe because nothing trusts it: [StationStore] decodes it,
  /// verifies the CRC over the whole body, and checks the version, the count and the decompressed
  /// length against the pointer before anything is written.
  static bool _isOk(int status) => status == 200 || status == 206;

  void close() => _inner.close();

  static String _short(Object e) => e is TimeoutException ? 'timeout' : e.toString().split('\n').first;
}

/// `site/static/stations/latest.json` (05-VERIFY §5.3), as the CLI writes it.
class StationPointer {
  const StationPointer({
    required this.version,
    required this.format,
    required this.count,
    required this.bytes,
    required this.crc32,
    required this.url,
    this.generated,
    this.feedVersion,
  });

  final int version;
  final int format;
  final int count;

  /// The size of the **uncompressed** `.vst`. Not comparable to `Content-Length`, which is the
  /// compressed size whenever Caddy serves the `.gz` sibling.
  final int bytes;
  final int crc32;

  /// Site-root-relative, e.g. `/stations/stations-12.vst`.
  final String url;
  final String? generated;

  /// The Fahrplanstand behind the import. An opaque string; nobody parses it.
  final String? feedVersion;

  static StationPointer? fromJson(Object? j) {
    if (j is! Map) return null;
    final version = j['version'];
    final url = j['url'];
    if (version is! num || url is! String || url.isEmpty) return null;
    // A pointer whose url leaves the site would turn a published file into an open redirect for
    // 280 kB of bytes this phone then trusts.
    if (!url.startsWith('/')) return null;
    return StationPointer(
      version: version.toInt(),
      format: (j['format'] as num?)?.toInt() ?? 0,
      count: (j['count'] as num?)?.toInt() ?? 0,
      bytes: (j['bytes'] as num?)?.toInt() ?? 0,
      crc32: (j['crc32'] as num?)?.toInt() ?? 0,
      url: url,
      generated: j['generated'] as String?,
      feedVersion: j['feed_version'] as String?,
    );
  }
}

sealed class StationPointerResult {
  const StationPointerResult();
}

sealed class StationDownloadResult {
  const StationDownloadResult();
}

class StationPointerFresh extends StationPointerResult {
  const StationPointerFresh({required this.pointer, this.etag});
  final StationPointer pointer;
  final String? etag;
}

class StationPointerNotModified extends StationPointerResult {
  const StationPointerNotModified();
}

class StationDownloadFresh extends StationDownloadResult {
  const StationDownloadFresh(this.bytes);
  final Uint8List bytes;
}

/// The one failure both requests share: nothing was learned, and the extract in hand stands.
class StationDownloadFailed extends StationPointerResult implements StationDownloadResult {
  const StationDownloadFailed(this.reason);
  final String reason;
}
