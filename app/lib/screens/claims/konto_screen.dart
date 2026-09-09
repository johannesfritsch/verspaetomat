import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../mock/mock_data.dart' show Mock, IncidentStatus, TicketType;
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'claims_widgets.dart';

class _KontoData {
  const _KontoData(this.ledger, this.claims);
  final ApiIncidents ledger;
  final List<ApiClaim> claims;
}

/// Konto: the ledger of delays that matter.
class KontoScreen extends StatefulWidget {
  const KontoScreen({super.key});

  @override
  State<KontoScreen> createState() => _KontoScreenState();
}

class _KontoScreenState extends State<KontoScreen> {
  final _loader = LoaderController();
  bool _busy = false;

  Future<void> _prepare(BuildContext context, String desk) async {
    final session = RepoScope.read(context);
    setState(() => _busy = true);
    try {
      final draft = await session.repo.draftClaim(desk: desk);
      if (!context.mounted) return;
      await context.push('${Routes.antrag}?id=${draft.claim.id}&desk=${Uri.encodeComponent(desk)}', extra: draft);
      _loader.refresh();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Antrag nicht möglich: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _simulateReply(BuildContext context) async {
    final session = RepoScope.read(context);
    try {
      final r = await session.repo.simulateInbound(
        body: 'Sehr geehrte Damen und Herren,\n\nvielen Dank für Ihren Antrag. Es ergibt sich eine Entschädigung von insgesamt 4,50 EUR. Der Betrag wird auf das angegebene Konto überwiesen.\n\nMit freundlichen Grüßen\nIhr Servicecenter Fahrgastrechte',
      );
      if (!context.mounted) return;
      await context.push('${Routes.antwort}?mail=${r.mail.id}');
      _loader.refresh();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Keine Antwort möglich: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    return Loader<_KontoData>(
      controller: _loader,
      load: (repo) async {
        final ledger = await repo.incidents();
        List<ApiClaim> claims = const [];
        try {
          claims = await repo.claims();
        } catch (_) {}
        return _KontoData(ledger, claims);
      },
      builder: (context, data, refresh) {
        final ledger = data.ledger;
        final summary = ledger.summary;
        final byId = {for (final i in ledger.incidents) i.id: i};
        final readyDesk = summary.readyDesk;
        final submitted = ledger.incidents.where((i) => i.status == IncidentStatus.eingereicht).toList();
        final confirmed = ledger.incidents.where((i) => i.status == IncidentStatus.bestaetigt).toList();
        final closed = ledger.incidents.where((i) => i.status == IncidentStatus.abgelehnt || i.status == IncidentStatus.verfallen).toList();
        final ngoName = session.ngos.where((n) => n.id == session.me?.settings.ngoId).map((n) => n.name).firstOrNull ?? '–';
        final desks = _sortedDesks(summary.desks);

        return VScreen(
          showBack: false,
          eyebrow: 'Deine Ansprüche',
          title: 'Konto',
          trailing: Padding(
            padding: const EdgeInsets.only(right: VSpace.s),
            child: VIconButton(icon: Icons.refresh, onTap: refresh, color: VColors.ink2),
          ),
          bottom: readyDesk == null
              ? null
              : VPrimaryButton(
                  label: _busy ? 'Einen Moment …' : 'Antrag vorbereiten',
                  icon: Icons.edit_outlined,
                  onTap: _busy ? null : () => _prepare(context, readyDesk),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(summary: summary, ngoName: ngoName),
              if (summary.oldestOpen != null) ...[
                const VGap.m(),
                _DeadlineLine(oldest: summary.oldestOpen!),
              ],
              const VGap.xl(),
              if (desks.isEmpty) ...[
                const VSection('Offen'),
                const VGap.m(),
                Text('Nichts offen. Gut so.', style: VText.bodyStrong),
                const VGap.xs(),
                Text('Verspätungen ab 60 Minuten landen hier.', style: VText.caption),
              ] else
                for (final d in desks)
                  _DeskGroup(
                    desk: d,
                    incidents: d.incidentIds.map((id) => byId[id]).whereType<ApiIncident>().toList(),
                    showHeading: desks.length > 1,
                    minPayoutCents: summary.minPayoutCents,
                  ),
              if (desks.length > 1)
                Text('Ansprüche werden pro Bahnunternehmen gebündelt. Jedes Bündel muss 4 € erreichen.', style: VText.caption),
              if (submitted.isNotEmpty) ...[
                const VGap.xl(),
                VSection('Eingereicht', trailing: Text(fmtCents(summary.submittedCents), style: VText.captionInk)),
                for (final i in submitted)
                  IncidentRow(incident: i, note: _sentNote(data.claims, i), onTap: () => showEvidenceSheet(context, i)),
                if (!session.isLocal) ...[
                  const VGap.m(),
                  VDemoControl(
                    label: 'Antwort der Bahn simulieren',
                    icon: Icons.mark_email_unread_outlined,
                    onTap: () => _simulateReply(context),
                  ),
                ],
              ],
              if (confirmed.isNotEmpty) ...[
                const VGap.xl(),
                VSection('Bestätigt', trailing: Text(fmtCents(summary.confirmedCents), style: VText.captionInk)),
                for (final i in confirmed) IncidentRow(incident: i, onTap: () => showEvidenceSheet(context, i)),
              ],
              if (closed.isNotEmpty) ...[
                const VGap.xl(),
                const VSection('Abgeschlossen'),
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
      },
    );
  }

  String? _sentNote(List<ApiClaim> claims, ApiIncident i) {
    final claim = claims.where((c) => c.id == i.claimId || c.incidentIds.contains(i.id)).firstOrNull;
    final sent = claim?.sentAt;
    if (sent == null) return 'Abgeschickt · Antwort in etwa 4 Wochen';
    return 'Abgeschickt ${Mock.shortDate(sent.toLocal())} · Antwort in etwa 4 Wochen';
  }

  List<ApiDeskSummary> _sortedDesks(List<ApiDeskSummary> desks) {
    final list = List.of(desks);
    list.sort((a, b) {
      final as = a.desk.startsWith('Service') ? 0 : 1;
      final bs = b.desk.startsWith('Service') ? 0 : 1;
      return as.compareTo(bs);
    });
    return list;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.summary, required this.ngoName});
  final ApiIncidentSummary summary;
  final String ngoName;

  @override
  Widget build(BuildContext context) {
    final readyDesk = summary.readyDesk;
    final openTotal = summary.desks.fold(0, (s, d) => s + d.openCents);
    final openCount = summary.desks.fold(0, (s, d) => s + d.incidentIds.length);

    String big;
    String line;
    if (readyDesk != null) {
      final d = summary.desks.firstWhere((d) => d.desk == readyDesk);
      big = fmtCents(d.openCents);
      line = 'Bereit. ${d.incidentIds.length == 1 ? 'Eine Verspätung' : '${d.incidentIds.length} Verspätungen'}, ein Antrag.';
    } else if (openCount > 0) {
      final missing = (summary.minPayoutCents - openTotal).clamp(0, summary.minPayoutCents);
      big = fmtCents(openTotal);
      line = 'Gesammelt · noch ${fmtCents(missing)} bis zur Auszahlung';
    } else {
      big = fmtCents(0);
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
        VKeyValue('Bestätigt, insgesamt', fmtCents(summary.confirmedCents), strong: true),
        const VRule(),
        VKeyValue('Eingereicht, unterwegs', fmtCents(summary.submittedCents)),
        const VRule(),
        VKeyValue('Zweck', ngoName),
      ],
    );
  }
}

class _DeadlineLine extends StatelessWidget {
  const _DeadlineLine({required this.oldest});
  final ApiOldestOpen oldest;

  @override
  Widget build(BuildContext context) {
    final days = oldest.daysLeft;
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
            '$text ${oldest.line} vom ${Mock.monthDate(oldest.date)}',
            style: VText.bodyS.copyWith(color: urgent ? VColors.red : VColors.ink2, fontWeight: urgent ? FontWeight.w600 : FontWeight.w400),
          ),
        ),
      ],
    );
  }
}

class _DeskGroup extends StatelessWidget {
  const _DeskGroup({required this.desk, required this.incidents, required this.showHeading, required this.minPayoutCents});
  final ApiDeskSummary desk;
  final List<ApiIncident> incidents;
  final bool showHeading;
  final int minPayoutCents;

  @override
  Widget build(BuildContext context) {
    final ready = desk.ready;
    final hasSingle = incidents.any((i) => i.ticket == TicketType.einzelfahrkarte);
    final label = showHeading ? 'Offen · ${deskDisplay(desk.desk)}' : 'Offen';
    final needed = (minPayoutCents / 150).ceil();
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VSection(
            label,
            trailing: ready
                ? const VChip('bereit', tone: VTone.ink)
                : Text(hasSingle ? fmtCents(desk.openCents) : '${fmtCents(desk.openCents)} von ${fmtCents(minPayoutCents)}', style: VText.captionInk),
          ),
          for (final i in incidents) IncidentRow(incident: i, onTap: () => showEvidenceSheet(context, i)),
          if (!ready) ...[
            const VGap.s(),
            Row(
              children: [
                VDots(filled: incidents.length.clamp(0, needed), total: needed),
                const SizedBox(width: 10),
                Text('${incidents.length} von $needed · noch ${fmtCents(desk.missingCents)} · ${deskDisplay(desk.desk)}', style: VText.caption),
              ],
            ),
          ],
          if (showHeading && desk.desk != 'Servicecenter Fahrgastrechte') ...[
            const VGap.xs(),
            Text('Eigene Stelle. Geht als eigener Antrag raus.', style: VText.caption),
          ],
        ],
      ),
    );
  }
}
