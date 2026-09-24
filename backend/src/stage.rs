//! Which server this is: `ENVIRONMENT` = `development` (the default, a laptop), `staging` or
//! `production`. Read once, at first use.
//!
//! Two things depend on it. Production refuses the Stellwerk calls that change the world a
//! customer sees — a delay, a fast-forward, a railway answer, a position — because there they
//! would be lies about real journeys ([`Simulation`]). And staging sends mail only to the domains
//! it is told it may ([`mail_allowed`]), so a route pointing at a railway desk cannot reach one.

use std::sync::OnceLock;

use axum::{extract::FromRequestParts, http::request::Parts, http::StatusCode, Json};
use serde_json::{json, Value};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Stage {
    Development,
    Staging,
    Production,
}

impl Stage {
    pub fn name(self) -> &'static str {
        match self {
            Stage::Development => "development",
            Stage::Staging => "staging",
            Stage::Production => "production",
        }
    }

    fn parse(s: &str) -> anyhow::Result<Stage> {
        match s.trim().to_ascii_lowercase().as_str() {
            "" | "development" | "dev" => Ok(Stage::Development),
            "staging" => Ok(Stage::Staging),
            "production" | "prod" => Ok(Stage::Production),
            other => anyhow::bail!("ENVIRONMENT={other}: expected development, staging or production"),
        }
    }
}

static CURRENT: OnceLock<Stage> = OnceLock::new();

/// The stage from `ENVIRONMENT`. A value that is none of the three stops the API at startup
/// ([`check`]) instead of quietly meaning „development" — which would open the simulation calls.
pub fn current() -> Stage {
    *CURRENT.get_or_init(|| Stage::parse(&std::env::var("ENVIRONMENT").unwrap_or_default()).unwrap_or(Stage::Development))
}

/// Called once from `main` before anything is served.
pub fn check() -> anyhow::Result<Stage> {
    Stage::parse(&std::env::var("ENVIRONMENT").unwrap_or_default())?;
    Ok(current())
}

/// The commit the binary was built from, when the build said (`GIT_SHA`, a Docker build arg).
pub fn commit() -> &'static str {
    option_env!("GIT_SHA").filter(|s| !s.is_empty()).unwrap_or("unknown")
}

/// Extractor for the Stellwerk calls that simulate the world. Refused in production.
pub struct Simulation;

impl<S: Send + Sync> FromRequestParts<S> for Simulation {
    type Rejection = (StatusCode, Json<Value>);
    async fn from_request_parts(_parts: &mut Parts, _s: &S) -> Result<Self, Self::Rejection> {
        if current() == Stage::Production {
            Err((StatusCode::FORBIDDEN, Json(json!({ "error": "not in production: this call simulates the world" }))))
        } else {
            Ok(Simulation)
        }
    }
}

/// Whether mail to `address` may leave this server. Production and development: always (the
/// routes table decides where claims go). Staging: only to a domain on `MAIL_ALLOW`
/// (comma-separated) or to its own `RELAY_DOMAIN`. Unset means nothing leaves.
pub fn mail_allowed(address: &str) -> bool {
    if current() != Stage::Staging {
        return true;
    }
    allowed_by(address, &std::env::var("MAIL_ALLOW").unwrap_or_default(), std::env::var("RELAY_DOMAIN").ok().as_deref())
}

fn allowed_by(address: &str, allow: &str, relay: Option<&str>) -> bool {
    // „Name <a@b>" as well as the bare address.
    let addr = address.rsplit('<').next().unwrap_or(address).trim_end_matches('>').trim();
    let Some((_, domain)) = addr.rsplit_once('@') else { return false };
    let domain = domain.to_ascii_lowercase();
    relay.into_iter().chain(allow.split(',')).map(|d| d.trim().trim_start_matches('@').to_ascii_lowercase()).any(|d| !d.is_empty() && d == domain)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stages_parse_and_nonsense_does_not() {
        assert_eq!(Stage::parse("").unwrap(), Stage::Development);
        assert_eq!(Stage::parse("Staging").unwrap(), Stage::Staging);
        assert_eq!(Stage::parse("prod").unwrap(), Stage::Production);
        assert!(Stage::parse("prodution").is_err());
    }

    #[test]
    fn the_allowlist_matches_whole_domains_only() {
        let allow = "zoom7.de, @verspaetomat.de";
        assert!(allowed_by("info@zoom7.de", allow, None));
        assert!(allowed_by("Verspätomat <team@verspaetomat.de>", allow, None));
        assert!(allowed_by("fahrgast-1@users.staging.verspaetomat.de", "", Some("users.staging.verspaetomat.de")));
        assert!(!allowed_by("fahrgastrechte@bahn.de", allow, None));
        assert!(!allowed_by("x@evilzoom7.de", allow, None));
        assert!(!allowed_by("x@sub.verspaetomat.de", allow, None));
        assert!(!allowed_by("no-at-sign", allow, None));
        assert!(!allowed_by("x@zoom7.de", "", None));
    }
}
