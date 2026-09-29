# 12 — Gamification

## Two figures: minutes and euros

Since 29 September 2026 (#74, docs/47) there are no Geduldspunkte. There were never more than
minutes under a second name.

| Figure | Who earns it | How | Shown where |
|---|---|---|---|
| **Minuten** | Everyone, on every delayed ride | The delay at the destination, from minute 1, once per journey (docs/17). A cancellation counts at least 60. A journey given up counts the waiting (docs/22 §1). A ride entered afterwards ("Nachtrag") counts its minutes, marked „selbst eingetragen", and never ranks. | Home, profile, boards, community, sharing |
| **Euro** | Few, on 60+ minute delays and on ordinary-ticket claims | The statutory claim amount, shown as "Anspruch" until sent, "eingereicht" after sending, "bestätigt" after the railway's reply | Ledger, NGO page, community |

Minutes are the loud metric. Euros are the true metric. The community screen shows both, never
blended. The rule is `rules::counted_minutes`; the backend owns it.

## Levels

Named after where the customer is standing. Purely for the profile; no unlocks gated behind them.

| Level | Minutes | Name |
|---|---|---|
| 1 | 0 | Frischer Fahrgast |
| 2 | 60 | Bahnsteigkante |
| 3 | 240 | Wartehäuschen |
| 4 | 600 | Gleis 7 |
| 5 | 1,500 | Bahnhofsmission |
| 6 | 4,000 | Bahnsteig-Buddha |

## Badges

Named after real causes and situations. Each badge names a thing that actually happened; the collection is a little museum of German rail life.

| Badge | Earned when |
|---|---|
| Erste Verspätung | first delayed ride |
| Schienenersatzverkehr | checked in to a replacement bus on a rail line |
| Stellwerksstörung | a delay whose stated cause is a signal box failure |
| Personen im Gleis | same, for "Personen im Gleis" |
| Gegenzug abgewartet | a delay under 10 minutes that ends on time or better at the exit stop |
| Letzter Zug | a check-in after 23:00 |
| Nachtschicht | arrival between 0:00 and 5:00 |
| Volle Stunde | first 60-minute delay |
| Bagatellgrenze geknackt | first D-Ticket bundle reached 4 € |
| Abgeschickt | first claim sent |
| Bestätigt | first railway reply uploaded |
| Deutschlandreise | check-ins in five different Bundesländer |
| Stammgleis | 50 rides on the same line |
| 1.000 Minuten … 64.000 Minuten | 1,000 minutes counted, then doubling |

Badges are shown once, on the arrival screen, then live quietly on the profile. They can be shared as a card.

Badges that depend on the operator's stated cause (Stellwerksstörung, Personen im Gleis) or on trip type (Schienenersatzverkehr) are awarded only when the live data carries that information; otherwise nothing happens. They are post-launch until the data sources in 06 confirm the fields.

## Boards

- **Meine Linie**: the seven-day patience board for one line, e.g. "RE 7 Krefeld–Rheine". Winnable, recognisable, the one people screenshot.
- **Meine Stadt**: seven-day board per city.
- **Deutschland**: for the curious. Never the default.
- Boards rank the counted minutes of the last seven days, and only rides verified by a location fix at the station. Unverified rides (and every Nachtrag) still count their minutes and euros for the customer; they just do not rank.
- Everyone can hide themselves from boards with one switch.

## What we deliberately do not do

- No buying minutes, no premium tiers, no boosts.
- No teams for now. Nothing in the product points at them, not even the statistics; they can come back when there are enough customers on one line to make one.
- No NGO campaigns with goals and deadlines. The confirmed total per NGO is the story; a finish line would need NGO-side tooling and invites fake urgency.
- No employer matching. A sponsor's promise would be a second kind of money in a ledger that is honest precisely because it holds only one.
- No streaks. Commuting is not a habit to be policed, and a missed day is not a loss. Nothing in the app resets because the customer did not open it.
- No shaming: no "you missed a day" push, no public loss.
- No leaderboards on euros. Money is not a competition; minutes are.
- No fake urgency. The only urgency in the app is real: "Älteste Verspätung verfällt in 3 Wochen."
- No celebrating a delay while the customer is still in it. The ride screen stays calm; the reveal is at arrival.
