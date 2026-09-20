# 45 — Die Bahnhöfe auf dem Telefon

Entschieden am 20. September 2026, Issue #39. Dies ist die Formatbeschreibung des Stationsauszugs
`.vst`: Byte für Byte, damit vier Sprachen dieselbe Datei lesen — Rust auf dem Laptop, Dart in der
App, Swift und Kotlin in den Hintergrundschichten. Wer einen Leser schreibt, schreibt ihn gegen
dieses Dokument und gegen nichts anderes.

## Warum überhaupt eine Datei

docs/44 hat die Bahnhöfe in unsere eigene Tabelle geholt. Damit geht bei „welche Bahnhöfe sind hier
in der Nähe" keine Koordinate mehr an Transitous. Sie geht aber weiter an **uns**: docs/25 hat auf
einer echten Fahrt vierzehn Nachfragen in neunundfünfzig Minuten gezählt, gegen ein aufgeschriebenes
Budget von „ein Tag quer durch Deutschland: unter 10". Jede davon ist eine Position, die ein Telefon
verlässt, dessen Besitzer gerade nicht hinschaut.

Bahnhöfe ändern sich zweimal im Jahr. Eine Frage, deren Antwort ein halbes Jahr hält, muss man nicht
jedes Mal stellen. Also rendern wir die Tabelle einmal auf dem Laptop, veröffentlichen sie als
statische Datei auf der Website, und das Telefon rechnet selbst.

## Was diese Änderung ist — und was noch nicht

Diese Änderung baut die Datei und veröffentlicht sie. **Sie liest noch niemand.**

| Schritt | Issue | Stand |
|---|---|---|
| Auszug rendern, veröffentlichen | #39, Server-Hälfte | dieses Dokument |
| Dart liest ihn: `nearby_monitor.dart`, die Bahnhofssuche, `app/assets/stations/stations.vst` | #39, Dart-Hälfte | offen |
| `Geofence.swift`, `GeofenceManager.kt` scannen ihn im Hintergrund | eigenes Issue | offen |

Bis die Dart-Hälfte da ist, fragen `Geofence.swift:1208` und `GeofenceManager.kt:294` weiter
`/v1/stations/nearby`. Die alten Routen `/v1/stations/nearby` und `/v1/stations/search` bleiben,
solange Builds im Feld sind, die sie rufen — also auf absehbare Zeit immer.

## Das Format

Alle Zahlen **little-endian**, immer, nie die des Hosts. Alle Offsets sind Byte-Offsets ab
Dateianfang, außer die Tabelle sagt etwas anderes.

### Der Kopf — 32 Bytes ab Offset 0

| Offset | Größe | Typ | Feld | Wert |
|---|---|---|---|---|
| 0 | 4 | `u8[4]` | `magic` | `"VSST"` = `0x56 0x53 0x53 0x54` |
| 4 | 2 | `u16` | `format` | `1` |
| 6 | 2 | `u16` | `header_len` | `32` — hier fangen die Datensätze an |
| 8 | 4 | `u32` | `count` | Anzahl der Datensätze |
| 12 | 4 | `u32` | `record_len` | `20` — Bytes pro Datensatz |
| 16 | 4 | `u32` | `blob_len` | Bytes im Namensblock |
| 20 | 4 | `u32` | `generated` | Unix-Sekunden, UTC (reicht bis 2106) — wann *dieser Datenbank* ihr Import fertig wurde, siehe unten |
| 24 | 4 | `u32` | `version` | die Seriennummer des Auszugs, siehe unten |
| 28 | 4 | `u32` | `crc32` | CRC-32/ISO-HDLC über die Bytes `[header_len, EOF)` |

`crc32` ist das gewöhnliche zlib/PNG-CRC-32: gespiegeltes Polynom `0xEDB88320`, Startwert
`0xFFFFFFFF`, abschließendes XOR `0xFFFFFFFF`. Rust: `crc32fast`. Kotlin: `java.util.zip.CRC32`.
Swift und Dart: eine 256er-Tabelle, etwa zwanzig Zeilen.

### Die Datensätze — `count * record_len` Bytes ab `header_len`

| Offset | Größe | Typ | Feld | Bedeutung |
|---|---|---|---|---|
| 0 | 4 | `u32` | `id` | unsere Bahnhofs-ID — die `4711` aus `vs:4711` (`stations/mod.rs`) |
| 4 | 4 | `i32` | `lat_e6` | Breite × 1 000 000 |
| 8 | 4 | `i32` | `lon_e6` | Länge × 1 000 000 |
| 12 | 1 | `u8` | `rank` | die Leiter aus docs/23: 3 Fernverkehr, 2 Nahverkehr, 1 nur S-Bahn |
| 13 | 1 | `u8` | `flags` | Bit 0 = `looks_like_station(name)` (`train/transitous.rs`); Bits 1–7 sind 0 |
| 14 | 1 | `u8` | `name_len` | Bytes des UTF-8-Namens, 1..=255 |
| 15 | 1 | `u8` | `reserved` | wird als 0 geschrieben; **Leser ignorieren es, sie prüfen es nicht** |
| 16 | 4 | `u32` | `name_off` | Byte-Offset **in den Namensblock**, ab dessen erstem Byte |

Zwanzig Bytes, nicht die sechzehn, die Issue #39 skizziert hat: In sechzehn ist kein Platz für einen
ausdrücklichen Namens-Offset, und die Alternativen — eine Präfixsumme, die O(n) aufzulösen ist, oder
ein viertes Segment mit einem Offset-Array — kosten entweder den wahlfreien Zugriff oder ein
Segment, das man in vier Sprachen beschreiben muss. Zwanzig ist durch vier teilbar, also liegt jedes
`u32`/`i32` auf einer Vier-Byte-Grenze. Gemessen kosten die vier zusätzlichen Bytes bei 7 604
Bahnhöfen 30 416 Bytes roh, von denen gzip das meiste wieder wegnimmt.

**Die Datensätze sind streng aufsteigend nach `id` sortiert.** `Index::load` erzeugt diese Reihenfolge
ohnehin (`order by id`); `render` prüft sie, statt zu sortieren. Ein Leser kann binär nach einer ID
suchen — 13 Lesezugriffe, ohne beim Laden einen Index zu bauen.

Die Bytes 0..14 sind alles, was ein Nähe-Scan braucht. Er fasst den Namensblock nie an.

### Der Namensblock — `blob_len` Bytes ab `header_len + record_len * count`

UTF-8-Namen, aneinandergehängt: keine Trenner, keine Terminatoren, keine Längenpräfixe.

```
absoluter_offset = header_len + record_len * count + name_off
name             = utf8(datei[absoluter_offset .. absoluter_offset + name_len])
```

Jeder Ausschnitt beginnt und endet auf einer UTF-8-Zeichengrenze. Zwei Datensätze mit
byte-identischem Namen teilen sich einen Ausschnitt (das erste Vorkommen in Datensatzreihenfolge
gewinnt) — ein Leser darf sich nicht darauf verlassen, dass sie es *nicht* tun. Gemessen: 7 600
verschiedene Namen bei 7 604 Bahnhöfen; die vier Doppelten sind „Wissembourg, Bahnhof", „Oelsnitz,
Bahnhof", „Zimmern, Bahnhof" und „Wiesenburg, Bahnhof". Das Teilen spart 72 Bytes und existiert
dafür, dass die Datei eine Funktion der Tabelle ist und sonst nichts.

Die Namen sind die **Anzeigenamen**, genau so, wie `display_station_name` sie beim Import erzeugt
hat. Das Telefon leitet nie einen Namen selbst ab. Gemessen: längster Name 51 Bytes, Mittel 16,860.
`render` verweigert alles über 255 Bytes, statt zu kürzen.

### Die Datei als Ganzes

`dateilänge == header_len + record_len * count + blob_len`, exakt, gerechnet als `u64`.

## Endianness, Ausrichtung, Koordinaten

| Sprache | `lat_e6` an Datensatz-Offset 4 |
|---|---|
| Rust | `i32::from_le_bytes(rec[4..8].try_into().unwrap())` |
| Dart | `ByteData.view(bytes.buffer).getInt32(base + 4, Endian.little)` |
| Swift | `raw.loadUnaligned(fromByteOffset: base + 4, as: Int32.self).littleEndian` |
| Kotlin | `ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN).getInt(base + 4)` |

Leser geben die Byte-Reihenfolge ausdrücklich an, obwohl jedes Ziel little-endian ist. Swift benutzt
`loadUnaligned(fromByteOffset:as:)` und nie `load(as:)`, das abstürzt, wenn der Compiler die
Ausrichtung nicht beweisen kann.

**Gerundet wird nur beim Bauen:** `lat_e6 = (lat * 1_000_000.0).round() as i32` (`f64::round`, von
der Null weg). Ein Leser teilt nur. Über einen Grenzfall kann kein Leser anderer Meinung sein.

Gemessen an der Tabelle von heute: 0 von 7 604 Zeilen haben mehr als sechs Nachkommastellen, und der
größte Koordinatenversatz durch den Mikrograd-Rundlauf ist **0,0 m**. Solange das so ist, ist die
Antwort aus der Datei Zeichen für Zeichen die Antwort des Servers. Liefert ein Feed irgendwann mehr
Stellen, ist der schlimmste Fall ein halbes Mikrograd — 5,6 cm in der Breite, 3,5 cm in der Länge auf
51° N — gegen ein Rangband von 300 m. Sichtbar wird das nur als zwei Bahnhöfe, die auf derselben
Bandkante wenige Zentimeter auseinanderliegen und die Plätze tauschen.

## Was ein Leser prüft, in dieser Reihenfolge

1. `dateilänge >= 32`
2. `magic == "VSST"`
3. `format == 1` — alles andere: den Auszug behalten, den man schon hat
4. `header_len >= 32` — ein Format-1-Leser ignoriert die Bytes `[32, header_len)`
5. `record_len >= 20` — er liest die ersten 20 Bytes jedes Datensatzes und springt um `record_len`
6. `count >= 1`
7. `dateilänge == header_len + record_len * count + blob_len`, als `u64`
8. `crc32(datei[header_len..]) == kopf.crc32` — **`header_len`, nie eine 32 im Code**
9. jeder Datensatz: `name_len >= 1`, `name_off + name_len <= blob_len`

Was daran scheitert: die ganze Datei verweigern. Es gibt kein teilweises Lesen.

`backend/src/stations/extract.rs::parse` ist genau diese Liste, in dieser Reihenfolge. Sie läuft auf
dem Laptop, bevor ein Byte in den Arbeitsbaum geschrieben wird.

## Wie das Format wächst

`format` ändert sich **nur, wenn ein vorhandenes Byte seine Bedeutung ändert**. Ein neues Feld am
Ende eines Datensatzes erhöht `record_len`, ein neues Kopffeld erhöht `header_len`; `format` bleibt
1, und jedes Telefon, das schon draußen ist, liest weiter. Das ist die Draht-Regel aus CLAUDE.md,
aufgeschrieben für eine Binärdatei. `reserved` an Datensatz-Offset 15 ist der erste Platz für ein
neues Byte — deshalb prüfen Leser es nicht, sondern ignorieren es.

## Wie groß das ist

```
bytes = 32 + 20 * count + summe(len(utf8(name)) über verschiedene Namen)
```

Gemessen an der Tabelle von heute (7 604 Bahnhöfe, Import 7):

| | Bytes |
|---|---|
| Kopf | 32 |
| Datensätze (7 604 × 20) | 152 080 |
| Namensblock (7 600 verschiedene Namen) | 128 132 |
| **roh** | **280 244** |
| **gzip, wie `stellwerk` sie schreibt** (flate2, `Compression::best`) | **147 232** |
| gzip -9, zum Vergleich | 147 549 |

36,9 Bytes pro Bahnhof; tausend neue Bahnhöfe kosten etwa 37 KB.

## Warum nicht einfach JSON

**Nicht wegen der Bytes.** Gemessen sind dieselben fünf Felder als kompaktes JSON
(`[{"id":…,"n":"…","lat":…,"lon":…,"r":…}]`, kürzeste rundlauffeste Gleitkommaschreibweise) 552 577
Bytes roh und 150 968 mit gzip -9. Die Binärdatei steht mit demselben gzip -9 bei 147 549 und spart
über den Draht also 3 419 Bytes, 2,26 %. Für 2 % baut niemand ein eigenes Format.

Es entscheidet der Schritt danach — `Geofence.swift` und `GeofenceManager.kt`, die in einem
Standort-Callback im Hintergrund laufen, wo iOS dem Prozess ein paar Sekunden gibt und Android im
Doze sein kann:

1. **Der Nähe-Scan darf nichts allozieren.** Einmal `mmap`, ein `UnsafeRawBufferPointer` bzw. ein
   `ByteBuffer`, `count` mal vierzehn Bytes lesen, die besten drei nach `nearby_order` behalten.
   Nach dem `mmap` keine einzige Allokation, und nur die 152 KB Datensätze werden eingelagert. JSON
   erzeugt bei jedem Aufwachen 7 604 Dictionaries und 7 604 Strings.
2. **Bit 0 in `flags` hält den Namensblock aus dem Ranking heraus.** Der Gleichstand im 300-m-Band
   wird mit `looks_like_station` gebrochen, einer Suffixprüfung über UTF-8. Gemessen tragen 2 732
   von 7 604 Bahnhöfen das Flag — es ist ein echter Gleichstandsbrecher, kein theoretischer. Als Bit
   ist die innere Schleife reine Arithmetik.
3. **Eine Schleifenform in vier Sprachen.** Konstante Schrittweite über ein flaches `[u8]`.
4. **Binäre Suche nach der ID**, ohne beim Laden eine Map zu bauen.
5. **Es wird einmal entschieden.** Ein JSON-Auszug müsste für den nativen Schritt neu entschieden
   werden.

## Versionen, Dateinamen, der Zeiger

**`version`** ist die ID der jüngsten übernommenen Zeile in `station_imports`. Sie steigt, wird nie
wiederverwendet, und sie bedeutet einem Menschen etwas: *der siebte Import, den wir angenommen
haben*. Sie steht im Kopf der Datei, im Dateinamen und im Zeiger.

Sie gilt **pro Datenbank**. Die Entwicklungsdatenbank ist bei Import 7, die Produktion hat ihre
eigene Nummer. Deshalb verweigert `stellwerk stations extract` das Schreiben in den Arbeitsbaum für
jedes Ziel außer `--prod`; alles andere braucht `--out <dir>`.

**`crc32`** ist die Inhaltsidentität. `render` ist eine reine Funktion von `(index, version,
generated)`, und alle drei kommen aus der Tabelle — zwei Auszüge mit derselben `version` haben also
immer dasselbe `crc32`. Umgekehrt gilt das nicht: Ein erneuter Import desselben Fahrplans ergibt
eine neue `version` über identischen Datensätzen.

| | URL | `Cache-Control` |
|---|---|---|
| Datei | `https://verspaetomat.de/stations/stations-<version>.vst` | `public, max-age=31536000, immutable` |
| Zeiger | `https://verspaetomat.de/stations/latest.json` | `public, max-age=3600` |

`site/static/` wird vom Website-Generator rekursiv nach `site/dist/` kopiert, also wird
`site/static/stations/` ohne eine Zeile Generatoränderung zu `site/dist/stations/`. `build()` löscht
`dist/` vorher ganz, also kann eine aus `static/` entfernte Version dort nicht überleben. `site/dist`
ist eingecheckt und `dist_ist_aktuell` vergleicht jede Datei Byte für Byte — ein vergessenes
`cd site && cargo run` fällt in `cargo test` auf.

`latest.json`, so wie `stellwerk` ihn schreibt:

```json
{
  "version": 7,
  "format": 1,
  "count": 7604,
  "bytes": 280244,
  "crc32": 2957696257,
  "generated": "2026-09-20T16:11:20Z",
  "feed_version": "2026-09-12T15:06:17",
  "url": "/stations/stations-7.vst"
}
```

`generated` ist die Importzeit dieser Datenbank, `feed_version` die Fahrplanversion aus dem Feed —
zwei verschiedene Dinge, die beide wie ein ISO-Zeitstempel aussehen und nebeneinander stehen. Wer
sie verwechselt, liest das Fahrplandatum als Importzeit; das ist beim Schreiben der Dart-Hälfte
einmal passiert. `serde_json::to_vec_pretty` plus abschließendes Newline; die Schlüsselreihenfolge ist die
Deklarationsreihenfolge, die Bytes sind also stabil und `dist_ist_aktuell` bleibt still. `crc32` ist
eine JSON-Zahl — ein `u32` ist in einem Double exakt. `url` ist site-relativ, der Host ist damit
Sache der App und eine Staging-Seite funktioniert unverändert. `feed_version` ist eine
undurchsichtige Zeichenkette aus dem Feed — heute `2026-09-12T15:06:17`. Niemand liest sie, niemand
zerlegt sie.

### Wie die App fragt, ob es einen neueren gibt (für die Dart-Hälfte)

1. Höchstens wöchentlich: `GET /stations/latest.json` mit `If-None-Match: <der ETag-Wert, den sie
   zuletzt bekommen hat, Byte für Byte, samt Suffix>`. `304` → nichts zu tun.
2. `version` gleich der des **heruntergeladenen** Auszugs, den das Telefon hält → nichts zu tun.
   Ausdrücklich nicht gegen die Version des mitgelieferten Assets vergleichen: siehe „Drei Zahlen,
   die keine Reihenfolge sind" weiter unten.
3. Sonst `GET <url>`, dann prüfen: die Länge des **ausgepackten** Körpers gleich `bytes`;
   `header_len` aus den Bytes 6..8 lesen und `crc32(body[header_len..])` gegen das `crc32` des
   Zeigers halten; `magic`, `format`, `count` und `version` im Kopf gegen den Zeiger halten. Bei
   jeder Abweichung: den Download wegwerfen und behalten, was man hat.

   **Nicht `Content-Length` gegen `bytes` halten.** Sobald Caddy die `.gz`-Datei daneben ausliefert,
   ist `Content-Length` die *komprimierte* Länge. Gemessen an der echten Konfiguration: mit
   `Accept-Encoding: gzip` kommen `Content-Length: 147232` und `Content-Encoding: gzip`, ohne
   `Content-Length: 280244`. Die Prüfung gehört hinter das Auspacken.
4. Nach `<documents>/stations/stations-<v>.vst.part` schreiben, fsync, an die richtige Stelle
   umbenennen, dann die ältere Datei löschen. Das Umbenennen ist der Commit.

### Drei Zahlen, die keine Reihenfolge sind

Im Kopf und im Zeiger stehen drei Zahlen, die aussehen, als könnte man mit ihnen entscheiden,
welcher von zwei Auszügen der neuere ist. Keine davon kann das, sobald die beiden aus
verschiedenen Datenbanken kommen — und genau das ist der Normalfall, weil das mitgelieferte Asset
irgendwann gerendert wurde und der Download von der Produktion kommt.

| Zahl | was sie ist | warum sie nicht ordnet |
|---|---|---|
| `version` | die Id der jüngsten übernommenen Zeile in `station_imports` | eine Seriennummer ihrer eigenen Datenbank. Gemessen am 20. September 2026: Produktion steht bei **1**, die Entwicklungsdatenbank bei **7**. Die 7 ist nicht neuer als die 1, sie ist aus einer anderen Zählung. |
| `generated` | `coalesce(finished_at, started_at)` der Importzeile — wann *dieser Datenbank* ihr Import lief | ein Zufall des Zeitpunkts. Gemessen: Produktion `2026-09-20T17:07:39Z`, ein Laptop-Render `2026-09-20T16:11:20Z` — die Produktion liegt heute 56 Minuten vorn und nach dem nächsten Import auf dem Laptop wieder hinten. Es ist **kein** Renderzeitpunkt und **nicht** das Fahrplandatum. |
| `feed_version` | die Fahrplanversion aus dem GTFS-Feed, undurchsichtig | auf beiden Seiten dieselbe, sobald beide denselben Feed importiert haben — gemessen beide `2026-09-12T15:06:17`. Gleichstand ordnet nichts. |

Die Regel, die als einzige gegen alle drei immun ist: **ein Download, der die Prüfung aus Schritt 3
besteht, ersetzt immer das mitgelieferte Asset.** Das Asset ist der Boden für den ersten Start und
nie eine Zahl, die man schlagen muss. Ein Vergleich von `version` gehört allein zwischen den Zeiger
und den zuletzt *heruntergeladenen* Auszug, also innerhalb einer Datenbank.

Das ist keine Vorsichtsmaßnahme gegen etwas Ausgedachtes. Mit der Regel „höhere `version` gewinnt"
hätte ein Telefon den ersten echten Download verworfen (`1 >= 7` ist falsch) und den Laptop-Stand
behalten, bis die Produktion sieben Importe weit ist — bei zweimal im Jahr rund drei Jahre. Mit der
Regel „neueres `generated` gewinnt" wäre es heute gutgegangen und hätte zwei Minuten später
angefangen, still zu scheitern: so lange dauert ein Import auf dem Laptop und ein neues Render.

### Drei gemessene Eigenheiten der Auslieferung

Gemessen gegen genau diese Caddy-Konfiguration (Caddy 2.10.2, die `.vst` und die `.vst.gz`
nebeneinander), nicht erschlossen:

**Eine 206 ist der Normalfall, keine Störung.** Sobald `precompressed gzip` die `.gz`-Datei
ausliefert, antwortet Caddy mit `206 Partial Content` und einem `Content-Range: bytes
0-147231/147232`, das die ganze Datei umfasst — auch ohne `Range` im Request. Ausgepackt ist der
Körper Byte für Byte die `.vst`. Mit `Accept-Encoding: identity` oder ganz ohne den Header kommt eine
gewöhnliche `200` mit 280 244 Bytes. Das liegt an `precompressed` selbst, nicht an `encode` — ohne
`encode` passiert dasselbe. Ein Leser, der auf `== 200` prüft, verwirft also jeden komprimierten
Download; **200 und 206 sind beide gültig.** `dart:io` schickt `Accept-Encoding: gzip` von sich aus.

**Der ETag gehört zur Kodierung.** Bei `precompressed` sind es zwei verschiedene Dateien und damit
zwei verschiedene ETags — gemessen `"dlketfybbzzr608k"` ohne und `"dlketfybpe2t35ls"` mit gzip (bei
Kompression durch `encode` hängt Caddy stattdessen `-gzip` an denselben Wert an). Wer den einen
speichert und ihn mit dem anderen `Accept-Encoding` zurückspielt, bekommt eine 200 mit 280 244 Bytes
statt einer 304 mit null. Also: **den Header-Wert genau so speichern und zurückspielen, wie er
ankam, und dabei dasselbe `Accept-Encoding` schicken wie beim letzten Mal.** Gemessen: gleiches
Paar → `304`, 0 Bytes; gekreuzt → `200`, 280 244 Bytes.

**Der Content-Type ist festgenagelt.** Caddy hält `.vst` für eine Visio-Schablone und liefert ohne
Zutun `application/vnd.visio` aus — die Annahme „eine unbekannte Endung wird `application/
octet-stream`" stimmt für diese Endung nicht. Deshalb steht im Caddyfile eine `header`-Zeile, die
den Typ auf `application/octet-stream` setzt; gemessen greift sie für beide Kodierungen, und
`latest.json` bleibt `application/json`.

Und der ETag ist immer nur ein Hinweis, nie die Identität: Caddy leitet ihn aus Änderungszeit und
Größe der ausgelieferten Datei ab, und `site/dist` ist auf dem Server ein Git-Checkout — jede
Operation, die die Datei neu schreibt, ändert den ETag, ohne ein Byte zu ändern. Die Identität ist
das `crc32` im Zeiger.

## Der Befehl

```
stellwerk --prod stations extract [--out <dir>] [--keep 1] [--asset] [--dry-run]
```

Er holt die Bytes von `GET /admin/stations/extract`, liest sie mit demselben Leser, den das Telefon
bekommt, vergleicht Version und Anzahl gegen `GET /admin/stations` und schreibt dann
`stations-<v>.vst`, `stations-<v>.vst.gz` und `latest.json`.

Ein echter Lauf gegen die Entwicklungsdatenbank (dort ist der jüngste übernommene Import die 7):

```
$ stellwerk stations extract --out /tmp/auszug --keep 1
Auszug 7  ·  7604 Stationen  ·  273,7 KB (gzip 143,8 KB)  ·  Fahrplanstand 2026-09-12T15:06:17  ·  CRC b04add01
Geschrieben: /tmp/auszug/stations-7.vst
Geschrieben: /tmp/auszug/stations-7.vst.gz
Geschrieben: /tmp/auszug/latest.json
Entfernt: stations-5.vst und stations-5.vst.gz
Weiter: cd site && cargo run  ·  site/dist committen  ·  deployen  ·  danach erst die App bauen.
```

In Produktion steht statt `--out` nur `stellwerk --prod stations extract`; die Dateien landen dann
in `site/static/stations/` und heißen nach der Importnummer der Produktionsdatenbank.

### Nach einem angenommenen Import

Ein Import ändert die Tabelle, und an der Tabelle hängt mehr als der Auszug. Der Reihe nach:

1. **`stellwerk --prod stations import`** — die neue Tabelle. Alles Weitere hängt daran.
2. **`cd backend && cargo test --release --lib write_the_nearby_probe_fixture -- --ignored`** —
   `testdata/stations/nearby-probes.tsv` neu erzeugen. Die Datei nennt in ihrem Kopf `crc32` und
   `count` der Tabelle, zu der sie gehört, und der Dart-, der Swift- und der Kotlin-Leser prüfen das
   gegen den Auszug in ihrer Hand. (Rust prüft nicht dagegen — Rust erzeugt sie.) Nach einem Import
   passt sie nicht mehr.
3. **`stellwerk --prod stations extract`** — `.vst`, `.vst.gz`, `latest.json`, und mit `--asset`
   die Kopie in der App.
4. **`cd site && cargo run`**, `site/dist` committen, deployen. Website, Backend, dann TestFlight.

Schritt 2 erzeugt aus der Datenbank, auf die `DATABASE_URL` zeigt — also der lokalen, nicht der
Produktion. Damit das stimmt, muss derselbe Import auch dort angekommen sein. Die Probe darauf ist
eingebaut und kostet nichts: Das `crc32` im Kopf des Fixtures muss dem `crc32` in der
veröffentlichten `latest.json` gleichen. Tut es das nicht, beschreiben die beiden verschiedene
Tabellen, und das fällt beim nächsten Testlauf auf statt auf einem Telefon.

Schritt 2 vergessen heißt: die Leser-Testsuites werden rot, alle mit „the probe fixture belongs to
a different extract". **Das ist ein Papierschnitt, kein Datenproblem** — ein veralteter Fixture kann
nie ein falsches Bestehen erzeugen, immer nur ein lautes und richtig benanntes Fehlschlagen. Der
Befehl steht auch in den ersten Zeilen der Datei selbst.

`Unverändert: Auszug <v> liegt vollständig im Baum.` steht erst da, wenn **jede** Datei geprüft
wurde, die der Satz behauptet — die `.vst`, die `.vst.gz`, `latest.json` und, mit `--asset`, die
Kopie unter `app/assets/`. Fehlt eine davon, wird genau sie geschrieben und genau sie gemeldet.

`--keep 1` lässt einen älteren Auszug liegen: Ein Telefon, das `latest.json` kurz vor dem Deploy
gelesen hat, fragt noch nach der Datei, von der man ihm erzählt hat.

Was das kostet: Jeder angenommene Import legt fünf Dateien ins Repository — die `.vst` und die
`.vst.gz` unter `site/static/stations/`, dieselben zwei noch einmal unter dem eingecheckten
`site/dist/stations/`, und später die Kopie als Flutter-Asset. Zusammen 1 135 830 rohe Bytes, nach
Gits eigener Kompression etwa 735 KB. Zweimal im Jahr sind das rund **1,5 MB Repository-Wachstum pro
Jahr**. `--keep` begrenzt den Arbeitsbaum, nicht die Historie.

`--asset` schreibt `app/assets/stations/stations.vst`, die Kopie, die eine frische Installation
ohne Netz schon hat. Sie kam mit der Dart-Hälfte, im selben Commit wie der `assets:`-Eintrag in
`app/pubspec.yaml` — die Datei benannt, nicht das Verzeichnis, damit nie zwei Versionen in einem
Build landen.

`--asset` geht **nur mit `--prod`**, und das ist keine Förmlichkeit. Die App lädt einen Auszug nur
herunter, wenn sie noch keinen heruntergeladenen hält; das mitgelieferte Asset ist der Boden für den
ersten Start. Ein aus der Entwicklungsdatenbank gerendertes Asset trägt deren Seriennummer, und die
ist höher als die der Produktion — gemessen 7 gegen 1. Eine frühere Fassung dieses Befehls hat genau
das getan, und ein Telefon hätte den ersten echten Download verworfen und den Laptop-Stand behalten,
bis die Produktion sieben Importe weit ist. Bei zweimal im Jahr sind das rund drei Jahre.

## Warum es keine unauthentifizierte Route auf der API gibt

Issue #39 will die Datei ohne Token abrufbar — und das ist sie, auf dem **Website**-vhost, nicht auf
`api.verspaetomat.de`.

1. **Die Rechnung mit der Privatsphäre geht nur auf dem anderen Host auf.** Der API-Block in
   `deploy/caddy/Caddyfile` hat `log { output stdout format console }`, und kein Dienst in
   `deploy/docker-compose.yml` hat einen `logging:`-Block — das ist also das ganze Log, und es hält
   die Client-IP fest. Ein wöchentlicher Abruf dort stünde im selben Strom wie der authentifizierte
   Verkehr.
2. **Caddy kann die schwierigen Teile für die Website schon**: bedingte GETs mit einer 0-Byte-304,
   `Cache-Control` pro Pfad, eine vorkomprimierte Datei daneben. Die API müsste ETag,
   `Last-Modified` und Kompression für genau eine Route lernen.
3. **Kosten.** 280 KB durch axum und den Reverse-Proxy, pro Installation und Woche, gegen eine
   statische Datei.
4. **Reihenfolge beim Ausliefern.** Website, Backend, dann TestFlight — auf dem Website-vhost ist
   die Datei schon im ersten Schritt da.
5. **Kein Gewinn.** Eine zweite Quelle wäre eine zweite Art zu scheitern, und genau die Sorte
   Rückfallebene, die in Köln funktioniert und in Kißlegg nicht.

In der Caddy-Konfiguration hängen vier Zeilen daran: `precompressed gzip` im `file_server` (der
Auszug steht mit keinem seiner Typen auf der eingebauten Liste von `encode`, ginge also sonst mit
vollen 280 244 Bytes raus), zwei `header`-Zeilen mit den Cache-Zeiten, eine dritte, die den
Content-Type festnagelt, und `log_skip /stations/*`, damit der Abruf nicht in Caddys stdout landet.
Gemessen: mit `log_skip` steht nach einem Abruf keine Zeile für `/stations/*` im Log. Die Hintergrund-Abfragen der
App laufen bis auf Weiteres weiter über `/v1/stations/nearby` am API-vhost und stehen dort mit IP im
Log — das ändert erst der native Teil.

Vor dem Deploy `caddy validate` laufen lassen: `deploy/deploy.sh` lädt Caddy bedingungslos neu, und
beide vhosts stehen in derselben Datei. Eine kaputte Konfiguration nimmt die API mit.

## Was der Auszug nicht trägt

Keine MOTIS-IDs, keine `modes`, kein `first_seen`/`last_seen`, keine stillgelegten Zeilen, und
nicht die beiden Falten `plain` und `normal`, die `Index::search` vorberechnet.

Die Falten nicht, weil sie die Datei fast verdoppeln — allein die kleingeschriebenen Namen
kämen gemessen auf weitere 128 132 Bytes, also noch einmal den ganzen Namensblock, und die
normalisierten noch einmal in derselben Größenordnung — und weil sie keine Richtigkeit kaufen: Das
Telefon muss `normalise_station_name` für die *Eingabe* ohnehin umsetzen. Beide Seiten mit derselben
Dart-Funktion zu falten lässt einen Umsetzungsunterschied sich aufheben; nur die Bahnhofsseite
einzubacken lässt ihn zubeißen.

Die MOTIS-IDs nicht, weil das Telefon nie versuchen darf, eine Upstream-ID abzuleiten. `upstream_id`
bleibt Sache des Servers, und genau das hält `vs:4711` bedeutungsvoll.

Und: **Ein Auszug ist eine Momentaufnahme.** Ein Bahnhof, der nach dem Bauen stillgelegt wird,
verschwindet aus dem nächsten Auszug — aber ein Telefon, das den vorherigen hält, bietet ihn weiter
an, bis es auffrischt. Das können Monate sein. Das ist kein Fehler, es ist der Preis dafür, nicht zu
fragen; es muss nur jemandem auffallen, bevor es ihn wundert.
