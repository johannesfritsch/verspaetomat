# 11 — Every screen

Navigation (decided 10 September 2026): a bottom bar with four tabs and one action: **Home · Anträge · [Einchecken] · Wir · Ich**. The middle slot is a raised black square with the train icon; it is not a tab but opens the check-in directly (at a station: "Wohin?" for that station, predictions first; elsewhere: the station search, then "Wohin?"). Home is the Bahnsteig. Anträge answers "what is happening with my claims?", Wir "what did it all add up to?". The settings gear sits top right on every tab. Nothing is ever called "Spendenkonto": most of what the ledger holds is not a donation yet, and some of it never will be. The ride view and the claim flow are full-screen moments that sit on top of the tabs.

All copy below is German because that is what the customer reads. Explanations are in English.

---

## 0. Before the app: icon, widget, lock screen

- **Icon:** the station clock face, second hand at twelve, black and red on paper white.
- **Home-screen widget (small):** "Einchecken" button and, when a ride is running, the train and its delay. This is the fallback for people who refuse background location.
- **Lock screen / Live Activity during a ride:** one line. "RE 7 → Münster Hbf · nächster Halt Rheine · +14".

---

## 1. Welcome (three cards, swipe)

**Card 1 — the idea.** A large "+14" with a red plus counts up from 0. "Du wartest sowieso. Mach was draus." One line below: "Verspätungen werden Punkte. Große Verspätungen werden Spenden."

**Card 2 — the promise.** Three short lines, each with a small icon: "Dein Standort bleibt am Bahnhof." "Kein Geld läuft durch uns." "Kein Euro gilt als gespendet, bevor er es ist."

**Card 3 — start.** "Los geht's" and, in small type, "Ohne Konto. Ohne Kreditkarte."

No account is created here. Sign-in is offered later, only for people who want a backup.

---

## 2. Permissions (one screen, two asks)

- **Mitteilungen:** "Damit wir dir beim Ankommen sagen können, wie spät es war." Asked first; nearly everyone accepts.
- **Standort am Bahnhof:** explained with the clock image: "Wir schauen nur, ob du an einem Bahnhof stehst. Während der Fahrt folgen wir dem Zug, nicht dir." Three options, "Auch im Hintergrund" preselected (docs/15): it asks the OS for the Always permission when tapped or on "Weiter"; "Nur wenn die App offen ist" asks for While Using; "Später, ich checke selbst ein" asks for nothing. Every path continues.

Every path continues to the next screen. Nothing is gated.

---

## 3. Dein Ticket, dein Zweck (setup)

**Ticket.** Large cards: "Deutschlandticket", "Andere Zeitkarte", "Einzelfahrkarten". One line under each with what a delay is worth. The D-Ticket card says honestly: "1,50 € pro Verspätung ab 60 Minuten. Ausgezahlt ab 4 €. Wir sammeln für dich." Can be changed per ride and in the profile.

**Zweck.** The NGO list, three to five partners, each as a card with a photo, one sentence, and the money confirmed so far ("Bestätigt über Verspätomat: 12.410 €"). The customer picks one default. Tapping a card opens screen 14.

Personal details and the ticket number are **not** asked here. They are asked the first time a claim is ready.

---

## 4. Bahnsteig (home)

The screen the customer sees a hundred times. Second version, decided 10 September 2026 (docs/16): six blocks, everything above the fold, and the top block adapts to the moment. The clock hero, the date line, "Kein Zug. Gut so.", the standalone search field and the separate nudge and Nachtrag widgets are gone; the small clock stays in the header corner, with the "Standort: Stellwerk · …" caption on its left when a simulated position is active.

**1 · Einchecken (action).**
- Idle away from a station: a compact row of chips: the home station ("Köln Hbf · Stammbahnhof"), up to two more frequent stations, nearby ones with distance if the phone has a fix, and a "Suchen" chip that opens the station search. Each chip opens Einchecken (screen 6). Without a position, one caption offers "Standort erlauben".
- At a station (≤ 300 m): one card "Köln Hbf · Du bist hier · 120 m". Destination first (docs/17): the predicted destinations as one-tap buttons on top ("Nach Hause · Bonn Hbf", "Düsseldorf Hbf"), then "Anderes Ziel …" (or "Wohin? Ziel wählen …" for a fresh account) which opens "Wohin?" (screen 5a); a destination button goes straight to "Welcher Zug?" (screen 5b). Underneath, "Oder erst der Zug:" and the next three rail departures; tapping a row opens "Wohin?" with that train as leg 1. "Alle Abfahrten" in the card's header opens the full board; a long press on the header offers "Diesen Bahnhof nie" (mute).
- Riding: the ride card (line, the journey's destination, live delay, next stop, the transfer or the exit, ETA) with "Zur Fahrt" and "Zug wechseln".
- In transfer: the confirmation card "UMSTEIGEN · Hagen Hbf · RB 52 nach Lüdenscheid · 08:55 · Gl. 6 · Ich bin drin"; after a missed connection the card turns red ("ANSCHLUSS VERPASST") and shows the next possibility.
- Just arrived: the arrival summary with the journey delay, "Anschluss verpasst" when it applies, "Ansehen" and "Fertig", until dismissed.

**2 · Momentum.** "+96" in board type, "Geduldspunkte diese Woche · letzte Woche 41", the level bar underneath with "Gleis 7 · 128 bis „Bahnhofsmission“". A quiet week reads "Diese Woche noch keine Fahrt", never a zero. Tap for Ich.

**3 · The claim cycle.** A four-step strip, Sammeln → Antrag bereit → Eingereicht → Bestätigt, the current step in ink with a red dot, the others grey, joined by a hairline. One line beneath the active step: collecting "4,50 von 4,00 € · für Bahnhofsmission Köln" (or "Noch keine Verspätung ab 60 Minuten. Die erste zählt 1,50 €."); ready: the primary button "6,00 € beantragen" with "Bündel bereit · geht an …"; submitted: "Antwort bis 8. Okt. · 4,50 € unterwegs" or "Rückfrage der Bahn · bitte antworten"; answered (a claim closed in the last 14 days): "4,50 € bestätigt · geht an …" or "Abgelehnt · Widerspruch möglich", and the last step is labelled accordingly. Priority: a claim awaiting a reply shows Eingereicht, else a recently closed one, else ready or collecting; a ready bundle keeps an outline button "Nächstes Bündel: 6,00 € beantragen" underneath in the other stages. Tap for Anträge.

**4 · Standing.** "Platz 5" board type, "auf der RE 7 diese Woche · 38 Punkte bis Platz 4"; at rank 1 "ganz oben, von 23". The city board when the line board has fewer than five riders; hidden when the customer is on neither. Tap for Wir.

**5 · Community with my share.** "1.208.316 Minuten haben wir gewartet · 1.372 davon deine." ticking, and "48.320 € an Vereine bestätigt · 4,50 € durch dich". Tap for Wir.

**6 · The one next thing.** At most one card: "Post von der Bahn · 4,50 € bestätigt" (→ Anträge, scrolled to the claim), "Läuft bald ab · RE 10 vom 21.08. verfällt in 10 Tagen" (→ Anträge, red when 7 days or fewer), "Gestern vergessen?" (→ Nachtrag, only for people who ride most days), "Neues Abzeichen · Volle Stunde" (→ Ich). Nothing otherwise.

Data: `GET /v1/me/standing` computes blocks 2 to 6 server-side (docs/16); the station context comes from nearby stations, the geofence station set and the current ride.


---

## 5a. Wohin? (destination)

Replaces "Wo steigst du aus?" (docs/17). Eyebrow "Ab Köln Hbf", or "Mit RE 7 ab Köln Hbf" when the customer tapped a train first.

- **Predicted destinations** as one-tap buttons: "Nach Hause · Bonn Hbf" (ink, primary), "Düsseldorf Hbf" (outline). The current station is never offered.
- **Zuletzt:** the last five distinct destinations as rows.
- **Bahnhof suchen:** the station search sheet for everything else. A fresh account sees "Beim ersten Mal suchst du dein Ziel. Ab dann steht es hier." and only the search.
- Footer caption: "Der Ausstieg ergibt sich aus der Verbindung. Wir fragen nicht danach."

Any pick opens 5b. Data: `GET /v1/me/destinations?from=<station>`.

---

## 5b. Welcher Zug? (itineraries)

Eyebrow "Köln Hbf → Lüdenscheid", title "Welcher Zug?". The itineraries from `GET /v1/journeys/plan` (rail only), the preferred one first, each as a board row plus a chip line:

- The first leg as a departure row: planned time, line badge, headsign, platform and operator, "+3" or "pünktlich".
- Chips: "direkt" (green) or "1× umsteigen in Hagen Hbf" (ink), "nächste" on the preferred one, "an 09:38 · 111 min" (red when the live arrival is later).
- For connections a caption line: "RB 52 ab Hagen Hbf 08:55".
- The ticket toggle at the bottom, as on Einchecken.

One tap creates the journey (`POST /v1/journeys` with the itinerary's legs, the one-shot location fix and the station's coordinates) and opens Unterwegs. When the customer came from a departure row, the list is filtered to itineraries starting with that train.

---

## 5. Station nudge (notification)

Fires after about three minutes near a station, at most once per station visit, never during a running ride.

"Hauptbahnhof? Check dich ein." Two actions on the notification itself: "Einchecken" (opens screen 6 with the station preset) and "Heute nicht". A long-press offers "Diesen Bahnhof nie" for the station near the customer's home.

If the customer dismisses nudges three times in a row without checking in, the app asks once whether it should stop nudging at that station.

---

## 6. Einchecken (check-in sheet)

A bottom sheet, one thumb.

- **Header:** station name, time, "Standort bestätigt ✓" if a fix was taken (makes the ride board-eligible), or "Ohne Standort" otherwise.
- **List of departures** in board style: line, destination, planned time, platform, and "+3" in red-plus notation if already late. Cancelled trains show "Ausfall" in red and stay tappable (see edge state E1).
- **Filter chips:** "Alle", "RE/RB", "S", "Fern". A search field for a train number.
- Tapping a train slides to screen 7.
- **Ticket toggle** at the bottom, preset from setup: "Deutschlandticket ▾".

If live data is missing: "Keine Live-Daten für diesen Bahnhof." and a manual entry: line, destination, planned departure. Manual rides earn points and can be claimed, marked "selbst eingetragen".

---

## 7. Wo steigst du aus? (exit stop) — retired

Replaced by 5a/5b on 10 September 2026 (docs/17): the exit stop of every leg follows from the itinerary. The screen and its route stay in the code for the legacy single-ride path ("Falscher Zug?") only. Total taps from nudge to riding stay at three: destination, train, done.

---

## 8. Unterwegs (the journey)

Full screen, same paper as everywhere. Designed to be glanced at, not read. Shows the journey (docs/17), not just the train.

- **Top:** line and headsign of the current leg, then "National Express · Leg 1 von 2 · Ziel Lüdenscheid".
- **Centre:** the delay in very large digits, "+14", or "pünktlich" in green. Under it: "Umstieg Hagen Hbf 09:06 statt 08:38" on a leg with a transfer ahead, "Ankunft Lüdenscheid …" on the last one.
- **Stop line:** stops as dots, passed ones filled, next one pulsing, the exit stop marked.
- **DANACH:** the next leg with its live status ("RB 52 nach Lüdenscheid · ab Hagen Hbf 08:55 · Gl. 6"), a red "knapp" chip when the ETA is later than its departure, and the line "Am Umstieg fragen wir einmal: bist du drin?"; then "Ziel Lüdenscheid · an 09:38".
- **Quiet footer:** "Stand 08:41 · Wir folgen dem Zug, nicht dir."
- **Buttons:** "Falscher Zug?" (edge state E2) and "Abbrechen" (the journey is abandoned, no incident). No sharing here; the reveal is at arrival.

**In transfer** (leg done, journey not): "Umsteigen · Hagen Hbf", "RE 7 war +5. Weiter nach Lüdenscheid.", the confirmation card with the next leg (line, headsign, big departure time, platform, arrival at the destination) and the primary button "Ich bin drin". After a missed connection the eyebrow reads "Anschluss verpasst", the card is red-bordered "NÄCHSTE MÖGLICHKEIT" with the re-planned train, and the caption says the delay counts at the destination. Below: "Ich bin da" (ends the journey here, with the delay so far) and "Abbrechen". The same card is what a tap on the transfer push opens.

If the delay passes 60 minutes the footer changes once: "Ab hier entsteht ein Anspruch." Nothing celebrates yet. The claim is measured at the destination of the journey, so on a leg before a transfer the footer is a hint, not a promise.

If data stops: "Letzter Stand 08:41" and the digits dim. If the data never resumes, arrival asks for the actual time (E3).

---

## 9. Angekommen (arrival)

The reveal, and the only screen allowed to feel like a reward. Appears as a notification and as a full screen when the app is opened.

1. Above the number: the lines of the journey and "Köln Hbf → Lüdenscheid".
2. The final delay at the destination ticks in: "+68". "Ankunft Lüdenscheid 10:46 statt 09:38". After a missed connection, in red: "Anschluss verpasst in Hagen Hbf. Zählt am Ziel, nicht pro Zug." A journey ended early via "Ich bin da" says so: "Beendet unterwegs: die Verspätung bis Hagen Hbf zählt."
3. One line: "68 Minuten. 68 Geduldspunkte."
4. If a badge was earned, it appears here, once.
5. The money line, honest and specific:
   - D-Ticket, 60+: "Anspruch entstanden: 1,50 € für die Bahnhofsmission. Gesammelt: 3 von 3 · Bündel ist bereit." or "… 1 von 3."
   - Ordinary ticket, 60+: "Anspruch entstanden: ca. 15,00 € (25 % von 60,00 €). Jetzt einreichen."
   - Under 60 minutes: "Kein Anspruch, aber 14 Minuten Geduld. Trotzdem spenden →" (link out to the NGO's page, see screen 14).
6. Two buttons: "Teilen" (a card image with the delay, the lines, and the NGO) and "Fertig".

If the claim is ready, "Jetzt einreichen" opens the claim flow (screen 11).

---

## 10. Anträge (my claims)

Replaces Konto in the nav (10 September 2026). One question: what is happening with my claims? Header "Anträge" with a caption like "3 Fälle gesammelt · 1 Antrag unterwegs", the gear top right.

- **Sammeln.** The bundle being collected, grouped by claims desk with a heading only when there is more than one: the incidents, "4,50 von 4,00 €" or the "bereit" chip, the dots "2 von 3 · noch 1,50 €", and one line explaining the per-desk bundling when it applies. The deadline line above it in red when the oldest incident expires within 30 days. "Antrag vorbereiten" as the primary button at the bottom when a bundle is ready. Empty: "Nichts offen. Gut so. Verspätungen ab 60 Minuten landen hier. Ab 4 € geht ein Antrag raus."
- **Eingereicht.** One card per claim that is out: "Antrag vom 15.08." with the amount, a status chip (eingereicht · Rückfrage · nicht zugestellt), "Antwort bis 12.09. · Servicecenter", the incidents, then the mail thread collapsed to the last message ("POST VON DER BAHN · 18.07." or "DEINE MAIL · 15.08." above a compact mail view). Buttons: "Antworten" on a question, "Alle 3 Nachrichten" or "Ganze Mail lesen" (opens screen 12 with the thread and the reply form), "PDF ansehen".
- **Bestätigt.** The same card for accepted claims: "4,50 € überwiesen", the railway's mail beneath.
- **Abgeschlossen.** Rejected claims (with "Widerspruch") and expired incidents, with the one line: "Verfallen heißt: die Frist ist um, bevor 4 € zusammenkamen. Die Minuten und Punkte bleiben."
- A push for railway mail opens this tab scrolled to the claim (`/antraege?claim=<id>`). Tapping an incident shows the evidence sheet as before.

Ordinary-ticket incidents appear under Sammeln too, each with its own "Einreichen". They take the same five steps with one incident instead of a bundle: step 1 shows the fare and the booking number instead of the D-Ticket number, step 2 asks for the ticket itself (the booking PDF or a photo of the paper ticket), and the amount is 25 % or 50 % of the fare.

---

## 11. Antrag (the claim flow, five steps, full screen)

Step indicator at the top: "1 Prüfen · 2 Ticket · 3 Zweck · 4 Unterschrift · 5 Senden".

**11.1 Prüfen.** The incidents in this bundle, each with its details, editable. The desk it goes to. First time only: name, address, private e-mail, D-Ticket number, asked here. The app then shows the customer's new sender address: "Deine Anträge gehen von fahrgast-4711@users.verspaetomat.de raus. Antworten der Bahn landen dort und sofort auch in deinem Postfach." One line: "Diese Daten stehen nur auf dem Formular."

**11.2 Ticket.** "Füge einen Screenshot deines Tickets mit Barcode an." Buttons: "Aus Fotos", "Aus Ticket-App" (share-in). When the bundle spans months, the app asks for one screenshot per month covered ("August und September") because each month is technically a new ticket. The images are shown, with: "Werden nur diesem Antrag beigefügt und nach Abschluss gelöscht."

**11.3 Zweck.** The NGO card, large, with account holder name and IBAN shown in full: "Die Entschädigung geht direkt an: Bahnhofsmission Köln e.V., DE12 …". A switch: "Anderen Zweck für diesen Antrag wählen".

**11.4 Unterschrift.** The filled form is shown as the real PDF the server generated, first page inline with a full-screen zoomable view, exactly what will be attached. Under it a signature field with the customer's name typed already; drawing is optional for the EU form, required for the paper route. The declaration text from the form is repeated in plain German: "Ich bestätige, dass die Angaben stimmen und ich Inhaber:in des Tickets bin."

**11.5 Senden.** The mail as it will go, with the signed PDF shown under "Anhang": from the customer's Verspätomat address with their name, to the claims desk, subject, the short body (which states that the mail is transmitted via Verspätomat and names the claimant), the two attachments, and "Kopie an: dein privates Postfach". One button: "Absenden". A quiet full-screen "Abgeschickt. 9. September 2026." follows, the incidents turn "eingereicht", and the copy is in the customer's inbox before they close the screen.

Paper route alternative on 11.5: "Als PDF zum Drucken" with the postal address shown. Bounces (wrong or dead operator address) come back within minutes as a ledger note: "Nicht zustellbar. Wir prüfen die Adresse."

---

## 12. Antwort (the reply)

The thread behind a claim card on Anträge (screen 10), reached with "Alle Nachrichten", "Antworten" or "Widerspruch"; the reply form lives here. Most replies arrive on their own. The railway answers to the customer's Verspätomat address; the app forwards the mail whole to the private inbox and, at the same moment, shows it here.

- **Accepted:** "Die Bahn hat geantwortet: 4,50 € an Bahnhofsmission überwiesen." The original mail is one tap away. Incidents turn "bestätigt". If the amount could not be read, the app shows the mail and asks the customer to enter it.
- **Question from the railway:** the mail is shown, with "Antworten" opening a reply composed by the customer, again through their own address. Templates for the usual questions (ticket copy, exact train) are offered; nothing is sent without the customer.
- **Rejected:** the mail is shown, the reason highlighted if recognisable, incidents turn "abgelehnt". The customer sees the mediation link (söp) once, without pressure, and a template for a reply if they want to push back themselves.
- **Postal reply instead:** four weeks after sending, if nothing has arrived: "Post von der Bahn bekommen?" with "Fotografiere die Antwort"; the app reads the amount if it can.
- Confirmation also arrives when the NGO's monthly report lists the transfer. That report is entered by us from the NGO's statement; affected customers get one notification ("Bahnhofsmission bestätigt 4,50 € aus deinem Antrag vom 20. Juni") and the incidents turn "bestätigt" the same way.

---

## 13. Wir (community)

- **Dein Teil first** (10 September 2026): two figures, "Bestätigt, durch dich" (euros the railway confirmed for this customer) and "Minuten gewartet", the level bar with "Gleis 7 · 128 bis „Bahnhofsmission“", then the rows "Eingereicht, unterwegs" and "Zweck" (tap opens the NGO page). These were the header numbers of the old Konto.
- **Top community figure, board type:** minutes waited together, ticking.
- **Two euro figures side by side:** "Eingereicht" and "Bestätigt", the second larger. Tap either for the source sheet.
- **Vereine:** one row per NGO with the euros confirmed for it and, smaller, the euros submitted and still unanswered. No goals, no deadlines, no progress bars: the number is the story.
- **Boards:** "Meine Linie" as the default, with "Meine Stadt" and "Deutschland" as tabs. Seven-day window, ten names, the customer's own row pinned at the bottom if not in the ten.

---

## 14. Zweck (NGO page)

- Photo, name, the one sentence, three short paragraphs about what the money does.
- **Transparency block:** account holder, IBAN, "Bestätigt über Verspätomat: 12.410 €", last report date.
- Two buttons: "Als Standard wählen" and "Trotzdem spenden" (opens the NGO's own donation page in the browser, with one line first: "Das läuft nicht über uns. Du landest direkt bei der Bahnhofsmission.").

---

## 15. Ich (profile)

- Name or nickname, level name, Geduldspunkte total, points this week. The level bar moved to Home and Wir; the gear is the shared one in the tab header.
- Badges as a grid, earned ones in colour, others as outlines with their names visible (the museum is part of the fun).
- History ("Alle Fahrten"): every journey, grouped by day and filterable by line, as one row "RE 7 · Köln Hbf → Lüdenscheid · +68" with chips for "2× umsteigen", "Anschluss verpasst", "unvollständig", "abgebrochen"; a tap unfolds the legs with their times and delays (docs/17). Data: `GET /v1/journeys`.
- "Meine Statistik": average delay, most patient line, longest wait, minutes this year.
- Links to Einstellungen.

---

## 16. Einstellungen & Datenschutz

- Ticket type, default NGO.
- Nudges: on/off, quiet hours. Stumme Bahnhöfe: the muted list with a remove action, and "Bahnhof hinzufügen" via the station search; muting also happens on the nudge itself ("Diesen Bahnhof nie"). The list lives on the account, not the phone.
- Standort: current permission with a plain explanation and a link to change it.
- Persönliche Daten für Anträge: view, edit, delete.
- Meine Verspätomat-Adresse: the sender address, what arrives there, "Korrespondenz nach Abschluss behalten" switch (off by default), and a full export of all sent and received mails.
- Konto: Name (the nickname shown in boards and on Ich; a blank one takes the first name once claim data is saved), Wiederherstellungscode (no sign-in; the 12-word code moves the account), Träwelling.
- Träwelling verbinden: import check-ins from a linked Träwelling account so nobody checks in twice. Read-only, off by default.
- Boards: "Mich in Ranglisten zeigen" switch.
- Daten exportieren · Alles löschen: one tap each, with a confirmation.
- "Woher kommen die Daten?" opens the content of doc 13 as a page.
- Rechtliches: three pages rendered from `app/lib/content/legal.dart` (Impressum, Datenschutz, "Wie wir Anträge weiterleiten"); the last one is also linked from the send step of the claim ("Mehr").

---

## 17. Rechtliches (Impressum · Datenschutz · Wie wir Anträge weiterleiten)

Plain reading pages under `/rechtliches/:id`. Eyebrow "Rechtliches", the title, a two-line lead, then sections with a hairline above each heading; text is selectable. Each page ends with links to the other two. The Datenschutz page is the wording the store privacy labels are derived from (docs/40-store-listing.md). Placeholders in square brackets (operator name and address) are filled in before the first store build.

---

## Edge states

**E1 — Ausfall.** A cancelled train is tappable in the check-in sheet. The app asks: "Wann fährst du stattdessen?" and offers the next departures. The ride is recorded against the cancelled train with the actual arrival of the replacement; the delay is the difference. If the customer gives up: "Reise nicht angetreten" is recorded, which is a valid claim reason on the form.

**E2 — Falscher Zug.** From the ride screen: pick another departure from the same station within the last 30 minutes. Points are not affected; boards count the ride only if changed within ten minutes.

**E3 — Keine Daten bei Ankunft.** "Wann bist du angekommen?" with a time picker preset to the planned arrival. The ride earns points; the ledger marks it "selbst eingetragen" and the claim PDF says so in the free text.

**E4 — Nachtrag.** "Gestern vergessen einzuchecken?" from Bahnsteig. The customer picks date, station, train and exit stop. Earns one point, is claimable if the delay data exists, never ranks on boards. The screen says why the two differ: points reward being there, claims rest on the railway's own delay record.

**E5 — Betreiber nicht im Verzeichnis.** At the claim step: the operator's name, "Wir kennen die Adresse für Anträge noch nicht.", a link to the operator's passenger-rights page, and a field to enter the address. We add it to the directory afterwards.

**E6 — Verfall.** Three weeks before the oldest incident hits the three-month deadline: one notification, one red line in Konto. If the bundle is under 4 € at the deadline, that incident alone turns "verfallen" with a plain explanation; its minutes and points stay, and the remaining incidents keep collecting toward the next bundle.

**E7 — Grenzfall 59 Minuten.** The arrival screen says "+59. Kein Anspruch, um eine Minute. Wir wissen." Nothing else. The customer will screenshot it.

**E8 — Offline.** Every screen shows its last state with an age stamp. Check-in works offline against the cached timetable and syncs later.
