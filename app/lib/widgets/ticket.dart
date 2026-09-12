import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'kit.dart';

/// The shareable Fahrkarte (docs/27 §1).
///
/// A punched ticket: perforated top and bottom, a hole where the conductor's Lochzange went
/// through, fare-card fields, and one number bigger than everything else. A punched ticket means
/// *used*; this one means the delay has been cashed in.
///
/// It is a plain widget with no state and no I/O, so it renders in the screenshot tour like any
/// screen and is captured for sharing through a `RepaintBoundary`.
enum TicketFace { antrag, angekommen, puenktlich, abzeichen, wir }

/// Everything printed on one ticket. Built by [TicketData.antrag] and friends so the screens
/// never assemble the fields by hand.
class TicketData {
  const TicketData({
    required this.face,
    required this.caption,
    required this.number,
    required this.numberLabel,
    this.fahrgast,
    this.strecke,
    this.date,
    this.fields = const [],
    this.ngoName,
    this.ngoLogo,
    this.badgeAsset,
    this.line,
  });

  final TicketFace face;

  /// Over the big number: `VERSPÄTUNG`, `GEWARTET`, `PÜNKTLICH`.
  final String caption;

  /// The hero. Null on the badge face, where the artwork takes its place.
  final int? number;
  final String numberLabel;

  /// The nickname from Einstellungen; null when the passenger switched it off (docs/27 §5).
  /// Never the legal name from Deine Angaben.
  final String? fahrgast;

  /// „Köln Hbf → Rheine"; null when switched off, which keeps the story and loses the routine.
  final String? strecke;
  final DateTime? date;

  /// The fields under the red rule: label and value, in the order they are printed.
  final List<(String, String)> fields;
  final String? ngoName;

  /// The NGO's own mark, as a data URI from the backend (docs/27 §5). Null renders the name alone.
  final String? ngoLogo;
  final String? badgeAsset;

  /// The sentence the passenger chose (docs/27 §1).
  final String? line;

  /// The claim, the moment it is sent: the whole bundle on one ticket.
  factory TicketData.antrag({
    required int minutes,
    required int cases,
    required String euro,
    required String ngoName,
    String? ngoLogo,
    String? fahrgast,
    DateTime? date,
    String? line,
    bool paid = false,
  }) =>
      TicketData(
        face: TicketFace.antrag,
        caption: 'VERSPÄTUNG',
        number: minutes,
        numberLabel: minutes == 1 ? 'MINUTE' : 'MINUTEN',
        fahrgast: fahrgast,
        date: date,
        fields: [
          (cases == 1 ? 'FALL' : 'FÄLLE', '$cases'),
          (paid ? 'BEZAHLT' : 'ZAHLT AN', ngoName),
          ('BETRAG', euro),
        ],
        ngoName: ngoName,
        ngoLogo: ngoLogo,
        line: line,
      );

  /// One arrival. The delay is the hero; the money only appears if there is any.
  factory TicketData.angekommen({
    required int minutes,
    required int points,
    String? strecke,
    String? fahrgast,
    DateTime? date,
    String? line,
  }) =>
      TicketData(
        face: TicketFace.angekommen,
        caption: 'VERSPÄTUNG',
        number: minutes,
        numberLabel: minutes == 1 ? 'MINUTE' : 'MINUTEN',
        fahrgast: fahrgast,
        strecke: strecke,
        date: date,
        fields: [('PUNKTE', '+$points')],
        line: line,
      );

  /// The rare one. Ink, never red — nothing here is a complaint.
  factory TicketData.puenktlich({
    String? strecke,
    String? fahrgast,
    DateTime? date,
    String? line,
  }) =>
      TicketData(
        face: TicketFace.puenktlich,
        caption: 'PÜNKTLICH',
        number: 0,
        numberLabel: 'MINUTEN',
        fahrgast: fahrgast,
        strecke: strecke,
        date: date,
        line: line,
      );

  /// A badge. The artwork replaces the number, and the rule that earned it does the talking.
  factory TicketData.abzeichen({
    required String name,
    required String rule,
    String? asset,
    String? fahrgast,
    DateTime? date,
    String? line,
  }) =>
      TicketData(
        face: TicketFace.abzeichen,
        caption: 'FREIGESCHALTET',
        number: null,
        numberLabel: name,
        fahrgast: fahrgast,
        date: date,
        fields: [('WOFÜR', rule)],
        badgeAsset: asset,
        line: line,
      );

  /// The collective number (docs/27 §2). Nobody's own ego is in this one, which is exactly why
  /// it gets shared.
  factory TicketData.wir({required int minutes, required int people, String? line}) => TicketData(
        face: TicketFace.wir,
        caption: 'ZUSAMMEN GEWARTET',
        number: minutes,
        numberLabel: 'MINUTEN',
        fields: [('FAHRGÄSTE', '$people')],
        line: line,
      );

  bool get isPunctual => face == TicketFace.puenktlich;
}

/// The ticket itself, at a fixed logical size. Captured at `pixelRatio: 3` this is 1080 × 1350.
class Ticket extends StatelessWidget {
  const Ticket({super.key, required this.data, this.width = 360});
  final TicketData data;
  final double width;

  static const aspect = 4 / 5;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width / aspect,
      child: CustomPaint(
        painter: _PerforationPainter(),
        child: Padding(
          padding: EdgeInsets.fromLTRB(width * 0.075, width * 0.09, width * 0.075, width * 0.09),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _head(),
              SizedBox(height: width * 0.05),
              ..._fieldRows([
                if (data.fahrgast != null) ('FAHRGAST', data.fahrgast!),
                if (data.strecke != null) ('STRECKE', data.strecke!),
                if (data.date != null) ('AM', _date(data.date!)),
              ]),
              SizedBox(height: width * 0.035),
              Container(height: 2, color: VColors.red),
              Expanded(child: _hero()),
              Container(height: 1, color: VColors.rule),
              SizedBox(height: width * 0.03),
              ..._fieldRows(data.fields),
              if (data.ngoLogo != null)
                Padding(
                  padding: EdgeInsets.only(left: width * 0.34, top: width * 0.01),
                  child: NgoLogo(dataUri: data.ngoLogo, height: width * 0.075),
                ),
              if (data.line != null) ...[
                SizedBox(height: width * 0.035),
                Text(
                  '„${data.line!}"',
                  style: VText.caption.copyWith(color: VColors.ink, height: 1.35),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _head() => Row(
        children: [
          Expanded(child: Text('VERSPÄTOMAT', style: VText.eyebrow.copyWith(color: VColors.ink))),
          Text(
            switch (data.face) {
              TicketFace.antrag => 'FAHRGASTRECHTE',
              TicketFace.abzeichen => 'ABZEICHEN',
              TicketFace.wir => 'WIR ZUSAMMEN',
              _ => 'FAHRKARTE',
            },
            style: VText.eyebrow,
          ),
        ],
      );

  List<Widget> _fieldRows(List<(String, String)> rows) => [
        for (final (label, value) in rows)
          Padding(
            padding: EdgeInsets.only(bottom: width * 0.012),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: width * 0.34,
                  child: Text(label, style: VText.eyebrow, maxLines: 1, overflow: TextOverflow.visible, softWrap: false),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: VText.bodySStrong,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ];

  /// The big block. The number is the design: at thumbnail size it is the only legible thing.
  Widget _hero() {
    final badge = data.badgeAsset;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: width * 0.03),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(data.caption, style: VText.eyebrow),
                if (badge != null)
                  Padding(
                    padding: EdgeInsets.only(top: width * 0.02),
                    child: Row(
                      children: [
                        Image.asset(badge, width: width * 0.22, height: width * 0.22, fit: BoxFit.contain),
                        SizedBox(width: width * 0.04),
                        Expanded(
                          child: Text(data.numberLabel, style: VText.h2, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  )
                else if (data.number != null) ...[
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${data.number}',
                      style: VText.display.copyWith(
                        fontSize: width * 0.34,
                        height: 0.95,
                        color: data.isPunctual ? VColors.ink : VColors.red,
                      ),
                    ),
                  ),
                  Text(data.numberLabel, style: VText.eyebrow),
                ] else
                  Padding(
                    padding: EdgeInsets.only(top: width * 0.02),
                    child: Text(data.numberLabel, style: VText.h2, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
          _punch(),
        ],
      ),
    );
  }

  /// The hole the Lochzange left. The confetti in the app is what came out of it (docs/27 §4).
  Widget _punch() => Container(
        width: width * 0.09,
        height: width * 0.09,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: VColors.ink.withValues(alpha: 0.10),
          border: Border.all(color: VColors.ink2, width: 2),
        ),
      );

  static String _date(DateTime d) {
    const days = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    const months = [
      'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
    ];
    return '${days[d.weekday - 1]}, ${d.day}. ${months[d.month - 1]} ${d.year}';
  }
}

/// The torn edges, top and bottom. A ticket is recognisable by its silhouette before anything
/// on it can be read, which is the whole point at thumbnail size.
///
/// The card is captured as a standalone PNG, so the bites cannot be cut out of a background
/// the way [VTicketBorder] does it in the app — they are painted in paper grey on white
/// instead, which is exactly how the website's hero card does it (`.fahrkarte::before`).
/// Same radius, same pitch, same two hairlines down the sides.
class _PerforationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = VColors.paperElevated);

    final bite = Paint()..color = VColors.paper;
    const r = VTicketBorder.radius;
    const pitch = VTicketBorder.pitch;
    final count = (size.width / pitch).floor();
    final start = (size.width - count * pitch) / 2 + pitch / 2;
    for (var i = 0; i < count; i++) {
      final x = start + i * pitch;
      canvas.drawCircle(Offset(x, 0), r, bite);
      canvas.drawCircle(Offset(x, size.height), r, bite);
    }

    final side = Paint()
      ..color = VColors.ruleSoft
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(0.5, 0), Offset(0.5, size.height), side);
    canvas.drawLine(Offset(size.width - 0.5, 0), Offset(size.width - 0.5, size.height), side);
  }

  @override
  bool shouldRepaint(covariant _PerforationPainter old) => false;
}

/// An NGO logo delivered as a `data:image/…;base64,…` URI (docs/27 §5). Null or unreadable
/// renders nothing, and the name beside it carries the card on its own.
class NgoLogo extends StatelessWidget {
  const NgoLogo({super.key, required this.dataUri, this.height = 22});
  final String? dataUri;
  final double height;

  static Uint8List? decode(String? uri) {
    if (uri == null) return null;
    final i = uri.indexOf('base64,');
    if (i < 0) return null;
    try {
      return base64Decode(uri.substring(i + 7));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = decode(dataUri);
    if (bytes == null) return const SizedBox.shrink();
    return Image.memory(bytes, height: height, fit: BoxFit.contain, filterQuality: FilterQuality.medium);
  }
}
