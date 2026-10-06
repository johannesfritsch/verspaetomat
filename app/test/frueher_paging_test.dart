import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/screens/ride/earlier_page.dart';

/// „Früher" (#84): one tap has to reach the train you are sitting in, and the paging ends only
/// when nothing further back is still under way.

/// A time on 2 October 2026, as the clock in Ulm shows it (CEST, two hours ahead of UTC).
DateTime local(int h, int m, {int day = 2}) => DateTime.utc(2026, 10, day, h - 2, m);

ApiItinerary train(String line, DateTime dep, DateTime arr) => ApiItinerary(
      id: '$line-${dep.toIso8601String()}',
      plannedDeparture: dep,
      plannedArrival: arr,
      legs: [
        ApiLeg(
          tripId: '$line@${dep.toIso8601String()}',
          line: line,
          fromStationId: 'vs:1',
          fromStationName: 'Ulm Hbf',
          toStationId: 'vs:2',
          toStationName: 'Mannheim Hbf',
          plannedDeparture: dep,
          plannedArrival: arr,
        ),
      ],
    );

/// What `GET /v1/journeys/plan?time=…` answers: from [start] on, every train of the two hours
/// the backend searches (`PLAN_PAGE_WINDOW`), and at least four.
List<ApiItinerary> planner(List<ApiItinerary> timetable, DateTime start) {
  final from = timetable.where((it) => !departureOf(it)!.isBefore(start)).toList()..sort((a, b) => departureOf(a)!.compareTo(departureOf(b)!));
  final end = start.add(const Duration(hours: 2));
  return [
    for (final (i, it) in from.indexed)
      if (i < 4 || !departureOf(it)!.isAfter(end)) it,
  ];
}

List<String> lines(Iterable<ApiItinerary> its) => [for (final it in its) it.first.line];

void main() {
  group('Ulm Hbf → Mannheim Hbf at 12:10, the timetable of 2 October', () {
    final now = local(12, 10);
    final ice690 = train('ICE 690', local(10, 1), local(11, 26));
    final re5 = train('RE 5', local(10, 15), local(12, 0));
    final ice610 = train('ICE 610', local(10, 47), local(12, 26));
    final ice918 = train('ICE 918', local(11, 33), local(13, 4));
    final ice598 = train('ICE 598', local(12, 1), local(13, 26));
    final later = [
      train('ICE 1220', local(12, 20), local(13, 59)),
      train('ICE 1247', local(12, 47), local(14, 26)),
      train('ICE 1333', local(13, 33), local(15, 4)),
    ];
    final timetable = [ice690, re5, ice610, ice918, ice598, ...later];
    // The first page, from half an hour back: ICE 598 is „schon weg", the rest still to come.
    final firstPage = [ice598, ...later];

    test('ICE 610, under way since 10:47, is on the list after one tap', () async {
      final asked = <DateTime>[];
      final page = await pageBack(
        shown: firstPage,
        now: now,
        fetch: (start) async {
          asked.add(start);
          return planner(timetable, start);
        },
      );
      expect(asked, [local(10, 1)], reason: 'two hours before ICE 598');
      // ICE 690 and the RE 5 have arrived: nobody is sitting in them.
      expect(lines(page.fresh), ['ICE 610', 'ICE 918']);
      expect(page.end, isFalse);
    });

    test('the next tap goes on from where this page began', () {
      final page = readEarlierPage(shown: firstPage, start: local(10, 1), page: planner(timetable, local(10, 1)), now: now);
      final shown = [...firstPage, ...page.fresh];
      expect(earlierPageStart(shown: shown, lastStart: page.start, now: now), local(8, 1));
    });
  });

  group('a stretch without trains', () {
    // A line every two hours, with a gap in the early morning: 05:58, then 08:58, 10:58 …
    final now = local(9, 10);
    final early = train('RE 1', local(5, 58), local(6, 40));
    final shown = [
      train('RE 2', local(8, 58), local(9, 40)),
      train('RE 3', local(10, 58), local(11, 40)),
      train('RE 4', local(12, 58), local(13, 40)),
      train('RE 5', local(14, 58), local(15, 40)),
    ];
    final timetable = [early, ...shown];

    test('a page of trains already on the list does not end the paging', () {
      final page = readEarlierPage(shown: shown, start: local(6, 58), page: planner(timetable, local(6, 58)), now: now);
      expect(page.fresh, isEmpty);
      expect(page.end, isFalse, reason: 'nothing left before 08:58 in this page says nothing about before 06:58');
      expect(earlierPageStart(shown: shown, lastStart: page.start, now: now), local(4, 58), reason: 'the next page goes further back');
    });

    test('one tap reaches past it, and the paging ends where everything has arrived', () async {
      final asked = <DateTime>[];
      final page = await pageBack(
        shown: shown,
        now: now,
        fetch: (start) async {
          asked.add(start);
          return planner(timetable, start);
        },
      );
      expect(asked, [local(6, 58), local(4, 58)]);
      expect(page.fresh, isEmpty, reason: 'the 05:58 arrived at 06:40');
      expect(page.end, isTrue);
    });

    test('a tap asks for three pages at most, and a longer gap leaves the button on', () async {
      final asked = <DateTime>[];
      final page = await pageBack(
        shown: shown,
        now: now,
        fetch: (start) async {
          asked.add(start);
          return planner(shown, start);
        },
      );
      expect(asked, [local(6, 58), local(4, 58), local(2, 58)]);
      expect(page.fresh, isEmpty);
      expect(page.end, isFalse);
      expect(page.start, local(2, 58), reason: 'the next tap goes on from there');
    });

    test('a train before it that is still under way comes in', () async {
      final slow = train('IC 9', local(5, 30), local(9, 50));
      final page = await pageBack(shown: shown, now: now, fetch: (start) async => planner([slow, early, ...shown], start));
      expect(lines(page.fresh), ['IC 9']);
      expect(page.end, isFalse);
    });
  });

  test('an empty page is the end: the Demo has nothing before its morning', () async {
    final shown = [train('S 6', local(7, 51), local(8, 20))];
    final page = await pageBack(shown: shown, now: local(8, 0), fetch: (_) async => const []);
    expect(page.fresh, isEmpty);
    expect(page.end, isTrue);
  });
}
