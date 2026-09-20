/// The legal texts shown in the app: Impressum, Datenschutzerklärung and the
/// messenger clause ("Bote, nicht Vertreter"). Plain data, no widgets, so the
/// wording can be edited without touching a screen. Sources: docs/05-legal.md,
/// docs/03-claim-filing.md, docs/14-location-concept.md.
///
/// The operator's own details are below and in `legalCompany…`; the website
/// renders these same texts (docs/31 §4) and `cargo run -p verspaetomat-site
/// -- --strict` refuses to publish while a `[Platzhalter]` is left anywhere in
/// here. Nothing in here is invented.
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

/// The one address, for everything: the Impressum, data requests, deletion, complaints, a
/// question about a claim. It appears in all three legal texts, in the store listings (docs/40)
/// and in the website's footer, and it is answered by a person. There is deliberately no second
/// one — a private address next to the company's only made people guess which one was meant.
const legalEmail = 'info@zoom7.de';

/// The operator, as in the commercial register.
const legalCompany = 'Zoom7 GmbH';
const legalAddress = 'Pfarrer-Eggart-Str. 5\n88085 Langenargen';
const legalPhone = '+49 751 18 527 44-0';

const impressum = LegalDoc(
  id: 'impressum',
  eyebrow: 'Rechtliches',
  title: 'Impressum',
  lead: 'Angaben nach § 5 DDG.',
  sections: [
    LegalSection('Anbieter', [
      '$legalCompany\n$legalAddress\nDeutschland',
    ]),
    LegalSection('Vertreten durch', [
      'Johannes Fritsch',
    ]),
    LegalSection('Kontakt', [
      'Telefon: $legalPhone\nE-Mail: $legalEmail',
      'Dieselbe Adresse für alles, was die App betrifft — Auskunft, Löschung, Rückfragen zu einem Antrag.',
    ]),
    LegalSection('Registereintrag', [
      'Registergericht: Amtsgericht Ulm\nRegisternummer: HRB 728616',
    ]),
    LegalSection('Umsatzsteuer-Identifikationsnummer', [
      'Nach § 27a Umsatzsteuergesetz: DE286789402',
    ]),
    LegalSection('Verantwortlich für den Inhalt', [
      'Johannes Fritsch, Anschrift wie oben.',
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
  lead: 'Was wir speichern, warum, wie lange, und was du jederzeit selbst löschen kannst. Kurz: kein Konto, kein Tracking, keine Werbung. Wo du bist, erfahren wir beim Einchecken — und solange der Hinweis am Bahnhof eingeschaltet ist, auch dann, wenn dein Telefon im Hintergrund neu sortiert, welche Bahnhöfe es beobachtet.',
  stand: 'Stand: 21. September 2026',
  sections: [
    LegalSection('Verantwortlicher', [
      '$legalCompany\n$legalAddress\nE-Mail: $legalEmail. Siehe Impressum.',
    ]),
    LegalSection('Kein Konto, aber ein Gerät', [
      'Verspätomat hat kein Benutzerkonto. Beim ersten Start erzeugt die App eine zufällige Gerätekennung und einen Zugangsschlüssel. Der Schlüssel bleibt im Schlüsselbund deines Telefons; bei uns liegt nur ein Prüfwert. Alles, was wir über dich speichern, hängt an dieser Kennung, nicht an deinem Namen.',
      'Der Wiederherstellungscode (Einstellungen → Konto) ist der einzige Weg, dein Konto auf ein anderes Gerät zu holen. Wir können ihn nicht wiederherstellen.',
      'Rechtsgrundlage: Art. 6 Abs. 1 lit. b DSGVO (Nutzung der App).',
    ]),
    LegalSection('Was wir speichern', [
      'Beim Fahren: den Bahnhof, an dem du eingecheckt hast, die Position, mit der du das bestätigt hast, den Zug, den Ausstieg, die Zeiten laut Fahrplan und Live-Daten, die daraus berechneten Geduldspunkte und Abzeichen. Optional einen Anzeigenamen, den du selbst wählst.',
      'Beim ersten Antrag, nicht früher: Name, Anschrift, deine private E-Mail-Adresse und bei Zeitkarten die Ticketnummer. Name, Anschrift und Ticketnummer stehen auf dem Antragsformular, weil das Eisenbahnunternehmen sie verlangt. Deine private E-Mail-Adresse steht nicht darauf: Im Formular steht die Verspätomat-Adresse dieses Antrags, damit die Antwort dorthin geht. Deine eigene Adresse benutzen wir nur, um dir jede Mail in Kopie zu schicken.',
      'Pro Antrag: das Bild deines Tickets für die betroffenen Monate und deine Unterschrift (getippt oder gezeichnet). Beides landet nur im PDF und in der Mail an das Unternehmen.',
      'Der Schriftverkehr über deine Verspätomat-Adresse: die Anträge, die du abschickst, und die Antworten des Unternehmens. Dazu unten mehr.',
      'Einstellungen wie Ticketart, gewählter Verein, Standortmodus, stumme Bahnhöfe.',
    ]),
    LegalSection('Standort', [
      'Solange die App offen ist und du nicht gerade auf einer Fahrt bist, lässt sie sich von deinem Telefon melden, wenn du dich um mehr als 500 Meter bewegt hast — grob, nicht metergenau. Nach einer frischen Position fragt sie beim Start, bei der Rückkehr in den Vordergrund und immer dann, wenn sich für sie etwas geändert hat. Welche Bahnhöfe in der Nähe liegen und was hinter einem Namen im Suchfeld steckt, beantwortet die App auf dem Telefon, aus einem Bahnhofsverzeichnis, das sie selbst dabeihat; diese Positionen schickt sie uns nicht. Was die Hintergrund-Schicht tut, steht weiter unten.',
      'Dieses Verzeichnis ist in der App schon eingebaut; etwa einmal pro Woche sieht sie auf verspaetomat.de nach, ob es eine neuere Fassung gibt. Dabei geht keine Kennung, kein Schlüssel und keine Position mit — unser Webserver sieht dabei deine IP-Adresse, wie bei jedem Aufruf einer Webseite.',
      'Beim Einchecken schickst du uns eine Position mit. Sie bestätigt, dass du wirklich am Abfahrtsbahnhof stehst; nur dann zählt die Fahrt in den Ranglisten. Sie hängt an dieser einen Fahrt und verschwindet mit ihr — und aus den Positionen deiner Fahrten entstehen die Zonen, um die es gleich geht.',
      'Hinweis am Bahnhof im Hintergrund (Standard, abschaltbar): Mit der Freigabe „Immer“ merkt sich dein Telefon bis zu 19 Bahnhöfe als Zonen — bis zu 15 Bahnhöfe, an denen du in den letzten 30 Tagen eingecheckt hast, dein Stammbahnhof ist immer darunter, dazu die vier nächsten in deiner Umgebung. Weiter als 50 Kilometer von all diesen Bahnhöfen entfernt zählen nur noch die nächsten um dich herum; auf Android können es dann bis zu 20 sein. Dazu kommt ein weiterer Kreis um deinen Aufenthaltsort: Auf dem iPhone reicht er bis kurz vor den nächsten Bahnhof, den dein Telefon nicht ohnehin beobachtet — mindestens ein Kilometer, auf freier Strecke bis zu 200 Kilometer; auf Android sind es immer 8 Kilometer. Das Betriebssystem weckt die App nur, wenn du eine dieser Zonen betrittst oder verlässt.',
      'Beim Betreten einer Bahnhofszone sieht die App nach, ob du wirklich dort stehst. Auf dem iPhone schaltet sie dafür bis zu sechs Minuten lang ihre eigene Ortung ein und meldet sich etwa 45 Sekunden, nachdem eine Position auf 50 Meter herangekommen ist; kommt keine so nah, geht die Ortung ohne Hinweis wieder aus. Auf Android nimmt sie nach drei Minuten in der Zone eine einzelne Position und meldet sich, wenn die höchstens 300 Meter entfernt ist oder gar nicht erst zustande kommt. Diese Positionen verlassen das Telefon nicht.',
      'Was das Telefon im Hintergrund doch verlässt, ist die Frage „welche Bahnhöfe sind hier?“ — mit deiner Position und deiner Gerätekennung, an unseren Server. Sie geht raus, wenn du den großen Kreis verlässt, wenn das Betriebssystem einen größeren Ortswechsel meldet, und wenn die App ihre Zonen neu setzt und die Bahnhofsliste, die sie dafür hält, von woanders stammt; ihre Zonen setzt sie unter anderem neu, wenn eine Fahrt beginnt oder endet. Das passiert auch während einer Fahrt: Eine offene Fahrt unterdrückt den Hinweis, nicht diese Frage. Auf einer längeren Fahrt können im Lauf einer Stunde mehrere solcher Fragen zusammenkommen.',
      'Während der Fahrt folgen wir dem Zug in den Fahrplandaten, nicht deinem Telefon.',
      'Bei Dritten landet davon nichts: Seit das Bahnhofsverzeichnis bei uns liegt, bekommt kein anderer Dienst deine Koordinaten zu sehen. Bei uns landet eine Position an den beiden genannten Stellen — beim Einchecken, wo sie an der Fahrt bleibt, und bei der Frage aus dem Hintergrund, die wir beantworten und nicht speichern. Standortverläufe führen wir nicht. Was unser Server beim Beantworten protokolliert, steht unten unter „Kein Tracking, keine Werbung“.',
      'Ohne Standortfreigabe funktioniert die App vollständig; du wählst den Bahnhof dann selbst. Abschalten: Einstellungen → „Hinweis am Bahnhof“ oder Standortmodus „Nur wenn die App offen ist“; in den Systemeinstellungen die Freigabe „Immer“ entziehen.',
      'Rechtsgrundlage: deine Einwilligung über die Standortfreigabe des Betriebssystems (Art. 6 Abs. 1 lit. a DSGVO), jederzeit in den Systemeinstellungen widerrufbar.',
    ]),
    LegalSection('Deine Verspätomat-Adresse', [
      'Für Anträge bekommst du eine persönliche E-Mail-Adresse auf unserer Domain, zum Beispiel fahrgast-a1b2c3d4@users.verspaetomat.de. Jeder einzelne Antrag bekommt zusätzlich eine eigene Adresse, zum Beispiel antrag-9c31af02@users.verspaetomat.de: von ihr geht dieser Antrag an das Eisenbahnunternehmen, in Kopie an dein privates Postfach, und sie steht auch als Kontaktadresse im Formular. Antworten des Unternehmens kommen dort an, werden sofort und unverändert an dein privates Postfach weitergeleitet und in der App unter „Antwort“ angezeigt.',
      'Wir behandeln dieses Postfach als deins. Das Fernmeldegeheimnis (§ 3 TDDDG) gilt. Eine Software liest jede eingehende Mail nur, um drei Dinge zu erkennen: welche Fahrten das Unternehmen bezahlt oder ablehnt, den Betrag, den es dafür nennt, und ob es eine Rückfrage stellt. Dafür lesen Sprachmodelle von OpenAI den Text der Antwort; bezahlt oder abgelehnt ist eine Fahrt nur, wenn zwei von ihnen dasselbe lesen. Vorher entfernen wir deinen Namen, deine Anschrift, E-Mail-Adressen, Ticketnummer, IBAN und Telefonnummern, soweit eine Software sie erkennen kann, und den zitierten Verlauf (siehe Dienstleister). Mehr wird nicht ausgewertet, nichts wird zu anderen Zwecken verwendet, niemand bei uns liest mit. Antworten auf Rückfragen schreibst du selbst in der App; wir schicken nichts, was du nicht abgeschickt hast.',
      'Rechtsgrundlage: Art. 6 Abs. 1 lit. b DSGVO; für die Adresse und die Auswertung deine Einwilligung beim ersten Antrag (Art. 6 Abs. 1 lit. a DSGVO).',
    ]),
    LegalSection('Wer was bekommt', [
      'Das Eisenbahnunternehmen, genauer seine Fahrgastrechte-Stelle, bekommt das ausgefüllte Formular mit deinen Angaben, Ticketbild und Unterschrift, weil du es dorthin schickst. Was es damit tut, regelt seine eigene Datenschutzerklärung.',
      'Der Verein, den du als Zweck gewählt hast, bekommt Geld vom Eisenbahnunternehmen, nicht von uns. Er erfährt von uns nicht, wer du bist, und schickt uns nichts. Ob Geld fließt, entnehmen wir allein der Antwort des Eisenbahnunternehmens.',
      'Wir selbst geben deine Daten an niemanden weiter und verkaufen nichts.',
    ]),
    LegalSection('Dienstleister', [
      'Fahrplan- und Verspätungsdaten: Transitous (transitous.org), ein offener Dienst auf Basis öffentlicher Fahrplandaten. Er bekommt die Zugabfragen unseres Servers, keine Kennung von dir und keine Position. Das Verzeichnis der Bahnhöfe liegt bei uns: Wir übernehmen es aus den Fahrplandaten von DELFI e.V. und des VBB (Lizenz CC BY 4.0, bezogen über Transitous) und halten es selbst vor. Die App hat dieses Verzeichnis dabei und beantwortet „Bahnhöfe in der Nähe“ und die Bahnhofssuche damit auf dem Telefon; nur die Frage aus dem Hintergrund geht noch an unseren Server. Außerhalb unseres Servers erfährt niemand, wo du bist.',
      'E-Mail: Postmark, ein Dienst der ActiveCampaign, LLC, Chicago, USA, stellt deine Anträge zu und übergibt Antworten an uns. Damit verlassen diese Mails die EU; Grundlage sind ein Auftragsverarbeitungsvertrag und die Standardvertragsklauseln der EU-Kommission.',
      'Antworten lesen: OpenAI, San Francisco, USA. Sprachmodelle lesen eingehende Antworten der Eisenbahnunternehmen, um zu erkennen, ob und wie viel sie zahlen. Sie bekommen den Text ohne zitierten Verlauf und, soweit eine Software sie erkennen kann, ohne Namen, Anschrift, E-Mail-Adressen, Ticketnummer, IBAN und Telefonnummern, dazu Datum, Zug, Strecke und Verspätung der beantragten Fahrten. OpenAI verwendet diese Daten nicht zum Training und bewahrt sie höchstens 30 Tage zur Missbrauchserkennung auf. Grundlage sind ein Auftragsverarbeitungsvertrag und die Standardvertragsklauseln der EU-Kommission.',
      'Mitteilungen: Apple (APNs) und Google (Firebase Cloud Messaging) stellen Push-Nachrichten zu, wenn du Mitteilungen erlaubst. Sie sehen einen Zustellschlüssel und den Text der Mitteilung („Angekommen, +14“), sonst nichts.',
      'Server: Hetzner Online GmbH, Gunzenhausen. Der Dienst läuft auf Servern in der Europäischen Union.',
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
      'Die App enthält keine Werbung, keine Analyse-SDKs und keine Tracker. Wir messen nicht, wie du die App nutzt. Unser Server schreibt technische Protokolle: Zeitpunkt, angefragte Adresse, Fehler — bei der Bahnhofsfrage aus dem Hintergrund steht in dieser Adresse auch die Position, nach der gefragt wurde. Wir werten diese Protokolle nicht aus und geben sie nicht weiter; sie liegen auf unserem Server in der Europäischen Union.',
    ]),
    LegalSection('Deine Rechte', [
      'Auskunft und Übertragbarkeit: Einstellungen → Deine Daten → „Daten exportieren“ gibt dir alles, was wir über dich haben, als Datei.',
      'Löschung: Einstellungen → Deine Daten → „Alles löschen“ entfernt Konto, Fahrten, Anträge, Anhänge und deine Verspätomat-Adresse sofort und endgültig. Ein bereits abgeschickter Antrag liegt beim Eisenbahnunternehmen weiter; seine Antwort sehen wir dann nicht mehr.',
      'Berichtigung: Name, Anschrift, Postfach und Ticketnummer änderst du unter Einstellungen → Anträge. Deinen Anzeigenamen unter Einstellungen → Konto.',
      'Widerspruch, Beschwerde: schreib an $legalEmail. Du kannst dich außerdem bei einer Datenschutzaufsichtsbehörde beschweren, für uns ist das der Landesbeauftragte für den Datenschutz und die Informationsfreiheit Baden-Württemberg.',
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
      'Alles, was an deine Verspätomat-Adresse kommt, leiten wir vollständig und unverändert an dein privates Postfach weiter. In der App zeigen wir dieselbe Mail. Eine Software erkennt darin nur, welche Fahrten bezahlt oder abgelehnt sind, den genannten Betrag und ob eine Rückfrage kommt, damit dein Konto stimmt. Ist sie sich nicht sicher, zählt nichts, bis die Antwort eindeutig ist.',
      'Antworten auf Rückfragen schreibst du selbst, in der App oder aus deinem Postfach. Wir bieten Textvorschläge an, abgeschickt wird nur, was du abschickst.',
    ]),
    LegalSection('Das Geld geht an den Verein, nie an uns', [
      'Auf dem Formular steht das Konto des Vereins, den du gewählt hast. Das Eisenbahnunternehmen überweist dorthin. Wir haben kein Konto dafür, wir nehmen nichts entgegen, wir leiten nichts weiter. Als bestätigt zählt ein Betrag, sobald das Unternehmen schreibt, dass es ihn zahlt; der Verein muss uns nichts melden.',
    ]),
    LegalSection('Warum das so ist', [
      'Wer für andere Ansprüche durchsetzt, braucht in Deutschland eine Zulassung als Rechtsdienstleister. Wer Geld weiterleitet, eine als Zahlungsdienstleister. Beides wollen wir nicht sein, und beides musst du nicht wollen: Dein Anspruch ist klar geregelt, das Formular ist amtlich, und die Bahn zahlt.',
    ]),
  ],
);

const legalDocs = [impressum, datenschutz, bote];

LegalDoc legalDocById(String id) => legalDocs.firstWhere((d) => d.id == id, orElse: () => impressum);

/// The version shown in Einstellungen on a release build (docs/22 §3). `tools/release.sh`
/// passes the real `1.0.0 (13)`; a plain `flutter run` falls back to the pubspec's version.
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
