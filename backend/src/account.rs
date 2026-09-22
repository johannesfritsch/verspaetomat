//! Deleting an account, for real.
//!
//! The foreign keys do most of it: `devices` → `customers` → rides, journeys, incidents, claims,
//! mails, uploads, badges all cascade (see the migrations). Three things do not, because nothing
//! points at the customer with a key:
//!
//! - `audit_log` rows name a claim, an incident or a ride by id only;
//! - `flag_log` rows name the customer by id only;
//! - an upload written since 0027 is a file under `UPLOAD_DIR`, and deleting its row leaves the
//!   file on the volume.
//!
//! So the ids and paths are read first, everything is deleted in one transaction, and the files
//! go after the commit — a file removed before a rollback would be a picture gone from a claim
//! that still exists. Mail to the account's addresses is refused afterwards: inbound routing finds
//! no customer and answers 404 (`process_detached`), so nothing is stored for an account that is gone.

use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

#[derive(Debug, Default, Serialize, PartialEq)]
pub struct Deleted {
    pub rides: i64,
    pub claims: i64,
    pub mails: i64,
    pub uploads: i64,
    pub files: usize,
    pub audit_rows: u64,
}

pub async fn delete_customer(pool: &PgPool, id: Uuid) -> anyhow::Result<Deleted> {
    let mut tx = pool.begin().await?;
    let (rides, claims, mails, uploads): (i64, i64, i64, i64) = sqlx::query_as(
        "select (select count(*) from rides where customer_id = $1),
                (select count(*) from claims where customer_id = $1),
                (select count(*) from mails where customer_id = $1),
                (select count(*) from uploads where customer_id = $1)",
    )
    .bind(id)
    .fetch_one(&mut *tx)
    .await?;
    let paths: Vec<String> = sqlx::query_scalar("select path from uploads where customer_id = $1 and path is not null")
        .bind(id)
        .fetch_all(&mut *tx)
        .await?;
    // Everything the audit log may name for this customer.
    let audit = sqlx::query(
        "delete from audit_log where entity_id = $1
            or entity_id in (select id from claims where customer_id = $1)
            or entity_id in (select id from incidents where customer_id = $1)
            or entity_id in (select id from rides where customer_id = $1)
            or entity_id in (select id from journeys where customer_id = $1)
            or entity_id in (select id from mails where customer_id = $1)",
    )
    .bind(id)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    sqlx::query("delete from flag_log where customer_id = $1").bind(id).execute(&mut *tx).await?;
    let gone = sqlx::query("delete from devices where id = $1").bind(id).execute(&mut *tx).await?.rows_affected();
    anyhow::ensure!(gone == 1, "no device {id}");
    // The cascade is the migrations' promise; check it inside the transaction rather than trust it.
    // A table added later without `on delete cascade` would otherwise leave rows behind silently.
    let left: i64 = sqlx::query_scalar(
        "select (select count(*) from customers where id = $1) + (select count(*) from rides where customer_id = $1)
              + (select count(*) from claims where customer_id = $1) + (select count(*) from mails where customer_id = $1)
              + (select count(*) from uploads where customer_id = $1) + (select count(*) from incidents where customer_id = $1)
              + (select count(*) from journeys where customer_id = $1) + (select count(*) from badge_awards where customer_id = $1)
              + (select count(*) from sim_customer_location where customer_id = $1)",
    )
    .bind(id)
    .fetch_one(&mut *tx)
    .await?;
    anyhow::ensure!(left == 0, "{left} rows of customer {id} survived the delete");
    tx.commit().await?;

    for p in &paths {
        crate::storage::remove(p).await;
    }
    Ok(Deleted { rides, claims, mails, uploads, files: paths.len(), audit_rows: audit })
}
