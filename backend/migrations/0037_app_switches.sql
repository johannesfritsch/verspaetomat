-- Switches that turn a shipped behaviour off from the server, without a new build (#40).
--
-- The geofence layer is the part of this app with no tests and the longest repair loop: Kotlin
-- has none at all, the Swift assertion at app/ios/Runner/Geofence.swift:222 has been failing
-- unnoticed since docs/30 because nothing runs the Swift tests, and a mistake there does not
-- crash — it shows up as a nudge that does not come, on somebody else's phone, days later.
-- docs/42 records what that costs when there is no switch: "Vom Server aus ist das nicht zu
-- heilen — der Satz hängt an keinem Feld", and the only cure left was expiring eleven builds.
--
-- One row, and one rule for every column that will ever be added here: FALSE IS THE BEHAVIOUR
-- THAT ALREADY SHIPPED. A switch is read as "somebody has positively said the new path is safe
-- here", never as "nobody has said it is not".
create table app_switches (
    id             integer primary key default 1 check (id = 1),
    -- Whether the NATIVE background layer answers "which stations are near me" from the .vst
    -- extract on disk (docs/45) instead of GET /v1/stations/nearby. This governs the native
    -- layer and nothing else: Dart's foreground lookup has had no server rung since #39
    -- (app/lib/repo/http_repository.dart, a compile-time constant), and no server-side flag can
    -- give a release build back a call its binary does not contain.
    stations_local boolean not null default false,
    updated_at     timestamptz not null default now()
);
insert into app_switches (id) values (1) on conflict do nothing;
