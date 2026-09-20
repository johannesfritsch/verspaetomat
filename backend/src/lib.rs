#![allow(clippy::type_complexity)]
//! The parts of the backend a tool outside the server needs as well.
//!
//! `stellwerk stations import` builds the station candidate set on a laptop rather than on the VPS
//! (issue #37: it is a 338 MB download and a pass over 2.8 GB of stop times, and the server has an
//! API to serve), so [`stations::gtfs`] and the two modules it stands on have to be reachable from
//! a second binary. `src/main.rs` keeps its own module declarations and is untouched by this.
pub mod clock;
pub mod stations;
pub mod train;
