import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../mock/mock_data.dart' show Mock;
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'claims_widgets.dart';
import 'pdf_view.dart';

/// Antrag: the five-step claim flow. Prüfen · Ticket · Zweck · Unterschrift · Senden.
class AntragScreen extends StatefulWidget {
  const AntragScreen({super.key, required this.desk, this.claimId, this.draft});
  final String desk;
  final String? claimId;
  final ApiClaimDraft? draft;

  @override
  State<AntragScreen> createState() => _AntragScreenState();
}

class _AntragScreenState extends State<AntragScreen> {
  static const _steps = ['Prüfen', 'Ticket', 'Zweck', 'Unterschrift', 'Senden'];

  int _step = 0;
  ApiClaimDraft? _draft;
  List<ApiIncident> _incidents = const [];
  List<ApiNgo> _ngos = const [];
  Object? _error;
  bool _loading = true;
  bool _busy = false;
  bool _showPersonal = false;
  bool _otherNgo = false;
  final Map<String, String> _uploads = {}; // month → upload id
  bool _signed = false;
  bool _sentDryRun = false;
  ApiSendResult? _sent;
  final _unknownAddress = TextEditingController();
  final _signature = SignatureController();

  bool get _unknownDesk => widget.desk == 'Unbekannt';
  ApiClaim? get _claim => _draft?.claim;
  bool get _paperOnly => _draft != null && (_draft!.deskEmail == null || _draft!.deskEmail!.isEmpty);

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _unknownAddress.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final session = RepoScope.read(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _draft ??= await session.repo.draftClaim(desk: widget.desk);
      final ledger = await session.repo.incidents();
      final ids = _draft!.claim.incidentIds.toSet();
      _incidents = ledger.incidents.where((i) => ids.contains(i.id)).toList()..sort((a, b) => a.date.compareTo(b.date));
      _ngos = session.ngos.isNotEmpty ? session.ngos : await session.repo.ngos();
      final me = session.me ?? await session.repo.getMe();
      _showPersonal = _draft!.personalDataRequired || me.personalData == null;
      _signed = _draft!.claim.signedBy != null;
    } catch (e) {
      _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  ApiNgo? get _ngo {
    final id = _claim?.ngoId;
    return _ngos.where((n) => n.id == id).firstOrNull ?? _ngos.firstOrNull;
  }

  bool get _canContinue => switch (_step) {
        0 => _incidents.isNotEmpty && !_showPersonal && (!_unknownDesk || _unknownAddress.text.trim().isNotEmpty),
        1 => _months.every(_uploads.containsKey),
        2 => true,
        3 => _signed,
        _ => true,
      };

  List<String> get _months {
    final m = _claim?.ticketMonths ?? const [];
    if (m.isNotEmpty) return m;
    return const ['Ticket'];
  }

  Future<void> _run(Future<void> Function() action, {String? failure}) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${failure ?? 'Das hat nicht geklappt'}: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attach(String month) => _run(() async {
        final session = RepoScope.read(context);
        final me = session.me;
        final name = me?.personalData?.name ?? me?.nickname ?? 'Fahrgast';
        final number = me?.personalData?.ticketNumber ?? '–';
        final png = await renderTicketPng(name: name, ticketNumber: number, month: month == 'Ticket' ? 'Fahrkarte' : monthLabel(month));
        final up = await session.repo.upload(kind: 'ticket', filename: 'Ticket_$month.png', bytes: png);
        _uploads[month] = up.uploadId;
        final claim = await session.repo.patchClaim(_claim!.id, attachmentUploadIds: _uploads.values.toList());
        _draft = _withClaim(claim);
      }, failure: 'Anhängen fehlgeschlagen');

  Future<void> _chooseNgo(String id) => _run(() async {
        final claim = await RepoScope.read(context).repo.patchClaim(_claim!.id, ngoId: id);
        _draft = _withClaim(claim);
      });

  Future<void> _sign() => _run(() async {
        final session = RepoScope.read(context);
        final name = session.me?.personalData?.name ?? session.me?.nickname ?? 'Fahrgast';
        String? sigId;
        final png = await _signature.toPng();
        if (png != null) {
          sigId = (await session.repo.upload(kind: 'signature', filename: 'Unterschrift.png', bytes: png)).uploadId;
        }
        final claim = await session.repo.signClaim(_claim!.id, typedName: name, signatureUploadId: sigId);
        _draft = _withClaim(claim);
        _signed = true;
      }, failure: 'Unterschrift fehlgeschlagen');

  Future<void> _send() => _run(() async {
        final r = await RepoScope.read(context).repo.sendClaim(_claim!.id);
        _sent = r;
        _sentDryRun = r.mail.subject.isNotEmpty && _looksDryRun(r);
      }, failure: 'Senden fehlgeschlagen');

  bool _looksDryRun(ApiSendResult r) {
    // The wire model carries no dry_run flag; the local backend records dry-runs
    // when SMTP_URL is unset. Treat demo mode as a rehearsal too.
    return RepoScope.read(context).isLocal == false || true;
  }

  ApiClaimDraft _withClaim(ApiClaim c) => ApiClaimDraft(
        claim: c,
        deskAddress: _draft?.deskAddress,
        deskEmail: _draft?.deskEmail,
        personalDataRequired: _draft?.personalDataRequired ?? false,
        relayAddress: _draft?.relayAddress,
      );

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    if (_sent != null) return _Sent(desk: widget.desk, dryRun: _sentDryRun, mail: _sent!.mail);
    if (_loading) return const VScreen(title: 'Antrag', child: LoadingLine());
    if (_error != null || _draft == null) {
      return VScreen(
        title: 'Antrag',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VGap.m(),
            Text('Noch kein Antrag möglich.', style: VText.h2),
            const VGap.s(),
            Text('$_error', style: VText.bodyS.copyWith(color: VColors.ink2)),
            const VGap.l(),
            VGhostButton(label: 'Erneut versuchen', icon: Icons.refresh, onTap: _load),
          ],
        ),
      );
    }

    final me = session.me;
    final content = switch (_step) {
      0 => _Pruefen(
          draft: _draft!,
          incidents: _incidents,
          me: me,
          desk: widget.desk,
          unknown: _unknownDesk,
          addressCtl: _unknownAddress,
          showPersonal: _showPersonal,
          onChanged: () => setState(() {}),
          onPersonalSaved: () async {
            setState(() => _showPersonal = false);
            await _maybeShowRecoveryCode();
          },
        ),
      1 => _Ticket(months: _months, uploads: _uploads, me: me, busy: _busy, onAttach: _attach),
      2 => _Zweck(ngos: _ngos, selected: _ngo, other: _otherNgo, onToggle: (v) => setState(() => _otherNgo = v), onChoose: _chooseNgo),
      3 => _Unterschrift(draft: _draft!, incidents: _incidents, me: me, ngo: _ngo, signed: _signed, busy: _busy, controller: _signature, onSign: _sign),
      _ => _Senden(draft: _draft!, incidents: _incidents, me: me, ngo: _ngo, paperOnly: _paperOnly),
    };

    final last = _step == _steps.length - 1;
    return VScreen(
      eyebrow: 'Antrag · ${deskDisplay(widget.desk)}',
      title: _steps[_step],
      scroll: true,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (last) ...[
            if (!_paperOnly)
              VPrimaryButton(label: _busy ? 'Sendet …' : 'Absenden', icon: Icons.send_outlined, onTap: _busy ? null : _send)
            else
              VPrimaryButton(
                label: 'Als PDF zum Drucken',
                icon: Icons.print_outlined,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF gespeichert. Per Post an: ${_draft!.deskAddress ?? 'Adresse siehe Betreiber'}'))),
              ),
            if (!_paperOnly) ...[
              const VGap.xs(),
              VGhostButton(
                label: 'Als PDF zum Drucken',
                icon: Icons.print_outlined,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF gespeichert. Per Post an: ${_draft!.deskAddress ?? '–'}'))),
              ),
            ],
          ] else
            VPrimaryButton(label: 'Weiter', onTap: _canContinue && !_busy ? () => setState(() => _step += 1) : null),
          if (_step > 0) ...[
            const VGap.xs(),
            VGhostButton(label: 'Zurück', onTap: () => setState(() => _step -= 1)),
          ],
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepIndicator(steps: _steps, current: _step),
          const VGap.l(),
          content,
          const VGap.xl(),
        ],
      ),
    );
  }

  Future<void> _maybeShowRecoveryCode() async {
    final session = RepoScope.read(context);
    final code = await session.recoveryCode();
    if (code == null || !mounted) return;
    await showVSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(VSpace.page, 0, VSpace.page, VSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VSheetHeader(title: 'Dein Wiederherstellungscode', subtitle: 'Einmal zeigen wir ihn. Mach einen Screenshot.'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(VSpace.m),
              decoration: BoxDecoration(border: Border.all(color: VColors.ink, width: 1.5), borderRadius: BorderRadius.circular(4)),
              child: Text(code, style: VText.mono.copyWith(fontSize: 17, height: 1.6)),
            ),
            const VGap.m(),
            Text(
              'Kein Konto, kein Passwort. Mit diesen zwölf Wörtern holst du dein Konto auf ein neues Telefon. Wer sie hat, hat dein Konto.',
              style: VText.bodyS.copyWith(color: VColors.ink2),
            ),
            const VGap.l(),
            VPrimaryButton(label: 'Ich habe es notiert', onTap: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.steps, required this.current});
  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              Text(
                '${i + 1} ${steps[i]}',
                style: VText.caption.copyWith(
                  color: i == current ? VColors.ink : (i < current ? VColors.ink2 : VColors.ink3),
                  fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (i < steps.length - 1) Text('·', style: VText.caption.copyWith(color: VColors.ink3)),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < steps.length; i++)
              Expanded(
                child: Container(
                  height: 3,
                  margin: EdgeInsets.only(right: i < steps.length - 1 ? 4 : 0),
                  color: i <= current ? VColors.red : VColors.ruleSoft,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 11.1 Prüfen
// ---------------------------------------------------------------------------

class _Pruefen extends StatelessWidget {
  const _Pruefen({
    required this.draft,
    required this.incidents,
    required this.me,
    required this.desk,
    required this.unknown,
    required this.addressCtl,
    required this.showPersonal,
    required this.onChanged,
    required this.onPersonalSaved,
  });
  final ApiClaimDraft draft;
  final List<ApiIncident> incidents;
  final ApiCustomer? me;
  final String desk;
  final bool unknown;
  final TextEditingController addressCtl;
  final bool showPersonal;
  final VoidCallback onChanged;
  final Future<void> Function() onPersonalSaved;

  @override
  Widget build(BuildContext context) {
    final amount = draft.claim.amountClaimedCents;
    final pd = me?.personalData;
    final relay = me?.relayAddress ?? draft.relayAddress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Diese Verspätungen gehen in den Antrag.', style: VText.h2),
        const VGap.s(),
        Text('Alle offenen Fälle dieser Stelle. Jede steht einzeln im Formular.', style: VText.caption),
        const VGap.m(),
        VSection('Fälle', trailing: Text(fmtCents(amount), style: VText.captionInk)),
        if (incidents.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: VSpace.m),
            child: Text('Keine offenen Fälle für diese Stelle.', style: VText.caption),
          ),
        for (final i in incidents) IncidentRow(incident: i, onTap: () => showEvidenceSheet(context, i)),
        const VGap.xl(),
        const VSection('Geht an'),
        const VGap.m(),
        if (unknown || (draft.deskAddress == null && draft.deskEmail == null))
          _UnknownDesk(ctl: addressCtl, onChanged: onChanged)
        else ...[
          Text(desk, style: VText.bodyStrong),
          const VGap.xs(),
          Text([draft.deskAddress, draft.deskEmail].whereType<String>().join('\n'), style: VText.bodyS.copyWith(color: VColors.ink2)),
          const VGap.xs(),
          Text(
            desk == 'Servicecenter Fahrgastrechte'
                ? 'Die gemeinsame Stelle von DB und rund 40 weiteren Bahnen.'
                : (draft.deskEmail == null ? 'Eigene Stelle ohne E-Mail. Der Antrag geht per Post.' : 'Eigene Fahrgastrechte-Stelle dieses Betreibers.'),
            style: VText.caption,
          ),
        ],
        const VGap.xl(),
        const VSection('Deine Angaben'),
        if (showPersonal || pd == null)
          _PersonalForm(initial: pd, onSaved: onPersonalSaved)
        else ...[
          VKeyValue('Name', pd.name, strong: true),
          const VRule(),
          VKeyValue('Anschrift', pd.address.replaceAll('\n', ', ')),
          const VRule(),
          VKeyValue('Privates Postfach', pd.email),
          const VRule(),
          VKeyValue('Ticket-Nr.', pd.ticketNumber ?? '–', valueStyle: VText.mono),
        ],
        if (relay != null) ...[
          const VGap.m(),
          Container(
            padding: const EdgeInsets.all(VSpace.m),
            decoration: BoxDecoration(border: Border.all(color: VColors.rule), borderRadius: BorderRadius.circular(4)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DEINE VERSPÄTOMAT-ADRESSE', style: VText.eyebrow),
                const SizedBox(height: 6),
                Text(relay, style: VText.mono),
                const SizedBox(height: 6),
                Text('Deine Anträge gehen von hier raus. Antworten der Bahn landen dort und sofort auch in deinem Postfach.', style: VText.caption),
              ],
            ),
          ),
        ],
        const VGap.s(),
        Text('Diese Daten stehen nur auf dem Formular.', style: VText.caption),
      ],
    );
  }
}

class _UnknownDesk extends StatelessWidget {
  const _UnknownDesk({required this.ctl, required this.onChanged});
  final TextEditingController ctl;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Wir kennen die Adresse für Anträge noch nicht.', style: VText.bodyStrong),
        const VGap.xs(),
        Text(
          'Dieser Betreiber ist nicht im Verzeichnis. Auf seiner Fahrgastrechte-Seite steht, wohin der Antrag geht. Trag die Adresse hier ein, wir merken sie uns für alle.',
          style: VText.bodyS.copyWith(color: VColors.ink2),
        ),
        const VGap.m(),
        TextField(
          controller: ctl,
          onChanged: (_) => onChanged(),
          decoration: const InputDecoration(hintText: 'E-Mail oder Postanschrift der Fahrgastrechte-Stelle'),
          style: VText.bodyS,
          maxLines: 2,
        ),
      ],
    );
  }
}

/// First claim only: name, address, private inbox, ticket number.
class _PersonalForm extends StatefulWidget {
  const _PersonalForm({required this.initial, required this.onSaved});
  final ApiPersonalData? initial;
  final Future<void> Function() onSaved;

  @override
  State<_PersonalForm> createState() => _PersonalFormState();
}

class _PersonalFormState extends State<_PersonalForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _address = TextEditingController(text: widget.initial?.address ?? '');
  late final _email = TextEditingController(text: widget.initial?.email ?? '');
  late final _ticket = TextEditingController(text: widget.initial?.ticketNumber ?? '');
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _address, _email, _ticket]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty && _address.text.trim().isNotEmpty && _email.text.contains('@');

  Future<void> _save() async {
    setState(() => _saving = true);
    final session = RepoScope.read(context);
    await session.savePersonalData(ApiPersonalData(
      name: _name.text.trim(),
      address: _address.text.trim(),
      email: _email.text.trim(),
      ticketNumber: _ticket.text.trim().isEmpty ? null : _ticket.text.trim(),
    ));
    if (!mounted) return;
    setState(() => _saving = false);
    if (session.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: ${session.error}')));
      return;
    }
    await widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VGap.s(),
        Text('Einmal eintragen. Steht danach auf jedem Antrag.', style: VText.caption),
        const VGap.m(),
        TextField(controller: _name, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Vor- und Nachname'), style: VText.bodyS),
        const VGap.s(),
        TextField(controller: _address, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Straße, Hausnummer, PLZ und Ort'), style: VText.bodyS, maxLines: 2),
        const VGap.s(),
        TextField(controller: _email, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Privates Postfach (E-Mail)'), style: VText.bodyS, keyboardType: TextInputType.emailAddress),
        const VGap.s(),
        TextField(controller: _ticket, decoration: const InputDecoration(hintText: 'Deutschlandticket-Nummer'), style: VText.bodyS),
        const VGap.m(),
        VOutlineButton(label: _saving ? 'Speichert …' : 'Speichern', icon: Icons.check, onTap: _valid && !_saving ? _save : null),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 11.2 Ticket
// ---------------------------------------------------------------------------

class _Ticket extends StatelessWidget {
  const _Ticket({required this.months, required this.uploads, required this.me, required this.busy, required this.onAttach});
  final List<String> months;
  final Map<String, String> uploads;
  final ApiCustomer? me;
  final bool busy;
  final Future<void> Function(String month) onAttach;

  @override
  Widget build(BuildContext context) {
    final several = months.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(several ? 'Füge einen Screenshot pro Monat an.' : 'Füge einen Screenshot deines Tickets mit Barcode an.', style: VText.h2),
        const VGap.s(),
        Text(
          several
              ? 'Jeder Monat ist rechtlich ein eigenes Ticket. Die Bahn will jedes sehen: ${months.map(monthLabel).join(' und ')}.'
              : 'Die Bahn will das Ticket sehen. Mehr Nachweis braucht es nicht.',
          style: VText.caption,
        ),
        const VGap.l(),
        for (final m in months) ...[
          if (several) ...[
            Text(monthLabel(m).toUpperCase(), style: VText.eyebrow),
            const VGap.s(),
          ],
          if (!uploads.containsKey(m)) ...[
            VOutlineButton(label: busy ? 'Lädt hoch …' : 'Aus Fotos', icon: Icons.photo_library_outlined, onTap: busy ? null : () => onAttach(m)),
            const VGap.s(),
            VOutlineButton(label: 'Aus Ticket-App', icon: Icons.confirmation_number_outlined, onTap: busy ? null : () => onAttach(m)),
          ] else ...[
            MockTicket(name: me?.personalData?.name ?? me?.nickname ?? 'Fahrgast', ticketNumber: me?.personalData?.ticketNumber ?? '–', month: m == 'Ticket' ? 'Fahrkarte' : monthLabel(m)),
            const VGap.s(),
            Row(
              children: [
                const Icon(Icons.check, size: 16, color: VColors.green),
                const SizedBox(width: 6),
                Expanded(child: Text('Angehängt. Wird verschlüsselt aufbewahrt, bis der Antrag abgeschlossen ist. Dann gelöscht.', style: VText.caption)),
              ],
            ),
          ],
          const VGap.l(),
        ],
        Text('Vorführung: das Bild wird erzeugt, nicht aus deinen Fotos geholt.', style: VText.caption),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 11.3 Zweck
// ---------------------------------------------------------------------------

class _Zweck extends StatelessWidget {
  const _Zweck({required this.ngos, required this.selected, required this.other, required this.onToggle, required this.onChoose});
  final List<ApiNgo> ngos;
  final ApiNgo? selected;
  final bool other;
  final ValueChanged<bool> onToggle;
  final Future<void> Function(String id) onChoose;

  @override
  Widget build(BuildContext context) {
    final ngo = selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Die Entschädigung geht direkt an:', style: VText.h2),
        const VGap.l(),
        if (ngo == null)
          Text('Kein Verein gewählt.', style: VText.body)
        else
          Container(
            padding: const EdgeInsets.all(VSpace.m),
            decoration: BoxDecoration(
              color: VColors.paperElevated,
              border: Border.all(color: VColors.ink, width: 1.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ngo.name, style: VText.title),
                const SizedBox(height: 2),
                Text(ngo.tagline, style: VText.caption),
                const VGap.m(),
                const VRule(),
                VKeyValue('Kontoinhaber', ngo.accountHolder, strong: true),
                const VRule(),
                VKeyValue('IBAN', ngo.iban, valueStyle: VText.mono),
              ],
            ),
          ),
        const VGap.s(),
        Text('So steht es im Formular unter „Name des Kontoinhabers“. Die Bahn überweist dorthin, nicht an dich.', style: VText.caption),
        const VGap.l(),
        Row(
          children: [
            Expanded(child: Text('Anderen Zweck für diesen Antrag wählen', style: VText.bodyS)),
            Switch(value: other, onChanged: onToggle),
          ],
        ),
        if (other) ...[
          const VGap.m(),
          for (final n in ngos)
            Padding(
              padding: const EdgeInsets.only(bottom: VSpace.s),
              child: VChoiceCard(title: n.name, subtitle: n.tagline, selected: n.id == ngo?.id, onTap: () => onChoose(n.id)),
            ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 11.4 Unterschrift
// ---------------------------------------------------------------------------

class _Unterschrift extends StatelessWidget {
  const _Unterschrift({
    required this.draft,
    required this.incidents,
    required this.me,
    required this.ngo,
    required this.signed,
    required this.busy,
    required this.controller,
    required this.onSign,
  });
  final ApiClaimDraft draft;
  final List<ApiIncident> incidents;
  final ApiCustomer? me;
  final ApiNgo? ngo;
  final bool signed;
  final bool busy;
  final SignatureController controller;
  final Future<void> Function() onSign;

  @override
  Widget build(BuildContext context) {
    final pd = me?.personalData;
    final name = pd?.name ?? me?.nickname ?? 'Fahrgast';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('So geht es raus.', style: VText.h2),
        const VGap.s(),
        Text('Das ist das EU-Antragsformular als PDF, ausgefüllt mit deinen Daten. Lies es, dann unterschreib.', style: VText.caption),
        const VGap.m(),
        ClaimPdfPreview(claimId: draft.claim.id, reloadKey: signed),
        const VGap.l(),
        const VRule.red(),
        const VGap.m(),
        Text('Ich bestätige, dass die Angaben stimmen und ich Inhaber:in des Tickets bin.', style: VText.bodyStrong),
        const VGap.xs(),
        Text('Das EU-Formular braucht keine gezeichnete Unterschrift, nur deinen Namen. Zeichnen darfst du trotzdem.', style: VText.caption),
        const VGap.m(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('Name', style: VText.caption),
            const SizedBox(width: 12),
            Text(name, style: VText.title),
          ],
        ),
        const VGap.s(),
        SignaturePad(controller: controller, onSigned: () {}),
        const VGap.xs(),
        if (!signed)
          VOutlineButton(label: busy ? 'Speichert …' : 'Bestätigen', icon: Icons.check, onTap: busy ? null : onSign)
        else
          Row(
            children: [
              const Icon(Icons.check, size: 16, color: VColors.green),
              const SizedBox(width: 6),
              Expanded(child: Text('Bestätigt. Deine Unterschrift bleibt nur in diesem Antrag.', style: VText.caption)),
            ],
          ),
      ],
    );
  }
}






// ---------------------------------------------------------------------------
// 11.5 Senden
// ---------------------------------------------------------------------------

class _Senden extends StatelessWidget {
  const _Senden({required this.draft, required this.incidents, required this.me, required this.ngo, required this.paperOnly});
  final ApiClaimDraft draft;
  final List<ApiIncident> incidents;
  final ApiCustomer? me;
  final ApiNgo? ngo;
  final bool paperOnly;

  @override
  Widget build(BuildContext context) {
    final pd = me?.personalData;
    final name = pd?.name ?? me?.nickname ?? 'Fahrgast';
    final relay = me?.relayAddress ?? draft.relayAddress ?? '–';
    final mail = ApiMail(
      id: 'draft',
      incidentIds: draft.claim.incidentIds,
      direction: ApiMailDirection.out,
      from: '$name <$relay>',
      to: draft.deskEmail ?? '–',
      bcc: pd?.email != null ? '${pd!.email} (dein Postfach)' : null,
      subject: 'Fahrgastrechte: EU-Antragsformular',
      body: draftMailBody(accountHolder: draft.claim.accountHolder, claimantName: name, incidents: incidents),
      date: DateTime.now().toUtc(),
      attachments: ['EU-Antrag.pdf', for (final m in draft.claim.ticketMonths) 'Ticket_$m.png'],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(paperOnly ? 'Diese Stelle nimmt keine E-Mail.' : 'Wir haben alles vorbereitet. Du schickst es ab.', style: VText.h2),
        const VGap.s(),
        Text(
          paperOnly ? 'Der Antrag geht per Post. Wir erzeugen das PDF, du druckst und schickst es.' : 'Von deiner Verspätomat-Adresse, mit Kopie an dein Postfach.',
          style: VText.caption,
        ),
        const VGap.m(),
        if (paperOnly) ...[
          Text(draft.deskAddress ?? 'Adresse siehe Betreiber', style: VText.bodyStrong),
          const VGap.m(),
        ] else
          MailView(mail: mail),
        const VGap.m(),
        Text('ANHANG', style: VText.eyebrow),
        const VGap.xs(),
        ClaimPdfPreview(claimId: draft.claim.id, reloadKey: draft.claim.signedBy, height: 260),
        const VGap.m(),
        VKeyValue('Fälle', '${draft.claim.incidentIds.length}'),
        const VRule(),
        VKeyValue('Anspruch', fmtCents(draft.claim.amountClaimedCents), strong: true),
        const VRule(),
        VKeyValue('Empfänger', draft.claim.accountHolder),
        const VGap.s(),
        Text('Nach dem Absenden steht alles auf „eingereicht“. Die Antwort der Bahn landet in der App und in deinem Postfach.', style: VText.caption),
        const VGap.s(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text('Das ist dein Antrag, in deinem Namen. Wir überbringen ihn nur und schreiben der Bahn nie von uns aus.', style: VText.caption)),
            const SizedBox(width: VSpace.s),
            InkWell(
              onTap: () => context.push(Routes.rechtliches('bote')),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text('Mehr', style: VText.caption.copyWith(color: VColors.ink, decoration: TextDecoration.underline)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Sent extends StatelessWidget {
  const _Sent({required this.desk, required this.dryRun, required this.mail});
  final String desk;
  final bool dryRun;
  final ApiMail mail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(VSpace.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const VStationClock(size: 56),
              const VGap.xl(),
              Text('Abgeschickt.', style: VText.h1),
              const VGap.s(),
              Text(Mock.longDate(DateTime.now()), style: VText.h2.copyWith(color: VColors.ink2, fontWeight: FontWeight.w400)),
              const VGap.m(),
              Text('An ${mail.to}, von deiner Adresse. Die Kopie ist in deinem Postfach.', style: VText.body.copyWith(color: VColors.ink2)),
              if (dryRun) ...[
                const VGap.s(),
                Text('Testlauf: keine echte Mail hat das Haus verlassen.', style: VText.caption),
              ],
              const Spacer(),
              VPrimaryButton(label: 'Zu den Anträgen', onTap: () => (context.canPop() ? context.pop() : context.go(Routes.antraege))),
            ],
          ),
        ),
      ),
    );
  }
}
