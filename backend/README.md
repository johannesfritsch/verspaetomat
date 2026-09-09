# Verspätomat backend (skeleton)

Rust, axum, in-memory. Serves the same data the showcase app uses, from JSON fixtures, and implements the ledger rules server-side (claim amounts, bundle readiness, status transitions, relay mail records). No database, no live train data, no real mail yet. The stack decision and the full data inventory are in `docs/20-backend.md` and `docs/21-data-requirements.md`; the API contract is `openapi.yaml`.

## Run

```bash
cd backend
cargo run
# → http://127.0.0.1:8080
curl -s localhost:8080/v1/stations/nearby | jq .
curl -s localhost:8080/v1/incidents | jq .summary
curl -s -X POST localhost:8080/v1/rides -H 'content-type: application/json' \
  -d '{"departure_id":"re7-0747","exit_stop":"Münster (Westf) Hbf","from_station":"Köln Hbf","location_verified":true}'
curl -s -X POST localhost:8080/v1/rides/current/arrival -H 'content-type: application/json' -d '{"delay_minutes":68}'
curl -s -X POST localhost:8080/v1/claims/draft -H 'content-type: application/json' -d '{"desk":"Servicecenter Fahrgastrechte"}'
```

There is one anonymous customer; no auth yet. Fixtures live in `fixtures/` and are embedded at compile time.

## Layout

```
src/main.rs       router, state, startup
src/model.rs      domain types (serde), mirrors docs/21
src/rules.rs      claim amounts, bundle readiness, status refresh, deadlines
src/fixtures.rs   loads fixtures/*.json
src/handlers.rs   HTTP handlers
fixtures/*.json   stations, departures, operators, ngos, badges, incidents, mails, community, boards, teams, me
openapi.yaml      the contract the Flutter app will be switched to
```

## Next steps (not in this skeleton)

Postgres with sqlx migrations, device auth, Transitous/gtfs.de trip follower, Typst claim PDF, SMTP relay with inbound webhook, push, NGO report import. See docs/20-backend.md.
