# 07 — Market, competition, precedents, funding

## Market

| Figure | Value (date) |
|---|---|
| Deutschlandticket subscribers | 14.5 million (end of 2025), peak 14.7 million |
| D-Ticket price | 63 €/month (2026) |
| Ticket mix | 74 % standard, 15 % Jobticket (≈ 2.2 million), 11 % semester |
| Age skew | about 26 % of 18 to 34 year olds hold one |
| Regional rail journeys | 2.7 billion in 2024 (≈ 7.4 million/day) |
| Long-distance passengers | 142 million in 2024 |
| Regional punctuality (< 6 min) | 88.5 % (Aug 2026) |
| Long-distance punctuality | 60.1 % (2025), 54.2 % (Aug 2026); cancelled trains not counted |
| Passenger-rights claims | 6.9 million filed in 2024, 196.8 million € paid |
| Share of eligible passengers who claim | about 6 % |

## Competition

| Player | Check-in | Gamified | Delay claims | Donation | Note |
|---|---|---|---|---|---|
| Träwelling | Yes | Points, 7-day board | No | No | Open source (AGPL), volunteer-run, public API. Closest cousin. Forking obliges publishing code. |
| DB Navigator | Komfort Check-in | No | In-app for digital tickets | No | Owns the claim flow for DB-account tickets. |
| refundrebel | No | No | 35 % fee | Opt-in, one charity (Bahnhofsmission Heidelberg) | Only German "donate your compensation" feature. No D-Ticket. |
| Bahn-Buddy | No | No | Assignment model | No | Regulated territory. No D-Ticket. |
| hellaw.de | No | No | Free form generator | No | No D-Ticket. |
| Zugfinder | No | No | No | No | Delay statistics. Possible data partner. |
| Thameslink, Avanti West Coast (UK) | Automatic | No | Automatic from 15 min | Charity tick box | Proof the mechanic works when the operator runs it. |

Nobody in Germany combines check-in, gamification and delay-to-donation. No German operator runs a delay-donation campaign.

## Precedents for the mechanic

- ShareTheMeal (WFP): 1.8 million users, 270 million meals. One tap, one visible community total.
- Ecosia: personal and global tree counter on every search.
- Charity Miles: activity earns sponsor-funded donations, cumulative total visible.
- Research: gamification raises 90-day retention (Deloitte 2024, cited widely); public donation totals and in-group social norms raise giving.

## Träwelling decision

Options: integrate its API so users can link accounts and import check-ins; contribute the claim-and-donate layer upstream; or build independently with a friendlier UX. Decide before the prototype.

## Funding

| Programme | Amount | Fit |
|---|---|---|
| Prototype Fund (BMBF) | up to 47,500 €, 6 months, rolling | Civic tech. Bahn-Vorhersage was funded on a narrower pitch. Best first step. |
| mFUND line 1 (BMV) | up to 200,000 €, 18 months | Data-based mobility. Follow-on once a prototype exists. |
| DSEE TransformD | programme-level | Digitalisation plus social cohesion. |
| Employer matching | per deal | Jobticket employers add a fixed amount per claimed delay, paid to the NGO directly. |
| Operator sponsorship | later | The UK model. A Verkehrsverbund adding a charity tick box is the 12-month goal. |

## Name

"Verspätomat" returned no products, apps or campaigns in web search. Domain (DENIC) and trademark (DPMA) must be checked manually.
