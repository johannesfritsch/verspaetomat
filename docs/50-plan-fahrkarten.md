# 50 — Plan: Fahrkarten, Töpfe, und was sich in App und Backend ändert

Plan zu Issue #66, 30. September 2026. Grundlage ist docs/49 (Recherche, Datenmodell, Johannes'
Entscheidungen vom 30. September: D-Ticket über Monate ohne Grenze, die sechs ersten Produkte,
Minuten statt Fälle, Preis nur für den Deckel). Die Fundstellen unten stammen aus einer
Bestandsaufnahme des Codes am Stand 4597f14.

Die Reihenfolge folgt den Hausregeln: alles auf dem Draht nur hinzufügen, der Server steht vor
dem Build, der ihn braucht, jede Phase einzeln auf Staging.

## Überblick

| Phase | Was | Wo | Sichtbar für Menschen |
|---|---|---|---|
| 1 | Katalog und Rechnung | Backend | Frist zwölf statt drei Monate |
| 2 | Fahrkarten, Töpfe, neue Endpunkte | Backend | nichts (alte App läuft unverändert) |
| 3 | Deine Fahrkarten, Einchecken, Nachtrag | App | Fahrkarten statt Tickettyp |
| 4 | Anträge je Topf, Antrag mit Schritt „Fahrkarte" | App | Minuten-Töpfe, Fahrkarte ändern |
| 5 | Unterwegs, Ankunft, Texte, Website | App, Site | Rechte je Fahrkarte, neue Bilder |

Phase 1 und 2 können zusammen auf Staging, 3 bis 5 zusammen als ein TestFlight-Build, wenn das
schneller ist — getrennt sind sie, damit jede für sich prüfbar ist.

---

## Phase 1 — Katalog und Rechnung (Backend)

**Neu**

- `backend/fixtures/fares.toml` — der Katalog aus docs/49 §5.2: Tarife (`eu_minimum`, `db`,
  `deutschlandtarif`, `spnv_standard`, `vrr_nrw`, `hvv`, `mvv`, `vbb`, `rmv`, `niedersachsen`,
  `sh`, `flixtrain`) und die sechs Produktfamilien der ersten Runde:
  `deutschlandticket`, `bahncard100`, `verbund_zeitkarte` (Verbund = Tarif), `streckenzeitkarte_fern`,
  `einzel_db` / `einzel_nah` / `einzel_flixtrain`, `laender_ticket`. Jeder Wert mit Quelle und
  Einstufung. `toml` ist schon Abhängigkeit (Cargo.toml:29).
- `backend/src/fares/mod.rs` — die Typen (`Rule`, `Compensation`, `Window`, `Cap`, …), das Laden
  aus `include_str!` wie `src/fixtures.rs`, die Vererbung Tarif → Produkt, die Auswahl des
  Regelstands nach Datum. Beim Laden prüfen: jede Regel vollständig, jede Quelle da, sonst
  startet der Server nicht.
- `backend/src/fares/evaluate.rs` — `evaluate(rule, ticket, cases, today) -> Pot`, rein, ohne
  Datenbank. Dazu die **Zuteilung**: der Betrag eines Topfs wird auf seine Fälle verteilt
  (nach Minuten, größter Rest), damit jeder Fall weiter ein `amount_cents` hat, dessen Summe der
  Topf ist. Das brauchen alte Builds, `reply.rs` (Obergrenze je Fahrt) und die Mitteilungen.
- Tests: die dreizehn Beispiele aus docs/49 §5.5, dazu Deckel über Monatsgrenzen (Abo-Topf,
  Deckel je Kalendermonat der Fahrt), Rundung auf 5 Cent, `inclusive` am Rand 4,00 €, Regelstand
  am Tag des Preiswechsels.

**Geändert**

- `rules.rs:17,88-90` `legal_deadline`: zwölf Monate nach der Fahrt; neu `aim_date` (drei Monate).
  `WARN_DAYS_BEFORE_DEADLINE` warnt vor dem Ziel, nicht vor der harten Frist
  (`scanner.rs:70-95`). Migration: `incidents.legal_deadline` neu rechnen; `verfallen`, das in
  den zwölf Monaten liegt und nie eingereicht war, wird wieder `gesammelt` (mit Audit-Eintrag).
- `rules.rs:23-72` `claim_amount_cents` und `flat_claim_cents` rufen den Katalog für die drei
  alten Typen auf (Abbildung: `deutschlandticket` → Produkt `deutschlandticket`, `zeitkarte` →
  `verbund_zeitkarte`/`spnv_standard` bzw. `streckenzeitkarte_fern` wie heute nach Kategorie,
  `einzelfahrkarte` → `einzel_db`). Bis Phase 2 ändert das keinen Betrag.
- `stellwerk fares list | show <product>` (Muster `stellwerk ngo`, stellwerk.rs:618).

**Fertig, wenn** `cargo test` und `clippy` sauber sind und die alten Tests in `rules.rs`
(`amounts` :253, `monthly_cap` :383, …) unverändert durchlaufen — außer `deadline` :290.

---

## Phase 2 — Fahrkarten und Töpfe (Backend)

### Datenbank

- **`0044_tickets.sql`**: `tickets`, `journey_tickets`, `ticket_uploads` (docs/49 §5.3–5.4), alle
  mit `on delete cascade` an `customers` (sonst bleiben sie beim Löschen stehen, `account.rs:33-67`
  und `admin.rs:739-750`); `incidents` + `ticket_id`, `first_class`, `arrival_delay`, `rule_from`,
  `window_key`; `claims` + `ticket_id`, `window_key`, `rule_from`, `breakdown jsonb`.
- **`0045_tickets_from_customers.sql`**: je Kunde eine Fahrkarte aus `customers.ticket`
  (`deutschlandticket` → D-Ticket mit `ticket_number` und 63 €; `zeitkarte` → Verbund-Zeitkarte
  mit `spnv_standard` und Merker `product_unsure`; `einzelfahrkarte` → keine), jede offene
  Reise und jeder offene Fall bekommt ihre `ticket_id`; Einzelfahrkarten-Fälle je eine eigene
  Fahrkarte ohne Preis (die 39,90 € fallen weg). Eingereichte Fälle bleiben, wie sie sind.

### Wo Fälle entstehen

- `journeys.rs:1419-1512` `create_journey_incident`: nicht mehr ein Fall je Reise, sondern **ein
  Fall je Fahrkarte der Reise** (`journey_tickets`), gemessen am Ziel des letzten Abschnitts
  dieser Fahrkarte. Schwelle ist die kleinste des Produkts (20 im Minuten-Topf, 60 sonst) statt
  `MIN_DELAY_MINUTES`. Die Kategorie (Fern oder nicht) bestimmt den Satz nicht mehr.
  Ein Ausfall geht mit seiner tatsächlichen Ankunftsverspätung hinein (docs/49 §1); die
  angerechneten 60 Minuten bleiben nur in `counted_minutes`.
- `journeys.rs:475-492` `create`: nimmt `tickets: [{ticket_id | new_ticket, first_leg,
  last_leg}]`. Fehlt das Feld (alter Build), macht der Server aus `ticket` wie heute eine
  Fahrkarte: die gespeicherte des Produkts, sonst eine neue. `insert_leg_ride` (:406, :423)
  schreibt weiter das alte `ticket` auf die Fahrten, abgeleitet.
- `handlers.rs:846-899` `on_ride_finalised` (einzelne Fahrt ohne Reise) und `:957-997` `nachtrag`:
  `nachtrag` nimmt `ticket_id` (optional; ohne: zuletzt benutzte Fahrkarte, dann wie heute).
- `admin.rs:894-1130` `backdate`: `--ticket <product>` legt bei Bedarf eine Fahrkarte an;
  `--delay` darf unter 60 liegen. `stellwerk ff`/`cancel` drucken den Topf statt
  „Kein Anspruch (unter 60 Minuten)" (stellwerk.rs:1205, :1782).

### Töpfe statt Desk-Bündel

- `rules.rs:151-222` `refresh_statuses`: gruppiert offene Fälle nach **(ticket_id, window_key,
  desk)**, ruft `evaluate`, schreibt `bereit`/`gesammelt`/`gedeckelt` und die zugeteilten
  `amount_cents`. `bundle_ready`, `apply_monthly_cap` und `draft_after_removal` werden dünne
  Hüllen darum und verschwinden, sobald nichts mehr sie ruft.
- `handlers.rs:1003-1044` `GET /v1/incidents`: `summary.pots: [{id, ticket_id, ticket_label,
  product, window_key, desk, minutes, next_unit_minutes, amount_cents, payable, blockers,
  ready_from, aim, deadline, incident_ids}]`. `summary.desks` bleibt mit derselben Bedeutung
  (Summe je Desk) für alte Builds; `flat_claim_cents` und `delay_minutes_threshold` bleiben, aus
  der zuletzt benutzten Fahrkarte.
- `handlers.rs:1216-1274` `claim_draft`: nimmt `pot` (neu) oder `desk` (alt; dann der erste
  zahlbare Topf dieses Desks — für einen D-Ticket-Kunden ist das derselbe Antrag wie heute).
  412 kommt mit dem `blocker` statt „bundle below the 4 € minimum". Ein Entwurf je Topf statt je
  Desk (`draft_action` :1193 und die Tests :2979-3002).
- `PATCH /v1/incidents/{id}` `{ticket_id}` — neu. Nur, solange kein nicht-Entwurf-Antrag den Fall
  hält (`delete_refusal`). Entwürfe, aus denen der Fall fällt, laufen durch dieselbe Regel wie
  beim Verwerfen (`draft_after_removal`, :1082).
- `GET /v1/fares`, `GET/POST/PATCH/DELETE /v1/me/tickets` — neu. Löschen heißt archivieren, wenn
  Fälle daran hängen.
- `handlers.rs:237,284,359,373,578-626` `/v1/me`: `settings.ticket` bleibt lesbar und schreibbar
  (alter Build) und bedeutet „Produkt der zuletzt benutzten Fahrkarte"; `personal_data.ticket_number`
  liest und schreibt die Nummer der D-Ticket-Fahrkarte. `first_class` wandert an die Fahrkarte.
- `handlers.rs:798`, `journeys.rs:272` `claim_from_minute`: aus dem Produkt der Reise (20 oder 60).

### Antrag, PDF, Mail

- `pdf.rs:94-176` `claim_inputs`: liest Produkt, Klasse, Nummer, Preis aus der Fahrkarte des
  Antrags. `kind` = `season` für Topf- und Fall-Produkte, `60`/`120` für Einzelfahrkarten.
- `templates/eu_form.typ`: 3.2.7 Nummer, 3.2.8 Preis; im Freitext (:74-91) Fahrkartenart und
  Klasse, bei Minuten-Töpfen je Fall die Minuten und die Summe („280 Minuten, 4 volle Stunden,
  je 1,50 €"). `pdf.rs:118` wird aus dem Katalog erzeugt statt fest.
- `handlers.rs:1487,1549` Mailtext „Zeitfahrkarte" nach Produkt.
- `claim_patch` (:1319-1387): Belege kommen aus `ticket_uploads` der Fahrkarte (je Monat beim
  D-Ticket, sonst einer), `ticket_months` wird weiter befüllt.
- `push.rs:230-235` „Anspruch entstanden": bei Minuten-Töpfen „68 Minuten gesammelt — zusammen
  4,50 € für {Verein}." bzw. „noch 38 Minuten bis zur nächsten vollen Stunde"; sonst wie heute.

### Tests und Verträge

- `api_tests.rs`: Helfer `ride` :75 und `incident` :99 bekommen eine Fahrkarte; neu: Topf über
  Monatsgrenze, Deckel je Monat, BahnCard 100 je Fall, Fall ändern (Entwurf schrumpft/geht),
  alter Build ohne `tickets` auf `POST /v1/journeys`, `claim_draft` mit `desk`.
- `pdf.rs` Tests :244, :367; `push.rs` :603-684.
- `openapi.yaml`: die neuen Endpunkte und Felder; :170 (Ledger) ist heute schon veraltet und wird
  dabei vollständig.
- **`deploy/compat.sh`** (die E2E des letzten Produktions-Builds gegen Staging) muss grün
  bleiben: sie wählt `ticket-deutschlandticket`, datiert viermal 70 Minuten zurück und erwartet
  „4 Fälle · 6,00 €" je Desk. Im Minuten-Topf sind das 280 Minuten = 4 volle Stunden = 6,00 € —
  derselbe Betrag, derselbe Desk. Das ist der Prüfstein für Phase 2.

---

## Phase 3 — Deine Fahrkarten, Einchecken, Nachtrag (App)

### Modelle und Repository

- `lib/api/models.dart`: neu `ApiFare` (Katalog: id, name, family, rule_line, valid_on, fields,
  offer, caveat), `ApiTicket` (Fahrkarte), `ApiPot`; `StartJourneyRequest.tickets`,
  `NachtragRequest.ticketId`, `ApiIncident.ticketId`, `ApiIncidentSummary.pots`,
  `ApiJourney.tickets`, `ApiJourneyLive.rights`. Alte Felder bleiben lesbar.
- `lib/api/client.dart`, `repo/app_repository.dart`, `repo/http_repository.dart`: `fares()`,
  `tickets()`, `saveTicket()`, `archiveTicket()`, `setIncidentTicket()`, `draftClaim(pot:)`.
- `lib/mock/mock_data.dart:7-20` `TicketType` und seine Regeltexte (`.rule`) verschwinden aus der
  Oberfläche; das Enum bleibt nur für den alten Draht. Die Sätze kommen aus `ApiFare.ruleLine`.
- **Demo-Modus** (`mock_repository.dart`, `demo_state.dart`, `mock_data.dart`): bekommt einen
  Katalog als Datei `app/assets/demo/fares.json`, erzeugt vom Server
  (`stellwerk fares export > …`), damit die Demo keine eigene Kopie der Regeln pflegt, und eine
  kleine Topf-Rechnung für die drei Arten. `claimAmountFor` (demo_state.dart:8-18) und die
  4-€-Bündel je Desk (:611-636) gehen. Die Demo-Fälle (mock_data.dart:500-680) bekommen eine
  D-Ticket-Fahrkarte mit gemischten Verspätungen (auch 25 und 40 Minuten), eine BahnCard 100 und
  einen Sparpreis mit Preis.

### Screen: „Deine Fahrkarten" (neu) — Einstellungen → Fahrkarten

Ersetzt die Zeile „Ticket" (`einstellungen_screen.dart:51-56`) und den Picker `_pickTicket`
(:273-305). Standardkopf: Eyebrow „Einstellungen", Titel „Deine Fahrkarten".

- Eine Zeile je Fahrkarte: Name („Deutschlandticket", „Monatskarte VRS"), darunter die Regelzeile
  aus dem Katalog und, falls nötig, was fehlt („Preis fehlt — zählt nur für die Obergrenze").
- „Fahrkarte hinzufügen" → **Screen „Welche Fahrkarte?"**: die sechs Familien als
  `VChoiceCard` mit der Regelzeile. Dann **Screen „Deine <Fahrkarte>"** mit genau den Feldern des
  Produkts (`ApiFare.fields`): Nummer, Klasse, Preis (bei Zeitkarten „Optional — nur für die
  Obergrenze", D4), bei Monatskarte der Verbund (Liste, „weiß ich nicht"), bei der BahnCard 100
  das Geburtsdatum, bei Streckenzeitkarten Von/Nach (Bahnhofssuche wie beim Einchecken).
- Antippen einer Fahrkarte öffnet denselben Screen zum Ändern; „Nicht mehr in Gebrauch"
  archiviert.
- Die „Deutschlandticket-Nummer" in den persönlichen Daten (`einstellungen_screen.dart:378-409`,
  :139) geht in die Fahrkarte. Der Löschtext (:444) nennt die Fahrkarten.

### Screen: Fahrkarten-Auswahl beim Einchecken (`welcher_zug_screen.dart:410-560`)

Heute drei feste Karten (`TicketType.values`, :524-534) mit Vorwahl aus der Einstellung.

- **Titel** bleibt „Fahrkarte auswählen". Oben die gespeicherten Fahrkarten, die zuletzt benutzte
  vorgewählt; darunter „Einzelfahrkarte" und „Andere Fahrkarte".
- **Was im Zug nicht gilt**, ist ausgegraut mit Grund aus `valid_on` („Das Deutschlandticket gilt
  nicht im ICE.") — ersetzt `_allowed` (:444-446), das nur `fern` kannte.
- **Einzelfahrkarte** klappt zwei Felder auf: Fahrpreis (optional, „kannst du später
  eintragen"), Klasse. Das legt eine Fahrkarte für diese Reise an.
- **Andere Fahrkarte** führt in „Welche Fahrkarte?" (oben) und kommt mit der neuen Fahrkarte
  zurück.
- **Erste Fahrt** (keine Fahrkarte gespeichert): die Liste zeigt direkt die Familien.
- Unter der Auswahl die Regelzeile der gewählten Fahrkarte.
- Keys für die E2E: `ticket-<id>` für gespeicherte, `fare-<product>` für neue.
- Weiterfahrt (`unterwegs_screen.dart:137-141`) und Zugwechsel (`change_train_sheet.dart:119`)
  erben die Fahrkarten der Reise wie heute. Zwei Fahrkarten auf einer Reise bietet die App in
  dieser Runde nicht an (das Modell kann es).

### Screen: Nachtrag (`nachtrag_screen.dart:99-110`)

Bekommt dieselbe Fahrkarten-Auswahl als Zeile „Fahrkarte" mit der zuletzt benutzten
vorgewählt. Heute nimmt der Server die Einstellung.

### Onboarding

Keine neue Frage. `fertig_screen.dart:47` „Ab 60 Minuten zahlt die Bahn an deinen Verein" wird
„Die Bahn zahlt an deinen Verein — ab wann, hängt von deiner Fahrkarte ab." (oder aus dem
Katalog, sobald eine Fahrkarte da ist). Die erste Fahrkarte entsteht beim ersten Einchecken.

---

## Phase 4 — Anträge je Topf, Antrag mit Fahrkarte (App)

### Screen: Anträge (`antraege_screen.dart`)

Heute Karten je Desk (`summary.desks`, :189, :215-233), Text „Ansprüche werden pro
Bahnunternehmen gebündelt. Jedes Bündel muss 4 € erreichen." (:276-279).

- Eine Karte je **Topf** (`summary.pots`). Titel ist die Fahrkarte („Deutschlandticket"), die
  Stelle steht darunter („an Servicecenter Fahrgastrechte").
- **Minuten-Topf** (D3): große Zahl „280 Minuten gesammelt", darunter „4 volle Stunden · 6,00 €",
  der Fortschritt bis zur nächsten vollen Stunde, nicht bis 4 €. Nicht zahlbar: „Noch 38 Minuten,
  dann sind es 4,50 € — ab da geht der Antrag raus." Gedeckelt: „Für September ist die Obergrenze
  erreicht (15,75 €). Die Minuten zählen weiter."
- **Fall-Topf** (BahnCard 100, Verbund-Monatskarte): „3 Fälle · 4,50 €"; bei NRW „Mindestens drei
  Fälle"; bei der Monatskarte „Geht nach Monatsende raus".
- **Einzelfahrkarte**: eine Karte je Fahrkarte, „25 % von 39,90 € = 9,98 €", ohne Preis
  „Trag den Fahrpreis ein, dann rechnen wir" mit Knopf.
- Die `blockers` des Servers sind die Sätze; die App rechnet nichts.
- `_CollectingCard` (:411-540), `_EmptyCollecting` (:789), `_ExpiredCard` (:812), `EmptyAntraege`
  (:542-665), der Fußtext (:276) werden danach neu geschrieben; `_ClaimCard` (eingereichte
  Anträge) bleibt.
- Die Frist-Zeile (`_DeadlineLine` :822-845) zeigt das Ziel (drei Monate) und nennt die harte
  Frist erst, wenn sie näher ist.

### Screen: Fall-Details (`claims_widgets.dart:329-430` `showEvidenceSheet`)

„Ticket" (:372) zeigt die Fahrkarte und bekommt **„Fahrkarte ändern"** (solange nicht
eingereicht) → dieselbe Auswahl wie beim Einchecken → `setIncidentTicket`. Danach sagt ein
Hinweis, in welchen Topf der Fall gewandert ist. Bei Minuten-Töpfen zeigt die Zeile „Anspruch"
„68 Minuten für den Topf" statt eines Betrags.

### Screen: Antrag (`antrag_screen.dart`)

Route und Schlüssel werden der Topf statt des Desks (`AntragScreen(desk:)` :26, `_available` :223,
`claims_routes.dart:18`, `?desk=` → `?pot=`; `?desk=` bleibt als Einstieg aus alten
Mitteilungen).

Die fünf Schritte bleiben fünf, der zweite wird umgebaut:

1. **Prüfen** (`_Pruefen` :819-1012): die Fallliste zeigt je Fall die Minuten (Topf) oder den
   Betrag, dazu „Fahrkarte ändern" je Fall wie in den Fall-Details. „Ticket-Nr." verschwindet aus
   den persönlichen Daten (:930, :1123-1129, Banner :1142).
2. **Fahrkarte** (war „Ticket", `_Ticket` :1307-1435, `_WhatToUpload` :1255-1305): oben die
   Fahrkarte mit den Feldern, die für diesen Antrag fehlen (Nummer, Klasse, Preis — beim
   Einzelfahrschein Pflicht, bei Zeitkarten optional), darunter die Belege, die das Produkt will:
   D-Ticket ein Bild je Monat mit Fällen (liegt es schon an der Fahrkarte, ist es angehakt),
   BahnCard 100 kein Bild, Einzelfahrkarte das Ticket, Zeitkarte ohne Preisaufdruck zusätzlich
   „Nachweis, was du gezahlt hast (optional)".
3. **Zweck**, 4. **Unterschrift**, 5. **Senden** bleiben; „Inhaber:in des Tickets" (:1573) und die
   Anhangsnamen (:1678) nach Fahrkarte.

`_Ueberblick` (:730-815) nennt den zweiten Schritt „Fahrkarte". Die 4-€-Hinweise (:175, :203)
kommen aus dem `blocker` des Servers.

### Screen: Antwort (`antwort_screen.dart:39,304,328-428`)

„Kopie Ihres Deutschlandtickets" und „Ticketkopie nachreichen" nach Fahrkarte des Antrags;
`_attachTicket` nimmt zuerst den Beleg, der schon an der Fahrkarte liegt.

---

## Phase 5 — Unterwegs, Ankunft, Texte, Website (App, Site)

### Screen: Unterwegs (`unterwegs_screen.dart`)

- `claimFrom` (:323) kommt aus `claim_from_minute` der Reise (20 oder 60); der Untertitel
  (:353-358) „Ab hier entsteht ein Anspruch." wird bei Minuten-Töpfen „Ab hier zählt es mit."
- Neu eine Zeile Rechte aus `ApiJourneyLive.rights` (Server, aus `reduced_fare` und
  `release_after_min`): ab 20 Minuten mit Einzelfahrkarte „Deine Zugbindung ist aufgehoben — du
  darfst einen anderen Zug nehmen."; mit D-Ticket keine solche Zeile.
- **Fehler beheben:** das Abbrechen-Sheet liest die Fahrkarte aus der Einstellung
  (`me.settings.ticket`, :1232), nicht aus der Reise. `showGaveUpSheet` (:1271-1320) nimmt das
  Produkt der Reise.

### Screen: Angekommen (`angekommen_screen.dart`)

- Die festen 60 (:174, :247, :783) kommen aus der Reise.
- `_ClaimLine` (:706-750) heute: nur fürs D-Ticket „Gesammelt 2 von 3" mit Punkten, sonst „Jede
  Fahrt einzeln". Neu nach Art: Minuten-Topf „+68 Minuten · jetzt 280 Minuten, 6,00 €" mit dem
  Fortschritt zur nächsten Stunde; Fall-Topf „2 von 3 Fällen"; Einzelfahrkarte der Betrag oder
  „Fahrpreis eintragen".
- `_NoClaimCard` (:755-790) „Ab 60 Minuten entsteht ein Anspruch" nach Produkt; mit D-Ticket bei
  25 Minuten gibt es keine Nicht-Anspruchs-Karte mehr, sondern die Minuten im Topf.
- `canFile` (:175-181) aus `pot.payable`.

### Texte

- `content/legal.dart` :98, :99, :101 (gespeicherte Fahrkarten sind neue personenbezogene Daten:
  Art, Nummer, Preis, Klasse, Geburtsdatum bei der BahnCard 100), :117, :121, :128, :134, :146.
  Das geht auch auf die Website (docs/31: die Rechtstexte kommen aus der App).
- `datenherkunft_screen.dart:25-30`, `showcase_screen.dart:58,70,99`, `mock_data.dart:734-735`
  (Abzeichen „Bagatellgrenze geknackt — Erstes Bündel über 4 €" bleibt richtig; prüfen).
- Jeder neue Satz wird gegen den Katalog geprüft, bevor er gebaut wird (Memory: keine unbelegten
  Zusagen).

### Website (`site/`)

- `site/content/index.toml` :69, :84 „Ab 60 Minuten entsteht ein Anspruch", FAQ :187-192 („Und
  mit dem Deutschlandticket? … sammelt, bis drei Verspätungen zusammenkommen") neu: ab 20 Minuten
  zählt mit, je volle Stunde 1,50 €, über Monate gesammelt. Heldenkarte :56 (204 Minuten,
  12,00 €) nachrechnen.
- `site/static/shots/antraege.webp` (Alt-Text und Unterschrift :120-122) und `unterwegs.webp` aus
  der Tour neu, auf 640 px, `site/dist` neu erzeugen (Hausregel).

### Tour und E2E

- `integration_test/screenshot_tour_test.dart`: neue Bilder `fahrkarten`, `fahrkarte-neu`,
  `fahrkarte-dticket`, `einchecken-fahrkarte` (neu), `antraege` mit Minuten-Topf,
  `antrag-fahrkarte` (statt `antrag-ticket`), `fall-fahrkarte-aendern`; betroffen außerdem
  `angekommen-*`, `unterwegs`, `abbrechen-*`, `einstellungen`, `daten`, `datenschutz`,
  `antrag-pruefen`, `antrag-senden`, `antwort-*`.
- `integration_test/workflow_test.dart`: die Tasten `ticket-zeitkarte`/`ticket-deutschlandticket`
  (:328-337) werden `fare-deutschlandticket` (erste Fahrt) bzw. `ticket-<id>`; der vierte
  Feldeintrag Ticketnummer (:429-439, :690-696) wandert in den Schritt Fahrkarte. Neu: ein
  D-Ticket-Topf aus drei zurückdatierten Fahrten zu 60, 60 und 25 Minuten (zusammen 145 Minuten,
  2 volle Stunden, 3,00 €, nicht zahlbar), dann eine vierte mit 40 Minuten (185 Minuten → 4,50 €,
  zahlbar); ein Fall wird auf eine Einzelfahrkarte umgehängt. Stellwerk `backdate` braucht dafür
  `--ticket` und Verspätungen unter 60 (Phase 2).
- Die alte E2E muss bis Phase 5 gegen den neuen Server grün bleiben (`compat.sh`, Phase 2).

---

## Was bewusst nicht in diese Runde kommt

- Zwei Fahrkarten auf einer Reise in der App (D-Ticket bis Köln, Sparpreis ab Köln) — das Modell
  trägt es, die Oberfläche folgt, wenn jemand danach fragt.
- Hin- und Rückfahrt als ein Kauf, Gruppenfahrkarten, Pässe, Semestertickets, internationale
  Fahrkarten, freiwillige Garantien, fehlende 1. Klasse.
- Das Taxi- und Hotelrecht als Antrag (nur als Hinweis unterwegs).

## Risiken

- **Der Topf über Monate** ist Johannes' Lesart, nicht belegt (docs/49 §9). Der erste Antrag mit
  Monatswechsel ist der Test; Umstellen ist eine Zeile im Katalog, aber schon eingereichte
  Anträge bleiben, wie sie sind.
- **Zuteilung auf Fälle**: `reply.rs` prüft die Antwort der Bahn gegen den je Fahrt beantragten
  Betrag. Bei Minuten-Töpfen nennt die Bahn vermutlich eine Summe; die Tests der
  Antworterkennung brauchen einen Topf-Fall.
- **Fälle ab 20 Minuten** vervielfachen die Zahl der Fälle für D-Ticket-Pendler. Die Ansichten
  (Anträge, Fallliste im Antrag, Freitext im EU-Formular mit 2.500 Zeichen) müssen 30 Fälle
  tragen; der Freitext braucht eine Kurzform je Fall.
- **Migration offener Fälle** ändert Beträge, die Menschen schon gesehen haben (39,90 € weg,
  BahnCard 100 höher, Fristen länger). Eine Mitteilung beim ersten Start des neuen Builds erklärt
  das in einem Satz.
