import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
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
}
