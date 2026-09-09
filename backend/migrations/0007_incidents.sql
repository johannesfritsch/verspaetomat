create type incident_status as enum ('gesammelt', 'bereit', 'eingereicht', 'bestaetigt', 'abgelehnt', 'verfallen', 'gedeckelt');

create table incidents (
    id             uuid primary key,
    customer_id    uuid not null references customers(id) on delete cascade,
    ride_id        uuid references rides(id) on delete set null,
    ride_date      date not null,
    line           text not null,
    from_name      text not null,
    to_name        text not null,
    delay_min      integer not null,
    amount_cents   bigint not null,
    ticket         ticket_type not null,
    operator       text not null,
    desk           text not null,
    status         incident_status not null default 'gesammelt',
    cancelled      boolean not null default false,
    self_entered   boolean not null default false,
    ngo_id         text not null references ngos(id),
    claim_id       uuid,
    fare_cents     bigint,
    legal_deadline date not null,
    warned_at      timestamptz,
    evidence       jsonb,
    created_at     timestamptz not null default now()
);
create index incidents_customer_idx on incidents (customer_id, ride_date desc);
create index incidents_open_idx on incidents (customer_id, desk) where status in ('gesammelt', 'bereit');
