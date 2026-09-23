//! City names for stations whose feed name leaves the city out (issue #60).
//!
//! DELFI is the sum of every German transit authority's export, and some of them name a stop the
//! way you would inside their own network: VVS calls Stuttgart Hbf „Hauptbahnhof (oben)", MVV
//! calls a Munich S-Bahn stop „Laim", HVV „Altona". Nothing in our table said „Stuttgart", so a
//! passenger searching for Stuttgart found nothing at all, and a claim form would have printed
//! „Hauptbahnhof (oben)" as the station.
//!
//! The stop id carries the answer. A German stop id is a DHID, `de:08111:6115`, and its second
//! part is the district key (Kreisschlüssel). For a kreisfreie Stadt the district *is* the city,
//! so every stop under `08111` is in Stuttgart. Landkreise are left alone: their key names a
//! district, not the town the station is in, and „Ostalbkreis, Aalen" would be worse than „Aalen".
//!
//! A name that already says the city — as a word, or in the short form the local feed uses
//! („MA-Käfertal", „HD-Pfaffengrund", „N Frankenstadion") — is kept exactly as it is.

use super::Candidate;

/// Kreisfreie Städte: district key, the city as it is written in front of a station, and the
/// words that already mean this city in a feed's name (lower case, whole words).
const CITIES: &[(&str, &str, &[&str])] = &[
    ("01001", "Flensburg", &["flensburg"]),
    ("01002", "Kiel", &["kiel"]),
    ("01003", "Lübeck", &["lübeck"]),
    ("01004", "Neumünster", &["neumünster"]),
    ("02000", "Hamburg", &["hamburg"]),
    ("03101", "Braunschweig", &["braunschweig"]),
    ("03102", "Salzgitter", &["salzgitter"]),
    ("03103", "Wolfsburg", &["wolfsburg"]),
    ("03401", "Delmenhorst", &["delmenhorst"]),
    ("03402", "Emden", &["emden"]),
    ("03403", "Oldenburg (Oldb)", &["oldenburg"]),
    ("03404", "Osnabrück", &["osnabrück"]),
    ("03405", "Wilhelmshaven", &["wilhelmshaven"]),
    ("04011", "Bremen", &["bremen"]),
    ("04012", "Bremerhaven", &["bremerhaven"]),
    ("05111", "Düsseldorf", &["düsseldorf"]),
    ("05112", "Duisburg", &["duisburg"]),
    ("05113", "Essen", &["essen"]),
    ("05114", "Krefeld", &["krefeld"]),
    ("05116", "Mönchengladbach", &["mönchengladbach"]),
    ("05117", "Mülheim (Ruhr)", &["mülheim"]),
    ("05119", "Oberhausen", &["oberhausen"]),
    ("05120", "Remscheid", &["remscheid"]),
    ("05122", "Solingen", &["solingen"]),
    ("05124", "Wuppertal", &["wuppertal"]),
    ("05314", "Bonn", &["bonn"]),
    ("05315", "Köln", &["köln"]),
    ("05316", "Leverkusen", &["leverkusen"]),
    ("05512", "Bottrop", &["bottrop"]),
    ("05513", "Gelsenkirchen", &["gelsenkirchen"]),
    ("05515", "Münster", &["münster"]),
    ("05711", "Bielefeld", &["bielefeld"]),
    ("05911", "Bochum", &["bochum"]),
    ("05913", "Dortmund", &["dortmund"]),
    ("05914", "Hagen", &["hagen"]),
    ("05915", "Hamm", &["hamm"]),
    ("05916", "Herne", &["herne"]),
    ("06411", "Darmstadt", &["darmstadt"]),
    ("06412", "Frankfurt (Main)", &["frankfurt"]),
    ("06413", "Offenbach (Main)", &["offenbach"]),
    ("06414", "Wiesbaden", &["wiesbaden"]),
    ("06611", "Kassel", &["kassel"]),
    ("07111", "Koblenz", &["koblenz"]),
    ("07211", "Trier", &["trier"]),
    ("07311", "Frankenthal (Pfalz)", &["frankenthal"]),
    ("07312", "Kaiserslautern", &["kaiserslautern"]),
    ("07313", "Landau (Pfalz)", &["landau"]),
    ("07314", "Ludwigshafen", &["ludwigshafen", "lu"]),
    ("07315", "Mainz", &["mainz"]),
    ("07316", "Neustadt (Weinstr.)", &["neustadt"]),
    ("07317", "Pirmasens", &["pirmasens"]),
    ("07318", "Speyer", &["speyer"]),
    ("07319", "Worms", &["worms"]),
    ("07320", "Zweibrücken", &["zweibrücken"]),
    ("08111", "Stuttgart", &["stuttgart"]),
    ("08121", "Heilbronn", &["heilbronn"]),
    ("08211", "Baden-Baden", &["baden-baden", "baden"]),
    ("08212", "Karlsruhe", &["karlsruhe", "ka"]),
    ("08221", "Heidelberg", &["heidelberg", "hd"]),
    ("08222", "Mannheim", &["mannheim", "ma"]),
    ("08231", "Pforzheim", &["pforzheim"]),
    ("08311", "Freiburg", &["freiburg"]),
    ("08421", "Ulm", &["ulm"]),
    ("09161", "Ingolstadt", &["ingolstadt"]),
    ("09162", "München", &["münchen"]),
    ("09163", "Rosenheim", &["rosenheim"]),
    ("09261", "Landshut", &["landshut"]),
    ("09262", "Passau", &["passau"]),
    ("09263", "Straubing", &["straubing"]),
    ("09361", "Amberg", &["amberg"]),
    ("09362", "Regensburg", &["regensburg"]),
    ("09363", "Weiden (Oberpf.)", &["weiden"]),
    ("09461", "Bamberg", &["bamberg"]),
    ("09462", "Bayreuth", &["bayreuth"]),
    ("09463", "Coburg", &["coburg"]),
    ("09464", "Hof", &["hof"]),
    ("09561", "Ansbach", &["ansbach"]),
    ("09562", "Erlangen", &["erlangen"]),
    ("09563", "Fürth", &["fürth"]),
    ("09564", "Nürnberg", &["nürnberg", "n"]),
    ("09565", "Schwabach", &["schwabach"]),
    ("09661", "Aschaffenburg", &["aschaffenburg"]),
    ("09662", "Schweinfurt", &["schweinfurt"]),
    ("09663", "Würzburg", &["würzburg"]),
    ("09761", "Augsburg", &["augsburg"]),
    ("09762", "Kaufbeuren", &["kaufbeuren"]),
    ("09763", "Kempten (Allgäu)", &["kempten"]),
    ("09764", "Memmingen", &["memmingen"]),
    ("11000", "Berlin", &["berlin"]),
    ("12051", "Brandenburg (Havel)", &["brandenburg"]),
    ("12052", "Cottbus", &["cottbus"]),
    ("12053", "Frankfurt (Oder)", &["frankfurt"]),
    ("12054", "Potsdam", &["potsdam"]),
    ("13003", "Rostock", &["rostock"]),
    ("13004", "Schwerin", &["schwerin"]),
    ("14511", "Chemnitz", &["chemnitz"]),
    ("14612", "Dresden", &["dresden"]),
    ("14713", "Leipzig", &["leipzig"]),
    ("15001", "Dessau-Roßlau", &["dessau", "roßlau", "dessau-roßlau"]),
    ("15002", "Halle (Saale)", &["halle"]),
    ("15003", "Magdeburg", &["magdeburg"]),
    ("16051", "Erfurt", &["erfurt"]),
    ("16052", "Gera", &["gera"]),
    ("16053", "Jena", &["jena"]),
    ("16054", "Suhl", &["suhl"]),
    ("16055", "Weimar", &["weimar"]),
];

/// The district key of a MOTIS stop id: `de-DELFI_de:08111:6115:1:1` → `08111`.
fn district_of(source: &str) -> Option<&str> {
    let dhid = source.split_once('_').map(|(_, rest)| rest).unwrap_or(source);
    let mut parts = dhid.split(':');
    if parts.next()? != "de" {
        return None;
    }
    let key = parts.next()?;
    (key.len() == 5 && key.bytes().all(|b| b.is_ascii_digit())).then_some(key)
}

/// Does the name already say the city — one of [words] as a whole word?
fn names_city(name: &str, words: &[&str]) -> bool {
    let lower = name.to_lowercase();
    // Words, split on anything that is not a letter or a hyphenated part of a name. „Karlsruhe-
    // Durlach" is both „karlsruhe-durlach" and „karlsruhe"; „MA-Käfertal" gives „ma".
    let tokens: Vec<&str> = lower.split(|c: char| !c.is_alphanumeric() && c != '-').filter(|t| !t.is_empty()).collect();
    tokens.iter().any(|t| words.iter().any(|w| t == w || t.split('-').any(|p| p == *w)))
}

/// The name with its city in front, when the district is a city and the name does not say it.
pub fn qualified(name: &str, sources: &[String]) -> Option<String> {
    let key = sources.iter().find_map(|s| district_of(s))?;
    let (_, city, words) = CITIES.iter().find(|(k, _, _)| *k == key)?;
    if names_city(name, words) {
        return None;
    }
    Some(format!("{city}, {name}"))
}

/// Puts the city in front of every name that needs it. Returns how many changed.
pub fn qualify_names(stations: &mut [Candidate]) -> usize {
    let mut changed = 0;
    for c in stations.iter_mut() {
        if let Some(q) = qualified(&c.name, &c.sources) {
            c.name = q;
            changed += 1;
        }
    }
    changed
}

#[cfg(test)]
mod tests {
    use super::*;

    fn q(name: &str, source: &str) -> Option<String> {
        qualified(name, &[source.to_string()])
    }

    #[test]
    fn stuttgart_gets_its_name() {
        assert_eq!(q("Hauptbahnhof (oben)", "de-DELFI_de:08111:6115").as_deref(), Some("Stuttgart, Hauptbahnhof (oben)"));
        assert_eq!(q("Zazenhausen", "de-DELFI_de:08111:6361:1:1").as_deref(), Some("Stuttgart, Zazenhausen"));
        assert_eq!(q("Laim", "de-DELFI_de:09162:4").as_deref(), Some("München, Laim"));
        assert_eq!(q("Altona", "de-DELFI_de:02000:10950").as_deref(), Some("Hamburg, Altona"));
    }

    #[test]
    fn a_name_that_says_the_city_is_left_alone() {
        for (name, src) in [
            ("München Hbf", "de-DELFI_de:09162:6"),
            ("Karlsruhe-Durlach", "de-DELFI_de:08212:90"),
            ("MA-Käfertal, DB-Bahnhof", "de-DELFI_de:08222:1"),
            ("HD-Pfaffengrund/Wieblingen", "de-DELFI_de:08221:1"),
            ("N Frankenstadion Sonderbstg.", "de-DELFI_de:09564:1"),
            ("Frankfurt (Main) Galluswarte", "de-DELFI_de:06412:1"),
            ("Heidelberg, Altstadt", "de-DELFI_de:08221:2"),
            ("Flughafen Köln/Bonn Bf", "de-DELFI_de:05315:1"),
            ("Ostbahnhof (Berlin)", "de-VBB_de:11000:900120003"),
        ] {
            assert_eq!(q(name, src), None, "{name}");
        }
    }

    #[test]
    fn a_landkreis_is_not_a_city() {
        assert_eq!(q("Aalen, Hauptbahnhof", "de-DELFI_de:08136:1000"), None);
        assert_eq!(q("Ahlten Bahnhof", "de-DELFI_de:03241:1"), None);
    }

    #[test]
    fn hof_is_a_word_not_a_prefix() {
        assert_eq!(q("Hof Hbf", "de-DELFI_de:09464:1"), None);
        assert_eq!(q("Neuhof", "de-DELFI_de:09464:2").as_deref(), Some("Hof, Neuhof"));
    }

    #[test]
    fn an_id_that_is_not_a_dhid_is_left_alone() {
        assert_eq!(q("Wien Hbf", "at-Railway_at:49:1"), None);
        assert_eq!(q("Irgendwo", "de-DELFI_000123"), None);
    }
}
