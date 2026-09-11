import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/theme/tokens.dart';
import 'package:verspaetomat/widgets/kit.dart';

/// The Home screen showed „pünktlich" at 56 px next to the station name, took the whole row with
/// it, and left the name one letter per line („Aulendo / rf"). The figure slot is for figures.
/// A phone-wide box, but loose inside it: a bare `Text` under a tight `SizedBox` would be
/// stretched to the full width and every measurement below would read 375.
Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 375,
            child: Align(alignment: Alignment.centerLeft, child: child),
          ),
        ),
      ),
    );

Text _text(WidgetTester tester) => tester.widget<Text>(find.descendant(of: find.byType(VDelay), matching: find.byType(Text)));

void main() {
  testWidgets('on time is a green nought, not a word', (tester) async {
    await _pump(tester, const VDelay(0, size: VDelaySize.large));
    expect(find.text('0'), findsOneWidget);
    expect(find.text('pünktlich'), findsNothing);
    expect(_text(tester).style?.color, VColors.green);
  });

  testWidgets('the nought leaves room beside it', (tester) async {
    await _pump(
      tester,
      const Row(
        children: [
          VDelay(0, size: VDelaySize.large),
          SizedBox(width: 16),
          Expanded(child: Text('Aulendorf')),
        ],
      ),
    );
    // A nought at 56 px is about 35 px wide; the word was about 250 px and ate the row.
    expect(tester.getSize(find.byType(VDelay)).width, lessThan(100));
    // Enough left over that the station name stays on one line.
    expect(tester.getSize(find.text('Aulendorf')).height, lessThan(40));
  });

  testWidgets('a counting figure passes through zero in ink', (tester) async {
    await _pump(tester, const VDelay(0, size: VDelaySize.display, punctualZero: false));
    expect(_text(tester).style?.color, VColors.ink);
  });

  testWidgets('a delay keeps its red plus', (tester) async {
    await _pump(tester, const VDelay(68, size: VDelaySize.large));
    final rich = tester.widget<RichText>(find.descendant(of: find.byType(VDelay), matching: find.byType(RichText)));
    expect((rich.text as TextSpan).toPlainText(), '+68');
  });

  testWidgets('Ausfall is a word and drops out of the figure size', (tester) async {
    await _pump(tester, const VDelay(0, size: VDelaySize.display, cancelled: true));
    expect(find.text('Ausfall'), findsOneWidget);
    final style = _text(tester).style!;
    expect(style.color, VColors.red);
    expect(style.fontSize, lessThan(VText.display.fontSize!));
    // And it fits: the word used to be set at 168 px, about 700 px wide — no phone is.
    expect(tester.getSize(find.byType(VDelay)).width, lessThan(375));
  });
}
