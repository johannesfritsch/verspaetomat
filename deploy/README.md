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

Two jobs: the API host, and mail for the relay addresses `fahrgast-XXXX@verspaetomat.de`.

| Record | Name | Value | Why |
|---|---|---|---|
| A | `api.verspaetomat.de` | the VPS IPv4 | Caddy gets its certificate for this name |
| AAAA | `api.verspaetomat.de` | the VPS IPv6 (if any) | same |
| MX | `verspaetomat.de` | `10 inbound.postmarkapp.com` | Railway replies to `fahrgast-*@` land at Postmark, which posts them to us |
| TXT | `verspaetomat.de` | `v=spf1 include:spf.mtasv.net -all` | SPF: Postmark may send as `@verspaetomat.de` |
| CNAME | `<selector>._domainkey.verspaetomat.de` | what Postmark shows under Sender Signatures → DKIM | DKIM: signatures on outbound mail |
| CNAME | `pm-bounces.verspaetomat.de` | `pm.mtasv.net` | Return-Path alignment (DMARC passes on the envelope sender) |
| TXT | `_dmarc.verspaetomat.de` | `v=DMARC1; p=quarantine; rua=mailto:dmarc@verspaetomat.de; adkim=s; aspf=s` | DMARC with reports; strict alignment because we control both |

Deutsche Bahn's Servicecenter is a large corporate mail system: SPF, DKIM and DMARC all
have to pass, or the claim mail lands in quarantine and nobody ever answers. Verify with
Postmark's "DNS check" and with `dig TXT verspaetomat.de` before the first real claim.

If SES instead of Postmark: SPF `include:amazonses.com`, DKIM via SES "Easy DKIM" (three
CNAMEs), inbound via SES receipt rule → SNS → HTTPS to the same webhook, and
`SMTP_URL=smtp://SMTP-USER:SMTP-PASS@email-smtp.eu-central-1.amazonaws.com:587`.

## 2. Mail provider (Postmark as the worked example)

1. **[you]** Servers → create a server "Verspätomat", Transactional stream.
2. **[you]** Sender Signatures → add domain `verspaetomat.de`, set the DKIM and Return-Path
   records from step 1, wait for both to verify.
3. **[you]** Server → API Tokens → copy one. Outbound over SMTP uses that token as both user
   and password: `SMTP_URL=smtps://TOKEN:TOKEN@smtp.postmarkapp.com:465`.
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
   `verspaetomat.de` so `fahrgast-anything@verspaetomat.de` is accepted (the MX record
   from step 1 makes Postmark the receiver). Every relay address is routed by the
   backend: it looks the customer up by the `To` address.

The secret in the URL is the only guard on the webhook; make it long and random.

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

Caddy answers 404 for `/admin/*` from the internet. Use the CLI inside the container:

```bash
docker compose exec api stellwerk customers
docker compose exec api stellwerk push Johannes "Testnachricht"
docker compose exec api stellwerk ngo-report bahnhofsmission /tmp/statement.csv
```

`STELLWERK_URL` and `ADMIN_TOKEN` are already set in the container's environment. From
your laptop, tunnel instead: `ssh -L 8080:127.0.0.1:8080 vps` will not work because the
port is not published on the host; use `docker compose exec` or publish `127.0.0.1:8080:8080`
on the api service if you want the tunnel.

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
cd /opt/verspaetomat && git pull
cd deploy && docker compose up -d --build api      # rebuilds only the API, Postgres and Caddy keep running
docker compose logs --tail 50 api                  # migrations applied, listening
```

Rolling back is `git checkout <previous> && docker compose up -d --build api`; migrations
are forward-only, so roll back only across commits without new migration files.

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
