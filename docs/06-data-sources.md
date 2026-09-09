# 06 — Where the data comes from (system view, brief)

The customer-facing view is in [13-where-the-data-comes-from.md](13-where-the-data-comes-from.md). This is the short supplier list.

## Live train data

| Source | Regional real-time | Per-stop delay by trip | Cost | Note |
|---|---|---|---|---|
| Transitous (MOTIS, community-run) | Yes | To verify | Free | Träwelling moved here April 2025. No SLA. |
| gtfs.de realtime feed | Yes, coverage gaps | Yes | Free tier, paid full feed | Updated every 10 s. Regional trains only. |
| DB API Marketplace RIS::Journeys | Yes | Yes | Contract, price on request | The official upgrade path once there is traction. |
| v6.db.transport.rest / db-vendo-client | Yes | Yes | Free | Unofficial, blocked without notice. Prototyping only. |
| DB HAFAS | — | — | — | Dead since April 2025. |

Plan: Transitous plus gtfs.de behind one abstraction, RIS::Journeys later. Delay = forecast arrival minus planned arrival at the exit stop. Keep the raw evidence per journey (planned, actual, source, timestamp) because it goes on the claim.

## Stations

About 5,400 DB stations from RIS::Stations (CC BY 4.0), DELFI's free stop directory, or OpenStreetMap. Geofences are only needed for the station nudge.

## Operators

The trip's agency from the timetable feed, mapped to a claims desk via the operator directory in [04-operators.md](04-operators.md).

## Phone constraints

- Android: geofencing API with a native "dwell" trigger, up to 100 fences. Background location needs a Play Console declaration. From late October 2026 Play removes geofencing as a use case for foreground location services, so the OS geofence API is the only route anyway.
- iOS: 20 monitored regions per app, rotated to the nearest stations; background delivery needs a CLServiceSession since iOS 18; "Always" location is reviewed strictly. Response latency 3 to 5 minutes, which matches the dwell idea.
- No tracking during the ride. The server follows the trip.

## Forms

- DB Fahrgastrechte-Formular ME/08/25 (fillable PDF).
- EU standard claim form (PDF, German version from europa.eu). This is what the app generates.
- Operator directory as content.

## NGO content

Name, story, campaign goal, dedicated IBAN, donation-page URL, monthly confirmation of railway transfers.
