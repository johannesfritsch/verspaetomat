import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../mock/mock_data.dart';
import '../../platform/geofence_sync.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../../content/legal.dart';
import 'community_widgets.dart';

/// Einstellungen & Datenschutz.
class EinstellungenScreen extends StatefulWidget {
  const EinstellungenScreen({super.key});

  @override
  State<EinstellungenScreen> createState() => _EinstellungenScreenState();
}

class _EinstellungenScreenState extends State<EinstellungenScreen> {
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

    return VScreen(
      title: 'Einstellungen',
      eyebrow: 'Dein Verspätomat',
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
            subtitle: locationMode == LocationMode.always ? 'Nach etwa einer Minute an einem deiner Bahnhöfe' : 'Nur solange die App offen ist',
            value: settings?.nudgeEnabled ?? state.nudgeEnabled,
            onChanged: (v) => session.updateSettings(MePatch(nudgeEnabled: v)),
          ),
          SwitchRow(
            title: 'Ruhezeiten',
            subtitle: (settings?.quietHours ?? state.quietHours) ? '${settings?.quietFrom ?? '22:00'} bis ${settings?.quietTo ?? '06:00'} kein Hinweis' : 'Hinweis rund um die Uhr',
            value: settings?.quietHours ?? state.quietHours,
            onChanged: (v) => session.updateSettings(MePatch(quietFrom: v ? '22:00' : '', quietTo: v ? '06:00' : '')),
          ),
          VListRow(
            title: 'Stumme Bahnhöfe',
            subtitle: session.mutedStations.isEmpty ? 'Keine' : session.mutedStations.map((m) => m.name).join(', '),
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
              onTap: () async {
                await session.updateSettings(MePatch(locationMode: m));
                await GeofenceSync.requestFor(m);
              },
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
            title: 'Name',
            subtitle: displayName(me) == null ? 'Noch keiner. So heißt du in Ranglisten.' : '${displayName(me)} · in Ranglisten und auf dem Ich-Screen',
            chevron: true,
            onTap: () => _editNickname(context, session, me?.nickname ?? ''),
          ),
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
          const VSection('Rechtliches'),
          for (final d in legalDocs)
            VListRow(
              title: d.title,
              subtitle: switch (d.id) { 'impressum' => 'Wer hinter der App steht', 'datenschutz' => 'Was wir speichern und wie lange', _ => 'Bote, nicht Vertreter' },
              chevron: true,
              onTap: () => context.push(Routes.rechtliches(d.id)),
            ),
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

  void _editNickname(BuildContext context, Session session, String current) {
    final c = TextEditingController(text: current == 'Fahrgast' ? '' : current);
    showVSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(VSpace.page, 0, VSpace.page, VSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VSheetHeader(title: 'Dein Name', subtitle: 'Für Ranglisten und den Ich-Screen. Kein Klarname nötig.'),
            TextField(
              controller: c,
              autofocus: true,
              maxLength: 24,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'z. B. Johannes oder Gleis7'),
              style: VText.body,
            ),
            const VGap.m(),
            VPrimaryButton(
              label: 'Speichern',
              onTap: () async {
                Navigator.of(ctx).pop();
                await session.updateSettings(MePatch(nickname: c.text.trim()));
                if (context.mounted) showSnack(context, session.error ?? 'Gespeichert.');
              },
            ),
          ],
        ),
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
      builder: (ctx) => ListenableBuilder(
        listenable: RepoScope.of(context),
        builder: (ctx, _) {
          final session = RepoScope.of(context);
          final muted = session.mutedStations;
          return Padding(
            padding: const EdgeInsets.only(bottom: VSpace.l),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VSheetHeader(title: 'Stumme Bahnhöfe', subtitle: 'Hier kommt nie ein Hinweis'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.s, VSpace.page, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (muted.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: VSpace.s),
                          child: Text('Kein Bahnhof stumm. Du kannst einen direkt am Hinweis stummschalten oder hier suchen.', style: VText.caption),
                        )
                      else
                        for (final m in muted)
                          VListRow(
                            title: m.name,
                            trailing: VIconButton(icon: Icons.close, color: VColors.ink2, onTap: () => session.unmuteStation(m.id)),
                          ),
                      VListRow(
                        title: 'Bahnhof hinzufügen',
                        subtitle: 'Bahnhof suchen und stummschalten',
                        leading: const Icon(Icons.search, size: 20, color: VColors.ink),
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          await _addMutedStation(context);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Search a station and mute it. Same search the Bahnsteig uses.
  Future<void> _addMutedStation(BuildContext context) async {
    final session = RepoScope.read(context);
    final picked = await showVSheet<ApiStation>(
      context,
      expand: true,
      builder: (ctx) => _StationSearchSheet(search: session.repo.searchStations),
    );
    if (picked == null || !context.mounted) return;
    await session.muteStation(ApiMutedStation(id: picked.id, name: picked.name));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${picked.name} bleibt still.')));
    _mutedStations(context);
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

/// Debounced station search; pops with the chosen station.
class _StationSearchSheet extends StatefulWidget {
  const _StationSearchSheet({required this.search});
  final Future<List<ApiStation>> Function(String) search;

  @override
  State<_StationSearchSheet> createState() => _StationSearchSheetState();
}

class _StationSearchSheetState extends State<_StationSearchSheet> {
  final _controller = TextEditingController();
  List<ApiStation> _results = const [];
  bool _busy = false;
  String? _error;
  int _seq = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onChanged(String q) async {
    final seq = ++_seq;
    if (q.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (seq != _seq || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.search(q.trim());
      if (seq != _seq || !mounted) return;
      setState(() => _results = r);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Suche fehlgeschlagen. Erneut versuchen.');
    } finally {
      if (mounted && seq == _seq) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VSheetHeader(title: 'Bahnhof stummschalten', subtitle: 'Hier kommt dann nie ein Hinweis'),
        Padding(
          padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.s, VSpace.page, VSpace.s),
          child: TextField(
            controller: _controller,
            autofocus: true,
            onChanged: _onChanged,
            decoration: const InputDecoration(hintText: 'Bahnhof suchen', prefixIcon: Icon(Icons.search, color: VColors.ink3)),
          ),
        ),
        if (_busy) const Padding(padding: EdgeInsets.symmetric(horizontal: VSpace.page), child: Text('Sucht …', style: TextStyle(color: VColors.ink2))),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: VSpace.page), child: Text(_error!, style: VText.caption.copyWith(color: VColors.red))),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
            children: [
              for (final s in _results) VListRow(title: s.name, onTap: () => Navigator.of(context).pop(s)),
            ],
          ),
        ),
      ],
    );
  }
}
