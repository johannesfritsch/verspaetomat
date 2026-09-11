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
import '../community/community_widgets.dart' show TabHeader, pickNgo;
import '../ride/checkin_launcher.dart' show startCheckin;
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

  /// Takes one case out of every open bundle, or puts it back (docs/21 §4).
  Future<void> _discard(BuildContext context, String id, String reason) async {
    final session = RepoScope.read(context);
    try {
      await session.repo.discardIncident(id, reason);
      _loader.refresh();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ging nicht: $e')));
    }
  }

  Future<void> _restore(BuildContext context, String id) async {
    final session = RepoScope.read(context);
    try {
      await session.repo.restoreIncident(id);
      _loader.refresh();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ging nicht: $e')));
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
        final desks = _sortedDesks(summary.desks);
        final claims = data.claims.where((c) => c.status != ApiClaimStatus.draft).toList()
          ..sort((a, b) => (b.sentAt ?? DateTime(0)).compareTo(a.sentAt ?? DateTime(0)));
        final out = claims.where((c) => c.status == ApiClaimStatus.sent || c.status == ApiClaimStatus.question || c.status == ApiClaimStatus.bounced).toList();
        final expired = ledger.incidents.where((i) => !i.discarded && i.status == IncidentStatus.verfallen).toList();
        final discarded = ledger.incidents.where((i) => i.discarded).toList();
        final nothingAtAll = ledger.incidents.isEmpty && claims.isEmpty;
        final openCount = summary.desks.fold(0, (s, d) => s + d.incidentIds.length);
        final caption = [
          if (openCount > 0) '$openCount ${openCount == 1 ? 'Fall' : 'Fälle'} gesammelt',
          if (out.isNotEmpty) '${out.length} ${out.length == 1 ? 'Antrag' : 'Anträge'} unterwegs',
          if (openCount == 0 && out.isEmpty) 'Nichts offen',
        ].join(' · ');
        _scrollToClaim();

        String? ngoName(String id) => session.ngos.where((n) => n.id == id).map((n) => n.name).firstOrNull;
        final cards = <Widget>[
          // The bundle(s) being collected first (docs/18); nothing at all gets the explainer (docs/21 §5).
          if (nothingAtAll)
            _EmptyAntraege(ngoName: ngoName(session.me?.settings.ngoId ?? ''))
          else if (desks.isEmpty)
            _EmptyCollecting()
          else
            for (final d in desks)
              _CollectingCard(
                desk: d,
                ngoName: ngoName(session.me?.settings.ngoId ?? ''),
                onChangeNgo: () => pickNgo(context, session, session.me?.settings.ngoId),
                incidents: d.incidentIds.map((id) => byId[id]).whereType<ApiIncident>().toList(),
                showDesk: desks.length > 1,
                minPayoutCents: summary.minPayoutCents,
                oldest: summary.oldestOpen,
                busy: _busy,
                discarded: discarded,
                onDiscard: (id, reason) => _discard(context, id, reason),
                onRestore: (id) => _restore(context, id),
                onPrepare: d.ready ? () => _prepare(context, d.desk) : null,
              ),
          // Cases taken out while no bundle is collecting still need a way back.
          if (desks.isEmpty && discarded.isNotEmpty) _DiscardedCard(incidents: discarded, onRestore: (id) => _restore(context, id)),
          // Then every claim, newest first, status in words.
          for (final c in claims)
            _ClaimCard(
              key: _keyFor(c.id),
              claim: c,
              ngoName: ngoName(c.ngoId),
              incidents: _incidentsOf(c, byId),
              mails: _mailsOf(c, data.mails),
              onOpenThread: () => session.markClaimSeen(c.id),
              onChanged: refresh,
            ),
          if (expired.isNotEmpty) _ExpiredCard(incidents: expired),
        ];

        return VScreen(
          showBack: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TabHeader(title: 'Anträge', caption: caption, onSettings: () => context.push(Routes.einstellungen).then((_) => refresh())),
              const VGap.l(),
              ...cards,
              if (!session.isLocal && out.isNotEmpty)
                VDemoControl(label: 'Antwort der Bahn simulieren', icon: Icons.mark_email_unread_outlined, onTap: () => _simulateReply(context)),
              if (desks.length > 1) ...[
                const VGap.s(),
                Text('Ansprüche werden pro Bahnunternehmen gebündelt. Jedes Bündel muss 4 € erreichen.', style: VText.caption),
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

/// One claim: a card with the status in words, what went out, what came back, what to do.
class _ClaimCard extends StatelessWidget {
  const _ClaimCard({super.key, required this.claim, required this.ngoName, required this.incidents, required this.mails, required this.onOpenThread, required this.onChanged});
  final ApiClaim claim;
  final String? ngoName;
  final List<ApiIncident> incidents;
  final List<ApiMail> mails;
  final VoidCallback onOpenThread;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = claim;
    final last = mails.isEmpty ? null : mails.last;
    final amount = c.status == ApiClaimStatus.accepted ? (c.amountConfirmedCents ?? c.amountClaimedCents) : c.amountClaimedCents;
    final title = c.sentAt != null ? 'Antrag vom ${Mock.shortDate(c.sentAt!.toLocal())}' : 'Antrag';
    final (status, color) = switch (c.status) {
      ApiClaimStatus.accepted => ('Bestätigt · ${fmtCents(amount)}${ngoName != null ? ' an $ngoName' : ''}', VColors.green),
      ApiClaimStatus.rejected => ('Abgelehnt', VColors.red),
      ApiClaimStatus.question => ('Rückfrage · bitte antworten', VColors.red),
      ApiClaimStatus.bounced => ('Nicht zugestellt · Adresse prüfen', VColors.red),
      _ => (c.expectedReplyBy != null ? 'Eingereicht · Antwort bis ${Mock.shortDate(c.expectedReplyBy!.toLocal())}' : 'Eingereicht · Antwort in etwa 4 Wochen', VColors.ink),
    };
    void openThread(String mailId) {
      onOpenThread();
      context.push('${Routes.antwort}?mail=$mailId').then((_) => onChanged());
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.m),
      child: Container(
        padding: const EdgeInsets.all(VSpace.m),
        decoration: BoxDecoration(border: Border.all(color: VColors.rule, width: 1.5), borderRadius: BorderRadius.circular(4)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(title, style: VText.title)),
                const SizedBox(width: 8),
                Text(fmtCents(amount), style: VText.numberM),
              ],
            ),
            const SizedBox(height: 4),
            Text(status, style: VText.bodySStrong.copyWith(color: color), maxLines: 2),
            const SizedBox(height: 2),
            Text(deskDisplay(c.desk), style: VText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
            // The payee is in the status line once confirmed; until then it is a line of its own (docs/20 §4).
            if (c.status != ApiClaimStatus.accepted && ngoName != null) ...[
              const SizedBox(height: 2),
              Text('Für $ngoName', style: VText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
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
                    onTap: () => openThread(last.id),
                  ),
                if (mails.isNotEmpty)
                  VGhostButton(
                    label: mails.length == 1 ? 'Ganze Mail lesen' : 'Alle ${mails.length} Nachrichten',
                    icon: Icons.mail_outline,
                    onTap: () => openThread(last!.id),
                  ),
                VGhostButton(label: 'PDF ansehen', icon: Icons.picture_as_pdf_outlined, onTap: () => ClaimPdfPage.open(context, c.id)),
              ],
            ),
            // A sent claim is out of the passenger's hands (docs/21 §4).
            const VGap.xs(),
            Text('Eingereicht — Änderungen nur noch über eine Antwort an das Unternehmen.', style: VText.caption.copyWith(color: VColors.ink2)),
            // The claim's own address, a footnote: the only place an address appears in the app (docs/18).
            if (c.replyAddress != null) ...[
              const VGap.s(),
              Text('Antragsadresse: ${c.replyAddress}', style: VText.caption.copyWith(color: VColors.ink3), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}

/// The bundle being collected: its incidents, the oldest deadline, the button when ready.
class _CollectingCard extends StatelessWidget {
  const _CollectingCard({
    required this.desk,
    required this.ngoName,
    required this.onChangeNgo,
    required this.incidents,
    required this.showDesk,
    required this.minPayoutCents,
    required this.oldest,
    required this.busy,
    required this.discarded,
    required this.onDiscard,
    required this.onRestore,
    required this.onPrepare,
  });
  final ApiDeskSummary desk;
  final String? ngoName;
  final VoidCallback onChangeNgo;
  final List<ApiIncident> incidents;
  final bool showDesk;
  final int minPayoutCents;
  final ApiOldestOpen? oldest;
  final bool busy;
  final List<ApiIncident> discarded;
  final Future<void> Function(String id, String reason) onDiscard;
  final Future<void> Function(String id) onRestore;
  final VoidCallback? onPrepare;

  @override
  Widget build(BuildContext context) {
    final ready = desk.ready;
    final hasSingle = incidents.any((i) => i.ticket == TicketType.einzelfahrkarte);
    final status = ready
        ? 'Bereit · ${fmtCents(desk.openCents)}'
        : hasSingle
            ? '${fmtCents(desk.openCents)} gesammelt'
            : '${fmtCents(desk.openCents)} von ${fmtCents(minPayoutCents)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.m),
      child: Container(
        padding: const EdgeInsets.all(VSpace.m),
        decoration: BoxDecoration(border: Border.all(color: VColors.ink, width: 1.5), borderRadius: BorderRadius.circular(4)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(showDesk ? 'Wird gesammelt · ${deskDisplay(desk.desk)}' : 'Wird gesammelt', style: VText.title),
            const SizedBox(height: 4),
            Text(status, style: VText.bodySStrong.copyWith(color: ready ? VColors.green : VColors.ink)),
            if (!ready) ...[
              const SizedBox(height: 2),
              Text('Ab ${fmtCents(minPayoutCents)} geht der Antrag raus. Noch ${fmtCents(desk.missingCents)}.', style: VText.caption),
            ],
            if (showDesk && desk.desk != 'Servicecenter Fahrgastrechte') ...[
              const SizedBox(height: 2),
              Text('Eigene Stelle. Geht als eigener Antrag raus.', style: VText.caption),
            ],
            // Where the money goes, before there is an Antrag (docs/20 §4).
            const SizedBox(height: 4),
            InkWell(
              onTap: onChangeNgo,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(ngoName != null ? 'Für $ngoName' : 'Noch kein Zweck gewählt', style: VText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 6),
                    Text('ändern', style: VText.caption.copyWith(color: VColors.ink2, decoration: TextDecoration.underline)),
                  ],
                ),
              ),
            ),
            const VGap.s(),
            for (final i in incidents)
              IncidentRow(incident: i, onTap: () => showEvidenceSheet(context, i, onDiscard: (reason) => onDiscard(i.id, reason))),
            if (oldest != null && incidents.any((i) => i.id == oldest!.id)) ...[
              const VGap.s(),
              _DeadlineLine(oldest: oldest!),
            ],
            if (discarded.isNotEmpty) ...[
              const VGap.s(),
              _DiscardedLine(incidents: discarded, onRestore: onRestore),
            ],
            if (onPrepare != null) ...[
              const VGap.m(),
              VPrimaryButton(label: busy ? 'Einen Moment …' : 'Antrag vorbereiten', icon: Icons.edit_outlined, onTap: busy ? null : onPrepare),
            ],
          ],
        ),
      ),
    );
  }
}

/// The whole tab is empty: no case, no Antrag, nothing taken out. Say what will
/// happen here and when, rather than showing an empty box (docs/21 §5).
class _EmptyAntraege extends StatelessWidget {
  const _EmptyAntraege({required this.ngoName});
  final String? ngoName;

  @override
  Widget build(BuildContext context) {
    final steps = [
      'Einchecken, wenn du in den Zug steigst.',
      'Ab 60 Minuten Verspätung am Ziel entstehen 1,50 €.',
      'Ab 4 € geht ein Antrag an das Eisenbahnunternehmen — mit deiner Unterschrift, von dir.',
      'Antwortet die Bahn, zahlt sie direkt an ${ngoName ?? 'deinen Verein'}.',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.m),
      // docs/22 §4: no box. Nothing is collected yet, so nothing should look like a container.
      child: Container(
        key: const Key('antraege-empty'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hier wird es später voll.', style: VText.title),
            const SizedBox(height: 4),
            Text('So läuft es:', style: VText.bodySStrong.copyWith(color: VColors.ink2)),
            const VGap.s(),
            for (var n = 0; n < steps.length; n++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 22, child: Text('${n + 1}.', style: VText.bodySStrong.copyWith(color: VColors.red))),
                    Expanded(child: Text(steps[n], style: VText.bodyS)),
                  ],
                ),
              ),
            const VGap.xs(),
            Text('Anträge müssen innerhalb eines Jahres gestellt werden. Wir erinnern dich rechtzeitig.', style: VText.caption),
            const VGap.m(),
            VPrimaryButton(label: 'Einchecken', icon: Icons.train_outlined, onTap: () => startCheckin(context)),
          ],
        ),
      ),
    );
  }
}

/// "1 Fall nicht eingereicht · anzeigen": the way back for a case taken out (docs/21 §4).
class _DiscardedLine extends StatefulWidget {
  const _DiscardedLine({required this.incidents, required this.onRestore});
  final List<ApiIncident> incidents;
  final Future<void> Function(String id) onRestore;

  @override
  State<_DiscardedLine> createState() => _DiscardedLineState();
}

class _DiscardedLineState extends State<_DiscardedLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.incidents.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Flexible(child: Text('$n ${n == 1 ? 'Fall' : 'Fälle'} nicht eingereicht', style: VText.caption, maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                Text(_open ? 'verbergen' : 'anzeigen', style: VText.caption.copyWith(color: VColors.ink2, decoration: TextDecoration.underline)),
              ],
            ),
          ),
        ),
        if (_open)
          for (final i in widget.incidents)
            IncidentRow(
              incident: i,
              note: discardReasons[i.discardReason] ?? 'Nicht eingereicht',
              onTap: () => showEvidenceSheet(context, i, onRestore: () => widget.onRestore(i.id)),
            ),
      ],
    );
  }
}

/// Cases taken out while nothing is collecting: their own small card, so they are never lost.
class _DiscardedCard extends StatelessWidget {
  const _DiscardedCard({required this.incidents, required this.onRestore});
  final List<ApiIncident> incidents;
  final Future<void> Function(String id) onRestore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.m),
      child: Container(
        padding: const EdgeInsets.all(VSpace.m),
        decoration: BoxDecoration(border: Border.all(color: VColors.rule, width: 1.5), borderRadius: BorderRadius.circular(4)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nicht eingereicht', style: VText.title),
            const SizedBox(height: 4),
            Text('Von dir aussortiert. Die Minuten und Punkte bleiben.', style: VText.caption),
            const VGap.s(),
            for (final i in incidents)
              IncidentRow(
                incident: i,
                note: discardReasons[i.discardReason] ?? 'Nicht eingereicht',
                onTap: () => showEvidenceSheet(context, i, onRestore: () => onRestore(i.id)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Nothing collected yet.
class _EmptyCollecting extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.m),
      child: Container(
        padding: const EdgeInsets.all(VSpace.m),
        decoration: BoxDecoration(border: Border.all(color: VColors.rule, width: 1.5), borderRadius: BorderRadius.circular(4)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Wird gesammelt', style: VText.title),
            const SizedBox(height: 4),
            Text('Noch nichts', style: VText.bodySStrong.copyWith(color: VColors.ink2)),
            const SizedBox(height: 2),
            Text('Verspätungen ab 60 Minuten landen hier. Ab 4 € geht ein Antrag raus.', style: VText.caption),
          ],
        ),
      ),
    );
  }
}

/// Incidents whose deadline passed before 4 € came together.
class _ExpiredCard extends StatelessWidget {
  const _ExpiredCard({required this.incidents});
  final List<ApiIncident> incidents;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.m),
      child: Container(
        padding: const EdgeInsets.all(VSpace.m),
        decoration: BoxDecoration(border: Border.all(color: VColors.rule, width: 1.5), borderRadius: BorderRadius.circular(4)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Verfallen', style: VText.title),
            const SizedBox(height: 4),
            Text('Frist um, bevor 4 € zusammenkamen. Die Minuten und Punkte bleiben.', style: VText.caption),
            const VGap.s(),
            for (final i in incidents) IncidentRow(incident: i, onTap: () => showEvidenceSheet(context, i)),
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
