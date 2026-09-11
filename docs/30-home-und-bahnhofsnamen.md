# 30 — Wir zuerst, und ein Bahnhof mit zwei Namen

Decided 11 September 2026 (Johannes, from build 18 on a real phone). Three small things, one of
which reverses an earlier decision on purpose.

## 1. „Ab Kißlegg" stood on the card twice

The away box — the one that asks „Von wo fährst du los?" when you are not at a station — merges
two lists: the **frequent stations** from this person's ride history (`GET /v1/me/geofence`) and
the **nearby** ones from the feed. It deduplicated them by exact id, or failing that by exact name.

Neither holds. One platform has an id per feed, as docs/28 found out the hard way; and the two
sources spell it differently — „Kißlegg Bahnhof" here, „Kißlegg" there, and a ride checked in
months ago carries whatever it was called then. So the same station arrived twice and the card
offered it twice.

`sameStation(a, b)` in `ride_widgets.dart` is the test to use wherever two lists of stations
meet: normalise (which already folds `Hauptbahnhof` to `Hbf`, drops parentheses and commas), then
allow one name to be the other plus the word for the thing itself — `Bahnhof`, `Bf`, `Hbf`. So
Kißlegg is Kißlegg Bahnhof and Köln Hbf is Köln Hauptbahnhof, while Köln Hbf is still not Köln
Messe/Deutz and Düsseldorf Hbf is still not Düsseldorf Flughafen.

Note what the tour cannot tell us here: in Demo mode both lists come from the same mock ids, so
they never collided and the duplicate never appeared. The rule has unit tests; the confirmation
is on a platform.

## 2. Wir goes to the top of Home

Home now reads: **Wir · Einchecken · Deine Woche.**

This reverses docs/16 §1, which put the action first — „the action for this moment", everything
above the fold. The reason to reverse it: the collective number is what the app is *for*, and it
is true whether or not anybody is travelling this minute. The check-in card is only the most
useful thing on the screen when you happen to be standing on a platform.

It costs a scroll to reach Einchecken when you are on one. That is the trade, made knowingly.

## 3. „Deine Woche" wears the same box as „Wir"

Two blocks that say the same kind of thing should look the same. Deine Woche was bare text beside
a bordered box; it is now the box: elevated paper, a hairline, the number as the hero, one quiet
line under it, and a bar.

One honest limit of that bar: it is scaled against the better of this week and last, so the
better week always fills the track completely. It reads „this week against last week" only if you
also read the caption. Wir's bar means something exact — your share of the whole — and this one
does not yet. Worth revisiting if it bothers anyone; noted rather than left to be discovered.

## Tests

- `test/same_station_test.dart`: both directions of the `Bahnhof` tail, and the pairs that must
  stay apart.
- Tour: `bahnsteig-deine-woche`, a scrolled shot, because the section that changed sits below the
  fold and an unphotographed change is an unchecked one.

## Nachtrag, 12. September 2026: die Hälfte, die im Backend fehlte

Build 20 zeigte „Ab Kißlegg Bahnhof" wieder zweimal — und diesmal mit **identischen Namen**, was
den Fehler sofort verriet: `sameStation` in der App ist nur die Schranke, wenn zwei *verschiedene*
Quellen zusammenfließen (die häufigen Bahnhöfe aus der Fahrtenhistorie und die nahen aus dem
Feed). Die häufigen Bahnhöfe selbst kamen ungeprüft in die Liste, weil sie aus dem Backend schon
dedupliziert hätten kommen sollen. Taten sie nicht: `geofence_set` verglich Ids, und
`select … group by from_station_id, from_station_name` macht aus einem Bahnsteig zwei Zeilen,
sobald derselbe Bahnsteig einmal über DELFI und einmal über amarillo-bw eingecheckt wurde.

**Korrektur, nachdem ich in die Produktionsdaten gesehen habe:** meine erste Erklärung — zwei
Feeds, DELFI und amarillo-bw — war falsch, und die Wahrheit ist banaler und häufiger. Die Zeilen
hinter dem Duplikat waren:

```
de-DELFI_de:08436:1159_G     Kißlegg Bahnhof   47.7935, 9.8818   2
de-DELFI_de:08436:1159:2:3   Kißlegg Bahnhof   47.7935, 9.8818   1
```

Ein Feed, ein Name, dieselben Koordinaten. Es sind der **Haltestellen-Knoten und einer seiner
Steige**: eine DHID ist `Land:Regionalschlüssel:Halt:Steig:Abschnitt`, und `_G` markiert den
Knoten selbst. Transitous gibt beim Einchecken manchmal den einen und manchmal den anderen zurück.
Damit ist der Fall nicht exotisch, sondern der Normalfall an jedem Bahnhof mit mehr als einem
Gleis — er war nur bisher nicht sichtbar, weil man dafür zweimal am selben Bahnhof über
verschiedene Knoten einchecken muss.

Das hatte drei Folgen, von denen nur eine zu sehen war:

1. Zwei Chips auf Home, mit demselben Namen.
2. **Zwei von zwanzig Regionen** auf dem Telefon für einen Bahnsteig (docs/25 §2). Das Budget ist
   knapp und wurde für ein Duplikat ausgegeben.
3. Die Check-ins waren geteilt: vier Fahrten ab Kißlegg zählten als zwei plus zwei. Damit stand
   auch der Stammbahnhof falsch in der Reihenfolge.

Ein Bahnhof ist ein Bahnhof, und **eine Schranke entscheidet das für jede Liste**:
`train::same_platform(StationRef, StationRef)`, mit zwei Kriterien in der Reihenfolge dessen, was
sie wissen:

1. **Die Id selbst**, wo sie eine deutsche DHID ist: gleich bis zum Halt heißt derselbe Bahnhof,
   der Steig ist nicht unsere Sache. Das ist der Fall oben, und die Id ist dabei die verlässlichste
   Quelle, die es gibt — genauer als jeder Namensvergleich.
2. **Sonst der Name** nach `normalise_station_name`, mit Nähe, wo die Liste Koordinaten hat. Das
   fängt die Feeds, die einen Bahnhof unterschiedlich schreiben.

Bewusst strenger als
`station_names_match`, das ein Wortpräfix akzeptiert: „Wangen" ist ein Präfix von „Wangen im
Allgäu Nord" und ein anderer Halt. Wo eine Liste keine Koordinaten hat — die Ziel-Listen speichern
keine —, entscheidet der Name allein; zwei Orte mit gleichem Bahnhofsnamen gibt es, aber eine
Abkürzung für beide ist der kleinere Fehler als derselbe Name zweimal, und der andere Bahnhof ist
eine Suche weit.

Angewandt an drei Stellen, die alle vorher Ids verglichen:

- `geofence_set`: die Zeilen werden erst zusammengefaltet (erste Schreibweise gewinnt, weil die
  Zeilen in Häufigkeitsreihenfolge kommen; die Check-ins addieren sich), dann wie vorher gefiltert.
  Auch der Stammbahnhof wird über die Schranke gesucht, sonst kam er ein zweites Mal unter der Id
  zurück, die das Zusammenfalten behalten hat.
- `rank_destinations`: gruppiert nach Bahnsteig statt nach Id, und der Bahnhof, an dem man steht,
  fällt auch unter seinem anderen Namen heraus (den Namen dazu findet die Funktion in der Historie
  selbst — kein neuer Query-Parameter).
- die „Zuletzt"-Liste in `destinations`: dasselbe.

In der App wurde nichts geändert: die eine Schranke dort (`sameStation`) gehört an die Stelle, wo
zwei Quellen zusammenkommen, und dort steht sie. Damit reicht ein Deploy — Build 20 bekommt die
saubere Liste, ohne dass etwas Neues installiert werden muss.

Tests: `same_platform` (Knoten und Steig mit den echten Ids aus der Produktion · zwei Feeds, ein
Bahnsteig · Wortpräfix bleibt getrennt · gleicher Name in einer anderen Stadt bleibt getrennt ·
leerer Name trifft nur seine eigene Id), `geofence_set`
(Zusammenfalten mit Summe; der Stammbahnhof nicht zweimal) und `rank_destinations`
(nach Bahnhof gezählt; der eigene Standort fällt unter beiden Ids heraus). 61 Rust-Tests.
