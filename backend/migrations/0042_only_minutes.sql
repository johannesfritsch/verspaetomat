-- #74: only minutes. What was called Geduldspunkte was one point per minute late, with two
-- exceptions: a cancellation counted 60 and a ride entered afterwards (Nachtrag) counted 1. Both
-- are minute rules now (`rules::counted_minutes`, docs/47): a cancellation counts at least 60
-- minutes, a Nachtrag its own minutes — it stays off the boards, which rank only rides with a
-- location fix, and a Nachtrag never has one.
--
-- The `points` columns keep their name, so no query and no older build breaks, and hold the
-- counted minutes. This sets the Nachträge that were stored with 1, and rebuilds `waited_minutes`
-- (#71) on the same column, so every figure called „minutes" is one number by construction.
comment on column rides.points is 'Counted minutes (#74): the delay, at least 60 for a cancellation. Named before points were dropped.';
comment on column journeys.points is 'Counted minutes (#74): the delay at the destination, at least 60 for a cancellation.';

update rides
   set points = case when cancelled then greatest(60, coalesce(final_delay_min, 0)) else greatest(coalesce(final_delay_min, 0), 0) end
 where nachtrag and status = 'arrived';

drop view waited_minutes;
create view waited_minutes as
    select j.customer_id, j.id as journey_id, null::uuid as ride_id,
           j.points as minutes, j.created_at as started_at
    from journeys j
    where j.status = 'arrived'
  union all
    select r.customer_id, r.journey_id, r.id,
           r.points, r.checked_in_at
    from rides r
    where r.status = 'abandoned' and r.points > 0
  union all
    select r.customer_id, null::uuid, r.id,
           r.points, r.checked_in_at
    from rides r
    where r.journey_id is null and r.status = 'arrived';
