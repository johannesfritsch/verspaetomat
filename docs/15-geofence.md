# 15 — Station geofencing: the nudge when the app is closed

Decided 10 September 2026. Extends [14-location-concept.md](14-location-concept.md): the phone still decides, the server never guesses, no location history. What changes: the nudge works with the app closed, and **background is the default** ("Auch im Hintergrund" preselected in onboarding, `loc_mode` default `always`).

## Limits we design around

iOS monitors at most 20 regions per app, Android 100. So the app registers a small, personal set:

| Slot | Content | Count |
|---|---|---|
| Frequent | the customer's check-in stations of the last 30 days by frequency, home station always included, muted stations excluded | up to 15 |
| Nearest | the 3 stations nearest to the phone at registration time, if not already in the set | up to 3 |
| Umbrella | one circle of 8 km around the phone's position at registration | 1 |

Leaving the umbrella wakes the app: one fix, `GET /v1/stations/nearby`, re-register nearest 3, recentre the umbrella. The frequent set only changes when the app is opened (it comes from the server). Total ≤ 19 on iOS.

## Behaviour

1. **Entry into a station region** (radius 300 m). iOS gives a woken app about 30 s, not enough to measure a dwell, so the nudge is not measured, it is scheduled: the app posts a local notification with a 60 s trigger and iOS delivers it on its own, app alive or not. For the next 25 s the app watches location fixes; a fix outside the radius, or at vehicle speed (≥ 8 m/s), cancels the pending notification. Leaving the region (exit event) cancels it too. Android uses the platform's own dwell transition (60 s loitering) plus one confirming fix instead.
2. **Before scheduling**: quiet hours (Ruhezeiten, evaluated for the delivery time) → nothing; the same station nudged within the last 30 min → nothing; a ride in progress (native knows from the last `configure`) → nothing.
3. **Nudge** = the local notification: title "Am Köln Hbf?", body "Einchecken, bevor der Zug kommt." Tapping opens the app on `/checkin?station=<id>&name=<name>`; if the app was not running, the tap is kept as `pendingNudge` and handed to Dart on the next `status` call.
4. **Already inside**: iOS fires no entry for a region the phone is already in when monitoring starts (typical right after an umbrella exit re-registers the nearest stations), so the app asks for the region state after registering and treats "inside" like an entry.
5. **Nothing is sent to the server** by the native layer except the one nearby query on umbrella exit (same query the Bahnsteig makes). No fix is stored anywhere.

## Contract: MethodChannel `de.verspaetomat/geofence`

Dart → native:

| Method | Arguments | Returns |
|---|---|---|
| `configure` | all eleven keys `GeofenceConfig.toChannel()` sends, and no others: `{apiUrl, token, enabled, riding, stations: [{id, name, lat, lon}], umbrellaRadiusM: 8000, stationRadiusM: 300, nudgeRadiusM: 50, stationsLocal: false, quietFrom: "22:00"?, quietTo: "06:00"?}`. Both native sides additionally accept `nudgeDelayS`, which nothing sends today, so both fall back to their own default | `{registered: int}` — native persists the config, drops all regions, registers `stations` (≤ 16 after native adds the nearest 3 it may already know) plus the umbrella at the current position (one fix; if no fix, umbrella is skipped and retried on next configure) |
| `requestPermission` | `{always: bool}` | permission string |
| `status` | — | **Abridged — this row has never been the full list.** iOS returns 26 keys plus `lastEvent` and `pendingNudge` when there are any; Android returns 6 plus `pendingNudge`. The ones named here are the ones prose elsewhere refers to: `{permission: notDetermined/denied/whileInUse/always, notifications: bool, registered: int, lastEvent: string?, ignored: {stationId: int}, counters: {name: int}, stationsLocal: bool, …}`. The Entwicklung page (`entwicklung_screen.dart`) renders whatever is there and is the readable list |
| `stop` | — | removes all regions, keeps nothing |

Native → Dart:

| Method | Arguments | When |
|---|---|---|
| `nudgeTapped` | `{stationId, stationName}` | the notification was tapped; if the app was not running, native keeps it and replies to `status` with `pendingNudge` once |

Permission strings: `notDetermined`, `denied`, `whileInUse`, `always`. `enabled=false` in `configure` behaves like `stop` but keeps the config.

## Backend

`GET /v1/me/geofence` → all eight keys the handler returns: `{enabled, idle, last_checkin, stations: [{id, name, lat, lon, checkins}], quiet_from, quiet_to, snooze_until, stations_local}`. Stations come from the customer's rides of the last 30 days (`from_lat/from_lon` stored at check-in from migration 0019 on) plus the home station; muted stations are excluded server-side. `enabled` is `loc_mode == always && nudge_enabled`, minus a running snooze (docs/24 §3) and minus the 30-day idle switch-off (docs/25 §4) — `idle`, `last_checkin` and `snooze_until` say which of those is folded in.

`stations_local` is #40's kill switch, and **false is the old path**: the native background layer asks `GET /v1/stations/nearby` on umbrella exit, as builds 64 and 65 do. True arms the local resolve from the `.vst` extract on disk (docs/45). It governs the native layer and nothing else — Dart's foreground lookup has had no server rung since #39, gated by a compile-time constant, and no server-side flag can give a release binary back a call it does not contain. Absent means false at every layer, so an old build ignores it and a new build against an old backend keeps the old path.

It lives in one row of `app_switches` (migration 0037), global rather than per-customer, and is flipped with `stellwerk --prod switch stations-local on|off` — one UPDATE, no restart. **The flip reaches the phone at the next `configure`, which is the next time the app is opened**, not the next time it leaves an umbrella; and `GeofenceSync.sync()` returns early without a logged-in session *and* a healthy backend, so the switch needs a reachable server on both ends and cannot rescue a phone whose backend is down. That bound is not new: `enabled: false` from a running snooze and the idle switch-off already reach the phone only through the same `configure`.

## Settings and onboarding

- Onboarding "Standort am Bahnhof": "Auch im Hintergrund" is preselected; choosing it requests Always (iOS asks While Using first and upgrades later by design; the app handles both answers).
- Einstellungen: "Hinweis am Bahnhof" and "Ruhezeiten" now drive `configure`; "Nur wenn die App offen ist" keeps the foreground nudge only; "Aus" stops monitoring.
- The Datenschutz text and the store labels (docs/40) gain the Always permission and its purpose; docs/14 gains a pointer here.

## Verification without a train

Verified on 10 September 2026 on the iOS simulator, app in the background (Settings in front):

```
xcrun simctl location <udid> set 50.7320,7.0970        # Bonn: umbrella registered here
xcrun simctl location <udid> set 50.9432,6.9586        # Köln Hbf: umbrella exit → nearby → 2 stations → "inside" → nudge scheduled
xcrun simctl location <udid> set 50.94321,6.95861      # a few jittered fixes: the simulator ignores identical coordinates
```

Log lines (`NSLog("[geofence] …")`, read with `xcrun simctl spawn <udid> log stream --predicate 'eventMessage CONTAINS "[geofence]"'`): `configure: 0 stations, enabled=true, riding=false, auth=always` → `umbrella exit` → `umbrella recentred, nearest 2` → `enter Köln Dom/Hbf` → `nudge scheduled … in 60 s` → five `watch fix at 169 m, 0 m/s` → `watch over …, nudge stays scheduled`; SpringBoard suspended the app 26 s after entry; the banner appeared 60 s after entry; tapping it opened Einchecken for that station with live departures.

Permission prompts on the simulator cannot be granted with `simctl privacy` for notifications; `idb ui tap` (Facebook's idb) taps the system alert. `stellwerk` is not involved: the native layer never talks to the admin API.

Known: the nearby query is not restricted to heavy rail, so at Köln the nearest station is the Stadtbahn stop "Köln Dom/Hbf" (169 m) rather than "Köln Hbf". Cosmetic for the nudge; the check-in screen it opens lists the DB departures of the station id it was given.
