import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart';
import '../../router.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'claims_widgets.dart';

/// Antrag: the five-step claim flow. Prüfen · Ticket · Zweck · Unterschrift · Senden.
class AntragScreen extends StatefulWidget {
  const AntragScreen({super.key, required this.desk});
  final String desk;

  @override
  State<AntragScreen> createState() => _AntragScreenState();
}

class _AntragScreenState extends State<AntragScreen> {
  int _step = 0;
  bool _sent = false;
  bool _showPersonal = false;
  bool _otherNgo = false;
  final _unknownAddress = TextEditingController();

  static const _steps = ['Prüfen', 'Ticket', 'Zweck', 'Unterschrift', 'Senden'];

  bool get _unknownDesk => widget.desk == 'Unbekannt';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = DemoScope.read(context);
      if (s.draftDesk == null || s.draftDesk != widget.desk) {
        s.startClaim(widget.desk);
      }
      setState(() => _showPersonal = !s.personalDataEntered);
    });
  }

  @override
  void dispose() {
    _unknownAddress.dispose();
    super.dispose();
  }

  bool _canContinue(DemoState s) => switch (_step) {
        0 => s.draftIncidentIds.isNotEmpty && (!_unknownDesk || _unknownAddress.text.trim().isNotEmpty),
        1 => s.draftTicketAttached,
        2 => true,
        3 => s.draftSigned,
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final state = DemoScope.of(context);
    if (_sent) return _Sent(desk: widget.desk);

    final content = switch (_step) {
      0 => _Pruefen(
          state: state,
          desk: widget.desk,
          unknown: _unknownDesk,
          addressCtl: _unknownAddress,
          showPersonal: _showPersonal,
          onChanged: () => setState(() {}),
          onPersonalSaved: () => setState(() => _showPersonal = false),
        ),
      1 => _Ticket(state: state),
      2 => _Zweck(state: state, other: _otherNgo, onToggle: (v) => setState(() => _otherNgo = v)),
      3 => _Unterschrift(state: state),
      _ => _Senden(state: state, desk: widget.desk),
    };

    final last = _step == _steps.length - 1;
    return VScreen(
      eyebrow: 'Antrag · ${deskDisplay(widget.desk)}',
      title: _steps[_step],
      scroll: true,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (last) ...[
            VPrimaryButton(
              label: 'Absenden',
              icon: Icons.send_outlined,
              onTap: () {
                state.sendBundle();
                setState(() => _sent = true);
              },
            ),
            const VGap.xs(),
            VGhostButton(
              label: 'Als PDF zum Drucken',
              icon: Icons.print_outlined,
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('PDF gespeichert. Per Post an: ${deskPostalAddress(widget.desk)}')),
              ),
            ),
          ] else
            VPrimaryButton(
              label: 'Weiter',
              onTap: _canContinue(state) ? () => setState(() => _step += 1) : null,
            ),
          if (_step > 0 && !last) ...[
            const VGap.xs(),
            VGhostButton(label: 'Zurück', onTap: () => setState(() => _step -= 1)),
          ],
          if (last) ...[
            const VGap.xs(),
            VGhostButton(label: 'Zurück', onTap: () => setState(() => _step -= 1)),
          ],
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepIndicator(steps: _steps, current: _step),
          const VGap.l(),
          content,
          const VGap.xl(),
        ],
      ),
    );
  }

}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.steps, required this.current});
  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              Text(
                '${i + 1} ${steps[i]}',
                style: VText.caption.copyWith(
                  color: i == current ? VColors.ink : (i < current ? VColors.ink2 : VColors.ink3),
                  fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (i < steps.length - 1) Text('·', style: VText.caption.copyWith(color: VColors.ink3)),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < steps.length; i++)
              Expanded(
                child: Container(
                  height: 3,
                  margin: EdgeInsets.only(right: i < steps.length - 1 ? 4 : 0),
                  color: i <= current ? VColors.red : VColors.ruleSoft,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 11.1 Prüfen
// ---------------------------------------------------------------------------

class _Pruefen extends StatelessWidget {
  const _Pruefen({
    required this.state,
    required this.desk,
    required this.unknown,
    required this.addressCtl,
    required this.showPersonal,
    required this.onChanged,
    required this.onPersonalSaved,
  });
  final DemoState state;
  final String desk;
  final bool unknown;
  final TextEditingController addressCtl;
  final bool showPersonal;
  final VoidCallback onChanged;
  final VoidCallback onPersonalSaved;

  @override
  Widget build(BuildContext context) {
    final incidents = state.incidents.where((i) => i.desk == desk && (i.isOpen || state.draftIncidentIds.contains(i.id))).toList();
    final amount = state.draftAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Diese Verspätungen gehen in den Antrag.', style: VText.h2),
        const VGap.s(),
        Text('Tippe eine an, um sie rauszulassen. Jede steht einzeln im Formular.', style: VText.caption),
        const VGap.m(),
        VSection('Fälle', trailing: Text(fmtEuro(amount), style: VText.captionInk)),
        if (incidents.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: VSpace.m),
            child: Text('Keine offenen Fälle für diese Stelle.', style: VText.caption),
          ),
        for (final i in incidents)
          IncidentRow(
            incident: i,
            leading: _Check(on: state.draftIncidentIds.contains(i.id)),
            onTap: () => state.toggleDraftIncident(i.id),
          ),
        if (amount < 4 && incidents.isNotEmpty && incidents.every((i) => i.ticket == TicketType.deutschlandticket)) ...[
          const VGap.s(),
          Text('Unter 4 € zahlt die Bahn nicht aus. Lass alle drin.', style: VText.caption.copyWith(color: VColors.red)),
        ],
        const VGap.xl(),
        VSection('Geht an'),
        const VGap.m(),
        if (unknown) _UnknownDesk(ctl: addressCtl, onChanged: onChanged) else ...[
          Text(desk, style: VText.bodyStrong),
          const VGap.xs(),
          Text(Mock.deskAddresses[desk] ?? '', style: VText.bodyS.copyWith(color: VColors.ink2)),
          const VGap.xs(),
          Text(
            desk == 'Servicecenter Fahrgastrechte'
                ? 'Die gemeinsame Stelle von DB und rund 40 weiteren Bahnen.'
                : 'Eigene Fahrgastrechte-Stelle dieses Betreibers.',
            style: VText.caption,
          ),
        ],
        const VGap.xl(),
        VSection('Deine Angaben'),
        if (showPersonal) _PersonalForm(onSaved: onPersonalSaved) else ...[
          VKeyValue('Name', Mock.userName, strong: true),
          const VRule(),
          VKeyValue('Anschrift', Mock.userAddress.replaceAll('\n', ', ')),
          const VRule(),
          VKeyValue('Privates Postfach', Mock.userEmail),
          const VRule(),
          VKeyValue('Ticket-Nr.', Mock.ticketNumber, valueStyle: VText.mono),
        ],
        const VGap.m(),
        Container(
          padding: const EdgeInsets.all(VSpace.m),
          decoration: BoxDecoration(border: Border.all(color: VColors.rule), borderRadius: BorderRadius.circular(4)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DEINE VERSPÄTOMAT-ADRESSE', style: VText.eyebrow),
              const SizedBox(height: 6),
              Text(Mock.relayAddress, style: VText.mono),
              const SizedBox(height: 6),
              Text('Deine Anträge gehen von hier raus. Antworten der Bahn landen dort und sofort auch in deinem Postfach.', style: VText.caption),
            ],
          ),
        ),
        const VGap.s(),
        Text('Diese Daten stehen nur auf dem Formular.', style: VText.caption),
      ],
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.on});
  final bool on;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? VColors.red : Colors.transparent,
        border: Border.all(color: on ? VColors.red : VColors.rule, width: 1.5),
      ),
      child: on ? const Icon(Icons.check, size: 14, color: VColors.paper) : null,
    );
  }
}

class _UnknownDesk extends StatelessWidget {
  const _UnknownDesk({required this.ctl, required this.onChanged});
  final TextEditingController ctl;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Wir kennen die Adresse für Anträge noch nicht.', style: VText.bodyStrong),
        const VGap.xs(),
        Text(
          'Dieser Betreiber ist nicht im Verzeichnis. Auf seiner Fahrgastrechte-Seite steht, wohin der Antrag geht. Trag die Adresse hier ein, wir merken sie uns für alle.',
          style: VText.bodyS.copyWith(color: VColors.ink2),
        ),
        const VGap.s(),
        Row(
          children: [
            const Icon(Icons.open_in_new, size: 16, color: VColors.ink2),
            const SizedBox(width: 6),
            Text('Fahrgastrechte-Seite des Betreibers', style: VText.caption.copyWith(decoration: TextDecoration.underline)),
          ],
        ),
        const VGap.m(),
        TextField(
          controller: ctl,
          onChanged: (_) => onChanged(),
          decoration: const InputDecoration(hintText: 'E-Mail oder Postanschrift der Fahrgastrechte-Stelle'),
          style: VText.bodyS,
          maxLines: 2,
        ),
      ],
    );
  }
}

/// First claim only: name, address, private inbox, ticket number. Stored on the phone.
class _PersonalForm extends StatefulWidget {
  const _PersonalForm({required this.onSaved});
  final VoidCallback onSaved;

  @override
  State<_PersonalForm> createState() => _PersonalFormState();
}

class _PersonalFormState extends State<_PersonalForm> {
  late final _name = TextEditingController(text: Mock.userName);
  late final _street = TextEditingController(text: Mock.userAddress.split('\n').first);
  late final _city = TextEditingController(text: Mock.userAddress.split('\n').last);
  late final _email = TextEditingController(text: Mock.userEmail);
  late final _ticket = TextEditingController(text: Mock.ticketNumber);

  @override
  void dispose() {
    for (final c in [_name, _street, _city, _email, _ticket]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VGap.s(),
        Text('Einmal eintragen. Steht danach auf jedem Antrag.', style: VText.caption),
        const VGap.m(),
        TextField(controller: _name, decoration: const InputDecoration(hintText: 'Vor- und Nachname'), style: VText.bodyS),
        const VGap.s(),
        TextField(controller: _street, decoration: const InputDecoration(hintText: 'Straße und Hausnummer'), style: VText.bodyS),
        const VGap.s(),
        TextField(controller: _city, decoration: const InputDecoration(hintText: 'PLZ und Ort'), style: VText.bodyS),
        const VGap.s(),
        TextField(controller: _email, decoration: const InputDecoration(hintText: 'Privates Postfach (E-Mail)'), style: VText.bodyS, keyboardType: TextInputType.emailAddress),
        const VGap.s(),
        TextField(controller: _ticket, decoration: const InputDecoration(hintText: 'Deutschlandticket-Nummer'), style: VText.bodyS),
        const VGap.m(),
        VOutlineButton(
          label: 'Speichern',
          icon: Icons.check,
          onTap: () {
            DemoScope.read(context).savePersonalData();
            widget.onSaved();
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 11.2 Ticket
// ---------------------------------------------------------------------------

class _Ticket extends StatelessWidget {
  const _Ticket({required this.state});
  final DemoState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Füge einen Screenshot deines Tickets mit Barcode an.', style: VText.h2),
        const VGap.s(),
        Text('Die Bahn will das Ticket sehen. Mehr Nachweis braucht es nicht.', style: VText.caption),
        const VGap.l(),
        if (!state.draftTicketAttached) ...[
          VOutlineButton(label: 'Aus Fotos', icon: Icons.photo_library_outlined, onTap: state.attachTicket),
          const VGap.s(),
          VOutlineButton(label: 'Aus Ticket-App', icon: Icons.confirmation_number_outlined, onTap: state.attachTicket),
        ] else ...[
          const MockTicket(),
          const VGap.s(),
          Row(
            children: [
              const Icon(Icons.check, size: 16, color: VColors.green),
              const SizedBox(width: 6),
              Expanded(child: Text('Angehängt. Wird verschlüsselt aufbewahrt, bis der Antrag abgeschlossen ist. Dann gelöscht.', style: VText.caption)),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 11.3 Zweck
// ---------------------------------------------------------------------------

class _Zweck extends StatelessWidget {
  const _Zweck({required this.state, required this.other, required this.onToggle});
  final DemoState state;
  final bool other;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final ngo = Mock.ngoById(state.draftNgoId ?? state.ngoId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Die Entschädigung geht direkt an:', style: VText.h2),
        const VGap.l(),
        Container(
          padding: const EdgeInsets.all(VSpace.m),
          decoration: BoxDecoration(
            color: VColors.paperElevated,
            border: Border.all(color: VColors.ink, width: 1.5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ngo.name, style: VText.title),
              const SizedBox(height: 2),
              Text(ngo.tagline, style: VText.caption),
              const VGap.m(),
              const VRule(),
              VKeyValue('Kontoinhaber', ngo.accountHolder, strong: true),
              const VRule(),
              VKeyValue('IBAN', ngo.iban, valueStyle: VText.mono),
            ],
          ),
        ),
        const VGap.s(),
        Text('So steht es im Formular unter „Name des Kontoinhabers“. Die Bahn überweist dorthin, nicht an dich.', style: VText.caption),
        const VGap.l(),
        Row(
          children: [
            Expanded(child: Text('Anderen Zweck für diesen Antrag wählen', style: VText.bodyS)),
            Switch(value: other, onChanged: onToggle),
          ],
        ),
        if (other) ...[
          const VGap.m(),
          for (final n in Mock.ngos)
            Padding(
              padding: const EdgeInsets.only(bottom: VSpace.s),
              child: VChoiceCard(
                title: n.name,
                subtitle: n.tagline,
                selected: n.id == ngo.id,
                onTap: () => state.setDraftNgo(n.id),
              ),
            ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 11.4 Unterschrift
// ---------------------------------------------------------------------------

class _Unterschrift extends StatelessWidget {
  const _Unterschrift({required this.state});
  final DemoState state;

  @override
  Widget build(BuildContext context) {
    final ngo = Mock.ngoById(state.draftNgoId ?? state.ngoId);
    final incidents = state.incidents.where((i) => state.draftIncidentIds.contains(i.id)).toList()..sort((a, b) => a.date.compareTo(b.date));
    final first = incidents.isNotEmpty ? incidents.first : null;
    final bundled = incidents.length > 1 || (first?.ticket == TicketType.deutschlandticket);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('So geht es raus.', style: VText.h2),
        const VGap.s(),
        Text('Das ist das EU-Antragsformular, ausgefüllt mit deinen Daten. Lies es, dann unterschreib.', style: VText.caption),
        const VGap.m(),
        _FormPreview(
          children: [
            _FormTitle('Antragsformular für Erstattungen und Entschädigungen'),
            _FormSub('gemäß der Verordnung (EU) 2021/782 des Europäischen Parlaments und des Rates'),
            const SizedBox(height: 12),
            _FormHead('1. Grund/Gründe für Ihren Antrag'),
            _FormLine('[X] Verspätung${incidents.any((i) => i.cancelled) ? '   [X] Ausfall' : '   [ ] Ausfall'}   [ ] Verpasster Anschluss'),
            const SizedBox(height: 10),
            _FormHead('3. Angaben zu Ihrer Fahrt'),
            _FormLine('3.1 Eisenbahnunternehmen: ${first?.operator ?? '–'}'),
            if (first != null) ...[
              _FormLine('3.2.1 Abreisedatum: ${_dmy(first.date)}'),
              _FormLine('3.2.2 Abreisebahnhof: ${first.from}'),
              _FormLine('3.2.3 Zielbahnhof: ${first.to}'),
              _FormLine('3.2.5 Ankunft laut Fahrplan: ${first.plannedArrival != null ? fmtTime(first.plannedArrival!) : '–'}'),
              _FormLine('3.2.6 Zugnummer: ${first.line}'),
              _FormLine('3.2.7 Fahrkartennummer: ${first.ticket == TicketType.einzelfahrkarte ? 'Auftrags-Nr. 9K2M4P' : Mock.ticketNumber}'),
              _FormLine('3.3.3 Tatsächliche Ankunft: ${first.actualArrival != null ? fmtTime(first.actualArrival!) : '–'}'),
            ],
            const SizedBox(height: 10),
            _FormHead('4. Art Ihres Antrags'),
            _FormLine(bundled
                ? '[X] Entschädigung: für wiederholte Verspätungen oder Ausfälle, Inhaber einer Zeitfahrkarte'
                : '[X] Entschädigung: Verspätung bei der Ankunft von ${(first?.delayMinutes ?? 0) >= 120 ? 'mindestens 120' : '60 bis 119'} Minuten'),
            const SizedBox(height: 10),
            _FormHead('5. Angaben zur Person'),
            _FormLine('5.1 Name: ${Mock.userName}'),
            _FormLine('5.2 Anschrift: ${Mock.userAddress.replaceAll('\n', ', ')}'),
            _FormLine('5.3.1 E-Mail: ${Mock.relayAddress}'),
            _FormLine('5.4 Auszahlung: [X] Geld   [ ] Gutschein'),
            _FormLine('5.5.1 IBAN: ${ngo.iban}'),
            _FormLine('5.5.4 Name des Kontoinhabers: ${ngo.accountHolder}', strong: true),
            const SizedBox(height: 10),
            _FormHead('6. Zusätzliche Angaben'),
            if (bundled) ...[
              _FormLine('Wiederholte Verspätungen mit Deutschlandticket ${Mock.ticketNumber}:'),
              for (final i in incidents)
                _FormLine(
                  '· ${_dmy(i.date)} ${i.line} ${i.from} – ${i.to}, Ankunft ${i.plannedArrival != null ? fmtTime(i.plannedArrival!) : '–'} geplant, ${i.actualArrival != null ? fmtTime(i.actualArrival!) : '–'} tatsächlich (+${i.delayMinutes} Min${i.cancelled ? ', Zugausfall' : ''}${i.selfEntered ? ', Ankunftszeit selbst eingetragen' : ''})',
                ),
              _FormLine('Summe: ${fmtEuro(state.draftAmount)} (${incidents.length} × 1,50 €)'),
            ] else
              _FormLine('Fahrpreis ${first?.fare != null ? fmtEuro(first!.fare!) : '–'}, Anspruch ${fmtEuro(state.draftAmount)}.'),
            const SizedBox(height: 12),
            _FormLine('Hiermit erkläre ich, dass alle in diesem Formular gemachten Angaben der Wahrheit entsprechen.', strong: true),
            _FormLine('Datum: ${_dmy(DateTime.now())}   Ort: Köln'),
            _FormLine('Name des Fahrgastes: ${Mock.userName}'),
          ],
        ),
        const VGap.l(),
        const VRule.red(),
        const VGap.m(),
        Text('Ich bestätige, dass die Angaben stimmen und ich Inhaber:in des Tickets bin.', style: VText.bodyStrong),
        const VGap.xs(),
        Text('Das EU-Formular braucht keine gezeichnete Unterschrift, nur deinen Namen. Zeichnen darfst du trotzdem.', style: VText.caption),
        const VGap.m(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('Name', style: VText.caption),
            const SizedBox(width: 12),
            Text(Mock.userName, style: VText.title),
          ],
        ),
        const VGap.s(),
        SignaturePad(onSigned: state.sign),
        if (!state.draftSigned) ...[
          const VGap.xs(),
          VGhostButton(label: 'Nur mit Namen bestätigen', onTap: state.sign),
        ] else ...[
          const VGap.xs(),
          Row(
            children: [
              const Icon(Icons.check, size: 16, color: VColors.green),
              const SizedBox(width: 6),
              Text('Bestätigt. Deine Unterschrift bleibt nur in diesem Antrag.', style: VText.caption),
            ],
          ),
        ],
      ],
    );
  }

  String _dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

class _FormPreview extends StatelessWidget {
  const _FormPreview({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(VSpace.m),
      decoration: BoxDecoration(
        color: VColors.paperElevated,
        border: Border.all(color: VColors.rule),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _FormTitle extends StatelessWidget {
  const _FormTitle(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Text(t.toUpperCase(), style: VText.captionInk.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.3));
}

class _FormSub extends StatelessWidget {
  const _FormSub(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Text(t, style: VText.caption.copyWith(fontStyle: FontStyle.italic, fontSize: 11));
}

class _FormHead extends StatelessWidget {
  const _FormHead(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(t, style: VText.captionInk.copyWith(fontWeight: FontWeight.w700)),
      );
}

class _FormLine extends StatelessWidget {
  const _FormLine(this.t, {this.strong = false});
  final String t;
  final bool strong;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(t, style: VText.mono.copyWith(fontSize: 12, fontWeight: strong ? FontWeight.w700 : FontWeight.w400, color: VColors.ink)),
      );
}

// ---------------------------------------------------------------------------
// 11.5 Senden
// ---------------------------------------------------------------------------

class _Senden extends StatelessWidget {
  const _Senden({required this.state, required this.desk});
  final DemoState state;
  final String desk;

  @override
  Widget build(BuildContext context) {
    final mail = RailMail(
      id: 'draft',
      incidentIds: state.draftIncidentIds,
      direction: MailDirection.out,
      from: '${Mock.userName} <${Mock.relayAddress}>',
      to: deskMailAddress(desk),
      subject: 'Fahrgastrechte: EU-Antragsformular',
      body: draftMailBody(state),
      date: DateTime.now(),
      attachments: const ['EU-Antrag.pdf', 'Ticket.png'],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Wir haben alles vorbereitet. Du schickst es ab.', style: VText.h2),
        const VGap.s(),
        Text('Von deiner Verspätomat-Adresse, mit Kopie an dein Postfach.', style: VText.caption),
        const VGap.m(),
        MailView(mail: mail, bcc: '${Mock.userEmail} (dein Postfach)'),
        const VGap.m(),
        VKeyValue('Fälle', '${state.draftIncidentIds.length}'),
        const VRule(),
        VKeyValue('Anspruch', fmtEuro(state.draftAmount), strong: true),
        const VRule(),
        VKeyValue('Empfänger', Mock.ngoById(state.draftNgoId ?? state.ngoId).accountHolder),
        const VGap.s(),
        Text('Nach dem Absenden steht alles auf „eingereicht“. Die Antwort der Bahn landet in der App und in deinem Postfach.', style: VText.caption),
      ],
    );
  }
}

class _Sent extends StatelessWidget {
  const _Sent({required this.desk});
  final String desk;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(VSpace.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const VStationClock(size: 56),
              const VGap.xl(),
              Text('Abgeschickt.', style: VText.h1),
              const VGap.s(),
              Text(Mock.longDate(DateTime.now()), style: VText.h2.copyWith(color: VColors.ink2, fontWeight: FontWeight.w400)),
              const VGap.m(),
              Text('An $desk, von deiner Adresse. Die Kopie ist schon in deinem Postfach.', style: VText.body.copyWith(color: VColors.ink2)),
              const Spacer(),
              VPrimaryButton(label: 'Zurück zum Konto', onTap: () => context.go(Routes.konto)),
            ],
          ),
        ),
      ),
    );
  }
}
