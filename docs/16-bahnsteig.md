# 16 — The Bahnsteig, second version

Decided 10 September 2026. The start screen has two jobs: get the person into a check-in in one tap, and make opening the app worth it the other 95 % of the time. The first version was a status screen (clock hero, "Kein Zug. Gut so.", numbers below the fold). This version adapts to the moment and puts every number above the fold.

## Blocks, top to bottom

| # | Block | Idle away from a station | At a station (≤ 300 m) | Riding | Just arrived |
|---|---|---|---|---|---|
| 1 | **Action** | compact station row: home station, up to two frequent stations, nearby ones if any, a search icon; each opens Einchecken | one card "Köln Hbf" with the next three rail departures inline; tapping a row goes straight to "Wo steigst du aus?" | the live ride card (delay in red digits, next stop, exit stop, "Zug wechseln") | the arrival result inline with its claim call-to-action |
| 2 | **Momentum** | Geduldspunkte this week with the delta to last week ("+96 · letzte Woche 41"; a quiet week reads "Diese Woche noch keine Fahrt" instead of a zero), level bar underneath ("128 bis Bahnhofsmission") | same | same | same |
| 3 | **Money countdown** | "Noch 1,50 € bis zum Antrag" or, when a bundle is ready, a primary button "6,00 € beantragen · an Bahnhofsmission Köln" | same | same | same |
| 4 | **Standing** | "Platz 7 auf der RE 7 diese Woche · 12 Punkte bis Platz 6"; falls back to the city board when the line board is too small (< 5 riders); hidden when neither has the customer | same | same | same |
| 5 | **Community with my share** | "1.208.316 Minuten gewartet · 62 davon deine", ticking | same | same | same |
| 6 | **Next thing** | at most one: post from the railway waiting, a claim expiring within 21 days, yesterday's forgotten check-in (only for people who ride most days), a badge earned in the last three days; nothing otherwise | same | same | same |

Gone: the big clock hero, the date line, "Kein Zug. Gut so.", the standalone search field, the separate nudge and Nachtrag widgets (they became the next-thing slot). The small clock stays in the header corner like on the other tabs.

## Data: `GET /v1/me/standing`

One call, computed server-side so Demo mode and the app never recompute rules:

```json
{
  "points_this_week": 96,
  "points_last_week": 41,
  "rides_this_week": 3,
  "level": { "name": "Bahnsteigkante", "next_name": "Bahnhofsmission", "points_to_next": 128, "progress": 0.62 },
  "money": { "open_cents": 450, "missing_cents": 150, "ready": false, "ready_desk": null, "ngo_name": "Bahnhofsmission Köln" },
  "board": { "scope": "line", "key": "RE 7", "rank": 7, "size": 23, "points": 96, "gap_to_next": 12 },
  "community": { "minutes_total": 1208316, "my_minutes": 62, "confirmed_cents": 4832000, "my_confirmed_cents": 450 },
  "next": { "kind": "mail", "title": "Post von der Bahn", "body": "4,50 € bestätigt", "claim_id": "…" }
}
```

- `board` is `null` when the customer is on no board with at least 5 entries; `gap_to_next` is `null` at rank 1.
- `next.kind` ∈ `mail` (an inbound mail in the last 7 days, or a claim in `question`), `deadline` (oldest open incident within 21 days; fields `days_left`, `incident_id`), `nachtrag` (no ride yesterday, but rides on at least 3 of the last 14 days), `badge` (earned in the last 3 days; `badge_id`). Priority in that order. `null` when nothing applies.
- Week = Monday to Sunday, local time (Europe/Berlin), simulated clock respected.

The station context comes from what the Bahnsteig already has: `GET /v1/stations/nearby` (≤ 300 m → at a station), `GET /v1/me/geofence` (frequent stations for the compact row), `GET /v1/rides/current`.
