# 42 — Runbook: Hetzner VPS and TestFlight

Written 10 September 2026 against commit `341afc4` plus the release fixes of the same day. Everything here was checked on this machine: the Docker image builds (196 MB), `docker compose config` validates, `flutter build ios --release` succeeds. What could not be checked without your accounts is marked **[you]**.

Total time if nothing goes wrong: about 90 minutes of doing, plus waiting for DNS (minutes to hours) and App Store Connect processing (10 to 30 minutes per build).

The code lives at https://github.com/johannesfritsch/verspaetomat (public). The server clones it; `deploy/.env` and `deploy/secrets/` are git-ignored and stay on the server.

---

## Part A — Backend on a Hetzner VPS

### A1. Create the server **[you]** (5 min)

1. https://console.hetzner.cloud → New project "Verspätomat" → Add Server.
2. Location **Falkenstein** or **Nuremberg** (EU, matters for the DPIA). Image **Ubuntu 24.04**. Type **CX22** (2 vCPU, 4 GB, 40 GB, about 4 €/month). Shared vCPU is fine; the API idles at a few MB.
3. Networking: IPv4 **and** IPv6.
4. SSH key: add your public key (`cat ~/.ssh/id_ed25519.pub`). Never use the password option.
5. Firewall: create one with inbound **22/tcp, 80/tcp, 443/tcp** only, attach it to the server.
6. Name: `verspaetomat-1`. Create. Note the IPv4 and IPv6.

### A2. DNS **[you]** (2 min, then wait)

At your registrar for `verspaetomat.de`:

| Type | Name | Value |
|---|---|---|
| A | `api` | the IPv4 from A1 |
| AAAA | `api` | the IPv6 from A1 |

Check from your Mac until both answer:

```bash
dig +short api.verspaetomat.de A
dig +short api.verspaetomat.de AAAA
```

The mail records (MX, SPF, DKIM, DMARC) come later with Postmark; they are in `deploy/README.md` section 1. Not needed for TestFlight.

### A3. Prepare the server (10 min)

```bash
ssh root@api.verspaetomat.de            # or the IPv4 while DNS propagates
apt-get update && apt-get -y dist-upgrade
apt-get install -y git unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades   # choose Yes
curl -fsSL https://get.docker.com | sh
docker --version && docker compose version  # Docker 27+, Compose v2.x
mkdir -p /opt/verspaetomat /var/backups
exit
```

### A4. Clone the code (1 min)

```bash
ssh root@api.verspaetomat.de
git clone https://github.com/johannesfritsch/verspaetomat.git /opt/verspaetomat
```

Public repository, so no key is needed on the server. Every later update is `git pull` (A7).

### A5. Configure (5 min)

```bash
ssh root@api.verspaetomat.de
cd /opt/verspaetomat/deploy
cp .env.example .env
openssl rand -hex 24    # run three times, one value each for the three secrets below
nano .env
```

Set exactly these lines; leave everything that starts with `# ` commented for now (mail and push then run in dry-run, which is what you want until Postmark and Apple exist):

```
POSTGRES_PASSWORD=<random 1>
API_DOMAIN=api.verspaetomat.de
ACME_EMAIL=j@jfritsch.de
ADMIN_TOKEN=<random 2>
```

Keep `<random 3>` for `INBOUND_SECRET` later. Keep a space before any inline `#` comment you leave in place; compose reads the value up to it.

### A6. First start (10 min, mostly compiling)

```bash
docker compose up -d --build
docker compose logs -f api
```

Expected in the log, in this order: migrations `0001` to `0019` applied, `push: no APNS_*/FCM_* credentials, pushes are logged (dry-run)`, `verspaetomat-api listening on http://0.0.0.0:8080`. Ctrl-C leaves it running.

```bash
curl https://api.verspaetomat.de/health
# {"db":true,"ok":true,"service":"verspaetomat-api"}
docker compose exec api stellwerk customers
# empty table: no app has connected yet
```

If `curl` fails with a certificate error, Caddy is still fetching it: `docker compose logs caddy` shows the ACME steps. That needs A2 to have propagated and ports 80 and 443 open (A1 step 5).

### A7. Every later update

```bash
# on the Mac
git push
# on the server
ssh root@api.verspaetomat.de 'cd /opt/verspaetomat && git pull && cd deploy && docker compose up -d --build api && docker compose logs --tail 30 api'
```

Postgres and Caddy keep running; only the API is rebuilt and restarted. Migrations run on start. Rolling back is `git checkout <commit>` plus the same compose line; migrations are forward-only, so only roll back across commits without new migration files.

### A8. Backups (2 min)

```bash
crontab -e
```

Add:

```
15 3 * * * cd /opt/verspaetomat/deploy && docker compose exec -T db pg_dump -U verspaetomat verspaetomat | gzip > /var/backups/verspaetomat-$(date +\%F).sql.gz && find /var/backups -name 'verspaetomat-*.sql.gz' -mtime +30 -delete
```

Copy dumps off the machine from time to time (`scp root@api.verspaetomat.de:/var/backups/verspaetomat-*.sql.gz ~/Backups/`). They contain personal data; keep them encrypted and in the EU.

### A9. Stellwerk against the server

The admin API is not reachable from the internet (Caddy answers 404 for `/admin/*`). Use it inside the container:

```bash
ssh root@api.verspaetomat.de 'cd /opt/verspaetomat/deploy && docker compose exec api stellwerk customers'
ssh root@api.verspaetomat.de 'cd /opt/verspaetomat/deploy && docker compose exec api stellwerk locate Johannes "Köln Hbf"'
```

---

## Part B — iOS build into TestFlight

Facts already in the project: bundle id `de.verspaetomat.verspaetomat`, team `PNC6S4SMVN`, automatic signing, version `1.0.0+1` in `app/pubspec.yaml`, display name "Verspätomat", app icon (Bahnhofsuhr) in all sizes, privacy manifest, `ITSAppUsesNonExemptEncryption = false` (no export-compliance question per build), Always-location and background-location strings, `UIBackgroundModes = location`.

A release build starts at Willkommen on a fresh install and at the Bahnsteig once onboarding is done, and talks to the real backend by default. The Showcase stays reachable from Einstellungen.

### B1. Apple accounts **[you]** (once)

1. https://developer.apple.com/programs/enroll → Apple Developer Program, 99 €/year. Team `PNC6S4SMVN` is already in the project, so you may already have this; check at https://developer.apple.com/account under Membership.
2. Xcode → Settings → Accounts → your Apple ID is signed in and shows the team.

### B2. Register the app id and capabilities **[you]** (5 min)

```bash
open /Users/johannes/code/verspaetomat/app/ios/Runner.xcworkspace
```

Target **Runner** → **Signing & Capabilities** → tab **Release**:

1. "Automatically manage signing" on, Team = your team. Xcode registers `de.verspaetomat.verspaetomat` and creates the profiles.
2. **+ Capability → Push Notifications.** Needed now: the entitlement must be in the build for pushes to work later, and every later change needs a new upload.
3. **+ Capability → Background Modes → Location updates** checked. (The plist key is already there; this only makes Xcode agree.)
4. Build once in Xcode (⌘B) to confirm signing works. Fix any red text before continuing.

Repeat 1 to 3 for the **Debug** tab if Xcode asks.

### B3. App Store Connect record **[you]** (5 min)

https://appstoreconnect.apple.com → My Apps → **+** → New App:

| Field | Value |
|---|---|
| Platforms | iOS |
| Name | Verspätomat |
| Primary language | German (Germany) |
| Bundle ID | de.verspaetomat.verspaetomat |
| SKU | verspaetomat |
| User access | Full |

### B4. Build the IPA (5 min)

```bash
cd /Users/johannes/code/verspaetomat/app
flutter build ipa --release \
  --build-name=1.0.0 --build-number=1 \
  --dart-define=API_URL=https://api.verspaetomat.de \
  --dart-define=BACKEND=local
```

Output: `build/ios/ipa/verspaetomat.ipa`. Every upload needs a higher `--build-number`; the name can stay.

If it fails with a signing or provisioning message, go back to B2 and build in Xcode once; Flutter uses the same automatic signing.

### B5. Upload (5 min, then 10 to 30 min processing)

Easiest: **Transporter** from the Mac App Store → sign in → drag the `.ipa` in → Deliver.

Command line alternative, with an app-specific password from https://appleid.apple.com → Sign-In and Security → App-Specific Passwords:

```bash
xcrun altool --upload-app --type ios \
  --file build/ios/ipa/verspaetomat.ipa \
  --username j@jfritsch.de --password '<app-specific password>'
```

### B6. TestFlight **[you]** (5 min)

App Store Connect → Verspätomat → **TestFlight**:

1. Wait until the build leaves "Processing". No export-compliance question appears (the plist answers it).
2. **Internal Testing** → **+** → group "Ich" → add yourself (your Apple ID must be a user of the team under Users and Access).
3. Enable the build for the group.
4. On the phone: install **TestFlight** from the App Store, accept the invitation mail, install Verspätomat.

First launch: Willkommen → Berechtigungen (iOS asks for location "Beim Verwenden"; the Always upgrade prompt comes later on its own, as Apple designs it; allow notifications) → Dein Ticket, dein Zweck → Bahnsteig. Then on the server:

```bash
ssh root@api.verspaetomat.de 'cd /opt/verspaetomat/deploy && docker compose exec api stellwerk customers'
```

Your phone is the row with the newest `last_seen`. Set a nickname in Einstellungen so it stops saying "Fahrgast".

### B7. Push, once the APNs key exists **[you]** (10 min)

1. https://developer.apple.com/account/resources/authkeys/list → **+** → name "Verspätomat APNs", tick **Apple Push Notifications service (APNs)** → Continue → Register → **Download** (only possible once; keep the `.p8` safe). Note the **Key ID** on that page and your **Team ID** (top right, or Membership).
2. Copy the key to the server and switch push on:

```bash
scp ~/Downloads/AuthKey_XXXXXXXXXX.p8 root@api.verspaetomat.de:/opt/verspaetomat/deploy/secrets/
ssh root@api.verspaetomat.de
cd /opt/verspaetomat/deploy && nano .env
```

Uncomment and fill:

```
APNS_KEY_P8=/secrets/AuthKey_XXXXXXXXXX.p8
APNS_KEY_ID=XXXXXXXXXX
APNS_TEAM_ID=PNC6S4SMVN
APNS_TOPIC=de.verspaetomat.verspaetomat
APNS_SANDBOX=0
```

`APNS_SANDBOX=0` is right for TestFlight installs (they use the production APNs environment). Only builds installed by Xcode directly use the sandbox.

```bash
docker compose up -d api && docker compose logs --tail 20 api    # "push: APNs configured"
docker compose exec api stellwerk push Johannes "Hallo vom Server"
```

The phone shows the notification within seconds. If the log says `BadDeviceToken`, the sandbox flag is wrong for that install.

---

## Part C — What is still off after this

| Feature | State after A and B | Switch on with |
|---|---|---|
| Check-in, live delays, ledger, Geduldspunkte, badges, boards, geofence nudge, PDF preview | working | — |
| Sending a claim to the railway | dry-run: the mail is composed, logged, not sent | Postmark: `deploy/README.md` sections 1 and 2, then `SMTP_URL` |
| Railway replies | nothing arrives | Postmark inbound + `INBOUND_SECRET` (`<random 3>`) |
| Push | after B7 | — |
| Android | debug APK builds; Play needs the console account | `docs/41-launch-checklist.md` A5 |

The order for the following week, from `docs/41-launch-checklist.md`: Postmark account and mail DNS first, because domain reputation takes days; the NGO agreement in parallel, because a real claim needs a real payee.
