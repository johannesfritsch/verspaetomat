import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/models.dart';
import '../../content/labels.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../../widgets/konfetti.dart';
import '../../widgets/ticket.dart';
import '../claims/claims_widgets.dart' show fmtCents;
import 'share_lines.dart';
import 'share_sheet.dart';

/// The share cards of issue #49, and the moments they turn up by themselves.
///
/// Every card is one passenger's own fact from `GET /v1/me/share`, drawn on the phone. Each
/// moment turns up once: what has been shown is remembered on this device, so a record, a month
/// or a confirmed claim is offered one time and then lives on Ich, where it can be shared again.
class ShareMoments {
  ShareMoments(this.prefs);
  final SharedPreferences prefs;

  static const _celebratedKey = 'share.celebrated_claims';
  static const _recordKey = 'share.record_ride';
  static const _monthKey = 'share.month_seen';

  /// The first confirmed claim this device has not celebrated yet.
  ApiShareConfirmed? pendingConfirmed(ApiShareFacts f) {
    final seen = prefs.getStringList(_celebratedKey) ?? const [];
    return f.confirmedClaims.where((c) => !seen.contains(c.claimId)).firstOrNull;
  }

  Future<void> markConfirmed(String claimId) async {
    final seen = prefs.getStringList(_celebratedKey) ?? const [];
    await prefs.setStringList(_celebratedKey, [...seen.take(49), claimId]);
  }

  /// A record is new when a different ride holds it than the last time this device looked. The
  /// very first look only takes note: a first delayed ride beats nothing, and every install would
  /// open on a „Rekord" that is merely the first entry.
  bool recordIsNew(ApiShareFacts f) {
    final r = f.record;
    if (r == null) return false;
    final known = prefs.getString(_recordKey);
    if (known == null) {
      // Not awaited: the in-memory cache answers the next call at once; a lost disk write costs
      // at most one record card after a cold start.
      unawaited(prefs.setString(_recordKey, r.rideId));
      return false;
    }
    return known != r.rideId;
  }

  Future<void> markRecord(ApiShareFacts f) async {
    final r = f.record;
    if (r != null) await prefs.setString(_recordKey, r.rideId);
  }

  /// Last month's card on Home: in the first week of the month, once, and only if something
  /// was late in it (the server sends no month otherwise).
  bool monthDue(ApiShareFacts f, {DateTime? now}) {
    final m = f.lastMonth;
    if (m == null) return false;
    if ((now ?? DateTime.now()).day > 7) return false;
    return prefs.getString(_monthKey) != m.month;
  }

  Future<void> markMonth(ApiShareFacts f) async {
    final m = f.lastMonth;
    if (m != null) await prefs.setString(_monthKey, m.month);
  }
}

/// „September" from "2026-09".
String monthName(String ym) => monthLabel(ym).split(' ').first;

Future<void> shareMine(BuildContext context, ApiShareFacts f, {int? together}) => showShareSheet(
  context,
  date: DateTime.now(),
  lines: ShareLines.mine(minutes: f.minutesTotal, together: together),
  build: ({fahrgast, strecke, date, line}) => TicketData.mine(
    minutes: f.minutesTotal,
    rides: f.ridesTotal,
    confirmedEuro: f.confirmedCents > 0 ? fmtCents(f.confirmedCents) : null,
    fahrgast: fahrgast,
    date: date,
    line: line,
  ),
);

Future<void> shareRecord(BuildContext context, ApiShareRecord r) => showShareSheet(
  context,
  date: r.at,
  lines: ShareLines.rekord(minutes: r.minutes, to: r.to),
  build: ({fahrgast, strecke, date, line}) => TicketData.rekord(minutes: r.minutes, train: r.line, to: r.to, date: date, fahrgast: fahrgast, line: line),
);

Future<void> shareLine(BuildContext context, ApiShareLine l) => showShareSheet(
  context,
  lines: ShareLines.linie(train: l.line, minutes: l.minutes, rides: l.rides, month: monthName(l.month)),
  build: ({fahrgast, strecke, date, line}) =>
      TicketData.linie(train: l.line, minutes: l.minutes, rides: l.rides, month: monthName(l.month), fahrgast: fahrgast, line: line),
);

Future<void> shareMonth(BuildContext context, ApiShareMonth m) => showShareSheet(
  context,
  lines: ShareLines.monat(month: monthName(m.month), minutes: m.minutes, rides: m.rides, worst: m.worstMinutes, confirmedCents: m.confirmedCents),
  build: ({fahrgast, strecke, date, line}) => TicketData.monat(
    month: monthLabel(m.month),
    minutes: m.minutes,
    rides: m.rides,
    worst: m.worstMinutes,
    confirmedEuro: m.confirmedCents > 0 ? fmtCents(m.confirmedCents) : null,
    fahrgast: fahrgast,
    line: line,
  ),
);

Future<void> shareConfirmed(BuildContext context, ApiShareConfirmed c) => showShareSheet(
  context,
  date: c.confirmedAt ?? DateTime.now(),
  lines: ShareLines.bestaetigt(minutes: c.minutes, cents: c.cents, ngo: c.ngo),
  build: ({fahrgast, strecke, date, line}) =>
      TicketData.antrag(minutes: c.minutes, cases: c.cases, euro: fmtCents(c.cents), ngoName: c.ngo, paid: true, fahrgast: fahrgast, date: date, line: line),
);

/// The railway said yes (#49, drawn in #53): the one moment in the app that is good news all the
/// way through, so it gets the punch's confetti and the card that can finally say „zahlt".
Future<void> showConfirmedSheet(BuildContext context, ApiShareConfirmed c) => _showMomentSheet(
      context,
      picture: const _Picture.asset('assets/sheet/bestaetigt.webp'),
      eyebrow: 'Antwort der Bahn',
      title: 'Bestätigt.',
      red: fmtCents(c.cents),
      rest: ' gehen an ${c.ngo}.',
      body: '${c.cases == 1 ? 'Ein Fall' : '${c.cases} Fälle'} · ${ShareLines.duration(c.minutes)} gewartet. Die Bahn zahlt direkt an den Verein.',
      facts: [
        (Icons.receipt_long_outlined, '${c.cases}', c.cases == 1 ? 'Fall' : 'Fälle'),
        (Icons.schedule, shortDuration(c.minutes), 'gewartet'),
        (Icons.favorite, null, 'Direkt an den Verein'),
      ],
      konfetti: true,
      onShare: () => shareConfirmed(context, c),
    );

/// A new longest delay (#49), in the sheet #53 drew for the confirmation.
Future<void> showRecordSheet(BuildContext context, ApiShareRecord r) => _showMomentSheet(
      context,
      picture: const _Picture.scene(VSheetSceneArt.clock),
      eyebrow: 'Neuer Rekord',
      title: 'So lange noch nie.',
      red: '${r.minutes} Minuten',
      rest: r.to == null ? ' zu spät.' : ' zu spät nach ${r.to}.',
      body: 'Deine längste Verspätung, seit du mit Verspätomat fährst.',
      facts: [
        (Icons.train_outlined, r.line, r.to == null ? 'Zug' : 'nach ${r.to}'),
        (Icons.schedule, shortDuration(r.minutes), 'Verspätung'),
        if (r.at != null) (Icons.event_outlined, _day(r.at!.toLocal()), 'am'),
      ],
      onShare: () => shareRecord(context, r),
    );

/// Last month, once it is over (#49), in the same sheet.
Future<void> showMonthSheet(BuildContext context, ApiShareMonth m) => _showMomentSheet(
      context,
      picture: const _Picture.scene(VSheetSceneArt.platform),
      eyebrow: 'Rückblick',
      title: 'Dein ${monthName(m.month)}.',
      red: '${m.minutes} Minuten',
      rest: ' gewartet.',
      body: m.confirmedCents > 0
          ? '${m.rides == 1 ? 'Eine Fahrt' : '${m.rides} Fahrten'} im ${monthName(m.month)}. Bestätigt: ${fmtCents(m.confirmedCents)} für den Verein.'
          : '${m.rides == 1 ? 'Eine Fahrt' : '${m.rides} Fahrten'} im ${monthName(m.month)}.',
      facts: [
        (Icons.train_outlined, '${m.rides}', m.rides == 1 ? 'Fahrt' : 'Fahrten'),
        (Icons.schedule, shortDuration(m.minutes), 'gewartet'),
        (Icons.timer_outlined, '${m.worstMinutes} Min', 'die längste'),
      ],
      onShare: () => shareMonth(context, m),
    );

/// „4 Std 41 Min", „45 Min", „2 Std": the short form for a fact strip.
String shortDuration(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m Min';
  return m == 0 ? '$h Std' : '$h Std $m Min';
}

String _day(DateTime d) {
  const m = ['Jan.', 'Feb.', 'März', 'Apr.', 'Mai', 'Juni', 'Juli', 'Aug.', 'Sep.', 'Okt.', 'Nov.', 'Dez.'];
  return '${d.day}. ${m[d.month - 1]}';
}

/// What stands at the top of a moment sheet: a drawing of its own, or one of the sheet scenes.
class _Picture {
  const _Picture.asset(String this.asset) : scene = null;
  const _Picture.scene(VSheetSceneArt this.scene) : asset = null;
  final String? asset;
  final VSheetSceneArt? scene;
}

/// The moment sheet (#53): a picture, the eyebrow, a big title, one sentence with its figure in
/// red, a line of detail, three facts on a strip, and the two answers. Teilen opens the preview
/// with the card; Schließen is grey, because leaving is not the thing this sheet is for.
Future<void> _showMomentSheet(
  BuildContext context, {
  required _Picture picture,
  required String eyebrow,
  required String title,
  required String red,
  required String rest,
  required String body,
  required List<(IconData, String?, String)> facts,
  required VoidCallback onShare,
  bool konfetti = false,
}) {
  return showVSheet<void>(
    context,
    builder: (ctx) => _MomentSheet(
      picture: picture,
      eyebrow: eyebrow,
      title: title,
      red: red,
      rest: rest,
      body: body,
      facts: facts,
      konfetti: konfetti,
      onShare: () {
        Navigator.of(ctx).pop();
        if (context.mounted) onShare();
      },
    ),
  );
}

class _MomentSheet extends StatefulWidget {
  const _MomentSheet({
    required this.picture,
    required this.eyebrow,
    required this.title,
    required this.red,
    required this.rest,
    required this.body,
    required this.facts,
    required this.konfetti,
    required this.onShare,
  });
  final _Picture picture;
  final String eyebrow;
  final String title;
  final String red;
  final String rest;
  final String body;
  final List<(IconData, String?, String)> facts;
  final bool konfetti;
  final VoidCallback onShare;

  @override
  State<_MomentSheet> createState() => _MomentSheetState();
}

class _MomentSheetState extends State<_MomentSheet> {
  late bool _konfetti = widget.konfetti;

  Widget _picture() {
    final asset = widget.picture.asset;
    if (asset == null) {
      return SizedBox(height: 190, child: ClipRect(child: VSheetScene(art: widget.picture.scene!, height: 190)));
    }
    // The drawing is on white; multiplied with the sheet's paper it takes the paper's tone, and
    // its lower edge fades into the text instead of ending on a line.
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.black, Colors.black, Colors.transparent],
        stops: [0, 0.82, 1],
      ).createShader(rect),
      child: Image.asset(asset, fit: BoxFit.fitWidth, width: double.infinity, color: VColors.paper, colorBlendMode: BlendMode.multiply),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _picture(),
                // The grabber, over the picture: the sheet still closes by a pull from the top.
                const Positioned(left: 0, right: 0, top: 0, child: VSheetHeader()),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(VSpace.sheet, VSpace.s, VSpace.sheet, VSpace.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.eyebrow.toUpperCase(), style: VText.eyebrow),
                  const VGap.xs(),
                  Text(widget.title, style: VText.h1),
                  const VGap.s(),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: widget.red, style: const TextStyle(color: VColors.red)),
                      TextSpan(text: widget.rest),
                    ]),
                    style: VText.h2,
                  ),
                  const VGap.s(),
                  Text(widget.body, style: VText.body.copyWith(color: VColors.ink2)),
                  const VGap.m(),
                  _FactStrip(facts: widget.facts),
                  const VGap.l(),
                  VPrimaryButton(label: 'Teilen', icon: Icons.ios_share, onTap: widget.onShare),
                  const VGap.s(),
                  VTintButton(label: 'Schließen', tone: VTintTone.neutral, onTap: () => Navigator.of(context).pop()),
                ],
              ),
            ),
          ],
        ),
        if (_konfetti) Positioned.fill(child: IgnorePointer(child: Konfetti(onDone: () => setState(() => _konfetti = false)))),
      ],
    );
  }
}

/// Three facts side by side, each a red-tinted mark and two short lines, rules between them.
class _FactStrip extends StatelessWidget {
  const _FactStrip({required this.facts});
  final List<(IconData, String?, String)> facts;

  @override
  Widget build(BuildContext context) {
    return VCard(
      tone: VCardTone.sunken,
      padding: const EdgeInsets.symmetric(horizontal: VSpace.s, vertical: VSpace.md),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < facts.length; i++) ...[
              if (i > 0) const VerticalDivider(width: VSpace.m, thickness: 1, color: VColors.rule),
              // Mark above the two lines: the mockup sets them side by side on a wider phone, and at
              // a third of this width that cut „4 Std 41 Min" to „4 Std 4…".
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VIconBadge(icon: facts[i].$1, tone: VBadgeTone.red, size: VControl.badgeSmall),
                    const SizedBox(height: VSpace.s),
                    if (facts[i].$2 != null)
                      FittedBox(fit: BoxFit.scaleDown, child: Text(facts[i].$2!, style: VText.bodySStrong, maxLines: 1)),
                    Text(facts[i].$3, style: VText.caption, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
