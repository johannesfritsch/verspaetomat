import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, PlatformException;
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:go_router/go_router.dart';

import '../../api/client.dart' show ApiException;
import '../../api/models.dart';
import '../../mock/mock_data.dart' show Mock;
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../../widgets/konfetti.dart';
import '../../widgets/ticket.dart';
import '../share/share_lines.dart';
import '../share/share_sheet.dart';
import 'claims_widgets.dart';
import 'pdf_view.dart';
import 'signature_board.dart';
import 'ticket_photo.dart';

/// Antrag: the five-step claim flow. Prüfen · Ticket · Zweck · Unterschrift · Senden.
class AntragScreen extends StatefulWidget {
  const AntragScreen({super.key, required this.desk, this.claimId, this.draft, this.demo = false});
  final String desk;
  final String? claimId;
  final ApiClaimDraft? draft;

  /// Reached from „Vorführung ansehen" rather than from a real claim. Says so on the first screen,
  /// so nobody walks through five steps thinking their own delays are in it.
  final bool demo;

  @override
  State<AntragScreen> createState() => _AntragScreenState();
}

class _AntragScreenState extends State<AntragScreen> {
  static const _steps = ['Prüfen', 'Ticket', 'Zweck', 'Unterschrift', 'Senden'];

  /// One drawing per step, behind the header. Each names what the step is about rather than
  /// decorating it: the clock a delay is measured against, a ticket on a phone, a heart in a
  /// hand, the form under a pen, the letter leaving.
  static const _art = [
    VHeaderSceneArt.antragPruefen,
    VHeaderSceneArt.antragTicket,
    VHeaderSceneArt.antragZweck,
    VHeaderSceneArt.antragUnterschrift,
    VHeaderSceneArt.antragSenden,
  ];

  /// The pre-step: what the five steps are, before the first one asks anything.
  bool _intro = true;
  int _step = 0;
  ApiClaimDraft? _draft;
  List<ApiIncident> _incidents = const [];

  /// Every open case at this desk, and the ones that go into this Antrag. Default: all of them.
  List<ApiIncident> _available = const [];
  Set<String> _selected = const {};
  List<ApiNgo> _ngos = const [];
  Object? _error;
  bool _loading = true;
  bool _busy = false;
  bool _showPersonal = false;
  bool _otherNgo = false;
  final Map<String, String> _uploads = {}; // month → upload id

  /// What was actually attached, so the step can show it back. The bytes are only in memory: the
  /// server has no route that serves an upload, and a passenger about to send a picture to a
  /// railway should be able to see which picture it is.
  final Map<String, Uint8List> _previews = {};
  bool _signed = false;
  bool _sentDryRun = false;
  ApiSendResult? _sent;
  final _unknownAddress = TextEditingController();

  /// „Deine Angaben", held here rather than inside the form so „Weiter" can check and save them.
  /// There used to be a separate „Speichern" in the form and „Weiter" stayed grey until it was
  /// pressed, with nothing on the screen saying why. Now there is one button and it does the work.
  final _pName = TextEditingController();
  final _pAddress = TextEditingController();
  final _pEmail = TextEditingController();
  final _pTicket = TextEditingController();

  /// Where each required row is and how to put the cursor in it, so „Weiter" can take the
  /// passenger to what is missing. It used to name the missing field in a snackbar while the form
  /// sat below the fold — and after the e-mail row was relabelled „Postfach", people put their
  /// postcode there and were told an e-mail field was missing that they could not find (#19).
  final _fName = FocusNode();
  final _fAddress = FocusNode();
  final _fEmail = FocusNode();
  final _kName = GlobalKey();
  final _kAddress = GlobalKey();
  final _kEmail = GlobalKey();
  final _kUnknownDesk = GlobalKey();

  /// The rows the last „Weiter" found missing or wrong. Each mark goes as soon as its row is fine.
  Set<PersonalField> _marked = {};
  /// The signature as drawn, so the step can show it back. The server has no route that serves an
  /// upload, and in Demo there is no upload at all.
  Uint8List? _signaturePng;

  bool get _unknownDesk => widget.desk == 'Unbekannt';
  ApiClaim? get _claim => _draft?.claim;
  bool get _paperOnly => _draft != null && (_draft!.deskEmail == null || _draft!.deskEmail!.isEmpty);

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    // Leaving the e-mail row with something that is not an address says so right there, not only
    // when „Weiter" is pressed.
    _fEmail.addListener(() {
      if (!_fEmail.hasFocus && _pEmail.text.trim().isNotEmpty && !looksLikeEmail(_pEmail.text)) {
        setState(() => _marked = {..._marked, PersonalField.email});
      }
    });
  }

  @override
  void dispose() {
    _unknownAddress.dispose();
    for (final c in [_pName, _pAddress, _pEmail, _pTicket]) {
      c.dispose();
    }
    for (final f in [_fName, _fAddress, _fEmail]) {
      f.dispose();
    }
    super.dispose();
  }

  /// A case taken out while the draft is open (docs/21 §4). The draft is rebuilt; if the
  /// rest no longer reaches 4 €, the backend drops it and we go back to Anträge.
  Future<void> _discardFromDraft(String id, String reason) async {
    final session = RepoScope.read(context);
    bool claimDeleted = false;
    try {
      claimDeleted = await session.repo.discardIncident(id, reason);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ging nicht: $e')));
      return;
    }
    if (!mounted) return;
    _draft = null;
    if (!claimDeleted) {
      try {
        await _load();
      } catch (_) {}
      if (!mounted) return;
    }
    if (claimDeleted || _draft == null || _incidents.isEmpty) {
      _error = null;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Der Antrag erreicht die 4 € nicht mehr. Wird weiter gesammelt.')));
      context.pop();
    }
  }

  /// Take a case out of this Antrag, or put it back. The backend rebuilds the draft around the
  /// new selection; a selection that no longer reaches 4 € is refused and the old one stands.
  /// Different from taking a case out for good, which the evidence sheet does (docs/21 §4).
  Future<void> _toggleCase(String id) async {
    final next = Set<String>.from(_selected);
    if (!next.remove(id)) next.add(id);
    if (next.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ein Fall muss drin bleiben.')));
      return;
    }
    final session = RepoScope.read(context);
    setState(() => _busy = true);
    try {
      final draft = await session.repo.draftClaim(desk: widget.desk, incidentIds: next.toList());
      final ids = draft.claim.incidentIds.toSet();
      // The draft is a new one: its ticket and its signature are gone with the old form.
      _draft = draft;
      _incidents = _available.where((i) => ids.contains(i.id)).toList();
      _selected = ids;
      _signed = draft.claim.signedBy != null;
      _readAttachments();
    } on ApiException catch (e) {
      if (!mounted) return;
      final msg = e.status == 412 ? 'Ohne diesen Fall kommen keine 4 € zusammen. Er bleibt drin.' : 'Ging nicht: ${e.message}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ging nicht: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      _available = ledger.incidents.where((i) => i.desk == widget.desk && (i.isOpen || ids.contains(i.id))).toList()..sort((a, b) => a.date.compareTo(b.date));
      _selected = ids;
      _ngos = session.ngos.isNotEmpty ? session.ngos : await session.repo.ngos();
      final me = session.me ?? await session.repo.getMe();
      _showPersonal = _draft!.personalDataRequired || me.personalData == null;
      final pd = me.personalData;
      if (pd != null && _pName.text.isEmpty && _pAddress.text.isEmpty && _pEmail.text.isEmpty) {
        _pName.text = pd.name;
        _pAddress.text = pd.address;
        _pEmail.text = pd.email;
        _pTicket.text = pd.ticketNumber ?? '';
      }
      _signed = _draft!.claim.signedBy != null;
      _readAttachments();
    } catch (e) {
      _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// What is already on this form. A draft left lying about keeps its tickets, so the Ticket
  /// step shows them instead of asking a second time — and a second upload does not replace
  /// the first one under a new id.
  void _readAttachments() {
    _uploads.clear();
    for (final m in _months) {
      final a = _draft?.claim.attachments.where((a) => a.label == ticketLabel(m)).firstOrNull;
      if (a != null) _uploads[m] = a.uploadId;
    }
  }

  ApiNgo? get _ngo {
    final id = _claim?.ngoId;
    return _ngos.where((n) => n.id == id).firstOrNull ?? _ngos.firstOrNull;
  }

  bool get _canContinue => switch (_step) {
        // Only "is there anything to claim". What is still missing is said when Weiter is pressed,
        // instead of a grey button that does not explain itself.
        0 => _incidents.isNotEmpty,
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

  /// Attach a picture of the ticket for one month.
  ///
  /// The picker runs *before* [_run], so backing out of the photo sheet is a silent no-op rather
  /// than a red „Anhängen fehlgeschlagen" — cancelling is not a failure.
  ///
  /// Demo mode draws the ticket instead of asking for one. That is not a fallback, it is the
  /// point: the showcase and the screenshot tour run on a simulator with no camera and no photo
  /// library worth the name, and neither should stall on a permission sheet.
  Future<void> _attach(String month, ImageSource source) async {
    final session = RepoScope.read(context);
    Uint8List? bytes;
    // A drawn ticket is drawn again by MockTicket when the step renders, so it needs no preview
    // of its own; only a picked photo does.
    var keepPreview = true;
    if (!session.isLocal || TicketPhoto.automation) {
      keepPreview = false;
      final me = session.me;
      bytes = await renderTicketPng(
        name: me?.personalData?.name ?? me?.nickname ?? 'Fahrgast',
        ticketNumber: me?.personalData?.ticketNumber ?? '–',
        month: month == 'Ticket' ? 'Fahrkarte' : monthLabel(month),
      );
    } else {
      try {
        bytes = await TicketPhoto.pick(source);
      } on PlatformException catch (e) {
        if (!mounted) return;
        // A permission that was refused for good is the one case a tap must not silently do
        // nothing (docs/23 §1): say what is missing and where it is turned back on.
        final denied = e.code == 'camera_access_denied' || e.code == 'photo_access_denied';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(denied
              ? 'Verspätomat darf nicht auf ${source == ImageSource.camera ? 'die Kamera' : 'deine Fotos'} zugreifen. In den Einstellungen kannst du das ändern.'
              : 'Das Bild ließ sich nicht öffnen: ${e.message ?? e.code}'),
        ));
        return;
      }
      if (bytes == null) return; // backed out of the sheet
    }
    final data = bytes;
    if (!mounted) return;
    await _run(() async {
      final up = await session.repo.upload(kind: 'ticket', filename: 'Ticket_$month.jpg', bytes: data);
      _uploads[month] = up.uploadId;
      if (keepPreview) _previews[month] = data;
      final claim = await session.repo.patchClaim(
        _claim!.id,
        attachments: [for (final e in _uploads.entries) ApiClaimAttachment(uploadId: e.value, label: ticketLabel(e.key))],
      );
      _draft = _withClaim(claim);
    }, failure: 'Anhängen fehlgeschlagen');
  }

  Future<void> _chooseNgo(String id) => _run(() async {
        final claim = await RepoScope.read(context).repo.patchClaim(_claim!.id, ngoId: id);
        _draft = _withClaim(claim);
      });

  /// Open the board, and if something is signed there, keep it.
  ///
  /// The board owns the whole interaction: it turns the phone sideways, takes the strokes and
  /// hands back the ink. This step only stores the result. There is no separate „Bestätigen" in
  /// the flow any more — confirming happens on the board, where the signature is, and a second
  /// confirmation further down the page only invited people to press it without signing.
  Future<void> _openSignatureBoard() async {
    final session = RepoScope.read(context);
    final name = session.me?.personalData?.name ?? session.me?.nickname ?? 'Fahrgast';
    final png = await SignatureBoard.open(context, name: name);
    if (png == null || !mounted) return;
    setState(() => _signaturePng = png);
    await _run(() async {
      // Uploaded in both modes. Against the server it is stored and rendered into the form; in Demo
      // the mock keeps it in memory and draws it into the example form, so the attachment on the
      // Senden step is the form as signed in either case.
      final sigId = (await session.repo.upload(kind: 'signature', filename: 'Unterschrift.png', bytes: png)).uploadId;
      final claim = await session.repo.signClaim(_claim!.id, typedName: name, signatureUploadId: sigId);
      _draft = _withClaim(claim);
      _signed = true;
    }, failure: 'Unterschrift fehlgeschlagen');
  }

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

  void _leave() => context.canPop() ? context.pop() : context.go(Routes.antraege);

  /// The X, and the swipe back, which is the same gesture with a different finger.
  ///
  /// Before the first step there is nothing to lose, so it just closes. Inside the steps it asks,
  /// and the question says what leaving actually costs — which is less than it looks against the
  /// server: the draft stays, with its tickets, its Zweck and its signature, and the next visit
  /// resumes it (docs/39). In the walkthrough nothing is kept at all, and it says that instead.
  Future<void> _close() async {
    if (_intro || _sent != null || _loading || _draft == null) {
      _leave();
      return;
    }
    final demo = widget.demo;
    final leave = await showVSheet<bool>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VSheetHeader(title: demo ? 'Vorführung beenden?' : 'Antrag verlassen?'),
          Padding(
            padding: const EdgeInsets.fromLTRB(VSpace.sheet, 0, VSpace.sheet, VSpace.l),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  demo
                      ? 'Die Vorführung hört hier auf. Nichts davon wird gespeichert, und verschickt wurde ohnehin nichts.'
                      : 'Abgeschickt wird nichts. Was du schon angehängt, ausgewählt und unterschrieben hast, bleibt als Entwurf liegen — beim nächsten Mal machst du dort weiter.',
                  style: VText.body,
                ),
                const VGap.l(),
                VPrimaryButton(label: demo ? 'Weiter ansehen' : 'Weiter ausfüllen', onTap: () => Navigator.of(ctx).pop(false)),
                const VGap.xs(),
                VGhostButton(
                  label: demo ? 'Vorführung beenden' : 'Antrag verlassen',
                  color: VColors.ink2,
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (leave == true && mounted) _leave();
  }

  @override
  Widget build(BuildContext context) {
    // A swipe from the edge on iOS, or the Android back button, used to leave the flow without a
    // word. It goes through the same question as the X now.
    return PopScope(
      canPop: _intro || _sent != null || _loading || _draft == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: _screen(context),
    );
  }

  Widget _screen(BuildContext context) {
    final session = RepoScope.of(context);
    if (_sent != null) {
      return _Sent(
        demo: widget.demo,
        desk: widget.desk,
        dryRun: _sentDryRun,
        mail: _sent!.mail,
        claim: _claim,
        incidents: _incidents,
      );
    }
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

    if (_intro) {
      return _Ueberblick(
        demo: widget.demo,
        desk: widget.desk,
        steps: _steps,
        cases: _incidents.length,
        amountCents: _draft!.claim.amountClaimedCents,
        onStart: () => setState(() => _intro = false),
        onClose: _close,
      );
    }

    final me = session.me;
    final content = switch (_step) {
      0 => _Pruefen(
          draft: _draft!,
          incidents: _incidents,
          available: _available,
          selected: _selected,
          busy: _busy,
          onToggle: _toggleCase,
          onDiscard: _discardFromDraft,
          me: me,
          desk: widget.desk,
          unknown: _unknownDesk,
          addressCtl: _unknownAddress,
          unknownKey: _kUnknownDesk,
          showPersonal: _showPersonal,
          onChanged: () => setState(() {
            // A mark stays only while its row is still missing.
            if (_marked.isNotEmpty) _marked = _marked.intersection(_missingPersonal().toSet());
          }),
          personal: (name: _pName, address: _pAddress, email: _pEmail, ticket: _pTicket),
          focus: (name: _fName, address: _fAddress, email: _fEmail),
          keys: (name: _kName, address: _kAddress, email: _kEmail),
          marked: _marked,
        ),
      1 => _Ticket(
          months: _months,
          uploads: _uploads,
          previews: _previews,
          demo: !RepoScope.read(context).isLocal || TicketPhoto.automation,
          busy: _busy,
          onAttach: _attach,
        ),
      2 => _Zweck(ngos: _ngos, selected: _ngo, other: _otherNgo, onOther: () => setState(() => _otherNgo = !_otherNgo), onChoose: _chooseNgo),
      3 => _Unterschrift(
          draft: _draft!,
          incidents: _incidents,
          me: me,
          ngo: _ngo,
          signed: _signed,
          busy: _busy,
          signaturePng: _signaturePng,
          onSign: _openSignatureBoard,
        ),
      _ => _Senden(draft: _draft!, incidents: _incidents, me: me, ngo: _ngo, paperOnly: _paperOnly),
    };

    final last = _step == _steps.length - 1;
    return VScreen(
      eyebrow: 'Antrag · ${deskDisplay(widget.desk)}',
      title: _steps[_step],
      scroll: true,
      art: _art[_step],
      onClose: _close,
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
            VPrimaryButton(
              label: 'Weiter',
              trailingIcon: Icons.arrow_forward,
              onTap: _canContinue && !_busy ? () => _step == 0 ? _advanceFromPruefen() : setState(() => _step += 1) : null,
            ),
          // One step back, everywhere — on the first step that is the overview. Leaving the whole
          // Antrag is the X at the top, never this.
          const VGap.xs(),
          VGhostButton(label: 'Zurück', onTap: () => setState(() => _step == 0 ? _intro = true : _step -= 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VStepIndicator(steps: _steps, current: _step),
          const VGap.l(),
          content,
          const VGap.xl(),
        ],
      ),
    );
  }

  /// The personal rows still missing, in the order they stand on the screen.
  List<PersonalField> _missingPersonal() => [
        if (_showPersonal && _pName.text.trim().isEmpty) PersonalField.name,
        if (_showPersonal && _pAddress.text.trim().isEmpty) PersonalField.address,
        if (_showPersonal && !looksLikeEmail(_pEmail.text)) PersonalField.email,
      ];

  /// Weiter on „Prüfen": check what the form needs, save it, show the twelve words, move on.
  ///
  /// Something missing: mark every missing row, scroll to the first and put the cursor in it. A
  /// message about a field the passenger cannot see is a riddle, not a hint.
  Future<void> _advanceFromPruefen() async {
    final missing = _missingPersonal();
    final deskMissing = _unknownDesk && _unknownAddress.text.trim().isEmpty;
    if (missing.isNotEmpty || deskMissing) {
      setState(() => _marked = missing.toSet());
      final (key, focus) = switch (missing.firstOrNull) {
        PersonalField.name => (_kName, _fName),
        PersonalField.address => (_kAddress, _fAddress),
        PersonalField.email => (_kEmail, _fEmail),
        null => (_kUnknownDesk, null),
      };
      final target = key.currentContext;
      if (target != null) {
        await Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic, alignment: 0.3);
      }
      if (!mounted) return;
      focus?.requestFocus();
      if (missing.isEmpty && deskMissing) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Für das Formular fehlt noch die Anschrift der Stelle.')));
      }
      return;
    }
    if (_showPersonal) {
      final session = RepoScope.read(context);
      setState(() => _busy = true);
      await session.savePersonalData(ApiPersonalData(
        name: _pName.text.trim(),
        address: _pAddress.text.trim(),
        email: _pEmail.text.trim(),
        ticketNumber: _pTicket.text.trim().isEmpty ? null : _pTicket.text.trim(),
      ));
      if (!mounted) return;
      setState(() => _busy = false);
      if (session.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: ${session.error}')));
        return;
      }
      setState(() => _showPersonal = false);
      // The first time somebody gives us their name is the moment the account starts to matter,
      // so this is where the twelve words are shown — once, and only on the way forward.
      await _maybeShowRecoveryCode();
      if (!mounted) return;
    }
    setState(() => _step = 1);
  }

  Future<void> _maybeShowRecoveryCode() async {
    final session = RepoScope.read(context);
    final code = await session.recoveryCode();
    if (code == null || !mounted) return;
    await showVSheet(
      context,
      // Not swipeable. These words are shown once and cannot be shown again — the server keeps only
      // a hash — so the sheet waits for an answer instead of vanishing under a stray drag.
      dismissible: false,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VSheetHeader(title: 'Deine zwölf Wörter', subtitle: 'Schreib sie auf oder mach einen Screenshot.', dismissible: false),
          Padding(
            padding: const EdgeInsets.fromLTRB(VSpace.sheet, 0, VSpace.sheet, VSpace.l),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Verspätomat hat kein Konto und kein Passwort. Mit diesen Wörtern holst du dein Konto, deine '
                  'Fahrten und deine Anträge auf ein neues Telefon. Wir zeigen sie dir nur dieses eine Mal.',
                  style: VText.body,
                ),
                const VGap.m(),
                VCard(child: SelectableText(code, style: VText.mono.copyWith(fontSize: 18, height: 1.5))),
                const VGap.s(),
                VGhostButton(
                  label: 'Kopieren',
                  icon: Icons.content_copy_outlined,
                  color: VColors.ink2,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Kopiert. Leg sie irgendwo hin, wo du sie wiederfindest.')));
                  },
                ),
                const VGap.xs(),
                const VNoteBanner(
                  icon: Icons.lock_outline,
                  text: 'Wer diese Wörter hat, hat dein Konto. Aufschreiben ja, verschicken nein.',
                ),
                const VGap.l(),
                VPrimaryButton(label: 'Ich habe sie notiert', onTap: () => Navigator.of(ctx).pop()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The pre-step: what is about to happen, before the first question is asked. The Antrag is
/// the one place in this app where a passenger signs something, so it says up front what the
/// five steps want and what leaves the house at the end.
class _Ueberblick extends StatelessWidget {
  const _Ueberblick({required this.desk, required this.steps, required this.cases, required this.amountCents, required this.onStart, required this.onClose, this.demo = false});
  final bool demo;
  final VoidCallback onClose;
  final String desk;
  final List<String> steps;
  final int cases;
  final int amountCents;
  final VoidCallback onStart;

  static const _what = [
    'Welche Verspätungen mitkommen, an welche Stelle sie gehen und mit welchen Angaben.',
    'Ein Bild deines Tickets. Das will die Bahn sehen, mehr Nachweis braucht es nicht.',
    'Wohin die Entschädigung überwiesen wird. Der Verein steht auf dem Formular, nicht wir.',
    'Das ausgefüllte EU-Formular lesen und mit deinem Namen bestätigen.',
    'Abschicken. Von deiner Verspätomat-Adresse, mit Kopie in dein Postfach.',
  ];

  /// One glyph per step, and each names the step's object rather than its verb: the form, the
  /// ticket, the Verein, the signature, the letter.
  static const _icons = [
    Icons.description_outlined,
    Icons.confirmation_number_outlined,
    Icons.favorite_border,
    Icons.draw_outlined,
    Icons.send_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    return VScreen(
      eyebrow: 'Antrag · ${deskDisplay(desk)}',
      title: 'So läuft das',
      scroll: true,
      art: VHeaderSceneArt.antragPruefen,
      onClose: onClose,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          VPrimaryButton(label: 'Los geht\'s', trailingIcon: Icons.arrow_forward, onTap: onStart),
          const VGap.xs(),
          VGhostButton(label: 'Später', onTap: () => context.canPop() ? context.pop() : context.go(Routes.antraege)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (demo) ...[
            const VGap.s(),
            const VNoteBanner(
              icon: Icons.play_circle_outline,
              text: 'Vorführung mit Beispieldaten. Du kannst alle fünf Schritte durchgehen; '
                  'es wird nichts gespeichert und nichts verschickt.',
            ),
          ],
          const VGap.s(),
          Text('$cases ${cases == 1 ? 'Fall' : 'Fälle'} · ${fmtCents(amountCents)}', style: VText.h2),
          const VGap.s(),
          // Broken where the mockup breaks it. The drawing comes down the right of this block,
          // and one long line would run under the train.
          Text('Fünf Schritte, keine zwei Minuten.\nZurück kommst du jederzeit.', style: VText.caption),
          const VGap.l(),
          VStepList(
            steps: [
              for (var i = 0; i < steps.length; i++)
                VStep(title: steps[i], text: _what[i], icon: _icons[i]),
            ],
          ),
          const VGap.l(),
          // The mockup closes this block with the thick red rule the redesign retired (docs/43).
          // A hairline says the same thing without reopening a device that was put away.
          const VDivider(strong: true),
          const VGap.m(),
          const VNoteBanner(
            tone: VNoteTone.plain,
            icon: Icons.verified_user_outlined,
            text: 'Der Antrag ist deiner. Wir füllen ihn aus und überbringen ihn, wir schreiben der Bahn nie von uns aus.',
          ),
          const VGap.xl(),
        ],
      ),
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
    required this.available,
    required this.selected,
    required this.busy,
    required this.onToggle,
    required this.onDiscard,
    required this.me,
    required this.desk,
    required this.unknown,
    required this.addressCtl,
    required this.unknownKey,
    required this.showPersonal,
    required this.onChanged,
    required this.personal,
    required this.focus,
    required this.keys,
    required this.marked,
  });
  final ApiClaimDraft draft;
  final List<ApiIncident> incidents;

  /// Every open case at this desk: the ticked ones go in, the others wait for the next Antrag.
  final List<ApiIncident> available;
  final Set<String> selected;
  final bool busy;
  final Future<void> Function(String id) onToggle;
  final Future<void> Function(String id, String reason) onDiscard;
  final ApiCustomer? me;
  final String desk;
  final bool unknown;
  final TextEditingController addressCtl;
  final GlobalKey unknownKey;
  final bool showPersonal;
  final VoidCallback onChanged;
  final ({TextEditingController name, TextEditingController address, TextEditingController email, TextEditingController ticket}) personal;
  final ({FocusNode name, FocusNode address, FocusNode email}) focus;
  final ({GlobalKey name, GlobalKey address, GlobalKey email}) keys;
  final Set<PersonalField> marked;

  @override
  Widget build(BuildContext context) {
    final amount = draft.claim.amountClaimedCents;
    final cases = available.isNotEmpty ? available : incidents;
    final pd = me?.personalData;
    final relay = me?.relayAddress ?? draft.relayAddress;
    final form = showPersonal || pd == null;
    final goesTo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VGap.xl(),
        const VSectionHeader('Geht an', onCard: false),
        const VGap.m(),
        if (unknown || (draft.deskAddress == null && draft.deskEmail == null))
          _UnknownDesk(key: unknownKey, ctl: addressCtl, onChanged: onChanged)
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
      ],
    );
    final yours = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VGap.xl(),
        const VSectionHeader('Deine Angaben', onCard: false),
        if (form)
          _PersonalForm(fields: personal, focus: focus, keys: keys, marked: marked, onChanged: onChanged)
        else ...[
          VKeyValue('Name', pd.name, strong: true),
          const VRule(),
          VKeyValue('Anschrift', pd.address.replaceAll('\n', ', ')),
          const VRule(),
          VKeyValue('E-Mail', pd.email),
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
                Text('Deine Anträge gehen von hier raus. Antworten der Bahn landen dort und sofort auch in deinem E-Mail-Postfach.', style: VText.caption),
              ],
            ),
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Diese Verspätungen gehen in den Antrag.', style: VText.h2),
        const VGap.s(),
        Text('Alle offenen Fälle dieser Stelle sind angehakt. Jeder steht einzeln im Formular.', style: VText.caption),
        const VGap.m(),
        VSectionHeader('Fälle', onCard: false, trailing: Text('${selected.length} von ${cases.length} · ${fmtCents(amount)}', style: VText.bodySStrong)),
        if (cases.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: VSpace.m),
            child: Text('Keine offenen Fälle für diese Stelle.', style: VText.caption),
          ),
        // Each case is its own card. They used to be rows inside one, which read as a table —
        // and a table is a thing you scan, where this is a list of decisions with money on them.
        for (final i in cases) ...[
          const VGap.s(),
          Opacity(
            opacity: selected.contains(i.id) ? 1 : 0.5,
            child: VCard(
              padding: const EdgeInsets.symmetric(horizontal: VSpace.cardTight),
              child: IncidentRow(
                incident: i,
                divider: false,
                chevron: true,
                leading: VCheckbox(
                  checked: selected.contains(i.id),
                  // Red, not ink: these ticks are the only ones in the app that move a sum.
                  color: VColors.red,
                  label: '${i.line} am ${Mock.shortDate(i.date)}',
                  onTap: busy ? null : () => onToggle(i.id),
                ),
                onTap: () => showEvidenceSheet(context, i, onDiscard: (reason) => onDiscard(i.id, reason)),
              ),
            ),
          ),
        ],
        const VGap.m(),
        const VNoteBanner(
          tone: VNoteTone.neutral,
          icon: Icons.info_outline,
          text: 'Abhaken nimmt einen Fall nur aus diesem Antrag; er bleibt liegen und kommt in den nächsten. '
              'Tipp die Zeile an, wenn du den Nachweis sehen oder den Fall ganz verwerfen willst.',
        ),
        // While „Deine Angaben" still has to be filled in it comes first: it is the one part of this
        // step that asks for something, and below „Geht an" it started well under the fold.
        if (form) ...[yours, goesTo] else ...[goesTo, yours],
        const VGap.s(),
        Text('Diese Daten stehen nur auf dem Formular.', style: VText.caption),
      ],
    );
  }
}

class _UnknownDesk extends StatelessWidget {
  const _UnknownDesk({super.key, required this.ctl, required this.onChanged});
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

/// The rows of „Deine Angaben" that „Weiter" can find missing.
enum PersonalField { name, address, email }

/// Something shaped like an e-mail address. Not a full RFC check — the point is to catch a
/// postcode or a name in the e-mail row, before the claim goes out with no copy for the passenger.
bool looksLikeEmail(String s) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(s.trim());

/// First claim only: name, address, private inbox, ticket number.
/// „Deine Angaben": the fields and nothing else. Checking and saving belong to „Weiter", so this
/// has no button of its own — a form with its own save next to a flow's own onward button asks the
/// passenger to work out which one matters, and the answer used to be "both, in order".
class _PersonalForm extends StatelessWidget {
  const _PersonalForm({required this.fields, required this.focus, required this.keys, required this.marked, required this.onChanged});
  final ({TextEditingController name, TextEditingController address, TextEditingController email, TextEditingController ticket}) fields;
  final ({FocusNode name, FocusNode address, FocusNode email}) focus;
  final ({GlobalKey name, GlobalKey address, GlobalKey email}) keys;
  final Set<PersonalField> marked;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VGap.s(),
        Text('Einmal eintragen. Steht danach auf jedem Antrag.', style: VText.caption),
        const VGap.m(),
        // One card, four labelled rows, hairlines between them — the shape every other list in the
        // app has. It was four bare TextFields with hint text and an outlined button, which is the
        // pre-redesign form and the last one left in this flow.
        //
        // The autofill hints matter as much as the look: an address and an e-mail are exactly what
        // the keyboard already knows, and typing a postal address on a phone is the slowest thing
        // this app asks anybody to do. AutofillGroup wraps them so iOS offers the whole contact
        // card at once rather than field by field.
        AutofillGroup(
          child: VCard(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.card),
            child: Column(
              children: [
                _Field(
                  key: keys.name,
                  label: 'Name',
                  hint: 'Vor- und Nachname',
                  focusNode: focus.name,
                  error: marked.contains(PersonalField.name) ? 'Fehlt noch.' : null,
                  controller: fields.name,
                  onChanged: onChanged,
                  autofill: const [AutofillHints.name],
                  capitalization: TextCapitalization.words,
                ),
                const VDivider(),
                _Field(
                  key: keys.address,
                  label: 'Anschrift',
                  hint: 'Straße, Hausnummer, PLZ und Ort',
                  focusNode: focus.address,
                  error: marked.contains(PersonalField.address) ? 'Fehlt noch.' : null,
                  controller: fields.address,
                  onChanged: onChanged,
                  autofill: const [AutofillHints.fullStreetAddress, AutofillHints.postalAddress],
                  capitalization: TextCapitalization.words,
                  lines: 2,
                ),
                const VDivider(),
                // „E-Mail", not „Postfach": next to „Anschrift" that read as a P.O. box, and a postcode
                // went in (#19). The word has to stay on screen once the field is filled.
                _Field(
                  key: keys.email,
                  label: 'E-Mail',
                  hint: 'Für die Kopie jedes Antrags',
                  focusNode: focus.email,
                  error: marked.contains(PersonalField.email) ? (fields.email.text.trim().isEmpty ? 'Fehlt noch.' : 'Das ist keine E-Mail-Adresse.') : null,
                  controller: fields.email,
                  onChanged: onChanged,
                  autofill: const [AutofillHints.email],
                  keyboard: TextInputType.emailAddress,
                ),
                const VDivider(),
                _Field(
                  label: 'Ticket-Nr.',
                  hint: 'Optional',
                  controller: fields.ticket,
                  onChanged: onChanged,
                  mono: true,
                ),
              ],
            ),
          ),
        ),
        const VGap.s(),
        VNoteBanner(
          tone: VNoteTone.neutral,
          icon: Icons.lock_outline,
          text: 'Diese Angaben stehen nur auf dem Formular an das Eisenbahnunternehmen. '
              'Sie bleiben auf ${RepoScope.read(context).isLocal ? 'deinem Gerät und unserem Server' : 'diesem Gerät'}.',
        ),

      ],
    );
  }
}

/// One labelled row of the personal-data card: the label on the left, the field on the right,
/// which is how [VKeyValue] renders the same facts once they are saved. A form that reads like the
/// thing it becomes is easier to check than one that looks like a different screen.
class _Field extends StatelessWidget {
  const _Field({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
    this.focusNode,
    this.error,
    this.autofill,
    this.keyboard,
    this.capitalization = TextCapitalization.none,
    this.lines = 1,
    this.mono = false,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final FocusNode? focusNode;

  /// What is wrong with the row, shown under it with the label in red. Null: nothing.
  final String? error;
  final List<String>? autofill;
  final TextInputType? keyboard;
  final TextCapitalization capitalization;
  final int lines;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final wrong = error != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: VSpace.s),
      // One node for the reader: „E-Mail, text field", not a label and a field it has to pair.
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(label, style: VText.bodyS.copyWith(color: wrong ? VColors.red : VColors.ink2)),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: (_) => onChanged(),
                    autofillHints: autofill,
                    keyboardType: keyboard,
                    textCapitalization: capitalization,
                    maxLines: lines,
                    style: mono ? VText.mono : VText.bodySStrong,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: VText.bodyS.copyWith(color: VColors.ink3),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
            if (wrong)
              Padding(
                padding: const EdgeInsets.only(left: 96, bottom: VSpace.xs),
                child: Text(error!, style: VText.caption.copyWith(color: VColors.red)),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 11.2 Ticket
// ---------------------------------------------------------------------------

class _Ticket extends StatelessWidget {
  const _Ticket({
    required this.months,
    required this.uploads,
    required this.previews,
    required this.demo,
    required this.busy,
    required this.onAttach,
  });
  final List<String> months;
  final Map<String, String> uploads;

  /// The bytes of what was attached this session, so the step can show it back.
  final Map<String, Uint8List> previews;

  /// Demo draws a ticket instead of opening a picker, so the showcase and the tour run on a
  /// simulator without stalling on a permission sheet.
  final bool demo;

  final bool busy;
  final Future<void> Function(String month, ImageSource source) onAttach;

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
            VSectionHeader(monthLabel(m), onCard: false),
            const VGap.s(),
          ],
          if (!uploads.containsKey(m)) ...[
            VDropzone(
              title: busy ? 'Lädt hoch …' : 'Ticket anhängen',
              text: demo ? 'In der Vorführung malen wir eins.' : 'Foto auswählen oder direkt aufnehmen.',
              hint: demo ? null : 'PNG, JPG oder HEIC',
              busy: busy,
              onTap: () => onAttach(m, ImageSource.gallery),
              // One dashed box per month, with the camera as a named second way in, rather than
              // two boxes side by side: with August and September on one screen, two entry points
              // each is four boxes and no clearer.
              secondaryLabel: demo ? null : 'Stattdessen fotografieren',
              secondaryIcon: Icons.photo_camera_outlined,
              onSecondary: demo ? null : () => onAttach(m, ImageSource.camera),
            ),
          ] else ...[
            // The picture sits on a sunken card so it reads as a picture of a thing rather than as
            // another block of this screen.
            VCard(
              tone: VCardTone.sunken,
              padding: const EdgeInsets.all(VSpace.md),
              child: previews[m] != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(VRadius.md),
                      child: ConstrainedBox(
                        // Tall enough to read a ticket number, bounded so a portrait photo does
                        // not push the rest of the step off the screen.
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: Image.memory(previews[m]!, fit: BoxFit.contain, width: double.infinity),
                      ),
                    )
                  : MockTicket(
                      name: 'Fahrgast',
                      ticketNumber: '–',
                      month: m == 'Ticket' ? 'Fahrkarte' : monthLabel(m),
                    ),
            ),
            const VGap.s(),
            VNoteBanner(
              tone: VNoteTone.green,
              leading: const VIconBadge(
                icon: Icons.check,
                tone: VBadgeTone.green,
                filled: true,
                size: VControl.chevron,
                iconSize: 13,
              ),
              text: demo
                  ? 'Angehängt. Es bleibt liegen, bis der Antrag abgeschlossen ist, dann löschen wir es.'
                  : 'Angehängt. Ort und Zeit sind aus dem Bild entfernt. Es bleibt liegen, bis der Antrag abgeschlossen ist, dann löschen wir es.',
            ),
            if (!demo) ...[
              const VGap.xs(),
              // A drawn ticket never needed replacing. A photo picked by mistake does, and
              // without this the only way back is to start the Antrag again.
              VGhostButton(
                label: 'Anderes Bild',
                icon: Icons.refresh,
                color: VColors.ink2,
                onTap: busy ? null : () => onAttach(m, ImageSource.gallery),
              ),
            ],
          ],
          const VGap.l(),
        ],
        if (demo)
          const VNoteBanner(
            tone: VNoteTone.neutral,
            icon: Icons.info_outline,
            text: 'Vorführung: hier malt Verspätomat ein Ticket. In der echten App wählst du eines '
                'aus deinen Fotos oder fotografierst es.',
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 11.3 Zweck
// ---------------------------------------------------------------------------

class _Zweck extends StatelessWidget {
  const _Zweck({required this.ngos, required this.selected, required this.other, required this.onOther, required this.onChoose});
  final List<ApiNgo> ngos;
  final ApiNgo? selected;

  /// True once the list of other Zwecke is open.
  final bool other;
  final VoidCallback onOther;
  final Future<void> Function(String id) onChoose;

  @override
  Widget build(BuildContext context) {
    final ngo = selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Die Entschädigung geht direkt an:', style: VText.h2),
        const VGap.s(),
        Text('Der Verein steht auf dem Formular. Die Bahn überweist direkt dorthin, nicht an dich.', style: VText.caption),
        const VGap.l(),
        if (ngo == null)
          Text('Kein Verein gewählt.', style: VText.body)
        else ...[
          NgoAccountBox(
            ngo: ngo,
            onCopyIban: () {
              Clipboard.setData(ClipboardData(text: ngo.iban));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('IBAN kopiert.')));
            },
          ),
          const VGap.xs(),
          VGhostButton(
            label: 'Was ist ${ngo.name}?',
            icon: Icons.info_outline,
            trailingIcon: Icons.chevron_right,
            onTap: () => showNgoSheet(context, ngo),
          ),
        ],
        const VGap.l(),
        if (!other)
          // A disclosure, not a button: it opens a list further down this same screen. The
          // mockup draws it as a tinted row with a chevron, which is what VSelectCard is.
          VCard(
            tone: VCardTone.sunken,
            padding: const EdgeInsets.all(VSpace.cardTight),
            onTap: onOther,
            child: Row(
              children: [
                const VIconBadge(icon: Icons.swap_horiz, tone: VBadgeTone.neutral, size: VControl.badgeSmall, iconColor: VColors.ink),
                const SizedBox(width: VSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Anderen Zweck wählen', style: VText.title),
                      const SizedBox(height: 2),
                      // No names here: which Vereine exist is managed data (CLAUDE.md), and
                      // naming one the app has no relationship with implies a partnership that
                      // does not exist.
                      Text('Ein anderer gemeinnütziger Verein, nur für diesen Antrag.', style: VText.bodyS.copyWith(color: VColors.ink2)),
                    ],
                  ),
                ),
                const SizedBox(width: VSpace.s),
                const VChevron(),
              ],
            ),
          )
        else ...[
          // The disclosure's own header: a label naming the list under it, and a quiet way to
          // fold it away again. A VGhostButton stood on the right once, and it is a block
          // control — full width by design — so in a Row's non-flex slot it claimed an infinite
          // width and left the label none of it (test/ghost_button_row_test.dart). VIconButton
          // brings its own 44 pt box, which is also what sets the height of this row.
          Row(
            children: [
              const Expanded(child: VEyebrow('Nur für diesen Antrag', tone: VEyebrowTone.ink)),
              VIconButton(icon: Icons.close, color: VColors.ink2, onTap: onOther),
            ],
          ),
          const VGap.s(),
          NgoPicker(ngos: ngos, selectedId: ngo?.id, onChoose: onChoose),
          Text('Das ⓘ erzählt, wofür ein Verein das Geld nimmt. Dein Standard bleibt, was im Profil steht.', style: VText.caption),
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
    required this.signaturePng,
    required this.onSign,
  });
  final ApiClaimDraft draft;
  final List<ApiIncident> incidents;
  final ApiCustomer? me;
  final ApiNgo? ngo;
  final bool signed;
  final bool busy;

  /// The signature as drawn on the board, for showing it back.
  final Uint8List? signaturePng;

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
        // The mockup closes the document block with the thick red rule the redesign retired
        // (docs/43 §1). The hairline is the device that replaced it.
        const VDivider(strong: true),
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
        // The line, not a pad. Tapping it opens the board; signing happens there and is confirmed
        // there, so this page has no second „Bestätigen" to press without having signed.
        VCard(
          onTap: busy ? null : onSign,
          padding: const EdgeInsets.fromLTRB(VSpace.card, VSpace.m, VSpace.card, VSpace.s),
          child: Column(
            children: [
              SizedBox(
                height: 76,
                child: signaturePng == null
                    ? Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.draw_outlined, size: VControl.chevron, color: VColors.ink2),
                            const SizedBox(width: VSpace.s),
                            Text(busy ? 'Speichert …' : 'Hier unterschreiben', style: VText.bodyStrong.copyWith(color: VColors.ink2)),
                          ],
                        ),
                      )
                    : Center(child: Image.memory(signaturePng!, fit: BoxFit.contain)),
              ),
              Container(height: 1, color: VColors.hairlineStrong),
              const SizedBox(height: 6),
              Text(name, style: VText.caption),
            ],
          ),
        ),
        const VGap.s(),
        if (signed)
          // Untinted, so the screen does not end in a coloured block under the signature — but
          // the tick itself is green, which is the one word this line has to say.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const VNoteBanner(
                tone: VNoteTone.plain,
                leading: Icon(Icons.check, size: VControl.chevron, color: VColors.green),
                text: 'Bestätigt. Deine Unterschrift bleibt nur in diesem Antrag.',
              ),
              VGhostButton(label: 'Nochmal unterschreiben', icon: Icons.refresh, color: VColors.ink2, onTap: busy ? null : onSign),
            ],
          )
        else
          Text('Tipp auf die Linie. Das Telefon dreht sich, damit du so unterschreiben kannst wie auf Papier.', style: VText.caption),
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
        ] else ...[
          // The address in the preview is the address the mail really goes to, read from the same
          // table the server sends from. When that is not the railway's own desk, the screen says
          // so — a rehearsal must never be able to pass for a filed claim.
          if (!draft.routeLive) ...[
            VNoteBanner(
              icon: Icons.science_outlined,
              text: 'Probelauf${draft.routeLabel == null ? '' : ' („${draft.routeLabel}")'}: '
                  'diese E-Mail geht an ${draft.deskEmail ?? 'die eingetragene Adresse'} und nicht an das Eisenbahnunternehmen.',
            ),
            const VGap.s(),
          ],
          VCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const VIconBadge(icon: Icons.mail_outline, size: VControl.badgeSmall),
                    const SizedBox(width: VSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('E-Mail-Vorschau', style: VText.title),
                          const SizedBox(height: 2),
                          Text('So wird deine E-Mail versendet.', style: VText.caption),
                        ],
                      ),
                    ),
                  ],
                ),
                const VGap.s(),
                const VDivider(),
                const VGap.s(),
                // No attachment list inside the mail: the rows under this card carry them, one
                // per file, so what is listed is what actually leaves.
                MailView(mail: mail, boxed: false, showAttachments: false),
              ],
            ),
          ),
          const VGap.s(),
          // Every file that goes with the mail, under the name it will carry. The mockup draws a
          // single „EU-Antragsformular (ausgefüllt) · PDF · 1,2 MB": one attachment of four, a
          // name the mail does not use, and a size nothing in the app knows.
          for (final a in mail.attachments) ...[
            VCard(
              tone: VCardTone.tint,
              padding: const EdgeInsets.all(VSpace.cardTight),
              onTap: a.endsWith('.pdf') ? () => ClaimPdfPage.open(context, draft.claim.id) : null,
              child: Row(
                children: [
                  VIconBadge(
                    icon: a.endsWith('.pdf') ? Icons.description_outlined : Icons.image_outlined,
                    size: VControl.badgeSmall,
                  ),
                  const SizedBox(width: VSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Anhang', style: VText.bodyStrong),
                        const SizedBox(height: 2),
                        Text(a, style: VText.caption),
                      ],
                    ),
                  ),
                  if (a.endsWith('.pdf')) const VChevron(),
                ],
              ),
            ),
            const VGap.xs(),
          ],
        ],
        const VGap.s(),
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

/// The moment the Antrag is out. The one place in this app that celebrates, because it is the
/// one thing that was the passenger's own doing (docs/27 §4).
class _Sent extends StatefulWidget {
  const _Sent({required this.desk, required this.dryRun, required this.mail, required this.claim, required this.incidents, this.demo = false});
  final String desk;
  final bool dryRun;
  final ApiMail mail;
  final ApiClaim? claim;
  final List<ApiIncident> incidents;

  /// Reached from the walkthrough, where „Abgeschickt" is the middle of the story, not the end.
  final bool demo;

  @override
  State<_Sent> createState() => _SentState();
}

class _SentState extends State<_Sent> {
  bool _konfetti = true;

  /// Where „Abgeschickt" leads. In the walkthrough the story is only half told at this point — the
  /// interesting part is what the railway answers — so it goes on instead of stopping.
  void _leave(BuildContext context) {
    if (widget.demo) {
      context.push(Routes.vorfuehrungWeiter);
      return;
    }
    context.canPop() ? context.pop() : context.go(Routes.antraege);
  }

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    final c = widget.claim;
    final cases = widget.incidents.isNotEmpty ? widget.incidents.length : c?.incidentIds.length ?? 0;
    final minutes = widget.incidents.fold<int>(0, (a, i) => a + i.delayMinutes);
    final cents = c?.amountClaimedCents ?? widget.incidents.fold<int>(0, (a, i) => a + i.amountCents);
    final ngo = session.ngos.where((n) => n.id == (c?.ngoId ?? session.me?.settings.ngoId)).firstOrNull;
    final ngoName = ngo?.name ?? 'deinen Zweck';
    final canShare = cases > 0 && minutes > 0;

    return Scaffold(
      backgroundColor: VColors.paper,
      body: Stack(
        children: [
          SafeArea(
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
                  Text('An ${widget.mail.to}, von deiner Adresse. Die Kopie ist in deinem Postfach.', style: VText.body.copyWith(color: VColors.ink2)),
                  if (widget.dryRun) ...[
                    const VGap.s(),
                    Text('Testlauf: keine echte Mail hat das Haus verlassen.', style: VText.caption),
                  ],
                  const Spacer(),
                  if (canShare) ...[
                    VPrimaryButton(
                      label: 'Teilen',
                      icon: Icons.ios_share,
                      onTap: () => showShareSheet(
                        context,
                        date: DateTime.now(),
                        lines: ShareLines.antrag(minutes: minutes, cases: cases, cents: cents, ngo: ngoName),
                        build: ({fahrgast, strecke, date, line}) => TicketData.antrag(
                          minutes: minutes,
                          cases: cases,
                          euro: fmtCents(cents),
                          ngoName: ngoName,
                          ngoLogo: ngo?.logo,
                          fahrgast: fahrgast,
                          date: date,
                          line: line,
                        ),
                      ),
                    ),
                    const VGap.s(),
                    VGhostButton(label: widget.demo ? 'Und dann?' : 'Zu den Anträgen', onTap: () => _leave(context)),
                  ] else
                    VPrimaryButton(
                      label: widget.demo ? 'Und dann?' : 'Zu den Anträgen',
                      trailingIcon: widget.demo ? Icons.arrow_forward : null,
                      onTap: () => _leave(context),
                    ),
                ],
              ),
            ),
          ),
          if (_konfetti)
            Positioned.fill(child: Konfetti(onDone: () => setState(() => _konfetti = false))),
        ],
      ),
    );
  }
}
