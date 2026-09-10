//! Postgres: pool, migrations, seed, and the row types handlers read.

pub mod rows;

use anyhow::Context;
use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;

pub async fn connect() -> anyhow::Result<PgPool> {
    let url = std::env::var("DATABASE_URL").unwrap_or_else(|_| "postgres://localhost/verspaetomat".to_string());
    let pool = PgPoolOptions::new().max_connections(8).connect(&url).await.context("connect to postgres")?;
    sqlx::migrate!("./migrations").run(&pool).await.context("run migrations")?;
    Ok(pool)
}

/// Idempotent: operators, NGOs, badges and seeded board rows from the fixtures.
pub async fn seed(pool: &PgPool) -> anyhow::Result<()> {
    let f = crate::fixtures::Fixtures::embedded();

    for o in &f.operators {
        let aliases: Vec<String> = match o.name.as_str() {
            "DB Regio NRW" => vec!["DB Regio AG NRW".into(), "DB Regio AG".into(), "DB Regio NRW".into()],
            "DB Fernverkehr" => vec!["DB Fernverkehr AG".into(), "DB Fernverkehr".into()],
            "National Express" => vec!["National Express".into(), "National Express Rail GmbH".into()],
            "NordWestBahn" => vec!["NordWestBahn".into(), "NordWestBahn GmbH".into()],
            "ODEG" => vec!["ODEG".into(), "Ostdeutsche Eisenbahn GmbH".into()],
            "eurobahn" => vec!["eurobahn".into(), "eurobahn GmbH & Co. KG".into()],
            _ => vec![o.name.clone()],
        };
        sqlx::query(
            "insert into operators (name, aliases, desk, postal_address, email, accepts_email, last_verified)
             values ($1, $2, $3, $4, $5, $6, $7)
             on conflict (name) do update set aliases = excluded.aliases, desk = excluded.desk,
               postal_address = excluded.postal_address, email = excluded.email,
               accepts_email = excluded.accepts_email, last_verified = excluded.last_verified",
        )
        .bind(&o.name)
        .bind(&aliases)
        .bind(&o.desk)
        .bind(&o.postal_address)
        .bind(&o.email)
        .bind(o.accepts_email)
        .bind(o.last_verified)
        .execute(pool)
        .await?;
    }

    // NGOs are managed data (admin API, `stellwerk ngo …`): the fixture only fills an empty table.
    let ngo_count: i64 = sqlx::query_scalar("select count(*) from ngos").fetch_one(pool).await?;
    for n in f.ngos.iter().filter(|_| ngo_count == 0) {
        sqlx::query(
            "insert into ngos (id, name, tagline, story, account_holder, iban, donation_url, last_report, seed_confirmed_cents, seed_submitted_cents)
             values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
             on conflict (id) do update set name = excluded.name, tagline = excluded.tagline, story = excluded.story,
               account_holder = excluded.account_holder, iban = excluded.iban, donation_url = excluded.donation_url,
               last_report = excluded.last_report, seed_confirmed_cents = excluded.seed_confirmed_cents,
               seed_submitted_cents = excluded.seed_submitted_cents",
        )
        .bind(&n.id)
        .bind(&n.name)
        .bind(&n.tagline)
        .bind(serde_json::to_value(&n.story)?)
        .bind(&n.account_holder)
        .bind(&n.iban)
        .bind(&n.donation_url)
        .bind(n.last_report)
        .bind(n.confirmed_total_cents)
        .bind(n.submitted_total_cents)
        .execute(pool)
        .await?;
    }

    for b in &f.badges {
        sqlx::query("insert into badges (id, name, rule) values ($1, $2, $3) on conflict (id) do update set name = excluded.name, rule = excluded.rule")
            .bind(&b.id)
            .bind(&b.name)
            .bind(&b.rule)
            .execute(pool)
            .await?;
    }

    for (scope, list) in [("line", &f.boards.line), ("city", &f.boards.city), ("germany", &f.boards.germany)] {
        for e in list.iter().filter(|e| !e.is_me) {
            sqlx::query("insert into board_seed (scope, rank, name, points) values ($1, $2, $3, $4) on conflict (scope, rank) do update set name = excluded.name, points = excluded.points")
                .bind(scope)
                .bind(e.rank as i32)
                .bind(&e.name)
                .bind(e.points as i32)
                .execute(pool)
                .await?;
        }
    }
    Ok(())
}
