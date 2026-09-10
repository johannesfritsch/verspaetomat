# 20 — Riding on Home, no second check-in, the Zweck up front, Ich owns the level

Decided 10 September 2026 (Johannes, after build 9). Five changes.

## 1. The Einchecken square is disabled while a journey is under way

While `RideMonitor.active` (riding or transfer) the square in the bottom nav is drawn disabled: `VColors.rule` fill instead of ink, icon and label in `VColors.ink2`, no shadow. A tap does not start a check-in; it opens the ride sheet instead (the square points at the journey you are on). The shell passes `checkinEnabled` to `VBottomNav`; `startCheckin` is never reached while active.

## 2. Home shows the ride as a card

Block 1 on Home while riding or in transfer is a card (hairline border, paper-elevated), not nothing. Tapping the card opens the sheet. Contents:

- Riding: eyebrow `UNTERWEGS`, then the line badge and `RE 7 nach Rheine` (title), the live delay as a VDelay (or `pünktlich`), and two key lines: `Nächster Halt · Solingen Hbf 10:06` and `Ziel · Rheine an 12:08` (planned arrival plus the live delay; for a journey the destination and the journey's planned arrival). Beneath, a caption `Tippen für Details`.
- Transfer: eyebrow `UMSTEIGEN`, title `Hagen Hbf`, the next leg as `RE 5 nach Kleve · 10:41 · Gleis 3` (live time when known), a primary ink button `Ich bin drin` (same action as the bar) and, when the connection was missed, the caption `Anschluss verpasst · nächste Möglichkeit`.

The bar above the nav stays on every tab, Home included (the card is the detail, the bar is the constant). The arrival card for `arrived` is unchanged.

## 3. Home header: no clock

The small `VStationClock` in Home's header goes; the gear stays top right. The Stellwerk caption on the left stays.

## 4. The Zweck is visible before there is an Antrag

The customer picks the Verein in setup, so every claim already has one; it was just invisible until "Bestätigt … an X". Now:

- The collecting card on Anträge gets a line under the status: `Für Bahnhofsmission Köln` with a trailing `ändern` link (caption, ink2) that opens the same picker Einstellungen uses (`_pickNgo`, move it into `claims_widgets.dart` or `community_widgets.dart` and share it). Changing it updates the customer's setting (`MePatch(ngoId:)`), as today.
- Every claim card (sent, question, rejected, expired) shows `Für <Verein>` as a caption line in its body; the accepted card keeps `Bestätigt · 4,50 € an <Verein>` in the status line and does not repeat it.
- The Antrag flow keeps its Zweck step, pre-selected as today (it is the moment to confirm the payee against the IBAN on the form).

## 5. Wir loses "Dein Teil"; Ich owns the level

- Wir: remove the whole `Dein Teil` section (the two figures, the level bar, `Eingereicht, unterwegs`, the `Zweck` row). Wir is: the big community number, the Vereine, the Ranglisten with the customer's own rank line on top (`Platz 5 auf der RE 7 …` stays here, it is relative to the others).
- Ich: under the Geduldspunkte figure and the red rule, the level bar with `Bahnsteigkante · 90 bis „Wartehäuschen“` (from `standing.level`, the same line Home uses), then the pair `Bestätigt, durch dich` (euros, tap → Anträge) and `Eingereicht, unterwegs` (euros), then the existing pair `Diese Woche` / `Fahrten, letzte 14 Tage`. Under `Mehr`: a row `Dein Zweck · <Verein>` (chevron, tap → `/zweck?id=`). Ich loads `standing` and the ledger summary next to `me`, `badges`, `rides`.

## Tests

- Tour: `home-riding-card` (Home while riding, with the bar), `home-transfer-card`, `nav-disabled` (any tab while riding: the grey square), `antraege-collecting` now shows the Zweck line, `wir` and `ich` re-shot.
- Workflow E2E: after check-in the test still closes the auto-opened sheet and reopens it from the bar (key `ride-bar`); the card on Home now also contains `nach …`, so the test finds the bar by key, not by text. The connection scenario may confirm through the bar or the card, whichever it finds first.
