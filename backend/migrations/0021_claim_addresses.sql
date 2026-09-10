-- docs/18 §4: mail belongs to a claim. Every claim gets its own reply address at send time
-- (antrag-<8 hex>@RELAY_DOMAIN); inbound mail is routed by it first. Unread state per mail.
alter table claims add column reply_address text unique;
alter table mails add column seen_at timestamptz;
create index mails_unread_idx on mails (customer_id) where direction = 'inbound' and seen_at is null;
