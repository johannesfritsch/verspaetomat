# 14 — Where is the customer? The location concept

The one promise printed in the app: *Dein Standort bleibt am Bahnhof.* Everything below follows from it.

## Source of truth: the phone, at three moments only

| Moment | What we read | Why | Stored? |
|---|---|---|---|
| Opening the Bahnsteig | one position fix | list stations nearby, show the nudge when a station is within 300 m | no |
| Checking in | one position fix | mark the ride "verified" for the boards (within 500 m of the from-station) | lat/lon on the ride only |
| During the ride | nothing | the server follows the train, not the phone | — |

No continuous tracking, no location history, no background location in this version. The background geofence nudge is a later, separate decision (docs/06).

## The server never guesses

`GET /v1/stations/nearby` answers only from what it is given:

- phone coordinates → stations near them, `source: "gps"`
- a Stellwerk override for this customer → stations near that, `source: "stellwerk"`, with the label
- neither → `source: "none"` and an empty list

There is no default station. A fresh install with location denied sees the search field, not Köln Hbf.

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
stellwerk locate Johannes "Köln Hbf"      # by station name (geocoded through Transitous)
stellwerk locate Johannes 50.943,6.9586   # by coordinates
stellwerk locate Johannes --clear         # the phone decides again
stellwerk reset Johannes                  # also clears the location
```

The override lives in `sim_customer_location`, one row per customer, and applies only to "nearby stations" and the nudge. It does not touch check-in verification. Admin routes are never exposed publicly, so production has no override path at all.

## Simulator note

`xcrun simctl location set` fakes the operating system's GPS on the iOS simulator. It works, but it is invisible to the app and to the Stellwerk. Prefer `stellwerk locate`, which is visible in the app as a caption and clears with `reset`.

## Privacy summary

Coordinates leave the phone only as a query parameter for nearby stations and, at check-in, as the verification fix stored on that ride. Nothing else stores or derives position. The Datenschutz-Folgenabschätzung in docs/05 should describe exactly this and nothing more.
