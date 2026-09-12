# 37 — Alles auf Karten, weiße Klappen, ein Sheet an einer Stelle

Decided 12 September 2026 (Johannes, aus den Issues 10, 12 und 13).

## 1. Weiße Klappen (Issue 10)

Die Klappen sind jetzt in beiden Lichtern Papier: **weiße Karten auf dem schwarzen Brett**,
papierfarbene auf dem erhobenen Papier. Die Ziffern sind immer Ink. Was sich unterscheidet, ist
das, was drumherum liegt.

Eine Falle dabei: die Gruppentrenner hängen **zwischen** den Klappen, also auf dem Brett selbst.
Mit der Umstellung auf Ink waren sie schwarz auf schwarz und `1.208.316` las sich als
`1 208 316`. Sie nehmen jetzt die Farbe des Bretts.

## 2. Ein Sheet, an derselben Stelle (Issue 12)

Der Check-in hat zwei Eingänge und die öffneten dasselbe Sheet auf verschiedenen Navigatoren:

- **Home-Knopf** — sein Kontext liegt *innerhalb* des Shell-Navigators, das Sheet erscheint im
  Body des Scaffolds, die untere Leiste bleibt sichtbar.
- **Quadrat in der Leiste** — sein Kontext liegt *über* diesem Navigator, also landete das Sheet
  auf dem Root-Navigator und deckte die Leiste zu.

Jetzt hält der Shell einen `Builder` um `widget.child` und merkt sich dessen Kontext; das Quadrat
öffnet damit. Ein Kontext, ein Ergebnis: Leiste sichtbar, in beiden Fällen.

(Die Sperre gegen zwei Sheets übereinander aus docs/36 §4 bleibt, wo sie ist — sie löst das
andere Problem, nicht dieses.)

## 3. Wir und Ich: nichts liegt mehr lose auf dem Papier (Issue 13)

Bisher stand die Regel: Listen und Zeilen haben keine Fläche. Auf Wir und Ich heißt sie jetzt
anders herum — **jeder Block steht auf einer Karte**, die Abschnittsüberschrift davor bleibt
draußen:

| Schirm | Karten |
|---|---|
| Wir | die Anzeige, die Vereine, die Ranglisten (Platzzeile, Reiter, Tabelle, Fußnote in einer) |
| Ich | die Anzeige, die vier Kennzahlen, die Abzeichen, Meine Statistik, Mehr |

Zwei Maße sind dabei aufgefallen und angepasst: Eine **Liste auf einer Karte** bekommt nur 8 px
seitlich statt 16, sonst bricht „Bahnhofsmission Köln" neben seiner Zahl um. Und das
**Abzeichen-Raster** ist auf die schmalere Zelle nachgerechnet (`childAspectRatio` 0,80 bei 4 px
Rand), weil eine Kachel aus 64 px Grafik plus zwei Textzeilen eine feste Höhe hat — mit dem alten
Verhältnis lief sie um 5,3 px über.

`app/STYLE.md` trägt die Ausnahme: die Regel „Regeln statt Karten" gilt weiter für Bahnsteig,
Anträge und die Unterseiten; auf den beiden Übersichtsschirmen gilt sie nicht mehr.

## Anmerkung zur Werkstatt

Die Tour ist an diesem Nachmittag mehrfach danebengegriffen — Aufnahmen landeten auf dem
nächsten Schirm. Ursache war nicht die App: die Platte war voll, der Simulator entsprechend
langsam, und `simctl io screenshot` hing den Markern hinterher. Das Fenster nach jedem Marker ist
deshalb von 1,5 auf 3 Sekunden verbreitert. Die Swift-Tests aus docs/36 ließen sich aus demselben
Grund weiterhin nicht ausführen (`xcodebuild` kann kein Testgerät klonen); sie kompilieren.
