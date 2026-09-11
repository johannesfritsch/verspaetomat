# 26 — Reading the ride, and sheets that let go

Decided 11 September 2026 (Johannes, from build 15 on a real phone). Four things, one of them a
bug that had been there since sheets existed.

## 1. Home stops ranking anyone

Home carried a level and a countdown: `Bahnsteigkante · 180 bis „Wartehäuschen“`, under a
progress bar. It goes.

The level is not wrong — it is on Ich, where docs/20 §5 put it, and it stays there. But Home
answers "what is happening now" and "what did this week come to", and a rank with a distance to
the next rank is a third conversation that neither needs. It also quietly reframes the week's
Geduldspunkte as progress towards a title rather than as minutes somebody waited.

Home keeps `+96 Geduldspunkte diese Woche · letzte Woche 41`. Nothing else changes.

## 2. A sheet you cannot pull down is a trap

Opening a ride that is not in an Antrag gives a sheet taller than the screen. It scrolled
inside, and it could not be pulled down — the only way out was a few pixels of header above the
list, or the back gesture.

The cause is not the sheet, it is iOS scroll physics. `showVSheet` puts the content in a
`SingleChildScrollView`, which on iOS gets `BouncingScrollPhysics`; a drag at the top of the
list becomes that list's own overscroll bounce and never reaches the sheet. On Android, where
clamping is the default, the same sheet always worked. This affected **every** long sheet in the
app, not only this one.

- The sheet's scroll view uses `ClampingScrollPhysics`. Refusing the overscroll hands the drag
  back to the sheet, so the whole thing pulls down from anywhere in the content.
- The header is a handle: a downward flick anywhere on it closes the sheet.
- The grabber gets a real tap target — 36 × 4 pixels is the smallest thing on screen, and it was
  also the only thing to aim at. Tapping it closes the sheet too.

## 3. "Dein Zweck" on Ich opens the choice

The row under **Mehr** led to the Zweck's own page, whose action is `Trotzdem spenden` — an
invitation to give money directly, which is the right thing to offer beside a claim that came to
nothing and the wrong thing to offer someone who tapped a row labelled with their own choice.

It now opens the same picker sheet Einstellungen opens, so the row changes the Zweck. The Zweck
page and its `Trotzdem spenden` stay where they are, reached from a claim.

## 4. The ride reads as one journey

The stop list in the ride sheet showed the whole trip of the train the passenger is on — every
stop, including the ones it called at before they got on — and stopped at the change. The second
train was a single line of text with no stops at all.

A journey is what the passenger is doing, not what the train is doing:

- **Stops before boarding are not drawn**, and neither are the ones past the exit. They are the
  train's journey, not the passenger's: before they got on it was somewhere else, and after they
  get off it carries on without them. On a journey with a change, the stops beyond the Umstieg
  are actively misleading — the real continuation is the next train, further down the page.
- The boarding stop is marked **Zustieg**.
- The stop where the trains change is marked **Umstieg**, on both sides of the change.
- **The next train's stops are drawn too**, under its own Umstieg, so the whole journey runs down
  the page as one line.
- The last stop is marked **Ziel**, in red — it is the only stop the money depends on (docs/17).

`ApiLeg` carries only its endpoints, so the second train's stops come from its trip. Until that
arrives, the endpoints alone still say where the passenger gets on and off, which is the part
that matters; the list fills in rather than blanking.

## Tests

- Tour: `sheet-riding` with the new timeline, `unterwegs-transfer`, `historie-loeschen` (the
  sheet that started this), and `bahnsteig` without the rank line.
- On a phone: the journey sheet pulls down from the middle of its content.
