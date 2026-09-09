# 21 — Data requirements, derived from the mock

Everything the showcase app reads from `Mock` or from `DemoState`, turned into what a backend must store, compute or fetch. Source: `app/lib/mock/mock_data.dart`, `app/lib/state/demo_state.dart`, and every `Mock.*` / `state.*` access in `app/lib/screens`. Endpoint names refer to `backend/openapi.yaml`.

## 1. Entities

### Customer (`me`)

| Field | Mock today | Backend | Origin |
|---|---|---|---|
| id, device token | — | required | created on first launch, `POST /v1/devices` |
| name | `Mock.userName` | optional nickname | customer |
| relay address | `Mock.relayAddress` | assigned at first claim, unique, permanent | server |
| private e-mail | `Mock.userEmail` | required at first claim | customer |
| postal address | `Mock.userAddress` | required at first claim | customer |
| ticket type | `state.ticket` | required | customer, changeable per ride |
| ticket number | `Mock.ticketNumber` | required for season tickets at first claim | customer |
| default NGO | `state.ngoId` | required | customer |
| settings | `locationMode`, `notificationsGranted`, `showOnBoards`, `keepCorrespondence` | required | customer |
| onboarding done, personal data entered | `onboardingDone`, `personalDataEntered` | derived | server |
| Träwelling link | `traewellingLinked` | optional OAuth token, read-only | customer via Träwelling |
| push token | — | required for arrival, reply and deadline pushes | device |
| points total, points this week, level | `Mock.pointsTotal`, `pointsThisWeek`, `levelName`, `nextLevelAt`, `bonusPoints` | derived from rides | server |

### Station

`Mock.nearbyStations`: id, name, distance, EVA number. Backend: id, name, EVA/IBNR, lat/lon, country, `GET /v1/stations/nearby`. Source: DB RIS::Stations or DELFI stop directory, imported nightly. Home station (`Mock.homeStation`) is derived from check-in frequency.

### Departure and trip

`Mock.departuresKoelnHbf`: id, line, destination, planned time, platform, category (S, RB, RE, Fern, Bus), operator, delay, cancelled, cause, stops (name, planned time). Backend: `GET /v1/stations/{id}/departures` and `GET /v1/trips/{id}` with per-stop planned and forecast times, cancellation flags and cause text. Source: Transitous / gtfs.de now, RIS::Journeys later. The operator name per trip is mandatory because it decides the claims desk.

### Operator and claims desk

`Mock.desks`, `Mock.deskAddresses`, `Mock.deskFor`: operator → desk name; desk → postal address and e-mail. Backend: an operator directory table maintained as content (`GET /v1/operators`): operator, desk (Servicecenter or own), postal address, e-mail for the EU form, accepts-e-mail flag, notes, last verified date. Source: docs/04-operators.md and manual verification.

### Ride

`state.trip`, `liveDelay`, `passedStops`, `liveCause`, `finalDelay`, `finalCancelled`, `finalSelfEntered`, `Mock.rides` / `state.rides` (date, line, from, to, delay, cancelled, verified). Backend: ride id, customer, trip id, operator, line, from station, exit stop, ticket type at check-in, checked-in at, location fix (lat/lon/accuracy, optional), status (`riding`, `arrived`, `abandoned`), planned and actual arrival, final delay, cancelled, self-entered, cause, source and timestamp of the delay evidence, points earned, verified flag, Nachtrag flag, Träwelling import id. `POST /v1/rides`, `GET /v1/rides/current`, `PATCH /v1/rides/{id}` (change train), `POST /v1/rides/{id}/arrival` (manual time), `POST /v1/rides/nachtrag`, `GET /v1/rides`.

### Incident (a claimable delay)

`Mock.incidents` / `state.incidents`: id, date, line, from, to, delay minutes, amount, ticket, operator, desk, status, planned and actual arrival, cancelled, self-entered, NGO id, bundle id, fare. Backend adds: ride id, legal deadline, warning sent at, cap flag, evidence snapshot (planned, actual, source, fetched at), first-class flag. Derived views the app uses: `openIncidents`, `openByDesk`, `openAmountFor(desk)`, `bundleReady(desk)`, `readyDesk`, `confirmedTotal`, `submittedTotal`, `oldestOpen`, `daysUntilOldestExpires`. `GET /v1/incidents` returns the list plus that summary so the app does not recompute rules.

### Claim (a sent bundle)

`draftDesk`, `draftIncidentIds`, `draftTicketAttached`, `draftNgoId`, `draftSigned`, `draftAmount`, `lastSentBundleId`. Backend: claim id, customer, desk, incident ids, NGO (account holder, IBAN snapshot at send time), ticket months covered, attachments (one ticket image per month, or the ordinary ticket), signature image or typed name, generated PDF, status (`draft`, `sent`, `question`, `accepted`, `rejected`, `bounced`), sent at, expected reply by, reply mail id, amount claimed, amount confirmed, closed at. `POST /v1/claims/draft`, `POST /v1/claims/{id}/attachments`, `PATCH /v1/claims/{id}`, `GET /v1/claims/{id}/preview.pdf`, `POST /v1/claims/{id}/sign`, `POST /v1/claims/{id}/send`, `POST /v1/claims/{id}/postal-reply`.

### Mail

`Mock.mails` / `state.mails`: id, incident ids, direction, from, to, subject, body, date, attachments, amount, outcome. Backend: mail id, claim id, direction, message id, in-reply-to, from, to, bcc, subject, body text, attachments (object keys), received/sent at, classification (`accepted`, `question`, `rejected`, `bounce`, `other`) with confidence, extracted amount and reference, forwarded-to-customer at. `GET /v1/mails`, `GET /v1/mails/{id}`, `POST /v1/mails/{id}/reply`, internal `POST /internal/inbound-mail`.

### NGO

`Mock.ngos`: id, name, tagline, story paragraphs, account holder, IBAN, confirmed total, submitted total, donation URL, last report date. Backend adds: dedicated IBAN per NGO for Verspätomat claims, written consent date, contact, active flag, monthly report imports. `GET /v1/ngos`. Totals are derived from claims.

### Badge

`Mock.badges`: id, name, rule, earned, earned on. Backend: badge catalogue (id, name, rule text, data dependency) and awards per customer (badge id, ride id, awarded at). `GET /v1/badges`, `GET /v1/me/badges`. Awards are computed by the trip follower at arrival and by the claim flow (first send, first confirmation).

### Boards and community

`Mock.boardLine`, `boardCity`, `boardGermany` (rank, name, points, is me), `Mock.communityMinutes`, `communitySubmitted`, `communityConfirmed`, `communityUsers`, per-NGO confirmed and submitted totals. Backend: rolling seven-day sums per customer, scoped by line, city and country, verified rides only, respecting `showOnBoards`; community aggregates recomputed every minute. `GET /v1/boards?scope=&key=`, `GET /v1/community`.

### Team

`Mock.teams`: id, name, members, minutes, euros, top member. Backend: team id, name, invite link token, members, created by; aggregates derived. `GET /v1/teams`, `POST /v1/teams`, `GET /v1/teams/{id}`, `POST /v1/teams/join`.

## 2. What each screen needs

| Screen | Reads | Writes |
|---|---|---|
| Willkommen, Berechtigungen | nothing | device creation, permission states |
| Setup | ticket types, NGO list with confirmed totals | ticket, default NGO |
| Bahnsteig | nearby stations, current ride, points this week, ledger summary, community line, offline flag | nudge dismissals, muted stations |
| Einchecken | departures at a station with live delays, ticket type | check-in (ride) with optional location fix |
| Wo steigst du aus? | trip stops | exit stop |
| Unterwegs | current ride live state (delay, passed stops, cause, ETA) | change train |
| Angekommen | final delay, points, new badge, claim amount and bundle state for the desk | dismiss; manual arrival time when no data |
| Nachtrag | past departures for a date and station | Nachtrag ride |
| Konto | incidents grouped by desk with summary, confirmed and submitted totals, deadline, sent dates and expected reply per bundle, evidence per incident | start a draft |
| Antrag | draft, desk address, personal data, ticket months required, NGO account details, form preview, mail preview with BCC | personal data, attachments, NGO override, signature, send |
| Antwort | mails for a claim, classification, amount, templates | customer reply, postal reply upload |
| Wir | community aggregates, per-NGO totals, boards, teams | create team |
| Zweck | NGO detail and totals | set default NGO |
| Team | team aggregates and members | share link |
| Ich | profile, points, level, badges, statistics from rides, teams | — |
| Alle Fahrten | rides with delays, cancellations, verified flag | — |
| Einstellungen | settings, personal data, relay address, Träwelling link state | all settings, delete account, export |
| Woher kommen die Daten? | static content | — |

## 3. External sources the backend must integrate

| Need | Source | Notes |
|---|---|---|
| Departures, trip live data, operator per trip | Transitous (MOTIS API), gtfs.de realtime (protobuf); DB RIS::Journeys later | abstraction trait with two implementations |
| Stations and coordinates | DB RIS::Stations (CC BY 4.0) or DELFI ZHV | nightly import |
| Operator → desk, addresses, e-mails | content table from docs/04 | verified manually, dated |
| Claim form | EU standard form structure reproduced in a Typst template | signature embedded |
| Outbound mail | transactional provider over SMTP | relay domain with SPF/DKIM/DMARC; BCC to the customer |
| Inbound mail | provider inbound webhook | per-customer relay address routing |
| NGO statements | monthly CSV or PDF from each NGO | matched by amount, date, claimant |
| Träwelling check-ins | Träwelling REST API with the customer's token | read-only; IBNR to station mapping |
| Push | APNs, FCM | arrival, reply, deadline, NGO confirmation |

## 4. Things the mock has that the backend does not need

Demo controls (`tickRide`, `simulateArrival`, `receiveReply`, `reset`, `toggleOffline`), the fixed "today" (`Mock.today`), date formatting helpers, and the showcase index.

## 5. Things the backend needs that the mock never had

- Device identity and bearer tokens; account deletion and export (GDPR).
- Push tokens and notification preferences.
- Uploads: ticket images, signature, postal-reply photos; object storage keys and retention.
- Station geodata and the nearby query.
- The operator directory as data, with a "last verified" date and an "unknown operator" path (the app's E5).
- Trip identity across feeds (Transitous trip id vs gtfs.de trip id vs later RIS) and the station id mapping (IBNR, EVA, DELFI, Träwelling).
- Evidence snapshots per incident (what the feed said, when), because they go on the claim and may be questioned.
- The relay: message ids, threading, bounce handling, classification confidence, forwarding records.
- The 25 % monthly cap and first-class amounts, which the mock ignores.
- Audit log of every status transition on incidents and claims.
- Rate limits on check-ins per device and on claim sends.
