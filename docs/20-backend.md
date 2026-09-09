# 20 — Backend: stack decision and architecture

Decided 9 September 2026. The skeleton lives in `backend/` (see `backend/README.md`). The data it must hold and serve is inventoried in [21-data-requirements.md](21-data-requirements.md).

## Decision: Rust

Rust, with axum on tokio, Postgres via sqlx, and a single deployable binary.

Why it fits this product better than Go or Node:

- **The core job is long-running and concurrent.** For every active ride the server follows one trip through live delay feeds every 30 to 60 seconds until the exit stop. Thousands of rides in the morning peak, near-zero at night. Tokio handles that cheaply, and GTFS-RT is protobuf, which `prost` decodes natively.
- **The ledger is money-adjacent.** Amounts, thresholds, deadlines and status transitions must never be silently wrong. Rust's type system (no nulls, exhaustive matches, newtypes for cents and minutes) and sqlx's compile-time checked queries catch the class of bug that would otherwise reach a claim form.
- **Mail is first-class.** Outbound via SMTP (`lettre`), inbound via a mail provider's webhook parsed with `mail-parser`. Both are mature crates.
- **Operations cost.** One static binary, tens of megabytes of memory, no runtime to patch. This is a side project that must run unattended for months.
- **PDF generation.** The claim document is generated with Typst (a Rust library), which produces clean, deterministic PDFs from a template. This sidesteps AcroForm filling, which is the one place Node (`pdf-lib`) would have been easier. The EU form's content and section structure are reproduced; the customer signs the generated document.

Where Rust costs more: development speed for a solo developer new to it, and slower compile cycles. Go would be the honest second choice (fast to write, excellent HTTP and mail libraries, weaker typing for money). Node would only win on AcroForm filling. Neither outweighs the reasons above.

## Stack

| Concern | Choice |
|---|---|
| HTTP | axum 0.8, tower-http (CORS, tracing, compression) |
| Runtime | tokio |
| Database | Postgres 16, sqlx with migrations; one schema per entity in 21 |
| Live train data | Transitous (MOTIS) HTTP API and the gtfs.de realtime protobuf feed via `prost`; DB RIS::Journeys behind the same trait later |
| Stations | DB RIS::Stations or DELFI stop directory, imported nightly into Postgres with PostGIS for "nearby" |
| Outbound mail | `lettre` over SMTP to a transactional provider (Postmark, Mailgun or SES) with SPF, DKIM, DMARC on the relay domain |
| Inbound mail | Provider inbound webhook → `POST /internal/inbound-mail` (JSON) or `/internal/inbound-mail/raw` (RFC 822, parsed with `mail-parser`); attachments as uploads of kind `inbound` today, object storage later |
| PDF | Typst template rendered server-side; signature PNG embedded |
| Object storage | S3-compatible (ticket images, signatures, PDFs, inbound attachments), encrypted at rest, keyed per claim |
| Push | APNs (`a2`) and FCM HTTP v1 (`reqwest`); today only the token is stored (`PUT /v1/me/push-token`), no sender |
| Auth | Anonymous device accounts with a bearer token; optional e-mail sign-in later for backup |
| Observability | `tracing` with JSON logs, OpenTelemetry export |
| Deployment | Docker image, one container plus Postgres, behind a reverse proxy |

## Service layout

One binary, several loops:

- **API** — the routes in `backend/openapi.yaml`.
- **Trip follower** — for each ride in `riding`, poll the trip every 30 to 60 s, store the latest stop-by-stop forecast, detect arrival at the exit stop (forecast turned actual, or the trip's next stop is beyond the exit stop), finalise the delay, create an incident when the rules in 21 say so, send the arrival push.
- **Relay** — outbound queue (send claim mails with BCC, retry, record message ids), inbound processing (match by relay address and claim reference, classify accepted / question / rejected / bounce, extract amount, forward the original to the customer's private inbox, update the claim).
- **Deadline scanner** (`backend/src/scanner.rs`, shipped 10 September 2026) — hourly on the simulated clock: warn 21 days before an incident's legal deadline (once, `warned_at`), mark `verfallen` at the deadline across all customers, nudge once when a sent claim passed its expected reply date without an answer (`nudged_at`), sweep retention. Events go out over SSE; a push sender can hang off the same events later.
- **NGO report matcher** (`POST /admin/ngos/{id}/report`, `stellwerk ngo-report`, shipped) — import of each NGO's statement as JSON or CSV; match transfers to sent claims by amount, a 90-day window and the claimant's name or claim reference; mark `bestätigt`; SSE event. Imports are recorded in `ngo_reports`.
- **Aggregates** — community totals and seven-day boards computed on read from the rides and incidents tables (boards: real customers first, seeded rows fill the list).
- **Retention** (shipped) — delete attachment bytes and inbound-mail attachments when a claim closes, unless the customer set "keep correspondence"; ledger, claim, mail and audit rows stay.

## Rules the backend owns (single source of truth)

- Claim amount per ticket type and category: D-Ticket 1.50 € (2.25 € first class); other season tickets 1.50 € regional or 5.00 € long-distance; ordinary tickets 25 % of the fare at 60 min, 50 % at 120 min.
- Bundle readiness: an ordinary-ticket incident is always ready; season-ticket incidents are ready when the open sum for that claims desk reaches 4.00 €.
- Monthly cap: at most 25 % of the ticket price per D-Ticket month; incidents beyond the cap are recorded but marked `gedeckelt` (in ride order per calendar month, rejected and expired ones not counted; released when an earlier one drops out). Enforced in `rules::apply_monthly_cap` on every status refresh.
- Deadlines: legal 3 months from the ride, warning at 21 days before, expiry at the deadline; DB's 12-month goodwill is noted on the incident but never relied on.
- Status machine for incidents: `gesammelt → bereit → eingereicht → bestätigt | abgelehnt`, plus `verfallen` from any open state, plus `gedeckelt`.
- Points: one per minute late from minute 1; cancellation counts as 60; Nachtrag earns 1; only rides with a location fix at the station rank on boards.
- Relay discipline: nothing is sent without a signed claim and an explicit send call; the server never composes mail to a railway on its own; every inbound mail is forwarded whole.

## What the backend does not do

- No payments, no wallets, no donation processing.
- No GPS during rides. The only location the server ever sees is the optional one-shot fix at check-in.
- No automatic follow-ups to railways, no disputes, no chasing.
- No campaigns, no employer matching, no streaks (decided 9 September 2026).
