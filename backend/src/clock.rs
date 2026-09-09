//! The system clock with a Stellwerk offset. Every "now" in the backend goes through here,
//! so a clock shift moves deadlines, reply nudges and the follower alike.

use std::sync::atomic::{AtomicI64, Ordering};

use chrono::{DateTime, Duration, NaiveDate, Utc};
use sqlx::PgPool;

static OFFSET_SECS: AtomicI64 = AtomicI64::new(0);

pub fn now() -> DateTime<Utc> {
    Utc::now() + Duration::seconds(OFFSET_SECS.load(Ordering::Relaxed))
}

pub fn today() -> NaiveDate {
    now().date_naive()
}

pub fn offset_secs() -> i64 {
    OFFSET_SECS.load(Ordering::Relaxed)
}

pub async fn load(pool: &PgPool) -> anyhow::Result<()> {
    let off: Option<i64> = sqlx::query_scalar("select offset_secs from sim_clock where id = 1").fetch_optional(pool).await?;
    OFFSET_SECS.store(off.unwrap_or(0), Ordering::Relaxed);
    Ok(())
}

pub async fn set_offset(pool: &PgPool, secs: i64) -> anyhow::Result<()> {
    sqlx::query("update sim_clock set offset_secs = $1, updated_at = now() where id = 1").bind(secs).execute(pool).await?;
    OFFSET_SECS.store(secs, Ordering::Relaxed);
    Ok(())
}

/// "+100d", "-2h", "+90m", "3h30m", "0" → seconds.
pub fn parse_shift(s: &str) -> Option<i64> {
    let s = s.trim();
    if s == "0" || s.eq_ignore_ascii_case("now") {
        return Some(0);
    }
    let (sign, rest) = match s.chars().next()? {
        '+' => (1, &s[1..]),
        '-' => (-1, &s[1..]),
        _ => (1, s),
    };
    let mut total = 0i64;
    let mut num = String::new();
    for c in rest.chars() {
        if c.is_ascii_digit() {
            num.push(c);
        } else {
            let n: i64 = num.parse().ok()?;
            num.clear();
            total += match c {
                'd' => n * 86_400,
                'h' => n * 3_600,
                'm' => n * 60,
                's' => n,
                _ => return None,
            };
        }
    }
    if !num.is_empty() {
        // bare number = minutes
        total += num.parse::<i64>().ok()? * 60;
    }
    Some(sign * total)
}

#[cfg(test)]
mod tests {
    use super::parse_shift;
    #[test]
    fn shifts() {
        assert_eq!(parse_shift("+100d"), Some(8_640_000));
        assert_eq!(parse_shift("-2h"), Some(-7200));
        assert_eq!(parse_shift("3h30m"), Some(12_600));
        assert_eq!(parse_shift("+25"), Some(1500));
        assert_eq!(parse_shift("now"), Some(0));
        assert_eq!(parse_shift("x"), None);
    }
}
