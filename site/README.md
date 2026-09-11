# site — verspaetomat.de

Eine Seite, vier Dokumente, keine Laufzeit. Das Konzept steht in `docs/31-website.md`.

```bash
cd site
cargo run                       # baut dist/
cargo run -- --strict           # bricht ab, solange ein Rechtstext [Platzhalter] enthält
cargo test                      # Rechtstexte, dist/, Store-Zustände
python3 -m http.server 4321 -d dist    # ansehen: http://127.0.0.1:4321
```

## Was hier wo liegt

| Pfad | Was |
|---|---|
| `content/index.toml` | Jedes Wort der Startseite. Auch die drei Store-Zustände (`soon` / `testflight` / `live`). |
| `content/legal.json` | Impressum, Datenschutz, „Wie wir Anträge weiterleiten“ — **erzeugt**, nicht geschrieben. |
| `content/loeschen.toml` | Die Löschseite, die Google Play als URL verlangt. Kein Rechtstext, deshalb hier und nicht in der App. |
| `templates/` | `base.html` (Kopf, Fuß, Bahnhofsuhr), `index.html`, `doc.html`. Jinja, zur Laufzeit gelesen. |
| `static/` | Stylesheet, Schriften, Screenshots, og.png, favicon. Wird eins zu eins nach `dist/` kopiert. |
| `og/og.html` | Die Quelle für `static/og.png`, einmal im Browser aufgenommen. Anleitung steht in der Datei. |
| `dist/` | Das Ergebnis. **Liegt im Git**, siehe unten. |

## Die Rechtstexte kommen aus der App

Sie stehen in `app/lib/content/legal.dart` und nirgends sonst. Nach jeder Änderung dort:

```bash
cd app && dart run tools/legal_json.dart > ../site/content/legal.json
cd ../site && cargo run
```

`cargo test` schlägt fehl, wenn `legal.json` älter ist als `legal.dart` — oder wenn ein Absatz
aus der App auf der Website fehlt.

Solange `legal.dart` noch `[Name]`, `[Straße Nr]` und `[PLZ Ort]` sagt, warnt jeder Bau, die
betroffene Seite trägt einen roten Hinweis, und `--strict` veröffentlicht gar nicht erst.

## Warum `dist/` im Git liegt

Der Server baut das Backend aus dem Quelltext, aber er hat weder Rust noch Node für eine
Website. Also wird hier gebaut und das Ergebnis eingecheckt; Caddy hängt `site/dist` als
`/srv/site` ein und liefert Dateien aus. Das macht das Deployment zu einem `git pull` und
nimmt der API-Auslieferung jedes Risiko: an einem Tippfehler in einer TOML-Datei kann kein
Backend-Deploy mehr scheitern.

Der Preis ist ein erzeugtes Verzeichnis in der Versionsverwaltung. Dagegen steht der Test
`dist_ist_aktuell`: er baut frisch und vergleicht. Wer Inhalte ändert und `cargo run` vergisst,
bekommt einen roten Test statt einer Website, die etwas anderes sagt als das Repository.
