-- Stumme Bahnhöfe: stations where the customer never wants the nudge. Part of the account, not the phone.
alter table customers add column muted_stations jsonb not null default '[]';   -- [{"id": "...", "name": "..."}]
