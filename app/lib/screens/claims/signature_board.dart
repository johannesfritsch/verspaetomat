import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/tokens.dart';
import '../../widgets/kit.dart';

/// Signing, on a screen that is only for signing.
///
/// It used to be a 140 pt box inside the scrolling Unterschrift step, which fought the passenger
/// twice. A finger dragged across a pad inside a ScrollView is ambiguous — the gesture arena hands
/// some of those drags to the scroller and the line breaks — and a signature written in a strip
/// two centimetres tall is not the one anybody writes on paper.
///
/// So: the whole screen, turned sideways, because that is the shape a signature has. The page
/// underneath keeps its place; this is pushed over it and returns the ink.
///
/// **What it returns is ink and nothing else.** The old pad captured its own RepaintBoundary, so
/// the PNG carried the card, its shadow, the baseline rule and the words „Hier unterschreiben" —
/// and that whole picture was stamped onto the EU form sent to the railway. Here the strokes are
/// painted alone onto a transparent bitmap at the end, in their own coordinate space, so what
/// reaches the form is a signature on the paper it is printed on.
class SignatureBoard extends StatefulWidget {
  const SignatureBoard({super.key, required this.name});

  /// Printed under the line, the way a form prints the name beneath a signature.
  final String name;

  /// Opens the board and returns the signature as a transparent PNG, or null if nothing was
  /// confirmed. Restores the portrait lock on the way out whatever happens.
  static Future<Uint8List?> open(BuildContext context, {required String name}) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    try {
      if (!context.mounted) return null;
      return await Navigator.of(context, rootNavigator: true).push<Uint8List>(
        MaterialPageRoute(builder: (_) => SignatureBoard(name: name), fullscreenDialog: true),
      );
    } finally {
      // The rest of the app is portrait. This runs on every path out — confirmed, cancelled, or
      // swiped away — because a phone left stuck sideways is worse than no signature at all.
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  @override
  State<SignatureBoard> createState() => _SignatureBoardState();
}

class _SignatureBoardState extends State<SignatureBoard> {
  /// Strokes in the signing area's own coordinates, so the bitmap can be rebuilt without the
  /// screen furniture around them.
  final List<List<Offset>> _strokes = [];
  Size _area = Size.zero;

  bool get _hasInk => _strokes.any((s) => s.length > 1);

  /// Paint the strokes alone onto a transparent bitmap.
  ///
  /// Drawn from the recorded points rather than captured off the screen, which is the whole reason
  /// the form no longer carries a picture of a text field.
  Future<Uint8List?> _ink() async {
    if (!_hasInk || _area.isEmpty) return null;
    const scale = 3.0;
    // Cropped to the ink, with a little air. The form sets the signature at a fixed height (34 pt in
    // eu_form.typ), so the whole board area would shrink a signature written small in the middle
    // down to a scribble. Cropped, the ink itself fills the field.
    var box = Rect.zero;
    var first = true;
    for (final stroke in _strokes) {
      for (final p in stroke) {
        final r = Rect.fromCircle(center: p, radius: 2);
        box = first ? r : box.expandToInclude(r);
        first = false;
      }
    }
    box = box.inflate(8).intersect(Offset.zero & _area);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    canvas.translate(-box.left, -box.top);
    final paint = Paint()
      ..color = VColors.ink
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    for (final stroke in _strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
    final picture = recorder.endRecording();
    final img = await picture.toImage((box.width * scale).round().clamp(1, 8000), (box.height * scale).round().clamp(1, 8000));
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<void> _confirm() async {
    final png = await _ink();
    if (!mounted) return;
    Navigator.of(context).pop(png);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(VSpace.m),
          child: Column(
            children: [
              Row(
                children: [
                  VIconButton(icon: Icons.close, color: VColors.ink2, onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: VSpace.s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const VEyebrow('Unterschrift', tone: VEyebrowTone.ink),
                        const SizedBox(height: 2),
                        Text('Mit dem Finger, wie auf Papier.', style: VText.caption),
                      ],
                    ),
                  ),
                  if (_hasInk)
                    VGhostButton(
                      label: 'Nochmal',
                      icon: Icons.refresh,
                      color: VColors.ink2,
                      onTap: () => setState(_strokes.clear),
                    ),
                ],
              ),
              const VGap.s(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _area = Size(constraints.maxWidth, constraints.maxHeight);
                    return VCard(
                      padding: EdgeInsets.zero,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(VRadius.lg),
                        child: GestureDetector(
                          // No scroll view above this any more, so a drag is a drag.
                          onPanStart: (d) => setState(() => _strokes.add([d.localPosition])),
                          onPanUpdate: (d) => setState(() => _strokes.last.add(d.localPosition)),
                          child: Stack(
                            children: [
                              Positioned.fill(child: Container(color: VColors.paperElevated)),
                              // The line to sign on, and the name under it — a form's own layout.
                              Positioned(
                                left: VSpace.xl,
                                right: VSpace.xl,
                                bottom: 54,
                                child: Container(height: 1, color: VColors.hairlineStrong),
                              ),
                              Positioned(
                                left: VSpace.xl,
                                right: VSpace.xl,
                                bottom: 28,
                                child: Text(widget.name, style: VText.caption, textAlign: TextAlign.center),
                              ),
                              if (!_hasInk)
                                Center(child: Text('Hier unterschreiben', style: VText.body.copyWith(color: VColors.ink3))),
                              Positioned.fill(child: CustomPaint(painter: _InkPainter(_strokes))),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const VGap.s(),
              VPrimaryButton(
                label: 'Bestätigen',
                trailingIcon: Icons.check,
                onTap: _hasInk ? _confirm : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.strokes);
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = VColors.ink
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _InkPainter old) => true;
}
