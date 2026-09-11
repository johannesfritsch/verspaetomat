# 31 — Die Website: eine Seite, die aussieht wie eine Fahrkarte

Concept and an offer, written 11 September 2026. Nothing built yet.

## 0. This is not a marketing page (or not only)

The site looks optional and is not. Three things in the repo already point at URLs that do not
exist, and one of them blocks the store submission:

| Who asks | URL | Where it is written down | If it is missing |
|---|---|---|---|
| App Store Connect | `https://verspaetomat.de/datenschutz` | docs/40 §"App Store: App Privacy" | The listing cannot be submitted: the privacy policy URL is mandatory |
| Play Console | `https://verspaetomat.de/loeschen` | docs/40 §"Data safety" | Data-safety form incomplete |
| Every shared Fahrkarte | `www.verspaetomat.de` | docs/27 §3, printed on the card | The one line the card prints leads nowhere |
| § 5 DDG | `/impressum` | `app/lib/content/legal.dart` | A German site that advertises an app needs one |

So the deliverable is **one page plus four documents**, and the four documents are the part with
a deadline. The one page is the part with the fun in it.

## 1. The shape

| Route | What | Source |
|---|---|---|
| `/` | The page. Everything below in §2. | `site/content/index.md` + template |
| `/impressum` | Verbatim from the app | `legal.json` |
| `/datenschutz` | Verbatim from the app | `legal.json` |
| `/bote` | „Wie wir Anträge weiterleiten" — verbatim from the app | `legal.json` |
| `/loeschen` | Short page: how deletion works in the app, plus the e-mail address. Play asks for a URL, not a form. | `site/content/loeschen.md` |
| `/og.png` | 1200 × 630 — the Fahrkarte, so a link previews as a ticket | asset |

`verspaetomat.de` is canonical (docs/40 prints it without `www`); `www.verspaetomat.de` 301s to it,
because that is the host printed on the card and it must land. Both already resolve to the VPS.

No blog, no Impressum-quality prose about our mission, no newsletter, no cookie banner (§3).

## 2. The page, block by block

Seven blocks, in this order. Everything is one column at phone width; the widest thing on the
page is a 720 px measure, because this is a page about a small paper object.

### 2.0 Kopf

A 1 px rule, `VERSPÄTOMAT` in letterspaced small caps on the left, the station clock on the
right. That is the whole header — no nav, because there is nowhere to navigate to. The clock is
an inline SVG with a CSS-animated second hand that pauses at twelve, exactly as
`VStationClock` does in the app. One decorative element, and it is the brand.

### 2.1 Der Held: eine Fahrkarte, groß

The hero is **the artefact itself** at the size of a hand. Same object as docs/27: perforated
edge, the one red rule, the punch hole, the hero number. Built in HTML and CSS, not as an image,
so it is sharp on every screen and readable by a crawler.

```
FAHRGASTRECHTE, OHNE PAPIERKRIEG

Die Bahn war zu spät.
Diesmal zahlt sie dafür.

Verspätomat merkt sich deine Verspätungen, füllt den
Antrag aus und schickt ihn ab. Das Geld geht an einen
Verein, den du wählst. Nicht an uns.

[ Im App Store laden ]   So funktioniert's ↓
```

Next to it (below it on a phone) the card, with one plausible real ride on it — an example, and
labelled as one in small type underneath: `Beispiel. Deine Karte trägt deine Zahlen.` Inventing a
number and presenting it as a fact is the one thing this page must not do.

The perforation is a `repeating-radial-gradient` — the only gradient allowed anywhere near this
project, and it is a paper edge, not decoration. The punch hole is `VColors.ink` at 10 % with a
2 px `ink2` rim, as in `app/lib/widgets/ticket.dart`.

### 2.2 Der Fahrplan: so geht das

The strongest train idiom the app owns is its **stop list** (docs/26): a vertical rail, a dot per
stop, the line running through them. The five steps get exactly that treatment — one rail down
the left, five dots, `Zustieg`-style labels in the eyebrow position.

| Stop | Label | Copy |
|---|---|---|
| ● | EINCHECKEN | Am Bahnsteig ein Tipp. Dein Zug steht schon in der Liste, weil das Handy weiß, wo du stehst. |
| ● | FAHREN | Leg das Handy weg. Die Verspätung holt unser Server aus den öffentlichen Fahrplandaten — nicht aus deinem Standort. |
| ● | ANKOMMEN | Jede Minute wird gezählt. Unter 60 Minuten gibt es Geduldspunkte. Ab 60 Minuten einen Anspruch. |
| ● | ANTRAG STELLEN | Das EU-Formular ist ausgefüllt. Du unterschreibst mit dem Finger, der Antrag geht von deiner eigenen Adresse an die Fahrgastrechte-Stelle. |
| ◉ | DIE BAHN ZAHLT | An den Verein, den du gewählt hast. Direkt auf sein Konto. Wir sehen das Geld nie. |

The last dot is the red one, the way the app marks `Ziel`.

### 2.3 Bildstreifen

Five screenshots, phone-width, side by side in a horizontally scrollable strip; three visible on a
desktop, one and a half on a phone, scroll for the rest. No device frames, no perspective, no
shadows — STYLE.md forbids shadows in the app and the site should not undercut it. A caption of at
most six words under each.

Which five: **Bahnsteig** (the list of trains), **die Fahrt** (a ride running, +68), **der Antrag**
(the claim desk, the bundle), **die Fahrkarte** (what you share), **Wir** (the collective figure).

They come out of `app/tools/tour.sh`, which already produces one shot per screen in Demo mode.
That matters more than it sounds: the screenshots are then a build artefact of the app, not a
folder of stale PNGs somebody dragged in once.

### 2.4 Was wir nicht sind

Five lines, rules between them, the most load-bearing block on the page. Every competitor in this
market takes a cut; saying so plainly is the whole pitch.

- **Keine Provision.** Andere behalten 20 bis 30 Prozent. Wir behalten nichts — wir bekommen nichts.
- **Kein Konto.** Keine E-Mail, kein Passwort. Ein anonymes Gerätekonto und zwölf Wörter, falls du das Handy wechselst.
- **Kein Tracking.** Keine Analyse-SDKs, keine Werbung, kein Datenverkauf. Diese Seite lädt nichts von Dritten.
- **Kein Standortverlauf.** Die App schaut einmal am Bahnsteig und einmal beim Einchecken. Den Zug verfolgt der Fahrplan, nicht dein Handy.
- **Bote, kein Vertreter.** Der Antrag ist deiner, er trägt deinen Namen und deine Unterschrift. Wir füllen aus und leiten weiter. → `/bote`

### 2.5 Fragen

Plain `<details>`/`<summary>`, hairline-separated, no JavaScript. Nine of them, and the answers are
the ones the code actually implements (`backend/src/rules.rs`):

1. **Was kostet das?** — Nichts. Keine Gebühr, keine Provision, keine Werbung, keine In-App-Käufe.
2. **Wer bekommt das Geld?** — Der Verein, den du in der App wählst. Auf dem Antrag steht seine Kontoverbindung, nie unsere. Die Bahn überweist direkt.
3. **Ab wann gibt es überhaupt Geld?** — Ab 60 Minuten Verspätung am Ziel: 25 % des Fahrpreises. Ab 120 Minuten: 50 %. Darunter gibt es keinen gesetzlichen Anspruch — dafür Geduldspunkte.
4. **Und mit dem Deutschlandticket?** — Da sind es pauschal 1,50 € im Nahverkehr. Auszahlen muss die Bahn erst ab 4 €, deshalb sammelt Verspätomat, bis drei Verspätungen zusammenkommen, und schickt sie als einen Antrag.
5. **Muss ich mich anmelden?** — Nein. Beim ersten Antrag brauchst du Name und Adresse, weil das Formular sie verlangt. Vorher nichts.
6. **Was macht die App mit meinem Standort?** — Sie fragt den Bahnhof ab, an dem du stehst, und merkt sich beim Einchecken einen Fixpunkt als Nachweis. Kein Standort während der Fahrt, kein Verlauf. Ohne Standortfreigabe tippst du den Bahnhof ein und alles andere funktioniert.
7. **Vertritt Verspätomat mich gegenüber der Bahn?** — Nein, und das ist Absicht. Du stellst den Antrag, wir füllen ihn aus und leiten ihn weiter.
8. **Welche Züge?** — Alle, die in den offenen Fahrplandaten stehen: Fern- und Nahverkehr, jedes Eisenbahnunternehmen in Deutschland, und auch der Schienenersatzverkehr, wenn der Bus unter der Zugnummer fährt.
9. **Was, wenn die Bahn ablehnt?** — Die Antwort landet in der App, im Klartext. Wenn du sie für falsch hältst, ist die Schlichtungsstelle söp kostenlos zuständig — zwischen dir und der Bahn, ohne uns.

### 2.6 Holen

The App Store and Play badges, official artwork, side by side. The block renders from one small
config with three states per platform, because today neither store has it:

| State | What the block shows |
|---|---|
| `soon` | „Bald im App Store" in ink, no badge (Apple's guidelines do not allow the badge for an unreleased app) |
| `testflight` | „Jetzt testen" → the public TestFlight link |
| `live` | The official badge → the store URL |

One line in `site/content/stores.toml` flips it on release day. Today: iOS `testflight` once the
public link exists, otherwise `soon`; Android `soon`.

### 2.7 Fuß

`Impressum · Datenschutz · Wie wir Anträge weiterleiten · Daten löschen · j@jfritsch.de`, a
hairline above, the clock's second hand at twelve. No social icons — there are no accounts.

## 3. Look

The site is the app's design language on a wider screen. Not a new one.

- Tokens copied from `app/lib/theme/tokens.dart` into CSS custom properties, same names
  (`--paper`, `--ink`, `--ink2`, `--rule`, `--red`). Where the app says `paperElevated` for a card,
  the ticket uses white on paper, as the widget does.
- **Archivo self-hosted** as two `woff2` files (regular, semibold) with `font-display: swap`.
  Not Google Fonts: a German site embedding fonts from Google's CDN hands visitor IPs to a third
  party, which is precisely the kind of thing this app exists not to do — and it is what German
  courts have been unhappy about since 2022. Tabular figures via `font-variant-numeric: tabular-nums`
  everywhere a number appears.
- No third-party request of any kind. No analytics, no embeds, no CDN. Therefore **no consent
  banner is needed at all**, which is both a legal and an aesthetic win.
- Numbers in German formatting, `1,50 €`, dates as `Fr, 11. September 2026`.
- Prefers-color-scheme: **light only, deliberately.** The Bahnhofsuhr is a white enamel dial. A dark
  mode of it is a different object. `color-scheme: light` and done.
- Responsive down to 360 px. One `<img>` per screenshot, `loading="lazy"`, explicit
  width/height so nothing jumps.
- Weight budget: **under 200 KB** for the page including fonts, excluding screenshots (which are
  lazy). No framework ships inside that, which is most of §5.

## 4. The legal pages are not written twice

`app/lib/content/legal.dart` already holds Impressum, Datenschutz and „Bote" as structured data
(`LegalDoc` → `LegalSection` → paragraphs). docs/40 already warns that the wording lives in three
places and all three must move together. A hand-typed copy on the website would be the fourth, and
it would be the one nobody remembers.

So the website does not contain those texts. It generates them:

```
app/tools/legal_json.dart   →  site/content/legal.json  →  /impressum /datenschutz /bote
  (a 20-line Dart script;         (committed, so the site
   the Dart compiler is the        builds without Flutter)
   parser, not a regex)
```

And one test keeps them honest: the site build fails if `legal.json` is older than
`legal.dart`, and `cargo test` in the site crate asserts that every section in the JSON appears in
the generated HTML. Drift becomes a red build instead of a wrong privacy policy.

The placeholders are the blocker here, not the pipeline: `legal.dart` still says `[Name]`,
`[Straße Nr]`, `[PLZ Ort]`. An Impressum needs a real address before the site goes up — and so
does the store submission, so it is the same task.

## 5. Die Technik: das Angebot

The question was Rust-and-static or Next.js. **Recommendation: static, generated by a small Rust
binary in the repo.** Here is the comparison honestly:

| | Rust + static | Next.js |
|---|---|---|
| What the visitor gets | 5 HTML files, 1 CSS, 2 fonts, 6 images | The same, if configured right (`output: 'export'`) |
| New languages in the repo | none (Rust and Dart are already here) | JavaScript/TypeScript — a third |
| New dependency tree | 4 crates (`minijinja`, `serde`, `serde_json`, `toml`) | ~300 npm packages for React + Next, patched forever |
| Build on the VPS | `cargo build`, already installed for the API | Node toolchain to install and keep current |
| Runtime on the VPS | none — Caddy serves files | none in export mode, a Node server otherwise |
| CI | the `cargo test` we already run | a second pipeline |
| Time to first version | ~1 sitting | ~1 sitting |
| Cost when it is neglected for a year | it still builds | `npm audit` has 40 findings and the lockfile has rotted |
| What it buys us that we need | nothing extra | routing, ISR, image optimisation, i18n — none of which this page uses |

There is an honest case for Next.js, and it is this: if the site grows into a product with logins,
a Jahresbilanz that reads live data, or a second language, React is a better place to be. I do not
think that is the road here. The Jahreskarte (docs/27 §1a) is a phone feature, a public Wir figure
is one build-time `fetch` away, and everything on this page is text. Choosing Next.js for five
documents means installing a web framework to avoid writing a `<details>` element.

Against that, using Rust here is not Rust-for-its-own-sake either: the generator's real job is
§4 — read `legal.json`, render three documents, fail the build on drift — plus the store-badge
state machine of §2.6. That is ~300 lines and it lives next to the code that already knows how to
be deployed on this server.

Concretely:

```
site/
  Cargo.toml            minijinja, serde, serde_json, toml, anyhow. Its own crate, not a
                        member of backend/ — the API's dependency tree has no business here.
  src/lib.rs            read content/, render templates/, write dist/.
  src/main.rs           the flags: --strict, --out.
  templates/            base.html (Kopf, Fuß, Bahnhofsuhr), index.html, doc.html
  content/
    index.toml          the copy of §2, including the §2.6 store state
    loeschen.toml       the deletion page, in the same shape as a legal document
    legal.json          generated from the app
  static/
    verspaetomat.css    the tokens of §3, hand-written
    fonts/archivo-*.woff2 + OFL.txt
    shots/*.png         out of the tour
    og.png, favicon.svg
  og/og.html            the source of og.png, rendered once in a browser
  tests/legal.rs        the drift tests of §4
  dist/                 the result, committed (see §6)
```

`cargo run` writes `dist/`. That is the whole toolchain. No Markdown renderer: the deletion page
turned out to be a document with headings and paragraphs like the other four, so it goes through
the same template, and `pulldown-cmark` was never needed.

## 6. Serving it

Six lines in `deploy/caddy/Caddyfile`, next to the API block that is already there:

```
verspaetomat.de {
	encode zstd gzip
	root * /srv/site
	file_server
	header /assets/* Cache-Control "public, max-age=31536000, immutable"
}
www.verspaetomat.de {
	redir https://verspaetomat.de{uri} permanent
}
```

plus one read-only volume in `deploy/docker-compose.yml` (`../site/dist:/srv/site:ro`) and a
`docker compose up -d caddy` in `deploy/deploy.sh`, so a changed mount actually takes effect.
No new container, no new port, no new process to monitor, and Caddy fetches the two certificates
by itself, as it did for the API.

**`dist/` is committed.** The server builds the API from source but has neither Rust nor Node for
a website, so the site is built on the laptop and the result is checked in; deploying it is a
`git pull`. That was also the answer to the risk I was worried about here — that a failing site
build could stop a deploy meant for the backend. It cannot now: there is no site build on the
deploy path at all. The price is a generated directory in version control, and the test
`dist_ist_aktuell` pays it: it renders fresh and compares, so forgetting `cargo run` is a red
test rather than a website that says something the repository no longer says.

## 7. In and out

**In:** the seven blocks of §2, the four documents of §1, the CSS of §3, the legal pipeline of §4,
the generator of §5, the serving of §6, the OG image, a favicon, `robots.txt`, a `sitemap.xml`,
and the screenshots pulled from the tour.

**Out, on purpose:** dark mode, English, a blog, a newsletter, a contact form (an e-mail address
is a contact form that always works), animation beyond the second hand, analytics of any kind,
and a live Wir figure — which needs a public endpoint the backend does not have, and can be added
later in one build-time fetch.

## 8. Three decisions I would like

1. ~~**The Impressum address.**~~ Settled the same evening: Zoom7 GmbH, Pfarrer-Eggart-Str. 5,
   88085 Langenargen, with the register (Amtsgericht Ulm, HRB 728616), the VAT id and the company's
   own telephone and mail. `--strict` passes; see the note below about the one sentence that still
   needs a signature behind it.
2. **The hero card's example ride.** I would use a real one of yours with the name on it — it reads
   true in a way an invented Musterfahrt does not — or an anonymous one if you would rather not.
3. **iOS state in §2.6**: „Bald im App Store", or a public TestFlight link so the page can already
   hand somebody the app.

---

## Gebaut am 11. September 2026

Alles oben, mit diesen Abweichungen — und einer Überraschung:

- **Die Bilder sind echt.** `app/tools/tour.sh` lief durch (74 Aufnahmen, alle Tests grün), fünf
  davon liegen auf 640 px verkleinert in `site/static/shots/`: Home mit Einchecken-Karte, eine
  laufende Fahrt mit Umstieg, der Antragsschalter, die Fahrkarte im Teilen-Blatt, und Wir.
- **Die große Zahl ist rot.** Auf dem Schirm der App ist sie das auch — das war beim Vergleich von
  Entwurf und Aufnahme zu sehen, nicht vorher zu wissen.
- **Die Löschseite ist ein Dokument wie die drei anderen**, nur eben hier geschrieben. Damit
  entfällt der Markdown-Renderer aus §5.
- **`--strict` hat mehr gefunden als erwartet, und alles davon ist jetzt ausgefüllt.** Nicht nur
  `[Name]`, `[Straße Nr]`, `[PLZ Ort]` im Impressum: die Datenschutzerklärung wartete außerdem auf
  den Mail-Dienstleister mitsamt Sitz und auf das `[Bundesland]` der zuständigen Aufsichtsbehörde.
  Vier Lücken, nicht drei — und die App zeigte diese Klammern jedem, der in den Einstellungen
  nachlas. Eingetragen sind: der Anbieter mit Registereintrag und USt-IdNr., Postmark
  (ActiveCampaign, LLC, Chicago) als Versanddienstleister mit dem Hinweis auf die Übermittlung in
  die USA, Hetzner Online GmbH als Serverbetreiber, und Baden-Württemberg als Aufsicht.
  **Eine Zeile steht noch auf Vorschuss:** „Grundlage sind ein Auftragsverarbeitungsvertrag und die
  Standardvertragsklauseln" — das stimmt erst, wenn der Postmark-AVV wirklich unterschrieben ist.
  Der Mailversand läuft bis dahin ohnehin im Trockenlauf, es ist also noch nichts passiert; vor dem
  ersten echten Antrag muss der Vertrag stehen.
- **Gefunden beim Nachsehen:** die Website schrieb „Stand: Stand: 10. September 2026" — die Vorlage
  setzte das Wort davor, das die App längst im Text mitliefert. Nur auf dem Schirm zu sehen.
- **Die Schriften liegen selbst gehostet** (`static/fonts/`, 90 KB + 86 KB, SIL OFL). Die Seite
  lädt nichts von Dritten; deshalb braucht sie auch kein Einwilligungsbanner.
- **Ungeprüft:** dass Caddy die beiden Zertifikate (Apex und www) wirklich bekommt. Das lässt sich
  erst auf dem Server sehen. Die Konfiguration selbst ist mit `caddy validate` geprüft.
