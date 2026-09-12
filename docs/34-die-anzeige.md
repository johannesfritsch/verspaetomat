# 34 — Die Anzeige, und eine Kante, die kaum da ist

Decided 12 September 2026 (Johannes, aus den wieder geöffneten Issues 5, 6 und 7). docs/33 hat
zwei Flächen eingeführt und beide zu leise gemacht: „the rest is just a bit too subtle".

## Die Tafel hat jetzt zwei Blicke

**`VTafelLook.anzeige`** ist eine Fallblattanzeige, wie sie am Bahnsteig hängt: schwarzes Brett,
jede Ziffer auf einer eigenen Klappe (eine Spur dunkler als das Brett), die **Scharnierlinie quer
durch die Ziffer** — die Linie, die man auf jedem Solari-Brett sieht, und die dort über der
Schrift liegt, nicht darunter. Darunter eine rote Haarlinie statt des gelben Trennstreifens des
Originals: Gelb gibt es in dieser App nicht, Rot ist der eine Akzent.

**Höchstens eine Anzeige pro Schirm**, und zwar für die Zahl, um die es auf dem Schirm geht:

| Schirm | Anzeige | Papier |
|---|---|---|
| Home | „Wir" — die gemeinsamen Minuten | „Deine Woche" |
| Wir | „Zusammen gewartet" | — |
| Ich | Geduldspunkte und Stufe | die vier Kennzahlen |

**`VTafelLook.papier`** ist die stille Variante von vorher: erhobenes Papier, Haarlinie, 4 px. Für
alles unter der Falte. Zwei schwarze Bretter übereinander wären ein Cockpit, kein Bahnsteig.

Auf dem Brett werden auch die Nebendinge dunkel: Label und Bildunterschrift in `VTafel.boardInk`
(`VTafelLabel`, `VTafelCaption`), der Balken bekommt eine dunkle Spur (`VProgress(track:)`).

## Die Kante der Fahrkarte war zu dunkel

Issue 5, zum zweiten Mal: die Seitenlinien der Antrags-Karten. Sie standen auf `rule` (D2D2CC),
die Sammelkarte sogar auf 1,5 px Ink — die Website nimmt an derselben Stelle `--rule-soft`
(E6E6E1). Jetzt ist es überall `ruleSoft`, und `strong` gibt es nicht mehr: Die offene Kasse
unterscheidet sich durch das, was auf ihr steht, nicht durch eine dunklere Kante. Eine Fahrkarte
erkennt man an der Perforation, nicht am Rahmen.

## Mehr Fahrkarte

„I would love to see more of the ticket card style." Die Ankunft ist jetzt eine: der Zug, die
Strecke, die große Zahl und die beiden Zeilen darunter stehen auf einer gestanzten Karte — der
Moment, in dem die Fahrt verbraucht ist. Was danach kommt (Abzeichen, Anspruch, Knöpfe), folgt
aus der Karte und steht nicht auf ihr.

Nicht zur Fahrkarte geworden ist die Historie: 13 Fahrten als 13 gestanzte Karten untereinander
sind ein Stapel, durch den man nicht mehr scannen kann. Listen bleiben Listen; die Form soll
selten genug sein, dass sie etwas bedeutet.

## Und ein Fehler, der zwei Tage lang Bilder verdorben hat

`NO_ANIM=1` hat nie gewirkt: `bool.fromEnvironment` kennt nur die Zeichenkette `"true"`, alles
andere ist `false`. Die Tour lief also die ganze Zeit mit laufender Animation — daher das
Standbild mitten im Klappen und die Aufnahme, die eine Seite hinterherhing. Jetzt wird wie bei
`NO_LOCATION` die Zeichenkette verglichen. Die Klappen bleiben im Standbild sichtbar; nur
klappen sie nicht: die Zellen sind der Look, nicht die Bewegung.

Dazu: eine Klappe ist 18 % höher als die Ziffer darauf, und die Ziffer steht mittig darin. Vorher
war die Zelle so hoch wie die Zeile, und die Ziffern standen auf der Schnittkante.
