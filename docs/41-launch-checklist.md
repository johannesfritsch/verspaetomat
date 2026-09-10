# 41 — Launch checklist: what only Johannes can do

Everything in the code that can be built without an account is built (see 30 for the shipped list). What remains are accounts, keys and signatures. Ordered by lead time: start the slow ones first, they run in parallel with the rest. Each item says what to produce and where it goes.

## A. Start today, they take days

| # | Item | Why it is slow | What to hand over |
|---|---|---|---|
| A1 | **Domain `verspaetomat.de`** at a registrar with a DNS panel | DNS propagation, mail warm-up | Access to the DNS panel, or add the records from `deploy/README.md` yourself |
| A2 | **Mail provider** (Postmark recommended: one account does outbound and inbound) | Postmark approves new accounts manually, often within a day; a fresh sending domain needs DKIM verified and a few days of low volume | `SMTP_URL` (server token), the inbound webhook URL is ours, set `INBOUND_SECRET` |
| A3 | **NGO agreement** with one organisation (Bahnhofsmission Köln is the mock; pick whoever says yes first) | People, not systems | Account holder, IBAN, written consent to appear as payee on claims, a contact for the monthly statement (`stellwerk ngo-report`) |
| A4 | **Apple Developer Program** (99 €/year) | Enrolment verification takes 1 to 2 days | Team ID; then an APNs key (.p8) with Key ID; the bundle id `de.verspaetomat.verspaetomat` registered with the Push capability |
| A5 | **Google Play Console** (25 € once) | Identity verification takes days; new personal accounts must run a 14-day closed test with 12 testers before production | Service-account JSON for FCM (Firebase project) |

## B. Server (one evening)

| # | Item | Notes |
|---|---|---|
| B1 | A VPS (2 vCPU, 4 GB, Hetzner or similar) with Docker | `deploy/docker-compose.yml` runs Postgres, the API and Caddy |
| B2 | DNS `api.verspaetomat.de` → VPS | Caddy fetches the TLS certificate itself |
| B3 | Fill `deploy/.env` from `deploy/.env.example` | `ADMIN_TOKEN` must not stay `stellwerk` |
| B4 | `docker compose up -d`, then `stellwerk customers` against `STELLWERK_URL=https://api.verspaetomat.de` | Proves migrations, admin auth and the follower run |
| B5 | Backup cron from `deploy/README.md` | Off-site copy of `pg_dump` |

## C. Mail (after A1 and A2)

| # | Item | Notes |
|---|---|---|
| C1 | DNS: SPF, DKIM, DMARC for `verspaetomat.de`; MX for the relay namespace | Exact records in `deploy/README.md` |
| C2 | Postmark inbound: route `fahrgast-*@verspaetomat.de` to `https://api.verspaetomat.de/internal/inbound-mail/raw` with the secret | The parser is verified against real MIME |
| C3 | **First real claim**: your own D-Ticket incidents once the bundle reaches 4 €, payee the NGO from A3 | This single round trip validates form, relay address, classifier. The Servicecenter answers in about four weeks |

## D. App stores (after A4 and A5)

| # | Item | Notes |
|---|---|---|
| D1 | Xcode signing with the team from A4, build number, TestFlight upload | `docs/40-store-listing.md` has the privacy labels and review notes |
| D2 | APNs key into `deploy/.env` (`APNS_*`), `APNS_SANDBOX=1` for TestFlight builds | Push then leaves dry-run |
| D3 | Play: signing key, closed test track, `FCM_SERVICE_ACCOUNT_JSON` into `.env` | Data safety form from `docs/40-store-listing.md` |
| D4 | App Attest / Play Integrity | Only before public release; rate limits cover TestFlight |

## E. Content that needs your name

| # | Item | Notes |
|---|---|---|
| E1 | Impressum placeholders in `app/lib/content/legal.dart` | Name, postal address; § 5 DDG requires a summonable address |
| E2 | Named mail provider and hoster in the Datenschutzerklärung | Two placeholders in the same file |
| E3 | Träwelling OAuth client (optional for MVP) | Register at traewelling.de, hand over client id and secret |

## What I can do as soon as each item lands

- A1 + A2: verify DNS, send the SMTP sink test against the real provider, switch the relay out of dry-run.
- A3: `stellwerk --prod ngo set <id> --name … --holder … --iban … --consent YYYY-MM-DD` (NGOs live in the database, not in the repo; the fixture only seeds an empty table), then regenerate a claim PDF and check it.
- A4: nothing on my side until D1, then the TestFlight build with `API_URL=https://api.verspaetomat.de`.
- B1: I can run the deployment with you on a shared terminal; the compose file is tested locally.
