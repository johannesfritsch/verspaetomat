create type ride_status as enum ('riding', 'arrived', 'abandoned');
create type train_category as enum ('s', 'rb', 're', 'fern', 'bus');

create table rides (
    id                 uuid primary key,
    customer_id        uuid not null references customers(id) on delete cascade,
    trip_id            text not null,                  -- Transitous trip id
    line               text not null,
    headsign           text not null default '',
    operator           text not null,                  -- our operator name (mapped) or the raw agency name
    category           train_category not null,
    from_station_id    text not null,
    from_station_name  text not null,
    exit_station_id    text not null,
    exit_station_name  text not null,
    planned_departure  timestamptz not null,
    planned_arrival    timestamptz not null,
    actual_arrival     timestamptz,
    ticket             ticket_type not null,
    status             ride_status not null default 'riding',
    live_delay_min     integer not null default 0,
    passed_stops       integer not null default 0,
    cause              text,
    final_delay_min    integer,
    cancelled          boolean not null default false,
    self_entered       boolean not null default false,
    nachtrag           boolean not null default false,
    location_verified  boolean not null default false,
    location_lat       double precision,
    location_lon       double precision,
    points             integer not null default 0,
    checked_in_at      timestamptz not null default now(),
    finalised_at       timestamptz,
    last_polled_at     timestamptz
);
create index rides_customer_idx on rides (customer_id, checked_in_at desc);
create index rides_riding_idx on rides (status) where status = 'riding';

-- Evidence: what the feed said, when. Kept for open incidents.
create table ride_snapshots (
    id         bigserial primary key,
    ride_id    uuid not null references rides(id) on delete cascade,
    fetched_at timestamptz not null default now(),
    source     text not null,
    payload    jsonb not null
);
create index ride_snapshots_ride_idx on ride_snapshots (ride_id, fetched_at desc);
