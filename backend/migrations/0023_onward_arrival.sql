-- docs/21 §2: a self-chosen pause does not count. When a journey is interrupted mid-way (the
-- passenger gives up on a train, or a connection is missed) we record the arrival the earliest
-- onward connection would have reached the destination at. The delay that is claimed is measured
-- against min(actual arrival, this) — the railway's share, never the passenger's own waiting.
alter table journeys add column earliest_onward_arrival timestamptz;
