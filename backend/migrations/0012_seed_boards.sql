-- Seeded board rows for the showcase until there are enough real users.
create table board_seed (
    scope  text not null,               -- line | city | germany
    rank   integer not null,
    name   text not null,
    points integer not null,
    primary key (scope, rank)
);
