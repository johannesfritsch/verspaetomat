# Deploying Verspätomat on one VPS

One machine, three containers: Postgres, the API, Caddy for TLS. The API is a single
binary with migrations, fixtures and the PDF fonts embedded. Nothing else runs on the box.

Everything below that needs an account (domain registrar, mail provider, Apple, Google)
is marked **[you]**. The rest is copy and paste.

## 0. What you need before starting

| Item | Where it goes |
|---|---|
| **[you]** A VPS with Docker and Docker Compose (2 vCPU, 2 GB RAM, Debian or Ubuntu) | — |
| **[you]** The domain `verspaetomat.de` at a registrar with editable DNS | DNS records below |
| **[you]** A Postmark account (or SES) with the domain verified | `SMTP_URL`, inbound webhook |
| **[you]** APNs auth key (.p8), key id, team id | `APNS_*` |
| **[you]** Firebase service account JSON with the Cloud Messaging role | `FCM_SERVICE_ACCOUNT_JSON` |

## 1. DNS

Two jobs: the API host, and mail for the relay addresses `fahrgast-XXXX@users.verspaetomat.de`. The relay lives on the subdomain `users.` so the apex `verspaetomat.de` keeps its own mailboxes; `RELAY_DOMAIN` in `.env` changes it.

| Record | Name | Value | Why |
|---|---|---|---|
| A | `api.verspaetomat.de` | the VPS IPv4 | Caddy gets its certificate for this name |
| AAAA | `api.verspaetomat.de` | the VPS IPv6 (if any) | same |
| MX | `users.verspaetomat.de` | `10 inbound.postmarkapp.com` | Railway replies to `fahrgast-*@users.` land at Postmark, which posts them to us. No MX at the apex for this |
| TXT | `users.verspaetomat.de` | `v=spf1 include:spf.mtasv.net -all` | SPF for the From domain of the relay |
| TXT | `verspaetomat.de` | `v=spf1 include:spf.mtasv.net -all` | SPF at the apex too (Postmark checks it when verifying the domain) |
| TXT | `<selector>._domainkey.verspaetomat.de` (Postmark shows the exact host, e.g. `20260910pm._domainkey`) | the long `k=rsa; p=…` value from Sender Signatures → DKIM | DKIM on the apex covers `users.` too: a verified domain in Postmark may send from its subdomains |
| CNAME | `pm-bounces.verspaetomat.de` | `pm.mtasv.net` | Return-Path alignment (DMARC passes on the envelope sender) |
| TXT | `_dmarc.verspaetomat.de` | `v=DMARC1; p=none; rua=mailto:dmarc@verspaetomat.de` | DMARC in monitor mode first; tighten to `p=quarantine; adkim=s; aspf=s` after a few clean weeks of reports |

Deutsche Bahn's Servicecenter is a large corporate mail system: SPF, DKIM and DMARC all
have to pass, or the claim mail lands in quarantine and nobody ever answers. Verify with
Postmark's "DNS check" and with `dig TXT verspaetomat.de` before the first real claim.

If SES instead of Postmark: SPF `include:amazonses.com`, DKIM via SES "Easy DKIM" (three
CNAMEs), inbound via SES receipt rule → SNS → HTTPS to the same webhook, and
`SMTP_URL=smtp://SMTP-USER:SMTP-PASS@email-smtp.eu-central-1.amazonaws.com:587`.

## 2. Mail provider (Postmark as the worked example)

1. **[you]** Servers → create a server "Verspätomat", Transactional stream.
2. **[you]** Sender Signatures → add domain `verspaetomat.de` (the apex; subdomains are covered), set the DKIM and Return-Path
   records from step 1, wait for both to verify.
3. **[you]** Server → API Tokens → copy one. Outbound over SMTP uses that token as both user
   and password. Postmark speaks STARTTLS on 587 (no implicit TLS on 465):
   `SMTP_URL=smtp://TOKEN:TOKEN@smtp.postmarkapp.com:587`.
4. **[you]** Inbound: Server → Inbound stream → "Inbound webhook":

   ```
   https://api.verspaetomat.de/internal/inbound-mail?secret=<INBOUND_SECRET>
   ```

   The JSON endpoint understands Postmark's payload as posted (`To`/`ToFull`, `From`,
   `Subject`, `TextBody`, `MessageID`, `Headers`, base64 `Attachments`). Tick
   **"Include raw email content in JSON payload"** as well: with `RawEmail` present the
   backend parses the original MIME instead, which keeps every threading header and
   attachment exactly as sent. Providers that POST the bare RFC 822 message use
   `/internal/inbound-mail/raw?secret=…` (same secret, same processing).
5. **[you]** Inbound domain forwarding: under the inbound stream, set the inbound domain to
   `users.verspaetomat.de` so `fahrgast-anything@users.verspaetomat.de` is accepted (the MX record
   from step 1 makes Postmark the receiver). Every relay address is routed by the
   backend: it looks the customer up by the `To` address.

The secret in the URL is the only guard on the webhook; make it long and random.

A new Postmark account is in "test mode": it may only send to addresses on your own verified
domains until you request approval (Account → "Request approval", a short form about what you
send). The Servicecenter's address is not on your domain, so request approval right away.

Check both directions with one command once `SMTP_URL` and the webhook are set:
`stellwerk --prod mail-test <customer> you@example.org`, then reply to that mail from your inbox;
the reply shows up in `docker compose logs api` as an inbound mail for that relay address.

## 3. First start

```bash
git clone https://github.com/johannesfritsch/verspaetomat.git /opt/verspaetomat && cd /opt/verspaetomat/deploy
cp .env.example .env
$EDITOR .env                       # POSTGRES_PASSWORD, ADMIN_TOKEN, INBOUND_SECRET, SMTP_URL, API_DOMAIN, ACME_EMAIL, APNS_*, FCM_*
mkdir -p secrets && cp ~/Downloads/AuthKey_*.p8 secrets/ && cp ~/Downloads/firebase-*.json secrets/firebase-service-account.json
docker compose up -d --build       # ~10 min the first time (Typst and friends)
docker compose logs -f api         # "listening on", "push: APNs configured", "push: FCM configured"
curl https://api.verspaetomat.de/health
```

Migrations run on every start. Fixtures (operators, NGOs, badges, seeded boards) are
upserted on every start, so editing `backend/fixtures/*.json` and redeploying updates them.

The app is pointed at the server with `--dart-define=API_URL=https://api.verspaetomat.de`
and `--dart-define=BACKEND=local`.

## 4. Stellwerk against the server

`/admin/*` is reachable over HTTPS and guarded by `ADMIN_TOKEN` (long and random, compared in
constant time). From a laptop:

```bash
stellwerk config init --ssh verspaetomat   # once: reads ADMIN_TOKEN from the server's deploy/.env,
                                           # writes ~/.config/verspaetomat/stellwerk.toml (mode 600)
stellwerk --prod customers                 # --dev (the local backend on 8080) is the default
stellwerk --prod push Johannes "Test"
```

Or on the server: `docker compose exec api stellwerk customers`.

## 5. Backups

Daily dump, kept for 30 days, on the VPS:

```cron
15 3 * * * cd /opt/verspaetomat/deploy && docker compose exec -T db pg_dump -U verspaetomat verspaetomat | gzip > /var/backups/verspaetomat-$(date +\%F).sql.gz && find /var/backups -name 'verspaetomat-*.sql.gz' -mtime +30 -delete
```

Restore: `gunzip -c file.sql.gz | docker compose exec -T db psql -U verspaetomat verspaetomat`.

The database holds personal data (names, addresses, private e-mail, signatures, ticket
scans). Encrypt the backup volume or ship dumps with `age`/`gpg` before copying them off
the machine, and keep them inside the EU.

## 6. Updating

```bash
ssh verspaetomat /opt/verspaetomat/deploy/deploy.sh     # git pull, rebuild only the API, reload Caddy, show status
```

Postgres keeps running. Migrations run on start. Rolling back is `git checkout <previous>`
followed by `docker compose up -d --build api`; migrations are forward-only, so roll back
only across commits without new migration files. After a change to `docker-compose.yml`
itself, run `docker compose up -d` once so the affected containers are recreated.

## 7. Checks after every deploy

- `curl https://api.verspaetomat.de/health` → `{"db":true,"ok":true}`.
- `docker compose exec api stellwerk push <your customer>` → "sent" (or "dry-run" if
  `APNS_*` are unset), and the phone shows it.
- Outbound: send a claim from a test customer to your own address by pointing the desk
  e-mail at yourself in `backend/fixtures/operators.json` on a staging box, never on
  production.
- Inbound: reply to that mail; the reply must appear on the Antwort screen within a
  minute. Postmark's inbound stream page shows every delivery attempt and our response
  code.

## Where the secrets live

`deploy/.env` and `deploy/secrets/` are git-ignored. Rotate `ADMIN_TOKEN` and
`INBOUND_SECRET` by editing `.env` and `docker compose up -d api`; rotate the Postmark
token in Postmark, then in `.env`.
