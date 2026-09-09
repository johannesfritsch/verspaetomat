# 08 — Risks, validation plan, success criteria

## Risks ranked

| Risk | Severity | Mitigation |
|---|---|---|
| D-Ticket euros too small to make the community total feel alive | High | All ticket types from day one; minutes as headline metric; "Trotzdem spenden"; employer matching. |
| DB refuses payment to a third-party account, or changes the form | High | Test claims before building. Fallback: customer receives the money and gets a one-tap link to the NGO's donation page. |
| Community total cannot be verified | Low with the relay | Railway replies arrive at the customer's Verspätomat address and update the ledger; NGO monthly reporting; photo upload for postal replies; separate "eingereicht" and "bestätigt" counters. |
| Railways treat mail from one domain as a claims agency and demand powers of attorney, or block it | Medium | Transparent body text naming the claimant and the service; customer's name as sender display name; one bundle per customer; talk to the Servicecenter early; paper route as fallback. |
| Relay classed as representation (RDG) or as a telecom service (TDDDG) | Medium | Messenger rules in 03 and 05; explicit legal opinion on the relay; consent and retention design. |
| Unofficial DB data gets blocked | Medium | Transitous plus gtfs.de from day one; RIS::Journeys later. |
| Background permission refusal, especially iOS | Medium | Nudge is optional; widget, calendar and "usual commute" reminders as fallbacks. |
| Servicecenter applies the 4 € minimum per operator inside a bundle | Medium | Test claim; ledger can bundle per operator. |
| Legal-services classification | Low if rules kept | Customer always sends; no stored auto-signatures; legal opinion. |
| Passenger-rights rules change | Low | No German cut found; EU draft strengthens rights. |
| D-Ticket politics | Low | Funded to 2030; app works with any ticket. |

## Four-week validation plan (no code)

1. **File two real test claims** with an NGO's IBAN as account holder: one EU form by e-mail from a relay-style address with a D-Ticket bundle of three 2nd-class incidents, one DB paper form by post. This settles the model, and shows whether DB's reply comes by e-mail with a readable amount.
2. **Measure incidence.** Record the gtfs.de realtime feed for four weeks; count regional arrivals by delay bucket (6+, 60+ minutes). Replaces the 0.5 % guess.
3. **Sign three NGOs**: Bahnhofsmission, a climate NGO, a children's charity. Dedicated IBAN and monthly reporting of railway transfers.
4. **Fake-door landing page** with the slogan and "Meine nächste Verspätung spenden". Success bar: 10 % leave an e-mail. Ask one question: D-Ticket or other tickets?
5. **One legal opinion** covering the relay model under the Rechtsdienstleistungsgesetz (messenger vs representative), the TDDDG mailbox question, and DPIA scope.
6. **Confirm Transitous** exposes per-stop delays for a trip id.
7. **Check the name** at DENIC and DPMA.
8. **Apply to Prototype Fund.**

## Success criteria

| When | What |
|---|---|
| Month 3 after launch | 2,000 monthly active check-in users; 500 claims generated; first 5,000 € confirmed by NGOs |
| Month 6 | One employer matching programme live; one NGO campaign reached its goal; store rating above 4.5 |
| Month 12 | A Verkehrsverbund or operator in talks about a charity tick box in their own claim flow |
