# 17 — Journeys: destination first, legs confirmed one tap at a time

Decided 10 September 2026 (Johannes). Passenger rights compensate the delay at the **final destination of the journey**, not per train. Today the app measures each train at its exit stop, so two 25-minute legs with a missed connection and a 70-minute late arrival produce nothing, and the form's "Zielbahnhof" is the first train's exit stop. This document turns rides into legs of a journey.

Two choices made: **destination first** at check-in (predicted, one tap for commuters), and **plan at check-in, confirm each leg** with a one-tap nudge at the transfer, because a confirmed leg is evidence and a guessed one is not.

## Model

- **Journey**: customer, origin station, destination station, the planned itinerary as a snapshot from Transitous at check-in (legs with trip ids, planned departure and arrival per leg, transfer stops), planned arrival at the destination, status `riding | transfer | arrived | abandoned`, actual arrival at the destination, final delay, `missed_connection`, `incomplete` (finalised without reaching the destination in the app), points.
- **Leg** = today's `rides` row, plus `journey_id`, `leg_no`, `planned_departure`, `transfer_station_id/name` (where this leg hands over, null on the last leg). The follower works per leg exactly as today.
- **Delay that counts** = actual arrival of the last leg at the destination − planned arrival at the destination from the snapshot. Points = that delay (cancellation of any leg = at least 60). An incident is created from the journey, not the leg; incidents get `journey_id`; the leg-based path stays only as the `incomplete` fallback (delay at the last confirmed stop against the snapshot's planned arrival there).
- **Missed connection** = the actual arrival at a transfer stop is later than the planned departure of the next leg (or that leg was cancelled). The next leg is then re-planned from the transfer stop at the actual arrival time.

## Backend

Transitous `GET /api/v1/plan?fromPlace=<stop id>&toPlace=<stop id>&time=<iso>&numItineraries=4&transitModes=RAIL,REGIONAL_RAIL,REGIONAL_FAST_RAIL,HIGHSPEED_RAIL,LONG_DISTANCE,SUBURBAN` returns itineraries with legs (`mode`, `routeShortName`, `from`/`to` with `stopId` and `name`, `scheduledStartTime`/`scheduledEndTime`, `startTime`/`endTime` live, `tripId`, `realTime`). Verified on 10 September 2026: Köln Hbf → Bonn Hbf gave ICE 929 and RB 26 with trip ids that `GET /trip` accepts.

Routes:

| Route | Does |
|---|---|
| `GET /v1/me/destinations` | predicted destinations: the customer's journey destinations by frequency, weighted by time of day and origin (from the current station, what did they usually do at this hour?), home station labelled "Nach Hause" when away from it; up to 3, plus the last 5 distinct for the list |
| `GET /v1/journeys/plan?from=<stop id>&to=<stop id>[&time=]` | itineraries from Transitous, rail only, grouped by first leg; each with legs, transfers, planned arrival; a `preferred` flag on the itinerary whose first leg departs next |
| `POST /v1/journeys` `{from, to, itinerary}` | creates the journey with the snapshot and leg 1 (a ride, `riding`); returns journey + current leg. Accepts the optional one-shot location fix like check-in does |
| `GET /v1/journeys/current` | the journey with legs, status, the next planned leg while in `transfer`, and live data for the current leg (what `rides/current` gives today) |
| `POST /v1/journeys/{id}/legs` `{trip_id}` | confirms the next leg (the planned one, or a re-planned alternative after a missed connection); creates the ride |
| `POST /v1/journeys/{id}/finish` | manual end: "Ich bin da" or "Abbrechen"; finalises with what is known |
| `GET /v1/journeys` | history, replaces `GET /v1/rides` for the app's list (rides stay as the leg detail) |

Follower: when a leg's exit stop is reached and the journey has a next planned leg, the journey goes to `transfer`: planned next leg checked against live data, missed-connection detection, re-plan when missed, event `journey` with `transfer: true` and the proposal, push "Anschluss RE 5 nach Kleve 10:41, Gleis 3 · Bist du drin?" (a tap opens the app on the confirmation). If nobody confirms within 2 h after the planned arrival of the next leg, the journey is finalised `incomplete`. When the last leg arrives at the destination, the journey is finalised, the incident created (amount from the journey delay), the arrival push sent with the journey delay.

Events: `journey` kinds (`transfer`, `arrived`, `finished`) next to the existing `ride` events, so the app's current listeners keep working during the transition.

Stellwerk: `stellwerk journey <customer>` (legs, transfer state, proposal), `ff` finalises the current leg and moves the journey on (into `transfer` or `arrived`), `delay`/`cancel` act on the current leg, `stellwerk confirm <customer>` confirms the proposed next leg as the phone would. `stellwerk ride` stays as the leg view.

PDF: journey fields in section 3 (origin, destination, planned and actual arrival at the destination); with a connection, the reason "Verpasster Anschluss" is ticked when `missed_connection`, and section 6 lists the legs with their times. The form never claims per leg.

Migration 0020: `journeys` table; `rides.journey_id`, `leg_no`, `planned_departure`, `transfer_station_id`, `transfer_station_name`; `incidents.journey_id`. Existing rides stay as single-leg journeys created lazily when read, or simply remain leg rows without a journey (the ledger reads both).

## JSON

Field names are snake_case like the rest of the API. Times are UTC ISO strings.

**Leg** (inside `itineraries[].legs`, `journey.legs`, `journey.next_leg`):

```json
{ "trip_id": "20260910_17:50_de-DELFI_339851", "line": "RE 7", "headsign": "Rheine", "operator": "National Express", "category": "re",
  "from_station_id": "de-DELFI_de:05315:…", "from_station_name": "Köln Hbf", "to_station_id": "…", "to_station_name": "Hagen Hbf",
  "planned_departure": "2026-09-10T15:56:00Z", "planned_arrival": "2026-09-10T16:25:00Z",
  "live_departure": null, "live_arrival": null, "platform": "7", "cancelled": false, "delay_min": 0 }
```

In `journey.legs` a leg also carries `leg_no`, `ride_id` (null until confirmed), `status` (`planned | riding | arrived | cancelled | skipped`), `actual_arrival`, `final_delay_min`. In `journey.next_leg` it carries `replanned` (true after a missed connection) and `reason` (`"verpasst"`, `"ausfall"` or null).

**`GET /v1/journeys/plan?from=<stop id>&to=<stop id>[&time=<iso>][&first_trip=<trip id>]`**:

```json
{ "from": { "id": "…", "name": "Köln Hbf" }, "to": { "id": "…", "name": "Kleve" },
  "itineraries": [ { "id": "…", "preferred": true, "transfers": 1, "transfer_stations": ["Hagen Hbf"],
                     "planned_departure": "…", "planned_arrival": "…", "live_arrival": null, "duration_min": 95, "legs": [ Leg, Leg ] } ] }
```

Rail legs only (walks between platforms are folded into the transfer); `preferred` marks the itinerary whose first leg departs next; `first_trip` keeps only itineraries starting with that trip (the "tapped a departure first" path).

**`POST /v1/journeys`** body:

```json
{ "from_station_id": "…", "from_station_name": "Köln Hbf", "to_station_id": "…", "to_station_name": "Kleve",
  "legs": [ { "trip_id": "…", "from_station_id": "…", "to_station_id": "…" }, { "trip_id": "…", "from_station_id": "…", "to_station_id": "…" } ],
  "ticket": "deutschlandticket", "location": { "lat": 50.94, "lon": 6.96, "accuracy_m": 20 }, "from_lat": 50.9432, "from_lon": 6.9586 }
```

`ticket`, `location`, `from_lat/lon` are optional. The server re-reads every trip, snapshots planned times, creates the journey and leg 1. Response = the `journeys/current` shape. 409 when a journey is already riding or in transfer.

**`GET /v1/journeys/current`** (404 when there is nothing current and no arrival in the last two hours):

```json
{ "journey": Journey, "ride": RideRow-or-null, "stops": [ TripStop… ], "eta": "…", "next_leg": Leg-or-null, "just_arrived": false, "claim_from_minute": 60 }
```

`ride` and `stops` describe the current leg while `riding` (same objects as `GET /v1/rides/current`); during `transfer` `ride` is the leg just finished.

**Journey**:

```json
{ "id": "…", "status": "riding", "origin_station_id": "…", "origin_station_name": "Köln Hbf", "destination_station_id": "…", "destination_station_name": "Kleve",
  "planned_departure": "…", "planned_arrival": "…", "actual_arrival": null, "final_delay_min": null,
  "missed_connection": false, "incomplete": false, "cancelled": false, "points": 0, "ticket": "deutschlandticket",
  "current_leg": 1, "legs": [ Leg+… ], "next_leg": null, "transfer_station_name": null, "transfer_deadline": null,
  "created_at": "…", "finalised_at": null }
```

**`POST /v1/journeys/{id}/legs`** body `{ "trip_id": "…" }` (the proposed one, or any trip from the transfer stop); response = `journeys/current`. **`POST /v1/journeys/{id}/finish`** body `{ "arrived": true }` ("Ich bin da": finalises now with the delay at the destination, or at the last stop when in transfer) or `{ "arrived": false }` (abort: `abandoned`, no incident); response = the Journey. **`GET /v1/journeys`** → `[Journey…]`, newest first.

**`GET /v1/me/destinations?from=<stop id>`**:

```json
{ "home": { "station_id": "…", "station_name": "Bonn Hbf" },
  "predicted": [ { "station_id": "…", "station_name": "Bonn Hbf", "label": "Nach Hause", "count": 12 } ],
  "recent": [ { "station_id": "…", "station_name": "Düsseldorf Hbf", "last_at": "…" } ] }
```

`predicted` ≤ 3 (scored by frequency, same hour ±2 h ×2, same origin ×2; the current station is never predicted); `label` is `"Nach Hause"` for the home station when `from` is not home, else null; `recent` = last 5 distinct destinations.

**Events** (`GET /v1/events`): kind `journey` with `{ "journey_id", "status", "transfer": bool, "arrived": bool, "finished": bool, "missed_connection": bool, "final_delay_min": n|null, "incident": id|null, "next_leg": Leg|null }`. Kind `ride` stays as today and additionally carries `journey_id` and `leg_no`. Push `kind: "journey"` opens Unterwegs (transfer) or the arrival.

## App

- **At a station** (Bahnsteig card): the predicted destinations as one-tap buttons on top ("Nach Hause · Bonn Hbf", "Düsseldorf Hbf", "Anderes Ziel …"), the next departures below as the other way in. Tapping a destination opens **Welcher Zug?**: the itineraries from `plan`, each as a departure row plus a transfer chip ("1× umsteigen in Hagen", "direkt"), the preferred one first; one tap creates the journey. Tapping a departure row instead opens **Wohin?** with the same predictions, then plans with that train as leg 1 (itineraries filtered to that first trip).
- **Wohin?** replaces "Wo steigst du aus?": predictions, recent destinations, station search. The exit stop is derived from the itinerary, never asked.
- **Unterwegs** shows the journey: current leg with live delay, the transfer ahead with the planned connection and its live status, then the destination with the planned arrival. In `transfer`: the confirmation card "RE 5 nach Kleve 10:41 · Gleis 3 · Ich bin drin" with the alternative when the connection was missed ("Anschluss verpasst · nächste Möglichkeit RE 5 11:41").
- **Angekommen** shows the journey delay at the destination, and "Anschluss verpasst in Hagen" when it applies.
- **Konto / PDF** use journey fields. **Alle Fahrten** lists journeys with their legs collapsed.
- The transfer confirmation also arrives as a push; tapping it opens Unterwegs on the confirmation card. (A geofence-based nudge at the transfer station is a later step; the push at the planned arrival is enough now.)
- Demo mode: the mock gets two predicted destinations, one direct and one connecting itinerary, a transfer state.
- The workflow E2E is rewritten around the new flow: check in via a predicted destination on a direct itinerary; Stellwerk `ff`; the rest unchanged. A second scenario with a connection: `ff` leg 1 → transfer state visible → `stellwerk confirm` → `ff` leg 2 → arrival with the journey delay.

## Not in this step

Geofence nudge text at transfer stations, multi-modal legs (bus, tram) inside a journey, Träwelling import of journeys.
