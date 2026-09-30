-- #66, docs/49 §5.3–5.4, docs/50 phase 2: the passenger's tickets. A ticket is a contract — the
-- D-Ticket Abo, a BahnCard 100, a Monatskarte, one Sparpreis for one direction — of one product of
-- the fare catalogue (fixtures/fares.toml). Journeys, rides, cases and claims point at the ticket
-- they were made with; the old `ticket` enum columns stay, derived from the product, for builds
-- that read nothing else.

create table tickets (
    id                        uuid primary key,
    customer_id               uuid not null references customers(id) on delete cascade,
    -- A product id of the catalogue. Not a foreign key: the catalogue is not a table.
    product                   text not null,
    -- Made from a legacy "Andere Zeitkarte": which Verbund it is was never asked. The Antrag asks.
    product_unsure            boolean not null default false,
    first_class               boolean not null default false,
    label                     text,
    -- Abo, Zeitkarten or BahnCard number, or the booking number of a single ticket (EU form 3.2.7).
    number                    text,
    -- Auftragsnummer: tickets sharing one are one contract (BB A.1.3.4).
    booking_ref               text,
    -- BahnCard 100 only: the DB form identifies it by number and date of birth.
    birth_date                date,
    -- What was paid. A single ticket: the fare of its direction. A season ticket: the price of the
    -- window its cap is counted in (the month for the D-Ticket, the whole validity otherwise).
    -- Null = not entered: no amount for a single ticket, the list price for a season ticket's cap.
    price_cents               bigint,
    valid_from                date,
    -- Null = open-ended (an Abo).
    valid_until               date,
    -- Single tickets and Streckenzeitkarten: the stations of the ticket, our ids (vs:…).
    origin_station_id         text,
    origin_station_name       text,
    destination_station_id    text,
    destination_station_name  text,
    created_at                timestamptz not null default now(),
    -- A ticket someone no longer has. Its cases stay.
    archived_at               timestamptz
);
create index tickets_customer_idx on tickets (customer_id, created_at desc);

-- Which ticket covers which legs of a journey. One row per ticket; the app offers one ticket per
-- journey for now, the model carries a D-Ticket to Köln and a Sparpreis from there.
create table journey_tickets (
    journey_id  uuid not null references journeys(id) on delete cascade,
    ticket_id   uuid not null references tickets(id) on delete cascade,
    first_leg   integer not null default 1,
    -- Null = to the last leg.
    last_leg    integer,
    primary key (journey_id, ticket_id)
);
create index journey_tickets_ticket_idx on journey_tickets (ticket_id);

alter table rides add column ticket_id uuid references tickets(id) on delete set null;
alter table incidents
    add column ticket_id uuid references tickets(id) on delete set null,
    add column first_class boolean,
    -- The pot the case belongs to within its ticket (docs/49 §5.5); set with pots.
    add column window_key text;
alter table claims
    add column ticket_id uuid references tickets(id) on delete set null,
    add column window_key text,
    -- The pot as it was evaluated when the claim was built.
    add column breakdown jsonb;
