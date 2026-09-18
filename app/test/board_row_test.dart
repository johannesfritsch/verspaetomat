import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/screens/community/community_widgets.dart';
import 'package:verspaetomat/theme/tokens.dart';
import 'package:verspaetomat/widgets/kit.dart';

/// #24: the Ranglisten on Wir. What the rewrite promises and what has to keep being true:
/// every name on the same left edge, the passenger's own row marked without moving its text,
/// and a place that fits its column however far down the list it is.
void main() {
  Widget list(List<ApiBoardEntry> entries) => MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(VSpace.card),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final e in entries) BoardRow(entry: e)],
            ),
          ),
        ),
      );

  const others = [
    ApiBoardEntry(rank: 1, name: 'Miri aus Hamm', points: 212),
    ApiBoardEntry(rank: 2, name: 'tobi_aus_kalk', points: 174),
    ApiBoardEntry(rank: 4, name: 'Gleiswechsel', points: 133),
    ApiBoardEntry(rank: 10, name: 'Johannes', points: 4),
  ];

  testWidgets('every name starts on the same edge, the passenger\'s own included', (tester) async {
    await tester.pumpWidget(list([...others, const ApiBoardEntry(rank: 11, name: '—', points: 0, isMe: true)]));
    final lefts = {
      for (final name in ['Miri aus Hamm', 'tobi_aus_kalk', 'Gleiswechsel', 'Johannes', 'Du'])
        name: tester.getRect(find.text(name)).left,
    };
    expect(lefts.values.toSet(), hasLength(1), reason: 'one column of names: $lefts');
  });

  testWidgets('the row draws no rule of its own — the list owns the line between two rows', (tester) async {
    await tester.pumpWidget(list(others));
    expect(
      find.descendant(of: find.byType(BoardRow), matching: find.byType(VRule)),
      findsNothing,
      reason: 'a rule inside the row is a rule under the last row too (STYLE.md)',
    );
  });

  testWidgets('a four-figure place stays on one line inside its column', (tester) async {
    await tester.pumpWidget(list(const [ApiBoardEntry(rank: 3021, name: 'Du', points: 7, isMe: true)]));
    final place = tester.getRect(find.text('3021'));
    expect(place.width, lessThanOrEqualTo(28), reason: 'it is scaled down, not wrapped');
    expect(place.height, lessThan(24), reason: 'one line: a second one would be clipped by the disc');
  });

  testWidgets('the top three carry a disc and the rest do not', (tester) async {
    await tester.pumpWidget(list(others));
    BoxDecoration? discOf(String rank) {
      final box = find.ancestor(of: find.text(rank), matching: find.byType(Container)).first;
      return tester.widget<Container>(box).decoration as BoxDecoration?;
    }

    expect(discOf('1')?.shape, BoxShape.circle);
    expect(discOf('2')?.shape, BoxShape.circle);
    expect(discOf('4'), isNull);
    expect(discOf('10'), isNull);
  });
}
