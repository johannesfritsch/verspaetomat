# 33 — Zwei Flächen, und eine Tafel, die sich selbst stellt

Decided 12 September 2026 (Johannes, aus den Issues 5, 6 und 7). docs/32 hat der App die
Fahrkarte gegeben und dabei eine Frage offen gelassen: wenn eine Fahrkarte etwas bedeutet, was
bedeuten dann die anderen Kästen? Auf Home standen plötzlich drei Sorten Fläche untereinander,
auf Wir und Ich gar keine, und in einem Antrag steckte ein Kasten in einem Kasten.

## Die Regel

**Es gibt zwei Flächen, sonst keine.**

1. **Die Fahrkarte** (`VFahrkarte`, docs/32) — *eine Fahrt oder ein Antrag*. Perforiert, weiß,
   Haarlinie an den Seiten. Etwas, das man jemandem in die Hand geben könnte.
2. **Die Tafel** (`VTafel`) — *die Zahlen, die auf einen Blick zusammengehören*. Erhobenes
   Papier, Haarlinie rundum, 4 px Radius. Was wir zusammen gewartet haben, was deine Woche
   ergeben hat, was du gesammelt hast.

Alles andere — Listen, Zeilen, Abzeichen, Einstellungen, Erklärungen — steht ohne Fläche auf dem
Papier, getrennt durch Regeln. Das war schon immer die Regel (`app/STYLE.md`), sie hatte nur
keine Ausnahmen mit Namen.

**Eine Fläche enthält nie eine Fläche.** Das ist die Regel, an der Issue 5 hing: In einem Antrag
saß die Mail der Bahn in einem eigenen gerahmten Kasten, eingerückt um das Padding der Karte.
Damit hatte ein Bildschirm drei linke Kanten — den Seitenrand, die Kartenlinie und den Rahmen der
Mail. `MailView(boxed: false)` lässt den Rahmen weg, wenn die Mail in einer Fahrkarte liegt; auf
einer eigenen Seite (Antwort, Sheet) behält sie ihn. Was in einer Fläche liegt, richtet sich an
deren Padding aus, an nichts anderem.

## Wo die Tafel jetzt steht

| Fläche | Vorher |
|---|---|
| Home · „Wir" und „Deine Woche" | zwei handgebaute Container mit denselben Werten |
| Wir · „Zusammen gewartet" | nackte Zahl auf Papier, darunter eine rote Regel |
| Ich · Geduldspunkte und Stufe | nackte Zahl, rote Regel, Fortschritt |
| Ich · die vier Kennzahlen | vier `BigFigure` frei im Raum |

Dieselbe Aussage sieht jetzt überall gleich aus. Die rote Regel unter der Wir-Zahl ist weg: die
Tafel trennt bereits, und zwei Trenner übereinander sind Lärm.

## Die Tafel stellt sich wie eine Fallblattanzeige (Issue 6)

`VTafelZahl` setzt eine Zahl so, wie ein Bahnhof sie setzt: **jede Ziffer, die sich geändert hat,
klappt auf ihren neuen Wert** — durch die Ziffern dazwischen, von links nach rechts versetzt.
Ziffern, die gleich bleiben, stehen still. Das hat zwei angenehme Folgen:

- Beim Öffnen eines Schirms stellt sich die ganze Reihe von 0 auf ihren Wert. Eine Tafel, die
  sich stellt.
- Die Wir-Zahl auf Home tickt jede Sekunde um ein paar Minuten hoch — es klappt dann nur die
  letzte Stelle, genau wie an einer echten Anzeige.

Tabellenziffern und eine feste Zellenhöhe, damit beim Laufen nichts springt. Höchstens sechs
Klappen pro Ziffer, damit 0 → 9 keine Sekunde dauert. Das ist die dritte und letzte Animation in
der App, neben dem Sekundenzeiger und dem Hochzählen bei der Ankunft.

## Was sonst noch dazugehört

Issue 3 steht jetzt in `CLAUDE.md`: Code auf Englisch (die drei deutschen Kommentare in
`bahnsteig_screen.dart` sind übersetzt), Englisch im Gespräch, Screenshots der Website gehören zu
jeder sichtbaren Änderung, alte App-Versionen müssen mit dem neuen Backend weiterlaufen, und die
Reihenfolge beim Ausliefern ist Website, Backend, TestFlight.

Issue 1: eine Adresse, `info@zoom7.de`, überall. `legalContactEmail` und `legalCompanyEmail` sind
zu `legalEmail` geworden — zwei Adressen nebeneinander ließen die Leute raten, welche gemeint
ist. Die Rechtstexte kommen aus `app/lib/content/legal.dart`, die Website bekommt sie über
`app/tools/legal_json.dart`; beide Dateien sind neu erzeugt. Issue 2 und 4 sind Copy auf der
Website: der Held und eine FAQ-Antwort, beide wörtlich wie im Issue — nur „schickt in ab" ist als
„schickt ihn ab" geschrieben.
