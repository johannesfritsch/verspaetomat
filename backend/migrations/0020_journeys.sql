-- Journeys: a destination, a planned itinerary snapshot and one or more legs (rides).
-- Passenger rights compensate the delay at the final destination, so the incident
-- comes from the journey, not from a leg. See docs/17-journeys.md.

create type journey_status as enum ('riding', 'transfer', 'arrived', 'abandoned');

create table journeys (
    id                        uuid primary key,
    customer_id               uuid not null references customers(id) on delete cascade,
    origin_station_id         text not null,
    origin_station_name       text not null,
    destination_station_id    text not null,
    destination_station_name  text not null,
    -- The itinerary as planned at check-in: evidence of what the timetable promised.
    itinerary                 jsonb not null,
    -- The effective plan: the original legs, replaced from the transfer on after a re-plan.
    plan                      jsonb not null,
    planned_departure         timestamptz not null,
    planned_arrival           timestamptz not null,
    status                    journey_status not null default 'riding',
    current_leg               integer not null default 1,
    next_leg                  jsonb,
    transfer_deadline         timestamptz,
    actual_arrival            timestamptz,
    final_delay_min           integer,
    missed_connection         boolean not null default false,
    incomplete                boolean not null default false,
    cancelled                 boolean not null default false,
    points                    integer not null default 0,
    ticket                    ticket_type not null,
    created_at                timestamptz not null default now(),
    finalised_at              timestamptz,
    dismissed_at              timestamptz
);
create index journeys_customer_idx on journeys (customer_id, created_at desc);
create index journeys_open_idx on journeys (status) where status in ('riding', 'transfer');

alter table rides
    add column journey_id            uuid references journeys(id) on delete set null,
    add column leg_no                integer,
    add column transfer_station_id   text,
    add column transfer_station_name text;
create index rides_journey_idx on rides (journey_id, leg_no);

alter table incidents add column journey_id uuid references journeys(id) on delete set null;
