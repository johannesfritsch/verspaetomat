import '../../api/models.dart';

/// „Früher" (#67, #84), decided without a widget: where the next page back starts, what a page
/// that came back adds to the list, and when there is nothing further back to fetch.

/// How far one page goes back. The backend searches the same two hours from a page's time
/// (`PLAN_PAGE_WINDOW` in backend/src/journeys.rs), so a page holds every train of its stretch
/// and the pages meet without a gap.
const earlierStep = Duration(hours: 2);

/// When a connection leaves: the first leg's live time when the feed has one.
DateTime? departureOf(ApiItinerary it) => it.first.liveDeparture ?? it.plannedDeparture;

/// When it arrives, live when the feed has it.
DateTime? arrivalOf(ApiItinerary it) => it.liveArrival ?? it.plannedArrival;

/// One connection, the same however many pages bring it.
String connectionKey(ApiItinerary it) => it.legs.map((l) => '${l.tripId}@${l.plannedDeparture?.toIso8601String()}').join('|');

bool _arrived(ApiItinerary it, DateTime now) {
  final a = arrivalOf(it);
  return a != null && !a.isAfter(now);
}

DateTime? _earliest(Iterable<ApiItinerary> its) => its.map(departureOf).whereType<DateTime>().fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);

/// Where the next page starts: [earlierStep] before the earliest train on the list, or before
/// the last page when that one began earlier still — it brought nothing before the list.
DateTime earlierPageStart({required Iterable<ApiItinerary> shown, DateTime? lastStart, required DateTime now}) {
  var from = _earliest(shown) ?? now;
  if (lastStart != null && lastStart.isBefore(from)) from = lastStart;
  return from.subtract(earlierStep);
}

/// What one page back brings.
class EarlierPage {
  const EarlierPage({required this.start, required this.fresh, required this.end});

  /// Where it started; the next page goes back from here or from the list, whichever is earlier.
  final DateTime start;

  /// What goes on the list: connections it did not have that have not arrived yet. A train that
  /// has arrived is left out — nobody is sitting in it.
  final List<ApiItinerary> fresh;

  /// Nothing further back is still under way: every train this page has from before the list has
  /// arrived. A page with nothing from before the list is not the end — the trains before it may
  /// lie further back than one page reaches, after a night or a gap in the timetable. An empty
  /// page is: the planner always answers with the next trains from its time on, so an empty
  /// answer means there are none (and the Demo has nothing before its morning).
  final bool end;
}

/// Reads the page that came back for [start] against the list as [shown].
EarlierPage readEarlierPage({required List<ApiItinerary> shown, required DateTime start, required List<ApiItinerary> page, required DateTime now}) {
  final known = {for (final it in shown) connectionKey(it)};
  final fresh = page.where((it) => !known.contains(connectionKey(it)) && !_arrived(it, now)).toList();
  final earliest = _earliest(shown);
  final before = page.where((it) {
    final d = departureOf(it);
    return earliest == null || (d != null && d.isBefore(earliest));
  }).toList();
  final end = page.isEmpty || (before.isNotEmpty && before.every((it) => _arrived(it, now)));
  return EarlierPage(start: start, fresh: fresh, end: end);
}

/// How many pages one tap may ask for: six hours, enough to cross a night's gap without a tap
/// that shows nothing.
const earlierPagesPerTap = 3;

/// One tap on „Früher": pages back with [fetch] until a page brings something or is the end, at
/// most [earlierPagesPerTap] of them.
Future<EarlierPage> pageBack({
  required List<ApiItinerary> shown,
  DateTime? lastStart,
  required DateTime now,
  required Future<List<ApiItinerary>> Function(DateTime start) fetch,
}) async {
  var start = earlierPageStart(shown: shown, lastStart: lastStart, now: now);
  for (var i = 1;; i++) {
    final page = readEarlierPage(shown: shown, start: start, page: await fetch(start), now: now);
    if (page.fresh.isNotEmpty || page.end || i >= earlierPagesPerTap) return page;
    start = earlierPageStart(shown: shown, lastStart: start, now: now);
  }
}
