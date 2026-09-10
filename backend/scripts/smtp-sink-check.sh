#!/usr/bin/env bash
# End-to-end check of the real SMTP path against a local sink: three check-ins on
# live departures, +68 each via Stellwerk, one claim with signature, sent with the
# EU form attached. Then the received MIME is inspected: From is the relay address,
# To the desk, the customer's private address only as a separate RCPT (a BCC), the
# PDF intact.
#
# Needs: a scratch backend started with
#   SMTP_URL=smtp://127.0.0.1:1025?starttls=no BIND=127.0.0.1:8092 DATABASE_URL=postgres://localhost/verspaetomat_pushtest cargo run
# and the sink:  python3 scripts/smtp-sink.py 127.0.0.1 1025 /tmp/sink
# Usage: API=http://127.0.0.1:8092 SINK=/tmp/sink scripts/smtp-sink-check.sh
set -euo pipefail
API="${API:-http://127.0.0.1:8092}"
SINK="${SINK:-/tmp/sink}"
ADMIN_TOKEN="${ADMIN_TOKEN:-stellwerk}"
STELLWERK="${STELLWERK:-$(dirname "$0")/../target/debug/stellwerk}"
export STELLWERK_URL="$API" ADMIN_TOKEN

say() { printf '\n== %s\n' "$*"; }
api() { curl -sf -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' "$@"; }

say "device"
DEV=$(curl -sf -X POST "$API/v1/devices")
TOKEN=$(jq -r .token <<<"$DEV"); CUST=$(jq -r .device_id <<<"$DEV")
echo "customer $CUST"
api -X PATCH "$API/v1/me" -d '{"nickname":"SmtpCheck","ticket":"deutschlandticket","ngo_id":"bahnhofsmission"}' >/dev/null
api -X PUT "$API/v1/me/push-token" -d '{"platform":"ios","token":"sink-check-token"}' >/dev/null
"$STELLWERK" locate "$CUST" "Köln Hbf" >/dev/null

say "three rides"
STATION=$(api "$API/v1/stations/nearby" | jq -r '.stations[0].id')
for n in 1 2 3; do
  DEP=$(api "$API/v1/stations/$STATION/departures" | jq -c '[.[] | select(.cancelled==false and .desk=="Servicecenter Fahrgastrechte" and (.category=="re" or .category=="rb" or .category=="s"))][0]')
  TRIP=$(jq -r .trip_id <<<"$DEP"); LINE=$(jq -r .line <<<"$DEP")
  STOPS=$(api "$API/v1/trips?trip_id=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$TRIP")")
  EXIT=$(jq -c '[.stops[] | select(.stop_id != null)] | last' <<<"$STOPS")
  api -X POST "$API/v1/rides" -d "$(jq -n --arg t "$TRIP" --arg s "$STATION" --argjson e "$EXIT" '{trip_id:$t, from_station_id:$s, from_station_name:"Köln Hbf", exit_station_id:$e.stop_id, exit_station_name:$e.name}')" >/dev/null
  "$STELLWERK" delay "$CUST" +68 >/dev/null
  "$STELLWERK" ff "$CUST" >/dev/null
  echo "ride $n: $LINE → $(jq -r .name <<<"$EXIT")"
  sleep 1
done

say "claim"
api -X PUT "$API/v1/me/personal-data" -d '{"name":"Johannes Test","address":"Venloer Straße 123, 50823 Köln","email":"johannes-private@example.org","ticket_number":"D-123456"}' >/dev/null
CLAIM=$(api -X POST "$API/v1/claims/draft" -d '{"desk":"Servicecenter Fahrgastrechte"}' | jq -r '.claim.id // .id')
api -X POST "$API/v1/claims/$CLAIM/sign" -d '{"typed_name":"Johannes Test"}' >/dev/null
SENT=$(api -X POST "$API/v1/claims/$CLAIM/send" -d '{}')
echo "send: $(jq -c '{status: (.claim.status // .status), relay: (.mail.from // .from // .relay_address)}' <<<"$SENT")"
sleep 2

say "received"
EML=$(ls -t "$SINK"/*.eml | head -1)
echo "file: $EML ($(wc -c <"$EML") bytes)"
grep -E '^X-Sink-|^From:|^To:|^Bcc:|^Subject:|^Message-ID:|^Content-Type: (multipart|application/pdf)|filename=' "$EML" | sed 's/^/  /'
if grep -q '^Bcc:' "$EML"; then echo "FAIL: Bcc header visible in the message"; exit 1; fi
RCPTS=$(grep -c '^X-Sink-Rcpt-To:' "$EML")
[ "$RCPTS" -eq 2 ] || { echo "FAIL: expected 2 RCPT TO (desk + BCC), got $RCPTS"; exit 1; }
grep -q '^X-Sink-Rcpt-To: <johannes-private@example.org>' "$EML" || { echo "FAIL: customer BCC not delivered as RCPT"; exit 1; }
grep -q '^X-Sink-Mail-From: <fahrgast-' "$EML" || { echo "FAIL: envelope sender is not the relay address"; exit 1; }

say "attachment"
python3 - "$EML" "$SINK" <<'PY'
import email, sys, os
from email import policy
raw = open(sys.argv[1], 'rb').read()
# strip the sink envelope block
body = raw.split(b"\r\n", 2)
while body[0].startswith(b"X-Sink-"):
    raw = raw[len(body[0]) + 2:]
    body = raw.split(b"\r\n", 2)
msg = email.message_from_bytes(raw, policy=policy.default)
text = None
for part in msg.walk():
    if part.get_content_type() == 'text/plain' and text is None:
        text = part.get_content()
    if part.get_content_type() == 'application/pdf':
        pdf = part.get_payload(decode=True)
        out = os.path.join(sys.argv[2], part.get_filename())
        open(out, 'wb').write(pdf)
        print(f"  {part.get_filename()}: {len(pdf)} bytes, header {pdf[:8]!r}, ends with EOF: {b'%%EOF' in pdf[-64:]}")
        assert pdf.startswith(b'%PDF-'), 'not a PDF'
        assert len(pdf) > 20000, 'PDF suspiciously small'
print("  text part starts:", (text or '')[:90].replace('\n', ' | '))
PY
say "ok"
