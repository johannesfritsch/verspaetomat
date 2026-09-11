import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/models.dart';
import '../../platform/diagnose_log.dart';
import '../../platform/geofence.dart';
import '../../repo/repo_scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../ride/ride_widgets.dart' show ErrorLine, LoadingLine, fmtLocal, shortError;

/// `Entwicklung` (docs/25 §5): what the geofence layer is actually doing, read from the phone.
///
/// It exists so a question like "why no nudge at Memmingen?" can be answered where it happened
/// rather than guessed at from a laptop. Nothing here leaves the phone by itself, and the log
/// holds paths, not bodies: it must stay safe to paste into a message.
class EntwicklungScreen extends StatefulWidget {
  const EntwicklungScreen({super.key});

  /// Shown in a debug build, and in a release build only with `--dart-define=DEBUG_PAGE=1`.
  static bool get available {
    const flag = String.fromEnvironment('DEBUG_PAGE', defaultValue: '');
    if (flag == '1' || flag == 'true') return true;
    var debug = false;
    assert(() {
      debug = true;
      return true;
    }());
    return debug;
  }

  @override
  State<EntwicklungScreen> createState() => _EntwicklungScreenState();
}

class _EntwicklungScreenState extends State<EntwicklungScreen> {
  GeofenceStatus? _status;
  ApiGeofence _geofence = ApiGeofence.empty;
  List<LogLine> _log = const [];
  String _filter = 'alle';
  bool _loading = true;
  String? _error;

  static const _sources = ['alle', 'geofence', 'http', 'push', 'app'];

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
      final status = await Geofence.instance.status();
      final native = await Geofence.instance.readLog();
      final geo = await RepoScope.read(context).repo.geofence().catchError((_) => ApiGeofence.empty);
      if (!mounted) return;
      setState(() {
        _status = status;
        _geofence = geo;
        _log = DiagnoseLog.instance.merged(native);
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
          if (_loading && s == null) const LoadingLine(label: 'Status wird gelesen …'),
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

            // The coverage disc (docs/25 §1): the thing that decides how often we ask the backend.
            const VSection('Abdeckung'),
            if (s.disc == null)
              _Row('Scheibe', 'noch keine')
            else ...[
              _Row('Mitte', '${s.disc!.lat.toStringAsFixed(4)}, ${s.disc!.lon.toStringAsFixed(4)}'),
              _Row('Radius', '${(s.disc!.radiusM / 1000).round()} km · ${s.disc!.band}'),
              _Row('Gesetzt', s.disc!.at == null ? '–' : fmtLocal(s.disc!.at)),
            ],
            const VGap.m(),

            // Counters since midnight, so the traffic table in docs/25 is falsifiable on a trip.
            const VSection('Heute'),
            _Row('Backend-Anfragen', '${s.counters['requests'] ?? 0}'),
            _Row('stations/nearby', '${s.counters['nearby'] ?? 0}'),
            _Row('Hinweise geplant', '${s.counters['scheduled'] ?? 0}'),
            _Row('… ausgelöst', '${s.counters['fired'] ?? 0}'),
            _Row('… abgebrochen', '${s.counters['cancelled'] ?? 0}'),
            const VGap.m(),

            if (s.regions.isNotEmpty) ...[
              const VSection('Regionen'),
              for (final r in s.regions)
                _Row(
                  r.isUmbrella ? 'Schirm' : r.name,
                  [
                    if (r.distanceM != null) '${(r.distanceM! / 1000).toStringAsFixed(1)} km',
                    if (r.inside) 'drin',
                  ].join(' · '),
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
          const VGap.m(),
          Text(
            'Alles hier bleibt auf dem Telefon. Im Log stehen Pfade, keine Inhalte, und nichts aus einem Antrag.',
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
