# 29 — Ein Einchecken

Decided 11 September 2026 (Johannes, after the RB 53): *„Wouldn't the right solution be to have
only one Einchecken flow? … I see no benefit in these different flows, do you?"*

No. There were five ways to start a ride, and the bug that exposed them was only visible because
they disagreed with each other.

## How five happened

Nobody designed five. Each document added a way and none removed the one before it:

| | added | removed |
|---|---|---|
| before docs/17 | a departures board at a station, then „Wo steigst du aus?" | — |
| docs/17 | destination first: Wohin? → Welcher Zug? | nothing |
| docs/24 §1 | the three sheets, and pointed the Einchecken square at them | nothing |

So by build 17 the square ran the sheets, while **a station nudge and the Home station picker
still ran the pre-docs/17 board**, and the Home card's destination buttons went to a fourth thing
— a full-screen Welcher Zug. The two demo shortcuts made a fifth: they built a ride by hand out
of `departures` and a guessed exit stop, through `POST /v1/rides`.

That is how the Schienenersatzverkehr bug (docs/28) could be half-fixed and look finished. The
planner got the new rule; the departures board did not; the square found the RB 53 and the nudge
did not. **A feature with one code path cannot disagree with itself.**

## One way

`runCheckinFlow(from:, to:)` is the only entry, and it can be joined at any step:

| Entry | Starts at |
|---|---|
| Einchecken square | Von wo? — it asks even when the detection is right (docs/24 §1) |
| station nudge, away box, station search | Wohin? — the station is settled |
| the Home card's destination buttons | Welcher Zug? — both ends are settled |
| Weiterfahrt from the ride sheet (docs/21 §2) | Welcher Zug?, with the journey id and the delay ceiling |

Deleted, not deprecated: `checkin_screen.dart` (the board), `exit_stop_screen.dart`, `WohinScreen`,
`WelcherZugScreen`, and their four routes and route constants. `DestinationButton` and
`WelcherZugList` stay — the sheets use them. There is no full-screen train picker left, so there
is nothing for a sixth caller to find.

**The demo shortcuts go through the same path**: `demoStartJourney` → `planJourney` →
`startJourney`. A shortcut may skip the screens; it must not skip the path. Building a ride by
hand meant the showcase and the tour exercised code no passenger touches, and produced rides of
a shape the app no longer creates — coverage that proves nothing.

## And nothing legacy in the backend

`POST /v1/rides` was kept "for compatibility" by docs/17 and was, by the end, used only by those
demo shortcuts. It is gone, with `handlers::check_in`, its `CheckIn` body, and
`journeys::create_single_leg` — which existed only to wrap a legacy check-in into a one-leg
journey, and which the compiler declared dead the moment the route went.

One endpoint creates a ride: `POST /v1/journeys`. One client method calls it. One flow reaches it.

## The rule the feed reads through

The same lesson, one layer down. The SEV rule was applied at four call sites, each repeating
`parse_line` then the check — and the fifth reader would have forgotten, exactly as the departures
board did. There is now one gate, `feed_row_belongs(mode, route_short_name)`, which takes the raw
shape so no caller has to remember what to do first.

## What this costs

Builds 15 to 17 in TestFlight lose their **demo-mode** check-in shortcut, because it calls the
endpoint that is now gone. Real check-ins in those builds are unaffected: they already went
through `startJourney`. Build 18 fixes the demo path.

## Tests

- Both E2E scenarios and the tour, which between them now drive the only path there is.
- The tour list lost the screens that no longer exist; the flow's own `einchecken-*` shots cover
  what replaced them.
