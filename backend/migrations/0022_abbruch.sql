-- docs/21: a journey records why it ended, an incident can be taken out of a bundle by the
-- passenger, and "Geduld ist eine Tugend" goes (it fired at the same moment as minuten-1000).
alter table journeys add column end_reason text;
alter table incidents add column discarded_at timestamptz;
alter table incidents add column discard_reason text;
create index incidents_active_idx on incidents (customer_id) where discarded_at is null;

delete from badge_awards where badge_id = 'geduld';
delete from badges where id = 'geduld';
