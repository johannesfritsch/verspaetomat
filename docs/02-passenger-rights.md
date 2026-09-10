# 02 — Passenger rights and the numbers

Legal basis: EU Regulation 2021/782 (applicable in Germany since 7 June 2023) and the German Eisenbahnverkehrsordnung (EVO). Everything below reflects DB's published practice as of September 2026.

## Deutschlandticket

The D-Ticket is classed as an "erheblich ermäßigter Fahrausweis" (significantly discounted fare). That is why it gets a flat-rate scheme instead of a percentage refund.

| Rule | Value |
|---|---|
| Compensation per delay of 60+ min at the destination (Nahverkehr) | 1.50 € (2nd class), 2.25 € (1st class) |
| Minimum payout ("Bagatellgrenze") | 4.00 €, so incidents must be bundled: three in 2nd class, two in 1st class |
| Monthly cap | 25 % of the ticket price = 15.75 € at the 2026 price of 63 € |
| Delay measured | at the destination station, per journey |
| Cancellations | count when the resulting arrival is 60+ min late ("Reise nicht angetreten" option on the form) |
| Deadline | 3 months per delay under EU law; DB accepts up to 12 months as goodwill |
| Proof of delay | none required, DB records all delays electronically |
| Not valid on | ICE / IC / EC, so the trains with the worst punctuality are outside the D-Ticket world |
| Exceptions with real money | last train of the day missed or arrival between 0:00 and 5:00 due to 60+ min delay: reimbursement of an alternative (taxi, higher-class train) up to 120 € |

Since 7 June 2023 railways pay nothing when the delay is caused by "außergewöhnliche Umstände" outside their control: extreme weather, persons on the track, cable theft, third-party obstruction. Strikes are **not** exempt. The list is open-ended and operators have interpretive leeway.

## Ordinary tickets (Einzelfahrkarten, Sparpreis, Flexpreis)

| Delay at destination | Compensation |
|---|---|
| 60 to 119 min | 25 % of the fare |
| 120+ min | 50 % of the fare |
| Minimum payout | 4 € |
| Stranded overnight | hotel and taxi within statutory limits |

Every ticket is its own contract and its own claim. A 60 € ICE ticket delayed 60 minutes is 15 €, paid on its own.

## Other season tickets

| Ticket | Per delay of 60+ min | Cap |
|---|---|---|
| Zeitkarte Nahverkehr (non-D-Ticket) | 1.50 € / 2.25 € | 25 % of ticket value |
| Zeitkarte Fernverkehr | 5 € / 7.50 € | 25 % of ticket value |
| BahnCard 100 | 10 € / 15 € | 25 % of BahnCard price |

Season-ticket holders may bundle repeated delays within the validity period and claim them together.

## What this means in practice

Estimated figures. DB does not publish the share of regional trips delayed 60+ minutes. The 0.5 % used below is a high-side estimate that includes cancellations on hourly lines. Regional punctuality (arrival under 6 min late) was 88.5 % in August 2026; long-distance 54.2 %.

| Passenger | Trips / year | Qualifying delays | Claimable | Paid out? |
|---|---|---|---|---|
| D-Ticket commuter, 2 regional trips per workday | 440 | ≈ 2 | 3.00 € | No, below 4 € and deadline-bound |
| D-Ticket heavy user on an unreliable rural line | 440 | ≈ 6 | 9.00 € | Yes, two bundles |
| Monthly ICE traveller, 60 € tickets | 24 | ≈ 2 | ≈ 30 € | Yes, each on its own |

Ten thousand active D-Ticket users move a low five-figure sum per year, much of it stranded below the threshold. Ten thousand mixed users including regular ICE travellers can move well into six figures.

Context: DB received 6.9 million passenger-rights claims in 2024 and paid out 196.8 million €. Only about 6 % of eligible passengers claim at all.

## Giving up mid-journey (researched 11 September 2026)

Johannes asked whether abandoning a badly delayed journey earns compensation. It does not, but a different right applies.

- **Art. 18(1) VO (EU) 2021/782**: from an *expected* delay of 60 minutes at the destination the passenger chooses between (a) the full fare back, plus a ride back to the start when the journey has lost its point, (b) re-routing at the earliest opportunity, (c) re-routing later at a time of their own choosing. The Eisenbahn-Bundesamt puts it as: *"Zeichnet sich eine Verspätung von mindestens 60 Minuten ab, kann der Fahrgast auch von einer Fahrt absehen und Rückerstattung des Fahrpreises verlangen oder die Fahrt zu einem späteren Zeitpunkt auch mit geänderter Streckenführung durchführen."*
- **Art. 19(1)**: compensation is owed only for a delay *"für die keine Fahrpreiserstattung nach Artikel 18 erfolgt ist"*. Refund and compensation are alternatives.
- The compensation is measured **at the destination**. DB's Deutschland-Ticket FAQ: *"Erreichen Sie Ihr Ziel im Nahverkehr … mit mindestens 60 Minuten Verzögerung"*. Someone who never arrives has no arrival delay.
- So: **Einzelfahrkarte** — abandoning is worth the whole fare, usually more than the 25 %. **Deutschlandticket or another Zeitkarte** — no single fare exists to refund, so abandoning is worth nothing.
- **But options (b) and (c) keep the compensation right alive.** Taking the next train onward still produces an arrival late against the *original* plan, and that is an ordinary 1,50 € case. Hence "Ich fahre weiter" is the first option in the abort sheet (docs/21).
- **A self-chosen break does not count, though.** Compensation is for the delay the railway caused. The carriers' conditions allow the "later time of your own choosing" option *"wenn dem Fahrgast dadurch die zügige Weiterreise erleichtert wird"* — it exists to let you travel faster, not to pause. So the app measures against the **earliest onward connection** at the moment of the interruption: `counted = min(tatsächliche Ankunft, früheste mögliche Ankunft)`. The form still prints the true arrival and adds a line saying only the railway-caused part is claimed. Under-claiming with a reason is safe; overstating a time is not (docs/21 §2).

Sources: [Art. 19 VO (EU) 2021/782](https://www.buzer.de/19_Fahrgastrechte-VO.htm), [Art. 18](https://www.buzer.de/18_Fahrgastrechte-VO.htm), [EBA Beispiele und Ausnahmen](https://www.eba.bund.de/DE/Themen/Fahrgastrechte/Bahn/Beispiele_Ausnahmen/beispiele_ausnahmen_node.html), [DB Deutschland-Ticket Fahrgastrechte](https://www.bahn.de/faq/pk/angebot/regionale-angebote/deutschland-ticket/fahrgastrechte), [DB Erstattung](https://www.bahn.de/faq/deutschlandticket-verspaetung-erstattung).

## Legislative outlook

No German plan to cut regional-rail compensation was found for 2024 to 2026. A May 2026 European Commission draft revision strengthens rights (multi-ticket journeys). D-Ticket funding by Bund and Länder is secured until 2030; from 2027 the price follows a cost index.
