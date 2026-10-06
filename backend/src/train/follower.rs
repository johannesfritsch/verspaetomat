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

use super::sim::TrainSource;
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
    from_station_id: String,
    from_station_name: String,
    exit_station_id: String,
    exit_station_name: String,
    planned_arrival: DateTime<Utc>,
    journey_id: Option<Uuid>,
    leg_no: Option<i32>,
}

/// The minutes a ride counts (#74): its delay from minute 1; a cancellation counts at least 60.
pub fn counted_minutes(final_delay_min: i64, cancelled: bool) -> i64 {
    if cancelled {
        final_delay_min.max(60)
    } else {
        final_delay_min.max(0)
    }
}

/// How many stops of the ridden leg the train has put behind it: `rides.passed_stops` (#78).
///
/// Counted from the boarding stop up to, not including, the exit stop. A stop counts once its
/// departure — live where the feed has one, planned otherwise — lies before `now`. So:
///
/// - 0 means the train has not left the boarding stop yet, which is what makes a change of train a
///   mis-tap (`journeys::decide_train_change`, docs/24 §2);
/// - `boarding index + passed_stops` is the index, in the trip's stops, of the next stop the
///   train has yet to leave: the one it stands at or runs to. It never passes the exit stop.
///
/// That sum is what every build of the app computes (`passedStops + fromIndex`) and what
/// `journeys::next_stop_of` computes, so the figure has to start at the boarding stop. It used to
/// count from the train's origin: a passenger who boarded at the fifth stop saw a „Nächster Halt"
/// four stops too far, behind their own exit.
///
/// Without a boarding stop the count starts at the trip's first stop, which is also where the app
/// falls back to when it cannot find it, so the sum still names the next stop. Without an exit
/// stop it runs to the trip's end.
pub fn passed_stops(trip: &TripInfo, boarding: Option<usize>, exit: Option<usize>, now: DateTime<Utc>) -> i32 {
    let from = boarding.unwrap_or(0);
    let to = exit.unwrap_or(trip.stops.len()).min(trip.stops.len());
    if to <= from {
        return 0;
    }
    trip.stops[from..to]
        .iter()
        .filter(|s| s.live_departure.or(s.scheduled_departure).is_some_and(|t| t < now))
        .count() as i32
}

/// Start the follower loop. Returns a receiver on which every finalised ride is announced.
pub fn spawn(pool: PgPool, client: Arc<TrainSource>, stations: crate::stations::Shared, interval: Duration) -> broadcast::Receiver<RideFinalised> {
    let (tx, rx) = broadcast::channel::<RideFinalised>(64);
    let announce = tx.clone();
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval(interval);
        ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        loop {
            ticker.tick().await;
            if let Err(e) = poll_once(&pool, &client, &crate::stations::snapshot(&stations), &announce).await {
                tracing::warn!(error = %e, "trip follower: poll failed");
            }
        }
    });
    rx
}

/// One pass over all riding rides. Public so a demo control or a test can drive it.
pub async fn poll_once(pool: &PgPool, client: &TrainSource, stations: &crate::stations::Index, announce: &broadcast::Sender<RideFinalised>) -> Result<()> {
    let riding: Vec<RidingRow> = sqlx::query_as(
        "select id, customer_id, trip_id, from_station_id, from_station_name, exit_station_id, exit_station_name, planned_arrival, \
         journey_id, leg_no from rides where status = 'riding' order by checked_in_at",
    )
    .fetch_all(pool)
    .await
    .context("select riding rides")?;

    for row in riding {
        match client.trip(&row.trip_id).await {
            Ok(trip) => {
                if let Err(e) = apply_trip(pool, &row, &trip, stations, announce).await {
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

async fn apply_trip(pool: &PgPool, row: &RidingRow, trip: &TripInfo, stations: &crate::stations::Index, announce: &broadcast::Sender<RideFinalised>) -> Result<()> {
    let now = crate::clock::now();

    sqlx::query("insert into ride_snapshots (ride_id, source, payload) values ($1, 'transitous', $2)")
        .bind(row.id)
        .bind(serde_json::to_value(trip).context("serialise trip")?)
        .execute(pool)
        .await
        .context("insert snapshot")?;

    let boarding = trip.find_stop(&stations.candidate_ids(&row.from_station_id), &row.from_station_name);
    let exit = trip.find_stop(&stations.candidate_ids(&row.exit_station_id), &row.exit_station_name);
    if boarding.is_none() {
        tracing::warn!(ride = %row.id, trip = %row.trip_id, station = %row.from_station_name, "trip follower: boarding stop not on the trip; counting passed stops from its origin");
    }
    let passed_stops = passed_stops(trip, boarding.map(|(i, _)| i), exit.map(|(i, _)| i), now);

    // `live_known` (#78): whether the delay comes from a live forecast. Without realtime MOTIS
    // repeats the timetable as the live time, and 0 minutes would read as „pünktlich".
    let (live_delay_min, live_known, exit_cancelled, arrival_estimate) = match exit {
        Some((_, stop)) => {
            let scheduled = stop.scheduled_arrival.unwrap_or(row.planned_arrival);
            let live = stop.live_arrival;
            let delay = live.map(|l| (l - scheduled).num_minutes()).unwrap_or(0);
            (delay, Some(trip.realtime && live.is_some()), stop.cancelled, live.unwrap_or(scheduled))
        }
        None => {
            // Nothing to measure against. The ride goes on counting 0 minutes as before — what it is
            // finalised with is a rule of its own and not changed here — but no longer in silence,
            // and the 0 is not „pünktlich".
            tracing::warn!(ride = %row.id, trip = %row.trip_id, station = %row.exit_station_name, "trip follower: exit stop not on the trip; delay written as 0");
            (0, Some(false), false, row.planned_arrival)
        }
    };

    let cause: Option<String> = None; // Transitous carries no cause text on trips today.

    sqlx::query(
        "update rides set live_delay_min = $2, passed_stops = $3, cause = coalesce($4, cause), live_known = coalesce($5, live_known), \
         last_polled_at = now() where id = $1 and status = 'riding'",
    )
    .bind(row.id)
    .bind(live_delay_min as i32)
    .bind(passed_stops)
    .bind(cause)
    .bind(live_known)
    .execute(pool)
    .await
    .context("update live state")?;

    let departs = boarding.and_then(|(_, s)| s.track.as_deref());
    let arrives = exit.and_then(|(_, s)| s.track.as_deref());
    if let Err(e) = refresh_tracks(pool, row, departs, arrives).await {
        // A stale track is worth a line in the log, not a ride left unfinalised.
        tracing::warn!(ride = %row.id, error = %e, "trip follower: tracks not refreshed");
    }

    let cancelled = trip.cancelled || exit_cancelled;
    let arrived = arrival_estimate + ARRIVAL_GRACE < now;
    if cancelled || arrived {
        let final_delay = if cancelled { live_delay_min.max(60) } else { live_delay_min };
        // Actual = the ride's own planned time plus the delay: consistent evidence even when the
        // Stellwerk has shifted the trip's clock.
        let actual = if cancelled { None } else { Some(row.planned_arrival + ChronoDuration::minutes(live_delay_min)) };
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

/// The tracks of the riding leg as the live trip has them now, written back into the journey's
/// plan (#79): the departure track at the boarding stop as the leg's `platform`, the arrival track
/// at the exit stop as its `arrival_platform`.
///
/// The plan is what `journeys/current` hands out for every leg, and until now it held whatever the
/// timetable said at check-in: a train moved to another track stayed on the old one in the app.
/// Writing the existing fields means every build shows the new track without an update. Only a
/// track that differs is written, and a track the feed has stopped naming is left as it was rather
/// than erased. The leg is matched by its position and its trip, so a plan rewritten in the
/// meantime — a confirmed connection, a change of train — is never touched.
async fn refresh_tracks(pool: &PgPool, row: &RidingRow, departs: Option<&str>, arrives: Option<&str>) -> Result<()> {
    let (Some(journey), Some(leg_no)) = (row.journey_id, row.leg_no) else {
        return Ok(()); // A ride from before journeys has no plan to keep.
    };
    if departs.is_none() && arrives.is_none() {
        return Ok(());
    }
    sqlx::query(
        "update journeys set plan = jsonb_set(
                jsonb_set(plan, array[$2::text, 'platform'], coalesce(to_jsonb($3::text), plan->$2->'platform', 'null'::jsonb)),
                array[$2::text, 'arrival_platform'], coalesce(to_jsonb($4::text), plan->$2->'arrival_platform', 'null'::jsonb))
          where id = $1 and status = 'riding' and current_leg = $5
            and jsonb_typeof(plan) = 'array' and plan->$2->>'trip_id' = $6
            and (($3::text is not null and plan->$2->>'platform' is distinct from $3::text)
              or ($4::text is not null and plan->$2->>'arrival_platform' is distinct from $4::text))",
    )
    .bind(journey)
    .bind(leg_no - 1)
    .bind(departs)
    .bind(arrives)
    .bind(leg_no)
    .bind(&row.trip_id)
    .execute(pool)
    .await
    .context("update the leg's tracks")?;
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
    let points = counted_minutes(final_delay_min, cancelled);
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
    use crate::train::{TrainCategory, TripStop};

    /// The RE 96 of #78 without realtime: Lindau-Reutin to Buchloe, boarded at Kißlegg (index 4),
    /// off at Memmingen (index 9). Minutes after `t0`, the 07:47 departure at Lindau-Reutin.
    fn re96(t0: DateTime<Utc>) -> TripInfo {
        let at = |m: i64| Some(t0 + ChronoDuration::minutes(m));
        let stop = |name: &str, arr: Option<i64>, dep: Option<i64>| TripStop {
            stop_id: Some(format!("test:{name}")),
            name: name.to_string(),
            scheduled_arrival: arr.and_then(at),
            live_arrival: arr.and_then(at),
            scheduled_departure: dep.and_then(at),
            live_departure: dep.and_then(at),
            cancelled: false,
            track: None,
        };
        TripInfo {
            trip_id: "re96".into(),
            line: "RE 96".into(),
            train_number: Some("78914".into()),
            headsign: "Buchloe".into(),
            agency_name: "Arverio Bayern".into(),
            operator: "Arverio Bayern".into(),
            category: TrainCategory::Re,
            mode: "REGIONAL_RAIL".into(),
            realtime: false,
            cancelled: false,
            stops: vec![
                stop("Lindau-Reutin", None, Some(0)),
                stop("Lindau-Insel", Some(5), Some(5)),
                stop("Hergatz", Some(14), Some(14)),
                stop("Wangen (Allgäu)", Some(22), Some(22)),
                stop("Kißlegg", Some(32), Some(41)),
                stop("Leutkirch", Some(49), Some(49)),
                stop("Aichstetten", Some(55), Some(55)),
                stop("Aitrach-Marstetten", Some(60), Some(60)),
                stop("Tannheim (Württ)", Some(65), Some(65)),
                stop("Memmingen", Some(73), Some(76)),
                stop("Mindelheim", Some(85), Some(85)),
                stop("Türkheim", Some(92), Some(92)),
                stop("Buchloe", Some(100), None),
            ],
        }
    }

    const KISSLEGG: usize = 4;
    const MEMMINGEN: usize = 9;

    /// #78: at 08:45 seven stops of the train lie behind it, three of them on this leg. The app
    /// adds the boarding index to the figure, so it must be three, and the next stop is
    /// Aitrach-Marstetten, not Türkheim behind the exit.
    #[test]
    fn passed_stops_count_from_the_boarding_stop() {
        let t0 = Utc::now();
        let trip = re96(t0);
        let at_0845 = t0 + ChronoDuration::minutes(58);
        let passed = passed_stops(&trip, Some(KISSLEGG), Some(MEMMINGEN), at_0845);
        assert_eq!(passed, 3, "Kißlegg, Leutkirch, Aichstetten");
        assert_eq!(trip.stops[KISSLEGG + passed as usize].name, "Aitrach-Marstetten");
    }

    /// Still standing in Kißlegg after the check-in: nothing of the leg is behind the train. One
    /// minute after it left, the boarding stop is.
    #[test]
    fn standing_at_the_boarding_stop_nothing_is_passed() {
        let t0 = Utc::now();
        let trip = re96(t0);
        assert_eq!(passed_stops(&trip, Some(KISSLEGG), Some(MEMMINGEN), t0 + ChronoDuration::minutes(33)), 0, "08:20");
        assert_eq!(passed_stops(&trip, Some(KISSLEGG), Some(MEMMINGEN), t0 + ChronoDuration::minutes(42)), 1, "08:29");
    }

    /// Late in the ride the count stops at the exit: the train runs on, the passenger does not.
    #[test]
    fn the_count_never_passes_the_exit_stop() {
        let t0 = Utc::now();
        let trip = re96(t0);
        let at_0930 = t0 + ChronoDuration::minutes(103);
        let passed = passed_stops(&trip, Some(KISSLEGG), Some(MEMMINGEN), at_0930);
        assert_eq!(KISSLEGG + passed as usize, MEMMINGEN);
    }

    /// No boarding stop on the trip: the count starts at its first stop, which is where the app
    /// falls back to as well, so the sum still names the next stop. No exit: up to the last stop.
    #[test]
    fn without_a_boarding_stop_the_count_starts_at_the_origin() {
        let t0 = Utc::now();
        let trip = re96(t0);
        let at_0845 = t0 + ChronoDuration::minutes(58);
        assert_eq!(passed_stops(&trip, None, Some(MEMMINGEN), at_0845), 7);
        assert_eq!(passed_stops(&trip, Some(KISSLEGG), None, at_0845), 3);
        let at_1000 = t0 + ChronoDuration::minutes(133);
        assert_eq!(passed_stops(&trip, Some(KISSLEGG), None, at_1000), 8, "the last stop has no departure");
    }

    #[test]
    fn points() {
        assert_eq!(counted_minutes(14, false), 14);
        assert_eq!(counted_minutes(0, false), 0);
        assert_eq!(counted_minutes(-2, false), 0);
        assert_eq!(counted_minutes(12, true), 60);
        assert_eq!(counted_minutes(75, true), 75);
    }
}
