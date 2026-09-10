# 03 — How a claim actually gets filed

## Channels

| Channel | Accepted? | Bundling several delays | Third-party payee | Verdict |
|---|---|---|---|---|
| DB online form / DB Navigator | Yes | One trip per claim | Own bank details pre-filled | Only for tickets bought in or stored in a DB customer account. Most D-Tickets are sold by Verbünde or other operators and do not qualify. |
| DB "Fahrgastrechte-Formular" (PDF, version ME/08/25) | Post, DB Reisezentrum, sales outlet only | One journey per sheet; several sheets in one envelope | Separate "Kontoinhaber (Name, Vorname)" field | Works, but paper. |
| EU standard claim form (Implementing Regulation 2024/949) by e-mail to `EUAntragFGR@deutschebahn.com`, subject "Fahrgastrechte: EU-Antragsformular" | Yes; PDF, JPG, PNG, TIF, DOC, XLS, TXT, GIF attachments | Tick box "wiederholte Verspätungen … Zeitfahrkarte" plus a 2,500-character free text (about 15 to 20 incidents) | "Name des Kontoinhabers (Vorname, Nachname)" separate from the passenger | **The path.** Fully digital. |
| Fax | Not offered anywhere | — | — | Drop. |
| Operators outside the joint Servicecenter scheme | Own address per operator | Varies | Varies | Needs an operator directory. See [04-operators.md](04-operators.md). |

DB says it "recommends" its own channels, but railways are legally obliged to accept the EU form, on paper or electronically. Payment for EU-form claims is bank transfer only, no PayPal or Apple Pay, no voucher for refund cases.

DB replies within about a month, by post or e-mail, to the claimant. With the relay model the e-mail reply arrives at the customer's Verspätomat address, so the app can read the outcome and forward the original to the customer. Postal replies still need the photo path.

## Proof of travel

There is none, and DB does not ask for one. A claim needs:

- a copy of the ticket (for the D-Ticket: a screenshot with the barcode) and the ticket number in the "Zeitkarte" field
- the journey: date, start and destination station, planned and actual arrival, train number
- the signed declaration: "Ich bestätige die Richtigkeit meiner Angaben … dass ich der rechtmäßige Inhaber der Fahrkarte(n) bin"

DB then runs a "Plausibilitätsprüfung" against its own delay records. Optional delay certificates from train staff exist but are not needed.

The app already holds every field. The timestamped check-in, with an optional one-shot location fix at the station, is the customer's own record should DB ever ask.

## Bundling

- **D-Ticket: collect.** Send a bundle when the incidents reach 4 € (three in 2nd class, two in 1st class), all against the same claims desk, and the oldest incident is still inside the deadline. A customer with two incidents at the three-month mark has nothing to send; the app must say so honestly.
- **Ordinary tickets: one claim per incident, immediately.** Each ticket clears the 4 € minimum on its own.
- Practical limits: about 15 to 20 incidents per EU form free text; at most 10 paid incidents per D-Ticket month because of the 25 % cap.
- Open question: whether DB accepts incidents from different months in one D-Ticket bundle (each month is technically a new ticket). The EU form allows several ticket numbers. Build the ledger so it can bundle per month if needed.
- Open question: whether the Servicecenter applies the 4 € minimum per bundle or per operator inside a bundle.

## Signature

- The EU form has **no signature line**. It ends with a truth declaration, date, place, and "Name des Fahrgastes oder seines Vertreters". A typed name satisfies it.
- The DB paper form requires "Unterschrift". A drawn signature embedded in the PDF and printed is what DB receives from every scanned claim already.
- A compensation claim has no statutory written-form requirement. An in-app drawn signature is a simple electronic signature under eIDAS; Article 25 says it cannot be denied legal effect for being electronic.
- Rules for the app: show the fully filled form before signing; sign per claim, or sign once plus an explicit per-claim "send" confirmation; never auto-apply a stored signature; treat the signature image as personal data and do not keep it longer than needed; the customer presses send.

## Sending: the relay model

Each customer gets a personal sender address on our domain, e.g. `fahrgast-4711@users.verspaetomat.de`, created at the first claim. When the customer presses send:

- the mail goes from that address to the claims desk, with the customer's name as display name, the PDF and the ticket image attached;
- the customer's private inbox receives an identical copy (BCC), so they hold the full record;
- the body states in plain German that the mail was transmitted via Verspätomat, a form-filling and relay service, and names the claimant;
- the reply address is the same personal address, so the railway's answer, follow-up questions and rejections reach us;
- every inbound mail is forwarded to the customer's private address immediately and unchanged, and the ledger status is updated from it;
- the customer can answer a follow-up question from inside the app, again through their own address.

What we get: "eingereicht" set at send time and "bestätigt" set when the reply arrives, both without the customer doing anything, bounce detection for wrong operator addresses, response times and acceptance rates per operator, and no share-sheet dance.

Rules that keep this a relay and not representation:

1. Nothing is sent without the customer signing and pressing send for that specific claim.
2. We never write to a railway on our own initiative, never chase, never dispute. Follow-ups and rejections are the customer's to answer; the app offers templates.
3. Inbound mail is delivered to the customer whole. We extract status, amount and reference; we do not act on the content.
4. Mails and attachments are kept only as long as the claim is open, then reduced to the ledger entry, unless the customer keeps them.
5. One bundle per customer. Never a combined submission for several people, even though technically trivial.

Why not the customer's own mail app: replies would go to the customer's inbox, invisible to the app, and the community total would depend on people photographing letters. The relay is the only way to close that loop. Fallback remains: "Als PDF zum Drucken" and the photo upload for postal replies.

Open questions for the legal opinion and the test claims: whether transmitting a customer-signed claim counts as messenger activity (Bote) rather than representation under the Rechtsdienstleistungsgesetz; whether operating personal mailboxes makes us a telecommunications service under the TDDDG with its secrecy obligations; and how the Servicecenter reacts to volume from one domain. See [05-legal.md](05-legal.md).

## Things the first two test claims must settle

1. Does DB pay to an NGO named as account holder?
2. Does DB accept the free-text incident list as a bundle?
3. Does the EU-form inbox process claims for the other railways in the joint Servicecenter scheme?
4. Does DB's EU-form desk ask for a signed copy in practice?
5. Does DB reply by e-mail to a claim sent from a relay address, and does the reply contain the amount and a reference we can read?
