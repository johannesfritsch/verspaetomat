//! stellwerk: drive the world a customer sees. Talks to the backend's /admin API.
//!
//!   stellwerk customers
//!   stellwerk ride Johannes
//!   stellwerk journey Johannes  |  stellwerk confirm Johannes [--trip <trip id>]
//!   stellwerk delay Johannes +25
//!   stellwerk backdate Johannes --delay 70 --days 3 [--count 3] [--from "Bonn Hbf" --to "Köln Hbf"]
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
//!   stellwerk route list | set <desk> <address> [--label …] | default <address> | remove <desk>
//!   stellwerk ngo list | set <id> --name … --holder … --iban … | import ngos.json | remove <id>
//!   stellwerk stations import [--from <dir>] [--out stations.json] [--dry-run] [--force]
//!   stellwerk stations extract [--out <dir>] [--keep 1] [--asset] [--dry-run]
//!   stellwerk switch [stations-local on|off]
//!   stellwerk mail-test Johannes j@example.org [--claim <id>]
//!   stellwerk scan
//!
//! Targets: `--dev` (default) talks to http://127.0.0.1:8080 with token `stellwerk`; `--prod`
//! (or `--target NAME`) reads ~/.config/verspaetomat/stellwerk.toml: a URL and the admin token
//! per target. `stellwerk config init --ssh verspaetomat` writes that file and fetches the
//! server's ADMIN_TOKEN over SSH once.
//!
//! Env overrides: STELLWERK_TARGET, STELLWERK_URL, ADMIN_TOKEN, STELLWERK_CONFIG (file path).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

use clap::{Args, Parser, Subcommand};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use verspaetomat_api::stations::{extract, gtfs};

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

/// `site/static/stations/latest.json`: what a phone reads to find out whether it is holding the
/// newest extract, without downloading 274 KB to find out. Key order is declaration order, so the
/// bytes are deterministic and `dist_ist_aktuell` stays quiet.
#[derive(Serialize)]
struct ExtractPointer {
    version: u32,
    format: u16,
    count: u32,
    bytes: u64,
    crc32: u32,
    generated: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    feed_version: Option<String>,
    url: String,
}

fn config_path() -> PathBuf {
    if let Ok(p) = std::env::var("STELLWERK_CONFIG") {
        return PathBuf::from(p);
    }
    dirs::home_dir().unwrap_or_else(|| PathBuf::from(".")).join(".config").join("verspaetomat").join("stellwerk.toml")
}

/// The repo this binary was built from. `site/src/main.rs` does the same with
/// `env!("CARGO_MANIFEST_DIR")`: a tool that writes into the working tree should not depend on
/// which directory it was started in.
fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..")
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

// clap builds one enum variant per subcommand and `Set` carries a dozen optional strings, so it
// dwarfs `List`. That is what a CLI argument enum looks like; boxing it would buy nothing.
#[allow(clippy::large_enum_variant)]
#[derive(Subcommand)]
enum NgoCmd {
    /// All NGOs, inactive ones included, with totals and how many customers chose them
    List,
    /// Create or update one NGO; a new one needs --name, --holder and --iban
    Set {
        /// Id: letters, digits, - and _ (e.g. bahnhofsmission-koeln)
        id: String,
        #[arg(long)]
        name: Option<String>,
        #[arg(long)]
        tagline: Option<String>,
        /// Story paragraph; repeat for several paragraphs (replaces the story)
        #[arg(long = "story")]
        story: Vec<String>,
        /// Account holder as it appears on the claim form
        #[arg(long)]
        holder: Option<String>,
        #[arg(long)]
        iban: Option<String>,
        #[arg(long = "donation-url")]
        donation_url: Option<String>,
        /// What this Verein had received before Verspätomat, in cents. Added to what we can account for.
        #[arg(long = "seed-confirmed")]
        seed_confirmed: Option<i64>,
        /// What had been submitted for it before Verspätomat, in cents.
        #[arg(long = "seed-submitted")]
        seed_submitted: Option<i64>,
        /// Date of the written consent to appear as payee (YYYY-MM-DD)
        #[arg(long)]
        consent: Option<String>,
        /// The NGO's own logo as a PNG or SVG file; stored inline and printed on shared tickets
        /// (docs/27). Pass an empty path to remove it.
        #[arg(long = "logo")]
        logo: Option<String>,
        #[arg(long, conflicts_with = "inactive")]
        active: bool,
        #[arg(long)]
        inactive: bool,
    },
    /// Create or update NGOs from a JSON file: one object or an array, same fields as fixtures/ngos.json
    Import { file: std::path::PathBuf },
    /// Delete an NGO nobody references, otherwise deactivate it
    Remove { id: String },
}

/// Where claim mail is allowed to go.
#[derive(Subcommand)]
enum RouteCmd {
    /// Every route, and whether its target is the real desk or a stand-in
    List,
    /// Point a desk's mail at an address. This is the ONLY way a destination comes to exist.
    Set {
        /// The desk, exactly as it appears on a claim, e.g. "Servicecenter Fahrgastrechte"
        desk: String,
        /// Where the mail actually goes
        to: String,
        /// What this represents, printed in `route list` and on a rehearsal's subject line
        #[arg(long)]
        label: Option<String>,
        /// Where this route's paper would go. Without it the operator directory's address is shown.
        #[arg(long = "postal")]
        postal: Option<String>,
        #[arg(long)]
        note: Option<String>,
    },
    /// The catch-all: where a desk with no route of its own sends. One row, keyed „*"
    Default {
        /// Where that mail actually goes. Leave it out to show the catch-all as it stands
        to: Option<String>,
        /// What this represents, printed in `route list` and on a rehearsal's subject line
        #[arg(long)]
        label: Option<String>,
        /// Where this route's paper would go
        #[arg(long = "postal")]
        postal: Option<String>,
        #[arg(long)]
        note: Option<String>,
        /// Take the catch-all away. A desk without its own route can then send nothing
        #[arg(long)]
        remove: bool,
    },
    /// Remove a route. Nothing can be sent to that desk afterwards.
    Remove { desk: String },
    /// The domains a desk's answers may come from, besides the domain its mail goes to. Only
    /// verified mail from these can accept, refuse or ask. Without options: show them
    Answers {
        /// The desk, exactly as in `route list`
        desk: String,
        /// Add a domain (repeatable, or comma-separated); subdomains count too
        #[arg(long)]
        add: Vec<String>,
        /// Remove a domain (repeatable, or comma-separated)
        #[arg(long)]
        remove: Vec<String>,
        /// Remove every added domain; the destination's own domain stays
        #[arg(long)]
        clear: bool,
        /// Allow a free-mail provider (gmail.com, web.de, …) — only for a test inbox
        #[arg(long)]
        force: bool,
    },
}

/// Our own station table (issue #37).
///
/// The candidate set is built **here**, on the laptop: it is a 400 MB download and a pass over
/// 2.8 GB of stop times, and the VPS has an API to serve. The same division of labour as `site/`,
/// which is generated here and only served there. What crosses the wire is the finished set, and
/// the server decides what it means for the ids it has already handed to phones.
#[derive(Subcommand)]
enum StationsCmd {
    /// Build the set from the Transitous GTFS feeds and hand it to the server
    Import {
        /// Read de_DELFI.gtfs.zip and de_VBB.gtfs.zip from here instead of downloading them
        #[arg(long)]
        from: Option<PathBuf>,
        /// Also write the built set here as JSON, to look at
        #[arg(long)]
        out: Option<PathBuf>,
        /// Ask the server what it would do. Nothing is written
        #[arg(long = "dry-run")]
        dry_run: bool,
        /// Skip the server's guards, and send even when the sample below came back short. The
        /// first import needs this: an empty table cannot pass the retirement guard
        #[arg(long)]
        force: bool,
        /// How many of the built ids to ask the live API about before handing them over; 0 skips it
        #[arg(long, default_value_t = 20)]
        check: usize,
    },
    /// Render the phone's binary extract from the table and write it under site/static/stations
    Extract {
        /// Write the published files here instead of <repo>/site/static/stations. Required for any
        /// target other than prod: the version is a station_imports id and is per-database, so a
        /// dev extract in the repo would publish the laptop's table under production's name
        #[arg(long)]
        out: Option<PathBuf>,
        /// How many older extracts to leave beside the new one, so a phone that has just read
        /// latest.json still finds the file it was told about
        #[arg(long, default_value_t = 1)]
        keep: usize,
        /// Also refresh <repo>/app/assets/stations/stations.vst. Off until #39's Dart half ships
        /// the reader that uses it
        #[arg(long)]
        asset: bool,
        /// Fetch it, check it, write nothing
        #[arg(long = "dry-run")]
        dry_run: bool,
    },
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
    /// Show a customer's journey: legs, transfer state, the proposed next leg (docs/17)
    Journey { customer: String },
    /// Confirm the proposed next leg at a transfer, as the phone would; --trip for another train
    Confirm {
        customer: String,
        #[arg(long)]
        trip: Option<String>,
    },
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
    /// The latest desk answers: who read each (rules or model), what came of it, and why
    Replies,
    /// Read a stored desk answer again and let it act — for mail that came in while the model was unavailable
    Reread { mail: String },
    /// How a desk's mail would be read — rules, model and the checks between them — without
    /// touching any claim. Reads the mail text from FILE, or from stdin with "-"
    ReadMail {
        file: String,
        #[arg(long)]
        from: Option<String>,
        #[arg(long)]
        subject: Option<String>,
        /// Read it as the answer to this claim id (its rides, its passenger taken out)
        #[arg(long, conflicts_with = "to")]
        claim: Option<String>,
        /// Or the address the answer was sent to (antrag-…@users.verspaetomat.de): the claim is found
        /// the way the webhook finds it
        #[arg(long)]
        to: Option<String>,
        /// Without --claim or --to: cents claimed for the single made-up ride it is read against (default 150)
        #[arg(long)]
        claimed: Option<i64>,
        /// Without --claim or --to: that ride's date, YYYY-MM-DD (default today)
        #[arg(long)]
        date: Option<String>,
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
    /// Invent a ride that already happened, with the delay it had: test data for claims
    Backdate {
        customer: String,
        /// Minutes late at the destination; 60 and up is what makes a claim
        #[arg(long, default_value_t = 70)]
        delay: i64,
        /// How many days back the newest invented ride departed
        #[arg(long, default_value_t = 1)]
        days: i64,
        /// How many rides to invent, one a day going further back
        #[arg(long, default_value_t = 1)]
        count: i64,
        /// Departure in German local time
        #[arg(long, default_value = "08:12")]
        at: String,
        /// Scheduled travel time in minutes
        #[arg(long, default_value_t = 52)]
        duration: i64,
        #[arg(long, default_value = "Bonn Hbf")]
        from: String,
        #[arg(long, default_value = "Köln Hbf")]
        to: String,
        #[arg(long, default_value = "RE 5")]
        line: String,
        /// s | rb | re | fern | bus
        #[arg(long, default_value = "re")]
        category: String,
        #[arg(long, default_value = "DB Regio NRW")]
        operator: String,
        /// deutschlandticket | zeitkarte | einzelfahrkarte (default: the customer's own)
        #[arg(long)]
        ticket: Option<String>,
        /// The train was cancelled
        #[arg(long)]
        cancelled: bool,
    },
    /// Delete a customer entirely (device, rides, incidents, claims, mails, uploads); --force when claims were already sent
    Forget {
        customer: String,
        #[arg(long)]
        force: bool,
    },
    /// Where claim mail is allowed to go. An empty list means nothing can be sent.
    Route {
        #[command(subcommand)]
        cmd: RouteCmd,
    },
    /// Manage the NGOs customers can choose (list, set, import, remove)
    Ngo {
        #[command(subcommand)]
        cmd: NgoCmd,
    },
    /// Our own station table: build it from the Transitous GTFS feeds and hand it over
    Stations {
        #[command(subcommand)]
        cmd: StationsCmd,
    },
    /// Import an NGO's monthly statement (CSV date,amount,reference,counterparty; amount "4,50" or "4.50") and confirm matching claims
    /// Send one real test mail from the customer's relay address (assigned if missing); reply to it to test the inbound path
    MailTest {
        customer: String,
        to: String,
        /// Send from this claim's antrag-… address instead (claim id or prefix)
        #[arg(long)]
        claim: Option<String>,
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
    /// Server-side switches that turn a shipped behaviour off without a new build.
    /// Without arguments: show them all
    Switch {
        /// stations-local
        name: Option<String>,
        /// on | off
        value: Option<String>,
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
    /// The one admin answer that is not JSON. A failure still is, so it reads like every other
    /// command's failure.
    async fn get_bytes(&self, path: &str) -> anyhow::Result<Vec<u8>> {
        let r = self.http.get(format!("{}{}", self.url, path)).header("x-admin-token", &self.token).send().await?;
        let status = r.status();
        let body = r.bytes().await?;
        if !status.is_success() {
            let v: Value = serde_json::from_slice(&body).unwrap_or(json!({}));
            anyhow::bail!("{} {}", status.as_u16(), v.get("error").and_then(|e| e.as_str()).unwrap_or("error"));
        }
        Ok(body.to_vec())
    }
    async fn post(&self, path: &str, body: Value) -> anyhow::Result<Value> {
        let r = self.http.post(format!("{}{}", self.url, path)).header("x-admin-token", &self.token).json(&body).send().await?;
        Self::body(r).await
    }
    async fn put(&self, path: &str, body: Value) -> anyhow::Result<Value> {
        let r = self.http.put(format!("{}{}", self.url, path)).header("x-admin-token", &self.token).json(&body).send().await?;
        Self::body(r).await
    }
    async fn delete(&self, path: &str) -> anyhow::Result<Value> {
        let r = self.http.delete(format!("{}{}", self.url, path)).header("x-admin-token", &self.token).send().await?;
        Self::body(r).await
    }
    /// The same target with a longer patience, for the one request that hands over eight thousand
    /// stations and then waits while the server writes every one of them in a single transaction.
    fn patient(&self, secs: u64) -> anyhow::Result<Api> {
        let http = reqwest::Client::builder().timeout(Duration::from_secs(secs)).build()?;
        Ok(Api { http, url: self.url.clone(), token: self.token.clone() })
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

/// A JSON array of strings, as strings.
fn strings(v: &Value) -> Vec<String> {
    v.as_array().map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_string)).collect()).unwrap_or_default()
}

fn s(v: &Value, key: &str) -> String {
    match v.get(key) {
        Some(Value::String(x)) => x.clone(),
        Some(Value::Null) | None => "–".into(),
        Some(x) => x.to_string(),
    }
}

/// "273,7 KB (gzip 144,1 KB)" — German decimal comma, like the rest of the output.
fn kb(raw: usize, gz: usize) -> String {
    format!("{:.1} KB (gzip {:.1} KB)", raw as f64 / 1024.0, gz as f64 / 1024.0).replace('.', ",")
}

/// Paths inside the repo print relative, so the lines fit on one screen.
fn rel(root: &Path, p: &Path) -> String {
    p.strip_prefix(root).unwrap_or(p).display().to_string()
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

/// "07.09. 08:12" in local time, for a ride that is not today's.
fn dhm(v: &Value) -> String {
    match v.as_str().and_then(|t| chrono::DateTime::parse_from_rfc3339(t).ok()) {
        Some(d) => d.with_timezone(&chrono::Local).format("%d.%m. %H:%M").to_string(),
        None => "–".into(),
    }
}

fn print_journey(v: &Value) {
    let j = &v["journey"];
    if j.is_null() {
        println!("{}  ·  keine Fahrt", s(v, "customer"));
        return;
    }
    let status = s(j, "status");
    println!(
        "{}  ·  {} → {}  ·  {}  ·  geplant an {}{}",
        s(v, "customer"), s(j, "origin_station_name"), s(j, "destination_station_name"), status.to_uppercase(), hhmm(&j["planned_arrival"]),
        if j["missed_connection"].as_bool().unwrap_or(false) { "  ·  ANSCHLUSS VERPASST" } else { "" }
    );
    if status == "arrived" {
        println!("angekommen {}  ·  +{} min  ·  {} Punkte{}", hhmm(&j["actual_arrival"]), s(j, "final_delay_min"), s(j, "points"), if j["incomplete"].as_bool().unwrap_or(false) { "  ·  unvollständig" } else { "" });
    }
    // Why it ended, and — while in transfer — whether this is a real change of train (docs/21).
    match j["end_reason"].as_str() {
        Some("aufgegeben") => println!("beendet: aufgegeben  ·  keine Punkte, kein Anspruch"),
        Some("nicht_gefahren") => println!("beendet: gar nicht mitgefahren"),
        Some("beendet") => println!("beendet: vom Fahrgast"),
        _ => {}
    }
    if j["transfer_reason"].as_str() == Some("weiterfahrt") {
        println!("wartet auf Weiterfahrt ab {}  (bis {})", s(j, "transfer_station_name"), hhmm(&j["transfer_deadline"]));
    }
    if let Some(legs) = j["legs"].as_array() {
        for l in legs {
            let mark = match s(l, "status").as_str() { "riding" => "▶", "arrived" => "✓", "cancelled" => "✗", "skipped" => "·", _ => "○" };
            let delay = l["final_delay_min"].as_i64().or(l["delay_min"].as_i64()).unwrap_or(0);
            println!("  {mark} {} {:<8} {} → {}   {} → {}   +{} min   {}", s(l, "leg_no"), s(l, "line"), s(l, "from_station_name"), s(l, "to_station_name"), hhmm(&l["planned_departure"]), hhmm(&l["planned_arrival"]), delay, s(l, "status"));
        }
    }
    if let Some(n) = j.get("next_leg").filter(|n| !n.is_null()) {
        let platform = n["platform"].as_str().map(|p| format!(", Gleis {p}")).unwrap_or_default();
        println!(
            "  → Vorschlag: {} nach {} ab {} {}{}   (bis {} bestätigen)",
            s(n, "line"), s(n, "headsign"), s(n, "from_station_name"), hhmm(&n["live_departure"]).replace('–', &hhmm(&n["planned_departure"])), platform, hhmm(&j["transfer_deadline"])
        );
        if n["replanned"].as_bool().unwrap_or(false) {
            println!("    neu geplant ({})", s(n, "reason"));
        }
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
    // Long enough for a reply read by the model (its budget is 25 s) with the server's own work on top.
    let api = Api { http: reqwest::Client::builder().timeout(Duration::from_secs(60)).build()?, url, token };

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
        Cmd::Journey { customer } => print_journey(&api.get(&format!("/admin/customers/{customer}/journey")).await?),
        Cmd::Confirm { customer, trip } => {
            let body = match trip { Some(t) => json!({ "trip_id": t }), None => json!({}) };
            let v = api.post(&format!("/admin/customers/{customer}/confirm"), body).await?;
            println!("Bestätigt.");
            print_journey(&v);
        }
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
        Cmd::Replies => {
            let v = api.get("/admin/replies").await?;
            for r in v.as_array().into_iter().flatten() {
                println!(
                    "{}  {}  {:<9} {:>6}  {:<32} {}",
                    s(r, "at").chars().take(16).collect::<String>(),
                    s(r, "id"),
                    s(r, "outcome"),
                    r["amount_cents"].as_i64().map(|c| format!("{c} ct")).unwrap_or_default(),
                    s(r, "read_by"),
                    s(r, "from")
                );
                println!("    {}   (Absender geprüft: {})", s(r, "because"), r["sender_verified"].as_str().unwrap_or("nein"));
            }
        }
        Cmd::Reread { mail } => {
            let v = api.post(&format!("/admin/mails/{mail}/reread"), json!({})).await?;
            println!("vorher:  {} {} ct  ({})  {}", s(&v["before"], "outcome"), s(&v["before"], "amount_cents"), s(&v["before"], "read_by"), s(&v["before"], "because"));
            println!("jetzt:   {} {} ct  ({})  {}", s(&v["after"], "outcome"), s(&v["after"], "amount_cents"), s(&v["after"], "read_by"), s(&v["after"], "because"));
            if v["changed"].as_bool() == Some(false) {
                println!("Nichts geändert: {}", s(&v, "why_unchanged"));
            } else {
                println!("Antrag:  {}", v["claim_moved_to"].as_str().unwrap_or("unverändert"));
            }
        }
        Cmd::ReadMail { file, from, subject, claim, to, claimed, date } => {
            let body = if file == "-" {
                let mut b = String::new();
                std::io::Read::read_to_string(&mut std::io::stdin(), &mut b)?;
                b
            } else {
                std::fs::read_to_string(&file)?
            };
            let v = api.post("/admin/read-mail", json!({ "from": from, "subject": subject, "body": body, "claim_id": claim, "to": to, "claimed_cents": claimed, "ride_date": date })).await?;
            let verdict = &v["verdict"];
            let matched = &v["matched"];
            if !matched.is_null() {
                match matched["claim_id"].as_str() {
                    Some(id) => println!("Zugeordnet: Antrag {id} ({}), Fahrgast {} — über {}", s(matched, "claim_status"), s(matched, "customer"), s(matched, "how")),
                    None => println!("Zugeordnet: Fahrgast {}, aber kein offener Antrag — über {}. Es kann sich nichts bewegen.", s(matched, "customer"), s(matched, "how")),
                }
            }
            println!("Gelesen von: {}   (Modell eingerichtet: {})", s(&v, "read_by"), v["model_configured"].as_str().unwrap_or("nein"));
            println!("Ergebnis:    {}   Betrag {} ct", s(verdict, "outcome"), s(verdict, "amount_cents"));
            println!("Weil:        {}", s(verdict, "because"));
            for r in verdict["rides"].as_array().into_iter().flatten() {
                println!("  Fahrt {}  {} {}", s(r, "incident_id"), s(r, "decision"), r["cents"].as_i64().map(|c| format!("{c} ct")).unwrap_or_default());
            }
            let trace = &v["trace"];
            if let Some(answer) = trace.get("answer") {
                println!("\nModell sagt: {}", serde_json::to_string_pretty(answer)?);
            }
            if let Some(err) = trace["extra"].get("error").or_else(|| trace.get("error")) {
                println!("\nModell nicht erreichbar: {err}");
            }
            if let Some(shown) = trace["shown"].as_str() {
                println!("\nDas hat das Modell gesehen:\n{shown}");
            }
        }
        Cmd::Clock { shift } => {
            let v = match shift {
                Some(sh) if sh == "now" || sh == "0" => api.post("/admin/clock", json!({ "offset_secs": 0 })).await?,
                Some(sh) => api.post("/admin/clock", json!({ "shift": sh })).await?,
                None => api.get("/admin/clock").await?,
            };
            println!("Uhr: {}  (Versatz {} s)", s(&v, "now"), s(&v, "offset_secs"));
        }
        Cmd::Switch { name, value } => {
            let v = match (name.as_deref(), value.as_deref()) {
                (None, _) | (Some("stations-local"), None) => api.get("/admin/switches").await?,
                (Some("stations-local"), Some(x)) => {
                    let on = match x {
                        "on" | "true" | "1" | "an" => true,
                        "off" | "false" | "0" | "aus" => false,
                        _ => anyhow::bail!("on oder off, nicht {x:?}"),
                    };
                    api.post("/admin/switches", json!({ "stations_local": on })).await?
                }
                (Some(other), _) => anyhow::bail!("unbekannter Schalter {other:?}; bekannt: stations-local"),
            };
            let local = v.get("stations_local").and_then(Value::as_bool).unwrap_or(false);
            println!(
                "stations-local: {}   (Bahnhöfe im Hintergrund {})",
                if local { "an" } else { "aus" },
                if local { "aus der Datei" } else { "vom Server" }
            );
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
        Cmd::Route { cmd } => match cmd {
            RouteCmd::List => {
                let v = api.get("/admin/routes").await?;
                let rows = v.as_array().cloned().unwrap_or_default();
                if rows.is_empty() {
                    println!("Keine Route. Es kann nichts rausgehen, bis eine existiert:");
                    println!("  stellwerk route set \"Servicecenter Fahrgastrechte\" du@example.org");
                    println!("  stellwerk route default du@example.org      # für jeden Schalter ohne eigene Route");
                } else {
                    println!("{:<34} {:<34} Bezeichnung", "Schalter", "geht wirklich an");
                    for r in rows {
                        // „*" is the catch-all, and a column of asterisks explains nothing. It
                        // sorts first, so it reads as the heading of the list it governs.
                        let desk = match r["desk"].as_str().unwrap_or("–") {
                            "*" => "Auffanglinie (jeder andere)",
                            d => d,
                        };
                        println!(
                            "{:<34} {:<34} {}",
                            desk,
                            r["to_address"].as_str().unwrap_or("–"),
                            r["label"].as_str().unwrap_or("–")
                        );
                        println!("  Antworten zählen von: {}", strings(&r["answer_domains"]).join(", "));
                        let free = strings(&r["free_mail_answer_domains"]);
                        if !free.is_empty() {
                            println!("  ⚠  {} ist ein Freemail-Anbieter: jede Adresse dort kann Geld bestätigen.", free.join(", "));
                        }
                        if !r["matches_a_desk"].as_bool().unwrap_or(true) {
                            println!(
                                "  ⚠  Kein Antrag trägt diesen Schalter. Die Route greift nie. Bekannte Schalter: {}",
                                api.get("/admin/desks").await.ok()
                                    .and_then(|v| v.as_array().map(|a| a.iter().filter_map(|d| d.as_str()).collect::<Vec<_>>().join(", ")))
                                    .unwrap_or_default()
                            );
                        }
                    }
                }
            }
            RouteCmd::Set { desk, to, label, postal, note } => {
                let mut body = serde_json::Map::new();
                body.insert("to_address".into(), json!(to));
                body.insert("label".into(), json!(label.unwrap_or_else(|| "Fahrgastrechte-Stelle".into())));
                if let Some(p) = postal {
                    body.insert("postal_address".into(), json!(p));
                }
                if let Some(n) = note {
                    body.insert("note".into(), json!(n));
                }
                body.insert("desk".into(), json!(desk));
                let v = api.put("/admin/routes", Value::Object(body)).await?;
                println!("{} → {}  ({})", desk, v["to_address"].as_str().unwrap_or("–"), v["label"].as_str().unwrap_or("–"));
                println!("  Antworten zählen von: {}", strings(&v["answer_domains"]).join(", "));
            }
            // The catch-all is an ordinary route under the reserved key „*"; the subcommand exists
            // so nobody has to quote a shell glob and so `--help` says what it is for.
            RouteCmd::Default { to, label, postal, note, remove } => {
                if remove {
                    api.post("/admin/routes/remove", json!({ "desk": "*" })).await?;
                    println!("Auffanglinie entfernt. Ein Schalter ohne eigene Route kann jetzt nichts mehr senden.");
                } else if let Some(to) = to {
                    let mut body = serde_json::Map::new();
                    body.insert("desk".into(), json!("*"));
                    body.insert("to_address".into(), json!(to));
                    body.insert("label".into(), json!(label.unwrap_or_else(|| "Auffanglinie".into())));
                    if let Some(p) = postal {
                        body.insert("postal_address".into(), json!(p));
                    }
                    if let Some(n) = note {
                        body.insert("note".into(), json!(n));
                    }
                    let v = api.put("/admin/routes", Value::Object(body)).await?;
                    println!("Auffanglinie → {}  ({})", v["to_address"].as_str().unwrap_or("–"), v["label"].as_str().unwrap_or("–"));
                    println!("  Jeder Schalter ohne eigene Route sendet hierhin.");
                    println!("  Antworten zählen von: {}", strings(&v["answer_domains"]).join(", "));
                } else {
                    let rows = api.get("/admin/routes").await?;
                    match rows.as_array().and_then(|a| a.iter().find(|r| r["desk"] == "*")) {
                        Some(r) => {
                            println!("Auffanglinie → {}  ({})", s(r, "to_address"), s(r, "label"));
                            println!("  Antworten zählen von: {}", strings(&r["answer_domains"]).join(", "));
                        }
                        None => println!("Keine Auffanglinie. Ein Schalter ohne eigene Route sendet nichts."),
                    }
                }
            }
            RouteCmd::Remove { desk } => {
                api.post("/admin/routes/remove", json!({ "desk": desk })).await?;
                println!("{desk}: Route entfernt. An diesen Schalter geht jetzt nichts mehr raus.");
            }
            RouteCmd::Answers { desk, add, remove, clear, force } => {
                let v = api.post("/admin/routes/answers", json!({ "desk": desk, "add": add, "remove": remove, "clear": clear, "force": force })).await?;
                println!("{desk} → {}", s(&v, "to_address"));
                println!("  Antworten zählen von: {}", strings(&v["answer_domains"]).join(", "));
                println!("  (Subdomains zählen mit; die Domain der Zieladresse immer.)");
            }
        },
        Cmd::Ngo { cmd } => match cmd {
            NgoCmd::List => {
                let v = api.get("/admin/ngos").await?;
                println!("{:<24} {:<32} {:<8} {:<11} {:<11} {:<8} {:<10} IBAN", "ID", "Name", "aktiv", "bestätigt", "eingereicht", "Kunden", "Consent");
                for n in v.as_array().unwrap_or(&vec![]) {
                    println!(
                        "{:<24} {:<32} {:<8} {:>9} € {:>9} € {:<8} {:<10} {}",
                        s(n, "id"),
                        s(n, "name").chars().take(32).collect::<String>(),
                        if n["active"].as_bool().unwrap_or(false) { "ja" } else { "nein" },
                        n["confirmed_total_cents"].as_i64().unwrap_or(0) / 100,
                        n["submitted_total_cents"].as_i64().unwrap_or(0) / 100,
                        s(n, "customers"),
                        n["consent_date"].as_str().unwrap_or("–"),
                        s(n, "iban")
                    );
                }
            }
            NgoCmd::Set { id, name, tagline, story, holder, iban, donation_url, seed_confirmed, seed_submitted, consent, logo, active, inactive } => {
                let mut body = serde_json::Map::new();
                if let Some(v) = name { body.insert("name".into(), json!(v)); }
                if let Some(v) = tagline { body.insert("tagline".into(), json!(v)); }
                if !story.is_empty() { body.insert("story".into(), json!(story)); }
                if let Some(v) = holder { body.insert("account_holder".into(), json!(v)); }
                if let Some(v) = iban { body.insert("iban".into(), json!(v)); }
                if let Some(v) = seed_confirmed { body.insert("seed_confirmed_cents".into(), json!(v)); }
                if let Some(v) = seed_submitted { body.insert("seed_submitted_cents".into(), json!(v)); }
                if let Some(v) = donation_url { body.insert("donation_url".into(), json!(v)); }
                if let Some(v) = consent { body.insert("consent_date".into(), json!(v)); }
                if let Some(path) = logo {
                    // Inline, because the card is drawn on a phone that may be underground and
                    // there is nowhere to host partner logos (docs/27 §5).
                    if path.is_empty() {
                        body.insert("logo".into(), Value::Null);
                    } else {
                        let bytes = std::fs::read(&path)?;
                        let mime = if path.to_lowercase().ends_with(".svg") { "image/svg+xml" } else { "image/png" };
                        let b64 = base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &bytes);
                        if bytes.len() > 200_000 {
                            anyhow::bail!("{path} is {} KB; keep a logo under 200 KB — it rides along with every NGO fetch", bytes.len() / 1024);
                        }
                        body.insert("logo".into(), json!(format!("data:{mime};base64,{b64}")));
                    }
                }
                if active { body.insert("active".into(), json!(true)); }
                if inactive { body.insert("active".into(), json!(false)); }
                let v = api.put(&format!("/admin/ngos/{id}"), Value::Object(body)).await?;
                println!("{} · {} · {} · {} · aktiv: {}", s(&v, "id"), s(&v, "name"), s(&v, "account_holder"), s(&v, "iban"), v["active"].as_bool().unwrap_or(false));
            }
            NgoCmd::Import { file } => {
                let v: Value = serde_json::from_str(&std::fs::read_to_string(&file)?)?;
                let items: Vec<Value> = match v {
                    Value::Array(a) => a,
                    o => vec![o],
                };
                for item in items {
                    let id = item["id"].as_str().ok_or_else(|| anyhow::anyhow!("every NGO needs an \"id\""))?.to_string();
                    let r = api.put(&format!("/admin/ngos/{id}"), item).await?;
                    println!("{} · {} · {}", s(&r, "id"), s(&r, "name"), s(&r, "iban"));
                }
            }
            NgoCmd::Remove { id } => {
                let v = api.delete(&format!("/admin/ngos/{id}")).await?;
                println!("{}", if v["deleted"].as_bool().unwrap_or(false) { "gelöscht" } else { "deaktiviert (wird referenziert)" });
            }
        },
        Cmd::Stations { cmd } => match cmd {
            StationsCmd::Import { from, out, dry_run, force, check } => {
                // The commentary goes to stderr so that the result on stdout stays pipeable, and
                // it goes out at all because this takes minutes and silence would read as a hang.
                let progress = std::sync::Arc::new(|line: &str| eprintln!("  {line}"));
                let set = gtfs::build(gtfs::BuildOptions { from, progress: Some(progress) }).await?;
                let r = gtfs::ranks(&set);
                println!(
                    "{} Stationen  ·  Fern {}  ·  Nahverkehr {}  ·  nur S-Bahn {}  ·  Fahrplanstand {}",
                    set.stations.len(),
                    r[3],
                    r[2],
                    r[1],
                    set.feed_version.as_deref().unwrap_or("–")
                );
                if let Some(path) = &out {
                    std::fs::write(path, serde_json::to_vec_pretty(&set)?)?;
                    println!("Geschrieben: {}", path.display());
                }
                // An id that is verbatim in stops.txt is still only a guess about what MOTIS
                // answers to until MOTIS has answered to it.
                if check > 0 {
                    let (ok, tried, failures) = gtfs::sample_upstream(&set, check).await?;
                    println!("Stichprobe bei Transitous: {ok} von {tried} Ids beantwortet");
                    for f in failures.iter().take(10) {
                        println!("  {f}");
                    }
                    if ok < tried && !force {
                        anyhow::bail!("{} Id(s) kennt die API nicht — nichts gesendet (--check 0 oder --force)", tried - ok);
                    }
                }
                let v = api
                    .patient(600)?
                    .post(&format!("/admin/stations/import?force={force}&dry_run={dry_run}"), serde_json::to_value(&set)?)
                    .await?;
                println!(
                    "{}: {} neu  ·  {} stillgelegt  ·  {} verschoben  ·  {} umbenannt  ·  {} insgesamt",
                    if v["committed"].as_bool().unwrap_or(false) { "Übernommen" } else { "Nicht übernommen" },
                    s(&v, "added"),
                    s(&v, "retired"),
                    s(&v, "moved"),
                    s(&v, "renamed"),
                    s(&v, "total")
                );
                if let Some(note) = v["note"].as_str() {
                    println!("  {note}");
                }
                // The import is what makes the probe fixture stale — the extract is merely the
                // next thing anybody runs. Every reader suite that consumes that file pins its
                // `crc32`/`count` against the table, so without this they go red together and the
                // cause is two commands back. It fails safely: a stale fixture cannot pass
                // wrongly, only fail loudly — but the next person should not have to work that
                // out at midnight.
                if v["committed"].as_bool().unwrap_or(false) {
                    println!("  Die Tabelle ist neu — der Probe-Fixture gehört noch zur alten und macht die Leser-Tests rot");
                    println!("  (laut und richtig benannt, nie still falsch). Neu erzeugen:");
                    println!("    cd backend && cargo test --release --lib write_the_nearby_probe_fixture -- --ignored");
                }
            }
            StationsCmd::Extract { out, keep, asset, dry_run } => {
                let root = repo_root();
                // A version is a station_imports id and means nothing outside its own database.
                // Writing a dev extract into the repo would publish the laptop's table under
                // production's filename, and the --keep sweep would then delete the real one.
                let dir = match out {
                    Some(d) => d,
                    None => {
                        anyhow::ensure!(
                            name == "prod",
                            "in den Baum schreibt nur --prod (die Version ist eine station_imports-Id und gilt nur für ihre Datenbank). Sonst --out <dir>."
                        );
                        root.join("site/static/stations")
                    }
                };

                // The extract first: its header carries the version, so the status call is only
                // needed for the Fahrplanstand and the count cross-check.
                let bytes = api.patient(120)?.get_bytes("/admin/stations/extract").await?;
                // The laptop runs the reader the phone will run, before anything is written.
                let read = extract::parse(&bytes)?;
                let version = read.version;
                anyhow::ensure!(version > 0, "Auszug ohne Version: kein übernommener Import. Erst `stellwerk stations import`.");

                let status = api.get("/admin/stations").await?;
                let live = status["live"].as_u64().unwrap_or(0);
                let feed_version = status["feed_version"].as_str().map(str::to_string);
                anyhow::ensure!(
                    status["version"].as_u64().unwrap_or(0) as u32 == version && read.stations.len() as u64 == live,
                    "Auszug {version} mit {} Stationen passt nicht zu Import {} mit {live} — dazwischen lief ein Import. Nochmal laufen lassen.",
                    read.stations.len(),
                    status["version"]
                );

                // The gzip sibling Caddy serves with `precompressed gzip`. Its mtime is the
                // import's, not the clock's, so the same table gzips to the same bytes.
                let gz = {
                    use std::io::Write;
                    let mut e = flate2::GzBuilder::new().mtime(read.generated).write(Vec::new(), flate2::Compression::best());
                    e.write_all(&bytes)?;
                    e.finish()?
                };
                let pointer = ExtractPointer {
                    version,
                    format: read.format,
                    count: read.stations.len() as u32,
                    bytes: bytes.len() as u64,
                    crc32: read.crc32,
                    generated: chrono::DateTime::from_timestamp(read.generated as i64, 0)
                        .unwrap_or_default()
                        .to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
                    feed_version: feed_version.clone(),
                    url: format!("/stations/stations-{version}.vst"),
                };
                let mut pointer_bytes = serde_json::to_vec_pretty(&pointer)?;
                pointer_bytes.push(b'\n');

                let vst = dir.join(format!("stations-{version}.vst"));
                let vstgz = dir.join(format!("stations-{version}.vst.gz"));
                let json = dir.join("latest.json");
                let asset_path = root.join("app/assets/stations/stations.vst");

                println!(
                    "Auszug {version}  ·  {} Stationen  ·  {}  ·  Fahrplanstand {}  ·  CRC {:08x}",
                    read.stations.len(),
                    kb(bytes.len(), gz.len()),
                    feed_version.as_deref().unwrap_or("–"),
                    read.crc32
                );
                if dry_run {
                    println!("Trockenlauf: nichts geschrieben.");
                    return Ok(());
                }

                // Every artefact, not just the .vst. Saying "unverändert" after checking one of
                // four is claiming a state nobody verified.
                let mut planned: Vec<(PathBuf, &[u8])> =
                    vec![(vst, &bytes), (vstgz, &gz), (json, &pointer_bytes)];
                if asset {
                    // Same reason the site files need --prod, and one degree nastier. The app only
                    // downloads a pointer whose version is *greater* than the one it already holds
                    // (`station_store.dart:149`), and a dev version is whatever the laptop's
                    // station_imports counter happens to have reached — higher than production's
                    // almost immediately. Shipping a dev-rendered asset would therefore not go
                    // stale loudly; it would pin every phone to the laptop's table for good and
                    // never ask again.
                    anyhow::ensure!(
                        name == "prod",
                        "--asset schreibt den Auszug in die App und geht nur mit --prod: die App lädt nur eine höhere Version nach, und eine Dev-Version ist höher als die echte."
                    );
                    planned.push((asset_path, &bytes));
                }
                let todo: Vec<(PathBuf, &[u8])> = planned
                    .into_iter()
                    .filter(|(p, want)| std::fs::read(p).map(|old| old != *want).unwrap_or(true))
                    .collect();
                if todo.is_empty() {
                    println!("Unverändert: Auszug {version} liegt vollständig im Baum.");
                    return Ok(());
                }
                for (p, content) in &todo {
                    if let Some(parent) = p.parent() {
                        std::fs::create_dir_all(parent)?;
                    }
                    std::fs::write(p, content)?;
                    println!("Geschrieben: {}", rel(&root, p));
                }

                // Keep the previous one: a phone that read latest.json a moment before the deploy
                // is still asking for the file it was told about.
                let mut old: Vec<(u32, PathBuf)> = std::fs::read_dir(&dir)?
                    .filter_map(|e| e.ok())
                    .filter_map(|e| {
                        let n = e.file_name().to_string_lossy().to_string();
                        let v: u32 = n.strip_prefix("stations-")?.strip_suffix(".vst")?.parse().ok()?;
                        (v != version).then(|| (v, e.path()))
                    })
                    .collect();
                old.sort_by(|a, b| b.0.cmp(&a.0));
                for (v, path) in old.into_iter().skip(keep) {
                    std::fs::remove_file(&path).ok();
                    std::fs::remove_file(path.with_extension("vst.gz")).ok();
                    println!("Entfernt: stations-{v}.vst und stations-{v}.vst.gz");
                }
                println!(
                    "Weiter: Probe-Fixture neu erzeugen  ·  cd site && cargo run  ·  site/dist committen  ·  deployen  ·  danach erst die App bauen."
                );
                println!("  Fixture: cd backend && cargo test --release --lib write_the_nearby_probe_fixture -- --ignored");
            }
        },
        Cmd::MailTest { customer, to, claim } => {
            let v = api.post(&format!("/admin/customers/{customer}/mail-test"), json!({ "to": to, "claim": claim })).await?;
            println!("{} → {} · {}", s(&v, "from"), s(&v, "to"), if v["dry_run"].as_bool().unwrap_or(true) { "Trockenlauf (SMTP_URL nicht gesetzt)" } else { "gesendet" });
        }
        Cmd::Push { customer, text } => {
            let v = api.post(&format!("/admin/customers/{customer}/push"), json!({ "text": text })).await?;
            let platform = v["platform"].as_str().unwrap_or("–");
            let token = if v["token"].as_bool().unwrap_or(false) { "Token da" } else { "kein Token" };
            let how = if v["configured"].as_bool().unwrap_or(false) { "Provider konfiguriert" } else { "Dry-Run, nur Log" };
            println!("Push an {} ({platform}, {token}, {how}): {}", s(&v, "nickname"), s(&v, "result"));
            println!("  {} – {}", s(&v, "title"), s(&v, "body"));
        }
        Cmd::Backdate { customer, delay, days, count, at, duration, from, to, line, category, operator, ticket, cancelled } => {
            if count < 1 {
                anyhow::bail!("--count must be at least 1");
            }
            let mut warned = false;
            for i in 0..count {
                let body = json!({
                    "from": from, "to": to, "delay_minutes": delay, "days_ago": days + i, "departure": at,
                    "duration_minutes": duration, "line": line, "category": category, "operator": operator,
                    "ticket": ticket, "cancelled": cancelled,
                });
                let v = api.post(&format!("/admin/customers/{customer}/backdate"), body).await?;
                let j = &v["journey"];
                println!(
                    "{}  {}  {} → {}  ·  +{} min  ·  {} Punkte",
                    dhm(&j["planned_departure"]), s(&v["ride"], "line"), s(j, "origin_station_name"), s(j, "destination_station_name"),
                    s(j, "final_delay_min"), s(&v, "points")
                );
                match v.get("incident").filter(|i| !i.is_null()) {
                    Some(inc) => println!("    Anspruch {} ct  ·  {}  ·  {}  ·  Frist {}", s(inc, "amount_cents"), s(inc, "status"), s(inc, "desk"), s(inc, "legal_deadline")),
                    None => println!("    Kein Anspruch (unter 60 Minuten)."),
                }
                if let Some(b) = v.get("new_badge").filter(|b| !b.is_null()) {
                    println!("    Abzeichen: {}", s(b, "name"));
                }
                if !warned && v["operator_known"].as_bool() == Some(false) {
                    println!("    Hinweis: »{operator}« steht nicht im Betreiberverzeichnis; die Stelle heißt deshalb »Unbekannt«.");
                    warned = true;
                }
            }
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
