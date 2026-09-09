# 13 — Where the data comes from, in customer terms

Every number in the app should be tappable and answer "Woher weißt du das?". This is the answer for each one.

| What you see | Where it comes from | How fresh | If it is missing |
|---|---|---|---|
| "Du bist am Hauptbahnhof" (station nudge) | Your phone noticed you have been near a station for a few minutes. Nothing leaves the phone until you check in. | Within about 3 to 5 minutes | Nothing happens. Open the app and pick the station yourself. |
| Departures at a station, platforms, delays so far | The same public timetable and live-delay information that feeds the boards on the platform, provided through open transit data services. | Refreshed every few seconds while the sheet is open | "Keine Live-Daten für diese Station" and a manual entry field for the train. |
| Which company runs your train | The timetable itself names the operator. | With the timetable | The claim step asks you to pick the operator from a short list. |
| Your train's position, next stop, current delay during the ride | The live-delay feed for that one train, followed by our server while you ride. Your phone's location is not used. | Every 30 to 60 seconds, shown with a "Stand 08:41" stamp | The ride screen shows the last known state and its age. At arrival you can enter the actual time yourself; such rides earn points but are marked "selbst eingetragen" on any claim. |
| Delay at your exit stop (the number that counts) | Planned arrival from the timetable, actual arrival from the live feed, at the stop you chose. | Final a few minutes after arrival | Same as above. |
| Delay cause ("Stellwerksstörung") | The operator's own service message, when they publish one. | With the delay | Badge not awarded; nothing else changes. |
| Geduldspunkte | Counted by the app from the final delay. | Instant at arrival | — |
| "Anspruch: 1,50 €" | The legal rules for your ticket type, applied to the final delay. The rules are written in the app and linked to the official DB page. | Instant at arrival | — |
| Ledger status "gesammelt / bereit / eingereicht / bestätigt / abgelehnt / verfallen" | gesammelt and bereit: computed by the app. eingereicht: your claim left your Verspätomat address. bestätigt or abgelehnt: the railway's e-mail reply to that address, read for amount and outcome, or your photo of a postal reply, or the NGO's report. verfallen: the deadline passed. | Replies: the moment they arrive | A reply we could not read is shown to you to enter the outcome yourself. |
| "Älteste Verspätung verfällt in 3 Wochen" | Three months after the ride date (the legal deadline). | Daily | — |
| Your name, address, ticket number on the claim | Typed by you the first time you send a claim. Stored on your phone. | — | Asked for at the claim step. |
| Ticket screenshot on the claim | Attached by you from your ticket app or photos. Kept encrypted only while the claim is open, in case the railway asks. | — | The claim cannot be sent without it. |
| Your Verspätomat address (fahrgast-4711@verspaetomat.de) | Created by us at your first claim. Your name is the sender name. Every mail out gets copied to your private inbox; every mail in is forwarded to it whole. | — | — |
| The railway's reply shown in the app | The actual e-mail the railway sent to your Verspätomat address. We read status, amount and reference from it; we never answer it ourselves. | The moment it arrives | Postal replies: photograph them. |
| The NGO's name and account on the claim | Provided by the NGO in writing to us. Shown in full on the NGO page for transparency. | Updated when the NGO tells us | — |
| The claim form itself | The official EU passenger-rights form (or DB's own form for the paper route), filled in by the app. | Form version shown on the preview | — |
| Where the claim is sent | Our operator directory: the joint Servicecenter for about 40 railways, a specific address for the others. | Reviewed monthly | The app shows the operator's public passenger-rights page and lets you enter the address. |
| "Bestätigt: 4,50 € an Bahnhofsmission" | The railway's e-mail reply to your Verspätomat address, read automatically; or your photo of a postal reply; or the NGO's monthly report of transfers received from railways. | E-mail replies: the moment they arrive. Photos: when you upload. NGO reports: monthly. | Stays "eingereicht". We never guess. |
| Community totals: minutes | Sum of all customers' final delays. | Live | — |
| Community totals: euros "eingereicht" and "bestätigt" | Sum of ledger states across all customers. | Live for both; NGO-report confirmations land monthly | — |
| Campaign progress bar | Confirmed euros for that NGO since the campaign start. | Monthly | — |
| Employer match "zugesagt" | The sponsor's promise per submitted claim, entered by us. | — | Shown as promised until the NGO confirms receipt. |
| Boards | Verified rides only (a location fix at the station at check-in). | Live, seven-day window | Unverified rides earn points but do not rank. |
| Badges | Awarded by the app from ride data and, for causes, from the operator's service message. | At arrival | — |

## Three promises printed in the app

1. **Dein Standort bleibt am Bahnhof.** We look at where you are only to notice a station. During the ride we follow the train, not you.
2. **Kein Geld läuft durch uns.** The railway pays the NGO. We fill in forms and carry the mail; you sign and send, and you get a copy of everything.
3. **Kein Euro ist gespendet, bevor er es ist.** Totals show submitted and confirmed separately, and confirmed only means a railway reply or an NGO statement exists.
