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
| Stations | Our own `stations` table, imported from the Transitous GTFS feeds by `stellwerk stations import` (issue #37, docs/44). Held in memory and scanned; no PostGIS — eight thousand rows do not need an index |
| Outbound mail | `lettre` over SMTP to a transactional provider (Postmark, Mailgun or SES) with SPF, DKIM, DMARC on the relay domain |
| Inbound mail | Provider inbound webhook → `POST /internal/inbound-mail` (JSON) or `/internal/inbound-mail/raw` (RFC 822, parsed with `mail-parser`); attachments as uploads of kind `inbound` today, object storage later |
| PDF | Typst template rendered server-side; signature PNG embedded |
| File storage | Ticket images, signatures and inbound attachments as files under `UPLOAD_DIR` (a Docker volume on the VPS), one per upload id; the row keeps the path, not the bytes. No application-level encryption: the host disk is encrypted and retention deletes the file. S3 later if one host stops being enough |
| Push | APNs over HTTP/2 with token auth (`a2`, ring) and FCM HTTP v1 (service-account JWT via `jsonwebtoken`, `reqwest`); `backend/src/push.rs`; dry-run without credentials |
| Auth | Anonymous device accounts with a bearer token; optional e-mail sign-in later for backup |
| Observability | `tracing` with JSON logs, OpenTelemetry export |
| Deployment | `deploy/`: multi-stage Dockerfile, compose with Postgres 17 + API + Caddy (TLS, `/admin` hidden), `.env.example`, README with DNS/mail/backup/update steps |

## Service layout

One binary, several loops:

- **API** — the routes in `backend/openapi.yaml`.
- **Trip follower** — for each ride in `riding`, poll the trip every 30 to 60 s, store the latest stop-by-stop forecast, detect arrival at the exit stop (forecast turned actual, or the trip's next stop is beyond the exit stop), finalise the delay, create an incident when the rules in 21 say so, send the arrival push.
- **Relay** — outbound queue (send claim mails with BCC, retry, record message ids), inbound processing (match by relay address and claim reference, read the answer per ride — see below —, forward the original to the customer's private inbox, update the claim).
- **Deadline scanner** (`backend/src/scanner.rs`, shipped 10 September 2026) — hourly on the simulated clock: warn 21 days before an incident's legal deadline (once, `warned_at`), mark `verfallen` at the deadline across all customers, nudge once when a sent claim passed its expected reply date without an answer (`nudged_at`), sweep retention. Events go out over SSE.
- **Push sender** (`backend/src/push.rs`, shipped 10 September 2026) — taps the event bus and turns events into notifications: arrival, post from the railway, a confirmed payment, deadline warning, reply nudge. Copy is composed server-side in the app's voice; the payload carries `kind` and the id so the app opens the right screen. APNs (token auth) and FCM v1; dead tokens are removed; `notifications=false` mutes; no credentials means one log line per push. `stellwerk push` for a test.
- **Confirmation comes from the railway's answer, and from nothing else** (`reply.rs`). The desk
  writes that it pays or has paid; that is read, and the claim becomes `accepted`, each paid ride
  `bestätigt` at the figure the desk wrote for it (`incidents.confirmed_cents`), each refused ride
  `abgelehnt`, the badge is awarded and the passenger's and the Verein's totals move. There is no
  second path and no manual confirmation.
  - Two readers. The rules (`classify.rs`) read every mail. With `OPENAI_API_KEY` set, a model
    (`openai.rs`, pinned snapshot `gpt-5.4-mini-2026-03-17`, `OPENAI_MODEL` overrides) reads it too
    and decides, per ride. Without a key the rules decide alone. When the call fails or runs out of
    its 25 s budget, the rules may refuse, ask or pass a mail on but never confirm money; the mail
    waits for `stellwerk reread <mail>` (`stellwerk replies` lists the latest answers and why).
  - Our own words out first (`redact::without_ours`): every line of an answer that is text from a
    mail we sent — the claim, a reply written in the app — is removed before anything reads it, so
    a desk system that echoes our claim, or relays back what the passenger wrote, cannot pass it off
    as the desk's decision.
  - Two readers must agree before a claim is accepted or refused: when the first model's reading
    survives the gate as a payment or refusal, a second, larger model (`OPENAI_CONFIRM_MODEL`,
    pinned `gpt-5.5-2026-04-23`) reads the same text, and only the same outcome with the same rides
    and figures counts. In testing most misreadings were a model's mood (two runs in three).
  - The model proposes, the gate decides (`reply::gate_model`). Money moves only if the sentence the
    model quotes is in the mail, every amount it names is written in the mail as money, the ride
    amounts add up to the total, no ride gets more than was claimed for it (the fare is not the
    payment), and the rules do not read the opposite. Anything else is `other`.
  - What the model sees (`redact.rs`): subject and the desk's own part of the mail, without the quoted
    history, without the passenger's name, address, e-mail, ticket number, relay addresses, and
    without anything shaped like an e-mail address, IBAN, phone number or a name in a salutation;
    plus date, train, stations and minutes of each claimed ride. `store: false`. The text shown and
    the raw answer are kept on the mail (`mails.read_by`, `mails.reading`).
  - Every rule and every check fails towards "a human should read this". A wrong `accepted` tells
    somebody their delay became money that never arrived and adds it to a Verein's public total; a
    wrong `other` costs one look at an inbox.
  - Order is the design: a bounce is judged on the envelope first, because a delivery failure quotes
    the mail it could not deliver; automatic and interim replies next; refusal before payment,
    because a refusal often explains what would have been paid.
  - The amount is the one the desk named, never the one we claimed, and it is recorded per ride.
    A rules reading of several rides confirms them only when the named figure is exactly the claim;
    a partial award needs the model's per-ride reading.
  - Only the desk moves a claim: a mail that would accept, refuse or ask has to come from one of the
    route's answer domains — the domain the claim was sent to, plus the domains added with
    `stellwerk route answers "<Schalter>" --add deutschebahn.de` (subdomains count; free-mail
    providers are refused) — **and** carry the receiving provider's verification of that domain:
    SpamAssassin's `DKIM_VALID_AU` in Postmark's `X-Spam-Tests`, present exactly once, on a webhook
    guarded by `INBOUND_SECRET`, with exactly one mailbox in From (`handlers::sender_auth`, all
    copies stored in `mails.sender_auth`). `Received-SPF` and
    `Authentication-Results` are ignored — nothing says the provider writes them, so a copy may be
    the sender's. A mail that fails is recorded and moves nothing: the passenger holds the reply
    address too, and a From header is only text. Check the first real answers in `stellwerk
    replies` ("Absender geprüft"); a desk that does not DKIM-sign its mail, or a Postmark stream
    without spam headers, shows "nein" for every answer and needs a decision, not a workaround.
  - A claim already accepted or refused is not re-decided by a later mail (the claim row is locked
    while the answer is written), a delivery with a known message id is not read twice (a unique
    index), and the forward to the passenger goes out before anything that could fail after commit.
  - Where the vetoes look: everything the desk wrote except the quoted claim — below a signature, a
    line of dashes or a ticket system's echo too — but only in sentences that talk about money or
    the claim, so a footer's "nicht an Dritte weitergegeben" blocks nothing. Stops (a voucher, a
    payment made before or to someone other than the Verein, a claim passed to another desk) and
    conditions ("sofern", "sobald", "unter Vorbehalt", "nach Eingang Ihrer Kopie") keep money from
    moving; a payment phrase negated anywhere later in its sentence is no payment. The model reads
    the same text minus the echo of the passenger's own message.
  - `stellwerk reread <mail>` reads a stored answer again (for mail that arrived while the model was
    unavailable); a mail whose claim is closed or gone is read but not changed. Replies planted by
    `stellwerk reply` are read by the rules only, so end-to-end tests need no network.
  - Trying a real answer without touching a claim: `stellwerk read-mail mail.txt --date 2026-09-03
    --claimed 150`, or against a real claim: `--to antrag-…@users.verspaetomat.de` finds it the way
    the webhook does (claim address first, then the passenger's older address and their newest open
    claim), `--claim <id>` names it directly.
  - Removed: the NGO bank-statement import (`POST /admin/ngos/{id}/report`, `stellwerk ngo-report`,
    the `ngo_reports` table). It required a monthly CSV from each Verein, which they will not send.
- **Backdated test data** (`POST /admin/customers/{key}/backdate`, `stellwerk backdate`, shipped 13 September 2026) — a ride that already happened, with the delay it had: an arrived journey, its one leg and the case the rules allow, so bundles, the monthly cap, deadlines and the claim form can be tested without waiting for a real train. No feed is consulted; the evidence names the Stellwerk and the case counts as self-entered, so no claim ever dresses invented data up as live data.
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
- **Where mail goes is data, not code.** The destination of every outbound claim mail comes from the
  `mail_routes` table and from nowhere else — no fixture seeds it, no migration inserts into it, and
  no railway address exists anywhere in this repository. An empty table means nothing can be sent,
  which is the correct state for a system nobody has told where to send. Manage it with
  `stellwerk route list | set <desk> <address> [--label …] | default <address> | remove <desk>`, and read the
  answer to "where does this actually go" straight out of `route list`.
  - **Routing knows nothing about a rehearsal** (#25). A desk has an address and mail goes to it —
    one behaviour, no flag. `mail_routes.live` is gone: it first changed nothing but a subject line,
    then briefly decided delivery, and both were the same mistake. A demo is something the app does,
    not a property of a destination. The walkthrough („Vorführung ansehen") runs on the mock
    repository, which has no HTTP client at all, so it cannot reach this server — and the Senden
    step of a real claim shows the exact address the server will use.
  - **One catch-all** (#25): the row keyed `*`, set with `stellwerk route default <address>`, is
    where a desk with no route of its own sends. It is an ordinary row in the same table, printed
    first by `route list` as „Auffanglinie", so the fallback is not a second mechanism to remember.
    A desk with its own route always wins over it. The draft says `desk_route_via_default` when the
    catch-all answered, and the app prints that on the step that names the desk — so "nobody has
    looked this operator up yet" is visible rather than silently absorbed. Answers are matched
    through the same resolver, or a claim sent on the catch-all could never be confirmed.
  - This replaced `CLAIM_MAIL_REDIRECT`, an optional environment variable that had to be remembered
    to be safe and failed open when it was not: unset, empty, whitespace, missing `@`, or the name
    typed wrong all sent to the railway silently. Two paths never consulted it at all — answering an
    inbound mail went to whatever `From` that mail carried, which for a `stellwerk reply` rehearsal
    was a real address, and `stellwerk mail-test` took any address given. All three now read the
    table; `mail-test` refuses an address no route points at.
  - The passenger sees the route's address on the Senden step, because that is the address the mail
    will really go to — sender, receiver and copy, all three, with nothing added and nothing hidden.

## What the backend does not do

- No payments, no wallets, no donation processing.
- No GPS during rides. The only location the server ever sees is the optional one-shot fix at check-in.
- No automatic follow-ups to railways, no disputes, no chasing.
- No campaigns, no employer matching, no streaks (decided 9 September 2026).
