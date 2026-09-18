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

A sub-page under Einstellungen, `Entwicklung`, **in every build including a release one** (issue #29). It exists so a question like "why no nudge at Memmingen?" can be answered from the phone instead of guessed at from a laptop.

It used to need `--dart-define=DEBUG_PAGE=1`, which `tools/release.sh` never passed, so the page shipped inside every TestFlight build with no way in. It is safe in a passenger's hands: nothing on the page itself writes anything, and the app has no admin surface. The workshop tools that change what the app *is* — switching backend, the demo toys, the "alles erfunden" footer — stay behind `kDebugMode` in their own block in `einstellungen_screen.dart`.

Since issue #28 the page also carries **Alle Schirme → Showcase**, the index of every screen, in every build. That one is not read-only the way this page is, so it guards itself: in local mode it leaves out the entries that would write to the real account — the three onboarding screens, which set the ticket, the NGO and the onboarding flag and raise the iOS prompts, and the two `Antrag` rows, which POST a draft that can delete one already holding a ticket photo and a signature — and the entries that would show real data under an invented label, which is every `Angekommen` variant, since the variant only applies outside local mode. A note on the page says it has done so. It is pushed rather than gone to, and draws a back arrow when it can pop; without that it would be a room with no door in a release build.

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

**The map** (issue #29)

The set drawn to scale, because the thing that is wrong is usually a shape: a disc around the wrong town, a station nowhere near the others, a circle that does not reach the platform. **No tiles and no map package** — nothing about where the phone has been leaves it to draw this, which is the point of the page. An equirectangular projection fitted to the regions, a scale bar, one circle per monitored region at its true radius, the nudge threshold drawn only where the scale can carry it, and the umbrella and the disc dashed. Native has always sent each region's `lat`/`lon`; Dart simply discarded them.

Two rules it keeps: a region without coordinates is **not drawn** and is counted in a line that says so, and the disc centre is labelled as the disc centre with its age — never as the phone's position, which this app does not record. Tapping a region fills the frame with it, which is the only scale at which the 300 m circle and the 50 m nudge threshold are two different things.

**Three segments** (issue #32): `Zustand`, `Zahlen`, `Log`. Only the open one is built — an `IndexedStack` would keep the log's 120 lines laid out on every frame, which is the weight the split exists to remove, and would let the tour photograph the wrong segment under the right name without failing. Everything that is not a reading — `Neu laden`, `Jetzt neu suchen`, `Testhinweis`, `Showcase` — sits above the segments, because the page used to be one eager column about two and a half screens tall and nothing below the log was ever reached.

**Der Satz** (issue #31): when the station set was last handed to iOS and around which centre, when the nearby list behind it was last fetched and how many came back, and what the layer is doing right now. This section exists because the page had exactly one date — the disc's — and it describes something else: `configure` moves the disc to wherever its fix lands while re-registering the set it already had, since `nearest` is only ever written by `refreshNearest` after an umbrella exit. So „Gesetzt: gerade eben" could sit above stations chosen thirteen kilometres away, and the one timestamp on the page argued the opposite of the truth. A caption reads the two dates against each other and says plainly when a set was redrawn from a stale list, and how far the disc reaches before anything new is looked up.

The region list is sorted nearest-first with the umbrella last — native hands back a `Set` in arbitrary order, and with eighteen rows „is this station in here?" was a linear scan with no anchor. An empty set now says so, keyed on the *count* rather than on the list, because Android sends a count and no list and would otherwise claim a phone with live fences has none.

**Verlauf auf der Karte** (issue #29): the log walked one event at a time, with the station it happened at lit on the map. This is the whole of "the state at different times", and it records nothing new to do it: native's lines name their station ("enter Köln Hbf", "312 m from Memmingen") and the region set says where that station is, so the join places an event in time *and* space without a coordinate ever being stored. Its one limit is on screen rather than hidden — a line about a station that is no longer registered cannot be placed, because `stopAllRegions` wipes the set on every re-registration and no log line has ever carried a coordinate, so those lines are counted and left off. `GeofenceReplay.place` in `app/lib/platform/geofence_replay.dart`, with the rule under test.

**Zäune**: the three radii the layer is made of — umbrella 8 km, station circle 300 m, nudge 50 m — named on the page, because they decide everything and appear nowhere else.

**Die Tage davor** (issue #29): the counters of previous days. `bumpCounter` has always written one key per day and deleted none, so this is history the phone already had and could not show; `counters()` only ever read today's prefix. Nothing new is recorded for it, and there are no positions in it. A day with no row is not a zero — the app was off or not installed.

**Actions**: refresh the region set now, clear the log, **force a nearby lookup** (`refreshNow`, the umbrella-exit path by hand, so one behaviour has one code path) and **fire a test notification in 10 seconds** (`testNudge`, which deliberately bypasses `scheduleNudge`: no cooldown written, no station marked, no counter moved, empty payload, so it can never become a real check-in — and thread `test`, not `nudge`, because `willPresent` swallows that one in the foreground).

**Refused regions**: `monitoringDidFailFor` logs a line and bumps a `refused` counter. Without it a region iOS rejected — the usual cause being the hard cap of 20, which `regionSet` plus the umbrella can reach — is simply absent from the set with nothing saying why, and the map would look authoritative while missing the region whose absence is the bug.

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
