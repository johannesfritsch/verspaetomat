-- Stellwerk: a simulated position per customer. Overrides the phone's GPS for "nearby stations".
create table sim_customer_location (
    customer_id uuid primary key references customers(id) on delete cascade,
    lat         double precision not null,
    lon         double precision not null,
    label       text not null default '',
    updated_at  timestamptz not null default now()
);
