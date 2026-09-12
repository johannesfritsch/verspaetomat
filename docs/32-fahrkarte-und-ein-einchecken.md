# 32 — Die Fahrkarte als Kartenform, und ein Einchecken

Decided 12 September 2026 (Johannes). Zwei Dinge: die App bekommt die Kartenform der Website,
und das Einchecken hört auf, seine erste Frage zweimal zu stellen.

## 1. Eine Karte ist eine Fahrkarte

Die Website hat für ihren Helden eine Silhouette gebaut (docs/31 §2.1, `.fahrkarte` in
`site/static/verspaetomat.css`): weißes Papier auf grauem Grund, links und rechts eine Haarlinie,
oben und unten nichts — dort sind Halbkreise **aus der Kante herausgebissen**. Man erkennt das
Ding als Fahrkarte, bevor ein Wort darauf gelesen ist.

In der App gab es das bisher an genau einer Stelle, der Teilen-Karte (`widgets/ticket.dart`), und
dort andersherum: ein Rechteck in Papierfarbe mit **grauen Punkten obendrauf**. Aus der Nähe liest
das als Punktreihe, nicht als Riss. Alle anderen „Karten" waren 1,5-px-Rahmen mit 4 px Radius —
also genau die Form, die `app/STYLE.md` verbietet („Rules instead of cards"), nur überall.

Jetzt gibt es **eine** Kartenform, `VFahrkarte` in `widgets/kit.dart`:

- `VTicketBorder`, ein `ShapeBorder`: das Rechteck **minus** einer Reihe Halbkreise oben und
  unten (`Path.combine(difference)`), dazu die zwei Seitenlinien. Subtraktiv, also zeigt der Biss
  das, was wirklich dahinter liegt — dieselbe Form funktioniert auf Papier, auf Weiß und über
  einem Sheet.
- Die Zahlen der Website: Radius 5, Raster 14. Die Zähne sind **mittig verteilt**, damit keiner
  von einer Ecke halbiert wird; ein halber Zahn liest sich als Rendering-Fehler, ein ganzer als
  Perforation.
- `strong: true` ist die eine Karte auf einem Screen, die die offene Kasse ist: Seitenlinien in
  Ink statt Rule.

**Die Form bedeutet etwas**, sonst bedeutet sie nichts: eine Fahrkarte ist **eine Fahrt oder ein
Antrag** — etwas, das man jemandem in die Hand geben könnte. Also: die laufende Fahrt und die
Ankunft auf Home, jeder Antrag und die Sammelkarte in Anträge, die Einchecken-Karte. Nicht:
„Deine Woche", „Wir", Auswahlkarten, Einstellungszeilen. Und ausdrücklich nicht der
Deutschlandticket-Schuss (`MockTicket`) — das ist die Fahrkarte eines anderen Produkts und soll
wie ein fremder Screenshot aussehen, nicht wie unsere.

Die Teilen-Karte behält ihren Painter, mit einer Ausnahme, die ihr Grund hat: sie wird über eine
`RepaintBoundary` als PNG aufgenommen und muss deckend bleiben; ein echter Clip gäbe transparente
Bisse. Sie malt deshalb wie die Website: weißer Körper, Zähne in Papiergrau, dieselben zwei
Haarlinien, derselbe Radius, dasselbe Raster (`VTicketBorder.radius`, `.pitch`). Drei Medien —
App, geteiltes Bild, Website — ein Objekt.

## 2. Ein Einchecken, eine erste Frage

Home hat Bahnhöfe vorgeschlagen: die Karte mit „Von <Bahnhof>", den Zielen aus der Historie und
dem „Wohin?"-Feld, und wenn kein Fix da war, die Fernbox mit Stammbahnhof, häufigen und nahen
Bahnhöfen. Der erste Schritt des Eincheckens (`Von wo?`, docs/24 §1) stellt dieselbe Frage — kannte
aber nur den erkannten Bahnhof und zwei Nachbarn. Zwei Orte, zwei verschiedene Antworten auf
„von wo fährst du los?", und der bessere Vorschlag stand an der Stelle, die nicht die Frage war.

Jetzt:

- **Home ist ein Knopf.** Ein Stück Papier, „Fährst du gleich?", „Von wo, wohin, welcher Zug. Ab
  dann zählen wir mit.", `Einchecken`. Kein Bahnhofsname, keine Ziele, kein Feld. Home weiß
  nichts mehr über Bahnhöfe — nur, dass hier eine Fahrt anfangen kann.
- **„Von wo?" schlägt vor**, und zwar alles, was es gibt: der erkannte Bahnhof mit Entfernung
  zuerst, die zwei nächsten darunter, dann „Deine Bahnhöfe" aus `GET /v1/me/geofence` (der
  Stammbahnhof als solcher beschriftet), dann die Suche. Doppelte fallen über `sameStation`
  heraus, nicht über die Id allein (docs/30 §1).
- **„Standort erlauben"** steht jetzt dort, wo es hilft: im Sheet, wenn das Telefon nichts weiß
  und nicht gerade sucht. Vorher hing es an der Fernbox auf Home und war damit weg, sobald die
  Karte einen Bahnhof zeigte.
- Der Ein-Tipp-Weg von Home („Nach Rheine" direkt in die Zugliste) fällt weg. Er hat einen Schritt
  gespart und dafür eine zweite Wahrheit gepflegt.

Damit gilt der Satz aus `checkin_flow.dart` ohne Fußnote: **das ist der einzige Weg in ein
Check-in.** Quadrat, Hinweis und Home-Knopf laufen dieselben drei Sheets; nur der Hinweis darf
Schritt 1 überspringen, weil er den Bahnhof mitbringt.

Mitgegangen ist: die Von-Zeile, die Fernbox, die „Standort wird geprüft"-Karte, das
„Wohin?"-Feld auf Home — und das Stummschalten per Long-Press auf der Home-Karte. Stumm schalten
geht weiter am Hinweis selbst und in den Einstellungen, was die beiden Stellen sind, an denen man
es sucht.

## Was das an Tests und Bildern kostet

- Die E2E (`workflow_test.dart`) hatte zwei Wege durch den Check-in, den Karten-Weg und
  `viaSquare`. Es gibt nur noch einen Weg; `viaSquare` entscheidet jetzt bloß, welcher Knopf
  gedrückt wird — das Quadrat (`nav-checkin`) oder der auf Home (`einchecken-cta`).
- Die Tour verliert `bahnsteig-away`, `bahnsteig-locating`, `bahnsteig-von-nach` und
  `einchecken-von-square` (Home sieht in allen Fällen gleich aus) und bekommt dafür einen Schuss
  vom leeren „Wohin?".
- `site/static/shots/bahnsteig.png` zeigt die alte Karte, und die Bildunterschrift verspricht
  „Einchecken in zwei Tipps". Beides neu aus der Tour, beides im selben Commit.
