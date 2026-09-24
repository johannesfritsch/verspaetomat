import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart' show TicketType;
import '../../repo/app_repository.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../share/share_lines.dart';
import '../share/share_sheet.dart';
import '../../widgets/ticket.dart';
import '../community/community_widgets.dart' show BadgeIcon;
import 'ride_widgets.dart';

/// The reveal. The only screen allowed to feel like a reward.
///
/// A sheet's body since #63, never a page of its own: inside the ride sheet when the journey
/// arrives under it, otherwise in [showArrivalSheet]. Fed by an [ApiArrivalResult] (a legacy
/// ride's arrival), or by the last arrival the repository knows. `variant` = 68 | 14 | 59 |
/// cancelled | nodata drives the showcase in demo mode.
class AngekommenScreen extends StatefulWidget {
  const AngekommenScreen({super.key, this.variant, this.result, this.onDone});
  final String? variant;
  final ApiArrivalResult? result;

  /// "Fertig". Without it the arrival is dismissed and the sheet closed.
  final VoidCallback? onDone;

  @override
  State<AngekommenScreen> createState() => _AngekommenScreenState();
}

class _AngekommenScreenState extends State<AngekommenScreen> {
  ApiArrivalResult? _result;
  ApiJourney? _journey;
  ApiIncidents? _incidents;
  bool _loading = true;
  String? _error;
  int? _enteredDelay; // E3

  @override
  void initState() {
    super.initState();
    _result = widget.result;
    if (widget.variant != 'nodata') WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = RepoScope.read(context);
    final repo = session.repo;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var result = _result;
      final v = widget.variant;
      if (result == null && v != null && !session.isLocal) {
        result = await _demoVariant(repo, v);
      }
      // The journey behind the arrival (docs/17): its delay at the destination is the one that counts.
      ApiJourney? journey;
      try {
        final jl = await repo.currentJourney();
        if (jl != null && jl.journey.arrived) journey = jl.journey;
      } catch (_) {}
      if (result == null) {
        final live = await repo.currentRide();
        if (live != null && live.ride.status == ApiRideStatus.arrived) {
          result = ApiArrivalResult(ride: live.ride);
        } else if (live != null && !session.isLocal) {
          result = await repo.arrival(const ArrivalRequest());
        }
      }
      final inc = await repo.incidents();
      if (!mounted) return;
      setState(() {
        _result = result;
        _journey = journey;
        _incidents = inc;
      });
    } catch (e) {
      if (mounted) setState(() => _error = shortError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Demo mode: make sure a ride exists, then arrive with the variant's delay.
  Future<ApiArrivalResult> _demoVariant(AppRepository repo, String v) async {
    final live = await repo.currentRide();
    if (live == null || live.ride.status != ApiRideStatus.riding) {
      // Through plan + startJourney, the way a passenger's ride is made (docs/29). Building one
      // by hand here meant the arrival screen was demonstrated on a ride of a shape the app no
      // longer creates.
      await demoStartJourney(repo);
    }
    return switch (v) {
      '68' => repo.arrival(const ArrivalRequest(delayMinutes: 68)),
      '14' => repo.arrival(const ArrivalRequest(delayMinutes: 14)),
      '59' => repo.arrival(const ArrivalRequest(delayMinutes: 59)),
      'cancelled' => repo.arrival(const ArrivalRequest(delayMinutes: 60, cancelled: true)),
      'nodata' => repo.arrival(ArrivalRequest(delayMinutes: _enteredDelay ?? 0, selfEntered: true)),
      _ => repo.arrival(const ArrivalRequest()),
    };
  }

  Future<void> _finish() async {
    final done = widget.onDone;
    if (done != null) {
      done();
      return;
    }
    try {
      await RepoScope.read(context).repo.dismissRide();
    } catch (_) {}
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);

    if (widget.variant == 'nodata' && _enteredDelay == null) {
      return _NoDataStep(
        onDone: (d) {
          setState(() => _enteredDelay = d);
          _load();
        },
      );
    }

    final result = _result;
    if (result == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(VSpace.sheet, 0, VSpace.sheet, VSpace.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading) ...const [VGap.s(), VSkeletonBoard(), VGap.md(), VSkeletonCard()],
            if (_error != null) ErrorLine(message: _error!, onRetry: _load),
            if (!_loading && _error == null) ...[
              const VGap.m(),
              Text('Noch keine Ankunft.', style: VText.h2),
              const VGap.s(),
              Text('Check ein, fahr los, komm an. Dann steht hier die Zahl.', style: VText.body.copyWith(color: VColors.ink2)),
              const VGap.l(),
              VOutlineButton(label: 'Schließen', onTap: _finish),
            ],
          ],
        ),
      );
    }

    final r = result.ride;
    final j = _journey;
    // Either one: a journey that does not carry the flag still ended on a cancelled train.
    final cancelled = (j?.cancelled ?? false) || r.cancelled;
    final delay = j?.finalDelayMin ?? r.finalDelayMinutes ?? 0;
    final points = (j?.points ?? r.points) > 0 ? (j?.points ?? r.points) : (cancelled ? 60 : delay);
    final planned = j?.plannedArrival ?? r.plannedArrival;
    final actual = j?.actualArrival ?? planned?.add(Duration(minutes: delay));
    final where = j?.destinationStationName ?? r.exitStationName;
    final origin = j?.originStationName ?? r.fromStationName;
    // The ledger row for this journey, when the arrival result carried none.
    final incident = result.incident ??
        (j == null ? null : _incidents?.incidents.where((i) => (i.journeyId != null && i.journeyId == j.id) || (i.rideId != null && i.rideId == r.id)).firstOrNull);
    final ticket = r.ticket;
    final ngoId = incident?.ngoId ?? session.me?.settings.ngoId;
    final ngo = session.ngos.where((n) => n.id == ngoId).firstOrNull;
    final ngoName = ngo?.name ?? 'deinen Zweck';
    final hasClaim = incident != null || delay >= 60 || cancelled;
    final desk = incident?.desk ?? '';
    final deskSummary = _incidents?.summary.desks.where((d) => d.desk == desk).firstOrNull;
    final openCount = deskSummary?.incidentIds.length ?? (incident == null ? 0 : 1);
    final ready = deskSummary?.ready ?? result.bundleReady;
    final counted = hasClaim ? openCount.clamp(1, 3) : openCount;
    final amountCents = incident?.amountCents;
    final canFile = hasClaim && incident != null && (ticket == TicketType.einzelfahrkarte || ready);

    void share() => showShareSheet(
          context,
          strecke: '$origin → $where',
          date: actual ?? planned ?? DateTime.now(),
          // docs/27: the arrival is the first of the four faces, and a punctual ride is its own
          // card — rare enough to be the joke, and the joke travels.
          lines: delay > 0 ? ShareLines.angekommen(minutes: delay, to: where) : ShareLines.puenktlich(to: where),
          build: ({fahrgast, strecke, date, line}) => delay > 0
              ? TicketData.angekommen(minutes: delay, points: points, strecke: strecke, fahrgast: fahrgast, date: date, line: line)
              : TicketData.puenktlich(strecke: strecke, fahrgast: fahrgast, date: date, line: line),
        );

    // #63: Teilen and Fertig side by side, Fertig the red one — unless there is a claim to file,
    // which then is the red one and both of the others step back.
    final actions = canFile
        ? Column(
            children: [
              VPrimaryButton(label: 'Jetzt einreichen', onTap: () => context.push('${Routes.claim}?desk=${Uri.encodeComponent(desk)}')),
              const VGap.s(),
              Row(
                children: [
                  Expanded(child: VOutlineButton(label: 'Teilen', icon: Icons.ios_share, onTap: share)),
                  const SizedBox(width: VSpace.s),
                  Expanded(child: VOutlineButton(label: 'Fertig', onTap: _finish)),
                ],
              ),
            ],
          )
        : Row(
            children: [
              Expanded(child: VOutlineButton(label: 'Teilen', icon: Icons.ios_share, onTap: share)),
              const SizedBox(width: VSpace.s),
              Expanded(child: VPrimaryButton(label: 'Fertig', onTap: _finish)),
            ],
          );

    final String subline;
    if (cancelled) {
      subline = 'Reise nicht angetreten. 60 Minuten angerechnet.';
    } else {
      final extra = '${r.cause != null ? ' · ${r.cause}' : ''}${r.selfEntered ? ' · selbst eingetragen' : ''}';
      subline = delay > 0
          ? 'Ankunft $where ${fmtLocal(actual)} statt ${fmtLocal(planned)}$extra'
          : 'Ankunft $where ${fmtLocal(actual)}, wie geplant$extra';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(VSpace.sheet, 0, VSpace.sheet, VSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The station you arrived at, over the platform drawing; on its left, what the ride
          // came to: the check when it was on time, the figure when it was not.
          ArrivalArt(
            station: where,
            mark: delay <= 0 && !cancelled ? const _OnTimeMark() : CountUpDelay(delay, cancelled: cancelled, size: VDelaySize.large),
          ),
          const VGap.s(),
          Text('ANGEKOMMEN', style: VText.eyebrow),
          const VGap.xs(),
          Text(_headline(delay, cancelled, points), style: VText.h1),
          const VGap.s(),
          Text(subline, style: VText.body.copyWith(color: VColors.ink2)),
          if (j != null && j.missedConnection) ...[
            const VGap.xs(),
            Text('Anschluss verpasst in ${j.transferStationName ?? (j.legs.length > 1 ? j.legs.first.toStationName : '')}. Zählt am Ziel, nicht pro Zug.', style: VText.bodySStrong.copyWith(color: VColors.red)),
          ] else if (j != null && j.incomplete) ...[
            const VGap.xs(),
            Text('Beendet unterwegs: die Verspätung bis ${j.transferStationName ?? where} zählt.', style: VText.caption),
          ],
          const VGap.m(),
          _TripCard(journey: j, ride: r, arrivedAt: cancelled ? null : actual),
          if (result.newBadge != null) ...[
            const VGap.s(),
            VCard(
              tone: VCardTone.sunken,
              padding: const EdgeInsets.all(VSpace.cardTight),
              child: Row(
                children: [
                  BadgeIcon(badge: result.newBadge!, size: 44),
                  const SizedBox(width: VSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Neues Abzeichen', style: VText.caption),
                        Text(result.newBadge!.name, style: VText.bodyStrong.copyWith(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const VGap.s(),
          if (hasClaim)
            VCard(
              tone: VCardTone.sunken,
              padding: const EdgeInsets.all(VSpace.card),
              child: _ClaimLine(ticket: ticket, amountCents: amountCents, ngoName: ngoName, counted: counted, ready: ready, pending: incident == null),
            )
          else ...[
            _NoClaimCard(delay: delay, ngoName: ngoName),
            if (ngo != null && delay != 59) ...[
              const VGap.s(),
              _Tile(
                icon: Icons.card_giftcard,
                title: 'Trotzdem spenden',
                body: 'Auch ohne Anspruch kannst du ${ngo.name} unterstützen.',
                onTap: () => _trotzdem(context, ngo),
              ),
            ],
          ],
          const VGap.l(),
          actions,
        ],
      ),
    );
  }

  String _headline(int delay, bool cancelled, int points) {
    if (cancelled) return '60 Minuten.\n$points Geduldspunkte.';
    if (delay == 59) return '59 Minuten.\nUm eine Minute.';
    if (delay <= 0) return 'Pünktlich.\nAuch das gibt es.';
    if (delay == 1) return 'Eine Minute.\nEin Geduldspunkt.';
    return '$delay Minuten.\n$points Geduldspunkte.';
  }

  void _trotzdem(BuildContext context, ApiNgo ngo) {
    showVSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(VSpace.page, 0, VSpace.page, VSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VSheetHeader(title: 'Das läuft nicht über uns.'),
            Text('Du landest direkt bei ${ngo.name}. Was du dort gibst, sehen wir nicht, und es taucht nicht in der Community-Summe auf.', style: VText.body),
            const VGap.l(),
            VPrimaryButton(
              label: 'Zu ${ngo.name}',
              icon: Icons.open_in_new,
              onTap: () {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Öffnet ${ngo.donationUrl} im Browser. (Demo)')));
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The arrival as its own sheet over the active tab (#63), for when the ride sheet is not the
/// one showing it: a notification, the Bahnsteig card, a legacy ride, the showcase. The same
/// content the ride sheet shows when the journey arrives under it.
Future<void> showArrivalSheet(BuildContext context, {String? variant, ApiArrivalResult? result, void Function(Route<void> route)? onRoute}) {
  return showVSheet<void>(
    context,
    builder: (ctx) {
      final route = ModalRoute.of(ctx);
      if (route != null) onRoute?.call(route);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const VSheetHeader(),
          AngekommenScreen(variant: variant, result: result),
        ],
      );
    },
  );
}

/// The drawing of #63: a train in at a platform, the station's own name on the sign. The sign
/// in the picture is blank; its face is measured in the image (612 × 382) — centre (490, 121),
/// 136 × 54, tilted by 15.8° — so the name sits on it at any width.
class ArrivalArt extends StatelessWidget {
  const ArrivalArt({super.key, required this.station, this.mark});
  final String station;

  /// What stands on the left, in front of the sky: the check or the figure.
  final Widget? mark;

  /// The name in at most two lines, broken at the space nearest the middle.
  static String signLines(String name) {
    final n = name.trim();
    if (n.length <= 12 || !n.contains(' ')) return n;
    var best = -1;
    for (var i = 0; i < n.length; i++) {
      if (n[i] == ' ' && (best < 0 || (i - n.length / 2).abs() < (best - n.length / 2).abs())) best = i;
    }
    return '${n.substring(0, best)}\n${n.substring(best + 1)}';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // Room on the left for the figure: „+68" at its size is about a quarter of the width.
      final w = c.maxWidth * 0.72;
      final h = w * 382 / 612;
      double x(double v) => w * v / 612;
      double y(double v) => h * v / 382;
      return SizedBox(
        height: h,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: 0,
              top: 0,
              width: w,
              height: h,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (rect) => const LinearGradient(
                        colors: [Colors.transparent, Colors.black],
                        stops: [0, 0.3],
                      ).createShader(rect),
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (rect) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black, Colors.black, Colors.transparent],
                          stops: [0, 0.8, 1],
                        ).createShader(rect),
                        // The drawing is on white; multiplied with the paper it takes the sheet's tone.
                        child: Image.asset('assets/sheet/angekommen.webp', fit: BoxFit.cover, color: VColors.paperElevated, colorBlendMode: BlendMode.multiply),
                      ),
                    ),
                  ),
                  Positioned(
                    left: x(490 - 68),
                    top: y(121 - 27),
                    width: x(136),
                    height: y(54),
                    child: Transform.rotate(
                      angle: -0.276,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          signLines(station),
                          key: const Key('arrival-sign'),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: VText.title.copyWith(color: VColors.inkOnDark, height: 1.15),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (mark != null) Positioned(left: 0, top: h * 0.3, child: mark!),
          ],
        ),
      );
    });
  }
}

/// On time: a green check, the one place on the arrival where green means „so war es geplant".
class _OnTimeMark extends StatelessWidget {
  const _OnTimeMark();

  @override
  Widget build(BuildContext context) => Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(color: VColors.green, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, color: VColors.paperElevated, size: 40),
      );
}

/// The ride as it went (#63): where it left, each train, where it arrived — time, track and
/// station on one line, the trains between them on the spine. Only what the plan and the feed
/// say; a track nobody knows is left out rather than guessed.
class _TripCard extends StatelessWidget {
  const _TripCard({required this.journey, required this.ride, required this.arrivedAt});
  final ApiJourney? journey;
  final ApiRide ride;
  final DateTime? arrivedAt;

  @override
  Widget build(BuildContext context) {
    final j = journey;
    final rows = <Widget>[];
    var legs = j == null ? const <ApiLeg>[] : ([...j.legs]..sort((a, b) => (a.legNo ?? 0).compareTo(b.legNo ?? 0)));
    // The trains actually taken: a journey ended at a change never rode the rest of its plan.
    final ridden = legs.where((l) => l.status == ApiLegStatus.arrived || l.status == ApiLegStatus.riding).toList();
    if (ridden.isNotEmpty) legs = ridden;
    if (legs.isEmpty) {
      rows
        ..add(_TripStation(time: null, track: null, name: ride.fromStationName, first: true))
        ..add(_TripLine(line: ride.line, from: ride.fromStationName, to: ride.exitStationName))
        ..add(_TripStation(time: arrivedAt, track: null, name: ride.exitStationName, last: true));
    } else {
      for (var i = 0; i < legs.length; i++) {
        final l = legs[i];
        rows.add(_TripStation(time: l.liveDeparture ?? l.plannedDeparture, track: l.platform, name: l.fromStationName, first: i == 0, change: i > 0));
        rows.add(_TripLine(line: l.line, from: l.fromStationName, to: l.toStationName));
      }
      final last = legs.last;
      rows.add(_TripStation(time: arrivedAt ?? last.actualArrival ?? last.liveArrival ?? last.plannedArrival, track: last.arrivalPlatform, name: last.toStationName, last: true));
    }
    return VCard(
      key: const Key('arrival-trip'),
      tone: VCardTone.sunken,
      padding: const EdgeInsets.symmetric(horizontal: VSpace.cardTight, vertical: VSpace.s),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }
}

const double _tripGutter = 24;

/// The spine beside a row: a line above, a line below, and a mark or nothing in between.
class _TripSpine extends StatelessWidget {
  const _TripSpine({this.top = true, this.bottom = true, this.mark});
  final bool top;
  final bool bottom;
  final Widget? mark;

  @override
  Widget build(BuildContext context) {
    Widget line(bool on) => Expanded(child: Center(child: Container(width: 2.2, color: on ? VColors.red : Colors.transparent)));
    return SizedBox(
      width: _tripGutter,
      child: Column(children: [line(top), if (mark != null) mark!, line(bottom)]),
    );
  }
}

class _TripStation extends StatelessWidget {
  const _TripStation({required this.time, required this.track, required this.name, this.first = false, this.last = false, this.change = false});
  final DateTime? time;
  final String? track;
  final String name;
  final bool first;
  final bool last;

  /// A change between two trains: the arrival of one and the departure of the next.
  final bool change;

  @override
  Widget build(BuildContext context) {
    // Hollow where it began and where you changed, filled where it ended: the one that happened.
    final Widget dot = Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        color: last ? VColors.red : VColors.surfaceMuted,
        shape: BoxShape.circle,
        border: Border.all(color: VColors.red, width: 2.4),
      ),
    );
    final t = track == null || track!.trim().isEmpty ? null : track!.trim();
    return IntrinsicHeight(
      child: Row(
        children: [
          _TripSpine(top: !first, bottom: !last, mark: dot),
          const SizedBox(width: VSpace.md),
          // Fixed columns so the stations line up; a larger text size scales the figure down
          // rather than spilling it into the track.
          SizedBox(
            width: 48,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(fmtLocal(time), style: VText.bodyStrong.merge(VText.mono).copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
          SizedBox(
            width: 68,
            child: t == null
                ? null
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: VSpace.s, vertical: 3),
                      decoration: BoxDecoration(color: VColors.greyPill, borderRadius: BorderRadius.circular(VRadius.sm)),
                      child: Text('Gleis $t', style: VText.pill, maxLines: 1),
                    ),
                  ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: VSpace.s),
              child: Text(name, style: change ? VText.bodyL.copyWith(color: VColors.ink2) : VText.bodyL, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripLine extends StatelessWidget {
  const _TripLine({required this.line, required this.from, required this.to});
  final String line;
  final String from;
  final String to;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        children: [
          const _TripSpine(),
          const SizedBox(width: VSpace.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: VSpace.xs),
              child: Row(
                children: [
                  LineBadge(line),
                  const SizedBox(width: VSpace.s),
                  Expanded(child: Text('$from → $to', style: VText.bodyS, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClaimLine extends StatelessWidget {
  const _ClaimLine({required this.ticket, required this.amountCents, required this.ngoName, required this.counted, required this.ready, required this.pending});
  final TicketType ticket;
  final int? amountCents;
  final String ngoName;
  final int counted;
  final bool ready;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(pending ? 'Anspruch wird geprüft' : 'Anspruch entstanden', style: VText.bodyStrong)),
            Text(
              amountCents == null ? '–' : (ticket == TicketType.einzelfahrkarte ? 'ca. ${fmtEuro(amountCents! / 100)}' : fmtEuro(amountCents! / 100)),
              style: VText.numberM,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('für $ngoName', style: VText.bodyS.copyWith(color: VColors.ink2)),
        const SizedBox(height: 12),
        if (ticket == TicketType.deutschlandticket)
          Row(
            children: [
              VDots(filled: counted, total: 3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ready ? 'Gesammelt $counted von 3 · Bündel ist bereit' : 'Gesammelt $counted von 3 · noch ${3 - counted} bis zur Auszahlung',
                  style: VText.caption,
                ),
              ),
            ],
          )
        else
          Text('Jede Fahrt einzeln. Kein Sammeln nötig.', style: VText.caption),
      ],
    );
  }
}

/// No claim (#63): why not, on a grey card with the info mark.
class _NoClaimCard extends StatelessWidget {
  const _NoClaimCard({required this.delay, required this.ngoName});
  final int delay;
  final String ngoName;

  @override
  Widget build(BuildContext context) {
    final title = delay == 59
        // E7: one minute short. The line, and nothing else.
        ? 'Kein Anspruch, um eine Minute. Wir wissen.'
        : delay <= 0
            ? 'Kein Anspruch, keine Wartezeit.\nMorgen wieder.'
            : 'Kein Anspruch, aber $delay Minuten Geduld.';
    return VCard(
      tone: VCardTone.sunken,
      padding: const EdgeInsets.all(VSpace.card),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 22, color: VColors.ink2),
          const SizedBox(width: VSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: VText.bodyStrong),
                if (delay != 59) ...[
                  const SizedBox(height: VSpace.xs),
                  Text('Ab 60 Minuten entsteht ein Anspruch. Bis dahin zählen die Punkte, und $ngoName freut sich auch so.', style: VText.bodyS),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A red-tinted tile with a mark, what it is, what it does and the chevron that says so.
class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.body, required this.onTap});
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: VColors.redTintSoft,
      borderRadius: BorderRadius.circular(VRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(VRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(VSpace.cardTight),
          child: Row(
            children: [
              VIconBadge(icon: icon, tone: VBadgeTone.red, size: VControl.badgeSmall),
              const SizedBox(width: VSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: VText.bodyStrong),
                    const SizedBox(height: 2),
                    Text(body, style: VText.bodyS.copyWith(color: VColors.ink2)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: VColors.ink2),
            ],
          ),
        ),
      ),
    );
  }
}

/// E3: no data at arrival. Ask for the actual delay, preset to the plan.
class _NoDataStep extends StatefulWidget {
  const _NoDataStep({required this.onDone});
  final ValueChanged<int> onDone;

  @override
  State<_NoDataStep> createState() => _NoDataStepState();
}

class _NoDataStepState extends State<_NoDataStep> {
  int _minutes = 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(VSpace.sheet, VSpace.s, VSpace.sheet, VSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('KEINE DATEN BEI ANKUNFT', style: VText.eyebrow),
          const VGap.xs(),
          Text('Wann bist du angekommen?', style: VText.h1),
          const VGap.s(),
          Text('Der Live-Feed hat deinen Zug verloren. Wie viele Minuten nach Plan bist du angekommen?', style: VText.body.copyWith(color: VColors.ink2)),
          const VGap.xl(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              VIconButton(icon: Icons.remove, onTap: () => setState(() => _minutes = (_minutes - 5).clamp(0, 300))),
              Expanded(child: Center(child: VDelay(_minutes, size: VDelaySize.large))),
              VIconButton(icon: Icons.add, onTap: () => setState(() => _minutes = (_minutes + 5).clamp(0, 300))),
            ],
          ),
          const VGap.xl(),
          Text('Die Fahrt zählt Punkte. Im Konto steht sie als „selbst eingetragen“, und im Antrag auch.', style: VText.caption),
          const VGap.l(),
          VPrimaryButton(label: 'Übernehmen', onTap: () => widget.onDone(_minutes)),
        ],
      ),
    );
  }
}
