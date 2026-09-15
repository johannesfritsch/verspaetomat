import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/theme/tokens.dart';
import 'package:verspaetomat/widgets/kit.dart';

/// VGhostButton is a block control: it fills the width it is given, which is right in a Column,
/// where it is the quiet second action under a VPrimaryButton. It used to *demand* that width
/// with `width: double.infinity`, and in a Row's non-flex slot there is nothing finite to clamp
/// against — so the button came back infinitely wide, every flex sibling was laid out at zero,
/// and its own centred label was painted off the screen.
///
/// On the Antrag flow's Zweck step that turned „Nur für diesen Antrag" into a column of single
/// letters and made „Schließen" vanish. The call site now uses a VIconButton, and the button
/// itself can no longer arm the trap for the next caller.
void main() {
  const label = 'Nur für diesen Antrag';

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 360, child: Align(alignment: Alignment.topLeft, child: child)),
        ),
      ),
    );
  }

  testWidgets('a bare ghost button in a row leaves its flex sibling room', (tester) async {
    await pump(
      tester,
      Row(
        children: [
          Expanded(child: Text(label, style: VText.eyebrow)),
          VGhostButton(label: 'Schließen', onTap: () {}),
        ],
      ),
    );

    // The bug laid the label out at width 0, so it broke after every letter and stood ~380 tall.
    final text = tester.getSize(find.text(label));
    expect(text.width, greaterThan(120), reason: 'the label was starved to a column of letters');
    expect(text.height, lessThan(60), reason: 'one or two lines, not one line per letter');

    // And it centred the button's label at infinity, which is to say nowhere on the screen.
    final button = tester.getRect(find.text('Schließen'));
    expect(button.left, greaterThanOrEqualTo(0));
    expect(button.right, lessThanOrEqualTo(360));
  });

  testWidgets('in a column it still fills the width and centres its label', (tester) async {
    await pump(tester, const Column(children: [VGhostButton(label: 'Zurück')]));

    // The common case must not move: full width, label on the centre line, 52 tall.
    expect(tester.getSize(find.byType(VGhostButton)), const Size(360, 52));
    expect(tester.getCenter(find.text('Zurück')).dx, closeTo(180, 1));
  });

  testWidgets('inside an Expanded it still fills its share', (tester) async {
    await pump(
      tester,
      const Row(
        children: [
          Expanded(child: VGhostButton(label: 'Links')),
          Expanded(child: VGhostButton(label: 'Rechts')),
        ],
      ),
    );

    expect(tester.getCenter(find.text('Links')).dx, closeTo(90, 1));
    expect(tester.getCenter(find.text('Rechts')).dx, closeTo(270, 1));
  });

  testWidgets('the Zweck header keeps the label and the close glyph on one line', (tester) async {
    // The shape antrag_screen.dart builds when the "Anderen Zweck wählen" list is open.
    await pump(
      tester,
      Row(
        children: [
          const Expanded(child: VEyebrow(label, tone: VEyebrowTone.ink)),
          VIconButton(icon: Icons.close, color: VColors.ink2, onTap: () {}),
        ],
      ),
    );

    // VEyebrow uppercases, which is what every other section label in the app does.
    final eyebrow = tester.getRect(find.text(label.toUpperCase()));
    expect(eyebrow.height, lessThan(40), reason: 'one line');

    // The glyph carries its own 44 pt touch box and sets the height of the row.
    expect(tester.getSize(find.byType(VIconButton)), const Size(44, 44));
    expect(tester.getRect(find.byType(VIconButton)).right, 360);
    expect(eyebrow.right, lessThanOrEqualTo(316));
  });
}
