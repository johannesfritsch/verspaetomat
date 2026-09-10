# 40 — Store listing: privacy labels, review notes, Data safety

Everything the two store consoles ask that can be answered from the code as it is. Source of truth for the answers: the in-app Datenschutzerklärung (`app/lib/content/legal.dart`), docs/05-legal.md and docs/14-location-concept.md. The iOS privacy manifest (`app/ios/Runner/PrivacyInfo.xcprivacy`) says the same thing in Apple's format. If one of the three changes, change all three.

What still needs the accounts (not in this file): Apple Developer team, bundle id registration, TestFlight, Play Console account, signing keys, the store screenshots.

## Facts the answers rest on

- No user account. An anonymous device id plus a bearer token; recovery by a 12-word code.
- Location: one fix when the Bahnsteig opens (not stored) and one at check-in (stored on that ride as the verification fix). Never in the background, never during the ride.
- Personal data (name, address, e-mail, ticket number) only at the first claim, printed on the EU form.
- Ticket images and the signature per claim; deleted when the claim closes unless "Korrespondenz behalten" is on.
- Relay mailbox per customer; inbound mail forwarded whole to the private inbox; a classifier reads outcome, amount and reference.
- No analytics SDK, no ads, no tracking, no third-party sharing beyond the railway (the customer sends the form) and the mail provider (delivery).
- Push tokens stored once the customer allows notifications (delivery not live yet).

## App Store: App Privacy ("nutrition label")

Answer "Yes, we collect data from this app". Then, per data type:

| Data type | Collected | Linked to user | Used for tracking | Purpose |
|---|---|---|---|---|
| Precise Location | yes | yes (to the device account) | no | App Functionality |
| Coarse Location | no | | | |
| Name | yes | yes | no | App Functionality |
| Physical Address | yes | yes | no | App Functionality |
| Email Address | yes | yes | no | App Functionality |
| Phone Number | no | | | |
| User ID (device account id) | yes | yes | no | App Functionality |
| Device ID | no (we generate our own random id; no IDFV/IDFA use) | | | |
| Photos or Videos (ticket images) | yes | yes | no | App Functionality |
| Other User Content (signature, ticket number, relay mails, rides, points) | yes | yes | no | App Functionality |
| Emails or Text Messages | yes (the relay mailbox: the customer's claim mails and the railway's replies) | yes | no | App Functionality |
| Purchase History, Financial Info | no (the app never sees money; the NGO's IBAN is the NGO's, not the user's) | | | |
| Contacts, Health, Browsing, Search History, Usage Data, Diagnostics, Crash Data | no | | | |

"Linked to user": yes throughout, because everything hangs on the device account and the customer can export it. "Tracking": no, nothing leaves for advertising or data brokers.

Optional disclosure text (App Store Connect allows a privacy policy URL only): host the Datenschutz text at `https://verspaetomat.de/datenschutz` with the same wording as in the app.

## App Store: App Review notes

Paste into "Notes" in App Review Information:

> Verspätomat is a form-filling and forwarding helper for EU rail passenger rights (Regulation (EU) 2021/782). The app records train delays the user checks in to, computes the statutory compensation, fills in the EU standard claim form with the user's own details and sends it from the user's personal relay address (fahrgast-…@verspaetomat.de) to the railway's claims desk. The railway pays the compensation directly to a charity the user chose. The app never collects, holds or forwards money (no IAP, no donations inside the app; "Trotzdem spenden" opens the charity's own website in Safari). See guideline 3.2.2(iv): nothing is collected in-app.
>
> No login: accounts are anonymous device accounts created on first launch. No demo credentials are needed. A recovery code (Einstellungen → Konto) restores an account on another device.
>
> Location: requested "When In Use" only. It is read once when the home screen opens (to list nearby stations) and once at check-in (to mark the ride as verified). No background location, no location during the ride: the server follows the train in public timetable data, not the phone. The app is fully usable with location denied (stations can be searched by name).
>
> Testing without live delays: real German trains at the moment of review will mostly be on time, so the compensation flow (delay ≥ 60 min) will not trigger by itself. To see it: Einstellungen → Backend → "Demo (eingebaut)" switches the app to built-in sample data, where the whole flow (check-in, arrival +68, claim, signature, send, reply) can be walked through offline. Our server-side test controls ("Stellwerk") are not reachable from the app and not available to reviewers.
>
> Sending a claim in review: in the built-in demo nothing is sent anywhere. Against the production backend a sent claim goes to the railway; please use the demo mode for the send step.
>
> Contact for review questions: j@jfritsch.de.

Age rating: 4+. Category: Travel (secondary: Utilities). Export compliance: uses standard HTTPS only (answer "No" to proprietary encryption; TLS is exempt).

## Google Play: Data safety form

Section by section, as the console asks.

**Data collection and security**

- Does your app collect or share any of the required user data types? Yes.
- Is all of the user data collected by your app encrypted in transit? Yes (HTTPS/TLS).
- Do you provide a way for users to request that their data is deleted? Yes: in app, Einstellungen → Deine Daten → "Alles löschen" (immediate, complete), plus e-mail to j@jfritsch.de. The console also asks for a deletion URL: `https://verspaetomat.de/loeschen` describing the in-app control.

**Data types**

| Category | Type | Collected | Shared | Optional | Purpose |
|---|---|---|---|---|---|
| Location | Precise location | yes | no | yes (user can deny; app works) | App functionality |
| Location | Approximate location | no | | | |
| Personal info | Name | yes | shared with the railway when the user sends a claim | yes (only at first claim) | App functionality |
| Personal info | Email address | yes | shared with the railway (BCC copy goes to the user's own address) | yes | App functionality |
| Personal info | Address | yes | shared with the railway when the user sends a claim | yes | App functionality |
| Personal info | User IDs (device account id) | yes | no | no | App functionality |
| Personal info | Phone number, race, political opinions, sexual orientation, other | no | | | |
| Financial info | any | no (no payment ever passes through the app) | | | |
| Photos and videos | Photos (ticket images) | yes | shared with the railway as claim attachment | yes | App functionality |
| Messages | Emails (the relay mailbox: claims out, railway replies in) | yes | with the railway; replies forwarded to the user's own inbox | yes | App functionality |
| Files and docs | Files (the generated claim PDF, signature image) | yes | with the railway | yes | App functionality |
| App activity | Other user-generated content (rides, points, nickname) | yes | no (boards show the nickname to other users only if "Mich in Ranglisten zeigen" is on) | yes | App functionality |
| App activity | App interactions, in-app search history, installed apps | no | | | |
| App info and performance | Crash logs, diagnostics | no | | | |
| Device or other IDs | Device or other IDs | no (own random id, listed under User IDs) | | | |

"Shared" here means: transferred to the railway because the user pressed send. The console's definition of sharing excludes "transfers at the user's specific initiative", so strictly these may be answered "not shared"; answering "shared with the railway, at the user's initiative" is the conservative choice and matches the in-app text. Pick one and keep it consistent with Apple's label (where the same transfer is not "tracking").

**Permissions declaration** (Play Console → App content)

- `ACCESS_FINE_LOCATION`: foreground only, core feature "find the station you are at and verify a check-in". No background location: do not fill in the background location declaration; do not request `ACCESS_BACKGROUND_LOCATION` (the manifest does not).
- `INTERNET`: standard.
- No SMS/Call Log, no Accessibility, no VPN, no device admin.

Target audience: 18+ (claims need a legal declaration and an address). Ads: none. Content rating questionnaire: Utility/Productivity, no user-generated content visible to others except the optional nickname on boards.

## Screens the reviewers will see

Onboarding (Willkommen, Berechtigungen, Setup), Bahnsteig, Einchecken, Unterwegs, Angekommen, Konto, Antrag (five steps), Antwort, Wir, Ich, Einstellungen with Rechtliches (Impressum, Datenschutz, "Wie wir Anträge weiterleiten"). Screenshot set: `app/tools/tour.sh` produces one per screen.
