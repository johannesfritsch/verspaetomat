import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart' show TicketType, TicketTypeX;
import '../../repo/app_repository.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// "09:38" in local time, or "–" when unknown.
/// A span of minutes for prose. Long ones read as hours, because a four-digit minute
/// figure looks like a bug even when it is true: "120" → "2 Stunden", "135" → "2 Stunden
/// 15 Minuten". Spelled out, so it can end a sentence without a doubled full stop.
String fmtMinutes(int m) {
  if (m < 120) return '$m ${m == 1 ? 'Minute' : 'Minuten'}';
  final h = m ~/ 60, rest = m % 60;
  final hours = '$h ${h == 1 ? 'Stunde' : 'Stunden'}';
  return rest == 0 ? hours : '$hours $rest ${rest == 1 ? 'Minute' : 'Minuten'}';
}

String fmtLocal(DateTime? d) => d == null ? '–' : fmtTime(TimeOfDay.fromDateTime(d.toLocal()));

/// "Di 09.09." for a date.
String fmtDay(DateTime d) {
  const wd = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  final l = d.toLocal();
  return '${wd[l.weekday - 1]} ${l.day.toString().padLeft(2, '0')}.${l.month.toString().padLeft(2, '0')}.';
}

/// Planned arrival at a stop (arrival, or departure for the first stop).
DateTime? plannedAt(ApiStop s) => s.scheduledArrival ?? s.scheduledDeparture;

/// Live arrival at a stop when known.
DateTime? liveAt(ApiStop s) => s.arrival ?? s.departure;

/// What the phone says about location right now (docs/23 §1). The Bahnsteig asks before it
/// asks for a fix, so a refusal leads somewhere instead of failing silently.
enum LocationAccess {
  /// A fix can be taken.
  granted,

  /// Never asked: the system dialog is still to come.
  notAsked,

  /// Refused for good: only the system settings can change it.
  denied,

  /// Location is off for the whole phone.
  serviceOff,

  /// `--dart-define=NO_LOCATION=1`: demos and screenshots never ask.
  suppressed,
}

Future<LocationAccess> locationAccess() async {
  const noLocation = String.fromEnvironment('NO_LOCATION', defaultValue: '');
  if (noLocation == '1' || noLocation == 'true') return LocationAccess.suppressed;
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.serviceOff;
    return switch (await Geolocator.checkPermission()) {
      LocationPermission.denied => LocationAccess.notAsked,
      LocationPermission.deniedForever => LocationAccess.denied,
      _ => LocationAccess.granted,
    };
  } catch (_) {
    return LocationAccess.denied;
  }
}

/// Opens the phone's settings for this app, so a permanent refusal has a way back.
Future<void> openLocationSettings() async {
  try {
    await Geolocator.openAppSettings();
  } catch (_) {
    // Nothing to open: the line above the button has already said what is missing.
  }
}

/// One-shot position, always a fresh fix — never a cached one, so the card can never fill in
/// with where the phone was an hour ago (docs/23 §1). Null when the platform, the permission
/// or the time budget says no.
Future<ApiLocation?> currentPosition({Duration timeout = const Duration(seconds: 4)}) async {
  // `--dart-define=NO_LOCATION=1` keeps the OS permission dialog out of demos and screenshots.
  const noLocation = String.fromEnvironment('NO_LOCATION', defaultValue: '');
  if (noLocation == '1' || noLocation == 'true') return null;
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
    final pos = await Geolocator.getCurrentPosition(locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: timeout));
    return ApiLocation(lat: pos.latitude, lon: pos.longitude, accuracyM: pos.accuracy);
  } catch (_) {
    return null;
  }
}

/// Index of the customer's station in a trip's stops, by id first, then by name.
int fromIndex(List<ApiStop> stops, String? stationId, String stationName) {
  if (stationId != null) {
    final byId = stops.indexWhere((s) => s.stationId == stationId);
    if (byId >= 0) return byId;
  }
  final n = normaliseStation(stationName);
  final byName = stops.indexWhere((s) => normaliseStation(s.name) == n);
  if (byName >= 0) return byName;
  final loose = stops.indexWhere((s) {
    final a = normaliseStation(s.name);
    return a.startsWith(n) || n.startsWith(a);
  });
  return loose >= 0 ? loose : 0;
}

String normaliseStation(String name) => name
    .toLowerCase()
    .replaceAll('hauptbahnhof', 'hbf')
    .replaceAll(RegExp(r'\(.*?\)'), '')
    .replaceAll(RegExp(r'[,/]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

// ---------------------------------------------------------------------------
// Loading and error lines
// ---------------------------------------------------------------------------

class LoadingLine extends StatelessWidget {
  const LoadingLine({super.key, this.label = 'Lädt …'});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: VSpace.m),
      child: Row(
        children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: VColors.ink2)),
          const SizedBox(width: 10),
          Text(label, style: VText.caption),
        ],
      ),
    );
  }
}

class ErrorLine extends StatelessWidget {
  const ErrorLine({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: VSpace.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: VText.bodyS.copyWith(color: VColors.red)),
          if (onRetry != null)
            InkWell(
              onTap: onRetry,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Erneut versuchen', style: VText.bodyStrong),
              ),
            ),
        ],
      ),
    );
  }
}

String shortError(Object e) {
  final s = e.toString();
  return s.length > 140 ? '${s.substring(0, 140)}…' : s;
}

// ---------------------------------------------------------------------------
// Line badge, departure row, stop line
// ---------------------------------------------------------------------------

/// The line label ("RE 7") as a small ink block, the way boards set it.
class LineBadge extends StatelessWidget {
  const LineBadge(this.line, {super.key, this.cancelled = false, this.large = false});
  final String line;
  final bool cancelled;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 10 : 8, vertical: large ? 5 : 3),
      decoration: BoxDecoration(
        color: cancelled ? VColors.red : VColors.ink,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        line,
        style: (large ? VText.bodyStrong : VText.captionInk).copyWith(
          color: VColors.paper,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A fixed-width slot for a [LineBadge] in list rows, so the destination column
/// starts at the same x for "S 6" and "ICE 512" alike.
class LineBadgeColumn extends StatelessWidget {
  const LineBadgeColumn({super.key, required this.child});
  final Widget child;
  static const width = 76.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, child: Align(alignment: Alignment.centerLeft, child: child));
  }
}

/// One departure in board style: line, destination, planned time, platform, delay.
class DepartureRow extends StatelessWidget {
  const DepartureRow({super.key, required this.departure, required this.onTap});
  final ApiDeparture departure;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = departure;
    final delay = d.delayMinutes;
    final meta = [if (d.platform != null && d.platform!.isNotEmpty) 'Gl. ${d.platform}', d.operator].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    fmtLocal(d.scheduledDeparture),
                    style: VText.mono.copyWith(
                      color: d.cancelled ? VColors.ink3 : VColors.ink,
                      decoration: d.cancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                LineBadgeColumn(child: LineBadge(d.line, cancelled: d.cancelled)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.destination, style: VText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(meta, style: VText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (d.cancelled)
                  const VChip('Ausfall', tone: VTone.red)
                else if (delay > 0)
                  VDelay(delay, size: VDelaySize.small)
                else
                  Text('pünktlich', style: VText.caption.copyWith(color: VColors.green)),
              ],
            ),
          ),
          const VRule(),
        ],
      ),
    );
  }
}

/// A vertical line of stops: dots joined by a rule. Passed dots are filled,
/// the next one pulses, the exit stop is marked with a ring.
class StopLine extends StatefulWidget {
  const StopLine({
    super.key,
    required this.stops,
    this.passed = -1,
    this.exitIndex,
    this.selectedIndex,
    this.onSelect,
    this.compact = false,
    this.firstSelectable = 1,
    this.showRadios = false,
    this.inlineChild,
    this.from = 0,
    this.to,
    this.labels = const {},
  });
  final List<ApiStop> stops;

  /// First stop to draw. Stops the train called at before the passenger boarded are not part
  /// of their journey and only push the useful part off the screen (docs/26 §4).
  final int from;

  /// Last stop to draw. Where the passenger gets off, the train carries on without them; those
  /// stops are the train's journey, not theirs, and on a journey with a change the real
  /// continuation is the next train below (docs/26 §4). Null draws to the end, which is what the
  /// exit picker wants — there the stops beyond are the choice.
  final int? to;

  /// Index → the word for that stop: `Zustieg`, `Umstieg`, `Ziel`. Drawn as a small eyebrow
  /// beside the name, so the timeline says what each marked stop means.
  final Map<int, String> labels;

  /// Index of the last passed stop (-1 = none yet).
  final int passed;
  final int? exitIndex;
  final int? selectedIndex;
  final ValueChanged<int>? onSelect;
  final bool compact;

  /// Stops before this index cannot be selected as the exit.
  final int firstSelectable;

  /// docs/22 §5: draw a radio mark in front of every selectable stop, so the list reads as a
  /// set of options rather than a decoration. Off everywhere else, where the timeline is only
  /// showing where the train is.
  final bool showRadios;

  /// Sits directly under the selected stop, inside the list — the place where the choice is
  /// confirmed. The list scrolls it into view whenever the selection moves.
  final Widget? inlineChild;

  @override
  State<StopLine> createState() => _StopLineState();
}

class _StopLineState extends State<StopLine> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  final _inlineKey = GlobalKey();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StopLine old) {
    super.didUpdateWidget(old);
    // The confirm block travels with the selection; keep it where the thumb already is.
    if (widget.inlineChild != null && old.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _inlineKey.currentContext;
        if (ctx != null && mounted) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 220), alignment: 0.7);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final first = widget.from.clamp(0, widget.stops.isEmpty ? 0 : widget.stops.length - 1);
    final last = (widget.to ?? widget.stops.length - 1).clamp(first, widget.stops.isEmpty ? 0 : widget.stops.length - 1);
    for (var i = first; i <= last; i++) {
      final s = widget.stops[i];
      final isPassed = i <= widget.passed;
      final isNext = i == widget.passed + 1;
      final isExit = widget.exitIndex == i;
      final isSelected = widget.selectedIndex == i;
      final isLast = i == last;
      // The connector is drawn against the first row on screen, not against stop zero.
      final isFirst = i == first;
      final afterExit = widget.exitIndex != null && i > widget.exitIndex!;
      final planned = plannedAt(s);
      final live = liveAt(s);
      final late = planned != null && live != null && live.difference(planned).inMinutes > 0;
      final shown = (!isPassed && late) ? live : planned;

      final dot = AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final pulse = isNext ? 0.55 + 0.45 * _pulse.value : 1.0;
          return Opacity(
            opacity: afterExit ? 0.35 : pulse,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isPassed ? VColors.ink : VColors.paper,
                border: Border.all(color: isExit || isSelected ? VColors.red : VColors.ink, width: isExit || isSelected ? 3 : 2),
              ),
            ),
          );
        },
      );

      final selectable = widget.onSelect != null && i >= widget.firstSelectable && !afterExit;
      rows.add(
        InkWell(
          onTap: widget.onSelect == null || i < widget.firstSelectable ? null : () => widget.onSelect!(i),
          child: SizedBox(
            height: widget.compact ? 44 : 52,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // docs/22 §5: the mark that says "this is a choice". Only where the list is
                // actually a set of options; a stop already behind the train gets none.
                if (widget.showRadios)
                  SizedBox(
                    width: 30,
                    child: Center(
                      child: selectable
                          ? Icon(
                              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                              size: 22,
                              color: isSelected ? VColors.red : VColors.ink3,
                            )
                          : const SizedBox(width: 22),
                    ),
                  ),
                SizedBox(
                  width: 28,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (!isLast && !isFirst) Container(width: 2, color: afterExit ? VColors.rule : VColors.ink),
                      if (isFirst && !isLast) Positioned(top: (widget.compact ? 20 : 26), bottom: 0, child: Container(width: 2, color: VColors.ink)),
                      if (isLast && !isFirst)
                        Positioned(top: 0, bottom: (widget.compact ? 20 : 26), child: Container(width: 2, color: afterExit ? VColors.rule : VColors.ink)),
                      dot,
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.name,
                          style: (isExit || isSelected ? VText.bodyStrong : VText.body).copyWith(
                            color: afterExit ? VColors.ink3 : (s.cancelled ? VColors.red : VColors.ink),
                            decoration: s.cancelled ? TextDecoration.lineThrough : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // What this stop is to the passenger: where they got on, where they change,
                      // where they are going (docs/26 §4). Falls back to the old "Ausstieg" chip
                      // where no word was given and there is room for it.
                      if (widget.labels[i] != null) ...[
                        VChip(widget.labels[i]!, tone: widget.labels[i] == 'Ziel' ? VTone.red : VTone.ink),
                        const SizedBox(width: 10),
                      ] else if (isExit && !widget.compact) ...[
                        const VChip('Ausstieg', tone: VTone.red),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        fmtLocal(shown),
                        style: VText.mono.copyWith(
                          color: afterExit ? VColors.ink3 : (late && !isPassed ? VColors.red : VColors.ink),
                          fontWeight: isExit ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      // The confirm block lives inside the list, under the stop it confirms (docs/22 §5).
      if (widget.inlineChild != null && isSelected) {
        rows.add(
          Padding(
            key: _inlineKey,
            padding: EdgeInsets.only(left: widget.showRadios ? 30 + 12 : 28 + 12, right: 2, bottom: 4),
            child: widget.inlineChild,
          ),
        );
      }
    }
    return Column(children: rows);
  }
}

// ---------------------------------------------------------------------------
// Banners
// ---------------------------------------------------------------------------

/// The station nudge as an in-app banner (the real one is a notification).
class NudgeBanner extends StatelessWidget {
  const NudgeBanner({super.key, required this.station, required this.onCheckIn, required this.onDismiss, this.onMute});
  final String station;
  final VoidCallback onCheckIn;
  final VoidCallback onDismiss;

  /// "Diesen Bahnhof nie": mutes the station on the account. Quiet, left of the snooze.
  final VoidCallback? onMute;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: VColors.paperElevated,
        border: Border.all(color: VColors.ink, width: 1.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const VStationClock(size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$station? Check dich ein.', style: VText.bodyStrong),
                    Text('Du bist in der Nähe.', style: VText.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                child: Text('Heute nicht', style: VText.bodySStrong.copyWith(color: VColors.ink2)),
              ),
              TextButton(
                onPressed: onCheckIn,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                child: Text('Einchecken', style: VText.bodySStrong.copyWith(color: VColors.red)),
              ),
            ],
          ),
          if (onMute != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onMute,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(44, 36)),
                child: Text('Diesen Bahnhof nie', style: VText.caption),
              ),
            ),
        ],
      ),
    );
  }
}

/// E8: the app says how old what it shows is.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.stamp});
  final String? stamp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: VColors.ruleSoft, borderRadius: BorderRadius.circular(4)),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 18, color: VColors.ink2),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              stamp == null ? 'Keine Verbindung. Wir zeigen den letzten Stand.' : 'Keine Verbindung. Letzter Stand $stamp Uhr.',
              style: VText.caption,
            ),
          ),
        ],
      ),
    );
  }
}

/// The delay figure counting up from zero. Used once, at arrival.
class CountUpDelay extends StatelessWidget {
  const CountUpDelay(this.minutes, {super.key, this.cancelled = false, this.size = VDelaySize.display});
  final int minutes;
  final bool cancelled;
  final VDelaySize size;

  @override
  Widget build(BuildContext context) {
    if (cancelled) return VDelay(0, size: size, cancelled: true);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: minutes.toDouble()),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => VDelay(v.round(), size: size),
    );
  }
}

// ---------------------------------------------------------------------------
// Sheets and shortcuts
// ---------------------------------------------------------------------------

/// The sheet that switches the ticket type for the next ride.
Future<void> showTicketSheet(BuildContext context) {
  final session = RepoScope.read(context);
  return showVSheet(
    context,
    builder: (ctx) => ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final current = session.me?.settings.ticket ?? TicketType.deutschlandticket;
        return Padding(
          padding: const EdgeInsets.only(bottom: VSpace.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const VSheetHeader(title: 'Welches Ticket?', subtitle: 'Entscheidet, was eine Verspätung wert ist.'),
              for (final t in TicketType.values)
                Padding(
                  padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.s, VSpace.page, 0),
                  child: VChoiceCard(
                    title: t.label,
                    subtitle: t.rule,
                    selected: current == t,
                    onTap: () {
                      session.updateSettings(MePatch(ticket: t));
                      Navigator.of(ctx).pop();
                    },
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

/// Station search as a sheet; returns the picked station.
Future<ApiStation?> showStationSearch(BuildContext context) {
  return showVSheet<ApiStation>(context, expand: true, builder: (ctx) => const _StationSearchSheet());
}

class _StationSearchSheet extends StatefulWidget {
  const _StationSearchSheet();

  @override
  State<_StationSearchSheet> createState() => _StationSearchSheetState();
}

class _StationSearchSheetState extends State<_StationSearchSheet> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  List<ApiStation> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(v));
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await RepoScope.read(context).repo.searchStations(q.trim());
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _error = shortError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VSheetHeader(title: 'Bahnhof suchen'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
          child: TextField(
            controller: _ctl,
            autofocus: true,
            onChanged: _onChanged,
            onSubmitted: _search,
            decoration: const InputDecoration(hintText: 'Köln Hbf, Münster …', prefixIcon: Icon(Icons.search, size: 20, color: VColors.ink2)),
          ),
        ),
        const VGap.s(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
            children: [
              if (_loading) const LoadingLine(label: 'Suche …'),
              if (_error != null) ErrorLine(message: _error!, onRetry: () => _search(_ctl.text)),
              for (final s in _results)
                VListRow(
                  title: s.name,
                  subtitle: s.distanceM != null ? '${s.distanceM} m' : null,
                  chevron: true,
                  onTap: () => Navigator.of(context).pop(s),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Demo shortcut: check in to the first regional train at the nearest station
/// and go to the ride screen. Works in both modes.
Future<void> demoCheckIn(BuildContext context) async {
  final repo = RepoScope.read(context).repo;
  try {
    final stations = (await repo.nearbyStations()).stations;
    if (stations.isEmpty) throw StateError('Kein Bahnhof gefunden.');
    final station = stations.first;
    final deps = await repo.departures(station.id);
    final d = deps.firstWhere((x) => !x.cancelled && (x.category == ApiCategory.re || x.category == ApiCategory.rb || x.category == ApiCategory.s), orElse: () => deps.first);
    final trip = await repo.trip(d.tripId);
    final from = fromIndex(trip.stops, station.id, station.name);
    var exitIdx = trip.stops.indexWhere((s) => s.name.startsWith('Münster'));
    if (exitIdx <= from) exitIdx = (from + 2).clamp(from + 1, trip.stops.length - 1);
    final exit = trip.stops[exitIdx];
    await repo.checkIn(CheckInRequest(
      tripId: d.tripId,
      fromStationId: station.id,
      fromStationName: station.name,
      exitStationId: exit.stationId ?? exit.name,
      exitStationName: exit.name,
    ));
    if (context.mounted) context.go(Routes.unterwegs);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Check-in nicht möglich: ${shortError(e)}')));
  }
}
