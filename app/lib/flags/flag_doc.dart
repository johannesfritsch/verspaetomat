import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;

/// The document served at `GET /v1/flags.json` — unauthenticated, ETag'd, one pre-rendered string
/// out of the server's memory (`backend/src/flags.rs`, `Table::wire_map`).
///
/// ```json
/// {"flags":{"stations_local":true}}
/// ```
///
/// **A key is present only when its value differs from what already shipped.** That is the whole
/// design, and it is why the fallback here can be trusted: "the flag is absent" is not an error
/// path, it is the answer every build gets for every flag on every launch of every ordinary day.
/// The rare case is the key being there at all. There is no untested branch to rot.
///
/// The document carries what is true for **everybody**. A flag under a rollout and a flag set for
/// one person are never in it — that would publish customer ids and make the document
/// uncacheable — so nothing in here is personal and nothing in here is secret.
@immutable
class FlagDoc {
  const FlagDoc({required this.values});

  /// No document: what a phone holds before its first answer, and after one that would not parse.
  static const empty = FlagDoc(values: <String, Object?>{});

  /// Raw JSON values keyed by wire name, exactly as the server wrote them, including names this
  /// build has never heard of and values of types it cannot use.
  ///
  /// Raw on purpose. Reading `true` out of this is [Flags]'s job; keeping whatever is actually
  /// there is this one's, so that the Entwicklung page can show the difference between "the server
  /// says nothing" and "the server says something this build cannot read".
  final Map<String, Object?> values;

  bool get isEmpty => values.isEmpty;

  /// Never throws, and answers null for anything it does not recognise as a document.
  ///
  /// Null and an empty document are deliberately different: null means "keep what you had" — a
  /// truncated body or an error page from a proxy must not blank every flag on every phone at
  /// once — and an empty one means "the server published nothing", which is the ordinary state of
  /// a system with no flag currently switched on.
  static FlagDoc? parse(String body) {
    try {
      final j = jsonDecode(body);
      if (j is! Map) return null;
      final flags = j['flags'];
      if (flags is! Map) return null;
      final values = <String, Object?>{};
      for (final entry in flags.entries) {
        final name = entry.key;
        if (name is! String || name.isEmpty) continue;
        values[name] = entry.value;
      }
      return FlagDoc(values: Map.unmodifiable(values));
    } catch (_) {
      return null;
    }
  }
}
