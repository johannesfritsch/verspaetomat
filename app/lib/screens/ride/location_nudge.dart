import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../platform/geofence.dart';
import '../../platform/geofence_sync.dart';
import '../../repo/repo_scope.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart' show openLocationSettings;

/// Asks, once and gently, for the location permission the reminder at the station needs (#18).
///
/// The reminder — „Du stehst am Bahnsteig, check ein" — only works when the phone may notice a
/// station while the app is closed, which is the permission „Immer". Many people grant „Beim
/// Verwenden" in the first dialog and never learn what that costs them: a check-in forgotten on
/// exactly the day the train is an hour late.
///
/// So Home carries a small card while the phone has not granted „Immer", whatever the passenger
/// chose in the app — „Nie" included, because that choice was made before anybody explained what
/// it switches off. The card opens a sheet that explains. The permission is read again every time
/// the app comes to the foreground, so granting it in the system settings makes the card go away
/// by itself.
///
/// #48: it came back too often and had no way to say no for good. The sheet now ends in the three
/// answers there are, in these words: „Immer aktivieren", „Nächstes Mal erinnern" (the card rests
/// for [snooze]) and „Nicht mehr fragen" (the card never comes back on this device). The card's ×
/// is the middle one — a stray tap on a small cross is not a decision for ever.
class LocationNudge extends ChangeNotifier with WidgetsBindingObserver {
  LocationNudge(this.session) {
    WidgetsBinding.instance.addObserver(this);
    check();
  }

  final Session session;
  static const _dismissedKey = 'location_nudge_dismissed';
  static const _snoozedUntilKey = 'location_nudge_snoozed_until';

  /// How long „Nächstes Mal erinnern" keeps the card away.
  static const snooze = Duration(days: 7);

  GeofencePermission? _permission;
  bool _disposed = false;

  /// Read once per foreground; null until the first answer.
  GeofencePermission? get permission => _permission;

  bool get dismissed => session.prefs.getBool(_dismissedKey) ?? false;

  /// Until when „Nächstes Mal erinnern" keeps the card away; null when it does not.
  DateTime? get snoozedUntil {
    final raw = session.prefs.getString(_snoozedUntilKey);
    final t = raw == null ? null : DateTime.tryParse(raw);
    return t != null && t.isAfter(DateTime.now()) ? t : null;
  }

  /// The card shows while the phone has not granted „Immer" and nobody has closed it. Never under
  /// automation: the tour and the end-to-end tests run on simulators that never have it.
  bool get visible =>
      !GeofenceSync.automation && !dismissed && snoozedUntil == null && _permission != null && _permission != GeofencePermission.always;

  Future<void> check() async {
    final status = await Geofence.instance.status();
    if (_disposed) return;
    if (status.permission != _permission) {
      _permission = status.permission;
      notifyListeners();
    }
  }

  /// „Nicht mehr fragen": gone for good on this device.
  Future<void> dismiss() async {
    await session.prefs.setBool(_dismissedKey, true);
    notifyListeners();
  }

  /// „Nächstes Mal erinnern", and the card's ×: back after [snooze].
  Future<void> remindLater({DateTime? now}) async {
    await session.prefs.setString(_snoozedUntilKey, (now ?? DateTime.now()).add(snooze).toIso8601String());
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// The card on Home: a corner of the platform drawing, one sentence, and the ×.
class LocationNudgeCard extends StatelessWidget {
  const LocationNudgeCard({super.key, required this.onOpen, required this.onDismiss});
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return VCard(
      key: const Key('location-nudge-card'),
      padding: EdgeInsets.zero,
      onTap: onOpen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VRadius.lg),
        // At least the drawing's height, taller when the words wrap: a fixed height clipped the
        // second line of the explanation on a narrow phone.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 112),
          child: Stack(
            children: [
              // The drawing the check-in opens on — canopy, train, the red sun — cropped to the
              // corner where the train stands, fading into the card towards the words.
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: 150,
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.transparent, Colors.black],
                    stops: [0, 0.45],
                  ).createShader(rect),
                  child: Image.asset(
                    'assets/header/checkin-platform.webp',
                    fit: BoxFit.cover,
                    alignment: const Alignment(0.95, -0.42),
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              // The pin, over the drawing: what the card is about, in one mark.
              const Positioned(
                right: 18,
                bottom: 14,
                child: VIconBadge(icon: Icons.near_me, tone: VBadgeTone.red, size: VControl.badgeSmall),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(VSpace.card, VSpace.cardTight, 120, VSpace.cardTight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('HINWEIS AM BAHNHOF', style: VText.eyebrow.copyWith(color: VColors.red)),
                    const SizedBox(height: 4),
                    Text('Nie mehr vergessen einzuchecken', style: VText.title, maxLines: 2),
                    const SizedBox(height: 2),
                    Text('Mit Standort „Immer" erinnert dich dein Telefon am Bahnsteig.', style: VText.bodyS.copyWith(color: VColors.ink2), maxLines: 2),
                  ],
                ),
              ),
              // On a light disc: the corner of the drawing behind it is sky, sun or canopy.
              Positioned(
                top: 6,
                right: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: VColors.paperElevated.withValues(alpha: 0.85), shape: BoxShape.circle),
                  child: VIconButton(key: const Key('location-nudge-dismiss'), icon: Icons.close, color: VColors.ink2, onTap: onDismiss),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sheet behind the card: why, what it does and does not do, and the one action.
Future<void> showLocationNudgeSheet(BuildContext context, LocationNudge nudge) {
  return showVSheet<void>(context, builder: (_) => _LocationNudgeSheet(nudge: nudge));
}

class _LocationNudgeSheet extends StatefulWidget {
  const _LocationNudgeSheet({required this.nudge});
  final LocationNudge nudge;

  @override
  State<_LocationNudgeSheet> createState() => _LocationNudgeSheetState();
}

class _LocationNudgeSheetState extends State<_LocationNudgeSheet> {
  bool _busy = false;

  /// The system will not ask again: iOS shows its „Immer" dialog once, Android never as a dialog.
  /// From then on the only way is the app's page in the phone's settings.
  bool _needsSettings = false;

  Future<void> _allow() async {
    setState(() => _busy = true);
    final session = widget.nudge.session;
    // Asking for „Immer" is choosing the reminder, so the app's own setting follows: without it
    // the phone would grant the permission and the app would still not watch any station.
    if (session.me?.settings.locationMode != LocationMode.always) {
      await session.updateSettings(const MePatch(locationMode: LocationMode.always));
    }
    final granted = await GeofenceSync.requestFor(LocationMode.always);
    await widget.nudge.check();
    if (!mounted) return;
    if (granted == GeofencePermission.always) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _needsSettings = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned(left: 0, right: 0, top: 0, bottom: -VSpace.l, child: ClipRect(child: VSheetScene(art: VSheetSceneArt.platform))),
              const VSheetHeader(
                eyebrow: 'Hinweis am Bahnhof',
                title: 'Dein Telefon denkt ans Einchecken',
                subtitle: 'Damit die Verspätung zählt, auch wenn du nicht an die App denkst.',
                narrow: true,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.sheet),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VGap.m(),
                const _Point(
                  icon: Icons.train,
                  title: 'Am Bahnsteig erinnert',
                  body: 'Stehst du an einem deiner Bahnhöfe, merkt es dein Telefon und fragt, ob du gleich fährst. So geht keine Verspätung verloren, nur weil du nicht eingecheckt hast.',
                ),
                const VGap.md(),
                const _Point(
                  icon: Icons.lock_outline,
                  title: 'Kein Standortverlauf',
                  body: 'Dein Telefon kennt nur die Bahnhöfe, nicht deinen Weg. Während der Fahrt folgen wir dem Zug, nicht dir. Abschalten kannst du es jederzeit in den Einstellungen.',
                ),
                const VGap.md(),
                const _Point(
                  icon: Icons.near_me,
                  title: 'Dafür braucht es „Immer"',
                  body: 'Nur mit der Standortfreigabe „Immer" darf das Telefon einen Bahnhof bemerken, während die App geschlossen ist.',
                ),
                const VGap.l(),
                if (_needsSettings) ...[
                  VCard(
                    tone: VCardTone.sunken,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Dein Telefon fragt nicht noch einmal.', style: VText.bodyStrong),
                        const VGap.xs(),
                        Text('In den Einstellungen für Verspätomat: Standort → Immer.', style: VText.bodyS.copyWith(color: VColors.ink2)),
                      ],
                    ),
                  ),
                  const VGap.m(),
                  VPrimaryButton(label: 'Zu den Einstellungen', trailingIcon: Icons.open_in_new, onTap: openLocationSettings),
                ] else
                  VPrimaryButton(label: 'Immer aktivieren', trailingIcon: Icons.near_me, onTap: _busy ? null : _allow),
                const VGap.s(),
                VGhostButton(
                  key: const Key('location-nudge-later'),
                  label: 'Nächstes Mal erinnern',
                  onTap: () {
                    widget.nudge.remindLater();
                    Navigator.of(context).pop();
                  },
                ),
                VGhostButton(
                  key: const Key('location-nudge-never'),
                  label: 'Nicht mehr fragen',
                  color: VColors.ink2,
                  onTap: () {
                    widget.nudge.dismiss();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VIconBadge(icon: icon, tone: VBadgeTone.neutral, size: VControl.badgeSmall, iconColor: VColors.ink),
        const SizedBox(width: VSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: VText.bodyStrong),
              const SizedBox(height: 2),
              Text(body, style: VText.bodyS.copyWith(color: VColors.ink2)),
            ],
          ),
        ),
      ],
    );
  }
}
