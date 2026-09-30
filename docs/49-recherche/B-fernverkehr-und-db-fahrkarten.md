> Recherche zu Issue #66 (30. September 2026), Grundlage für docs/49. Pfade `scratchpad/…` bezeichnen lokal heruntergeladene Quelltexte, die nicht im Repo liegen; die URLs stehen jeweils dabei.

# Research B: DB Fernverkehr products and DB-sold tickets, compensation rules (as of 2026-09-30)

Scope: every DB Fernverkehr product and DB-sold ticket, Fernverkehr Zeitkarten, international and third-party
operators in Germany, several-ticket journeys, data DB needs. No code changes.

## 0. Sources and confidence tags

| Tag | Meaning |
|---|---|
| **verified-primary** | Verbatim from the tariff / regulation / operator's own terms in force today |
| **secondary** | DB FAQ / brochure / operator help page (official but not the binding tariff), or a reliable secondary source |
| **inferred** | Derived from primary text by reading, not stated literally |
| **unknown** | Not found; needs a test claim or a question to DB |

Primary texts used:

- **BB** = *Beförderungsbedingungen Deutsche Bahn AG*, Neuausgabe 14.12.2025, **Stand 24.09.2026**, scratchpad `bb.txt`
  (source https://www.bahn.de/agb). Part A = BB Personenverkehr; B = Zeitkarten (Stand 05.06.2026); C = BahnCard
  (Stand 26.08.2026); D = Besondere Personengruppen; E = Aktionsangebote; G = bahn.business; K = Prämienfahrkarten.
- **SCIC-NRT/RPT** = *Besondere Internationale Beförderungsbedingungen der DB AG*, **Stand 01.08.2026** (TB 7/2026),
  https://assets.static-bahn.de/dam/jcr:e85e0ded-c7b8-4653-8dee-c56be74b86d5/… (scratchpad `scic.txt`).
- **VO** = Regulation (EU) 2021/782: Art. 19 (scratchpad `a19.txt`, gesetze.legal), Art. 12 and Art. 28 (buzer.de).
- **EVO** = Eisenbahnverkehrs-Verordnung 2023 (gesetze-im-internet.de, `evo.txt`).
- **FGF** = DB Fahrgastrechte-Formular "Formular 2025 (ME/08/25)" (`fgf.txt`).
- DB FAQ pages (bahn.de/faq/…), DB brochure "Ihre Rechte als unser Fahrgast", Stand 09/2024 (`brosch.txt`).
- Operators: flixtrain.de/fahrgastrechte, interrail.com/en/support/delay-compensation, oebb.at, europeansleeper.freshdesk.com.

Change note that matters: the tariff notice list says **"11/2026 BB Personenverkehr – Nr. 9.2.1: Änderung der
Rundungsregeln"**. The rounding text quoted below is the version now in force (commercial to the cent).

---

## 1. General rules for every DB single ticket (the base model)

Every row: **verified-primary**, BB A.9 unless noted.

| Rule | Value | Verbatim quote (BB) |
|---|---|---|
| Rate | 25 % at 60–119 min, 50 % at ≥120 min, arrival delay at the **destination of the ticket** | 9.2.1: „bei einer Verspätung von 60 bis 119 Minuten 25 % und ab 120 Minuten 50 % des gezahlten Fahrkartenwertes der vorgelegten Fahrkarte" |
| Basis | the **price paid** for the ticket shown (after the BahnCard discount; the BahnCard price itself is not included; the second point is inferred from „gezahlten Fahrkartenwertes der vorgelegten Fahrkarte") | same; VO Art. 19(3): „im Verhältnis zu dem vollen Preis berechnet, den der Fahrgast für den verspäteten Verkehrsdienst tatsächlich entrichtet hat" |
| Vouchers | **Aktionsgutscheine (E.1.3) are subtracted from the basis.** Wertgutscheine (gift card, Stornogutschein, Fahrgastrechtegutschein, E.1.2.4) are not subtracted. The first point is verified; the second is inferred, because the exclusion names only E.1.3 | 9.2.1: „Bei der Berechnung der Entschädigung werden im Rahmen der Bezahlung eingesetzte Aktionsgutscheine nach E.1.3 … nicht in Ansatz gebracht." |
| Rounding | commercial rounding to 2 decimals | 9.2.1: „Der Betrag wird kaufmännisch auf die zweite Nachkommastelle gerundet." |
| Once per ticket | per ticket; with return tickets, per direction | 9.2.1: „Der Entschädigungsanspruch kann pro Fahrkarte – bei Rückfahrkarten pro Fahrtrichtung – jeweils nur einmal geltend gemacht werden." |
| Payout minimum | **amount < 4.00 € is not paid**, so pay when `amount >= 4.00` | 9.2.1: „Entschädigungsbeträge unter 4 € werden nicht ausgezahlt." VO Art. 19(8): „höchstens 4 EUR pro Fahrkarte" |
| Exclusions | Art. 19(10) VO (weather or natural catastrophe, the passenger's fault, third parties). **Strikes of the railway's own staff and infrastructure-manager failures are not exclusions** | 9.2.1: „Die Geltendmachung von Ausschlussgründen nach Art. 19 Abs. 10 VO (EU) 2021/782 bleibt vorbehalten." VO 19(10) last sentence: „Streiks des Personals des Eisenbahnunternehmens … fallen nicht unter die Ausnahme" |
| No compensation | if the passenger was informed of the delay before buying the ticket, or if rerouting brought them in under 60 min | VO 19(9) |
| Self-affected | only the traveller personally affected | 9.2.1: „Der von einer Verspätung selbst betroffene Reisende" |
| Refund instead of compensation | at an expected delay of ≥60 min: abandon the trip or do not start it, and get a refund (not both) | 9.1.3: „… kann er auch die Reise abbrechen oder gar nicht erst antreten. Er hat dann anstelle der Ansprüche nach Nr. 9.1.1 und Nr. 9.1.2 Anspruch auf Erstattung des von ihm bezahlten Fahrpreises …" Aktionsgutscheine are not refunded: „Bei der Bezahlung der Fahrkarte eingesetzte Aktionsgutscheine … werden nicht erstattet." VO 19(1): compensation only „für die keine Fahrpreiserstattung nach Artikel 18 erfolgt ist" |
| Train binding lifted | from an **expected** delay of 20 min at the destination; any train, including higher categories, but not trains with compulsory reservation | 9.1.1: „mindestens 20 Minuten verspätet ankommen wird, hat er, auch mit einer zuggebundenen Fahrkarte … die Wahl … Er kann dabei auch den Zug einer höherwertigen Produktklasse benutzen. Die Benutzung eines reservierungspflichtigen Zuges oder eines Sonderzuges ist allerdings nicht gestattet." |
| 100-min information rule | if DB gives no rerouting information within 100 min, the passenger may book a non-DB railway or bus and is reimbursed | 9.1.2 |
| Taxi / other mode | scheduled arrival 0:00–5:00 with ≥60 min expected, or the last train of the day cancelled and the destination not reachable by 24:00; **max 120 €** | 9.1.5: „… Anspruch auf Ersatz der dafür erforderlichen Aufwendungen bis zu einem Höchstbetrag von 120 €." |
| Hotel | when the journey cannot reasonably continue the same day; "angemessene Kosten"; max 3 nights in Art. 19(10) cases | 9.1.6 |
| Deadline | **1 year after the ticket's validity ends** | 9.5: „Ansprüche nach den Nummern 9.1 bis 9.3 verjähren innerhalb eines Jahres nach Ablauf der Geltungsdauer der Fahrkarte." |
| Ticket validity (for the deadline) | ≤100 km: until 03:00 the day after the travel day; >100 km: until 03:00 of the second day after the travel day | A.2.5.1: „Die Geltungsdauer endet bei einer Entfernung bis 100 km um 3.00 Uhr des auf den Geltungstag folgenden Tages, bei einer Entfernung über 100 km um 3:00 Uhr am zweiten auf den Geltungstag folgenden Tag." |
| Payout form | bank transfer, or a DB voucher on request (valid 3 years). **Refund claims (abandonment, taxi or hotel receipts) must be paid in cash** | FAQ (secondary): „Bei Fällen mit Erstattungsansprüchen … sind wir verpflichtet, eine Geldauszahlung vorzunehmen." VO 19(7): „auf Wunsch des Fahrgasts in Form eines Geldbetrags"; E.1.2.4: Fahrgastrechtegutschein valid 3 years |
| Payout time | within one month of the claim | VO 19(7) |
| Desk | **Servicecenter Fahrgastrechte** (DB Dialog GmbH on behalf of the participating railways), 60647 Frankfurt am Main; online in the DB Kundenkonto or DB Navigator, or through the Auftragssuche; DB Reisezentrum only for immediate refunds when the trip was not started or was abandoned | BB 9.3, 9.4; FGF |
| Language / form | in German, on the Fahrgastrechte-Formular; copies suffice for compensation; **originals are required for refunds and expense claims** | 9.3.2: „Für Erstattungs- und Aufwendungsersatzansprüche sind die begründenden Unterlagen (Fahrkarten, Belege) immer im Original beizufügen. Für Entschädigungsansprüche können grundsätzlich Kopien der Belege beigefügt werden." DB must also accept the EU standard form (VO 19(6)); by e-mail to EUAntragFGR@deutschebahn.com (FAQ, secondary) |
| Online uploads | receipts up to 120 € gross as a scan; above that, or alternatively, post the originals within 14 days | 9.4.4 |
| Joint liability on one through ticket | all participating railways are jointly and severally liable | A.1.3.4 |

**Deadline clarification: 1 year vs. the 3-month complaint rule.**
- BB 9.5 (verified-primary): 1 year after the end of validity. The DB FAQ (secondary) says „innerhalb von 12 Monaten
  nach dem Vorfall" and warns that some international railways use 3 months.
- VO Art. 28(2) (verified-primary): „Eine solche Beschwerde muss innerhalb von drei Monaten nach dem Vorfall …
  eingereicht werden." Art. 28 governs **complaints** (Beschwerden) about the regulation. A compensation **claim**
  under Art. 19 is a separate claim, and its limitation is CIV Art. 60 in Annex I (BB 9.5 refers to it). DB applies
  the 1-year rule to its own tickets. The 2024 DB brochure mentions 3 months and adds that DB also processes later
  claims (secondary, from the fetched summary of the bahn.de "rechtliche Regelungen" page).
- **Model:** DB tickets use deadline = end of validity + 1 year. Build in a 3-month soft target for non-DB operators
  (FlixTrain, Interrail and others below state 3 months explicitly). Confidence: verified-primary for DB; inferred for
  how Art. 28 relates to Art. 19.

---

## 2. Single tickets, product by product

Unless a row says otherwise, **everything in §1 applies**: rate 25/50 %, thresholds 60/120, basis = price paid,
commercial rounding, payout if ≥4 €, 1 year after validity, Servicecenter Fahrgastrechte, 20-min binding release,
60-min refund option.

### 2.1 Flexpreis (1st/2nd class) (incl. Flexpreis with BahnCard 25/50)
- Validity (A.2.5.1): the travel day, plus the next day if >100 km; no train binding. Price: A.3.2. Return ticket:
  „Bei Fahrkarten für die Hin- und Rückfahrt wird der Fahrpreis für die Hinfahrt und für die Rückfahrt getrennt
  berechnet und sodann addiert" (3.2.2).
- Basis = the discounted price actually paid (BahnCard 25 → 75 %, BahnCard 50 → 50 % of Flexpreis). **verified-primary**
  for "price paid"; **secondary** (bahndampf.de, finanztip) that the BahnCard discount lowers the basis. The BahnCard's
  annual fee is never apportioned: **inferred**.
- 1st class free seat reservation (A.5.3); its value is 0, so there is nothing to refund.
- "Flexpreis Plus": **does not exist in the 2026 BB.** The products are Flexpreis, Flexpreis Business (G.3.6.3) and
  Flexpreis Young (E.21/E.32). **verified-primary** (absent from A.3 and Anlage 1).

### 2.2 Flexpreis Young (E.32, 01.09.–12.12.2026; earlier E.21, 01.04.–31.07.2026)
- 20 % off Flexpreis, 2nd class only, CityTicket included, BahnCard stackable. No FGR clause of its own, so §1
  applies. **verified-primary** (E.32 2.3–2.7); FGR by default: **inferred**.

### 2.3 Sparpreis, Super Sparpreis, Sparpreis/Super Sparpreis Young, Sparpreis/Super Sparpreis Senior
- Train binding plus C-class feeders on the travel day until 10:00 of the next day (3.3.1.2). Digital only (3.3.1.4).
  Entry prices from 2026 (3.3.2): Sparpreis 21.99 € / 29.99 €; Super Sparpreis 17.99 € / 23.99 €; Sparpreis Young
  16.99 €; Super Sparpreis Young 4.99 €; Sparpreis Senior 19.99 €; Super Sparpreis Senior 15.99 €.
- A BahnCard 25 **or 50** gives 25 % off (C.2.1).
- Rate and basis as in §1. **verified-primary.**
- Binding lifted from 20 min, per 9.1.1: „auch mit einer zuggebundenen Fahrkarte". The DB FAQ confirms this for the
  Senior fares (secondary).
- Refund option from 60 min: the refund is the price paid (9.1.3). Aktionsgutscheine are not refunded.
- **Missing 1st class (9.2.2)**, verified-primary: when an ICE/IC/EC runs without its scheduled 1st class, Sparpreis
  and Super Sparpreis 1st class holders get **20 € once, for each person on the ticket**, capped at the ticket value.
  Children entered free are excluded. Proof is required, e.g. a certificate from the train crew. Quote: „… erhalten
  gegen Nachweis (z. B. Bescheinigung des Zugpersonals) einmalig einen Betrag in Höhe von jeweils 20 €, für alle in
  der Fahrkarte eingetragenen Personen … Maximal wird jedoch der Wert der Fahrkarte Sparpreis bzw. Super Sparpreis
  für die 1. Wagenklasse erstattet."
- Minor: with Super Sparpreis Young at 4.99 €, 25 % = 1.25 € and 50 % = 2.50 €, both below 4 €, so nothing is paid
  (**inferred**). A payout needs a basis of **≥16.00 € at 25 %**, or **≥8.00 € at 50 %**. Mind the rounding at the
  edge: 15.98 € × 25 % = 3.995 € rounds to 4.00 €. Compare after rounding (**inferred**).

### 2.4 Aktions-Sparpreise (E.9/E.17 "Super Sparpreis Aktion" from 6.99 €, E.23 "Super Sparpreis Last Minute", E.8 "Sparpreis Business", E.11 Event fares, E.26 "Familienticket")
- None of these has its own FGR clause, so BB 9 applies with the price paid as the basis. **inferred** (each E-section
  says „Es gelten die BB Personenverkehr …").
- Familienticket (E.26; sold 14.06.–12.09.2026, travel until 14.09.2026): **one price for up to 5 persons**, 59.99 €
  single / 99.99 € return; 81.99 € / 143.99 € with C-class feeders. See §2.9 for how to split it per person;
  **unknown** whether DB pays per ticket or per person.

### 2.5 Hin- und Rückfahrt (return tickets)
- Each direction is a separate contract. A.1.3.4: „Beinhaltet eine Fahrkarte eine Hin- und Rückfahrt, so bilden
  diese Hin- und Rückfahrt jeweils einen separaten Beförderungsvertrag." **verified-primary**
- Basis = the price shown for that direction. **If no split is shown: half.** VO 19(3): „Wenn der Fahrpreis für die
  Einzelstrecken der Reise nicht angegeben ist, wird die Entschädigung dafür auf der Grundlage des halben entrichteten
  Fahrpreises berechnet." DB brochure: „Wenn der Fahrpreis für die Hin- und Rückfahrt gesamthaft ausgewiesen ist, wird
  die Entschädigung auf der Grundlage des halben entrichteten Fahrpreises berechnet." SCIC 19.2.5 (international):
  „Bei Fahrkarten für Hin- und Rückfahrt ist zur Ermittlung des Preises einer einfachen Fahrt der aufgedruckte Betrag
  zu halbieren." **verified-primary**
- Payout minimum: applied per claim, one claim per direction (9.2.1). **inferred**
- Deadline: runs from the end of each direction's validity. **inferred** from 2.5.1 and 9.5.

### 2.6 City-Ticket (+City)
- Free with Flexpreis (3.5.1). With the Sparpreis family it is charged separately when the connection needs local
  transport in the city area; no BahnCard discount on it (3.5.2).
- The local transport part is **its own contract with the local operator**. 3.5.3: „Werden im Rahmen des Zusatzes
  „+City" die Leistungen anderer Verkehrsträger (z.B. U-Bahn oder Bus) in Anspruch genommen, so kommt mit diesen ein
  jeweils eigenständiger Beförderungsvertrag nach deren Beförderungsbedingungen zustande." Also A.1.3.5.
  **verified-primary**
- Consequences:
  - A delay on the U-Bahn, tram or bus leg earns nothing under the EU regulation (FGF: „U-Bahnen, Straßenbahnen oder
    Busse fallen nicht hierunter").
  - The delay is measured at the **destination station of the rail ticket**, not at the final address.
  - Whether the paid City-Ticket surcharge is included in the basis: **unknown**. It appears as a separate price
    line. The conservative model is to exclude it for Sparpreis.

### 2.7 BahnCard 25 / 50 discounted fares
- Basis = the discounted price. BahnCard fee not apportioned (**inferred**). BahnCard prices 2026 (C.2.3, for
  reference): BC25 62.90 € / 125 €; BC50 244 € / 492 €.

### 2.8 Gruppenfahrkarten: Sparpreis Gruppe (3.6.1), Super Sparpreis Gruppe (3.6.2)
- 6–99 paying persons, **price per person** fixed (Sparpreis Gruppe: 9.99–135.99 € 2nd class / 26.99–215.99 € 1st;
  Super Sparpreis Gruppe: 8.99–127.49 € / 22.99–215.99 €). Children aged 6–14 pay half. Train binding. Digital only
  from 01.10.2026. Returns are issued as **two tickets** (3.6.1.3 as of 01.10.2026).
- FGR: BB 9 applies. The basis is the ticket (the group ticket = one contract).
  - Compensation = 25/50 % of the **total group price**, with one 4 € threshold per ticket: **inferred** from
    „pro Fahrkarte".
  - Only the affected persons may claim („selbst betroffene Reisende"). A split per person is possible if only some
    travellers were delayed: **inferred**.
  - **unknown**: how DB computes it when part of the group took an earlier train.
- For the app: only the booking person (Hauptreisender) has the Auftragsnummer. A per-person claim needs the group
  price divided by persons (the per-person price is stated in the tariff): **inferred**.

### 2.9 Children free on the parent's ticket (3.7.1–3.7.3) and the DB Familienkarte
- Children up to 5 travel free without a ticket. Children 6–14 travel free when entered on the ticket of a person
  ≥15 (Flexpreis, Sparpreis family), or with the DB Familienkarte above 5 persons.
- Their share of the price is **0 €**, so their compensation is 0 €. The ticket's compensation is computed once on the
  price paid; the child adds nothing. **inferred** from „gezahlten Fahrkartenwertes". 9.2.2/9.2.3 expressly exclude
  entered children from the 1st-class compensation (verified-primary).
- "Familienreservierung": the family reservation (5.2 price) can be refunded under 5.4 if it could not be used
  (see §2.14). No special rule. **inferred**
- Children travelling alone (3.7.4) pay half the Flexpreis or the Sparpreis. Normal rules on that price.

### 2.10 BahnBonus Prämienfahrkarten (K) and "free" tickets
- **Compensation is in BahnBonus points, not money.** K.3.1: „Im Falle von Ansprüchen auf Fahrpreisentschädigung
  nach Nr. 9.2 BB Personenverkehr erhalten Inhaber:innen von BahnBonus Prämienfahrkarten den jeweiligen Anteil (25%
  bzw. 50%) der für die BahnBonus Prämienfahrkarte angerechneten BahnBonus Prämienpunkte erstattet."
- Abandonment: the points are credited back (K.3.2).
- Freifahrt Flex: the points go to the account holder who ordered the reward, not to the traveller (K.4.2.5).
- **verified-primary**
- Consequence for the NGO model: **no cash is involved, so nothing can go to the NGO.** Treat these as not claimable
  for the NGO. The form field „BahnBonus-Nummer (wenn Punkte eingelöst wurden)" (FGF) exists for this case.
- A Prämienfahrkarte obtained through an Aktionsgutschein (K.2.2.2) falls under the same K.3 rule. **inferred**
- Mixed payment (points plus money) is not possible: Gutscheine cannot be combined with BahnBonus rewards (E.1.1.4).

### 2.11 Tickets paid with vouchers
- **Aktionsgutscheine** (E.1.3, e.g. 10/15/20 € coupons for BahnCard holders or the newsletter, "Kunden werben
  Kunden"): subtracted from the compensation basis (9.2.1) and not refunded (9.1.3). **verified-primary**
  Example: a 49 € ticket paid with a 15 € coupon has a basis of 34 €, so 25 % = 8.50 €.
- **Wertgutscheine** (Geschenkgutschein, DB Geschenkkarte, Stornogutschein, Fahrgastrechtegutschein, E.1.2.4): not
  excluded by 9.2.1, so they count as paid. **inferred** (the exclusion expressly names only E.1.3).
- The app needs to know which kind of voucher was used. The ticket PDF or booking shows it; **unknown** how. It is
  usually listed as a payment line.

### 2.12 bahn.business / Firmenkunden (G): Flexpreis Business, Sparpreis Business (E.8), BahnCard Business
- The normal BB 9 rules apply; no separate FGR clause. Flexpreis Business is valid 5 days per direction (G.3.6.3.3),
  so the validity end, and with it the deadline, differs.
- Online claim through the Geschäftskundenportal (G.4.7.1).
- Payee: the company paid, but the compensation belongs to the contract partner / traveller. Who that is for business
  bookings (the traveller or the company) is **unknown**. The DB FAQ: „Firma-gekaufte Tickets werden durch das
  ausgebende Unternehmen bearbeitet" (secondary).
- Bonus points (bahn.business Bonus) reduce nothing on the ticket price. **inferred**
- Firm-specific negotiated fares (Sonderabmachungen, EVO §4): basis = price paid. **inferred**

### 2.13 Schwerbehinderte Menschen
- Free travel under SGB IX Teil 3 Kap. 13 is **Nahverkehr only**, with the Wertmarke. In Fernverkehr only the
  **Begleitperson (Merkzeichen B)** travels free, plus a free seat reservation (D.2.1.1–2.1.2).
- The free companion has price 0, so no compensation. The disabled traveller's own paid ticket gets the normal
  compensation. **inferred** (D.2.1.1 verified; the limitation of free travel to Nahverkehr comes from SGB IX §228,
  secondary knowledge, not re-fetched).
- Short connection booked at the traveller's own insistence against DB's warning: DB is not liable for the missed
  connection (D.2.4.2). **verified-primary**

### 2.14 Seat reservation, bicycle ticket, bicycle space reservation
- Seat reservation: 5.50 € (2nd class) / 6.90 € (1st class) per person and direction (5.2).
  - **Refund in full** if the seat was not assigned, not provided, or could not be taken because of a delay. 5.4:
    „Konnten reservierte Sitzplätze nicht zugeteilt oder zugeteilte Sitzplätze nicht bereitgehalten oder wegen
    Verspätung eines Zuges nicht eingenommen werden, hat der Reisende Anspruch auf Rückzahlung des dafür gezahlten
    Reservierungsentgelts." **verified-primary**
  - **No delay threshold** and no 4 € minimum (it is a refund, not compensation under 9.2): **inferred**. The DB FAQ
    says it applies to „Sitz- und Fahrradstellplätze" and is claimed under „Verspätung unter 60 Minuten" → „Ich konnte
    meine Reservierung nicht nutzen" (secondary).
  - Refund, so paid in money, not as a voucher: **inferred** from the FAQ.
- The reservation is **not** part of the compensation basis for domestic tickets. It is a separate product and 9.2.1
  refers to the ticket: **inferred**. **International is different:** SCIC 19.2.3: „Für die Berechnung der
  Gesamtentschädigung werden neben der Fahrkarte auch zur Fahrkarte gehörige Reservierungen, Aufpreise und Zuschläge,
  sofern sie verpflichtend zu entrichten waren und eindeutig als zugehörig erkennbar sind, addiert."
  **verified-primary**
- Fahrradkarte Fernverkehr (8.4.1): 20 % of the 2nd class Flexpreis, min 7.99 €, max 14.99 €; with Sparpreis fares the
  same 20 % with the same limits (8.4.3). It includes the space reservation and follows the train binding.
  - Refund when carriage was impossible: the form has a tick box „Fahrradmitnahme war nicht möglich" (FGF).
  - Whether a 25/50 % delay compensation applies to the bicycle ticket itself: **unknown**. It is a Beförderungsentgelt,
    so a claim is arguable. DB practice is not documented.
- Bicycle space reservation alone: 7.50 €, cannot be cancelled (8.4.2). Refundable under 5.4 per the FAQ (secondary).
- BahnCard 100 holders: bicycle free; reservation from the quota or 7.50 € (C.3.7.1, from 02.09.2026).

### 2.15 1st class upgrades (Übergang)
- **Übergang 1. Klasse** for Flexpreis (A.2.6.2, the Flexpreis difference) and the online Aktionsangebot „Übergang 1.
  Klasse" (E.4). Not possible with train binding (2.6.4).
- An Übergang is a supplement to the Flexpreis ticket. Compensation on the combined price (ticket + Übergang):
  **inferred**. Whether DB treats it as its own ticket with its own 4 € threshold: **unknown**.
- Missing 1st class with Flexpreis (9.2.3): „eine Entschädigung in Höhe des Differenzbetrages zwischen den Flexpreisen
  der 2. und 1. Wagenklasse, für alle in der Fahrkarte eingetragenen Personen" for the affected legs, on proof.
  Entered children excluded. **verified-primary**
- BahnBonus "1. Klasse Upgrade" (K.4.3): points only (K.3).

### 2.16 10-Fahrten-Ticket / 20-Fahrten-Ticket (E.5) and "Mehrfahrtenticket Plus" (E.28/E.29, 60 % off for Deutschland-Ticket holders, 07.07.2026–30.01.2027)
- A bundle; each single trip is booked as its own ticket valid on the travel day until 03:00 of the next day (E.5 4.4).
- No FGR clause, so BB 9 applies. The basis per trip = bundle price / 10 (or / 20): **inferred**, with Art. 19(3)
  last sentence by analogy („anteilig zum vollen Preis"). **unknown** how DB actually computes it.
- Payout minimum per single trip. On short routes of ≤250 km, 25 % will often be below 4 €. **inferred**
- E.28/E.29 (combined with the Deutschland-Ticket): C-class trains are not allowed. The D-Ticket and the
  Mehrfahrtenticket are separate contracts (see §5). **inferred**

### 2.17 Sparpreis Europa / Super Sparpreis Europa / Flexpreis Europa (international DB tickets)
See §4.1.

### 2.18 Kinder-/Familien-/Event-/Business products summary table

| Product | Basis for 25/50 % | Special | Confidence |
|---|---|---|---|
| Flexpreis (± BahnCard) | price paid | 1st-class-missing: Flexpreis difference (9.2.3) | verified-primary |
| Flexpreis Young | price paid | – | inferred |
| Flexpreis Business | price paid | 5-day validity | inferred |
| Sparpreis / Super Sparpreis (+Young/Senior) | price paid | 1st-class-missing 20 €/person (9.2.2) | verified-primary |
| Super Sparpreis Aktion / Last Minute | price paid | – | inferred |
| Sparpreis Business / Event fares | price paid | – | inferred |
| Familienticket (flat for ≤5) | ticket price (per-person split unknown) | – | inferred |
| Sparpreis Gruppe / Super Sparpreis Gruppe | ticket price; split per person unknown | – | inferred |
| Free child 6–14 on ticket | 0 € | excluded from 9.2.2/9.2.3 | inferred / verified |
| Return ticket | per direction; half if not split | – | verified-primary |
| Prämienfahrkarte | points, 25/50 % of points | no money | verified-primary |
| Aktionsgutschein part | excluded | – | verified-primary |
| Wertgutschein part | included | – | inferred |
| Seat reservation | full refund of the fee if unusable | no threshold | verified-primary (refund) |

---

## 3. Fernverkehr Zeitkarten (flat rates per case)

General: VO 19(2) lets the railway set its own conditions for season tickets. Brochure (secondary, Stand 09/2024):
„Zeitkarteninhaber (Ausnahme BahnCard 100) können auch mehrere Verspätungsfälle ab 20 Minuten innerhalb der
Geltungsdauer der Zeitkarte zusammenrechnen und gesammelt zur Erstattung oder Entschädigung einreichen." and
„Entschädigungsbeträge unter 4 Euro werden nicht ausgezahlt; reichen Sie deshalb Entschädigungsanträge bei
Zeitfahrkarten des Nahverkehrs gesammelt ein."

### 3.1 BahnCard 100 (C.3), incl. Probe BahnCard 100 and My BahnCard 100 (E.7)
- Validity: 1 year (Probe: 3 months), ending at 03:00 after the last day (C.3.2.1).
- Price 2026: **4,899 € (2nd class) / 7,999 € (1st class)** (C.3.3.1); Probe 1,459 € / 2,599 €; My BahnCard 100
  3,199 € / 5,999 € (E.7 4.1, can be bought until 13.12.2026).
- **Rate: 10 € (2nd class) / 15 € (1st class) per case of ≥60 min.** C.3.10.1: „… bei Ausfall, Verspätung oder
  Anschlussversäumnis von Zügen ab 60 Minuten eine Erstattung bzw. Entschädigung in Höhe von 10 €, Inhaber einer
  BahnCard 100 1. Klasse eine solche in Höhe von 15 € erhalten, insgesamt max. 25 % des gezahlten BahnCard-Preises.
  Verspätungen können nicht zwecks Erreichen der Zeitgrenze nach Satz 1 addiert werden." **verified-primary**
- Pooling: **no**. Each case must reach ≥60 min on its own.
- 120-min step: none. 10/15 € flat regardless of 60 or 180 min: **verified-primary** (single amount in C.3.10.1).
- Cap: **25 % of the BahnCard price paid**, over the card's validity:
  - 2nd class: 1,224.75 €, i.e. 122 cases.
  - 1st class: 1,999.75 €, i.e. 133 cases.
  - The cap basis is the price **paid**, so a My BahnCard 100 has 799.75 € / 1,499.75 €.
  - An Aktionsgutschein used when buying the card (e.g. the 350/600 € vouchers „für ehemalige BahnCard 100
    Abo-Kunden", E.1.3.4) presumably reduces the cap. **inferred**, since 9.2.1's voucher rule applies to tickets.
- Expenses for taxi or other modes (9.1.5/9.1.6) are also capped at 25 % of the BahnCard price, except in the
  Art. 20(2)(c)/(3) cases (C.3.10.1).
- Missing 1st class: **extra 10 €** per affected trip for BahnCard 100 1st class, on proof (C.3.10.2: „erhalten
  Inhaber einer BahnCard 100 1. Klasse gegen Nachweis (z. B. Bescheinigung des Zugpersonals) für die betroffene Fahrt
  einen Betrag in Höhe von 10 €"). **verified-primary**
- Payout minimum: 9.2 applies through the C.3.10.1 reference, so <4 € is not paid. With 10 € per case it never
  matters.
- **Monthly payment:** **no longer offered.** C.3.2.2: „Die Zahlung des Fahrpreises ist sofort fällig." No instalment
  option appears anywhere in C.3 (verified-primary). The monthly BahnCard 100 subscription ended in December 2022
  (secondary: reisetopia, monsterdealz, mannheimer-morgen „Warum es die BahnCard 100 nicht mehr als Abo gibt").
  Legacy subscriptions no longer exist; E.1.3.4 now targets „ehemalige BahnCard 100 Abo-Kunden".
- **Employer-paid:** the cap stays 25 % of the price paid for the card. Who receives the money (holder or employer)
  is **unknown**. DB pays the applicant's account. The holder is the contract party (personal, photo ID), so the
  holder is entitled: **inferred**. With a company BahnCard 100 through bahn.business, claims go through the
  Geschäftskundenportal (G.4.7.2).
- **BahnCard 100 on a Nahverkehr train (RE/RB/S):**
  - The BahnCard 100 itself is valid in **all trains of classes ICE, IC/EC and C** (C.3.1.1: „berechtigt ihren Inhaber
    zur Beförderung in allen Zügen gemäß Nr. 1.4 der BB Personenverkehr"; 1.4 (ii) includes class C).
  - A Deutschland-Ticket is also issued free as a **separate contract**. C.3.1.1.1: „Die BahnCard 100 und das
    Deutschland-Ticket stellen getrennte Beförderungsverträge auch im Hinblick auf die tariflichen Fahrgastrechte dar."
    C.3.10.3: „Die Fahrgastrechte bei Nutzung des Deutschland-Tickets richten sich gem. Nr. 3.1.1.1 nach dem Tarif für
    das Deutschland-Ticket." **verified-primary**
  - Reading: C.3.10.3 governs only when the journey was made **on the D-Ticket**. A journey inside Germany on
    RE/RB/S between tariff points of the Streckenentfernungszeiger is also covered by the BahnCard 100 contract. That
    suggests 10 € per case ≥60 min, if the holder claims under the BahnCard 100. **inferred.** DB practice is
    **unknown**; the brochure and FAQ don't address it.
  - The D-Ticket route gives only 1.50 € per case with pooling (other agent's scope).
  - What decides it in practice is which "ticket" is chosen in the online claim (BahnCard → „Optionen" →
    „Entschädigung beantragen" vs. D-Ticket). **Open question, test with a real claim.**
  - Outside the Streckenentfernungszeiger (e.g. U-Bahn, Verbund-only lines), only the D-Ticket covers the journey.
- Claim: online in the Kundenkonto (BahnCard → Optionen → „Entschädigung beantragen", FAQ) or by the form, ticking
  „BahnCard 100" with BahnCard number **and date of birth** (FGF: „Geburtsdatum (TT.MM.JJJJ) – Nur bei BahnCard 100
  anzugeben"). No price proof is needed: brochure/fgr page „Wenn Ihre Fahrkarte keinen Preisaufdruck hat, legen Sie
  bitte zudem einen Kostennachweis bei (Ausnahme: BahnCard 100)." **verified-primary** (bahn.de page)
- Deadline: 1 year after the BahnCard 100's validity ends (9.5 through C.3.10.1). There is no statutory point by
  which one must submit; each case can be claimed individually. **inferred**

### 3.2 Streckenzeitkarten ICE and IC/EC (Wochenkarte, Monatskarte, Jahreskarte im Abo, Monatskarte im Abo), 1st/2nd class
- B.13.1, **verified-primary**: „Für Inhaber einer Zeitkarte für die Produktklassen IC/EC oder ICE oder einer
  IC/EC-Aufpreiskarte nach Nr. 12 gelten die Nummern 9.1.3, 9.2 und 9.3 BB Personenverkehr mit der Maßgabe, dass diese
  bei Ausfall, Verspätung oder Anschlussversäumnis ab 60 Minuten innerhalb der Geltungsdauer der Fahrkarte eine
  Erstattung bzw. Entschädigung in Höhe von 5 € für die 2. Wagenklasse und 7,50 € für die 1. Wagenklasse erhalten,
  Verspätungen ab 20 Minuten können zwecks Erreichen der Zeitgrenze nach Satz 1 addiert und gesammelt eingereicht
  werden. Insgesamt werden maximal 25 % des gezahlten Fahrkartenpreises ausgezahlt."
  - Rate: 5 € (2nd class) / 7.50 € (1st class) per 60 min block, flat; no 120-min step.
  - **Pooling: yes.** Delays of ≥20 min each are added up within the card's validity. Each full 60 min of the sum is
    one case: **inferred**. The text says only „addiert … zwecks Erreichen der Zeitgrenze". Whether remainders carry
    over is **unknown**.
  - Cap: 25 % of the ticket price paid.
- B.13.3, verified-primary: „Eine Kumulation der Entschädigungsbeträge nach Nr. 13.1 erfolgt nur, wenn die
  Entschädigungsforderungen gesammelt eingereicht werden, bei Wochen- und Monatskarten gesammelt für den
  Geltungszeitraum nach Ablauf der Geltungsdauer der Fahrkarte. Bei Fahrkarten ohne Preis ist vom Reisenden ein Beleg
  über den gezahlten Preis beizufügen."
  - **Wochen- and Monatskarten: submit once, after expiry, for the whole period.**
  - Jahreskarten: no fixed point. Collected claims may be submitted at any time (e.g. when ≥4 €). **inferred**
- Payout minimum: <4 € not paid (9.2 through 13.1). A single 2nd class case (5 €) is already enough.
- **Cap window and basis:** "innerhalb der Geltungsdauer der Fahrkarte" / "gezahlten Fahrkartenpreises".
  - Wochenkarte: the week price; Monatskarte: the month price.
  - Jahreskarte im Abo paid at once: the annual price, over the year.
  - **Monatskarte im Abo** (monthly payment, B.5.3): the card is still issued with a one-year validity (B.3.2.1: „Die
    Fahrkarte wird unabhängig hiervon mit einer Geltungsdauer von jeweils einem Jahr ausgestellt"). The cap is then
    presumably 25 % of the amount paid so far in that year, or of 12 monthly instalments. **unknown**.
- Deadline: 1 year after the card's validity ends (9.5). **inferred**
- Form: tick „Zeitkarte" and give the Zeitkarten-Nummer (FGF); ticket copy; price proof if no price is printed (13.3).
  Online in the Kundenkonto under „Zeitkarten & Abos" (FAQ). **verified-primary / secondary**
- Samstag-Mitnahme of 1 person plus 3 children (B.2.3): the companion paid nothing, so nothing is due. **inferred**
- **Refund option ≥60 min (9.1.3)** also applies to Zeitkarten per B.13.1, but at the flat amount. **inferred**
- Missing 1st class for Zeitkarten: no special rule (9.2.2/9.2.3 name Sparpreis and Flexpreis; C.3.10.2 names the
  BahnCard 100). **verified-primary** (absence)

### 3.3 Schüler-/Studenten-Streckenzeitkarten (Schülermonatskarte, Schülermonatskarte im Abo, Schülerwochenkarte)
- Schülerzeitkarten are Zeitkarten (B.1: „Zeitkarten sind die Strecken- und die Schülerzeitkarten"). If issued for
  ICE or IC/EC, B.13.1 applies: 5 € per ≥60 min, pooling from 20 min, cap 25 %. 2nd class only (B.2.4).
  **inferred** (B.13.1 speaks of „Zeitkarte für die Produktklassen IC/EC oder ICE").
- A C-class-only Schülerzeitkarte falls under the Nahverkehr rules (other agent's scope).

### 3.4 Pendler-/Job-Streckenzeitkarten
- There is **no separate "Job-Ticket" product in the DB Fernverkehr tariff (B).** Employer-subsidised cards are the
  normal Streckenzeitkarten, or Sonderabmachungen under EVO §4. Same rules as §3.2. **inferred** (B lists only
  Jahreskarte/Monatskarte im Abo, Monats-, Wochen- and Schülerkarten).

### 3.5 IC/EC-Aufpreiskarte (to Verbund-Zeitkarten), B.12
- Sale discontinued: annual cards since 01.10.2025, weekly and monthly since 31.12.2025. Subscription contracts ran
  out by about spring 2026 (6 more months after 01.10.2025). A few annual cards may still be valid until about
  September 2026. B.12.4/12.5 **verified-primary**
- FGR: the same as Streckenzeitkarten (B.13.1 names them): 5 € / 7.50 € per ≥60 min, pooling from 20 min, cap 25 %
  of the **Aufpreis** price. **verified-primary**
- Practical relevance in October 2026: close to none. Keep for old data.

### 3.6 IC/EC-Semesterticket (B Anlage 1 b)
- Student ID with IC/EC validity through an AStA agreement.
- Anlage 1 b 6.1, **verified-primary**: „Für Inhaber, die innerhalb der Geltungsdauer des IC/EC-Semestertickets
  wiederholt Verspätungen/Anschlussverluste (mindestens 3/Monat) mit jeweils mindestens 60 Minuten erleiden, gelten
  die Nummern 9.2 und 9.3 BB Personenverkehr mit der Maßgabe, dass der Inhaber eine Entschädigung in Höhe von 1,30 € je
  Einzelfall, maximal 4 €/Monat erhält."
  - **1.30 € per case**, only when ≥3 cases of ≥60 min occur in a month; **max 4 € per month**; no pooling of shorter
    delays.
- 6.2: collected submission for the whole semester, after it ends.
- Payout minimum: the 4 € rule is in 9.2, and a month maxes out at 4 €. Whether the 4 € minimum applies to the
  semester total (pay if ≥4 €) or would bar every month: **inferred** that it applies to the semester total, since it
  is submitted collectively.
- Also: „Entfall Anerkennung der Studierendenausweise der Universität Marburg in freigegebenen IC-/EC Zügen"
  (notice 14/2026). Few ASten remain.

### 3.7 44-Stunden-Ticket Young (E.19)
- 44 € flat, 2nd class, ages ≤26, ICE/IC/EC only. Weekends Fri 18:00 – Sun 14:00; sold 01.02.–19.03.2026 for the
  weekends 06.02.–22.03.2026. **Expired.** Could reappear.
- E.19 4.2, **verified-primary**: „… eine Erstattung bzw. Entschädigung in Höhe von 5 € erhalten. Verspätungen ab 20
  Minuten können … addiert und gesammelt eingereicht werden. Insgesamt werden je „44-Stunden-Ticket Young" maximal 25%
  des Preises der Fahrkarte ausgezahlt."
  - 5 € per ≥60 min; pooling ≥20 min; cap 11 € (2 cases).
  - C-class trains are not usable even when the binding is lifted (4.1).

### 3.8 German Rail Pass (DB pass for non-residents, SCIC-RPT C.3)
- 3.15, **verified-primary**: „Für German Rail Pässe wird bei Verspätungsfällen von mindestens 60 Minuten pro Fall eine
  pauschale Entschädigung von 5,00€ bei Pässen 2. Klasse bzw. 7,50€ bei Pässen 1. Klasse, bis zu einem maximalen Betrag
  von 25% des Passpreises erstattet."
  - Form by post to the Servicecenter Fahrgastrechte.
  - No pooling clause, so no pooling. **inferred**

### 3.9 "Deutschland-Ticket + Fernverkehr" add-ons and new 2026 products
- There is no general D-Ticket add-on for Fernverkehr. The 2026 tariff has only:
  - the **regional Mehrfahrtenticket Plus** discounts (E.28 MV–Hamburg, E.29 Mainz–Bonn), see §2.16;
  - the free D-Ticket bundled with the BahnCard 100 (C.3.1.1.1);
  - the Nahverkehr-only D-Ticket recognised on some IC/EC routes (Preisliste Nr. 2; other agent's scope). There, the
    D-Ticket's FGR apply: **inferred** from BB 1.2.1/1.2.2.
- No Fernverkehr flat rate other than the BahnCard 100 exists in the 2026 BB. **verified-primary** (TOC and all E
  sections checked). The "Probe BahnCard Gold" (E.18) is a BahnCard promotion, not a ticket.

### 3.10 Zeitkarten summary

| Product | Per case | Threshold | Pooling | Cap | Submit | Confidence |
|---|---|---|---|---|---|---|
| BahnCard 100, 2nd class | 10 € | ≥60 min each | **no** | 25 % of the BC price paid (validity window) | any time within 1 year after validity | verified-primary |
| BahnCard 100, 1st class | 15 € (+10 € if 1st class missing) | ≥60 | no | 25 % | same | verified-primary |
| Streckenzeitkarte ICE or IC/EC, 2nd class | 5 € | ≥60 (sum of ≥20-min delays) | **yes, ≥20 min** | 25 % of the ticket price paid (validity) | week/month: after expiry, collected; year: collected | verified-primary |
| Streckenzeitkarte, 1st class | 7.50 € | same | yes | 25 % | same | verified-primary |
| IC/EC-Aufpreiskarte | 5 / 7.50 € | same | yes | 25 % of the Aufpreis | same | verified-primary |
| Schülerzeitkarte ICE or IC/EC | 5 € | same | yes | 25 % | same | inferred |
| IC/EC-Semesterticket | 1.30 € | ≥60 each, and ≥3 cases per month | no | 4 €/month | after the semester | verified-primary |
| 44-Stunden-Ticket Young | 5 € | ≥60 | yes, ≥20 | 25 % of 44 € | – | verified-primary |
| German Rail Pass | 5 / 7.50 € | ≥60 | not stated | 25 % of the pass price | by post | verified-primary |

---

## 4. International and other operators

### 4.1 DB international tickets (Flexpreis Europa, Sparpreis Europa, Super Sparpreis Europa, group fares; CIV through tickets)
- Conditions: GCC-CIV/PRR + DB SCIC-NRT (BB A.1.1). Stations abroad that are part of the domestic tariff count as
  domestic (A.1.1).
- Rate: 25/50 % at 60/120 min under VO Art. 19. **verified-primary**
- Basis: the price shown on the DB ticket. SCIC 19.2.1: „… besteht ein Anspruch auf eine Verspätungsentschädigung auf
  Basis des auf der DB FAHRKARTE angegebenen Fahrpreises."
  - **Plus mandatory reservations and supplements** (19.2.3, quoted in §2.14).
  - Return ticket: halve the printed amount (19.2.5).
- Delays that occurred **outside the EU** do not count toward the delay (VO 19(4): „Verspätungen, für die das
  Eisenbahnunternehmen nachweisen kann, dass sie außerhalb der Union eingetreten sind, werden … nicht berücksichtigt").
  Relevant for Switzerland, the UK and Norway. **verified-primary**
- Payout minimum: SCIC 19.2.2: „Entschädigungsbeträge unter 4,00€ werden nicht ausgezahlt." **verified-primary**
- Binding release: from **60 min** for international journeys, not 20. DB FAQ and brochure (secondary): „Bei einer zu
  erwartenden Verspätung von 20 Minuten oder mehr bei nationalen Reisen bzw. von 60 Minuten oder mehr bei
  internationalen Reisen …"
- Deadline: SCIC A.20: „Ansprüche nach Nr. 19 verjähren innerhalb eines Jahres nach Ablauf der Geltungsdauer der
  Fahrkarte." **verified-primary**
- Desk: SCIC 19.1.2/19.1.3: the Servicecenter Fahrgastrechte for DB tickets; for claims generally the **issuing
  company** (AUSGEBENDES UNTERNEHMEN). Non-DB tickets can be handed to DB, which forwards them.
  - Taxi and hotel costs are handled by the carrier obliged at the place of disruption (19.1.4); DB for DB lines and
    for ICE to/from Brussels over their whole route.
  - DB FAQ (secondary): „Das Eisenbahnunternehmen, das die Fahrkarte ausgegeben hat, bearbeitet den Verspätungsfall."

### 4.2 Tickets issued by foreign railways used in Germany (ÖBB incl. Nightjet, SNCF/TGV, SBB, NS, ČD, PKP …)
- The issuing company handles the claim (VO; DB FAQ „Firma-/Drittgekaufte Tickets … ausgebende Unternehmen"; SCIC
  19.1.3). **secondary**
- ÖBB / Nightjet (secondary, oebb.at): 25 % of the one-way fare at 60+ min, 50 % at 120+, „provided the amount reaches
  at least €4"; claim online or through ÖBB customer service. **ÖBB claim deadline not confirmed** (open). DB warns
  that international railways may apply 3 months. **unknown / secondary**
- SNCF/TGV Inoui on the Germany–France high-speed service: on DB-issued tickets the DB desk; on SNCF-issued tickets
  SNCF (G30 / EU form). **inferred**
- Eurostar: out of scope (no service in Germany).

### 4.3 Interrail / Eurail passes (SCIC-RPT C.1/C.2; interrail.com)
- **Flat 12 € at 60–119 min, 24 € at ≥120 min, per delay**, for Global and One Country passes. SCIC C.1.16:
  „Für Verspätungen am Zielort zwischen 60 und 119 Minuten werden 12 EUR, für Verspätungen am Zielort ab 120 Minuten
  werden 24 EUR als Entschädigung gezahlt." **verified-primary**
- Payout minimum: „Entschädigungen werden nur ausgezahlt, wenn der berechnete Betrag höher als 4€ ist" (C.1.16). The
  operator is **`> 4`**, not `>= 4`, but irrelevant at 12 €.
- Cap: „The maximum compensation amount is limited to 50% of the Pass price." (interrail.com) **verified-primary**
  (operator's own page)
- Deadline: „within three months of the end of the last day of validity of your Pass" (interrail.com).
  **verified-primary**
- Desk:
  - Global passes: online at Interrail/Eurail (eurail.delay-compensation).
  - One Country / German Rail Eurail passes: online there, or the DB form by post to the Servicecenter Fahrgastrechte.
  - DB FAQ (secondary): the Servicecenter Fahrgastrechte may forward to Interrail; extra costs (taxi, hotel) are handled
    by the Servicecenter itself.
- Pooling: none. Separate contracts are treated per segment (interrail.com).
- Passzuschlag (supplement for DB international trains, SCIC 5.2.5): a separate ticket; normal rules on its price.
  **inferred**
- Note: „Abschaffung Interrail One Country Germany Pass" appears in the SCIC 2026 change log. **verified-primary**

### 4.4 FlixTrain (Flix SE, open access; its own conditions; not in DB's joint procedure)
- Rate: „25 % des Preises der Fahrkarte bei einer Verspätung von 60 bis 119 Minuten", „50 % … ab 120 Minuten"
  (flixtrain.de/fahrgastrechte). **verified-primary** (operator page)
- Payout minimum: „Entschädigungen werden nur ausgezahlt, wenn der berechnete Betrag **höher als** 4 EUR ist."
  Payable when `amount > 4.00`, stricter than DB's `>= 4.00`. **verified-primary**
- Deadline: „… Zug-Fahrgäste innerhalb von drei Monaten nach der tatsächlichen oder geplanten Durchführung eines
  Linienverkehrsdienstes beim Beförderer Beschwerden einreichen." The summary also lists „The complaint wasn't
  submitted within three months" as an exclusion. **3 months from the journey.** **verified-primary**
- Desk: the FlixTrain contact form (help.flixtrain.com). Escalation to the Schlichtungsstelle Reise & Verkehr or the
  EBA.
- Voucher vs cash: not stated. By VO 19(7) cash is due on request. **inferred**
- No 20-min rerouting onto DB trains; only the 100-min rule (VO Art. 18(3)). **secondary**
- DB tickets are not valid on FlixTrain, and vice versa. A connection between FlixTrain and DB = separate contracts,
  §5. **inferred**

### 4.5 European Sleeper (Brussels–Prague via Berlin; Paris–Berlin since 03/2026; Brussels–Milan from 09/2026)
- 25 % at 60–119 min, 50 % at ≥120 min, claimed through its claim form with the booking code
  (europeansleeper.freshdesk.com). **secondary** (operator help centre)
- Payout minimum, deadline: **unknown**. Presumably 4 € and the Art. 28 3 months; to be checked.
- Other costs (hotel, other trains) are excluded by its help page. That conflicts with Art. 18/20 of the regulation;
  flag it.

### 4.6 Other open-access trains in Germany in 2026 (desk = the operator; rules = VO 2021/782 minimum)
- **GoVolta** (Amsterdam–Berlin and Amsterdam–Hamburg since 19.03.2026), **Snälltåget** (Berlin–Malmö–Stockholm night
  train), **RDC / BTE AutoReiseZug** (Hamburg–Lörrach), **Alpen-Sylt Nachtexpress** (Salzburg–Westerland).
  Source: railjournal, railvolution, Wikipedia (secondary).
- Each is its own carrier with its own desk. Expect 25/50 %, a 4 € minimum at most, and often a 3-month window.
  Their terms: **unknown**.
- SBB GmbH (Konstanz), CFL, and Thalys/Eurostar are listed as NE-EVU partners in BB Anlage zu 1.3.1. On DB-tariff
  tickets their trains fall under the joint DB procedure. **verified-primary** (list)

### 4.7 Participating railways in DB's joint procedure
- The list is at bahn.de/service/buchung/fahrgastrechte/teilnehmende_evu (BB 1.3.4, 9.3.1). For tickets in the DB
  tariff (Fernverkehr tickets including their C-class feeders), their trains are covered through the Servicecenter
  Fahrgastrechte. **verified-primary** (reference; list not re-fetched)

---

## 5. Journeys with several tickets

- **One through ticket = one contract**, including several tickets from **one purchase transaction**. BB A.1.3.4:
  „Gleiches gilt, wenn im Rahmen eines einzelnen Verkaufsvorgangs aus technischen Gründen mehrere Fahrkarten
  ausgegeben werden, die zusammen die einfache Fahrt abbilden." SCIC definition: „Bei Ausgabe mehrerer Fahrkarten liegt
  eine DURCHGANGSFAHRKARTE dann vor, wenn die Fahrkarten in einer einzigen KOMMERZIELLEN TRANSAKTION gebucht wurden und
  bei der Buchung nicht auf eine Abweichung hingewiesen wurde." **verified-primary**
  - Then the delay is measured at the **final destination of the ticket**. A missed connection counts; the basis is
    the whole price.
- VO Art. 12(1): a single railway (including one group, "demselben Eigentümer gehören") **must** offer through tickets
  for its long-distance services. Art. 12(2): the passenger must be told before purchase whether the tickets form a
  through ticket. **verified-primary**
  - Art. 12(3)–(7) (not quoted verbatim): if a railway or ticket vendor sells separate tickets as a combined journey
    without the required information, it owes the Art. 18 refund plus 75 % compensation. **secondary**
    (general knowledge of Art. 12(3)/(5); **re-verify the verbatim text** on EUR-Lex).
- **Separate purchases = separate contracts.** Each ticket's delay counts only between its own departure and
  destination stations. A connection missed because ticket A's train was late gives **no** claim on ticket B, and B's
  binding **stays**.
  - DB FAQ (secondary): „Sie haben keinen Anspruch auf durchgängige Fahrgastrechte zwischen Nah- und Fernverkehr." …
    „bleibt die Zugbindung bestehen" … „Entschädigungsansprüche werden für jedes Ticket einzeln geprüft und gelten nur
    für das jeweilige Fernverkehrsticket oder das Deutschland-Ticket."
  - Interrail (primary for passes): „Under multiple separate Contracts of Carriage, each segment is treated
    independently."
- **Deutschland-Ticket + Fernverkehr ticket:** two contracts, as above. The delay of the Fernverkehr ticket is measured
  at **its** destination. A D-Ticket delay is compensated under the D-Ticket tariff (1.50 € per case; other agent).
  - If a delay forces the use of ICE/IC on the D-Ticket leg, the fare is reimbursed up to 120 € in the 0–5 h and
    last-train cases only (D-Ticket FAQ, secondary).
- **Fernverkehr ticket with C-class feeders on the same ticket** (Sparpreis „Vor- und Nachlauf", Flexpreis routes
  including RE/RB): one contract. A missed ICE because the feeder RE was late **does** count. Binding lifted from
  20 min (9.1.1).
- **BahnCard 100 + D-Ticket:** separate contracts, see §3.1.
- **City-Ticket local transport:** a separate contract with the local operator, not rail FGR (§2.6).
- **Return tickets:** each direction is its own contract (§2.5).
- Model implication: store per ride the ticket (contract) it belongs to, that ticket's destination and planned
  arrival, and the purchase transaction id (Auftragsnummer). Compute the delay per ticket at that ticket's
  destination. Tickets from one Auftragsnummer form one through ticket.

---

## 6. Data DB needs (form, EU form, online)

### 6.1 Fahrgastrechte-Formular (ME/08/25), fgf.txt — verified-primary
- **Section 1 (trip):**
  - What happened: „Verspätung am Ziel (mind. 60 Minuten)" / „Reise nicht angetreten" / „Reise unterwegs
    abgebrochen und zurück zum Startbahnhof" (+ station) / „Reise unterbrochen und mit anderem Verkehrsmittel
    fortgesetzt, für das Zusatzkosten entstanden sind" (+ station).
  - Planned trip (Hinfahrt/Rückfahrt): date*, departure station*, scheduled departure*, destination station*,
    scheduled arrival*. Stations „so detailliert wie möglich".
  - Actual arrival: date* and time* (not filled when the trip was not started or was abandoned at the start).
  - Extra expenses: additional train ticket / other mode (taxi, bus) / overnight / other, **with complete receipts**.
  - Extra information: „Ich konnte meine Reservierung nicht nutzen", „Fahrradmitnahme war nicht möglich", other.
- **Section 2 (ticket):**
  - Digitales Ticket: **Auftrags-Nummer**.
  - BahnCard 100: **BahnCard-Nummer + Geburtsdatum**.
  - Zeitkarte: **Zeitkarten-Nummer**.
  - BahnBonus: **BahnBonus-Nummer** (when points were used).
  - Other ticket (e.g. from a ticket machine): **enclose the ticket**.
- **Section 3 (payout):** Gutschein or Geldauszahlung/Überweisung; Kontoinhaber (Name, Vorname)*, **IBAN***, **BIC***;
  own reference (optional). Hint: „In bestimmten Fällen ist eine Gutscheinausgabe nicht möglich."
- **Section 4 (person):**
  - Company (optional); salutation; first name*, surname*; street*, number*, postcode*, town*, country (if not DE);
    phone (optional); **e-mail for a digital reply** (optional).
  - Signature* and date*, confirming „dass ich der rechtmäßige Inhaber der Fahrkarte(n) bin" and that originals are
    not returned.
  - Data processed by DB Dialog GmbH and forwarded to other railways when responsible.
- **Enclosures:** the ticket or a copy (for compensation). **Price proof when the ticket shows no price, except the
  BahnCard 100.** Originals for refunds and expenses. Train crew certificates („Bescheinigung Fahrgastrechte",
  „Bescheinigung über Komfortmängel") if any. (bahn.de/fahrgastrechte, 9.3.2)
- Address: DB Fernverkehr AG, Servicecenter Fahrgastrechte, 60647 Frankfurt am Main (FGF). The brochure names „DB
  Dialog GmbH, Servicecenter Fahrgastrechte, 60647 Frankfurt am Main". Or hand it in at a DB Reisezentrum or Agentur,
  which forwards it.

### 6.2 EU standard form (Commission implementing act under Art. 19(5))
- DB accepts it by post or e-mail to **EUAntragFGR@deutschebahn.com**, subject „Fahrgastrechte: EU-Antragsformular".
  - Attachments must be .pdf, .jpg, .tif, .doc(x), .xls(x), .txt, .gif or .png.
  - Reply in German if the German form was used, otherwise in English.
  - **No payout to PayPal, Apple Pay and the like.**
  - Source: DB FAQ „eu-formular" (secondary).
- Relevant for a relaying app: **e-mail submission is possible** through the EU form, whereas the DB form is
  post-only. **secondary**

### 6.3 Online (DB Kundenkonto, DB Navigator, Auftragssuche)
- Single tickets: the ticket must be bought in or stored in the Kundenkonto → „Vergangene Reisen" → „Entschädigung
  beantragen". Without an account: the Auftragssuche with the **12-digit Auftragsnummer + the traveller's surname**.
  - Only **one claim per booking**: „Sie haben bereits eine Entschädigung für diese Buchung beantragt. Eine erneute
    Beantragung ist nicht möglich."
  - The button appears only from the validity date on, and not for cancelled tickets or after the deadline.
  - Source: FAQ „Ansprüche", secondary.
- BahnCard 100: Kundenkonto → BahnCard → Optionen → „Entschädigung beantragen" (BB 9.4.3).
- Zeitkarten: Kundenkonto → „Zeitkarten & Abos".
- Business: the bahn.business portal (G.4.7).
- Receipts: upload up to 120 € (9.4.4).
- The online process has no documented third-party submission. The form's signature line asserts „rechtmäßige
  Inhaber der Fahrkarte(n)". **verified-primary**

---

## 7. Open questions (explicit)

1. **Payee = NGO.** The form has a free „Kontoinhaber" field, so an IBAN of a third party can be entered. But the
   applicant signs as ticket holder, and DB pays „auf das von Ihnen im Antrag angegebene Konto". Does DB accept a
   non-holder's IBAN, or require an assignment (Abtretung)? Does DB's tariff exclude assignment? Nothing found in the
   BB 2026. **unknown**, and critical for the product.
2. **BahnCard 100 used on RE/RB/S** (within the Streckenentfernungszeiger): does DB pay 10 € under C.3.10.1, or push
   it to the D-Ticket tariff under C.3.10.3? **unknown**. Test with a real claim.
3. **Monatskarte im Abo (Streckenzeitkarte), cap basis:** 25 % of the instalments paid, or of the annual price? The
   window is one year or one month? **unknown**
4. **Pooling arithmetic for Zeitkarten:** do sums above 60 min give floor(sum/60) cases, and does the remainder carry
   over? **unknown**
5. **City-Ticket surcharge** (Sparpreis +City): part of the basis? **unknown**. The conservative model excludes it.
6. **Group and Familienticket:** is the 4 € minimum and the basis per ticket or per affected person, and is a partial
   group delay handled? **unknown**
7. **10/20-Fahrten-Ticket:** basis per single trip (bundle/10)? **unknown**
8. **Fahrradkarte:** is the 25/50 % also paid on the bicycle ticket price, or only a refund if carriage was
   impossible? **unknown**
9. **Übergang 1. Klasse:** included in the Flexpreis basis, or treated separately? **unknown**
10. **Rounding change 11/2026:** the previous wording is not in hand. The current text is „kaufmännisch auf die zweite
    Nachkommastelle". Is the 4 € comparison done on the rounded amount? **inferred** yes.
11. **International third-party desks** (ÖBB, SNCF, European Sleeper, GoVolta, Snälltåget): exact deadlines and
    minimums not fetched. **unknown**
12. **Art. 12(3)–(5) VO** (75 % extra when a ticket vendor sold separate tickets without informing): verify the verbatim
    text on EUR-Lex before modelling.
13. **Payment with Wertgutschein** is counted in the basis; this is inferred from the wording. DB practice is
    **unknown**.
14. **Employer-paid BahnCard 100 / Zeitkarte:** who is entitled to the compensation (holder vs. payer)? **unknown**.
    Tariff reading suggests the holder.
15. **Deadline in DB's online tool:** is the button cut off at 1 year after validity (FAQ) or 12 months after the
    incident? Both are practically equal for single tickets. For Zeitkarten the tariff ties the deadline to the end of
    validity. **inferred**

## 8. Minimal model proposal (for rules.rs, informative)

```
single_ticket:  amount = round_half_up(basis * (0.25 if 60<=d<120 else 0.50 if d>=120 else 0), 2)
                basis  = price_paid(direction) - aktionsgutschein_share      # half the total if no split is shown
                pay if amount >= 4.00 (DB)   |  amount > 4.00 (FlixTrain, Interrail)
                deadline = validity_end + 1 year (DB)  |  journey + 3 months (FlixTrain)  |  pass_end + 3 months (Interrail)
bahncard100:    per case d>=60: 10 € (2nd) / 15 € (1st); no pooling; cap 0.25*bc_price_paid over validity
zeitkarte_fv:   pool delays >=20 min; per 60 min: 5 € / 7.50 €; cap 0.25*price_paid; week/month: submit after expiry
semesterticket: 1.30 €/case only if >=3 cases/month; <=4 €/month; submit after the semester
praemie:        points (25/50 %), no money -> not claimable for the NGO
reservation:    full refund of the reservation fee if unusable; no threshold
```

