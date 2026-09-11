# 25 — Geofencing that behaves on a long trip, and a way to see what it does

Decided 11 September 2026 (Johannes, after a München → Memmingen trip with no nudge). The geofence design in docs/15 is right for a commuter standing at their home station and wrong for someone crossing the country. This replaces its trigger, its region budget and its dwell rule, adds an off-switch that works by itself, and makes the whole thing observable.

## 0. What is wrong today

| Symptom | Cause |
|---|---|
| No nudge at Memmingen after 10 minutes | Memmingen was never registered. The nearest 3 are recomputed only on umbrella exit, from wherever the phone was at that moment, which on a moving train is between stations. |
| Chatter | The umbrella is 8 km. At 160 km/h it is crossed every 3 minutes, and every crossing is a wake plus a `GET /v1/stations/nearby`. A München → Memmingen trip is roughly 20 calls, which iOS throttles and the backend does not need. |
| A nudge lost on arrival | Entry schedules the notification 60 s out and cancels it if vehicle speed is seen in the first 25 s. Rolling into a station and then stopping can cancel a nudge that should have fired. |

## 1. The coarse layer becomes Significant Location Change

`startMonitoringSignificantLocationChanges()` costs almost nothing, is delivered from cell towers, arrives at most every few minutes, and relaunches a terminated app. It replaces the umbrella region as the "where am I roughly" trigger, which also frees the 20th region slot.

The app keeps a **coverage disc**: the centre it last registered around, and a radius. On every significant-location update:

- inside the disc → **nothing happens, no network call**;
- outside → one `GET /v1/stations/nearby`, re-register, recentre the disc.

The radius adapts to how fast the phone is moving, measured from the last two updates:

| speed | radius | why |
|---|---|---|
| under 30 km/h | 5 km | walking or local: be precise |
| 30–120 km/h | 25 km | a regional train: one refresh every few stops |
| over 120 km/h | 60 km | long distance: one refresh per leg, not per field |

A München → Memmingen trip becomes 2 or 3 calls instead of about 20, and the registered set is always drawn around somewhere the passenger recently *was*, not somewhere they flashed through.

The umbrella region stays only as a backstop for devices where significant-location updates are unavailable, and is then sized from the same table.

## 2. The region budget follows the passenger

iOS allows 20 monitored regions. Today it is 16 frequent + 3 nearest + 1 umbrella, whatever the situation. The frequent set is worth its slots at home and worthless 300 km away.

- Within 50 km of any frequent station: **16 frequent + 4 nearest**.
- Further away: **20 nearest**, the frequent set dropped entirely.

`GET /v1/me/geofence` returns the frequent set as it does now; the nearest come from `stations/nearby`, which after docs/23 §1 already returns them ranked by what actually departs there, so tram and bus stops never take a slot.

## 3. "There for a bit of time"

The nudge should mean *you are standing at a station*, not *you went past one*.

- On entry the app schedules the local notification **3 minutes** out (was 60 seconds) and cancels it on region exit. A train passing through is gone long before it fires; a passenger on a platform is not. This costs nothing and needs no background execution, which iOS would not grant anyway.
- The vehicle-speed cancellation inside the 25 s watch window **goes**. It was a guess at the same thing and it cancelled real arrivals. Exit is the honest signal.
- The check at fire time is unchanged in spirit and stricter in fact: no nudge while a journey is open, while a snooze runs (docs/24 §3), inside quiet hours, or when the station is muted.
- 3 minutes is the default and is adjustable on the debug page, so it can be tuned on real trips rather than argued about.

## 4. Background scanning switches itself off

Nobody should be nudged forever by an app they stopped using.

- **Per station**: a nudge that is ignored three times in a row — no tap, no check-in within 30 minutes — mutes that station for 30 days. The existing per-station mute carries it, with an expiry.
- **Globally**: no check-in for 30 days switches background scanning off. The next time the app is opened, Home says so in one line and offers to turn it back on. Nothing is deleted and no permission is revoked.
- Both counters reset on any check-in.
- This sits alongside the manual snooze from docs/24 §3, which is the deliberate version of the same thing.

## 5. The debug page

A sub-page under Einstellungen, `Entwicklung`, shown when `--dart-define=DEBUG_PAGE=1` and always in a debug build. It exists so a question like "why no nudge at Memmingen?" can be answered from the phone instead of guessed at from a laptop.

**Status**

- Permission state, background scanning on/off and why, snooze end, riding flag.
- The coverage disc: centre, radius, speed bucket, when it was last recentred.
- Every registered region: name, distance now, and whether the phone is currently inside it.
- Counters since midnight: backend requests in total, `stations/nearby` calls, nudges scheduled, fired, cancelled and why.

**Log**

A ring buffer of the last 500 entries with a timestamp, a source and a line of text:

- `geofence` — configure, register, enter, exit, schedule, cancel, fire. **Written natively** into a small persisted buffer, because nearly all of it happens while the app is suspended; Dart reads it through the channel and merges it in.
- `http` — method, path, status, duration in ms, response size, written by one interceptor in `client.dart`.
- `push` — received, tapped, payload kind.
- `app` — launch, resume, background, route changes.

The buffer survives a background kill and a relaunch. The page filters by source, and has `Alles kopieren` so a whole trip can be pasted into a message. Nothing in it leaves the phone by itself, and it holds no claim content: paths, not bodies.

**Actions**: refresh the region set now, clear the log, force a nearby lookup, fire a test nudge in 10 seconds.

## Expected traffic, so the numbers can be checked

| Situation | `stations/nearby` calls |
|---|---|
| Standing still all day | 0 after the first |
| Commute of 20 km | 1–2 |
| München → Memmingen (110 km) | 2–3 |
| A day crossing Germany | under 10 |

The debug page's counters make this falsifiable on a real trip; if the numbers come out higher, the radius table is wrong and can be changed in one place.

## Tests

- Backend: unchanged apart from the geofence payload; the nearest set already comes from docs/23 §1.
- Unit: the radius table by speed; the disc containment check; the region budget switching at the 50 km boundary; the ignored-nudge counter reaching three.
- Tour: `debug-status`, `debug-log`, `einstellungen` with the `Entwicklung` row present in a debug build.
- On a real trip: the counters, checked against the table above.
