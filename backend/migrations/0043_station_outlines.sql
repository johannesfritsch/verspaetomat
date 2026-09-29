-- Station premises from OpenStreetMap (issue #64, docs/48): per station its premise, the ring the
-- phone watches for arriving and leaving, and the touch points whose entry is the nudge.
--
-- A table of its own on purpose, never columns of `stations`: the rows are derived from OSM and
-- stand under the ODbL, whose share-alike reaches this database and not the station names and
-- ids from DELFI next to it (docs/48, „Was die ODbL verlangt"). `stellwerk stations outlines`
-- builds them on a laptop and replaces the whole table in one transaction; nothing edits a row.
create table station_outlines (
    station_id     integer          primary key references stations(id) on delete cascade,
    -- [[lat, lon], …], counter-clockwise, at most 24 corners.
    outline        jsonb            not null,
    ring_lat       double precision not null,
    ring_lon       double precision not null,
    ring_radius_m  real             not null,
    -- [{"lat": …, "lon": …, "r": …}, …], one to six, each at least 120 m.
    touch          jsonb            not null,
    -- The OSM objects the premise is built from ("w123", "r45", "n6"): for attribution, for
    -- tracing a wrong premise back to what is mapped, and for the published file.
    osm_ids        text[]           not null,
    -- The day of the OSM extract the row was built from.
    osm_timestamp  date,
    imported_at    timestamptz      not null default now()
);

comment on table station_outlines is
    'Derived from OpenStreetMap, © OpenStreetMap contributors, ODbL 1.0 (docs/48). Kept apart from stations for the licence.';
