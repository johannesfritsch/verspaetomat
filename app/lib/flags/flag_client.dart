import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// The flag document, fetched (issue #41).
///
/// **No token, and deliberately not `ApiClient`.** `ApiClient._headers` (app/lib/api/client.dart:39)
/// attaches a bearer to everything it sends, and an authenticated request costs a Postgres *write*
/// on this backend: the `Customer` extractor runs an unconditional
/// `update devices set last_seen_at = now()` per request (backend/src/auth.rs:113) through a pool
/// capped at eight connections (backend/src/db/mod.rs:11). A flag read is the most frequent thing
/// this app could possibly do, so it is the one request that must not be a write. Unauthenticated,
/// it is a pre-rendered string out of the server's memory: no query, no write, no customer id.
///
/// The same reasoning is written out for the station extract at
/// app/lib/stations/station_download.dart:9 — this is the second thing in the app that reads
/// something public and must do it anonymously.
///
/// Subclass it to answer from canned bytes; every test does, so no test opens a socket.
class FlagClient {
  FlagClient({required this.baseUrl, http.Client? inner}) : _inner = inner ?? http.Client();

  final http.Client _inner;

  /// Where the document lives. `--dart-define=FLAGS_URL` moves it; it defaults to `API_URL`, so
  /// dev, the E2E and production all drive the same path with the same command, and
  /// `stellwerk flag …` against the local backend changes what the simulator reads.
  final String baseUrl;

  static const String path = '/v1/flags.json';

  /// Short on purpose. Nothing waits on this call — it is always started with `unawaited` — but a
  /// socket that hangs for a minute holds an `http.Client` open behind a slow proxy for no reason.
  static const Duration timeout = Duration(seconds: 10);

  /// A conditional GET. [etag] is replayed **exactly as it was received** and nothing here sets
  /// `Accept-Encoding`, for the reason written out at station_download.dart:33 — an ETag belongs
  /// to an encoding, and Caddy hands out a different one for the compressed and the plain body.
  Future<FlagFetchResult> fetch({String? etag}) async {
    try {
      final res = await _inner.get(
        Uri.parse('${baseUrl.replaceAll(RegExp(r'/$'), '')}$path'),
        headers: {
          'accept': 'application/json',
          if (etag != null && etag.isNotEmpty) 'if-none-match': etag,
        },
      ).timeout(timeout);
      if (res.statusCode == 304) return const FlagFetchNotModified();
      if (res.statusCode != 200) return FlagFetchFailed('${res.statusCode}');
      return FlagFetchFresh(body: utf8.decode(res.bodyBytes), etag: res.headers['etag']);
    } catch (e) {
      return FlagFetchFailed(_short(e));
    }
  }

  void close() => _inner.close();

  static String _short(Object e) => e is TimeoutException ? 'timeout' : e.toString().split('\n').first;
}

sealed class FlagFetchResult {
  const FlagFetchResult();
}

/// A document to read. The body is unparsed: [FlagDoc.parse] decides whether it is one.
class FlagFetchFresh extends FlagFetchResult {
  const FlagFetchFresh({required this.body, this.etag});
  final String body;
  final String? etag;
}

/// The server confirmed what this phone already holds — the answer nearly every check gets, and
/// the reason the steady cost of this whole system is a few bytes of headers.
class FlagFetchNotModified extends FlagFetchResult {
  const FlagFetchNotModified();
}

/// Nothing was learned. Whatever the phone holds still stands — a failed call is not an answer.
class FlagFetchFailed extends FlagFetchResult {
  const FlagFetchFailed(this.reason);
  final String reason;
}
