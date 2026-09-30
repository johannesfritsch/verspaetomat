> Recherche zu Issue #66 (30. September 2026), Grundlage für docs/49. Pfade `scratchpad/…` bezeichnen lokal heruntergeladene Quelltexte, die nicht im Repo liegen; die URLs stehen jeweils dabei.

# Research D — Cross-cutting Fahrgastrechte rules (any ticket), state 30 Sep 2026

Scope: rules that apply regardless of ticket type, for an app that relays EU-standard-form claims by
e-mail with an NGO named as Kontoinhaber. Read against docs/02, 03, 04 and docs/49.

Confidence tags:
- **verified-primary**: I read the legal text / tariff / operator's own page myself (quote below).
- **secondary**: authority or consumer body page, operator FAQ paraphrase, news, forum.
- **inferred**: my reasoning from primary texts; no source says it in these words.
- **unknown**: no source found; needs a test claim or legal opinion.

Source abbreviations (local copies in `scratchpad/` and `scratchpad/d/`):

| Abbr. | Document | Where |
|---|---|---|
| EU | VO (EU) 2021/782 (Art. 3, 18, 19, 20, 28; Anhang I = CIV Art. 32, 60) | buzer.de/…_Fahrgastrechte-VO.htm, gesetze.legal (a18/a19.html) |
| CIV | Anhang I VO 2021/782 | https://www.buzer.de/Anhang_I_Fahrgastrechte-VO.htm |
| FORM | Durchführungs-VO (EU) 2024/949, Anhang (EU standard form) | https://eur-lex.europa.eu/legal-content/DE/TXT/HTML/?uri=CELEX:32024R0949 (`d/reg949.txt`) |
| EVO | Eisenbahn-Verkehrsordnung 2023 | gesetze-im-internet.de/evo_2023 (`evo.html`) |
| BB | DB Beförderungsbedingungen, Stand 24.09.2026 | bahn.de/agb (`bb.txt`) |
| DT-A / DT-C / DT-D / DTX | Deutschlandtarif Teil A (14.06.2026), C (14.12.2025), D (14.06.2026), D-Ticket (15.06.2026) | deutschlandtarifverbund.de/tarifbedingungen |
| FGF | DB Fahrgastrechte-Formular ME/08/25 | cms.static-bahn.de/…/Fahrgastrechte-Formular_deutsch-feb25-2.pdf |
| DB-RR | bahn.de „Ihre Rechte als Fahrgast im Eisenbahnverkehr" | https://www.bahn.de/service/informationen-buchung/fahrgastrechte/rechtliche-regelungen |
| DB-FAQ | bahn.de FAQ pages (URL given per rule) | bahn.de/faq/… |
| EBA | Eisenbahn-Bundesamt FAQ Fahrgastrechte Bahn | https://www.eba.bund.de/DE/Themen/Fahrgastrechte/Bahn/FAQ/fahrgastrechte_bahn_faq_node.html |
| SC-LIST | „Übersicht teilnehmender Eisenbahnunternehmen im Servicecenter Fahrgastrechte" (PDF title „01052025_…", created 14.05.2025) | https://cms.static-bahn.de/wmedia/redaktion/aushaenge/fahrgastrechte/FGR-Servicecenter-Teilnehmende-Eisenbahnen.pdf |
| RefE-2026 | BMV Referentenentwurf „Zehntes Gesetz zur Änderung eisenbahnrechtlicher Vorschriften", Bearbeitungsstand 07.08.2026 | https://table.media/assets/berlin/26_08_12_eisenbahn.pdf (`d/tm.txt`) |
| COM-233 | COM(2026) 233 final, 13.5.2026, amending 2021/782 (single tickets) | https://transport.ec.europa.eu/document/download/fc019827-59c9-400f-a530-4d7d21957a7d_en?filename=COM_2026_233_Proposal_on_the_protection_of_passengers_with_single_tickets.pdf (`d/com233.txt`) |

---

## 1. Deadlines

### 1.1 Three different periods exist; only one of them bars a compensation claim

| Period | Applies to | Rule | Confidence |
|---|---|---|---|
| **3 months after the incident** | *Beschwerden* (complaints about rights not being respected) under Art. 28 | EU Art. 28(2): „Eine solche Beschwerde muss innerhalb von drei Monaten nach dem Vorfall, auf den sich die Beschwerde bezieht, eingereicht werden." | verified-primary |
| **1 year after the end of the ticket's validity** | *Ansprüche* (refund, expenses, compensation) — Verjährung | CIV Art. 60(2): „Andere Ansprüche aus dem Beförderungsvertrag verjähren in einem Jahr." Art. 60(3)(c): begins „in allen anderen die Beförderung von Reisenden betreffenden Fällen mit dem Tag des Ablaufes der Geltungsdauer des Beförderungsausweises." BB A.9.5: „Ansprüche nach den Nummern 9.1 bis 9.3 verjähren innerhalb eines Jahres nach Ablauf der Geltungsdauer der Fahrkarte." DT-A 8.2.8: „Ansprüche nach den Nummern 8.2.1 und 8.2.6 verjähren innerhalb eines Jahres nach Ablauf der Geltungsdauer der Fahrkarte oder Fahrberechtigung." | verified-primary |
| General BGB (§ 195: 3 years) | not applicable | CIV Art. 60 is lex specialis via Art. 17 VO 2021/782 („die Haftung … ist in Anhang I Titel IV Kapitel II geregelt"); only Hemmung/Unterbrechung falls back to national law: CIV Art. 60(4) „Im Übrigen gilt für die Hemmung und die Unterbrechung der Verjährung Landesrecht." | verified-primary (text) / inferred (that BGB § 195 is displaced) |

**What the Eisenbahn-Bundesamt says (national enforcement body):**
- Anträge: „Wenn Sie einen Anspruch auf Verspätungsentschädigungs-/Erstattungszahlung geltend machen möchten, müssen Sie spätestens innerhalb eines Jahres nach dem Vorfall einen Antrag stellen." — EBA FAQ 04_fristen_faq02 (https://www.eba.bund.de/SharedDocs/FAQs/DE/Fahrgastrechte/Bahn/04_fristen_faq02.html). **secondary (authority)**
- Beschwerden: „können Sie binnen 3 Monaten nach dem Vorfall beim Eisenbahnunternehmen oder Bahnhofsbetreiber … Ihre Beschwerde einreichen." — EBA 04_fristen_faq01. **secondary (authority)**

**What DB says (inconsistent across its own pages):**
- DB-RR (bahn.de/…/rechtliche-regelungen): „Die Verordnung (EU) 2021/782 sieht vor, dass Beschwerden innerhalb von 3 Monaten nach dem Vorfall eingereicht werden müssen. Wir als DB werden hier aber bis auf Weiteres die fahrgastrechtlichen Beschwerden auch nach Ablauf der 3-Monats-Frist annehmen und bearbeiten. Wir orientieren uns dabei an dem bisher bekannten 12-Monatszeitraum. Wir bitten Sie dennoch, Ihren Fahrgastrechteantrag möglichst innerhalb der 3-Monats-Frist einzureichen." **verified-primary (DB's own page)**
- DB-FAQ Frist (https://www.bahn.de/faq/innerhalb-welcher-frist-kann-ich-meine-fahrgastrechtsansprueche-geltend-machen): „Die Verordnung (EU) 2021/782 sieht vor, dass Beschwerden innerhalb von 12 Monaten nach dem Vorfall eingereicht werden müssen. … Bitte beachten Sie, dass einige internationale Eisenbahnverkehrsunternehmen abweichende Fristen anwenden (z.B. 3 Monate)." **verified-primary** (note: the „12 Monate" attribution to the VO is factually wrong — it is Art. 28's 3 months for complaints, CIV's 1 year for claims).
- DB-FAQ „Warum wird der Button … nicht angezeigt?" (faq.txt): „Die Antragsfrist wurde überschritten. Sie können Ansprüche nur bis spätestens ein Jahr nach Ablauf der Gültigkeitsdauer der Fah[rkarte] …" **verified-primary**
- VIAS (per search snippet of its page): „innerhalb eines Jahres nach Ablauf der Gültigkeit des Fahrausweises". **secondary**

**Conclusion (inferred, high confidence):** DB's „3-Monats-Frist" is Art. 28 complaint law misapplied to claims; the binding contract terms (BB, DT-A) and the EBA give one year. The binding hard limit is *one year after the ticket's validity ends*. The safe operational limit is **12 months after the ride** (EBA wording; always ≤ the legal limit because a ride happens inside validity). Recommended app rule: target submission within 3 months (no argument possible with anyone, including foreign operators), hard stop at ride date + 12 months.

Verjährung is an Einrede (the railway must invoke it); a late claim is not void, only refusable. **inferred** (BGB § 214 via CIV Art. 60(4)).

### 1.2 „Ablauf der Geltungsdauer" for the open-ended D-Ticket Abo

- DTX 1.3: „Das Abonnement wird für unbestimmte Zeit abgeschlossen und kann monatlich gekündigt werden. … Das Deutschland-Ticket gilt im Falle einer Kündigung bis Betriebsschluss nach dem Ende des letzten Tages dieses Kalendermonats, längstens jedoch bis 3.00 Uhr des Folgetags." DTX 1.2: „Ein als Papierticket ausgegebenes Deutschland-Ticket gilt für maximal einen Kalendermonat." **verified-primary**
- No source defines the Verjährung start for an open-ended Abo. Two readings: (a) the end of the calendar month of the ride (each monthly payment = one period of validity); (b) the end of the Abo. **unknown**
- Recommendation: use reading (a) *and* the 12-months-after-ride rule; the latter is always earlier, so the question never decides a real case for us. **inferred**

---

## 2. How the delay is measured

| # | Rule | Source / quote | Confidence |
|---|---|---|---|
| 2.1 | Delay = planned vs actual arrival **at the destination station of the passenger**, per published timetable. | EU Art. 3 Nr. 17: „„Verspätung" die Zeitdifferenz zwischen der planmäßigen Ankunftszeit des Fahrgasts gemäß dem veröffentlichten Fahrplan und dem Zeitpunkt seiner tatsächlichen oder erwarteten Ankunft am Zielbahnhof". Art. 19(1): „zwischen dem auf der Fahrkarte oder Durchgangsfahrkarte angegebenen Abfahrts- und Zielort". | verified-primary |
| 2.2 | For tickets without a destination (D-Ticket, Zeitkarten network-wide) the „Ziel" is the destination of the passenger's journey. | DB D-Ticket FAQ: „Erreichen Sie Ihr Ziel im Nahverkehr aufgrund einer Verspätung oder eines Zugausfalls mit mindestens 60 Minuten Verzögerung, erhalten Sie 1,50 Euro Entschädigung pro Fall." (https://www.bahn.de/faq/deutschlandticket-verspaetung-erstattung) | secondary (DB FAQ) + inferred |
| 2.3 | Missed connections count if the scheduled transfer time was respected; DB uses bahn.de's transfer times. | DT-A 8.1: „bei Verbindungen mit Umstiegen unter Einhaltung der fahrplanmäßigen Übergangszeiten". BB 9.1.4: „Die Übergangszeiten für planmäßige Umstiege (Umsteigezeiten) orientieren sich an der elektronischen Fahrplanauskunft unter www.bahn.de." | verified-primary |
| 2.4 | Separate tickets = separate contracts; no through rights. D-Ticket + Fernverkehr ticket = two contracts. | DB D-Ticket FAQ: „Bei einer Kombination aus Deutschland-Ticket und Fernverkehrsticket gelten 2 getrennte Beförderungsverträge … Entschädigungsansprüche werden für jedes Ticket einzeln geprüft". EBA 02_verspaetungen_faq03: „Sollten mehrere Beförderungsverträge die Grundlage Ihrer Reise sein, wäre jeder Vertrag hinsichtlich einer möglichen Verspätungsentschädigung für sich gesondert zu betrachten." | verified-primary / secondary |
| 2.5 | Bus, tram, U-Bahn never count, even inside the ticket; a bus delay causing a missed train gives nothing. | FGF: „Der Entschädigungsanspruch gilt ausschließlich für Eisenbahnverkehrsleistungen (von der S-Bahn bis zum ICE). U-Bahnen, Straßenbahnen oder Busse fallen nicht hierunter." DB D-Ticket FAQ: „Die Verspätung eines Busses mit Anschlussverlust auf einen Zug gibt keinen Anspruch auf Fahrgastrechte im Eisenbahnverkehr. Fahrgastrechte gelten nicht verkehrsträgerübergreifend." DT-A 8.1: „gelten die Fahrgastrechte … nur für die Schienenstrecke". EBA 01_geltunsgbereich_faq02: „Die Fahrgastrechte gelten nicht für Fahrten in der U-Bahn oder Straßenbahn." | verified-primary |
| 2.6 | S-Bahn counts (it is rail). | FGF „(von der S-Bahn bis zum ICE)". | verified-primary |
| 2.7 | **SEV bus replacing a train counts as the train** (contractual carrier stays the railway). | BB A.1.3.6: „Bei der Nutzung von Schienenersatzverkehren, welche bei Bauarbeiten oder Störungen des Betriebsablaufes gemäß Bekanntmachung vorübergehend mit anderen Verkehrsmitteln (z.B. Bussen oder Taxen) durchgeführt werden, bleibt vertraglicher Beförderer das jeweilige EVU. Der Betreiber der Ersatzverkehre ist lediglich ausführender Beförderer". bwegt (Land Baden-Württemberg): „Wenn Busse Züge ersetzen (bei kurzfristigen Störungen „Busnotverkehr", bei geplanten Maßnahmen „Schienenersatzverkehr"), werden diese Busse hinsichtlich der Fahrgastrechte wie der ersetzte Zugverkehr behandelt." (https://www.bwegt.de/reiseinformationen/fahrgastrechte-und-mobilitaetsgarantie) | verified-primary (BB) / secondary (bwegt) |
| 2.7a | … but it is **legally contested** today; the federal ministry is legislating a clarification. RefE-2026 Art. (AEG) Nr. 7: new § 10 Abs. 3 AEG „Für Beförderungen im Schienenersatzverkehr gelten die Rechte der Fahrgäste im Eisenbahnverkehr." Begründung: „Gesetzliche Klarstellung. Auf Beförderungen von Fahrgästen im Schienenersatzverkehr sind, auch wenn diese in Bussen auf der Straße durchgeführt werden, die Rechte der Fahrgäste im Eisenbahnverkehr anwendbar. … In der Vergangenheit hat es Abgrenzungsprobleme gegeben. Eine klare gesetzliche Regelung fehlt bislang." | verified-primary (draft, not law) |
| 2.8 | No proof of delay needed; railways use their own recorded data. | DB D-Ticket FAQ: „Sie müssen keine Verspätungsbescheinigung vorlegen … Alle Zugverspätungen und Ausfälle werden elektronisch im System erfasst und ausgewertet." EBA 02_verspaetungen_faq07: „da die Daten über die Abfahrts- und Ankunftszeiten der Eisenbahnen in der Regel gespeichert werden und bei der Bearbeitung der Anträge auf diese Daten zurückgegriffen werden kann." FGF: data used „für die Plausibilitätsprüfung". BB 9.3.4: confirmation in a Reisezentrum „bis längstens ein Jahr nach dem Verspätungsereignis". | verified-primary |
| 2.9 | Rerouting that brings the arrival under 60 min kills the compensation. | EU Art. 19(9): „…oder wenn bei ihrer Ankunft am Zielort eine Verspätung aufgrund der Fortsetzung der Reise mit einem anderen Verkehrsdienst oder mit geänderter Streckenführung weniger als 60 Minuten beträgt." → measure the actual arrival, whatever train it was. | verified-primary |
| 2.10 | Informed before purchase → no compensation. | EU Art. 19(9): „wenn sie bereits vor dem Fahrkartenkauf über eine Verspätung informiert wurden". For Abo/Zeitkarten the purchase precedes any given delay, so practically only relevant for single tickets bought at the station/app after a delay was shown. | verified-primary (rule) / inferred (Zeitkarte irrelevance) |
| 2.11 | Refund (Art. 18(1)(a)) and compensation are alternatives. | EU Art. 19(1): „…eine Verspätung erleidet, für die keine Fahrpreiserstattung nach Artikel 18 erfolgt ist." FORM footnote (**): „Sie [können] entweder eine Entschädigung oder eine Erstattung der Fahrkarte(n) bei einem Eisenbahnunternehmen beantragen …, jedoch nicht beides für dieselbe Fahrt." | verified-primary |
| 2.12 | „Reise nicht angetreten" / abandoning = refund route, not compensation. FGF lists „Reise nicht angetreten (Zugausfall oder erwartete Verspätung am Ziel von mind. 60 Minuten)" and „Reise unterwegs abgebrochen und zurück zum Startbahnhof" as incident types; they lead to Art. 18(1)(a) refund (BB 9.1.3, DT-A 8.2.2). Someone who never arrives has no arrival delay. | verified-primary (texts) / inferred (consequence, as docs/02) |
| 2.13 | Cancellations: for single tickets a cancellation counts through the resulting arrival delay. For Zeitkarten DT-C 8.1 names „wiederholten Zugausfällen, Verspätungen oder Anschlussversäumnissen ab 60 Minuten … je Einzelfall" — reading „ab 60 Minuten" as qualifying all three, a cancellation counts when it produces ≥ 60 min at the destination. Whether DB counts a cancellation *as* 60 min regardless of the resulting arrival is not stated anywhere. | verified-primary (text) / unknown (flat-60 treatment) |
| 2.14 | Self-chosen later train (Art. 18(1)(c), BB 9.1.1 (ii)): no source says how the delay is then measured. docs/02's `min(actual, earliest possible)` is a defensible under-claim. | inferred |
| 2.15 | Delays outside the EU don't count. | EU Art. 19(4). | verified-primary |

---

## 3. Force majeure (Art. 19(10))

- **Text** (EU Art. 19(10)): no compensation if the railway „nachweisen kann, dass Verspätungen, verpasste Anschlüsse oder Zugausfälle als direkte Folge von oder in untrennbarem Zusammenhang mit folgenden Umständen aufgetreten sind: a) außerhalb des Eisenbahnbetriebs liegende, außergewöhnliche Umstände wie extreme Witterungsbedingungen, große Naturkatastrophen oder schwere Krisen im Bereich der öffentlichen Gesundheit, die das Eisenbahnunternehmen trotz Anwendung der nach Lage des Falles gebotenen Sorgfalt nicht vermeiden und deren Folgen es nicht abwenden konnte, b) Verschulden des Fahrgasts oder c) Verhalten eines Dritten wie Betreten der Gleise, Kabeldiebstahl, Notfälle im Zug, Strafverfolgungsmaßnahmen, Sabotage oder Terrorismus …". **verified-primary**
- **Carve-out:** „Streiks des Personals des Eisenbahnunternehmens, Handlungen oder Unterlassungen eines anderen Unternehmens, das dieselbe Eisenbahninfrastruktur nutzt, und Handlungen oder Unterlassungen der Infrastrukturbetreiber und Bahnhofsbetreiber fallen nicht unter die Ausnahme nach Unterabsatz 1 Buchstabe c." **verified-primary** → infrastructure faults (DB InfraGO: Stellwerk, Weiche, Oberleitung) and other operators' trains blocking the line are *not* exempt.
- **Burden of proof on the railway**: „wenn sie nachweisen können" (EU); DT-A 8.2.6 „nachweislich". **verified-primary**
- **Tariff copies**: DT-A 8.2.6 reproduces the list verbatim; BB 9.2.1 only reserves it: „Die Geltendmachung von Ausschlussgründen nach Art. 19 Abs. 10 VO (EU) 2021/782 bleibt vorbehalten." **verified-primary**
- **DB's own statement** (https://www.bahn.de/bahnbusiness/faq/gibt-es-auch-faelle-in-denen-ich-keine-verspaetungsentschaedigung-erhalte): „Ein gewöhnliches Unwetter fällt nicht unter diese Kategorie. Daher werden Sie in der Regel auch in Zukunft in vollem Umfang bei Verspätungen eine Entschädigung im Rahmen der Fahrgastrechte erhalten. Zum anderen sind dies Umstände, die durch das Verhalten eines Dritten hervorgerufen werden. Darunter fallen z.B. Betreten der Gleise, Kabeldiebstahl, Polizeieinsätze oder Bombenentschärfungen. In solchen Fällen behalten sich das Eisenbahnverkehrsunternehmen vor, gemäß der Verordnung keine Entschädigung bei Verspätungen zu zahlen. Streik zählt explizit nicht zu den in der Verordnung genannten Fällen. Im Streikfall erhalten Sie daher wie bisher im Rahmen der Fahrgastrechte Ihre vollumfängliche Entschädigung." **verified-primary**
- Verbraucherzentrale (Stand 24.08.2026): „normale jahreszeitlich bedingte Witterungsbedingungen, wie z. B. Herbststürme" do not qualify. **secondary**
- **Practice**: DB decides case by case against its incident records; the rejection letter names the cause. Reports (reise-preise.de, ICE-Treff forum) say „Personenunfall"/„Notarzteinsatz am Gleis" cases are typically refused, and that re-contesting refusals by phone often succeeds (one user: 10 of 30 refused, all 10 later paid). **secondary (anecdotal)**. No DB statistics on the share of refusals under Art. 19(10) found. **unknown**
- **History**: EuGH 26.09.2013, C-509/11 (ÖBB-Personenverkehr): under the old VO 1371/2007 a railway could not exclude compensation for force majeure; the CIV exemptions did not apply to fare compensation (LTO: https://www.lto.de/recht/nachrichten/n/eugh-urteil-c-509-11-fahrpreiserstattung-verspaetung-hoehere-gewalt). VO 2021/782 Art. 19(10) reversed this from 7 June 2023. **secondary**
- **Hotel after force majeure**: can be capped at three nights (EU Art. 20(2)(b); BB 9.1.6; DT-A 8.2.5). **verified-primary**
- **For the app**: force majeure is unknowable at claim time; it is a refusal reason we read from the reply. Never under-claim because of it (burden is on the railway). **inferred**

---

## 4. Minimum payout, rounding, per ticket vs per claim

| Rule | Quote | Confidence |
|---|---|---|
| EU cap on the minimum: **per ticket**. | Art. 19(8): „Die Eisenbahnunternehmen dürfen Mindestbeträge festlegen, unterhalb deren keine Entschädigungszahlungen vorgenommen werden. Dieser Mindestbetrag darf höchstens 4 EUR pro Fahrkarte betragen." Also: no deduction of transaction costs. | verified-primary |
| DB single tickets: below 4 € not paid; rounding commercial to the cent. | BB 9.2.1: „Der Betrag wird kaufmännisch auf die zweite Nachkommastelle gerundet. … Entschädigungsbeträge unter 4 € werden nicht ausgezahlt." | verified-primary |
| Deutschlandtarif single tickets: rounded **up** to 5 cent; below 4 € not paid. | DT-A 8.2.6: „Der Betrag wird auf einen durch 5 Cent teilbaren Betrag aufgerundet. … Entschädigungsbeträge unter 4 € werden nicht ausgezahlt." | verified-primary |
| Deutschlandtarif Zeitkarten (incl. D-Ticket, Länder-Tickets): paid if the claim **exceeds** 4 €. | DT-C 8.1: „Eine Zahlung erfolgt jeweils auf Antrag, wenn der Anspruch den Betrag von 4 € (Bagatellgrenze) überschreitet." | verified-primary |
| DB's public page for Nahverkehr Zeitkarten: „unter 4 Euro nicht ausgezahlt". | DB-RR: „Wenn Sie eine Zeitfahrkarte des Nahverkehrs besitzen, beachten Sie bitte, dass Entschädigungsbeträge unter 4 Euro nicht ausgezahlt werden." | verified-primary |
| One claim per ticket (per direction for returns). | BB 9.2.1 / DT-A 8.2.6: „Der Entschädigungsanspruch kann pro Fahrkarte – bei Rückfahrkarten pro Fahrtrichtung – jeweils nur einmal geltend gemacht werden." | verified-primary |
| Whether the 4 € threshold applies per bundle or per operator inside a Servicecenter bundle. | not stated anywhere. EU says „pro Fahrkarte" → a D-Ticket bundle is one ticket, so per bundle is the text's natural reading. | unknown (practice) / inferred (text) |
| Rounding of the 25 % cap for odd prices (Jobticket 59,85 € → 14,9625 €). | not stated. | unknown |

**Several tickets in one EU form:** FORM 3.2.7 „Fahrkartennummer(n)/Buchungsnummer" and 3.2.8 „Fahrkartenpreis(e)" are plural, but section 3 describes **one** journey (one date, one start, one destination, one planned/actual arrival). So: several tickets for one journey fit; several journeys do not, except via the Zeitkarte checkbox plus the section-6 free text. **verified-primary (form) / inferred (bundling)**. Whether DB's EU-form desk accepts a multi-journey list in section 6 is **unknown** (test claim 2 in docs/03).

---

## 5. EU standard form (Durchführungs-VO (EU) 2024/949) — exact fields

Adopted 27.03.2024, OJ 2.4.2024, applies from **2 July 2024**. Art. 1: „Das einheitliche Formular kann als physisches Dokument oder auf elektronischem Wege eingereicht werden." Railways may not refuse a claim for not using it (EU Art. 19(6)); if imprecise they must ask and help. **verified-primary**

Official PDF (DE): https://europa.eu/youreurope/citizens/files/forms/reimbursement-compensation-railway/reimbursement-form_de.pdf

| Section | Field (verbatim) | Relevance |
|---|---|---|
| 1 | ☐ Verspätung ☐ Ausfall ☐ Verpasster Anschluss aufgrund einer Verspätung oder eines Ausfalls | multi-tick |
| 2 | Vorheriger Antrag … für dieselbe Bahnfahrt: 2.1 Datum, 2.2 an welches EVU, 2.3 Kanal/Referenznummer | must be answered honestly (e.g. if customer also used DB Navigator) |
| 3.1 | Name des Eisenbahnunternehmens | one field (2.2 allows several) |
| 3.2.1–3.2.6 | Abreisedatum; Abreisebahnhof; Zielbahnhof; Abfahrtszeit laut Fahrplan; Ankunftszeit am Zielort laut Fahrplan; Zugnummer/Zugkategorie | one journey |
| **3.2.7** | **Fahrkartennummer(n)/Buchungsnummer** | the only ticket-identity field — this is where the D-Ticket / Abo number goes |
| **3.2.8** | **Fahrkartenpreis(e)** | price paid |
| 3.3.1–3.3.5 | Tatsächliches Ankunftsdatum; tatsächliche Abfahrtszeit; tatsächliche Ankunftszeit am Zielort; Zugnummer/Zugkategorie; Verpasster Anschluss in (Bahnhof) | |
| 4 | ☐ Erstattung der Fahrkarte(n) … ☐ Entschädigung: ☐ 60 bis 119 Minuten ☐ mindestens 120 Minuten ☐ **„für wiederholte Verspätungen oder Ausfälle, die Fahrgäste betreffen, die Inhaber einer Zeitfahrkarte sind (****)"** ☐ Erstattung der Kosten … (andere EVU, Linienbus, Reisebus, Taxi, Hotel, Mahlzeiten, Erfrischungen) | the Zeitkarte box is the only ticket-type signal on the form; footnote (****): criteria are „in den Entschädigungsbedingungen des Eisenbahnunternehmens gemäß Artikel 19 Absatz 2" |
| 5.1–5.3 | Vorname, Familienname; Straße, Nr., Land, PLZ, Ort; **„E-Mail-Adresse (ggf. bitte die zum Zeitpunkt der Buchung verwendete Adresse angeben)"**; Telefon | relay address ≠ booking address for DB-account tickets (note for Einzelfahrkarten) |
| 5.4 | ☐ Geld ☐ Gutscheine … | |
| 5.5.1–5.5.4 | IBAN; SWIFT/BIC; Andere Zahlungsmethoden (PayPal, Apple Pay); **„Name des Kontoinhabers (Vorname, Nachname)"** | the NGO field; note it asks for *Vorname, Nachname* — an organisation name does not fit the template literally |
| 6 | free text, „Maximal 2 500 Zeichen", incl. extra costs | class, ticket type, incident list go here |
| end | „BITTE FÜGEN SIE DIE ENTSPRECHENDEN BELEGE BEI (z. B. Fahrkarte(n) oder Reservierung(en) …; gegebenenfalls Bestätigung der Verspätung/des Ausfalls)"; GDPR onward-transfer consent **JA ☐ NEIN ☐**; truth declaration „…für alle Fahrgäste der Wahrheit entsprechen"; Datum; Ort; **„Name des Fahrgastes oder seines Vertreters/seiner Vertreterin"** | no signature line |

Not on the form: **no class field, no ticket-type list (no D-Ticket / BahnCard 100 / Zeitkarte-number field), no booking-reference field separate from 3.2.7**. **verified-primary**

Form preamble: „Nach nationalem Recht gelten eventuell Fristen für die Einreichung von Anträgen." **verified-primary**

DB channel for the EU form (https://www.bahn.de/faq/eu-formular): „per E-Mail: EUAntragFGR@deutschebahn.com | Bitte in der Betreffzeile (wenn möglich) folgendes angeben: Fahrgastrechte: EU-Antragsformular"; attachments „.pdf/.pdf.A, .jpg/.jpeg, .tif, .doc/.docx, .xls/.xlsx, .txt, .gif, .png"; „Wichtig: Eine Auszahlung auf ein anderes Konto (PayPal oder Apple Pay usw.) ist nicht möglich." German form → German reply. **verified-primary**

Attachments: compensation claims may use copies, refunds need originals. BB 9.3.2: „Für Erstattungs- und Aufwendungsersatzansprüche sind die begründenden Unterlagen (Fahrkarten, Belege) immer im Original beizufügen. Für Entschädigungsansprüche können grundsätzlich Kopien der Belege beigefügt werden." **verified-primary** → taxi/hotel receipts by e-mail may be asked for in original (BB 9.4.4 does so for online claims up to 120 €). **inferred**

BB 9.3.2 also says claims are „mit einem vom Reisenden ausgefüllten Fahrgastrechte-Formular einzureichen" — relevant to the messenger model (the passenger must adopt the filled form as theirs). **verified-primary**

---

## 6. Payee, third parties, assignment

| # | Point | Source / quote | Confidence |
|---|---|---|---|
| 6.1 | The claim belongs to the passenger who was delayed. | BB 9.2.1 / DT-A 8.2.6: „Der von einer Verspätung selbst betroffene Reisende hat Anspruch …" | verified-primary |
| 6.2 | Both forms have a separate account-holder field, so a payee ≠ passenger is foreseen by the form. | FORM 5.5.4 „Name des Kontoinhabers"; FGF „Kontoinhaber (Name, Vorname)*". | verified-primary |
| 6.3 | Legally, naming someone else's account is a **payment instruction**, not an assignment: payment to a third party with the creditor's consent discharges the debt. | BGB § 362(2): „Wird an einen Dritten zum Zwecke der Erfüllung geleistet, so findet die Vorschrift des § 185 Anwendung." § 185(1): „…ist wirksam, wenn sie mit Einwilligung des Berechtigten erfolgt." | verified-primary (law) / inferred (application) |
| 6.4 | Therefore DB needs no proof of assignment for the NGO model; the passenger remains claimant and signatory. An *assignment* (Abtretung, § 398 BGB) would make the NGO the creditor and — forum report — DB then wants proof: „Das muß dann aber der Bahn nachgewiesen werden" (ICE-Treff, https://www.ice-treff.de/index.php?mode=thread&id=262142). | inferred / secondary (forum) |
| 6.5 | Whether the Servicecenter pays to an IBAN whose holder name is an organisation different from the claimant, without asking: no public statement found. DB says only „auf das im Antrag angegebene Konto". | DB-FAQ (in-welcher-form-erhalte-ich-meine-entschaedigung): „Die Entschädigung erhalten Sie als Banküberweisung auf das von Ihnen im Antrag angegebene Konto." | unknown (test claim 1) |
| 6.6 | RDG: collecting **assigned** claims as a business is Inkasso and needs registration; acting for others with legal assessment is a Rechtsdienstleistung. A relay where the passenger claims in their own name and only the payee is the NGO avoids § 2(2); the pre-filling (rule application) is the part a legal opinion must clear under § 2(1) (or § 6 unentgeltlich, which requires supervision by a qualified person when done outside close personal relations). | RDG § 2(1): „Rechtsdienstleistung ist jede Tätigkeit in konkreten fremden Angelegenheiten, sobald sie eine rechtliche Prüfung des Einzelfalls erfordert." § 2(2): „…die Einziehung fremder oder zum Zweck der Einziehung auf fremde Rechnung abgetretener Forderungen, wenn die Forderungseinziehung als eigenständiges Geschäft betrieben wird … (Inkassodienstleistung)." § 6(2): unentgeltliche RDL outside close relations only „durch eine Person, der die entgeltliche Erbringung dieser Rechtsdienstleistung erlaubt ist, durch eine Person mit Befähigung zum Richteramt oder unter Anleitung einer solchen Person". | verified-primary (law) / inferred (application) |
| 6.7 | Existing services: **refundrebel** (B2B; recovers compensation for employers „ohne das Zutun der Reisenden", 35 % success fee + VAT for consumers per search snippet; payout to the company; legal mechanism not published). **hellaw.de/bahn**: free document generator, „ein rechtssicheres Schreiben" the passenger sends; payment goes to the passenger — closest analogue to Verspätomat's messenger model. DB Navigator: own claims in-app, only for tickets in the DB account (BB 9.4). | https://www.refundrebel.com/ , https://hellaw.de/bahn | secondary |
| 6.8 | DB business customers: admins may file for travellers; DB page does not say who is paid. | https://www.bahn.de/bahnbusiness/faq/geschaeftsreisende-fahrgastrechte | secondary |

---

## 7. Operators

### 7.1 Servicecenter scheme

- Legal basis: BB 9.3.1: „Die unter www.bahn.de/fahrgastrechte genannten EVU haben sich für die Bearbeitung … auf die Durchführung eines gemeinsamen Beschwerdeverfahrens … verständigt." They are joint controllers under Art. 26 GDPR. **verified-primary**
- Current list (SC-LIST, **dated 01.05.2025**, still the one linked from bahn.de in Sept 2026): agilis; AKN; AVG; Arriva Nederland; Bentheimer Eisenbahn; BOB; cantus; City-Bahn Chemnitz; DB Fernverkehr (ICE, ICE Sprinter, IC, EC, ECE, RJ, RJX, NJ, D); DB Regio (RE, RB, IRE, S, MEX) incl. DB Regio-Netz (Kurhessenbahn, Erzgebirgsbahn, Gäubodenbahn, Oberweißbacher Berg- und Schwarzatalbahn, Südostbayernbahn, Westfrankenbahn) and DB ZugBus Alb-Bodensee; S-Bahn Berlin; S-Bahn Hamburg; Start Unterelbe / Niedersachsen-Mitte / Taunus / Mitteldeutschland; Die Länderbahn (ALX, VBG, VX, TLX, OPB, OPX, TL, EX, RBG, WBA, BLB); Pressnitztalbahn; EVB; Erfurter Bahn; erixx; erixx Holstein; eurobahn; Freiberger Eisenbahn; Arverio Baden-Württemberg; Arverio Bayern; Hanseatische Eisenbahn; HLB Hessenbahn; metronom (ME, ENO); National Express Rail; NEB; nordbahn; NEG Niebüll; ODEG; **Transdev Verkehr GmbH (Zuggattung „VEN", Postfach Moers)**; SAB; SBB GmbH; Süd Thüringen Bahn; SWEG (SWE/HZL); vlexx; WEG. **verified-primary** — docs/04's list matches this PDF entry for entry.
- Joint liability for through tickets among participants (BB A.1.3.4: „…als Gesamtschuldner"). **verified-primary**
- Claims for non-participants sent to the SC are forwarded; direct is faster (DB bahnbusiness FAQ „wozu brauchen wir ein servicecenter fahrgastrechte"). **verified-primary**

### 7.2 Non-participants that need direct claims (verified this round)

| Operator | Channel | Confidence |
|---|---|---|
| NordWestBahn (Transdev) | Transdev Service GmbH, Passage 3-5, 17034 Neubrandenburg; e-mail fahrgastrechte@nordwestbahn.de | secondary (search snippet of nordwestbahn.de/…/fahrgastrechte) |
| Bayerische Regiobahn / Meridian / BOB (Transdev) | online form or PDF; Transdev Service GmbH – BRB, Postfach 10 01 07, 17041 Neubrandenburg; own Kundengarantie from 15 min | secondary |
| RheinRuhrBahn (Transdev) | Kundencenter, Transdev Service GmbH Passage 3-5 Neubrandenburg, online form; **no Servicecenter mention** | verified-primary (page fetched) |
| Mitteldeutsche Regiobahn (Transdev) | online form, Transdev Service GmbH Neubrandenburg; SC only „when delays aren't the responsibility of Transdev"; „Pauschalpreisangebote, z.B. Quer-durchs-Land-Ticket, Deutschland-Ticket oder Länder-Tickets, werden wie Zeitfahrkarten des Nahverkehrs entschädigt." | verified-primary (page fetched, via summariser) |
| VIAS / VIAS Rail | e-mail with own form; one year after validity | secondary (contradictory snippet about SC) |
| MittelrheinBahn / trans regio | own online form or PDF | secondary |
| FlixTrain | help.flixtrain.com form | secondary |

Not checked: Transdev Hannover (S-Bahn Hannover), Regiobahn (S28), Usedomer Bäderbahn, Kahlgrundbahn, Rurtalbahn, RegioShuttle, Saarbahn, HKX, Nightjet/ÖBB. **unknown**

---

## 8. Legislative changes

| Item | Status | Content relevant to us | Confidence |
|---|---|---|---|
| **COM(2026) 233** (13.5.2026) amending VO 2021/782 („single tickets", part of the „Passenger Package") | Commission proposal; not adopted | Full rights for journeys sold as a „single ticket" if minimum connection times are respected; vendors who ignore them pay 75 %; Art. 19(1) thresholds **unchanged** (25 %/50 %) but for single tickets ≥ 12 h compensation only per individual contract (except night trains). Nothing on Zeitkarten, minimum payout, force majeure, deadlines or intermediaries. Quote: „(a) 25 % of the ticket price for a delay of 60 to 119 minutes; (b) 50 % … 120 minutes or more." | verified-primary |
| Multimodal passenger rights, COM(2023) 752 | Council general approach 5.12.2024; EP mandate 9.7.2025; in trilogue (EP legislative train, updated 1.8.2026) | through-journey rights across modes | secondary |
| Enforcement regulation (amends five passenger-rights regulations; common claim forms, complaint handling, NEB powers) | provisional agreement 25.6.2026 (Consilium press release); needs EP plenary + Council; applies from the entry into force of the air-passenger regulation | may change complaint deadlines/forms — text not yet read | secondary |
| **German RefE „Zehntes Gesetz zur Änderung eisenbahnrechtlicher Vorschriften"** (BMV, Stand 07.08.2026) | Referentenentwurf; Verkehrsforum statement 18.08.2026 | new **§ 10 Abs. 3 AEG: „Für Beförderungen im Schienenersatzverkehr gelten die Rechte der Fahrgäste im Eisenbahnverkehr."** | verified-primary (draft) |
| EVO | EVO 2023 (BGBl. 2023 I Nr. 208) unchanged since; no amendment 2024–2026 found | — | secondary (absence) |
| D-Ticket passenger rights | no announced change; DTX 1.6 unchanged (Stand 15.06.2026) | — | verified-primary (current text) / secondary (no plans) |

---

## 9. Other statutory money rights (not compensation)

| Right | Trigger | Money | Excluded / conditions | Source | Confidence |
|---|---|---|---|---|---|
| **Refund on abandoning / not starting** (Art. 18(1)(a)) | expected ≥ 60 min at destination | full fare for unused part, plus used part if the journey „sinnlos geworden ist", plus return ride; within 30 days (Art. 18(5)); cash obligatory, no voucher unless accepted | instead of compensation; Zeitkarten: no per-journey fare → effectively nothing | EU Art. 18; BB 9.1.3; DT-A 8.2.2; EBA 03_zugausfall_faq01 („Machen Sie von dieser Option Gebrauch, treten Sie damit vom Beförderungsvertrag zurück.") | verified-primary |
| **Other train from 20 min** (EVO § 11(1) Nr. 1; BB 9.1.1 for DB) | expected ≥ 20 min at destination | reimbursement of the other ticket (incl. IC/ICE for Nahverkehr tickets), pay first | not reservation-compulsory or special trains (§ 11(3)); **not for erheblich ermäßigte tickets** (EVO § 3(2)) | EVO § 11(1)(2); DT-A 8.2.1 | verified-primary |
| **Taxi / other means, night or last train** (EVO § 11(1) Nr. 2; BB 9.1.5; DT-A 8.2.4) | planned arrival 0–5 h and ≥ 60 min expected, or last connection of the day cancelled and destination not reachable by 24:00 | up to **120 €** | EVO § 11 only for tickets „ausschließlich für den öffentlichen Personennahverkehr"; BB 9.1.5 gives DB tickets the same; railway's own offer has priority, self-help only if the railway could not be contacted „aus vom EVU zu vertretenden Gründen". **Not** removable for erheblich ermäßigte tickets (§ 3(2) only covers Nr. 1). DB D-Ticket FAQ: ICE/IC in this case too, „bis zu einer Höhe von 120 Euro". | EVO § 11; BB 9.1.5; DB D-Ticket FAQ | verified-primary |
| **Hotel** (Art. 20(2)(b); BB 9.1.6; DT-A 8.2.5) | journey cannot reasonably continue the same day | hotel + transfer; self-organised only if railway unreachable; force majeure → max 3 nights; alternative transport up to 120 € | also Nahverkehr | EU Art. 20; BB 9.1.6; DT-A 8.2.5; DB-RR | verified-primary |
| **Meals/refreshments** (Art. 20(2)(a)) | ≥ 60 min | in kind | **not in SPNV**: EVO § 2(1) „Auf die Beförderungen im Schienenpersonennahverkehr sind Artikel 20 Absatz 2 Buchstabe a, Artikel 29 und Artikel 30 Absatz 1 Satz 1 der Verordnung (EU) 2021/782 nicht anzuwenden." | EVO § 2 | verified-primary |
| **Self-organised rerouting after 100 min** (Art. 18(3)) | no rerouting options communicated within 100 min of scheduled departure | „notwendigen, angemessenen und zumutbaren Kosten" for another rail, coach or bus operator; DB: „Die Kosten für eine Nutzung eines Taxis, Flugzeugs oder einer Privatabholung werden in diesem Fall nicht erstattet." | applies in Nahverkehr too (DT-A 8.2.3). Whether it lets D-Ticket holders recover a Fernverkehr ticket is contested: DB D-Ticket FAQ says no Fernverkehr refund except the night/last-train case. | EU Art. 18(3); BB 9.1.2; DT-A 8.2.3; DB-RR | verified-primary (rule) / unknown (D-Ticket + ICE) |
| Unused reservation | seat not provided / not usable | reservation fee back | — | DB-FAQ (faq.txt) | verified-primary |

**Which tickets are „erheblich ermäßigt"** (only effect: no EVO § 11(1) Nr. 1 reimbursement):
- Definition, EVO § 3(3): named as such in the tariff **and** > 50 % saving; „Nicht als erheblich ermäßigtes Beförderungsentgelt gelten Mehrtages-Zeitkarten, insbesondere Wochenkarten, Monatskarten und Jahreskarten." § 3(4): „Das Entgelt für das Deutschlandticket gilt als erheblich ermäßigtes Beförderungsentgelt". **verified-primary**
- Deutschlandticket incl. Job-/Semesterticket (DTX 1.6). **verified-primary**
- Quer-durchs-Land-Ticket, all Länder-Tickets (Bayern, Brandenburg-Berlin, MV, RLP/Saarland, Sachsen/Sachsen-Anhalt/Thüringen, …) and most regional Tageskarten in DT-D Anlage 1 (each entry says „Es handelt sich bei dem Angebot um eine Fahrkarte mit erheblich ermäßigtem Beförderungsentgelt im Sinne von § 3 …"); DT-D 4.1: „in der Regel". DB-RR names „Deutschland-Ticket, Länder-Tickets, Quer-durchs-Land-Ticket". **verified-primary**
- Ordinary Monats-/Jahreskarten are **not** (EVO § 3(3) S. 2). DB Fernverkehr Sparpreise are not in this category (EVO § 11 does not concern them; BB 9.1.1 lifts Zugbindung from 20 min). **verified-primary / inferred**

**Day tickets and compensation** (resolves docs/49 §9 Q4 in part): DT-D 4.1.1: „Für Entschädigungsansprüche … gelten die Regelungen der Nr. 8 der Tarifbedingungen des Deutschlandtarifs (Grundsätze), bzw. der Nr. 8 der Zeitkartenbedingungen entsprechend." DB-RR: „Zeitfahrkarten des Nah- und Fernverkehrs (z.B. Wochen- oder Monatskarten, Länder-Tickets, Quer-durchs-Land-Ticket) werden pauschal jeweils ab einer Verspätung ab 60 Minuten am Zielbahnhof entschädigt. … Zeitfahrkarten des Nahverkehrs: 1,50 Euro (2. Klasse), 2,25 Euro (1. Klasse) … Insgesamt werden maximal 25 Prozent des Zeitfahrkartenwertes entschädigt. Als Zeitkarteninhaber (Ausnahme BahnCard 100) können Sie auch mehrere Verspätungsfälle ab 20 Minuten addieren". MRB says the same. → Länder-Ticket/QdL = Nahverkehrs-Zeitkarte rules, cap 25 % of the day-ticket price (so a 30 € Länder-Ticket caps at 7,50 €). **verified-primary**

**Escalation path**: EVO § 15 — railways must point to Schlichtung in their reply („Das Eisenbahnverkehrsunternehmen hat bei der Beantwortung einer Beschwerde wegen der Nichtbeachtung von Fahrgastrechten auf die Möglichkeit der Schlichtung hinzuweisen"). EBA cannot enforce Nahverkehr Zeitkarten tariff terms: „Die Genehmigung und Überwachung der Tarifbestimmungen / Beförderungsbedingungen im Schienenpersonennahverkehr liegt jedoch nicht beim Eisenbahn-Bundesamt, sondern fällt in die Zuständigkeit der Bundesländer." (EBA 02_verspaetungen_faq02) → D-Ticket disputes go to the Schlichtungsstelle Reise & Verkehr (6.236 new rail cases in 2025, SRUV Jahresbericht 2025), not the EBA. **verified-primary / secondary**

---

## 10. Corrections to docs/02–04

**docs/02-passenger-rights.md**
1. „Deadline | 3 months per delay under EU law; DB accepts up to 12 months as goodwill" → wrong in substance. Art. 28's 3 months apply to *Beschwerden*; claims verjähren one year after the ticket's validity ends (CIV Art. 60, BB A.9.5, DT-A 8.2.8), EBA: „spätestens innerhalb eines Jahres nach dem Vorfall". DB's own page mixes the two. Operational rule: aim for 3 months, hard limit ride + 12 months. (Already flagged in the doc's superseded note; the table row still says 3 months.)
2. „Cancellations | count when the resulting arrival is 60+ min late ("Reise nicht angetreten" option on the form)" → the „Reise nicht angetreten" box on the DB form is the **refund** path (Art. 18), not compensation, and does not exist on the EU form. For Zeitkarten a cancellation counts through its arrival delay (DT-C 8.1 „Zugausfällen … ab 60 Minuten"); no source says a cancellation counts as a flat 60.
3. „Monthly cap 25 % of the ticket price" — fine; add that the same Zeitkarte rules and 25 % cap apply to Länder-Tickets and Quer-durchs-Land (DT-D 4.1.1, DB-RR).
4. Force-majeure paragraph: add that the railway bears the burden of proof („nachweisen können"), that infrastructure-manager faults and other operators' trains are expressly **not** third-party causes, and DB's own line that „ein gewöhnliches Unwetter" does not qualify. „The list is open-ended" is right (the „wie" makes it exemplary).
5. „Exceptions with real money … taxi, higher-class train up to 120 €" — correct; add that the self-help right exists only if the railway offered nothing and could not be contacted, and that meals (Art. 20(2)(a)) are not owed in Nahverkehr (EVO § 2(1)).
6. Legislative outlook: specify COM(2026) 233 of **13 May 2026** (single tickets; leaves Art. 19(1) percentages unchanged; ≥ 12 h single tickets compensated per contract). Add the June 2026 enforcement deal and the German RefE of 7 Aug 2026 with § 10(3) AEG on SEV.

**docs/03-claim-filing.md**
7. „the ticket number in the "Zeitkarte" field" → the EU form has no Zeitkarte field; the number goes into **3.2.7 „Fahrkartennummer(n)/Buchungsnummer"**, price into 3.2.8. „Zeitkarte / Zeitkarten-Nummer" is a field of the **DB** form ME/08/25.
8. The EU form has **no class field** and **no ticket-type list**; class and ticket type must go into section 6. Only signal: the Zeitkarte checkbox in section 4.
9. Add the mandatory-looking parts the relay must fill: section 2 (previous claim for the same journey), the GDPR **JA/NEIN** consent tick, „Ort der Antragstellung", 5.3.1 e-mail „ggf. die zum Zeitpunkt der Buchung verwendete Adresse".
10. 5.5.4 asks for „Name des Kontoinhabers (Vorname, Nachname)" — an organisation name is off-template; expect this to be the point where the NGO payee is questioned (test claim 1).
11. Copies vs originals: compensation may use copies, refunds/expenses need originals (BB 9.3.2). A taxi/hotel refund by e-mail may trigger a request for the originals.
12. „No proof of travel … DB does not ask for one" — correct; the form's truth declaration covers „alle Fahrgäste".
13. BB 9.3.2 requires a form „vom Reisenden ausgefüllt" — supports the rule that the customer confirms every field before sending.

**docs/04-operators.md**
14. „Participants per DB's list (September 2026)" → the linked PDF is **dated 1 May 2025** (file title „01052025_Übersicht teilnehmende Eisenbahnen im SC FGR"); contents match docs/04.
15. „The RheinRuhrBahn form points to the Servicecenter" → RheinRuhrBahn's own page (Sept 2026) sends claims to **Transdev Service GmbH, Passage 3-5, 17034 Neubrandenburg** or its online form and does not mention the Servicecenter. Treat RRB as a direct-claim operator.
16. Add verified direct-claim operators: NordWestBahn (fahrgastrechte@nordwestbahn.de — the only e-mail channel found), BRB (Postfach 10 01 07, 17041 Neubrandenburg), MRB, VIAS (e-mail), MittelrheinBahn/trans regio, FlixTrain.
17. „Transdev Verkehr GmbH" on the list carries the Zuggattung „VEN" and a Moers address — it is not a catch-all for Transdev brands.

---

## 11. Open questions

1. **NGO as Kontoinhaber**: does the Servicecenter pay to an organisation account named in FORM 5.5.4 without asking for authorisation? (unknown; test claim 1)
2. **Multi-journey bundle on one EU form** (Zeitkarte box + section 6 list): accepted by the EU-form desk? Per-bundle or per-operator 4 € threshold? (unknown; test claim 2)
3. **SEV delays**: does the Servicecenter currently pay for delays on replacement buses (BB 1.3.6 says the EVU remains carrier; the ministry says there were „Abgrenzungsprobleme")? Does § 10(3) AEG survive into law? (unknown)
4. **Cancellation treatment for Zeitkarten**: counted via resulting arrival delay, or flat? (unknown)
5. **Art. 19(10) refusal rate** in practice and whether refusals name the cause precisely enough to contest (unknown; needs reply data).
6. **Verjährung start for the D-Ticket Abo** (month of ride vs end of Abo) — moot if the app uses ride + 12 months. (unknown)
7. **Art. 18(3) for D-Ticket holders**: after 100 min without rerouting information, can a D-Ticket holder recover a Fernverkehr or FlixBus ticket? DB says no for Fernverkehr; the EU text does not exclude it. (unknown)
8. **RDG**: is pre-filling the form from app data a Rechtsdienstleistung under § 2(1) (rule application to the individual case) or a technical aid? If it is one and free, § 6(2) requires a qualified person's supervision. (legal opinion)
9. **Enforcement regulation (June 2026)**: once published, check whether it changes complaint deadlines or the common form. (pending)
10. **Rounding of the 25 % cap** for prices like 59,85 € (14,9625 €). (unknown)
11. Operators not yet checked (Transdev Hannover, Regiobahn S28, UBB, Saarbahn, Nightjet/ÖBB, HKX). (unknown)

