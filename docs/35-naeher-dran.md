# 35 — Näher dran, etwas später dran, und ein Brett im Hellen

Decided 12 September 2026 (Johannes, aus den Issues 8, 9 und 10 — nach dem Feldversuch am
Kißlegg Bahnhof, bei dem der Hinweis 30 m vor dem Eingang ankam).

## 1. Der Hinweis soll heißen: du stehst hier (Issue 8)

300 m sind zu weit. Wer an einem Bahnhof vorbeigeht, bekommt einen Hinweis, den er nicht
gebraucht hat.

Naheliegend wäre, die überwachte Region auf 50 m zu verkleinern. Das geht nicht: iOS überwacht
Regionen aus Funkzellen und WLAN heraus, nicht mit dem GPS, und liefert kleine Kreise spät oder
gar nicht. Ein 50-m-Kreis ist ein Kreis, der manchmal einfach nicht auslöst — und der Hinweis,
der gerade zum ersten Mal im Feld funktioniert hat, wäre wieder kaputt.

Also zwei Stufen:

- **Die Region bleibt bei 300 m.** Sie ist der Wecker, nicht der Hinweis.
- **Nach dem Eintritt schaut die App selbst nach.** Sie schaltet ihre eigenen Fixe an
  (`kCLLocationAccuracyNearestTenMeters`, Hintergrundmodus `location`, den die App ohnehin hat)
  und plant den Hinweis erst, wenn ein Fix **innerhalb von 50 m** liegt — dann 45 Sekunden
  später statt der bisherigen drei Minuten, denn die drei Minuten waren der Ersatz für genau
  diese Messung.
- Kein Fix so nah innerhalb von **6 Minuten** → kein Hinweis, GPS wieder aus. Wer vorbeigeht,
  bleibt unbehelligt.

Kosten: bis zu sechs Minuten GPS pro Bahnhofseintritt, gedeckelt durch die 30-Minuten-Sperre pro
Bahnhof. Gespeichert oder gesendet wird davon nichts — wie gehabt (docs/14, docs/15 §5).

Android bleibt vorerst bei seiner Plattform-Dwell-Logik; iOS ist, was in TestFlight steht.

## 2. Züge, die gerade weg sind (Issue 9)

Wer einsteigt und erst dann an die App denkt, sitzt in einem Zug, der schon abgefahren ist.
`GET /v1/journeys/plan` plant deshalb auf Wunsch **30 Minuten in die Vergangenheit**
(`PLAN_LOOKBACK_MIN`) und holt sieben statt vier Verbindungen, damit die letzte halbe Stunde auf
einer dichten Linie nicht die ganze Liste füllt.

Auf Wunsch heißt: **`?lookback=30`**. Eine App, die die Vergangenheit nicht beschriften kann,
fragt nicht danach und bekommt die Liste, die sie immer bekommen hat — die Hausregel aus Issue 3,
dass ältere Builds mit dem neuen Backend weiterlaufen, ist genau dieser Fall.

In der Liste stehen sie unter **„Schon abgefahren"**, mit „vor 12 Min" statt einer Abfahrtszeit
in der Zukunft, aber mit ihrer echten Live-Verspätung: es ist derselbe Zug, er fährt noch.
Einchecken geht normal; das Backend hat nie verlangt, dass eine Abfahrt in der Zukunft liegt.

Die Grenze ist dieselbe wie im Backend plus etwas Luft (35 Minuten). Was älter ist, ist nicht
„gerade weg", sondern ein Fahrplan, den die App zufällig noch hält — der Demo-Fixture etwa hält
seine Morgenabfahrten den ganzen Tag —, und steht wie bisher in der normalen Liste.

## 3. Dasselbe Brett, im Hellen (Issue 10)

Die dritte Karte auf Home („Deine Woche") ist jetzt dieselbe Fallblattanzeige wie die erste, nur
im Hellen: Klappen in Papierfarbe auf dem erhobenen Papier, die Scharnierlinie in `rule` statt in
Schwarz. Beide Karten tragen jetzt denselben Aufbau — Label, Klappen, rote Haarlinie, Balken,
Zeile darunter —, und man sieht, dass es zweimal dasselbe Ding ist, einmal laut und einmal leise.

Die vier kleinen Kennzahlen auf Ich behalten nackte Ziffern (`flaps: false`): vier Bretter in
einem Raster übertönen das eine, um das es geht.
