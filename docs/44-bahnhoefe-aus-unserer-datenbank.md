# 44 — Die Bahnhöfe kommen aus unserer Datenbank

Entschieden am 20. September 2026, Issue #37. Vorher gab es gar keine Bahnhofstabelle: Jede Frage
„welche Bahnhöfe sind hier in der Nähe" war eine Live-Anfrage — das Telefon schickte seine
Koordinaten, wir reichten sie an Transitous weiter, und dahinter gingen bis zu fünf weitere
Abfragen raus, nur um herauszufinden, welche der Haltestellen ringsum überhaupt Bahnhöfe sind.

Das ist viel Last auf einem ehrenamtlichen Dienst, es ist eine Position, die das Telefon verlässt,
und es ist alles für Daten, die sich zweimal im Jahr ändern.

## Was jetzt gilt

| | vorher | jetzt |
|---|---|---|
| „Bahnhöfe in der Nähe" | reverse-geocode plus bis zu acht `rank_of`-Abfragen | ein Scan über unsere Tabelle |
| „ist das ein Bahnhof" | aus den Abfahrten der nächsten Stunde geraten | `route_type` aus dem Fahrplan, beim Import entschieden |
| Bahnhofssuche | Freitext an Transitous | derselbe Scan |
| Koordinaten an Dritte | ja, bei jeder Auflösung | nein |
| Bahnhofs-ID auf dem Draht | die von MOTIS, je nach Codepfad eine andere | unsere: `vs:4711` |

## Die ID gehört uns

`stations.id` ist eine `integer`-Identity, sie erreicht die App als `vs:4711`, und sie ist
endgültig: Eine einmal vergebene ID wird nie wieder vergeben, auch nicht, wenn der Bahnhof aus dem
Fahrplan verschwindet. Die Zeile bleibt dann stehen und bekommt ein `retired_at`, damit eine Fahrt,
die sie nennt, weiter lesbar ist.

Warum nicht die ID von MOTIS: Sie ist feed-abhängig und je nach Codepfad eine andere. Kißlegg
existiert heute live als `de:08436:1159`, `…_G`, `…_G_G` und `…:2:3`; Köln Hbf liefert der
Gazetteer als belgische `be-sncb_8015458`, die Abfahrtsabfrage als `de-DELFI_de:05315:11201`. Genau
daran hing das Doppelt-auf-Home aus docs/30. Und warum keine DHID: 15 % der deutschen Bahnhöfe
haben gar keine, DELFI führt nur 5.270 Eltern-Einträge zu 551.291 Haltestellenzeilen, und wer eine
DHID abschneidet, erfindet IDs, die es nicht gibt.

Die IDs, auf die MOTIS hört, stehen in `station_sources`, eine Zeile pro Feed, das den Bahnhof
bedient — Berlin Hbf kommt bei der S-Bahn aus dem VBB-Feed und beim Regionalverkehr aus DELFI, und
das ist ein Gebäude. Nach draußen geht davon nichts: Erst auf dem Weg zu MOTIS wird übersetzt. Eine
ID aus einem Build, der älter ist als die Tabelle, ist keine von uns und geht unverändert durch.

## Woher die Daten kommen

Zwei Feeds von <https://api.transitous.org/gtfs/>, denselben Dateien, die die laufende
MOTIS-Instanz importiert:

| Datei | Größe | MOTIS-Key | Lizenz |
|---|---|---|---|
| `de_DELFI.gtfs.zip` | 338 MB | `de-DELFI` | CC-BY-4.0 |
| `de_VBB.gtfs.zip` | 72 MB | `de-VBB` | CC-BY-4.0 |

VBB ist nicht optional: `feeds/de.json` wirft 39 Verkehrsunternehmen aus dem DELFI-Import, darunter
die S-Bahn Berlin GmbH, weil andere Feeds sie abdecken. Berlins S-Bahn fehlt in DELFIs Bahnrouten
und steht im VBB-Feed.

Herunterladen ist der vorgesehene Weg, nicht der geduldete: Die Nutzungsbedingungen von Transitous
sagen ausdrücklich, dass man den Datensatz laden soll, statt die API abzugrasen. Sie verlangen
außerdem quelloffenen Code — das Repository wird vor dem ersten Release öffentlich.

Der Fahrplan beantwortet die Bahn-Frage genauer als die Abfahrten es je konnten. DELFI benutzt die
erweiterten `route_type`-Nummern, und darin ist die S-Bahn (109) von der U-Bahn (1, 400–405) durch
eine Zahl getrennt. Die Heuristik aus docs/23, die `^S\d` gegen `^U\d` stellte, weil MOTIS beide
`METRO` nennt, wird dafür nicht mehr gebraucht.

## Gebaut wird auf dem Laptop

Wie die Website. `stellwerk stations import` lädt die Feeds, streamt die 2,8 GB `stop_times.txt`,
faltet die Bahnsteige zu Bahnhöfen und schickt das Ergebnis an `POST /admin/stations/import`. Der
Server macht daraus nur noch das eine, was nirgends sonst gemacht werden kann: Er entscheidet,
welche davon Bahnhöfe sind, die wir schon einmal benannt haben.

Die Zuordnung, in dieser Reihenfolge: eine bekannte Quell-ID; sonst derselbe normalisierte Name
innerhalb eines Kilometers; sonst neu. Was in der Tabelle steht und in keiner der beiden Regeln
vorkommt, wird stillgelegt.

## Der Import darf sich weigern

Jede dieser Grenzen ist ein Fehler, den ein Prototyp beim Entwurf tatsächlich produziert hat:

- unter 6.000 oder über 12.000 Bahnhöfe — das ist kein Land, das einen Haltepunkt dazubekommt;
- mehr als 50 Stilllegungen auf einmal;
- ein Bahnhof, der weiter als zwei Kilometer „umgezogen" ist, ist nicht umgezogen, sondern falsch
  zugeordnet.

`--force` hebt sie auf. Der allererste Import braucht das, und der Tag, an dem sich oben wirklich
etwas Großes ändert, braucht einen Menschen, der ja sagt.

Jeder Lauf schreibt eine Zeile nach `station_imports`, auch ein abgelehnter. Ein schlechter Import
soll etwas sein, das man hinterher nachlesen kann, und nicht etwas, das man in der App bemerkt.

## Was daraus als Nächstes folgt

Die Tabelle ist die Voraussetzung, nicht das Ziel. Das Ziel ist, dass die Hintergrund-Anfragen
verschwinden: Solange das Telefon für „welcher Bahnhof ist hier" den Server fragen muss, fragt es
ihn auch mit geschlossener App — docs/25 hat auf einer echten Fahrt vierzehn solcher Anfragen in
neunundfünfzig Minuten gemessen. Erst ein Auszug auf dem Telefon beendet das, und dieser Auszug
trägt dann unsere IDs, weil App und Server sich sonst nicht einig sein können.

Danach, und erst danach, stimmt auch der Satz, der in der App schon steht.
