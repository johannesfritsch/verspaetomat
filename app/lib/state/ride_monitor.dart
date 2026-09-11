import 'dart:async';

import 'package:flutter/material.dart';

import '../api/events.dart';
import '../api/models.dart';
import '../repo/app_repository.dart';
import '../repo/repo_scope.dart';
import '../screens/ride/ride_widgets.dart' show fromIndex, shortError;

/// The one place that knows whether a journey is under way (docs/19).
///
/// Owned by the tab shell, read by the persistent bar, the ride sheet and the Bahnsteig,
/// so the ride is polled once, not per screen. Loads on start, on `ride`/`journey` events,
/// on app resume and on account changes; polls every 20 s while riding or in transfer.
class RideMonitor extends ChangeNotifier with WidgetsBindingObserver {
  RideMonitor(this.session);

  final Session session;

  ApiJourneyLive? journey;
  ApiRideLive? live;
  bool loading = true;
  bool busy = false;
  bool stale = false;
  DateTime? stamp;
  String? error;

  /// The sheet's presentation state. The bar is shown only while this is false.
  bool sheetOpen = false;

  /// Controls the draggable sheet; attached only while the sheet is in the tree.
  final DraggableScrollableController sheetController = DraggableScrollableController();

  StreamSubscription<AppEvent>? _events;
  Timer? _poll;
  Timer? _debounce;
  bool _started = false;
  bool _wasActive = false;
  bool _disposed = false;

  bool get transfer => journey?.journey.inTransfer == true;
  bool get riding => !transfer && (journey?.journey.riding == true || live?.ride.status == ApiRideStatus.riding);
  bool get arrived => !transfer && !riding && (journey?.journey.arrived == true || live?.ride.status == ApiRideStatus.arrived);

  /// Riding or waiting at a transfer: the bar and the sheet have something to show.
  bool get active => riding || transfer;

  /// Three hours past the planned arrival and still open (docs/23 §3). The backend decides
  /// when that is; the bar turns into the question. Not to be confused with [stale], which
  /// says the last refresh failed.
  bool get overdue => active && journey?.journey.stale == true;

  /// The current leg as the ride screens consume it.
  ApiRideLive? get rideLive => live ?? journey?.asRideLive;

  /// Geduldspunkte the last aborted journey was worth (docs/22 §1); 0 after an arrival.
  int lastAbandonPoints = 0;

  /// The sheet stays open on arrival and shows the reveal; this is that state.
  bool get arrivedInSheet => sheetOpen && arrived;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _events = session.events.listen((e) {
      if (e.touchesRide) refresh(quiet: true);
    });
    session.addListener(_onSession);
    refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    _poll?.cancel();
    _debounce?.cancel();
    session.removeListener(_onSession);
    if (_started) WidgetsBinding.instance.removeObserver(this);
    sheetController.dispose();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh(quiet: true);
  }

  /// Demo mode changes the world without events; a debounced refresh follows the session.
  void _onSession() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => refresh(quiet: true));
  }

  Future<void> refresh({bool quiet = false}) async {
    if (!quiet) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final repo = session.repo;
      final j = await repo.currentJourney().catchError((_) => null);
      final l = j?.asRideLive ?? await repo.currentRide();
      journey = j;
      live = l;
      stale = false;
      stamp = DateTime.now();
      error = null;
    } catch (e) {
      stale = true;
      if (journey == null && live == null) error = shortError(e);
    } finally {
      loading = false;
      // The journey ended while the sheet was closed: nothing to keep open; the bar goes.
      // While the sheet is open the body switches to the arrival on its own.
      if (_wasActive && !active && !arrived) sheetOpen = false;
      _wasActive = active;
      notifyListeners();
      _schedulePoll();
    }
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (active && !_disposed) _poll = Timer(const Duration(seconds: 20), () => refresh(quiet: true));
  }

  void openSheet() {
    if (!active && !arrived) return;
    if (sheetOpen) return;
    sheetOpen = true;
    notifyListeners();
  }

  void closeSheet() {
    if (!sheetOpen) return;
    sheetOpen = false;
    notifyListeners();
  }

  /// "Ich bin drin": the proposed next leg becomes the ride.
  Future<void> confirmLeg(ApiLeg leg) async {
    final j = journey;
    if (j == null || busy) return;
    busy = true;
    notifyListeners();
    try {
      await session.repo.confirmLeg(j.journey.id, leg.tripId);
      await refresh(quiet: true);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// "Ich bin da" / the abort with its reason (docs/21 §1); the plain arrival call on a
  /// legacy ride. Returns the arrival result for a legacy ride, null otherwise.
  Future<ApiArrivalResult?> finish({required bool arrived, String? reason}) async {
    if (busy) return null;
    busy = true;
    notifyListeners();
    try {
      final j = journey;
      if (j != null) {
        // docs/22 §1: an abandoned journey still reports the patience it earned, so the
        // closing card can name it. Arriving goes through the reveal as before.
        final done = await session.repo.finishJourney(j.journey.id, arrived: arrived, reason: reason);
        lastAbandonPoints = arrived ? 0 : done.points;
        await refresh(quiet: true);
        if (!arrived) sheetOpen = false;
        return null;
      }
      final result = await session.repo.arrival(const ArrivalRequest());
      await refresh(quiet: true);
      return result;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// "Ich fahre später weiter" (docs/21 §2): this leg ends, the journey waits for a train
  /// the passenger picks. The destination and its planned arrival stay, so the delay counts.
  Future<void> replan() async {
    final j = journey;
    if (j == null || busy) return;
    busy = true;
    notifyListeners();
    try {
      final r = j.ride;
      final stops = j.stops;
      // Where the passenger can actually get off: the next stop the train still reaches (the
      // one the sheet calls "Nächster Halt"), else the last one it passed. Never the exit
      // stop by default — on a direct journey that is the destination itself.
      final here = stops.isEmpty || r == null
          ? null
          : stops[(r.passedStops + fromIndex(stops, r.fromStationId, r.fromStationName)).clamp(0, stops.length - 1)];
      await session.repo.replanJourney(
        j.journey.id,
        fromStationId: here?.stationId ?? r?.fromStationId,
        fromStationName: here?.name ?? r?.fromStationName,
      );
      await refresh(quiet: true);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// The arrival was seen; the card and the sheet go.
  Future<void> dismiss() async {
    try {
      await session.repo.dismissRide();
    } catch (_) {}
    sheetOpen = false;
    await refresh(quiet: true);
  }
}

/// Bumped by whoever asks for the ride sheet (the `/unterwegs` redirect: a finished check-in,
/// a push, the nudge). The shell listens and opens the sheet, however the location reads.
final ValueNotifier<int> rideSheetRequests = ValueNotifier<int>(0);

void requestRideSheet() => rideSheetRequests.value++;

/// Hands the shell's [RideMonitor] to the tabs and the sheet.
class RideScope extends InheritedNotifier<RideMonitor> {
  const RideScope({super.key, required RideMonitor monitor, required super.child}) : super(notifier: monitor);

  static RideMonitor of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<RideScope>()!.notifier!;

  static RideMonitor? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<RideScope>()?.notifier;

  /// Without a dependency: for callbacks and tests.
  static RideMonitor? read(BuildContext context) => context.getInheritedWidgetOfExactType<RideScope>()?.notifier;
}
