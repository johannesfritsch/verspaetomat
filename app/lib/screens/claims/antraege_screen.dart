import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/events.dart';
import '../../api/models.dart';
import '../../mock/mock_data.dart' show Mock, IncidentStatus, TicketType;
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../community/community_widgets.dart' show TabHeader;
import 'claims_widgets.dart';
import 'pdf_view.dart';

class _AntraegeData {
  const _AntraegeData(this.ledger, this.claims, this.mails);
  final ApiIncidents ledger;
  final List<ApiClaim> claims;
  final List<ApiMail> mails;
}

/// Anträge: what is happening with my claims. The bundle being collected, the
/// claims that are out with their mail threads, and the closed ones.
/// Decided 10 September 2026; replaces Konto in the nav.
class AntraegeScreen extends StatefulWidget {
  const AntraegeScreen({super.key, this.claimId});

  /// Scrolls to this claim after loading (pushes for railway mail land here).
  final String? claimId;

  @override
  State<AntraegeScreen> createState() => _AntraegeScreenState();
}

class _AntraegeScreenState extends State<AntraegeScreen> {
  StreamSubscription<AppEvent>? _eventSub;
  final _loader = LoaderController();
  final _claimKeys = <String, GlobalKey>{};
  bool _busy = false;
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _eventSub = RepoScope.read(context).events.listen((e) {
      if (mounted && e.touchesLedger) _loader.refreshSoon();
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _loader.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String id) => _claimKeys.putIfAbsent(id, GlobalKey.new);

  void _scrollToClaim() {
    final id = widget.claimId;
    if (id == null || _scrolled) return;
    final ctx = _claimKeys[id]?.currentContext;
    if (ctx == null) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ctx.mounted) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.05);
    });
  }

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
      await session.repo.simulateInbound(
        body: 'Sehr geehrte Damen und Herren,\n\nvielen Dank für Ihren Antrag. Es ergibt sich eine Entschädigung von insgesamt 4,50 EUR. Der Betrag wird auf das angegebene Konto überwiesen.\n\nMit freundlichen Grüßen\nIhr Servicecenter Fahrgastrechte',
      );
      _loader.refresh();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Keine Antwort möglich: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    return Loader<_AntraegeData>(
      controller: _loader,
      load: (repo) async {
        final ledger = await repo.incidents();
        List<ApiClaim> claims = const [];
        List<ApiMail> mails = const [];
        try {
          claims = await repo.claims();
        } catch (_) {}
        try {
          mails = await repo.mails();
        } catch (_) {}
        return _AntraegeData(ledger, claims, mails);
      },
      builder: (context, data, refresh) {
        final ledger = data.ledger;
        final summary = ledger.summary;
        final byId = {for (final i in ledger.incidents) i.id: i};
        final readyDesk = summary.readyDesk;
        final desks = _sortedDesks(summary.desks);
        final claims = data.claims.where((c) => c.status != ApiClaimStatus.draft).toList()
          ..sort((a, b) => (b.sentAt ?? DateTime(0)).compareTo(a.sentAt ?? DateTime(0)));
        final out = claims.where((c) => c.status == ApiClaimStatus.sent || c.status == ApiClaimStatus.question || c.status == ApiClaimStatus.bounced).toList();
        final accepted = claims.where((c) => c.status == ApiClaimStatus.accepted).toList();
        final rejected = claims.where((c) => c.status == ApiClaimStatus.rejected).toList();
        final expired = ledger.incidents.where((i) => i.status == IncidentStatus.verfallen).toList();
        final openCount = summary.desks.fold(0, (s, d) => s + d.incidentIds.length);
        final caption = [
          if (openCount > 0) '$openCount ${openCount == 1 ? 'Fall' : 'Fälle'} gesammelt',
          if (out.isNotEmpty) '${out.length} ${out.length == 1 ? 'Antrag' : 'Anträge'} unterwegs',
          if (openCount == 0 && out.isEmpty) 'Nichts offen',
        ].join(' · ');
        _scrollToClaim();

        return VScreen(
          showBack: false,
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
              TabHeader(title: 'Anträge', caption: caption, onSettings: () => context.push(Routes.einstellungen).then((_) => refresh())),
              const VGap.l(),

              // (a) The bundle being collected.
              if (desks.isEmpty) ...[
                const VSection('Sammeln'),
                const VGap.m(),
                Text('Nichts offen. Gut so.', style: VText.bodyStrong),
                const VGap.xs(),
                Text('Verspätungen ab 60 Minuten landen hier. Ab 4 € geht ein Antrag raus.', style: VText.caption),
              ] else ...[
                if (summary.oldestOpen != null) ...[
                  _DeadlineLine(oldest: summary.oldestOpen!),
                  const VGap.m(),
                ],
                for (final d in desks)
                  _DeskGroup(
                    desk: d,
                    incidents: d.incidentIds.map((id) => byId[id]).whereType<ApiIncident>().toList(),
                    showHeading: desks.length > 1,
                    minPayoutCents: summary.minPayoutCents,
                  ),
                if (desks.length > 1) Text('Ansprüche werden pro Bahnunternehmen gebündelt. Jedes Bündel muss 4 € erreichen.', style: VText.caption),
              ],

              // (b) Claims that are out.
              if (out.isNotEmpty) ...[
                const VGap.xl(),
                VSection('Eingereicht', trailing: Text(fmtCents(out.fold(0, (s, c) => s + c.amountClaimedCents)), style: VText.captionInk)),
                const VGap.m(),
                for (final c in out) _ClaimCard(key: _keyFor(c.id), claim: c, incidents: _incidentsOf(c, byId), mails: _mailsOf(c, data.mails), onChanged: refresh),
                if (!session.isLocal) ...[
                  const VGap.s(),
                  VDemoControl(label: 'Antwort der Bahn simulieren', icon: Icons.mark_email_unread_outlined, onTap: () => _simulateReply(context)),
                ],
              ],

              // (c) Closed claims.
              if (accepted.isNotEmpty) ...[
                const VGap.xl(),
                VSection('Bestätigt', trailing: Text(fmtCents(summary.confirmedCents), style: VText.captionInk)),
                const VGap.m(),
                for (final c in accepted) _ClaimCard(key: _keyFor(c.id), claim: c, incidents: _incidentsOf(c, byId), mails: _mailsOf(c, data.mails), onChanged: refresh),
              ],
              if (rejected.isNotEmpty || expired.isNotEmpty) ...[
                const VGap.xl(),
                const VSection('Abgeschlossen'),
                const VGap.m(),
                for (final c in rejected) _ClaimCard(key: _keyFor(c.id), claim: c, incidents: _incidentsOf(c, byId), mails: _mailsOf(c, data.mails), onChanged: refresh),
                for (final i in expired) IncidentRow(incident: i, showStatus: true, onTap: () => showEvidenceSheet(context, i)),
                if (expired.isNotEmpty) ...[
                  const VGap.s(),
                  Text('Verfallen heißt: die Frist ist um, bevor 4 € zusammenkamen. Die Minuten und Punkte bleiben.', style: VText.caption),
                ],
              ],
              const VGap.xl(),
            ],
          ),
        );
      },
    );
  }

  List<ApiIncident> _incidentsOf(ApiClaim c, Map<String, ApiIncident> byId) {
    final list = c.incidentIds.map((id) => byId[id]).whereType<ApiIncident>().toList();
    if (list.isEmpty) return byId.values.where((i) => i.claimId == c.id).toList();
    return list;
  }

  /// The mails of a claim: matched by claim id, else by shared incidents. Oldest first.
  List<ApiMail> _mailsOf(ApiClaim c, List<ApiMail> mails) {
    final list = mails.where((m) => m.claimId == c.id || (m.claimId == null && m.incidentIds.any(c.incidentIds.contains))).toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
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

/// One claim: what went out, what came back, what to do.
class _ClaimCard extends StatelessWidget {
  const _ClaimCard({super.key, required this.claim, required this.incidents, required this.mails, required this.onChanged});
  final ApiClaim claim;
  final List<ApiIncident> incidents;
  final List<ApiMail> mails;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = claim;
    final last = mails.isEmpty ? null : mails.last;
    final (chipLabel, tone) = switch (c.status) {
      ApiClaimStatus.accepted => ('bestätigt', VTone.green),
      ApiClaimStatus.rejected => ('abgelehnt', VTone.red),
      ApiClaimStatus.question => ('Rückfrage', VTone.red),
      ApiClaimStatus.bounced => ('nicht zugestellt', VTone.red),
      _ => ('eingereicht', VTone.ink),
    };
    final amount = c.status == ApiClaimStatus.accepted ? (c.amountConfirmedCents ?? c.amountClaimedCents) : c.amountClaimedCents;
    final when = c.sentAt != null ? 'Antrag vom ${Mock.shortDate(c.sentAt!.toLocal())}' : 'Antrag';
    final line = switch (c.status) {
      ApiClaimStatus.accepted => '${fmtCents(amount)} überwiesen',
      ApiClaimStatus.rejected => 'Die Bahn zahlt nicht. Widerspruch möglich.',
      ApiClaimStatus.question => 'Die Bahn braucht noch etwas von dir.',
      ApiClaimStatus.bounced => 'Die Mail kam zurück. Bitte Adresse prüfen.',
      _ => c.expectedReplyBy != null ? 'Antwort bis ${Mock.shortDate(c.expectedReplyBy!.toLocal())}' : 'Antwort in etwa 4 Wochen',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.m),
      child: Container(
        padding: const EdgeInsets.all(VSpace.m),
        decoration: BoxDecoration(border: Border.all(color: VColors.rule, width: 1.5), borderRadius: BorderRadius.circular(4)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(when, style: VText.title)),
                Text(fmtCents(amount), style: VText.numberM),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                VChip(chipLabel, tone: tone),
                const SizedBox(width: 8),
                Expanded(child: Text('$line · ${deskDisplay(c.desk)}', style: VText.caption, maxLines: 2, overflow: TextOverflow.ellipsis)),
              ],
            ),
            if (incidents.isNotEmpty) ...[
              const VGap.s(),
              for (final i in incidents) IncidentRow(incident: i, onTap: () => showEvidenceSheet(context, i)),
            ],
            if (last != null) ...[
              const VGap.m(),
              Text(
                last.direction == ApiMailDirection.inbound ? 'POST VON DER BAHN · ${Mock.shortDate(last.date.toLocal())}' : 'DEINE MAIL · ${Mock.shortDate(last.date.toLocal())}',
                style: VText.eyebrow.copyWith(color: last.direction == ApiMailDirection.inbound ? VColors.red : VColors.ink2),
              ),
              const SizedBox(height: 6),
              MailView(mail: last, compact: true),
            ],
            const VGap.s(),
            Wrap(
              spacing: 4,
              children: [
                if (last != null && last.direction == ApiMailDirection.inbound && (last.outcome == ApiMailOutcome.question || last.outcome == ApiMailOutcome.rejected))
                  VOutlineButton(
                    label: last.outcome == ApiMailOutcome.question ? 'Antworten' : 'Widerspruch',
                    icon: Icons.reply,
                    onTap: () => context.push('${Routes.antwort}?mail=${last.id}').then((_) => onChanged()),
                  ),
                if (mails.isNotEmpty)
                  VGhostButton(
                    label: mails.length == 1 ? 'Ganze Mail lesen' : 'Alle ${mails.length} Nachrichten',
                    icon: Icons.mail_outline,
                    onTap: () => context.push('${Routes.antwort}?mail=${last!.id}').then((_) => onChanged()),
                  ),
                VGhostButton(label: 'PDF ansehen', icon: Icons.picture_as_pdf_outlined, onTap: () => ClaimPdfPage.open(context, c.id)),
              ],
            ),
          ],
        ),
      ),
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
    final label = showHeading ? 'Sammeln · ${deskDisplay(desk.desk)}' : 'Sammeln';
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
                Expanded(child: Text('${incidents.length} von $needed · noch ${fmtCents(desk.missingCents)} · ${deskDisplay(desk.desk)}', style: VText.caption)),
              ],
            ),
          ] else ...[
            const VGap.s(),
            Text('${fmtCents(desk.openCents)} zusammen. Der Antrag kann raus.', style: VText.caption),
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
