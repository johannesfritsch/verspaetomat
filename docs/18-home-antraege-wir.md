# 18 — Home says one thing, Anträge shows status, addresses belong to claims

Decided 10 September 2026 (Johannes, after build 7). Seven changes, one of them structural.

## 1. Home below the check-in card: three things, nothing else

The block list from docs/16 was right in content and wrong in density. Home now has, top to bottom:

1. **Einchecken** card (see 2).
2. **Deine Woche**: `+96 Geduldspunkte · letzte Woche 41` (quiet week: "Diese Woche noch keine Fahrt"), the level bar with `Gleis 7 · 128 bis „Bahnhofsmission“`.
3. **Deine Anträge**: the four-step cycle strip (Sammeln → Antrag bereit → Eingereicht → Bestätigt), the one status line beneath the active step, the primary button when a bundle is ready. Tap → Anträge.
4. **Wir**: one line, `1.208.316 Minuten haben wir gewartet · 1.372 davon deine`. Tap → Wir.

Gone from Home: the standing/rank line (it moves to Wir next to the boards), the "next thing" card (mail → the Anträge badge, deadline → Anträge, badge → Ich), the community euro line. The only conditional extra: a small caption link `Gestern vergessen einzuchecken?` under the card when the nachtrag rule applies (rides on ≥ 3 of the last 14 days, none yesterday).

## 2. The Einchecken card: destinations from history only

- At a station: the station name, then the customer's destinations **from previous journeys** as one-tap rows (most frequent first, the home station labelled "Nach Hause" when away from it, at most four). No departures list, no "Alle Abfahrten".
- Beneath the rows, always: a search field `Wohin?` that suggests stations as you type (the existing station search). With no history at all, the card is the station name plus this field.
- Tapping a destination or a suggestion → Welcher Zug? as today.
- Away from a station: the box from today (station choices + search) stays.

`GET /v1/me/destinations` drops the "predicted from time of day" heuristics down to: frequency over the customer's journeys, home station on top when away. No seeded or mock destinations for real accounts.

## 3. Bottom nav

The Einchecken square gets a 14 px radius (was 4). Everything else unchanged.

## 4. Mail belongs to a claim: `antrag-<id>@…`, and a badge instead of a card

- Every claim gets its own address at send time: `antrag-<first 8 hex of the claim id>@users.verspaetomat.de` (`RELAY_DOMAIN`), stored in `claims.reply_address`. The mail goes out From that address; the BCC to the customer's private mail stays.
- Inbound routing: look the address up in `claims.reply_address` first (customer and claim in one step); fall back to `customers.relay_address` for mail to the old per-customer address, matched to a claim as today. The Einstellungen block "Meine Verspätomat-Adresse" is removed; addresses appear only on Anträge, as a footnote on each claim card (`Antragsadresse: antrag-…@…`). No customer-level address is shown anywhere.
- **Unread**: `mails.seen_at` (null = unread). `POST /v1/claims/{id}/seen` marks every inbound mail of that claim seen (the app calls it when the claim card's thread is opened). `GET /v1/me/standing` gains `unread_mails` (count of inbound mails with `seen_at` null, all claims). The Anträge tab shows that number as a small red badge on its icon; Home shows nothing about mail.
- Pushes for railway mail keep opening Anträge on the claim.

## 5. Anträge: a card per Antrag, status as words

One card per claim, newest first, plus one card for the bundle being collected at the top:

| Card | Title | Status line (words, never dots) | Body |
|---|---|---|---|
| collecting | `Wird gesammelt` | `1,50 von 4,00 €` or `Bereit · 6,00 €` | incidents of the bundle, the oldest deadline, "Antrag vorbereiten" when ready |
| sent | `Antrag vom 15.08.` | `Eingereicht · Antwort bis 12.09.` | amount, desk, PDF action, the thread collapsed to the last message with "alle anzeigen" |
| question | same | `Rückfrage · bitte antworten` (red) | same, reply action prominent |
| accepted | same | `Bestätigt · 4,50 € an Bahnhofsmission Köln` (green) | same |
| rejected | same | `Abgelehnt` (red) | same, the railway's reason |
| expired | same | `Verfallen` | same |

Each card carries its `antrag-…` address as a footnote caption at the bottom; that is the only place an address appears in the app. The VDots "3 von 3" indicator disappears everywhere on Anträge and Home.

## 6. Ich

The "Einstellungen" row at the end goes; the gear top right is the only way in. Ich keeps profile, level, badges, statistics, "Alle Fahrten".

## 7. Wir

Order: the community's big numbers first (`1.208.316 Minuten` with `18.420 Fahrgäste`; no community "eingereicht"/"bestätigt"), then **Dein Teil** (confirmed euros through you, minutes waited, the level bar, `eingereicht, unterwegs`), then the Vereine (name, story link, confirmed total per Verein; no "eingereicht:" caption), then the boards with the customer's own rank line on top (`Platz 5 auf der RE 7 diese Woche · 38 Punkte bis Platz 4`, from `standing.board`).

## Data changes summary

- Migration 0021: `claims.reply_address text unique`, `mails.seen_at timestamptz`.
- `POST /v1/claims/{id}/seen`; `standing.unread_mails`; `destinations` simplified; inbound routing by claim address.
- App: Home, Bahnsteig card, nav radius, Anträge cards (address footnote), Ich, Wir, Einstellungen address block removed, tab badge.
