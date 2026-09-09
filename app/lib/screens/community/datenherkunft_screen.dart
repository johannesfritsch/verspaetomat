import 'package:flutter/material.dart';

import '../../repo/repo_scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';

class _Row {
  const _Row(this.what, this.origin, {this.fresh, this.missing});
  final String what;
  final String origin;
  final String? fresh;
  final String? missing;
}

const _rows = <_Row>[
  _Row('„Du bist am Hauptbahnhof“', 'Dein Telefon hat gemerkt, dass du seit ein paar Minuten in der Nähe eines Bahnhofs bist. Nichts verlässt das Telefon, bis du eincheckst.', fresh: 'Innerhalb von 3 bis 5 Minuten', missing: 'Nichts passiert. Öffne die App und wähle den Bahnhof selbst.'),
  _Row('Abfahrten, Gleise, Verspätungen am Bahnhof', 'Dieselben öffentlichen Fahrplan- und Live-Daten, die auch die Anzeigetafel am Gleis speisen, über offene Verkehrsdatendienste.', fresh: 'Alle paar Sekunden, solange die Liste offen ist', missing: '„Keine Live-Daten für diese Station“ und ein Feld, um den Zug selbst einzutragen.'),
  _Row('Welches Unternehmen deinen Zug fährt', 'Der Fahrplan selbst nennt den Betreiber.', fresh: 'Mit dem Fahrplan', missing: 'Beim Antrag wählst du den Betreiber aus einer kurzen Liste.'),
  _Row('Position, nächster Halt, aktuelle Verspätung während der Fahrt', 'Die Live-Daten für genau diesen einen Zug, die unser Server verfolgt, während du fährst. Dein Standort wird dafür nicht benutzt.', fresh: 'Alle 30 bis 60 Sekunden, mit „Stand 08:41“', missing: 'Der Fahrt-Screen zeigt den letzten Stand und sein Alter. Bei Ankunft kannst du die Zeit selbst eintragen; solche Fahrten sind auf dem Antrag als „selbst eingetragen“ markiert.'),
  _Row('Verspätung an deinem Ausstieg (die Zahl, die zählt)', 'Geplante Ankunft aus dem Fahrplan, tatsächliche Ankunft aus den Live-Daten, an dem Halt, den du gewählt hast.', fresh: 'Endgültig ein paar Minuten nach Ankunft'),
  _Row('Ursache („Stellwerksstörung“)', 'Die Störungsmeldung des Betreibers, wenn er eine veröffentlicht.', fresh: 'Mit der Verspätung', missing: 'Kein Abzeichen, sonst ändert sich nichts.'),
  _Row('Geduldspunkte', 'Von der App aus der endgültigen Verspätung gezählt.', fresh: 'Sofort bei Ankunft'),
  _Row('„Anspruch: 1,50 €“', 'Die gesetzlichen Regeln für deinen Tickettyp, angewendet auf die endgültige Verspätung. Die Regeln stehen in der App und verlinken auf die offizielle DB-Seite.', fresh: 'Sofort bei Ankunft'),
  _Row('Kontostatus: gesammelt, bereit, eingereicht, bestätigt, verfallen', 'gesammelt und bereit: von der App berechnet. eingereicht: dein Antrag hat deine Verspätomat-Adresse verlassen. bestätigt oder abgelehnt: die E-Mail-Antwort der Bahn an diese Adresse, gelesen nach Betrag und Ergebnis, oder dein Foto einer Postantwort, oder die Meldung des Vereins. verfallen: die Frist ist vorbei.', fresh: 'Antworten: sofort bei Eingang', missing: 'Eine Antwort, die wir nicht lesen können, zeigen wir dir, damit du das Ergebnis einträgst.'),
  _Row('„Älteste Verspätung verfällt in 3 Wochen“', 'Drei Monate nach dem Fahrtdatum, die gesetzliche Frist.', fresh: 'Täglich'),
  _Row('Name, Anschrift, Ticketnummer auf dem Antrag', 'Von dir eingetippt, beim ersten Antrag. Gespeichert auf deinem Telefon.', missing: 'Wird beim Antrag abgefragt.'),
  _Row('Ticket-Screenshot auf dem Antrag', 'Von dir angehängt, aus deiner Ticket-App oder den Fotos. Verschlüsselt aufbewahrt, nur solange der Antrag offen ist, falls die Bahn nachfragt.', missing: 'Ohne Screenshot geht kein Antrag raus.'),
  _Row('Deine Verspätomat-Adresse', 'Von uns angelegt, bei deinem ersten Antrag. Dein Name ist der Absendername. Jede Mail raus bekommt eine Kopie in dein privates Postfach; jede Mail rein wird komplett dorthin weitergeleitet.'),
  _Row('Name und Konto des Vereins auf dem Antrag', 'Vom Verein schriftlich an uns gegeben. Auf der Vereinsseite vollständig sichtbar.', fresh: 'Wenn der Verein uns etwas Neues sagt'),
  _Row('Das Antragsformular selbst', 'Das offizielle EU-Fahrgastrechteformular, oder das DB-Formular für den Postweg, von der App ausgefüllt.', fresh: 'Formularversion steht auf der Vorschau'),
  _Row('Wohin der Antrag geht', 'Unser Betreiberverzeichnis: das gemeinsame Servicecenter für rund 40 Bahnen, eine eigene Adresse für die übrigen.', fresh: 'Monatlich geprüft', missing: 'Die App zeigt die Fahrgastrechte-Seite des Betreibers und lässt dich die Adresse eintragen.'),
  _Row('Die Antwort der Bahn in der App', 'Die echte E-Mail, die die Bahn an deine Verspätomat-Adresse geschickt hat. Wir lesen Status, Betrag und Aktenzeichen. Wir antworten nie selbst.', fresh: 'Sobald sie eintrifft', missing: 'Antworten per Post: fotografieren.'),
  _Row('Community: Minuten', 'Summe aller endgültigen Verspätungen aller Fahrgäste.', fresh: 'Live'),
  _Row('Community: Euro „eingereicht“ und „bestätigt“', 'Summe der Kontostatus aller Fahrgäste.', fresh: 'Live für eingereicht, monatlich für bestätigt'),
  _Row('Bestätigt pro Verein', 'Summe aller bestätigten Anträge, die diesen Verein als Empfänger nennen.', fresh: 'Live; Vereinsmeldungen monatlich'),
  _Row('Check-ins aus Träwelling', 'Wenn du Träwelling verbunden hast, erscheinen die Fahrten, die du dort eingecheckt hast, hier als Fahrten.', fresh: 'Innerhalb einer Minute', missing: 'Ohne Verbindung ändert sich nichts.'),
  _Row('Ranglisten', 'Nur verifizierte Fahrten (ein Standort-Fix am Bahnhof beim Check-in).', fresh: 'Live, sieben Tage', missing: 'Unverifizierte Fahrten bringen Punkte, aber keinen Platz.'),
  _Row('Abzeichen', 'Von der App aus den Fahrtdaten vergeben, bei Ursachen aus der Störungsmeldung des Betreibers.', fresh: 'Bei Ankunft'),
];

/// Every number on screen and where it comes from.
class DatenherkunftScreen extends StatelessWidget {
  const DatenherkunftScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return VScreen(
      title: 'Woher kommen die Daten?',
      eyebrow: 'JEDE ZAHL UND IHRE QUELLE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.m(),
          Text('Tippe in der App auf eine Zahl, und sie beantwortet „Woher weißt du das?“. Das hier ist die ganze Liste.', style: VText.body.copyWith(color: VColors.ink2)),
          const VGap.l(),
          _rowWidget(_Row('Backend', 'Woher die App gerade ihre Daten holt: ${RepoScope.of(context).mode.label}.', fresh: RepoScope.of(context).isLocal ? 'Lokaler Server unter ${RepoScope.of(context).apiUrl}' : 'Eingebaute Vorführdaten, kein Netz', missing: 'Umschalten unter Einstellungen → Backend.')),
          for (final r in _rows) _rowWidget(r),
          const VGap.xl(),
          const VRule.red(),
          const VGap.m(),
          Text('DREI VERSPRECHEN', style: VText.eyebrow),
          const VGap.m(),
          _promise('1', 'Dein Standort bleibt am Bahnhof.', 'Wir schauen nur, ob du an einem Bahnhof stehst. Während der Fahrt folgen wir dem Zug, nicht dir.'),
          _promise('2', 'Kein Geld läuft durch uns.', 'Die Bahn zahlt an den Verein. Wir füllen Formulare aus und tragen die Post; du unterschreibst und schickst ab, und du bekommst von allem eine Kopie.'),
          _promise('3', 'Kein Euro gilt als gespendet, bevor er es ist.', 'Eingereicht und bestätigt stehen getrennt, und bestätigt heißt nur: Eine Antwort der Bahn oder eine Meldung des Vereins liegt vor.'),
        ],
      ),
    );
  }

  Widget _rowWidget(_Row r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.what, style: VText.bodyStrong),
              const SizedBox(height: 6),
              Text(r.origin, style: VText.bodyS),
              if (r.fresh != null) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 92, child: Text('Aktualität', style: VText.caption)),
                    Expanded(child: Text(r.fresh!, style: VText.captionInk)),
                  ],
                ),
              ],
              if (r.missing != null) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 92, child: Text('Wenn es fehlt', style: VText.caption)),
                    Expanded(child: Text(r.missing!, style: VText.captionInk)),
                  ],
                ),
              ],
            ],
          ),
        ),
        const VRule(),
      ],
    );
  }

  Widget _promise(String n, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(n, style: VText.numberM.copyWith(color: VColors.red)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: VText.bodyStrong),
                const SizedBox(height: 4),
                Text(body, style: VText.bodyS.copyWith(color: VColors.ink2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
