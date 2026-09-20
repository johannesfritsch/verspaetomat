# 14 — Where is the customer? The location concept

The one promise printed in the app: *Dein Standort bleibt am Bahnhof.* Everything below follows from it. It is the goal, not yet a description: the foreground reached it with #39, the background layer has not.

## Source of truth: the phone, and where each fix goes

| Moment | What we read | Where it goes | Stored? |
|---|---|---|---|
| App open, not riding | a low-accuracy stream reporting every 500 m (`nearby_monitor.dart:38,142-144`), plus a fresh fix at start, on resume and on any forced refresh | since #39, nowhere: the nearby list and the station search are answered from the extract on the phone | no |
| Checking in | one position fix | `POST /v1/journeys`, `from_lat`/`from_lon` | lat/lon on that ride only — and the geofence set is built from it (`handlers.rs:422`) |
| Entering a station region, app closed | iOS: up to six minutes of fixes (`nearWatchWindow`, `Geofence.swift:64`). Android: one fix after the platform's three-minute dwell (`GeofenceManager.kt:61,205`) | nowhere | no |
| Leaving the covered area, app closed | one fix | **still `GET /v1/stations/nearby`** — the native layer is not part of #39 | no |
| During the ride | nothing of its own | the server follows the train, not the phone — but the line above keeps firing, because `riding` suppresses the nudge and not the lookup | — |

No location history in the database. The background nudge (decided 10 September 2026) uses the
operating system's region monitoring, not location updates: see [15-geofence.md](15-geofence.md).

**What is not yet true.** docs/25 measured fourteen background lookups in fifty-nine minutes on one
journey. #39 took the foreground off the wire; the native layer still asks, so a phone still reports
where it is while nobody is looking at it. That is the next issue, and until it lands the
Datenschutzerklärung says so in as many words.

## The server never guesses

`GET /v1/stations/nearby` answers only from what it is given:

- phone coordinates → stations near them, `source: "gps"`
- a Stellwerk override for this customer → stations near that, `source: "stellwerk"`, with the label
- neither → `source: "none"` and an empty list

There is no default station. A fresh install with location denied sees the search field, not Köln Hbf.

Since issue #37 the answer is computed from our own `stations` table (docs/44) rather than by
asking Transitous. Two things follow, and both are worth saying plainly:

- **The coordinates stop at us.** They used to be forwarded to `api.transitous.org` as part of the
  lookup. They are not any more. Nothing outside this server ever sees where the passenger is.
- **There is no live fallback.** If the table has no station near a point, the honest answer is
  that there is none. A fallback would have fired hardest in the rural places a sparse answer is
  the correct one for, and would have put the coordinates back on the wire for exactly the people
  least able to notice.

The station search is the same story: `GET /v1/stations/search` reads the table, so a station name
typed into the `Von` row no longer leaves the server either.

## What the customer sees

| State | Bahnsteig shows |
|---|---|
| Permission granted, station within 3 km | nearby stations as chips with distances; the nudge banner if one is within 300 m |
| Permission granted, nothing within 3 km | "Kein Bahnhof in der Nähe." and the search field |
| Permission denied or not asked | the search field first, the home station as a chip once known ("Dein Stammbahnhof"), and a quiet "Standort erlauben" link |
| Location services off | same as denied |
| Stellwerk override active | stations near the simulated point, plus a caption under the list: "Standort: Stellwerk · Köln Hbf". A simulated position is never mistaken for a real one. |

The home station is derived server-side from the customer's most frequent check-in station, updated with each ride.

## Verified rides

A ride is `location_verified` only when the phone's own fix at check-in lies within 500 m of the from-station. A Stellwerk override never verifies a ride. Unverified rides earn points and claims like any other; they just do not rank on boards. Boards stay honest even while someone is testing.

## Stellwerk

```
stellwerk locate Johannes "Köln Hbf"      # by station name (from our own table since #37)
stellwerk locate Johannes 50.943,6.9586   # by coordinates
stellwerk locate Johannes --clear         # the phone decides again
stellwerk reset Johannes                  # also clears the location
```

The override lives in `sim_customer_location`, one row per customer, and applies only to "nearby stations" and the nudge. It does not touch check-in verification. Admin routes are never exposed publicly, so production has no override path at all.

## Simulator note

`xcrun simctl location set` fakes the operating system's GPS on the iOS simulator. It works, but it is invisible to the app and to the Stellwerk. Prefer `stellwerk locate`, which is visible in the app as a caption and clears with `reset`.

## Privacy summary

Coordinates leave the phone at two moments: at check-in, as the verification fix stored on that
ride, and — with the app closed — on the native layer's `GET /v1/stations/nearby`, which #39 did
not touch. The foreground stopped sending them with #39. Nothing stores or derives a position
beyond the ride's own fix, and nothing outside this server sees one at all since #37.

The Datenschutz-Folgenabschätzung in docs/05 should describe exactly this and nothing more — and
docs/05:16 still says "location at two moments" in the old sense, which was already wrong before
any of this and is on the list with the rest of the copy (#38).
