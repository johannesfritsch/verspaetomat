//! The trip follower: polls every riding ride against the live trip, stores evidence,
//! updates the live delay and finalises the ride at the exit stop. It knows nothing about
//! incidents; it announces `RideFinalised` on a broadcast channel and the ledger listens.

use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result};
use chrono::{DateTime, Duration as ChronoDuration, Utc};
use sqlx::PgPool;
use tokio::sync::broadcast;
use uuid::Uuid;

use super::transitous::TransitousClient;
use super::TripInfo;

/// Grace after the (live or scheduled) arrival at the exit stop before we call it arrived.
const ARRIVAL_GRACE: ChronoDuration = ChronoDuration::minutes(3);

#[derive(Debug, Clone)]
pub struct RideFinalised {
    pub ride_id: Uuid,
    pub customer_id: Uuid,
    pub final_delay_min: i64,
    pub cancelled: bool,
}

#[derive(Debug, sqlx::FromRow)]
struct RidingRow {
    id: Uuid,
    customer_id: Uuid,
    trip_id: String,
    exit_station_id: String,
    exit_station_name: String,
    planned_arrival: DateTime<Utc>,
}

/// Points for a ride: one per minute late from minute 1; a cancellation counts as at least 60.
pub fn points_for(final_delay_min: i64, cancelled: bool) -> i64 {
    if cancelled {
        final_delay_min.max(60)
    } else {
        final_delay_min.max(0)
    }
}

/// Start the follower loop. Returns a receiver on which every finalised ride is announced.
pub fn spawn(pool: PgPool, client: Arc<TransitousClient>, interval: Duration) -> broadcast::Receiver<RideFinalised> {
    let (tx, rx) = broadcast::channel::<RideFinalised>(64);
    let announce = tx.clone();
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval(interval);
        ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        loop {
            ticker.tick().await;
            if let Err(e) = poll_once(&pool, &client, &announce).await {
                tracing::warn!(error = %e, "trip follower: poll failed");
            }
        }
    });
    rx
}

/// One pass over all riding rides. Public so a demo control or a test can drive it.
pub async fn poll_once(pool: &PgPool, client: &TransitousClient, announce: &broadcast::Sender<RideFinalised>) -> Result<()> {
    let riding: Vec<RidingRow> = sqlx::query_as(
        "select id, customer_id, trip_id, exit_station_id, exit_station_name, planned_arrival \
         from rides where status = 'riding' order by checked_in_at",
    )
    .fetch_all(pool)
    .await
    .context("select riding rides")?;

    for row in riding {
        match client.trip(&row.trip_id).await {
            Ok(trip) => {
                if let Err(e) = apply_trip(pool, &row, &trip, announce).await {
                    tracing::warn!(ride = %row.id, error = %e, "trip follower: apply failed");
                }
            }
            Err(e) => {
                tracing::warn!(ride = %row.id, trip = %row.trip_id, error = %e, "trip follower: fetch failed");
                sqlx::query("update rides set last_polled_at = now() where id = $1")
                    .bind(row.id)
                    .execute(pool)
                    .await
                    .ok();
            }
        }
    }
    Ok(())
}

async fn apply_trip(pool: &PgPool, row: &RidingRow, trip: &TripInfo, announce: &broadcast::Sender<RideFinalised>) -> Result<()> {
    let now = Utc::now();

    sqlx::query("insert into ride_snapshots (ride_id, source, payload) values ($1, 'transitous', $2)")
        .bind(row.id)
        .bind(serde_json::to_value(trip).context("serialise trip")?)
        .execute(pool)
        .await
        .context("insert snapshot")?;

    let exit = trip.find_stop(Some(row.exit_station_id.as_str()), &row.exit_station_name);
    let passed_stops = trip
        .stops
        .iter()
        .filter(|s| s.live_departure.or(s.scheduled_departure).map(|t| t < now).unwrap_or(false))
        .count() as i32;

    let (live_delay_min, exit_cancelled, arrival_estimate) = match exit {
        Some((_, stop)) => {
            let scheduled = stop.scheduled_arrival.unwrap_or(row.planned_arrival);
            let live = stop.live_arrival;
            let delay = live.map(|l| (l - scheduled).num_minutes()).unwrap_or(0);
            (delay, stop.cancelled, live.unwrap_or(scheduled))
        }
        None => (0, false, row.planned_arrival),
    };

    let cause: Option<String> = None; // Transitous carries no cause text on trips today.

    sqlx::query(
        "update rides set live_delay_min = $2, passed_stops = $3, cause = coalesce($4, cause), last_polled_at = now() \
         where id = $1 and status = 'riding'",
    )
    .bind(row.id)
    .bind(live_delay_min as i32)
    .bind(passed_stops)
    .bind(cause)
    .execute(pool)
    .await
    .context("update live state")?;

    let cancelled = trip.cancelled || exit_cancelled;
    let arrived = arrival_estimate + ARRIVAL_GRACE < now;
    if cancelled || arrived {
        let final_delay = if cancelled { live_delay_min.max(60) } else { live_delay_min };
        let actual = if cancelled { None } else { Some(arrival_estimate) };
        finalise_ride(pool, row.id, final_delay, cancelled, actual, false).await?;
        let _ = announce.send(RideFinalised {
            ride_id: row.id,
            customer_id: row.customer_id,
            final_delay_min: final_delay,
            cancelled,
        });
        tracing::info!(ride = %row.id, delay = final_delay, cancelled, "trip follower: ride finalised");
    }
    Ok(())
}

/// Close a ride. Used by the follower, by the manual-arrival endpoint (no data, E3) and by demo
/// controls. Idempotent: does nothing if the ride is not riding any more.
pub async fn finalise_ride(
    pool: &PgPool,
    ride_id: Uuid,
    final_delay_min: i64,
    cancelled: bool,
    actual_arrival: Option<DateTime<Utc>>,
    self_entered: bool,
) -> Result<()> {
    let points = points_for(final_delay_min, cancelled);
    let updated = sqlx::query(
        "update rides set status = 'arrived', actual_arrival = coalesce($2, planned_arrival + make_interval(mins => $3)), \
         final_delay_min = $3, cancelled = $4, self_entered = $5, points = $6, finalised_at = now(), last_polled_at = now() \
         where id = $1 and status = 'riding'",
    )
    .bind(ride_id)
    .bind(actual_arrival)
    .bind(final_delay_min as i32)
    .bind(cancelled)
    .bind(self_entered)
    .bind(points as i32)
    .execute(pool)
    .await
    .context("finalise ride")?;
    if updated.rows_affected() == 0 {
        return Ok(());
    }
    let reason = if self_entered {
        "manual arrival time"
    } else if cancelled {
        "trip cancelled"
    } else {
        "arrived at exit stop"
    };
    sqlx::query("insert into audit_log (entity, entity_id, from_status, to_status, reason) values ('ride', $1, 'riding', 'arrived', $2)")
        .bind(ride_id)
        .bind(reason)
        .execute(pool)
        .await
        .context("audit ride")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn points() {
        assert_eq!(points_for(14, false), 14);
        assert_eq!(points_for(0, false), 0);
        assert_eq!(points_for(-2, false), 0);
        assert_eq!(points_for(12, true), 60);
        assert_eq!(points_for(75, true), 75);
    }
}
