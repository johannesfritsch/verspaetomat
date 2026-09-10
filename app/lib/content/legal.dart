/// The legal texts shown in the app: Impressum, Datenschutzerklärung and the
/// messenger clause ("Bote, nicht Vertreter"). Plain data, no widgets, so the
/// wording can be edited without touching a screen. Sources: docs/05-legal.md,
/// docs/03-claim-filing.md, docs/14-location-concept.md.
///
/// Placeholders in square brackets ([Name], [Straße Nr], [PLZ Ort]) must be
/// filled in before the first store build. Nothing in here is invented.
library;

class LegalSection {
  const LegalSection(this.heading, this.paragraphs);
  final String heading;
  final List<String> paragraphs;
}

class LegalDoc {
  const LegalDoc({required this.id, required this.eyebrow, required this.title, required this.lead, required this.sections, this.stand});
  final String id; // impressum | datenschutz | bote
  final String eyebrow;
  final String title;
  final String lead;
  final List<LegalSection> sections;
  final String? stand;
}

/// Contact that appears in all three texts.
const legalContactEmail = 'j@jfritsch.de';

const impressum = LegalDoc(
  id: 'impressum',
  eyebrow: 'Rechtliches',
  title: 'Impressum',
  lead: 'Angaben nach § 5 DDG.',
  sections: [
    LegalSection('Anbieter', [
      '[Name]\n[Straße Nr]\n[PLZ Ort]\nDeutschland',
      'E-Mail: $legalContactEmail',
    ]),
    LegalSection('Verantwortlich für den Inhalt', [
      '[Name], Anschrift wie oben.',
    ]),
    LegalSection('Was Verspätomat ist', [
      'Verspätomat ist eine Ausfüll- und Weiterleitungshilfe für Fahrgastrechte. Die App hilft dir, deine Zugverspätungen festzuhalten, füllt das EU-Antragsformular mit deinen Angaben aus und schickt es von deiner persönlichen Verspätomat-Adresse an die Fahrgastrechte-Stelle des Eisenbahnunternehmens. Die Entschädigung überweist das Unternehmen direkt an den Verein, den du gewählt hast.',
      'Verspätomat nimmt kein Geld entgegen, verwaltet keine Spenden und tritt gegenüber der Bahn nicht als dein Vertreter auf. Siehe „Wie wir Anträge weiterleiten“.',
    ]),
    LegalSection('Keine Rechtsberatung', [
      'Die App erklärt die gesetzlichen Regeln zu Fahrgastrechten allgemein und rechnet nach den veröffentlichten Sätzen. Sie prüft deinen Einzelfall nicht und ersetzt keine Rechtsberatung. Ob ein Anspruch besteht, entscheidet das Eisenbahnunternehmen und im Streitfall die Schlichtungsstelle oder ein Gericht.',
    ]),
    LegalSection('Streitschlichtung', [
      'Die Europäische Kommission stellt eine Plattform zur Online-Streitbeilegung bereit: https://ec.europa.eu/consumers/odr. Wir sind nicht verpflichtet und nicht bereit, an Streitbeilegungsverfahren vor einer Verbraucherschlichtungsstelle teilzunehmen.',
      'Für Streit über deinen Fahrgastrechte-Anspruch selbst ist die Schlichtungsstelle für den öffentlichen Personenverkehr (söp) zuständig. Das betrifft dich und das Eisenbahnunternehmen, nicht Verspätomat.',
    ]),
    LegalSection('Fahrplan- und Verspätungsdaten', [
      'Abfahrten, Fahrtverläufe und Verspätungen stammen aus öffentlichen Verkehrsdaten (Transitous, auf Basis der offenen Fahrplandaten der Verkehrsverbünde und der DELFI-Daten). Wir übernehmen keine Gewähr für ihre Richtigkeit. Auf dem Antrag steht, welche Werte wir wann gesehen haben.',
    ]),
  ],
);

const datenschutz = LegalDoc(
  id: 'datenschutz',
  eyebrow: 'Rechtliches',
  title: 'Datenschutz',
  lead: 'Was wir speichern, warum, wie lange, und was du jederzeit selbst löschen kannst. Kurz: kein Konto, kein Tracking, keine Werbung, kein Standort während der Fahrt.',
  stand: 'Stand: 10. September 2026',
  sections: [
    LegalSection('Verantwortlicher', [
      '[Name], [Straße Nr], [PLZ Ort]. E-Mail: $legalContactEmail. Siehe Impressum.',
    ]),
    LegalSection('Kein Konto, aber ein Gerät', [
      'Verspätomat hat kein Benutzerkonto. Beim ersten Start erzeugt die App eine zufällige Gerätekennung und einen Zugangsschlüssel. Der Schlüssel bleibt im Schlüsselbund deines Telefons; bei uns liegt nur ein Prüfwert. Alles, was wir über dich speichern, hängt an dieser Kennung, nicht an deinem Namen.',
      'Der Wiederherstellungscode (Einstellungen → Konto) ist der einzige Weg, dein Konto auf ein anderes Gerät zu holen. Wir können ihn nicht wiederherstellen.',
      'Rechtsgrundlage: Art. 6 Abs. 1 lit. b DSGVO (Nutzung der App).',
    ]),
    LegalSection('Was wir speichern', [
      'Beim Fahren: den Bahnhof, an dem du eingecheckt hast, den Zug, den Ausstieg, die Zeiten laut Fahrplan und Live-Daten, die daraus berechneten Geduldspunkte und Abzeichen. Optional einen Anzeigenamen, den du selbst wählst.',
      'Beim ersten Antrag, nicht früher: Name, Anschrift, deine private E-Mail-Adresse und bei Zeitkarten die Ticketnummer. Sie stehen auf dem Antragsformular, weil das Eisenbahnunternehmen sie verlangt.',
      'Pro Antrag: das Bild deines Tickets für die betroffenen Monate und deine Unterschrift (getippt oder gezeichnet). Beides landet nur im PDF und in der Mail an das Unternehmen.',
      'Der Schriftverkehr über deine Verspätomat-Adresse: die Anträge, die du abschickst, und die Antworten des Unternehmens. Dazu unten mehr.',
      'Einstellungen wie Ticketart, gewählter Verein, Standortmodus, stumme Bahnhöfe.',
    ]),
    LegalSection('Standort', [
      'Dein Standort bleibt am Bahnhof. Die App fragt dein Telefon genau zweimal nach einer Position: wenn du den Bahnsteig öffnest, um Bahnhöfe in der Nähe zu zeigen, und beim Einchecken, um die Fahrt für die Ranglisten als „vor Ort“ zu bestätigen. Die erste Position wird nicht gespeichert; die zweite liegt nur an dieser einen Fahrt.',
      'Während der Fahrt folgen wir dem Zug in den Fahrplandaten, nicht deinem Telefon. Es gibt keine Standortverläufe. Ohne Standortfreigabe funktioniert die App vollständig; du wählst den Bahnhof dann selbst.',
      'Hinweis am Bahnhof im Hintergrund (Standard, abschaltbar): Mit der Freigabe „Immer“ merkt sich dein Telefon bis zu 19 Bahnhöfe als Zonen: die Bahnhöfe, an denen du in den letzten 30 Tagen eingecheckt hast, dein Stammbahnhof und die drei nächsten in deiner Umgebung, dazu einen Kreis von 8 km um deinen aktuellen Aufenthaltsort. Das Betriebssystem weckt die App nur, wenn du eine dieser Zonen betrittst oder verlässt. Beim Betreten eines Bahnhofs prüft die App für höchstens 90 Sekunden, ob du dort stehst, und zeigt dann eine Mitteilung. Beim Verlassen des Kreises fragt die App einmal nach Bahnhöfen in der Nähe, dieselbe Anfrage wie beim Öffnen des Bahnsteigs. Sonst verlässt nichts das Telefon: keine Position wird gespeichert oder übertragen, weder bei uns noch bei Dritten. Abschalten: Einstellungen → „Hinweis am Bahnhof“ oder Standortmodus „Nur wenn die App offen ist“; in den Systemeinstellungen die Freigabe „Immer“ entziehen.',
      'Rechtsgrundlage: deine Einwilligung über die Standortfreigabe des Betriebssystems (Art. 6 Abs. 1 lit. a DSGVO), jederzeit in den Systemeinstellungen widerrufbar.',
    ]),
    LegalSection('Deine Verspätomat-Adresse', [
      'Für Anträge bekommst du eine persönliche E-Mail-Adresse auf unserer Domain, zum Beispiel fahrgast-a1b2c3d4@users.verspaetomat.de. Von ihr gehen deine Anträge an das Eisenbahnunternehmen, in Kopie an dein privates Postfach. Antworten des Unternehmens kommen dort an, werden sofort und unverändert an dein privates Postfach weitergeleitet und in der App unter „Antwort“ angezeigt.',
      'Wir behandeln dieses Postfach als deins. Das Fernmeldegeheimnis (§ 3 TDDDG) gilt. Eine Software liest jede eingehende Mail nur, um drei Dinge zu erkennen: ob der Antrag angenommen, abgelehnt oder mit einer Rückfrage versehen wurde, den genannten Betrag und ein Aktenzeichen. Mehr wird nicht ausgewertet, nichts wird zu anderen Zwecken verwendet, niemand liest mit. Antworten auf Rückfragen schreibst du selbst in der App; wir schicken nichts, was du nicht abgeschickt hast.',
      'Rechtsgrundlage: Art. 6 Abs. 1 lit. b DSGVO; für die Adresse und die Auswertung deine Einwilligung beim ersten Antrag (Art. 6 Abs. 1 lit. a DSGVO).',
    ]),
    LegalSection('Wer was bekommt', [
      'Das Eisenbahnunternehmen, genauer seine Fahrgastrechte-Stelle, bekommt das ausgefüllte Formular mit deinen Angaben, Ticketbild und Unterschrift, weil du es dorthin schickst. Was es damit tut, regelt seine eigene Datenschutzerklärung.',
      'Der Verein, den du als Zweck gewählt hast, bekommt Geld vom Eisenbahnunternehmen, nicht von uns. Er erfährt von uns nicht, wer du bist. Zur Abstimmung der Eingänge bekommen wir vom Verein eine Aufstellung der Überweisungen (Betrag, Datum, Verwendungszweck), die wir mit den Anträgen abgleichen.',
      'Wir selbst geben deine Daten an niemanden weiter und verkaufen nichts.',
    ]),
    LegalSection('Dienstleister', [
      'Fahrplan- und Verspätungsdaten: Transitous (transitous.org), ein offener Dienst auf Basis öffentlicher Fahrplandaten. Er bekommt die Bahnhofs- und Zugabfragen unseres Servers, keine Kennung von dir.',
      'E-Mail: ein Versand- und Empfangsdienstleister für unsere Domain, der deine Anträge zustellt und Antworten an uns übergibt. [Dienstleister und Sitz werden vor dem Start eingetragen.]',
      'Mitteilungen: Apple (APNs) und Google (Firebase Cloud Messaging) stellen Push-Nachrichten zu, wenn du Mitteilungen erlaubst. Sie sehen einen Zustellschlüssel und den Text der Mitteilung („Angekommen, +14“), sonst nichts.',
      'Server: der Dienst läuft auf Servern in der Europäischen Union.',
    ]),
    LegalSection('Wie lange', [
      'Fahrten, Punkte, Abzeichen und die Einträge im Konto bleiben, bis du sie löschst.',
      'Ticketbilder, Unterschrift und die Anhänge der Antworten löschen wir, sobald ein Antrag abgeschlossen ist (bestätigt, abgelehnt oder verfallen). Wenn du unter Einstellungen „Korrespondenz nach Abschluss behalten“ einschaltest, bleiben sie, bis du es ausschaltest oder alles löschst.',
      'Offene Ansprüche verfallen drei Monate nach der Fahrt; danach steht nur noch der Eintrag „verfallen“ im Konto.',
    ]),
    LegalSection('Ranglisten und Community', [
      'Die Zahlen unter „Wir“ sind Summen über alle Fahrgäste ohne Namen. In den Ranglisten erscheinst du nur mit deinem Anzeigenamen und nur, wenn „Mich in Ranglisten zeigen“ eingeschaltet ist.',
    ]),
    LegalSection('Kein Tracking, keine Werbung', [
      'Die App enthält keine Werbung, keine Analyse-SDKs und keine Tracker. Wir messen nicht, wie du die App nutzt. Der Server schreibt technische Protokolle (Zeitpunkt, Route, Fehler) und löscht sie nach 14 Tagen.',
    ]),
    LegalSection('Deine Rechte', [
      'Auskunft und Übertragbarkeit: Einstellungen → Deine Daten → „Daten exportieren“ gibt dir alles, was wir über dich haben, als Datei.',
      'Löschung: Einstellungen → Deine Daten → „Alles löschen“ entfernt Konto, Fahrten, Anträge, Anhänge und deine Verspätomat-Adresse sofort und endgültig. Ein bereits abgeschickter Antrag liegt beim Eisenbahnunternehmen weiter; seine Antwort sehen wir dann nicht mehr.',
      'Berichtigung: Name, Anschrift, Postfach und Ticketnummer änderst du unter Einstellungen → Anträge. Deinen Anzeigenamen unter Einstellungen → Konto.',
      'Widerspruch, Beschwerde: schreib an $legalContactEmail. Du kannst dich außerdem bei einer Datenschutzaufsichtsbehörde beschweren, zum Beispiel der für [Bundesland] zuständigen.',
    ]),
  ],
);

const bote = LegalDoc(
  id: 'bote',
  eyebrow: 'Rechtliches',
  title: 'Wie wir Anträge weiterleiten',
  lead: 'Verspätomat ist ein Bote, kein Vertreter. Das ist kein Kleingedrucktes, sondern der Kern der App.',
  sections: [
    LegalSection('Der Antrag ist deiner', [
      'Das Formular, das die App ausfüllt, ist deine eigene Erklärung gegenüber dem Eisenbahnunternehmen. Du prüfst die Fälle, du wählst den Verein, du unterschreibst, du drückst auf „Abschicken“. Wir tragen nur ein, was du uns gegeben hast und was der Fahrplan zeigt.',
    ]),
    LegalSection('Wir überbringen, wir handeln nicht', [
      'Der Antrag geht von deiner persönlichen Verspätomat-Adresse raus, mit deinem Namen als Absender, und du bekommst jede Mail in Kopie. Wir sind dabei wie die Post: Wir befördern deine Erklärung unverändert an die richtige Stelle.',
      'Wir schreiben dem Unternehmen nie von uns aus. Keine Erinnerungen, keine Nachfragen, keine Widersprüche, keine Mahnungen. Wenn eine Antwort ausbleibt, sagen wir dir Bescheid; was dann passiert, entscheidest du.',
    ]),
    LegalSection('Wir vertreten dich nicht', [
      'Wir prüfen deinen Fall nicht, wir beraten nicht, wir streiten nicht. Wir treten gegenüber dem Unternehmen nicht als dein Bevollmächtigter auf und kaufen dir deinen Anspruch nicht ab. Eine Ablehnung ist eine Ablehnung an dich; ob du sie hinnimmst, bei der Schlichtungsstelle söp einreichst oder anders vorgehst, ist deine Sache. Die App hilft dir nur, nichts zu verpassen.',
    ]),
    LegalSection('Jede Antwort ganz', [
      'Alles, was an deine Verspätomat-Adresse kommt, leiten wir vollständig und unverändert an dein privates Postfach weiter. In der App zeigen wir dieselbe Mail. Eine Software erkennt darin nur Ergebnis, Betrag und Aktenzeichen, damit dein Konto stimmt.',
      'Antworten auf Rückfragen schreibst du selbst, in der App oder aus deinem Postfach. Wir bieten Textvorschläge an, abgeschickt wird nur, was du abschickst.',
    ]),
    LegalSection('Das Geld geht an den Verein, nie an uns', [
      'Auf dem Formular steht das Konto des Vereins, den du gewählt hast. Das Eisenbahnunternehmen überweist dorthin. Wir haben kein Konto dafür, wir nehmen nichts entgegen, wir leiten nichts weiter. Der Verein bestätigt uns die Eingänge, damit die Zahlen in der App stimmen.',
    ]),
    LegalSection('Warum das so ist', [
      'Wer für andere Ansprüche durchsetzt, braucht in Deutschland eine Zulassung als Rechtsdienstleister. Wer Geld weiterleitet, eine als Zahlungsdienstleister. Beides wollen wir nicht sein, und beides musst du nicht wollen: Dein Anspruch ist klar geregelt, das Formular ist amtlich, und die Bahn zahlt.',
    ]),
  ],
);

const legalDocs = [impressum, datenschutz, bote];

LegalDoc legalDocById(String id) => legalDocs.firstWhere((d) => d.id == id, orElse: () => impressum);
