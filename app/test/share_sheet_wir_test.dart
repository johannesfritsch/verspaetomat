import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/screens/community/community_widgets.dart' show SwitchRow;
import 'package:verspaetomat/screens/share/share_lines.dart';
import 'package:verspaetomat/screens/share/share_sheet.dart';
import 'package:verspaetomat/state/demo_state.dart';
import 'package:verspaetomat/widgets/ticket.dart';

/// #50: the share sheet opened from Wir builds its card and its button; a sheet that throws
/// while building is what a release build shows as an empty box.
void main() {
  testWidgets('wir share sheet builds', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final session = Session(demo: DemoState(), prefs: prefs, apiUrl: '');
    await tester.binding.setSurfaceSize(const Size(375, 812));
    await tester.pumpWidget(RepoScope(
      session: session,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showShareSheet(
                  context,
                  lines: ShareLines.wir(minutes: 1234),
                  build: ({fahrgast, strecke, date, line}) => TicketData.wir(minutes: 1234, people: 3, line: line),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(Ticket), findsOneWidget);
    expect(find.text('Teilen'), findsWidgets);
  });

  testWidgets('#49: the portrait switch puts the card on a 9:16 sheet', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final session = Session(demo: DemoState(), prefs: prefs, apiUrl: '');
    await tester.binding.setSurfaceSize(const Size(375, 1400));
    await tester.pumpWidget(RepoScope(
      session: session,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showShareSheet(
                  context,
                  lines: ShareLines.mine(minutes: 1298),
                  build: ({fahrgast, strecke, date, line}) => TicketData.mine(minutes: 1298, rides: 41, line: line),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('1.298'), findsOneWidget, reason: 'the hero is grouped the German way');
    final boundary = find.byType(RepaintBoundary).evaluate().map((e) => e.renderObject!).whereType<RenderRepaintBoundary>();
    final before = boundary.map((b) => b.size).where((s) => s.width == 360).toList();
    expect(before.any((s) => s.height == 450), isTrue, reason: '4:5 by default');
    await tester.ensureVisible(find.text('Hochformat'));
    await tester.tap(find.descendant(of: find.widgetWithText(SwitchRow, 'Hochformat'), matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    final after = find.byType(RepaintBoundary).evaluate().map((e) => e.renderObject!).whereType<RenderRepaintBoundary>().map((b) => b.size);
    expect(after.any((s) => s.width == 360 && s.height == 640), isTrue, reason: '9:16 once switched');
  });
}
