import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/screens/onboarding/wiederherstellen_screen.dart';
import 'package:verspaetomat/widgets/kit.dart';

/// Twelve boxes instead of one free-text field (#43), and the one behaviour that decides whether
/// that is an improvement or a chore: a whole phrase has to be able to arrive at once.
///
/// Nobody types twelve words they wrote on paper into twelve separate boxes by hand if they can
/// paste — and the drawn screen has no „Einfügen" button, so the boxes themselves have to take a
/// phrase. If this ever goes red, the screen has quietly become a form that demands twelve
/// separate taps.
void main() {
  const phrase = 'bahnhof zug gleis fahrplan schiene wagen abteil tunnel bruecke signal weiche depot';
  final words = phrase.split(' ');

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: WiederherstellenScreen()));
    await tester.pumpAndSettle();
  }

  List<String> boxes(WidgetTester tester) =>
      tester.widgetList<TextField>(find.byType(TextField)).map((f) => f.controller?.text ?? '').toList();

  testWidgets('there are twelve boxes and they start empty', (tester) async {
    await pump(tester);
    expect(find.byType(TextField), findsNWidgets(12));
    expect(boxes(tester).every((t) => t.isEmpty), isTrue);
    for (var i = 1; i <= 12; i++) {
      expect(find.text('Wort $i'), findsOneWidget, reason: 'box $i is not numbered');
    }
  });

  testWidgets('a whole phrase pasted into the first box lays itself out across all twelve', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, phrase);
    await tester.pumpAndSettle();
    expect(boxes(tester), words, reason: 'the phrase did not spread in order');
  });

  testWidgets('a phrase pasted into the middle fills from there, and the rest is dropped rather than wrapped', (tester) async {
    await pump(tester);
    // Ten words into box 11: two fit, eight have nowhere to go. Wrapping them back to box 1 would
    // silently overwrite words somebody already typed.
    await tester.enterText(find.byType(TextField).at(10), words.take(10).join(' '));
    await tester.pumpAndSettle();
    final filled = boxes(tester);
    expect(filled[10], words[0]);
    expect(filled[11], words[1]);
    expect(filled.take(10).every((t) => t.isEmpty), isTrue, reason: 'the overflow wrapped round');
  });

  testWidgets('a word finished with a space moves on to the next box', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, 'bahnhof ');
    await tester.pumpAndSettle();
    expect(boxes(tester)[0], 'bahnhof', reason: 'the space stayed in the box');
    expect(boxes(tester)[1], '');
  });

  testWidgets('Wiederherstellen stays off until the twelfth word', (tester) async {
    await pump(tester);
    VPrimaryButton button() => tester.widget<VPrimaryButton>(find.widgetWithText(VPrimaryButton, 'Wiederherstellen'));
    expect(button().onTap, isNull, reason: 'an empty form could be submitted');

    // Eleven of twelve is still not a recovery code.
    await tester.enterText(find.byType(TextField).first, words.take(11).join(' '));
    await tester.pumpAndSettle();
    expect(button().onTap, isNull, reason: 'eleven words armed the button');

    await tester.enterText(find.byType(TextField).at(11), words[11]);
    await tester.pumpAndSettle();
    expect(button().onTap, isNotNull, reason: 'twelve words did not arm the button');
  });

  testWidgets('what a recovery word may contain is decided as it is typed', (tester) async {
    await pump(tester);
    // Capitals, digits and punctuation: the server is asked with lower-case letters only, and
    // the screen says „Groß- und Kleinschreibung zählt nicht" by simply not keeping them.
    await tester.enterText(find.byType(TextField).first, 'Bahnhof123!');
    await tester.pumpAndSettle();
    expect(boxes(tester)[0], 'bahnhof');

    await tester.enterText(find.byType(TextField).at(1), 'STRASSE');
    await tester.pumpAndSettle();
    expect(boxes(tester)[1], 'strasse');
  });
}
