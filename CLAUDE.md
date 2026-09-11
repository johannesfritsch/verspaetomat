# Verspätomat — working notes for Claude and humans

Gamified train check-in app for Germany. Delays earn Geduldspunkte; delays of 60 minutes or more become statutory Fahrgastrechte claims whose payee is a partner NGO. The app is a messenger, never a representative: it fills and relays, it never writes to a railway on its own. Product docs live in `docs/` (start at `docs/README.md`); the design language is `app/STYLE.md` (paper white, ink, one red, Archivo, the Bahnhofsuhr).

## Layout

| Path | What |
|---|---|
| `backend/` | Rust (axum, sqlx/Postgres 17). Migrations and fixtures embedded. `src/bin/stellwerk.rs` is the admin CLI. |
| `app/` | Flutter. Demo mode (mock, no server) and local mode (HTTP). Native geofence layers in `ios/Runner/Geofence.swift` and `android/.../GeofenceManager.kt`. |
| `site/` | The website at verspaetomat.de: a Rust generator (`cargo run`) that writes the committed `site/dist`, which Caddy serves. The legal texts come from `app/lib/content/legal.dart`. |
| `deploy/` | docker compose for one VPS (Postgres, API, Caddy), `.env.example`, README with DNS and Postmark steps. |
| `docs/` | Research 01–08, product 10–15, backend 20–21, plans and runbooks 30, 40, 41, 42. |

## Everyday commands

```bash
# backend on 127.0.0.1:8080 (Homebrew postgresql@17, DB "verspaetomat", ADMIN_TOKEN=stellwerk)
cd backend && ./dev.sh
cargo build --bins && cargo test && cargo clippy --bins      # must be warning-free

# admin CLI against the local backend
backend/target/debug/stellwerk customers | locate <who> "Köln Hbf" | delay <who> 68 | ff <who> | reply <who> accepted | reset <who> | forget <who> | push <who> | scan

# app on the iOS simulator, local mode
cd app && flutter run -d <simulator udid> --dart-define=API_URL=http://127.0.0.1:8080 --dart-define=BACKEND=local --dart-define=INITIAL_ROUTE=/bahnsteig
flutter analyze                                              # must be clean

# workflow E2E (uses its own keychain slot and customer; drives the world through Stellwerk)
flutter test integration_test/workflow_test.dart -d <udid> --dart-define=API_URL=http://127.0.0.1:8080 --dart-define=BACKEND=local --dart-define=NO_LOCATION=1 --dart-define=E2E=true --dart-define=ADMIN_TOKEN=stellwerk --dart-define=INITIAL_ROUTE=/bahnsteig

# one screenshot per screen (Demo mode) for visual passes
app/tools/tour.sh
```

Dart-defines: `API_URL`, `BACKEND=local`, `INITIAL_ROUTE`, `NO_LOCATION=1` (string compare), `E2E=true`, `ADMIN_TOKEN`. Release builds default to local mode and start at Willkommen/Bahnsteig; debug builds default to Demo and the Showcase.

## Production

- API: `https://api.verspaetomat.de` (Caddy with Let's Encrypt in front of the container). `/admin/*` is reachable and guarded by the long random `ADMIN_TOKEN`.
- Deploy: push to `main`, then `ssh verspaetomat /opt/verspaetomat/deploy/deploy.sh` (pull, rebuild only the API, reload Caddy, print status). The server builds the image from source; nothing is transferred. Migrations run on start.
- Stellwerk against production: `stellwerk --prod …` after a one-time `stellwerk config init --ssh verspaetomat`. `--dev` is the default. NGOs are managed data: `stellwerk --prod ngo list|set|import|remove`; the fixture only seeds an empty table.
- iOS release: `app/tools/release.sh` (App Store Connect API key in `~/.config/verspaetomat/release.env`, key file in `~/.appstoreconnect/private_keys/`), build number = last uploaded build + 1 (git tags ios-<version>-<build>).
- Checks: `curl https://api.verspaetomat.de/health`; `stellwerk --prod customers`; `ssh verspaetomat 'cd /opt/verspaetomat/deploy && docker compose logs --tail 50 api'`.
- Secrets live only in `deploy/.env` and `deploy/secrets/` on the server. Mail (Postmark) and push (APNs, FCM) are switched on by uncommenting the lines there; see `deploy/README.md` and `docs/42-runbook-vps-testflight.md`.
- Never `docker compose down -v` (drops the database). Backups: nightly `pg_dump` in `/var/backups` on the server.

## Rules that are easy to break

- The backend owns every money rule (`backend/src/rules.rs`); the app never recomputes amounts or readiness.
- The server never guesses a location; no default station (docs/14). The native geofence layer never talks to the admin API (docs/15).
- No streaks, no campaigns, no employer matching, no teams: removed on purpose.
- Test customers: the E2E resets only its own customer. Do not reset or locate other people's customers without saying so.
- Sub-screens use the standard header (caption eyebrow + h2 title); tabs use `TabHeader`. Figures in pairs share one size. See the visual pass notes in docs/30.
