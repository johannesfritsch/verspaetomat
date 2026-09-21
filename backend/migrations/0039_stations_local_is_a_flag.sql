-- #41's last step: `stations_local` stops being a bespoke switch and becomes an ordinary flag.
--
-- #40 built that switch by hand — a column, a one-row table, a body struct, a branch, a query in
-- `handlers::geofence`, two admin routes, a `stellwerk switch` arm — because there was no system
-- to put it in. #41 built the system. Leaving the first switch outside it would have meant
-- maintaining both for ever, and moving it is the only thing that proves the system can hold a
-- switch that matters. 0038 said this would be a separate, later step. This is it.
--
-- **The wire does not change.** GET /v1/me/geofence still carries `stations_local`: same name,
-- same type, same meaning, still present on every response. Only the server's source for the
-- value moves, from this table to the flag snapshot. Builds 64 to 67 read that field and have
-- never cared where it came from.
--
-- Carrying the value across: only a `true` is copied, and 0037's own rule is why. FALSE IS THE
-- BEHAVIOUR THAT ALREADY SHIPPED — a `false` here records that nobody ever said yes, which is
-- exactly what a flag at its default already means. Copying it would be copying the absence of
-- information, and it would overwrite a flag somebody had meanwhile set. In production both
-- sides are false today, so this moves nothing there; it matters on a machine where the switch
-- was flipped on and the flag was never touched.
--
-- `on conflict` rather than a plain update, because a database that never ran the startup
-- reconcile has no row yet; `rollout_bp` is deliberately left alone, so a flag that is already
-- rolling out to a percentage keeps rolling out to that percentage rather than jumping to
-- everybody.
insert into flags (key, kind, value, rollout_bp)
select 'stations_local', 'bool', 'true'::jsonb, null
  from app_switches
 where id = 1 and stations_local
    on conflict (key) do update set value = 'true'::jsonb, orphan = false, updated_at = now();

-- Same shape as a global write from `admin::flag_set`: the whole setting, not the bare value.
insert into flag_log (key, customer_id, from_value, to_value, reason)
select 'stations_local',
       null,
       jsonb_build_object('value', to_jsonb(false), 'rollout_bp', null),
       jsonb_build_object('value', to_jsonb(true), 'rollout_bp', null),
       'aus app_switches (0037) übernommen, beim Umzug auf flags (#41)'
  from app_switches
 where id = 1 and stations_local;

-- And the table goes. One row holding a boolean nobody reads is not worth two places to look,
-- and a dead table is precisely the debt the flag system exists to stop accumulating.
drop table app_switches;
