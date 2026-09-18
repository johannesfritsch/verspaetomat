import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/theme/tokens.dart';
import 'package:verspaetomat/widgets/kit.dart';

/// Two things Johannes found on the boards: the figure said nowhere that it explains itself, and
/// the handwritten note beside it came out shaved off on the right.
void main() {
  Widget board({VoidCallback? onTap, VoidCallback? onExplain, Widget? aside}) => MaterialApp(
        home: Scaffold(
          body: VBoard(
            onTap: onTap,
            onExplain: onExplain,
            aside: aside,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [VBoardLabel('Minuten haben wir gewartet', icon: Icons.schedule)],
            ),
          ),
        ),
      );

  Finder mark() => find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.info_outline);

  testWidgets('a board with a source sheet says so with a mark in its corner', (tester) async {
    await tester.pumpWidget(board(onExplain: () {}));
    expect(mark(), findsOneWidget);
    final board_ = tester.getRect(find.byType(VBoard));
    final it = tester.getRect(mark());
    expect(board_.right - it.right, lessThan(28), reason: 'it hangs in the top right corner');
    expect(it.top - board_.top, lessThan(28));
  });

  testWidgets('the mark opens the sheet even where the board itself goes somewhere else', (tester) async {
    var explained = 0, tapped = 0;
    await tester.pumpWidget(board(onTap: () => tapped++, onExplain: () => explained++));
    await tester.tap(mark());
    expect((explained, tapped), (1, 0), reason: 'Home taps through to Wir; the mark explains');
  });

  testWidgets('a board that explains nothing carries no mark', (tester) async {
    await tester.pumpWidget(board(onTap: () {}));
    expect(mark(), findsNothing);
  });

  testWidgets('the note keeps its ink: nothing is clipped to the measured box', (tester) async {
    await tester.pumpWidget(board(
      onExplain: () {},
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

  testWidgets('a label too long for the board stops short of the mark rather than running under it', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
          child: VBoard(
            onExplain: () {},
            child: const VBoardLabel('Ein Label, das viel zu lang ist für dieses Brett', icon: Icons.schedule),
          ),
        ),
      ),
    ));
    expect(mark(), findsOneWidget);
    // The one thing markRoom exists for. The mark is drawn in the board's corner whatever the
    // label does, so its presence proves nothing; the clearance does.
    expect(
      tester.getRect(find.text('EIN LABEL, DAS VIEL ZU LANG IST FÜR DIESES BRETT')).right,
      lessThanOrEqualTo(tester.getRect(mark()).left),
    );
  });

  testWidgets('the mark costs a board with a margin note no height', (tester) async {
    const note = VHandNote('Aus\nVerspätung\nwird\nGutes.', angle: -0.09, align: TextAlign.right);
    await tester.pumpWidget(board(aside: note));
    final plain = tester.getSize(find.byType(VBoard));
    await tester.pumpWidget(board(onExplain: () {}, aside: note));
    expect(tester.getSize(find.byType(VBoard)).height, plain.height,
        reason: 'the corner is taken out of the note\'s width, not out of the board\'s top');
  });
}
