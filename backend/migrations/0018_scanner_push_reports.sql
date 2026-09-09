-- Deadline scanner, push tokens, NGO report imports (10 September 2026).
-- incidents.warned_at exists since 0007; the scanner sets it once the 21-day warning went out.

-- Reply nudge: set once when a sent claim passes expected_reply_by without an inbound mail.
alter table claims add column nudged_at timestamptz;

-- Push token per installation. Delivery (APNs/FCM) is not wired; the token is only stored.
alter table devices add column push_platform text check (push_platform in ('ios', 'android'));
alter table devices add column push_token text;
alter table devices add column push_updated_at timestamptz;

-- Monthly NGO statements: one row per import, counts only; matched claims carry the outcome.
create table ngo_reports (
    id          uuid primary key,
    ngo_id      text not null references ngos(id),
    imported_at timestamptz not null default now(),
    rows        integer not null,
    matched     integer not null
);
create index ngo_reports_ngo_idx on ngo_reports (ngo_id, imported_at desc);
