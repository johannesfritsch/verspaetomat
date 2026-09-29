# 48 — Bahnhofsumrisse: wo ein Bahnhof anfängt

Recherche und Plan zu Issue #64, 29. September 2026. Johannes' Auftrag: „Let's first write a
prototype description how this could look like! Maybe we get the polygon outline of a
trainstation from OSM? Or from the Bahn Open Data stuff?"

**Entschieden (Johannes, 29. September):**

- **OSM unter ODbL ist in Ordnung.** Veröffentlichung der Umrisse und Namensnennung werden geplant
  (unten).
- **Keine Anfrage an DB InfraGO**; offene DB-Daten ja, wenn sie etwas hergeben.
- **„Am Bahnhof" heißt: irgendwo auf dem Gelände.** Läden, Halle, Vorplatz, Wege gehören dazu.
- **Erst zählen, wie weit wir kommen.** Wo es keinen Umriss gibt, bleibt der 300-m-Kreis die
  Grenze.

## Was heute gilt

Ein Bahnhof ist für die App ein **Punkt** — die Koordinate, die unsere Tabelle aus dem Feed
übernimmt (docs/44). Darum liegt ein fester Kreis von 300 m, der die App weckt
(`Geofence.swift`, `GeofenceManager.kt`, docs/25). Was danach passiert, ist auf den beiden
Plattformen verschieden:

**iOS: die 50-m-Schwelle.** Beim Betreten des 300-m-Kreises (`didEnterRegion`) schaltet die App
das GPS ein — laufende Standortmeldungen mit 10 m Genauigkeit, auch im Hintergrund
(`beginNearWatch`). Es wird nicht geschlafen und nachgesehen: Jede Meldung, die iOS liefert, wird
sofort geprüft (`didUpdateLocations`, Fall `.dwell`). Die Beobachtung endet beim ersten dieser
vier Ereignisse:

| Ereignis | Folge |
|---|---|
| ein Fix liegt höchstens 50 m vom Bahnhofspunkt | Nudge in 45 s, GPS aus |
| ein Fix liegt außerhalb der 300 m | kein Nudge, GPS aus („left before getting close") |
| iOS meldet das Verlassen des 300-m-Kreises (`didExitRegion`) | kein Nudge, GPS aus, ein geplanter Nudge wird zurückgenommen |
| sechs Minuten vergangen (`nearWatchWindow`) | kein Nudge, GPS aus |

**Android: keine 50-m-Schwelle.** Der Kreis ist als Geofence mit *Dwell* registriert: Wer drei
Minuten im 300-m-Kreis bleibt, bekommt nach einem einzigen Kontroll-Fix (ebenfalls „innerhalb
300 m") den Nudge (`onStationDwell`). Android prüft also schon heute nur den 300-m-Kreis — genau
das, was als Rückfall ohne Umriss gewollt ist.

Die 50 m sind die Schwachstelle: Sie messen den Abstand zu einem Punkt, nicht, ob man auf dem
Gelände steht.

## Gemessen

### Zehn Bahnhöfe gegen die 50 m (Overpass, 29. September)

Zug-Bahnsteige aus OSM (`railway=platform` im Umkreis von 450 m, ohne Tram-, Bus- und
U-Bahn-Steige) gegen den Punkt unserer Tabelle:

| Bahnhof | weitester Bahnsteigpunkt | Anteil der Bahnsteige innerhalb 50 m |
|---|---|---|
| München Hbf | 688 m | 0 % |
| Hamburg Hbf | 468 m | 8 % |
| Stuttgart, Hauptbahnhof (oben) | 355 m | 0 % |
| Rheine, Bahnhof | 281 m | 0 % |
| Kißlegg Bahnhof | 191 m | 36 % |
| Hagen Hbf | 178 m | 0 % |
| Langenargen Bahnhof | 166 m | 53 % |
| Leichlingen Bf | 138 m | 17 % |

In München, Stuttgart, Rheine und Hagen liegt **kein einziger Bahnsteigpunkt** innerhalb der 50 m.
Wer dort am Gleis wartet, bekommt auf dem iPhone keinen Nudge, außer er geht am Punkt vorbei. Und
München reicht 688 m weit: weiter, als der 300-m-Kreis wacht.

### Stufe 1, die Steige aus unseren Feeds: gezählt, reicht nicht

Der Import liest jede Zeile von `stops.txt`, auch jeden Steig mit Koordinate. Gezählt über den
ganzen DELFI-Feed (550.000 Zeilen) gegen unsere 7.632 Bahnhöfe, deutsche Bahnhöfe allein (die
übrigen sind polnische und andere Auslandsbahnhöfe ohne deutsche DHID):

| Rang | Bahnhöfe | mit ≥ 3 Steigpunkten |
|---|---|---|
| 3, Fernverkehr | 308 | 240 (78 %) |
| 2, Regional | rund 5.070 | 3.287 (65 %) |
| 1, nur S-Bahn | rund 830 | 590 (71 %) |

Die Abdeckung wäre ordentlich, **die Form ist es nicht**: Köln Hbf hat 11 Steigpunkte auf 104 m,
die echten Bahnsteige messen rund 410 m. Hamburg Hbf hat 3 Punkte auf 87 m. Umgekehrt zieht die
DHID in kleinen Orten Bushaltestellen mit hinein (Langenargen: 252 m Spanne gegen 98 m
Bahnsteig), und einzelne Gruppen sind kaputt (eine reicht 260 km weit). Die Feed-Steige sind
Haltepunkte für die Fahrplanauskunft, keine Vermessung. **Stufe 1 fällt weg.**

### DB Open Data: OpenStation, keine Umrisse

DB InfraGO veröffentlicht **OpenStation**, einen NeTEx-Datensatz aller Personenbahnhöfe, frei
herunterladbar über die Mobilithek
(https://mobilithek.info/offers/879076212433727488, Doku https://github.com/dbinfrago/openstation-docs).
Geladen und ausgezählt (Stand 29. September, 304 MB): 5.393 Bahnhöfe, 21.784 Bahnsteigkanten,
5.346 Zugangsbereiche, 1.761 Eingänge — und **kein einziges Polygon**. Koordinaten tragen nur
2.485 Ausstattungsorte (Aufzüge, Rolltreppen); Bahnhöfe und Steige haben keine. Reich an
Beschreibung (Adresse, Barrierefreiheit, Ausstattung), aber ohne Geometrie. Das Streckennetz von
DB InfraGO (WFS, CC BY 4.0) führt Bahnhöfe als Punkte; sein Endpunkt antwortete am 29. September
mit 404.

Für die Umrisse bleibt **OpenStreetMap**. OpenStation bleibt als Quelle für Aufzüge und
Barrierefreiheit interessant — ein eigenes Thema.

### Stufe 2, OSM: gezählt für Nordrhein-Westfalen

Aus dem Geofabrik-Auszug NRW (914 MB) mit `osmium tags-filter` die Bahnhofs-Objekte gezogen
(7 MB) und für jeden unserer 782 Bahnhöfe in NRW ein **Gelände** gebildet:

1. **Anker:** der nächste OSM-Bahnhof (`railway=station`/`halt`, ohne U-, Stadt- und
   Museumsbahn) höchstens 400 m von unserem Punkt.
2. **Glieder:** Zug-Bahnsteige, Empfangsgebäude (`building=train_station`) und Bahnhofsflächen
   (`public_transport=station`) höchstens 500 m vom Anker, die diesem Anker näher sind als jedem
   anderen Bahnhof.
3. **Gelände:** die konvexe Hülle der Glieder, 20 m gepuffert. Die Hülle schließt ein, was
   zwischen Gebäude und Gleisen liegt — Halle, Läden, Wege, Vorplatz — und das ist gewollt.

| Rang | Bahnhöfe | mit Gelände | Rückfall 300 m | Gelände reicht weiter als 300 m |
|---|---|---|---|---|
| 3 | 46 | 44 (95 %) | 2 | 43 % |
| 2 | 567 | 554 (97 %) | 13 | 5 % |
| 1 | 169 | 164 (97 %) | 5 | 9 % |

Beispiele: Köln Hbf 6 Bahnsteige, 10 ha, reicht 358 m weit; Düsseldorf Hbf 15 Bahnsteige, 23 ha,
467 m; Dortmund Hbf 10 Bahnsteige, 15 ha, 587 m; Leichlingen 1 Bahnsteig, 0,2 ha, 137 m.

**Fallstrick:** Köln Messe/Deutz ist in OSM zwei Bahnhöfe, „hoch" und „tief". Die
Nächster-Anker-Regel gibt unserem einen Bahnhof nur die Bahnsteige des einen. Die Zuordnung muss
mehrere OSM-Bahnhöfe gleichen Namens zu einem von uns zusammenlegen können.

NRW ist dicht gemappt; im ländlichen Osten und Süden kann die Quote niedriger liegen. Die Zählung
für ganz Deutschland ist der erste Lauf des Prototyps.

## Der Plan

### Im Import

Einmal pro Stationsimport (in Produktion, wie die Ids — docs/46):

1. Geofabrik-Auszug Deutschland laden (rund 4,4 GB), mit `osmium tags-filter` auf Bahnhöfe,
   Bahnsteige, Empfangsgebäude und Bahnhofsflächen reduzieren (erwartet unter 50 MB). Kein
   Overpass: Der öffentliche Server lieferte schon beim Prototypen über Minuten nur Timeouts.
2. Pro Bahnhof das Gelände wie oben, mit der Zusammenlegung gleichnamiger OSM-Bahnhöfe.
3. Vereinfachen auf höchstens 24 Ecken; Plausibilität: Fläche unter 50 ha, unser Punkt höchstens
   400 m entfernt, sonst verworfen und im Importbericht genannt.

Neue, **eigene Tabelle** `station_outlines` (nicht Spalten in `stations`, siehe Lizenz):

| Feld | Inhalt |
|---|---|
| `station_id` | unser Bahnhof |
| `outline` | das Polygon, WGS84, ≤ 24 Ecken |
| `osm_ids` | die OSM-Objekte, aus denen es gebaut ist (für Nachvollziehbarkeit und Korrekturen) |
| `osm_timestamp` | Stand des OSM-Auszugs |
| `wake_lat`, `wake_lon`, `wake_radius_m` | Weckkreis: kleinster umschließender Kreis des Geländes + 100 m, mindestens 300 m, höchstens 1.000 m |

### Auf dem Telefon

- Das Gelände kommt mit dem Bahnhofsauszug aufs Gerät (docs/45), als eigener Block im Auszug, den
  ältere Builds überspringen.
- iOS und Android überwachen weiter **Kreise** (Polygone können sie nicht): den Weckkreis statt
  300 m um den Punkt.
- **iOS:** Der Nudge kommt beim ersten Fix **im Gelände** statt beim ersten Fix in 50 m. Punkt-in-
  Polygon auf dem Gerät; der Standort verlässt das Telefon nicht (docs/14), der native Layer
  spricht nicht mit der Admin-API (docs/15).
- **Android:** Der Kontroll-Fix nach den drei Minuten Dwell prüft „im Gelände" statt „in 300 m".
- **Kein Gelände:** der 300-m-Kreis ist die Grenze, auf beiden Plattformen gleich. Auf iOS heißt
  das: die 50-m-Schwelle entfällt ganz — ein Fix im Kreis genügt, wie heute auf Android.
- Die Entwicklungsseite (docs/25) zeichnet das Gelände mit ein.

### Draht

Nur neue, optionale Felder und ein neuer Block im Auszug. Ids bleiben unsere (`vs:…`); OSM-Ids
stehen nur in der Veröffentlichung (unten), nicht im Auszug fürs Telefon.

## Veröffentlichung und Namensnennung

### Was die ODbL verlangt (Einschätzung, keine Rechtsberatung)

- Die Gelände-Tabelle ist aus OSM **abgeleitet** und wird **öffentlich genutzt** (sie steckt in
  jeder App). Also: Namensnennung, und die abgeleitete Tabelle muss unter ODbL **angeboten**
  werden (ODbL 4.3, 4.4, 4.6).
- Share-Alike gilt für die **Gelände-Tabelle**, nicht für die App, nicht für die Stationsnamen
  und Ids aus DELFI und nicht für den Rest der Datenbank. Darum eine eigene Tabelle und ein eigener
  Block im Auszug: Sie ist mit unseren übrigen Daten *zusammengestellt* (Collective Database),
  nicht mit ihnen *vermengt*. Die Umrisse nie in die Spalten von `stations` schreiben.
- Die OSM Foundation beschreibt das in den Community Guidelines, u. a. „Collective Database" und
  „Produced Work": https://osmfoundation.org/wiki/Licence/Community_Guidelines, Attribution:
  https://osmfoundation.org/wiki/Licence/Attribution_Guidelines.

### Was wir veröffentlichen

- **Die Datei:** `https://verspaetomat.de/daten/bahnhofsumrisse.geojson` — pro Bahnhof unsere Id,
  der Name, das Polygon, die OSM-Ids, der OSM-Stand. Lizenz ODbL 1.0, im Kopf der Datei genannt.
  Erwartete Größe um 2 MB. Die Website erzeugt sie beim Bauen aus der Tabelle (`site/`), neu nach
  jedem Stationsimport.
- **Der Weg dorthin:** Der Import-Code wird mit dem Repo öffentlich, bevor die App erscheint; die
  Datei nennt den Commit, der sie gebaut hat. Das erfüllt 4.6 doppelt.
- **Eine Seite dazu:** `verspaetomat.de/daten` — was die Datei ist, woher sie kommt, Lizenz,
  Stand, und ein Satz: Wer einen Umriss falsch findet, verbessert ihn am besten in OSM; der
  nächste Import übernimmt es.

### Wo die Namensnennung steht

| Ort | Text |
|---|---|
| App, „Woher kommen die Daten?" (Einstellungen) | „Bahnhofsgelände: © OpenStreetMap-Mitwirkende, ODbL" mit Link auf openstreetmap.org/copyright |
| App, Entwicklungsseite, wo das Gelände gezeichnet wird | „Gelände © OpenStreetMap-Mitwirkende" unter der Zeichnung |
| Website, Seite `daten` und Fußzeile | wie oben |
| `bahnhofsumrisse.geojson` | Lizenz und Quelle im Kopf |
| Bahnhofsauszug für das Telefon | Quelle und Lizenz im Kopf des Gelände-Blocks |

Die Texte in `app/lib/content/legal.dart` (Datenherkunft) und `docs/13` werden ergänzt; wie immer
gilt: kein Satz, den die Implementierung nicht hält.

## Reihenfolge

1. Prototyp als `stellwerk stations outlines --dry-run`: ganz Deutschland, Zählung wie oben pro
   Rang und Bundesland, Liste der Verworfenen. Dazu 30 Gelände als Bild in `docs/assets` (10 große,
   10 mittlere, 10 ländliche) gegen den heutigen Punkt und die zwei Kreise.
2. Tabelle, Import in Produktion, Kopie nach Staging (wie die Stationen).
3. Auszug mit Gelände-Block; iOS und Android prüfen „im Gelände", sonst 300 m.
4. Veröffentlichung und Namensnennung — **vor** dem ersten Build, der das Gelände ausliefert.
5. Probefahrt: München Hbf Gleis 26, Köln Hbf Gleis 11, ein ländlicher Halt.
