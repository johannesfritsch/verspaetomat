import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/content/labels.dart';

/// docs/39 §3. The name of a ticket is how a draft that was left lying about recognises the
/// file it already carries — and it is the file name in the mail to the railway. Two callers,
/// one rule; if they ever disagree, the passenger is asked for the same picture twice.
void main() {
  test('a month becomes a German month', () {
    expect(monthLabel('2026-08'), 'August 2026');
    expect(monthLabel('2026-01'), 'Januar 2026');
    expect(monthLabel('2026-12'), 'Dezember 2026');
  });

  test('anything that is not a month stays as it is', () {
    expect(monthLabel('Ticket'), 'Ticket');
    expect(monthLabel('2026-13'), '2026-13');
    expect(monthLabel('2026'), '2026');
  });

  test('the ticket label names its month, and a single ticket names none', () {
    expect(ticketLabel('2026-09'), 'Ticket September 2026');
    expect(ticketLabel('Ticket'), 'Ticket');
  });
}
