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
///  1. **Von wo?** — the detected station preselected, the next two beneath it, then search.
///  2. **Wohin?** — destinations from history, then search.
///  3. **Welcher Zug?** — the itineraries, one swipe from the choice above.
///
/// The square always starts at step 1, even when the detection is right: one tap on the
/// preselected station moves on, and the passenger sees what the app thinks before committing
/// to it. The one-tap path for the common case lives on the Home card instead, whose `Nach`
/// row starts at step 3. [from] skips step 1 for a caller that already knows the station —
/// a station nudge or a deep link.
Future<void> runCheckinFlow(BuildContext context, {ApiStation? from}) async {
  final near = NearbyScope.read(context);
  // A fix may still be in flight when the square is tapped right after a cold start.
  if (from == null && near != null && near.station == null) await near.refresh();
  if (!context.mounted) return;

  var source = from;
  ApiStation? destination;
  var step = source == null ? 0 : 1;

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

class _VonSheet extends StatelessWidget {
  const _VonSheet({this.current, this.near});
  final ApiStation? current;
  final NearbyMonitor? near;

  @override
  Widget build(BuildContext context) {
    // The fix may land while the sheet is open; it follows the monitor rather than freezing
    // whatever was known at the moment of the tap.
    return AnimatedBuilder(
      animation: near ?? const AlwaysStoppedAnimation(0),
      builder: (context, _) => _body(context, current ?? near?.station),
    );
  }

  Widget _body(BuildContext context, ApiStation? detected) {
    final near = this.near;
    final others = (near?.others(take: 2) ?? const <ApiStation>[]).where((s) => s.id != detected?.id).toList();
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
                    subtitle: detected.distanceM == null ? null : '${detected.distanceM} m',
                    chevron: true,
                    onTap: () => Navigator.of(context).pop(StepResult<ApiStation>.value(detected)),
                  ),
                for (final s in others)
                  VListRow(
                    title: s.name,
                    subtitle: s.distanceM == null ? null : '${s.distanceM} m',
                    chevron: true,
                    onTap: () => Navigator.of(context).pop(StepResult<ApiStation>.value(s)),
                  ),
                if (detected == null && others.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: VSpace.s),
                    child: Text(
                      near?.checking == true
                          ? 'Wir schauen noch, wo du bist.'
                          : 'Wir wissen gerade nicht, wo du bist. Such deinen Bahnhof.',
                      style: VText.bodyS.copyWith(color: VColors.ink2),
                    ),
                  ),
                const VGap.m(),
                VOutlineButton(
                  label: 'Bahnhof suchen',
                  icon: Icons.search,
                  onTap: () async {
                    final s = await showStationSearch(context);
                    if (s == null || !context.mounted) return;
                    // A station chosen by hand is where the passenger is, for everything else too.
                    near?.pick(s);
                    if (context.mounted) Navigator.of(context).pop(StepResult<ApiStation>.value(s));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
Future<StepResult<void>?> showWelcherZugSheet(
  BuildContext context, {
  required ApiStation from,
  required ApiStation to,
}) {
  return showVSheet<StepResult<void>>(
    context,
    expand: true,
    builder: (ctx) => _WelcherZugSheet(from: from, to: to),
  );
}

class _WelcherZugSheet extends StatelessWidget {
  const _WelcherZugSheet({required this.from, required this.to});
  final ApiStation from;
  final ApiStation to;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VSheetHeader(title: 'Welcher Zug?'),
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
