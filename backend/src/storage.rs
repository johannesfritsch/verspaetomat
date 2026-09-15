//! Where an upload's bytes live.
//!
//! They used to live in a `bytea` column, and the migration that created it said `-- object
//! storage later`. A drawn ticket was forty kilobytes and nobody noticed; a photograph of a ticket
//! is three megabytes, and every read pulls the whole blob through the API process and every
//! `pg_dump` carries it. So the bytes are files now, one per upload id, under [`dir`], and the row
//! keeps the path.
//!
//! **There is no application-level encryption here, on purpose.** Two docs used to promise one and
//! no code ever did it, which is the worse of the two states. The host's disk is encrypted, the
//! directory is a Docker volume that only the API container mounts, and what the app promises the
//! passenger is the thing we actually do: the file is deleted when the claim closes (docs/05).
//!
//! Old rows keep their `bytes` and no `path`. [`load`] takes both and prefers the file, so nothing
//! has to be migrated on the way in.

use std::path::{Path, PathBuf};

use uuid::Uuid;

/// The directory uploads are written to. `UPLOAD_DIR`, or `./uploads` beside the working
/// directory for `./dev.sh`. In the container it is a mounted volume (deploy/docker-compose.yml).
pub fn dir() -> PathBuf {
    std::env::var("UPLOAD_DIR").map(PathBuf::from).unwrap_or_else(|_| PathBuf::from("uploads"))
}

/// Create the directory if it is not there. Called once at start so a misconfigured volume fails
/// loudly on boot rather than on the first passenger's ticket.
pub fn init() -> std::io::Result<PathBuf> {
    let d = dir();
    std::fs::create_dir_all(&d)?;
    Ok(d)
}

/// Where one upload's file goes. The id is a v4 UUID, so the name is already safe and unique;
/// nothing from the request reaches the path.
fn path_for(id: Uuid) -> PathBuf {
    dir().join(id.to_string())
}

/// The value stored in `uploads.path`: relative to [`dir`], so moving the volume does not
/// invalidate every row.
pub async fn put(id: Uuid, data: &[u8]) -> std::io::Result<String> {
    let p = path_for(id);
    if let Some(parent) = p.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }
    tokio::fs::write(&p, data).await?;
    Ok(id.to_string())
}

/// The bytes of an upload, wherever they are. `path` wins; `bytes` is the legacy column.
///
/// A row whose file has gone (retention, or a volume that was not mounted) reads as empty rather
/// than as an error, because every caller already has a branch for "the bytes are gone" and none
/// of them should turn a missing file into a 500 on an unrelated request.
pub async fn load(path: Option<&str>, bytes: Option<Vec<u8>>) -> Vec<u8> {
    if let Some(rel) = path {
        if !is_safe(rel) {
            tracing::error!(path = rel, "upload path is not a plain name; refusing to read");
            return Vec::new();
        }
        let p = dir().join(rel);
        return match tokio::fs::read(&p).await {
            Ok(b) => b,
            Err(e) => {
                tracing::warn!(path = %p.display(), error = %e, "upload file missing");
                Vec::new()
            }
        };
    }
    bytes.unwrap_or_default()
}

/// Delete one upload's file. Retention calls this before it clears the row's path.
pub async fn remove(path: &str) {
    if !is_safe(path) {
        tracing::error!(path, "upload path is not a plain name; refusing to delete");
        return;
    }
    let p = dir().join(path);
    if let Err(e) = tokio::fs::remove_file(&p).await {
        if e.kind() != std::io::ErrorKind::NotFound {
            tracing::warn!(path = %p.display(), error = %e, "could not delete upload file");
        }
    }
}

/// True if this looks like a PNG. Used where the bytes used to be sniffed in SQL.
pub fn is_png(data: &[u8]) -> bool {
    data.starts_with(&[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
}

/// Guard against a path that tries to leave [`dir`]. Values we write are plain UUIDs, so this only
/// matters for a row somebody edited by hand — but the cost of checking is nothing and the cost of
/// not checking is reading or deleting an arbitrary file on the host.
fn is_safe(rel: &str) -> bool {
    !rel.is_empty() && Path::new(rel).components().all(|c| matches!(c, std::path::Component::Normal(_)))
}
