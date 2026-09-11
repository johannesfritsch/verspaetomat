# 22 — Giving up still earns patience, and four bits of tidying

Decided 11 September 2026 (Johannes, after build 12). Five items.

## 1. Giving up still counts for Geduldspunkte

docs/21 made "Ich gebe auf" cost the passenger everything: no claim *and* no points. Half of that was wrong. The claim hangs on arriving, so it is gone — that is the law. The Geduldspunkte are **our** currency, and they measure waiting, which really happened. Sitting 40 minutes on a platform before giving up is exactly the patience the app exists to honour.

- **`aufgegeben`**: the current leg is closed with the live delay at that moment, and the points follow `rules::points_for(delay, cancelled, false)` as everywhere else. **No incident, no claim** — the money rule is untouched.
- **`nicht_gefahren`**: no points. It never happened.
- The ride row stays `abandoned` and carries its `points`. Every sum of points must therefore count abandoned rides too: `customer_json`, `standing`, and the statistics behind Ich currently read `where status = 'arrived'`; they become `where status in ('arrived','abandoned')`. Grep for `sum(points)` and fix every one. Anything that sums *money* or builds bundles stays on `arrived` only.
- The arrival-side badge rules are not touched: giving up awards no badge.

Copy changes:

- The abort sheet's middle choice becomes: **Ich gebe auf** — `Zu viel Verspätung, ich fahre nicht mehr. Die Wartezeit zählt für deine Geduldspunkte, ein Anspruch entsteht nicht.`
- The closing card's first line becomes `Aufgegeben. +<n> Geduldspunkte für die Wartezeit.` and, beneath it, `Ein Anspruch entsteht nicht — die Entschädigung hängt an der Ankunft.` The Art. 18 block and the "Fährst du doch noch?" block stay as they are.
- History shows the points on an `aufgegeben` journey like any other.

## 2. The Rangliste tabs must not move the page

Switching "Meine Linie · Meine Stadt · Deutschland" swaps a `Loader` whose spinner is shorter than the board, so the page jumps and the scroll position lands somewhere else.

Load all three scopes **once**, together with the rest of Wir, and keep them in the screen's state. A tab switch then only re-renders rows that are already there: no loader, no height change, no scroll jump. Reserve the board area at the height of the largest of the three so even an uneven board count cannot reflow the page. Errors and the refresh path keep working; a failed scope shows its error line inside the reserved box.

## 3. Einstellungen loses everything that belongs to the workshop

In a **release** build (`kDebugMode == false`) these disappear completely:

- the `Backend` section with the mode choice and the health/`Prüfen` row,
- the `Vorführung` section (the "Offline simulieren" switch and the Showcase link),
- the footer `Verspätomat 0.1 · Vorführung · Alle Daten erfunden`.

In a debug build they all stay exactly as they are, because the tour and the local loop need them. The release footer is a single quiet line with the version and build number, nothing else.

## 4. The Anträge empty state has no box

The card from docs/21 §5 keeps its content and loses the border and the rounded corners: the title, "So läuft es:", the four numbered lines, the deadline caption and the button sit directly on the page, like any other section. Nothing else about it changes.

## 5. "Wo steigst du aus?": the stop list is the control

Today the screen shows a caption, a timeline, and an "Einchecken" button pinned to the bottom bar. Nothing says the timeline is what you are meant to touch, and the button sits nowhere near the choice it confirms.

- Every selectable stop gets a **radio mark** in front of it (`Icons.radio_button_checked` in red for the selected one, `Icons.radio_button_unchecked` in ink3 for the rest), left of the time column, so the list reads as a set of options at a glance. Stops before the boarding point keep their passed styling and no mark.
- The instruction above becomes `VText.bodyStrong` in ink: `Wo steigst du aus?` is already the eyebrow, so the line reads `Tipp auf deinen Ausstieg.` with the caption `Der übliche Halt ist vorgewählt.` underneath.
- **The button moves into the list.** The bottom bar goes. Directly under the selected stop's row, inside the timeline, an inline block appears: the ticket and operator caption, then the primary `Einchecken` button at full width. Selecting another stop moves the block to that row. The list scrolls the block into view when the selection changes.
- The same treatment applies to the "Zug wechseln" variant of this screen if it shares the widget.

## Tests

- Backend: a unit test that `aufgegeben` yields points and no incident, and that `nicht_gefahren` yields neither; a test that the points sum includes abandoned rides.
- Tour: `abbrechen-sheet` and `abbrechen-aufgegeben` re-shot with the new copy, `wir` (boards), `einstellungen` (debug build, unchanged), `antraege-empty` (no box), `exit-stop` (radio marks and the inline button).
- E2E: both scenarios keep passing.
