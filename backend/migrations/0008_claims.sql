create type claim_status as enum ('draft', 'sent', 'question', 'accepted', 'rejected', 'bounced');

create table claims (
    id                    uuid primary key,
    customer_id           uuid not null references customers(id) on delete cascade,
    desk                  text not null,
    ngo_id                text not null references ngos(id),
    account_holder        text not null,      -- snapshot at draft time
    iban                  text not null,
    ticket_months         text[] not null default '{}',
    status                claim_status not null default 'draft',
    signed_by             text,
    signed_at             timestamptz,
    sent_at               timestamptz,
    expected_reply_by     date,
    amount_claimed_cents  bigint not null default 0,
    amount_confirmed_cents bigint,
    closed_at             timestamptz,
    created_at            timestamptz not null default now()
);
create table claim_incidents (
    claim_id    uuid not null references claims(id) on delete cascade,
    incident_id uuid not null references incidents(id) on delete cascade,
    primary key (claim_id, incident_id)
);
create table uploads (
    id           uuid primary key,
    customer_id  uuid not null references customers(id) on delete cascade,
    kind         text not null,            -- ticket | signature | postal_reply
    content_type text not null,
    bytes        bytea not null,           -- object storage later
    created_at   timestamptz not null default now()
);
create table claim_attachments (
    claim_id  uuid not null references claims(id) on delete cascade,
    upload_id uuid not null references uploads(id) on delete cascade,
    label     text not null,               -- e.g. "Deutschlandticket 2026-08"
    primary key (claim_id, upload_id)
);
alter table incidents add constraint incidents_claim_fk foreign key (claim_id) references claims(id) on delete set null;
