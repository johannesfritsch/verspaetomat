# 39 — Der Überblick vorweg, abgehakte Fälle, und ein Entwurf, der liegen bleibt

Entschieden 14. September 2026. Der Antrag ist die einzige Stelle, an der ein Fahrgast in dieser
App etwas unterschreibt. Diese Runde räumt die fünf Schritte davor auf — und repariert drei
Dinge, die dabei aufgefallen sind.

## 1. Erst der Überblick, dann die erste Frage

Vor Schritt 1 steht jetzt ein Vorschritt: „So läuft das". Er nennt die Zahl der Fälle und die
Summe, listet die fünf Schritte mit je einem Satz, was sie wollen, und endet mit dem Satz, der
für den ganzen Antrag gilt: *Wir füllen ihn aus und überbringen ihn, wir schreiben der Bahn nie
von uns aus.* Wer ihn nicht will, drückt „Später".

Der Grund: die erste Frage des alten Schritts 1 war „Name, Adresse, Ticketnummer" — die
persönlichsten Angaben der ganzen App, ohne dass vorher irgendwer gesagt hätte, wofür.

## 2. Ein Haken pro Fall

Schritt „Prüfen" zeigt alle offenen Fälle der Stelle mit einem eckigen Haken davor, alle
angehakt. Abhaken nimmt einen Fall **aus diesem Antrag**, nicht aus dem Konto: er bleibt liegen
und kommt in den nächsten. Das ist bewusst etwas anderes als „nicht einreichen" im
Nachweis-Sheet, das einen Fall für immer verwirft (docs/21 §4) — deshalb ein Haken und kein
Wischen, und deshalb der Satz unter der Liste, der beides auseinanderhält.

Der eckige Haken ist neu (`VCheckbox`): der runde Haken der App heißt „genau eines davon", und
hier dürfen mehrere an sein.

Die Zeile über der Liste zählt mit: „3 von 4 · 4,50 €".

**Die 4 € entscheidet der Server.** Die App rechnet nichts nach: sie schickt die neue Auswahl,
und wenn der Rest die Auszahlungsgrenze reißt, antwortet der Server mit 412 und die App sagt
„Ohne diesen Fall kommen keine 4 € zusammen. Er bleibt drin." Der alte Entwurf steht weiter.

## 3. Der Entwurf bleibt liegen, wie er war

Bisher baute jeder Besuch des Antrags einen neuen Entwurf: wer in Schritt 2 das Ticket angehängt
hatte und einmal zurückging, hängte es danach noch einmal an.

Jetzt gibt es **einen offenen Entwurf je Stelle**. Wer den Antrag ohne Auswahl öffnet — also
über „Antrag vorbereiten" — bekommt den Entwurf, der da liegt, mit seinem Ticket und seiner
Unterschrift. Nur eine *genannte* und *andere* Auswahl ersetzt ihn, denn ein Formular mit
anderen Fällen ist ein anderes Formular und will neu unterschrieben werden. Fällt einer seiner
Fälle inzwischen weg (verworfen, verfallen), wird ebenfalls neu gebaut.

Die App erkennt dabei wieder, was schon dranhängt: die Anhänge kommen mit ihrer Upload-Id
zurück, und der Name eines Tickets („Ticket September 2026") folgt einer Regel, die es nur
einmal gibt (`app/lib/content/labels.dart`). Damit fragt Schritt 2 nach einem wiederaufgenommenen
Entwurf nicht noch einmal nach demselben Bild.

## 4. Drei Reparaturen am Rand

**Die Unterschrift überlebt einen Anhang.** `PATCH /v1/claims/{id}` ersetzt die Tickets — die
Unterschrift ist keines. Sie bleibt beim Ersetzen stehen, sonst nimmt ein Ticket, das nach dem
Unterschreiben angehängt wird, die Unterschrift vom Formular.

**Ein PNG ist ein PNG.** Uploads ohne Content-Type landeten als `application/octet-stream`, und
das Formular druckt nur, was es als Bild erkennt. Der Server schaut jetzt auf die ersten Bytes
(und notfalls auf den Dateinamen); die App schickt den Typ von sich aus mit. Beides zusammen,
damit ältere Builds im TestFlight ihre Unterschrift behalten.

**Anhänge heißen `{upload_id, label}`.** Die App schickte eine nackte Liste von Ids — 422. Jetzt
schickt sie, was der Server seit jeher liest, und das Label wird der Dateiname in der Mail an die
Bahn (docs/18).

## Was geprüft ist

`backend/src/handlers.rs` hat die Entscheidung als reine Funktion (`draft_action`) mit drei
Tests, dazu die Typ-Erkennung (`image_content_type`). Der Workflow-E2E hat einen zweiten Lauf
bekommen, der ohne fahrende Züge auskommt: vier nachträglich eingetragene Fahrten aus dem
Stellwerk, der Vorschritt, ein abgehakter Fall, die abgelehnte Auswahl unter 4 €, das Verlassen
und Wiederkommen mit noch angehängtem Ticket, und der wieder angehakte vierte Fall, der das
Ticket kostet.
