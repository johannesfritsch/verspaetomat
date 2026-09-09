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

## Demo controls

Buttons drawn with a dashed grey outline and a "Demo:" prefix stand in for the real world: simulate the next stop, an arrival with a chosen delay, the railway's reply. They are part of the showcase, not the product.

Fonts load from Google Fonts on first run and are cached afterwards; without a network the app falls back to the system font.
