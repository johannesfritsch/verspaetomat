# Verspätomat app — build brief for screens

Fully mocked showcase. No backend, no network, no real data. Every screen is reachable from the Showcase index (`/showcase`) and from the natural flow.

## Look: "Bahnhofsuhr"

The German station clock. Paper white, black grotesk, one red second hand. Precise, calm. The number is the design.

- Use only the tokens and widgets in `lib/theme/tokens.dart` and `lib/widgets/kit.dart`. Do not invent colours, radii or shadows.
- Colours: `VColors.paper` background, `VColors.ink` text, `VColors.ink2` secondary text, `VColors.rule` hairlines, `VColors.red` the single accent (the "+" before a delay, the second hand, progress dots, the one thick rule). `VColors.green` only for "pünktlich". No amber. No gradients. No shadows. No cards with rounded corners and coloured left borders.
- Type: Archivo everywhere via `VText` styles. Delays and euros in `VText.display` / `VText.number` with tabular figures. Everything else quiet.
- **A figure's slot is for figures.** On time is a green `0` (`VDelay`), never the word „pünktlich“: a word in a slot built for `+204` is a different width class and breaks the layout around it — on Home it took the whole row and left the station name one letter per line. A word that must stand there („Ausfall“) drops to the label size for that slot.
- Figures in pairs share one size, and that includes blocks stacked down a screen. A `FittedBox` over a hero style is **not** a size: it only ever shrinks, so what you see depends on how many digits the number has — `1.208.473` came out at 65 px and `+60` at 168 px from the same line of code. Pick the size and keep the `FittedBox` as a net for the long ones.
- Rules instead of cards: sections are separated by a 1 px `VRule()` in `rule` grey; the one important break on a screen is a 2 px `VRule.red()`.
- **Two surfaces, and nothing else (docs/33).** A screen is paper with rules on it; where
  something has to stand out, it stands on one of exactly two surfaces:
  **the Fahrkarte** (`VFahrkarte`) for one journey or one claim — the check-in, the ride, the
  arrival, an Antrag, the till that collects them — and
  **the Tafel** (`VTafel`) for the numbers that belong together at one glance — what we all
  waited, what your week came to, what you have collected. A Tafel comes in two looks (docs/34):
  `VTafelLook.anzeige` is the departure board — black, white flaps with the hinge seam across
  them, a red hairline under the row — and there is **at most one per screen**, for the figure
  the screen is about; `VTafelLook.papier` is the quiet one, elevated paper with a hairline and
  a 4 px radius, for everything under the fold. Home, Wir and Ich use the same pair. Everything else — lists, rows, badges, settings, explanations — has no surface, **except on Wir and Ich** (docs/37): those two are overview screens, and there every block stands on a Tafel with its section label outside it. A list on a card keeps an 8 px gutter, not 16.
  **A surface never contains another surface**, and nothing inside one gets its own border: the
  content lines up with the surface's own padding, so a screen has one left edge, not three.
- A figure on a Tafel sets itself like a Fallblattanzeige (`VTafelZahl`): the digits that
  changed flip over to their new value, left to right, running through the ones in between. On
  the Anzeige each digit sits on its own flap; on paper the digits are bare.
  Digits that did not change stand still, so a total ticking up moves only its last flap. This is
  the third and last animation in the app.
- **The Fahrkarte, in detail.** `VFahrkarte` is white paper whose top and bottom edge the perforator bit into, a hairline down each side, no radius and no shadow — the same silhouette as the hero on verspaetomat.de and as the shareable card in `widgets/ticket.dart`, down to the 5 px tooth every 14 px (`VTicketBorder`). It is for **one journey or one claim**: the ride under way, the arrival, an Antrag, the open till, the check-in about to start. A week of numbers, a settings group, a choice, the Deutschlandticket mock — those are rows and rules, never this shape. `strong: true` is the one card on a screen that is the open till; its side lines go to ink.
- Buttons: `VPrimaryButton` (black, 56 px, 4 px radius), `VGhostButton` (text only). Never more than one primary per screen.
- Hit targets 44 px minimum. Bottom sheets and one-thumb layouts.
- Copy is German, "du", short, dry. See docs/10-experience.md. Never angry, never "schon wieder".
- Numbers in copy use German formatting: `1,50 €`, `1.208.311`.
- The station clock (`VStationClock`) appears small in headers and large on the idle home screen. Its second hand pauses at twelve. Nowhere else is there animation except the arrival count-up and the flaps on a Tafel (`VTafelZahl`).
- No emoji. Icons are `Icons.*` outlined, 20–24 px, ink colour, sparingly.
- No fake status bar, no fake keyboard.

## Behaviour

- State lives in `DemoState` (`lib/state/demo_state.dart`, a ChangeNotifier reachable via `DemoScope.of(context)`). Screens read from it and call its demo actions (`checkIn`, `simulateArrival`, `sendBundle`, `receiveReply`…). Do not add other state management.
- Mock data lives in `lib/mock/mock_data.dart`. Add to it if a screen needs more; keep it German and plausible.
- Routes are declared in `lib/router.dart`. Replace the placeholder for your screens; do not rename routes.
- Every screen must render without crashing in every `DemoState` phase.
- Small "demo controls" are allowed where the real world would take time (e.g. a "Ankunft simulieren" button on the ride screen), styled as `VDemoControl` so they read as showcase, not product.
