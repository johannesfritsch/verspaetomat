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

    test('the ticket says whom it is for, and says „bezahlt" only once the money has come', () {
      final asked = TicketData.antrag(minutes: 205, cases: 3, euro: '12,00 €', ngoName: 'Bahnhofsmission Köln');
      expect(asked.fields[1], ('FÜR', 'Bahnhofsmission Köln'));

      final paid = TicketData.antrag(minutes: 205, cases: 3, euro: '12,00 €', ngoName: 'Bahnhofsmission Köln', paid: true);
      expect(paid.fields[1], ('BEZAHLT', 'Bahnhofsmission Köln'));
    });

    test('#49: at send time no line says the railway has paid', () {
      final lines = ShareLines.antrag(minutes: 205, cases: 3, cents: 1200, ngo: 'Bahnhofsmission Köln');
      expect(lines.length, 4);
      for (final l in lines) {
        expect(l, isNot(contains('dazu gebracht')), reason: l);
        expect(l, isNot(contains('zahlt ')), reason: l);
        expect(l, isNot(contains('bekommt')), reason: l);
      }
      expect(lines.any((l) => l.contains('spenden') || l.contains('Spende')), isFalse);
      expect(lines.first, contains('205 Minuten'));
      expect(lines.last, contains('12,00 €'));
    });

    test('once confirmed, the line may say it', () {
      final lines = ShareLines.bestaetigt(minutes: 205, cents: 1200, ngo: 'Bahnhofsmission Köln');
      expect(lines.first, contains('dazu gebracht'));
      expect(lines.first, contains('205 Minuten'));
      expect(lines.any((l) => l.contains('12,00 €')), isTrue);
      expect(lines.any((l) => l.contains('Spende')), isFalse);
    });

    test('one minute is a Minute in the copy too', () {
      final lines = ShareLines.bestaetigt(minutes: 1, cents: 150, ngo: 'X');
      expect(lines.first, contains('1 Minute '));
      expect(lines.first, isNot(contains('1 Minuten')));
    });
  });

  group('#49: my own cards', () {
    test('my minutes, with the total only when it says something', () {
      expect(ShareLines.mine(minutes: 1298).first, 'Ich habe schon 1.298 Minuten auf Züge gewartet.');
      expect(ShareLines.mine(minutes: 1298, together: 1208311).any((l) => l.contains('1.208.311')), isTrue);
      expect(ShareLines.mine(minutes: 50, together: 50).any((l) => l.contains('Zusammen')), isFalse);
    });

    test('durations read like speech', () {
      expect(ShareLines.duration(45), '45 Minuten');
      expect(ShareLines.duration(60), '1 Stunde');
      expect(ShareLines.duration(61), '1 Stunde 1 Minute');
      expect(ShareLines.duration(192), '3 Stunden 12 Minuten');
    });

    test('a line gets no article: der RE 7, but die S 12', () {
      for (final l in ShareLines.linie(train: 'S 12', minutes: 90, rides: 3, month: 'September')) {
        expect(l, isNot(contains('der S 12')));
        expect(l, isNot(contains('Der S 12')));
      }
    });

    test('a month card mentions money only when some was confirmed', () {
      expect(ShareLines.monat(month: 'August', minutes: 318, rides: 17, worst: 94).any((l) => l.contains('€')), isFalse);
      expect(ShareLines.monat(month: 'August', minutes: 318, rides: 17, worst: 94, confirmedCents: 450).any((l) => l.contains('4,50 €')), isTrue);
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
