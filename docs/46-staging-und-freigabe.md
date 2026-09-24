# 46 — Staging und Freigabe

Entschieden am 24. September 2026. Bis dahin hieß „ausliefern": auf `main` pushen, den einen
Server deployen, einen TestFlight-Build hochladen. Jetzt gibt es zwei Server und zwei Apps, und
Produktion bekommt nur noch, was vorher auf Staging lief.

## Was wo läuft

| | Produktion | Staging |
|---|---|---|
| Server | `ssh verspaetomat` (2.28.232.83) | `ssh verspaetomat-staging` (188.245.28.196) |
| API | `https://api.verspaetomat.de` | `https://api.staging.verspaetomat.de` |
| Website | `https://verspaetomat.de` | `https://staging.verspaetomat.de` (`noindex, nofollow`) |
| Git | Branch `production`, nur vorgespult | Branch `main` |
| `ENVIRONMENT` | `production` | `staging` |
| App | „Verspätomat", `de.verspaetomat.app` | „Verspätomat β", `de.verspaetomat.staging.app`, Symbol mit STAGING-Band |
| TestFlight | App „Verspätomat", Tags `ios-1.0.0-<build>` | App „Verspätomat Staging", nur intern, Tags `ios-staging-1.0.0-<build>` |
| Stellwerk | `stellwerk --prod …` | `stellwerk --staging …` |
| Daten | echte Fahrgäste, nächtliches Backup | nur erfundene, wegwerfbar |
| Mail-Relay | `users.verspaetomat.de` | `users.staging.verspaetomat.de`, raus nur an `MAIL_ALLOW` |
| Push | APNs-Schlüssel C4JKP6QHKA (Team S4NEUU3775), Topic der App | derselbe Schlüssel, Topic der Staging-App |

Beide Apps lassen sich nebeneinander installieren und haben getrennte Schlüsselbunde: ein Konto
auf dem einen Server begegnet dem anderen nie.

## Was `ENVIRONMENT` entscheidet (`backend/src/stage.rs`)

- **Produktion lehnt die Stellwerk-Aufrufe ab, die die Welt simulieren:** `delay`, `cancel`, `ff`,
  `reply`, `reset`, `locate`, `backdate`, `confirm` und das Setzen der Uhr. Dort wären sie Lügen über
  echte Fahrten. Stationen, Vereine, Routen, Push, Flags und Kunden bleiben erreichbar.
- **Staging schickt Mail nur an Domains aus `MAIL_ALLOW`** (und an die eigene `RELAY_DOMAIN`),
  geprüft für Empfänger und Bcc, bevor irgendetwas rausgeht. Ohne `MAIL_ALLOW` geht nichts raus.
  Selbst eine Route, die auf einen echten Schalter der Bahn zeigt, kommt dort nicht an.
- `/health` nennt Stage und Commit. Daran prüft die Freigabe, dass Staging läuft, was sie ausliefert.
- Die Variable ist Pflicht: Fehlt sie in `deploy/.env`, startet der Stack nicht, statt still als
  „development" zu laufen.

## Der Rhythmus

**Staging-Release (oft)**

```bash
git push                                                     # main
ssh verspaetomat-staging /opt/verspaetomat/deploy/deploy.sh  # Backend und Website auf Staging
STAGE=staging app/tools/release.sh                           # Staging-App nach TestFlight
```

**Freigabe für Produktion (manchmal)**

```bash
deploy/promote.sh            # den Commit, der auf Staging läuft
```

Das Skript prüft, dass Staging gesund ist und genau diesen Commit meldet, dass er auf `main` liegt
und `production` zu ihm vorspulen kann. Dann lässt es den letzten Produktions-Build der App gegen
Staging laufen (`deploy/compat.sh`, siehe unten), schiebt `production` vor, deployt den
Produktionsserver (Website und Backend) und prüft, dass Produktion denselben Commit meldet. Die
Produktions-App kommt danach aus demselben Commit — das Skript druckt den Befehl. Die Reihenfolge
bleibt: Website, Backend, dann TestFlight.

Ein iOS-Build lässt sich nicht auf einen anderen Server umbiegen (`API_URL` ist eingebacken), darum
wird die Produktions-App aus dem freigegebenen Commit neu gebaut, nicht der Staging-Build
weitergereicht.

## Alte App gegen neues Backend (`deploy/compat.sh`)

Hausregel: Alte App-Versionen müssen gegen das neue Backend weiter funktionieren. Das Skript prüft
es: Es checkt die App am Tag des letzten Produktions-Builds in einem eigenen Worktree aus und lässt
deren Workflow-E2E im Simulator gegen Staging laufen. Der E2E treibt die Welt über Stellwerk, was
Staging erlaubt und Produktion ablehnt.

## Stationen

Stations-Ids vergibt die Datenbank, die importiert, in der Reihenfolge, in der sie den Halten
begegnet. Zwei Datenbanken, die denselben Feed importieren, nummerieren ihn verschieden — am
24. September 2026 gemessen: jede Id um eins verschoben. Die App trägt den Auszug der Produktion,
eine Staging-App schickte also Ids, unter denen Staging andere Bahnhöfe versteht.

Darum werden Ids nur in Produktion gemacht. Staging importiert nie selbst, sondern bekommt eine
Kopie der drei Stationstabellen:

```bash
stellwerk --prod stations import       # wie bisher, nur in Produktion
deploy/stations-to-staging.sh          # danach, und nach jedem reset-staging.sh
```

Dabei geht nur öffentliche Fahrplanwelt über die Leitung, nichts, was einen Menschen nennt.

## Staging zurücksetzen

Staging hält nur Erfundenes. Wenn dort etwas verfahren ist — eine Migration nach dem Lauf
geändert, eine Welt in eine Ecke simuliert:

```bash
ssh verspaetomat-staging /opt/verspaetomat/deploy/reset-staging.sh
deploy/stations-to-staging.sh
```

Das Skript verweigert sich überall, wo `.env` nicht `ENVIRONMENT=staging` sagt.

Eine Migration, die Staging erreicht hat, wird nicht mehr geändert: sqlx vergleicht Prüfsummen und
startet sonst nicht. Ändern heißt: eine neue Migration schreiben.

## Keine Produktionsdaten auf Staging

Staging bekommt nie einen Dump der Produktion. Dort stehen Namen, Adressen, Unterschriften und
Fahrkartenfotos. Die Rücksicherung der Backups wird in Produktion in eine eigene Datenbank geprobt,
nicht auf Staging. Die einzige Ausnahme sind die Stationstabellen (öffentlich, siehe oben). Die
Vereine sind auf beiden Servern dieselben aus `backend/fixtures/ngos.json`.

## Einmal eingerichtet (24. September 2026)

- Hetzner CX22 (Ubuntu 26.04), dieselbe Firewall (22, 80, 443), derselbe SSH-Schlüssel.
- DNS bei Namecheap: A `staging` und A `api.staging` → 188.245.28.196.
- Server wie in docs/42 A3–A6 (Docker, unattended-upgrades, Klon nach `/opt/verspaetomat`), `.env`
  mit eigenen Geheimnissen — keins ist aus Produktion übernommen, außer dem team-weiten APNs-Schlüssel.
- `stellwerk config init --ssh verspaetomat-staging --name staging`.
- Produktion: Branch `production` am damals laufenden Commit 81d5380, der Server folgt ihm;
  `ENVIRONMENT=production` in `deploy/.env` ergänzt (die alte Datei liegt als `.env.bak-2026-09-24`).
- Apple: beide Apps ziehen ins Team S4NEUU3775 um, mit neuen Bundle-Ids `de.verspaetomat.app` und
  `de.verspaetomat.staging.app` (Push an), je ein App-Store-Connect-Eintrag mit interner Testgruppe.
  Neuer API-Schlüssel TZ7F36WN22 (App Manager), neuer APNs-Schlüssel C4JKP6QHKA. Die alten Apps im
  Team PNC6S4SMVN bekommen keine Builds mehr; ihre Konten ziehen nicht mit (anderes Team, anderer
  Schlüsselbund).
- Postmark: eigener Server „Verspätomat Staging", Domain `users.staging.verspaetomat.de` (DKIM,
  Return-Path, SPF), MX dorthin; Token als `POSTMARK_TOKEN` in der `.env` von Staging.
