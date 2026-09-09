# Verspätomat — showcase app

A fully mocked Flutter app. No backend, no network, no real data. Every screen from `docs/11-screens.md` is reachable from the Showcase index that the app opens on.

## Run

```bash
cd app
flutter pub get
flutter run -d "iPhone 15 Pro"      # or any simulator / device / chrome / macos
```

Open a specific screen directly (handy for screenshots):

```bash
flutter run -d "iPhone 15 Pro" --dart-define=INITIAL_ROUTE=/angekommen?variant=68
```

Route names live in `lib/router.dart`.

## Structure

```
lib/
  main.dart               app entry, DemoScope + router
  router.dart             all routes, the four-tab shell
  theme/tokens.dart       colours, spacing, type (Archivo via google_fonts)
  theme/app_theme.dart    ThemeData
  widgets/kit.dart        the widget kit: VScreen, VRule, VPrimaryButton, VDelay, VStationClock…
  mock/mock_data.dart     models and all invented data (stations, trains, ledger, NGOs, badges, mails)
  state/demo_state.dart   one ChangeNotifier holding the showcase state and demo actions
  screens/
    showcase_screen.dart  the index of every screen
    onboarding/           Willkommen, Berechtigungen, Setup
    ride/                 Bahnsteig, Einchecken, Ausstieg, Unterwegs, Angekommen, Nachtrag
    claims/               Konto, Antrag (5 Schritte), Antwort, Zweck
    community/            Wir, Team, Ich, Historie, Einstellungen, Datenherkunft
```

`STYLE.md` is the build brief for the "Bahnhofsuhr" look. The design canvas with the chosen direction and the two alternatives is linked from the session that produced it.

## Stellwerk

In local mode the app carries no simulate buttons. The world is driven from the backend's signal box, a small CLI:

```bash
cd backend
cargo run --bin stellwerk -- customers          # who exists, who is riding
cargo run --bin stellwerk -- watch Johannes     # live view of a customer's ride
cargo run --bin stellwerk -- delay Johannes +25 # add 25 minutes to the current trip
cargo run --bin stellwerk -- ff Johannes        # fast-forward: exit stop reached, ride finalised
cargo run --bin stellwerk -- reply Johannes --accepted   # the railway answers (--question, --rejected)
cargo run --bin stellwerk -- clock +100d        # move the system clock: deadlines, expiry
cargo run --bin stellwerk -- reset Johannes     # wipe that customer's rides, claims, mails
```

The app polls the backend and shows whatever the Stellwerk made true: the delay grows on Unterwegs, the reveal appears on arrival, the ledger turns "bestätigt" after a reply.

Demo mode (built-in data, no backend) keeps its own dashed "Demo:" buttons for the same moments, so the showcase works on a plane.

Fonts load from Google Fonts on first run and are cached afterwards; without a network the app falls back to the system font.
