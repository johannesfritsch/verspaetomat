-- Devices: one anonymous identity per installation. No accounts.
create table devices (
    id            uuid primary key,
    token_hash    bytea not null unique,          -- sha256 of the bearer token
    recovery_hash bytea,                           -- sha256 of the recovery code, set at first claim
    created_at    timestamptz not null default now(),
    last_seen_at  timestamptz not null default now()
);
