import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../mock/mock_data.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'community_widgets.dart';

/// Einstellungen & Datenschutz.
class EinstellungenScreen extends StatefulWidget {
  const EinstellungenScreen({super.key});

  @override
  State<EinstellungenScreen> createState() => _EinstellungenScreenState();
}

class _EinstellungenScreenState extends State<EinstellungenScreen> {
  bool _nudges = true;
  bool _quietHours = true;
  final Set<String> _muted = {'Köln Hansaring'};

  @override
  Widget build(BuildContext context) {
    final state = DemoScope.of(context);
    final session = RepoScope.of(context);
    final me = session.me;
    final settings = me?.settings;
    final ticket = settings?.ticket ?? state.ticket;
    final ngoId = settings?.ngoId ?? state.ngoId;
    final ngoName = session.ngos.where((n) => n.id == ngoId).map((n) => n.name).firstOrNull ?? state.ngo.name;
    final locationMode = settings?.locationMode ?? state.locationMode;
    final keepCorrespondence = settings?.keepCorrespondence ?? state.keepCorrespondence;
    final showOnBoards = settings?.showOnBoards ?? state.showOnBoards;
    final traewellingLinked = settings?.traewellingLinked ?? state.traewellingLinked;
    final personal = me?.personalData;
    final relay = me?.relayAddress ?? Mock.relayAddress;
    final privateMail = personal?.email ?? Mock.userEmail;

    return VScreen(
      title: 'Einstellungen',
      eyebrow: 'UND DATENSCHUTZ',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.m(),
          const VSection('Fahren'),
          VListRow(
            title: 'Ticket',
            subtitle: ticket.label,
            chevron: true,
            onTap: () => _pickTicket(context, session, ticket),
          ),
          VListRow(
            title: 'Zweck',
            subtitle: ngoName,
            chevron: true,
            onTap: () => _pickNgo(context, session, ngoId),
          ),
          const VGap.xl(),
          const VSection('Bahnsteig-Hinweis'),
          SwitchRow(
            title: 'Hinweis am Bahnhof',
            subtitle: 'Nach zwei bis drei Minuten an einem Bahnhof',
            value: _nudges,
            onChanged: (v) => setState(() => _nudges = v),
          ),
          SwitchRow(
            title: 'Ruhezeiten',
            subtitle: '22:00 bis 06:00 kein Hinweis',
            value: _quietHours,
            onChanged: (v) => setState(() => _quietHours = v),
          ),
          VListRow(
            title: 'Stumme Bahnhöfe',
            subtitle: _muted.isEmpty ? 'Keine' : _muted.join(', '),
            chevron: true,
            onTap: () => _mutedStations(context),
          ),
          const VGap.xl(),
          const VSection('Standort'),
          const VGap.s(),
          Text('Wir schauen nur, ob du an einem Bahnhof stehst. Während der Fahrt folgen wir dem Zug, nicht dir.', style: VText.bodyS.copyWith(color: VColors.ink2)),
          const VGap.s(),
          for (final m in LocationMode.values)
            ChoiceRow(
              title: m.label,
              subtitle: switch (m) {
                LocationMode.always => 'Für den Hinweis am Bahnsteig',
                LocationMode.whileUsing => 'Der Hinweis kommt nur, wenn du die App gerade nutzt',
                LocationMode.never => 'Manueller Check-in, jederzeit möglich',
              },
              selected: locationMode == m,
              onTap: () => session.updateSettings(MePatch(locationMode: m)),
            ),
          const VGap.xl(),
          const VSection('Anträge'),
          VListRow(
            title: 'Persönliche Daten für Anträge',
            subtitle: personal == null ? 'Noch nicht hinterlegt. Fragen wir beim ersten Antrag.' : '${personal.name} · ${personal.ticketNumber ?? 'ohne Ticketnummer'}',
            chevron: true,
            onTap: () => _personalData(context, session, personal),
          ),
          const VGap.m(),
          Text('Meine Verspätomat-Adresse', style: VText.bodyStrong),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(VSpace.m),
            decoration: BoxDecoration(border: Border.all(color: VColors.rule), borderRadius: BorderRadius.circular(4)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(relay, style: VText.mono),
                const SizedBox(height: 8),
                Text(
                  'Deine Anträge gehen von hier raus. Antworten der Bahn landen hier und sofort auch in deinem Postfach ($privateMail). Wir lesen Status, Betrag und Aktenzeichen, mehr nicht.',
                  style: VText.caption,
                ),
              ],
            ),
          ),
          const VGap.s(),
          SwitchRow(
            title: 'Korrespondenz nach Abschluss behalten',
            subtitle: 'Sonst bleibt nur der Eintrag im Konto',
            value: keepCorrespondence,
            onChanged: (v) => session.updateSettings(MePatch(keepCorrespondence: v)),
          ),
          VListRow(title: 'Alle Mails exportieren', subtitle: 'Gesendet und empfangen, als Archiv', chevron: true, onTap: () => showSnack(context, 'Archiv wird erstellt. Du bekommst einen Link per Mail.')),
          const VGap.xl(),
          const VSection('Konto'),
          VListRow(
            title: 'Wiederherstellungscode',
            subtitle: 'Kein Konto. Dieser Code holt dein Konto auf ein neues Gerät.',
            chevron: true,
            onTap: () => _recoveryCode(context, session),
          ),
          VListRow(
            title: 'Träwelling verbinden',
            subtitle: traewellingLinked ? 'Verbunden' : 'Check-ins importieren, Punkte behalten',
            chevron: true,
            onTap: () => _traewelling(context, session),
          ),
          SwitchRow(title: 'Mich in Ranglisten zeigen', subtitle: 'Ohne dich bleiben die Listen trotzdem da', value: showOnBoards, onChanged: (v) => session.updateSettings(MePatch(showOnBoards: v))),
          const VGap.xl(),
          const VSection('Deine Daten'),
          VListRow(title: 'Daten exportieren', subtitle: 'Alles, was wir über dich haben', chevron: true, onTap: () => _export(context, session)),
          VListRow(title: 'Alles löschen', subtitle: 'Konto, Fahrten, Anträge, Adresse', chevron: true, onTap: () => _deleteAll(context, state, session)),
          VListRow(title: 'Woher kommen die Daten?', subtitle: 'Jede Zahl und ihre Quelle', chevron: true, onTap: () => context.push(Routes.datenherkunft)),
          const VGap.xl(),
          const VSection('Backend'),
          for (final m in BackendMode.values)
            ChoiceRow(
              title: m.label,
              subtitle: m == BackendMode.demo ? 'Alles auf dem Gerät, erfundene Daten' : session.apiUrl,
              selected: session.mode == m,
              onTap: () => session.switchMode(m),
            ),
          const VGap.s(),
          Row(
            children: [
              Icon(
                session.busy ? Icons.sync : (session.healthy == true ? Icons.check_circle_outline : Icons.error_outline),
                size: 18,
                color: session.busy ? VColors.ink2 : (session.healthy == true ? VColors.green : VColors.red),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  session.busy
                      ? 'Verbinde …'
                      : session.error ?? (session.healthy == true ? '${session.repo.label} erreichbar${session.isLocal && session.me != null ? ' · Gerät ${session.me!.id.substring(0, session.me!.id.length < 8 ? session.me!.id.length : 8)}' : ''}' : 'Nicht erreichbar'),
                  style: VText.caption,
                ),
              ),
              TextButton(onPressed: session.checkHealth, child: Text('Prüfen', style: VText.bodySStrong)),
            ],
          ),
          const VGap.xl(),
          const VSection('Vorführung'),
          SwitchRow(title: 'Offline simulieren', subtitle: 'Screens zeigen den letzten Stand', value: state.offline, onChanged: (_) => state.toggleOffline()),
          VListRow(title: 'Showcase', subtitle: 'Alle Screens auf einen Blick', chevron: true, onTap: () => context.go(Routes.showcase)),
          const VGap.l(),
          Text('Verspätomat 0.1 · Vorführung · Alle Daten erfunden', style: VText.caption),
        ],
      ),
    );
  }

  void _traewelling(BuildContext context, Session session) {
    showVSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(VSpace.page, 0, VSpace.page, VSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VSheetHeader(title: 'Träwelling'),
            Text(
              'Träwelling ist der offene Check-in-Dienst für Bahnfahrten. Wenn du dort schon eincheckst, übernehmen wir deine Fahrten hier, und du musst nichts doppelt machen.',
              style: VText.body,
            ),
            const VGap.m(),
            Text('Wir lesen nur deine Check-ins. Nichts wird bei Träwelling verändert.', style: VText.body.copyWith(color: VColors.ink2)),
            const VGap.l(),
            VPrimaryButton(
              label: 'Mit Träwelling anmelden',
              onTap: () {
                session.updateSettings(const MePatch(traewellingLinked: true));
                Navigator.of(ctx).pop();
                showSnack(context, 'Vorführung: Verbindung folgt.');
              },
            ),
            const VGap.xs(),
            VGhostButton(label: 'Nicht jetzt', onTap: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    );
  }

  void _pickTicket(BuildContext context, Session session, TicketType current) {
    showVSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: VSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VSheetHeader(title: 'Dein Ticket', subtitle: 'Bestimmt, was eine Verspätung wert ist'),
            Padding(
              padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.s, VSpace.page, 0),
              child: Column(
                children: [
                  for (final t in TicketType.values) ...[
                    VChoiceCard(
                      title: t.label,
                      subtitle: t.rule,
                      selected: current == t,
                      onTap: () {
                        session.updateSettings(MePatch(ticket: t));
                        Navigator.of(ctx).pop();
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pickNgo(BuildContext context, Session session, String current) {
    showVSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: VSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VSheetHeader(title: 'Dein Zweck', subtitle: 'Wohin die Bahn überweist'),
            Padding(
              padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.s, VSpace.page, 0),
              child: Column(
                children: [
                  for (final n in session.ngos) ...[
                    VChoiceCard(
                      title: n.name,
                      subtitle: n.tagline,
                      selected: current == n.id,
                      onTap: () {
                        session.updateSettings(MePatch(ngoId: n.id));
                        Navigator.of(ctx).pop();
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mutedStations(BuildContext context) {
    showVSheet(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.only(bottom: VSpace.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const VSheetHeader(title: 'Stumme Bahnhöfe', subtitle: 'Hier kommt nie ein Hinweis'),
              Padding(
                padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.s, VSpace.page, 0),
                child: Column(
                  children: [
                    for (final s in Mock.nearbyStations)
                      SwitchRow(
                        title: s.name,
                        subtitle: s.distanceLabel,
                        value: _muted.contains(s.name),
                        onChanged: (v) {
                          setState(() => v ? _muted.add(s.name) : _muted.remove(s.name));
                          setSheet(() {});
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _personalData(BuildContext context, Session session, ApiPersonalData? current) {
    final name = TextEditingController(text: current?.name ?? '');
    final address = TextEditingController(text: current?.address ?? '');
    final email = TextEditingController(text: current?.email ?? '');
    final ticketNo = TextEditingController(text: current?.ticketNumber ?? '');
    showVSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: VSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VSheetHeader(title: 'Persönliche Daten', subtitle: 'Stehen nur auf dem Formular'),
            Padding(
              padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.s, VSpace.page, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Name'), style: VText.body),
                  const VGap.s(),
                  TextField(controller: address, maxLines: 2, decoration: const InputDecoration(labelText: 'Anschrift'), style: VText.body),
                  const VGap.s(),
                  TextField(controller: email, decoration: const InputDecoration(labelText: 'Privates Postfach'), style: VText.body),
                  const VGap.s(),
                  TextField(controller: ticketNo, decoration: const InputDecoration(labelText: 'Deutschlandticket-Nummer'), style: VText.mono),
                  const VGap.m(),
                  VPrimaryButton(
                    label: 'Speichern',
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await session.savePersonalData(ApiPersonalData(
                        name: name.text.trim(),
                        address: address.text.trim(),
                        email: email.text.trim(),
                        ticketNumber: ticketNo.text.trim().isEmpty ? null : ticketNo.text.trim(),
                      ));
                      if (context.mounted) showSnack(context, session.error ?? 'Gespeichert. Steht nur auf dem Formular.');
                    },
                  ),
                  const SizedBox(height: 4),
                  VGhostButton(label: 'Daten löschen', color: VColors.red, onTap: () => Navigator.of(ctx).pop()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAll(BuildContext context, DemoState state, Session session) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VColors.paper,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
        title: Text('Alles löschen?', style: VText.h2),
        content: Text('Fahrten, Anträge, Abzeichen und deine Verspätomat-Adresse. Offene Anträge bei der Bahn laufen weiter, aber wir sehen die Antwort nicht mehr.', style: VText.bodyS),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('Abbrechen', style: VText.bodyStrong)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('Löschen', style: VText.bodyStrong.copyWith(color: VColors.red))),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await session.deleteEverything();
      if (!session.isLocal) state.reset();
      if (context.mounted) context.go(Routes.showcase);
    }
  }

  Future<void> _recoveryCode(BuildContext context, Session session) async {
    final code = await session.recoveryCode();
    if (!context.mounted) return;
    showVSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(VSpace.page, 0, VSpace.page, VSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VSheetHeader(title: 'Wiederherstellungscode', subtitle: 'Statt eines Kontos'),
            Text(
              'Verspätomat hat kein Konto. Dieser Code holt dein Konto, deine Fahrten und deine Verspätomat-Adresse auf ein neues Gerät. Mach einen Screenshot.',
              style: VText.body,
            ),
            const VGap.m(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(VSpace.m),
              decoration: BoxDecoration(border: Border.all(color: VColors.ink, width: 1.5), borderRadius: BorderRadius.circular(4)),
              child: Text(code ?? (session.error ?? 'Kein Code verfügbar.'), style: VText.mono.copyWith(fontSize: 18)),
            ),
            const VGap.l(),
            VPrimaryButton(label: 'Verstanden', onTap: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context, Session session) async {
    try {
      final json = await session.repo.exportMe();
      if (context.mounted) showSnack(context, 'Export: ${json.length} Zeichen. Der Download folgt.');
    } catch (e) {
      if (context.mounted) showSnack(context, 'Export fehlgeschlagen: $e');
    }
  }
}
