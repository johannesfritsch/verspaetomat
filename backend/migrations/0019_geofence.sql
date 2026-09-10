-- Station geofencing (docs/15): the app registers the customer's frequent stations as regions.
-- Coordinates of the from-station are stored at check-in so the set can be computed server-side.
alter table rides add column from_lat double precision, add column from_lon double precision;

-- Background is the default for new customers; existing rows keep their choice.
alter table customers alter column loc_mode set default 'always';
alter table customers add column nudge_enabled boolean not null default true;
alter table customers add column quiet_from time default '22:00';
alter table customers add column quiet_to time default '06:00';
