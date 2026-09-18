import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/screens/claims/antraege_screen.dart' show EmptyAntraege;

/// #30: the Anträge tab before anything has happened.
///
/// This screen is the first thing a new passenger reads about how money works here, and every
/// number on it belongs to the backend (`rules.rs`). These tests pin the two ways it could lie:
/// by printing an amount that is only true for one kind of ticket, and by promising a deadline or
/// a reminder the app does not actually keep.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    int? flatClaimCents,
    int minPayoutCents = 400,
    int delayMinutes = 60,
    bool notifications = true,
    String? ngoName = 'Bahnhofsmission Köln',
  }) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EmptyAntraege(
              ngoName: ngoName,
              minPayoutCents: minPayoutCents,
              flatClaimCents: flatClaimCents,
              delayMinutes: delayMinutes,
              notifications: notifications,
            ),
          ),
        ),
      ));

  group('the amount is the server’s, or it is not stated', () {
    testWidgets('a Deutschlandticket gets its real rate', (tester) async {
      await pump(tester, flatClaimCents: 150);
      expect(find.textContaining('1,50 €'), findsOneWidget);
    });

    testWidgets('first class gets its own, higher rate — not the common one', (tester) async {
      await pump(tester, flatClaimCents: 225);
      expect(find.textContaining('2,25 €'), findsOneWidget);
      expect(find.textContaining('1,50 €'), findsNothing);
    });

    testWidgets('a ticket with no flat rate gets a sentence, never a number', (tester) async {
      // A Zeitkarte pays 1,50 € on a regional train and 5,00 € on a long-distance one; a single
      // ticket pays a share of its own fare. Printing any one number here is wrong for someone.
      await pump(tester, flatClaimCents: null);
      expect(find.textContaining('€'), findsWidgets, reason: 'the 4 € threshold is still shown');
      expect(find.textContaining('1,50'), findsNothing);
      expect(find.textContaining('2,25'), findsNothing);
      expect(find.textContaining('5,00'), findsNothing);
      expect(find.textContaining('hängt von deinem Ticket'), findsOneWidget);
    });

    testWidgets('the payout threshold comes from the server too', (tester) async {
      await pump(tester, minPayoutCents: 400);
      expect(find.textContaining('4,00 €'), findsOneWidget);

      // If the rule ever moved, the screen has to move with it rather than keep its own copy.
      await pump(tester, minPayoutCents: 750);
      expect(find.textContaining('7,50 €'), findsOneWidget);
      expect(find.textContaining('4,00 €'), findsNothing);
    });

    testWidgets('the delay threshold comes from the server too', (tester) async {
      await pump(tester, delayMinutes: 60);
      expect(find.textContaining('60 Minuten'), findsOneWidget);
      await pump(tester, delayMinutes: 90);
      expect(find.textContaining('90 Minuten'), findsOneWidget);
    });
  });

  group('what it promises', () {
    testWidgets('three months, never a year', (tester) async {
      // `rules.rs` sets the legal deadline three months after the ride and expires the case
      // itself. The old copy said "innerhalb eines Jahres", which is the railway's goodwill
      // window, not the one this app enforces — so it invited someone to miss their own deadline.
      await pump(tester);
      expect(find.textContaining('drei Monate'), findsOneWidget);
      expect(find.textContaining('Jahr'), findsNothing);
    });

    testWidgets('the reminder is only promised where it can arrive', (tester) async {
      // The 21-day warning travels as a push and the backend gates it on the notifications flag.
      await pump(tester, notifications: true);
      expect(find.textContaining('Wir melden uns rechtzeitig'), findsOneWidget);

      await pump(tester, notifications: false);
      expect(find.textContaining('Wir melden uns rechtzeitig'), findsNothing);
      expect(find.textContaining('nur mit Mitteilungen'), findsOneWidget);
    });

    testWidgets('the money goes to the named club, and the club can be unknown', (tester) async {
      await pump(tester, ngoName: 'Bahnhofsmission Köln');
      expect(find.textContaining('Bahnhofsmission Köln'), findsOneWidget);

      await pump(tester, ngoName: null);
      expect(find.textContaining('deinen Verein'), findsOneWidget);
    });
  });

  group('what issue #30 asked for', () {
    testWidgets('no Einchecken button', (tester) async {
      await pump(tester);
      expect(find.text('Einchecken'), findsNothing);
    });

    testWidgets('the walkthrough is still reachable — it is the only thing left to press', (tester) async {
      // antraege_screen.dart: the only way an App Store reviewer sees the claim flow at all.
      await pump(tester);
      expect(find.text('Vorführung ansehen'), findsOneWidget);
    });

    testWidgets('the tour’s handle survives', (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('antraege-empty')), findsOneWidget);
    });
  });
}
