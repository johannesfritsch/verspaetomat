import 'package:flutter/material.dart';

import '../../mock/mock_data.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'claims_widgets.dart';

/// Antwort: what the railway said, and everything else that went in and out.
class AntwortScreen extends StatefulWidget {
  const AntwortScreen({super.key, this.mailId, this.demo});
  final String? mailId;
  final String? demo; // question | rejected

  @override
  State<AntwortScreen> createState() => _AntwortScreenState();
}

class _AntwortScreenState extends State<AntwortScreen> {
  String? _mailId;
  bool _demoRan = false;

  @override
  void initState() {
    super.initState();
    _mailId = widget.mailId;
    if (widget.demo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _demoRan) return;
        _demoRan = true;
        final state = DemoScope.read(context);
        final outcome = widget.demo == 'rejected' ? MailOutcome.rejected : MailOutcome.question;
        final mail = state.receiveReply(outcome: outcome);
        setState(() => _mailId = mail?.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = DemoScope.of(context);
    RailMail? mail;
    for (final m in state.mails) {
      if (m.id == _mailId) mail = m;
    }
    mail ??= state.mails.where((m) => m.direction == MailDirection.inbound).firstOrNull;

    return VScreen(
      eyebrow: 'Post von der Bahn',
      title: 'Antwort',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mail == null)
            _NothingYet(state: state)
          else if (mail.direction == MailDirection.out)
            _Outgoing(mail: mail)
          else
            _Inbound(mail: mail, state: state),
          const VGap.xl(),
          VSection('Alle Nachrichten'),
          if (state.mails.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: VSpace.m),
              child: Text('Noch keine Nachrichten.', style: VText.caption),
            ),
          for (final m in state.mails)
            VListRow(
              leading: Icon(
                m.direction == MailDirection.inbound ? Icons.call_received : Icons.call_made,
                size: 20,
                color: m.direction == MailDirection.inbound ? VColors.red : VColors.ink2,
              ),
              title: m.direction == MailDirection.inbound ? 'Servicecenter Fahrgastrechte' : 'Du → ${m.to.split('@').first}',
              subtitle: '${Mock.shortDate(m.date)} · ${m.subject}',
              trailing: m.amount != null ? Text(fmtEuro(m.amount!), style: VText.bodySStrong) : null,
              chevron: true,
              onTap: () => setState(() => _mailId = m.id),
            ),
          const VGap.m(),
          Text(
            'Jede Mail geht von deiner Verspätomat-Adresse raus und kommt dort an. Du bekommst jede in Kopie in dein privates Postfach.',
            style: VText.caption,
          ),
          const VGap.xl(),
        ],
      ),
    );
  }
}

class _NothingYet extends StatelessWidget {
  const _NothingYet({required this.state});
  final DemoState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VGap.m(),
        Text('Noch keine Antwort.', style: VText.h2),
        const VGap.s(),
        Text('Die Bahn antwortet meist innerhalb eines Monats. Die Antwort landet hier und in deinem Postfach.', style: VText.body.copyWith(color: VColors.ink2)),
        const VGap.l(),
        _PostalPath(),
      ],
    );
  }
}

class _Outgoing extends StatelessWidget {
  const _Outgoing({required this.mail});
  final RailMail mail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VGap.s(),
        Text('Dein Antrag vom ${Mock.longDate(mail.date)}.', style: VText.h2),
        const VGap.s(),
        Text('Abgeschickt. Noch keine Antwort dazu.', style: VText.body.copyWith(color: VColors.ink2)),
        const VGap.m(),
        MailView(mail: mail, compact: true),
        const VGap.s(),
        VGhostButton(label: 'Ganze Mail lesen', icon: Icons.mail_outline, onTap: () => showMailSheet(context, mail)),
      ],
    );
  }
}

class _Inbound extends StatelessWidget {
  const _Inbound({required this.mail, required this.state});
  final RailMail mail;
  final DemoState state;

  @override
  Widget build(BuildContext context) {
    final ngo = _ngoFor(mail, state);
    return switch (mail.outcome) {
      MailOutcome.accepted || null => _Accepted(mail: mail, ngo: ngo),
      MailOutcome.question => _Question(mail: mail),
      MailOutcome.rejected => _Rejected(mail: mail),
    };
  }

  Ngo _ngoFor(RailMail m, DemoState s) {
    for (final i in s.incidents) {
      if (m.incidentIds.contains(i.id)) return Mock.ngoById(i.ngoId);
    }
    return s.ngo;
  }
}

class _Accepted extends StatelessWidget {
  const _Accepted({required this.mail, required this.ngo});
  final RailMail mail;
  final Ngo ngo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VGap.s(),
        Text('Die Bahn hat geantwortet.', style: VText.caption),
        const VGap.s(),
        Text(mail.amount != null ? fmtEuro(mail.amount!) : '–', style: VText.number),
        const VGap.s(),
        Text('an ${ngo.name} überwiesen.', style: VText.h2),
        const VGap.m(),
        const VRule.red(),
        VKeyValue('Eingegangen', '${Mock.shortDate(mail.date)} ${fmtTime(TimeOfDay.fromDateTime(mail.date))}'),
        const VRule(),
        VKeyValue('Fälle', '${mail.incidentIds.length}'),
        const VRule(),
        VKeyValue('Status', 'bestätigt', strong: true),
        const VGap.m(),
        VPrimaryButton(label: 'Antwort lesen', icon: Icons.mail_outline, onTap: () => showMailSheet(context, mail)),
        const VGap.s(),
        Text('Die Zahl auf dem Wir-Screen ist gerade um diesen Betrag gewachsen. Das warst du.', style: VText.caption),
      ],
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({required this.mail});
  final RailMail mail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VGap.s(),
        Text('Rückfrage der Bahn.', style: VText.h2),
        const VGap.s(),
        Text('Das Servicecenter braucht noch etwas von dir. Nichts geht raus, bevor du es abschickst.', style: VText.body.copyWith(color: VColors.ink2)),
        const VGap.m(),
        MailView(mail: mail),
        const VGap.m(),
        VPrimaryButton(label: 'Antworten', icon: Icons.reply, onTap: () => _reply(context)),
      ],
    );
  }

  Future<void> _reply(BuildContext context) {
    const templates = [
      ('Ticketkopie nachreichen', 'Sehr geehrte Damen und Herren,\n\nanbei die gewünschte Kopie meines Deutschlandtickets für Juli 2026.\n\nMit freundlichen Grüßen\n${Mock.userName}'),
      ('Zug und Zeiten bestätigen', 'Sehr geehrte Damen und Herren,\n\nzu Ihrer Rückfrage: Die Fahrt fand wie im Antrag angegeben statt. Planmäßige und tatsächliche Ankunft habe ich dem Live-Fahrplan entnommen.\n\nMit freundlichen Grüßen\n${Mock.userName}'),
      ('Frei schreiben', ''),
    ];
    return showVSheet(
      context,
      expand: true,
      builder: (ctx) => _ReplyComposer(templates: templates, to: mail.from),
    );
  }
}

class _ReplyComposer extends StatefulWidget {
  const _ReplyComposer({required this.templates, required this.to});
  final List<(String, String)> templates;
  final String to;

  @override
  State<_ReplyComposer> createState() => _ReplyComposerState();
}

class _ReplyComposerState extends State<_ReplyComposer> {
  int _selected = 0;
  late final TextEditingController _c = TextEditingController(text: widget.templates.first.$2);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        VSheetHeader(title: 'Antworten', subtitle: 'von ${Mock.relayAddress}'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.s, VSpace.page, VSpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < widget.templates.length; i++)
                      InkWell(
                        onTap: () => setState(() {
                          _selected = i;
                          _c.text = widget.templates[i].$2;
                        }),
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: _selected == i ? VColors.ink : Colors.transparent,
                            border: Border.all(color: _selected == i ? VColors.ink : VColors.rule),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(widget.templates[i].$1, style: VText.caption.copyWith(color: _selected == i ? VColors.paper : VColors.ink)),
                        ),
                      ),
                  ],
                ),
                const VGap.m(),
                Text('An ${widget.to}', style: VText.caption),
                const VGap.s(),
                TextField(controller: _c, maxLines: 10, minLines: 6, style: VText.bodyS),
                const VGap.s(),
                Row(
                  children: [
                    const Icon(Icons.attach_file, size: 16, color: VColors.ink2),
                    const SizedBox(width: 6),
                    Text('Deutschlandticket_2026-07.png', style: VText.caption),
                  ],
                ),
                const VGap.l(),
                VPrimaryButton(
                  label: 'Absenden',
                  icon: Icons.send_outlined,
                  onTap: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Abgeschickt. Kopie in deinem Postfach.')));
                  },
                ),
                const VGap.xs(),
                Text('Geht von deiner Adresse raus. Wir schreiben nie von uns aus an die Bahn.', style: VText.caption),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Rejected extends StatelessWidget {
  const _Rejected({required this.mail});
  final RailMail mail;

  @override
  Widget build(BuildContext context) {
    final reason = _reason(mail.body);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VGap.s(),
        Text('Abgelehnt.', style: VText.h2),
        const VGap.s(),
        Text('Die Bahn zahlt für diesen Fall nicht. Du entscheidest, ob du das so lässt.', style: VText.body.copyWith(color: VColors.ink2)),
        const VGap.m(),
        if (reason != null) ...[
          Container(
            padding: const EdgeInsets.all(VSpace.m),
            decoration: BoxDecoration(
              color: VColors.redSoft,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BEGRÜNDUNG', style: VText.eyebrow.copyWith(color: VColors.red)),
                const SizedBox(height: 6),
                Text(reason, style: VText.bodyS),
              ],
            ),
          ),
          const VGap.m(),
        ],
        MailView(mail: mail, compact: true),
        const VGap.s(),
        VGhostButton(label: 'Ganze Mail lesen', icon: Icons.mail_outline, onTap: () => showMailSheet(context, mail)),
        const VGap.m(),
        const VRule(),
        const VGap.m(),
        Text('Wenn du das anders siehst', style: VText.bodyStrong),
        const VGap.xs(),
        Text(
          'Die Schlichtungsstelle für den öffentlichen Personenverkehr (söp) vermittelt kostenlos, nach einer endgültigen Ablehnung oder zwei Monaten ohne Antwort.',
          style: VText.bodyS.copyWith(color: VColors.ink2),
        ),
        const VGap.xs(),
        Text('soep-online.de', style: VText.mono.copyWith(color: VColors.ink2)),
        const VGap.m(),
        VOutlineButton(
          label: 'Vorlage: Widerspruch',
          icon: Icons.reply,
          onTap: () => showVSheet(
            context,
            expand: true,
            builder: (ctx) => _ReplyComposer(
              templates: const [
                ('Widerspruch', 'Sehr geehrte Damen und Herren,\n\nich widerspreche der Ablehnung. Nach meiner Kenntnis lag am 22.07.2026 keine Unwetterwarnung für die Strecke vor. Ich bitte um erneute Prüfung.\n\nMit freundlichen Grüßen\n${Mock.userName}'),
                ('Frei schreiben', ''),
              ],
              to: mail.from,
            ),
          ),
        ),
      ],
    );
  }

  String? _reason(String body) {
    final idx = body.indexOf('beruhte auf');
    if (idx < 0) return null;
    final end = body.indexOf('.', idx);
    return body.substring(idx, end < 0 ? body.length : end + 1).replaceFirst('beruhte auf', 'Beruhte auf');
  }
}

class _PostalPath extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Post statt Mail?', style: VText.bodyStrong),
        const VGap.xs(),
        Text('Manchmal antwortet die Bahn per Brief. Dann fotografierst du ihn, wir lesen den Betrag.', style: VText.caption),
        const VGap.s(),
        VDemoControl(
          label: 'Fotografiere die Antwort',
          icon: Icons.photo_camera_outlined,
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kamera öffnet sich. Wir lesen den Betrag, du bestätigst ihn.'))),
        ),
      ],
    );
  }
}
