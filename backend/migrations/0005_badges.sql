create table badges (
    id   text primary key,
    name text not null,
    rule text not null
);
create table badge_awards (
    customer_id uuid not null references customers(id) on delete cascade,
    badge_id    text not null references badges(id),
    ride_id     uuid,
    awarded_at  timestamptz not null default now(),
    primary key (customer_id, badge_id)
);
