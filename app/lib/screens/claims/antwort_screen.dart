import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart' show Mock;
import '../../repo/app_repository.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
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
  final _loader = LoaderController();
  String? _mailId;
  bool _demoRan = false;
  String? _demoError;

  static const _bodies = {
    'question':
        'Sehr geehrte Damen und Herren,\n\nzur Bearbeitung Ihres Antrags benötigen wir noch eine Kopie Ihres Deutschlandtickets für den Monat Juli 2026. Bitte senden Sie diese als Antwort auf diese E-Mail.\n\nMit freundlichen Grüßen\nIhr Servicecenter Fahrgastrechte',
    'rejected':
        'Sehr geehrte Damen und Herren,\n\nleider können wir Ihrem Antrag nicht entsprechen. Die Verspätung beruhte auf außergewöhnlichen Umständen (Unwetter), für die nach VO (EU) 2021/782 Art. 19 Abs. 10 keine Entschädigung geleistet wird.\n\nMit freundlichen Grüßen\nIhr Servicecenter Fahrgastrechte',
  };

  @override
  void initState() {
    super.initState();
    _mailId = widget.mailId;
  }

  bool _demoIgnored = false;

  Future<List<ApiMail>> _load(AppRepository repo) async {
    if (widget.demo != null && !_demoRan) {
      _demoRan = true;
      if (RepoScope.read(context).isLocal) {
        _demoIgnored = true;
        return repo.mails();
      }
      try {
        final r = await repo.simulateInbound(body: _bodies[widget.demo] ?? _bodies['question']!);
        _mailId = r.mail.id;
      } catch (e) {
        _demoError = e.toString();
      }
    }
    return repo.mails();
  }

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    return Loader<List<ApiMail>>(
      controller: _loader,
      load: _load,
      builder: (context, mails, refresh) {
        ApiMail? mail = mails.where((m) => m.id == _mailId).firstOrNull;
        if (widget.demo == null) {
          mail ??= mails.where((m) => m.direction == ApiMailDirection.inbound).firstOrNull;
        }
        final ngoName = session.ngos.where((n) => n.id == session.me?.settings.ngoId).map((n) => n.name).firstOrNull ?? 'den Verein';

        return VScreen(
          eyebrow: 'Post von der Bahn',
          title: 'Antwort',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_demoIgnored)
                Text('Antworten kommen vom Stellwerk oder von der Bahn.', style: VText.body.copyWith(color: VColors.ink2))
              else if (widget.demo != null && _demoError != null)
                const _NothingSubmitted()
              else if (mail == null)
                const _NothingYet()
              else if (mail.direction == ApiMailDirection.out)
                _Outgoing(mail: mail)
              else
                _Inbound(mail: mail, ngoName: ngoName, onReplied: refresh),
              const VGap.xl(),
              const VSection('Alle Nachrichten'),
              if (mails.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: VSpace.m),
                  child: Text('Noch keine Nachrichten.', style: VText.caption),
                ),
              for (final m in mails)
                VListRow(
                  leading: Icon(
                    m.direction == ApiMailDirection.inbound ? Icons.call_received : Icons.call_made,
                    size: 20,
                    color: m.direction == ApiMailDirection.inbound ? VColors.red : VColors.ink2,
                  ),
                  title: m.direction == ApiMailDirection.inbound ? _senderName(m.from) : 'Du → ${_recipientName(m.to)}',
                  subtitle: '${Mock.shortDate(m.date.toLocal())} · ${m.subject}',
                  trailing: m.amountCents != null ? Text(fmtCents(m.amountCents!), style: VText.bodySStrong) : null,
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
      },
    );
  }

  String _senderName(String from) {
    final lt = from.indexOf('<');
    final name = lt > 0 ? from.substring(0, lt).trim() : from;
    return name.contains('deutschebahn') || name.toLowerCase().contains('servicecenter') ? deskDisplay('Servicecenter Fahrgastrechte') : name;
  }

  String _recipientName(String to) {
    if (to.contains('deutschebahn')) return deskDisplay('Servicecenter Fahrgastrechte');
    return to.split('@').first;
  }
}

/// Demo route opened before anything was sent.
class _NothingSubmitted extends StatelessWidget {
  const _NothingSubmitted();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VGap.m(),
        Text('Nichts eingereicht.', style: VText.h2),
        const VGap.s(),
        Text('Schick erst ein Bündel ab. Die Antwort der Bahn kann nur auf einen Antrag folgen.', style: VText.body.copyWith(color: VColors.ink2)),
        const VGap.l(),
        VGhostButton(label: 'Zum Konto', icon: Icons.receipt_long_outlined, onTap: () => (context.canPop() ? context.pop() : context.go(Routes.konto))),
      ],
    );
  }
}

class _NothingYet extends StatelessWidget {
  const _NothingYet();

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
        const _PostalPath(),
      ],
    );
  }
}

class _Outgoing extends StatelessWidget {
  const _Outgoing({required this.mail});
  final ApiMail mail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VGap.s(),
        Text('Dein Antrag vom ${Mock.longDate(mail.date.toLocal())}.', style: VText.h2),
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
  const _Inbound({required this.mail, required this.ngoName, required this.onReplied});
  final ApiMail mail;
  final String ngoName;
  final VoidCallback onReplied;

  @override
  Widget build(BuildContext context) {
    return switch (mail.outcome) {
      ApiMailOutcome.question => _Question(mail: mail, onReplied: onReplied),
      ApiMailOutcome.rejected => _Rejected(mail: mail, onReplied: onReplied),
      _ => _Accepted(mail: mail, ngoName: ngoName),
    };
  }
}

class _Accepted extends StatelessWidget {
  const _Accepted({required this.mail, required this.ngoName});
  final ApiMail mail;
  final String ngoName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VGap.s(),
        Text('Die Bahn hat geantwortet.', style: VText.caption),
        const VGap.s(),
        Text(mail.amountCents != null ? fmtCents(mail.amountCents!) : '–', style: VText.number),
        const VGap.s(),
        Text('an $ngoName überwiesen.', style: VText.h2),
        const VGap.m(),
        const VRule.red(),
        VKeyValue('Eingegangen', fmtStamp(mail.date)),
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
  const _Question({required this.mail, required this.onReplied});
  final ApiMail mail;
  final VoidCallback onReplied;

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

  Future<void> _reply(BuildContext context) async {
    final name = RepoScope.read(context).me?.personalData?.name ?? RepoScope.read(context).me?.nickname ?? 'Fahrgast';
    final templates = [
      ('Ticketkopie nachreichen', 'Sehr geehrte Damen und Herren,\n\nanbei die gewünschte Kopie meines Deutschlandtickets für den angefragten Monat.\n\nMit freundlichen Grüßen\n$name'),
      ('Zug und Zeiten bestätigen', 'Sehr geehrte Damen und Herren,\n\nzu Ihrer Rückfrage: Die Fahrt fand wie im Antrag angegeben statt. Planmäßige und tatsächliche Ankunft habe ich dem Live-Fahrplan entnommen.\n\nMit freundlichen Grüßen\n$name'),
      ('Frei schreiben', ''),
    ];
    final sent = await showVSheet<bool>(context, expand: true, builder: (ctx) => _ReplyComposer(templates: templates, mail: mail));
    if (sent == true) onReplied();
  }
}

class _ReplyComposer extends StatefulWidget {
  const _ReplyComposer({required this.templates, required this.mail});
  final List<(String, String)> templates;
  final ApiMail mail;

  @override
  State<_ReplyComposer> createState() => _ReplyComposerState();
}

class _ReplyComposerState extends State<_ReplyComposer> {
  int _selected = 0;
  bool _sending = false;
  late final TextEditingController _c = TextEditingController(text: widget.templates.first.$2);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final session = RepoScope.read(context);
    try {
      await session.repo.replyToMail(widget.mail.id, _c.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Abgeschickt. Kopie in deinem Postfach.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Senden fehlgeschlagen: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final relay = RepoScope.of(context).me?.relayAddress ?? 'deiner Verspätomat-Adresse';
    return Column(
      children: [
        VSheetHeader(title: 'Antworten', subtitle: 'von $relay'),
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
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
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
                Text('An ${widget.mail.from}', style: VText.caption),
                const VGap.s(),
                TextField(controller: _c, maxLines: 10, minLines: 6, style: VText.bodyS),
                const VGap.l(),
                VPrimaryButton(label: _sending ? 'Sendet …' : 'Absenden', icon: Icons.send_outlined, onTap: _sending ? null : _send),
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
  const _Rejected({required this.mail, required this.onReplied});
  final ApiMail mail;
  final VoidCallback onReplied;

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
            decoration: BoxDecoration(color: VColors.redSoft, borderRadius: BorderRadius.circular(4)),
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
          onTap: () async {
            final name = RepoScope.read(context).me?.personalData?.name ?? 'Fahrgast';
            final sent = await showVSheet<bool>(
              context,
              expand: true,
              builder: (ctx) => _ReplyComposer(
                templates: [
                  ('Widerspruch', 'Sehr geehrte Damen und Herren,\n\nich widerspreche der Ablehnung. Nach meiner Kenntnis lag am fraglichen Tag keine Unwetterwarnung für die Strecke vor. Ich bitte um erneute Prüfung.\n\nMit freundlichen Grüßen\n$name'),
                  ('Frei schreiben', ''),
                ],
                mail: mail,
              ),
            );
            if (sent == true) onReplied();
          },
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
  const _PostalPath();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Post statt Mail?', style: VText.bodyStrong),
        const VGap.xs(),
        Text('Manchmal antwortet die Bahn per Brief. Dann fotografierst du ihn, wir lesen den Betrag.', style: VText.caption),
        const VGap.s(),
        if (RepoScope.of(context).isLocal)
          VGhostButton(
            label: 'Antwort fotografieren',
            icon: Icons.photo_camera_outlined,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kamera folgt. Wir lesen den Betrag, du bestätigst ihn.'))),
          )
        else
          VDemoControl(
            label: 'Fotografiere die Antwort',
            icon: Icons.photo_camera_outlined,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kamera öffnet sich. Wir lesen den Betrag, du bestätigst ihn.'))),
          ),
      ],
    );
  }
}
