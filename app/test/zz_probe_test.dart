import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/screens/claims/claims_widgets.dart';

void main() {
  testWidgets('LoadError without Scaffold', (t) async {
    await t.pumpWidget(MaterialApp(home: LoadError(error: 'boom', onRetry: () {})));
    final ex = t.takeException();
    // ignore: avoid_print
    print('PROBE_EXCEPTION: $ex');
  });
  testWidgets('LoadError via a pushed route (go_router style MaterialPageRoute)', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (c) => Scaffold(body: ElevatedButton(onPressed: () {
        Navigator.of(c).push(MaterialPageRoute(builder: (_) => LoadError(error: 'boom', onRetry: () {})));
      }, child: const Text('go')))),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    // ignore: avoid_print
    print('PROBE_EXCEPTION_2: ${t.takeException()}');
  });
}
