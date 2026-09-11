# 27 — Teilen: eine Karte, vier Gesichter

Written 11 September 2026 at Johannes' request, and **built the same day** — the four faces, the
Wir card, the confetti and the NGO logos. The Jahreskarte (§1a) waits for a year of real data.
What shipped is marked at the end.

## 0. What is actually shareable

Nobody shares an achievement. People share a true story about themselves that they are glad to
be seen in. The badge is not the story.

The story Verspätomat owns is unusually good, and it is one sentence: **I waited, and the waiting
turned into money for somebody else.** In Germany the first half is the most reliable piece of
small talk there is; the second half is the part nobody has heard before. A post that carries
both is a complaint with a punchline, and the person posting comes out well — not as someone
collecting points, but as someone who did something mildly clever with a wasted hour.

So every card leads with **a number that really happened** and says underneath **what it became**.
That ordering is the whole design. A badge card that leads with the badge is a card only our own
customers can read; a badge card that leads with "zehn Fahrten über eine Stunde zu spät" is a card
anyone can read.

## 1. The artefact: die Fahrkarte

One card, in the app's own language (`app/STYLE.md`): paper white, ink, the one red, Archivo with
tabular figures, no gradients, no shadows, **no emoji**.

It is shaped like a **ticket** — the small card kind, with a perforated edge and a hole where the
conductor's punch went through. That is the right object for three reasons: it is what the whole
app is about, its field-and-label layout is a natural way to lay out facts, and its silhouette is
recognisable in a feed at thumbnail size, which very little else is. It also closes a loop with
§4 — the confetti is what the punch leaves behind, and the hole in the card is where it came from.

A punched ticket means *used*. This one means the delay has been cashed in.

```
   ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌        ← perforation
  │ VERSPÄTOMAT          FAHRGASTRECHTE │
  │                                      │
  │ FAHRGAST    Johannes                 │
  │ STRECKE     Köln Hbf → Rheine        │
  │ AM          Fr, 11. September 2026   │
  ├──────────────────────────────────────┤   ← the one red rule
  │  VERSPÄTUNG                          │
  │                                      │
  │    204                         ◉     │   ← the hero, and the punch hole
  │    MINUTEN                           │
  │                                      │
  ├──────────────────────────────────────┤
  │ ZAHLT AN    Bahnhofsmission Köln  ◆  │   ← the NGO's own logo
  │ BETRAG      12,00 €                  │
  │                                      │
  │ „Ich habe die Bahn dazu gebracht,    │   ← the chosen line
  │  an die Bahnhofsmission Köln zu      │
  │  zahlen. Weil sie mich 204 Minuten   │
  │  warten ließ."                       │
   ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
```

**The number is the design**, and on this card it is bigger than anything else by a long way —
`204` should be the only thing a person can read when the card is the size of a thumbnail. The
labels are small caps in ink2; the fare-card fields do the rest of the work quietly.

Two sizes: **1080 × 1350** for feeds and **1080 × 1920** for stories. Nothing else; everything
else crops acceptably from these.

### The four faces

Same ticket, different middle. Only the big block and the lower fields change.

| Face | The big number | The fields below |
|---|---|---|
| **Antrag** | the minutes of the whole bundle | ZAHLT AN · BETRAG · the chosen line |
| **Angekommen** | the delay of that ride | STRECKE · GEDULDSPUNKTE |
| **Pünktlich** | `0`, in ink, never red | „Heute war die Bahn pünktlich." — rare enough to be the joke, and the joke travels |
| **Abzeichen** | the badge artwork in place of the number | **the fact that earned it**, in words an outsider can read |

### The line on the ticket

The passenger picks one of four in the preview, and the same line pre-fills the post. One choice,
two places. They differ by register rather than by content, because the right voice for this is
not the same for everybody:

1. „Ich habe die Bahn dazu gebracht, an die Bahnhofsmission Köln zu zahlen. Weil sie mich
   204 Minuten warten ließ." — the dry one
2. „204 Minuten zu spät. Das Geld dafür bekommt die Bahnhofsmission Köln." — the plain one
3. „204 Minuten meines Lebens. Immerhin zahlt die Bahn dafür an die Bahnhofsmission Köln."
4. „Aus 204 Minuten Warten werden 12,00 € für die Bahnhofsmission Köln." — the warm one

Each face has its own set; the punctual one is mostly jokes, and deserves to be.

Two things about the set. The first line is the one Johannes wants and it is the best of them —
„dazu gebracht" is exactly the dry humour this app can carry, and it is also *true*: the railway
is paying because a passenger made a claim. It sidesteps the „spenden" problem in §8.4 entirely,
because nobody is calling it a donation any more. And having four means the plain option exists
for anyone who would rather not be funny about it, which is most people some of the time.

A fifth face, the **Jahreskarte**, is the year on one ticket. It is the biggest of the five and
the only one that needs data the app does not already show; §1a says what it is and why it waits.

## 1a. Die Jahreskarte — what "Bilanz" means

The fifth face is the year (or the month) on one ticket, and since a ticket that covers a whole
year already has a name, that is what it is: a **Jahreskarte**.

It is the Spotify-Wrapped shape. Once a year, an app that has been quietly counting hands you the
total and you post it, because it is about you, it is genuinely surprising, and it only arrives
once — so it never becomes nagging. For this app the numbers are unusually good, because nobody
knows their own answer:

```
   ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
  │ VERSPÄTOMAT              JAHRESKARTE │
  │                                      │
  │ FAHRGAST    Johannes                 │
  │ GÜLTIG      2026                     │
  ├──────────────────────────────────────┤
  │  GEWARTET                            │
  │                                      │
  │    2.412                       ◉     │
  │    MINUTEN                           │
  │                                      │
  ├──────────────────────────────────────┤
  │ FAHRTEN     84                       │
  │ ANTRÄGE     7                        │
  │ GEZAHLT     96,00 €                  │
  │ AN          Bahnhofsmission Köln  ◆  │
  │                                      │
  │ „2.412 Minuten. 40 Stunden. Fast     │
  │  zwei Tage auf Bahnsteigen."         │
   ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
```

The line underneath is where the year earns its share: **the minutes converted into something a
person can feel.** 2.412 Minuten means nothing; „fast zwei Tage auf Bahnsteigen" is a fact about
somebody's life. The app can do that conversion without editorialising, and it should — it is the
one number nobody has ever been shown about themselves.

Why it is listed separately from the other four: it needs figures the app does not currently put
on any screen (a year's rides, a year's minutes, a year's confirmed euros, per calendar year), and
it needs a moment to arrive in — either a quiet card on Ich in January, or a push, which is a
decision of its own given docs/12's rules about not nagging. The other four faces need none of
that; they share something that is already on screen in front of the passenger.

My suggestion: build the four first, and let the Jahreskarte follow once there is a year of real
data to put on it. There is not one yet.

## 2. Where the button lives

Five places, matching the moments that already carry feeling:

1. **Angekommen**, in the arrival reveal — the stub is already there
   (`angekommen_screen.dart`).
2. **Antrag**, the moment it is sent. This is the gratification moment and it is not made to
   wait: the passenger has just done the thing, and the card says so in the same second. The
   confirmation weeks later is a quieter, separate moment — the ticket there reads `BEZAHLT`
   instead of `ZAHLT AN`, and the amount stops being a claim.
3. **Abzeichen**, in the badge sheet on Ich — the stub is already there (`ich_screen.dart`), and
   docs/12 always said badges "can be shared as a card".
4. **Bilanz**, when a month or a year closes.
5. **Wir**, for the collective number — „Wir haben zusammen 1.208.638 Minuten gewartet." Nobody's
   own ego is in that one, which is exactly why it gets shared.

**Always available, only sometimes offered.** The button is present on every arrival, including a
four-minute delay nobody will post. The app *highlights* it only where the card is actually worth
looking at: 60 minutes and up, a punctual ride, a new badge, a confirmed claim. A button that is
pushed at every trivial moment is a button people stop seeing.

## 3. Preview, then share

Tapping **Teilen** opens a sheet with the finished card at full size and one primary button. Two
reasons, both practical: nobody posts an image they have not seen, and the preview is where the
few switches live (below).

Then the native share sheet with the image and a short pre-written text the person can edit:

> Ich habe die Bahn dazu gebracht, an die Bahnhofsmission Köln zu zahlen.
> Weil sie mich 204 Minuten warten ließ. verspaetomat.de

Dry, short, no exclamation mark, no emoji, no hashtags. The tone rule from docs/10 holds here more
than anywhere: **never angry, never „schon wieder", and never pleased about the delay itself.**
The app is not delighted that the train was late. It is only matter-of-fact about what followed.

## 4. Lochzangen-Konfetti

The moment the Antrag goes out earns a celebration, and the app has never had one. It gets one
here — but party confetti in twelve colours would be the first thing in this app to look like
every other app, and `STYLE.md` has no gradients, no shadows and no animation beyond the arrival
count-up.

So the confetti is made of the right material: **the little discs a conductor's ticket punch
leaves behind.** Paper white, ink, and the one red, falling once for about a second and a half
when the claim is sent. It is celebratory and it is unmistakably railway, which is the only kind
of celebration this app is allowed.

- Once, on sending. Never on arrival, never on a delay — docs/12 is clear that nothing in this
  app is pleased about a train being late, and the Antrag is the one moment that is genuinely
  the passenger's own doing.
- On the screen, **not on the card.** A shared image with confetti printed on it reads as a
  template and fights the number, which is the thing that has to survive a thumbnail. The card
  stays calm; the app is the one that cheers.
- No sound.

## 5. What the card never contains

Nothing leaves the phone that was not put on the card, and the card is rendered on the device —
no server, no upload, no public page. That is both the strongest privacy position and the
simplest thing to build.

The NGO's own logo goes on the card — the partners have agreed to be named and shown, and the
mark is theirs as it stands; we do not redraw it. It needs somewhere to live: `ngos` has no logo
today, so this means a column and a file, managed through Stellwerk like the rest of the NGO data.

**FAHRGAST is the nickname** — the one from Einstellungen → Konto → Name, which is what a
passenger has actually chosen to be called. It is on by default and switchable off in the preview.

It is *not* the legal name from **Deine Angaben**. That name sits beside a postal address on a
claim form, it exists because the Fahrgastrechte process demands it, and nobody typed it in order
to publish it. A ticket that carries „Johannes" is a nice touch; one that carries the full name on
the Antrag is a different object with different consequences, and the two must not be confused
because they look similar in a settings screen.

Never on a card, under any setting:

- the legal name from Deine Angaben, the postal address, the ticket number, the e-mail, the relay
  address;
- anything from a claim's correspondence or its PDF;
- another passenger, ever.

Switchable in the preview:

- **the date** — off makes the card undatable, which matters to anyone who would rather not
  publish where they were on a given afternoon;
- **the nickname** — see the open questions;
- **the route** — a commuter posting the same two stations every week is publishing their routine.
  Dropping to the line alone („RE 7") keeps the story and loses the pattern.

## 6. How it is built

- The card is an ordinary Flutter widget in the app's own kit, wrapped in a `RepaintBoundary`,
  captured with `toImage(pixelRatio: 3)` and handed to `share_plus`. No backend work at all.
- Because it is a widget, it goes through the screenshot tour like every screen, and its four
  faces are four more shots. A card that renders wrong is caught the way everything else is.
- It works offline, which matters: the moment worth sharing happens on a platform, not on wifi.

## 7. The ways this goes wrong

Worth writing down, because the pull of a sharing feature is always towards more of it.

- **Rewarding a share corrupts the ledger.** No Geduldspunkte for sharing, no badge for sharing,
  nothing gated behind it. The numbers in this app are honest because they only ever measure
  waiting; a number that also measures marketing is no longer evidence of anything. docs/12 bans
  buying points for the same reason.
- **Counting shares invites nagging**, and nagging is against the house rules already: no streaks,
  no shaming, no fake urgency (docs/12). „Du hast diese Woche noch nichts geteilt" must never
  exist.
- **This morning we removed ranking from Home** (docs/26 §1) because it reframed somebody's
  waiting as progress towards a title. Sharing amplifies exactly that risk: broadcast the badges
  loudly enough and the delays start to look like something a person might want. The defence is
  the ordering in §0 — the fact first, the achievement second — and a voice that never celebrates
  the delay.
- **No share button on the moving train.** docs/12: nothing celebrates a delay while the customer
  is still sitting in it. The reveal is at arrival, and so is the card.

## 8. Open questions — these need Johannes

1. ~~Nickname on the card~~ — **settled**: on, as FAHRGAST, from Einstellungen. Switchable off in
   the preview, and never the legal name from Deine Angaben (§5).
2. ~~NGO logo~~ — **settled**: the partners permit name and logo, and we use each NGO's current
   mark as it stands. Remaining detail: `ngos` has no logo column, so where the file lives and how
   Stellwerk sets it needs deciding with the rest of the build.
3. ~~The Bahnhofsuhr on a public card~~ — **settled**: it goes on the card. Recorded as Johannes'
   decision; the licensing question (the station-clock face is SBB/Mondaine property) is his to
   close, and it applies to `VStationClock` inside the app just as much.
4. ~~Antrag: when sent or when confirmed?~~ — **settled**: when sent. The framing carries the
   honesty instead of the timing — „gebeten" is exactly what has happened at that moment, and the
   passenger gets the gratification while they still feel it.

   The „spenden" worry from the first draft is gone with it: the four lines in §1 say „zahlen"
   and „dazu gebracht", which is what actually happened — the railway is paying because somebody
   made a claim. Nobody has to call it a donation for the sentence to land.
5. ~~Link target~~ — **settled**: `www.verspaetomat.de`, one address for every card. No per-card
   public page, so no public URL describing a real person's journey.

   The site does not exist yet — both names resolve to the VPS, but Caddy serves
   `api.verspaetomat.de` and nothing else. That is known and is the next piece of work after this
   one; the cards link there regardless. The only ordering that matters: the page is up before the
   first ticket is shared, because the one person who follows the link is the one who was curious.
   It does not have to be much — what the app is, what happens to the money, the store links.
6. **Is Bilanz in scope now**, or after the four faces are out? See §1a — it is the biggest of
   the five and the only one that needs data the app does not already have on screen.

## 9. What shipped, and what did not

Built:

- `lib/widgets/ticket.dart` — the Fahrkarte with five faces (Antrag, Angekommen, Pünktlich,
  Abzeichen, Wir), perforated edges, the punch hole, and the number at a third of the card's
  width so nothing else competes with it at thumbnail size.
- `lib/widgets/konfetti.dart` — the Lochzangen-Konfetti, seeded so the tour sees the same
  celebration every run.
- `lib/screens/share/` — the preview sheet with the four lines and the switches, and the four
  sentence sets. Captured with `RepaintBoundary.toImage(pixelRatio: 3)` to a 1080 × 1350 PNG and
  handed to the native share sheet; the widget on screen is the thing that goes out.
- Migration 0026 and `stellwerk ngo set <id> --logo <datei.png>` — the NGO's mark, stored inline
  as a data URI. Not a URL: the card is drawn on a phone that may be underground, there is
  nowhere to host partner logos until the website exists, and hotlinking a partner's own server
  for something we print is not a thing to do. Stellwerk refuses anything over 200 KB.
- The five places from §2, including the two stubs that had been waiting since docs/12.

Not built, deliberately:

- **The Jahreskarte** (§1a) — there is not a year of data to put on one.
- **The confirmation card.** The ticket knows how (`paid: true`, and it is unit-tested: `ZAHLT AN`
  becomes `BEZAHLT`), but nothing calls it. The confirmation arrives through an NGO report weeks
  after the fact, and giving that moment a place of its own is a separate piece of work.

## 10. Tests

- Tour: `karte-angekommen`, `karte-puenktlich`, `karte-abzeichen` with the preview sheet around
  them. `karte-antrag` needs a sent claim in Demo mode and is not in the tour yet.
- `test/share_lines_test.dart` — ten of them, and the first Dart unit tests in this repo. One
  asserts that **no line ever says „spenden"**, so the honesty in §8.4 is enforced rather than
  remembered.
- By eye at thumbnail size: the big number is the only legible thing. If the route or the name
  competes with it, the number is not big enough.
- Unit: the card's copy for 0 minutes, 59, 60, a cancellation, and a claim in each of its states;
  the Antrag sentence for one Fall and for many („1 Verspätung" against „3 Verspätungen"); German
  number formatting throughout (`1,50 €`, `1.208.638`).
- Tour: `konfetti` on the sending screen, caught mid-fall.
- By hand: one card into a feed, a story and a chat app, to see that the crop survives all three.
