import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/models.dart';
import '../../platform/diagnose_log.dart';
import '../../platform/geofence.dart';
import '../../platform/geofence_replay.dart';
import '../../repo/repo_scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/geofence_map.dart';
import '../../widgets/kit.dart';
import '../ride/ride_widgets.dart' show ErrorLine, fmtDay, fmtLocal, shortError;

/// `Entwicklung` (docs/25 §5): what the geofence layer is actually doing, read from the phone.
///
/// It exists so a question like "why no nudge at Memmingen?" can be answered where it happened
/// rather than guessed at from a laptop. Nothing here leaves the phone by itself, and the log
/// holds paths, not bodies: it must stay safe to paste into a message.
///
/// **It is in every build, including a release one** (issue #29). It used to be hidden unless
/// `--dart-define=DEBUG_PAGE=1` was passed, which `tools/release.sh` has never done — so the page
/// shipped inside every TestFlight build with no way to reach it, which is the whole of "I cannot
/// find it in the current build". Showing it is safe: there is no write control on it in any
/// form, and the app has no admin surface to expose. The workshop tools that change what the app
/// *is* — switching backend, the demo toys, the Showcase — stay behind `kDebugMode` in their own
/// block in `einstellungen_screen.dart`.
class EntwicklungScreen extends StatefulWidget {
  const EntwicklungScreen({super.key});

  @override
  State<EntwicklungScreen> createState() => _EntwicklungScreenState();
}

class _EntwicklungScreenState extends State<EntwicklungScreen> {
  GeofenceStatus? _status;
  ApiGeofence _geofence = ApiGeofence.empty;
  List<LogLine> _log = const [];
  List<GeofenceDay> _history = const [];
  String _filter = 'alle';
  bool _loading = true;
  String? _error;

  /// The station the map is filled with, or null for the whole set.
  String? _focusId;

  /// Which replayed event the map is showing, as an index into [_replay]. Null is "now".
  int? _replayAt;

  /// Built once per load, not per frame: the join is every log line against every region, and it
  /// would otherwise run several times for each pixel the replay slider moves.
  GeofenceReplay _replay = const GeofenceReplay(events: [], unplaceable: 0);

  /// A timestamp on this page can be hours or days old, and the question the page exists for is
  /// exactly how stale it is — so anything not from today carries its date. `fmtLocal` alone
  /// renders a disc set last Tuesday as „07:12", which reads as this morning.
  static String _stamp(DateTime? d) {
    if (d == null) return '–';
    final l = d.toLocal(), now = DateTime.now();
    final sameDay = l.year == now.year && l.month == now.month && l.day == now.day;
    return sameDay ? fmtLocal(l) : '${fmtDay(l)} ${fmtLocal(l)}';
  }

  /// Today as native writes its counter keys, so „Die Tage davor" can leave it out by name.
  static String get _today {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static const _sources = ['alle', 'geofence', 'http', 'push', 'app'];

  /// The five counters, in the order docs/25 §5 lists them, with the labels the table uses.
  static const _counterNames = <String, String>{
    'requests': 'Anfragen',
    'nearby': 'nearby',
    'scheduled': 'geplant',
    'fired': 'ausgelöst',
    'cancelled': 'abgebrochen',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // The repo is taken before the first await: the context must not be read across one.
      final repo = RepoScope.read(context).repo;
      final status = await Geofence.instance.status();
      final native = await Geofence.instance.readLog();
      final history = await Geofence.instance.countersHistory(days: 8);
      final geo = await repo.geofence().catchError((_) => ApiGeofence.empty);
      if (!mounted) return;
      setState(() {
        _status = status;
        _geofence = geo;
        _log = DiagnoseLog.instance.merged(native);
        _history = history;
        _replay = GeofenceReplay.place(status.regions, _log);
        // The log is a ring: a reload can drop the line the replay was sitting on.
        if (_replayAt != null && _replayAt! >= _replay.events.length) _replayAt = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = shortError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clearLog() async {
    DiagnoseLog.instance.clear();
    await Geofence.instance.clearLog();
    await _load();
  }

  Future<void> _copyAll() async {
    final text = _visible.map((l) => l.plainWithDate).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_visible.length} Zeilen kopiert.')),
      );
    }
  }

  List<LogLine> get _visible =>
      _filter == 'alle' ? _log : _log.where((l) => l.source == _filter).toList();

  /// The event the map is currently showing, if the index still points at one.
  GeofencePlacedEvent? _replayed() {
    final i = _replayAt;
    if (i == null || i < 0 || i >= _replay.events.length) return null;
    return _replay.events[i];
  }

  /// The station the map is filled with, if it is still in the set after a reload.
  GeofenceRegion? _focused(GeofenceStatus s) {
    for (final r in s.regions) {
      if (r.id == _focusId && r.hasPosition) return r;
    }
    return null;
  }

  /// What the picture is and, more importantly, what it is not.
  ///
  /// Every clause is conditional on purpose: naming a dashed disc on a page that has no disc, or
  /// inviting a tap where nothing is tappable, is the small kind of lie a diagnostics page cannot
  /// afford — it sends someone looking for a thing that was never drawn.
  String _mapCaption(GeofenceStatus s) {
    final focused = _focused(s);
    if (focused != null) {
      return [
        '${focused.name}: der überwachte Kreis, gestrichelt der Abstand, ab dem ein Hinweis '
            'geplant wird.',
        // The crosshair is still painted at this scale when the disc centre falls inside the
        // frame, so the sentence that says what it is cannot be dropped with the disc.
        if (s.disc != null) 'Ein Kreuz wäre die Mitte der Scheibe — nicht dein Standort jetzt.',
        'Tippe die Region unten noch einmal an für den ganzen Satz.',
      ].join(' ');
    }
    final unplaced = s.regions.where((r) => !r.hasPosition).length;
    final tappable = s.regions.any((r) => !r.isUmbrella && r.hasPosition);
    final dashed = <String>[
      if (s.disc != null) 'die Scheibe',
      if (s.regions.any((r) => r.isUmbrella && r.hasPosition)) 'der Schirm',
    ];
    return [
      'Jeder Punkt ist eine überwachte Region; wo der Maßstab es hergibt, ist ihr Kreis '
          'mitgezeichnet.',
      if (dashed.length == 1) 'Gestrichelt ${dashed.single} — auch nur, wo der Maßstab es hergibt.',
      if (dashed.length == 2)
        'Gestrichelt ${dashed.first} und ${dashed.last} — beide nur, wo der Maßstab sie hergibt.',
      if (s.disc != null)
        'Das Kreuz ist die Mitte der Scheibe: der letzte Ort, an dem das Telefon eine Bewegung '
            'bemerkt hat${s.disc!.at == null ? '' : ' (${_stamp(s.disc!.at)})'} — nicht dein Standort jetzt.',
      if (_replayAt != null)
        'Hell markiert ist der Bahnhof, an dem die unten gewählte Zeile passiert ist — nicht, wo '
            'das Telefon jetzt ist.'
      else if (s.regions.any((r) => r.inside))
        'Hell markiert ist der Kreis, in dem das Telefon nach dem letzten bekannten Ort steht.',
      if (unplaced == 1) 'Eine Region ohne Koordinaten ist nicht gezeichnet.',
      if (unplaced > 1) '$unplaced Regionen ohne Koordinaten sind nicht gezeichnet.',
      if (tappable) 'Tippe unten eine Region an, um sie von nahem zu sehen.',
    ].join(' ');
  }

  Future<void> _refreshNow() async {
    final result = await Geofence.instance.refreshNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          GeofenceRefresh.started => 'Suche läuft. Das braucht einen Moment — dann „Neu laden“.',
          GeofenceRefresh.denied => 'Ohne Standort-Berechtigung gibt es nichts zu suchen.',
          GeofenceRefresh.off => 'Nichts zu suchen: der Hintergrund-Scan ist aus.',
          // The one case worth spelling out: it is not a failure, it is the layer already doing
          // the thing this button would have started.
          GeofenceRefresh.busy => 'Gerade läuft schon etwas — das wird nicht unterbrochen.',
          GeofenceRefresh.unavailable => 'Auf diesem Gerät gibt es die Hintergrund-Schicht nicht.',
        }),
      ),
    );
  }

  Future<void> _testNudge() async {
    final scheduled = await Geofence.instance.testNudge();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(scheduled
            ? 'Testhinweis in 10 Sekunden. Sperr den Bildschirm.'
            : 'Das System hat den Hinweis abgelehnt — sieh oben bei „Mitteilungen“ nach.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final session = RepoScope.of(context);
    return VScreen(
      eyebrow: 'Nur für uns',
      title: 'Entwicklung',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.s(),
          if (_loading && s == null) const VSkeletonList(rows: 4, trailing: false),
          if (_error != null) ErrorLine(message: _error!, onRetry: _load),
          if (s != null) ...[
            const VSection('Status'),
            _Row('Berechtigung', s.permission.name),
            _Row('Mitteilungen', s.notifications ? 'erlaubt' : 'aus'),
            _Row('Hintergrund-Scan', _scanningLine(s, session)),
            _Row('Regionen', '${s.registered} registriert'),
            if (_geofence.snoozeUntil != null)
              _Row('Pause bis', fmtLocal(_geofence.snoozeUntil)),
            if (_geofence.idle)
              _Row('Ruhend', 'seit 30 Tagen kein Check-in'),
            const VGap.m(),

            // The set, drawn (issue #29). A picture finds in a second what a list of coordinates
            // hides: a disc around the wrong town, a station nowhere near the others, a circle
            // that does not reach the platform you are standing on.
            const VSection('Karte'),
            const VGap.xs(),
            VGeofenceMap(
              regions: s.regions,
              disc: s.disc,
              focus: _focused(s),
              highlightId: _replayed()?.regionId,
              height: 240,
            ),
            const VGap.xs(),
            Text(_mapCaption(s), style: VText.caption),
            if (_focusId != null) ...[
              const VGap.s(),
              VOutlineButton(
                label: 'Ganzen Satz zeigen',
                icon: Icons.zoom_out_map,
                onTap: () => setState(() => _focusId = null),
              ),
            ],
            const VGap.m(),

            // „Der Zustand zu verschiedenen Zeiten" (issue #29): the log, walked one event at a
            // time, with the station it happened at lit on the map above.
            _Replay(
              events: _replay.events,
              unplaceable: _replay.unplaceable,
              at: _replayAt,
              stamp: _stamp,
              onChanged: (i) => setState(() {
                _replayAt = i;
                // A replay is about the whole set; staying zoomed into one station would hide
                // every event that happened anywhere else.
                if (i != null) _focusId = null;
              }),
            ),
            const VGap.m(),

            // The three radii the whole layer is made of. They decide everything and are named
            // nowhere else in the app (issue #29).
            const VSection('Zäune'),
            _Row('Schirm', '${(GeofenceConfig.defaultUmbrellaRadiusM / 1000).round()} km'),
            _Row('Bahnhofskreis', '${GeofenceConfig.defaultStationRadiusM} m'),
            _Row('Hinweis ab', '${GeofenceConfig.defaultNudgeRadiusM} m'),
            const VGap.xs(),
            Text(
              'Der Schirm weckt die App, wenn du ihn verlässt, und der Satz wird neu gezogen. Der '
              'Bahnhofskreis ist absichtlich weit — kleine Kreise meldet iOS spät oder gar nicht. '
              'Der Hinweis kommt erst, wenn ein Standort wirklich so nah liegt.',
              style: VText.caption,
            ),
            const VGap.m(),

            // The coverage disc (docs/25 §1): the thing that decides how often we ask the backend.
            const VSection('Abdeckung'),
            if (s.disc == null)
              _Row('Scheibe', 'noch keine')
            else ...[
              _Row('Mitte', '${s.disc!.lat.toStringAsFixed(4)}, ${s.disc!.lon.toStringAsFixed(4)}'),
              _Row('Radius', '${(s.disc!.radiusM / 1000).round()} km · ${s.disc!.band}'),
              _Row('Gesetzt', _stamp(s.disc!.at)),
            ],
            const VGap.m(),

            // Counters since midnight, so the traffic table in docs/25 is falsifiable on a trip.
            const VSection('Heute'),
            _Row('Backend-Anfragen', '${s.counters['requests'] ?? 0}'),
            _Row('stations/nearby', '${s.counters['nearby'] ?? 0}'),
            _Row('Hinweise geplant', '${s.counters['scheduled'] ?? 0}'),
            _Row('… ausgelöst', '${s.counters['fired'] ?? 0}'),
            _Row('… abgebrochen', '${s.counters['cancelled'] ?? 0}'),
            if ((s.counters['refused'] ?? 0) > 0) _Row('Von iOS abgelehnt', '${s.counters['refused']}'),
            const VGap.m(),

            // The days before today (issue #29). Nothing new is recorded for this: the counters
            // have always been written one key per day and never deleted, so this is history the
            // phone already had and could not show.
            if (_history.any((d) => d.day != _today)) ...[
              const VSection('Die Tage davor'),
              const VGap.xs(),
              _HistoryTable(days: _history, names: _counterNames, today: _today),
              const VGap.xs(),
              Text(
                'Ein Tag ohne Zeile ist ein Tag, an dem die Hintergrund-Schicht nichts zu tun '
                'hatte — meistens, weil das Telefon die Scheibe nicht verlassen hat. Das ist der '
                'normale Tag zu Hause, kein Fehler. Wo das Telefon war, steht in dieser Tabelle '
                'nicht: nur, wie oft gefragt und gemeldet wurde.',
                style: VText.caption,
              ),
              const VGap.m(),
            ],

            if (s.regions.isNotEmpty) ...[
              VSection('Regionen', trailing: Text('${s.regions.length}', style: VText.caption)),
              for (final r in s.regions)
                _RegionRow(
                  region: r,
                  selected: r.id == _focusId,
                  // The umbrella has no inside to look at, and a region without coordinates
                  // cannot be shown on the map at all.
                  onTap: r.isUmbrella || !r.hasPosition
                      ? null
                      : () => setState(() => _focusId = r.id == _focusId ? null : r.id),
                ),
              const VGap.m(),
            ],
          ],

          // The log itself.
          VSection('Log', trailing: Text('${_visible.length}', style: VText.caption)),
          const VGap.xs(),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in _sources)
                _FilterChip(label: f, selected: _filter == f, onTap: () => setState(() => _filter = f)),
            ],
          ),
          const VGap.s(),
          Container(
            key: const Key('diagnose-log'),
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: VColors.rule), borderRadius: BorderRadius.circular(4)),
            child: _visible.isEmpty
                ? Text('Noch nichts aufgezeichnet.', style: VText.caption)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final l in _visible.reversed.take(120))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(l.plain, style: VText.mono),
                        ),
                    ],
                  ),
          ),
          const VGap.m(),
          Row(
            children: [
              Expanded(child: VOutlineButton(label: 'Alles kopieren', icon: Icons.copy_all, onTap: _copyAll)),
              const SizedBox(width: 8),
              Expanded(child: VOutlineButton(label: 'Log leeren', icon: Icons.delete_outline, onTap: _clearLog)),
            ],
          ),
          const VGap.s(),
          Row(
            children: [
              Expanded(child: VOutlineButton(label: 'Neu laden', icon: Icons.refresh, onTap: _load)),
            ],
          ),
          const VGap.xl(),

          // The two actions docs/25 §5 promised and nobody built (issue #29). They exist so the
          // fence can be tested where it runs — on a platform, from a shipped build.
          const VSection('Ausprobieren'),
          const VGap.xs(),
          Row(
            children: [
              Expanded(child: VOutlineButton(label: 'Jetzt neu suchen', icon: Icons.my_location, onTap: _refreshNow)),
              const SizedBox(width: 8),
              Expanded(child: VOutlineButton(label: 'Testhinweis', icon: Icons.notifications_active_outlined, onTap: _testNudge)),
            ],
          ),
          const VGap.xs(),
          Text(
            '„Jetzt neu suchen“ holt einen frischen Standort und zieht den Satz neu — dasselbe, was '
            'sonst beim Verlassen des Schirms passiert. „Testhinweis“ schickt in zehn Sekunden eine '
            'Mitteilung an dieses Telefon, die nichts enthält und beim Antippen nichts tut: sie '
            'beantwortet nur, ob Hinweise hier überhaupt ankommen. Sperr den Bildschirm und warte.',
            style: VText.caption,
          ),
          const VGap.m(),
          Text(
            'Alles hier bleibt auf dem Telefon und geht von selbst nirgendwohin. Im Log stehen '
            'Pfade, keine Inhalte, und nichts aus einem Antrag. Es stehen aber Bahnhofsnamen mit '
            'Uhrzeit darin — „enter Köln Hbf“ —, weil genau das die Frage beantwortet, für die '
            'die Seite da ist. Die letzten 500 Zeilen sind leicht eine Reisewoche, und „Alles '
            'kopieren“ legt sie mit Datum in die Zwischenablage. Überleg dir also, an wen du das '
            'schickst, und „Log leeren“ ist daneben.',
            style: VText.caption,
          ),
          const VGap.xl(),
        ],
      ),
    );
  }

  /// Why background scanning is or is not happening, in one line — the question the page exists
  /// for. The phone comes first: the backend's `enabled` is permission to scan, not proof that
  /// anything is. Without the Always permission nothing runs whatever the account says, and a
  /// set with no regions registered is not watching anything either.
  String _scanningLine(GeofenceStatus s, Session session) {
    if (s.permission != GeofencePermission.always) {
      return 'aus · keine Hintergrund-Berechtigung (${s.permission.name})';
    }
    if (!s.notifications) return 'läuft · aber keine Mitteilungen erlaubt';
    if (session.nudgesSnoozed) return 'aus · pausiert';
    if (_geofence.idle) return 'aus · 30 Tage kein Check-in';
    if (!_geofence.enabled) return 'aus · im Konto abgeschaltet';
    if (s.registered == 0) return 'an · aber keine Region registriert';
    return 'an';
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(label, style: VText.bodyS.copyWith(color: VColors.ink2))),
          Expanded(child: Text(value, style: VText.bodySStrong)),
        ],
      ),
    );
  }
}

/// „Der Zustand zu verschiedenen Zeiten": the log walked one event at a time (issue #29).
///
/// No new data stands behind this; see [GeofenceReplay.place] for the join and what it cannot do.
/// Dragging the slider picks a line and lights that station on the map above, so a trip can be
/// read in the order the phone saw it.
class _Replay extends StatelessWidget {
  const _Replay({
    required this.events,
    required this.unplaceable,
    required this.at,
    required this.stamp,
    required this.onChanged,
  });

  final List<GeofencePlacedEvent> events;
  final int unplaceable;
  final int? at;
  final String Function(DateTime?) stamp;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VSection('Verlauf auf der Karte'),
          const VGap.xs(),
          Text(
            unplaceable == 0
                ? 'Noch keine Ereignisse im Log. Sobald der Hintergrund-Scan etwas meldet, lässt '
                    'sich der Verlauf hier Zeile für Zeile auf der Karte nachgehen.'
                : '$unplaceable Zeilen im Log, aber keine davon gehört zu einem Bahnhof, der '
                    'gerade registriert ist — wo die gewesen sind, weiß das Telefon nicht mehr.',
            style: VText.caption,
          ),
        ],
      );
    }

    final i = at == null ? events.length - 1 : at!.clamp(0, events.length - 1);
    final current = events[i];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VSection('Verlauf auf der Karte', trailing: Text('${events.length}', style: VText.caption)),
        const VGap.xs(),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: VColors.ink,
            inactiveTrackColor: VColors.rule,
            thumbColor: VColors.ink,
            overlayColor: VColors.pressedOverlay,
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            key: const Key('replay-slider'),
            value: i.toDouble(),
            min: 0,
            max: (events.length - 1).toDouble(),
            divisions: events.length > 1 ? events.length - 1 : null,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 92, child: Text(stamp(current.at), style: VText.bodySStrong)),
            Expanded(child: Text(current.text, style: VText.mono.copyWith(fontSize: 12))),
          ],
        ),
        const VGap.xs(),
        Row(
          children: [
            Expanded(
              child: VOutlineButton(
                label: 'Zurück',
                icon: Icons.chevron_left,
                onTap: () => onChanged((i - 1).clamp(0, events.length - 1)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: VOutlineButton(
                label: 'Weiter',
                icon: Icons.chevron_right,
                onTap: () => onChanged((i + 1).clamp(0, events.length - 1)),
              ),
            ),
          ],
        ),
        if (at != null) ...[
          const VGap.xs(),
          VOutlineButton(label: 'Verlauf verlassen', icon: Icons.close, onTap: () => onChanged(null)),
        ],
        const VGap.xs(),
        Text(
          [
            'Jede Zeile ist ein Ereignis aus dem Log, auf der Karte an seinem Bahnhof markiert. '
                'Gespeichert wurde dafür nichts Neues — nur, was der Hintergrund-Scan ohnehin '
                'notiert hat.',
            if (unplaceable == 1)
              'Eine weitere Zeile gehört zu keinem gerade registrierten Bahnhof und fehlt hier.',
            if (unplaceable > 1)
              '$unplaceable weitere Zeilen gehören zu keinem gerade registrierten Bahnhof und '
                  'fehlen hier.',
          ].join(' '),
          style: VText.caption,
        ),
      ],
    );
  }
}

/// One monitored region, with where it is and how wide (issue #29).
///
/// The list is the map's index: tapping a station fills the picture with it, which is the only
/// scale at which its 300 m circle and its 50 m nudge threshold are two different things.
class _RegionRow extends StatelessWidget {
  const _RegionRow({required this.region, required this.selected, this.onTap});

  final GeofenceRegion region;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = region;
    // „entfernt" would be the obvious word and it would be wrong: native measures against the
    // coverage disc's centre, not a live fix, so this is a distance from a place the phone was —
    // possibly hours ago. The same caveat is why the row says nothing about being near it now.
    final facts = <String>[
      if (r.radiusM > 0) r.radiusM >= 1000 ? '${(r.radiusM / 1000).toStringAsFixed(0)} km' : '${r.radiusM.round()} m',
      if (r.distanceM != null) '${(r.distanceM! / 1000).toStringAsFixed(1).replaceAll('.', ',')} km von der Scheibenmitte',
      if (r.hasPosition) '${r.lat!.toStringAsFixed(3)}, ${r.lon!.toStringAsFixed(3)}',
      if (!r.hasPosition) 'ohne Koordinaten',
    ];
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // One red, and it means "this one": the region being looked at, or the one the phone
            // is inside. Both are answers to a question somebody is asking right now.
            // `redBright` is the *this one* red (STYLE.md), the same mark the map uses.
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 4, right: 8),
              decoration: BoxDecoration(
                color: selected || r.inside ? VColors.redBright : VColors.ink3,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(r.isUmbrella ? 'Schirm' : r.name, style: VText.bodySStrong),
                      ),
                      if (r.inside) Text('drin', style: VText.caption.copyWith(color: VColors.redInk)),
                    ],
                  ),
                  Text(facts.join(' · '), style: VText.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The counters of the days before today, one row per day (issue #29).
///
/// This is the only history the app has, and it is history it already had: the native side has
/// written one key per day since the counters existed and deleted none, so nothing new is
/// recorded to show it. There are no positions in it, because none were ever kept.
class _HistoryTable extends StatelessWidget {
  const _HistoryTable({required this.days, required this.names, required this.today});

  final List<GeofenceDay> days;
  final Map<String, String> names;

  /// `yyyy-MM-dd`. Today is shown in its own section above, and it is excluded by name rather
  /// than by position: `countersHistory` leaves out days with no traffic, so on a quiet morning
  /// the newest entry is yesterday and dropping the first row would hide it.
  final String today;

  @override
  Widget build(BuildContext context) {
    final earlier = days.where((d) => d.day != today).toList();
    if (earlier.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('counter-history'),
      decoration: BoxDecoration(border: Border.all(color: VColors.rule), borderRadius: BorderRadius.circular(4)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(width: 74, child: Text('Tag', style: VText.caption)),
              for (final label in names.values)
                Expanded(child: Text(label, style: VText.caption, textAlign: TextAlign.right, maxLines: 2)),
            ],
          ),
          const VGap.xs(),
          for (final d in earlier) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(width: 74, child: Text(_dayLabel(d.day), style: VText.bodySStrong)),
                  for (final key in names.keys)
                    Expanded(
                      child: Text(
                        '${d.get(key)}',
                        style: VText.mono.copyWith(fontSize: 12, color: d.get(key) == 0 ? VColors.ink3 : VColors.ink),
                        textAlign: TextAlign.right,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// `2026-09-17` as `17.09.` — the year is never the question here.
  static String _dayLabel(String isoDay) {
    final parts = isoDay.split('-');
    return parts.length == 3 ? '${parts[2]}.${parts[1]}.' : isoDay;
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? VColors.ink : null,
          border: Border.all(color: selected ? VColors.ink : VColors.rule),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label, style: VText.caption.copyWith(color: selected ? VColors.paper : VColors.ink2)),
      ),
    );
  }
}
