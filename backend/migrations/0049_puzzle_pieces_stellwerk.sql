-- docs/51 §9c: pieces the Stellwerk puts into an account, so a picture can be tested without
-- riding. They are marked, because the daily cap of three counts only what journeys brought.
-- `journey_id` cannot tell: a piece stays when its journey is deleted, and then it is null too.

alter table puzzle_pieces add column stellwerk boolean not null default false;
