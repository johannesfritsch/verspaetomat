-- #61: the shelf is listed in the order of the fixture, not by id. By id, `minuten-16000` came
-- before `minuten-2000`. The seed writes each badge's index in `fixtures/badges.json`.
alter table badges add column position integer not null default 0;
