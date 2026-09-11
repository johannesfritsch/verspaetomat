import '../claims/claims_widgets.dart' show fmtCents;

/// The sentences a passenger can pick from (docs/27 §1).
///
/// Four per face, differing by register rather than by content, because the right voice for this
/// is not the same for everybody. The first is the dry one and it is the default; the plain one
/// exists for anyone who would rather not be funny about it, which is most people some of the time.
///
/// None of them calls the payment a donation: the railway is paying because somebody made a
/// claim, and „dazu gebracht … zu zahlen" is exactly what happened.
class ShareLines {
  static List<String> antrag({required int minutes, required int cases, required int cents, required String ngo}) {
    final min = '$minutes ${minutes == 1 ? 'Minute' : 'Minuten'}';
    final euro = fmtCents(cents);
    return [
      'Ich habe die Bahn dazu gebracht, an $ngo zu zahlen. Weil sie mich $min warten ließ.',
      '$min zu spät. Das Geld dafür bekommt $ngo.',
      '$min meines Lebens. Immerhin zahlt die Bahn dafür an $ngo.',
      'Aus $min Warten werden $euro für $ngo.',
    ];
  }

  static List<String> angekommen({required int minutes, required String? to}) {
    final min = '$minutes ${minutes == 1 ? 'Minute' : 'Minuten'}';
    final ziel = to == null ? '' : ' nach $to';
    return [
      '$min zu spät$ziel. Immerhin zählt das jetzt für etwas.',
      '$min Verspätung$ziel. Gesammelt, nicht vergessen.',
      'Die Bahn schuldet mir $min$ziel.',
      '$min gewartet$ziel. Verspätomat zählt mit.',
    ];
  }

  static List<String> puenktlich({required String? to}) {
    final ziel = to == null ? '' : ' nach $to';
    return [
      'Heute war die Bahn pünktlich. Screenshot als Beweis.',
      'Pünktlich$ziel. Ich war genauso überrascht.',
      'Null Minuten Verspätung. Es kommt vor.',
      'Der Zug$ziel war pünktlich. Kein Anspruch, kein Ärger.',
    ];
  }

  /// The badge name is quoted inside a sentence that the ticket quotes again, so it takes the
  /// inner German marks, and no line opens with it — „‚ side by side is a cramped way to
  /// start a sentence. Nesting: „… ‚Erste Verspätung‘ …“.
  static List<String> wir({required int minutes}) => [
        'Zusammen haben wir schon ${_int(minutes)} Minuten auf Züge gewartet.',
        '${_int(minutes)} Minuten Wartezeit. Wir machen Geld daraus, das anderen hilft.',
        'Wir sind viele, die warten: ${_int(minutes)} Minuten bisher.',
      ];

  /// German thousands, the way the app writes every other number.
  static String _int(int v) {
    final s = v.toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write('.');
      out.write(s[i]);
    }
    return out.toString();
  }

  static List<String> abzeichen({required String name}) => [
        'Freigeschaltet: ‚$name‘. Nicht ganz freiwillig.',
        'Neues Abzeichen: $name.',
        'Ich habe mir ‚$name‘ erarbeitet. Genauer gesagt: die Bahn hat das.',
        'Man nimmt, was man kriegt: ‚$name‘.',
      ];
}
