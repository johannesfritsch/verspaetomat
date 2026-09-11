import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/screens/share/share_lines.dart';
import 'package:verspaetomat/widgets/ticket.dart';

/// docs/27 §9. The card is the most public thing this app makes, so the copy on it is worth
/// pinning down: singulars, German number formatting, and the words that decide whether the
/// sentence is true.
void main() {
  group('Antrag', () {
    test('one Fall reads as one, several as several', () {
      final one = TicketData.antrag(minutes: 1, cases: 1, euro: '1,50 €', ngoName: 'X');
      expect(one.numberLabel, 'MINUTE');
      expect(one.fields.first, ('FALL', '1'));

      final many = TicketData.antrag(minutes: 205, cases: 3, euro: '12,00 €', ngoName: 'X');
      expect(many.numberLabel, 'MINUTEN');
      expect(many.fields.first, ('FÄLLE', '3'));
    });

    test('the ticket says who is being asked, and changes when the money has arrived', () {
      final asked = TicketData.antrag(minutes: 205, cases: 3, euro: '12,00 €', ngoName: 'Bahnhofsmission Köln');
      expect(asked.fields[1], ('ZAHLT AN', 'Bahnhofsmission Köln'));

      final paid = TicketData.antrag(minutes: 205, cases: 3, euro: '12,00 €', ngoName: 'Bahnhofsmission Köln', paid: true);
      expect(paid.fields[1], ('BEZAHLT', 'Bahnhofsmission Köln'));
    });

    test('no line calls it a donation — the railway is paying a claim', () {
      final lines = ShareLines.antrag(minutes: 205, cases: 3, cents: 1200, ngo: 'Bahnhofsmission Köln');
      expect(lines.length, 4);
      expect(lines.any((l) => l.contains('spenden') || l.contains('Spende')), isFalse);
      expect(lines.first, contains('dazu gebracht'));
      expect(lines.first, contains('205 Minuten'));
      // German money, everywhere.
      expect(lines.last, contains('12,00 €'));
    });

    test('one minute is a Minute in the copy too', () {
      final lines = ShareLines.antrag(minutes: 1, cases: 1, cents: 150, ngo: 'X');
      expect(lines.first, contains('1 Minute '));
      expect(lines.first, isNot(contains('1 Minuten')));
    });
  });

  group('Angekommen und pünktlich', () {
    test('a delay is red, a punctual arrival is not', () {
      expect(TicketData.angekommen(minutes: 68, points: 68).isPunctual, isFalse);
      expect(TicketData.puenktlich().isPunctual, isTrue);
    });

    test('0 minutes is a different face, not the delay card with a zero in it', () {
      final p = TicketData.puenktlich();
      expect(p.face, TicketFace.puenktlich);
      expect(p.caption, 'PÜNKTLICH');
      expect(ShareLines.puenktlich(to: null).first, contains('pünktlich'));
    });

    test('59 and 60 minutes both read as minutes; the claim is not the card’s business', () {
      expect(TicketData.angekommen(minutes: 59, points: 59).numberLabel, 'MINUTEN');
      expect(TicketData.angekommen(minutes: 60, points: 60).numberLabel, 'MINUTEN');
    });
  });

  group('Abzeichen', () {
    test('the fact comes with the badge, so an outsider can read the card', () {
      final t = TicketData.abzeichen(name: 'Volle Stunde', rule: 'Erste 60-Minuten-Verspätung');
      expect(t.fields.first, ('WOFÜR', 'Erste 60-Minuten-Verspätung'));
      expect(t.caption, 'FREIGESCHALTET');
      expect(t.number, isNull);
    });

    test('the badge name takes the inner German quotes and never opens a line', () {
      final lines = ShareLines.abzeichen(name: 'Volle Stunde');
      for (final l in lines) {
        expect(l.startsWith('‚'), isFalse, reason: '„‚ side by side is a cramped opening');
        expect(l.contains('„'), isFalse, reason: 'the outer quotes belong to the ticket');
      }
      expect(lines.first, contains('‚Volle Stunde‘'));
    });
  });

  group('Wir', () {
    test('the collective number is grouped the German way', () {
      expect(ShareLines.wir(minutes: 1208638).first, contains('1.208.638'));
      expect(ShareLines.wir(minutes: 999).first, contains('999'));
      expect(ShareLines.wir(minutes: 1000).first, contains('1.000'));
    });
  });
}
