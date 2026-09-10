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
//!   stellwerk locate Johannes "Köln Hbf"   |  locate Johannes 50.943,6.9586  |  locate Johannes --clear
//!   stellwerk forget Johannes
//!   stellwerk ngo-report bahnhofsmission statement.csv   (or .json)
//!   stellwerk scan
//!
//! Targets: `--dev` (default) talks to http://127.0.0.1:8080 with token `stellwerk`; `--prod`
//! (or `--target NAME`) reads ~/.config/verspaetomat/stellwerk.toml: a URL and the admin token
//! per target. `stellwerk config init --ssh verspaetomat` writes that file and fetches the
//! server's ADMIN_TOKEN over SSH once.
//!
//! Env overrides: STELLWERK_TARGET, STELLWERK_URL, ADMIN_TOKEN, STELLWERK_CONFIG (file path).

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;

use clap::{Args, Parser, Subcommand};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

#[derive(Parser)]
#[command(name = "stellwerk", about = "Verspätomat Stellwerk: simulate delays, arrivals, replies and time for one customer.")]
struct Cli {
    /// Use the "prod" target from the config file
    #[arg(long, global = true, conflicts_with_all = ["dev", "target"])]
    prod: bool,
    /// Use the "dev" target (the default: local backend on 8080)
    #[arg(long, global = true, conflicts_with = "target")]
    dev: bool,
    /// Use a named target from the config file
    #[arg(long, global = true, env = "STELLWERK_TARGET")]
    target: Option<String>,
    /// Backend base URL (overrides the target)
    #[arg(long, global = true, env = "STELLWERK_URL")]
    url: Option<String>,
    /// Admin token (overrides the target)
    #[arg(long, global = true, env = "ADMIN_TOKEN")]
    token: Option<String>,
    #[command(subcommand)]
    cmd: Cmd,
}

// ---------------------------------------------------------------------------
// Targets and the config file
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct Target {
    /// Base URL of the backend.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    url: Option<String>,
    /// x-admin-token of that backend.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    token: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Default)]
struct ConfigFile {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    default: Option<String>,
    #[serde(default)]
    targets: BTreeMap<String, Target>,
}

fn config_path() -> PathBuf {
    if let Ok(p) = std::env::var("STELLWERK_CONFIG") {
        return PathBuf::from(p);
    }
    dirs::home_dir().unwrap_or_else(|| PathBuf::from(".")).join(".config").join("verspaetomat").join("stellwerk.toml")
}

fn load_config() -> anyhow::Result<ConfigFile> {
    let p = config_path();
    if !p.exists() {
        return Ok(ConfigFile::default());
    }
    Ok(toml::from_str(&std::fs::read_to_string(&p)?)?)
}

fn save_config(c: &ConfigFile) -> anyhow::Result<PathBuf> {
    let p = config_path();
    if let Some(dir) = p.parent() {
        std::fs::create_dir_all(dir)?;
    }
    std::fs::write(&p, toml::to_string_pretty(c)?)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o600))?;
    }
    Ok(p)
}

fn builtin_dev() -> Target {
    Target { url: Some("http://127.0.0.1:8080".into()), token: Some("stellwerk".into()) }
}

/// Which target this invocation uses, and its settings after flags and env.
fn resolve(cli: &Cli, cfg: &ConfigFile) -> anyhow::Result<(String, Target)> {
    let name = if cli.prod {
        "prod".to_string()
    } else if cli.dev {
        "dev".to_string()
    } else if let Some(t) = &cli.target {
        t.clone()
    } else {
        cfg.default.clone().unwrap_or_else(|| "dev".into())
    };
    let mut t = match cfg.targets.get(&name) {
        Some(t) => t.clone(),
        None if name == "dev" => builtin_dev(),
        None => anyhow::bail!("no target \"{name}\" in {} (run: stellwerk config init --ssh <host> --name {name})", config_path().display()),
    };
    if let Some(u) = &cli.url {
        t.url = Some(u.clone());
    }
    if let Some(tok) = &cli.token {
        t.token = Some(tok.clone());
    }
    if t.token.is_none() && name == "dev" {
        t.token = Some("stellwerk".into());
    }
    Ok((name, t))
}

#[derive(Subcommand)]
enum ConfigCmd {
    /// Write the config file; with --ssh, fetch the server's ADMIN_TOKEN over SSH
    Init(ConfigInit),
    /// Print the config file (tokens masked)
    Show,
    /// Print the path of the config file
    Path,
}

#[derive(Args)]
struct ConfigInit {
    /// SSH host or alias of the server; used once to read ADMIN_TOKEN from deploy/.env
    #[arg(long)]
    ssh: Option<String>,
    /// Target name to write
    #[arg(long, default_value = "prod")]
    name: String,
    /// Public URL of the API; the target talks to /admin there with the token
    #[arg(long, default_value = "https://api.verspaetomat.de")]
    url: String,
    /// Admin token (default: read from the SSH host's /opt/verspaetomat/deploy/.env)
    #[arg(long)]
    token: Option<String>,
}

fn config_command(c: ConfigCmd) -> anyhow::Result<()> {
    match c {
        ConfigCmd::Path => println!("{}", config_path().display()),
        ConfigCmd::Show => {
            let cfg = load_config()?;
            println!("# {}", config_path().display());
            println!("default = \"{}\"", cfg.default.clone().unwrap_or_else(|| "dev".into()));
            for (name, t) in &cfg.targets {
                println!("[targets.{name}]");
                if let Some(u) = &t.url {
                    println!("url = \"{u}\"");
                }
                if let Some(tok) = &t.token {
                    println!("token = \"{}…\"", tok.chars().take(4).collect::<String>());
                }
            }
            if cfg.targets.is_empty() {
                println!("# no targets yet: stellwerk config init --ssh verspaetomat");
            }
        }
        ConfigCmd::Init(i) => {
            let mut cfg = load_config()?;
            let mut t = Target { url: Some(i.url.trim_end_matches('/').to_string()), token: None };
            t.token = match (i.token, &i.ssh) {
                (Some(tok), _) => Some(tok),
                (None, Some(h)) => {
                    eprintln!("reading ADMIN_TOKEN from {h}:/opt/verspaetomat/deploy/.env …");
                    let out = Command::new("ssh").args(["-o", "BatchMode=yes", h, "grep -m1 '^ADMIN_TOKEN=' /opt/verspaetomat/deploy/.env"]).output()?;
                    if !out.status.success() {
                        anyhow::bail!("ssh {h} failed: {}", String::from_utf8_lossy(&out.stderr).trim());
                    }
                    let line = String::from_utf8_lossy(&out.stdout);
                    let tok = line.trim().trim_start_matches("ADMIN_TOKEN=").split_whitespace().next().unwrap_or("").to_string();
                    if tok.is_empty() {
                        anyhow::bail!("no ADMIN_TOKEN= line in the server's deploy/.env");
                    }
                    Some(tok)
                }
                (None, None) => anyhow::bail!("give --token, or --ssh <host> to read it from the server"),
            };
            cfg.targets.entry("dev".into()).or_insert_with(builtin_dev);
            cfg.targets.insert(i.name.clone(), t);
            if cfg.default.is_none() {
                cfg.default = Some("dev".into());
            }
            let p = save_config(&cfg)?;
            println!("wrote {} (mode 600): target \"{}\" ready. Try: stellwerk --{} customers", p.display(), i.name, i.name);
        }
    }
    Ok(())
}

#[derive(Subcommand)]
enum Cmd {
    /// Targets: init the config file for --prod, show it, print its path
    Config {
        #[command(subcommand)]
        cmd: ConfigCmd,
    },
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
    /// Send a test push to the customer's device (logged only without APNS_*/FCM_* credentials)
    Push { customer: String, text: Option<String> },
    /// Delete a customer entirely (device, rides, incidents, claims, mails, uploads); --force when claims were already sent
    Forget {
        customer: String,
        #[arg(long)]
        force: bool,
    },
    /// Import an NGO's monthly statement (CSV date,amount,reference,counterparty; amount "4,50" or "4.50") and confirm matching claims
    NgoReport {
        /// NGO id, e.g. bahnhofsmission
        ngo: String,
        /// CSV file; a .json file ({transfers:[…]}) is sent as is
        file: std::path::PathBuf,
    },
    /// Run one deadline-scanner pass now (warnings, expiry, reply nudges, retention)
    Scan,
    /// Put a customer at a station ("Köln Hbf") or at lat,lon; --clear returns to the phone's GPS
    Locate {
        customer: String,
        /// Station name, or "lat,lon"
        place: Option<String>,
        #[arg(long)]
        clear: bool,
    },
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
    if let Cmd::Config { cmd } = cli.cmd {
        return config_command(cmd);
    }
    let cfg = load_config()?;
    let (name, target) = resolve(&cli, &cfg)?;
    let url = target.url.clone().ok_or_else(|| anyhow::anyhow!("target \"{name}\" has no url"))?.trim_end_matches('/').to_string();
    if name != "dev" {
        eprintln!("[{name}] {url}");
    }
    let token = target.token.ok_or_else(|| anyhow::anyhow!("target \"{name}\" has no token"))?;
    let api = Api { http: reqwest::Client::builder().timeout(Duration::from_secs(30)).build()?, url, token };

    match cli.cmd {
        Cmd::Config { .. } => unreachable!(),
        Cmd::Customers => {
            let v = api.get("/admin/customers").await?;
            println!("{:<10} {:<36} {:<34} {:<8} {:<14} {:<6} Fahrt", "Name", "ID", "Relay", "offen", "Standort", "Push");
            for c in v.as_array().unwrap_or(&vec![]) {
                let ride = c.get("ride").filter(|r| !r.is_null()).map(|r| format!("{} → {} (+{})", s(r, "line"), s(r, "exit_station_name"), s(r, "live_delay_min"))).unwrap_or_else(|| "–".into());
                let loc = c.get("sim_location").and_then(|l| l.as_str()).map(|l| format!("SW: {l}")).unwrap_or_else(|| "Telefon".into());
                let push = c.get("push_platform").and_then(|p| p.as_str()).unwrap_or("–");
                println!("{:<10} {:<36} {:<34} {:<8} {:<14} {:<6} {}", s(c, "nickname"), s(c, "id"), s(c, "relay_address"), s(c, "open_incidents"), loc, push, ride);
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
        Cmd::Locate { customer, place, clear } => {
            if clear {
                api.delete(&format!("/admin/customers/{customer}/locate")).await?;
                println!("Standort-Override entfernt; das Telefon entscheidet wieder.");
            } else {
                let place = place.ok_or_else(|| anyhow::anyhow!("give a station name or lat,lon, or --clear"))?;
                let body = match place.split_once(',') {
                    Some((a, b)) if a.trim().parse::<f64>().is_ok() && b.trim().parse::<f64>().is_ok() => json!({ "lat": a.trim().parse::<f64>()?, "lon": b.trim().parse::<f64>()? }),
                    _ => json!({ "station": place }),
                };
                let v = api.post(&format!("/admin/customers/{customer}/locate"), body).await?;
                println!("{} steht jetzt bei {} ({}, {})", s(&v, "customer"), s(&v, "label"), s(&v, "lat"), s(&v, "lon"));
            }
        }
        Cmd::Forget { customer, force } => {
            let path = format!("/admin/customers/{customer}{}", if force { "?force=true" } else { "" });
            let v = api.delete(&path).await?;
            println!("Vergessen: {} ({}), {} gesendete Anträge", s(&v, "nickname"), s(&v, "forgotten"), s(&v, "sent_claims"));
        }
        Cmd::NgoReport { ngo, file } => {
            let text = std::fs::read_to_string(&file)?;
            let body = if file.extension().and_then(|e| e.to_str()) == Some("json") {
                serde_json::from_str::<Value>(&text)?
            } else {
                let transfers: Vec<Value> = text
                    .lines()
                    .map(str::trim)
                    .filter(|l| !l.is_empty() && !l.starts_with('#'))
                    .filter_map(|l| {
                        let sep = if l.matches(';').count() >= l.matches(',').count() { ';' } else { ',' };
                        let f: Vec<&str> = l.splitn(4, sep).map(|x| x.trim().trim_matches('"')).collect();
                        // The header line has no parsable date.
                        let first = *f.first()?;
                        let date = chrono::NaiveDate::parse_from_str(first, "%Y-%m-%d").or_else(|_| chrono::NaiveDate::parse_from_str(first, "%d.%m.%Y")).ok()?;
                        Some(json!({ "date": date, "amount": f.get(1)?, "reference": f.get(2).unwrap_or(&""), "counterparty": f.get(3).unwrap_or(&"") }))
                    })
                    .collect();
                json!({ "transfers": transfers })
            };
            let v = api.post(&format!("/admin/ngos/{ngo}/report"), body).await?;
            let matched = v.get("matched").and_then(|m| m.as_array()).cloned().unwrap_or_default();
            let unmatched = v.get("unmatched").and_then(|m| m.as_array()).cloned().unwrap_or_default();
            println!("Bericht {}: {} Überweisungen, {} zugeordnet, {} offen", s(&v, "report_id"), s(&v, "rows"), matched.len(), unmatched.len());
            for id in &matched {
                println!("  ✓ Antrag {}", id.as_str().unwrap_or_default());
            }
            for u in &unmatched {
                println!("  · {}  {:>8} ct  {}  {}", s(u, "date"), s(u, "amount_cents"), s(u, "reference"), s(u, "counterparty"));
            }
        }
        Cmd::Push { customer, text } => {
            let v = api.post(&format!("/admin/customers/{customer}/push"), json!({ "text": text })).await?;
            let platform = v["platform"].as_str().unwrap_or("–");
            let token = if v["token"].as_bool().unwrap_or(false) { "Token da" } else { "kein Token" };
            let how = if v["configured"].as_bool().unwrap_or(false) { "Provider konfiguriert" } else { "Dry-Run, nur Log" };
            println!("Push an {} ({platform}, {token}, {how}): {}", s(&v, "nickname"), s(&v, "result"));
            println!("  {} – {}", s(&v, "title"), s(&v, "body"));
        }
        Cmd::Scan => {
            let v = api.post("/admin/scan", json!({})).await?;
            println!("Scanner ({}): {} gewarnt, {} verfallen, {} angestupst, {} bereinigt", s(&v, "today"), s(&v, "warned"), s(&v, "expired"), s(&v, "nudged"), s(&v, "retained"));
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
