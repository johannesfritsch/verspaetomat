import 'dart:typed_data';
import 'dart:ui' as ui;

import 'dart:async';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart' show Mock, IncidentStatus, IncidentStatusX, TicketType, TicketTypeX;
import '../../router.dart';
import '../../repo/app_repository.dart';
import '../../repo/repo_scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../../widgets/server_down.dart';
import '../../widgets/ticket.dart' show NgoLogo;
import '../ride/ride_widgets.dart';

// The claims screens reach for monthLabel and ticketLabel through this file.
export '../../content/labels.dart';

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

/// Runs one repository call and renders the result. Call [refresh] via the returned controller to
/// reload.
///
/// While the call runs it shows [placeholder]: the screen's own header over skeleton cards, so the
/// page has its shape from the first frame and fills in rather than jumping from a caption in the
/// corner to a full layout (#17).
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder, this.controller, this.placeholder});
  final Future<T> Function(AppRepository repo) load;
  final Widget Function(BuildContext context, T data, VoidCallback refresh) builder;
  final LoaderController? controller;

  /// The page before its data. Without one: two skeleton cards in the page gutter.
  final WidgetBuilder? placeholder;

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
        // A screen that could not load because the Verspätomat is unreachable gets the whole page
        // (#28), not a line of red text with an exception in it: nothing about that failure is
        // this passenger's doing and there is nothing on the page to keep. Everything else — a
        // 404, a conflict, a refused precondition — is one request being wrong and stays the
        // ordinary inline error, where the rest of the screen is still worth seeing.
        if (snap.hasError) {
          if (isBackendUnreachable(snap.error)) return ServerDownScreen(onRetry: _reload);
          return LoadError(error: snap.error, onRetry: _reload);
        }
        if (!snap.hasData) return widget.placeholder?.call(context) ?? const PagePlaceholder();
        return widget.builder(context, snap.data as T, _reload);
      },
    );
  }
}

/// A page before its data, for screens that have not drawn their own skeleton: a card and a list,
/// in the page gutter, below the status bar.
class PagePlaceholder extends StatelessWidget {
  const PagePlaceholder({super.key, this.title});

  /// The title the screen will have, when it is known before the data.
  final String? title;

  @override
  Widget build(BuildContext context) {
    const body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [VSkeletonCard(), SizedBox(height: VSpace.md), VSkeletonList()],
    );
    if (title != null) return VScreen(title: title!, child: body);
    return const Scaffold(
      backgroundColor: VColors.paper,
      body: SafeArea(child: Padding(padding: EdgeInsets.all(VSpace.page), child: body)),
    );
  }
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
  const IncidentRow({
    super.key,
    required this.incident,
    this.onTap,
    this.leading,
    this.note,
    this.showStatus = false,
    this.chevron = false,
    this.divider = true,
  });
  final ApiIncident incident;
  final VoidCallback? onTap;
  final Widget? leading;

  /// A chevron at the far end, for when the row is a card of its own and its edge no longer
  /// says "there is more of me".
  final bool chevron;

  /// The hairline under the row. On in a list of rows inside one card; off when each case is its
  /// own card, where the gap between cards already separates them.
  final bool divider;

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
                          const SizedBox(width: VSpace.s),
                          LineBadge(i.line, cancelled: i.cancelled),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${i.from} → ${i.to}',
                        style: VText.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                    VDelayPill(i.delayMinutes),
                    const SizedBox(height: 4),
                    Text(fmtCents(i.shownCents), style: VText.amountS),
                    if (showStatus) ...[
                      const SizedBox(height: 4),
                      VChip(i.status.label, tone: toneFor(i.status)),
                    ],
                  ],
                ),
                if (chevron) ...[const SizedBox(width: VSpace.s), const VChevron()],
              ],
            ),
          ),
          if (divider) const VRule(),
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
                VKeyValue('Anspruch', fmtCents(i.amountCents), strong: i.confirmedCents == null),
                if (i.status == IncidentStatus.bestaetigt && i.confirmedCents != null) ...[
                  const VRule(),
                  VKeyValue('Bestätigt', fmtCents(i.confirmedCents!), strong: true),
                ],
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
// Zweck: one list, one explanation, used wherever an NGO is offered
// ---------------------------------------------------------------------------

/// Where the money lands: the name on the account and the IBAN, exactly as they go on the form.
class NgoAccountBox extends StatelessWidget {
  const NgoAccountBox({super.key, required this.ngo, this.showName = true, this.onCopyIban});
  final ApiNgo ngo;

  /// Off inside a sheet, where the header already carries the name.
  final bool showName;

  /// Puts a copy button on the IBAN row. The one number on this screen anybody would want to
  /// check against a bank statement.
  final VoidCallback? onCopyIban;

  @override
  Widget build(BuildContext context) {
    return VCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showName) ...[
            Row(
              children: [
                // The partner's own mark when it has sent one; otherwise a glyph. A logo is
                // managed data (docs/05), never an asset in the bundle.
                VIconBadge(
                  icon: Icons.volunteer_activism_outlined,
                  tone: VBadgeTone.green,
                  size: VControl.badge,
                  child: NgoLogo.decode(ngo.logo) == null
                      ? null
                      : NgoLogo(dataUri: ngo.logo, height: VControl.badge * 0.56),
                ),
                const SizedBox(width: VSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ngo.name, style: VText.title),
                      const SizedBox(height: 2),
                      Text(ngo.tagline, style: VText.caption),
                    ],
                  ),
                ),
              ],
            ),
            const VGap.s(),
            const VDivider(),
          ],
          VKeyValue('Kontoinhaber', ngo.accountHolder, strong: true),
          const VDivider(),
          VKeyValue(
            'IBAN',
            ngo.iban,
            valueStyle: VText.mono,
            trailing: onCopyIban == null
                ? null
                : VIconButton(icon: Icons.content_copy_outlined, color: VColors.ink2, onTap: onCopyIban!),
          ),
        ],
      ),
    );
  }
}

/// What one Zweck is, in a sheet: the story it tells and the account it collects on.
/// [onChoose] adds the button that takes it; without it the sheet only explains.
Future<void> showNgoSheet(BuildContext context, ApiNgo ngo, {Future<void> Function(String id)? onChoose}) {
  return showVSheet(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(VSpace.page, 0, VSpace.page, VSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VSheetHeader(title: ngo.name, subtitle: ngo.tagline),
          for (final p in ngo.story) ...[
            Text(p, style: VText.bodyS),
            const VGap.s(),
          ],
          const VGap.xs(),
          NgoAccountBox(ngo: ngo, showName: false),
          const VGap.s(),
          Text('Die Bahn überweist direkt dorthin. Wir sehen kein Geld, nur die Antwort.', style: VText.caption),
          const VGap.l(),
          if (onChoose != null) ...[
            VPrimaryButton(
              label: 'Diesen Zweck nehmen',
              icon: Icons.check,
              onTap: () {
                Navigator.of(ctx).pop();
                onChoose(ngo.id);
              },
            ),
            const VGap.xs(),
          ],
          VGhostButton(
            label: 'Alles über den Verein',
            icon: Icons.open_in_new,
            onTap: () {
              Navigator.of(ctx).pop();
              context.push('${Routes.zweck}?id=${Uri.encodeComponent(ngo.id)}');
            },
          ),
        ],
      ),
    ),
  );
}

/// The list of Zwecke to choose from. Each row takes the choice; the ⓘ explains it first.
class NgoPicker extends StatelessWidget {
  const NgoPicker({super.key, required this.ngos, required this.selectedId, required this.onChoose});
  final List<ApiNgo> ngos;
  final String? selectedId;
  final Future<void> Function(String id) onChoose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final n in ngos)
          Padding(
            padding: const EdgeInsets.only(bottom: VSpace.s),
            child: VChoiceCard(
              title: n.name,
              subtitle: n.tagline,
              selected: n.id == selectedId,
              onTap: () => onChoose(n.id),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => showNgoSheet(context, n, onChoose: onChoose),
                    icon: const Icon(Icons.info_outline, size: 20, color: VColors.ink2),
                    tooltip: 'Was ist ${n.name}?',
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  VSelectedMark(selected: n.id == selectedId),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Signature
// ---------------------------------------------------------------------------


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
  const MailView({super.key, required this.mail, this.compact = false, this.bcc, this.boxed = true, this.showAttachments = true});
  final ApiMail mail;
  final bool compact;
  final bool boxed;

  /// The paperclip list at the foot of the mail. Off where the screen lists the files itself, so
  /// the same attachments are not named twice.
  final bool showAttachments;

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
          if (showAttachments && mail.attachments.isNotEmpty) ...[
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
