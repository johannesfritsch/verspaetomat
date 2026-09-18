import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/theme/tokens.dart';
import 'package:verspaetomat/widgets/figures.dart';

/// #33: the week chart on the Bahnsteig.
///
/// The thing to get right is the empty week. Seven full-height bars must read as a *track* — a
/// place where something will go — and never as seven days that each earned something. That is
/// the whole reason they are one uniform unlit grey with nothing picked out.
void main() {
  const week = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  Future<List<Container>> bars(
    WidgetTester tester,
    List<int> values, {
    int todayIndex = 2,
    bool emptyIsTrack = true,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: VWeekBars(values: values, todayIndex: todayIndex, labels: week, emptyIsTrack: emptyIsTrack),
        ),
      ),
    ));
    return tester
        .widgetList<Container>(find.descendant(of: find.byType(VWeekBars), matching: find.byType(Container)))
        .toList();
  }

  Color? fillOf(Container c) => (c.decoration as BoxDecoration?)?.color;
  double? heightOf(Container c) => c.constraints?.maxHeight;

  group('a week with nothing in it', () {
    testWidgets('draws seven full-height bars, not seven stubs', (tester) async {
      final drawn = await bars(tester, const [0, 0, 0, 0, 0, 0, 0]);
      expect(drawn, hasLength(7));
      for (final c in drawn) {
        expect(heightOf(c), VControl.weekBarMax, reason: 'an empty week is a track, not a hole in the page');
      }
    });

    testWidgets('every bar is the same unlit grey — nothing is picked out', (tester) async {
      final drawn = await bars(tester, const [0, 0, 0, 0, 0, 0, 0]);
      for (final c in drawn) {
        expect(fillOf(c), VColors.track);
      }
      // One bar lit red would read as "something happened on Wednesday".
      expect(drawn.map(fillOf).contains(VColors.redBright), isFalse);
    });

    testWidgets('the labels are still there, so it is legible as a week', (tester) async {
      await bars(tester, const [0, 0, 0, 0, 0, 0, 0]);
      for (final d in week) {
        expect(find.text(d), findsOneWidget);
      }
    });
  });

  group('a week nobody has told us about', () {
    testWidgets('all-zero without the flag stays stubs, because that is also a failed load', (tester) async {
      // `ApiStanding.empty` is all zeroes too. Seven full-height bars while the page is still
      // loading, or after the server could not be reached, would be the chart claiming a week it
      // was never told about — so the track is opt-in and only the seven-day caller opts in.
      final drawn = await bars(tester, const [0, 0, 0, 0, 0, 0, 0], emptyIsTrack: false);
      for (final c in drawn) {
        expect(heightOf(c), lessThan(VControl.weekBarMax / 4));
      }
    });
  });

  group('a week with something in it', () {
    testWidgets('today is the lit one and the rest are the track', (tester) async {
      final drawn = await bars(tester, const [0, 3, 40, 0, 8, 0, 0], todayIndex: 2);
      expect(fillOf(drawn[2]), VColors.redBright, reason: 'redBright means *this one*');
      for (var i = 0; i < 7; i++) {
        if (i != 2) expect(fillOf(drawn[i]), VColors.track);
      }
    });

    testWidgets('bars are proportional, and a zero day is a stub rather than nothing', (tester) async {
      final drawn = await bars(tester, const [0, 20, 40, 0, 0, 0, 0], todayIndex: 2);
      expect(heightOf(drawn[2]), VControl.weekBarMax, reason: 'the peak sets the height');
      expect(heightOf(drawn[1]), closeTo(VControl.weekBarMax / 2, 0.01));
      // A day with nothing keeps a visible stub so the week still reads as seven days.
      expect(heightOf(drawn[0]), greaterThan(0));
      expect(heightOf(drawn[0]), lessThan(VControl.weekBarMax / 4));
    });

    testWidgets('a todayIndex outside the week lights nothing', (tester) async {
      final drawn = await bars(tester, const [1, 2, 3, 0, 0, 0, 0], todayIndex: -1);
      expect(drawn.map(fillOf).contains(VColors.redBright), isFalse);
    });

    testWidgets('today with nothing on it is not lit', (tester) async {
      // A lit 4 pt stub reads as "you earned a little today", which is the opposite of true.
      final drawn = await bars(tester, const [0, 20, 40, 0, 0, 0, 0], todayIndex: 3);
      expect(fillOf(drawn[3]), VColors.track);
      expect(drawn.map(fillOf).contains(VColors.redBright), isFalse);
    });
  });

  group('the fallback shape', () {
    testWidgets('two columns still work, for a server that sends no daily breakdown', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(child: VWeekBars(values: [41, 60], todayIndex: 1, labels: ['Letzte', 'Diese'])),
        ),
      ));
      expect(find.text('Letzte'), findsOneWidget);
      expect(find.text('Diese'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one column is not a chart and draws nothing', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: VWeekBars(values: [5], todayIndex: 0, labels: ['Diese']))),
      ));
      expect(find.text('Diese'), findsNothing);
    });
  });
}
