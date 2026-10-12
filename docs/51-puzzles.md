# 51 — Puzzles: jede Fahrt ein Teil

Konzept vom 12. Oktober 2026, auf Johannes' Wunsch: „To every cause you can support, we can provide
images in the backend. Those images can become puzzle pieces, that you can collect. Preferably you
get pieces from a cause you supported in the past. But also from others. Add a nice animation to
the reveal after each ride. Then have a page where your puzzles are visible."

Gebaut auf dem Branch `feature/puzzle`, noch nicht auf Staging. Was gebaut ist, steht in §9.

## 0. Welches Problem es löst

Die App belohnt heute genau eine Sache: Verspätung. Eine pünktliche Fahrt endet mit einer grünen
`+0` und sonst nichts. Das ist ehrlich, aber es hat eine Folge, die man am Bahnsteig sieht: Wer
morgens auf der Anzeige liest, dass sein Zug pünktlich ist, hat keinen Grund, einzuchecken. Er
checkt ein, wenn es schon schiefgeht — oder er vergisst es, weil es die letzten fünf Male nicht
schiefging. Eine App, die man nur an schlechten Tagen öffnet, wird keine Gewohnheit, und eine
Fahrt, die nicht eingecheckt ist, kann später auch keinen Anspruch werden.

Das zweite Problem ist der Zweck. Der Verein ist ein Name, ein Logo und drei Absätze Text. Das Geld
kommt Wochen später, nur ab 60 Minuten, und die meisten Fahrten bringen nie welches. Wofür man
eigentlich wartet, sieht man fast nie.

Das Puzzle löst beides mit einem Gegenstand: **Jede Fahrt bringt ein Teil eines Bildes, das ein
Verein von seiner Arbeit zeigt.** Pünktlich oder nicht. Wer oft fährt, sieht das Bild entstehen —
die Nachtschicht der Bahnhofsmission, die Baumreihe in der Eifel — und das fertige Bild ist das,
wofür die Minuten am Ende gut sind.

## 1. Was es ist

- **Ein Verein hinterlegt Bilder.** Wir laden sie im Stellwerk hoch (§8), mit einem Titel und
  einem Satz dazu, was man sieht. Jedes Bild hat ein Raster, Standard 3 × 4 = 12 Teile.
- **Jede Fahrt bringt ein Teil.** Es wird bei der Ankunft gezeigt, unter den Minuten (§5).
- **Ein fertiges Bild** verliert seine Fugen und zeigt den Satz des Vereins. Das ist der Moment,
  auf den das Ganze hinläuft.
- **Die Seite „Puzzles"** (von Ich aus) zeigt die angefangenen Bilder und die fertigen (§6).

## 2. Woher das Teil kommt

**Deine Vereine** sind der Verein, den du gerade als Zweck gewählt hast, und jeder Verein, an den
schon ein Antrag von dir ging oder gehen soll. Das ist „a cause you supported", gemessen an dem,
was wirklich passiert ist, nicht an einem Klick.

1. Mit **drei von vier** Teilen kommt das Teil aus einem Bild deiner Vereine, mit einem von vier
   aus einem anderen Verein. Ist eine der beiden Seiten leer (alles fertig, oder es gibt keinen
   anderen Verein mit Bildern), kommt es von der anderen.
2. **Ein Bild nach dem anderen.** Hat ein Verein ein angefangenes Bild, kommt das Teil daraus;
   erst wenn es fertig ist, beginnt das nächste Bild dieses Vereins. So konzentriert sich der
   Fortschritt, statt sich auf fünf halbe Bilder zu verteilen.
3. **Welches Teil im Bild, ist Zufall.** Das Bild füllt sich verstreut, nicht zeilenweise —
   so erkennt man früh, was es zeigt, und die letzten Lücken sind die spannenden.
4. **Keine Doppelten.** Es kommt nur ein Teil, das du noch nicht hast. Doppelte sind beim
   Stickeralbum der Teil, den niemand vermisst.
5. Gibt es kein Teil mehr, das du nicht hast, kommt keins, und die Ankunft sagt nichts dazu.

## 2a. Seltenheit: Minute, Viertelstunde, Stunde

Entschieden am 12. Oktober 2026 (Johannes: „We need different rarities"). Nicht als Münzen und
Päckchen — das wären eine zweite Währung neben den Minuten (docs/47) und eine Lootbox (JuSchG
§ 10b, und neben einem Kinderhospiz liest sich ein Päckchen als Glücksspiel). Sondern so:
**Die Seltenheit eines Teils ist, wie lange du gewartet hast.**

| Stufe | Kommt von | In einem Bild mit 12 / 20 / 30 Teilen |
|---|---|---|
| **Minute** | jeder beendeten Fahrt | 8 / 13 / 19 |
| **Viertelstunde** | einer Fahrt mit mindestens 15 gezählten Minuten | 3 / 5 / 8 |
| **Stunde** | einer Fahrt mit mindestens 60 gezählten Minuten — der, aus der ein Anspruch wird | 1 / 2 / 3 |

Gezählt wird mit `rules::counted_minutes`: Ein Ausfall zählt 60 und bringt also ein Stunden-Teil,
eine aufgegebene Reise zählt das Warten.

- **Jedes Bild hat seine Stufen fest.** Welcher Platz welche Stufe hat, legt der Server beim
  Hochladen fest und speichert es: Die Stunden-Teile liegen in der Mitte — das Herz des Bildes
  kommt mit der Fahrt, deren Verspätung für diesen Verein zu Geld wird —, die Viertelstunden
  verstreut, der Rest sind Minuten. Das Stellwerk kann es überschreiben.
- **Ein seltenes Teil geht dahin, wo es gebraucht wird.** Eine Fahrt der Stufe S füllt zuerst einen
  offenen Platz genau dieser Stufe (in einem angefangenen Bild, sonst im nächsten Bild des Vereins);
  erst wenn es keinen gibt, einen Platz einer niedrigeren Stufe. Ein Stunden-Teil verfällt nie zu
  einer Minute, solange irgendwo ein Stunden-Platz wartet.
- **Ein Bild kann auf sein seltenes Teil warten.** Fehlt nur noch das Stunden-Teil, bleibt das Bild
  offen — „Fehlt noch: das Stunden-Teil" — und pünktliche Fahrten fangen das nächste Bild des
  Vereins an. Damit gilt §2.2 („ein Bild nach dem anderen") für jede Stufe einzeln.
- **Die Stufe ist zu sehen — aber nur, wo sie selten ist.** Ein seltenes Teil trägt in der Ecke eine
  kleine Bahnhofsuhr: bei der Viertelstunde ein Viertel gefüllt, bei der Stunde die ganze Scheibe in
  Rot. Die Minute trägt nichts; zwölf Uhren auf einem Bild wären Lärm, und was keine Uhr hat, ist
  gewöhnlich. Die Viertelstunde hat einen feinen Rand in Tinte, die Stunde einen roten — Rot heißt
  in dieser App „das ist Geld" (STYLE.md), und das Stunden-Teil ist genau das. Ein fehlender
  seltener Platz zeigt seine Uhr auch: Man sieht, worauf das Bild wartet.
- **Mehr Verspätung bringt ein selteneres Teil, nicht mehr Teile.** Eine Fahrt, ein Teil. Sonst
  wäre das Puzzle wieder eine Währung und der Vorrat an Bildern in einer Woche leer.

Was das für die Dauer heißt: Ein Bild mit 12 Teilen braucht acht beliebige Fahrten, drei mit einer
Viertelstunde und eine mit einer Stunde. Für einen Pendler ist das eher ein Monat als eine Woche —
gewollt (Johannes: „So it takes a bit to complete"), und es entschärft den Nachschub (§4).

## 3. Was eine Fahrt dafür sein muss

- **Jede beendete Reise bringt ein Teil, einmal pro Reise** (nicht pro Zug, wie die Minuten,
  docs/17): angekommen, aufgegeben (man hat gewartet, docs/22 §1) oder ausgefallen. Dass ein Teil
  kommt, belohnt, dass du da warst; wie selten es ist, sagt die Verspätung (§2a).
- **Kein Teil** für einen Nachtrag (er rankt auch nicht, docs/47), für „nicht mitgefahren" und
  für eine Fahrt, die vor dem Ende gelöscht wird.
- **Höchstens drei Teile am Tag** (Berliner Zeit). Gegen das Ein- und Auschecken am Sofa; ein
  Pendler mit Hinweg, Rückweg und einer Erledigung merkt die Grenze nie.
- **Ein Teil bleibt.** Wird die Fahrt später gelöscht, bleibt das Teil. Nichts in dieser App wird
  weggenommen (docs/12).
- Das Teil hängt an der Reise (eine Reise, höchstens ein Teil). Ein zweiter Abschluss derselben
  Reise — ein Netzfehler, ein doppelter Tipp — bringt kein zweites.

## 4. Warum man wiederkommt — und wo wir aufhören

Johannes fragt nach der Klebrigkeit. Ehrlich betrachtet hat das Puzzle sieben Hebel, und die
App darf nur einen Teil davon ziehen.

**Was wirkt:**

1. **Jede Fahrt zählt.** Der wichtigste Hebel und der einzige, der der Sache selbst nützt: Wer
   jede Fahrt eincheckt, hat eingecheckt, wenn es schiefgeht. Das Puzzle macht den pünktlichen
   Morgen zu einem Grund, die App zu öffnen, und daraus wird die Gewohnheit, die an einem Tag
   mit 68 Minuten den Anspruch rettet.
2. **Die gewisse Belohnung mit einer offenen Frage.** *Dass* ein Teil kommt, ist sicher. *Welches*
   und *von wem*, nicht. Das ist der Reiz des Sammelalbums und reicht völlig — ohne Lotterie.
3. **Der Sog des fast fertigen Bildes.** Menschen beeilen sich, je näher das Ziel ist, und eine
   offene Lücke bleibt im Kopf. Die Minuten-Teile eines Bildes sind bei Hin- und Rückweg in
   einer Woche da; dann wartet es auf die seltenen (§2a), und die letzte Lücke ist die, auf die
   man sich freut. „Ein Bild nach dem anderen" (§2) ist genau dafür da.
4. **Seltenheit, die man versteht.** Ein Stunden-Teil ist selten, weil eine Stunde Verspätung
   selten ist — nicht, weil ein Würfel es so wollte. Darum ist es kein Glücksspiel, und darum
   tröstet es: Der schlimmste Morgen des Monats bringt das schönste Teil.
5. **Bedeutung statt Punkte.** Das Bild zeigt, wofür das Geld ist. Wer es fertig hat, hat sich
   ein Dankeschön abgeholt, und der Zweck ist danach kein Name mehr. Das stärkt die andere Seite
   der App: Wer weiß, wofür, schickt den Antrag ab.
6. **Entdeckung.** Jedes vierte Teil kommt von einem Verein, den man nicht gewählt hat. Das ist
   der „Wir"-Gedanke in klein: Man sieht, was die anderen unterstützen.
7. **Etwas zum Zeigen.** Ein fertiges Bild ist ein besseres Teilen-Motiv als ein Abzeichen, weil
   es von jemand anderem erzählt (§10, später).

**Was wir nicht tun** — die Regeln aus docs/12 gelten hier genauso:

- **Nichts verfällt, nichts reißt ab.** Kein „noch 2 Tage, um das Bild zu vollenden", keine Serie.
  Ein angefangenes Bild wartet ein Jahr, wenn es muss.
- **Keine zweite Zahl** (docs/47). Es gibt keine Summe über alle Puzzles („43 Teile"), keine
  Rangliste, keinen Vergleich mit anderen. Fortschritt gibt es nur pro Bild: „7 von 12".
- **Keine Mitteilung für ein Teil.** Das Teil kommt bei der Ankunft, die die App ohnehin zeigt.
  Kein „Dein Puzzle wartet!".
- **Nichts kaufen, nichts tauschen, keine Doppelten.**
- **Keine Ankündigung während der Fahrt.** Die Fahrt bleibt ruhig (docs/12, letzter Punkt); die
  Belohnung ist bei der Ankunft.
- **Keine Münzen, keine Päckchen, kein Zufall bei der Seltenheit** (§2a). Selten ist, was selten
  passiert ist. Und die Verspätung bringt nie mehr Teile, nur ein selteneres.

**Risiken:**

- **Der Nachschub.** Das ist die echte Grenze. Ein Pendler mit zehn Fahrten pro Woche sammelt
  rund 40 Teile im Monat, also drei bis vier Bilder à 12 — davon drei von seinem eigenen Verein.
  So viele Bilder schickt kein Verein. Darum: Das erste Bild eines Vereins hat 12 Teile, spätere
  20 (4 × 5) oder 30 (5 × 6); das Raster ist eine Eigenschaft des Bildes, und größere Bilder
  dürfen länger dauern. Und wenn alles fertig ist, ist alles fertig: Die Seite sagt „Neue Bilder
  kommen, wenn die Vereine welche schicken", und die Ankunft zeigt wieder nur die Minuten. Das ist
  ehrlicher als ein Ersatz-Puzzle mit Stockfotos.
- **Der Reiz lässt nach.** Sammelmechaniken nutzen sich ab. Das ist in Ordnung, solange das Puzzle
  nicht das Einzige ist, was die App trägt; es ist die kleine Belohnung für den guten Tag, die
  Minuten bleiben die große für den schlechten.
- **Bildrechte und Menschen auf Bildern.** Der Verein muss die Rechte haben und schreibt es uns;
  keine erkennbaren Menschen ohne deren Einwilligung (Hospiz!). Beim Hochladen fragt das Stellwerk
  danach, und die Datenschutzerklärung braucht keinen Zusatz, weil wir nichts über Menschen
  speichern, nur welches Teil wer hat.
- **Die Ankunft wird voller.** Die Minuten bleiben oben und zuerst; das Teil kommt danach und
  kleiner. Bei 0 Minuten ist das Teil die Hauptsache, und das ist gewollt.

## 5. Die Ankunft

docs/10: „Arrival … is the one moment the app is allowed to feel like a reward." Die Zahl zählt
hoch wie bisher. Danach, und erst danach:

1. Unter den Minuten erscheint eine Karte **„EIN TEIL FÜR BAHNHOFSMISSION KÖLN"**. Darin das Bild
   im Raster: Die Teile, die du hast, in Farbe; die fehlenden als blasse Umrisse auf `track`-Grau.
2. **Das neue Teil** kommt von unten herein, etwas größer, leicht gedreht, mit Schatten, als läge
   es in der Hand. Es schwebt an seinen Platz, dreht sich gerade und **rastet ein**: ein kurzes
   Nachfedern, ein einzelner Haptik-Tick, und an seinen Rändern leuchtet für einen Moment das
   eine Rot auf — das Licht unter dem, was gerade passiert ist (STYLE.md).
3. Darunter die Stufe und der Stand: **„Ein Viertelstunden-Teil. 7 von 12."** — „Ein
   Minuten-Teil.", „Ein Stunden-Teil." Wartet das Bild danach nur noch auf seltene Teile, steht
   es da: „Fehlt noch: das Stunden-Teil."
4. **War es das letzte Teil**, verschwinden danach die Fugen, das Bild atmet einmal (ein Hauch
   größer und zurück), und der Satz des Vereins steht darunter: „Fertig: Nachtschicht am Gleis 1."
5. Alles zusammen ungefähr anderthalb Sekunden. Ein Tipp überspringt es; mit `NO_ANIM` steht
   sofort das Endbild da. Ein Tipp auf die Karte öffnet die Puzzles.

Keine Konfetti: Die gehören dem Antrag (docs/27 §4).

## 6. Die Seite „Puzzles"

Unterseite mit dem Standardkopf (Eyebrow „SAMMLUNG", Titel „Deine Puzzles"), erreichbar von Ich
(Zeile „Puzzles" mit dem angefangenen Bild als Vorschau) und von der Karte bei der Ankunft.

- **Angefangen:** je Bild eine Karte — das Bild im Raster mit Lücken, Titel, Verein, „7 von 12".
  Das zuletzt gewachsene oben.
- **Fertig:** zwei Spalten, die ganzen Bilder ohne Fugen, Titel und Verein darunter. Ein Tipp
  öffnet das Bild groß, mit dem Satz des Vereins und dem Tag, an dem das letzte Teil kam.
- **Leer:** „Deine erste Fahrt bringt das erste Teil." Mit einem leeren Raster als Bild.
- **Alles fertig:** „Alle Bilder sind fertig. Neue kommen, wenn die Vereine welche schicken."

Bilder, die noch niemand angefangen hat, zeigt die Seite nicht — die Überraschung gehört der
Ankunft.

## 7. Wie die Teile aussehen

Echte Puzzleteile mit Nasen und Buchten, nicht Kacheln: Die Form ist das, was man sofort als
Puzzle liest. Die Nasen sind pro Bild fest (aus der Bild-ID abgeleitet), also sieht dasselbe Bild
auf jedem Telefon gleich aus. Der Server schneidet nichts; er schickt das ganze Bild und sagt,
welche Teile du hast. Das Telefon zeichnet die Teile mit einem Pfad darüber. Ein neugieriger Mensch
könnte das ganze Bild aus der Antwort holen — das Bild ist nicht geheim, es ist ein Foto eines
Vereins, und eine Antwort pro Teil wäre viel Aufwand für nichts.

## 8. Technik

**Datenbank** (Migration 0048):

- `puzzle_images`: `id`, `ngo_id`, `title`, `caption`, `rows`, `cols`, `tiers` (die Stufe jedes
  Platzes, §2a), `content_type`, `bytes` (das Bild selbst, `bytea`, höchstens 1 MB), `width`,
  `height`, `sha256`, `retired_at`, `created_at`. Bilder liegen in Postgres, weil die nächtliche Sicherung sie dann mitnimmt und
  es ein paar Dutzend sind, nicht Tausende.
- `puzzle_pieces`: `customer_id`, `image_id`, `piece` (0 … rows·cols−1), `journey_id`
  (eindeutig; wird die Reise gelöscht, wird es `null`, und das Teil bleibt), `own_cause` (ob der
  Verein in dem Moment einer deiner war), `awarded_at`; Primärschlüssel
  `(customer_id, image_id, piece)`.

**Deine Vereine** liest der Server aus `customers.ngo_id` und den `ngo_id` deiner Fälle
(`incidents`) und Anträge (`claims`). Eine Reise selbst merkt sich keinen Verein; das Teil tut es
jetzt (über sein Bild).

**Regel** (`backend/src/puzzles.rs`): Die Auswahl aus §2 ist eine reine Funktion über die
Kandidaten (je Verein ein Bild: das angefangene, sonst das nächste), die eigenen Vereine und einen
Würfelwurf, damit sie ohne Datenbank getestet werden kann. Vergeben wird an jedem Ende einer Reise,
das ein Teil bringt: in `finalise_journey` (der Tipp auf „Angekommen", die Reise, die der Server
selbst abschließt, der verstrichene Umstieg), im Abbruch von `finish` (aufgegeben) und in
`expire_transfers`. `puzzles::award` öffnet dafür eine eigene Transaktion und sperrt die Zeile des
Kunden, damit zwei gleichzeitig endende Reisen nicht dasselbe Teil oder die Tagesgrenze überholen.
Die Reise ist zu dem Zeitpunkt schon gespeichert: Scheitert das Vergeben, endet die Reise trotzdem,
nur ohne Teil. Fahrten, die das Stellwerk nachträglich anlegt (`backdate`), bringen keins — sie
sind wie ein Nachtrag.

**Schalter:** `puzzles` (docs/46-Muster: aus ist das, was schon ausgeliefert ist). Aus heißt: Der
Server vergibt keine Teile, die App zeigt nichts davon. Im Demo-Modus ist das Puzzle immer an.

**Draht** (nur hinzufügen, Hausregel). Ein Teil (`piece`):

```json
{ "image_id": "…uuid…", "piece": 7, "tier": "quarter", "rows": 4, "cols": 3,
  "tiers": ["minute", "quarter", "minute", "minute", "hour", "minute",
            "quarter", "minute", "minute", "minute", "quarter", "minute"],
  "owned": [0, 3, 7], "complete": false,
  "title": "Nachtschicht am Gleis 1", "caption": "Ein Becher Tee um drei Uhr nachts.",
  "ngo_id": "bahnhofsmission", "ngo_name": "Bahnhofsmission Köln", "own_cause": true,
  "image_url": "/v1/puzzle-images/…uuid…", "width": 900, "height": 1200,
  "awarded_at": "2026-10-12T17:40:00Z" }
```

`piece` zählt zeilenweise von links oben (`row * cols + col`), `owned` enthält das neue Teil schon.
`tier` ist `minute`, `quarter` oder `hour` (§2a), `tiers` die Stufe jedes Platzes, in derselben
Reihenfolge. `own_cause` wird beim Vergeben gespeichert, nicht später neu berechnet.

- `GET /v1/journeys/current` bekommt neben `just_arrived` ein optionales `piece` — das Teil, das
  diese Reise gebracht hat, oder `null`. Von dort liest die Ankunft.
- `POST /v1/journeys/{id}/finish` trägt dasselbe `piece` im Reise-Objekt.
- `GET /v1/me/puzzles` → `{ "puzzles": [Puzzle…], "more_waiting": true }`. Ein `Puzzle` hat die
  Felder des Teils ohne `piece`/`tier`/`awarded_at`/`own_cause` (also mit `tiers`), dazu `started_at`, `last_piece_at`,
  `completed_at` (oder `null`). Reihenfolge: angefangene nach letztem Teil absteigend, dann fertige
  nach Fertigstellung absteigend. `more_waiting` sagt, ob noch irgendein Teil zu holen ist
  (sonst: „Alle Bilder sind fertig").
- `GET /v1/puzzle-images/{id}`: das Bild, ohne Anmeldung (es ist ein Foto eines Vereins), mit
  `ETag` aus dem `sha256` und `Cache-Control: public, max-age=31536000, immutable` — ein Bild ändert
  sich nie, ein neues bekommt eine neue ID. Die App legt es einmal auf dem Telefon ab.
- Admin: `POST /admin/ngos/{id}/puzzle-images` (JSON mit `title`, `caption`, `rows`, `cols`,
  optional `tiers` zum Überschreiben der Verteilung aus §2a, `content_type`, `data` in Base64; JPEG, PNG oder WebP, höchstens 1 MB, Teile ungefähr quadratisch),
  `GET /admin/puzzle-images`, `POST /admin/puzzle-images/{id}/retire`,
  `DELETE /admin/puzzle-images/{id}` (nur ohne vergebene Teile).

**Stellwerk:**

```
stellwerk ngo image add <ngo> bild.jpg --title "Nachtschicht am Gleis 1" \
    --caption "Ein Becher Tee um drei Uhr nachts." [--grid 3x4]
stellwerk ngo image list [<ngo>]
stellwerk ngo image retire <id>
```

`retire` nimmt ein Bild aus der Verteilung. Wer schon Teile davon hat, behält es und kann es fertig
sammeln — sonst nähmen wir etwas weg. Gelöscht wird ein Bild nur, wenn es niemand angefangen hat.

**App:** `PuzzleBoard` zeichnet ein Bild mit Teilen (Pfad mit Nasen, fehlende als Umriss),
`PieceReveal` ist die Animation aus §5, `PuzzlesScreen` die Seite aus §6. Im Demo-Modus kommen drei
erfundene Bilder aus `assets/demo/puzzles/`.

## 9. Was gebaut ist

Siehe den Abschluss dieses Branches; hier nachgetragen, wenn er steht.

## 9a. Das Teil in der Hand (3D, nächster Schritt)

Johannes: „Maybe we can get 3D in? Like Apple does with their badges? I could provide textures
later." Apples Abzeichen sind echte 3D-Modelle, die man mit dem Finger dreht und die sich mit dem
Telefon neigen. Für ein flaches Puzzleteil braucht es kein Modell, sondern **2,5D**: das Teil als
Körper mit Dicke (die Kante als Wand aus der Teil-Form), geneigt über eine Perspektiv-Matrix, mit
Finger und Lagesensor, und beleuchtet von einem Fragment-Shader. So läuft es auf iOS und Android
gleich und braucht keine 3D-Engine.

- **Wo:** Ein Tipp auf ein Teil (bei der Ankunft, auf der Puzzles-Seite) hebt es heraus; man kann
  es drehen, die Rückseite ist Karton mit der Uhr der Stufe und dem Namen des Vereins.
- **Material nach Stufe:** Minute — Karton, matt. Viertelstunde — Tinte, lackiert. Stunde —
  rotes Email mit Glanz.
- **Texturen von Johannes**, wenn es so weit ist: je Stufe eine **Matcap** (eine beleuchtete
  Kugel, 512 × 512 PNG — die einfachste Art, einem Shader ein Material zu geben), dazu eine
  kachelbare **Normal-Map** für den Karton (1024 × 1024). Bis dahin zeichnet der Shader die
  Materialien selbst.

## 10. Später

- **Teilen:** ein fertiges Bild als fünftes Gesicht der Fahrkarte (docs/27) — „12 Fahrten.
  Ein Bild für Wald für morgen."
- **Die Vereinsseite** zeigt ihre Bilder und wie viele Menschen sie schon fertig haben.
- **Der Verein bekommt etwas zurück:** „Dein Bild wurde 214 Mal fertig gepuzzelt" im
  Monatsbericht. Das ist für den Verein ein Grund, neue Bilder zu schicken — und löst das
  Nachschub-Risiko aus §4 von der richtigen Seite.
