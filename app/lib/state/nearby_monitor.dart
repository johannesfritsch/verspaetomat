import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../api/events.dart';
import '../api/models.dart';
import '../platform/geofence.dart';
import '../repo/repo_scope.dart';
import '../screens/ride/ride_widgets.dart'
    show LocationAccess, currentPosition, locationAccess, openLocationSettings, shortError;

/// The one place that knows where the passenger is and which stations are around them
/// (docs/24 §0).
///
/// Before this, the Bahnsteig held a fix it took once and never again, and `startCheckin`
/// asked the phone a second time on its own, so Home and the Einchecken square could name
/// different stations. Everything that needs a station now reads this monitor; nothing else
/// calls [currentPosition] for one.
///
/// Owned by the tab shell exactly like `RideMonitor`, and refreshed on:
///  * start, and whenever the app returns to the foreground;
///  * a foreground position stream, once the phone has moved more than [_moveThresholdM]
///    from the last resolved fix, with [_resolveFloor] between resolves so a moving train
///    cannot spam the API;
///  * the native umbrella exit, so a card backgrounded across half of Germany is right the
///    moment it is seen again;
///  * the Stellwerk `location` event.
class NearbyMonitor extends ChangeNotifier with WidgetsBindingObserver {
  NearbyMonitor(this.session);

  final Session session;

  /// A fix older than this is not a guess we are willing to make (docs/23 §1).
  static const fixMaxAge = Duration(minutes: 5);

  /// How far the phone must move before the stations are asked for again.
  static const _moveThresholdM = 500.0;

  /// The floor between two resolves, whatever the phone reports.
  static const _resolveFloor = Duration(seconds: 60);

  /// Above this, the passenger is travelling and the card stops calling the station a fact.
  static const _movingKmh = 30.0;

  ApiLocation? position;

  /// The ranked stations for [position] (docs/23 §1), and when they were resolved.
  ApiNearby nearby = const ApiNearby(stations: [], source: 'none');
  DateTime? resolvedAt;

  /// The phone is being asked where it is right now.
  bool locating = false;
  String? error;

  /// The station picked by hand from the `Von` row, which wins over the nearest one. It is
  /// held whole, not by id, so a station found through the search survives the next resolve;
  /// it is dropped once the phone has moved away from where the choice was made.
  ApiStation? _picked;
  ApiLocation? _pickedAt;

  StreamSubscription<AppEvent>? _events;
  StreamSubscription<Position>? _positions;
  StreamSubscription<void>? _umbrella;
  Timer? _debounce;
  bool _started = false;
  bool _disposed = false;
  bool _foreground = true;
  bool _riding = false;
  bool _resolving = false;
  Completer<void>? _inFlight;
  DateTime? _lastResolveAttempt;

  /// The last two samples the stream gave us, newest first: the pair [moving] reads.
  _Sample? _sample;
  _Sample? _previous;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _events = session.events.listen((e) {
      // Stellwerk moved the world: the fix we hold says nothing about it any more.
      if (e.touchesLocation) refresh(force: true);
    });
    _umbrella = Geofence.instance.onUmbrellaExit.listen((_) => refresh(force: true));
    session.addListener(_onSession);
    _listenToPosition();
    refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    _positions?.cancel();
    _umbrella?.cancel();
    _debounce?.cancel();
    session.removeListener(_onSession);
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _listenToPosition();
    if (_foreground) refresh();
  }

  /// Demo mode changes the world without events; a debounced refresh follows the session.
  void _onSession() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => refresh(force: true));
  }

  /// Home hides the card while a journey runs, so the stream is dead weight then; it is also
  /// suspended in the background, where a foreground stream would not be delivered anyway.
  set riding(bool value) {
    if (_riding == value) return;
    _riding = value;
    _listenToPosition();
    // Coming off a journey the held fix is usually from the departure station.
    if (!value) refresh();
  }

  void _listenToPosition() {
    final wanted = _foreground && !_riding && !_disposed && !_noLocation;
    if (!wanted) {
      _positions?.cancel();
      _positions = null;
      return;
    }
    if (_positions != null) return;
    try {
      _positions = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, distanceFilter: 500),
      ).listen(_onSample, onError: (_) {});
    } catch (_) {
      _positions = null;
    }
  }

  void _onSample(Position p) {
    final now = DateTime.now();
    _previous = _sample;
    _sample = _Sample(lat: p.latitude, lon: p.longitude, at: now);
    final last = position;
    final moved = last == null
        ? double.infinity
        : Geolocator.distanceBetween(last.lat, last.lon, p.latitude, p.longitude);
    final since = _lastResolveAttempt == null ? _resolveFloor : now.difference(_lastResolveAttempt!);
    if (moved < _moveThresholdM && _fixFresh) {
      // Still in the same place: the stations cannot have changed. Only the caption might.
      notifyListeners();
      return;
    }
    if (since < _resolveFloor) {
      notifyListeners();
      return;
    }
    // The stream already has a fix; resolve the stations around it without asking again.
    refresh(from: ApiLocation(lat: p.latitude, lon: p.longitude, accuracyM: p.accuracy));
  }

  /// True when the phone has been told not to ask (`--dart-define=NO_LOCATION=1`): no stream,
  /// as `currentPosition` and `locationAccess` already refuse.
  static bool get _noLocation {
    const v = String.fromEnvironment('NO_LOCATION', defaultValue: '');
    return v == '1' || v == 'true';
  }

  /// Resolves the stations. [from] skips asking the phone when the caller already has a fix;
  /// [force] resolves even when the fix we hold is still fresh.
  Future<void> refresh({ApiLocation? from, bool force = false}) async {
    // Someone is already asking: wait for that answer rather than returning an empty one,
    // so a check-in started right after launch gets the station instead of the search.
    if (_resolving) return _inFlight?.future ?? Future<void>.value();
    if (!force && from == null && _fixFresh && nearby.stations.isNotEmpty) return;
    _resolving = true;
    _inFlight = Completer<void>();
    _lastResolveAttempt = DateTime.now();
    try {
      var fix = from;
      if (fix == null && (force || !_fixFresh)) {
        locating = true;
        notifyListeners();
        fix = await currentPosition(timeout: const Duration(seconds: 5));
        locating = false;
      }
      fix ??= _fixFresh ? position : null;
      final list = await session.repo.nearbyStations(lat: fix?.lat, lon: fix?.lon);
      if (_disposed) return;
      position = fix;
      // A list that does not depend on this phone (Stellwerk, demo) is always current.
      resolvedAt = fix != null || list.independentOfFix ? DateTime.now() : null;
      nearby = list;
      // A hand-picked station is about standing somewhere, not about the list: it survives a
      // resolve in the same place and goes once the passenger has actually moved on.
      final pickedAt = _pickedAt;
      if (_picked != null && fix != null && pickedAt != null &&
          Geolocator.distanceBetween(pickedAt.lat, pickedAt.lon, fix.lat, fix.lon) > _moveThresholdM) {
        _picked = null;
        _pickedAt = null;
      }
      error = null;
    } catch (e) {
      if (!_disposed) error = shortError(e);
    } finally {
      locating = false;
      _resolving = false;
      if (_inFlight?.isCompleted == false) _inFlight!.complete();
      _inFlight = null;
      notifyListeners();
    }
  }

  /// "Standort erlauben" (docs/23 §1): the tap always resolves to something. A permission
  /// that was never asked brings up the system dialog and then a fresh fix; one that was
  /// refused for good opens the settings, with one line saying why. The station being shown
  /// is dropped first, so the card never keeps an answer the tap was meant to replace.
  /// Returns the sentence to show, or null when it simply resolved.
  Future<String?> requestPermission() async {
    position = null;
    resolvedAt = null;
    _picked = null;
    _pickedAt = null;
    locating = true;
    notifyListeners();
    final access = await locationAccess();
    if (access == LocationAccess.denied || access == LocationAccess.serviceOff) {
      locating = false;
      notifyListeners();
      await openLocationSettings();
      await refresh(force: true);
      return access == LocationAccess.serviceOff
          ? 'Der Standort ist am Telefon ausgeschaltet. Ohne ihn wissen wir nicht, ob du an einem Bahnhof stehst.'
          : 'Der Standort ist für Verspätomat gesperrt. Ohne ihn wissen wir nicht, ob du an einem Bahnhof stehst.';
    }
    // notAsked: `currentPosition` brings the system dialog up on the way to the fix.
    await refresh(force: true);
    _listenToPosition();
    return null;
  }

  bool get _fixFresh => resolvedAt != null && DateTime.now().difference(resolvedAt!) < fixMaxAge;

  /// May a station be shown at all? Only from a list that does not depend on this phone
  /// (Stellwerk, demo) or from a fresh fix (docs/23 §1).
  bool get trustworthy => _picked != null || nearby.independentOfFix || _fixFresh;

  /// The card is waiting for the phone: no station yet, and never the last one. Only while a
  /// fix is actually in flight — a list that came back without one is the away box, not a wait.
  bool get checking => nearby.checking || (locating && !trustworthy);

  /// The station on offer: the one picked from the `Von` row, else the best one within 300 m.
  /// Null while no fix is worth trusting.
  ApiStation? get station {
    if (!trustworthy) return null;
    final picked = _picked;
    if (picked != null) {
      // The ranked list carries a live distance; prefer its copy when it still has one.
      return nearby.stations.where((x) => x.id == picked.id).firstOrNull ?? picked;
    }
    if (nearby.none || nearby.stations.isEmpty) return null;
    // The backend ranks: the first one is the best station in the nearest band (docs/23 §1).
    final s = nearby.stations.first;
    final d = s.distanceM;
    return d != null && d <= 300 ? s : null;
  }

  /// The next best stations, for the `Von` step and the away box, at most [take].
  List<ApiStation> others({int take = 2}) {
    final shown = station?.id;
    return nearby.stations.where((s) => s.id != shown).take(take).toList();
  }

  /// Faster than [_movingKmh] between the last two samples: the station still updates, the
  /// caption just stops pretending it is a settled fact (docs/24 §0).
  bool get moving {
    final a = _previous;
    final b = _sample;
    if (a == null || b == null) return false;
    final seconds = b.at.difference(a.at).inMilliseconds / 1000.0;
    if (seconds < 1) return false;
    final metres = Geolocator.distanceBetween(a.lat, a.lon, b.lat, b.lon);
    return metres / seconds * 3.6 > _movingKmh;
  }

  /// The caption under the station: how far away it is, or that we are keeping up with a
  /// train rather than asserting a platform.
  String? get caption {
    if (moving) return 'Du bewegst dich · Bahnhof wird laufend geprüft';
    final d = station?.distanceM;
    if (d == null) return null;
    return 'Du bist hier · ${d < 1000 ? '$d m' : '${(d / 100).round() / 10} km'}';
  }

  /// A station chosen by hand: the card and the flow switch over at once, without asking
  /// the phone again.
  void pick(ApiStation s) {
    _picked = s;
    _pickedAt = position;
    // Chosen by hand, so it stands on its own: it needs no fix to be believed.
    resolvedAt = DateTime.now();
    notifyListeners();
  }

  /// Back to whatever the phone says.
  void clearPick() {
    if (_picked == null) return;
    _picked = null;
    _pickedAt = null;
    notifyListeners();
  }
}

class _Sample {
  const _Sample({required this.lat, required this.lon, required this.at});
  final double lat;
  final double lon;
  final DateTime at;
}

/// Hands the shell's [NearbyMonitor] to the tabs, the check-in flow and the away box.
class NearbyScope extends InheritedNotifier<NearbyMonitor> {
  const NearbyScope({super.key, required NearbyMonitor monitor, required super.child}) : super(notifier: monitor);

  static NearbyMonitor of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<NearbyScope>()!.notifier!;

  static NearbyMonitor? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<NearbyScope>()?.notifier;

  /// Without a dependency: for callbacks and tests.
  static NearbyMonitor? read(BuildContext context) => context.getInheritedWidgetOfExactType<NearbyScope>()?.notifier;
}
