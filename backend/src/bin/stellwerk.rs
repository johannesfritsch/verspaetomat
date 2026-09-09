//! stellwerk: drive the world a customer sees. Talks to the backend's /admin API.
//!
//!   stellwerk customers
//!   stellwerk ride Johannes
//!   stellwerk delay Johannes +25
//!   stellwerk cancel Johannes
//!   stellwerk ff Johannes
//!   stellwerk poll
//!   stellwerk reply Johannes --accepted | --question | --rejected
//!   stellwerk clock [+100d | -2h | now]
//!   stellwerk reset Johannes
//!   stellwerk overrides [--clear]
//!   stellwerk watch Johannes
//!
//! Env: STELLWERK_URL (default http://127.0.0.1:8080), ADMIN_TOKEN (default stellwerk).

use std::time::Duration;

use clap::{Parser, Subcommand};
use serde_json::{json, Value};

#[derive(Parser)]
#[command(name = "stellwerk", about = "Verspätomat Stellwerk: simulate delays, arrivals, replies and time for one customer.")]
struct Cli {
    /// Backend base URL
    #[arg(long, env = "STELLWERK_URL", default_value = "http://127.0.0.1:8080")]
    url: String,
    /// Admin token
    #[arg(long, env = "ADMIN_TOKEN", default_value = "stellwerk")]
    token: String,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// List customers and who is riding
    Customers,
    /// Show a customer's current ride with stops and live state
    Ride { customer: String },
    /// Add minutes of delay to the customer's current trip ("+25", "-5")
    Delay { customer: String, minutes: String },
    /// Cancel the customer's current trip
    Cancel { customer: String },
    /// Fast-forward: the exit stop is reached now; the follower finalises the ride
    Ff { customer: String },
    /// Run one follower pass now
    Poll,
    /// The railway answers the customer's newest sent claim
    Reply {
        customer: String,
        #[arg(long)]
        accepted: bool,
        #[arg(long)]
        question: bool,
        #[arg(long)]
        rejected: bool,
        /// Override the amount in cents (accepted only)
        #[arg(long)]
        amount: Option<i64>,
    },
    /// Show or shift the system clock (+100d, -2h, 90m, now)
    Clock { shift: Option<String> },
    /// Wipe rides, incidents, claims, mails and uploads of one customer
    Reset { customer: String },
    /// List active trip overrides, or clear them all
    Overrides {
        #[arg(long)]
        clear: bool,
    },
    /// Live view of a customer's ride, refreshed every 3 s (Ctrl-C to stop)
    Watch { customer: String },
}

struct Api {
    http: reqwest::Client,
    url: String,
    token: String,
}

impl Api {
    async fn get(&self, path: &str) -> anyhow::Result<Value> {
        let r = self.http.get(format!("{}{}", self.url, path)).header("x-admin-token", &self.token).send().await?;
        Self::body(r).await
    }
    async fn post(&self, path: &str, body: Value) -> anyhow::Result<Value> {
        let r = self.http.post(format!("{}{}", self.url, path)).header("x-admin-token", &self.token).json(&body).send().await?;
        Self::body(r).await
    }
    async fn delete(&self, path: &str) -> anyhow::Result<Value> {
        let r = self.http.delete(format!("{}{}", self.url, path)).header("x-admin-token", &self.token).send().await?;
        Self::body(r).await
    }
    async fn body(r: reqwest::Response) -> anyhow::Result<Value> {
        let status = r.status();
        let v: Value = r.json().await.unwrap_or(json!({}));
        if !status.is_success() {
            anyhow::bail!("{} {}", status.as_u16(), v.get("error").and_then(|e| e.as_str()).unwrap_or("error"));
        }
        Ok(v)
    }
}

fn s(v: &Value, key: &str) -> String {
    match v.get(key) {
        Some(Value::String(x)) => x.clone(),
        Some(Value::Null) | None => "–".into(),
        Some(x) => x.to_string(),
    }
}

fn hhmm(v: &Value) -> String {
    match v.as_str() {
        Some(t) if t.len() >= 16 => {
            // RFC 3339 UTC → local HH:MM
            chrono::DateTime::parse_from_rfc3339(t)
                .map(|d| d.with_timezone(&chrono::Local).format("%H:%M").to_string())
                .unwrap_or_else(|_| t[11..16].to_string())
        }
        _ => "–".into(),
    }
}

fn print_ride(v: &Value) {
    if v.get("riding").and_then(|b| b.as_bool()) != Some(true) {
        println!("{}  ·  nicht unterwegs", s(v, "customer"));
        if let Some(last) = v.get("last").filter(|l| !l.is_null()) {
            println!("zuletzt: {} → {}  {}  +{}", s(last, "line"), s(last, "exit_station_name"), s(last, "status"), s(last, "final_delay_min"));
        }
        return;
    }
    let r = &v["ride"];
    println!("{}  ·  {} → {}  ·  +{} min  ·  {} Halte passiert", s(v, "customer"), s(r, "line"), s(r, "exit_station_name"), s(r, "live_delay_min"), s(r, "passed_stops"));
    println!("geplant {}  ·  eingecheckt {}  ·  zuletzt gepollt {}  ·  Uhr {}", hhmm(&r["planned_arrival"]), hhmm(&r["checked_in_at"]), hhmm(&r["last_polled_at"]), hhmm(&v["now"]));
    if let Some(o) = v.get("override").filter(|o| !o.is_null()) {
        println!("Stellwerk: +{} min, storniert {}, Zeitversatz {} s", s(o, "extra_delay_min"), s(o, "cancelled"), s(o, "time_shift_secs"));
    }
    println!();
    let exit = s(r, "exit_station_name");
    if let Some(stops) = v.get("stops").and_then(|x| x.as_array()) {
        for st in stops {
            let name = s(st, "name");
            let mark = if name == exit { "◉" } else { "○" };
            let sched = hhmm(&st["scheduled_arrival"]);
            let live = hhmm(&st["live_arrival"]);
            let canc = if st.get("cancelled").and_then(|c| c.as_bool()) == Some(true) { "  AUSFALL" } else { "" };
            println!("  {mark} {:<34} {:>5}  {:>5}{}", name, sched, live, canc);
        }
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    let api = Api { http: reqwest::Client::builder().timeout(Duration::from_secs(30)).build()?, url: cli.url.trim_end_matches('/').to_string(), token: cli.token };

    match cli.cmd {
        Cmd::Customers => {
            let v = api.get("/admin/customers").await?;
            println!("{:<10} {:<36} {:<34} {:<8} Fahrt", "Name", "ID", "Relay", "offen");
            for c in v.as_array().unwrap_or(&vec![]) {
                let ride = c.get("ride").filter(|r| !r.is_null()).map(|r| format!("{} → {} (+{})", s(r, "line"), s(r, "exit_station_name"), s(r, "live_delay_min"))).unwrap_or_else(|| "–".into());
                println!("{:<10} {:<36} {:<34} {:<8} {}", s(c, "nickname"), s(c, "id"), s(c, "relay_address"), s(c, "open_incidents"), ride);
            }
        }
        Cmd::Ride { customer } => print_ride(&api.get(&format!("/admin/customers/{customer}/ride")).await?),
        Cmd::Delay { customer, minutes } => {
            let m: i32 = minutes.trim_start_matches('+').parse()?;
            let v = api.post(&format!("/admin/customers/{customer}/delay"), json!({ "minutes": m })).await?;
            println!("Verspätung jetzt +{} min (Stellwerk +{} min)", s(&v["ride"], "live_delay_min"), s(&v["override"], "extra_delay_min"));
        }
        Cmd::Cancel { customer } => {
            let v = api.post(&format!("/admin/customers/{customer}/cancel"), json!({})).await?;
            println!("Zug storniert. Fahrt: {}  Anspruch: {}", s(&v["ride"], "status"), v.get("incident").filter(|i| !i.is_null()).map(|i| format!("{} ct, {}", s(i, "amount_cents"), s(i, "status"))).unwrap_or_else(|| "keiner".into()));
        }
        Cmd::Ff { customer } => {
            let v = api.post(&format!("/admin/customers/{customer}/ff"), json!({})).await?;
            let r = &v["ride"];
            println!("Angekommen: {} → {}  +{} min  ·  {} Punkte", s(r, "line"), s(r, "exit_station_name"), s(r, "final_delay_min"), s(r, "points"));
            if let Some(i) = v.get("incident").filter(|i| !i.is_null()) {
                println!("Anspruch: {} ct  ·  {}  ·  {}", s(i, "amount_cents"), s(i, "status"), s(i, "desk"));
            } else {
                println!("Kein Anspruch (unter 60 Minuten).");
            }
            if let Some(b) = v.get("new_badge").filter(|b| !b.is_null()) {
                println!("Abzeichen: {}", s(b, "name"));
            }
        }
        Cmd::Poll => {
            let v = api.post("/admin/poll", json!({})).await?;
            println!("Follower-Durchlauf um {}: {} Fahrt(en) abgeschlossen", hhmm(&v["now"]), v["finalised"].as_array().map(|a| a.len()).unwrap_or(0));
        }
        Cmd::Reply { customer, accepted, question, rejected, amount } => {
            let _ = accepted;
            let outcome = if question { "question" } else if rejected { "rejected" } else { "accepted" };
            let v = api.post(&format!("/admin/customers/{customer}/reply"), json!({ "outcome": outcome, "amount_cents": amount })).await?;
            println!("Antwort der Bahn: {}  ·  Betrag {} ct  ·  Antrag {}", s(&v, "outcome"), s(&v["mail"], "amount_cents"), s(&v, "claim_id"));
        }
        Cmd::Clock { shift } => {
            let v = match shift {
                Some(sh) if sh == "now" || sh == "0" => api.post("/admin/clock", json!({ "offset_secs": 0 })).await?,
                Some(sh) => api.post("/admin/clock", json!({ "shift": sh })).await?,
                None => api.get("/admin/clock").await?,
            };
            println!("Uhr: {}  (Versatz {} s)", s(&v, "now"), s(&v, "offset_secs"));
        }
        Cmd::Reset { customer } => {
            let v = api.post(&format!("/admin/customers/{customer}/reset"), json!({})).await?;
            println!("Zurückgesetzt: {}  ({} Overrides gelöscht)", s(&v, "reset"), s(&v, "trip_overrides_cleared"));
        }
        Cmd::Overrides { clear } => {
            if clear {
                api.delete("/admin/overrides").await?;
                println!("Alle Overrides gelöscht.");
            } else {
                let v = api.get("/admin/overrides").await?;
                let list = v.as_array().cloned().unwrap_or_default();
                if list.is_empty() {
                    println!("Keine Overrides.");
                }
                for o in list {
                    println!("{:<48} +{:>3} min  storniert {:<5}  Versatz {} s", s(&o, "trip_id"), s(&o, "extra_delay_min"), s(&o, "cancelled"), s(&o, "time_shift_secs"));
                }
            }
        }
        Cmd::Watch { customer } => loop {
            let v = api.get(&format!("/admin/customers/{customer}/ride")).await;
            print!("\x1B[2J\x1B[H");
            match v {
                Ok(v) => print_ride(&v),
                Err(e) => println!("{e}"),
            }
            println!("\n(aktualisiert alle 3 s · Ctrl-C beendet)");
            tokio::time::sleep(Duration::from_secs(3)).await;
        },
    }
    Ok(())
}
