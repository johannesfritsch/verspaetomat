# 48 — Bahnhofsumrisse: wo ein Bahnhof anfängt

Recherche und Prototyp-Beschreibung zu Issue #64, 29. September 2026. Noch keine Entscheidung und
kein Code. Johannes' Auftrag: „Let's first write a prototype description how this could look like!
Maybe we get the polygon outline of a trainstation from OSM? Or from the Bahn Open Data stuff?"

## Was heute gilt

Ein Bahnhof ist für die App ein **Punkt** — die Koordinate, die unsere Tabelle aus dem Feed
übernimmt (docs/44). Um ihn liegen zwei Kreise (`Geofence.swift`, `GeofenceManager.kt`, docs/25):

| Kreis | Radius | Aufgabe |
|---|---|---|
| Stationskreis | 300 m, fest | weckt die App; iOS liefert kleinere Kreise spät oder gar nicht |
| Nudge-Schwelle | 50 m um den Punkt | erst wenn ein eigener Standort-Fix so nah am Punkt liegt, kommt „Am Bahnhof?" |

Die 50 m sind die Schwachstelle: Sie messen den Abstand zu einem Punkt, nicht, ob man im Bahnhof
steht. Wo der Punkt am Rand liegt oder der Bahnhof groß ist, steht man auf dem Bahnsteig und ist
trotzdem „nicht am Bahnhof".

## Gemessen: zehn Bahnhöfe

Bahnsteige aus OpenStreetMap (Overpass, `railway=platform` im Umkreis von 450 m, ohne Tram-, Bus-
und U-Bahn-Steige) gegen den Punkt unserer Tabelle. Abgefragt am 29. September 2026.

| Bahnhof | weitester Bahnsteigpunkt | Anteil der Bahnsteige innerhalb 50 m | umschließender Kreis | sein Mittelpunkt liegt vom Punkt |
|---|---|---|---|---|
| München Hbf | 688 m | 0 % | r 399 m | 292 m |
| Hamburg Hbf | 468 m | 8 % | r 409 m | 89 m |
| Stuttgart, Hauptbahnhof (oben) | 355 m | 0 % | r 292 m | 70 m |
| Rheine, Bahnhof | 281 m | 0 % | r 149 m | 162 m |
| Kißlegg Bahnhof | 191 m | 36 % | r 169 m | 23 m |
| Hagen Hbf | 178 m | 0 % | r 73 m | 148 m |
| Langenargen Bahnhof | 166 m | 53 % | r 98 m | 70 m |
| Leichlingen Bf | 138 m | 17 % | r 110 m | 28 m |

Was das heißt:

- **Die 50-m-Schwelle trifft fast nie den Bahnsteig.** In München, Stuttgart, Rheine und Hagen
  liegt kein einziger Bahnsteigpunkt innerhalb 50 m unseres Punkts. Wer dort auf Gleis 26 wartet,
  bekommt keinen Nudge — es sei denn, er geht durch die Halle am Punkt vorbei.
- **Der 300-m-Kreis reicht nicht überall.** München reicht 688 m weit, Hamburg 468 m. Das Wecken
  klappt trotzdem meist, weil man auf dem Weg hinein durch den Kreis läuft; wer vom Holzkirchner
  Flügelbahnhof kommt, womöglich nicht.
- **Der Punkt ist oft nicht die Mitte.** 292 m in München, 162 m in Rheine: Die Feed-Koordinate
  ist ein Eingang, ein Empfangsgebäude oder der Schwerpunkt der Halte, nicht der Bahnhof.
- Kleine Halte (Leichlingen, Langenargen) sind 100–170 m lang. Ein Bahnsteig ist länger als die
  Schwelle, auch dort.

Grenzen der Messung, ehrlich: **Köln Hbf fehlt**, weil seine Bahnsteige als Multipolygon-Relationen
gemappt sind und mein Skript die Relationen in diesem Lauf nicht zu fassen bekam (eine erste
Abfrage hat sie gefunden: sieben Bahnsteige, rund 410 × 320 m). **Hagen** zeigt nur einen
Bahnsteig — die anderen sind vermutlich nur als `public_transport=platform` getaggt. **Berlin Hbf**
ist nicht gelaufen. Die Messung zeigt die Richtung, keine fertige Statistik.

## Woher ein Umriss kommen kann

### 1. Unsere eigenen Feeds: die Steige (sofort, ohne neue Lizenz)

Der Import liest schon heute **jede Zeile** von `stops.txt`, auch jeden Steig (`location_type = 0`)
mit `stop_lat`/`stop_lon` und `parent_station` (`backend/src/stations/gtfs.rs`). DELFI führt für
große Bahnhöfe einen Steig pro Gleisabschnitt: Stuttgart `de:08111:6115:1:1` bis `…:8:16`. Die
konvexe Hülle dieser Punkte, gepuffert, ist ein grober Umriss **der Gleise** — genau der Teil, auf
dem man steht, wenn man auf einen Zug wartet.

- Vorteil: keine neue Quelle, keine neue Lizenz (dieselbe wie heute), gleiche Ids.
- Schwäche: Punkte, keine Flächen; ein Halt mit einem einzigen Steig hat keine Hülle, nur den Punkt.
  Wie viele Steige ein Bahnhof im Mittel hat, ist noch nicht gezählt — das ist die erste Frage an
  den Prototypen.

### 2. OpenStreetMap: Bahnsteige und Bahnhofsgebäude (genau, mit Lizenzpflicht)

Wie Bahnhöfe gemappt sind (verifiziert an Köln, München, Hamburg, Stuttgart und fünf kleineren):

- `railway=platform` (und/oder `public_transport=platform` + `train=yes`) als Fläche oder als
  Linie, bei großen Bahnhöfen oft als Multipolygon-Relation, mit `ref` = Gleisnummern („9;10").
- `building=train_station` für Empfangsgebäude und Hallen.
- `public_transport=stop_area`-Relationen, die Station, Steige und Eingänge zusammenfassen. In
  Köln gibt es drei davon (Hauptbahnhof, Dom/Hbf, Breslauer Platz) — Tram und Bus inklusive, also
  **nicht** ohne Filter brauchbar.
- Tram- und Bussteige tragen oft `tram=yes`/`bus=yes`, aber nicht immer; der Filter muss auch am
  Namen und an der Nähe zu `railway=station` festmachen.

Beschaffung: nicht über die öffentliche Overpass-API — die hat heute schon beim Prototypen über
Minuten nur Timeouts geliefert. Sondern einmal pro Import aus dem **Geofabrik-Auszug Deutschland**
(`germany-latest.osm.pbf`, rund 4 GB) mit `osmium tags-filter` auf die paar Tags, die wir brauchen.

**Lizenz: ODbL.** Meine Einschätzung (keine Rechtsberatung): Eine Tabelle „Umriss pro Bahnhof",
die wir aus OSM ableiten und an Telefone ausliefern, ist eine *abgeleitete Datenbank*, die
öffentlich genutzt wird. Dann gilt Share-Alike **für diese abgeleitete Tabelle** — nicht für die
App und nicht für unsere übrigen Daten —, und „© OpenStreetMap-Mitwirkende" muss sichtbar genannt
werden (Datenherkunft, Website). Da das Repo ohnehin öffentlich wird, ist das billig: Die
Umriss-Tabelle wird unter ODbL mit veröffentlicht. Vor dem Start mit Johannes klären.
Quelle: https://www.openstreetmap.org/copyright, https://osmfoundation.org/wiki/Licence/Community_Guidelines

### 3. DB Open Data (Punkte, keine Umrisse — nicht verifiziert)

DB InfraGO veröffentlicht ihr Streckennetz mit Betriebsstellen als WFS/WMS unter CC BY 4.0
(Geodatenkatalog: https://gdk.gdi-de.org/geonetwork/srv/api/records/ec0237d0-37b7-11e6-bdf4-0800200c9a66).
Nach allem, was die Suche zeigt, sind Bahnhöfe dort **Punkte**; Bahnsteigdaten gibt es als
Attribute (Länge, Höhe), nicht als Fläche. **Nicht verifiziert:** Der WFS-Endpunkt
`geovdbn.deutschebahn.com/geoserver/tn-ra/ows` antwortete am 29. September mit 404; die
Feature-Typen konnte ich nicht lesen. Wenn es dort doch Flächen gibt, wäre CC BY die angenehmere
Lizenz als ODbL — eine Anfrage an Geodaten.DBInfraGO@deutschebahn.com klärt das.

### Nicht weiter verfolgt

ALKIS-Gebäudeumrisse (Ländersache, 16 Lizenzen, zeigt Gebäude, nicht Bahnsteige) und INSPIRE
Transport Networks (Linien, keine Bahnhofsflächen).

## Prototyp: wie es aussehen könnte

**Zwei Stufen, beide im Import, beide fallen auf heute zurück.**

1. **Stufe 1, Steige aus dem Feed.** Pro Bahnhof die Punkte seiner Steige sammeln; ab drei
   Punkten die konvexe Hülle, 25 m gepuffert, auf höchstens 24 Ecken vereinfacht.
2. **Stufe 2, OSM.** Zug-Bahnsteige (Filter oben) im Umkreis von 700 m um den Bahnhofspunkt,
   zugeordnet über den Namen oder die `stop_area` des nächsten `railway=station`; ihre
   Vereinigung, 25 m gepuffert, vereinfacht. Wo OSM einen Umriss hat, gewinnt er.

Daraus pro Bahnhof, neu in der Tabelle (`stations`, additiv):

| Feld | Inhalt |
|---|---|
| `outline` | das Polygon, vereinfacht (≤ 24 Ecken) |
| `outline_source` | `feed` oder `osm`, für die Namensnennung und die Diagnose |
| `wake_lat`, `wake_lon`, `wake_radius_m` | Kreis zum Wecken: kleinster umschließender Kreis des Umrisses + 100 m, mindestens 300 m, höchstens 1.000 m |

**Auf dem Telefon.** Der Umriss kommt mit dem Bahnhofsauszug aufs Gerät (docs/45), nicht über
eine neue Abfrage. Der native Layer registriert wie heute Kreise — iOS und Android können keine
Polygone überwachen —, nur eben den `wake`-Kreis statt 300 m um den Punkt. Die Nudge-Schwelle wird
**„ein Fix liegt im Umriss"** statt „ein Fix liegt 50 m am Punkt": ein Punkt-in-Polygon-Test auf
dem Gerät. Der Standort verlässt das Telefon dafür nicht (docs/14); der Server rät nichts, und der
native Layer spricht nicht mit der Admin-API (docs/15).

**Fallback.** Ohne Umriss (ein Halt mit einem Steig und nichts in OSM) bleibt alles, wie es ist:
300 m wecken, 50 m um den Punkt. Ein älteres Build ignoriert die neuen Felder.

**Draht.** Nur neue, optionale Felder im Auszug und in `stations/nearby`; die Ids bleiben unsere
(`vs:…`), MOTIS- und OSM-Ids verlassen den Server nicht.

## Wie wir es prüfen, bevor es gebaut wird

1. Den Prototyp-Import als `stellwerk stations outlines --dry-run` laufen lassen: wie viele
   Bahnhöfe bekommen einen Umriss aus dem Feed, wie viele aus OSM, wie viele keinen.
2. 30 Bahnhöfe von Hand ansehen: 10 große (Köln, München, Hamburg, Berlin, Frankfurt, Leipzig …),
   10 mittlere, 10 ländliche Halte. Umriss auf einer Karte gegen den heutigen Punkt und die zwei
   Kreise, als Bild in docs/assets.
3. Die Entwicklungsseite (docs/25) zeichnet den Umriss mit ein — dort sieht man auf der Reise, ob
   der Nudge am Bahnsteig gekommen wäre.
4. Eine echte Probefahrt mit einem Release-Build: München Hbf Gleis 26, Köln Hbf Gleis 11,
   ein ländlicher Halt.

## Offene Fragen an Johannes

1. **ODbL ja oder nein?** OSM ist die genaueste Quelle, bringt aber Share-Alike für die
   Umriss-Tabelle und eine sichtbare Namensnennung. Alternative: nur Stufe 1 (Feed-Steige), grober,
   aber ohne neue Lizenz.
2. **Soll ich DB InfraGO anschreiben**, ob es Bahnsteigflächen unter CC BY gibt?
3. **Wie streng soll „am Bahnhof" sein?** Im Umriss heißt: auch auf dem Bahnhofsvorplatz, wenn wir
   das Gebäude mitnehmen; nur Bahnsteige heißt: erst am Gleis. Ich würde nur Bahnsteige + 25 m
   nehmen — der Nudge soll kommen, wenn man auf den Zug wartet.
4. **Reihenfolge:** erst die Zählung aus Stufe 1 (ein Nachmittag, keine neue Quelle), dann
   entscheiden, ob Stufe 2 den Aufwand wert ist?
