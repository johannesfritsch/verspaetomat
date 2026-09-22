import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/screens/share/share_moments.dart';

/// #49: each moment turns up once on a device, and the first look never invents one.
void main() {
  ApiShareFacts facts({String? recordRide, String? month, List<String> confirmed = const []}) => ApiShareFacts(
        minutesTotal: 100,
        ridesTotal: 2,
        confirmedCents: 0,
        record: recordRide == null ? null : ApiShareRecord(rideId: recordRide, line: 'RE 7', minutes: 94),
        lastMonth: month == null ? null : ApiShareMonth(month: month, minutes: 94, rides: 2, worstMinutes: 94, points: 94, confirmedCents: 0),
        confirmedClaims: [for (final c in confirmed) ApiShareConfirmed(claimId: c, cents: 600, ngo: 'X', cases: 4, minutes: 281)],
      );

  Future<ShareMoments> moments([Map<String, Object> stored = const {}]) async {
    SharedPreferences.setMockInitialValues(stored);
    return ShareMoments(await SharedPreferences.getInstance());
  }

  test('the first record a device sees is noted, not celebrated; the next one is new', () async {
    final m = await moments();
    expect(m.recordIsNew(facts(recordRide: 'a')), isFalse);
    expect(m.recordIsNew(facts(recordRide: 'a')), isFalse);
    expect(m.recordIsNew(facts(recordRide: 'b')), isTrue);
    await m.markRecord(facts(recordRide: 'b'));
    expect(m.recordIsNew(facts(recordRide: 'b')), isFalse);
  });

  test('a confirmed claim is celebrated once', () async {
    final m = await moments();
    expect(m.pendingConfirmed(facts(confirmed: ['c1']))?.claimId, 'c1');
    await m.markConfirmed('c1');
    expect(m.pendingConfirmed(facts(confirmed: ['c1'])), isNull);
    expect(m.pendingConfirmed(facts(confirmed: ['c2', 'c1']))?.claimId, 'c2');
  });

  test('last month shows in the first week, once, and not at all when nothing was late', () async {
    final m = await moments();
    expect(m.monthDue(facts(month: '2026-08'), now: DateTime(2026, 9, 3)), isTrue);
    expect(m.monthDue(facts(month: '2026-08'), now: DateTime(2026, 9, 12)), isFalse);
    expect(m.monthDue(facts(), now: DateTime(2026, 9, 3)), isFalse);
    await m.markMonth(facts(month: '2026-08'));
    expect(m.monthDue(facts(month: '2026-08'), now: DateTime(2026, 9, 3)), isFalse);
  });
}
