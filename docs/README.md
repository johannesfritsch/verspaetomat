# Verspätomat — Documentation

Working title: **Verspätomat**. A gamified train check-in app for Germany where being late becomes giving. The app never touches money: it helps passengers file their statutory delay compensation with a partner NGO as the payee, and Deutsche Bahn (or the operator) pays the NGO directly.

Status: research, product concept and a fully mocked Flutter showcase app (`app/`, see `app/README.md`), September 2026. Chosen look: "Bahnhofsuhr" (paper white, black grotesk, one red second hand); see `app/STYLE.md`.

## Research (what we found out)

| Doc | Content |
|---|---|
| [01-idea.md](01-idea.md) | The idea, the money-flow model, the verdict |
| [02-passenger-rights.md](02-passenger-rights.md) | Compensation rules for the Deutschlandticket and ordinary tickets, the numbers |
| [03-claim-filing.md](03-claim-filing.md) | Channels, forms, bundling, proof of travel, signatures |
| [04-operators.md](04-operators.md) | Who the claim goes to, the joint Servicecenter scheme, exceptions |
| [05-legal.md](05-legal.md) | Payment law, app store rules, legal-services law, GDPR, tax receipts |
| [06-data-sources.md](06-data-sources.md) | Live train data, stations, phone constraints (brief, non-technical) |
| [07-market.md](07-market.md) | Market size, competitors, precedents, funding |
| [08-risks-and-validation.md](08-risks-and-validation.md) | Ranked risks, four-week validation plan, success criteria |

## Product (what we want to build)

| Doc | Content |
|---|---|
| [10-experience.md](10-experience.md) | The feeling of the app: tone, look, sound, principles |
| [11-screens.md](11-screens.md) | Every screen, what it shows, what the customer does there |
| [12-gamification.md](12-gamification.md) | Points, badges, boards, teams |
| [13-where-the-data-comes-from.md](13-where-the-data-comes-from.md) | Every piece of information on screen and its origin, in customer terms |

[sources.md](sources.md) lists the URLs behind the research.

Terms used throughout: **D-Ticket** = Deutschlandticket. **Servicecenter** = Servicecenter Fahrgastrechte, Frankfurt, the joint claims desk of DB and about 40 other railways. **Ledger** = the in-app "Konto" of qualifying delays and their claim status.
