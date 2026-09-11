# 24 — Source first, changing trains mid-journey, and a way to be left alone

Decided 11 September 2026 (Johannes, after riding with build 13). Three things.

## 0. One station source, and it keeps up with the train

Travelling from München without being checked in, the Einchecken card kept offering a München station for the whole journey. Two causes, both worth fixing properly.

**The position is fetched once and never again.** `bahnsteig_screen.dart` holds `_position` and reads it as `_position ??= await currentPosition(...)`, so the first fix of the screen's life is the only one. It is cleared only by a Stellwerk-simulated location event, never by the phone actually moving.

**Home and the check-in disagree.** `startCheckin` in `checkin_launcher.dart` asks for its own position and its own nearby list. Two independent answers to the same question, which is how Home and the Einchecken square can name different stations.

**The fix is one shared, live source.** A `NearbyMonitor` (`ChangeNotifier`, owned by the tab shell exactly like `RideMonitor`) holds the position, the ranked stations from docs/23 §1, when they were resolved, and the error. Home, the Einchecken flow and the away box all read it; nothing else calls `currentPosition` for a station. It refreshes on:

- start, and whenever the app returns to the foreground;
- a foreground position stream (`LocationAccuracy.low`, `distanceFilter: 500`) whenever the phone has moved more than 500 m from the last resolved fix, with a floor of 60 s between resolves so a moving train cannot spam the API;
- the native umbrella exit, which already fires after 8 km and already queries `nearby` (docs/15) — it now also tells Dart, through a new `umbrellaExit` event on the geofence channel, so a card that was backgrounded across half of Germany is right the moment it is seen again;
- the existing Stellwerk `location` event.

A fix older than 5 minutes is stale: the card shows `Standort wird geprüft …` rather than the old station (docs/23 §1). The stream is suspended while a journey is running, because Home hides the card then anyway, and while the app is backgrounded.

**Moving fast.** When the last two fixes imply more than 30 km/h, the card's caption becomes `Du bewegst dich · Bahnhof wird laufend geprüft` instead of `Du bist hier · 120 m`. The station still updates and still works; the caption just stops pretending it is a settled fact.

## 1. The check-in asks where you are before it asks where you are going

Today the source station is a fact the app asserts and the passenger can only accept. When the detection is wrong (docs/23 §1) there is no way through the flow at all.

**The Einchecken square** now always runs three steps, each a bottom sheet over the current tab:

1. **Von wo?** — the detected station preselected at the top with its distance, the next two candidates beneath it, then the search field. One tap moves on; the passenger never has to type when the detection is right.
2. **Wohin?** — as today: destinations from history, then the search.
3. **Welcher Zug?** — the itineraries, **as a bottom sheet** rather than a full screen, so a wrong choice above is one swipe away instead of a back-navigation.

Each step shows what the previous one settled as a small tappable breadcrumb (`Ab München Hbf ▾`), so any of them can be reopened without starting over.

**The Home card** keeps its one-tap path for the common case, but the source stops being an assertion. It becomes the card's first row, styled as a field and not as a label:

```
Von    München Hbf · 120 m        ▾
Nach   [ Nach Hause · Bonn Hbf  → ]
       [ Düsseldorf Hbf         → ]
       [ 🔍 Wohin?                ]
```

Tapping the `Von` row opens step 1 above. So a commuter still checks in with one tap on their destination, and a passenger whose station was guessed wrong fixes it in one tap without leaving Home. The `Nicht hier?` chip line from docs/23 §1 is replaced by this row, which says the same thing better.

## 2. Changing trains mid-journey

A journey is one ride, so a passenger who gets off and takes another train has no way back in. The machinery already exists (`replan` from docs/21 §2), it is only hidden behind "Falscher Zug?", which reads like an error report.

The ride sheet gets **one** clearly named action, `Zug wechseln`, which opens the Welcher-Zug bottom sheet from the current position to the unchanged destination. What it does on confirm is decided by the app, not by asking:

- The passenger has **not passed a stop yet** and picks a train from the same boarding station: the current leg is **replaced**. It was a mis-tap, nothing happened, no points and no `earliest_onward_arrival`.
- Otherwise: the current leg **ends** as in docs/21 §2 (it keeps its Geduldspunkte per docs/22 §1) and the chosen train becomes the next leg. The delay ceiling from docs/21 applies, so a train later than the earliest onward one does not inflate the claim.

`Falscher Zug?` disappears as a separate action. The destination never changes here; changing that is an abort plus a new check-in, and the sheet says so in a caption.

## 3. Ruhe: snoozing the station nudge

Travelling without the app means a nudge at every station the geofence knows. There is a per-station mute already ("Köln Hbf bleibt still"); this is the time-boxed global one.

- `customers.nudge_snooze_until timestamptz` (migration 0025), returned in `me` and settable through the existing settings patch.
- Reachable in two places: a row in Einstellungen, `Benachrichtigungen pausieren`, and directly from the nudge notification itself as an action, because that is the moment the passenger wants it.
- The sheet offers Johannes' ladder and one open-ended choice: **1, 2, 3, 5, 8, 24 Stunden** and `Bis ich sie wieder einschalte`.
- While a snooze runs, the geofence layer is configured with `enabled: false`, so nothing is scheduled and no notification can fire. The app reconfigures when the snooze expires or is lifted.
- The Home header carries one quiet line while it lasts: `Stumm bis 18:40 · aufheben`, tapping it lifts the snooze. That is the only place it is advertised, so it can never be forgotten silently.
- Ride and claim pushes are **not** affected. Someone who is not checked in gets none of those anyway, and someone who is checked in asked for them.

## Tests

- Tour: `bahnsteig-unterwegs` (the moving caption), `einchecken-von` (step 1), `einchecken-zug-sheet` (the itineraries as a sheet), `bahnsteig` with the Von/Nach card, `zug-wechseln`, `ruhe-sheet`, `bahnsteig-stumm` (the header line).
- E2E: the direct scenario now goes through the three steps; the connection scenario additionally changes train once through `Zug wechseln` and checks that the leg was replaced, not ended, when nothing had been passed.
- Backend: a unit test that a snooze in the future suppresses the nudge configuration, and one for the replace-vs-end decision in `replan`.
