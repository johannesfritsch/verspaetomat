import 'dart:typed_data';
import 'dart:ui' as ui;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../mock/mock_data.dart' show Mock, IncidentStatus, IncidentStatusX, TicketType, TicketTypeX;
import '../../repo/app_repository.dart';
import '../../repo/repo_scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';

/// One display name per claims desk, used on Konto, Antrag and Antwort.
String deskDisplay(String desk) => desk == 'Servicecenter Fahrgastrechte' ? 'Servicecenter (DB, ODEG, NEB …)' : desk;

VTone toneFor(IncidentStatus s) => switch (s) {
      IncidentStatus.bestaetigt => VTone.green,
      IncidentStatus.abgelehnt => VTone.red,
      IncidentStatus.verfallen => VTone.red,
      IncidentStatus.eingereicht => VTone.ink,
      _ => VTone.neutral,
    };

/// Euro cents → "4,50 €".
String fmtCents(int cents) => fmtEuro(cents / 100);

/// UTC timestamp → local "08:52".
String fmtClock(DateTime d) => fmtTime(TimeOfDay.fromDateTime(d.toLocal()));

/// "9. September 2026 08:52" from a UTC timestamp, local time.
String fmtStamp(DateTime d) => '${Mock.shortDate(d.toLocal())} ${fmtClock(d)}';

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

/// Runs one repository call and renders the result, with plain loading and
/// error lines. Call [refresh] via the returned controller to reload.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder, this.controller});
  final Future<T> Function(AppRepository repo) load;
  final Widget Function(BuildContext context, T data, VoidCallback refresh) builder;
  final LoaderController? controller;

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class LoaderController {
  VoidCallback? _refresh;
  Timer? _debounce;
  void refresh() => _refresh?.call();

  /// Reload once, [after] the last call in a burst. Used for event-stream refreshes,
  /// where a fast-forward emits ride, incident and claim events within milliseconds.
  void refreshSoon({Duration after = const Duration(milliseconds: 400)}) {
    _debounce?.cancel();
    _debounce = Timer(after, refresh);
  }

  void dispose() => _debounce?.cancel();
}

class _LoaderState<T> extends State<Loader<T>> {
  Future<T>? _future;
  AppRepository? _repo;

  @override
  void initState() {
    super.initState();
    widget.controller?._refresh = _reload;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = RepoScope.of(context).repo;
    if (!identical(repo, _repo)) {
      _repo = repo;
      _future = widget.load(repo);
    }
  }

  void _reload() {
    final repo = _repo;
    if (repo == null) return;
    setState(() {
      _future = widget.load(repo);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return LoadError(error: snap.error, onRetry: _reload);
        if (!snap.hasData) return const LoadingLine();
        return widget.builder(context, snap.data as T, _reload);
      },
    );
  }
}

class LoadingLine extends StatelessWidget {
  const LoadingLine({super.key, this.text = 'Lädt …'});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: VSpace.l),
        child: Text(text, style: VText.body.copyWith(color: VColors.ink2)),
      );
}

class LoadError extends StatelessWidget {
  const LoadError({super.key, required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: VSpace.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Das hat nicht geklappt.', style: VText.bodyStrong),
            const VGap.xs(),
            Text('$error', style: VText.caption, maxLines: 3, overflow: TextOverflow.ellipsis),
            const VGap.s(),
            VGhostButton(label: 'Erneut versuchen', icon: Icons.refresh, onTap: onRetry),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Incidents
// ---------------------------------------------------------------------------

/// One incident in the ledger: date, line, route on the left; delay,
/// amount and status on the right. Hairline below.
class IncidentRow extends StatelessWidget {
  const IncidentRow({super.key, required this.incident, this.onTap, this.leading, this.note, this.showStatus = false});
  final ApiIncident incident;
  final VoidCallback? onTap;
  final Widget? leading;

  /// Show the status chip. Off by default: sections already carry the status in their label.
  final bool showStatus;

  /// A caption under the route, e.g. "Abgeschickt 15.08. · Antwort in etwa 4 Wochen".
  final String? note;

  @override
  Widget build(BuildContext context) {
    final i = incident;
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 14)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(Mock.shortDate(i.date), style: VText.caption),
                          const SizedBox(width: 8),
                          Text(i.line, style: VText.bodySStrong),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('${i.from} → ${i.to}', style: VText.bodyS, maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (i.selfEntered || i.cancelled) ...[
                        const SizedBox(height: 2),
                        Text(
                          [if (i.cancelled) 'Ausfall', if (i.selfEntered) 'selbst eingetragen'].join(' · '),
                          style: VText.caption,
                        ),
                      ],
                      if (note != null) ...[
                        const SizedBox(height: 2),
                        Text(note!, style: VText.caption),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    VDelay(i.delayMinutes, size: VDelaySize.small),
                    const SizedBox(height: 2),
                    Text(fmtCents(i.amountCents), style: VText.captionInk.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    if (showStatus) ...[
                      const SizedBox(height: 4),
                      VChip(i.status.label, tone: toneFor(i.status)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const VRule(),
        ],
      ),
    );
  }
}

/// Why a case was taken out of a bundle (docs/21 §4).
const discardReasons = <String, String>{
  'nicht_gefahren': 'Ich bin da gar nicht mitgefahren',
  'doppelt': 'Doppelt erfasst',
  'sonst': 'Anderer Grund',
};

/// "Fahrt löschen": the ride, its points and its claim go, and nothing comes back (docs/23 §2).
/// Returns true when the passenger confirmed.
Future<bool> confirmDeleteRide(BuildContext context) async {
  final yes = await showVSheet<bool>(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.only(bottom: VSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VSheetHeader(
            title: 'Fahrt löschen?',
            subtitle: 'Die Fahrt, ihre Punkte und der Anspruch verschwinden. Das lässt sich nicht rückgängig machen.',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
            child: Column(
              children: [
                const VGap.s(),
                VOutlineButton(
                  key: const Key('delete-ride-confirm'),
                  label: 'Fahrt löschen',
                  icon: Icons.delete_outline,
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
                const VGap.xs(),
                VGhostButton(label: 'Behalten', color: VColors.ink2, onTap: () => Navigator.of(ctx).pop(false)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  return yes == true;
}

/// The evidence sheet behind an incident. [onDiscard] adds "Nicht einreichen" (and, for a
/// case already taken out, "Doch einreichen"); it is offered only while the bundle is open.
/// [onDelete] adds "Fahrt löschen" beside it (docs/23 §2), behind its own confirm.
Future<void> showEvidenceSheet(BuildContext context, ApiIncident i,
    {Future<void> Function(String reason)? onDiscard, Future<void> Function()? onRestore, Future<void> Function()? onDelete}) {
  final ev = i.evidence;
  return showVSheet(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.only(bottom: VSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VSheetHeader(title: '${i.line} · ${Mock.shortDate(i.date)}', subtitle: '${i.from} → ${i.to}'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VGap.s(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    VDelay(i.delayMinutes, size: VDelaySize.large, cancelled: false),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('Minuten am Ziel', style: VText.caption),
                    ),
                  ],
                ),
                const VGap.m(),
                const VRule.red(),
                VKeyValue('Ankunft laut Fahrplan', ev?.plannedArrival != null ? fmtClock(ev!.plannedArrival!) : '–'),
                const VRule(),
                VKeyValue('Tatsächliche Ankunft', ev?.actualArrival != null ? fmtClock(ev!.actualArrival!) : '–', strong: true),
                const VRule(),
                VKeyValue('Betreiber', i.operator),
                const VRule(),
                VKeyValue('Zuständige Stelle', i.desk),
                const VRule(),
                VKeyValue('Quelle', ev?.source ?? (i.selfEntered ? 'Selbst eingetragen' : 'Live-Daten Transitous')),
                const VRule(),
                VKeyValue('Erfasst am', ev?.fetchedAt != null ? fmtStamp(ev!.fetchedAt!) : Mock.shortDate(i.date)),
                const VRule(),
                VKeyValue('Ticket', i.ticket.label),
                const VRule(),
                VKeyValue('Anspruch', fmtCents(i.amountCents), strong: true),
                if (i.fareCents != null) ...[
                  const VRule(),
                  VKeyValue('Fahrpreis', fmtCents(i.fareCents!)),
                ],
                const VRule(),
                VKeyValue('Frist (gesetzlich)', Mock.longDate(i.legalDeadline)),
                const VGap.m(),
                VOutlineButton(
                  label: 'Als Nachweis exportieren',
                  icon: Icons.ios_share,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nachweis als PDF exportiert.')));
                  },
                ),
                if (onRestore != null) ...[
                  const VGap.xs(),
                  VGhostButton(
                    label: 'Doch einreichen',
                    icon: Icons.undo,
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await onRestore();
                    },
                  ),
                ] else if (onDiscard != null) ...[
                  const VGap.xs(),
                  VGhostButton(
                    label: 'Nicht einreichen',
                    icon: Icons.remove_circle_outline,
                    color: VColors.ink2,
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await showDiscardReasonSheet(context, onDiscard);
                    },
                  ),
                ],
                // The ride itself, not just the case (docs/23 §2). Beside "Doch einreichen",
                // because this is the other thing you may want with a ride you never took.
                if (onDelete != null) ...[
                  const VGap.xs(),
                  VGhostButton(
                    key: const Key('delete-ride'),
                    label: 'Fahrt löschen',
                    icon: Icons.delete_outline,
                    color: VColors.red,
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      if (await confirmDeleteRide(context)) await onDelete();
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Ticket
// ---------------------------------------------------------------------------

/// A mocked Deutschlandticket screenshot. No image assets.
class MockTicket extends StatelessWidget {
  const MockTicket({super.key, required this.name, required this.ticketNumber, this.month = 'September 2026'});
  final String name;
  final String ticketNumber;
  final String month;

  static const _bars = [3, 1, 4, 2, 1, 5, 2, 3, 1, 2, 4, 1, 3, 2, 5, 1, 2, 3, 1, 4, 2, 1, 3, 5, 1, 2, 4, 1, 3, 2, 2, 1, 4, 3, 1];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(VSpace.m),
      decoration: BoxDecoration(
        color: VColors.paperElevated,
        border: Border.all(color: VColors.rule),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Deutschlandticket', style: VText.title)),
              Text(month, style: VText.caption),
            ],
          ),
          const VGap.s(),
          const VRule(),
          const VGap.s(),
          Text(name, style: VText.bodyStrong),
          Text('Ticket-Nr. $ticketNumber', style: VText.mono.copyWith(color: VColors.ink2)),
          const VGap.m(),
          SizedBox(
            height: 46,
            child: Row(
              children: [
                for (final w in _bars) ...[
                  Container(width: w.toDouble(), color: VColors.ink),
                  const SizedBox(width: 2),
                ],
              ],
            ),
          ),
          const VGap.xs(),
          Text('Gültig im Nahverkehr · 2. Klasse', style: VText.caption),
        ],
      ),
    );
  }
}

/// Renders a plausible ticket image as PNG bytes, without any asset.
Future<Uint8List> renderTicketPng({required String name, required String ticketNumber, required String month}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const w = 720.0, h = 420.0;
  canvas.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFFFFFFF));
  canvas.drawRect(const Rect.fromLTWH(0, 0, w, 8), Paint()..color = VColors.red);
  void text(String s, double x, double y, double size, {FontWeight weight = FontWeight.w400, Color color = const Color(0xFF111111)}) {
    final p = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, fontWeight: weight, color: color, fontFamily: 'Helvetica')),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w - 2 * x);
    p.paint(canvas, Offset(x, y));
  }
  text('Deutschlandticket', 40, 40, 38, weight: FontWeight.w700);
  text(month, 40, 92, 22, color: const Color(0xFF6B6B66));
  text(name, 40, 150, 26, weight: FontWeight.w600);
  text('Ticket-Nr. $ticketNumber', 40, 190, 22);
  const bars = [3, 1, 4, 2, 1, 5, 2, 3, 1, 2, 4, 1, 3, 2, 5, 1, 2, 3, 1, 4, 2, 1, 3, 5, 1, 2, 4, 1, 3, 2, 2, 1, 4, 3, 1, 2, 5, 1, 3, 2, 4, 1, 2, 3, 1];
  var x = 40.0;
  for (final b in bars) {
    canvas.drawRect(Rect.fromLTWH(x, 250, b * 3.0, 110), Paint()..color = const Color(0xFF111111));
    x += b * 3.0 + 5;
  }
  text('Gültig im Nahverkehr · 2. Klasse · Vorführung', 40, 380, 18, color: const Color(0xFF6B6B66));
  final img = await recorder.endRecording().toImage(w.toInt(), h.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

// ---------------------------------------------------------------------------
// Signature
// ---------------------------------------------------------------------------

class SignatureController {
  _SignaturePadState? _state;
  bool get hasStrokes => _state?._strokes.isNotEmpty ?? false;
  Future<Uint8List?> toPng() => _state?._toPng() ?? Future.value(null);
}

/// A signature pad. Records strokes and calls [onSigned] after the first.
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key, required this.onSigned, this.height = 140, this.controller});
  final VoidCallback onSigned;
  final double height;
  final SignatureController? controller;

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  final List<List<Offset>> _strokes = [];
  final GlobalKey _boundary = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
  }

  Future<Uint8List?> _toPng() async {
    if (_strokes.isEmpty) return null;
    final rb = _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (rb == null) return null;
    final img = await rb.toImage(pixelRatio: 2);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onPanStart: (d) => setState(() => _strokes.add([d.localPosition])),
          onPanUpdate: (d) => setState(() => _strokes.last.add(d.localPosition)),
          onPanEnd: (_) {
            if (_strokes.isNotEmpty && _strokes.last.length > 1) widget.onSigned();
          },
          child: RepaintBoundary(
            key: _boundary,
            child: Container(
              height: widget.height,
              width: double.infinity,
              decoration: BoxDecoration(
                color: VColors.paperElevated,
                border: Border.all(color: VColors.rule),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Stack(
                children: [
                  Positioned(left: 14, right: 14, bottom: 30, child: Container(height: 1, color: VColors.rule)),
                  Positioned(left: 14, bottom: 10, child: Text('Unterschrift', style: VText.caption)),
                  if (_strokes.isEmpty) Center(child: Text('Hier unterschreiben', style: VText.body.copyWith(color: VColors.ink3))),
                  CustomPaint(size: Size.infinite, painter: _StrokePainter(_strokes)),
                ],
              ),
            ),
          ),
        ),
        if (_strokes.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(_strokes.clear),
              child: Text('Löschen', style: VText.caption),
            ),
          ),
      ],
    );
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.strokes);
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = VColors.ink
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.length < 2) {
        canvas.drawCircle(s.first, 1.2, p..style = PaintingStyle.fill);
        p.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final o in s.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter old) => true;
}

// ---------------------------------------------------------------------------
// Mail
// ---------------------------------------------------------------------------

/// A mail: header lines, body, attachments.
///
/// On a page of its own it is a box. Inside a Fahrkarte it is not — [boxed] off drops the border
/// and lets the header lines sit in the card's own column, because a surface never contains
/// another surface (app/STYLE.md, docs/33). A box inside a box gave Anträge three different
/// left edges on one screen.
class MailView extends StatelessWidget {
  const MailView({super.key, required this.mail, this.compact = false, this.bcc, this.boxed = true});
  final ApiMail mail;
  final bool compact;
  final bool boxed;

  /// Overrides the BCC header line (e.g. "… (dein Postfach)").
  final String? bcc;

  @override
  Widget build(BuildContext context) {
    final bccLine = bcc ?? mail.bcc;
    return Container(
      padding: boxed ? const EdgeInsets.all(VSpace.m) : EdgeInsets.zero,
      decoration: boxed
          ? BoxDecoration(
              color: VColors.paperElevated,
              border: Border.all(color: VColors.rule),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _hdr('Von', mail.from),
          _hdr('An', mail.to),
          if (bccLine != null && bccLine.isNotEmpty) _hdr('BCC', bccLine),
          _hdr('Betreff', mail.subject),
          _hdr('Datum', fmtStamp(mail.date)),
          const VGap.s(),
          const VRule(),
          const VGap.s(),
          Text(mail.body, style: VText.bodyS, maxLines: compact ? 6 : null, overflow: compact ? TextOverflow.ellipsis : null),
          if (mail.attachments.isNotEmpty) ...[
            const VGap.m(),
            for (final a in mail.attachments)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file, size: 16, color: VColors.ink2),
                    const SizedBox(width: 6),
                    Expanded(child: Text(a, style: VText.caption, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _hdr(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 58, child: Text(k, style: VText.caption)),
            Expanded(child: Text(v, style: VText.captionInk)),
          ],
        ),
      );
}

Future<void> showMailSheet(BuildContext context, ApiMail mail) {
  return showVSheet(
    context,
    expand: true,
    builder: (ctx) => Column(
      children: [
        VSheetHeader(title: mail.direction == ApiMailDirection.inbound ? 'Antwort der Bahn' : 'Dein Antrag', subtitle: mail.subject),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.s, VSpace.page, VSpace.xl),
            child: MailView(mail: mail),
          ),
        ),
      ],
    ),
  );
}

/// The body text of the outgoing claim mail, as the backend composes it.
String draftMailBody({required String accountHolder, required String claimantName, required List<ApiIncident> incidents}) {
  final single = incidents.length == 1 && incidents.first.ticket == TicketType.einzelfahrkarte;
  if (single) {
    final i = incidents.first;
    return 'Sehr geehrte Damen und Herren,\n\nanbei mein Antrag auf Entschädigung nach VO (EU) 2021/782 für die Fahrt mit ${i.line} am ${dmy(i.date)} (${i.from} – ${i.to}), Ankunft ${i.delayMinutes} Minuten verspätet.\n\nDie Entschädigung bitte ich auf das im Formular angegebene Konto zu überweisen (Kontoinhaber: $accountHolder).\n\nDiese E-Mail wurde über Verspätomat übermittelt, eine Ausfüll- und Weiterleitungshilfe. Antragsteller ist $claimantName.\n\nMit freundlichen Grüßen\n$claimantName';
  }
  return 'Sehr geehrte Damen und Herren,\n\nanbei mein gesammelter Antrag auf Entschädigung nach VO (EU) 2021/782 (wiederholte Verspätungen, Zeitfahrkarte). Die Einzelfälle sind im Formular unter Punkt 6 aufgeführt.\n\nKontoinhaber: $accountHolder\n\nDiese E-Mail wurde über Verspätomat übermittelt, eine Ausfüll- und Weiterleitungshilfe. Antragsteller ist $claimantName.\n\nMit freundlichen Grüßen\n$claimantName';
}

String dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// "2026-08" → "August 2026"
String monthLabel(String ym) {
  const months = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
  final parts = ym.split('-');
  if (parts.length != 2) return ym;
  final m = int.tryParse(parts[1]);
  if (m == null || m < 1 || m > 12) return ym;
  return '${months[m - 1]} ${parts[0]}';
}


/// "Nicht einreichen": ask which of the three reasons it is (docs/21 §4).
Future<void> showDiscardReasonSheet(BuildContext context, Future<void> Function(String reason) onPick) {
  return showVSheet(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.only(bottom: VSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VSheetHeader(title: 'Nicht einreichen', subtitle: 'Der Fall bleibt in deiner Historie, geht aber nicht an die Bahn.'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VGap.s(),
                for (final e in discardReasons.entries) ...[
                  VListRow(
                    title: e.value,
                    chevron: true,
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await onPick(e.key);
                    },
                  ),
                  const VRule.soft(),
                ],
                const VGap.m(),
                VGhostButton(label: 'Zurück', color: VColors.ink2, onTap: () => Navigator.of(ctx).pop()),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
