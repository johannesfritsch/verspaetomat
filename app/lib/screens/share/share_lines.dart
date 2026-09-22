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
  /// At send time (#49). Nobody has paid yet, so no line says anyone has: the claim is in, and
  /// the money is what it is for. [bestaetigt] says the rest once the railway has answered.
  static List<String> antrag({required int minutes, required int cases, required int cents, required String ngo}) {
    final min = _min(minutes);
    final euro = fmtCents(cents);
    return [
      '$min zu spät. Der Antrag ist raus, das Geld soll an $ngo gehen.',
      'Eingereicht: $min Verspätung, $euro für $ngo.',
      '$min gewartet. Jetzt ist die Bahn am Zug: $euro für $ngo.',
      'Aus $min Warten sollen $euro für $ngo werden.',
    ];
  }

  /// The railway has confirmed the claim (#49). Now „dazu gebracht … zu zahlen" is true.
  static List<String> bestaetigt({required int minutes, required int cents, required String ngo}) {
    final min = _min(minutes);
    final euro = fmtCents(cents);
    return [
      'Ich habe die Bahn dazu gebracht, an $ngo zu zahlen. Weil sie mich $min warten ließ.',
      'Die Bahn zahlt $euro an $ngo. Wegen mir.',
      'Aus $min Warten wurden $euro für $ngo.',
      '$min zu spät. Das Geld dafür bekommt $ngo.',
    ];
  }

  /// My own minutes (#49). With [together], the one line that also names everybody's.
  static List<String> mine({required int minutes, int? together}) {
    final min = _min(minutes);
    return [
      'Ich habe schon $min auf Züge gewartet.',
      if (together != null && together > minutes) 'Ich habe $min auf Züge gewartet. Zusammen sind wir bei ${_int(together)} Minuten.',
      '$min Verspätung. Gesammelt, nicht vergessen.',
      '$min meines Lebens am Bahnsteig. Verspätomat zählt mit.',
    ];
  }

  /// A new longest delay (#49).
  static List<String> rekord({required int minutes, String? to}) {
    final min = _min(minutes);
    final ziel = to == null ? '' : ' nach $to';
    return [
      'Neuer Rekord: $min zu spät$ziel.',
      '$min. Länger habe ich noch nie auf einen Zug gewartet.',
      'Mein Rekord steht jetzt bei $min$ziel.',
    ];
  }

  /// The line that cost the most this month (#49). No article in front of the line: it is „der
  /// RE 7" but „die S 12", and a sentence that guesses gets one of them wrong.
  static List<String> linie({required String train, required int minutes, required int rides, required String month}) {
    final dauer = duration(minutes);
    return [
      'Meine Linie im $month: $train, $dauer Verspätung.',
      '$train, $month: $dauer gewartet, in ${rides == 1 ? 'einer Fahrt' : '$rides Fahrten'}.',
      '$dauer Verspätung im $month. Linie: $train.',
    ];
  }

  /// Last month in one card (#49).
  static List<String> monat({required String month, required int minutes, required int rides, required int worst, int confirmedCents = 0}) {
    final min = _min(minutes);
    return [
      'Mein $month: $min Verspätung in ${rides == 1 ? 'einer Fahrt' : '$rides Fahrten'}.',
      '$month vorbei. $min gewartet, die längste Verspätung $worst Minuten.',
      if (confirmedCents > 0) 'Im $month $min gewartet. Bestätigt: ${fmtCents(confirmedCents)} für den Verein.',
    ];
  }

  static String _min(int minutes) => '${_int(minutes)} ${minutes == 1 ? 'Minute' : 'Minuten'}';

  /// „3 Stunden 12 Minuten", „1 Stunde", „45 Minuten".
  static String duration(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    final hs = h == 0 ? '' : '$h ${h == 1 ? 'Stunde' : 'Stunden'}';
    final ms = m == 0 ? '' : '$m ${m == 1 ? 'Minute' : 'Minuten'}';
    if (hs.isEmpty) return ms.isEmpty ? '0 Minuten' : ms;
    return ms.isEmpty ? hs : '$hs $ms';
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
