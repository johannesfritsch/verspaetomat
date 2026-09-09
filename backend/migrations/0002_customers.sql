-- One customer per device. Personal data is filled at the first claim.
create type ticket_type as enum ('deutschlandticket', 'zeitkarte', 'einzelfahrkarte');
create type location_mode as enum ('never', 'while_using', 'always');

create table customers (
    id                  uuid primary key references devices(id) on delete cascade,
    nickname            text not null default 'Fahrgast',
    relay_address       text unique,
    -- personal data (nullable until the first claim)
    full_name           text,
    postal_address      text,
    email               text,
    ticket_number       text,
    first_class         boolean not null default false,
    -- settings
    ticket              ticket_type not null default 'deutschlandticket',
    ngo_id              text not null default 'bahnhofsmission',
    loc_mode            location_mode not null default 'while_using',
    notifications       boolean not null default true,
    show_on_boards      boolean not null default true,
    keep_correspondence boolean not null default false,
    traewelling_linked  boolean not null default false,
    onboarding_done     boolean not null default false,
    home_station_id     text,
    home_station_name   text,
    created_at          timestamptz not null default now()
);
