# 11 — Every screen

Navigation (decided 10 September 2026): a bottom bar with four tabs and one action: **Home · Anträge · [Einchecken] · Wir · Ich**. The middle slot is a raised black square with the train icon; it is not a tab but opens the check-in directly (at a station: "Wohin?" for that station, predictions first; elsewhere: the station search, then "Wohin?"). While a journey is under way the square is drawn disabled (grey fill, no shadow) and a tap opens the ride sheet instead of a second check-in (docs/20). Home is the Bahnsteig. Anträge answers "what is happening with my claims?", Wir "what did it all add up to?". The settings gear sits top right on every tab. Nothing is ever called "Spendenkonto": most of what the ledger holds is not a donation yet, and some of it never will be. The claim flow is a full-screen moment that sits on top of the tabs. The ride is not: while a journey is under way, a 56 px **ride bar** sits directly above the bottom nav on every tab (line badge, "nach Rheine", the live delay, the next stop with its time; in transfer the next train, "Umsteigen in Hagen Hbf" and a small ink button "Ich bin drin"), and tapping it opens the **ride sheet** (screen 8) over the active tab. The bar and the sheet belong to the tab shell (`RideMonitor`, one poll for all tabs); the bar is hidden while the sheet is open. The shell docks the bar above the nav, so tab content is never covered by it (docs/19).

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

The screen the customer sees a hundred times. Fourth version, decided 10 September 2026 (docs/16, docs/18, then docs/19): the check-in card, then two things and nothing else. The gear sits in the header corner (no clock since docs/20), with the "Standort: Stellwerk · …" caption on its left when a simulated position is active.

**1 · The action.** The first station the customer picks is where the journey starts, and the card says so (docs/19 §3).
- Idle away from a station: the section is labelled "Startbahnhof". The box is titled "Von wo fährst du los?" (with a position but no station near: "Kein Bahnhof in der Nähe · von wo fährst du los?"), one line of context (without a position it starts with "Wo bist du?"), then chips, each reading "Ab <name>": the home station ("Ab Köln Hbf · Stammbahnhof"), up to two more frequent stations, nearby ones with distance, and "Suchen" (the station search). Each chip opens Einchecken (screen 6). Without a position the box offers "Standort erlauben".
- At a station (≤ 300 m): the section is labelled "Einchecken"; one card with the eyebrow "STARTBAHNHOF", the title "Ab Köln Hbf" and "Du bist hier · 120 m". Underneath, the destinations from this person's previous journeys as one-tap rows (most frequent first, the home station labelled "Nach Hause" when away from it, at most four), then always a "Wohin?" field that suggests stations as you type; a fresh account sees the station name and the field only. Tapping a destination or a suggestion goes straight to "Welcher Zug?" (screen 5b). No departures list. A long press on the station name offers "Diesen Bahnhof nie" (mute).
- Riding: block 1 is the **ride card** (docs/20) on elevated paper: eyebrow "UNTERWEGS", the line badge and "RE 7 nach Rheine", the live delay (or "pünktlich"), then "Nächster Halt · Solingen Hbf 10:06" and "Ziel · Rheine an 12:08", and the caption "Tippen für Details". Tapping it opens the sheet (screen 8). In transfer: eyebrow "UMSTEIGEN", the station as title, the next train as "RE 5 nach Kleve · 10:41 · Gleis 3", "Anschluss verpasst · nächste Möglichkeit" in red when it applies, and the primary button "Ich bin drin". The ride bar above the nav stays as well: the card is the detail, the bar the constant.
- Just arrived (sheet closed): the arrival summary with the journey delay, "Anschluss verpasst" when it applies, "Ansehen" and "Fertig", until dismissed.

Under the card, only when the person rides most days and skipped yesterday: the caption link "Gestern vergessen einzuchecken?" (→ Nachtrag).

**2 · Deine Woche.** "+96" in board type, "Geduldspunkte diese Woche · letzte Woche 41", the level bar underneath with "Gleis 7 · 128 bis „Bahnhofsmission“". A quiet week reads "Diese Woche noch keine Fahrt", never a zero. Tap for Ich.

**3 · Wir.** A block on elevated paper with a hairline border: the community's minutes as a large ticking figure in the display style ("1.208.316", caption "Minuten haben wir gewartet"), beneath it a thin bar whose filled part is this customer's share (drawn at least 6 px wide, so it is visible) with the caption "1.372 davon deine". The whole block taps through to Wir.

Gone since docs/18: the standing line (now above the boards on Wir), the "next thing" card (railway mail shows as a red count on the Anträge tab icon; deadlines live on Anträge; new badges on Ich), the community euro line. Gone since docs/19: the claim cycle strip (it lives on Anträge; the tab badge carries the news).

Data: `GET /v1/me/standing` computes blocks 2 and 3 and the unread count server-side (docs/16, docs/18); the station context comes from nearby stations, the geofence station set and `GET /v1/me/destinations` (history only); the ride comes from the shell's monitor (`GET /v1/journeys/current`, `GET /v1/rides/current`), polled every 20 s while under way and refreshed on ride events and app resume.


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

Eyebrow "Köln Hbf → Lüdenscheid", title "Welcher Zug?". The instruction above the list is one sentence in `bodyStrong`, "Tipp auf den Zug, in dem du sitzt.", with the caption "Umstiege folgen später von selbst." (docs/19 §4). The itineraries from `GET /v1/journeys/plan` (rail only), the preferred one first, each as a board row plus a chip line:

- The first leg as a departure row: planned time, line badge, headsign, platform and operator, "+3" or "pünktlich", then a chevron (ink2) at the end of the row; the whole row is one tap target with a pressed state.
- Chips: "direkt" (green) or "1× umsteigen in Hagen Hbf" (ink), "nächste Verbindung" on the preferred one, "an 09:38 · 111 min" (red when the live arrival is later).
- For connections a caption line: "RB 52 ab Hagen Hbf 08:55".
- The ticket toggle at the bottom, as on Einchecken.

One tap creates the journey (`POST /v1/journeys` with the itinerary's legs, the one-shot location fix and the station's coordinates) and returns to Home with the ride sheet open (screen 8). When the customer came from a departure row, the list is filtered to itineraries starting with that train.

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

## 8. Unterwegs (the ride sheet)

Since docs/19 not a screen but a draggable bottom sheet over the active tab, like the player in a music app: it opens at 0.92 of the screen, snaps at 0.92 and 0.5, and closes when dragged below 0.3 (the bar above the nav then carries the ride; tapping the bar opens the sheet again). A grab handle at the top, then the header pattern ("Unterwegs" caption, "RE 7 nach Rheine" title, a chevron to close) and the body below. It opens on a tap on the bar, when a check-in completes (Welcher Zug? → Home with the sheet), and for the `/unterwegs` route (pushes, the geofence nudge: the route opens Home with the sheet, so deep links keep working). Pulling it down returns to whatever tab was active. Same paper as everywhere; designed to be glanced at, not read. Shows the journey (docs/17), not just the train.

- **Top:** line and headsign of the current leg, then "National Express · Leg 1 von 2 · Ziel Lüdenscheid".
- **Centre:** the delay in very large digits, "+14", or "pünktlich" in green. Under it: "Umstieg Hagen Hbf 09:06 statt 08:38" on a leg with a transfer ahead, "Ankunft Lüdenscheid …" on the last one.
- **Stop line:** stops as dots, passed ones filled, next one pulsing, the exit stop marked.
- **DANACH:** the next leg with its live status ("RB 52 nach Lüdenscheid · ab Hagen Hbf 08:55 · Gl. 6"), a red "knapp" chip when the ETA is later than its departure, and the line "Am Umstieg fragen wir einmal: bist du drin?"; then "Ziel Lüdenscheid · an 09:38".
- **Quiet footer:** "Stand 08:41 · Wir folgen dem Zug, nicht dir."
- **Buttons:** "Falscher Zug?" (edge state E2) and "Abbrechen" (the journey is abandoned, no incident). No sharing here; the reveal is at arrival. In demo mode the controls "Nächster Halt" and "Ankunft +68" sit at the bottom of the sheet body.

**In transfer** (leg done, journey not): "Umsteigen · Hagen Hbf", "RE 7 war +5. Weiter nach Lüdenscheid.", the confirmation card with the next leg (line, headsign, big departure time, platform, arrival at the destination) and the primary button "Ich bin drin". After a missed connection the eyebrow reads "Anschluss verpasst", the card is red-bordered "NÄCHSTE MÖGLICHKEIT" with the re-planned train, and the caption says the delay counts at the destination. Below: "Ich bin da" (ends the journey here, with the delay so far) and "Abbrechen". The same card is what a tap on the transfer push opens.

If the delay passes 60 minutes the footer changes once: "Ab hier entsteht ein Anspruch." Nothing celebrates yet. The claim is measured at the destination of the journey, so on a leg before a transfer the footer is a hint, not a promise.

If data stops: "Letzter Stand 08:41" and the digits dim. If the data never resumes, arrival asks for the actual time (E3).

**Arrival while the sheet is open:** the body switches to the reveal (screen 9's body, with "Jetzt einreichen", "Teilen", "Fertig") in place; the bar disappears. Arrival while the sheet is closed: the bar goes and the arrival card appears on Home as before.

---

## 9. Angekommen (arrival)

The reveal, and the only screen allowed to feel like a reward. Appears as a notification, as a full screen when the app is opened or "Ansehen" is tapped on Home's arrival card, and as the ride sheet's body when the journey arrives while the sheet is open (screen 8).

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

Replaces Konto in the nav (10 September 2026). One question: what is happening with my claims? Header "Anträge" with a caption like "3 Fälle gesammelt · 1 Antrag unterwegs", the gear top right. The tab icon carries a small red count of railway mails nobody has opened yet (`standing.unread_mails`); opening a card's thread marks them seen (`POST /v1/claims/{id}/seen`).

One card per Antrag, status in words, never dots (docs/18):

- **Wird gesammelt** (first, one per claims desk when there are several): the status line "1,50 von 4,00 €" or "Bereit · 6,00 €" in green, the line "Für Bahnhofsmission Köln · ändern" (the Zweck is visible before there is an Antrag; "ändern" opens the same picker as Einstellungen and changes the customer's setting, docs/20), the incidents, the oldest deadline line (red within 30 days), "Antrag vorbereiten" inside the card when ready. Empty: "Wird gesammelt · Noch nichts · Verspätungen ab 60 Minuten landen hier. Ab 4 € geht ein Antrag raus."
- **Antrag vom 15.08.** for every claim, newest first, the amount at the right. The status line: "Eingereicht · Antwort bis 12.09.", "Rückfrage · bitte antworten" (red), "Bestätigt · 4,50 € an Bahnhofsmission Köln" (green), "Abgelehnt" (red), "Nicht zugestellt · Adresse prüfen" (red). A caption with the desk, and, unless the status line already names the payee, the caption "Für Bahnhofsmission Köln". Then the incidents, the mail thread collapsed to the last message, the buttons "Antworten" / "Widerspruch", "Alle 3 Nachrichten" or "Ganze Mail lesen" (screen 12), "PDF ansehen", and at the very bottom the footnote "Antragsadresse: antrag-…@users.verspaetomat.de", the only place an address appears in the app.
- **Verfallen**: expired incidents in one card with the line "Frist um, bevor 4 € zusammenkamen. Die Minuten und Punkte bleiben."
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

The thread behind a claim card on Anträge (screen 10), reached with "Alle Nachrichten", "Antworten" or "Widerspruch"; the reply form lives here. The composer (docs/18 §5) offers three templates, a switch "Ticketkopie anhängen" (on for "Ticketkopie nachreichen"; sends the claim's existing ticket uploads, no re-upload) and "Foto hinzufügen" (through the upload route); the attachments show as chips above "Absenden" and go out as `attach_ticket` and `upload_ids`. The mail leaves from the claim's own address. Most replies arrive on their own. The railway answers to the customer's Verspätomat address; the app forwards the mail whole to the private inbox and, at the same moment, shows it here.

- **Accepted:** "Die Bahn hat geantwortet: 4,50 € an Bahnhofsmission überwiesen." The original mail is one tap away. Incidents turn "bestätigt". If the amount could not be read, the app shows the mail and asks the customer to enter it.
- **Question from the railway:** the mail is shown, with "Antworten" opening a reply composed by the customer, again through their own address. Templates for the usual questions (ticket copy, exact train) are offered; nothing is sent without the customer.
- **Rejected:** the mail is shown, the reason highlighted if recognisable, incidents turn "abgelehnt". The customer sees the mediation link (söp) once, without pressure, and a template for a reply if they want to push back themselves.
- **Postal reply instead:** four weeks after sending, if nothing has arrived: "Post von der Bahn bekommen?" with "Fotografiere die Antwort"; the app reads the amount if it can.
- Confirmation also arrives when the NGO's monthly report lists the transfer. That report is entered by us from the NGO's statement; affected customers get one notification ("Bahnhofsmission bestätigt 4,50 € aus deinem Antrag vom 20. Juni") and the incidents turn "bestätigt" the same way.

---

## 13. Wir (community)

- **Zusammen gewartet first** (docs/18): the community's minutes in board type, ticking, with "18.420 Fahrgäste" in the header caption. No community "eingereicht" or "bestätigt" totals: those only exist for the customer.
- No "Dein Teil" (docs/20): everything about the customer alone lives on Ich. Wir is the community, the Vereine and the boards.
- **Vereine:** one row per NGO with the euros confirmed for it and "Geschichte und Zweck" underneath (the row opens the NGO page). No "eingereicht" caption, no goals, no progress bars.
- **Ranglisten:** the customer's own place first, "Platz 5 · auf der RE 7 diese Woche · 38 Punkte bis Platz 4" (from `standing.board`, the city board when the line board is too small), then "Meine Linie" as the default, with "Meine Stadt" and "Deutschland" as tabs. Seven-day window, ten names, the customer's own row pinned at the bottom if not in the ten.

---

## 14. Zweck (NGO page)

- Photo, name, the one sentence, three short paragraphs about what the money does.
- **Transparency block:** account holder, IBAN, "Bestätigt über Verspätomat: 12.410 €", last report date.
- Two buttons: "Als Standard wählen" and "Trotzdem spenden" (opens the NGO's own donation page in the browser, with one line first: "Das läuft nicht über uns. Du landest direkt bei der Bahnhofsmission.").

---

## 15. Ich (profile)

- Name or nickname, level name, Geduldspunkte total, then the level bar with "Bahnsteigkante · 90 bis „Wartehäuschen“" (docs/20; the same line as under "Deine Woche" on Home), the pair "Bestätigt, durch dich" (tap → Anträge) and "Eingereicht, unterwegs", then "Diese Woche" and "Fahrten, letzte 14 Tage". The gear is the shared one in the tab header. Under "Mehr": "Dein Zweck · Bahnhofsmission Köln" (→ the NGO page) and "Alle Fahrten".
- Badges as a grid, earned ones in colour, others as outlines with their names visible (the museum is part of the fun).
- History ("Alle Fahrten"): every journey, grouped by day and filterable by line, as one row "RE 7 · Köln Hbf → Lüdenscheid · +68" with chips for "2× umsteigen", "Anschluss verpasst", "unvollständig", "abgebrochen"; a tap unfolds the legs with their times and delays (docs/17). Data: `GET /v1/journeys`.
- "Meine Statistik": average delay, most patient line, longest wait, minutes this year.
- "Alle Fahrten" is the only link; Einstellungen is reached by the gear top right, nowhere else (docs/18).

---

## 16. Einstellungen & Datenschutz

- Ticket type, default NGO.
- Nudges: on/off, quiet hours. Stumme Bahnhöfe: the muted list with a remove action, and "Bahnhof hinzufügen" via the station search; muting also happens on the nudge itself ("Diesen Bahnhof nie"). The list lives on the account, not the phone.
- Standort: current permission with a plain explanation and a link to change it.
- Persönliche Daten für Anträge: view, edit, delete.
- No address block (docs/18): addresses appear only as the footnote on each claim card on Anträge. "Korrespondenz nach Abschluss behalten" (off by default) and the full export of all sent and received mails stay.
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
