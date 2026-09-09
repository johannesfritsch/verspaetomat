-- The customer acknowledged the arrival summary; current_ride stops returning it.
alter table rides add column dismissed_at timestamptz;
