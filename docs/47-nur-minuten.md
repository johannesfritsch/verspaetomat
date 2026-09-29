# 47 — Nur Minuten

Entschieden am 29. September 2026, Issue #74. Bis dahin gab es zwei Zahlen für dasselbe: Minuten
und Geduldspunkte. Jetzt gibt es nur noch Minuten — in der App, auf der Website, in den
Mitteilungen und in dieser Doku.

## Warum

Geduldspunkte waren „1 Punkt pro Minute Verspätung" (docs/12). Sie waren also Minuten unter
anderem Namen, mit zwei Ausnahmen, die kaum jemand kannte. Zwei Zahlen, die fast immer gleich
sind und manchmal nicht, lesen sich als Fehler: Home zeigte 158 Minuten, Ich 146 Geduldspunkte
(#71). Und ein Punkt bedeutet einem Menschen nichts, eine Minute schon — jeder weiß, wie sich 68
Minuten am Bahnsteig anfühlen. Die Abzeichen stehen für sich und brauchen keine Währung daneben.

## Die Regel (`backend/src/rules.rs`, `counted_minutes`)

Eine Fahrt zählt ihre **Verspätung am Ziel**, ab Minute 1. Eine Reise mit Umstieg zählt einmal,
am Ziel, nicht pro Zug (docs/17), gedeckelt um eine selbst gewählte Pause (docs/21 §2).

Die zwei Ausnahmen der Punkte sind Minuten-Regeln geworden:

| Fall | Vorher | Jetzt |
|---|---|---|
| **Ausfall** | 60 Punkte | zählt mit mindestens **60 Minuten** — das Recht behandelt einen Ausfall wie eine Stunde Verspätung, und ein Zug, der nicht fuhr, hat keine eigene Verspätung. Die App sagt „60 Minuten angerechnet". |
| **Nachtrag** (Fahrt nachträglich eingetragen) | 1 Punkt | zählt **seine Minuten** für einen selbst, steht als „selbst eingetragen" da und **nicht in den Ranglisten** — wie jede Fahrt ohne Standortbestätigung. Das ist der Schutz gegen erfundene Verspätungen, und er braucht keine zweite Währung. |
| **Aufgegeben** (docs/22 §1) | Punkte fürs Warten | zählt das **Warten** auf dem Zug, auf dem aufgegeben wurde. Einen Anspruch gibt es nicht. |
| **Nicht mitgefahren** | nichts | nichts |

Die Stufen (Frischer Fahrgast … Bahnsteig-Buddha) haben ihre Schwellen jetzt in Minuten: 60, 240,
600, 1.500, 4.000. Die Ranglisten zählen die Minuten der letzten sieben Tage, nur Fahrten mit
Standortbestätigung.

## Wo die Zahl liegt

- **Datenbank:** Die Spalten `rides.points` und `journeys.points` behalten ihren Namen — so bricht
  keine Abfrage und kein älterer Build — und tragen die **gezählten Minuten** (per
  `comment on column` dokumentiert, Migration 0042). Die Sicht `waited_minutes` (Migration 0041,
  #71) liest dieselbe Spalte: Jede Zahl, die „Minuten" heißt, ist eine Zahl.
- **Draht:** Die Felder heißen `minutes_total`, `minutes_this_week`, `minutes_last_week`,
  `minutes_by_day`, `level.minutes_to_next`, `counted_minutes` (Fahrt und Reise) und `minutes`
  (Ranglisten). Die alten `points_*`-Felder bleiben mit denselben Werten, solange ein älterer Build
  in TestFlight oder im Store ist (Hausregel: nur hinzufügen).
- **App:** liest die `minutes_*`-Felder, sonst die alten eines Servers von vorher.

## Was sich für Menschen ändert

- Ich zeigt oben „Minuten gewartet" statt Geduldspunkte; Home und Ich zeigen dieselbe Zahl.
- Die Ankunft sagt „68 Minuten. Alle gezählt." statt „68 Minuten. 68 Geduldspunkte.", ein Ausfall
  „Ausgefallen. 60 Minuten angerechnet."
- Ein Nachtrag bringt seine Minuten, nicht mehr einen Punkt. Alte Nachträge wurden umgerechnet.
- Die Teilen-Karte zeigt nur noch die Minuten.
- Mitteilungen: „68 Minuten gewartet." statt „68 Geduldspunkte.".

## Ältere Dokumente

Die Dokumente vor diesem sprechen von Geduldspunkten und Punkten. Sie sind Entscheidungen ihrer
Zeit und bleiben so stehen; gemeint sind die gezählten Minuten dieses Dokuments. Maßgeblich für
die Regeln ist docs/12, das nachgezogen ist.
