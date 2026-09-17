import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/theme/tokens.dart';
import 'package:verspaetomat/widgets/kit.dart';

/// Two things Johannes found on the boards: the figure said nowhere that it explains itself, and
/// the handwritten note beside it came out shaved off on the right.
void main() {
  Widget board({VoidCallback? onTap, Widget? aside}) => MaterialApp(
        home: Scaffold(
          body: VBoard(
            onTap: onTap,
            aside: aside,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [VBoardLabel('Minuten haben wir gewartet', icon: Icons.schedule)],
            ),
          ),
        ),
      );

  Finder mark() => find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.info_outline);

  testWidgets('a board that opens its source sheet says so with a mark', (tester) async {
    await tester.pumpWidget(board(onTap: () {}));
    expect(mark(), findsOneWidget);
  });

  testWidgets('a board that opens nothing carries no mark', (tester) async {
    await tester.pumpWidget(board());
    expect(mark(), findsNothing);
  });

  testWidgets('the note keeps its ink: nothing is clipped to the measured box', (tester) async {
    await tester.pumpWidget(board(
      onTap: () {},
      aside: const VHandNote('Aus\nVerspätung\nwird\nGutes.', angle: -0.09, align: TextAlign.right),
    ));
    final text = tester.widget<Text>(find.text('Aus\nVerspätung\nwird\nGutes.'));
    expect(text.overflow, TextOverflow.visible, reason: 'a script face paints past its advance widths');
  });

  testWidgets('a note too wide for its space shrinks instead of being cut or broken', (tester) async {
    const note = VHandNote('Aus\nVerspätung\nwird\nGutes.', angle: -0.09, align: TextAlign.right);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: SizedBox(width: 400, child: note))),
    ));
    final wide = tester.getSize(find.byType(VHandNote));

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: SizedBox(width: 40, child: note))),
    ));
    final tight = tester.getSize(find.byType(VHandNote));

    expect(tight.width, lessThanOrEqualTo(40), reason: 'it fits the space it is given');
    expect(tight.height, lessThan(wide.height), reason: 'the whole block scales, lines and all');
    // Still the four lines it was written with, not a re-wrap and not an ellipsis.
    expect(find.text('Aus\nVerspätung\nwird\nGutes.'), findsOneWidget);
  });

  testWidgets('the mark survives a label too long for the board', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
          child: VBoard(
            onTap: () {},
            child: const VBoardLabel('Ein Label, das viel zu lang ist für dieses Brett', icon: Icons.schedule),
          ),
        ),
      ),
    ));
    expect(mark(), findsOneWidget);
    expect(tester.getSize(mark()).width, greaterThan(0));
  });
}
