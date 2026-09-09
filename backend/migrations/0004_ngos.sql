create table ngos (
    id             text primary key,
    name           text not null,
    tagline        text not null,
    story          jsonb not null default '[]',
    account_holder text not null,
    iban           text not null,
    donation_url   text not null,
    last_report    date,
    active         boolean not null default true,
    consent_date   date,
    seed_confirmed_cents bigint not null default 0,  -- history before this system
    seed_submitted_cents bigint not null default 0
);
