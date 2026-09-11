// The three legal texts, as JSON for the website (docs/31 §4).
//
// The website does not keep its own copy of the Impressum, the Datenschutz-
// erklärung and „Wie wir Anträge weiterleiten": it renders these. The Dart
// compiler is the parser, so the export cannot drift from what the app shows.
//
//   cd app && dart run tools/legal_json.dart > ../site/content/legal.json
//
// Regenerate whenever lib/content/legal.dart changes; `cargo test` in site/
// fails if the JSON is older than the Dart file.
import 'dart:convert';
import 'dart:io';

import 'package:verspaetomat/content/legal.dart';

void main() {
  final out = {
    'contact': legalContactEmail,
    'docs': [
      for (final d in legalDocs)
        {
          'id': d.id,
          'eyebrow': d.eyebrow,
          'title': d.title,
          'lead': d.lead,
          if (d.stand != null) 'stand': d.stand,
          'sections': [
            for (final s in d.sections) {'heading': s.heading, 'paragraphs': s.paragraphs},
          ],
        },
    ],
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
