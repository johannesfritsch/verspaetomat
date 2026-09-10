import 'dart:async';

import '../api/events.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/client.dart';
import '../api/token_store.dart';
import '../state/demo_state.dart';
import 'app_repository.dart';
import 'http_repository.dart';
import 'mock_repository.dart';

enum BackendMode { demo, local }

extension BackendModeX on BackendMode {
  String get label => switch (this) {
        BackendMode.demo => 'Demo (eingebaut)',
        BackendMode.local => 'Lokal (API_URL)',
      };
}

/// The session: which backend is active, who the customer is, and the
/// small amount of shared state screens need (NGOs, health).
class Session extends ChangeNotifier {
  Session({required this.demo, required this.prefs, required this.apiUrl, TokenStore? tokens})
      // One keychain slot per API host: a build pointed at the local backend and one pointed at
      // the server keep separate device tokens instead of invalidating each other.
      : tokens = tokens ?? TokenStore(namespace: _namespaceFor(apiUrl)) {
    _mock = MockRepository(demo);
    _http = HttpRepository(client: ApiClient(baseUrl: apiUrl, tokens: this.tokens), tokens: this.tokens);
    demo.addListener(_onDemoChanged);
  }

  static const _modeKey = 'verspaetomat.backend_mode';

  final DemoState demo;
  final SharedPreferences prefs;
  final String apiUrl;
  final TokenStore tokens;

  late final MockRepository _mock;
  late final HttpRepository _http;

  BackendMode mode = BackendMode.demo;
  ApiCustomer? me;
  List<ApiNgo> ngos = const [];
  bool? healthy;
  String? error;
  bool busy = false;

  EventStream? _events;
  final _eventsOut = StreamController<AppEvent>.broadcast();

  /// Live events from the backend (local mode). Screens refresh what an event names.
  Stream<AppEvent> get events => _eventsOut.stream;
  bool get eventsConnected => _events?.connected ?? false;

  AppRepository get repo => mode == BackendMode.local ? _http : _mock;
  bool get isLocal => mode == BackendMode.local;

  Future<void> init() async {
    final stored = prefs.getString(_modeKey);
    const forced = String.fromEnvironment('BACKEND', defaultValue: '');
    // A release build talks to the real backend unless the person switched to Demo in
    // Einstellungen; debug builds keep Demo as the default so the showcase runs without a server.
    final local = forced == 'local' || (forced.isEmpty && stored == 'local') || (forced.isEmpty && stored == null && kReleaseMode);
    mode = local ? BackendMode.local : BackendMode.demo;
    await _bootstrap();
    if (me?.settings.onboardingDone == true) await prefs.setBool(onboardingDoneKey, true);
  }

  /// The local dev backend keeps the original, unprefixed slot so existing dev accounts survive.
  static String _namespaceFor(String apiUrl) {
    final host = Uri.tryParse(apiUrl)?.host ?? '';
    if (host.isEmpty || host == '127.0.0.1' || host == 'localhost') return '';
    return '$host.';
  }

  /// Local mirror of `me.settings.onboardingDone`, so the first frame can pick the
  /// start screen before the network answers.
  static const onboardingDoneKey = 'onboarding_done';

  Future<void> _restartEvents() async {
    _events?.dispose();
    _events = null;
    if (!isLocal || healthy != true) return;
    final t = await tokens.token();
    if (t == null) return;
    final es = EventStream(baseUrl: apiUrl, token: () => t);
    es.events.listen((e) async {
      _eventsOut.add(e);
      if (e.kind == 'reset' || e.kind == 'clock') {
        try {
          me = await repo.getMe();
          notifyListeners();
        } catch (_) {}
      }
    });
    es.start();
    _events = es;
  }

  Future<void> switchMode(BackendMode m) async {
    if (m == mode) return;
    mode = m;
    await prefs.setString(_modeKey, m == BackendMode.local ? 'local' : 'demo');
    await _bootstrap();
  }

  Future<void> _bootstrap() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (isLocal) {
        healthy = await _http.health().timeout(const Duration(seconds: 6), onTimeout: () => false);
        if (healthy == true) {
          await _http.ensureDevice();
        } else {
          error = 'Backend nicht erreichbar unter $apiUrl';
        }
      } else {
        healthy = true;
      }
      if (healthy == true) {
        try {
          me = await repo.getMe();
        } on ApiException catch (e) {
          // The server does not know this token (its database was reset, or the token is
          // from another server): start over as a fresh device rather than stay stuck.
          if (e.status != 401 || !isLocal) rethrow;
          await tokens.clear();
          await _http.ensureDevice();
          me = await repo.getMe();
        }
        ngos = await repo.ngos();
      }
      await _restartEvents();
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _onDemoChanged() {
    if (isLocal) return;
    // Cheap and synchronous underneath: keep `me` in step with DemoState.
    _mock.getMe().then((m) {
      me = m;
      notifyListeners();
    });
  }

  Future<void> refresh() async {
    try {
      me = await repo.getMe();
      ngos = await repo.ngos();
      error = null;
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  Future<void> checkHealth() async {
    healthy = await repo.health();
    notifyListeners();
  }

  Future<void> updateSettings(MePatch patch) async {
    try {
      me = await repo.patchMe(patch);
      error = null;
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    await prefs.setBool(onboardingDoneKey, true);
    await updateSettings(const MePatch(onboardingDone: true));
  }

  /// Stumme Bahnhöfe live on the account. Full replacement each time.
  List<ApiMutedStation> get mutedStations => me?.settings.mutedStations ?? const [];
  bool isMuted(String stationId) => mutedStations.any((m) => m.id == stationId);

  Future<void> muteStation(ApiMutedStation station) async {
    if (isMuted(station.id)) return;
    await updateSettings(MePatch(mutedStations: [...mutedStations, station]));
  }

  Future<void> unmuteStation(String stationId) async {
    await updateSettings(MePatch(mutedStations: mutedStations.where((m) => m.id != stationId).toList()));
  }

  Future<void> savePersonalData(ApiPersonalData data) async {
    try {
      me = await repo.putPersonalData(data);
      error = null;
      // A customer who never picked a name goes by their first name from now on.
      final nick = me?.nickname.trim() ?? '';
      final first = data.name.trim().split(RegExp(r'\s+')).first;
      if ((nick.isEmpty || nick == 'Fahrgast') && first.isNotEmpty) {
        me = await repo.patchMe(MePatch(nickname: first));
      }
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  Future<String?> recoveryCode() async {
    try {
      return await repo.recoveryCode();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> deleteEverything() async {
    try {
      await repo.deleteMe();
      if (isLocal) {
        await _http.ensureDevice();
      }
      me = await repo.getMe();
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _events?.dispose();
    _eventsOut.close();
    demo.removeListener(_onDemoChanged);
    super.dispose();
  }
}

/// Makes the [Session] available. Rebuilds dependents when it changes.
class RepoScope extends InheritedNotifier<Session> {
  const RepoScope({super.key, required Session session, required super.child}) : super(notifier: session);

  static Session of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RepoScope>();
    assert(scope != null, 'RepoScope missing above this context');
    return scope!.notifier!;
  }

  static Session read(BuildContext context) => context.getInheritedWidgetOfExactType<RepoScope>()!.notifier!;
}
