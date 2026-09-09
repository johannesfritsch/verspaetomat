# Verspätomat app — build brief for screens

Fully mocked showcase. No backend, no network, no real data. Every screen is reachable from the Showcase index (`/showcase`) and from the natural flow.

## Look: "Bahnhofsuhr"

The German station clock. Paper white, black grotesk, one red second hand. Precise, calm. The number is the design.

- Use only the tokens and widgets in `lib/theme/tokens.dart` and `lib/widgets/kit.dart`. Do not invent colours, radii or shadows.
- Colours: `VColors.paper` background, `VColors.ink` text, `VColors.ink2` secondary text, `VColors.rule` hairlines, `VColors.red` the single accent (the "+" before a delay, the second hand, progress dots, the one thick rule). `VColors.green` only for "pünktlich". No amber. No gradients. No shadows. No cards with rounded corners and coloured left borders.
- Type: Archivo everywhere via `VText` styles. Delays and euros in `VText.display` / `VText.number` with tabular figures. Everything else quiet.
- Rules instead of cards: sections are separated by a 1 px `VRule()` in `rule` grey; the one important break on a screen is a 2 px `VRule.red()`.
- Buttons: `VPrimaryButton` (black, 56 px, 4 px radius), `VGhostButton` (text only). Never more than one primary per screen.
- Hit targets 44 px minimum. Bottom sheets and one-thumb layouts.
- Copy is German, "du", short, dry. See docs/10-experience.md. Never angry, never "schon wieder".
- Numbers in copy use German formatting: `1,50 €`, `1.208.311`.
- The station clock (`VStationClock`) appears small in headers and large on the idle home screen. Its second hand pauses at twelve. Nowhere else is there animation except the arrival count-up.
- No emoji. Icons are `Icons.*` outlined, 20–24 px, ink colour, sparingly.
- No fake status bar, no fake keyboard.

## Behaviour

- State lives in `DemoState` (`lib/state/demo_state.dart`, a ChangeNotifier reachable via `DemoScope.of(context)`). Screens read from it and call its demo actions (`checkIn`, `simulateArrival`, `sendBundle`, `receiveReply`…). Do not add other state management.
- Mock data lives in `lib/mock/mock_data.dart`. Add to it if a screen needs more; keep it German and plausible.
- Routes are declared in `lib/router.dart`. Replace the placeholder for your screens; do not rename routes.
- Every screen must render without crashing in every `DemoState` phase.
- Small "demo controls" are allowed where the real world would take time (e.g. a "Ankunft simulieren" button on the ride screen), styled as `VDemoControl` so they read as showcase, not product.
