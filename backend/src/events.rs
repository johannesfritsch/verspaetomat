//! Per-customer event stream. Anything that changes a customer's world publishes here;
//! the app keeps `GET /v1/events` open and refreshes what the event names.
//! Kinds: location, ride, incident, claim, mail, clock, reset.
//!
//! A customer's channel exists only while somebody is listening (#42): [`EventHub::subscribe`]
//! creates it for the first open stream, [`EventHub::publish`] never creates one, and the hourly
//! scanner pass calls [`EventHub::sweep`] to drop the ones whose streams have ended.

use std::collections::HashMap;
use std::convert::Infallible;
use std::sync::RwLock;
use std::time::Duration;

use axum::extract::State;
use axum::response::sse::{Event, KeepAlive, Sse};
use futures_util::stream::Stream;
use serde_json::{json, Value};
use tokio::sync::broadcast;
use uuid::Uuid;

use crate::auth::Customer;
use crate::AppState;

#[derive(Debug, Clone)]
pub struct AppEvent {
    pub kind: &'static str,
    pub payload: Value,
}

#[derive(Default)]
pub struct EventHub {
    senders: RwLock<HashMap<Uuid, broadcast::Sender<AppEvent>>>,
    all: RwLock<Option<broadcast::Sender<AppEvent>>>,
    /// Sees every per-customer publish: the push sender hangs here.
    tap: RwLock<Option<broadcast::Sender<(Uuid, AppEvent)>>>,
}

impl EventHub {
    /// One open stream joins its customer's channel, creating it if it is the first listener.
    ///
    /// The receiver is attached **while the map lock is held**, and that is the whole trick. The
    /// sweep evicts channels with no receivers, and the instant between handing a sender out and
    /// subscribing to it is exactly such a channel. Under one lock only two orderings exist: the
    /// sweep runs before the entry is in the map (there is nothing to evict), or after the
    /// receiver is on it (`receiver_count() > 0`, so it is kept). A live stream can therefore
    /// never end up listening on a channel the map no longer holds — which would not look like a
    /// dropped event but like a stream that stays open and silent for ever.
    fn subscribe(&self, customer: Uuid) -> broadcast::Receiver<AppEvent> {
        let map = self.senders.read().unwrap();
        if let Some(s) = map.get(&customer) {
            return s.subscribe();
        }
        drop(map);
        // `entry`: another stream for the same customer may have taken the write lock in between.
        self.senders.write().unwrap().entry(customer).or_insert_with(|| broadcast::channel(64).0).subscribe()
    }

    /// Drop the channels nobody listens on any more. Runs once per scanner pass, hourly: a
    /// channel that outlives its stream costs a few KiB until the next pass, and nothing else is
    /// lost by waiting, because a channel with no receiver has nobody to deliver to anyway.
    ///
    /// Chosen over removing the entry when the stream ends: a teardown drop would have to ask
    /// `receiver_count()` all the same, because a second stream for the same customer may still
    /// be listening — the same test, run at a less predictable moment, and it needs a guard
    /// inside the SSE generator whose only job is to own what the map already owns. The sweep
    /// needs no ownership anywhere, and it also collects entries left behind by any other path.
    /// Returns how many were dropped.
    pub fn sweep(&self) -> usize {
        let mut map = self.senders.write().unwrap();
        let before = map.len();
        map.retain(|_, tx| tx.receiver_count() > 0);
        before - map.len()
    }

    fn all_sender(&self) -> broadcast::Sender<AppEvent> {
        if let Some(s) = self.all.read().unwrap().as_ref() {
            return s.clone();
        }
        let (tx, _) = broadcast::channel(64);
        *self.all.write().unwrap() = Some(tx.clone());
        tx
    }

    /// Tell one customer's open streams that something changed.
    pub fn publish(&self, customer: Uuid, kind: &'static str, payload: Value) {
        let ev = AppEvent { kind, payload };
        if let Some(t) = self.tap.read().unwrap().as_ref() {
            let _ = t.send((customer, ev.clone()));
        }
        // Look the channel up, never create one (#42): with no open stream there is nobody to
        // deliver to, and the channel would outlive the event by the lifetime of the process, for
        // a customer who may never have opened the app. The push sender is not affected — it
        // hangs on the tap above, which sees the event either way.
        let tx = self.senders.read().unwrap().get(&customer).cloned();
        if let Some(tx) = tx {
            let _ = tx.send(ev);
        }
    }

    /// Subscribe to every per-customer event (not the broadcast-to-all ones).
    pub fn tap(&self) -> broadcast::Receiver<(Uuid, AppEvent)> {
        if let Some(t) = self.tap.read().unwrap().as_ref() {
            return t.subscribe();
        }
        let (tx, rx) = broadcast::channel(256);
        *self.tap.write().unwrap() = Some(tx);
        rx
    }

    /// Tell every open stream (e.g. the clock moved).
    pub fn publish_all(&self, kind: &'static str, payload: Value) {
        let _ = self.all_sender().send(AppEvent { kind, payload });
    }
}

/// `GET /v1/events`: server-sent events for the authenticated customer.
pub async fn stream(State(s): State<AppState>, c: Customer) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let mine = s.events.subscribe(c.0.id);
    let all = s.events.all_sender().subscribe();
    let hello = json!({ "kind": "hello", "customer": c.0.id, "now": crate::clock::now() });
    let stream = async_stream::stream! {
        yield Ok(Event::default().event("hello").data(hello.to_string()));
        let mut mine = mine;
        let mut all = all;
        loop {
            let ev = tokio::select! {
                r = mine.recv() => r,
                r = all.recv() => r,
            };
            match ev {
                Ok(e) => yield Ok(Event::default().event(e.kind).data(e.payload.to_string())),
                Err(broadcast::error::RecvError::Lagged(_)) => yield Ok(Event::default().event("resync").data("{}")),
                Err(broadcast::error::RecvError::Closed) => break,
            }
        }
    };
    // The keep-alive is what holds an idle stream open through Caddy and a mobile NAT. It also
    // costs one write per open stream every 15 seconds — N/15 writes per second server-wide, so
    // 500/s at 7,500 concurrent streams on two vCPUs. That is a number for whatever decides
    // whether SSE is the right shape at that scale (#42), not one to tune here.
    Sse::new(stream).keep_alive(KeepAlive::new().interval(Duration::from_secs(15)).text("ping"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn channels(h: &EventHub) -> usize {
        h.senders.read().unwrap().len()
    }

    /// A customer opens `/v1/events` and closes it again: the next sweep leaves nothing behind.
    #[test]
    fn stream_teardown_releases_the_channel() {
        let hub = EventHub::default();
        let c = Uuid::new_v4();
        let rx = hub.subscribe(c); // what `stream()` does
        assert_eq!(channels(&hub), 1);
        assert_eq!(hub.sweep(), 0, "a live stream's channel was swept");
        drop(rx); // the customer closed the stream
        assert_eq!(hub.sweep(), 1);
        assert_eq!(channels(&hub), 0, "the channel outlived the stream");
    }

    /// The worse way in: a server-side event for somebody who has never connected at all.
    #[test]
    fn publish_without_a_listener_creates_nothing() {
        let hub = EventHub::default();
        let c = Uuid::new_v4();
        hub.publish(c, "ride", json!({}));
        assert_eq!(channels(&hub), 0, "publish allocated a channel for a customer who never connected");
    }

    /// Two streams for the same customer share one channel, and the channel belongs to the
    /// customer, not to the first stream: closing one must not silence the other.
    #[test]
    fn a_second_stream_keeps_the_channel() {
        let hub = EventHub::default();
        let c = Uuid::new_v4();
        let first = hub.subscribe(c);
        let mut second = hub.subscribe(c);
        assert_eq!(channels(&hub), 1);
        drop(first);
        assert_eq!(hub.sweep(), 0);
        hub.publish(c, "ride", json!({ "ride_id": "r1" }));
        assert_eq!(second.try_recv().unwrap().payload["ride_id"], "r1");
    }
}
