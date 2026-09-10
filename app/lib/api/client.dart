import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'token_store.dart';

class ApiException implements Exception {
  const ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => 'ApiException($status): $message';
}

/// Typed client for the Verspätomat API. One method per endpoint.
class ApiClient {
  ApiClient({required this.baseUrl, required this.tokens, http.Client? inner}) : _http = inner ?? http.Client();

  final String baseUrl;
  final TokenStore tokens;
  final http.Client _http;

  static const _timeout = Duration(seconds: 12);

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(path: '${base.path.replaceAll(RegExp(r'/$'), '')}$path', queryParameters: query == null || query.isEmpty ? null : query);
  }

  /// Set by the session: resolves once the device is registered. Requests that start
  /// before that (the Bahnsteig loads on its first frame) wait instead of going out
  /// without a token and failing with 401.
  Future<void> Function()? awaitDevice;

  Future<Map<String, String>> _headers({bool json = true}) async {
    var t = await tokens.token();
    if (t == null && awaitDevice != null) {
      await awaitDevice!().timeout(const Duration(seconds: 12), onTimeout: () {});
      t = await tokens.token();
    }
    return {
      if (json) 'content-type': 'application/json',
      'accept': 'application/json',
      if (t != null) 'authorization': 'Bearer $t',
    };
  }

  dynamic _decode(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (r.body.isEmpty) return null;
      return jsonDecode(utf8.decode(r.bodyBytes));
    }
    String msg = r.reasonPhrase ?? 'HTTP ${r.statusCode}';
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is Map && j['error'] != null) msg = j['error'].toString();
    } catch (_) {}
    throw ApiException(r.statusCode, msg);
  }

  /// Set by the session: called when the server answers 401 for the stored token
  /// (its database was reset, or the token belongs to another server). Replaces the
  /// device; the request is then retried once with the new token.
  Future<void> Function()? onUnauthorized;
  Future<void>? _reauth;

  Future<dynamic> _get(String path, [Map<String, String>? query]) => _retryOnce(() async {
        final r = await _http.get(_uri(path, query), headers: await _headers(json: false)).timeout(_timeout);
        return _decode(r);
      });

  Future<dynamic> _send(String method, String path, [Object? body]) => _retryOnce(() async {
        final req = http.Request(method, _uri(path))..headers.addAll(await _headers());
        if (body != null) req.body = jsonEncode(body);
        final r = await http.Response.fromStream(await _http.send(req).timeout(_timeout));
        return _decode(r);
      });

  Future<dynamic> _retryOnce(Future<dynamic> Function() attempt) async {
    try {
      return await attempt();
    } on ApiException catch (e) {
      final handler = onUnauthorized;
      if (e.status != 401 || handler == null) rethrow;
      // Concurrent 401s share one re-registration.
      _reauth ??= handler().whenComplete(() => _reauth = null);
      await _reauth;
      return await attempt();
    }
  }

  Future<dynamic> _post(String path, [Object? body]) => _send('POST', path, body ?? const {});
  Future<dynamic> _patch(String path, Object body) => _send('PATCH', path, body);
  Future<dynamic> _put(String path, Object body) => _send('PUT', path, body);
  Future<dynamic> _delete(String path) => _send('DELETE', path);

  Map<String, dynamic> _map(dynamic v) => (v as Map).cast<String, dynamic>();
  List<Map<String, dynamic>> _list(dynamic v) => (v as List).map((e) => (e as Map).cast<String, dynamic>()).toList();

  // -- health / auth --------------------------------------------------------

  Future<bool> health() async {
    try {
      final j = await _get('/health');
      return j is Map && j['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<DeviceAuth> createDevice() async => DeviceAuth.fromJson(_map(await _post('/v1/devices', {})));

  Future<DeviceAuth> recoverDevice(String recoveryCode) async =>
      DeviceAuth.fromJson(_map(await _post('/v1/devices/recover', {'recovery_code': recoveryCode})));

  Future<String> recoveryCode() async => _map(await _get('/v1/me/recovery-code'))['recovery_code'].toString();

  // -- reference ------------------------------------------------------------

  Future<ApiNearby> stationsNearby({double? lat, double? lon}) async => ApiNearby.fromJson(await _get('/v1/stations/nearby', {
        if (lat != null) 'lat': '$lat',
        if (lon != null) 'lon': '$lon',
      }));

  Future<List<ApiStation>> stationsSearch(String q) async => _list(await _get('/v1/stations/search', {'q': q})).map(ApiStation.fromJson).toList();

  Future<List<ApiDeparture>> departures(String stationId) async =>
      _list(await _get('/v1/stations/${Uri.encodeComponent(stationId)}/departures')).map(ApiDeparture.fromJson).toList();

  Future<ApiTrip> trip(String tripId) async => ApiTrip.fromJson(_map(await _get('/v1/trips', {'trip_id': tripId})));

  Future<List<ApiOperator>> operators() async => _list(await _get('/v1/operators')).map(ApiOperator.fromJson).toList();

  Future<List<ApiNgo>> ngos() async => _list(await _get('/v1/ngos')).map(ApiNgo.fromJson).toList();

  Future<List<ApiBadge>> badges() async => _list(await _get('/v1/badges')).map(ApiBadge.fromJson).toList();

  // -- customer -------------------------------------------------------------

  Future<ApiCustomer> me() async => ApiCustomer.fromJson(_map(await _get('/v1/me')));

  Future<ApiCustomer> patchMe(MePatch p) async => ApiCustomer.fromJson(_map(await _patch('/v1/me', p.toJson())));
  Future<ApiGeofence> geofence() async => ApiGeofence.fromJson(_map(await _get('/v1/me/geofence')));

  Future<ApiCustomer> putPersonalData(ApiPersonalData d) async => ApiCustomer.fromJson(_map(await _put('/v1/me/personal-data', d.toJson())));

  Future<void> deleteMe() async => _delete('/v1/me');
  Future<void> putPushToken({required String platform, required String token}) async => _put('/v1/me/push-token', {'platform': platform, 'token': token});

  Future<String> exportMe() async => jsonEncode(await _get('/v1/me/export'));

  // -- rides ----------------------------------------------------------------

  Future<List<ApiRide>> rides() async => _list(await _get('/v1/rides')).map(ApiRide.fromJson).toList();

  Future<ApiRide> checkIn(CheckInRequest r) async => ApiRide.fromJson(_map(await _post('/v1/rides', r.toJson())));

  Future<ApiRideLive?> currentRide() async {
    try {
      return ApiRideLive.fromJson(_map(await _get('/v1/rides/current')));
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<ApiArrivalResult> arrival(ArrivalRequest a) async => ApiArrivalResult.fromJson(_map(await _post('/v1/rides/current/arrival', a.toJson())));

  Future<void> dismissRide() async => _post('/v1/rides/current/dismiss');

  Future<ApiArrivalResult> nachtrag(NachtragRequest n) async => ApiArrivalResult.fromJson(_map(await _post('/v1/rides/nachtrag', n.toJson())));

  // -- ledger and claims ----------------------------------------------------

  Future<ApiIncidents> incidents() async => ApiIncidents.fromJson(_map(await _get('/v1/incidents')));

  Future<List<ApiClaim>> claims() async => _list(await _get('/v1/claims')).map(ApiClaim.fromJson).toList();

  Future<ApiClaimDraft> draftClaim({required String desk, List<String>? incidentIds}) async =>
      ApiClaimDraft.fromJson(_map(await _post('/v1/claims/draft', {'desk': desk, if (incidentIds != null) 'incident_ids': incidentIds})));

  Future<ApiClaim> patchClaim(String id, {String? ngoId, List<String>? attachmentUploadIds}) async => ApiClaim.fromJson(_map(await _patch(
        '/v1/claims/${Uri.encodeComponent(id)}',
        {if (ngoId != null) 'ngo_id': ngoId, if (attachmentUploadIds != null) 'attachments': attachmentUploadIds},
      )));

  /// The filled EU claim form as PDF (draft: unsigned; after signing: with the drawn signature).
  Future<Uint8List> claimPdf(String id) async {
    final t = await tokens.token();
    final r = await _http.get(_uri('/v1/claims/$id/pdf'), headers: {'accept': 'application/pdf', if (t != null) 'authorization': 'Bearer $t'}).timeout(const Duration(seconds: 30));
    if (r.statusCode >= 200 && r.statusCode < 300) return r.bodyBytes;
    _decode(r);
    return r.bodyBytes;
  }

  Future<ApiUpload> upload({required String kind, required String filename, required List<int> bytes}) async {
    final req = http.MultipartRequest('POST', _uri('/v1/uploads'))
      ..headers.addAll(await _headers(json: false))
      ..fields['kind'] = kind
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final r = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 30)));
    return ApiUpload.fromJson(_map(_decode(r)));
  }

  Future<ApiClaim> signClaim(String id, {required String typedName, String? signatureUploadId}) async => ApiClaim.fromJson(_map(await _post(
        '/v1/claims/${Uri.encodeComponent(id)}/sign',
        {'typed_name': typedName, if (signatureUploadId != null) 'signature_upload_id': signatureUploadId},
      )));

  Future<ApiSendResult> sendClaim(String id) async => ApiSendResult.fromJson(_map(await _post('/v1/claims/${Uri.encodeComponent(id)}/send')));

  Future<List<ApiMail>> mails() async => _list(await _get('/v1/mails')).map(ApiMail.fromJson).toList();

  Future<ApiMail> replyToMail(String id, String body) async => ApiMail.fromJson(_map(await _post('/v1/mails/${Uri.encodeComponent(id)}/reply', {'body': body})));

  /// Demo only: pretend the railway answered.
  Future<ApiInboundResult> simulateInbound({required String body, String? claimId, String? relayAddress}) async =>
      ApiInboundResult.fromJson(_map(await _post('/internal/inbound-mail', {
        'to': relayAddress ?? '',
        'from': 'Servicecenter Fahrgastrechte <fahrgastrechte@deutschebahn.com>',
        'subject': 'Ihr Antrag auf Entschädigung',
        'body': body,
        if (claimId != null) 'claim_id': claimId,
      })));

  // -- community ------------------------------------------------------------

  Future<ApiCommunity> community() async => ApiCommunity.fromJson(_map(await _get('/v1/community')));

  Future<List<ApiBoardEntry>> boards(String scope) async => _list(await _get('/v1/boards', {'scope': scope})).map(ApiBoardEntry.fromJson).toList();

}
