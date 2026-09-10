# 19 — The ride as a sheet, and four smaller fixes

Decided 10 September 2026 (Johannes, after build 8).

## 1. Home loses "Deine Anträge"

The cycle strip and its status line leave Home; they live on Anträge (and the badge on the tab). Home below the card is now: **Deine Woche**, then **Wir**.

## 2. "Wir" on Home: visual and prominent

A block, not a line: the community's minutes as a large ticking figure in the display style (`1.208.316`, caption `Minuten haben wir gewartet`), beneath it a thin bar whose filled part is the customer's share with the caption `1.372 davon deine` (the bar is illustrative: the share is tiny, so draw the filled part with a minimum of 6 px and say so nowhere). Paper-elevated background, hairline border, the whole block tappable → Wir. It sits where the strip was, so it is the second thing after the card.

## 3. The start station must read as the start

- At a station, the card's eyebrow reads `Ab Köln Hbf` above the destinations, and the first row of the away box gets the section label `Startbahnhof` instead of `Einchecken`.
- The away box title becomes `Von wo fährst du los?` (with position, no station near: `Kein Bahnhof in der Nähe · von wo fährst du los?`; without position: `Wo bist du?` stays as the caption line, the title stays `Von wo fährst du los?`).
- Every chip in the away box reads `Ab <name>` (`Ab Köln Hbf · Stammbahnhof`).
- On Wohin? the eyebrow already says `Ab Köln Hbf`; keep it.

## 4. Welcher Zug?: hierarchy

- The instruction line becomes `VText.bodyStrong` in ink, one sentence: `Tipp auf den Zug, in dem du sitzt.` and a caption under it: `Umstiege folgen später von selbst.`
- Every itinerary row ends with a chevron (`Icons.chevron_right`, ink2) after the delay column; the row is one tap target with a pressed state.
- The preferred itinerary is the first and gets the caption `nächste Verbindung` (already present as a chip: keep the chip).

## 5. The ride as a sheet with a persistent bar

While a journey is `riding` or `transfer`:

- **The bar**: a persistent strip docked directly above the bottom nav on every tab (part of the tab shell, not of a screen). Contents on one line: the line badge, `nach Rheine`, the live delay as a small VDelay (or `pünktlich`), and on the right the next stop with its time (`Solingen Hbf 10:06`). In `transfer`: the badge of the next train, `Umsteigen in Hagen Hbf`, and a small ink button `Ich bin drin`. Tapping the bar (anywhere except the button) opens the sheet. Paper-elevated background, hairline top border, 56 px high, safe-area aware. It is not shown while the sheet is open.
- **The sheet**: the Unterwegs content (line, headsign, big delay, the stop list with passed/next/exit, the transfer card, "Zug wechseln", "Ich bin da", "Abbrechen") in a draggable bottom sheet (initial 0.92 of the screen, min 0, snap points 0.92 and 0.5; dragging below 0.3 closes it and the bar reappears). A grab handle at the top, the header pattern below it (`Unterwegs` caption + `RE 7 nach Rheine` h2). It opens over whatever tab is active, so pulling it down returns to that tab.
- **Opening**: tapping the bar; a check-in completing (Welcher Zug? → the sheet opens on Home automatically); the `/unterwegs` route (pushes, the geofence nudge) opens Home with the sheet. The Unterwegs screen file is reused as the sheet body; the route stays for deep links.
- **Home while riding**: block 1 (the action) is not shown; the arrival card stays for `arrived`. The bar is the ride's only presence on Home.
- **Arrival**: when the journey arrives while the sheet is open, the sheet body switches to the arrival content (the Angekommen screen's body); the bar disappears. When it arrives while the sheet is closed, the bar is replaced by the arrival card on Home as today, and a tap on the bar's last state is not needed.
- Demo mode: the demo controls (`Nächster Halt`, `Ankunft +68`) stay at the bottom of the sheet body.

## Tests

- Screenshot tour: `bar-home`, `bar-antraege` (the bar on another tab), `sheet-riding`, `sheet-half`, `bar-transfer`.
- Workflow E2E: after check-in the test currently waits for `UNTERWEGS` on the Bahnsteig; it now waits for the bar's headsign text, opens the sheet by tapping the bar, then continues (Stellwerk ff → arrival). The connection scenario confirms the transfer through the bar's `Ich bin drin` button or the sheet's card, whichever it finds first.
