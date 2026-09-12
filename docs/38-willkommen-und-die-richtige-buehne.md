# 38 — Willkommen, dunkle Klappen, und der richtige Navigator

Decided 12 September 2026 (Johannes, aus den Issues 10, 12 und 14). Zwei davon sind Korrekturen
an der letzten Runde.

## 1. Die Klappe ist dunkel, der Kasten wechselt (Issue 10)

Letzte Runde waren die Klappen weiß mit Ink-Ziffern. Falsch herum: **die Klappe eines echten
Bretts ist dunkel und die Schrift darauf weiß** — das ändert sich nicht, wenn das Brett in einem
weißen Kasten hängt.

Also jetzt: Klappe `#1D1D1D`, Schrift Papier, Scharnier Schwarz — in beiden Karten. Was sich
unterscheidet, ist nur der Kasten darum: das schwarze Brett auf Wir und Ich, der weiße Kasten auf
„Deine Woche".

Die Gruppentrenner hängen zwischen den Klappen, also auf dem Kasten: auf dem Brett nehmen sie
Papier, auf der weißen Karte Ink. Ohne das verschwindet der Punkt in `1.208.317` je nach Karte.

## 2. Der Knopf war nie das Problem, der Navigator war es (Issue 12)

Die Korrektur der Korrektur. Letzte Runde habe ich den Kontext des Shell-Bodys über einen
`Builder` eingefangen — und damit einen Kontext **über** dem Shell-Navigator, denn der Builder
umschließt genau das Widget, das dieser Navigator ist. Das Sheet landete weiter auf dem
Root-Navigator und deckte die Leiste zu.

Jetzt hat die `ShellRoute` einen `navigatorKey`, und das Quadrat öffnet mit
`shellNavigatorKey.currentState.overlay.context` — dem Overlay des Shell-Navigators, und das
liegt **unter** ihm. Damit findet `showModalBottomSheet` den Shell-Navigator, das Sheet erscheint
im Body des Scaffolds, und die Leiste bleibt stehen. Genau wie beim Knopf auf Home, der schon
immer von innen kam.

## 3. Home heißt Willkommen (Issue 14)

Home war der einzige Schirm ohne Namen: nur ein Zahnrad oben rechts. Jetzt trägt er denselben
`TabHeader` wie Wir, Ich und Anträge — Titel „Willkommen", das Zahnrad rechts, und die
Stellwerk-Zeile als Bildunterschrift darunter, wo sie hingehört: eine Notiz darüber, wo die App
sich gerade wähnt.

(Die Zeile war vorher rot. Als Caption ist sie grau wie jede andere; sie steht jetzt unter einem
Titel und ist dadurch nicht weniger auffällig. Wenn sie schreien soll, gehört sie in ein eigenes
Element, nicht in die Kopfzeile.)
