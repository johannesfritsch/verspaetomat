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
| `INBOUND_SECRET` | unset | when set, `/internal/inbound-mail` requires `?secret=` |
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
migrations/        0001…0012, applied automatically at start (sqlx migrate)
src/main.rs        router, state, follower wiring
src/auth.rs        device tokens, recovery codes, the Customer extractor
src/db/            pool + seed (mod.rs), row types (rows.rs)
src/rules.rs       amounts, readiness, deadlines, status refresh, audit
src/handlers.rs    HTTP handlers
src/train/         Transitous client (transitous.rs), trip follower (follower.rs), shared types (mod.rs)
src/mail.rs        SMTP via lettre, dry-run without SMTP_URL
src/fixtures.rs    seed data (operators, NGOs, badges, seeded boards, community baseline) from fixtures/*.json
openapi.yaml       the contract
dev.sh             one-command dev start
```

## Loops

- Trip follower: every 45 s, every ride in `riding` is polled; snapshots go to `ride_snapshots`; at the exit stop the ride is finalised and an incident is created when the rules say so.
- Deadline scanner, NGO report import, retention: not yet (see docs/20-backend.md).

## Not yet

Typst PDF (the claim mail carries a plain-text summary), push notifications, provider inbound webhook verification beyond the shared secret, App Attest, real boards across users, the 25 % monthly cap enforcement.
