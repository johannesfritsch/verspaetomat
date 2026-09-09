//! The Stellwerk layer: a train-data source that passes Transitous through and applies
//! per-trip overrides (extra delay, cancellation, a time shift into the past). The follower
//! and the API both read through it, so a simulated delay is real for the whole system.

use std::collections::HashMap;
use std::sync::RwLock;

use anyhow::Result;
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

use super::transitous::TransitousClient;
use super::{DepartureInfo, StopInfo, TripInfo};

#[derive(Debug, Clone, Default, Serialize, Deserialize, sqlx::FromRow)]
pub struct TripOverride {
    pub trip_id: String,
    pub extra_delay_min: i32,
    pub cancelled: bool,
    pub time_shift_secs: i64,
}

pub struct TrainSource {
    inner: TransitousClient,
    overrides: RwLock<HashMap<String, TripOverride>>,
}

impl TrainSource {
    pub fn new(inner: TransitousClient) -> Self {
        Self { inner, overrides: RwLock::new(HashMap::new()) }
    }

    pub async fn load_overrides(&self, pool: &PgPool) -> Result<()> {
        let rows: Vec<TripOverride> = sqlx::query_as("select trip_id, extra_delay_min, cancelled, time_shift_secs from sim_trip_overrides").fetch_all(pool).await?;
        let mut map = self.overrides.write().unwrap();
        map.clear();
        for r in rows {
            map.insert(r.trip_id.clone(), r);
        }
        Ok(())
    }

    pub fn get_override(&self, trip_id: &str) -> Option<TripOverride> {
        self.overrides.read().unwrap().get(trip_id).cloned()
    }

    pub fn all_overrides(&self) -> Vec<TripOverride> {
        let mut v: Vec<_> = self.overrides.read().unwrap().values().cloned().collect();
        v.sort_by(|a, b| a.trip_id.cmp(&b.trip_id));
        v
    }

    /// Upsert an override in the database and in memory.
    pub async fn set_override(&self, pool: &PgPool, o: TripOverride) -> Result<()> {
        sqlx::query(
            "insert into sim_trip_overrides (trip_id, extra_delay_min, cancelled, time_shift_secs) values ($1,$2,$3,$4)
             on conflict (trip_id) do update set extra_delay_min = excluded.extra_delay_min, cancelled = excluded.cancelled,
             time_shift_secs = excluded.time_shift_secs, updated_at = now()",
        )
        .bind(&o.trip_id)
        .bind(o.extra_delay_min)
        .bind(o.cancelled)
        .bind(o.time_shift_secs)
        .execute(pool)
        .await?;
        self.overrides.write().unwrap().insert(o.trip_id.clone(), o);
        Ok(())
    }

    pub async fn clear_override(&self, pool: &PgPool, trip_id: &str) -> Result<()> {
        sqlx::query("delete from sim_trip_overrides where trip_id = $1").bind(trip_id).execute(pool).await?;
        self.overrides.write().unwrap().remove(trip_id);
        Ok(())
    }

    pub async fn clear_all(&self, pool: &PgPool) -> Result<()> {
        sqlx::query("delete from sim_trip_overrides").execute(pool).await?;
        self.overrides.write().unwrap().clear();
        Ok(())
    }

    // -- the source API, same shape as TransitousClient --------------------------------

    pub async fn nearby_stops(&self, lat: f64, lon: f64) -> Result<Vec<StopInfo>> {
        self.inner.nearby_stops(lat, lon).await
    }

    pub async fn search_stops(&self, text: &str) -> Result<Vec<StopInfo>> {
        self.inner.search_stops(text).await
    }

    pub async fn departures(&self, stop_id: &str, n: usize) -> Result<Vec<DepartureInfo>> {
        let mut deps = self.inner.departures(stop_id, n).await?;
        let map = self.overrides.read().unwrap();
        if map.is_empty() {
            return Ok(deps);
        }
        for d in deps.iter_mut() {
            if let Some(o) = map.get(&d.trip_id) {
                let shift = Duration::seconds(o.time_shift_secs);
                d.delay_min += o.extra_delay_min as i64;
                d.live_departure = Some(d.live_departure.unwrap_or(d.planned_departure) + Duration::minutes(o.extra_delay_min as i64) - shift);
                d.planned_departure -= shift;
                d.cancelled |= o.cancelled;
                d.realtime = true;
            }
        }
        Ok(deps)
    }

    pub async fn trip(&self, trip_id: &str) -> Result<TripInfo> {
        let mut t = self.inner.trip(trip_id).await?;
        let o = match self.get_override(trip_id) {
            Some(o) => o,
            None => return Ok(t),
        };
        let extra = Duration::minutes(o.extra_delay_min as i64);
        let shift = Duration::seconds(o.time_shift_secs);
        let bump = |live: Option<DateTime<Utc>>, sched: Option<DateTime<Utc>>| -> Option<DateTime<Utc>> {
            live.or(sched).map(|t| t + extra - shift)
        };
        for s in t.stops.iter_mut() {
            s.live_arrival = bump(s.live_arrival, s.scheduled_arrival);
            s.live_departure = bump(s.live_departure, s.scheduled_departure);
            s.scheduled_arrival = s.scheduled_arrival.map(|x| x - shift);
            s.scheduled_departure = s.scheduled_departure.map(|x| x - shift);
        }
        t.cancelled |= o.cancelled;
        t.realtime = true;
        Ok(t)
    }
}
