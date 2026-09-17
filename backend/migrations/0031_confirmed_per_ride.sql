-- What a desk actually paid, per ride, and who read the mail that said so.
--
-- A confirmed ride used to count at the amount we had claimed for it. That is right when the desk
-- pays exactly the claim and wrong every other time: a desk that pays for one ride and refuses the
-- other, or pays 3,00 EUR where we asked for 4,50 EUR, would still have put the full claim onto the
-- passenger's sum and onto a Verein's public total. So a confirmed ride carries the figure the desk
-- wrote, and every total reads that figure first. Null on rides confirmed before this existed,
-- where the claimed amount is the only figure there is.
alter table incidents add column confirmed_cents bigint;

comment on column incidents.confirmed_cents is 'what the desk wrote it pays for this ride; totals use it before amount_cents';

-- Who decided what an inbound mail means — the rules, or a named model — and what it saw. The
-- audit trail has one line per decision; this keeps the whole reading next to the mail, so a wrong
-- call can be traced to the sentence it was based on.
alter table mails add column read_by text;
alter table mails add column reading jsonb;

comment on column mails.read_by is '"rules" or "model:<snapshot>"; null for outbound mail and mail read before 0031';
comment on column mails.reading is 'the reader''s decision, its evidence and, for a model, the redacted text it was shown';

-- The same mail delivered twice — a provider retrying a webhook that was still reading — is one
-- mail. A second delivery must not be read again, because a model can read it differently.
create unique index mails_inbound_message_id on mails (message_id) where direction = 'inbound' and message_id is not null;

-- Who may answer for a desk. A reply address is known to the desk and to the passenger, who gets a
-- copy of every claim; without this, anybody holding it could write "wir überweisen 1,50 EUR" and
-- confirm money. Only mail from these domains can accept or refuse a claim; everything else is
-- recorded and left for a human.
alter table mail_routes add column reply_from text;

comment on column mail_routes.reply_from is 'comma-separated sender domains whose mail may accept or refuse a claim; null means the domain of to_address';

-- What the receiving side verified about the sender: the provider's own SPF, DKIM and spam-test
-- headers, and whether one of them passes for the From domain. A From header is only text; without
-- this, anybody's mail server can write "From: antwort@<desk domain>".
alter table mails add column sender_auth jsonb;

comment on column mails.sender_auth is 'the topmost Received-SPF, Authentication-Results and X-Spam-Tests values and whether one passes aligned with From; null for outbound and for mail read before 0031';
