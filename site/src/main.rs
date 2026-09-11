//! `cargo run -p verspaetomat-site` — renders `dist/` and exits.
//!
//! This is a second binary, and it is not the API: it never listens on a port and never touches
//! the database. It runs on a laptop, writes files, and Caddy serves them (docs/31 §5).
//!
//!   cargo run                 render into dist/, warn about unfilled placeholders
//!   cargo run -- --strict     refuse to render an Impressum that still says [Name]
//!   cargo run -- --out DIR    somewhere other than dist/
use anyhow::Result;

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let strict = args.iter().any(|a| a == "--strict");
    let out = match args.iter().position(|a| a == "--out") {
        Some(i) => args.get(i + 1).cloned().unwrap_or_else(|| "dist".into()),
        None => "dist".into(),
    };

    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let out = root.join(out);
    let report = verspaetomat_site::build(root, &out, strict)?;

    for w in &report.warnings {
        eprintln!("warnung: {w}");
    }
    println!("{} Seiten, {} Dateien → {}", report.pages, report.files, out.display());
    Ok(())
}
