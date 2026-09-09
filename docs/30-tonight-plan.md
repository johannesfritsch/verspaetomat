# 30 — Tonight: from mock to a working system

Written 9 September 2026, 20:40. Goal for tonight: the Flutter app on the simulator talks to a local Rust backend on Postgres, with device auth, real departures and trip following from Transitous, and every screen backed by the API. About six hours, two tracks in parallel, one integration pass at the end.

## What "working" means tonight

- Postgres holds customers, rides, incidents, claims, mails, NGOs, operators, badges, teams. Clean numbered migrations, reproducible from zero with one command.
- Device auth: first launch creates a device, gets a bearer token, stores it in the Keychain. No accounts. Recovery code shown at the first claim.
- Train data is real: stations near the phone, departures with live delays and operator, trip stops with forecast times, all from Transitous. The trip follower polls riding trips every 45 seconds, persists the forecast, finalises the ride at the exit stop and creates the incident if 60+.
- Ledger, claim draft, attachments (as uploads), signature, send, inbound webhook, reply classification, community and teams run against the database.
- Every screen in the app reads and writes through the API. Demo controls stay for the two things the real world will not do on demand tonight: "Ankunft simulieren" (forces the follower to finalise with a chosen delay) and "Antwort der Bahn simulieren" (posts to the inbound webhook).

## What is not tonight (cut list)

| Cut | Why | Stand-in tonight |
|---|---|---|
| Typst claim PDF | half a day on its own | claim attached as a plain-text summary; PDF next |
| Real SMTP send and provider inbound | needs a provider account, DNS (SPF/DKIM) | `lettre` wired behind `SMTP_URL`; without it "dry-run" records the mail; inbound via our own webhook |
| Push notifications | APNs/FCM setup | in-app state only |
| Background geofence nudge | a day of native work and store review | in-app banner when the app is open near a station |
| Träwelling OAuth | needs their client registration | settings row stays a mock |
| NGO report import UI | ops feature | SQL script |
| Boards from many users | one real user tonight | own points live, other rows seeded |
| App Attest / Play Integrity | later | per-device rate limits only |

## Timeline

| When | Track A: backend | Track B: app | Who |
|---|---|---|---|
| 20:40–21:00 | Phase 0: start Postgres, create db, freeze the contract (device auth, Transitous ids), decide the cut list | read the contract | both |
| 21:00–22:00 | Phase 1: migrations, sqlx repositories, device auth, `me`, settings, personal data | Phase 4a: API client, models, repository interface with mock and HTTP implementations, device bootstrap, settings screen on the API | A: me · B: builder agent |
| 21:00–22:00 | Phase 2 (parallel agent): Transitous adapter (stations nearby, search, departures, trip), operator mapping, trip follower loop | | builder agent |
| 22:00–23:00 | Phase 3: rides, incidents, rules on Postgres, claims, sign, send (dry-run or SMTP), inbound webhook, mails, community, teams | Phase 4b: Bahnsteig, Einchecken, Ausstieg, Unterwegs, Angekommen, Nachtrag on the API with device location | both |
| 23:00–23:45 | seed script, `make dev`, clippy, tests | Phase 4c: Konto, Antrag, Antwort, Zweck, Wir, Team, Ich, Historie on the API | both |
| 23:45–00:30 | Phase 5: integration on the simulator, walk the four workflows, fix what breaks | | me |
| 00:30–00:45 | Phase 6: commit, README run instructions, this doc updated with what actually shipped | | me |

## Phase 0 — foundations (20 min)

```bash
brew services start postgresql@17
createdb verspaetomat
export DATABASE_URL=postgres://localhost/verspaetomat
```

Contract changes to freeze before anyone writes code:
- `POST /v1/devices` → `{device_id, token}`; every other route requires `Authorization: Bearer <token>`.
- `POST /v1/devices/recover` with a recovery code re-attaches a new device.
- Station ids are Transitous stop ids as-is (e.g. `be-sncb_8015458` for Köln Hbf). Trip ids are Transitous trip ids as-is.
- Times become RFC 3339 timestamps, not "HH:MM".
- Uploads: `POST /v1/uploads` (multipart) → `{upload_id}`; claims reference upload ids.

## Phase 1 — Postgres and auth (60 min)

Migrations, one file each, in this order:

1. `devices` (id, token_hash, recovery_code_hash, created_at, last_seen_at)
2. `customers` (id = device id, nickname, relay_address unique, personal data columns, settings columns, points cache)
3. `operators` (name pk, desk, postal_address, email, accepts_email, last_verified)
4. `ngos` (id, name, tagline, story jsonb, account_holder, iban, donation_url, last_report, active)
5. `badges` (id, name, rule) and `badge_awards` (customer_id, badge_id, ride_id, awarded_at)
6. `rides` (id, customer_id, trip_id, station ids and names, exit stop, planned/actual arrival timestamptz, ticket, status, live_delay, passed_stops, cause, final_delay, cancelled, self_entered, nachtrag, location_verified, points, checked_in_at)
7. `ride_snapshots` (ride_id, fetched_at, payload jsonb) for evidence
8. `incidents` (id, ride_id, customer_id, date, line, from, to, delay, amount_cents, ticket, operator, desk, status, ngo_id, claim_id, fare_cents, legal_deadline, warned_at, evidence jsonb)
9. `claims` (id, customer_id, desk, ngo snapshot, ticket_months, status, signed_by, signed_at, sent_at, expected_reply_by, amount_claimed, amount_confirmed) and `claim_incidents`, `claim_attachments`
10. `mails` (id, claim_id, customer_id, direction, message_id, from, to, bcc, subject, body, attachments jsonb, outcome, amount_cents, forwarded_at, received_at)
11. `teams`, `team_members`
12. `audit_log` (entity, entity_id, from_status, to_status, at, reason)

Seed script loads operators, NGOs and badges from `backend/fixtures`. Auth is a tower middleware: hash the bearer, load the customer, inject it. Rate limit per device: 60 requests per minute, 5 claim sends per day.

## Phase 2 — train data (60 min, parallel)

Transitous MOTIS v1, verified tonight:
- `GET /api/v1/reverse-geocode?place=lat,lon&type=STOP` → nearby stops (filter to rail: keep stops whose departures include modes RAIL, REGIONAL_RAIL, SUBURBAN, HIGHSPEED_RAIL, LONG_DISTANCE; drop pure tram/bus).
- `GET /api/v1/geocode?text=…&language=de` → station search.
- `GET /api/v1/stoptimes?stopId=…&n=…` → departures: `routeShortName`, `headsign`, `place.scheduledDeparture` / `place.departure`, `realTime`, `agencyName`, `place.track`, `tripId`, `cancelled`, `tripCancelled`, `mode`.
- `GET /api/v1/trip?tripId=…` → stop-by-stop scheduled and realtime times (verify the exact shape first; it is the one endpoint not probed yet).

Adapter trait `TrainData` with `TransitousClient` now and room for RIS later. Cache departures per stop for 30 s. Map `agencyName` to our operator names (e.g. "DB Regio AG NRW" → "DB Regio NRW", "DB Fernverkehr AG" → "DB Fernverkehr") in the operators table via an `aliases` column.

Trip follower: a tokio task every 45 s: for each ride in `riding`, fetch the trip, store a snapshot, update `live_delay`, `passed_stops`, `cause`; when the exit stop has a realtime arrival in the past (plus 3 min grace) or the trip is cancelled at that stop, finalise: final delay, points, incident via the rules, badges, status `arrived`. A demo endpoint `POST /v1/rides/current/arrival` with a delay still exists tonight.

## Phase 3 — ledger, claims, relay on Postgres (60 min)

Port `rules.rs` unchanged. Repositories for incidents, claims, mails. `send`: refuse unsigned; build the mail; if `SMTP_URL` is set send via `lettre` with BCC, else record as dry-run with a generated message id; mark incidents `eingereicht`; audit log. Inbound webhook as today, plus HMAC check with `INBOUND_SECRET`. Community aggregates as SQL views refreshed on read (one user tonight, so cheap). Boards: own seven-day points from rides, merged into seeded rows.

## Phase 4 — the app on the API (90 min, parallel from 21:00)

- `lib/api/`: client (package `http`), typed models generated by hand from `openapi.yaml`, error type, token storage (`flutter_secure_storage`).
- `AppRepository` interface; `MockRepository` wraps today's `DemoState`; `HttpRepository` calls the API. A switch in Einstellungen ("Backend: Demo / Lokal") and a `--dart-define=API_URL`.
- Device bootstrap on first launch; recovery code sheet at the first claim.
- Location: `geolocator` for the one-shot fix at check-in and for nearby stations; the nudge banner appears when the app is open within 300 m of a station.
- Screens switch in the order of the workflows: onboarding and Bahnsteig, check-in and ride, arrival, ledger and claim, reply, community and profile. Each screen keeps working in Demo mode.

## Phase 5 — integration (45 min)

On the simulator with a simulated location at Köln Hbf: create device → nearby stations → real departures → check in to a real RE → follower ticks → "Ankunft simulieren +68" → incident and badge → Konto shows bereit → claim draft → personal data + recovery code → attach → sign → send (dry-run) → mail visible → "Antwort simulieren" → bestätigt → Wir moves. Then the same with an ordinary ticket. Then a fresh install to prove migrations and seed from zero.

## Risks tonight and what we do

| Risk | Plan |
|---|---|
| Transitous `trip` shape differs from expectation | probe first thing in Phase 2; fall back to `stoptimes` at the exit stop for the arrival forecast |
| Transitous rate limiting | 30 s departure cache, 45 s follower interval, one user |
| sqlx compile-time checks need a live database at build | use `sqlx::query_as` at runtime tonight; switch to offline `.sqlx` metadata later |
| Time | the cut list is the buffer; Phase 4c screens can stay on Demo mode if the evening runs out, and the doc says which |

## Needed from you

1. Go on the cut list above, or name what must move into tonight.
2. Optional: SMTP credentials for a transactional provider if you want a real mail to leave tonight. Without them the relay dry-runs.
3. The simulator will be driven from here; you only need to watch.


## What shipped (updated 9 September 2026, late evening)

Done and verified:
- Postgres 17 with twelve migrations (`backend/migrations`), applied automatically at start; seed of operators, NGOs, badges, seeded boards.
- Device auth: `POST /v1/devices` → bearer token (hashed at rest), recovery code of twelve words at the first claim, `POST /v1/devices/recover` verified end to end.
- Transitous adapter: nearby stations, search, departures with live delays, per-stop trip data; agency → operator → claims desk mapping.
- Trip follower: verified live. A check-in to RE 22 at Köln Hbf (19:21 UTC) finalised itself at Köln West at 19:30 UTC with +1 minute, points and audit entry, no manual call.
- Ledger, claims, uploads, signature, send via the relay (dry-run without `SMTP_URL`, real SMTP via lettre with it), inbound webhook with classification and forwarding, community, boards, teams, export, delete.
- Flutter: API client, repository switch (Demo / Lokal) in Einstellungen, all screens on the repository, one-shot location for nearby stations and the check-in fix, uploads and signature, recovery-code sheet. `--dart-define=BACKEND=local`, `API_URL`, `NO_LOCATION=1` for demos and screenshots.
- Local-mode screenshots on the iPhone 15 Pro simulator: Bahnsteig with real nearby stations, Einchecken with real departures, Konto, Wir, Ich, all without exceptions.
- End-to-end integration test (`app/integration_test/workflow_test.dart`) passing on the simulator against the local backend, driving the world through the Stellwerk admin API (no in-app simulate buttons in local mode): three check-ins to live departures with +68 delay and fast-forward, the five-step claim with personal data, recovery code, ticket upload, signature and relay send, the simulated railway reply, ledger "bestätigt", community figure. Run:
  `flutter test integration_test/workflow_test.dart -d <simulator> --dart-define=API_URL=http://127.0.0.1:8081 --dart-define=BACKEND=local --dart-define=NO_LOCATION=1 --dart-define=E2E=true --dart-define=ADMIN_TOKEN=stellwerk --dart-define=INITIAL_ROUTE=/bahnsteig`
- Proof: `app/integration_test/workflow_test.dart` passes on the simulator against the local backend: three real check-ins from live Köln Hbf departures, arrival +68 each, bundle "bereit", the five-step claim, "Abgeschickt.", "eingereicht", simulated reply, "bestätigt", Wir updated. Migration 0013 (`dismissed_at`) came out of it.

- Stellwerk: server-side simulation layer (`backend/src/train/sim.rs`), admin API, and the `stellwerk` CLI (delay, cancel, fast-forward, poll, reply, clock, reset, watch). Verified: a fast-forwarded ride is finalised by the real follower, incidents and badges follow, a clock shift of +100 days expires open incidents, reset cleans up. The app has no simulate buttons in local mode.

Not tonight (as planned): Typst PDF (plain-text summary attached instead), push, background geofence, Träwelling OAuth, NGO report import UI, App Attest, boards across real users, the 25 % monthly cap.

Gotchas found:
- The simulator's location permission alert survives app relaunches and hides the app; reboot the simulator or run with `NO_LOCATION=1` (a string compare: Flutter's `bool.fromEnvironment` only accepts the literal `true`).
- Transitous station names carry a country suffix ("Köln Hbf (DE)"); stripped in the adapter.
- Late in the evening the departures page of the feed is mostly buses and trams; the adapter now fetches 150 rows before filtering to rail.
- Known rough edges: Konto refreshes only when the claim or reply screen pops back; the nickname is never set, so boards show "Fahrgast"; the reply screen's "Zum Konto" control is missing on the accepted branch.

Run it:

```bash
cd backend && ./dev.sh                                  # API on 127.0.0.1:8080
cd app && flutter run -d "iPhone 15 Pro" --dart-define=BACKEND=local
```
