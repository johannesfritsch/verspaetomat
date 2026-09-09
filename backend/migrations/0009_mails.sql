create type mail_direction as enum ('out', 'inbound');
create type mail_outcome as enum ('accepted', 'question', 'rejected', 'bounce', 'other');

create table mails (
    id            uuid primary key,
    customer_id   uuid not null references customers(id) on delete cascade,
    claim_id      uuid references claims(id) on delete set null,
    direction     mail_direction not null,
    message_id    text,
    in_reply_to   text,
    from_addr     text not null,
    to_addr       text not null,
    bcc_addr      text,
    subject       text not null,
    body          text not null,
    attachments   jsonb not null default '[]',
    outcome       mail_outcome,
    amount_cents  bigint,
    dry_run       boolean not null default false,
    forwarded_at  timestamptz,
    occurred_at   timestamptz not null default now()
);
create index mails_customer_idx on mails (customer_id, occurred_at desc);
