import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/screens/claims/antrag_screen.dart';
import 'package:verspaetomat/screens/claims/demo_antrag_screen.dart';
import 'package:verspaetomat/widgets/kit.dart' show VPrimaryButton, VTintButton;

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

  /// True if [finder]'s widget is inside the visible screen.
  bool onScreen(WidgetTester tester, Finder finder) {
    final rect = tester.getRect(finder);
    final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    return screen.contains(rect.center);
  }

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

  Future<void> tapWeiter(WidgetTester tester) async {
    await tester.tap(find.text('Weiter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('the e-mail row says E-Mail, also once it is filled in', (tester) async {
    await openPruefen(tester);
    expect(find.text('Postfach'), findsNothing);
    await tester.enterText(fieldLabelled('E-Mail'), 'anita@example.org');
    await tester.pump();
    expect(find.text('E-Mail'), findsOneWidget);
  });

  testWidgets('Weiter with a postcode in the e-mail row brings that row into view and says why', (tester) async {
    await openPruefen(tester);
    await tester.enterText(fieldLabelled('Name'), 'Anita Müller');
    await tester.enterText(fieldLabelled('Anschrift'), 'Franz-Müller-Straße 23');
    await tester.enterText(fieldLabelled('E-Mail'), '99111');
    // Back to the top, where the passenger is when they reach for „Weiter".
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pump(const Duration(milliseconds: 300));

    await tapWeiter(tester);

    expect(onScreen(tester, fieldLabelled('E-Mail')), isTrue, reason: 'the row that is wrong has to be on screen');
    expect(find.text('Das ist keine E-Mail-Adresse.'), findsOneWidget);
    final field = tester.widget<TextField>(fieldLabelled('E-Mail'));
    expect(field.focusNode?.hasFocus, isTrue, reason: 'the cursor goes where the fix is');
  });

  testWidgets('Weiter with nothing filled in starts at the name and marks every missing row', (tester) async {
    await openPruefen(tester);
    await tapWeiter(tester);
    expect(onScreen(tester, fieldLabelled('Name')), isTrue);
    expect(find.text('Fehlt noch.'), findsNWidgets(3));
  });

  // #21: „Warum ist Weiter rot, obwohl das Formular nicht ausgefüllt ist?" The red light means
  // *do this* in this app, so it may only come on when the step is really done; until then the
  // button is the quiet tier and the line above it names what is missing.
  testWidgets('an unfinished step draws the quiet Weiter and says what is missing', (tester) async {
    await openPruefen(tester);
    expect(find.widgetWithText(VPrimaryButton, 'Weiter'), findsNothing, reason: 'nothing is filled in');
    expect(find.widgetWithText(VTintButton, 'Weiter'), findsOneWidget);
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

  testWidgets('a finished step draws the red Weiter and says nothing more', (tester) async {
    await openPruefen(tester);
    await tester.enterText(fieldLabelled('Name'), 'Anita Müller');
    await tester.enterText(fieldLabelled('Anschrift'), 'Franz-Müller-Straße 23');
    await tester.enterText(fieldLabelled('E-Mail'), 'anita@example.org');
    await tester.pump();
    expect(find.widgetWithText(VPrimaryButton, 'Weiter'), findsOneWidget);
    expect(find.widgetWithText(VTintButton, 'Weiter'), findsNothing);
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
