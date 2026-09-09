import 'package:flutter/material.dart';

import '../../mock/mock_data.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';

VTone toneFor(IncidentStatus s) => switch (s) {
      IncidentStatus.bestaetigt => VTone.green,
      IncidentStatus.abgelehnt => VTone.red,
      IncidentStatus.verfallen => VTone.red,
      IncidentStatus.eingereicht => VTone.ink,
      _ => VTone.neutral,
    };

/// One incident in the ledger: date, line, route on the left; delay,
/// amount and status on the right. Hairline below.
class IncidentRow extends StatelessWidget {
  const IncidentRow({super.key, required this.incident, this.onTap, this.leading});
  final Incident incident;
  final VoidCallback? onTap;
  final Widget? leading;

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
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    VDelay(i.delayMinutes, size: VDelaySize.small),
                    const SizedBox(height: 2),
                    Text(fmtEuro(i.amount), style: VText.captionInk.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    const SizedBox(height: 4),
                    VChip(i.status.label, tone: toneFor(i.status)),
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

/// The evidence sheet behind an incident.
Future<void> showEvidenceSheet(BuildContext context, Incident i) {
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
                VKeyValue('Ankunft laut Fahrplan', i.plannedArrival != null ? fmtTime(i.plannedArrival!) : '–'),
                const VRule(),
                VKeyValue('Tatsächliche Ankunft', i.actualArrival != null ? fmtTime(i.actualArrival!) : '–', strong: true),
                const VRule(),
                VKeyValue('Betreiber', i.operator),
                const VRule(),
                VKeyValue('Zuständige Stelle', i.desk),
                const VRule(),
                VKeyValue('Quelle', i.selfEntered ? 'Selbst eingetragen' : 'Live-Daten Transitous'),
                const VRule(),
                VKeyValue('Erfasst am', '${Mock.shortDate(i.date)} ${i.actualArrival != null ? fmtTime(i.actualArrival!) : ''}'),
                const VRule(),
                VKeyValue('Ticket', i.ticket.label),
                const VRule(),
                VKeyValue('Anspruch', fmtEuro(i.amount), strong: true),
                if (i.fare != null) ...[
                  const VRule(),
                  VKeyValue('Fahrpreis', fmtEuro(i.fare!)),
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
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// A mocked Deutschlandticket screenshot. No image assets.
class MockTicket extends StatelessWidget {
  const MockTicket({super.key, this.month = 'September 2026'});
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
          Text(Mock.userName, style: VText.bodyStrong),
          Text('Ticket-Nr. ${Mock.ticketNumber}', style: VText.mono.copyWith(color: VColors.ink2)),
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

/// A signature pad. Records strokes and calls [onSigned] after the first.
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key, required this.onSigned, this.height = 140});
  final VoidCallback onSigned;
  final double height;

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  final List<List<Offset>> _strokes = [];

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
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 30,
                  child: Container(height: 1, color: VColors.rule),
                ),
                Positioned(
                  left: 14,
                  bottom: 10,
                  child: Text('Unterschrift', style: VText.caption),
                ),
                if (_strokes.isEmpty)
                  Center(child: Text('Hier unterschreiben', style: VText.body.copyWith(color: VColors.ink3))),
                CustomPaint(size: Size.infinite, painter: _StrokePainter(_strokes)),
              ],
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

/// A mail rendered as a card: header lines, body, attachments.
class MailView extends StatelessWidget {
  const MailView({super.key, required this.mail, this.compact = false});
  final RailMail mail;
  final bool compact;

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
          _hdr('Von', mail.from),
          _hdr('An', mail.to),
          _hdr('Betreff', mail.subject),
          _hdr('Datum', '${Mock.shortDate(mail.date)} ${fmtTime(TimeOfDay.fromDateTime(mail.date))}'),
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

Future<void> showMailSheet(BuildContext context, RailMail mail) {
  return showVSheet(
    context,
    expand: true,
    builder: (ctx) => Column(
      children: [
        VSheetHeader(title: mail.direction == MailDirection.inbound ? 'Antwort der Bahn' : 'Dein Antrag', subtitle: mail.subject),
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

/// The body text of the outgoing claim mail, mirrored from DemoState.sendBundle.
String draftMailBody(DemoState state) {
  final ngo = Mock.ngoById(state.draftNgoId ?? state.ngoId);
  final incidents = state.incidents.where((i) => state.draftIncidentIds.contains(i.id)).toList();
  final single = incidents.length == 1 && incidents.first.ticket == TicketType.einzelfahrkarte;
  if (single) {
    final i = incidents.first;
    return 'Sehr geehrte Damen und Herren,\n\nanbei mein Antrag auf Entschädigung nach VO (EU) 2021/782 für die Fahrt mit ${i.line} am ${_dmy(i.date)} (${i.from} – ${i.to}), Ankunft ${i.delayMinutes} Minuten verspätet.\n\nDie Entschädigung bitte ich auf das im Formular angegebene Konto zu überweisen (Kontoinhaber: ${ngo.accountHolder}).\n\nDiese E-Mail wurde über Verspätomat übermittelt, eine Ausfüll- und Weiterleitungshilfe. Antragsteller ist ${Mock.userName}.\n\nMit freundlichen Grüßen\n${Mock.userName}';
  }
  return 'Sehr geehrte Damen und Herren,\n\nanbei mein gesammelter Antrag auf Entschädigung nach VO (EU) 2021/782 (wiederholte Verspätungen, Zeitfahrkarte Deutschlandticket). Die Einzelfälle sind im Formular unter Punkt 6 aufgeführt.\n\nKontoinhaber: ${ngo.accountHolder}\n\nDiese E-Mail wurde über Verspätomat übermittelt, eine Ausfüll- und Weiterleitungshilfe. Antragsteller ist ${Mock.userName}.\n\nMit freundlichen Grüßen\n${Mock.userName}';
}

String _dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String deskMailAddress(String? desk) {
  final a = Mock.deskAddresses[desk ?? ''];
  if (a == null) return '–';
  final lines = a.split('\n');
  return lines.length > 1 ? lines[1].replaceAll(' (Beispiel)', '') : lines.first;
}

String deskPostalAddress(String? desk) {
  final a = Mock.deskAddresses[desk ?? ''];
  if (a == null) return 'Adresse unbekannt';
  return a.split('\n').first;
}
