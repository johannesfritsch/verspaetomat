//! Just enough of an MP4 to check a puzzle video (docs/51 §9b): that it is one (`ftyp` first), how
//! long it runs (`moov/mvhd`) and how large its picture is (the first `tkhd` with a size). Nothing
//! is decoded. The boxes are walked from the file, so `moov` may sit at the end as well as at the
//! start; only `moov` itself is read into memory, and it is small.

use std::io::{Read, Seek, SeekFrom};

/// What the server keeps of a video.
#[derive(Debug, Clone, PartialEq)]
pub struct Facts {
    pub seconds: f64,
    pub width: u32,
    pub height: u32,
}

/// A `moov` larger than this is not a short clip's index; refuse rather than read it.
const MAX_MOOV: u64 = 16 * 1024 * 1024;

/// One box header: its type, where its payload starts and how long it is (None: to the end).
fn header(r: &mut (impl Read + Seek)) -> std::io::Result<Option<([u8; 4], u64, Option<u64>)>> {
    let mut h = [0u8; 8];
    match r.read_exact(&mut h) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(None),
        Err(e) => return Err(e),
    }
    let size = u32::from_be_bytes([h[0], h[1], h[2], h[3]]) as u64;
    let kind = [h[4], h[5], h[6], h[7]];
    let (len, head) = match size {
        0 => (None, 8),
        1 => {
            let mut l = [0u8; 8];
            r.read_exact(&mut l)?;
            (Some(u64::from_be_bytes(l)), 16)
        }
        n => (Some(n), 8),
    };
    let start = r.stream_position()?;
    Ok(Some((kind, start, len.map(|l| l.saturating_sub(head)))))
}

/// Duration and size of the MP4 in `r`, or why it is not one we take.
pub fn facts(r: &mut (impl Read + Seek)) -> Result<Facts, String> {
    let io = |e: std::io::Error| format!("cannot read the file: {e}");
    let mut first = true;
    loop {
        let Some((kind, start, len)) = header(r).map_err(io)? else { return Err("the MP4 has no moov box".into()) };
        if first && &kind != b"ftyp" {
            return Err("not an MP4: it does not start with an ftyp box".into());
        }
        first = false;
        if &kind == b"moov" {
            let len = match len {
                Some(l) => l,
                None => r.seek(SeekFrom::End(0)).map_err(io)? - start,
            };
            if len > MAX_MOOV {
                return Err("the MP4's moov box is too large".into());
            }
            r.seek(SeekFrom::Start(start)).map_err(io)?;
            let mut moov = vec![0u8; len as usize];
            r.read_exact(&mut moov).map_err(|_| "the MP4 is cut off inside its moov box".to_string())?;
            return moov_facts(&moov);
        }
        match len {
            Some(l) => r.seek(SeekFrom::Start(start + l)).map_err(io)?,
            None => return Err("the MP4 has no moov box".into()),
        };
    }
}

/// The children of a box held in memory: (type, payload).
fn children(b: &[u8]) -> impl Iterator<Item = ([u8; 4], &[u8])> {
    let mut at = 0usize;
    std::iter::from_fn(move || {
        let h = b.get(at..at + 8)?;
        let size = u32::from_be_bytes([h[0], h[1], h[2], h[3]]) as usize;
        let kind = [h[4], h[5], h[6], h[7]];
        let (head, size) = match size {
            0 => (8, b.len() - at),
            1 => (16, u64::from_be_bytes(b.get(at + 8..at + 16)?.try_into().ok()?) as usize),
            n => (8, n),
        };
        let payload = b.get(at + head..at.checked_add(size)?)?;
        at += size.max(head);
        Some((kind, payload))
    })
}

fn u32_at(b: &[u8], o: usize) -> Option<u32> {
    Some(u32::from_be_bytes(b.get(o..o + 4)?.try_into().ok()?))
}

fn u64_at(b: &[u8], o: usize) -> Option<u64> {
    Some(u64::from_be_bytes(b.get(o..o + 8)?.try_into().ok()?))
}

fn moov_facts(moov: &[u8]) -> Result<Facts, String> {
    let mvhd = children(moov).find(|(k, _)| k == b"mvhd").map(|(_, p)| p).ok_or("the MP4 has no mvhd box")?;
    // Version 0 keeps the times in 32 bits, version 1 in 64; the timescale is 32 bits in both.
    let (timescale, duration) = match mvhd.first() {
        Some(0) => (u32_at(mvhd, 12), u32_at(mvhd, 16).map(u64::from)),
        Some(1) => (u32_at(mvhd, 20), u64_at(mvhd, 24)),
        _ => (None, None),
    };
    let (Some(timescale), Some(duration)) = (timescale, duration) else { return Err("the MP4's mvhd box cannot be read".into()) };
    if timescale == 0 {
        return Err("the MP4's mvhd box has no timescale".into());
    }
    // The picture's size is in the track header as 16.16 fixed point, after the matrix.
    let size = children(moov).filter(|(k, _)| k == b"trak").find_map(|(_, trak)| {
        let tkhd = children(trak).find(|(k, _)| k == b"tkhd").map(|(_, p)| p)?;
        let at = match tkhd.first()? {
            0 => 76,
            1 => 88,
            _ => return None,
        };
        let (w, h) = (u32_at(tkhd, at)? >> 16, u32_at(tkhd, at + 4)? >> 16);
        (w > 0 && h > 0).then_some((w, h))
    });
    let (width, height) = size.ok_or("the MP4 has no video track")?;
    Ok(Facts { seconds: duration as f64 / timescale as f64, width, height })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    fn fbox(kind: &[u8; 4], payload: &[u8]) -> Vec<u8> {
        let mut b = ((payload.len() + 8) as u32).to_be_bytes().to_vec();
        b.extend_from_slice(kind);
        b.extend_from_slice(payload);
        b
    }

    fn mvhd_v0(timescale: u32, duration: u32) -> Vec<u8> {
        let mut p = vec![0u8; 100];
        p[12..16].copy_from_slice(&timescale.to_be_bytes());
        p[16..20].copy_from_slice(&duration.to_be_bytes());
        fbox(b"mvhd", &p)
    }

    fn mvhd_v1(timescale: u32, duration: u64) -> Vec<u8> {
        let mut p = vec![0u8; 112];
        p[0] = 1;
        p[20..24].copy_from_slice(&timescale.to_be_bytes());
        p[24..32].copy_from_slice(&duration.to_be_bytes());
        fbox(b"mvhd", &p)
    }

    fn trak(w: u32, h: u32) -> Vec<u8> {
        let mut p = vec![0u8; 84];
        p[76..80].copy_from_slice(&(w << 16).to_be_bytes());
        p[80..84].copy_from_slice(&(h << 16).to_be_bytes());
        fbox(b"trak", &fbox(b"tkhd", &p))
    }

    fn mp4(parts: &[Vec<u8>]) -> Vec<u8> {
        let mut f = fbox(b"ftyp", b"isom\0\0\x02\0isomavc1");
        for p in parts {
            f.extend_from_slice(p);
        }
        f
    }

    #[test]
    fn duration_and_size_from_the_headers() {
        // An audio track first (no size), then the video; moov at the start.
        let moov = fbox(b"moov", &[mvhd_v0(1000, 20_500), trak(0, 0), trak(900, 1200)].concat());
        let f = mp4(&[moov, fbox(b"mdat", &[0u8; 64])]);
        assert_eq!(facts(&mut Cursor::new(f)), Ok(Facts { seconds: 20.5, width: 900, height: 1200 }));
        // Version 1, moov at the end behind the media.
        let moov = fbox(b"moov", &[mvhd_v1(90_000, 1_800_000), trak(1200, 900)].concat());
        let f = mp4(&[fbox(b"mdat", &[0u8; 64]), moov]);
        assert_eq!(facts(&mut Cursor::new(f)), Ok(Facts { seconds: 20.0, width: 1200, height: 900 }));
    }

    #[test]
    fn what_is_not_an_mp4_says_why() {
        assert!(facts(&mut Cursor::new(b"\x89PNG\r\n\x1a\n........".to_vec())).unwrap_err().contains("ftyp"));
        assert!(facts(&mut Cursor::new(mp4(&[fbox(b"mdat", &[0u8; 8])]))).unwrap_err().contains("moov"));
        assert!(facts(&mut Cursor::new(mp4(&[fbox(b"moov", &trak(32, 32))]))).unwrap_err().contains("mvhd"));
        assert!(facts(&mut Cursor::new(mp4(&[fbox(b"moov", &mvhd_v0(600, 6000))]))).unwrap_err().contains("video track"));
        assert!(facts(&mut Cursor::new(mp4(&[fbox(b"moov", &[mvhd_v0(0, 6000), trak(32, 32)].concat())]))).unwrap_err().contains("timescale"));
        // Cut off in the middle of moov.
        let mut f = mp4(&[fbox(b"moov", &[mvhd_v0(600, 6000), trak(32, 32)].concat())]);
        f.truncate(f.len() - 10);
        assert!(facts(&mut Cursor::new(f)).unwrap_err().contains("cut off"));
        assert!(facts(&mut Cursor::new(Vec::new())).is_err());
    }

    #[test]
    fn the_test_fixture_reads_as_ffmpeg_wrote_it() {
        let f = include_bytes!("../tests/fixtures/puzzle-video.mp4");
        let got = facts(&mut Cursor::new(f.to_vec())).unwrap();
        assert_eq!((got.width, got.height), (32, 32));
        assert!((got.seconds - 11.0).abs() < 0.1, "{got:?}");
    }
}
