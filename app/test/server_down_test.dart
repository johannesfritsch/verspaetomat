import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:verspaetomat/api/client.dart' show ApiException;
import 'package:verspaetomat/widgets/server_down.dart';

/// #28: when the Verspätomat cannot be reached, a screen says so instead of printing an exception.
///
/// The line that matters is the predicate: it decides which failures are "the house is shut" and
/// get the whole page, and which are "this one request was wrong" and keep the inline error. Get
/// it too wide and a legitimate 409 looks like an outage; too narrow and a 502 shows a stack trace.
void main() {
  group('a failure that means the house is shut', () {
    test('a gateway or a restarting container', () {
      expect(isBackendUnreachable(ApiException(502, 'Bad Gateway')), isTrue);
      expect(isBackendUnreachable(ApiException(503, 'Service Unavailable')), isTrue);
      expect(isBackendUnreachable(ApiException(500, 'boom')), isTrue);
    });

    test('no network, a refused connection, a dead name, a failed handshake', () {
      expect(isBackendUnreachable(http.ClientException('Connection refused')), isTrue);
      expect(isBackendUnreachable(const SocketException('Network is unreachable')), isTrue);
      expect(isBackendUnreachable(const HandshakeException('bad certificate')), isTrue);
    });

    test('a request that ran out of time', () {
      expect(isBackendUnreachable(TimeoutException('too slow')), isTrue);
    });
  });

  group('a failure that means this one request was wrong', () {
    test('stays an ordinary error', () {
      for (final status in [400, 404, 409, 412, 422, 429]) {
        expect(isBackendUnreachable(ApiException(status, 'nope')), isFalse, reason: '$status is not an outage');
      }
      expect(isBackendUnreachable(StateError('a bug of ours')), isFalse);
      expect(isBackendUnreachable(null), isFalse);
    });
  });

  testWidgets('the page blames nobody and promises nothing it cannot keep', (tester) async {
    var retried = 0;
    await tester.pumpWidget(MaterialApp(home: ServerDownScreen(onRetry: () => retried++)));

    expect(find.text('Gerade nicht erreichbar'), findsOneWidget);
    expect(find.text('Du hast nichts falsch gemacht.'), findsOneWidget);

    // The three sentences the drawn mockup had that this project cannot say. Nothing informs
    // anybody when the server is down — there is no alerting in the repo at all — so the page must
    // not claim a team is on it; and with no outbox, „nichts verloren" must be about what is
    // stored, never about a tap that did not arrive.
    for (final lie in ['informiert', 'arbeiten bereits', 'Telefon ist in Ordnung', 'später gesendet']) {
      expect(find.textContaining(lie), findsNothing, reason: 'the page must not claim: $lie');
    }

    await tester.tap(find.text('Erneut versuchen'));
    expect(retried, 1);
  });
}
