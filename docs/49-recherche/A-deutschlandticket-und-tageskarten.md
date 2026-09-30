> Recherche zu Issue #66 (30. September 2026), Grundlage für docs/49. Pfade `scratchpad/…` bezeichnen lokal heruntergeladene Quelltexte, die nicht im Repo liegen; die URLs stehen jeweils dabei.

# Research A — Deutschland-Ticket family and Nahverkehr day tickets: Fahrgastrechte rules (as of 30.09.2026)

Scope: Deutschland-Ticket (D-Ticket) and its variants, the Länder-Tickets and Quer-durchs-Land-Ticket,
the Fahrradtageskarte, and D-Ticket use on IC sections. Research only, no code changes.

Confidence tags:
- **verified-primary**: tariff text or statute, quoted verbatim.
- **secondary**: operator/DB FAQ, Verbraucherzentrale, press. Quoted verbatim where available.
- **inferred**: my reading of the primary texts, with no source stating it outright.
- **unknown**: no evidence found.

## 0. Primary sources used

| Key | Document | Stand | Where |
|---|---|---|---|
| DTX | Tarifbestimmungen für das Deutschland-Ticket (DTV) | 15.06.2026 | scratchpad `dtx.txt`; deutschlandtarifverbund.de/tarifbedingungen/ |
| DT-A | Deutschlandtarif Teil A Grundsätze | 14.06.2026 | `dtA.txt` |
| DT-C | Deutschlandtarif Teil C Zeitkarten | 14.12.2025 (still current per the DTV page) | `dtC.txt` |
| DT-D | Deutschlandtarif Teil D Tageskartenangebote | 14.06.2026 | `dtD.txt` |
| DT-ES | D-Ticket Tarifbestimmungen in Einfacher Sprache | 15.05.2026 | https://www.deutschlandtarifverbund.de/wp-content/uploads/2026/05/20260515_TB-D-Ticket_Einfache_Sprache.pdf |
| BB-DB | DB Beförderungsbedingungen | 24.09.2026 | `bb.txt` |
| SPNV | "Fahrgastrechte im Schienenpersonennahverkehr" standard text | **old**: it cites VO 1371/2007, so it predates 2023 | `move.txt` |
| EVO | Eisenbahn-Verkehrsordnung §§ 3, 11 | current | `evo.html` / gesetze-im-internet |
| VO | VO (EU) 2021/782 | — | https://eur-lex.europa.eu/legal-content/DE/TXT/HTML/?uri=CELEX:32021R0782 |
| BW | bwtarif Beförderungsbedingungen und Tarifbestimmungen | 27.04.2026 | https://www.bwegt.de/fileadmin/media/PDF/bwtarif-Dokumente/bwtarif_Befoerderungsbedingungen-und-Tarifbestimmungen_27-04-2026.pdf |
| NDS | Niedersachsentarif Beförderungsbedingungen, Anlage 2b | from 01.01.2026 | https://www.niedersachsentarif.de/wp-content/uploads/2025/12/Anlage-2b_BefoerdBed.Niedersachsentarif_gueltig-ab-01.01.2026.pdf |

## 1. Rules shared by every product in scope (the "Zeitkarte" core rule)

The D-Ticket takes its Fahrgastrechte from DT-A Nr. 8 plus DT-C Nr. 8. Länder-Tickets refer to the same two
sections, and DB applies the same flat rates to them.

**R1. Legal hook, D-Ticket (verified-primary).** DTX 1.6: „Für Fahrten im Eisenbahnverkehr gelten die Fahrgastrechte gem. Teil A Nr. 8 der Tarifbedingungen des Deutschlandtarifs sowie Teil C Nr. 8 der Tarifbedingungen für Zeitkarten im Deutschlandtarif … Das Entgelt für das Deutschlandticket gilt als erheblich ermäßigtes Beförderungsentgelt gemäß § 3 EVO. Das zusätzliche Recht bei Verspätung gemäß § 11 Absatz 1 Nummer 1 EVO wird ausgeschlossen." The bwtarif D.6 repeats this word for word.

**R2. Rate, threshold, pooling and cap (verified-primary).** DT-C 8.1:
> „… bei wiederholten Zugausfällen, Verspätungen oder Anschlussversäumnissen ab 60 Minuten innerhalb der Geltungsdauer der Zeitkarte je Einzelfall eine Erstattung bzw. Entschädigung in Höhe von 1,50 € für die 2. Wagenklasse und 2,25 € für die 1. Wagenklasse erhalten. Inhaber einer Fahrkarte oder Fahrt-berechtigung als Zeitkarte können auch wiederholte Verspätungsfälle ab 20 Minuten innerhalb der Geltungsdauer der Zeitkarte zusammenrechnen und gesammelt … geltend machen. In diesen Fällen wird für jeweils volle 60 Minuten Verspätung eine Erstattung bzw. Entschädigung in Höhe von 1,50 € … und 2,25 € … geleistet. Insgesamt werden max. 25 % des gezahlten Zeitkartenpreises ausgezahlt. Eine Zahlung erfolgt jeweils auf Antrag, wenn der Anspruch den Betrag von 4 € (Bagatellgrenze) überschreitet."

The amounts are the same across all sources checked. DB's FAQ (secondary) says: „Zeitfahrkarten des Nahverkehrs: 1,50 Euro (2. Klasse), 2,25 Euro (1. Klasse) … Insgesamt werden maximal 25 Prozent des Zeitfahrkartenwertes entschädigt. Als Zeitkarteninhaber (Ausnahme BahnCard 100) können Sie auch mehrere Verspätungsfälle ab 20 Minuten addieren und gesammelt einreichen. Die zu addierenden Verspätungsfälle müssen dabei innerhalb des Geltungszeitraums der Zeitfahrkarte liegen." (https://www.bahn.de/faq/pk/service/buchung/fahrgastrechte/regelungen)

Modelling notes:
- **Two ways to count** (inferred from R2). A delay of 60 minutes or more is one case. Delays of 20–59 minutes can be added together, and each full 60 minutes of the sum is worth one rate. Open point: can a ≥60-minute case also go into the sum instead of counting alone? The text treats the two as alternatives. A safe model: ≥60 → 1 case; delays of 20–59 min → floor(sum/60) cases; delays under 20 min are ignored.
- **Delays of 60 minutes or more pay only 1 case each.** DT-C has no 120-minute step. Every case pays the flat amount (verified-primary, from the wording „je Einzelfall").
- **Cash cap.** The cap is 25 % of the price paid for this Zeitkarte, not a case count. For a 63 € D-Ticket that is 15,75 €. Ten cases pay 15,00 €. An 11th case would bring the total to 16,50 €, so the payout is cut to 15,75 € (inferred: cap = min(sum, 0,25 × price)). No source says whether DB cuts to the exact 25 % figure or to the last full 1,50 € step. **Open question.**

**R3. Minimum payout and the comparison operator (conflicting texts).**

| Source | Wording | Operator |
|---|---|---|
| DT-C 8.1 (primary) | „wenn der Anspruch den Betrag von 4 € … überschreitet" | > 4 |
| DT-A 8.2.6 (primary, single tickets) | „Entschädigungsbeträge unter 4 € werden nicht ausgezahlt." | ≥ 4 |
| VO 2021/782 Art. 19(8) (primary) | „Die Eisenbahnunternehmen dürfen Mindestbeträge festlegen, unterhalb deren keine Entschädigungszahlungen vorgenommen werden. Dieser Mindestbetrag darf höchstens 4 EUR pro Fahrkarte betragen." | ≥ 4 (EU ceiling) |
| bwtarif A.13 Nr. 2 (primary) | „Entschädigungen werden nur vorgenommen, sofern der Entschädigungsbetrag mindestens 4,00 € beträgt." | ≥ 4 |
| SPNV 6.5 (old) | „von zusammen weniger als 4,00 Euro … nicht ausgezahlt"; for Zeitkarten valid more than one month: „mindestens 4,00 Euro erreicht" | ≥ 4 |
| bahn.de FAQ (secondary) | „Entschädigungsbeträge unter 4 Euro werden nicht ausgezahlt." | ≥ 4 |

Recommendation: model **≥ 4,00 €**. The EU ceiling makes a strict „überschreitet" arguably invalid for exactly 4,00 €. In practice it does not matter: sums of 1,50 € and 2,25 € never land on exactly 4,00 €, so the result is the same either way. The only exception is a sum of ten 0,40 € bike cases. Effective minimum (secondary, BRB, https://www.brb.de/de/service/fahrgastrechte-und-kundengarantien): „Somit müssen Inhaber von Zeitkarten des Nahverkehrs mindestens zwei (1. Klasse) bzw. drei (2. Klasse) Verspätungen geltend machen und diese gesammelt einreichen."

**R4. Pooling window and when to submit (verified-primary).** DT-C 8.2:
> „Eine Kumulation der Entschädigungsbeträge für Einzelfälle nach den Nr. 8.1 erfolgt nur, wenn die Entschädigungsforderungen gesammelt eingereicht werden, bei Wochen- und Monatskarten gesammelt für den Geltungszeitraum nach Ablauf der Geltungsdauer der Zeitkarte. Bei Fahrkarten ohne Preisaufdruck ist vom Reisenden ein Beleg über den gezahlten Preis beizufügen."

Pooling, the 4 € threshold and the 25 % cap all apply per Geltungsdauer (validity period). See §2 for what that period is for the D-Ticket.

**R5. Rounding (verified-primary, but the texts differ).** DT-A 8.2.6: „Der Betrag wird auf einen durch 5 Cent teilbaren Betrag aufgerundet." BB-DB 9.2.1: „kaufmännisch auf die zweite Nachkommastelle gerundet." Flat amounts need no rounding. Rounding only affects cap figures such as 25 % × 59,85 € = 14,9625 €. That gives 15,00 € under DT-A and 14,96 € under BB-DB. **Open question.** The D-Ticket falls under DT-A.

**R6. Deadline (verified-primary plus secondary).**
- DT-A 8.2.8: „Ansprüche nach den Nummern 8.2.1 und 8.2.6 verjähren innerhalb eines Jahres nach Ablauf der Geltungsdauer der Fahrkarte oder Fahrberechtigung." BB-DB 9.5 says the same.
- VO Art. 28(2) sets a 3-month limit for complaints: „innerhalb von drei Monaten nach dem Vorfall".
- DB tolerates later claims (secondary, https://www.bahn.de/service/informationen-buchung/fahrgastrechte/rechtliche-regelungen): „Die Verordnung (EU) 2021/782 sieht vor, dass Beschwerden innerhalb von 3 Monaten nach dem Vorfall eingereicht werden müssen. Wir als DB werden hier aber bis auf Weiteres die fahrgastrechtlichen Beschwerden auch nach Ablauf der 3-Monats-Frist annehmen und bearbeiten. Wir orientieren uns dabei an dem bisher bekannten 12-Monatszeitraum. Wir bitten Sie dennoch, Ihren Fahrgastrechteantrag möglichst innerhalb der 3-Monats-Frist einzureichen."
- Recommendation: aim to submit within 3 months of the incident. Treat 1 year after the end of the validity month as the hard stop.

**R7. Exclusions (verified-primary).** DT-A 8.2.6 lists them: extraordinary circumstances outside rail operations, the passenger's own fault, and the conduct of third parties („Betreten der Gleise, Kabeldiebstahl, Notfälle im Zug, Strafverfolgungsmaßnahmen, Sabotage oder Terrorismus"). Strikes are not excluded (secondary, bahn.de: „Streik zählt explizit nicht zu den in der Verordnung genannten Fällen."). VO Art. 19(9): no compensation if the passenger knew of the delay before buying the ticket.

**R8. Rail only (verified-primary plus secondary).** DT-A 8.1: „gelten die Fahrgastrechte … nur für die Schienenstrecke". bahn.de: „Die Verspätung eines Busses mit Anschlussverlust auf einen Zug gibt keinen Anspruch auf Fahrgastrechte im Eisenbahnverkehr." Bus, tram and U-Bahn legs of a D-Ticket journey never count. A missed train connection because of a bus delay does not count either.

**R9. Other rights for this "erheblich ermäßigt" family (verified-primary).**
- **No reimbursed switch to a Fernverkehr train after a 20-minute delay.** EVO § 3(4): „Das Entgelt für das Deutschlandticket gilt als erheblich ermäßigtes Beförderungsentgelt im Sinne des Absatzes 2." § 3(2) allows the § 11(1) Nr. 1 right to be excluded. DTX 1.6 excludes it. DT-D 4.1 and each Länder-Ticket entry exclude it too („Ein Ersatz der erforderlichen Aufwendungen für die Nutzung eines anderen Zuges … erfolgt daher nicht").
- **Other Nahverkehr trains** can be used anyway, because the ticket covers them. There is no Zugbindung.
- **Taxi or other transport, up to 120 €, still applies.** EVO § 11(1) Nr. 2 and (2) are not excluded: scheduled arrival between 0:00 and 5:00 with an expected delay of 60 minutes or more, or the last connection of the day cancelled so the destination cannot be reached by 24:00. DB FAQ (secondary): „Nur dann ist im Rahmen der gesetzlichen Regeln des §11 (2) … auch die Nutzung eines ICE- oder IC/EC-Zuges möglich. … bis zu einer Höhe von 120 Euro erstattet." The same list also appears in DT-A 8.2.4.
- **Hotel costs** (DT-A 8.2.5) and **information within 100 minutes / self-rerouting** (DT-A 8.2.3) are not excluded. These are cost reimbursements and are **paid in cash, never as a voucher** (bahn.de FAQ).

**R10. Assignment to a third party — relevant for an NGO payee (primary, but an old text).** SPNV 4.3: „Erstattungs- bzw. entschädigungsberechtigt ist … der Fahrgast, sein Rechtsnachfolger, sein gesetzlicher Vertreter oder Derjenige, an den der Fahrgast seinen Anspruch abgetreten hat. Der entschädigungs- bzw. erstattungspflichtige vertragliche Beförderer, der Fahrkartenverkäufer oder das Servicecenter Fahrgastrechte der EVU können für die Abtretung einen Nachweis verlangen. Auch wenn ein Fahrausweis für mehrere Personen gilt, besteht der Anspruch nur einmal. Soweit es sich um einen personengebundenen Fahrausweis handelt, muss für die Erstattung oder Entschädigung grundsätzlich ein Identitätsnachweis mit einem gültigen amtlichen Lichtbildausweis erfolgen." The Fahrgastrechte form has a separate „Kontoinhaber (Name, Vorname)" field, so a payout to someone else's IBAN is possible on paper. **Unknown** whether SC FGR accepts that today without a written assignment (Abtretungserklärung). Build for a signed assignment from the start.

## 2. Deutschland-Ticket (standard)

| Field | Value | Confidence and source |
|---|---|---|
| Validity | Personal Abo. It runs indefinitely, starts on the 1st of a month, and can be cancelled by the 10th for the end of that month. Rail: SPNV, 2nd class, nationwide. | verified-primary, DTX 1.3: „Das Abonnement wird für unbestimmte Zeit abgeschlossen und kann monatlich gekündigt werden. Die Kündigung muss dabei bis zum 10. eines Monats zum Ende des jeweiligen Kalendermonats erfolgen." |
| Price 2026 | 63,00 €/month | verified-primary, DTX 1.4: „… ab dem 01. Januar 2026 63,00 EUR pro Monat bei monatlicher Zahlung. Eine jährliche Zahlung des zwölffachen Monatsbetrages kann angeboten werden." |
| Price 2027 | **Not officially set as of 30.09.2026.** Set by an index, not by political decision; D-TIX is due to publish it „spätestens Ende September". Estimates: 66,40 € (DUH) and 66,80 € (WDR). | secondary: ADAC 01.09.2026 https://www.adac.de/news/deutschlandticket-2027/ („Wie hoch die Kosten 2027 tatsächlich sein werden, soll spätestens Ende September feststehen"); teltarif 02.09.2026 („Der endgültige Preis für 2027 wird von der beauftragten Monitoring-Firma D-TIX ermittelt und soll spätestens Ende September bekanntgegeben werden."); VMK decision 25./26.03.2026. Recheck in early October. The DTV tariff itself runs only to 31.12.2026 (DTX 2.1). |
| Rate | 1,50 € per case (2nd class) | verified-primary (R2) and secondary: bahn.de https://www.bahn.de/faq/deutschlandticket-verspaetung-erstattung „…mit mindestens 60 Minuten Verzögerung, erhalten Sie 1,50 Euro Entschädigung pro Fall." |
| Threshold | Arrival at the destination ≥ 60 min late, or cancellation (Ausfall) with that effect. Pooling of delays ≥ 20 min per full 60 min. | verified-primary (R2) |
| Pooling window | The **validity period = calendar month**. This is not written anywhere for the D-Ticket directly. It follows from: the ticket is a monthly ticket in an Abo; DT-C 8.2 („bei Wochen- und Monatskarten gesammelt für den Geltungszeitraum nach Ablauf der Geltungsdauer"); cancellation and refund are counted per Kalendermonat (DTX 1.3, 1.7); Verbraucherzentrale: „Bei Zeitkarten im Nahverkehr müssen die Verspätungen aufgeschrieben und am Ende des Monats beim Servicecenter für Fahrgastrechte gesammelt eingereicht werden." (https://www.verbraucherzentrale.de/wissen/reise-mobilitaet/unterwegs-sein/erstattung-bei-zugverspaetung-so-gibts-geld-zurueck-12080) | inferred, with strong secondary support. **No evidence** that SC FGR combines cases across calendar months. Everything found says „innerhalb des Geltungszeitraums". Several months may go in one envelope, but each month is assessed on its own: its own 4 € threshold and its own cap (inferred). |
| Cap | 25 % of the **price paid for that month**: 15,75 € at 63 €, which is 10 full cases. Window: per validity month. | verified-primary (DT-C 8.1, „gezahlten Zeitkartenpreises") plus secondary (bahn.de: „Maximal werden 25 Prozent des Wertes Ihres Deutschland-Tickets entschädigt."). The per-month window is inferred. |
| Minimum payout | ≥ 4,00 € per month. In practice 3 cases (4,50 €). | R3 |
| Rounding | Not needed for flat amounts. Cap: rounded up to 5 cent (DT-A). | R5 |
| Deadline | 1 year after the end of the validity month; DB asks for submission within 3 months of the incident. "End of validity" for an open-ended Abo = end of each calendar month, each month counted separately (inferred). | R6 |
| Claim channel | Servicecenter Fahrgastrechte, 60647 Frankfurt am Main, by paper form, or the EU form by e-mail to EUAntragFGR@deutschebahn.com. Alternatively „der Fahrgastrechte-Abteilung des genutzten Eisenbahn-Verkehrsunternehmens". A DB Reisezentrum only forwards Zeitkarten claims: „Sie sind Inhaber einer Zeitfahrkarte (z.B. … Deutschland-Ticket)" → „ausschließlich im Servicecenter Fahrgastrechte". | secondary (bahn.de FAQs, quoted in §0 files). RMV sends D-Ticket holders to SC FGR: „Wenn Sie das Deutschland-Ticket … nutzen …, wenden Sie sich bitte an das Servicecenter Fahrgastrechte." |
| Online claim | Only if the ticket was „im DB Kundenkonto gekauft oder hinterlegt"; path „Zeitkarten & Abos" → „Entschädigung beantragen". **Unknown** whether a D-Ticket from another seller (a Verbund, a Stadtwerk, an app) can be stored (hinterlegt) in the DB Kundenkonto. Assume no, and use the paper or e-mail form. | secondary: https://www.bahn.de/faq/pk/service/buchung/fahrgastrechte/ansprueche |
| Required data | Per trip on the form: date, start station, destination, scheduled departure and arrival, actual arrival date and time. Ticket section: „Zeitkarte – Zeitkarten-Nummer" (= Abo / ticket number). Name, address, IBAN and account holder, signature. Attach a ticket copy and, because a D-Ticket usually shows no price, **proof of price** (DT-C 8.2: „Bei Fahrkarten ohne Preisaufdruck ist vom Reisenden ein Beleg über den gezahlten Preis beizufügen."). No delay certificate is needed (bahn.de: „Sie müssen keine Verspätungsbescheinigung vorlegen"). SPNV 6.6: for relationslose Zeitkarten the passenger must show that they were actually affected, so our GPS/check-in record is useful. | verified-primary (form `fgf.txt`, DT-C 8.2) plus secondary |
| Other rights | R9. No Fernverkehr switch. Taxi/bus up to 120 € in the 0–5 h and last-connection cases. Hotel. | verified-primary |
| Through-ticket with a Fernverkehr ticket | Two separate contracts. A Nahverkehr delay does **not** lift the Zugbindung of the Fernverkehr ticket, and each ticket is assessed separately. bahn.de: „Sie haben keinen Anspruch auf durchgängige Fahrgastrechte zwischen Nah- und Fernverkehr. … Kommt es zu einer Verspätung im Nahverkehr und Sie verpassen dadurch den Fernverkehrszug, bleibt die Zugbindung bestehen." | secondary, https://www.bahn.de/faq/pk/angebot/regionale-angebote/deutschland-ticket/fahrgastrechte |
| DB Einfache Sprache | „Das D-Ticket ist ein besonders vergünstigtes Angebot. Ein zusätzliches Recht bei Verspätung gibt es nicht. Auch wenn Deine Regionalbahn Verspätung hat oder ausfällt, darfst Du nicht mit einem Fernverkehrszug wie einem ICE oder IC fahren." | verified-primary (DT-ES) |

## 3. D-Ticket variants

For all variants: the ticket is still a D-Ticket, so R1–R10 apply unchanged. That covers the 1,50 € rate, the ≥ 60 / ≥ 20-pooling rule, the ≥ 4 € minimum, and the 25 % cap on the „gezahlten Zeitkartenpreises". **The only thing that changes is the price basis of the cap**, and no source defines it for subsidised variants.

### 3.1 Deutschland-Ticket Job (Jobticket)
- **Price (verified-primary).** DTX 1.5: „Der Fahrpreis für das Deutschland-Ticket als Jobticket ist der Fahrpreis nach Abschnitt 4, abzüglich 5 % Rabatt. Voraussetzung … Arbeitgeber einen Zuschuss …, der mindestens 25 % des Fahrpreises gemäß Abschnitt 4 beträgt." At 63 €: tariff price 59,85 €, minimum employer subsidy 15,75 €, employee pays at most 44,10 € (secondary: navit/belonio).
- **Cap basis: unknown.** Two candidates:
  - (a) 59,85 € tariff price → 14,96 or 15,00 € → 9 cases (13,50 €), then capped.
  - (b) the employee's own share, for example 44,10 € → 11,03 € → 7 cases (10,50 €), then capped.

  SC FGR will likely use the price on the proof the passenger sends, usually the Abo statement, which may show either figure. Recommendation: model (b), the price the passenger actually pays. Store the price from the passenger's proof, not an assumed one.
- Confidence: rate verified-primary; cap basis **unknown**.

### 3.2 Deutschlandsemesterticket
- **Price and term (verified-primary).** DTX 1.8: „Der Fahrpreis für das Deutschlandsemesterticket beträgt 60 % des Fahrpreises des regulären Deutschland-Tickets. … Das Deutschlandsemesterticket hat eine feste Laufzeit für das jeweilige Semester ohne monatliche Kündbarkeit." At 63 €: 37,80 €/month, 226,80 € for 6 months. The semester price follows the D-Ticket price set 8 months before the semester starts.
- **Validity = the semester (inferred).** It is neither a week nor a month ticket. That suggests a pooling window of the whole semester and a cap of 25 % of the semester price (56,70 €, which is 37 cases). The old SPNV 6.5 supports this: for Zeitkarten valid more than one month, payments are made „jeweils auf Antrag, wenn … mindestens 4,00 Euro erreicht". So a claim can be made during the validity period once 4 € has accumulated.
- Secondary (older, pre-D-Ticket landesweit Semesterticket page, https://www.dein-semesterticket.mobilitaet-im-studium.de/alles-zum-ticket/zugausfaelle-und-verspaetungen/): „maximal 25 % des Preises für das landesweite Semesterticket". Required documents there: a copy of the valid semester ticket with the current semester marked, plus proof of the ticket's cost.
- **Unknown** whether SC FGR in practice computes the cap per semester or per month (1/6).
- Confidence: rate verified-primary; window and cap inferred.

### 3.3 Sozialtickets (D-Ticket Sozial and Land variants)
- Prices vary by Land and Verbund (secondary, 2026): Hamburg 27,50 €, NRW 53 €, Hessen (Hessenpass mobil) 44 €. Others exist. Sources: https://www.gegen-hartz.de/news/buergergeld-hier-ist-das-deutschlandticket-2026-guenstiger-zu-haben, finanztip.
- Cap basis: price paid by the customer (inferred from „gezahlten"), for example Hamburg 27,50 € → 6,875 € → 4 cases (6,00 €).
- Confidence: rate verified-primary (same D-Ticket tariff); prices secondary; cap basis inferred.

### 3.4 Pupil and trainee D-Tickets (secondary, familienjournal.com 2026 overview)

| Land | Name | Price/month |
|---|---|---|
| BW | D-Ticket JugendBW (under 21, pupils, trainees, students) | 45 € |
| Bayern | Ermäßigungsticket (Azubis) | 43 € |
| MV | Deutschlandticket Azubi | 43 € |
| Niedersachsen | Deutschlandticket Azubi | 50,40 € (31,50 € with employer subsidy) |
| Berlin/Brandenburg | Deutschlandticket Zuschuss Ausbildung | 37,80 € |
| NRW | DeutschlandTicket Schule | 43 €, or 14 / 7 / 0 € with a transport entitlement |
| SH | Deutschland-Schulticket | 21–43 € |
| Saarland | Junge-Leute-Ticket | 44,40 € |
| Hamburg | hvv Deutschlandticket für Schüler | 0 € |

Some items in that overview (Hessen Schülerticket, Sachsen BildungsTicket, Bremen TIM, Berlin Schülerticket) are regional pupil tickets, **not** D-Tickets. For those the Verbund's own Zeitkarten rule applies, typically also 1,50 € (RMV: „Für eine Fahrkarte ohne 1.-Klasse-Zuschlag 1,50 €").

- The bwegt page explicitly lists „D-Ticket JugendBW" under „Zeitkarten des Nahverkehrs … 1,50 Euro (2. Klasse) beziehungsweise 2,25 Euro (1. Klasse)" (secondary, https://www.bwegt.de/reiseinformationen/fahrgastrechte-und-mobilitaetsgarantie).
- **Consequence to flag:** for free (0 €) or state-paid variants, 25 % of the „gezahlter" price is 0 €. Such a ticket may yield **no compensation at all**. The same applies to D-Tickets fully paid by third parties.
- Confidence: prices secondary (check each before shipping); cap basis inferred.

### 3.5 D-Ticket included with BahnCard 100
- **Verified-primary.** BB-DB C.3 3.1.1.1: „Zur BahnCard 100 … wird unentgeltlich und beschränkt auf deren Geltungsdauer ein Deutschland-Ticket ohne Abo-Regelung ausgegeben. … Die BahnCard 100 und das Deutschland-Ticket stellen getrennte Beförderungsverträge auch im Hinblick auf die tariflichen Fahrgastrechte dar." And 3.10.3: „Die Fahrgastrechte bei Nutzung des Deutschland-Tickets richten sich gem. Nr. 3.1.1.1 nach dem Tarif für das Deutschland-Ticket."
- **Consequence (inferred).** The included D-Ticket is free, so its cap is 25 % × 0 € = 0 €.
- **But** the BahnCard 100 itself is valid in all Deutschlandtarif SPNV trains (DT-A 3.5.2: „Die BahnCard 100 der Deutschen Bahn AG gilt in der jeweiligen Wagenklasse zur Fahrt in den Zügen gemäß Nr. 2.2."). So a BC100 holder should claim a Nahverkehr delay **under the BahnCard 100**, not under the D-Ticket.
- BC100 rules (BB-DB 3.10.1, verified-primary): „ab 60 Minuten eine Erstattung bzw. Entschädigung in Höhe von 10 €, Inhaber einer BahnCard 100 1. Klasse … 15 € …, insgesamt max. 25 % des gezahlten BahnCard-Preises. Verspätungen können nicht zwecks Erreichen der Zeitgrenze nach Satz 1 addiert werden." No pooling. Online claims go through the BahnCard area of the Kundenkonto.
- Which contract DB assigns a BC100 holder's Nahverkehr trip to is **unknown**. Model it as a BC100 claim.

### 3.6 1st class with a D-Ticket
- DTX 1.2: „Ein Übergang in die 1. Wagenklasse ist innerhalb der Geltungsbereiche von Verkehrsverbünden, Landestarifen und des Deutschlandtarifs nach den jeweiligen Tarifbestimmungen möglich." DTX 2.3 applies DT-C 4.4/4.5 (Einzelübergang and Dauerübergang for the validity period) to all D-Tickets. BW sells a „1.Klasse-Zusatzticket für einen Kalendermonat zum Festpreis von 63,- EUR je Kalendermonat", valid only with a D-Ticket for the same month (bwtarif B.8 Nr. 5, verified-primary).
- **2,25 € rate with an upgrade.** DT-A 1.1 makes add-on tickets part of the contract: „Werden Zusatzkarten für ergänzende Leistungen, z.B. für die Beförderung in der 1. Wagenklasse … ausgegeben, so sind diese Bestandteil des durchgehenden Beförderungsvertrages". RMV states it for its own Zeitkarten: „für eine Fahrkarte mit 1.-Klasse-Zuschlag 2,25 €". So: 2,25 € for trips made in 1st class under a valid monthly 1st-class upgrade (inferred for the D-Ticket; secondary for RMV Zeitkarten). For a single upgrade, probably only that trip counts at 2,25 € (inferred).
- **Cap basis** with an upgrade: D-Ticket price plus upgrade price, for example 63 € + 63 € = 126 € → 31,50 € (inferred). **Unknown** in practice.
- **Open question:** whether SC FGR handles Verbund-issued 1st-class add-ons, or refers them to the Verbund.

### 3.7 D-Ticket with a fixed 12-month term or annual payment
- DTX 1.3: „Neben der monatlichen Kündbarkeit kann in Verbindung mit anderen Produkten … auch eine feste Laufzeit von 12 Monaten angeboten werden." DTX 1.4 allows annual payment.
- Whether the Geltungsdauer is then 12 months (one window, cap 25 % of 756 € = 189 €) or still monthly is **unknown**. The ticket is still issued per month and refunds are per month (DTX 1.7: „Erstattet wird für volle Kalendermonate der in dem betreffenden Monat geltende Monatseinzug"). That points to monthly windows (inferred). Model it as monthly.

## 4. D-Ticket on IC/ICE sections opened to it, and D-Ticket + Fernverkehr ticket

**Sections (verified-primary, DTX 3.1).** DB Fernverkehr AG, „IC-/ICE-Züge (ggf. mit RE-Zugnummer)":
- Rostock Hbf – Stralsund Hbf
- Rostock Hbf – Hamburg Hbf (ICE: „nur ICE 1598/1599 (bis 10.07.2026), ICE 1520/1521 (11.07. – 12.12.2026)")
- Stuttgart Hbf – Singen/Konstanz
- Bremen Hbf – Norddeich Mole/Emden Außenhafen
- Erfurt – Gera
- Dresden Hbf – Chemnitz Hbf
- Dortmund Hbf – Dillenburg

Footnote 2 of DTX: other Fernverkehr trains released for Verbund tickets (for example in RMV, VVO, VMS, SH-Tarif, MDV) „dürfen … mit einem Deutschland-Ticket nicht genutzt werden".

**Rules on these sections (inferred).** The Fahrgastrechte follow the ticket (the D-Ticket tariff via DTX 1.6), not the train. So the D-Ticket rules apply: 1,50 € per case, the 25 % cap and pooling. The IC-Zeitkarte rule (BB-DB B.13: 5 €/7,50 €) applies only to „Inhaber einer Zeitkarte für die Produktklassen IC/EC oder ICE oder einer IC/EC-Aufpreiskarte". No source says so outright, but no source contradicts it. Delays count at the passenger's destination, and SC FGR handles them (DB Fernverkehr is a member).

**D-Ticket plus a separate Fernverkehr ticket (secondary, bahn.de):** „Bei einer Kombination aus Deutschland-Ticket und Fernverkehrsticket gelten 2 getrennte Beförderungsverträge … Entschädigungsansprüche werden für jedes Ticket einzeln geprüft". The Fernverkehr leg earns 25 % / 50 % of that ticket's price under DT-A 8.2.6 / BB-DB 9.2.1, with its destination = the destination printed on the Fernverkehr ticket. The D-Ticket leg earns 1,50 € per case. There is no through-ticket protection, and the Zugbindung stays.

**D-Ticket holders' discounted Fernverkehr offers** (BB-DB E.28 MV–Hamburg, E.29 Mainz–Bonn, 60 % off 10/20-Fahrten-Tickets for D-Ticket holders): these are separate Fernverkehr tickets with their own Fahrgastrechte, outside this scope.

## 5. Länder-Tickets and Quer-durchs-Land-Ticket

### 5.1 Which rule: percentage or flat?
DT-D 4.1.1 (verified-primary): „Für Entschädigungsansprüche nach der europäischen Fahrgastrechteverordnung … gelten die Regelungen der Nr. 8 der Tarifbedingungen des Deutschlandtarifs (Grundsätze), bzw. der Nr. 8 der Zeitkartenbedingungen entsprechend." DT-D 3.5 is sharper: „… gelten die Regelungen der Nr. 8 der Tarifbedingungen (Grundsätze), **in Verbindung mit** Nr. 8 der Zeitkartenbedingungen des Deutschlandtarifs entsprechend."

**Resolution: the flat Zeitkarte rule applies**, 1,50 € (2nd class) / 2,25 € (1st class) per case with the 25 % cap. Every operator and DB source treats Länder-Tickets as Zeitfahrkarten:
- bahn.de (secondary): „Zeitfahrkarten des Nah- und Fernverkehrs (z.B. Wochen- oder Monatskarten, Länder-Tickets, Quer-durchs-Land-Ticket) werden pauschal jeweils ab einer Verspätung ab 60 Minuten am Zielbahnhof entschädigt."
- fahrgastrechte.info, the industry site the DTV links to (secondary): table „Zeitkarten des Nahverkehrs · Länder-Tickets · Quer-durchs-Land-Ticket — 1,50 Euro / 2,25 Euro"; „Deutschland-Ticket, Quer-durchs-Land-Ticket und Länder-Tickets sind Zeitfahrkarten des Nahverkehrs."
- Niedersachsentarif 5.1.8 (verified-primary): „Das Niedersachsen-Ticket ist im Sinne der Fahrgastrechte eine Zeitkarte."
- bwegt (secondary) lists Länder-Tickets, the Quer-durchs-Land-Ticket and the Schönes-Wochenende-Ticket at 1,50 €.
- The VO definition fits: a Zeitfahrkarte is „eine für eine unbegrenzte Anzahl von Fahrten gültige Fahrkarte … während eines festgelegten Zeitraums" (Art. 3 Nr. 19).

Confidence: **verified-primary plus secondary, consistent**.

### 5.2 Mechanics
- **Window** = the validity day: weekdays 9:00 to 3:00 the next day, weekends and holidays 0:00 to 3:00 (DT-D 3.2.1); Nacht variants from 18:00 to 6:00/7:00. Pooling (≥ 20 min) and the cap apply within that single day.
- **Payout** needs ≥ 4 €: at least 3 cases of ≥ 60 min (4,50 €), or ≥ 180 pooled minutes, **on one day** in 2nd class; 2 cases (4,50 €) in 1st class. Realistically, a Länder-Ticket rarely pays out (inferred).
- **Cap** = 25 % of the price paid for the ticket, for example Bayern-Ticket 1 person 34 € → 8,50 € (5 cases).

### 5.3 Group tickets (1 person plus up to 4 companions)
- The only primary text found is SPNV 4.3 (old): „Auch wenn ein Fahrausweis für mehrere Personen gilt, besteht der Anspruch nur einmal." That means **one claim per ticket**, for the lead passenger, capped at 25 % of the total group price.
- A search-engine summary claimed "per person" for group tickets. I found **no quotable source** for that, so it is unverified.
- **No source defines a per-person share.** Recommendation: model one claim per ticket; the cap basis is the full ticket price. If the app later supports groups, attribute the claim to the ticket holder only. Confidence: primary but outdated; **open question**.

### 5.4 Other rights
Erheblich ermäßigt, so no reimbursed Fernverkehr switch (verified-primary, in every DT-D entry). The EVO § 11(1) Nr. 2 taxi right (up to 120 €) remains. Combining neighbouring Länder-Tickets **does not form a through-ticket** (verified-primary, for example DT-D 5.2.4: „Eine Kombination angrenzender Länder-Tickets … ergibt keine Durchgangsfahrkarte").

### 5.5 Deadline and claim channel
- Deadline: 1 year after the validity day (DT-A 8.2.8).
- Claim: SC FGR (bahn.de: „Sie sind Inhaber einer Zeitfahrkarte (z.B. …, Quer-durchs-Land-Ticket, Länder-Ticket …)" → processed only at SC FGR). SPNV 4.3: „Entschädigungen für relationslose Zeitfahrkarten (z.B. Schönes-Wochenende-Ticket, Länder-Tickets) erfolgen grundsätzlich durch das ‚Servicecenter Fahrgastrechte'". Identity proof or an assignment may be required because the tickets carry names.
- The bwtarif says: „an das verspätungsverursachende Verkehrsunternehmen oder an das Servicecenter Fahrgastrechte".
- Proof: the ticket (price printed on it) plus the form.

### 5.6 Product list, 2026

Existence: verified-primary where marked DT-D; secondary otherwise. Prices are for the 2nd class at a machine or online.

| Product | Tariff | 2026 price (1 person / + each additional) | Notes |
|---|---|---|---|
| Quer-durchs-Land-Ticket | DT-D 5.1 | 51,00 € / +12 € (up to 5 people: 99 €) | nationwide, 2nd class only |
| Bayern-Ticket | DT-D 5.2 | 34,00 € / +10 €; 1st class 46,50 € / +22 € | 1st-class upgrade 12,50 € (1 person) |
| Bayern-Ticket Nacht | DT-D 5.2 | 32,00 € / +7 € | Sun–Thu 18:00–6:00, Fri/Sat 18:00–7:00 |
| Brandenburg-Berlin-Ticket | DT-D 5.3 | 36,50 € flat; 1st class 61,50 € | the table has no per-person columns, so flat for up to 5 people (inferred) |
| Brandenburg-Berlin-Ticket Nacht | DT-D 5.3 | 27,00 €; 1st class 52,00 € | 18:00–7:00 |
| Mecklenburg-Vorpommern-Ticket | DT-D 5.4 | Mon–Thu 25,00 € / +5 €; Fri–Sun 27,00 € / +6 € | 1st-class upgrade 20 € flat |
| Rheinland-Pfalz-Ticket / Saarland-Ticket | DT-D 5.5 | 30,00 € / +10 € | |
| Sachsen-Ticket, Sachsen-Anhalt-Ticket, Thüringen-Ticket | DT-D 5.6 | 35,00 € / +8 € | |
| Baden-Württemberg-Ticket | bwtarif C.1 (primary) | 27,00 € / +9 €; 1st class 35 € / +17 € | valid from 0:00 since 01.04.2026; BW-Ticket Nacht discontinued (secondary: vgf „Aus acht macht eins"). DT-D still names „Baden-Württemberg-Ticket Nacht" (outdated text). |
| Niedersachsen-Ticket | Niedersachsentarif (primary for the Fahrgastrechte clause) | 29,00 € / +8 € (secondary) | „im Sinne der Fahrgastrechte eine Zeitkarte" |
| Schleswig-Holstein-Ticket | SH-Tarif | 32 / 38 / 44 / 50 / 56 € for 1–5 people from 01.04.2026 (secondary, nah.sh) | |
| Hessenticket | RMV/NVV | price not verified | RMV lists it as „stark vergünstigt" (no Fernverkehr switch) |
| SchönerTagTicket NRW → **24hTicket NRW** | NRW-Tarif | Single 39,80 €, 5 people 59,80 € (secondary) | renamed on 01.01.2026. Valid 24 h from validation, not per calendar day, so the pooling window is 24 h (inferred). DT-D still says „SchönerTagTicket NRW". |
| Regional day tickets in DT-D (Bayerwald, BGL, Gäubodenbahn, Guten Tag Ticket, Südostbayern, trilex, EgroNet, Bayern-Böhmen, Sachsen-Böhmen, Saar-Lor-Lux …) | DT-D 5.7–5.36 | various | same DT-D 3.5/4.1.1 rule, so 1,50 € flat (inferred). Cross-border legs are outside the scope. |

## 6. Fahrradtageskarte Nahverkehr (and bike day tickets generally)

| Field | Value | Confidence |
|---|---|---|
| Product | Fahrradtageskarte Nahverkehr, 7,50 € (DT-D 5.15.3: „Eine Fahrradtageskarte Nahverkehr kostet 7,50 €."). Valid on the day printed until 3:00, extended with Nacht tickets. Also Fahrrad-Tageskarte Bayern (DT-D 5.13) and the Niedersachsentarif Fahrradtageskarte. | verified-primary |
| Rate | 0,40 € per trip delayed ≥ 60 min, **added to the rider's own ticket claim** | SPNV 6.5 (old primary): „Die Entschädigung aus der Fahrradtageskarte beträgt dabei 0,40 Euro je mit mindestens 60 Minuten verspäteter Fahrt … Der Entschädigungsanspruch aus der Fahrradtageskarte wird zu dem Entschädigungsbetrag aus dem Fahrausweis des Reisenden selbst addiert." Still current per NEB (secondary, https://www.neb.de/tickets/rechte-pflichten/fahrgastrechte/): „Für Fahrradzeitkarten gibt es eine pauschale Entschädigung von 0,40 EUR pro Fall." DT-A/DT-C 2026 do **not** mention 0,40 € (they are silent on bikes). |
| Cap | Probably 25 % of 7,50 € = 1,875 € (4 cases = 1,60 €) (inferred: it is a Zeitkarte) | inferred |
| Minimum | Combined with the person's claim: „Auszahlungsbeträge für Entschädigungen von zusammen weniger als 4,00 Euro werden nicht ausgezahlt" | old primary |
| Proof | „Die Fahrradtageskarte muss im Original zusammen mit dem Fahrausweis oder der Fahrausweiskopie des Reisenden zur Entschädigung eingereicht werden." | old primary |
| Pooling with D-Ticket cases | The bike ticket's window is its own day; the D-Ticket's window is the month. Whether 0,40 € cases can be added to a monthly D-Ticket claim is **unknown**. | unknown |

Recommendation: low value (at most 1,60–1,90 € per bike day ticket). Treat as optional and add it only to a claim that already reaches the minimum.

## 7. Worked model (per D-Ticket month, 2nd class, 63 €)

```
cases60  = number of arrivals ≥60 min late (or equivalent cancellations) in the month
pooled   = floor(sum(delay minutes of arrivals with 20 ≤ delay < 60) / 60)
gross    = 1.50 × (cases60 + pooled)
cap      = 0.25 × price_paid_for_that_month          // 15.75 at 63 €
payout   = min(gross, cap)
eligible = payout ≥ 4.00                             // 3+ units
deadline = end_of_month + 1 year (aim: incident + 3 months)
```

Per Länder-Ticket day: the same formula, with the window = the validity day, the cap = 25 % of the ticket price and one claim per ticket.

## 8. Open questions (explicit)

1. **Cross-month pooling:** no evidence either way from SC FGR practice. Every text says „innerhalb der Geltungsdauer der Zeitkarte". For the D-Ticket, treat each calendar month as its own window. Test with one real claim containing two months.
2. **Cap cut:** is the payout cut to exactly 25 % (15,75 €) or to the last full 1,50 € step (15,00 €)? Rounding differs too (DT-A rounds up to 5 cent; BB-DB rounds to the cent).
3. **"Gezahlter Preis" for subsidised variants:** Jobticket (59,85 € tariff vs. employee share), Semesterticket (semester price vs. monthly share), Sozial and Schüler tickets, and **free** tickets (hvv Schüler 0 €, D-Ticket included with BC100 0 €). With a 0 € basis the cap is 0.
4. **Online claims for non-DB D-Tickets:** can a D-Ticket from another seller be stored (hinterlegt) in the DB Kundenkonto? Not found. Assume paper form or EU e-mail form.
5. **Price proof:** what SC FGR accepts for a D-Ticket without a printed price (Abo contract, bank statement, app screenshot). DT-C 8.2 requires „ein Beleg über den gezahlten Preis".
6. **Assignment / NGO payee:** does SC FGR accept payout to an NGO's IBAN with a signed Abtretungserklärung? Only the old SPNV 4.3 text is available. It allows assignment but lets them demand proof.
7. **Group Länder-Tickets:** one claim per ticket (old SPNV 4.3) vs. one per person (unverified). There is no per-person share rule.
8. **1st-class upgrade with a D-Ticket:** whether 2,25 € applies, and on what cap basis (D-Ticket plus upgrade?), is untested. Verbund-issued add-ons may be handled by the Verbund.
9. **Fixed-term 12-month D-Ticket / annual payment:** is the validity 12 months or monthly? Assume monthly.
10. **2027 D-Ticket price:** not announced in any source found up to 30.09.2026 (due by the end of September via D-TIX; estimated 66,40–66,80 €). Recheck in early October.
11. **BC100 holder's Nahverkehr delay:** DB assigns it to the BC100 (10 €) or to the free D-Ticket (1,50 €, cap 0). Presumably BC100, but unverified.
12. **DT-D outdated names** (BW-Ticket Nacht, SchönerTagTicket NRW): the 24hTicket NRW runs 24 h from validation, so its pooling window is 24 h rather than a calendar day (inferred).
13. **„Überschreitet" vs. „mindestens" 4 €:** irrelevant for multiples of 1,50 € / 2,25 €, but relevant if 0,40 € bike cases are added.
14. **SPNV text (`move.txt`) is pre-2023** (it cites VO 1371/2007). Its bike, assignment and group rules should be rechecked against a current operator text if they are relied on.

