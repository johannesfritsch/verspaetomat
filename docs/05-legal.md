# 05 — Legal and platform gates

## Payment law (ZAG)

Collecting donor money and forwarding it is money remittance and needs BaFin permission. **Our model never touches money.** The customer files a claim; the railway pays the NGO. There is no payment flow to license. Keep it that way: no wallets, no "we forward it for you", no pooled accounts.

## App stores

- Apple guideline 3.2.2(iv): non-nonprofits may not collect donations inside the app. 3.2.1(vi): approved nonprofits may fundraise in third-party apps with Apple Pay. **Neither applies**, because the app collects nothing. A form helper is an ordinary utility app.
- "Trotzdem spenden" links open the NGO's own donation page in the browser. That is explicitly allowed for non-nonprofits.
- Google Play exempts donations to tax-exempt nonprofits from Play Billing anyway.
- Background location on both stores needs a stated core-functionality justification and a declaration form on Google Play. The station nudge is optional; the app must work fully without it.

## In the app

The three texts a store build needs live in `app/lib/content/legal.dart` and are shown under Einstellungen → Rechtliches: Impressum (§ 5 DDG, operator placeholders still to fill), Datenschutzerklärung (the sections below turned into plain German: device account, location at two moments, relay mailbox and TDDDG, retention, rights with the in-app controls named), and "Wie wir Anträge weiterleiten", the messenger clause in the customer's words. The claim flow links the messenger clause on the send step. docs/40-store-listing.md derives the store privacy labels from the same text. Change all of them together.

## Legal-services law (Rechtsdienstleistungsgesetz)

Generating a document the customer reviews, signs and sends themselves is generally not a legal service. Submitting on the customer's behalf under a power of attorney, or taking assignment of claims (the Bahn-Buddy model), is regulated.

The relay model sits between the two and must stay on the messenger side. German law distinguishes the messenger (Bote), who transmits someone else's declaration unchanged, from the representative (Vertreter), who makes a declaration for someone else. A postal service is a messenger; a claims agency is a representative. Our position: the customer authors and signs the claim, presses send per claim, and receives every reply whole; we transmit and deliver, we do not examine the case, we do not correspond with the railway on our own initiative, we do not chase or dispute. The moment we answer a rejection ourselves, or send anything the customer did not trigger, we become a representative and probably an unregistered debt-collection service (Inkassodienstleistung, §10 RDG). The legal opinion must address this model explicitly, with the mail body text and the follow-up flow attached.

## Telecommunications secrecy (TDDDG)

Giving each customer a mailbox on our domain and reading what arrives there may make us a provider of a telecommunications service, bound by the secrecy of communications (§3 TDDDG). Handling that: the mailbox exists for one declared purpose, the customer is told exactly what we read (status, amount, reference) and why, consent is explicit and separate, inbound mail is forwarded whole, nothing is used for anything else, and retention ends with the claim. The DPIA must cover this. One question in the legal opinion.

## GDPR

- Systematic location monitoring plus behavioural triggers make a Datenschutz-Folgenabschätzung (DPIA) very likely mandatory. Commission it before launch.
- The claim needs name, address, ticket number. Collect them at first claim, not at sign-up. Generate the PDF on the device where possible.
- Keep the ticket image only while the claim is open, encrypted, so a railway follow-up can be answered; delete it with the claim's closure. The D-Ticket shows a date of birth the app never needs.
- Sent claims, replies and attachments live in the relay only as long as the claim is open, then only the ledger entry remains, unless the customer chooses to keep the correspondence.
- No location during the ride. The station nudge uses a geofence; the app may store "you were at Hbf at 08:12" only with the check-in.
- Signature images are personal data: embed and discard, or store encrypted with separate consent.
- Data export and delete-account must be one tap each.

## Tax receipts

Only an organisation in the Zuwendungsempfängerregister can issue a Zuwendungsbestätigung, and the money arrives at the NGO from the railway, not from the customer. Whether the NGO may issue a receipt for an assigned claim is a question for a partner NGO's accountant. Under 300 € a bank statement suffices in Germany anyway, and at 1.50 € per incident nobody will ask. Do not promise receipts in the app until settled.

## NGO consent

Listing an NGO's IBAN as payee needs written agreement, ideally with a dedicated account per NGO so incoming railway transfers can be reconciled and reported back. The NGO must expect many small transfers with no useful reference.

## Sammlungsgesetze

Public-collection laws still exist in Rheinland-Pfalz, Saarland, Sachsen and Thüringen. A form helper that collects nothing is almost certainly outside them. One line in the legal opinion.
