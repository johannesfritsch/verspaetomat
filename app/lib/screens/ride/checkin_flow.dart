import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../repo/app_repository.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../state/nearby_monitor.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart';
import 'welcher_zug_screen.dart';
import 'wohin_screen.dart';

/// The check-in, three steps, each a bottom sheet over the current tab (docs/24 §1).
///
/// Before this the source station was a fact the app asserted and the passenger could only
/// accept: when the detection was wrong there was no way through the flow at all. Now every
/// step is answerable, and each one shows what the previous settled as a breadcrumb, so any
/// of them can be reopened without starting over.
///
///  1. **Von wo?** — the detected station preselected, the next two beneath it, the stations
///     this person uses most, then search.
///  2. **Wohin?** — destinations from history, then search.
///  3. **Welcher Zug?** — the itineraries, one swipe from the choice above.
///
/// It always starts at step 1, even when the detection is right: one tap on the preselected
/// station moves on, and the passenger sees what the app thinks before committing to it. Home
/// no longer offers a shortcut past it (docs/30) — one question, asked in one place.
///
/// **This is the only way into a check-in.** Every entry point comes here: the square, a station
/// nudge, Home's Einchecken button. Before docs/29 there were three different journeys — the
/// square ran these sheets while a nudge and the Home card still ran the train-first board from
/// before docs/17, so the same station could offer different trains depending on which button
/// you pressed.
///
/// [from] skips step 1 (a nudge knows the station); [to] skips step 2 as well (the Home card's
/// destination buttons know both, and only the train is left to choose).
Future<void> runCheckinFlow(BuildContext context, {ApiStation? from, ApiStation? to}) async {
  final near = NearbyScope.read(context);
  // A fix may still be in flight when the square is tapped right after a cold start.
  if (from == null && near != null && near.station == null) await near.refresh();
  if (!context.mounted) return;

  var source = from;
  var destination = to;
  var step = source == null
      ? 0
      : destination == null
          ? 1
          : 2;

  while (context.mounted) {
    switch (step) {
      case 0:
        final r = await showVonSheet(context, current: source);
        if (!context.mounted || r == null) return;
        if (r.back) return; // nothing above step 1: a dismissal is a dismissal
        source = r.value;
        step = 1;
      case 1:
        final r = await showWohinSheet(context, from: source!);
        if (!context.mounted || r == null) return;
        if (r.back) {
          step = 0;
        } else {
          destination = r.value;
          step = 2;
        }
      case 2:
        final r = await showWelcherZugSheet(context, from: source!, to: destination!);
        if (!context.mounted || r == null) return;
        if (r.back) {
          step = 1;
        } else {
          return; // the journey is running; the sheet has navigated
        }
      default:
        return;
    }
  }
}

/// What a step gave back: a choice, or "reopen the step above". A null result from the sheet
/// means the passenger dismissed it, which ends the flow.
class StepResult<T> {
  const StepResult.value(this.value) : back = false;
  const StepResult.back() : value = null, back = true;
  final T? value;
  final bool back;
}

/// The breadcrumb: what an earlier step settled, tappable to reopen it (`Ab München Hbf ▾`).
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: VSpace.page, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(label, style: VText.bodySStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.expand_more, size: 18, color: VColors.ink2),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1 · Von wo?
// ---------------------------------------------------------------------------

/// The source station, asked rather than asserted. The detected one sits at the top with its
/// distance, the next two beneath it, then the search: one tap moves on, and the passenger
/// never has to type when the detection is right.
/// The monitor is resolved here, from a context under the shell: a sheet is built by the
/// Navigator, which sits *above* [NearbyScope], so a lookup inside it finds nothing.
Future<StepResult<ApiStation>?> showVonSheet(BuildContext context, {ApiStation? current}) {
  final near = NearbyScope.read(context);
  return showVSheet<StepResult<ApiStation>>(
    context,
    builder: (ctx) => _VonSheet(current: current, near: near),
  );
}

class _VonSheet extends StatefulWidget {
  const _VonSheet({this.current, this.near});
  final ApiStation? current;
  final NearbyMonitor? near;

  @override
  State<_VonSheet> createState() => _VonSheetState();
}

class _VonSheetState extends State<_VonSheet> {
  /// The stations this person checks in at most often (docs/15). They used to sit on Home as
  /// chips; the question they answer is this sheet's question, so this is where they live now.
  List<ApiGeofenceStation> _frequent = const [];
  String _homeStation = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return; // the sheet can be dismissed before the first frame lands
    final session = RepoScope.read(context);
    final g = await session.repo.geofence().catchError((_) => ApiGeofence.empty);
    if (!mounted) return;
    setState(() {
      _frequent = [...g.stations]..sort((a, b) => b.checkins.compareTo(a.checkins));
      _homeStation = session.me?.homeStation ?? '';
    });
  }

  void _pick(ApiStation s) => Navigator.of(context).pop(StepResult<ApiStation>.value(s));

  /// „Standort erlauben": without a fix this sheet can only offer history and the search, and
  /// the way out of that is a permission, not another list.
  Future<void> _locate() async {
    final message = await widget.near?.requestPermission();
    if (!mounted || message == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // The fix may land while the sheet is open; it follows the monitor rather than freezing
    // whatever was known at the moment of the tap.
    return AnimatedBuilder(
      animation: widget.near ?? const AlwaysStoppedAnimation(0),
      builder: (context, _) => _body(context, widget.current ?? widget.near?.station),
    );
  }

  Widget _body(BuildContext context, ApiStation? detected) {
    final near = widget.near;
    final others = (near?.others(take: 2) ?? const <ApiStation>[]).where((s) => s.id != detected?.id).toList();
    // The frequent ones the fix has not already named. The two lists come from different
    // sources and spell the same platform differently often enough that ids alone let
    // „Ab Kißlegg" appear twice (docs/30).
    bool listed(ApiGeofenceStation f) =>
        (detected != null && (f.id == detected.id || sameStation(f.name, detected.name))) ||
        others.any((s) => s.id == f.id || sameStation(s.name, f.name));
    final frequent = _frequent.where((f) => !listed(f)).take(3).toList();
    final nothingKnown = detected == null && others.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VSheetHeader(
            title: 'Von wo?',
            subtitle: near?.caption ?? 'Wähle den Bahnhof, an dem du stehst.',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (detected != null)
                  VListRow(
                    key: const Key('von-detected'),
                    title: detected.name,
                    subtitle: detected.distanceM == null ? null : _dist(detected.distanceM!),
                    chevron: true,
                    onTap: () => _pick(detected),
                  ),
                for (final s in others)
                  VListRow(
                    title: s.name,
                    subtitle: s.distanceM == null ? null : _dist(s.distanceM!),
                    chevron: true,
                    onTap: () => _pick(s),
                  ),
                if (nothingKnown)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: VSpace.s),
                    child: Text(
                      near?.checking == true
                          ? 'Wir schauen noch, wo du bist.'
                          : 'Wir wissen gerade nicht, wo du bist.',
                      style: VText.bodyS.copyWith(color: VColors.ink2),
                    ),
                  ),
                if (frequent.isNotEmpty) ...[
                  const VGap.m(),
                  const VSection('Deine Bahnhöfe'),
                  for (final f in frequent)
                    VListRow(
                      title: f.name,
                      subtitle: f.name == _homeStation ? 'Stammbahnhof' : null,
                      chevron: true,
                      onTap: () => _pick(ApiStation(id: f.id, name: f.name, lat: f.lat, lon: f.lon)),
                    ),
                ],
                const VGap.m(),
                VOutlineButton(
                  label: 'Bahnhof suchen',
                  icon: Icons.search,
                  onTap: () async {
                    final s = await showStationSearch(context);
                    if (s == null || !context.mounted) return;
                    // A station chosen by hand is where the passenger is, for everything else too.
                    near?.pick(s);
                    if (context.mounted) _pick(s);
                  },
                ),
                // Only when the phone is the missing piece: with a fix the list above is the answer.
                if (nothingKnown && near?.position == null && near?.checking != true) ...[
                  const VGap.s(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _locate,
                      child: Text('Standort erlauben', style: VText.bodySStrong.copyWith(color: VColors.red)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _dist(int m) =>
      m < 1000 ? '$m m' : '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
}

// ---------------------------------------------------------------------------
// 2 · Wohin?
// ---------------------------------------------------------------------------

/// The destination: the places this person has been to before, then the search. The exit stop
/// follows from the itinerary and is never asked (docs/17).
Future<StepResult<ApiStation>?> showWohinSheet(BuildContext context, {required ApiStation from}) {
  return showVSheet<StepResult<ApiStation>>(
    context,
    builder: (ctx) => _WohinSheet(from: from),
  );
}

class _WohinSheet extends StatefulWidget {
  const _WohinSheet({required this.from});
  final ApiStation from;

  @override
  State<_WohinSheet> createState() => _WohinSheetState();
}

class _WohinSheetState extends State<_WohinSheet> {
  ApiDestinations _dest = ApiDestinations.empty;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await RepoScope.read(context).repo.destinations(from: widget.from.id);
      if (mounted) setState(() => _dest = d);
    } catch (e) {
      if (mounted) setState(() => _error = shortError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pick(ApiStation s) => Navigator.of(context).pop(StepResult<ApiStation>.value(s));

  @override
  Widget build(BuildContext context) {
    final predicted = _dest.predicted.where((d) => d.stationId != widget.from.id).toList();
    final recent = _dest.recent
        .where((d) => d.stationId != widget.from.id && !predicted.any((p) => p.stationId == d.stationId))
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VSheetHeader(title: 'Wohin?'),
          _Breadcrumb(
            label: 'Ab ${widget.from.name}',
            onTap: () => Navigator.of(context).pop(const StepResult<ApiStation>.back()),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VGap.s(),
                if (_loading) const LoadingLine(label: 'Deine Ziele werden geladen …'),
                if (_error != null) ErrorLine(message: _error!, onRetry: _load),
                if (!_loading && predicted.isEmpty && recent.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: VSpace.m),
                    child: Text(
                      'Beim ersten Mal suchst du dein Ziel. Ab dann steht es hier.',
                      style: VText.body.copyWith(color: VColors.ink2),
                    ),
                  ),
                for (final d in predicted) ...[
                  DestinationButton(
                    destination: d,
                    primary: identical(d, predicted.first),
                    onTap: () => _pick(d.station),
                  ),
                  const VGap.s(),
                ],
                if (recent.isNotEmpty) ...[
                  const VGap.s(),
                  const VSection('Zuletzt'),
                  for (final d in recent) VListRow(title: d.stationName, chevron: true, onTap: () => _pick(d.station)),
                  const VGap.m(),
                ],
                VOutlineButton(
                  label: 'Bahnhof suchen',
                  icon: Icons.search,
                  onTap: () async {
                    final s = await showStationSearch(context);
                    if (s != null && context.mounted) _pick(s);
                  },
                ),
                const VGap.s(),
                Text('Der Ausstieg ergibt sich aus der Verbindung. Wir fragen nicht danach.', style: VText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3 · Welcher Zug?
// ---------------------------------------------------------------------------

/// The itineraries as a sheet rather than a screen, so a wrong choice above is one swipe away
/// instead of a back-navigation (docs/24 §1).
/// [continueJourneyId] makes this the Weiterfahrt (docs/21 §2) instead of a check-in: the
/// journey is already running and this confirms its next leg, with the delay ceiling from the
/// interruption still in force.
Future<StepResult<void>?> showWelcherZugSheet(
  BuildContext context, {
  required ApiStation from,
  required ApiStation to,
  String? continueJourneyId,
  DateTime? earliestOnwardArrival,
  int? countedMinutes,
}) {
  return showVSheet<StepResult<void>>(
    context,
    expand: true,
    builder: (ctx) => _WelcherZugSheet(
      from: from,
      to: to,
      continueJourneyId: continueJourneyId,
      earliestOnwardArrival: earliestOnwardArrival,
      countedMinutes: countedMinutes,
    ),
  );
}

class _WelcherZugSheet extends StatelessWidget {
  const _WelcherZugSheet({
    required this.from,
    required this.to,
    this.continueJourneyId,
    this.earliestOnwardArrival,
    this.countedMinutes,
  });
  final ApiStation from;
  final ApiStation to;
  final String? continueJourneyId;
  final DateTime? earliestOnwardArrival;
  final int? countedMinutes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VSheetHeader(
          title: 'Welcher Zug?',
          subtitle: continueJourneyId == null ? null : 'Deine Fahrt läuft weiter. Die Verspätung zählt am Ziel.',
        ),
        _Breadcrumb(
          label: '${from.name} → ${to.name}',
          onTap: () => Navigator.of(context).pop(const StepResult<void>.back()),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
            child: WelcherZugList(
              fromStationId: from.id,
              fromStationName: from.name,
              toStationId: to.id,
              toStationName: to.name,
              fromLat: from.lat,
              fromLon: from.lon,
              continueJourneyId: continueJourneyId,
              earliestOnwardArrival: earliestOnwardArrival,
              countedMinutes: countedMinutes,
              onStarted: () {
                Navigator.of(context).pop(const StepResult<void>.value(null));
                context.go(Routes.unterwegs);
              },
            ),
          ),
        ),
      ],
    );
  }
}
