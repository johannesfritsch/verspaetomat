import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart';
import '../../router.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart';

/// The reveal. The only screen allowed to feel like a reward.
///
/// `variant` = 68 | 14 | 59 | ausfall | nodata; without it the screen shows
/// what DemoState says about the last ride.
class AngekommenScreen extends StatefulWidget {
  const AngekommenScreen({super.key, this.variant});
  final String? variant;

  @override
  State<AngekommenScreen> createState() => _AngekommenScreenState();
}

class _AngekommenScreenState extends State<AngekommenScreen> {
  int? _enteredDelay; // E3

  @override
  Widget build(BuildContext context) {
    final state = DemoScope.of(context);
    final v = widget.variant;

    if (v == 'nodata' && _enteredDelay == null) {
      return _NoDataStep(onDone: (d) => setState(() => _enteredDelay = d));
    }

    final cancelled = v == 'ausfall' || (v == null && state.finalCancelled);
    final selfEntered = v == 'nodata' || (v == null && state.finalSelfEntered);
    final delay = switch (v) {
      '68' => 68,
      '14' => 14,
      '59' => 59,
      'ausfall' => 60,
      'nodata' => _enteredDelay ?? 0,
      _ => state.finalDelay ?? 0,
    };
    final line = state.trip?.departure.line ?? 'RE 7';
    final from = state.trip?.fromStation ?? 'Köln Hbf';
    final to = state.trip?.exitStop.name ?? 'Münster (Westf) Hbf';
    final planned = state.trip?.exitStop.planned ?? const TimeOfDay(hour: 9, minute: 38);
    final actual = addMinutes(planned, delay);
    final cause = v == null ? state.liveCause : (delay >= 60 ? 'Stellwerksstörung' : null);
    final ticket = state.ticket;
    final ngo = state.ngo;

    final badge = v == null
        ? state.newBadge
        : (delay >= 60 && !cancelled ? Mock.badges.firstWhere((b) => b.id == 'stunde') : null);

    final hasClaim = delay >= 60 || cancelled;
    final desk = Mock.deskFor(state.trip?.departure.operator ?? 'National Express');
    final openCount = (state.openByDesk[desk] ?? []).length;
    final counted = hasClaim ? openCount.clamp(1, 3) : openCount;
    final ready = state.bundleReady(desk);

    return VScreen(
      showBack: false,
      trailing: Text('${Mock.shortDate(Mock.today)} · ${fmtTime(actual)}', style: VText.caption),
      eyebrow: 'Angekommen',
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasClaim && ticket != TicketType.deutschlandticket || (hasClaim && ready))
            VPrimaryButton(label: 'Jetzt einreichen', onTap: () => context.push('${Routes.antrag}?desk=${Uri.encodeComponent(desk)}'))
          else if (!hasClaim)
            VPrimaryButton(label: 'Trotzdem spenden', icon: Icons.open_in_new, onTap: () => _trotzdem(context, ngo))
          else
            VPrimaryButton(label: 'Konto ansehen', onTap: () => context.go(Routes.konto)),
          Row(
            children: [
              Expanded(
                child: VGhostButton(
                  label: 'Teilen',
                  icon: Icons.ios_share,
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Karte geteilt: „$line, +$delay, $to“. (Demo)'))),
                ),
              ),
              Expanded(
                child: VGhostButton(
                  label: 'Fertig',
                  onTap: () {
                    state.dismissArrival();
                    context.go(Routes.bahnsteig);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$line · $from → $to', style: VText.bodyStrong),
          const VGap.l(),
          CountUpDelay(delay, cancelled: cancelled),
          const VGap.m(),
          Text(_headline(delay, cancelled), style: VText.h2),
          const VGap.xs(),
          Text(
            cancelled
                ? 'Reise nicht angetreten. 60 Minuten angerechnet.'
                : 'Ankunft ${fmtTime(actual)} statt ${fmtTime(planned)}${cause != null ? ' · $cause' : ''}${selfEntered ? ' · selbst eingetragen' : ''}',
            style: VText.bodyS.copyWith(color: VColors.ink2),
          ),
          const VGap.l(),
          const VRule.red(),
          if (badge != null) ...[
            const VGap.m(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text('Neues Abzeichen', style: VText.bodyS)),
                Text(badge.name, style: VText.bodyStrong.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const VGap.m(),
            const VRule(),
          ],
          const VGap.m(),
          if (hasClaim) _ClaimLine(ticket: ticket, delay: delay, ngo: ngo, counted: counted, ready: ready) else _NoClaimLine(delay: delay, ngo: ngo),
        ],
      ),
    );
  }

  String _headline(int delay, bool cancelled) {
    if (cancelled) return '60 Minuten. 60 Geduldspunkte.';
    if (delay == 59) return '59 Minuten. Um eine Minute.';
    if (delay <= 0) return 'Pünktlich. Auch das gibt es.';
    if (delay == 1) return 'Eine Minute. Ein Geduldspunkt.';
    return '$delay Minuten. $delay Geduldspunkte.';
  }

  void _trotzdem(BuildContext context, Ngo ngo) {
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
  const _ClaimLine({required this.ticket, required this.delay, required this.ngo, required this.counted, required this.ready});
  final TicketType ticket;
  final int delay;
  final Ngo ngo;
  final int counted;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final (amount, sub) = switch (ticket) {
      TicketType.deutschlandticket => (1.5, null),
      TicketType.zeitkarte => (1.5, 'Zeitkarte Nahverkehr'),
      TicketType.einzelfahrkarte => (
          (delay >= 120 ? 0.5 : 0.25) * 39.9,
          '${delay >= 120 ? '50' : '25'} % von ${fmtEuro(39.9)}',
        ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text('Anspruch entstanden', style: VText.bodyS)),
            Text(ticket == TicketType.einzelfahrkarte ? 'ca. ${fmtEuro(amount)}' : fmtEuro(amount), style: VText.numberM),
          ],
        ),
        const SizedBox(height: 6),
        Text('für die ${ngo.name}${sub != null ? ' · $sub' : ''}', style: VText.bodyS.copyWith(color: VColors.ink2)),
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
  const _NoClaimLine({required this.delay, required this.ngo});
  final int delay;
  final Ngo ngo;

  @override
  Widget build(BuildContext context) {
    final text = delay == 59
        ? 'Kein Anspruch, um eine Minute. Wir wissen.'
        : delay <= 0
            ? 'Kein Anspruch, keine Wartezeit. Morgen wieder.'
            : 'Kein Anspruch, aber $delay Minuten Geduld.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: VText.bodyStrong),
        const SizedBox(height: 4),
        Text('Ab 60 Minuten entsteht ein Anspruch. Bis dahin zählen die Punkte, und ${ngo.name} freut sich auch so.', style: VText.caption),
      ],
    );
  }
}

/// E3: no data at arrival. Ask for the actual time, preset to the plan.
class _NoDataStep extends StatefulWidget {
  const _NoDataStep({required this.onDone});
  final ValueChanged<int> onDone;

  @override
  State<_NoDataStep> createState() => _NoDataStepState();
}

class _NoDataStepState extends State<_NoDataStep> {
  static const _planned = TimeOfDay(hour: 9, minute: 38);
  int _minutes = 0;

  @override
  Widget build(BuildContext context) {
    final actual = addMinutes(_planned, _minutes);
    return VScreen(
      eyebrow: 'Keine Daten bei Ankunft',
      title: 'Wann bist du angekommen?',
      bottom: VPrimaryButton(label: 'Übernehmen', onTap: () => widget.onDone(_minutes)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.m(),
          Text('Der Live-Feed hat den RE 7 verloren. Geplant war Münster (Westf) Hbf um ${fmtTime(_planned)}.', style: VText.body.copyWith(color: VColors.ink2)),
          const VGap.xl(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              VIconButton(icon: Icons.remove, onTap: () => setState(() => _minutes = (_minutes - 5).clamp(0, 300))),
              Expanded(
                child: Column(
                  children: [
                    Text(fmtTime(actual), style: VText.number),
                    const SizedBox(height: 4),
                    VDelay(_minutes, size: VDelaySize.small),
                  ],
                ),
              ),
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
