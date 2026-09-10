# Verspätomat backend

Rust, axum, Postgres. Real stations, departures and trips from Transitous; a trip follower that finalises rides from live data; the ledger rules server-side; claims sent from a per-customer relay address (real SMTP when configured, dry-run otherwise); an inbound-mail webhook that updates statuses and forwards replies to the customer. No accounts: one device token per installation plus a recovery code.

Docs: `docs/20-backend.md` (stack, loops, rules), `docs/21-data-requirements.md` (entities), `docs/30-tonight-plan.md` (what shipped when). Contract: `openapi.yaml`.

## Run

```bash
cd backend
./dev.sh            # starts Homebrew postgresql@17 if needed, creates the db, runs migrations + seed, starts the API
./dev.sh --reset    # drop and recreate the database first
```

Environment:

| Variable | Default | Meaning |
|---|---|---|
| `DATABASE_URL` | `postgres://localhost/verspaetomat` | Postgres |
| `BIND` | `127.0.0.1:8080` | use `0.0.0.0:8080` for a phone on the LAN |
| `SMTP_URL` | unset → dry-run | `smtps://user:pass@host:465` or `smtp://user:pass@host:587` (STARTTLS) |
| `INBOUND_SECRET` | unset | when set, `/internal/inbound-mail` and `/internal/inbound-mail/raw` require `?secret=` |
| `ADMIN_TOKEN` | `stellwerk` | the `x-admin-token` for `/admin/*` and the `stellwerk` CLI |
| `RUST_LOG` | `info,tower_http=info,sqlx=warn` | tracing filter |

## Try it

```bash
TOK=$(curl -s -X POST localhost:8080/v1/devices | jq -r .token)
A="Authorization: Bearer $TOK"
curl -s -H "$A" "localhost:8080/v1/stations/nearby?lat=50.943&lon=6.9586" | jq .
curl -s -H "$A" "localhost:8080/v1/stations/be-sncb_8015458/departures" | jq '.[0]'
curl -s -H "$A" -G localhost:8080/v1/trips --data-urlencode "trip_id=<trip id from above>" | jq '.stops[:3]'
curl -s -H "$A" -H 'content-type: application/json' -X POST localhost:8080/v1/rides -d '{"trip_id":"…","from_station_id":"be-sncb_8015458","from_station_name":"Köln Hbf","exit_station_id":"…","exit_station_name":"Neuss Hauptbahnhof"}'
curl -s -H "$A" -H 'content-type: application/json' -X POST localhost:8080/v1/rides/current/arrival -d '{"delay_minutes":68}' | jq .
curl -s -H "$A" localhost:8080/v1/incidents | jq .summary
```

## Layout

```
migrations/        0001…0018, applied automatically at start (sqlx migrate)
src/main.rs        router, state, follower wiring
src/auth.rs        device tokens, recovery codes, the Customer extractor
src/db/            pool + seed (mod.rs), row types (rows.rs)
src/rules.rs       amounts, readiness, deadlines, monthly cap, status refresh, audit
src/handlers.rs    HTTP handlers
src/scanner.rs     deadline scanner loop (warnings, expiry, reply nudges, retention)
src/admin.rs       Stellwerk admin API (simulation, forget, NGO report import, scan)
src/pdf.rs         the EU claim form via Typst (templates/eu_form.typ)
src/train/         Transitous client (transitous.rs), trip follower (follower.rs), shared types (mod.rs)
src/mail.rs        SMTP via lettre, dry-run without SMTP_URL
src/fixtures.rs    seed data (operators, NGOs, badges, seeded boards, community baseline) from fixtures/*.json
openapi.yaml       the contract
dev.sh             one-command dev start
```

## Stellwerk: drive the world from the server

The app carries no simulate buttons when it talks to a real backend. Instead a thin layer in front of the train-data source applies per-trip overrides, and a CLI sets them. The follower, the API and the app all see the same altered world, so a simulated delay creates a real incident through the real code path.

```bash
cargo run --bin stellwerk -- customers              # who exists, who is riding
cargo run --bin stellwerk -- ride Johannes          # current ride, stops, live state
cargo run --bin stellwerk -- delay Johannes +25     # add delay to the current trip
cargo run --bin stellwerk -- cancel Johannes        # cancel it
cargo run --bin stellwerk -- ff Johannes            # fast-forward: exit reached, follower finalises
cargo run --bin stellwerk -- poll                   # one follower pass now
cargo run --bin stellwerk -- reply Johannes --accepted   # or --question, --rejected, --amount 450
cargo run --bin stellwerk -- clock +100d            # shift the system clock (deadlines, nudges); `clock now` resets
cargo run --bin stellwerk -- reset Johannes         # wipe one customer's rides, incidents, claims, mails
cargo run --bin stellwerk -- overrides [--clear]
cargo run --bin stellwerk -- watch Johannes         # live view, refreshes every 3 s
cargo run --bin stellwerk -- locate Johannes "Köln Hbf"   # put the customer at a station (or lat,lon); --clear returns to the phone's GPS
cargo run --bin stellwerk -- forget Johannes [--force]   # delete the customer entirely (device row; everything cascades); --force when claims were already sent
cargo run --bin stellwerk -- ngo-report bahnhofsmission statement.csv   # import the NGO's statement (CSV date,amount,reference,counterparty; amount "4,50" or "4.50"); matches confirm claims
cargo run --bin stellwerk -- scan                  # one deadline-scanner pass now (the loop runs hourly)
```

Every Stellwerk change is pushed to the app immediately over `GET /v1/events` (server-sent events per customer: location, ride, incident, claim, mail, clock, reset). The app keeps that stream open in local mode and refreshes the screen an event names; polling stays as the fallback.

Env: `STELLWERK_URL` (default `http://127.0.0.1:8080`), `ADMIN_TOKEN` (default `stellwerk`, same on the server). Customers can be addressed by nickname, id prefix or relay address. Clock shifts are global and one-way for expiry: an incident marked `verfallen` under a shifted clock stays so; use `reset`. Tables: `sim_trip_overrides`, `sim_clock` (migration 0014). Admin routes live under `/admin/*` and must not be exposed publicly.

## Loops

- Trip follower: every 45 s, every ride in `riding` is polled; snapshots go to `ride_snapshots`; at the exit stop the ride is finalised and an incident is created when the rules say so.
- Deadline scanner (`src/scanner.rs`): hourly on the simulated clock, first pass 30 s after start, `POST /admin/scan` or `stellwerk scan` for one pass now. It warns 21 days before an incident's legal deadline (`incidents.warned_at`, SSE `incident {incident_id, warning: true, legal_deadline}`), marks open incidents `verfallen` at the deadline for every customer, nudges once when a sent claim passed `expected_reply_by` without an inbound mail (`claims.nudged_at`, SSE `claim {claim_id, nudge: true}`), and sweeps retention.
- Retention: when a claim becomes accepted or rejected (inbound mail, Stellwerk reply, NGO report) the bytes of its uploads and of the inbound mails' attachments are deleted unless the customer set `keep_correspondence`. Ledger, claim, mail and audit rows stay; an upload still attached to another open claim is kept.
- Monthly cap: on every status refresh (incident creation, ledger read, scanner) Deutschlandticket incidents are summed per calendar month in ride order; from the one that pushes the month over 25 % of the ticket price they are `gedeckelt`, and released again when an earlier one is rejected or expires. The ledger summary reports `capped_cents`.
- NGO report import: `POST /admin/ngos/{id}/report` with `{transfers:[{date, amount_cents, reference, counterparty}]}` (or CSV). A transfer matches a sent claim of that NGO with exactly that amount, sent within the 60 days before the transfer, oldest unmatched first; a reference naming the claimant or the claim id prefix wins. Matches become `accepted` with the confirmed amount, incidents `bestaetigt` (audit "ngo report"), the badge is awarded, the customer gets incident and claim events, retention runs; one `ngo_reports` row (rows, matched) per import. Answer: `{matched:[claim ids], unmatched:[transfers]}`.
- Boards (`GET /v1/boards?scope=`): seven-day sums of `points` over location-verified rides finalised in the last seven days, per customer with `show_on_boards`. `line` = rides on my most frequent line of the last 30 days, `city` = rides starting at a station whose first word matches my home station's, `germany` = all; a scope with nothing to narrow on falls back to all. Filled from `board_seed` (entries carry `seed: true`) up to ten entries; the requesting customer always appears with `is_me`.
- Inbound mail: `POST /internal/inbound-mail` (JSON) and `POST /internal/inbound-mail/raw` (the RFC 822 message, parsed with mail-parser; attachments stored as uploads of kind `inbound`).
- Push tokens: `PUT/DELETE /v1/me/push-token` stores the platform and token on the device row.
- Push delivery (`src/push.rs`): one task taps the event bus and sends for five events: arrival (`+68 · RE 7` / `68 Geduldspunkte. Anspruch entstanden: 1,50 € für …`), post from the railway (`4,50 € bestätigt. Geht an …`, Rückfrage, abgelehnt, bounce), the 21-day deadline warning, the reply nudge, the NGO confirmation. APNs over HTTP/2 with token auth (`a2`), FCM HTTP v1 with a service-account JWT. A token the provider reports dead (APNs 410 / `BadDeviceToken` / `Unregistered`, FCM `UNREGISTERED`) is removed from the device row. `notifications = false` on the customer mutes everything. Without `APNS_*`/`FCM_*` every push is one `push (dry-run)` log line with title and body. `stellwerk push <customer> [text]` sends a test.
- Inbound JSON webhook: `/internal/inbound-mail` takes our own shape or Postmark's inbound payload as posted (with `RawEmail` present the original MIME is parsed); `/internal/inbound-mail/raw` takes the bare RFC 822 message. Both guarded by `?secret=INBOUND_SECRET`.
- SMTP: `smtps://` (implicit TLS, 465), `smtp://` (STARTTLS, 587), `smtp://host:1025?starttls=no` for a local sink. `scripts/smtp-sink-check.sh` drives three rides, a claim and a send against `scripts/smtp-sink.py` and checks envelope sender, desk recipient, the BCC as a separate RCPT with no `Bcc:` header, and the attached `EU-Antrag.pdf`.

## Deploying

`deploy/` has the Dockerfile (multi-stage, fonts and migrations embedded), a compose file with Postgres 17, the API and Caddy for TLS, `.env.example` with every variable, and a README with the DNS records for the API host and the mail domain (SPF, DKIM, DMARC, MX to Postmark), the inbound webhook, backups and the update procedure.

## Stellwerk targets

`stellwerk` talks to the local backend by default (`--dev`: http://127.0.0.1:8080, token `stellwerk`).
`stellwerk config init --ssh verspaetomat` writes `~/.config/verspaetomat/stellwerk.toml` with a `prod`
target (URL and the server's `ADMIN_TOKEN`, read once over SSH); then `stellwerk --prod …`.
`--target NAME`, `STELLWERK_TARGET`, `--url` and `ADMIN_TOKEN` override.

## Needs external setup

Everything else works; these need an account and go into `deploy/.env`:

| What | You produce | Env |
|---|---|---|
| Outbound mail | Postmark server token (or SES SMTP credentials); domain verified with SPF, DKIM, Return-Path | `SMTP_URL=smtps://TOKEN:TOKEN@smtp.postmarkapp.com:465` |
| Inbound mail | MX for `verspaetomat.de` to the provider; webhook URL with the secret | `INBOUND_SECRET` |
| Push, iOS | APNs auth key `.p8`, its key id, the team id, the bundle id | `APNS_KEY_P8` (or `APNS_KEY_P8_BASE64`), `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC`, `APNS_SANDBOX` |
| Push, Android | Firebase service account JSON with the Cloud Messaging role | `FCM_SERVICE_ACCOUNT_JSON` |
| Stellwerk on the server | a long random token | `ADMIN_TOKEN` |
| Träwelling | OAuth client registration | not wired yet |
| App Attest / Play Integrity | Apple and Google console setup | not wired yet; per-device rate limits only |
