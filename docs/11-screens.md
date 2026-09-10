# 11 — Every screen

Navigation: four tabs at the bottom, named after places, not features. **Bahnsteig** (home), **Konto** (the ledger of claims), **Wir** (community), **Ich** (profile). The ledger is never called "Spendenkonto": most of what it holds is not a donation yet, and some of it never will be. The ride view and the claim flow are full-screen moments that sit on top of the tabs.

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

The screen the customer sees a hundred times. Three stacked blocks, no cards within cards.

**Top: state of now.**
- Idle: "Kein Zug. Gut so." with the nearest stations as tappable chips ("Hbf · 400 m", "Deutz · 1,2 km") and a search field. Tapping a chip opens the check-in sheet (screen 6).
- Riding: the ride card, tap to open screen 8.
- Just arrived: the arrival summary until dismissed.

**Middle: your numbers.** Two figures side by side in board type: Geduldspunkte this week, and the ledger's state in one line: "3 Verspätungen gesammelt · 4,50 € bereit". Tapping goes to Konto.

**Bottom: the community line.** One sentence, ticking: "Wir haben zusammen 1.208.311 Minuten gewartet und 48.320 € bestätigt." Tap for Wir.


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

## 7. Wo steigst du aus? (exit stop)

The train's stops as a vertical line, the current station at the top, each stop with planned arrival. The customer's usual stop on this line is pre-highlighted after the second ride. One tap selects, a confirm bar appears: "RE 7 nach Münster · Ausstieg Rheine 08:52 · Einchecken".

Confirm: chime, haptic, the sheet closes, the ride card appears on Bahnsteig. Total taps from nudge to riding: three.

---

## 8. Unterwegs (ride)

Full screen, same paper as everywhere. Designed to be glanced at, not read.

- **Top:** line and destination, the operator in small type ("DB Regio NRW").
- **Centre:** the delay in very large digits, "+14", or "pünktlich" in green. Under it: "Ankunft Rheine 09:06 statt 08:52".
- **Stop line:** stops as dots, passed ones filled, next one pulsing, the exit stop marked.
- **Quiet footer:** "Stand 08:41 · Wir folgen dem Zug, nicht dir."
- **One button:** "Falscher Zug?" opens edge state E2. No sharing here; the reveal is at arrival.

If the delay passes 60 minutes the footer changes once: "Ab hier entsteht ein Anspruch." Nothing celebrates yet.

If data stops: "Letzter Stand 08:41" and the digits dim. If the data never resumes, arrival asks for the actual time (E3).

---

## 9. Angekommen (arrival)

The reveal, and the only screen allowed to feel like a reward. Appears as a notification and as a full screen when the app is opened.

1. The final delay ticks in: "+68".
2. One line: "68 Minuten. 68 Geduldspunkte."
3. If a badge was earned, it appears here, once.
4. The money line, honest and specific:
   - D-Ticket, 60+: "Anspruch entstanden: 1,50 € für die Bahnhofsmission. Gesammelt: 3 von 3 · Bündel ist bereit." or "… 1 von 3."
   - Ordinary ticket, 60+: "Anspruch entstanden: ca. 15,00 € (25 % von 60,00 €). Jetzt einreichen."
   - Under 60 minutes: "Kein Anspruch, aber 14 Minuten Geduld. Trotzdem spenden →" (link out to the NGO's page, see screen 14).
5. Two buttons: "Teilen" (a card image with the delay, the line, and the NGO) and "Fertig".

If the claim is ready, "Jetzt einreichen" opens the claim flow (screen 11).

---

## 10. Konto (the ledger)

The customer's delays that matter, as a list.

- **Header:** "Bereit: 4,50 €" or "Gesammelt: 3,00 € · noch 1,50 € bis zur Auszahlung" and, below, the total ever confirmed for this customer.
- **Deadline line** when relevant, in red when under 30 days: "Älteste Verspätung verfällt in 3 Wochen."
- **Grouped by claims desk** with a heading only when there is more than one: "Servicecenter Fahrgastrechte (DB, ODEG, NEB …)", "NordWestBahn". Each group carries its own total and its own distance to 4 €, and one line explains why: "Ansprüche werden pro Bahnunternehmen gebündelt. Jedes Bündel muss 4 € erreichen."
- **Each incident:** date, line, route, "+68", the amount, and a status chip: gesammelt · bereit · eingereicht · bestätigt · abgelehnt · verfallen. An "eingereicht" incident shows when it was sent and "Antwort in etwa 4 Wochen", so silence has a shape.
- **Primary button:** "Antrag vorbereiten" when a bundle is ready.
- Tapping an incident shows the evidence sheet: planned and actual times, source, timestamp, and "Als Nachweis exportieren".

Ordinary-ticket incidents appear here too, each with its own "Einreichen". They take the same five steps with one incident instead of a bundle: step 1 shows the fare and the booking number instead of the D-Ticket number, step 2 asks for the ticket itself (the booking PDF or a photo of the paper ticket), and the amount is 25 % or 50 % of the fare.

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

Most replies arrive on their own. The railway answers to the customer's Verspätomat address; the app forwards the mail whole to the private inbox and, at the same moment, shows it here.

- **Accepted:** "Die Bahn hat geantwortet: 4,50 € an Bahnhofsmission überwiesen." The original mail is one tap away. Incidents turn "bestätigt". If the amount could not be read, the app shows the mail and asks the customer to enter it.
- **Question from the railway:** the mail is shown, with "Antworten" opening a reply composed by the customer, again through their own address. Templates for the usual questions (ticket copy, exact train) are offered; nothing is sent without the customer.
- **Rejected:** the mail is shown, the reason highlighted if recognisable, incidents turn "abgelehnt". The customer sees the mediation link (söp) once, without pressure, and a template for a reply if they want to push back themselves.
- **Postal reply instead:** four weeks after sending, if nothing has arrived: "Post von der Bahn bekommen?" with "Fotografiere die Antwort"; the app reads the amount if it can.
- Confirmation also arrives when the NGO's monthly report lists the transfer. That report is entered by us from the NGO's statement; affected customers get one notification ("Bahnhofsmission bestätigt 4,50 € aus deinem Antrag vom 20. Juni") and the incidents turn "bestätigt" the same way.

---

## 13. Wir (community)

- **Top figure, board type:** minutes waited together, ticking.
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

- Name or nickname, level name, Geduldspunkte total, points this week.
- Badges as a grid, earned ones in colour, others as outlines with their names visible (the museum is part of the fun).
- History: every ride, filterable by line, with delays and points.
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
