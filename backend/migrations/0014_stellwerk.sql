-- Stellwerk: server-side simulation. Overrides sit in front of the train-data source,
-- so the follower and the app see the same altered world. Dev and staging only.
create table sim_trip_overrides (
    trip_id         text primary key,
    extra_delay_min integer not null default 0,
    cancelled       boolean not null default false,
    time_shift_secs bigint  not null default 0,   -- subtracted from every stop time: > 0 moves the trip into the past
    updated_at      timestamptz not null default now()
);
create table sim_clock (
    id          integer primary key default 1 check (id = 1),
    offset_secs bigint not null default 0,
    updated_at  timestamptz not null default now()
);
insert into sim_clock (id, offset_secs) values (1, 0);
