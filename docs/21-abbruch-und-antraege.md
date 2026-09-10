# 21 — Abbrechen with a reason, taking a case out of an Antrag, the empty Anträge tab

Decided 11 September 2026 (Johannes, after build 11). Starts with a legal question: *if I give up because the delay is too big, am I owed something?*

## 0. What the law actually says

Sources: VO (EU) 2021/782 Art. 18 and 19, the Eisenbahn-Bundesamt's examples, and DB's own Deutschland-Ticket FAQ (read 11 September 2026; links in `docs/02-passenger-rights.md`).

1. **Art. 18(1)**: once a delay of 60 minutes or more at the destination is *expected*, the passenger may choose between (a) the **full fare back** (plus a ride back to the start when the journey has become pointless), (b) continuing or being re-routed at the earliest opportunity, (c) continuing or being re-routed **later, at a time of their choosing**.
2. **Art. 19(1)**: compensation (25 % from 60 minutes, 50 % from 120) is owed for a delay *„für die keine Fahrpreiserstattung nach Artikel 18 erfolgt ist"*. Refund and compensation are alternatives, never both.
3. **Art. 19(2)** hands Zeitkarten to the carrier's conditions. In Germany that is the flat rate the app already uses: **1,50 €** per case in the Nahverkehr (2,25 € first class), a 4 € Bagatellgrenze (Art. 19(6): at most 4 € per Fahrkarte), and a monthly cap of 25 % of the ticket's value.
4. DB's Deutschland-Ticket FAQ ties the flat rate to arriving: *„Erreichen Sie Ihr Ziel im Nahverkehr … mit mindestens 60 Minuten Verzögerung"*.
5. **Art. 19(10)**: nothing is owed for außergewöhnliche Umstände (already in the app).

**The consequence for us.** Compensation is measured at the destination. Someone who gives up never arrives, so there is no arrival delay and no 1,50 €. What they do have is the Art. 18 right: the fare back. For an Einzelfahrkarte that is real money and usually more than the compensation would have been. For a Deutschlandticket or another Zeitkarte there is no single fare to hand back, so giving up yields nothing at all.

**The exception that matters most.** Art. 18(1)(b) and (c) — continuing at the next opportunity or by another route — do *not* consume the compensation right. Someone who abandons the RE 7 and takes the next train onward still arrives late against the original plan, and that is an ordinary case worth 1,50 €.

**But the clock does not keep running through a self-chosen break.** Compensation is for the delay the *railway* caused. The German carriers' conditions only allow the "later time of your own choosing" option *„wenn dem Fahrgast dadurch die zügige Weiterreise erleichtert wird"* — it exists to let you travel faster, not to let you pause. Someone who abandons a delayed train, spends two hours in a café and then travels on has an arrival that is partly the railway's doing and partly their own, and the app must never claim the second part.

**Therefore, one rule, and it is stated to the passenger in these words:**

> Es zählt die Verspätung, die die Bahn verursacht hat: bis zum frühesten Zug, mit dem du ab hier weiterkommst. Wartest du länger, ist die Extra-Zeit deine und zählt nicht mit.

Mechanically: when a journey is re-planned mid-way (a passenger giving up on a train, or a missed connection), the app records the **earliest onward connection** available at that moment and its arrival at the destination. At finalisation the delay that counts is measured against `min(tatsächliche Ankunft, früheste mögliche Ankunft)`. The claim form still carries the **true** actual arrival, plus one line saying the journey was interrupted and that only the railway-caused part is being claimed — the app under-claims with a reason, and never overstates a fact.

## 1. Abbrechen asks why

The ghost button "Abbrechen" in the ride sheet opens a sheet, `Fahrt beenden?`, with three choices as `VChoiceCard`s and a "Zurück". No option is destructive without its consequence written next to it.

| Choice | Title | Body | What happens |
|---|---|---|---|
| `weiterfahrt` | **Ich fahre weiter** | `Es zählt die Verspätung bis zum frühesten Zug ab hier. Eine längere Pause zählt nicht mit.` | The journey stays open (§ 2). Recommended, listed first. |
| `aufgegeben` | **Ich gebe auf** | `Zu viel Verspätung, ich fahre nicht mehr. Keine Geduldspunkte, kein Anspruch — die Entschädigung hängt an der Ankunft.` | `abandoned`, reason `aufgegeben`. |
| `nicht_gefahren` | **Ich bin gar nicht mitgefahren** | `War ein Versehen. Die Fahrt verschwindet, als hätte es sie nie gegeben.` | `abandoned`, reason `nicht_gefahren`. |

After `aufgegeben` the app shows one closing card (not a snack), because this is the moment the passenger has a right they do not know about:

> **Aufgegeben.** Keine Geduldspunkte für diese Fahrt.
> Ab 60 Minuten erwarteter Verspätung darfst du die Fahrt abbrechen und **den Fahrpreis zurückverlangen** (Art. 18 der EU-Fahrgastrechte). Mit Einzelfahrkarte holst du dir das Geld am Schalter oder über das Fahrgastrechte-Formular der Bahn.
> Mit dem Deutschlandticket gibt es für die einzelne Fahrt nichts zurück — das Ticket läuft ja weiter.
> **Fährst du doch noch?** Dann check wieder ein. Es zählt dann die Verspätung bis zum frühesten Zug ab hier, nicht die Pause.

With a Deutschlandticket the Einzelfahrkarte sentence is dropped and vice versa (`me.settings.ticket`).

After `nicht_gefahren` a plain snack: `Fahrt gelöscht.`

## 2. "Ich fahre weiter" — and what the pause costs

New: `POST /v1/journeys/{id}/replan` with `{ "from_station_id": …, "from_station_name": … }` (defaults to the current leg's last reached stop).

- The current riding leg becomes `abandoned` (leg status; the ride row is not finalised, no points, no incident).
- The journey goes to `transfer` with `transfer_station_id/name` = where the passenger is, `next_leg` = the **earliest onward connection** from Transitous, `transfer_deadline` = now + 6 h (the existing 2 h rule stays for real transfers).
- `planned_arrival` and the destination are untouched.
- **New column** `journeys.earliest_onward_arrival timestamptz`: the destination arrival of that earliest onward itinerary, written here and at every missed-connection re-plan (keep the earliest value already stored if a later re-plan would raise it — the first interruption is the one the railway caused). Null on journeys that were never interrupted.
- Response: the `journeys/current` shape, plus `earliest_onward_arrival`, so the app can name the number before the passenger decides.

**Finalisation.** `counted_arrival = min(actual_arrival, earliest_onward_arrival)` when the column is set, else `actual_arrival`. The delay that counts, the Geduldspunkte and the claim amount all follow `counted_arrival`. `actual_arrival` keeps the true value.

**The claim form** (docs/03) still prints the true actual arrival. When the two differ, section 6 gains one line: `Fahrt in <Station> unterbrochen. Frühestmögliche Weiterfahrt: <Linie>, an <Zeit>. Geltend gemacht wird nur die dadurch entstandene Verspätung von <n> Minuten.` The app under-claims with a reason; it never states a false time.

In the app the sheet then shows the transfer card it already has, with the heading `Weiterfahrt` instead of `Umsteigen`, the earliest connection proposed as usual, and beneath it the line `Frühester Zug ab hier: <Linie>, an <Zeit> · <n> Minuten zählen.` Picking any train confirms the leg through the existing `POST /v1/journeys/{id}/legs`; choosing a later one adds a caption `Deine Pause zählt nicht mit — es bleiben <n> Minuten.`

If the passenger never confirms, the 6 h deadline finalises the journey `incomplete` as today, and the cap applies to that too.

## 3. Journeys carry their end reason

Migration 0022: `journeys.end_reason text` (`null | 'aufgegeben' | 'nicht_gefahren' | 'beendet'`), written by `finish`; `POST /v1/journeys/{id}/finish` takes `{ "arrived": false, "reason": "aufgegeben" | "nicht_gefahren" }` (`arrived: true` writes `beendet`). `journey_json` returns `end_reason`.

History (Alle Fahrten) shows a chip per reason: `aufgegeben` (ink2) and `nicht gefahren` (ink3, the row itself in ink3). `nicht_gefahren` journeys are hidden from the statistics on Ich and from the destination history (`destinations` already skips `abandoned`).

## 4. Taking a case out of an Antrag

`incidents.discarded_at timestamptz` (migration 0022) and `discard_reason text`.

- `POST /v1/incidents/{id}/discard` `{ "reason": "nicht_gefahren" | "doppelt" | "sonst" }` → sets `discarded_at`; the incident leaves every open bundle. Refused with 409 when the incident already sits in a claim that is not a draft.
- `POST /v1/incidents/{id}/restore` → clears it.
- Every query that builds bundles, sums, readiness or the draft filters `discarded_at is null` (`rules::refresh_statuses`, `bundle_ready`, `claim_draft`, `standing`, the ledger summary).
- When the incident sits in a **draft** claim, discarding removes it from `claim_incidents` and recomputes `amount_claimed_cents`; if the rest falls below 4 €, the draft claim is deleted and the incidents return to collecting.

In the app:

- On the collecting card, an incident row's evidence sheet gets a ghost action **`Nicht einreichen`** with the three reasons; the row then leaves the card.
- The card gets a caption line at the bottom when something was discarded: `1 Fall nicht eingereicht · anzeigen` → a small list with **`Doch einreichen`** per row.
- The Antrag flow's step 1 (Prüfen) lists the cases with the same action, so it can still be corrected while the draft is open.
- A sent claim shows no such action; its card says `Eingereicht — Änderungen nur noch über eine Antwort an das Unternehmen.`

## 5. The empty Anträge tab

There is not always a claim, and there is not always an incident. Anträge with no incidents, no claims and nothing discarded shows one card instead of "Wird gesammelt · Noch nichts":

> **Hier wird es später voll.** (title)
> `So läuft es:` and four numbered lines:
> 1. `Einchecken, wenn du in den Zug steigst.`
> 2. `Ab 60 Minuten Verspätung am Ziel entstehen 1,50 €.`
> 3. `Ab 4 € geht ein Antrag an das Eisenbahnunternehmen — mit deiner Unterschrift, von dir.`
> 4. `Antwortet die Bahn, zahlt sie direkt an <Verein>.`
>
> Caption: `Anträge müssen innerhalb eines Jahres gestellt werden. Wir erinnern dich rechtzeitig.`
> Primary button `Einchecken` (calls `startCheckin`).

The cycle strip stays above it. When incidents exist but no claim was ever sent, the collecting card is the empty state and needs nothing extra.

## 6. "Geduld ist eine Tugend" goes

It fired at 1.000 Geduldspunkte, the same moment as `minuten-1000` (build 11), so two badges landed at once. The badge is removed from the fixture and the mock; migration 0022 deletes its awards and the row. 20 badges remain. The two `geduld-ist-eine-tugend-*.png` assets are deleted.

## Tests

- Backend: unit tests for `end_reason` on finish, `replan` (leg abandoned, journey in transfer, planned arrival untouched), discard/restore (bundle sum drops, draft below 4 € is deleted, 409 on a sent claim).
- Tour: `abbrechen-sheet`, `abbrechen-aufgegeben` (the closing card), `antraege-empty`, `antraege-discarded` (the "1 Fall nicht eingereicht" line), `ich` re-shot with 20 badges.
- E2E: unchanged scenarios must keep passing; one new step in the direct scenario — after the claim is sent, discarding is refused (the card offers no action).
