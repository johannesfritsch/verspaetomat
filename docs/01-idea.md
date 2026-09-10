# 01 — The idea

## In one sentence

You check in to your train. If it is late, you earn points. If it is very late, you have a legal claim to a few euros, and the app helps you send that claim so the money goes to a good cause instead of your own account.

Slogan candidates: *"Du bist spät, du spendest."* / *"Verspätung mit Sinn."*

## The model we chose

- The customer checks in to a train and picks the exit station.
- The app follows the train's live delay data. No location tracking during the ride.
- Every delay earns "Geduldspunkte" (patience points). Every delay is visible, shareable, funny rather than enraging.
- A delay of 60 minutes or more at the destination creates a statutory compensation claim.
- The app fills in the official claim form with the customer's details, the journey data it already holds, and a partner NGO as the payee (account holder).
- The customer signs in the app and presses send. The claim leaves through the customer's own Verspätomat address (e.g. `fahrgast-4711@users.verspaetomat.de`), with a copy to the customer's private inbox. The railway's reply arrives at that address, is forwarded to the customer unchanged, and updates the ledger. We relay; we never write to the railway on our own initiative.
- Deutsche Bahn (or the operator that ran the late train) pays the NGO directly.
- The app shows a community total: minutes waited, euros submitted, euros confirmed.

**The app never handles money and never acts as anyone's legal representative.** It is a form helper and a messenger: the customer authors, signs and sends; we transmit and deliver replies. That keeps the payment-services licence question, the App Store donation rules, and most of the legal-services exposure away. See [05-legal.md](05-legal.md).

## The verdict from the September 2026 study

**Feasible.** The check-in half is a solved problem (Träwelling, travelynx). The claim half is a form-filling problem with a fully digital route (the EU standard form by e-mail). Legally the model is unusually clean.

**The catch is arithmetic.** D-Ticket compensation is 1.50 € per qualifying delay (2.25 € in first class), nothing is paid below 4 €, and a typical commuter sees maybe two qualifying delays a year. The D-Ticket alone cannot power a community counter. Therefore:

1. Support every ticket type from day one. Ordinary tickets refund 25 % at 60 minutes and 50 % at 120. A late ICE is worth 10 to 40 €.
2. Make delay minutes the headline metric. Everyone earns them; few earn euros.
3. Offer "Trotzdem spenden", a link out to the NGO's own donation page, so the 95 % of delays that pay nothing can still become a gift. No money flows through the app.

## What the customer gets

- A reason to smile at a delay.
- Zero-effort compensation claims that were never worth the effort before.
- A visible, shared answer to "what did all this waiting amount to?"

## What the NGO gets

- Money from Deutsche Bahn, not from the passenger's wallet, so passengers do not feel poorer.
- A story ("Bahnverspätungen haben dieses Jahr 12.000 € für uns bezahlt").
- A young, urban, environmentally minded audience.
