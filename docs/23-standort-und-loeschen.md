# 23 — The right station, and getting rid of a ride

Decided 11 September 2026 (Johannes, from build 13 on a real phone at München Hbf). Three things.

## 1. München Hbf, not Seidlstraße

At München Hbf the app offered "Ab Seidlstraße". The cause is in `nearby_stops`: candidates are sorted by raw distance, and the only quality filter is *does this stop have any departure at all*. A tram stop 60 m from the entrance passes that test and beats a Hauptbahnhof whose centroid is 250 m away.

**Ranking.** Keep the reverse-geocode and the 8 nearest candidates, then classify each by what actually departs there, reusing `RAIL_MODES`:

| rank | what departs |
|---|---|
| 3 | long distance, high speed, night rail |
| 2 | rail, regional, regional fast |
| 1 | S-Bahn only, **or** no rail departure found but `looks_like_station(name)` |
| 0 | tram, bus, U-Bahn only |

Rank 0 is dropped. **S-Bahn stays** (Johannes, 11 September 2026): German S-Bahnen are Schienenpersonennahverkehr under railway law, so their delays are claimable exactly like a regional train's, a cancelled S-Bahn leg already counts as 60 minutes by our own rule, and a ten-minute S-Bahn can still cost a connection that is measured at the destination. The rank decides which station you may *start* from, not what may be claimed, and dropping it would make every S-Bahn-only station unusable — most of the Munich network outside the trunk line, and stations like Bornholmer Straße in Berlin. Ranked lowest it can never beat a Hauptbahnhof in the same band, which was the actual complaint.

**Two traps, found by querying Transitous on 11 September 2026:**

1. The current code classifies a stop from `departures(&id, 5)`. At München Hbf the first ten departures are tram, U-Bahn, bus and S-Bahn, with no long-distance or regional train among them, because the station is so busy. Ask MOTIS for rail departures specifically (the stoptimes endpoint takes a mode filter and `RAIL_MODES` already holds the list) rather than reading the head of a mixed list.
2. Transitous reports the Munich S-Bahn as `METRO`, not `SUBURBAN`. The mode alone cannot separate S-Bahn from U-Bahn, so for `METRO` and `SUBWAY` the line name decides: `^S\d` is rail rank 1, `^U\d` is not rail. `SUBURBAN` is accepted as rank 1 as well, since other feeds use it.

The stop Johannes saw, "Seidlstraße" (`de-DELFI_de:09162:99:11:11`), carries bus departures only, so it is rank 0 and disappears. The rest sort by `(distance / 300 m rounded down, then rank descending, then distance)`: inside the same 300 m band the better station wins, beyond it distance decides again. So a Hauptbahnhof at 250 m beats a tram stop at 60 m, and a tram stop never wins at all.

**Three, not one.** `GET /v1/stations/nearby` already returns a list; it now returns at most 3 with `distance_m` and a `rail_rank`. The Bahnsteig card shows the best one as it does today and, under the destinations, a quiet line: `Nicht hier?` followed by the other two as chips and `Anderer Bahnhof …` which opens the search. Tapping a chip switches the card to that station immediately, without asking the phone again.

**Never show a stale station.** On a cold start the card currently renders whatever station the last fix resolved to. Instead: while no fix newer than 5 minutes exists, the card shows `Standort wird geprüft …` in place of the station name, and fills in when the fix lands. A fix that never lands falls back to the away box, not to an old guess.

**"Standort erlauben" must resolve.** Today it asks for a position and reloads with whatever comes back, so a denied permission silently leaves the old station on screen. It now checks the permission first: not yet asked → ask, then force a fresh fix (no cached value) and re-resolve; permanently denied → open the system settings with one line saying why; granted → force a fresh fix. After the tap the card is never left showing the station it showed before.

## 2. A ride can be deleted

Discarding a case takes it out of a bundle (docs/21 §4) but the ride itself stays forever, in the "Nicht eingereicht" list and in Alle Fahrten. A journey logged by accident must be removable.

`DELETE /v1/journeys/{id}`: deletes the journey, its legs and the incident that came from it.

- Refused with 409 when the incident sits in a claim that is not a draft: `Diese Fahrt steckt in einem eingereichten Antrag.`
- A **draft** claim loses the incident and is recomputed exactly as a discard does, including deleting the draft when the rest falls below 4 €.
- Points, standing and the boards follow automatically, because the rows are gone.
- Legacy rides without a journey get the same treatment through `DELETE /v1/rides/{id}`.

In the app:

- **Anträge**, in the "Nicht eingereicht" list, each row gains `Fahrt löschen` beside `Doch einreichen`, behind a confirm sheet: `Fahrt löschen? Die Fahrt, ihre Punkte und der Anspruch verschwinden. Das lässt sich nicht rückgängig machen.`
- **Ich → Alle Fahrten**, each row opens the existing detail sheet, which gains `Fahrt löschen` at the bottom with the same confirm. When the ride is in a sent Antrag the action is shown disabled with the reason, so it is never a silent absence.

## 3. No nudge while a ride is open — and how to notice a stale one

Johannes got no station nudge at München Hbf. That is by design: `Geofence.swift` skips the nudge while a journey is open (`if c.riding { return }`), for the same reason the Einchecken square is disabled. Nothing to fix there.

What is missing is a way out of a ride that was forgotten. A journey left `riding` or `transfer` for more than **3 hours past its planned arrival** is almost certainly over:

- The ride bar changes to a question: `Noch unterwegs?` with two inline actions, `Ich bin da` and `Beenden`.
- One push goes out at the 3-hour mark, `Bist du angekommen?` / `Deine Fahrt nach Rheine läuft noch. Sag kurz Bescheid.`, sent once (`stale_asked_at` on the journey, migration 0024).
- Nothing is decided for the passenger: the journey keeps running until they answer or the existing rules finalise it.

## Tests

- Backend: a unit test for the ranking (a tram stop at 60 m loses to a Hbf at 250 m; a tram-only stop is dropped; beyond 300 m distance wins), and one for the delete (incident goes, sent claim refuses, draft recomputes).
- Tour: `bahnsteig` with the `Nicht hier?` chips, `bahnsteig-locating` (the checking state), `historie` with the delete action, `antraege-discarded` with `Fahrt löschen`, `bar-stale` (the "Noch unterwegs?" bar).
- E2E: both scenarios keep passing.
