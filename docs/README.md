# Verspätomat — Documentation

Working title: **Verspätomat**. A gamified train check-in app for Germany where being late becomes giving. The app never touches money: it helps passengers file their statutory delay compensation with a partner NGO as the payee, and Deutsche Bahn (or the operator) pays the NGO directly.

Status: research, product concept and a fully mocked Flutter showcase app (`app/`, see `app/README.md`), September 2026. Chosen look: "Bahnhofsuhr" (paper white, black grotesk, one red second hand); see `app/STYLE.md`.

## Research (what we found out)

| Doc | Content |
|---|---|
| [01-idea.md](01-idea.md) | The idea, the money-flow model, the verdict |
| [02-passenger-rights.md](02-passenger-rights.md) | Compensation rules for the Deutschlandticket and ordinary tickets, the numbers |
| [03-claim-filing.md](03-claim-filing.md) | Channels, forms, bundling, proof of travel, signatures |
| [04-operators.md](04-operators.md) | Who the claim goes to, the joint Servicecenter scheme, exceptions |
| [05-legal.md](05-legal.md) | Payment law, app store rules, legal-services law, GDPR, tax receipts |
| [06-data-sources.md](06-data-sources.md) | Live train data, stations, phone constraints (brief, non-technical) |
| [07-market.md](07-market.md) | Market size, competitors, precedents, funding |
| [08-risks-and-validation.md](08-risks-and-validation.md) | Ranked risks, four-week validation plan, success criteria |

## Product (what we want to build)

| Doc | Content |
|---|---|
| [10-experience.md](10-experience.md) | The feeling of the app: tone, look, sound, principles |
| [11-screens.md](11-screens.md) | Every screen, what it shows, what the customer does there |
| [12-gamification.md](12-gamification.md) | Points, badges, boards |
| [13-where-the-data-comes-from.md](13-where-the-data-comes-from.md) | Every piece of information on screen and its origin, in customer terms |
| [14-location-concept.md](14-location-concept.md) | Where the customer is: the phone at three moments, no server guessing, the Stellwerk override |
| [15-geofence.md](15-geofence.md) | Station geofencing: the nudge with the app closed, the 20-region limit, the MethodChannel contract, the backend endpoint |

## Backend

| Doc | Content |
|---|---|
| [20-backend.md](20-backend.md) | Stack decision (Rust, axum, Postgres), service layout, the rules the backend owns |
| [21-data-requirements.md](21-data-requirements.md) | Every entity, field and endpoint the mock implies, external sources, what the mock lacks |

The skeleton lives in `backend/` (see `backend/README.md`, `backend/openapi.yaml`).

## Decisions (in the order we rode with them)

Each of these was written after using a build on a real trip, and each says what changed and why. They
are the living part of the product documentation: where one of them contradicts 10–15, the later
number wins.

| Doc | Written after | Content |
|---|---|---|
| [16-bahnsteig.md](16-bahnsteig.md) | 10 Sep | The Bahnsteig, second version: action by the moment, every number above the fold |
| [17-journeys.md](17-journeys.md) | 10 Sep | Journeys: destination first, an itinerary snapshot, legs confirmed one tap at a time |
| [18-home-antraege-wir.md](18-home-antraege-wir.md) | build 7 | Home says one thing, Anträge shows status, reply addresses belong to claims |
| [19-ride-sheet.md](19-ride-sheet.md) | build 8 | The ride as a draggable sheet with a persistent bar, the Wir block, Welcher Zug? hierarchy |
| [20-riding-home-zweck-ich.md](20-riding-home-zweck-ich.md) | build 9 | Riding on Home, no second check-in, the Zweck up front, Ich owns the level |
| [21-abbruch-und-antraege.md](21-abbruch-und-antraege.md) | build 11 | Abbrechen asks why, a self-chosen pause is capped out of the claim, cases can leave a bundle |
| [22-aufgeben-zaehlt-und-aufraeumen.md](22-aufgeben-zaehlt-und-aufraeumen.md) | build 12 | Giving up still earns Geduldspunkte, and four bits of tidying |
| [23-standort-und-loeschen.md](23-standort-und-loeschen.md) | build 13 | Stations ranked by what departs there, deleting a ride, noticing a forgotten one |
| [24-einchecken-flow-und-ruhe.md](24-einchecken-flow-und-ruhe.md) | build 13 | One live station source, the check-in asks where you are, Zug wechseln, a snooze |
| [25-geofence-v2-und-diagnose.md](25-geofence-v2-und-diagnose.md) | build 13 | Significant Location Change, a coverage disc, a 3-minute dwell, the Entwicklung page |
| [26-fahrt-lesen-und-blaetter.md](26-fahrt-lesen-und-blaetter.md) | build 15 | Home stops ranking, sheets pull down again, Dein Zweck opens the choice, the ride reads as one journey |
| [27-teilen.md](27-teilen.md) | build 15 | Teilen: the Fahrkarte, five faces, the four lines, Lochzangen-Konfetti |
| [28-schienenersatzverkehr.md](28-schienenersatzverkehr.md) | build 17 | A bus running under a train's line number is part of the journey; the planner was dropping every one |
| [29-ein-einchecken.md](29-ein-einchecken.md) | build 17 | Five ways to start a ride became one; nothing legacy left in the backend |
| [30-home-und-bahnhofsnamen.md](30-home-und-bahnhofsnamen.md) | build 18 | Wir at the top of Home, Deine Woche in the same box, and one station with two names |

Two numbers are used twice: `20-backend.md` and `21-data-requirements.md` came first, the decision
series later walked into the same numbers. In prose and in code comments a bare **docs/20** or
**docs/21** always means the decision doc; the backend pair is always named in full.

## Shipping

| Doc | Content |
|---|---|
| [30-tonight-plan.md](30-tonight-plan.md) | The build plan and what shipped, day by day |
| [40-store-listing.md](40-store-listing.md) | App Store privacy label, review notes, Play Data safety form, derived from the in-app Datenschutz text |
| [41-launch-checklist.md](41-launch-checklist.md) | Launch checklist: what only Johannes can do (domain, mail provider, NGO, Apple, Google, server), ordered by lead time |
| [42-runbook-vps-testflight.md](42-runbook-vps-testflight.md) | Step-by-step: Hetzner VPS with Docker and Caddy, then the iOS build into TestFlight, then APNs |

[sources.md](sources.md) lists the URLs behind the research.

Terms used throughout: **D-Ticket** = Deutschlandticket. **Servicecenter** = Servicecenter Fahrgastrechte, Frankfurt, the joint claims desk of DB and about 40 other railways. **Ledger** = the in-app "Konto" of qualifying delays and their claim status.
