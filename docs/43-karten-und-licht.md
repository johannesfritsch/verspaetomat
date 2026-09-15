# 43 — Karten und Licht: die Oberfläche wird neu

Entschieden am 14. September 2026 (Johannes, aus vier Entwürfen in `docs/assets/redesign/`).

Vier gezeichnete Schirme — Home, Anträge, Wir und das Sheet während der Fahrt — lösen die
Bahnhofsuhr ab. Was sie zeigen, ist keine neue App: die Reihenfolge der Blöcke ist auf jedem
Schirm dieselbe wie vorher. Was sich ändert, ist die Haut.

## 1. Was jetzt gilt

**Die Seite ist kühl.** Jeder neutrale Ton hat mehr Blau als Rot. Nichts ist schwarz: die dunkelste
Schrift und das Brett sind Blauschwarz, und jeder neutrale Schatten ist aus einem Schiefernavy
gemacht — ein schwarzer Schatten auf kühlem Papier liest sich als Schmutz.

**Es gibt zwei Rot.** `VColors.red` ist das tiefe und heißt *tu das* oder *das ist Geld*: der
Knopf, der Kreis in der Leiste, ein Betrag, ein Link. `VColors.redBright` ist das helle und heißt
*dieses hier*: der heutige Balken, die ungelesene Zahl, das App-Zeichen. Zwischen beiden liegen
vierzig Stufen Grün, und ein Token kann nicht beides tragen.

**Die anderen Farben gehören anderen.** Türkis, die beiden Blau und das helle Grün bezeichnen ein
Eisenbahnunternehmen oder einen Verein. Sie tragen nie einen Zustand der App. Farbe ist für
Identität da; Rot und Grün sind für Bedeutung da.

**Drei Flächen, und sonst nichts** (das löst docs/33 ab):

| Fläche | Was sie ist | Wofür |
|---|---|---|
| Die Karte (`VCard`) | weiß, Radius 14, Schatten | alles, was ein Block ist. Der Normalfall. |
| Das Brett (`VBoard`) | dunkel oder rot, mit rotem Schein darunter | die eine Zahl, um die es auf dem Schirm geht. Höchstens eines. |
| Das Feld (`VPanel`) | getönt, innen in einer Karte | das eine, was das Auge zuerst erreichen soll. |

Verschachtelt wird höchstens zwei tief: eine Karte darf ein Feld tragen, ein Sheet eine Karte.
Nichts innerhalb einer Fläche bekommt einen eigenen Rand, und der Inhalt richtet sich an der
Polsterung der Fläche selbst aus — ein Schirm hat **eine** linke Kante, nicht drei. Die Entwürfe
brechen das in der Antrags-Karte; die App macht es nicht nach.

**Karten statt Linien.** Abschnitte trennt jetzt der Abstand, nicht ein Strich. Eine Haarlinie
überlebt nur *innerhalb* einer Karte, zwischen den Zeilen einer Liste, und nie unter der letzten
Zeile — ein Strich unter der letzten Zeile ist ein Strich unter nichts, und genau das lässt eine
Liste wie ein Formular aussehen.

**Der rote Schein.** Was gedrückt werden will, wirft keinen grauen Schatten, sondern gibt nach
unten rotes Licht ab. Das ist die Signatur des ganzen Entwurfs, und nichts sonst in der App darf
sich einen eigenen ausdenken.

## 2. Was das gekostet hat

Nicht weichzeichnen: drei Entscheidungen, die mit Absicht getroffen worden waren, fallen.

**Die Fallblattanzeige.** docs/33 nennt sie „die dritte und letzte Animation der App", docs/34 hat
die ganze Anzeige um sie herum gebaut. Auf beiden Brettern der Entwürfe stehen schlichte fette
Ziffern: keine Klappe, keine Scharnierfuge, keine rote Haarlinie unter der Reihe. Das war das eine
mechanische Stück Charme der App und das Einzige, was eine Zahl auf einem Schirm wie einen Bahnhof
wirken ließ. **`VTafelZahl` bleibt im Code und funktioniert weiter**, es ist nur nicht mehr
eingeschaltet (`flaps: false`). Ein Entwurf ist ein Standbild und kann keine Animation zeigen —
bevor der Verlust akzeptiert wird, sollte das Umblättern einmal auf dem neuen Brett laufen.

**Die Fahrkarte, innerhalb der App.** Die Perforation überlebt an genau zwei Stellen: in
`widgets/ticket.dart` und im Kopf von verspaetomat.de. In den Schirmen ist sie weg. Damit sieht
das, was man teilt, nicht mehr aus wie die App, aus der man es geteilt hat. Das ist ein echter
Preis und **eine offene Frage**, keine getroffene Entscheidung.

**Die Haarlinie als Struktur**, und mit ihr `VRule.red`, der eine wichtige Bruch, den ein Schirm
haben durfte. 63 Aufrufstellen.

**Das warme Papier.** `#F3F3F0` war gewählt. `#F7F7F8` ist keine Verschiebung davon, es ist die
andere Temperatur.

## 3. Was bleibt

Das eine Rot, dem Sinn nach. Die Tabellenziffern. Die grüne Null, jetzt vorzeichenbehaftet
(`+0`), weil sie in einer Spalte steht, in der jede Zeile ein Vorzeichen trägt. Die Bahnhofsuhr an
ihren fünf verbliebenen Stellen — Willkommen, Berechtigungen, Antrag, Hinweisleiste, Showcase —
mit dem Sekundenzeiger, der bei zwölf wartet. Der Kopf der Unterschirme. Der trockene Ton.
`VDemoControl` mit seinem absichtlich ungestalteten gestrichelten Kasten.

## 4. Fünf Entscheidungen, damit die Arbeit weitergehen konnte

Jede ist ein Token oder ein Schalter und damit billig zurückzunehmen.

| Frage | Genommen | Warum |
|---|---|---|
| Die Schrift | Archivo bleibt | Die Entwürfe sind **nicht** in Archivo gesetzt: ihr `i` trägt einen runden Punkt, Archivos ist ein hartes Quadrat. Archivo bleibt trotzdem, weil es die gefußte `1` schon hat — die lässt eine große Zahl wie eine Anzeigetafel wirken —, weil seine x-Höhe der gemessenen am nächsten kommt und weil es w800 erreicht, wo der nächste Kandidat bei w700 aufhört. |
| Die Schriftgrade | Die gemessenen, auf Archivo korrigiert | Archivos Versalhöhe ist 0,686 vom Geviert, nicht die 0,72, mit denen gemessen wurde. Deshalb sind mehrere Grade einen Punkt größer, als ein Lineal am Entwurf sagen würde. |
| Der Kartenradius | 14 außen, 10 für Felder, 12 für Knöpfe | Die vier Entwürfe stehen zwei zu zwei, bei 14 und bei 10. Ein einziger Radius von 12 überall würde alle vier annehmbar wiedergeben. |
| Das Rot | `#D61316` | Anträge misst diesen Wert, Home misst `#CE1F18`. Dieser trifft außerdem den Kreis in der Leiste, die Fortschrittsbalken und die aktiven Reiter auf drei Dateien — der andere liest sich als Rendering-Drift. |
| Die Fallblattanzeige | Im Code, ausgeschaltet | Siehe oben. |

## 5. Was noch offen ist

- **Zieht die Website mit?** Wenn die Fahrkarte aus der App verschwindet: ändert sich der Kopf auf
  verspaetomat.de und die Teilen-Karte mit, oder behalten die beiden bewusst eine Silhouette, die
  die App nicht mehr hat? Beide Antworten sind vertretbar. Keine Antwort ist es nicht.
- **Grün heißt jetzt dreierlei**: pünktlich, abholbereit („Bereit · 4,50 €") und S-Bahn. Auf dem
  Berechtigungsschirm heißt es außerdem „erlaubt". Entweder enger fassen oder aufschreiben, dass
  Grün allgemein „gut" bedeutet.
- **Wovon ist der Balken auf dem Brett von Wir ein Anteil?** Er steht auf 71,6 %, und nichts in
  `ApiCommunity` trägt das. docs/18 sagt, dass keine Euro-Summen der Gemeinschaft auf diesen Schirm
  gehören. Der Balken kann nicht ausgeliefert werden, bevor das beantwortet ist.
- **Die Wochenreihe.** Sieben Tage Geduldspunkte mit dem heutigen hervorgehoben. Die App kennt nur
  diese Woche gegen letzte Woche; die Reihe muss erst in die API. Bis dahin zeigt die Leiste zwei
  Spalten statt sieben — siehe §7.
- **Zwei neue Wege sind angedeutet**, keiner existiert: „Alle Wochen ›" auf Home und
  „Mehr erfahren ›" auf Wir.
- **Wo landen die sechs Zustände**, die in keinem Entwurf vorkommen: die Stumm-Zeile, das
  Offline-Band, die Fehlerzeile, die Ladezeile, die Stellwerk-Bildunterschrift und
  „Gestern vergessen einzuchecken?". Das sind echte Zustände, keine Dekoration.
- **Die Leiste unten ist jetzt etwa 100 pt hoch** gegen vorher 60 plus Sicherheitsbereich. Das sind
  vierzig Punkt von jedem Schirm.
- **Logos der Eisenbahnunternehmen.** Der DB-Keks ist eine eingetragene Marke, und die Doktrin des
  Produkts ist, dass die App Bote ist und nie Vertreterin. Marken kommen über verwaltete Daten
  (`stellwerk operator set … --logo`), nicht ins Binary — denselben Weg, den die Vereinslogos schon
  gehen. Der Zug in der Kopfzeichnung trägt aus demselben Grund keine Lackierung.

## 6. Die Kopfzeichnung

Home und Wir bekommen ein Band Landschaft hinter dem Titel: Hügel, Dunst, Nadelbäume, ein Zug, auf
Wir ein Herz. Zuerst war sie in Dart gemalt — flache Formen, auf jeder Breite richtig. Die Nase
eines Hochgeschwindigkeitszuges sind aber ein paar lange Kurven, und eine stilisierte liest sich
als Klotz. Die Zeichnung war mehr wert als die Skalierbarkeit, also liegt sie jetzt als Bild bei
(`app/assets/header/`, WebP, je 17 kB).

Zwei Dateien, die sich nur im Herz unterscheiden, damit das Herz genau dort sitzt, wo es gezeichnet
wurde, und nicht im Code noch einmal platziert werden muss. `lib/widgets/header_scene.dart` legt
zwei Verläufe darüber: links und oben löst sich das Bild ins Papier auf. Ohne die endet die
Zeichnung auf einer Kante — senkrecht mitten durch den Schirm, wo der Titel steht, und waagerecht
unter dem Kopf.

**Auf keiner der beiden trägt der Zug eine Lackierung.** Im Original klebte ein rotes Zeichen auf
der Nase, an der Stelle und in der Form, an der ein Keks klebt. Es ist herausretuschiert, aus
demselben Grund, aus dem die App Bote ist und nie Vertreterin.

## 7. Die Wochenleiste, wenn die Daten nicht reichen

Der Entwurf zeichnet sieben Balken. Die App hat keine Tagesreihe: `standing` liefert diese Woche
und letzte Woche. `VWeekBars` nimmt deshalb beliebig viele Spalten und verbreitert die Balken, bis
der Block wieder voll ist — zwei Balken „Letzte" und „Diese" sind eine Wochenhistorie in grober
Auflösung, ein leeres Rechteck ist gar nichts. Unter der Zahl steht, was sie bedeutet: „55 mehr als
letzte Woche", nicht die nackte Zahl der Vorwoche, die der Balken daneben schon zeigt.

In einer Woche, in der nichts passiert ist, bleibt **kein** Balken rot: jede Spalte ist ein Stummel,
und einer davon leuchtend rot läse sich als ein bisschen was. Kommt die Tagesreihe in die API, wird
aus dem Aufruf `VWeekBars(values: reihe, todayIndex: wochentag, labels: [Mo … So])` und sonst muss
sich auf dem Schirm nichts bewegen.

## 8. Fünf weitere Entwürfe, und was sich dadurch ändert

Nachgereicht am 15. September 2026: Ich, das Teilen-Sheet und die drei Schritte des Check-ins.
Sie lösen ein paar Sätze aus §1 und §4 ab.

**Das rote Brett ist nicht mehr nur Wir.** Ich bekommt es auch. Home behält das dunkle. Die Regel
heißt jetzt: das dunkle Brett ist das, dem man zuerst begegnet, und die roten stehen auf den beiden
Schirmen, bei denen es um Menschen geht — um uns alle und um dich.

**Das Linienschild hat drei Ansichten**, und die Farbe ist in allen dreien die Gattung: getönt für
eine Zeile in einer Liste, gefüllt für den Zug, um den eine Karte geht, dunkel für den Zug, in dem
man sitzt. Höchstens ein gefülltes pro Karte, sonst heißt es nicht mehr „dieser hier".

**Abschnittsüberschriften sind zweierlei.** Eine Überschrift (voll, in Titelgröße) führt einen Teil
des Schirms ein, zu dem man auch hätte navigieren können — Ichs „Abzeichen". Ein Kapitälchen-Label
benennt den Block direkt darunter — Wirs „VEREINE". Beides steht in den Entwürfen; welches man
nimmt, ist diese Frage und keine Geschmackssache.

**Zwei Dinge aus den Entwürfen kommen nicht.** „Hohe Auslastung" in der Verbindungsauswahl: es gibt
nirgends in App oder Backend eine Auslastung. Und das Ankunftsgleis: das Modell führt ein Gleis nur
für die Abfahrt. Beides ersatzlos gestrichen, nicht erfunden.

**Zwei Dinge macht die App anders als gezeichnet.** Der Untertitel auf Ich endet im Entwurf auf ein
Herz-Emoji; die App setzt die Worte und zeichnet das Herz. Und das Teilen-Sheet zeigt eine Reihe
Fremdlogos; die App öffnet stattdessen das System-Sheet, das als einziges weiß, was jemand
überhaupt installiert hat, und dafür keine fremden Marken ins Binary holt.

**Eine Interaktion ändert sich.** Bisher checkte ein Tipp auf einen Zug direkt ein — „eine Zeile,
ein Tipp", und der Chevron sagte es. Der Entwurf setzt einen Haken und einen „Weiter"-Knopf
dahinter. Auswählen und Bestätigen sind jetzt zwei Handlungen.

**Die Hintergründe der Check-in-Sheets** liegen als Bild bei (`assets/header/checkin-platform.webp`,
`checkin-clock.webp`): der Kölner Dom, die Hohenzollernbrücke, ein Bahnsteig mit Vordach, einmal mit
Bahnhofsuhr. Ihre untere Hälfte ist schon fast weiß — sie sind gezeichnet, um beschrieben zu werden.
Auf dem einen war ein Keks auf der Nase, auf dem anderen ein beleuchtetes DB-Schild; beide sind raus,
aus dem Grund aus §5.

## 9. Die Website zieht nach

Hausregel: eine sichtbare Änderung in der App ist nicht fertig, solange die Bilder auf
verspaetomat.de die alte zeigen. Alle fünf sind neu aus der Tour, und zwei Bildunterschriften
stimmten nicht mehr:

- Home versprach „eine perforierte Fahrkarte mit dem Knopf zum Einchecken". Die Fahrkarte ist aus
  den Schirmen verschwunden (§2); dort steht jetzt eine Karte.
- Die Fahrt hieß „Unterwegs, mit Umstieg" und zeigte einen Umstieg. Die Aufnahme aus der Tour ist
  eine Fahrt ohne — „Zug 1 von 1". Jetzt heißt sie „Unterwegs, Halt für Halt".
- Der Antragsschalter sprach von drei Verspätungen und 4,50 €. Es sind vier und 6,00 €.

Die Bilder liegen jetzt als **WebP** statt PNG. Mit der neuen Haut — Illustration, Verläufe,
Schatten — wogen die fünf als PNG zusammen 1,2 MB gegen vorher 848 kB; als WebP sind es 288 kB bei
denselben 640 px. Für eine Startseite, die jemand unterwegs im Zug öffnet, ist das der
Unterschied, um den es hier die ganze Zeit geht.

Dabei fielen zwei Regressionen auf, die der Umbau hinterlassen hatte und die nur die Tour findet:
der Check-in-Schritt 2 tippte noch auf `DestinationButton`, den es nicht mehr gibt, und die
Abzeichen auf Ich waren nicht mehr antippbar — ein Abzeichen, das sich nicht öffnen lässt, ist ein
Bild, und das Regal ist keine Galerie. Beides behoben; die Tour läuft wieder ganz durch (75
Aufnahmen). Der Zielvorschlag trägt wieder sein Etikett („Nach Hause"), das beim Umbau auf
`VSelectCard` verloren gegangen war.

