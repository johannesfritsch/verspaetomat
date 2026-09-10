# 30 — Tonight: from mock to a working system

Written 9 September 2026, 20:40. Goal for tonight: the Flutter app on the simulator talks to a local Rust backend on Postgres, with device auth, real departures and trip following from Transitous, and every screen backed by the API. About six hours, two tracks in parallel, one integration pass at the end.

## What "working" means tonight

- Postgres holds customers, rides, incidents, claims, mails, NGOs, operators, badges. Clean numbered migrations, reproducible from zero with one command.
- Device auth: first launch creates a device, gets a bearer token, stores it in the Keychain. No accounts. Recovery code shown at the first claim.
- Train data is real: stations near the phone, departures with live delays and operator, trip stops with forecast times, all from Transitous. The trip follower polls riding trips every 45 seconds, persists the forecast, finalises the ride at the exit stop and creates the incident if 60+.
- Ledger, claim draft, attachments (as uploads), signature, send, inbound webhook, reply classification and community run against the database.
- Every screen in the app reads and writes through the API. Demo controls stay for the two things the real world will not do on demand tonight: "Ankunft simulieren" (forces the follower to finalise with a chosen delay) and "Antwort der Bahn simulieren" (posts to the inbound webhook).

## What is not tonight (cut list)

| Cut | Why | Stand-in tonight |
|---|---|---|
| Typst claim PDF | half a day on its own | shipped 10 September: real EU form rendered server-side, see below |
| Real SMTP send and provider inbound | needs a provider account, DNS (SPF/DKIM) | `lettre` wired behind `SMTP_URL`; without it "dry-run" records the mail; inbound via our own webhook |
| Push notifications | APNs/FCM setup | in-app state only |
| Background geofence nudge | a day of native work and store review | shipped 10 September (docs/15): region monitoring on iOS and Android, background by default |
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
| 22:00–23:00 | Phase 3: rides, incidents, rules on Postgres, claims, sign, send (dry-run or SMTP), inbound webhook, mails, community | Phase 4b: Bahnsteig, Einchecken, Ausstieg, Unterwegs, Angekommen, Nachtrag on the API with device location | both |
| 23:00–23:45 | seed script, `make dev`, clippy, tests | Phase 4c: Konto, Antrag, Antwort, Zweck, Wir, Ich, Historie on the API | both |
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
11. `audit_log` (entity, entity_id, from_status, to_status, at, reason)

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
- Ledger, claims, uploads, signature, send via the relay (dry-run without `SMTP_URL`, real SMTP via lettre with it), inbound webhook with classification and forwarding, community, boards, export, delete. (Teams were removed on 10 September 2026.)
- Flutter: API client, repository switch (Demo / Lokal) in Einstellungen, all screens on the repository, one-shot location for nearby stations and the check-in fix, uploads and signature, recovery-code sheet. `--dart-define=BACKEND=local`, `API_URL`, `NO_LOCATION=1` for demos and screenshots.
- Local-mode screenshots on the iPhone 15 Pro simulator: Bahnsteig with real nearby stations, Einchecken with real departures, Konto, Wir, Ich, all without exceptions.
- End-to-end integration test (`app/integration_test/workflow_test.dart`) passing on the simulator against the local backend, driving the world through the Stellwerk admin API (no in-app simulate buttons in local mode): three check-ins to live departures with +68 delay and fast-forward, the five-step claim with personal data, recovery code, ticket upload, signature and relay send, the simulated railway reply, ledger "bestätigt", community figure. Run:
  `flutter test integration_test/workflow_test.dart -d <simulator> --dart-define=API_URL=http://127.0.0.1:8081 --dart-define=BACKEND=local --dart-define=NO_LOCATION=1 --dart-define=E2E=true --dart-define=ADMIN_TOKEN=stellwerk --dart-define=INITIAL_ROUTE=/bahnsteig`
- Proof: `app/integration_test/workflow_test.dart` passes on the simulator against the local backend: three real check-ins from live Köln Hbf departures, arrival +68 each, bundle "bereit", the five-step claim, "Abgeschickt.", "eingereicht", simulated reply, "bestätigt", Wir updated. Migration 0013 (`dismissed_at`) came out of it.

- Stellwerk: server-side simulation layer (`backend/src/train/sim.rs`), admin API, and the `stellwerk` CLI (delay, cancel, fast-forward, poll, reply, clock, reset, watch). Verified: a fast-forwarded ride is finalised by the real follower, incidents and badges follow, a clock shift of +100 days expires open incidents, reset cleans up. The app has no simulate buttons in local mode.

- Claim PDF (10 September): the EU standard form rebuilt as a Typst template (`backend/templates/eu_form.typ`), filled from the ledger per claim, served at `GET /v1/claims/{id}/pdf` and attached to the relay mail as `EU-Antrag.pdf` next to the plain-text summary. Verified: two pages, all six sections, the incident table, the sum and the 4 € note, signature line.

Not on 9 September (as planned): Typst PDF, push, background geofence, Träwelling OAuth, NGO report import, App Attest, boards across real users, the 25 % monthly cap. Most of that list shipped the next day, see below; what remains needs external accounts.

Shipped on 10 September 2026 (backend cut list, migration 0018):
- Typst PDF: `GET /v1/claims/{id}/pdf`, `pdf_url` in the claim JSON, `EU-Antrag.pdf` attached to the claim mail.
- 25 % monthly Deutschlandticket cap: incidents beyond the cap are `gedeckelt` per calendar month, released when an earlier one drops out; `capped_cents` in the ledger summary.
- Deadline scanner loop (`backend/src/scanner.rs`, hourly, `stellwerk scan` for one pass): 21-day warnings, expiry across all customers, reply nudges after the expected reply date, retention of attachment bytes when a claim closes (unless "keep correspondence").
- NGO monthly statement import: `POST /admin/ngos/{id}/report` (JSON or CSV), `stellwerk ngo-report <ngo> <file>`, matches confirm claims, recorded in `ngo_reports`.
- Real boards: customers with `show_on_boards` ranked by verified seven-day points, seeded rows fill the rest, `is_me` on the caller.
- `stellwerk forget <customer>` (`DELETE /admin/customers/{key}`).
- Raw-MIME inbound: `POST /internal/inbound-mail/raw` parsed with mail-parser, attachments stored as uploads.
- Push-token registration: `PUT/DELETE /v1/me/push-token`.
- Push delivery (`backend/src/push.rs`): APNs and FCM v1 senders behind the event bus, dry-run without credentials, `stellwerk push`. Verified on a scratch instance: arrival, reply, nudge and test pushes logged with the right copy; the Stellwerk reply no longer fires the mail event twice.
- Real SMTP path verified against a local sink (`backend/scripts/smtp-sink-check.sh`): envelope sender is the relay address, the desk is the only visible recipient, the customer's copy travels as a BCC (separate RCPT, no header), `EU-Antrag.pdf` arrives intact (43 KB). `smtp://…?starttls=no` for sinks, `smtp://` STARTTLS on 587, `smtps://` on 465.
- Inbound JSON webhook accepts Postmark's payload as posted (and `RawEmail`), so the provider needs no adapter.
- Deploy kit in `deploy/`: Dockerfile, compose (Postgres 17, API, Caddy), `.env.example`, README with DNS (SPF/DKIM/DMARC/MX), webhook, backups, updates. Träwelling OAuth and App Attest still need external setup; APNs/FCM/SMTP/inbound need only credentials in `.env`.
- App: the claim flow, Konto and Antwort show the backend's PDF (pdfx). Demo mode (no backend) ships one backend-rendered sample form as an asset instead of a placeholder.
- E2E: the test now uses its own keychain slot (`TokenStore(namespace: 'e2e.')`), so it gets its own customer and never resets the account a person uses on the same simulator; it locates that customer at Köln Hbf through Stellwerk.

Shipped later on 10 September 2026 (app, store plumbing):
- Rechtliches in the app: Impressum, Datenschutz and "Wie wir Anträge weiterleiten" from `app/lib/content/legal.dart`, under Einstellungen and linked from the claim's send step. Operator name and address are placeholders.
- Nickname: Einstellungen → Konto → Name edits it (PATCH /v1/me); Ich and the boards show it; a blank one takes the first name when claim data is saved (client-side, in `Session.savePersonalData`).
- Konto and Antwort reload on ledger events with a 400 ms debounce (`LoaderController.refreshSoon`), so a Stellwerk fast-forward or reply shows without leaving the screen.
- "Zum Konto" on every inbound reply branch (accepted, question, rejected).
- iOS privacy manifest (`ios/Runner/PrivacyInfo.xcprivacy`, registered as a Runner resource); Android manifest with INTERNET and fine/coarse location, label "Verspätomat", `compileSdk = 37` (flutter_secure_storage 10 requires it; `platforms;android-37` installed via sdkmanager); `flutter build apk --debug` succeeds.
- docs/40-store-listing.md: App Store privacy label, review notes, Play Data safety answers.

Gotchas found:
- The simulator's location permission alert survives app relaunches and hides the app; reboot the simulator or run with `NO_LOCATION=1` (a string compare: Flutter's `bool.fromEnvironment` only accepts the literal `true`).
- Transitous station names carry a country suffix ("Köln Hbf (DE)"); stripped in the adapter.
- Late in the evening the departures page of the feed is mostly buses and trams; the adapter now fetches 150 rows before filtering to rail.
- Known rough edges (all fixed later on 10 September): Konto refreshed only when a sub-screen popped back; the nickname was never set; the reply screen's "Zum Konto" control was missing on the accepted branch.

Run it:

```bash
cd backend && ./dev.sh                                  # API on 127.0.0.1:8080
cd app && flutter run -d "iPhone 15 Pro" --dart-define=BACKEND=local
```

Shipped later on 10 September 2026 (station geofencing, docs/15):
- Backend: migration 0019 (`rides.from_lat/from_lon`, `loc_mode` default `always`, `nudge_enabled`, `quiet_from/quiet_to`), check-in stores the from-station's coordinates, `GET /v1/me/geofence` (frequent stations of 30 days, home station, muted excluded, cap 15), PATCH /v1/me takes `nudge_enabled` and the quiet window.
- App: `lib/platform/geofence.dart` (MethodChannel `de.verspaetomat/geofence`) and `geofence_sync.dart` (debounced configure on session change, foreground, ride changes; pending nudge on start), onboarding preselects "Auch im Hintergrund" and requests Always, Einstellungen persist "Hinweis am Bahnhof" and "Ruhezeiten", a tapped nudge opens `/checkin?station=<id>&name=<name>`, Datenschutz text extended.
- Native iOS and Android layers: see their own entries.

10 September 2026, evening: production on a VPS (docs/42), TestFlight builds 3 and 4 via `app/tools/release.sh`, Stellwerk `--prod`, station geofencing (docs/15). Push verified end to end on a real iPhone with build 4; builds 1–3 never registered with APNs.

10 September 2026, later: `GET /v1/me/standing` for the second Bahnsteig (docs/16): one call with momentum, level, money countdown, board rank, community share and the next thing; week boundaries Monday–Sunday in Europe/Berlin on the simulated clock; boards refactored into `board_entries`. Verified on a scratch instance: fresh device all zeros, a +68 ride moves points/level/money and yields the badge, an inbound question mail becomes `next.kind = mail`.

11 September 2026: Journeys (docs/17) on the backend. Migration 0020; Transitous `plan` (rail only, walks folded); `GET /v1/me/destinations`, `GET /v1/journeys/plan`, `POST /v1/journeys`, `GET /v1/journeys/current`, `POST /v1/journeys/{id}/legs`, `POST /v1/journeys/{id}/finish`, `GET /v1/journeys`; the follower's leg arrival moves the journey into `transfer` (missed-connection check against live data, re-plan from the transfer stop) or `arrived` (incident from the delay at the destination); transfers time out after 2 h into `incomplete`; `journey` events and pushes ("Anschluss RE 10 nach Kleve · 16:38, Gleis 3 · Bist du drin?"); `stellwerk journey` and `stellwerk confirm`; the claim form ticks "Verpasster Anschluss" and lists the legs. `POST /v1/rides` keeps working and creates a one-leg journey.

Later on 10 September 2026: Bahnsteig v2 (docs/16, build 5), journeys with destination-first check-in and confirmed legs (docs/17, build 6), navigation `Home · Anträge · [Einchecken] · Wir · Ich` with the gear on every tab, the claim cycle strip on Home and Anträge replacing Konto (build 7). Both E2E scenarios and the screenshot tour pass on `069224a`.

11 September 2026, docs/18 backend: migration 0021 (`claims.reply_address`, `mails.seen_at`); claims send from `antrag-<8 hex>@users.verspaetomat.de` and replies are routed by that address (customer relay address as fallback); `POST /v1/claims/{id}/seen`; `standing.unread_mails`; destinations by frequency only, home first when away; `stellwerk mail-test … --claim <id>`; `stellwerk reply` answers to the claim's address; `POST /v1/mails/{id}/reply` takes `attach_ticket` and `upload_ids` and records the attachments on the mail.

Late on 10 September 2026: the docs/18 app (Home in three blocks, Anträge cards with word statuses, per-claim addresses as a footnote, reply attachments; build 8) and docs/19 (the ride as a draggable sheet with a persistent bar above the nav, Home without the cycle strip, the Wir block, "Ab Köln Hbf" start-station wording, Welcher Zug? hierarchy; build 9). Both E2E scenarios and the tour pass on `7f13b3b`. Trap: a connection reset during Stellwerk `ff` can leave a trip override behind; `DELETE /admin/overrides` clears it.
