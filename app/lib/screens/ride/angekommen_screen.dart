import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart' show TicketType;
import '../../repo/app_repository.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart';

/// The reveal. The only screen allowed to feel like a reward.
///
/// Fed by an [ApiArrivalResult] (from Unterwegs or the E1 flow), or by the
/// last arrival the repository knows. `variant` = 68 | 14 | 59 | ausfall | nodata
/// drives the showcase in demo mode.
class AngekommenScreen extends StatefulWidget {
  const AngekommenScreen({super.key, this.variant, this.result});
  final String? variant;
  final ApiArrivalResult? result;

  @override
  State<AngekommenScreen> createState() => _AngekommenScreenState();
}

class _AngekommenScreenState extends State<AngekommenScreen> {
  ApiArrivalResult? _result;
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
      final stations = (await repo.nearbyStations()).stations;
      final deps = await repo.departures(stations.first.id);
      final d = deps.firstWhere((x) => !x.cancelled, orElse: () => deps.first);
      final trip = await repo.trip(d.tripId);
      var exitIdx = trip.stops.indexWhere((s) => s.name.startsWith('Münster'));
      if (exitIdx < 1) exitIdx = trip.stops.length - 1;
      final exit = trip.stops[exitIdx];
      await repo.checkIn(CheckInRequest(
        tripId: d.tripId,
        fromStationId: stations.first.id,
        fromStationName: stations.first.name,
        exitStationId: exit.stationId ?? exit.name,
        exitStationName: exit.name,
      ));
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
      return VScreen(
        title: 'Angekommen',
        child: Column(
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
        ),
      );
    }

    final r = result.ride;
    final cancelled = r.cancelled;
    final delay = r.finalDelayMinutes ?? 0;
    final points = r.points > 0 ? r.points : (cancelled ? 60 : delay);
    final planned = r.plannedArrival;
    final actual = planned?.add(Duration(minutes: delay));
    final incident = result.incident;
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

    return VScreen(
      showBack: false,
      trailing: Text('${fmtDay(actual ?? DateTime.now())} · ${fmtLocal(actual)}', style: VText.caption),
      eyebrow: 'Angekommen',
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canFile) VPrimaryButton(label: 'Jetzt einreichen', onTap: () => context.push('${Routes.antrag}?desk=${Uri.encodeComponent(desk)}')),
          Row(
            children: [
              Expanded(
                child: VGhostButton(
                  label: 'Teilen',
                  icon: Icons.ios_share,
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Karte geteilt: „${r.line}, +$delay, ${r.exitStationName}“. (Demo)'))),
                ),
              ),
              Expanded(child: VGhostButton(label: 'Fertig', onTap: _finish)),
            ],
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${r.line} · ${r.fromStationName} → ${r.exitStationName}', style: VText.bodyStrong),
          const VGap.l(),
          CountUpDelay(delay, cancelled: cancelled),
          const VGap.m(),
          Text(_headline(delay, cancelled, points), style: VText.h2),
          const VGap.xs(),
          Text(
            cancelled
                ? 'Reise nicht angetreten. 60 Minuten angerechnet.'
                : 'Ankunft ${fmtLocal(actual)} statt ${fmtLocal(planned)}${r.cause != null ? ' · ${r.cause}' : ''}${r.selfEntered ? ' · selbst eingetragen' : ''}',
            style: VText.bodyS.copyWith(color: VColors.ink2),
          ),
          const VGap.l(),
          const VRule.red(),
          if (result.newBadge != null) ...[
            const VGap.m(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text('Neues Abzeichen', style: VText.bodyS)),
                Text(result.newBadge!.name, style: VText.bodyStrong.copyWith(fontWeight: FontWeight.w800)),
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
      ),
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
