-- A route carries the postal address too, so a screen can show the whole destination and not just
-- an e-mail. The operator directory still holds the railway's published postal address as a
-- product fact; this one is where THIS route's paper would go, which during a rehearsal is not the
-- same place. Null means "no paper route set", and the screen falls back to the directory.
alter table mail_routes add column postal_address text;

comment on column mail_routes.postal_address is 'where this route''s paper would go; null falls back to the operator directory';
