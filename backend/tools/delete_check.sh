#!/usr/bin/env bash
# Builds a customer with everything in it, deletes it via DELETE /v1/me, checks nothing is left.
set -euo pipefail
API=${API:-http://127.0.0.1:8080}; ADM='x-admin-token: stellwerk'
cd "$(dirname "$0")/.." && trap "rm -f ticket.png" EXIT
auth=$(curl -sf -X POST $API/v1/devices -H 'content-type: application/json' -d '{}')
id=$(echo "$auth" | python3 -c 'import json,sys;print(json.load(sys.stdin)["device_id"])')
tok=$(echo "$auth" | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])')
H="authorization: Bearer $tok"
curl -sf $API/v1/me -H "$H" >/dev/null
curl -sf -X PUT $API/v1/me/personal-data -H "$H" -H 'content-type: application/json' -d '{"name":"Lösch Test","address":"Weg 1, 50667 Köln","email":"loesch@example.org","ticket_number":"T-1"}' >/dev/null
curl -sf $API/v1/me/recovery-code -H "$H" >/dev/null
for d in 3 4 5; do curl -sf -X POST "$API/admin/customers/$id/backdate" -H "$ADM" -H 'content-type: application/json' -d "{\"from\":\"Köln Hbf\",\"to\":\"Bonn Hbf\",\"delay_minutes\":70,\"days_ago\":$d}" >/dev/null; done
printf '\x89PNG\r\n\x1a\n0000' > ticket.png
up=$(curl -sf -X POST $API/v1/uploads -H "$H" -F kind=ticket -F "file=@ticket.png;type=image/png" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("id") or d.get("upload_id"))')
desk=$(psql verspaetomat -Atc "select desk from incidents where customer_id='$id' limit 1")
claim=$(curl -sf -X POST $API/v1/claims/draft -H "$H" -H 'content-type: application/json' -d "{\"desk\":\"$desk\"}" | python3 -c 'import json,sys;d=json.load(sys.stdin);print((d.get("claim") or d)["id"])')
curl -sf -X PATCH $API/v1/claims/$claim -H "$H" -H 'content-type: application/json' -d "{\"attachments\":[{\"upload_id\":\"$up\",\"label\":\"x\"}]}" >/dev/null
path=$(psql verspaetomat -Atc "select coalesce(path,'') from uploads where id='$up'")
q="select (select count(*) from rides where customer_id='$id')||' rides, '||(select count(*) from incidents where customer_id='$id')||' incidents, '||(select count(*) from claims where customer_id='$id')||' claims, '||(select count(*) from uploads where customer_id='$id')||' uploads, '||(select count(*) from audit_log where entity_id in (select id from claims where customer_id='$id') or entity_id in (select id from incidents where customer_id='$id'))||' audit'"
echo "before: $(psql verspaetomat -Atc "$q")  file: ${path:-none} $( [ -n "$path" ] && [ -f "uploads/$path" ] && echo present)"
claimid=$claim
echo "delete: $(curl -sf -X DELETE $API/v1/me -H "$H")"
echo "after:  $(psql verspaetomat -Atc "select (select count(*) from devices where id='$id')+(select count(*) from customers where id='$id')+(select count(*) from rides where customer_id='$id')+(select count(*) from incidents where customer_id='$id')+(select count(*) from claims where customer_id='$id')+(select count(*) from uploads where customer_id='$id')+(select count(*) from mails where customer_id='$id')+(select count(*) from audit_log where entity_id='$claimid')||' rows left'")  file: $( [ -n "$path" ] && [ -f "uploads/$path" ] && echo STILL THERE || echo gone)"
echo "token after: $(curl -s -o /dev/null -w '%{http_code}' $API/v1/me -H "$H")"
