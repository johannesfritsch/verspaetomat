import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/screens/claims/antrag_screen.dart';
import 'package:verspaetomat/screens/claims/demo_antrag_screen.dart';
import 'package:verspaetomat/widgets/kit.dart' show VPrimaryButton;

/// #19: „Für das Formular fehlt noch deine E-Mail-Adresse", and no e-mail field to be found.
///
/// The field was there, labelled „Postfach", below the fold; a postcode went into it. The
/// end-to-end tests never noticed because they find fields by position and scroll to them before
/// typing. This test does neither: it finds rows by the words a person reads, and after „Weiter" it
/// only looks — the screen has to bring the missing field into view by itself.
void main() {
  /// The text field in the row labelled [label], found through the label.
  Finder fieldLabelled(String label) => find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
        matching: find.byType(TextField),
      );

  Future<void> openPruefen(WidgetTester tester) async {
    // Widget tests draw every glyph as a square of the font size, so labels that fit in Archivo
    // overflow their rows here. That is the test font, not this screen; anything else still fails.
    final report = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('RenderFlex overflowed')) return;
      report?.call(details);
    };
    addTearDown(() => FlutterError.onError = report);
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: DemoAntragScreen()));
    for (var i = 0; i < 30 && find.text('Los geht\'s').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Los geht\'s'));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('the e-mail row says E-Mail, also once it is filled in', (tester) async {
    await openPruefen(tester);
    expect(find.text('Postfach'), findsNothing);
    await tester.enterText(fieldLabelled('E-Mail'), 'anita@example.org');
    await tester.pump();
    expect(find.text('E-Mail'), findsOneWidget);
  });

  testWidgets('a postcode left in the e-mail row says why, on the row itself', (tester) async {
    await openPruefen(tester);
    await tester.enterText(fieldLabelled('E-Mail'), '99111');
    // Leave the row. „Weiter" is disabled until the step is done (#21), so the row has to answer
    // for itself the moment it is left — there is no press left to ask.
    await tester.showKeyboard(fieldLabelled('Name'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Das ist keine E-Mail-Adresse.'), findsOneWidget);
    // The line under the form says the same thing in the same words: a wrong row is not a missing
    // one, which is the riddle #19 removed.
    expect(find.textContaining('eine gültige E-Mail-Adresse'), findsOneWidget);
  });

  testWidgets('a row left empty marks itself, and the line names all of them', (tester) async {
    await openPruefen(tester);
    // Through the three rows without typing: each one marks itself as it is left.
    for (final row in ['Name', 'Anschrift', 'E-Mail', 'Name']) {
      await tester.showKeyboard(fieldLabelled(row));
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('Fehlt noch.'), findsNWidgets(3));
    expect(find.text('Es fehlen noch: dein Name, deine Anschrift und deine E-Mail-Adresse.'), findsOneWidget);
  });

  // #21: „Warum ist Weiter rot, obwohl das Formular nicht ausgefüllt ist?" The red light means
  // *do this* in this app, so it may only come on when the step is really done; until then the
  // button is the quiet tier and the line above it names what is missing.
  testWidgets('an unfinished step draws Weiter disabled and says what is missing', (tester) async {
    await openPruefen(tester);
    final weiter = find.widgetWithText(VPrimaryButton, 'Weiter');
    expect(weiter, findsOneWidget, reason: 'one button in both states, not two widgets');
    expect(tester.widget<VPrimaryButton>(weiter).onTap, isNull, reason: 'grey and off, not a ghost');
    expect(find.text('Es fehlen noch: dein Name, deine Anschrift und deine E-Mail-Adresse.'), findsOneWidget);
  });

  testWidgets('a postcode in the e-mail row asks for a valid address, not for a missing one', (tester) async {
    await openPruefen(tester);
    await tester.enterText(fieldLabelled('Name'), 'Anita Müller');
    await tester.enterText(fieldLabelled('Anschrift'), 'Franz-Müller-Straße 23');
    await tester.enterText(fieldLabelled('E-Mail'), '99111');
    await tester.pump();
    expect(find.text('Es fehlt noch: eine gültige E-Mail-Adresse.'), findsOneWidget);
  });

  testWidgets('a finished step lights Weiter and says nothing more', (tester) async {
    await openPruefen(tester);
    await tester.enterText(fieldLabelled('Name'), 'Anita Müller');
    await tester.enterText(fieldLabelled('Anschrift'), 'Franz-Müller-Straße 23');
    await tester.enterText(fieldLabelled('E-Mail'), 'anita@example.org');
    await tester.pump();
    final weiter = find.widgetWithText(VPrimaryButton, 'Weiter');
    expect(tester.widget<VPrimaryButton>(weiter).onTap, isNotNull, reason: 'the light comes on when the step is done');
    expect(find.textContaining('Es fehl'), findsNothing);
  });

  test('an e-mail address is recognised, a postcode or a name is not', () {
    expect(looksLikeEmail('anita@example.org'), isTrue);
    expect(looksLikeEmail(' anita.mueller@web.de '), isTrue);
    expect(looksLikeEmail('99111'), isFalse);
    expect(looksLikeEmail('Anita Müller'), isFalse);
    expect(looksLikeEmail('anita@example'), isFalse);
  });
}
