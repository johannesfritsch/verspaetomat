//! Die Rechtstexte stehen in der App. Diese Tests halten die Website daran fest (docs/31 §4).
use std::path::{Path, PathBuf};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn tmp(name: &str) -> PathBuf {
    let ns = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
    std::env::temp_dir().join(format!("verspaetomat-site-{name}-{ns}"))
}

/// Buchstaben und Ziffern, sonst nichts: so ist der Vergleich unabhängig davon, wie die Vorlage
/// Anführungszeichen, Umlaute oder Tags schreibt.
///
/// Die Entities fliegen vorher ganz heraus, nicht zeichenweise: minijinja schreibt den Schrägstrich
/// in `https://ec.europa.eu/consumers/odr` als `&#x2f;`, und ein „x2f“ mitten im Text wäre für
/// diesen Vergleich ein Buchstabe zu viel.
fn nur_zeichen(s: &str) -> String {
    ohne_entities(s).chars().filter(|c| c.is_alphanumeric()).collect()
}

fn ohne_entities(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(amp) = rest.find('&') {
        out.push_str(&rest[..amp]);
        let nach = &rest[amp + 1..];
        match nach.find(';') {
            // &…; mit höchstens sechs Zeichen ist eine Entity, alles andere ein echtes &
            Some(semi) if semi <= 6 => rest = &nach[semi + 1..],
            _ => {
                out.push('&');
                rest = nach;
            }
        }
    }
    out.push_str(rest);
    out
}

/// Wenn jemand legal.dart ändert und den Export vergisst, zeigt die Website den alten Text.
/// Das ist der Fehler, den niemand bemerkt — also bemerkt ihn der Test.
#[test]
fn legal_json_ist_aktuell() {
    let dart = root().join("../app/lib/content/legal.dart");
    let json = root().join("content/legal.json");
    let m = |p: &Path| std::fs::metadata(p).unwrap().modified().unwrap();
    assert!(
        m(&json) >= m(&dart),
        "content/legal.json ist älter als legal.dart. Neu erzeugen:\n  cd app && dart run tools/legal_json.dart > ../site/content/legal.json"
    );
}

/// Jeder Absatz aus der App steht auch auf der Website — vollständig, nicht sinngemäß.
#[test]
fn jeder_absatz_steht_auf_der_seite() {
    let out = tmp("absaetze");
    verspaetomat_site::build(&root(), &out, false).expect("bauen");
    let site = verspaetomat_site::Site::load(&root()).expect("laden");

    for doc in site.docs() {
        let html = std::fs::read_to_string(out.join(&doc.id).join("index.html")).expect("Seite fehlt");
        let seite = nur_zeichen(&html);
        assert!(seite.contains(&nur_zeichen(&doc.title)), "{}: Titel fehlt", doc.id);
        assert!(seite.contains(&nur_zeichen(&doc.lead)), "{}: Vorspann fehlt", doc.id);
        for section in &doc.sections {
            assert!(seite.contains(&nur_zeichen(&section.heading)), "{}: Überschrift „{}“ fehlt", doc.id, section.heading);
            for p in &section.paragraphs {
                assert!(seite.contains(&nur_zeichen(p)), "{}: ein Absatz unter „{}“ fehlt", doc.id, section.heading);
            }
        }
    }
    std::fs::remove_dir_all(&out).ok();
}

/// dist/ liegt im Git, damit der Server nichts bauen muss. Dann muss dist/ aber auch zu den
/// Inhalten passen — sonst zeigt die Website etwas, das niemand mehr geschrieben hat.
#[test]
fn dist_ist_aktuell() {
    let dist = root().join("dist");
    if !dist.exists() {
        return; // noch nie gebaut: dafür ist dieser Test nicht zuständig
    }
    let out = tmp("dist");
    verspaetomat_site::build(&root(), &out, false).expect("bauen");

    let mut unterschiede = Vec::new();
    vergleiche(&out, &dist, Path::new(""), &mut unterschiede);
    assert!(
        unterschiede.is_empty(),
        "dist/ ist nicht aktuell ({}). Neu erzeugen: cargo run -p verspaetomat-site\n  {}",
        unterschiede.len(),
        unterschiede.join("\n  ")
    );
    std::fs::remove_dir_all(&out).ok();
}

fn vergleiche(frisch: &Path, alt: &Path, rel: &Path, raus: &mut Vec<String>) {
    for entry in std::fs::read_dir(frisch).unwrap() {
        let entry = entry.unwrap();
        let name = entry.file_name();
        let r = rel.join(&name);
        let b = alt.join(&name);
        if entry.file_type().unwrap().is_dir() {
            if !b.is_dir() {
                raus.push(format!("{} fehlt in dist/", r.display()));
                continue;
            }
            vergleiche(&entry.path(), &b, &r, raus);
        } else {
            match std::fs::read(&b) {
                Ok(vorher) if vorher == std::fs::read(entry.path()).unwrap() => {}
                Ok(_) => raus.push(format!("{} unterscheidet sich", r.display())),
                Err(_) => raus.push(format!("{} fehlt in dist/", r.display())),
            }
        }
    }
}

/// Die drei Zustände der Store-Kacheln sind Daten, kein Code: soon → kein Abzeichen, kein Link.
#[test]
fn store_zustaende_sind_daten() {
    let site = verspaetomat_site::Site::load(&root()).expect("laden");
    assert!(!site.index.holen.laden.is_empty());
    for laden in &site.index.holen.laden {
        if laden.state == verspaetomat_site::State::Live {
            assert!(laden.url.is_some(), "{}: live ohne Link", laden.platform);
        }
    }
}
