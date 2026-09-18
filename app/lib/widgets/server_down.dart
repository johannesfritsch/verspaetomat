import 'dart:async';
import 'dart:io' show IOException;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api/client.dart' show ApiException;
import '../theme/tokens.dart';
import 'kit.dart';

/// True when a failure means *the house is shut*, not *this one request was wrong*.
///
/// Four families of failure reach a screen. [ApiException] carries the server's status; a 5xx is
/// in, because Caddy in front of a container that is not running answers 502 with an empty body
/// and a restarting one answers 503 — from the phone those are the same event as no network at
/// all. A 404, 409, 412 or 422 is out: that is one request being wrong, and it keeps the ordinary
/// inline error. Below HTTP, `package:http` wraps a socket failure in [http.ClientException], but
/// a TLS handshake failure is not wrapped and arrives as a bare [IOException], so the IO family is
/// matched as a whole rather than by name. A request that ran out of time is a [TimeoutException].
bool isBackendUnreachable(Object? e) =>
    (e is ApiException && e.status >= 500) || e is TimeoutException || e is http.ClientException || e is IOException;

/// The page a screen shows when the Verspätomat cannot be reached (#28).
///
/// It is deliberately not an error message with a stack trace in it. Nothing here is the
/// passenger's doing, so the page says so and offers the one thing that helps.
///
/// Every line is held to what the app can actually know, which cost the drawn mockup three of its
/// sentences. **It does not say „unser Team ist informiert"**: there is no alerting, no uptime
/// check and no error reporting anywhere in this project, so nothing informs anybody, and for the
/// same reason it cannot say „wir arbeiten bereits daran". **It does not say the phone is fine**:
/// this fires identically for flight mode, a hotel's captive portal and a dead gateway, and the
/// app has no way to tell them apart — „du hast nichts falsch gemacht" is true in all three.
/// **It does not say a check-in will be sent later**: there is no outbox and no queue, a call that
/// does not arrive simply did not happen, and only what is already stored is safe.
class ServerDownScreen extends StatelessWidget {
  const ServerDownScreen({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return VScreen(
      eyebrow: 'Störung',
      title: 'Gerade nicht erreichbar',
      bottom: VPrimaryButton(label: 'Erneut versuchen', icon: Icons.refresh, onTap: onRetry),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.s(),
          // Johannes' drawing for this page (#28). It carries its own alpha, because its white is
          // a hair brighter than the paper and an opaque rectangle would show its own edge.
          Center(
            child: Image.asset(
              'assets/header/stoerung.webp',
              height: 220,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              // An asset that failed to decode must not take the page down with it: the whole
              // point of this screen is to be the thing that still works when nothing else does.
              errorBuilder: (_, __, ___) => const VStationClock(size: 96, animated: true),
            ),
          ),
          const VGap.l(),
          Text(
            'Wir erreichen den Verspätomat im Moment nicht. Das kann an unserem Server liegen oder an deiner '
            'Verbindung — von hier aus sieht beides gleich aus.',
            style: VText.body.copyWith(color: VColors.ink2),
          ),
          const VGap.xl(),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Reassurance(
                icon: Icons.sentiment_satisfied_outlined,
                title: 'Nicht dein Fehler',
                line: 'Du hast nichts falsch gemacht.',
              ),
              _Reassurance(
                icon: Icons.inventory_2_outlined,
                title: 'Nichts ist weg',
                line: 'Fahrten, Anträge und Punkte sind gespeichert.',
              ),
              _Reassurance(
                icon: Icons.schedule,
                title: 'Gleich noch einmal',
                line: 'Versuch es in ein paar Minuten wieder.',
              ),
            ],
          ),
          const VGap.l(),
        ],
      ),
    );
  }
}

/// One of the three columns: the glyph in its tinted circle, a bold line, a quiet one.
class _Reassurance extends StatelessWidget {
  const _Reassurance({required this.icon, required this.title, required this.line});

  final IconData icon;
  final String title;
  final String line;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: VSpace.xs),
        child: Column(
          children: [
            VIconBadge(icon: icon, size: VControl.badge),
            const VGap.s(),
            Text(title, style: VText.bodySStrong, textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(line, style: VText.caption, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
