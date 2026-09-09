-- Operator directory: who ran the train -> which claims desk. Content, maintained by hand.
create table operators (
    name           text primary key,
    aliases        text[] not null default '{}',   -- agency names as feeds spell them
    desk           text not null,
    postal_address text not null,
    email          text,
    accepts_email  boolean not null default false,
    last_verified  date,
    notes          text
);
create index operators_aliases_idx on operators using gin (aliases);
