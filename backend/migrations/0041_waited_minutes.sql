-- #71: „Minuten hast du gewartet" on Home and the Geduldspunkte on Ich disagreed (158 against 146).
-- The minutes were summed ride by ride, so a journey with a change counted the first train's delay
-- at the change as well — although the delay counts at the destination, not per train (docs/17) —
-- and a journey given up counted nothing, although its waiting earns points (docs/22 §1).
--
-- One definition, the one the points already follow, read by every figure that says „minutes":
--   * a journey that arrived: its delay at the destination, already capped for a pause of one's
--     own (docs/21 §2);
--   * a leg given up on: the waiting on that train;
--   * a ride of its own, from before journeys or entered afterwards: its delay.
create view waited_minutes as
    select j.customer_id, j.id as journey_id, null::uuid as ride_id,
           coalesce(j.final_delay_min, 0) as minutes, j.created_at as started_at
    from journeys j
    where j.status = 'arrived'
  union all
    select r.customer_id, r.journey_id, r.id,
           coalesce(r.final_delay_min, 0), r.checked_in_at
    from rides r
    where r.status = 'abandoned' and r.points > 0
  union all
    select r.customer_id, null::uuid, r.id,
           coalesce(r.final_delay_min, 0), r.checked_in_at
    from rides r
    where r.journey_id is null and r.status = 'arrived';
