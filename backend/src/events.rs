//! Per-customer event stream. Anything that changes a customer's world publishes here;
//! the app keeps `GET /v1/events` open and refreshes what the event names.
//! Kinds: location, ride, incident, claim, mail, clock, reset.

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
    fn sender_for(&self, customer: Uuid) -> broadcast::Sender<AppEvent> {
        if let Some(s) = self.senders.read().unwrap().get(&customer) {
            return s.clone();
        }
        let (tx, _) = broadcast::channel(64);
        self.senders.write().unwrap().insert(customer, tx.clone());
        tx
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
        let _ = self.sender_for(customer).send(ev);
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
    let mine = s.events.sender_for(c.0.id).subscribe();
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
    Sse::new(stream).keep_alive(KeepAlive::new().interval(Duration::from_secs(15)).text("ping"))
}
