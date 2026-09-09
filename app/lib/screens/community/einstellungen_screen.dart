import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart';
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
            subtitle: state.ticket.label,
            chevron: true,
            onTap: () => _pickTicket(context, state),
          ),
          VListRow(
            title: 'Zweck',
            subtitle: state.ngo.name,
            chevron: true,
            onTap: () => _pickNgo(context, state),
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
              selected: state.locationMode == m,
              onTap: () => state.setLocationMode(m),
            ),
          const VGap.xl(),
          const VSection('Anträge'),
          VListRow(
            title: 'Persönliche Daten für Anträge',
            subtitle: '${Mock.userName} · ${Mock.ticketNumber}',
            chevron: true,
            onTap: () => _personalData(context),
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
                Text(Mock.relayAddress, style: VText.mono),
                const SizedBox(height: 8),
                Text(
                  'Deine Anträge gehen von hier raus. Antworten der Bahn landen hier und sofort auch in deinem Postfach (${Mock.userEmail}). Wir lesen Status, Betrag und Aktenzeichen, mehr nicht.',
                  style: VText.caption,
                ),
              ],
            ),
          ),
          const VGap.s(),
          SwitchRow(
            title: 'Korrespondenz nach Abschluss behalten',
            subtitle: 'Sonst bleibt nur der Eintrag im Konto',
            value: state.keepCorrespondence,
            onChanged: state.setKeepCorrespondence,
          ),
          VListRow(title: 'Alle Mails exportieren', subtitle: 'Gesendet und empfangen, als Archiv', chevron: true, onTap: () => showSnack(context, 'Archiv wird erstellt. Du bekommst einen Link per Mail.')),
          const VGap.xl(),
          const VSection('Konto'),
          VListRow(
            title: 'Anmelden',
            subtitle: 'Optional. Für Backup und Teams.',
            chevron: true,
            onTap: () => showSnack(context, 'In der Vorführung gibt es kein Konto. Alles bleibt auf dem Gerät.'),
          ),
          SwitchRow(title: 'Mich in Ranglisten zeigen', subtitle: 'Ohne dich bleiben die Listen trotzdem da', value: state.showOnBoards, onChanged: state.setShowOnBoards),
          const VGap.xl(),
          const VSection('Deine Daten'),
          VListRow(title: 'Daten exportieren', subtitle: 'Alles, was wir über dich haben', chevron: true, onTap: () => showSnack(context, 'Export wird erstellt.')),
          VListRow(title: 'Alles löschen', subtitle: 'Konto, Fahrten, Anträge, Adresse', chevron: true, onTap: () => _deleteAll(context, state)),
          VListRow(title: 'Woher kommen die Daten?', subtitle: 'Jede Zahl und ihre Quelle', chevron: true, onTap: () => context.push(Routes.datenherkunft)),
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

  void _pickTicket(BuildContext context, DemoState state) {
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
                      selected: state.ticket == t,
                      onTap: () {
                        state.setTicket(t);
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

  void _pickNgo(BuildContext context, DemoState state) {
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
                  for (final n in Mock.ngos) ...[
                    VChoiceCard(
                      title: n.name,
                      subtitle: n.tagline,
                      selected: state.ngoId == n.id,
                      onTap: () {
                        state.setNgo(n.id);
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

  void _personalData(BuildContext context) {
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
                  TextFormField(initialValue: Mock.userName, decoration: const InputDecoration(labelText: 'Name'), style: VText.body),
                  const VGap.s(),
                  TextFormField(initialValue: Mock.userAddress, maxLines: 2, decoration: const InputDecoration(labelText: 'Anschrift'), style: VText.body),
                  const VGap.s(),
                  TextFormField(initialValue: Mock.userEmail, decoration: const InputDecoration(labelText: 'Privates Postfach'), style: VText.body),
                  const VGap.s(),
                  TextFormField(initialValue: Mock.ticketNumber, decoration: const InputDecoration(labelText: 'Deutschlandticket-Nummer'), style: VText.mono),
                  const VGap.m(),
                  VPrimaryButton(
                    label: 'Speichern',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      showSnack(context, 'Gespeichert. Nur auf diesem Gerät.');
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

  Future<void> _deleteAll(BuildContext context, DemoState state) async {
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
      state.reset();
      context.go(Routes.showcase);
    }
  }
}
