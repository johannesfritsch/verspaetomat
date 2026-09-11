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
/// Fed by an [ApiArrivalResult] (from Unterwegs or the E1 flow), or by the
/// last arrival the repository knows. `variant` = 68 | 14 | 59 | ausfall | nodata
/// drives the showcase in demo mode.
class AngekommenScreen extends StatefulWidget {
  const AngekommenScreen({super.key, this.variant, this.result, this.embedded = false, this.onDone});
  final String? variant;
  final ApiArrivalResult? result;

  /// Inside the ride sheet (docs/19): the body without its own Scaffold; "Fertig" calls [onDone].
  final bool embedded;
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
      'ausfall' => repo.arrival(const ArrivalRequest(delayMinutes: 60, cancelled: true)),
      'nodata' => repo.arrival(ArrivalRequest(delayMinutes: _enteredDelay ?? 0, selfEntered: true)),
      _ => repo.arrival(const ArrivalRequest()),
    };
  }

  Future<void> _finish() async {
    if (widget.embedded) {
      widget.onDone?.call();
      return;
    }
    try {
      await RepoScope.read(context).repo.dismissRide();
    } catch (_) {}
    if (mounted) context.go(Routes.bahnsteig);
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
      final empty = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loading) const LoadingLine(label: 'Ankunft wird geladen …'),
          if (_error != null) ErrorLine(message: _error!, onRetry: _load),
          if (!_loading && _error == null) ...[
            const VGap.xl(),
            Text('Noch keine Ankunft.', style: VText.h2),
            const VGap.s(),
            Text('Check ein, fahr los, komm an. Dann steht hier die Zahl.', style: VText.body.copyWith(color: VColors.ink2)),
            const VGap.l(),
            VGhostButton(label: 'Zum Bahnsteig', onTap: () => context.go(Routes.bahnsteig)),
          ],
        ],
      );
      // Inside the ride sheet there is no screen to fill: the lines, nothing else.
      if (widget.embedded) return Padding(padding: const EdgeInsets.symmetric(horizontal: VSpace.page), child: empty);
      return VScreen(title: 'Angekommen', child: empty);
    }

    final r = result.ride;
    final j = _journey;
    final cancelled = j?.cancelled ?? r.cancelled;
    final delay = j?.finalDelayMin ?? r.finalDelayMinutes ?? 0;
    final points = (j?.points ?? r.points) > 0 ? (j?.points ?? r.points) : (cancelled ? 60 : delay);
    final planned = j?.plannedArrival ?? r.plannedArrival;
    final actual = j?.actualArrival ?? planned?.add(Duration(minutes: delay));
    final where = j?.destinationStationName ?? r.exitStationName;
    final lineLabel = j != null && j.legs.isNotEmpty ? j.lineLabel : r.line;
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

    final actions = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canFile) VPrimaryButton(label: 'Jetzt einreichen', onTap: () => context.push('${Routes.antrag}?desk=${Uri.encodeComponent(desk)}')),
        Row(
          children: [
            Expanded(
              child: VGhostButton(
                label: 'Teilen',
                icon: Icons.ios_share,
                // docs/27: the arrival is the first of the four faces, and a punctual ride is
                // its own card — rare enough to be the joke, and the joke travels.
                onTap: () => showShareSheet(
                  context,
                  strecke: '$origin → $where',
                  date: actual ?? planned ?? DateTime.now(),
                  lines: delay > 0
                      ? ShareLines.angekommen(minutes: delay, to: where)
                      : ShareLines.puenktlich(to: where),
                  build: ({fahrgast, strecke, date, line}) => delay > 0
                      ? TicketData.angekommen(
                          minutes: delay,
                          points: points,
                          strecke: strecke,
                          fahrgast: fahrgast,
                          date: date,
                          line: line,
                        )
                      : TicketData.puenktlich(
                          strecke: strecke,
                          fahrgast: fahrgast,
                          date: date,
                          line: line,
                        ),
                ),
              ),
            ),
            Expanded(child: VGhostButton(label: 'Fertig', onTap: _finish)),
          ],
        ),
      ],
    );
    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(VSpace.page, 0, VSpace.page, VSpace.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _arrivalBody(context, result: result, lineLabel: lineLabel, origin: origin, where: where, delay: delay, cancelled: cancelled, points: points, planned: planned, actual: actual, j: j, r: r, hasClaim: hasClaim, ticket: ticket, amountCents: amountCents, ngoName: ngoName, counted: counted, ready: ready, incident: incident, ngo: ngo),
            const VGap.l(),
            actions,
          ],
        ),
      );
    }

    return VScreen(
      showBack: false,
      trailing: Text('${fmtDay(actual ?? DateTime.now())} · ${fmtLocal(actual)}', style: VText.caption),
      eyebrow: 'Angekommen',
      bottom: actions,
      child: _arrivalBody(context, result: result, lineLabel: lineLabel, origin: origin, where: where, delay: delay, cancelled: cancelled, points: points, planned: planned, actual: actual, j: j, r: r, hasClaim: hasClaim, ticket: ticket, amountCents: amountCents, ngoName: ngoName, counted: counted, ready: ready, incident: incident, ngo: ngo),
    );
  }

  Widget _arrivalBody(
    BuildContext context, {
    required ApiArrivalResult result,
    required String lineLabel,
    required String origin,
    required String where,
    required int delay,
    required bool cancelled,
    required int points,
    required DateTime? planned,
    required DateTime? actual,
    required ApiJourney? j,
    required ApiRide r,
    required bool hasClaim,
    required TicketType ticket,
    required int? amountCents,
    required String ngoName,
    required int counted,
    required bool ready,
    required ApiIncident? incident,
    required ApiNgo? ngo,
  }) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$lineLabel · $origin → $where', style: VText.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
          const VGap.l(),
          CountUpDelay(delay, cancelled: cancelled),
          const VGap.m(),
          Text(_headline(delay, cancelled, points), style: VText.h2),
          const VGap.xs(),
          Text(
            cancelled
                ? 'Reise nicht angetreten. 60 Minuten angerechnet.'
                : 'Ankunft $where ${fmtLocal(actual)} statt ${fmtLocal(planned)}${r.cause != null ? ' · ${r.cause}' : ''}${r.selfEntered ? ' · selbst eingetragen' : ''}',
            style: VText.bodyS.copyWith(color: VColors.ink2),
          ),
          if (j != null && j.missedConnection) ...[
            const VGap.xs(),
            Text('Anschluss verpasst in ${j.transferStationName ?? (j.legs.length > 1 ? j.legs.first.toStationName : '')}. Zählt am Ziel, nicht pro Zug.', style: VText.bodySStrong.copyWith(color: VColors.red)),
          ] else if (j != null && j.incomplete) ...[
            const VGap.xs(),
            Text('Beendet unterwegs: die Verspätung bis ${j.transferStationName ?? where} zählt.', style: VText.caption),
          ],
          const VGap.l(),
          const VRule.red(),
          if (result.newBadge != null) ...[
            const VGap.m(),
            Row(
              children: [
                BadgeIcon(badge: result.newBadge!, size: 44),
                const SizedBox(width: VSpace.s),
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
            const VGap.m(),
            const VRule(),
          ],
          const VGap.m(),
          if (hasClaim)
            _ClaimLine(ticket: ticket, amountCents: amountCents, ngoName: ngoName, counted: counted, ready: ready, pending: incident == null)
          else
            _NoClaimLine(delay: delay, ngoName: ngoName, onTrotzdem: ngo == null ? null : () => _trotzdem(context, ngo)),
        ],
      );
  }

  String _headline(int delay, bool cancelled, int points) {
    if (cancelled) return '60 Minuten. $points Geduldspunkte.';
    if (delay == 59) return '59 Minuten. Um eine Minute.';
    if (delay <= 0) return 'Pünktlich. Auch das gibt es.';
    if (delay == 1) return 'Eine Minute. Ein Geduldspunkt.';
    return '$delay Minuten. $points Geduldspunkte.';
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
            Expanded(child: Text(pending ? 'Anspruch wird geprüft' : 'Anspruch entstanden', style: VText.bodyS)),
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

class _NoClaimLine extends StatelessWidget {
  const _NoClaimLine({required this.delay, required this.ngoName, required this.onTrotzdem});
  final int delay;
  final String ngoName;
  final VoidCallback? onTrotzdem;

  @override
  Widget build(BuildContext context) {
    // E7: one minute short. The line, and nothing else.
    if (delay == 59) {
      return Text('Kein Anspruch, um eine Minute. Wir wissen.', style: VText.bodyStrong);
    }
    final text = delay <= 0 ? 'Kein Anspruch, keine Wartezeit. Morgen wieder.' : 'Kein Anspruch, aber $delay Minuten Geduld.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: VText.bodyStrong),
        const SizedBox(height: 4),
        Text('Ab 60 Minuten entsteht ein Anspruch. Bis dahin zählen die Punkte, und $ngoName freut sich auch so.', style: VText.caption),
        const SizedBox(height: 8),
        if (onTrotzdem != null)
          InkWell(
            onTap: onTrotzdem,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.open_in_new, size: 18, color: VColors.ink),
                  const SizedBox(width: 8),
                  Text('Trotzdem spenden', style: VText.bodyStrong),
                ],
              ),
            ),
          ),
      ],
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
    return VScreen(
      eyebrow: 'Keine Daten bei Ankunft',
      title: 'Wann bist du angekommen?',
      bottom: VPrimaryButton(label: 'Übernehmen', onTap: () => widget.onDone(_minutes)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.m(),
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
        ],
      ),
    );
  }
}
