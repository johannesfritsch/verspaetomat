# 49 — Fahrkarten und Ansprüche: was wir die Bahn fragen dürfen

Recherche und Datenmodell zu Issue #66, 30. September 2026. Johannes' Auftrag: „Please research the
ticket landscape of the Deutsche Bahn and build a concept for Fahrgastrechte. What tickets to offer
for which train connections." Und danach: „Please do proper research for all tickets, then build a
data model for that, that works for everything and is flexible enough."

Noch nichts davon ist gebaut. Die vier Rechercheberichte mit jeder Regel, ihrer Quelle, dem
wörtlichen Tariftext und einer Einstufung (*belegt*: Primärquelle; *sekundär*: FAQ,
Verbraucherzentrale, Presse; *abgeleitet*; *unbekannt*) liegen in [`49-recherche/`](49-recherche/):

| Bericht | Inhalt |
|---|---|
| [A](49-recherche/A-deutschlandticket-und-tageskarten.md) | Deutschlandticket und Varianten, Länder-Tickets, Quer-durchs-Land, Fahrradtageskarte |
| [B](49-recherche/B-fernverkehr-und-db-fahrkarten.md) | DB-Einzelfahrkarten aller Art, BahnCard 100, Strecken- und Semesterzeitkarten, international, FlixTrain, Pässe, mehrere Fahrkarten auf einer Reise, was die Bahn wissen will |
| [C](49-recherche/C-verbuende-und-garantien.md) | 20 Verbund- und Landestarife, freiwillige Garantien |
| [D](49-recherche/D-uebergreifende-regeln.md) | Fristen, Messung, höhere Gewalt, EU-Formular Feld für Feld, Zahlung an den Verein, Bahnen, Gesetzgebung |

Dieses Dokument fasst zusammen (§1–3), sagt, was der Code heute falsch macht (§4), und legt das
Datenmodell fest (§5–8). Offen bleibt, was nur Johannes oder nur die Bahn beantworten kann (§9).

## 1. Was für jede Fahrkarte gilt

- **Gemessen wird am Ziel der Fahrkarte**, nicht am Ziel der Reise. Verpasste Anschlüsse zählen,
  wenn die planmäßige Umstiegszeit eingehalten war (DT-A 8.1, BB 9.1.4). Bus, Tram, U-Bahn zählen
  nie. Eine Fahrkarte ist ein Vertrag: mehrere Fahrkarten aus **einem Kaufvorgang** (eine
  Auftragsnummer) sind ein Vertrag (BB A.1.3.4), getrennt gekaufte sind getrennte Verträge — ein
  D-Ticket für den Zubringer und ein Sparpreis für den ICE sind zwei Fälle mit zwei Zielen, und die
  Zugbindung des Sparpreises bleibt, wenn der Zubringer zu spät kommt.
- **Frist.** Drei Monate (EU Art. 28(2)) gelten für *Beschwerden*, nicht für Ansprüche. Ansprüche
  verjähren **ein Jahr nach Ablauf der Geltungsdauer** der Fahrkarte (CIV Art. 60, BB A.9.5,
  DT-A 8.2.8); das Eisenbahn-Bundesamt sagt „spätestens innerhalb eines Jahres nach dem Vorfall".
  DB bittet um drei Monate und nimmt zwölf. **Unsere Regel: einreichen möglichst in drei Monaten,
  hart Schluss zwölf Monate nach der Fahrt** — das liegt immer innerhalb der gesetzlichen Frist und
  erübrigt die Frage, wann ein unbefristetes D-Ticket-Abo „abläuft". Abweichend: MVV drei Monate
  nach Ablauf der Fahrkarte, FlixTrain drei Monate nach der Fahrt, Interrail drei Monate nach
  Passende.
- **Bagatellgrenze 4 €** pro Fahrkarte (EU Art. 19(8)), mit zwei Vergleichen: DB-Einzelfahrkarten
  „unter 4 € nicht" (also ab 4,00 €); Deutschlandtarif-Zeitkarten, FlixTrain, Interrail, SH-Tarif
  „überschreitet"/„höher als" (also ab 4,01 €).
- **Runden:** DB kaufmännisch auf den Cent (BB 9.2.1, neu gefasst 11/2026), Deutschlandtarif und
  die meisten Verbünde (VBB, MVV, …) **auf volle 5 Cent auf**.
- **Höhere Gewalt** (EU Art. 19(10)) muss die Bahn beweisen. Nicht darunter: Streik, Störungen des
  Netzbetreibers, andere Züge auf der Strecke, „ein gewöhnliches Unwetter" (DB).
- **Schienenersatzverkehr** ist heute nicht eindeutig: BB A.1.3.6 macht die Bahn zum Beförderer,
  der Referentenentwurf vom 7. August 2026 will es mit § 10 Abs. 3 AEG klarstellen („Für
  Beförderungen im Schienenersatzverkehr gelten die Rechte der Fahrgäste im Eisenbahnverkehr").
- **Ausfall:** Keine Quelle sagt, dass ein Ausfall pauschal als 60 Minuten zählt. Er zählt mit der
  Verspätung, mit der man tatsächlich ankommt. Die angerechneten 60 Minuten aus docs/47 bleiben für
  die Minuten der App, gehen aber nicht in einen Antrag.
- **An den Verein zahlen** ist rechtlich eine **Zahlungsanweisung** (BGB § 362 Abs. 2 mit § 185),
  keine Abtretung: der Fahrgast bleibt Anspruchsteller und unterschreibt, der Verein ist nur
  Kontoinhaber. Das hält uns aus dem Inkasso heraus (RDG § 2 Abs. 2). Ob das Servicecenter an ein
  Vereinskonto zahlt, ohne nachzufragen, weiß niemand — das ist Testantrag 1. Das EU-Formular
  fragt in 5.5.4 nach „Name des Kontoinhabers (Vorname, Nachname)"; ein Vereinsname passt da nicht
  hinein, dort wird es sich entscheiden.
- **Das EU-Formular** (DVO 2024/949) hat **kein Klassenfeld, keine Liste von Fahrkartenarten und
  kein Zeitkartenfeld**. Die Nummer gehört in 3.2.7 „Fahrkartennummer(n)/Buchungsnummer", der Preis
  in 3.2.8, Klasse und Fahrkartenart in den Freitext (Abschnitt 6, 2.500 Zeichen). Das einzige
  Signal für die Art ist das Kreuz „für wiederholte Verspätungen … Inhaber einer Zeitfahrkarte".
  Auszufüllen sind außerdem Abschnitt 2 (früherer Antrag zur selben Fahrt), die Datenschutz-Frage
  JA/NEIN und der Ort.
- **Weitere Rechte** (kein Antrag, aber Geld, und unterwegs richtig zu sagen): ab 20 Minuten
  erwarteter Verspätung ein anderer Zug, auch ein höherer — **außer mit „erheblich ermäßigten"
  Fahrkarten** (EVO § 3 Abs. 4: D-Ticket, Länder-Tickets, Quer-durchs-Land, die meisten
  Nahverkehrs-Tageskarten; nie Monats- oder Jahreskarten); ab 60 Minuten abbrechen und den
  Fahrpreis zurück (Art. 18, docs/21); nachts oder bei ausgefallener letzter Verbindung Taxi bis
  120 €, auch für D-Ticket-Inhaber, auch ICE; Hotel; nach 100 Minuten ohne Auskunft selbst umbuchen
  (Art. 18(3)). Bei internationalen DB-Fahrkarten gilt die Freigabe erst ab 60 Minuten.

## 2. Die Fahrkarten

### 2.1 Die drei Arten zu rechnen

Alles, was die Recherche gefunden hat, lässt sich mit **drei** Rechnungen ausdrücken. Das ist die
wichtigste Erkenntnis für das Modell:

| Art | Rechnung | Wer |
|---|---|---|
| **Anteil am Preis** | ab 60 Min. 25 %, ab 120 Min. 50 % des gezahlten Preises, je Fahrkarte | alle Einzelfahrkarten: DB (Flex-, Spar-, Super Sparpreis, mit BahnCard 25/50), Deutschlandtarif, Verbünde, FlixTrain, European Sleeper, international |
| **Betrag je Fall** | fester Betrag je Fall ab einer Schwelle, nach Minuten gestuft möglich | BahnCard 100 (10/15 €), Verbund-Zeitkarten (1,50/2,25 €), IC/EC-Semesterticket (1,30 €), Interrail/Eurail (12 € ab 60, 24 € ab 120), German Rail Pass (5/7,50 €), Fahrradtageskarte (0,40 € zusätzlich) |
| **Minuten-Topf** | Fälle ab 20 Min. werden addiert, je volle 60 Min. ein fester Betrag | Deutschlandticket und alle Deutschlandtarif-Zeitkarten (1,50/2,25 €), DB-Streckenzeitkarten ICE und IC/EC (5/7,50 €), Länder-Tickets und Quer-durchs-Land |

Darüber liegen Deckel, Fenster, Mindestzahlen, Fristen und Rundung — Parameter, keine neuen
Rechnungen.

### 2.2 Zeitkarten des Nahverkehrs

| Produkt | Rechnung | Fenster | Deckel | Einstufung |
|---|---|---|---|---|
| **Deutschlandticket** (63 €; 2027 noch nicht beschlossen) | Topf, 1,50 € (2,25 € mit Aufpreis 1. Kl.) | **offen**, §9 Frage 1 | 25 % des gezahlten Preises je Monat → 15,75 € | belegt (DTX 1.6, DT-C 8.1) |
| D-Ticket Job (59,85 € oder Eigenanteil) | wie oben | wie oben | 25 % — **welcher** Preis, ist nicht geregelt | unbekannt |
| Deutschlandsemesterticket (37,80 €/Monat, feste Laufzeit) | wie oben | Semester? | 25 % des Semesterpreises? | abgeleitet |
| D-Ticket Sozial, Schüler, Azubi, JugendBW | wie oben | Monat | 25 % des gezahlten, bei 0 € also 0 | abgeleitet |
| D-Ticket der BahnCard 100 | wie oben, aber Preis 0 € | — | 0 € → **über die BahnCard 100 beantragen** | abgeleitet |
| Deutschlandtarif-Zeitkarte | Topf, 1,50 / 2,25 € | Geltungsdauer | 25 % | belegt (DT-C 8.1) |
| Verbund-Zeitkarten (Woche, Monat, Abo, Jahr, Schüler, Semester) | **je Fall ab 60 Min.** 1,50 / 2,25 € — **kein Topf** (Niedersachsen: Fall schon ab 20 Min.) | Woche/Monat: nach Ablauf gesammelt; länger: sobald ≥ 4 € | 25 %; VRR ausdrücklich je Monat; HVV Semesterticket 4,50 € je Semester | belegt, Tabelle in C §2 |
| — NRW (VRR, VRS, AVV, WestfalenTarif, NRW-Tarif) | wie oben, **mindestens 3 Fälle** | Monat | 25 % je Monat | belegt |
| — MVV | 1,50 €, keine 1. Klasse; Frist 3 Monate | — | 25 % | belegt |
| — SH-Tarif | Schulträger-Zeitkarten: nur der Schulträger darf beantragen | — | — | belegt |
| Tageskarten der Verbünde | zählen als Zeitkarte (VBB, RMV, HVV, MVV, SH, VBN, MDV, NRW) | der Tag | 25 % | belegt |

Die Verbünde, die kein eigenes Wort sagen (bwtarif, KVV, VGN, VRM, saarVV, VMS), verweisen auf die
Bedingungen der Bahn, und die haben den gemeinsamen SPNV-Mustertext. **Der Antrag geht nie an den
Verbund**, sondern an die Bahn, die den verspäteten Zug fuhr (Ausnahme: RMV-Fahrkarten an die
RMV-Servicegesellschaft). VRN schließt das D-Ticket in seinem eigenen Text aus; das widerspricht
dem Deutschlandtarif, der für das D-Ticket gilt.

### 2.3 Tageskarten des Deutschlandtarifs

Länder-Tickets (alle 2026 noch da; das SchönerTagTicket NRW heißt seit 1.1.2026 24hTicket NRW und
gilt 24 Stunden ab Entwertung) und Quer-durchs-Land (51 €) sind nach DT-D 4.1.1 und der DB
**Zeitkarten**: Topf ab 20 Minuten, 1,50 € je volle Stunde, 25 % des Ticketpreises, Fenster = die
Geltungsdauer, erheblich ermäßigt. Auszahlbar erst ab drei vollen Stunden **an einem Tag**, also
fast nie. Für Gruppentickets gibt es einen Anspruch je Fahrkarte, nicht je Person.

### 2.4 Fernverkehr

| Produkt | Rechnung | Deckel | Einreichen | Einstufung |
|---|---|---|---|---|
| **BahnCard 100** (4.899 € / 7.999 €, nur noch Einmalzahlung) | je Fall ab 60 Min. **10 € / 15 €**, nie addiert; +10 € wenn in 1. Klasse die 1. Klasse fehlt | 25 % des BahnCard-Preises | jederzeit | belegt (C.3.10) |
| **Streckenzeitkarte ICE, IC/EC** (Woche, Monat, Jahr, Abo; Schüler, Pendler) | Topf ab 20 Min., je 60 Min. **5 € / 7,50 €** | 25 % des gezahlten Preises | Woche/Monat nach Ablauf | belegt (B.13) |
| IC/EC-Semesterticket | 1,30 € je Fall, nur ab 3 Fällen im Monat | 4 € je Monat | nach dem Semester | belegt |
| IC/EC-Aufpreiskarte, 44-Stunden-Ticket Young | — | — | — | **nicht mehr verkauft** |

### 2.5 Einzelfahrkarten

Alle nach Anteil am **gezahlten** Preis (der BahnCard-Rabatt ist schon drin). Besonderheiten:

- **Aktionsgutscheine** gehen aus der Grundlage heraus, Wertgutscheine nicht (BB 9.2.1).
- **Hin- und Rückfahrt:** je Richtung ein Anspruch, auf den Preis dieser Richtung, sonst die Hälfte.
- **City-Ticket:** der Nahverkehrsteil ist ein eigener Vertrag mit dem Verkehrsbetrieb und bringt
  nichts; gemessen wird am Zielbahnhof.
- **Super Sparpreis ab 4,99 €:** 25 % sind 1,25 € — unter der Grenze. Etwas gibt es erst ab 16 €
  (60 Min.) oder 8 € (120 Min.). Die App muss das sagen, bevor jemand einen Antrag erwartet.
- **Fehlende 1. Klasse:** Sparpreis 20 € je Person (höchstens der Fahrkartenwert), Flexpreis die
  Differenz zur 2. Klasse (BB 9.2.2, 9.2.3), mit Nachweis.
- **Reservierung:** voll zurück, wenn nicht nutzbar, ohne Schwelle.
- **FlixTrain:** 25/50 %, auszahlbar nur **über** 4 €, drei Monate, eigenes Kontaktformular.
- **International (DB):** Pflichtreservierungen und Zuschläge zählen zur Grundlage, Freigabe ab
  60 Minuten. Fahrkarten ausländischer Bahnen (ÖBB, Nightjet, SNCF) an die ausgebende Bahn.

### 2.6 Wo nichts geht

| Fall | Warum |
|---|---|
| BahnBonus-Prämienfahrkarte | entschädigt nur in Punkten (BB K.3.1) — nichts für den Verein |
| Kind frei mitgefahren, Schwerbehinderte mit Freifahrt | Preis 0 €, 25 % von 0 |
| Schulträger-Zeitkarte in Schleswig-Holstein | nur der Schulträger darf beantragen |
| Bus, Tram, U-Bahn | keine Eisenbahn |
| KombiTicket, Rail&Fly (VGN) | ausgeschlossen |

### 2.7 Freiwillige Garantien

Nicht gesetzlich, aber Geld, ab 5 bis 30 Minuten und **mit Bus und Tram**: MVG München (5 € ab
20 Min., höchstens 4 im Monat), S-Bahn München (4 € ab 30 Min., nur MVV-Abos, nur an den Inhaber),
ÜSTRA Hannover (5 € ab 20 Min.), KVV (2,50 € ab 30 Min.), BRB (1 € ab 15 Min.), NVV (1 € ab 5 Min.,
nur bar am Schalter). Taxi-Garantien (NRW, VVS, VRN) zahlen nur gegen Quittung einer tatsächlich
genommenen Fahrt. Fristen drei bis vierzehn Tage, oft nur an den Inhaber, und **nie zusammen mit dem
gesetzlichen Anspruch für dasselbe Ereignis.** RMV-10-Minuten-, hvv- und NAH.SH-Garantie gibt es
nicht mehr.

Das Modell bekommt einen Platz dafür (§5.2), die App vorerst nicht: kurze Fristen, Zahlung nur an
den Inhaber, und jede Garantie verdrängt den gesetzlichen Anspruch. Das wäre ein eigenes Issue.

## 3. Was sich gegenüber docs/02–04 und dem ersten Entwurf ändert

- Frist: nicht drei Monate, sondern ein Jahr (§1). Der Code verfällt Fälle zu früh.
- Das „Zeitkarten-Feld" gibt es nur auf dem DB-Papierformular, nicht auf dem EU-Formular (§1).
- „Reise nicht angetreten" ist der Weg zur Erstattung, nicht zur Entschädigung.
- Länder-Tickets: geklärt, Zeitkarten-Regel (§2.3).
- Die 20-Minuten-Summe gilt für Deutschlandtarif und DB-Fernverkehrszeitkarten, **nicht** für die
  meisten Verbund-Zeitkarten. Eine Verbund-Monatskarte muss also wissen, welcher Verbund.
- RheinRuhrBahn nimmt Anträge selbst an (Transdev Neubrandenburg), nicht über das Servicecenter.
  NordWestBahn, BRB, MRB, VIAS, MittelrheinBahn und FlixTrain direkt. Die Teilnehmerliste des
  Servicecenters ist vom 1. Mai 2025.

## 4. Was der Code heute falsch macht

Stand `main` 4597f14:

1. Zeitkarten zählen erst ab 60 Minuten, je Fall; kein Minuten-Topf.
2. BahnCard 100 ist „Andere Zeitkarte" und bringt 1,50 € oder 5 € statt 10 €.
3. Der Satz folgt dem Zug (`Fern` → 5 €), nicht der Fahrkarte.
4. Der Deckel gilt nur fürs D-Ticket, mit fest 63 €; keine Fahrkarte hat einen Preis.
5. Einzelfahrkarten rechnen mit erfundenen 39,90 € (`DEFAULT_FARE_CENTS`).
6. Erste Klasse existiert in der Datenbank, wird aber nie gesetzt und nie gedruckt.
7. Das PDF liest die Fahrkarte vom Kunden statt vom Fall (`pdf.rs:101`).
8. Eine Reise hat genau eine Fahrkarte; D-Ticket plus Sparpreis geht nicht.
9. Ein Topf mischt Fahrkarten: eine Einzelfahrkarte macht das ganze Bündel eines Desks „bereit".
10. Die Frist ist drei Monate ab der Fahrt statt zwölf.
11. Ein Ausfall geht mit pauschal 60 Minuten in den Antrag.
12. Die Fahrkarte lässt sich im Antrag nicht ändern; ein Nachtrag fragt nicht.

## 5. Das Datenmodell

### 5.1 Drei Ebenen

```
Tarif ──< Produkt ──< Regelstand          (Katalog: was die Bahn verspricht, versioniert)
                         │
Kunde ──< Fahrkarte ─────┘                (was ein Mensch hat: ein Vertrag)
             │
Reise ──< Abschnitt der Fahrkarte ──< Fall (die Verspätung am Ziel dieser Fahrkarte)
                                        │
                              Topf = (Fahrkarte, Fenster, Desk)  →  Antrag
```

- **Der Katalog** sagt, was gilt. Er ändert sich, wenn ein Tarif sich ändert, nicht, wenn wir
  programmieren.
- **Die Fahrkarte** ist ein Vertrag im Sinne von §1: das D-Ticket-Abo, die BahnCard 100, die
  Monatskarte, der eine Sparpreis. Auch Einzelfahrkarten sind Fahrkarten, nur mit einer Reise.
- **Der Fall** gehört zu genau einer Fahrkarte und misst an deren Ziel.
- **Der Topf** wird nie gespeichert, er wird gerechnet. Ein Antrag ist ein eingefrorener Topf.

### 5.2 Der Katalog: Tarif, Produkt, Regelstand

Ein **Tarif** ist, wessen Bedingungen gelten: `db` (BB Personenverkehr), `deutschlandtarif`,
`spnv_standard` (der gemeinsame Mustertext), `vrr_nrw`, `hvv`, `mvv`, `vbb`, `rmv`,
`niedersachsen`, `sh`, …, `flixtrain`, `interrail`, `eu_minimum`. Tarife **erben**: `vbb` erbt von
`spnv_standard`, das von `eu_minimum`, und setzt nur, was abweicht. Ein neuer Verbund ist eine
Zeile mit drei Abweichungen.

Ein **Produkt** gehört zu einem Tarif: `deutschlandticket`, `deutschlandticket_job`,
`deutschlandsemesterticket`, `dt_zeitkarte`, `verbund_zeitkarte`, `verbund_tageskarte`,
`laender_ticket`, `quer_durchs_land`, `bahncard100`, `streckenzeitkarte_fern`,
`ic_semesterticket`, `einzel_db`, `einzel_dt`, `einzel_verbund`, `einzel_flixtrain`,
`einzel_international`, `interrail`, `german_rail_pass`, `praemie_db`, `fahrradtageskarte`.

Ein **Regelstand** ist die Regel eines Produkts ab einem Datum (`valid_from`). Preis 2027,
Rundungsänderung 11/2026, eine neue Frist: ein neuer Regelstand. Jeder Fall rechnet mit dem
Regelstand seines Fahrtdatums, jeder Antrag speichert, mit welchem er gerechnet wurde.

Die Regel, als Rust-Typen — der Code kennt die **Arten** von Regeln, die Daten die **Werte**:

```rust
/// Everything a product promises, from one date on. Fields left out inherit from the tariff.
pub struct Rule {
    pub valid_on: ValidOn,               // which trains the ticket can be delayed on
    pub compensation: Compensation,
    pub window: Window,                  // what is summed, capped and thresholded together
    pub min_cases: Option<u32>,          // NRW: 3; IC/EC-Semesterticket: 3 per month
    pub caps: Vec<Cap>,                  // all apply; the smallest wins
    pub payout_min: Threshold,           // 4 € and how it is compared
    pub rounding: Rounding,
    pub submit: Submit,                  // when a pot may leave the house
    pub deadline: Deadline,
    pub payout: Payout,                  // money, points, cash at a counter
    pub claimant: Claimant,              // who may ask: the passenger, only the holder, a school authority
    pub desk: DeskRule,                  // the operator of the late train, or a fixed desk (RMV, FlixTrain)
    pub reduced_fare: bool,              // "erheblich ermäßigt": no switching to a higher train
    pub release_after_min: Option<u32>,  // Zugbindung released: 20 (DB), 60 (international), None
    pub form: FormNeeds,                 // what the claim must carry
    pub sources: Vec<Source>,            // every value above with its source and grade
}

pub enum ValidOn {
    Classes { regional: bool, long_distance: bool, extra_routes: Vec<RouteId> }, // D-Ticket on IC Bremen–Norddeich
    Operator(OperatorId),                                                          // FlixTrain on FlixTrain
    BookedConnection,                                                              // a single ticket: its own trains
}

pub enum Compensation {
    /// Single tickets: a share of the price paid, stepped by minutes: [(60, 25 %), (120, 50 %)].
    ShareOfPrice { steps: Vec<(u32, BasisPoints)> },
    /// A fixed sum per case, stepped by minutes and class: BahnCard 100, Verbund-Zeitkarte, Interrail.
    PerCase { steps: Vec<(u32, ByClass<Cents>)> },
    /// Delays from `counts_from` are added up; each full `unit` minutes earns `per_unit`.
    MinutePool { counts_from: u32, unit: u32, per_unit: ByClass<Cents> },
    /// Paid in something that cannot reach the Verein (BahnBonus points).
    NotMoney,
    /// Adds to another ticket's claim (Fahrradtageskarte: 0,40 € per case).
    AddOn { per_case: Cents, to: ProductFamily },
}

pub enum Window { Ticket, ValidityDay, Validity, CalendarMonth, Semester, Subscription }
pub struct Cap { pub limit: CapLimit, pub per: Window }       // 25 % of the price, per month
pub enum CapLimit { ShareOfPrice(BasisPoints), Fixed(Cents) } // HVV Semesterticket: 4,50 €
pub struct Threshold { pub cents: Cents, pub inclusive: bool } // DB: ≥ 4,00; DT-C, Flix: > 4,00
pub enum Rounding { Cent, UpTo5Cents }
pub enum Submit { Immediately, AfterWindow, WhenPayable }
pub struct Deadline { pub from: DeadlineFrom, pub months: u32, pub aim_months: u32 }
pub enum DeadlineFrom { Ride, ValidityEnd, PassEnd }
pub enum Payout { Money, Points, CashInPerson }
pub enum Claimant { Passenger, HolderOnly, SchoolAuthority }
pub struct FormNeeds { pub season_box: bool, pub number: NumberKind, pub price_proof: bool,
                       pub copy: bool, pub birth_date: bool }
pub struct Source { pub field: String, pub doc: String, pub quote: String, pub grade: Grade }
pub enum Grade { Verified, Secondary, Inferred, Unknown }
```

Ein Produkt, bei dem ein Wert `Unknown` ist, wird der App mit einem Hinweis gezeigt oder gar nicht
(`offer: Offered | WithCaveat(text) | Hidden`) — „keine Zusage, die der Code nicht hält" als
Datenfeld.

Freiwillige Garantien bekommen später einen eigenen Typ (`Guarantee`: Auslöser in Minuten ab
Abfahrt oder Ankunft, Verkehrsmittel mit Bus, Leistung fest/Taxi bis/Ersatzticket, Grenzen je Tag
und Monat, Frist in Tagen, schließt den gesetzlichen Anspruch aus). Er hängt am Tarif, nicht am
Produkt.

**Wo der Katalog liegt.** Als TOML im Repo (`backend/fares/*.toml`, eine Datei je Tarif), in den
Build eingebettet und beim Start in die Datenbank gespiegelt, wie die Fixtures. Eine Regeländerung
ist damit ein Commit mit Review und Tests, kein Klick in Stellwerk; Stellwerk zeigt nur an
(`stellwerk fares list | show <product>`). Der Preis des D-Tickets 2027 ist eine Zeile:

```toml
[tariff.deutschlandtarif]
extends = "eu_minimum"
rounding = "up_to_5_cents"
payout_min = { cents = 400, inclusive = false }                      # DT-C 8.1 "überschreitet"

[product.deutschlandticket]
tariff = "deutschlandtarif"
name = "Deutschlandticket"
valid_on = { regional = true, long_distance = false, extra_routes = ["ic-bremen-norddeich", "ic-stuttgart-singen"] }
compensation = { minute_pool = { counts_from = 20, unit = 60, per_unit = { second = 150, first = 225 } } }
window = "subscription"                                             # §9 Frage 1
caps = [{ share = 2500, per = "calendar_month" }]
submit = "when_payable"
reduced_fare = true
form = { season_box = true, number = "abo", price_proof = true, copy = true }

[[product.deutschlandticket.price]]
valid_from = 2025-01-01
cents = 5800
[[product.deutschlandticket.price]]
valid_from = 2026-01-01
cents = 6300

[[product.deutschlandticket.source]]
field = "compensation"
doc = "DT-C 8.1, Stand 14.12.2025"
quote = "…können auch wiederholte Verspätungsfälle ab 20 Minuten innerhalb der Geltungsdauer der Zeitkarte zusammenrechnen…"
grade = "verified"
```

### 5.3 Die Fahrkarte des Kunden

```sql
create table tickets (
    id              uuid primary key,
    customer_id     uuid not null references customers(id) on delete cascade,
    product         text not null,          -- a catalogue product id
    first_class     boolean not null default false,
    label           text,                   -- "Monatskarte VRS Köln–Bonn"
    number          text,                   -- Abo, Zeitkarte, BahnCard or booking number (EU form 3.2.7)
    booking_ref     text,                   -- Auftragsnummer: tickets sharing one are one contract
    birth_date      date,                   -- BahnCard 100 only (DB form)
    price_cents     bigint,                 -- what was paid, per price_per; null = not known yet
    price_per       text,                   -- 'month' | 'validity' | 'ticket' | 'direction'
    valid_from      date,
    valid_until     date,                   -- null = open-ended subscription
    origin          text,                   -- single tickets and Streckenzeitkarten: station ids (vs:…)
    destination     text,
    created_at      timestamptz not null default now(),
    archived_at     timestamptz             -- a ticket someone no longer has; its cases stay
);
```

- Das D-Ticket-Abo ist **eine** Zeile, die Jahre hält; eine Monatskarte eine Zeile je Monat (die
  App bietet „nächsten Monat verlängern" an); ein Sparpreis eine Zeile je Richtung.
- `price_cents` ist, was der Mensch gezahlt hat. Leer heißt: keine Zahl im Antrag und keine im
  Satz, bis er es einträgt. Vorgabe aus dem Katalog nur, wo der Preis feststeht (D-Ticket 63 €).
- Ein Beleg (Foto, Preisnachweis) hängt an der Fahrkarte, nicht am Antrag: `ticket_uploads
  (ticket_id, upload_id, kind, month)`. Das D-Ticket-Foto für September gilt für jeden Antrag mit
  Septemberfällen.

### 5.4 Reise, Abschnitt, Fall

```sql
create table journey_tickets (
    journey_id  uuid not null references journeys(id) on delete cascade,
    ticket_id   uuid not null references tickets(id),
    first_leg   int  not null,              -- which legs of the itinerary this ticket covers
    last_leg    int  not null,
    primary key (journey_id, ticket_id)
);

alter table incidents
    add column ticket_id      uuid references tickets(id),
    add column first_class    boolean,
    add column arrival_delay  integer,      -- at this ticket's destination, what goes on the form
    add column rule_from      date;         -- the Regelstand it was computed with
```

- Eine Reise mit D-Ticket bis Köln und Sparpreis ab Köln hat zwei Zeilen und kann zwei Fälle haben,
  jeder an seinem Ziel. In der App ist das zunächst **eine** Fahrkarte je Reise (der häufige Fall);
  das Modell trägt beide.
- Ein Fall entsteht, sobald die Verspätung am Ziel seiner Fahrkarte die **kleinste Schwelle des
  Produkts** erreicht (20 Minuten im Minuten-Topf, 60 sonst) — also nicht mehr pauschal ab 60.
- `amount_cents` bleibt als Zwischenspeicher für alte Builds und Anzeigen, ist aber nicht mehr
  die Wahrheit: was ein Fall wert ist, sagt sein Topf.
- `ticket` (das alte Enum) bleibt und wird aus dem Produkt abgeleitet.

### 5.5 Der Topf und die Rechnung

Ein Topf ist `(ticket_id, window_key, desk)`. `window_key` kommt aus der Regel: `ticket` für eine
Einzelfahrkarte, `2026-09` für einen Kalendermonat, `abo` für ein ganzes Abo, das Datum für eine
Tageskarte. Die Rechnung ist **eine reine Funktion** ohne Datenbank:

```rust
pub fn evaluate(rule: &Rule, ticket: &Ticket, cases: &[Case], today: NaiveDate) -> Pot;

pub struct Pot {
    pub counted: Vec<CaseShare>,   // per case: minutes counted, cents it brings, why (not) counted
    pub minutes: i64,              // minute pools: the sum, and how far to the next full unit
    pub gross: Cents,
    pub capped_by: Option<Cap>,
    pub amount: Cents,             // after caps and rounding
    pub payable: bool,             // threshold, min_cases, submit window all met
    pub ready_from: Option<NaiveDate>,
    pub deadline: NaiveDate,       // the earliest case's hard limit
    pub aim: NaiveDate,            // three months: "reich ein, solange es frisch ist"
    pub blockers: Vec<Blocker>,    // PriceMissing, BelowMinimum{missing}, WindowOpen{until}, NotMoney, …
}
```

`bundle_ready`, `apply_monthly_cap`, `claim_amount_cents` und `flat_claim_cents` werden zu
Aufrufen dieser Funktion. `Blocker` ist das, was die App als Satz zeigt („Noch 40 Minuten bis zur
nächsten vollen Stunde", „Trag den Fahrpreis ein") — der Server liefert Art und Zahl, die App den
Satz.

Beispiele, die als Tests in `fares.rs` gehören:

| Fahrkarte | Fälle | Ergebnis |
|---|---|---|
| D-Ticket 2. Kl., 63 € | 6 × 30 Min. | 180 Min. → 3 × 1,50 = 4,50 €, zahlbar |
| D-Ticket | 70, 45, 25 Min. | 140 Min. → 2 × 1,50 = 3,00 €, nicht zahlbar, „noch 40 Min." |
| D-Ticket | 14 × 60 Min. in einem Monat | 21,00 € → Deckel 15,75 € (oder 15,00 €, wenn die Bahn auf volle Stunden kürzt — offen) |
| VRS-Monatskarte | 2 × 70 Min. | 3,00 €, unter 3 Fällen → nicht zahlbar |
| VRS-Monatskarte | 3 × 65 Min. | 4,50 €, nach Monatsende |
| BahnCard 100 2. Kl. | 1 × 61 Min. | 10 €, sofort |
| BahnCard 100 | 50 + 50 Min. | 0 € (nie addiert) |
| Sparpreis 39,90 € | 125 Min. | 19,95 €, sofort |
| Super Sparpreis 12,99 € | 75 Min. | 3,25 € → unter 4 €, nichts |
| Deutschlandtarif-Einzel 17,30 € | 62 Min. | 4,325 € → auf 5 Ct. auf 4,35 € |
| FlixTrain 16,00 € | 60 Min. | 4,00 € → nicht „höher als 4 €", nichts |
| Interrail | 130 Min. | 24 € |
| Länder-Ticket | 2 × 90 Min. an einem Tag | 180 Min. → 4,50 € |

### 5.6 Antrag

`claims` bekommt `ticket_id`, `window_key`, `rule_from` und `breakdown jsonb` (der `Pot` zum
Zeitpunkt des Einreichens). `ticket_months` bleibt für alte Builds. Ein Antrag ist ein Topf; das
PDF liest Produkt, Klasse, Nummer, Preis und die Fallliste mit Minuten aus dem Topf, nie vom
Kunden, und schreibt Klasse und Fahrkartenart in den Freitext (das EU-Formular hat kein Feld
dafür).

## 6. Auf dem Draht

Nur hinzufügen (Hausregel):

- `GET /v1/fares` — der Katalog für die App: Id, Name, Familie, eine Zeile Regel, gilt in
  (Nah/Fern), welche Felder, `offer` samt Hinweis. Die App kennt keinen Satz und keine Schwelle.
- `GET/POST/PATCH /v1/me/tickets` — die Fahrkarten.
- `POST /v1/journeys` nimmt `tickets: [{ticket_id | new_ticket, first_leg, last_leg}]`; ohne das
  Feld (alter Build) nimmt der Server `ticket` wie heute und legt die passende Fahrkarte an
  (`zeitkarte` → Verbund-Zeitkarte mit „Produkt unbestimmt", aufzulösen im Antrag).
- `PATCH /v1/incidents/{id}` mit `ticket_id` — die Fahrkarte eines Falls ändern, bis er eingereicht
  ist. Der Server sortiert ihn in den Topf, in den er jetzt gehört.
- Fall und Antrag bekommen `ticket_id` und `pot` (Minuten, Betrag, zahlbar, `blockers`,
  `ready_from`, `aim`, `deadline`). `ticket`, `amount_cents`, `ticket_months`,
  `flat_claim_cents` bleiben mit ihrer alten Bedeutung.

## 7. In der App

**Einchecken** (`welcher_zug_screen.dart`): statt dreier Typen „Deine Fahrkarten", die zuletzt
benutzte vorgewählt, darunter „Einzelfahrkarte" und „Fahrkarte hinzufügen". Was im Zug nicht gilt,
ist ausgegraut mit Grund („Das Deutschlandticket gilt nicht im ICE."), aus `valid_on`. Darunter
eine Zeile aus dem Katalog, was die Fahrkarte bringt. Einzelfahrkarte: Fahrpreis optional hier,
Pflicht vor dem Antrag.

**Fahrkarte hinzufügen:** erst die Familie (Deutschlandticket · BahnCard 100 · Monats-/Jahreskarte ·
Streckenzeitkarte ICE/IC · Länder-Ticket), dann nur, was das Produkt braucht — für eine
Monatskarte der Verbund (aus einer Liste; „weiß ich nicht" → `spnv_standard`), Klasse, Preis,
Geltungsdauer.

**Unterwegs:** die Rechte aus §1 nach `reduced_fare` und `release_after_min` — bei 20 Minuten mit
Sparpreis „Zugbindung aufgehoben", mit D-Ticket „zählt ab jetzt mit".

**Antrag:** erster Schritt „Fahrkarte" — mit welcher Fahrkarte die Fälle gefahren sind, Ändern je
Fall, und die Felder, die das Produkt braucht (Nummer, Klasse, Preis, Preisnachweis, bei der
BahnCard 100 Geburtsdatum statt Foto). Ein Topf, der noch nicht zahlbar ist, zeigt, was fehlt.

## 8. Bestehende Daten

- `customers.ticket = deutschlandticket` → eine D-Ticket-Fahrkarte mit `ticket_number` und 63 €;
  `zeitkarte` → eine Verbund-Zeitkarte „unbestimmt"; `einzelfahrkarte` → nichts, die Reisen bekommen
  je eine Einzelfahrkarte ohne Preis.
- Offene Fälle ziehen in Töpfe; eingereichte bleiben, wie sie sind (docs/23 §2).
- Die erfundenen 39,90 € verschwinden; der Fall fragt nach dem Preis.
- Fristen werden neu gerechnet (zwölf Monate). Was nach drei Monaten `verfallen` wurde und noch in
  den zwölf liegt, wird wieder offen.
- Fahrten mit Zeitkarte und 20 bis 59 Minuten bekommen rückwirkend ihren Fall.
- Staging: Reset statt Migration (docs/46).

## 9. Offen

### Entschieden (Johannes, 30. September)

1. **D-Ticket über Monate:** Fälle werden über Monatsgrenzen zusammengerechnet, „basically
   unlimited for now" — das Fenster ist das Abo (`window = "subscription"`). Der Deckel bleibt je
   Monat.
2. **Die ersten Produkte:** D-Ticket, BahnCard 100, Monats-/Jahreskarte (Verbund wählbar),
   Streckenzeitkarte ICE/IC, Einzelfahrkarte (DB, Nahverkehr, FlixTrain), Länder-Ticket.
3. **Minuten statt Fälle** für Minuten-Töpfe: „Minuten gesammelt" und der Betrag daraus.
4. **Preis:** der Mensch trägt ein, was er zahlt. Bei Zeitkarten zählt der Preis nur für den
   Deckel — er ist dort optional und fehlt er, gilt der Deckel aus dem Katalogpreis (D-Ticket 63 €)
   oder gar keiner. Bei Einzelfahrkarten ist er der Betrag und Pflicht vor dem Antrag.

### Die Fragen, wie sie gestellt waren

1. **Das Fenster des D-Tickets.** Johannes hat am 30. September entschieden, dass Fälle über
   Monatsgrenzen zusammengehören („two consecutive delays on the last day of the month and the
   first of the following would never be claimable"). Dafür spricht: DT-C 8.2 verlangt das
   Sammeln je Zeitraum nur für Wochen- und Monatskarten, und das D-Ticket ist ein Abo „für
   unbestimmte Zeit" (DTX 1.3); die DB-FAQ sagt nur „mehrere Verspätungsfälle sammeln".
   **Dagegen** hat Bericht A gefunden: die Verbraucherzentrale („am Ende des Monats … gesammelt
   einreichen"), die monatsweise Erstattung und Kündigung (DTX 1.3, 1.7), und VRR deckelt
   ausdrücklich je Monat. Eine Primärquelle für eine der beiden Lesarten gibt es nicht. Im Modell
   ist das **eine Zeile** (`window = "subscription"` oder `"calendar_month"`). Vorschlag: so wie
   entschieden, und der erste Antrag mit Monatswechsel klärt es; lehnt die Bahn den Teil des
   Vormonats ab, stellen wir um.
2. **Welche Produkte die App zuerst anbietet.** Vorschlag: D-Ticket, BahnCard 100,
   Monats-/Jahreskarte (Verbund wählbar), Streckenzeitkarte ICE/IC, Einzelfahrkarte (DB, Nahverkehr,
   FlixTrain), Länder-Ticket. Später: Pässe, Semestertickets, internationale Fahrkarten, Garantien.
3. **Minuten und Fälle in der App.** Für Minuten-Töpfe verschwindet der „Fall ab 60" aus der
   Sprache; es gibt „Minuten gesammelt" und den Betrag daraus (docs/47 passt dazu). Für
   Verbund-Monatskarten und die BahnCard 100 bleibt der Fall.
4. **Preis bei Jobticket und bezuschussten Tickets.** Vorschlag: der Mensch trägt ein, was er
   zahlt; der Antrag nennt diesen Preis.

### Für die Bahn (Hotline 030 586020920 oder die ersten Testanträge)

1. Zahlt das Servicecenter an ein Konto, dessen Inhaber der Verein ist (EU-Formular 5.5.4)?
2. Nimmt es eine Fallliste im Freitext mit Zeitkarten-Kreuz an, und gilt die 4-€-Grenze je Antrag
   oder je Bahn im Antrag?
3. Rechnet es D-Ticket-Minuten über Monatsgrenzen zusammen, und deckelt es je Monat?
4. Welcher Preisnachweis genügt fürs D-Ticket im Abo?
5. BahnCard 100 im Regionalzug: 10 € oder die Regeln des beigelegten D-Tickets (C.3.1.1.1 gegen
   C.3.10.3)?
6. Zahlt es für Verspätungen im Schienenersatzverkehr?

## 10. Schnitte

1. **Katalog und Rechnung**: `backend/fares/*.toml`, `fares.rs` mit `Rule`, `evaluate` und den
   Tests aus §5.5; die heutigen vier Funktionen in `rules.rs` rufen sie auf. Sichtbar nur: BahnCard
   100 = 10 €, Frist zwölf Monate.
2. **Fahrkarten**: `tickets`, `journey_tickets`, Migration aus `customers.ticket`,
   `GET /v1/fares`, `/v1/me/tickets`; PDF liest vom Fall.
3. **Töpfe**: Fälle ab 20 Minuten, `Pot` auf Fall und Antrag, Anträge je Topf.
4. **Einchecken**: Deine Fahrkarten, Fahrkarte hinzufügen, Fahrpreis.
5. **Antrag**: Schritt Fahrkarte, Ändern je Fall, Belege an der Fahrkarte.
6. **Unterwegs**: die Rechte nach Fahrkarte.

Mit Schnitt 3 werden die Rechtstexte (`app/lib/content/legal.dart`), die Website und docs/02
neu geschrieben, wo sie „1,50 € ab 60 Minuten" sagen.
