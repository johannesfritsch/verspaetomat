create table teams (
    id           uuid primary key,
    name         text not null,
    invite_token text not null unique,
    created_by   uuid not null references customers(id) on delete cascade,
    created_at   timestamptz not null default now()
);
create table team_members (
    team_id     uuid not null references teams(id) on delete cascade,
    customer_id uuid not null references customers(id) on delete cascade,
    joined_at   timestamptz not null default now(),
    primary key (team_id, customer_id)
);
