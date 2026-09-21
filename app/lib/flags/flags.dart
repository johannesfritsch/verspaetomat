import 'package:flutter/foundation.dart' show immutable;

import 'flag_doc.dart';

/// Every flag this build knows how to ask about (issue #41).
///
/// **The enum is the only key there is.** Nothing outside this file spells a flag name, so a
/// misspelt flag does not compile — where a string at the call site would have resolved to a
/// silent false and looked exactly like a flag that is switched off. Deleting a member breaks
/// every reader, which is how a flag gets retired instead of lingering.
///
/// **FALSE IS THE BEHAVIOUR THAT ALREADY SHIPPED** — migration 0037's rule, inherited verbatim.
/// There is no per-flag default anywhere in this file, so there is no way to declare a flag whose
/// absence turns something new on. A flag's name always says what turning it **on** does; a kill
/// switch for something that shipped unflagged is named for the killing
/// (`openai_reply_reading_off`), never for the feature.
///
/// The server sends a key only when its value differs from the default (`Table::wire_map` in
/// backend/src/flags.rs), so "absent" is the path every build takes for every flag on every
/// launch of every ordinary day. The fallback is the exercised branch, not the untested one.
enum Flag {
  /// Named exactly as `STATIONS_LOCAL` in `backend/src/flags.rs` spells it, which
  /// `test/flag_parity_test.dart` pins.
  stationsLocal(
    'stations_local',
    about: 'Die native Hintergrund-Schicht beantwortet „welche Bahnhöfe sind nah" aus der '
        'Auszugsdatei statt über GET /v1/stations/nearby.',
    readBy: null,
  );

  const Flag(this.wire, {required this.about, this.readBy});

  /// The name on the wire, in the database and in `stellwerk`.
  final String wire;

  /// One German sentence for whoever is reading the Entwicklung page at a platform edge.
  final String about;

  /// Where *this build* acts on the flag, or null when nothing does yet.
  ///
  /// It exists because a debug page that lists a flag implies the phone obeys it, and for a flag
  /// that is registered but not yet wired that would be a sentence the code does not support.
  /// `stations_local` is exactly that case, and the backend's own registry says so: the
  /// background layer still takes its value from the `stations_local` field on
  /// `GET /v1/me/geofence` (#40), which has to stay byte-identical while builds 64–66 are in
  /// TestFlight. Moving that call site is the last step of #41.
  final String? readBy;

  /// How `stellwerk` and the Entwicklung page spell it.
  String get cli => wire.replaceAll('_', '-');

  /// The flag with this name, or null when this build has never heard of it. Accepts both
  /// spellings, the way `stellwerk` does.
  static Flag? parse(String name) {
    for (final f in Flag.values) {
      if (f.wire == name || f.cli == name) return f;
    }
    return null;
  }
}

/// Why a flag reads the way it does. The Entwicklung page prints it; nothing branches on it.
enum FlagSource {
  /// The server said nothing about it, so this build does what it has always done. The ordinary
  /// case, on every launch, for every flag that is not currently switched on.
  shipped,

  /// The server published a value for it.
  server,

  /// Pinned in this process — by a test, or by `--dart-define=FLAGS=` on a debug build.
  pinned,

  /// The server published something this build cannot read as a yes or a no.
  ///
  /// Narrower than it looks, and deliberately kept anyway. A flag whose *stored row* is of the
  /// wrong type never reaches the wire: `Table::wire_map` goes through `value_of`, which coerces
  /// a wrong-typed row back to its default, so such a flag is simply **absent** and reads as
  /// [shipped] (measured by flags-backend against a row set to `"vielleicht"`: one `WARN` and
  /// `{"flags":{}}`). What can still land here is a malformed body that parsed as JSON, and a
  /// flag that has become an `int` or a `string` server-side while this build still reads
  /// booleans — which is the case `test/flag_parity_test.dart` is meant to catch at build time,
  /// with this as the runtime net under it.
  ///
  /// It resolves to false like every other kind of not knowing. It is named rather than folded
  /// into [shipped] because "the server says on and the phone says off" is otherwise
  /// unanswerable from the device.
  unreadable,
}

extension FlagSourceLabel on FlagSource {
  /// For the Entwicklung page, in the register the rest of it uses.
  String get label => switch (this) {
        FlagSource.shipped => 'Standard',
        FlagSource.server => 'Server',
        FlagSource.pinned => 'erzwungen',
        FlagSource.unreadable => 'unlesbar',
      };
}

/// One flag's answer, and where it came from.
@immutable
class FlagState {
  const FlagState(this.flag, {required this.on, required this.source});
  final Flag flag;
  final bool on;
  final FlagSource source;
}

/// What the server last said, resolved for this phone.
///
/// A value, not a service: no I/O, no async, no null, and it never throws. [on] is a map lookup,
/// so a screen can ask on its way into `build()` and **no screen ever waits on a flag**.
@immutable
class Flags {
  const Flags({this.doc = FlagDoc.empty, this.confirmedAt, this.pins = const <Flag, bool>{}});

  /// Before the first answer, in Demo, offline, and on a phone that has never reached the
  /// server: every flag false. Named so that the fallback is a thing you can point at.
  static const none = Flags();

  /// The document as the server wrote it, including names this build does not know.
  ///
  /// **If a per-customer set ever arrives, it replaces this one — it is not merged into it, key
  /// by key.** Nothing carries per-customer flags today (`handlers.rs` has no `flags` key), so
  /// this is a note for whoever wires one up rather than a description of code that exists, and
  /// it is written down because the wrong version of it is the obvious version.
  ///
  /// Per-key precedence looks right and silently breaks the one case targeting exists for.
  /// Taking one person back out of a rollout means global `true`, override `false`. The document
  /// says `{"stations_local":true}`. The customer's own map **omits** the key, because `false` is
  /// the default and the server never sends a value equal to its default. A per-key lookup misses
  /// it, falls through to the document, and answers `true` — the override lost, precisely when
  /// somebody was trying to switch one person off.
  ///
  /// So a customer's map is the complete and authoritative answer for that customer, and this
  /// document is the fallback before there is one: first launch, logged out, offline.
  final FlagDoc doc;

  /// When the server last confirmed [doc] — a 200 or a 304. A failed fetch does not move it,
  /// because a failed call is not an answer.
  ///
  /// Nothing resolves on it: the backend publishes no maximum age, so a flag does not expire and
  /// a phone that never reaches the server keeps its last answer indefinitely. It is here because
  /// "how old is this answer?" is the second question anybody debugging a flag asks, and the
  /// Entwicklung page has to be able to answer it.
  final DateTime? confirmedAt;

  /// Pinned in this process: a test, or the `--dart-define=FLAGS=` door on a debug build.
  final Map<Flag, bool> pins;

  /// True only when somebody positively said so.
  ///
  /// Every other answer is false: no document yet, a document that would not parse, a fetch that
  /// failed, a flag the server has never heard of, a value this build cannot read. That is one
  /// behaviour with one name, and it is the behaviour this build already had before the flag
  /// existed.
  bool on(Flag f) => stateOf(f).on;

  /// [on], with the reason attached. The Entwicklung page is the only caller.
  FlagState stateOf(Flag f) {
    final pinned = pins[f];
    if (pinned != null) return FlagState(f, on: pinned, source: FlagSource.pinned);

    // The server sends a key only when it differs from the default, so this is the branch almost
    // every read takes, almost always.
    if (!doc.values.containsKey(f.wire)) return FlagState(f, on: false, source: FlagSource.shipped);

    final value = doc.values[f.wire];
    if (value is! bool) return FlagState(f, on: false, source: FlagSource.unreadable);
    return FlagState(f, on: value, source: FlagSource.server);
  }

  /// Every flag this build knows, in declaration order. The Entwicklung page draws this.
  List<FlagState> get all => [for (final f in Flag.values) stateOf(f)];

  /// The ones that are on, by wire name, sorted. For the pasted log header.
  List<String> get onNames => [for (final s in all) if (s.on) s.flag.wire]..sort();

  /// Names the server published and this build does not know.
  ///
  /// Benign and confusing: the server says on, the phone has no code behind it. Showing them is
  /// how that gets noticed instead of guessed at.
  List<String> get unknownNames => doc.values.keys.where((n) => Flag.parse(n) == null).toList()..sort();

  Flags copyWith({FlagDoc? doc, DateTime? confirmedAt, Map<Flag, bool>? pins}) => Flags(
        doc: doc ?? this.doc,
        confirmedAt: confirmedAt ?? this.confirmedAt,
        pins: pins ?? this.pins,
      );

  /// Same answers to every question anybody can ask? Used to decide whether a refresh is worth
  /// telling the app about, so a 304 every half hour does not rebuild the tree.
  bool sameAnswersAs(Flags other) {
    if (unknownNames.join(',') != other.unknownNames.join(',')) return false;
    for (final f in Flag.values) {
      final a = stateOf(f), b = other.stateOf(f);
      if (a.on != b.on || a.source != b.source) return false;
    }
    return true;
  }
}
