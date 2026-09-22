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

/// The railway said yes (#49): the one moment in the app that is good news all the way through,
/// so it gets the punch's confetti and the card that can finally say „zahlt".
Future<void> showConfirmedSheet(BuildContext context, ApiShareConfirmed c) {
  return showVSheet<void>(
    context,
    builder: (ctx) => _ConfirmedSheet(claim: c, outer: context),
  );
}

class _ConfirmedSheet extends StatefulWidget {
  const _ConfirmedSheet({required this.claim, required this.outer});
  final ApiShareConfirmed claim;
  final BuildContext outer;

  @override
  State<_ConfirmedSheet> createState() => _ConfirmedSheetState();
}

class _ConfirmedSheetState extends State<_ConfirmedSheet> {
  bool _konfetti = true;

  @override
  Widget build(BuildContext context) {
    final c = widget.claim;
    return Stack(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VSheetHeader(eyebrow: 'Antwort der Bahn', title: 'Bestätigt.'),
            Padding(
              padding: const EdgeInsets.fromLTRB(VSpace.sheet, 0, VSpace.sheet, VSpace.l),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${fmtCents(c.cents)} gehen an ${c.ngo}.', style: VText.h2),
                  const VGap.s(),
                  Text(
                    '${c.cases == 1 ? 'Ein Fall' : '${c.cases} Fälle'}, ${ShareLines.duration(c.minutes)} gewartet. Das Geld zahlt die Bahn direkt an den Verein.',
                    style: VText.body.copyWith(color: VColors.ink2),
                  ),
                  const VGap.l(),
                  VPrimaryButton(
                    label: 'Teilen',
                    icon: Icons.ios_share,
                    onTap: () {
                      Navigator.of(context).pop();
                      if (widget.outer.mounted) shareConfirmed(widget.outer, c);
                    },
                  ),
                  const VGap.xs(),
                  VGhostButton(label: 'Schließen', onTap: () => Navigator.of(context).pop()),
                ],
              ),
            ),
          ],
        ),
        if (_konfetti)
          Positioned.fill(
            child: IgnorePointer(child: Konfetti(onDone: () => setState(() => _konfetti = false))),
          ),
      ],
    );
  }
}
