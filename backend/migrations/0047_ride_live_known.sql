-- #78: whether a ride's live delay comes from a live forecast. Without realtime Transitous repeats
-- the timetable as the live times, so „no live data" and „on time" were the same 0 minutes and the
-- app said „pünktlich" for both. The follower and the check-in write it; the app says „pünktlich"
-- only when it is true.
--
-- Null: nobody knows — rides from before this column. Builds that do not read it carry on as before.

alter table rides add column live_known boolean;
