-- docs/24 §3: the time-boxed global pause on station nudges. The per-station mute
-- ("Köln Hbf bleibt still") stays what it is; this is "leave me alone until 18:40", set
-- from Einstellungen or straight from the nudge notification. Null means no snooze.
-- A far-future value is the open-ended "bis ich sie wieder einschalte".
alter table customers add column nudge_snooze_until timestamptz;
