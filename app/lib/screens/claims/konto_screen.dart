import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart';
import '../../router.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'claims_widgets.dart';

/// Konto: the ledger ("Spendenkonto") of delays that matter.
class KontoScreen extends StatelessWidget {
  const KontoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = DemoScope.of(context);
    final open = state.openByDesk;
    final readyDesk = state.readyDesk;
    final submitted = state.incidents.where((i) => i.status == IncidentStatus.eingereicht).toList();
    final confirmed = state.incidents.where((i) => i.status == IncidentStatus.bestaetigt).toList();
    final closed = state.incidents
        .where((i) => i.status == IncidentStatus.abgelehnt || i.status == IncidentStatus.verfallen)
        .toList();
    final days = state.daysUntilOldestExpires;

    return VScreen(
      showBack: false,
      eyebrow: 'Spendenkonto',
      title: 'Konto',
      trailing: const Padding(padding: EdgeInsets.only(right: VSpace.s), child: VStationClock(size: 36)),
      bottom: readyDesk == null
          ? null
          : VPrimaryButton(
              label: 'Antrag vorbereiten',
              icon: Icons.edit_outlined,
              onTap: () {
                state.startClaim(readyDesk);
                context.push('${Routes.antrag}?desk=${Uri.encodeComponent(readyDesk)}');
              },
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(state: state),
          if (days != null) ...[
            const VGap.m(),
            _DeadlineLine(days: days, incident: state.oldestOpen!),
          ],
          const VGap.xl(),
          if (open.isEmpty) ...[
            VSection('Offen'),
            const VGap.m(),
            Text('Nichts offen. Gut so.', style: VText.bodyStrong),
            const VGap.xs(),
            Text('Verspätungen ab 60 Minuten landen hier.', style: VText.caption),
          ] else
            for (final entry in _sortedDesks(open))
              _DeskGroup(desk: entry.key, incidents: entry.value, showHeading: open.length > 1, state: state),
          if (submitted.isNotEmpty) ...[
            const VGap.xl(),
            VSection('Eingereicht', trailing: Text(fmtEuro(state.submittedTotal), style: VText.captionInk)),
            for (final i in submitted) IncidentRow(incident: i, onTap: () => showEvidenceSheet(context, i)),
            const VGap.m(),
            VDemoControl(
              label: 'Antwort der Bahn simulieren',
              icon: Icons.mark_email_unread_outlined,
              onTap: () {
                final mail = state.receiveReply();
                if (mail != null) context.push('${Routes.antwort}?mail=${mail.id}');
              },
            ),
          ],
          if (confirmed.isNotEmpty) ...[
            const VGap.xl(),
            VSection('Bestätigt', trailing: Text(fmtEuro(state.confirmedTotal), style: VText.captionInk)),
            for (final i in confirmed) IncidentRow(incident: i, onTap: () => showEvidenceSheet(context, i)),
          ],
          if (closed.isNotEmpty) ...[
            const VGap.xl(),
            VSection('Abgeschlossen'),
            for (final i in closed) IncidentRow(incident: i, onTap: () => showEvidenceSheet(context, i)),
            const VGap.s(),
            Text(
              'Verfallen heißt: die Frist ist um, bevor 4 € zusammenkamen. Die Minuten und Punkte bleiben.',
              style: VText.caption,
            ),
          ],
          const VGap.xl(),
        ],
      ),
    );
  }

  List<MapEntry<String, List<Incident>>> _sortedDesks(Map<String, List<Incident>> open) {
    final list = open.entries.toList();
    list.sort((a, b) {
      final as = a.key.startsWith('Service') ? 0 : 1;
      final bs = b.key.startsWith('Service') ? 0 : 1;
      return as.compareTo(bs);
    });
    return list;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});
  final DemoState state;

  @override
  Widget build(BuildContext context) {
    final readyDesk = state.readyDesk;
    final open = state.openIncidents;
    final openTotal = open.fold(0.0, (s, i) => s + i.amount);

    String big;
    String line;
    if (readyDesk != null) {
      big = fmtEuro(state.openAmountFor(readyDesk));
      line = 'Bereit. ${open.length == 1 ? 'Eine Verspätung' : '${open.length} Verspätungen'}, ein Antrag.';
    } else if (open.isNotEmpty) {
      final missing = (4.0 - openTotal).clamp(0.0, 4.0);
      big = fmtEuro(openTotal);
      line = 'Gesammelt · noch ${fmtEuro(missing)} bis zur Auszahlung';
    } else {
      big = fmtEuro(0);
      line = 'Nichts gesammelt';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VGap.s(),
        Text(big, style: VText.number),
        const VGap.s(),
        Text(line, style: VText.bodyS.copyWith(color: VColors.ink2)),
        const VGap.m(),
        const VRule.red(),
        Row(
          children: [
            Expanded(child: VKeyValue('Bestätigt, insgesamt', fmtEuro(state.confirmedTotal), strong: true)),
          ],
        ),
        const VRule(),
        VKeyValue('Eingereicht, unterwegs', fmtEuro(state.submittedTotal)),
        const VRule(),
        VKeyValue('Zweck', state.ngo.name),
      ],
    );
  }
}

class _DeadlineLine extends StatelessWidget {
  const _DeadlineLine({required this.days, required this.incident});
  final int days;
  final Incident incident;

  @override
  Widget build(BuildContext context) {
    final urgent = days < 30;
    final text = days <= 0
        ? 'Älteste Verspätung ist verfallen.'
        : days < 14
            ? 'Älteste Verspätung verfällt in $days Tagen.'
            : 'Älteste Verspätung verfällt in ${(days / 7).round()} Wochen.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.schedule, size: 18, color: urgent ? VColors.red : VColors.ink2),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$text ${incident.line} vom ${Mock.monthDate(incident.date)}',
            style: VText.bodyS.copyWith(color: urgent ? VColors.red : VColors.ink2, fontWeight: urgent ? FontWeight.w600 : FontWeight.w400),
          ),
        ),
      ],
    );
  }
}

class _DeskGroup extends StatelessWidget {
  const _DeskGroup({required this.desk, required this.incidents, required this.showHeading, required this.state});
  final String desk;
  final List<Incident> incidents;
  final bool showHeading;
  final DemoState state;

  @override
  Widget build(BuildContext context) {
    final ready = state.bundleReady(desk);
    final amount = state.openAmountFor(desk);
    final hasSingle = incidents.any((i) => i.ticket == TicketType.einzelfahrkarte);
    final label = showHeading ? 'Offen · ${_shortDesk(desk)}' : 'Offen';
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VSection(
            label,
            trailing: ready
                ? const VChip('bereit', tone: VTone.ink)
                : Text(hasSingle ? fmtEuro(amount) : '${fmtEuro(amount)} von 4,00 €', style: VText.captionInk),
          ),
          for (final i in incidents) IncidentRow(incident: i, onTap: () => showEvidenceSheet(context, i)),
          if (!ready) ...[
            const VGap.s(),
            Row(
              children: [
                VDots(filled: incidents.length, total: 3),
                const SizedBox(width: 10),
                Text('${incidents.length} von 3 · ${_shortDesk(desk)}', style: VText.caption),
              ],
            ),
          ],
          if (showHeading && desk != 'Servicecenter Fahrgastrechte') ...[
            const VGap.xs(),
            Text('Eigene Stelle. Geht als eigener Antrag raus.', style: VText.caption),
          ],
        ],
      ),
    );
  }

  String _shortDesk(String d) => d == 'Servicecenter Fahrgastrechte' ? 'Servicecenter (DB, ODEG, NEB …)' : d;
}
