-- Feature flags (#41): #40's one switch, generalised. One row per flag.
--
-- backend/src/flags.rs is the source of truth for WHICH flags exist and what each defaults to;
-- this table only holds what a human has said since. A missing row, a key no Rust item claims,
-- and a value of the wrong JSON type all mean the same thing: the default.
--
-- And the default is the rule 0037 wrote down, kept here verbatim: FALSE IS THE BEHAVIOUR THAT
-- ALREADY SHIPPED. A flag is read as "somebody has positively said the new path is safe here",
-- never as "nobody has said it is not". `BoolFlag` therefore has no default field at all.
--
-- A flag lands on a phone the next time the app is foregrounded, and not before: the native
-- background layer only learns a value when Dart calls `configure`. That is not fixable from
-- here, and it is exactly why the default has to be the shipped behaviour — the worst a stale
-- phone can do is keep doing what its own build already did.
--
-- A flag never governs money. backend/src/rules.rs owns every amount, every readiness and every
-- payee, and nothing here may reach them.
--
-- app_switches (0037) is NOT touched and NOT migrated. handlers::geofence still reads it, and
-- the wire field `stations_local` on GET /v1/me/geofence stays byte-identical for the builds in
-- TestFlight. Moving that call site onto this table is a separate, later step.
create table flags (
    key        text primary key,
    kind       text not null check (kind in ('bool', 'int', 'string')),
    -- What a human last set globally, as JSON of `kind`. Seeded from the Rust default.
    value      jsonb not null,
    -- Null: `value` applies to everybody. Set: `value` applies to the customers whose stable
    -- bucket falls below it, in basis points, and everybody else gets the default.
    rollout_bp integer check (rollout_bp between 0 and 10000),
    -- Set by the startup reconcile when no descriptor in flags.rs claims this key any more. An
    -- orphan is never loaded into the snapshot and never served; the row stays so the value is
    -- still readable and the history still joins.
    orphan     boolean not null default false,
    updated_at timestamptz not null default now()
);

-- Per-customer overrides, on the row every authenticated request has already loaded
-- (src/auth.rs: `select c.*`). One JSON object per customer, not one row per customer per flag:
-- reading an override costs no query, and a customer without one costs an empty object. Same
-- shape as muted_stations (0017).
alter table customers
    add column flag_overrides jsonb not null default '{}'::jsonb
        constraint customers_flag_overrides_is_object check (jsonb_typeof(flag_overrides) = 'object');

-- Who changed what, when. Deliberately NOT audit_log (0011): that table is the status-transition
-- record of rides, incidents, claims and mails, it is evidence in a Fahrgastrechte dispute, and
-- its entity_id is `uuid not null`, which a flag key is not. Never pruned: ten changes a day for
-- ten years is 36,500 rows, about 7 MB. No foreign key on customer_id — nothing in this codebase
-- deletes a customers row (both `forget` and `delete_me` delete only from `devices`), so a
-- referential action here would be decoration.
create table flag_log (
    id          bigserial primary key,
    key         text not null,
    customer_id uuid,                     -- null for a global change
    -- One person's override is the bare value; a global change is the whole setting,
    -- {"value": …, "rollout_bp": …}, because ending a rollout leaves the value alone and a
    -- history that records that as "true → true" hides what happened.
    from_value  jsonb,                    -- null: there was nothing here
    to_value    jsonb,                    -- null: the value or the override was removed
    reason      text,
    at          timestamptz not null default now()
);
create index flag_log_key_idx on flag_log (key, at desc);

-- No index on flag_overrides. The only query that would use one is an admin listing run
-- approximately never. If it ever hurts:
--   create index concurrently customers_flag_overrides_idx on customers using gin (flag_overrides)
--     where flag_overrides <> '{}'::jsonb;
-- is one line, at any time, with no downtime.
