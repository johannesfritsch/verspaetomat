-- docs/23 §3: a journey left riding or transfer for more than three hours past its planned
-- arrival is almost certainly over. We ask once, and remember that we asked.
alter table journeys add column stale_asked_at timestamptz;
