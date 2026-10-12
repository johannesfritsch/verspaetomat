//! Puzzles (docs/51): every finished journey brings one piece of a picture a Verein sent us.
//!
//! Which piece is a pure function over the pictures, the customer's own Vereine, the journey's
//! tier and a roll of the dice ([`choose`]), so the rules of §2 and §2a are tested without a
//! database. [`award`] runs it where the ways a journey ends meet — `journeys::finalise_journey`
//! and the abort in `journeys::finish` — and writes the piece; `GET /v1/journeys/current` and `GET /v1/me/puzzles` read it back.

use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use axum::body::Bytes;
use chrono::{DateTime, NaiveDate, TimeZone, Utc};
use std::collections::HashMap;
use serde_json::{json, Value};
use sqlx::{PgConnection, PgPool};
use uuid::Uuid;

use crate::auth::{internal, Customer};
use crate::db::rows::*;
use crate::AppState;

/// At most this many pieces per customer and Berlin calendar day (docs/51 §3): against checking
/// in and out on the sofa. A commuter's way there, way back and one errand never reach it.
pub const MAX_PER_DAY: i64 = 3;
/// The largest picture the admin route takes, decoded.
pub const MAX_BYTES: usize = 1_000_000;
/// The most pixels a picture may have: 1 MB of JPEG or a flat PNG can hold far more than a phone
/// should decode for a card. The longest side, and the whole.
pub const MAX_SIDE: u32 = 2400;
pub const MAX_PIXELS: u64 = 6_000_000;
/// A piece's width over its height, both ends inclusive: roughly square, or the noses look wrong.
pub const PIECE_ASPECT: (f64, f64) = (0.66, 1.5);

// ---------------------------------------------------------------------------
// Pure rules
// ---------------------------------------------------------------------------

/// How rare a piece is: how long the journey that brought it waited (docs/51 §2a). Ordered, so a
/// rarer piece compares greater.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Tier {
    Minute,
    Quarter,
    Hour,
}

impl Tier {
    pub const ALL: [Tier; 3] = [Tier::Minute, Tier::Quarter, Tier::Hour];

    pub fn as_str(self) -> &'static str {
        match self {
            Tier::Minute => "minute",
            Tier::Quarter => "quarter",
            Tier::Hour => "hour",
        }
    }

    pub fn parse(s: &str) -> Option<Tier> {
        Tier::ALL.into_iter().find(|t| t.as_str() == s)
    }

    /// The tier a journey's counted minutes earn: an hour from 60 on — the delay that becomes a
    /// claim — a quarter from 15, else a minute. It follows the minutes the journey shows, nothing
    /// else: a cancelled last leg the follower finalises counts 60 (`rules::counted_minutes`) and
    /// earns the hour, while „Ich bin da" on a cancelled leg finalises an arrival and counts the
    /// delay it saw.
    pub fn for_minutes(counted: i64) -> Tier {
        match counted {
            60.. => Tier::Hour,
            15..=59 => Tier::Quarter,
            _ => Tier::Minute,
        }
    }
}

/// A number from the image id and a slot, the same on every machine and every run: the order in
/// which ties and the scattering of quarters fall, without storing a seed.
fn slot_hash(id: Uuid, salt: &[u8], slot: i32) -> u64 {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(id.as_bytes());
    h.update(salt);
    h.update(slot.to_be_bytes());
    u64::from_be_bytes(h.finalize()[..8].try_into().expect("8 bytes"))
}

/// The tier of every slot of a new picture, row by row (docs/51 §2a). For n slots: max(1, n/12)
/// hours, n/4 quarters, both rounded, and minutes for the rest — 12 → 1/3/8, 20 → 2/5/13,
/// 30 → 3/8/19. The hours are the slots nearest the centre, the heart of the picture; the
/// quarters are scattered over the rest. Both follow from the image id alone.
pub fn default_tiers(id: Uuid, rows: i32, cols: i32) -> Vec<Tier> {
    let n = rows * cols;
    let hours = ((n as f64 / 12.0).round() as i32).max(1) as usize;
    let quarters = (n as f64 / 4.0).round() as usize;
    // Twice the distance from the centre, squared, in whole numbers: no rounding decides a tie.
    let off_centre = |slot: i32| {
        let (dr, dc) = (2 * (slot / cols) + 1 - rows, 2 * (slot % cols) + 1 - cols);
        dr * dr + dc * dc
    };
    let mut slots: Vec<i32> = (0..n).collect();
    slots.sort_by_key(|&s| (off_centre(s), slot_hash(id, b"hour", s)));
    let (heart, rest) = slots.split_at_mut(hours.min(n as usize));
    rest.sort_by_key(|&s| slot_hash(id, b"quarter", s));
    let mut tiers = vec![Tier::Minute; n as usize];
    for &s in heart.iter() {
        tiers[s as usize] = Tier::Hour;
    }
    for &s in rest.iter().take(quarters) {
        tiers[s as usize] = Tier::Quarter;
    }
    tiers
}

/// One picture as the choice sees it.
#[derive(Debug, Clone)]
pub struct Image {
    pub id: Uuid,
    pub ngo_id: String,
    /// The tier of every slot, row by row; rows · cols of them.
    pub tiers: Vec<Tier>,
    /// Retired, or its Verein is no longer active: nobody starts it any more.
    pub closed: bool,
    /// The pieces this customer holds.
    pub owned: Vec<i32>,
}

impl Image {
    fn started(&self) -> bool {
        !self.owned.is_empty()
    }

    /// The open slots of this tier.
    fn missing(&self, tier: Tier) -> Vec<i32> {
        (0..self.tiers.len() as i32).filter(|p| self.tiers[*p as usize] == tier && !self.owned.contains(p)).collect()
    }

    fn complete(&self) -> bool {
        self.owned.len() >= self.tiers.len()
    }
}

/// The dice: which side (one in four is another Verein's), which picture when it is down to
/// chance, which of the missing pieces. Rolled once per award; tests pass their own.
#[derive(Debug, Clone, Copy)]
pub struct Dice {
    pub side: u32,
    pub pick: u64,
    pub piece: u64,
}

impl Dice {
    pub fn roll() -> Dice {
        Dice { side: rand::random_range(0..4), pick: rand::random(), piece: rand::random() }
    }
}

/// The pictures that can still bring a piece (docs/51 §2.2, §2a): every one this customer has
/// started and not finished — a retired one too, when it was started before — and per Verein the
/// oldest one they have not started that is still handed out. So a Verein can have two open: one
/// waiting for its rare piece, and the next, which the common pieces start meanwhile. `images`
/// come in the order they were added, and so does the answer.
pub fn candidates(images: &[Image]) -> Vec<&Image> {
    let mut next_of: Vec<&str> = Vec::new();
    images
        .iter()
        .filter(|i| {
            if i.started() {
                return !i.complete();
            }
            if i.closed || next_of.contains(&i.ngo_id.as_str()) {
                return false;
            }
            next_of.push(&i.ngo_id);
            true
        })
        .collect()
}

/// Which picture, which piece and its tier, or nothing when no open slot is left that a journey
/// of `tier` may fill (docs/51 §2, §2a).
///
/// Three of four pieces come from the customer's own Vereine (`own`: the one chosen now, and every
/// one a case or a claim of theirs went to), one from another. The tier comes before the side: a
/// slot of exactly the journey's tier first, on the rolled side and then on the other, in any
/// picture there — the next picture of a Verein included — and only when neither side has one,
/// the next tier down, the same way. A rare piece is never spent on a common slot while a slot of
/// its own kind waits anywhere, and a common one never fills a rare slot. Among the pictures with
/// such a slot, a started one comes before a new one, then the one with the most pieces, then on
/// the own side the chosen Verein's (`current`), then chance. The slot is chance among the open
/// ones of its tier, so a piece never repeats.
pub fn choose(images: &[Image], own: &[String], current: &str, tier: Tier, dice: &Dice) -> Option<(Uuid, i32, Tier)> {
    let (mine, others): (Vec<&Image>, Vec<&Image>) = candidates(images).into_iter().partition(|i| own.contains(&i.ngo_id));
    let sides = if dice.side.is_multiple_of(4) { [(&others, false), (&mine, true)] } else { [(&mine, true), (&others, false)] };
    let chosen = Tier::ALL.into_iter().rev().filter(|t| *t <= tier).find_map(|t| {
        sides.iter().find_map(|&(side, is_mine)| {
            let rank = |i: &Image| (i.started(), i.owned.len(), is_mine && i.ngo_id == current);
            let open: Vec<&Image> = side.iter().copied().filter(|i| !i.missing(t).is_empty()).collect();
            let best = open.iter().map(|i| rank(i)).max()?;
            let ties: Vec<&Image> = open.into_iter().filter(|i| rank(i) == best).collect();
            let image = ties[(dice.pick % ties.len() as u64) as usize];
            let slots = image.missing(t);
            Some((image.id, slots[(dice.piece % slots.len() as u64) as usize], t))
        })
    });
    chosen
}

/// Does this ending bring a piece (docs/51 §3)? Arrived — on foot, by the follower, after a
/// cancelled last leg or a transfer that timed out — or given up: the waiting happened. Never
/// having boarded brings nothing.
pub fn earns_piece(j: &JourneyRow) -> bool {
    match j.status {
        JourneyStatus::Arrived => true,
        JourneyStatus::Abandoned => j.end_reason.as_deref() == Some("aufgegeben"),
        JourneyStatus::Riding | JourneyStatus::Transfer => false,
    }
}

/// Midnight to midnight, Europe/Berlin, of the day `now` falls on.
pub fn berlin_day(now: DateTime<Utc>) -> (DateTime<Utc>, DateTime<Utc>) {
    use chrono_tz::Europe::Berlin;
    let midnight = |d: NaiveDate| {
        let t = d.and_hms_opt(0, 0, 0).unwrap();
        Berlin.from_local_datetime(&t).earliest().unwrap_or_else(|| Berlin.from_utc_datetime(&t)).with_timezone(&Utc)
    };
    let day = now.with_timezone(&Berlin).date_naive();
    (midnight(day), midnight(day.succ_opt().unwrap()))
}

/// What the admin route accepts: JPEG, PNG or WebP that really is what it says, upright, cut into
/// roughly square pieces. Width and height, or why not. The size is checked before, with its own
/// status.
pub fn inspect(content_type: &str, bytes: &[u8], rows: i32, cols: i32) -> Result<(u32, u32), String> {
    use imagesize::ImageType;
    if !(2..=8).contains(&rows) || !(2..=8).contains(&cols) {
        return Err("rows and cols must be 2 to 8".into());
    }
    let want = match content_type {
        "image/jpeg" => ImageType::Jpeg,
        "image/png" => ImageType::Png,
        "image/webp" => ImageType::Webp,
        _ => return Err("content_type must be image/jpeg, image/png or image/webp".into()),
    };
    if imagesize::image_type(bytes).ok() != Some(want) {
        return Err(format!("the data is not {content_type}"));
    }
    let size = imagesize::blob_size(bytes).map_err(|e| format!("cannot read the picture's size: {e}"))?;
    let (w, h) = (size.width as u32, size.height as u32);
    if w == 0 || h == 0 {
        return Err("the picture has no size".into());
    }
    if w.max(h) > MAX_SIDE || w as u64 * h as u64 > MAX_PIXELS {
        return Err(format!(
            "the picture is {w} × {h} px ({:.1} megapixels); at most {MAX_SIDE} px on its longest side and {} megapixels in all",
            (w as u64 * h as u64) as f64 / 1e6,
            MAX_PIXELS / 1_000_000
        ));
    }
    // The phone turns a picture by its EXIF orientation, and then width and height swap and the
    // grid no longer fits what we stored. Rather than guess, the picture comes upright.
    if want == ImageType::Jpeg {
        if let Some(o @ 2..=8) = jpeg_orientation(bytes) {
            return Err(format!("the JPEG carries an EXIF rotation (orientation {o}); export it upright without one"));
        }
    }
    let piece = (w as f64 / cols as f64) / (h as f64 / rows as f64);
    if piece < PIECE_ASPECT.0 || piece > PIECE_ASPECT.1 {
        return Err(format!(
            "a piece would be {} × {} px; pieces must be roughly square (width/height {}–{}), so pick a grid that fits {w} × {h}",
            w / cols as u32,
            h / rows as u32,
            PIECE_ASPECT.0,
            PIECE_ASPECT.1
        ));
    }
    Ok((w, h))
}

/// The EXIF orientation of a JPEG (1 is upright), when it states one.
fn jpeg_orientation(b: &[u8]) -> Option<u16> {
    let mut i = 2;
    while i + 4 <= b.len() && b[i] == 0xFF {
        let marker = b[i + 1];
        // Start of scan or end of image: the headers are over.
        if marker == 0xDA || marker == 0xD9 {
            return None;
        }
        let len = u16::from_be_bytes([b[i + 2], b[i + 3]]) as usize;
        let seg = b.get(i + 4..i + 2 + len)?;
        if marker == 0xE1 && seg.starts_with(b"Exif\0\0") {
            return tiff_orientation(&seg[6..]);
        }
        i += 2 + len;
    }
    None
}

/// Tag 0x0112 of the first IFD of a TIFF header, in either byte order.
fn tiff_orientation(t: &[u8]) -> Option<u16> {
    let le = match t.get(0..2)? {
        b"II" => true,
        b"MM" => false,
        _ => return None,
    };
    let u16_at = |o: usize| t.get(o..o + 2).map(|s| if le { u16::from_le_bytes([s[0], s[1]]) } else { u16::from_be_bytes([s[0], s[1]]) });
    let u32_at = |o: usize| t.get(o..o + 4).map(|s| if le { u32::from_le_bytes([s[0], s[1], s[2], s[3]]) } else { u32::from_be_bytes([s[0], s[1], s[2], s[3]]) });
    let ifd = u32_at(4)? as usize;
    let n = u16_at(ifd)? as usize;
    (0..n).find_map(|k| {
        let e = ifd + 2 + k * 12;
        (u16_at(e)? == 0x0112).then(|| u16_at(e + 8)).flatten()
    })
}

// ---------------------------------------------------------------------------
// Awarding
// ---------------------------------------------------------------------------

/// What counts against the daily cap: the pieces journeys brought, not the Stellwerk's.
const JOURNEY_PIECES_TODAY: &str = "select count(*) from puzzle_pieces where customer_id = $1 and not stellwerk and awarded_at >= $2 and awarded_at < $3";

/// Every picture with the pieces this customer holds of it, oldest first.
async fn images_of(conn: &mut PgConnection, customer: Uuid) -> anyhow::Result<Vec<Image>> {
    let rows: Vec<(Uuid, String, Vec<String>, bool, Vec<i32>)> = sqlx::query_as(
        "select i.id, i.ngo_id, i.tiers, i.retired_at is not null or not n.active,
                coalesce(array_agg(p.piece order by p.piece) filter (where p.piece is not null), '{}')
         from puzzle_images i
         join ngos n on n.id = i.ngo_id
         left join puzzle_pieces p on p.image_id = i.id and p.customer_id = $1
         group by i.id, n.active
         order by i.created_at, i.id",
    )
    .bind(customer)
    .fetch_all(conn)
    .await?;
    Ok(rows.into_iter().map(|(id, ngo_id, tiers, closed, owned)| Image { id, ngo_id, tiers: tiers_of(&tiers), closed, owned }).collect())
}

/// The stored tiers; the table's check admits no other words.
fn tiers_of(stored: &[String]) -> Vec<Tier> {
    stored.iter().map(|t| Tier::parse(t).unwrap_or(Tier::Minute)).collect()
}

/// „Deine Vereine" (docs/51 §2): the one chosen now, and every one a case or a claim went to.
async fn own_causes(conn: &mut PgConnection, customer: Uuid) -> anyhow::Result<Vec<String>> {
    Ok(sqlx::query_scalar(
        "select ngo_id from customers where id = $1
         union select ngo_id from incidents where customer_id = $1
         union select ngo_id from claims where customer_id = $1",
    )
    .bind(customer)
    .fetch_all(conn)
    .await?)
}

/// The piece this journey brings, written and as the wire carries it, or nothing. Never fails the
/// caller: the case and the minutes are what a journey is for, the piece is the thank-you, and a
/// failure here is logged rather than turned into a journey that will not finish.
pub async fn award(pool: &PgPool, flags: &crate::flags::Table, customer: &CustomerRow, j: &JourneyRow) -> Option<Value> {
    if !flags.bool(&crate::flags::PUZZLES, Some(customer.into())) || !earns_piece(j) {
        return None;
    }
    match try_award(pool, customer, j).await {
        Ok(p) => p,
        Err(e) => {
            tracing::warn!(journey = %j.id, error = %e, "puzzle: no piece awarded");
            None
        }
    }
}

async fn try_award(pool: &PgPool, customer: &CustomerRow, j: &JourneyRow) -> anyhow::Result<Option<Value>> {
    let mut tx = pool.begin().await?;
    // One award per customer at a time: two journeys ending together would otherwise both see
    // the same missing piece, and both see two pieces today when the cap is three.
    sqlx::query("select 1 from customers where id = $1 for no key update").bind(customer.id).execute(&mut *tx).await?;
    let already: Option<Uuid> = sqlx::query_scalar("select image_id from puzzle_pieces where journey_id = $1").bind(j.id).fetch_optional(&mut *tx).await?;
    if already.is_some() {
        tx.commit().await?;
        return piece_of_journey(pool, j.id).await;
    }
    // A ride entered afterwards never has a journey (`handlers::nachtrag`); this keeps it so if
    // one ever does. It does not rank (docs/47) and it brings no piece.
    let nachtrag: bool = sqlx::query_scalar("select exists(select 1 from rides where journey_id = $1 and nachtrag)").bind(j.id).fetch_one(&mut *tx).await?;
    if nachtrag {
        return Ok(None);
    }
    let now = crate::clock::now();
    let (from, to) = berlin_day(now);
    let today: i64 = sqlx::query_scalar(JOURNEY_PIECES_TODAY)
        .bind(customer.id)
        .bind(from)
        .bind(to)
        .fetch_one(&mut *tx)
        .await?;
    if today >= MAX_PER_DAY {
        return Ok(None);
    }
    let images = images_of(&mut tx, customer.id).await?;
    let own = own_causes(&mut tx, customer.id).await?;
    // The journey's counted minutes, as it stored them: `rules::counted_minutes` when it arrived,
    // the waiting when it was given up (`abandon_minutes`).
    let tier = Tier::for_minutes(j.points as i64);
    let Some((image, piece, _)) = choose(&images, &own, &customer.ngo_id, tier, &Dice::roll()) else { return Ok(None) };
    let own_cause = images.iter().any(|i| i.id == image && own.contains(&i.ngo_id));
    sqlx::query("insert into puzzle_pieces (customer_id, image_id, piece, journey_id, awarded_at, own_cause) values ($1, $2, $3, $4, $5, $6)")
        .bind(customer.id)
        .bind(image)
        .bind(piece)
        .bind(j.id)
        .bind(now)
        .bind(own_cause)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    piece_of_journey(pool, j.id).await
}

// ---------------------------------------------------------------------------
// Reading
// ---------------------------------------------------------------------------

/// One picture a customer has started.
#[derive(sqlx::FromRow)]
struct Puzzle {
    image_id: Uuid,
    ngo_id: String,
    ngo_name: String,
    title: String,
    caption: String,
    rows: i32,
    cols: i32,
    width: i32,
    height: i32,
    tiers: Vec<String>,
    owned: Vec<i32>,
    started_at: DateTime<Utc>,
    last_piece_at: DateTime<Utc>,
    video_bytes: Option<i64>,
    video_seconds: Option<f64>,
    video_sha256: Option<String>,
    video_width: Option<i32>,
    video_height: Option<i32>,
}

impl Puzzle {
    fn complete(&self) -> bool {
        self.owned.len() as i32 >= self.rows * self.cols
    }

    /// The fields a piece and a puzzle share (docs/51 §8).
    fn json(&self) -> Value {
        json!({
            "image_id": self.image_id, "rows": self.rows, "cols": self.cols, "tiers": self.tiers,
            "owned": self.owned, "complete": self.complete(),
            "title": self.title, "caption": self.caption,
            "ngo_id": self.ngo_id, "ngo_name": self.ngo_name,
            "image_url": format!("/v1/puzzle-images/{}", self.image_id), "width": self.width, "height": self.height,
            // docs/51 §9b: that there is one is said from the start („bewegt sich, wenn es fertig
            // ist"); where it is, only once the picture is finished.
            "has_video": self.video_sha256.is_some(),
            "video": if self.complete() { self.video() } else { Value::Null },
        })
    }

    /// The video as the wire carries it, whether or not this customer may have it yet.
    fn video(&self) -> Value {
        match &self.video_sha256 {
            Some(sha) => json!({
                "url": format!("/v1/puzzle-videos/{}", self.image_id), "bytes": self.video_bytes, "seconds": self.video_seconds,
                "sha256": sha, "width": self.video_width, "height": self.video_height,
            }),
            None => Value::Null,
        }
    }

    /// As `GET /v1/me/puzzles` lists it.
    fn listed(&self) -> Value {
        let mut v = self.json();
        v["started_at"] = json!(self.started_at);
        v["last_piece_at"] = json!(self.last_piece_at);
        v["completed_at"] = json!(self.complete().then_some(self.last_piece_at));
        v
    }
}

/// The pictures this customer has started; one of them when `image` is set.
async fn puzzles_of(pool: &PgPool, customer: Uuid, image: Option<Uuid>) -> anyhow::Result<Vec<Puzzle>> {
    Ok(sqlx::query_as(
        "select i.id as image_id, i.ngo_id, n.name as ngo_name, i.title, i.caption, i.rows, i.cols, i.width, i.height, i.tiers,
                array_agg(p.piece order by p.piece) as owned, min(p.awarded_at) as started_at, max(p.awarded_at) as last_piece_at,
                i.video_bytes, i.video_seconds, i.video_sha256, i.video_width, i.video_height
         from puzzle_pieces p
         join puzzle_images i on i.id = p.image_id
         join ngos n on n.id = i.ngo_id
         where p.customer_id = $1 and ($2::uuid is null or i.id = $2)
         group by i.id, n.name",
    )
    .bind(customer)
    .bind(image)
    .fetch_all(pool)
    .await?)
}

/// The piece a journey brought, as `journeys/current` and the finish carry it, or nothing.
pub async fn piece_of_journey(pool: &PgPool, journey: Uuid) -> anyhow::Result<Option<Value>> {
    let row: Option<(Uuid, Uuid, i32)> = sqlx::query_as("select customer_id, image_id, piece from puzzle_pieces where journey_id = $1").bind(journey).fetch_optional(pool).await?;
    let Some((customer, image, piece)) = row else { return Ok(None) };
    piece_json(pool, customer, image, piece).await
}

/// One piece a customer holds, as the wire carries it (docs/51 §8).
async fn piece_json(pool: &PgPool, customer: Uuid, image: Uuid, piece: i32) -> anyhow::Result<Option<Value>> {
    let row: Option<(DateTime<Utc>, bool)> = sqlx::query_as("select awarded_at, own_cause from puzzle_pieces where customer_id = $1 and image_id = $2 and piece = $3")
        .bind(customer)
        .bind(image)
        .bind(piece)
        .fetch_optional(pool)
        .await?;
    let Some((awarded_at, own_cause)) = row else { return Ok(None) };
    let Some(p) = puzzles_of(pool, customer, Some(image)).await?.pop() else { return Ok(None) };
    let mut v = p.json();
    v["piece"] = json!(piece);
    // The tier of the slot it filled: the fact, whatever the journey would have earned.
    v["tier"] = json!(p.tiers.get(piece as usize));
    v["own_cause"] = json!(own_cause);
    v["awarded_at"] = json!(awarded_at);
    Ok(Some(v))
}

/// `GET /v1/me/puzzles`: the pictures started, the ones still growing first (the last to grow on
/// top), then the finished ones (the last finished on top). `more_waiting`: is there any piece
/// left to get at all — otherwise the page says every picture is finished.
pub async fn mine(State(s): State<AppState>, c: Customer) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    if !s.flags().bool(&crate::flags::PUZZLES, Some((&c.0).into())) {
        return Ok(Json(json!({ "puzzles": [], "more_waiting": false })));
    }
    let mut list = puzzles_of(&s.pool, c.0.id, None).await.map_err(internal)?;
    list.sort_by_key(|p| (p.complete(), std::cmp::Reverse(p.last_piece_at)));
    let mut conn = s.pool.acquire().await.map_err(internal)?;
    let more_waiting = !candidates(&images_of(&mut conn, c.0.id).await.map_err(internal)?).is_empty();
    let puzzles: Vec<Value> = list.iter().map(Puzzle::listed).collect();
    Ok(Json(json!({ "puzzles": puzzles, "more_waiting": more_waiting })))
}

// ---------------------------------------------------------------------------
// The Stellwerk's pieces (docs/51 §9c): a picture tested without riding
// ---------------------------------------------------------------------------

type ApiError = (StatusCode, Json<Value>);

fn refuse(status: StatusCode, msg: &str) -> ApiError {
    (status, Json(json!({ "error": msg })))
}

/// One customer's puzzles as the Stellwerk sees them: what the app lists, the switch, and how
/// many pieces journeys brought today against the cap.
pub async fn stellwerk_view(pool: &PgPool, flags: &crate::flags::Table, customer: &CustomerRow) -> anyhow::Result<Value> {
    let mut list = puzzles_of(pool, customer.id, None).await?;
    list.sort_by_key(|p| (p.complete(), std::cmp::Reverse(p.last_piece_at)));
    let (from, to) = berlin_day(crate::clock::now());
    let today: i64 = sqlx::query_scalar(JOURNEY_PIECES_TODAY).bind(customer.id).bind(from).bind(to).fetch_one(pool).await?;
    let more_waiting = !candidates(&images_of(&mut *pool.acquire().await?, customer.id).await?).is_empty();
    Ok(json!({
        "customer": customer.id, "nickname": customer.nickname,
        "puzzles_flag": flags.bool(&crate::flags::PUZZLES, Some(customer.into())),
        // The video's facts before it is finished too: the Stellwerk shows what is coming.
        "puzzles": list.iter().map(|p| {
            let mut v = p.listed();
            v["video_facts"] = p.video();
            v
        }).collect::<Vec<_>>(),
        "more_waiting": more_waiting,
        "today": { "journey_pieces": today, "cap": MAX_PER_DAY },
    }))
}

/// What the Stellwerk asks for one piece.
#[derive(Debug, Clone, Default)]
pub struct Give {
    /// Exactly this picture, retired or not.
    pub image: Option<Uuid>,
    /// Only this Verein's pictures, by the usual rules.
    pub ngo: Option<String>,
    /// As if a journey of this tier had ended. With `image` and without it: any open slot.
    pub tier: Option<Tier>,
    /// Exactly this slot of `image`.
    pub piece: Option<i32>,
}

/// A piece the Stellwerk puts into an account, as the wire carries it; nothing when there is no
/// open slot left that the request may fill. Without `image` the rules of a journey decide
/// ([`choose`], the side roll included); it never counts against the daily cap.
pub async fn give(pool: &PgPool, customer: &CustomerRow, g: &Give) -> Result<Option<Value>, ApiError> {
    let mut tx = pool.begin().await.map_err(internal)?;
    sqlx::query("select 1 from customers where id = $1 for no key update").bind(customer.id).execute(&mut *tx).await.map_err(internal)?;
    let images = images_of(&mut tx, customer.id).await.map_err(internal)?;
    let own = own_causes(&mut tx, customer.id).await.map_err(internal)?;
    let dice = Dice::roll();
    let chosen = match (g.image, &g.ngo) {
        (Some(id), _) => {
            let img = images.iter().find(|i| i.id == id).ok_or_else(|| refuse(StatusCode::NOT_FOUND, "no such picture"))?;
            match g.piece {
                Some(p) if p < 0 || p as usize >= img.tiers.len() => {
                    return Err(refuse(StatusCode::BAD_REQUEST, &format!("piece must be 0 to {} for this picture", img.tiers.len() - 1)));
                }
                Some(p) if img.owned.contains(&p) => return Err(refuse(StatusCode::CONFLICT, &format!("the customer already has piece {p} of this picture"))),
                Some(p) => Some((id, p)),
                None => Tier::ALL.into_iter().rev().filter(|t| g.tier.is_none_or(|want| *t <= want)).find_map(|t| {
                    let open = img.missing(t);
                    (!open.is_empty()).then(|| (id, open[(dice.piece % open.len() as u64) as usize]))
                }),
            }
        }
        (None, _) if g.piece.is_some() => return Err(refuse(StatusCode::BAD_REQUEST, "piece needs image")),
        (None, Some(ngo)) => {
            let of: Vec<Image> = images.iter().filter(|i| &i.ngo_id == ngo).cloned().collect();
            if of.is_empty() {
                return Err(refuse(StatusCode::NOT_FOUND, "this NGO has no pictures"));
            }
            choose(&of, std::slice::from_ref(ngo), ngo, g.tier.unwrap_or(Tier::Minute), &dice).map(|(i, p, _)| (i, p))
        }
        (None, None) => choose(&images, &own, &customer.ngo_id, g.tier.unwrap_or(Tier::Minute), &dice).map(|(i, p, _)| (i, p)),
    };
    let Some((image, piece)) = chosen else { return Ok(None) };
    let own_cause = images.iter().any(|i| i.id == image && own.contains(&i.ngo_id));
    sqlx::query("insert into puzzle_pieces (customer_id, image_id, piece, awarded_at, own_cause, stellwerk) values ($1, $2, $3, $4, $5, true)")
        .bind(customer.id)
        .bind(image)
        .bind(piece)
        .bind(crate::clock::now())
        .bind(own_cause)
        .execute(&mut *tx)
        .await
        .map_err(internal)?;
    tx.commit().await.map_err(internal)?;
    piece_json(pool, customer.id, image, piece).await.map_err(internal)
}

/// Fill a picture up to `leave` open slots, preferring to leave slots of `leave_tier`: „bis auf
/// das Stunden-Teil" is `leave 1, hour`, and the next journey of 60 minutes finishes it. `target`
/// is a picture's id, or a Verein's, which means its started picture, else its next one. Nothing
/// the customer holds is taken away. The added and the left slots, and the puzzle as it is now.
pub async fn fill(pool: &PgPool, customer: &CustomerRow, target: &str, leave: usize, leave_tier: Option<Tier>) -> Result<Value, ApiError> {
    let mut tx = pool.begin().await.map_err(internal)?;
    sqlx::query("select 1 from customers where id = $1 for no key update").bind(customer.id).execute(&mut *tx).await.map_err(internal)?;
    let images = images_of(&mut tx, customer.id).await.map_err(internal)?;
    let img = match target.parse::<Uuid>() {
        Ok(id) => images.iter().find(|i| i.id == id).ok_or_else(|| refuse(StatusCode::NOT_FOUND, "no such picture"))?,
        Err(_) => candidates(&images)
            .into_iter()
            .rev()
            .filter(|i| i.ngo_id == target)
            .max_by_key(|i| (i.started(), i.owned.len()))
            .ok_or_else(|| refuse(StatusCode::NOT_FOUND, "this NGO has no picture left to fill"))?,
    };
    let mut open: Vec<i32> = Tier::ALL.into_iter().flat_map(|t| img.missing(t)).collect();
    open.sort_by_key(|&p| (Some(img.tiers[p as usize]) != leave_tier, p));
    let left: Vec<i32> = open.iter().copied().take(leave).collect();
    let mut added: Vec<i32> = open.into_iter().skip(leave).collect();
    added.sort_unstable();
    let own_cause = own_causes(&mut tx, customer.id).await.map_err(internal)?.contains(&img.ngo_id);
    sqlx::query(
        "insert into puzzle_pieces (customer_id, image_id, piece, awarded_at, own_cause, stellwerk)
         select $1, $2, p, $4, $5, true from unnest($3::int[]) p",
    )
    .bind(customer.id)
    .bind(img.id)
    .bind(&added)
    .bind(crate::clock::now())
    .bind(own_cause)
    .execute(&mut *tx)
    .await
    .map_err(internal)?;
    tx.commit().await.map_err(internal)?;
    let puzzle = puzzles_of(pool, customer.id, Some(img.id)).await.map_err(internal)?.pop();
    let mut left = left;
    left.sort_unstable();
    Ok(json!({ "image_id": img.id, "added": added, "left": left, "puzzle": puzzle.as_ref().map(Puzzle::listed) }))
}

/// Take the Stellwerk's and the journeys' pieces out again, of one picture or of all. How many.
pub async fn clear(pool: &PgPool, customer: Uuid, image: Option<Uuid>) -> anyhow::Result<u64> {
    Ok(sqlx::query("delete from puzzle_pieces where customer_id = $1 and ($2::uuid is null or image_id = $2)")
        .bind(customer)
        .bind(image)
        .execute(pool)
        .await?
        .rows_affected())
}

/// The pictures already read, by id, so a phone fetching one does not pull a megabyte out of
/// Postgres each time. A picture never changes, so an entry is never stale; a deleted one is
/// taken out. Bounded: a few dozen pictures fit, and past either bound an arbitrary entry goes —
/// any one will do, they are all cheap to read again.
static PICTURES: std::sync::LazyLock<std::sync::Mutex<HashMap<Uuid, Bytes>>> = std::sync::LazyLock::new(Default::default);
const PICTURES_MAX: usize = 64;
const PICTURES_MAX_BYTES: usize = 64 * 1024 * 1024;

fn cached(id: Uuid) -> Option<Bytes> {
    PICTURES.lock().expect("pictures lock").get(&id).cloned()
}

fn remember(id: Uuid, bytes: Bytes) {
    let mut c = PICTURES.lock().expect("pictures lock");
    while !c.is_empty() && (c.len() >= PICTURES_MAX || c.values().map(Bytes::len).sum::<usize>() + bytes.len() > PICTURES_MAX_BYTES) {
        let some = *c.keys().next().expect("not empty");
        c.remove(&some);
    }
    c.insert(id, bytes);
}

/// A deleted picture leaves the cache with its row.
pub fn forget_picture(id: Uuid) {
    PICTURES.lock().expect("pictures lock").remove(&id);
}

/// `GET /v1/puzzle-images/{id}`: the picture, without a token — it is a Verein's photo, not a
/// secret (docs/51 §7). It never changes, so it caches for good; a new picture gets a new id.
/// The 304 is answered from the digest alone, and the bytes come from memory after the first read.
pub async fn image(State(s): State<AppState>, h: HeaderMap, Path(id): Path<String>) -> Response {
    use axum::http::header;
    let not_found = || (StatusCode::NOT_FOUND, Json(json!({ "error": "no such picture" }))).into_response();
    let Ok(id) = id.parse::<Uuid>() else { return not_found() };
    let row: Result<Option<(String, String)>, _> = sqlx::query_as("select content_type, sha256 from puzzle_images where id = $1").bind(id).fetch_optional(&s.pool).await;
    let (content_type, sha) = match row {
        Ok(Some(r)) => r,
        Ok(None) => return not_found(),
        Err(e) => return internal(e).into_response(),
    };
    let etag = format!("\"{sha}\"");
    // A 304 repeats the Cache-Control the 200 would carry (RFC 9110 §15.4.5).
    let cache = "public, max-age=31536000, immutable";
    if h.get(header::IF_NONE_MATCH).and_then(|v| v.to_str().ok()) == Some(etag.as_str()) {
        return (StatusCode::NOT_MODIFIED, [(header::CACHE_CONTROL, cache.to_string()), (header::ETAG, etag)]).into_response();
    }
    let bytes = match cached(id) {
        Some(b) => b,
        None => match sqlx::query_scalar::<_, Vec<u8>>("select bytes from puzzle_images where id = $1").bind(id).fetch_optional(&s.pool).await {
            Ok(Some(b)) => {
                let b = Bytes::from(b);
                remember(id, b.clone());
                b
            }
            Ok(None) => return not_found(),
            Err(e) => return internal(e).into_response(),
        },
    };
    ([(header::CONTENT_TYPE, content_type), (header::CACHE_CONTROL, cache.to_string()), (header::ETAG, etag)], bytes).into_response()
}

/// The longest a puzzle video may be, and the shortest, in seconds, and its largest size
/// (docs/51 §9b: 15–30 s are asked for; the Stellwerk warns outside those, the server refuses
/// outside these).
pub const VIDEO_SECONDS: (f64, f64) = (10.0, 35.0);
pub const MAX_VIDEO_BYTES: u64 = 40_000_000;

/// What a `Range` header asks of a file.
#[derive(Debug, PartialEq)]
pub enum ByteRange {
    /// No range, or one we do not serve in parts (several ranges): the whole file is a valid answer.
    Whole,
    /// First and last byte, both inclusive.
    Part(u64, u64),
    /// Outside the file: 416.
    Unsatisfiable,
}

/// The single byte range of `header` for a file of `len` bytes (RFC 9110 §14.1.2). A malformed
/// header is ignored, as the RFC allows.
pub fn byte_range(header: &str, len: u64) -> ByteRange {
    let Some(spec) = header.trim().strip_prefix("bytes=") else { return ByteRange::Whole };
    let Some((a, b)) = spec.split_once('-').filter(|_| !spec.contains(',')) else { return ByteRange::Whole };
    let (a, b) = (a.trim(), b.trim());
    let num = |s: &str| s.parse::<u64>().ok();
    match (a.is_empty(), b.is_empty()) {
        (true, true) => ByteRange::Whole,
        // The last n bytes.
        (true, false) => match num(b) {
            Some(0) => ByteRange::Unsatisfiable,
            Some(_) if len == 0 => ByteRange::Unsatisfiable,
            Some(n) => ByteRange::Part(len.saturating_sub(n), len - 1),
            None => ByteRange::Whole,
        },
        (false, _) => match (num(a), if b.is_empty() { Some(u64::MAX) } else { num(b) }) {
            (Some(first), Some(last)) if first > last => ByteRange::Whole,
            (Some(first), _) if first >= len => ByteRange::Unsatisfiable,
            (Some(first), Some(last)) => ByteRange::Part(first, last.min(len - 1)),
            _ => ByteRange::Whole,
        },
    }
}

/// `GET /v1/puzzle-videos/{id}`: the video of a picture, only for a customer who has finished it
/// (docs/51 §9b: the reward for the whole picture). In ranges, because a player and a resumed
/// download ask for them; it never changes, so it caches for good, privately.
pub async fn video(State(s): State<AppState>, c: Customer, h: HeaderMap, Path(id): Path<String>) -> Response {
    use axum::http::header;
    let refuse = |status: StatusCode, msg: &str| (status, Json(json!({ "error": msg }))).into_response();
    let Ok(id) = id.parse::<Uuid>() else { return refuse(StatusCode::NOT_FOUND, "no such video") };
    let row: Result<Option<(Option<String>, Option<String>, i32, i64)>, _> = sqlx::query_as(
        "select i.video_path, i.video_sha256, i.rows * i.cols, (select count(*) from puzzle_pieces p where p.image_id = i.id and p.customer_id = $2)
         from puzzle_images i where i.id = $1",
    )
    .bind(id)
    .bind(c.0.id)
    .fetch_optional(&s.pool)
    .await;
    let (path, sha, slots, owned) = match row {
        Ok(Some((Some(path), Some(sha), slots, owned))) => (path, sha, slots, owned),
        Ok(_) => return refuse(StatusCode::NOT_FOUND, "no such video"),
        Err(e) => return internal(e).into_response(),
    };
    if owned < slots as i64 {
        return refuse(StatusCode::FORBIDDEN, "the video comes with the finished picture");
    }
    let etag = format!("\"{sha}\"");
    let cache = "private, max-age=31536000, immutable";
    if h.get(header::IF_NONE_MATCH).and_then(|v| v.to_str().ok()) == Some(etag.as_str()) {
        return (StatusCode::NOT_MODIFIED, [(header::CACHE_CONTROL, cache.to_string()), (header::ETAG, etag)]).into_response();
    }
    let opened = match crate::storage::file(&path) {
        Some(p) => tokio::fs::File::open(&p).await,
        None => Err(std::io::Error::other("unsafe path")),
    };
    let file = match opened {
        Ok(f) => f,
        Err(e) => {
            tracing::error!(image = %id, path, error = %e, "puzzle video file missing");
            return refuse(StatusCode::NOT_FOUND, "no such video");
        }
    };
    let len = match file.metadata().await {
        Ok(m) => m.len(),
        Err(e) => return internal(e).into_response(),
    };
    // A range under If-Range only while the file is still the one it names.
    let ranged = h.get(header::IF_RANGE).is_none_or(|v| v.to_str().ok() == Some(etag.as_str()));
    let range = match h.get(header::RANGE).and_then(|v| v.to_str().ok()) {
        Some(r) if ranged => byte_range(r, len),
        _ => ByteRange::Whole,
    };
    let (status, first, last) = match range {
        ByteRange::Whole if len == 0 => (StatusCode::OK, 0, 0),
        ByteRange::Whole => (StatusCode::OK, 0, len - 1),
        ByteRange::Part(a, b) => (StatusCode::PARTIAL_CONTENT, a, b),
        ByteRange::Unsatisfiable => {
            return (StatusCode::RANGE_NOT_SATISFIABLE, [(header::CONTENT_RANGE, format!("bytes */{len}")), (header::ACCEPT_RANGES, "bytes".to_string())]).into_response();
        }
    };
    let count = if len == 0 { 0 } else { last - first + 1 };
    let body = axum::body::Body::from_stream(async_stream::stream! {
        use tokio::io::{AsyncReadExt, AsyncSeekExt};
        let mut file = file;
        if let Err(e) = file.seek(std::io::SeekFrom::Start(first)).await {
            yield Err(e);
            return;
        }
        let mut left = count;
        let mut buf = vec![0u8; 64 * 1024];
        while left > 0 {
            let want = buf.len().min(left as usize);
            match file.read(&mut buf[..want]).await {
                Ok(0) => break,
                Ok(n) => {
                    left -= n as u64;
                    yield Ok::<Bytes, std::io::Error>(Bytes::copy_from_slice(&buf[..n]));
                }
                Err(e) => {
                    yield Err(e);
                    break;
                }
            }
        }
    });
    let mut r = (status, body).into_response();
    let hs = r.headers_mut();
    hs.insert(header::CONTENT_TYPE, "video/mp4".parse().unwrap());
    hs.insert(header::ACCEPT_RANGES, "bytes".parse().unwrap());
    hs.insert(header::CONTENT_LENGTH, count.into());
    hs.insert(header::CACHE_CONTROL, cache.parse().unwrap());
    hs.insert(header::ETAG, etag.parse().unwrap());
    if status == StatusCode::PARTIAL_CONTENT {
        hs.insert(header::CONTENT_RANGE, format!("bytes {first}-{last}/{len}").parse().unwrap());
    }
    r
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A picture whose slots are spelled out: m, q, H for minute, quarter, hour.
    fn img(n: u128, ngo: &str, tiers: &str, closed: bool, owned: &[i32]) -> Image {
        let tiers = tiers.chars().map(|c| match c { 'H' => Tier::Hour, 'q' => Tier::Quarter, _ => Tier::Minute }).collect();
        Image { id: Uuid::from_u128(n), ngo_id: ngo.into(), tiers, closed, owned: owned.to_vec() }
    }

    fn own(ngos: &[&str]) -> Vec<String> {
        ngos.iter().map(|s| s.to_string()).collect()
    }

    fn ids(c: Vec<&Image>) -> Vec<u128> {
        c.iter().map(|i| i.id.as_u128()).collect()
    }

    /// The choice with the image as its number.
    fn pick(images: &[Image], own: &[String], current: &str, tier: Tier, dice: Dice) -> Option<(u128, i32, Tier)> {
        choose(images, own, current, tier, &dice).map(|(id, slot, t)| (id.as_u128(), slot, t))
    }

    const MINE: Dice = Dice { side: 1, pick: 0, piece: 0 };
    const OTHER: Dice = Dice { side: 0, pick: 0, piece: 0 };
    use Tier::{Hour, Minute, Quarter};

    #[test]
    fn the_candidates_are_every_started_picture_and_each_vereins_next() {
        let images = [
            img(1, "wald", "mmmm", false, &[0, 1, 2, 3]),
            img(2, "wald", "mmmm", false, &[1]),
            img(3, "wald", "mmmm", false, &[]),
            img(4, "wald", "mmmm", false, &[]),
            img(5, "hospiz", "mmmm", false, &[]),
        ];
        // The finished picture is none; wald's next is the oldest not started, and only that one.
        assert_eq!(ids(candidates(&images)), vec![2, 3, 5]);
    }

    #[test]
    fn a_retired_picture_counts_only_when_started() {
        assert_eq!(ids(candidates(&[img(1, "wald", "mmmm", true, &[]), img(2, "wald", "mmmm", false, &[])])), vec![2]);
        assert_eq!(ids(candidates(&[img(1, "wald", "mmmm", true, &[2]), img(2, "wald", "mmmm", false, &[])])), vec![1, 2]);
        assert!(candidates(&[img(1, "wald", "mmmm", true, &[])]).is_empty());
    }

    #[test]
    fn three_of_four_from_own_vereine_one_from_another() {
        let images = [img(1, "wald", "mmmm", false, &[]), img(2, "hospiz", "mmmm", false, &[])];
        for side in 1..4 {
            assert_eq!(pick(&images, &own(&["wald"]), "wald", Minute, Dice { side, ..MINE }).unwrap().0, 1, "side {side}");
        }
        assert_eq!(pick(&images, &own(&["wald"]), "wald", Minute, OTHER).unwrap().0, 2);
    }

    #[test]
    fn a_side_with_nothing_to_fill_gives_way() {
        // Nothing of their own left: the other side, whatever the dice say.
        let images = [img(1, "wald", "mmmm", false, &[0, 1, 2, 3]), img(2, "hospiz", "mmmm", false, &[])];
        assert_eq!(pick(&images, &own(&["wald"]), "wald", Minute, MINE).unwrap().0, 2);
        // No other Verein has pictures: their own.
        assert_eq!(pick(&[img(1, "wald", "mmmm", false, &[])], &own(&["wald"]), "wald", Minute, OTHER).unwrap().0, 1);
        // Their own side has only an hour slot open, which a minute cannot fill: the other side.
        let images = [img(1, "wald", "mmmH", false, &[0, 1, 2]), img(2, "hospiz", "mmmm", false, &[])];
        assert_eq!(pick(&images, &own(&["wald"]), "wald", Minute, MINE).unwrap().0, 2);
        // Everything finished: nothing.
        assert_eq!(pick(&[img(1, "wald", "mm", false, &[0, 1])], &own(&["wald"]), "wald", Minute, MINE), None);
        assert_eq!(pick(&[], &own(&["wald"]), "wald", Hour, MINE), None);
    }

    #[test]
    fn on_their_own_side_a_started_picture_the_fullest_then_the_chosen_verein_then_chance() {
        let all = own(&["bahnhofsmission", "wald", "hospiz"]);
        let images = [img(1, "bahnhofsmission", "mmmm", false, &[]), img(2, "wald", "mmmm", false, &[3]), img(3, "hospiz", "mmmm", false, &[1, 2])];
        assert_eq!(pick(&images, &all, "bahnhofsmission", Minute, MINE).unwrap().0, 3);
        let images = [img(1, "bahnhofsmission", "mmmm", false, &[]), img(2, "wald", "mmmm", false, &[])];
        assert_eq!(pick(&images, &all, "bahnhofsmission", Minute, MINE).unwrap().0, 1);
        assert_eq!(pick(&images, &all, "wald", Minute, MINE).unwrap().0, 2);
        // The chosen Verein has no picture: chance among the others.
        let images = [img(1, "hospiz", "mmmm", false, &[]), img(2, "wald", "mmmm", false, &[])];
        let picks: Vec<u128> = (0..2).map(|p| pick(&images, &all, "bahnhofsmission", Minute, Dice { pick: p, ..MINE }).unwrap().0).collect();
        assert_eq!(picks, vec![1, 2]);
    }

    #[test]
    fn on_the_other_side_a_started_picture_then_chance() {
        let images = [img(1, "wald", "mmmm", false, &[]), img(2, "hospiz", "mmmm", false, &[]), img(3, "tafel", "mmmm", false, &[3])];
        assert_eq!(pick(&images, &own(&["wald"]), "wald", Minute, OTHER).unwrap().0, 3);
        let images = [img(1, "wald", "mmmm", false, &[]), img(2, "hospiz", "mmmm", false, &[]), img(3, "tafel", "mmmm", false, &[])];
        let picks: Vec<u128> = (0..2).map(|p| pick(&images, &own(&["wald"]), "wald", Minute, Dice { pick: p, ..OTHER }).unwrap().0).collect();
        assert_eq!(picks, vec![2, 3]);
    }

    #[test]
    fn the_piece_is_one_that_is_missing_never_a_double() {
        let images = [img(1, "wald", "mmmm", false, &[0, 2])];
        let slots: Vec<i32> = (0..4).map(|piece| pick(&images, &own(&["wald"]), "wald", Minute, Dice { piece, ..MINE }).unwrap().1).collect();
        assert_eq!(slots, vec![1, 3, 1, 3]);
    }

    #[test]
    fn a_rare_piece_goes_to_a_slot_of_its_own_tier() {
        let images = [img(1, "wald", "mqmH", false, &[0])];
        assert_eq!(pick(&images, &own(&["wald"]), "wald", Quarter, MINE), Some((1, 1, Quarter)));
        assert_eq!(pick(&images, &own(&["wald"]), "wald", Hour, MINE), Some((1, 3, Hour)));
        assert_eq!(pick(&images, &own(&["wald"]), "wald", Minute, MINE).unwrap().2, Minute);
    }

    #[test]
    fn a_rare_piece_starts_the_next_picture_rather_than_fill_a_common_slot() {
        // The started picture has only minutes open; the next one of the Verein has its hour.
        let images = [img(1, "wald", "mmmH", false, &[3]), img(2, "wald", "mmHm", false, &[])];
        assert_eq!(pick(&images, &own(&["wald"]), "wald", Hour, MINE), Some((2, 2, Hour)));
    }

    #[test]
    fn a_rare_piece_fills_a_lower_slot_only_when_none_of_its_tier_is_open() {
        let images = [img(1, "wald", "mqmH", false, &[3])];
        assert_eq!(pick(&images, &own(&["wald"]), "wald", Hour, MINE), Some((1, 1, Quarter)), "the highest tier below first");
        let images = [img(1, "wald", "mqmH", false, &[1, 3])];
        assert_eq!(pick(&images, &own(&["wald"]), "wald", Hour, MINE).unwrap().2, Minute);
        // The highest tier below comes before the started picture: a quarter in a new picture.
        let images = [img(1, "wald", "mmmm", false, &[0]), img(2, "wald", "qmmm", false, &[])];
        assert_eq!(pick(&images, &own(&["wald"]), "wald", Hour, MINE), Some((2, 0, Quarter)));
    }

    #[test]
    fn a_rare_piece_crosses_to_the_other_side_before_it_drops_a_tier() {
        // Rolled for their own side, which has only minutes open: the other side's hour slot.
        let images = [img(1, "wald", "mmmm", false, &[]), img(2, "hospiz", "Hmmm", false, &[])];
        assert_eq!(pick(&images, &own(&["wald"]), "wald", Hour, MINE), Some((2, 0, Hour)));
        // And the other way round.
        let images = [img(1, "wald", "mmHm", false, &[]), img(2, "hospiz", "mmmm", false, &[])];
        assert_eq!(pick(&images, &own(&["wald"]), "wald", Hour, OTHER), Some((1, 2, Hour)));
        // The roll still decides who gets the first try at a tier both sides have open.
        let images = [img(1, "wald", "mmHm", false, &[]), img(2, "hospiz", "Hmmm", false, &[])];
        assert_eq!(pick(&images, &own(&["wald"]), "wald", Hour, MINE), Some((1, 2, Hour)));
        assert_eq!(pick(&images, &own(&["wald"]), "wald", Hour, OTHER), Some((2, 0, Hour)));
        // Neither side has an hour open: a quarter on the other side before a minute on its own.
        let images = [img(1, "wald", "mmmm", false, &[]), img(2, "hospiz", "qmmm", false, &[])];
        assert_eq!(pick(&images, &own(&["wald"]), "wald", Hour, MINE), Some((2, 0, Quarter)));
    }

    #[test]
    fn a_common_piece_never_fills_a_rare_slot() {
        let images = [img(1, "wald", "mqmH", false, &[0, 2])];
        assert_eq!(pick(&images, &own(&["wald"]), "wald", Minute, MINE), None);
        assert_eq!(pick(&images, &own(&["wald"]), "wald", Minute, OTHER), None);
    }

    #[test]
    fn a_picture_waits_for_its_hour_while_the_common_pieces_start_the_next() {
        let images = [img(1, "wald", "mmmH", false, &[0, 1, 2]), img(2, "wald", "mmmH", false, &[])];
        let (image, slot, tier) = pick(&images, &own(&["wald"]), "wald", Minute, MINE).unwrap();
        assert_eq!((image, tier), (2, Minute));
        assert!((0..3).contains(&slot));
        // And the hour piece, when it comes, finishes the first.
        assert_eq!(pick(&images, &own(&["wald"]), "wald", Hour, MINE), Some((1, 3, Hour)));
    }

    #[test]
    fn the_tier_is_how_long_the_journey_waited() {
        let tier = |delay, cancelled| Tier::for_minutes(crate::rules::counted_minutes(delay, cancelled));
        assert_eq!(tier(0, false), Minute);
        assert_eq!(tier(14, false), Minute);
        assert_eq!(tier(15, false), Quarter);
        assert_eq!(tier(59, false), Quarter);
        assert_eq!(tier(60, false), Hour);
        assert_eq!(tier(0, true), Hour, "a cancellation counts 60");
    }

    fn count(t: &[Tier]) -> (usize, usize, usize) {
        let n = |x| t.iter().filter(|&&y| y == x).count();
        (n(Hour), n(Quarter), n(Minute))
    }

    fn hours(t: &[Tier]) -> Vec<usize> {
        (0..t.len()).filter(|&i| t[i] == Hour).collect()
    }

    #[test]
    fn a_new_picture_has_its_hours_in_the_middle_and_its_quarters_scattered() {
        let id = Uuid::from_u128(7);
        // 3 × 4 (cols × rows), 4 × 5, 5 × 6.
        let t12 = default_tiers(id, 4, 3);
        let t20 = default_tiers(id, 5, 4);
        let t30 = default_tiers(id, 6, 5);
        assert_eq!(count(&t12), (1, 3, 8));
        assert_eq!(count(&t20), (2, 5, 13));
        assert_eq!(count(&t30), (3, 8, 19));
        assert_eq!(count(&default_tiers(id, 2, 2)), (1, 1, 2));
        // The centre of a 3 × 4 grid lies between slots 4 and 7; of 4 × 5 between 9 and 10.
        assert!([vec![4], vec![7]].contains(&hours(&t12)), "{t12:?}");
        assert_eq!(hours(&t20), vec![9, 10]);
        // 5 × 6: slots 12 and 17 are nearest, the third is one of the four next to them.
        let h = hours(&t30);
        assert!(h.contains(&12) && h.contains(&17) && h.iter().any(|s| [11, 13, 16, 18].contains(s)), "{h:?}");
        // The same picture always the same, and the ties fall differently for different pictures.
        assert_eq!(default_tiers(id, 6, 5), t30);
        let centres: std::collections::HashSet<Vec<usize>> = (0..20).map(|n| hours(&default_tiers(Uuid::from_u128(n), 4, 3))).collect();
        assert_eq!(centres.len(), 2);
        let quarters: std::collections::HashSet<Vec<Tier>> = (0..20).map(|n| default_tiers(Uuid::from_u128(n), 5, 4)).collect();
        assert!(quarters.len() > 10, "the quarters are scattered by the id");
    }

    fn journey(status: JourneyStatus, end_reason: Option<&str>) -> JourneyRow {
        let t = Utc::now();
        JourneyRow {
            id: Uuid::nil(), customer_id: Uuid::nil(),
            origin_station_id: String::new(), origin_station_name: String::new(),
            destination_station_id: String::new(), destination_station_name: String::new(),
            itinerary: json!({}), plan: json!([]), planned_departure: t, planned_arrival: t,
            status, current_leg: 1, next_leg: None, transfer_deadline: None, actual_arrival: None, final_delay_min: None,
            missed_connection: false, incomplete: false, cancelled: false, points: 0, ticket: TicketType::Deutschlandticket,
            created_at: t, finalised_at: None, dismissed_at: None, end_reason: end_reason.map(str::to_string),
            earliest_onward_arrival: None, stale_asked_at: None,
        }
    }

    #[test]
    fn arrived_and_given_up_earn_a_piece_never_boarded_does_not() {
        assert!(earns_piece(&journey(JourneyStatus::Arrived, None)));
        assert!(earns_piece(&journey(JourneyStatus::Arrived, Some("beendet"))));
        assert!(earns_piece(&journey(JourneyStatus::Abandoned, Some("aufgegeben"))));
        assert!(!earns_piece(&journey(JourneyStatus::Abandoned, Some("nicht_gefahren"))));
        assert!(!earns_piece(&journey(JourneyStatus::Riding, None)));
        assert!(!earns_piece(&journey(JourneyStatus::Transfer, None)));
    }

    #[test]
    fn one_byte_range_at_a_time() {
        use ByteRange::*;
        assert_eq!(byte_range("bytes=0-99", 1000), Part(0, 99));
        assert_eq!(byte_range("bytes=900-", 1000), Part(900, 999));
        assert_eq!(byte_range("bytes=900-5000", 1000), Part(900, 999));
        assert_eq!(byte_range("bytes=-100", 1000), Part(900, 999));
        assert_eq!(byte_range("bytes=-5000", 1000), Part(0, 999));
        assert_eq!(byte_range("bytes=0-0", 1000), Part(0, 0));
        assert_eq!(byte_range("bytes=1000-", 1000), Unsatisfiable);
        assert_eq!(byte_range("bytes=-0", 1000), Unsatisfiable);
        assert_eq!(byte_range("bytes=0-1,5-9", 1000), Whole, "several ranges: the whole file");
        assert_eq!(byte_range("bytes=9-1", 1000), Whole, "malformed: ignored");
        assert_eq!(byte_range("items=0-1", 1000), Whole);
        assert_eq!(byte_range("bytes=x-", 1000), Whole);
    }

    #[test]
    fn the_day_is_berlins() {
        let t = |s: &str| s.parse::<DateTime<Utc>>().unwrap();
        // 00:30 on 13 October in Berlin (summer time) is still the 12th in UTC.
        assert_eq!(berlin_day(t("2026-10-12T22:30:00Z")), (t("2026-10-12T22:00:00Z"), t("2026-10-13T22:00:00Z")));
        assert_eq!(berlin_day(t("2026-10-12T21:59:00Z")), (t("2026-10-11T22:00:00Z"), t("2026-10-12T22:00:00Z")));
        // The day summer time ends has 25 hours.
        assert_eq!(berlin_day(t("2026-10-25T12:00:00Z")), (t("2026-10-24T22:00:00Z"), t("2026-10-25T23:00:00Z")));
    }

    /// A PNG's signature and header: enough for the checks, which never decode the pixels.
    fn png(w: u32, h: u32) -> Vec<u8> {
        let mut b = b"\x89PNG\r\n\x1a\n\0\0\0\x0dIHDR".to_vec();
        b.extend_from_slice(&w.to_be_bytes());
        b.extend_from_slice(&h.to_be_bytes());
        b.extend_from_slice(&[8, 2, 0, 0, 0, 0, 0, 0, 0]);
        b
    }

    /// A JPEG's headers: an EXIF block with [orientation] when given, and a frame of w × h.
    fn jpeg(w: u16, h: u16, orientation: Option<u16>) -> Vec<u8> {
        let mut b = vec![0xFF, 0xD8];
        if let Some(o) = orientation {
            let mut tiff = b"MM\0\x2a\0\0\0\x08".to_vec();
            tiff.extend_from_slice(&[0, 1, 0x01, 0x12, 0, 3, 0, 0, 0, 1]);
            tiff.extend_from_slice(&o.to_be_bytes());
            tiff.extend_from_slice(&[0, 0, 0, 0, 0, 0]);
            let mut seg = b"Exif\0\0".to_vec();
            seg.extend_from_slice(&tiff);
            b.extend_from_slice(&[0xFF, 0xE1]);
            b.extend_from_slice(&(seg.len() as u16 + 2).to_be_bytes());
            b.extend_from_slice(&seg);
        }
        b.extend_from_slice(&[0xFF, 0xC0, 0, 17, 8]);
        b.extend_from_slice(&h.to_be_bytes());
        b.extend_from_slice(&w.to_be_bytes());
        b.extend_from_slice(&[3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1, 0xFF, 0xD9]);
        b
    }

    #[test]
    fn a_picture_is_what_it_says_upright_and_cut_into_square_pieces() {
        assert_eq!(inspect("image/png", &png(900, 1200), 4, 3), Ok((900, 1200)));
        assert_eq!(inspect("image/jpeg", &jpeg(900, 1200, None), 4, 3), Ok((900, 1200)));
        assert_eq!(inspect("image/jpeg", &jpeg(900, 1200, Some(1)), 4, 3), Ok((900, 1200)));
        assert!(inspect("image/jpeg", &jpeg(900, 1200, Some(6)), 4, 3).unwrap_err().contains("orientation 6"));
        assert!(inspect("image/jpeg", &png(900, 1200), 4, 3).unwrap_err().contains("not image/jpeg"));
        assert!(inspect("image/gif", &png(900, 1200), 4, 3).is_err());
        assert!(inspect("image/png", b"hello", 4, 3).is_err());
        // 900 × 1200 in 3 × 4 is 300 × 300; in 4 × 3 a piece is 225 × 400, too tall.
        assert!(inspect("image/png", &png(900, 1200), 3, 4).unwrap_err().contains("roughly square"));
        assert!(inspect("image/png", &png(900, 1200), 1, 3).is_err());
        assert!(inspect("image/png", &png(900, 1200), 4, 9).is_err());
        // The pixels are capped as well as the bytes: the longest side, and the whole.
        assert_eq!(inspect("image/png", &png(1800, 2400), 4, 3), Ok((1800, 2400)));
        assert!(inspect("image/png", &png(1800, 2401), 4, 3).unwrap_err().contains("1800 × 2401 px"));
        assert!(inspect("image/png", &png(3000, 4000), 4, 3).unwrap_err().contains("12.0 megapixels"));
    }
}
