//! The website generator (docs/31).
//!
//! Reads `content/`, renders `templates/`, copies `static/`, writes `dist/`. Five documents and a
//! stylesheet: the whole point of the crate is that it is small and that it cannot drift from the
//! app, because the three legal texts are the app's own (`content/legal.json`, exported from
//! `app/lib/content/legal.dart` by `app/tools/legal_json.dart`).
use std::path::{Path, PathBuf};

use anyhow::{bail, Context, Result};
use minijinja::{context, path_loader, Environment};
use serde::{Deserialize, Serialize};

pub const BASE_URL: &str = "https://verspaetomat.de";

// ── what the content files look like ────────────────────────────────────────

/// `content/index.toml` — every word on the front page.
#[derive(Debug, Deserialize, Serialize)]
pub struct Index {
    pub meta: Meta,
    pub hero: Hero,
    pub fahrplan: Fahrplan,
    pub bilder: Bilder,
    pub nicht: Nicht,
    pub fragen: Fragen,
    pub holen: Holen,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Meta {
    pub title: String,
    pub description: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Hero {
    pub eyebrow: String,
    pub headline: String,
    pub lead: String,
    pub cta: String,
    pub cta_secondary: String,
    pub karte: Karte,
}

/// The example Fahrkarte in the hero. Same fields the app prints on a real one (docs/27).
#[derive(Debug, Deserialize, Serialize)]
pub struct Karte {
    pub fahrgast: String,
    pub strecke: String,
    pub am: String,
    pub minuten: u32,
    pub ngo: String,
    pub betrag: String,
    pub zitat: String,
    pub hinweis: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Fahrplan {
    pub eyebrow: String,
    pub title: String,
    pub halt: Vec<Halt>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Halt {
    pub label: String,
    pub text: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Bilder {
    pub eyebrow: String,
    pub title: String,
    pub schuss: Vec<Schuss>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Schuss {
    pub src: String,
    pub alt: String,
    pub caption: String,
    #[serde(default = "shot_width")]
    pub width: u32,
    #[serde(default = "shot_height")]
    pub height: u32,
}

fn shot_width() -> u32 {
    1179
}
fn shot_height() -> u32 {
    2556
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Nicht {
    pub eyebrow: String,
    pub title: String,
    pub punkt: Vec<Punkt>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Punkt {
    pub title: String,
    pub text: String,
    #[serde(default)]
    pub link: Option<String>,
    #[serde(default)]
    pub link_text: Option<String>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Fragen {
    pub eyebrow: String,
    pub title: String,
    pub frage: Vec<Frage>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Frage {
    pub q: String,
    pub a: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Holen {
    pub eyebrow: String,
    pub title: String,
    pub laden: Vec<Laden>,
}

/// One store, in one of three states. Release day is a one-word edit in `content/index.toml`
/// (docs/31 §2.6): Apple does not allow the badge before the app is downloadable.
#[derive(Debug, Deserialize, Serialize)]
pub struct Laden {
    pub platform: String,
    pub state: State,
    pub label: String,
    pub note: String,
    #[serde(default)]
    pub url: Option<String>,
    #[serde(default)]
    pub link_text: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum State {
    /// Not submitted, or waiting for review: no badge, no link.
    Soon,
    /// A public TestFlight link exists.
    Testflight,
    /// In the store: the official badge.
    Live,
}

/// One legal document. The three real ones come from the app; `loeschen.toml` is written here
/// because the app has no page for it — Play asks for a URL, not a screen.
#[derive(Debug, Deserialize, Serialize)]
pub struct Doc {
    pub id: String,
    pub eyebrow: String,
    pub title: String,
    pub lead: String,
    #[serde(default)]
    pub stand: Option<String>,
    pub sections: Vec<Section>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Section {
    pub heading: String,
    pub paragraphs: Vec<String>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Legal {
    pub contact: String,
    pub docs: Vec<Doc>,
}

// ── the build ───────────────────────────────────────────────────────────────

pub struct Report {
    pub pages: usize,
    pub files: usize,
    pub warnings: Vec<String>,
}

/// Everything the templates need, loaded and checked.
pub struct Site {
    pub index: Index,
    pub legal: Legal,
    pub loeschen: Doc,
}

impl Site {
    pub fn load(root: &Path) -> Result<Site> {
        let c = root.join("content");
        let index: Index = toml::from_str(&read(&c.join("index.toml"))?).context("content/index.toml")?;
        let legal: Legal = serde_json::from_str(&read(&c.join("legal.json"))?).context("content/legal.json")?;
        let loeschen: Doc = toml::from_str(&read(&c.join("loeschen.toml"))?).context("content/loeschen.toml")?;
        Ok(Site { index, legal, loeschen })
    }

    /// Every document the site publishes: the app's three, plus the deletion page.
    pub fn docs(&self) -> Vec<&Doc> {
        self.legal.docs.iter().chain(std::iter::once(&self.loeschen)).collect()
    }

    /// `legal.dart` still carries `[Name]`, `[Straße Nr]`, `[PLZ Ort]`. An Impressum that says
    /// `[Name]` is worse than no Impressum, so `--strict` refuses to publish one.
    pub fn placeholders(&self) -> Vec<String> {
        let mut found = Vec::new();
        for doc in self.docs() {
            for section in &doc.sections {
                for p in &section.paragraphs {
                    for token in brackets(p) {
                        found.push(format!("{}: {} enthält {}", doc.id, section.heading, token));
                    }
                }
            }
        }
        found
    }
}

/// `[Name]` and friends. Nothing in these texts legitimately uses square brackets.
fn brackets(s: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut rest = s;
    while let Some(open) = rest.find('[') {
        let after = &rest[open + 1..];
        match after.find(']') {
            Some(close) => {
                out.push(format!("[{}]", &after[..close]));
                rest = &after[close + 1..];
            }
            None => break,
        }
    }
    out
}

pub fn build(root: &Path, out: &Path, strict: bool) -> Result<Report> {
    let site = Site::load(root)?;
    let warnings = site.placeholders();
    if strict && !warnings.is_empty() {
        bail!(
            "{} Platzhalter in den Rechtstexten; nichts veröffentlicht:\n  {}",
            warnings.len(),
            warnings.join("\n  ")
        );
    }

    let mut env = Environment::new();
    env.set_loader(path_loader(root.join("templates")));

    // A fresh dist/ every time: a file that stops being generated must stop being served.
    if out.exists() {
        std::fs::remove_dir_all(out).with_context(|| format!("dist aufräumen: {}", out.display()))?;
    }
    std::fs::create_dir_all(out)?;

    let nav: Vec<_> = site.docs().iter().map(|d| context!(id => d.id, title => nav_title(d))).collect();

    let mut pages = 0;
    let page = env.get_template("index.html")?.render(context! {
        meta => &site.index.meta,
        hero => &site.index.hero,
        fahrplan => &site.index.fahrplan,
        bilder => &site.index.bilder,
        nicht => &site.index.nicht,
        fragen => &site.index.fragen,
        holen => &site.index.holen,
        contact => &site.legal.contact,
        nav => nav,
        canonical => format!("{BASE_URL}/"),
    })?;
    std::fs::write(out.join("index.html"), page)?;
    pages += 1;

    // Pretty URLs: /impressum is dist/impressum/index.html, which Caddy serves as a directory.
    for doc in site.docs() {
        let dir = out.join(&doc.id);
        std::fs::create_dir_all(&dir)?;
        let placeholder_warning = warnings.iter().any(|w| w.starts_with(&format!("{}:", doc.id)));
        let page = env.get_template("doc.html")?.render(context! {
            doc => doc,
            meta => context!(title => format!("{} · Verspätomat", doc.title), description => doc.lead),
            contact => &site.legal.contact,
            nav => nav,
            placeholder_warning => placeholder_warning,
            canonical => format!("{BASE_URL}/{}", doc.id),
        })?;
        std::fs::write(dir.join("index.html"), page)?;
        pages += 1;
    }

    let mut files = copy_dir(&root.join("static"), out)?;

    std::fs::write(out.join("robots.txt"), format!("User-agent: *\nAllow: /\nSitemap: {BASE_URL}/sitemap.xml\n"))?;
    let mut urls = vec![format!("{BASE_URL}/")];
    urls.extend(site.docs().iter().map(|d| format!("{BASE_URL}/{}", d.id)));
    let sitemap = format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n{}</urlset>\n",
        urls.iter().map(|u| format!("  <url><loc>{u}</loc></url>\n")).collect::<String>()
    );
    std::fs::write(out.join("sitemap.xml"), sitemap)?;
    files += 2;

    Ok(Report { pages, files, warnings })
}

/// „Wie wir Anträge weiterleiten" is called „Bote" in the app's own list; the footer wants the
/// long form, which is what the document's title already is.
fn nav_title(doc: &Doc) -> &str {
    &doc.title
}

fn copy_dir(from: &Path, to: &Path) -> Result<usize> {
    let mut n = 0;
    for entry in std::fs::read_dir(from).with_context(|| format!("lesen: {}", from.display()))? {
        let entry = entry?;
        let name = entry.file_name();
        if name.to_string_lossy().starts_with('.') {
            continue;
        }
        let target: PathBuf = to.join(&name);
        if entry.file_type()?.is_dir() {
            std::fs::create_dir_all(&target)?;
            n += copy_dir(&entry.path(), &target)?;
        } else {
            std::fs::copy(entry.path(), &target)?;
            n += 1;
        }
    }
    Ok(n)
}

fn read(p: &Path) -> Result<String> {
    std::fs::read_to_string(p).with_context(|| format!("lesen: {}", p.display()))
}
