# Verspätomat app — build brief for screens

Fully mocked showcase. No backend, no network, no real data. Every screen is reachable from the Showcase index (`/showcase`) and from the natural flow.

## Look: cards on a cool page, and one red light

A screen is a cool grey page with white cards lifted off it. Where the app wants you to act, it puts red light under the thing you press. That glow is the signature of the whole design and nothing else in the app may invent one.

- Use only the tokens and widgets in `lib/theme/tokens.dart` and `lib/widgets/kit.dart` (which re-exports `surfaces.dart` and the rest). Do not invent colours, radii, shadows or sizes. The tokens for all four now exist — `VColors`, `VRadius`, `VShadow`, `VControl` — so there is no longer an excuse for a literal.
- **The palette is cool.** Every neutral has more blue than red. Nothing is black: the darkest ink and the hero board are both blue-blacks, and every neutral shadow is made of a slate navy, because a black shadow on a cool page reads as dirt.
- **There are two reds.** `VColors.red` is the deep one and means *do this* or *this is money*: the primary button, the check-in circle, an amount, a link. `VColors.redBright` is the lit one and means *this one*: today's bar in the week chart, the unread badge, the app mark. They are forty levels of green apart and one token cannot carry both.
- **A bar with no value in it is `VColors.track`, not a red tint** (issue #33). The week chart used to draw its unfilled days in `redTintMuted`, which made a quiet week look like a faint achievement; grey says *nothing here yet* and leaves the lit red to mean the one thing it means. An empty week draws seven full-height tracks rather than seven stubs, because a row of stubs reads as a hole in the page — and uniform, unlit, with the figure beside them at zero, they cannot be mistaken for values.
- **The podium is the fourth identity family.** Gold, silver and bronze (`podiumGold`,
  `podiumSilver`, `podiumBronze`) mark the first three places on a board. A place is who you are on
  that list, so this is identity like the hues below it — and it is held to the same rule: the metal
  is the disc under the numeral and never the type. They are muted into the tint band, so three
  quiet discs, not three medals.
- **The other hues belong to other people.** Teal, the two blues and the bright green identify an operator or a partner NGO. They never carry an app state. Colour is for identity; red and green are for meaning.
- **Green means good.** On time, and ready to file. It was narrower before and it is not any more — say what you mean with the label, not with the hue alone.
- Type: Archivo through the interface via `VText`, and Caveat in exactly one place — the four handwritten margin notes. A second face earns its place by doing a different job: those are asides, not interface. Figures use the tabular styles so a total does not jitter as it ticks up.

### The three surfaces, and nothing else

Where something has to stand out, it stands on one of exactly three surfaces:

- **The card** (`VCard`) — white, rounded 14, shadowed. The default. Anything that is a block.
- **The board** (`VBoard`) — the dark or the red hero, at most one per screen, for the figure the screen is about. It is the direct descendant of the departure board: the small-caps label above, the figure, the quiet caption below. Rounded now, and lit from underneath rather than ruled with a red hairline. **Home takes the dark one; Wir and Ich take the red.** The dark board is the one you meet first, and the red ones are the two screens that are about people — all of us, and you.
- **The panel** (`VPanel`) — a tinted block *inside* a card, for the one thing in it that the eye should reach first. No shadow, no border: the tint is the whole device.

**Nesting stops at two deep.** A card may hold a panel; a sheet may hold a card. Nothing inside a surface gets its own border, and the content lines up with the surface's own padding, so a screen has one left edge, not three. The design mockups break that rule inside the Anträge card and the app does not copy them.

**One left edge means the back arrow too.** A sub-screen puts the arrow on its own line above the title, and pulls its 44 pt box half a glyph left so the *arrow itself* lands on the gutter. Beside the title it forced a second edge at 52 pt for no reason anybody could see. Tabs gutter at 16 because cards carry their own padding on top; sub-screens gutter at 24, because prose with nothing around it at 16 runs the full width of the phone.

### Rules, sections, figures

- **Cards instead of rules.** Sections are separated by 12 pt of page. A hairline survives only *inside* a card, between the rows of one list (`VDivider`), and never after the last row — a line under the last row is a line under nothing, and it is what makes a list look like a form.
- A section heading is a small-caps label (`VEyebrow`) with no line under it. Standing on the page it is tracked wider than it is on a card, because it has nothing around it to hold it together.
- **A figure's slot is for figures.** On time is a green `+0`, never the word „pünktlich“: a word in a slot built for `+204` is a different width class and breaks the layout around it. It carries a sign now because it lives in a signed column and every row in that column carries one. „Ausfall“ has no figure to show, so it drops to the label size for its slot, or out of the pill entirely into a grey note under the route.
- Figures in pairs share one size, and that includes blocks stacked down a screen. A `FittedBox` over a hero style is **not** a size: it only ever shrinks, so what you see depends on how many digits the number has. Pick the size and keep the `FittedBox` as a net for the long ones.
- Numbers in copy use German formatting: `1,50 €`, `1.208.311`, `38 %` with the space.

### Controls

- `VPrimaryButton` is red, 44 pt, radius 12, and carries a red glow. **One primary per card**, not one per screen: a page of collected claims has a real action on each desk.
- `VTintButton` is the second tier — a filled tinted block, red ink on a red tint or ink on grey. `VGhostButton` is the third.
- **Hit targets are 44 pt minimum**, even where the mockups draw the control smaller. Two of them do; build the drawn size inside 44 pt of touch area.
- Icons are outlined in ink for navigation and disclosure, and **filled and coloured inside a tinted circle** (`VIconBadge`) when they name a block. That badge is the device the design uses instead of a section rule, so „sparingly“ no longer applies to it.
- **No emoji, and the design mockups are not an exception.** Ich's subtitle is drawn with a mockup that ends in a heart emoji; the app sets the words and draws the heart with `VHeartMark`. An emoji is somebody else's artwork rendered by somebody else's font, at a size and colour nobody here chose.
- **No third-party brand artwork.** The share sheet is drawn with a row of WhatsApp, Instagram and Messages icons. The app opens the system share sheet instead: it is the one place that knows what a person actually has installed, and it needs no trademarks in the bundle.
- The tab bar is a card the tabs stand on: rounded 14 at the top, a hairline, an upward shadow, and the faintest of gradients down it. The raised check-in circle is the one control with a real gradient.
- **A line badge has three looks and one colour rule.** The colour is always the line's class, cancelled or not, because colour on a line badge is identity: a cancelled S-Bahn is still an S-Bahn. `tint` is a line in a list. `solid` is the train a card is *about*, one per card. `dark` is the train in hand, and it sets a size larger because on a screen of tinted pills it is the one that reads as now.
- **A section header is either a heading or a label.** A heading (`heading: true`, full ink at title size) introduces a part of the screen you could have navigated to on its own — Ich's „Abzeichen". A small-caps label names the block directly under it — Wir's „VEREINE". Both are in the design; which one you reach for is that question, not taste.
- Bottom sheets and one-thumb layouts. Copy is German, „du“, short, dry. See docs/10-experience.md. Never angry, never „schon wieder“.
- **A chart shows the resolution the data has.** `VWeekBars` draws the seven days the design asks for, and it draws two columns when two is all there is. Widening the bars to fill the same block is honest; an empty slot waiting for an API is not. Nothing is picked out of a week where nothing happened.

### What survives, and what does not

The one red, in spirit. The tabular figures. The green nought. The station clock, in the five places it still has — Welcome, Permissions, Antrag, the nudge banner and the Showcase — with its second hand still pausing at twelve. The sub-screen header. The dry register. `VDemoControl`'s deliberately un-designed dashed box.

What went, and it is worth knowing what it cost:

- **The Fallblattanzeige.** The flaps, the hinge seam, the digits that stood still while their neighbours turned. It was the app's one piece of mechanical charm and the only thing that made a number on a screen feel like a station. `VTafelZahl` still exists and still works; it is simply not switched on. Try it on the new board before accepting the loss.
- **The Fahrkarte, inside the app.** The perforated silhouette survives in `widgets/ticket.dart` and on verspaetomat.de, where a shared object still means something. It is gone from the screens. That leaves the thing you post looking unlike the app you posted it from, which is a real cost and an open question, not a decision anybody has made.
- **The hairline as structure**, and with it `VRule.red`, the one important break a screen was allowed.
- **The warm paper.** `#F3F3F0` was chosen. `#F7F7F8` is not a nudge of it, it is the other temperature.

### Decisions taken on the way in

These were settled to unblock the work and each is one token or one flag to reverse.

| What | Taken | Why, and what it would cost to change |
|---|---|---|
| The typeface | Archivo stays | The mockups are not Archivo — their `i` has a round tittle where Archivo's is a hard square. Archivo was kept because it already has the footed `1` that makes a big figure read like a departure board, its x-height is closest to what the mockups measure, and it reaches w800 where the nearest alternative stops at w700. One line in `VText._a` to change. |
| The type sizes | The mockup sizes, corrected for Archivo | Archivo's cap height is 0.686 of the em, not the 0.72 the measurements assumed, so several sizes are a point larger than a ruler on the mockup would say. |
| The card radius | 14 outer, 10 panels, 12 buttons | The four mockups split two and two, at 14 and at 10. One radius of 12 everywhere would reproduce all four acceptably. |
| The red | `#D61316` | Anträge measures this and Home measures `#CE1F18`. This one also matches the check-in circle, the progress fills and the active tab labels on three files, so the other reads as render drift. |
| The Fallblattanzeige | Kept in code, switched off | See above. |

## Behaviour

- State lives in `DemoState` (`lib/state/demo_state.dart`, a ChangeNotifier reachable via `DemoScope.of(context)`). Screens read from it and call its demo actions (`checkIn`, `simulateArrival`, `sendBundle`, `receiveReply`…). Do not add other state management.
- Mock data lives in `lib/mock/mock_data.dart`. Add to it if a screen needs more; keep it German and plausible.
- Routes are declared in `lib/router.dart`. Replace the placeholder for your screens; do not rename routes.
- Every screen must render without crashing in every `DemoState` phase.
- Small "demo controls" are allowed where the real world would take time (e.g. a "Ankunft simulieren" button on the ride screen), styled as `VDemoControl` so they read as showcase, not product.

## Looking at what you built

`flutter test tools/preview_test.dart` renders single widgets to PNGs in `/tmp/verspaetomat-preview`, which is faster than driving the app to reach a screen, and it is the only way to see a state the demo never reaches — a journey with a change, an empty week, a note that was reported cut off.

Run `app/tools/fetch-preview-fonts.sh` once first. The bench has no network and `google_fonts` fetches at runtime, so without it every glyph falls back to the platform face, which has its own metrics and will lie to you about what fits. Material icons still draw as boxes there; that is the bench, not the app.

`app/tools/tour.sh` shoots the whole app in Demo mode and is what the website's screenshots come from.
