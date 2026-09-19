import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../content/legal.dart' show appVersion;
import '../../platform/diagnose_log.dart';
import '../../platform/geofence.dart';
import '../../platform/geofence_replay.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import 'community_widgets.dart' show SegmentTabs;
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
/// find it in the current build". Showing it is safe: nothing *on this page* writes anything, and
/// the app has no admin surface to expose. The workshop tools that change what the app *is* —
/// switching backend, the demo toys, the "alles erfunden" footer — stay behind `kDebugMode` in
/// their own block in `einstellungen_screen.dart`.
///
/// The one thing that leads away from here is the **Showcase** (issue #28), which is an index of
/// every screen and so is not read-only the way this page is. It carries its own guard: in local
/// mode it leaves out the entries that would write to the real account or show real data under an
/// invented label, and says on the page that it has done so.
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

  /// Native's "a refresh has landed" signal, subscribed lazily so the page only listens once it
  /// has asked for one.
  StreamSubscription<void>? _refreshLanded;

  /// Which segment is open (issue #32). The page was one eager column about 2 700 pt tall, so the
  /// Showcase and the two actions sat below a 120-line log and nobody scrolled that far.
  int _tab = 0;
  static const _tabs = ['Zustand', 'Zahlen', 'Log'];

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

  /// How far back the log is shown and copied. The ring holds days, and a round of debugging is
  /// usually about the last hour or the last trip — copying everything means pasting a week of
  /// movements to answer a question about twenty minutes.
  static const _windows = <String, Duration?>{
    '1 h': Duration(hours: 1),
    '3 h': Duration(hours: 3),
    '6 h': Duration(hours: 6),
    '12 h': Duration(hours: 12),
    '24 h': Duration(hours: 24),
    'alles': null,
  };
  String _window = '3 h';

  /// How many lines are drawn. The whole list is still copied — this is about the weight of an
  /// eager column, which is what made the page heavy enough to need tabs (issue #32).
  static const _shown = 150;

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

  @override
  void dispose() {
    _refreshLanded?.cancel();
    super.dispose();
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
    final lines = _visible;
    final text = '${_copyHeader(lines)}\n\n${lines.map((l) => l.plainWithDate).join('\n')}\n';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${lines.length} Zeilen aus $_window kopiert, mit Kopfzeile.')),
      );
    }
  }

  /// What the phone thinks, above the lines that got it there.
  ///
  /// A log on its own has cost two rounds of guessing already: the lines say what happened but
  /// not what state the layer ended up in, so the first question back is always „und was steht
  /// gerade auf der Seite?". This puts both in one paste.
  String _copyHeader(List<LogLine> lines) {
    final s = _status;
    final session = RepoScope.read(context);
    String when(DateTime? d) => d == null ? '–' : d.toUtc().toIso8601String();
    return [
      '# Verspätomat $appVersion · ${session.isLocal ? session.apiUrl : 'Vorführung'}',
      '# Fenster: $_window · Quelle: $_filter · ${lines.length} Zeilen'
          '${lines.isEmpty ? '' : ' · ${when(lines.first.at)} … ${when(lines.last.at)}'}',
      if (s == null)
        '# Status: nicht gelesen'
      else ...[
        '# Berechtigung: ${s.permission.name} · Mitteilungen: ${s.notifications ? 'an' : 'aus'} · Schicht: ${s.mode ?? '?'}',
        '# Regionen: ${s.registered} registriert, gezogen ${when(s.regionsAt)}'
            '${s.regionsCentre == null ? '' : ' um ${s.regionsCentre!.lat.toStringAsFixed(4)},${s.regionsCentre!.lon.toStringAsFixed(4)}'}',
        '# Nearest: ${when(s.nearestAt)} · ${s.nearestCount} zurück'
          '${s.nearestCentre == null ? ' · Ort unbekannt' : ' · geholt um ${s.nearestCentre!.lat.toStringAsFixed(4)},${s.nearestCentre!.lon.toStringAsFixed(4)}'}',
        if (s.disc != null)
          '# Scheibe: ${s.disc!.lat.toStringAsFixed(4)},${s.disc!.lon.toStringAsFixed(4)} '
              'r=${(s.disc!.radiusM / 1000).round()} km (${s.disc!.band}) gesetzt ${when(s.disc!.at)}',
        '# Heute: ${_counterNames.keys.map((k) => '$k=${s.counters[k] ?? 0}').join(' ')}'
            '${(s.counters['refused'] ?? 0) > 0 ? ' refused=${s.counters['refused']}' : ''}',
        for (final r in _sortedRegions(s.regions))
          '#   ${r.isUmbrella ? 'Schirm' : r.name}'
              '${r.hasPosition ? ' ${r.lat!.toStringAsFixed(4)},${r.lon!.toStringAsFixed(4)}' : ' (ohne Koordinaten)'}'
              '${r.distanceM == null ? '' : ' ${(r.distanceM! / 1000).toStringAsFixed(1)} km'}'
              '${r.inside ? ' drin' : ''}',
      ],
    ].join('\n');
  }

  /// The lines the source filter and the time window both let through, oldest first.
  List<LogLine> get _visible {
    final window = _windows[_window];
    final since = window == null ? null : DateTime.now().subtract(window);
    return _log
        .where((l) => _filter == 'alle' || l.source == _filter)
        .where((l) => since == null || l.at.isAfter(since))
        .toList();
  }

  /// The event the map is currently showing, if the index still points at one.
  GeofencePlacedEvent? _replayed() {
    final i = _replayAt;
    if (i == null || i < 0 || i >= _replay.events.length) return null;
    return _replay.events[i];
  }

  /// Why the set is empty, in the words the status already knows — never a guess.
  static String _whyNothingRegistered(GeofenceStatus s) {
    if (s.permission != GeofencePermission.always) {
      return 'Ohne Hintergrund-Berechtigung registriert iOS keine (${s.permission.name}).';
    }
    if (s.regionsAt == null) return 'Der Satz wurde noch nie gezogen.';
    return 'Warum, steht nicht fest — sieh ins Log.';
  }

  /// Nearest first, the umbrella last, and anything without a distance after the rest.
  static List<GeofenceRegion> _sortedRegions(List<GeofenceRegion> regions) {
    final out = [...regions];
    out.sort((a, b) {
      if (a.isUmbrella != b.isUmbrella) return a.isUmbrella ? 1 : -1;
      final da = a.distanceM, db = b.distanceM;
      if (da == null && db == null) return a.name.compareTo(b.name);
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return out;
  }

  /// The station the map is filled with, if it is still in the set after a reload.
  GeofenceRegion? _focused(GeofenceStatus s) {
    for (final r in s.regions) {
      if (r.id == _focusId && r.hasPosition) return r;
    }
    return null;
  }

  /// The one sentence the page exists for: is this set current, and if not, why not (issue #31).
  ///
  /// It only ever states what the two timestamps and the disc actually say. „Nearest" is the list
  /// the set is chosen from and it is fetched in exactly one place — after the phone leaves the
  /// umbrella — so a set redrawn long after the last lookup is a set redrawn from a stale list,
  /// which is the failure that looks like nothing happening.
  String _setCaption(GeofenceStatus s) {
    if (s.regionsAt == null) return 'Noch nie gezogen.';
    if (s.nearestAt == null) {
      return 'Die Liste der nahen Bahnhöfe wurde noch nie geholt — der Satz besteht nur aus deinen '
          'Stammbahnhöfen.';
    }

    // The question this page exists for, in the order it actually gets asked: is the list from
    // *here*, and if not, is anything going to fetch a new one?
    final away = _nearestAwayKm(s);
    if (away != null && away > 3) {
      return 'Die Liste der nahen Bahnhöfe wurde ${away.toStringAsFixed(0)} km von hier geholt. Sie '
          'beschreibt einen anderen Ort, und der Satz ist daraus gezogen — beim nächsten Start '
          'wird neu gesucht.';
    }

    final gap = s.regionsAt!.difference(s.nearestAt!);
    final parts = <String>[
      if (gap.inMinutes > 30)
        'Der Satz wurde ${_howLong(gap)} nach der letzten Suche neu gezogen — also aus derselben '
            'Liste wie vorher, nicht aus einer neuen.',
      if (s.disc != null)
        'Von selbst neu gesucht wird erst außerhalb der Scheibe, und die ist gerade '
            '${(s.disc!.radiusM / 1000).round()} km weit — im Stehen passiert das nie.',
    ];
    return parts.isEmpty ? 'Satz und Suche liegen dicht beieinander.' : parts.join(' ');
  }

  /// How far the stored nearby list was fetched from where the disc now sits, in km.
  static double? _nearestAwayKm(GeofenceStatus s) {
    final n = s.nearestCentre, d = s.disc;
    if (n == null || d == null) return null;
    // Equirectangular is exact enough for a distance that only has to be read as a number.
    const mPerDegLat = 111320.0;
    final mPerDegLon = mPerDegLat * math.cos(d.lat * math.pi / 180);
    final dy = (n.lat - d.lat) * mPerDegLat, dx = (n.lon - d.lon) * mPerDegLon;
    return math.sqrt(dy * dy + dx * dx) / 1000;
  }

  /// „3 Stunden", „12 Minuten" — a gap in the words the caption needs.
  static String _howLong(Duration d) {
    if (d.inMinutes < 90) return '${d.inMinutes} Minuten';
    if (d.inHours < 48) return '${d.inHours} Stunden';
    return '${d.inDays} Tage';
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
    // The lookup is asynchronous: the fix takes a second, the request a few hundred milliseconds.
    // Pressing „Neu laden" straight afterwards shows the state from *before* it — which is very
    // probably what made this feature look like it had done nothing at all. Native already tells
    // Dart when a refresh has landed, so the page reloads itself instead.
    _refreshLanded ??= Geofence.instance.onUmbrellaExit.listen((_) {
      if (mounted) _load();
    });
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

          // Everything that is not a reading lives above the segments (issue #32): the page used
          // to be one eager column about two and a half screens tall, with the Showcase and the
          // two actions below a 120-line log, so nothing down there was ever reached.
          Row(
            children: [
              Expanded(child: VOutlineButton(label: 'Neu laden', icon: Icons.refresh, onTap: _load)),
              const SizedBox(width: 8),
              Expanded(child: VOutlineButton(label: 'Neu suchen', icon: Icons.my_location, onTap: _refreshNow)),
            ],
          ),
          const VGap.s(),
          Row(
            children: [
              Expanded(child: VOutlineButton(label: 'Hinweis', icon: Icons.notifications_active_outlined, onTap: _testNudge)),
              const SizedBox(width: 8),
              Expanded(
                child: VOutlineButton(
                  key: const Key('showcase'),
                  label: 'Showcase',
                  icon: Icons.grid_view_outlined,
                  onTap: () => context.push(Routes.showcase),
                ),
              ),
            ],
          ),
          const VGap.xs(),
          Text(
            '„Neu suchen“ holt einen frischen Standort und zieht den Satz neu — dasselbe, was sonst '
            'beim Verlassen des Schirms passiert, und es unterbricht nichts, was gerade läuft. '
            '„Hinweis“ schickt in zehn Sekunden eine Mitteilung an dieses Telefon, die nichts '
            'enthält und beim Antippen nichts tut: sie beantwortet nur, ob Hinweise hier überhaupt '
            'ankommen. Sperr den Bildschirm und warte.',
            style: VText.caption,
          ),
          const VGap.l(),

          SegmentTabs(labels: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i)),
          const VGap.l(),

          if (_loading && s == null) const VSkeletonList(rows: 4, trailing: false),
          if (_error != null) ErrorLine(message: _error!, onRetry: _load),

          // One segment is built at a time. An IndexedStack would keep all three laid out — which
          // is the weight this change exists to remove — and would let the tour photograph the
          // wrong one under the right name without failing.
          if (_tab == 0 && s != null) ..._zustand(context, s, session),
          if (_tab == 1 && s != null) ..._zahlen(s),
          if (_tab == 2) ..._logTab(),
          const VGap.xl(),
        ],
      ),
    );
  }

  /// Everything about where the fence is and what it is doing (issues #31, #32).
  List<Widget> _zustand(BuildContext context, GeofenceStatus s, Session session) {
    return [
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
            _Row(
              'Schirm',
              '${(s.umbrellaRadiusM / 1000).toStringAsFixed(1)} km'
                  '${s.umbrellaComputed ? '' : ' — Vorgabe, nicht gerechnet'}',
            ),
            if (s.umbrellaWhy != null) _Row('… weil', s.umbrellaWhy!),
            if (s.maxRegionRadiusM > 0)
              _Row('… das Gerät kann', '${(s.maxRegionRadiusM / 1000).round()} km'),
            _Row('Bahnhofskreis', '${GeofenceConfig.defaultStationRadiusM} m'),
            _Row('Hinweis ab', '${GeofenceConfig.defaultNudgeRadiusM} m'),
            const VGap.xs(),
            Text(
              'Der Schirm weckt die App, wenn du ihn verlässt, und der Satz wird neu gezogen. Seine '
              'Größe ist keine feste Zahl mehr: sie reicht bis zum nächsten Bahnhof, den wir '
              'gerade *nicht* überwachen, abzüglich des Bahnhofskreises und der Strecke, die du '
              'zurücklegst, während iOS den Austritt meldet. In der Stadt sind das ein paar '
              'Kilometer, im Allgäu viele — und wenn der Server nicht ausdrücklich sagt, dass er '
              'vollständig gesucht hat, bleibt es bei der vorsichtigen Vorgabe. Der Bahnhofskreis '
              'ist absichtlich weit: kleine Kreise meldet iOS spät oder gar nicht.',
              style: VText.caption,
            ),
            const VGap.m(),

            // The coverage disc (docs/25 §1): the thing that decides how often we ask the backend.
            // issue #31: the set and the lookup behind it, dated in their own right. Until these
            // existed the page had one date — the disc's — and `configure` moves the disc to
            // wherever its fix lands while re-registering the set it already had, so „Gesetzt:
            // gerade eben" could sit above stations chosen thirteen kilometres away.
            const VSection('Der Satz'),
            _Row('Gezogen', _stamp(s.regionsAt)),
            _Row(
              'Gezogen um',
              s.regionsCentre == null
                  ? '–'
                  : '${s.regionsCentre!.lat.toStringAsFixed(4)}, ${s.regionsCentre!.lon.toStringAsFixed(4)}',
            ),
            _Row('Nearest geholt', _stamp(s.nearestAt)),
            _Row(
              '… und zwar um',
              s.nearestCentre == null
                  ? '–'
                  : '${s.nearestCentre!.lat.toStringAsFixed(4)}, ${s.nearestCentre!.lon.toStringAsFixed(4)}',
            ),
            _Row('… Bahnhöfe zurück', s.nearestAt == null ? '–' : '${s.nearestCount}'),
            _Row('Schicht macht', s.mode ?? '–'),
            const VGap.xs(),
            Text(
              _setCaption(s),
              style: VText.caption,
            ),
            const VGap.m(),

            const VSection('Abdeckung'),
            if (s.disc == null)
              _Row('Scheibe', 'noch keine')
            else ...[
              _Row('Mitte', '${s.disc!.lat.toStringAsFixed(4)}, ${s.disc!.lon.toStringAsFixed(4)}'),
              _Row('Radius', '${(s.disc!.radiusM / 1000).round()} km · ${s.disc!.band}'),
              _Row('Gesetzt', _stamp(s.disc!.at)),
            ],
            const VGap.m(),
            // An empty set drew nothing at all — no header, no count, no explanation — so the
            // page went straight from the counters to the log and looked like it had lost the
            // section. Keyed on `registered`, not on the list, because Android sends a count and
            // no list and would otherwise claim a phone with live fences has none.
            if (s.regions.isEmpty) ...[
              const VSection('Regionen'),
              const VGap.xs(),
              Text(
                s.registered > 0
                    ? '${s.registered} registriert, aber diese Plattform sagt nicht welche.'
                    : 'Keine Region registriert. ${_whyNothingRegistered(s)}',
                style: VText.caption,
              ),
              const VGap.m(),
            ],
            if (s.regions.isNotEmpty) ...[
              VSection('Regionen', trailing: Text('${s.regions.length}', style: VText.caption)),
              // Sorted by distance, umbrella last. Native hands back a Set in whatever order it
              // feels like, and with eighteen rows „is Lindau Reutin in here?" was a linear scan
              // with no anchor — which is most of „I cannot see the registered regions".
              for (final r in _sortedRegions(s.regions))
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
    ];
  }

  /// The counters, today and before.
  List<Widget> _zahlen(GeofenceStatus s) {
    return [
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
    ];
  }

  /// The log, its filters and the things you do with it.
  List<Widget> _logTab() {
    return [
          // The log itself.
          VSection('Zeitraum'),
          const VGap.xs(),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final w in _windows.keys)
                _FilterChip(label: w, selected: _window == w, onTap: () => setState(() => _window = w)),
            ],
          ),
          const VGap.s(),
          VSection('Quelle', trailing: Text('${_visible.length} Zeilen', style: VText.caption)),
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
                ? Text(
                    _log.isEmpty ? 'Noch nichts aufgezeichnet.' : 'Nichts in diesem Zeitraum. Nimm ein größeres.',
                    style: VText.caption,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final l in _visible.reversed.take(_shown)) _LogRow(line: l),
                      if (_visible.length > _shown) ...[
                        const VGap.xs(),
                        Text(
                          '… und ${_visible.length - _shown} ältere. Kopiert wird der ganze Zeitraum, '
                          'nicht nur das Sichtbare.',
                          style: VText.caption,
                        ),
                      ],
                    ],
                  ),
          ),
          const VGap.m(),
          Row(
            children: [
              Expanded(child: VOutlineButton(label: 'Kopieren', icon: Icons.copy_all, onTap: _copyAll)),
              const SizedBox(width: 8),
              Expanded(child: VOutlineButton(label: 'Log leeren', icon: Icons.delete_outline, onTap: _clearLog)),
            ],
          ),
          const VGap.xs(),
          Text(
            'Kopiert werden die ${_visible.length} Zeilen aus „$_window“ — mit einer Kopfzeile, die '
            'festhält, was das Telefon in diesem Moment denkt: Berechtigung, Regionen, Scheibe, '
            'Zähler. Das Log allein sagt, was passiert ist, aber nicht, wo es geendet hat.',
            style: VText.caption,
          ),
          const VGap.xl(),
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
    ];
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

/// One log line, laid out so a long log can be scanned rather than read.
///
/// Three columns of meaning, not three columns of layout: the time, the source as a short tag,
/// and the line itself wrapping under neither of them. The old rendering put all three in one
/// monospace run, so „13:52:07 geofence enter Köln Hbf" and „13:52:07 http GET /v1/…" started at
/// different places and the eye had nothing to follow down the page.
///
/// A line that went wrong is drawn heavier rather than coloured: this app's two reds both mean
/// something specific (STYLE.md), and a third meaning on a diagnostics page would spend a colour
/// the rest of the app needs.
class _LogRow extends StatelessWidget {
  const _LogRow({required this.line});

  final LogLine line;

  @override
  Widget build(BuildContext context) {
    final mono = VText.mono.copyWith(fontSize: 12, height: 1.35);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 58, child: Text(line.time, style: mono.copyWith(color: VColors.ink3))),
          SizedBox(
            width: 62,
            child: Text(
              line.source,
              style: VText.caption.copyWith(color: VColors.ink3),
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ),
          Expanded(
            child: Text(
              line.text,
              style: line.bad ? mono.copyWith(fontWeight: FontWeight.w700, color: VColors.ink) : mono,
            ),
          ),
        ],
      ),
    );
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
