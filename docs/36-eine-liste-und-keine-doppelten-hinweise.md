# 36 — Eine Liste, ein Hinweis, ein Sheet

Decided 12 September 2026 (Johannes, aus den Issues 9, 10, 11 und 12 — die ersten beiden nach
dem Ausprobieren von Build 25, die letzten beiden neu aus dem Feld).

## 1. Eine Liste, chronologisch (Issue 9)

Die abgefahrenen Züge standen unter einer eigenen Überschrift „Schon abgefahren" — und wurden
übersehen: wer oben nicht findet, was er sucht, hört auf zu lesen. Jetzt ist es **eine Liste in
Zeitreihenfolge**, wie ein Brett am Bahnsteig: der Zug von vor zwölf Minuten steht über dem
nächsten, weil er dort hingehört, und trägt „vor 12 Min" statt einer Abfahrtszeit in der Zukunft.

Damit fällt auch die Sortierung nach `preferred` weg, die den nächsten Zug nach oben zog. Die
Markierung „nächste Verbindung" bleibt — sie sagt jetzt etwas, statt die Reihenfolge zu machen.

Die E2E bevorzugt beim Auswählen einen Zug, der noch nicht weg ist: ein abgefahrener ist ein
echter Check-in, aber ein schlechter Testfall, weil das Szenario vom Einstieg zum Ausstieg
vorspult.

## 2. Das Plus gehört auf eine Klappe (Issue 10)

Auf einem Fallblattbrett hängt jedes Zeichen an einer Klappe, auch eines, das sich nie dreht.
`+96` hatte die 9 und die 6 auf Klappen und das Plus daneben in der Luft. Jetzt bekommt jedes
Zeichen außer den Gruppentrennern eine Klappe — die Punkte in `1.208.315` bleiben nackt, denn sie
sind Satzzeichen zwischen Zahlen, und ein Brett hat keine Klappe dafür. Die Klappe eines Zeichens
ist so breit wie das Zeichen; nur die Ziffern teilen sich eine Breite.

## 3. Warum es in Wangen zweimal geklingelt hat (Issue 11)

Drei Fehler, die zusammen genau dieses Bild ergeben: zwei Hinweise, zwei Bahnhöfe, ein Ort, und
das obwohl die Fahrt schon lief.

1. **Ein fehlgeschlagener Aufruf war eine Antwort.** `sync()` fragt das Backend „läuft eine
   Fahrt?" und hat jeden Fehler als *nein* verbucht. Am Bahnsteig mit einem Balken Empfang heißt
   das: die native Schicht vergisst die laufende Fahrt. Jetzt bleibt die letzte bekannte Antwort
   stehen, bis eine neue kommt.
2. **Ein geplanter Hinweis überlebte den Check-in.** Die Benachrichtigung liegt in iOS, nicht in
   der App; wer eincheckt, während einer aussteht, bekam ihn trotzdem. `configure` mit
   `riding` — oder mit abgeschalteter Schicht — nimmt jetzt alle ausstehenden zurück.
3. **Ein Ort, zwei Kreise.** Der häufige Satz und die Nahliste schreiben denselben Bahnsteig
   verschieden (docs/30), und nach jedem `configure` meldet iOS für *jede* Region, in der das
   Telefon schon steht, „inside" — das ist zweimal derselbe Ort und waren zwei Hinweise.
   `GeofenceRules.samePlace` faltet sie zusammen: 250 m und ein Name, der der andere plus das
   Wort für die Sache selbst ist (`Bahnhof`, `Bf`, `Hbf`) — die Swift-Hälfte von `sameStation`.

Dazu die Regel, die den Rest abfängt: **es steht immer nur ein Hinweis aus**. Solange einer
geplant ist (zehn Minuten), wird kein zweiter geplant, egal für welchen Bahnhof. Ein Nachbargleis
ist für einen Fahrgast derselbe Ort.

Tests dafür stehen in `app/ios/RunnerTests/GeofenceRulesTests.swift` (ein Bahnsteig ist ein
Kreis; der Nachbar bleibt eigener; derselbe Name 200 km weiter bleibt eigener).

## 4. Zwei Sheets übereinander (Issue 12)

Der Knopf auf Home liegt unter dem Sheet und ist mit dem Daumen erreichbar — zweimal getippt,
zwei „Von wo?". Das Quadrat in der Leiste hatte das Problem nicht, weil die Leiste unter dem
Sheet liegt. Die Sperre gehört deshalb nicht an die Knöpfe, sondern in `runCheckinFlow`: durch
diese Funktion geht jeder Weg ins Einchecken, und dort ist ein Check-in-Vorgang zur Zeit.
