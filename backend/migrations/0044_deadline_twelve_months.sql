-- #66, docs/49 §1: a case's hard deadline is twelve months after the ride, not three. Three months
-- is the EU deadline for complaints (Art. 28(2)); a compensation claim is time-barred only one year
-- after the ticket's validity ends (CIV Art. 60, BB A.9.5, DT-A 8.2.8). Twelve months after the
-- ride is never later than that. Three months stays as what we aim for (`rules::aim_date`).
--
-- Every open case gets the new date, and its deadline warning may come again. A case that expired
-- under the old rule, was never sent and is still inside the twelve months is open again; the next
-- status refresh sorts it into its bundle. The audit log says why.
--
-- The deadline warning (`warned_at`) now comes 21 days before the hard deadline, eleven months
-- after the ride. What used to be its moment gets a reminder of its own: 21 days before the aim,
-- once, and only for a case whose bundle can go out (`aim_nudged_at`, scanner.rs).

alter table incidents add column aim_nudged_at timestamptz;

update incidents
   set legal_deadline = (ride_date + interval '12 months')::date,
       warned_at = null
 where status in ('gesammelt', 'bereit', 'gedeckelt');

with reopened as (
    update incidents i
       set status = 'gesammelt',
           legal_deadline = (i.ride_date + interval '12 months')::date,
           warned_at = null
     where i.status = 'verfallen'
       and i.discarded_at is null
       and (i.ride_date + interval '12 months')::date >= current_date
       and not exists (
           select 1 from claim_incidents ci join claims c on c.id = ci.claim_id
            where ci.incident_id = i.id and c.status <> 'draft')
    returning i.id
)
insert into audit_log (entity, entity_id, from_status, to_status, reason)
select 'incident', id, 'verfallen', 'gesammelt', 'deadline is twelve months (#66)' from reopened;
