import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../repo/repo_scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../../widgets/ticket.dart';
import '../community/community_widgets.dart' show SwitchRow;
import '../ride/ride_widgets.dart' show shortError;

/// Preview, then share (docs/27 §3).
///
/// Nobody posts an image they have not seen, and the preview is the only place the switches and
/// the four lines can live. The card is rendered on the device and nothing leaves the phone that
/// is not on it: no server, no upload, no public page.
Future<void> showShareSheet(
  BuildContext context, {
  required TicketData Function({String? fahrgast, String? strecke, DateTime? date, String? line}) build,
  required List<String> lines,
  String? strecke,
  DateTime? date,
}) async {
  final session = RepoScope.read(context);
  final nickname = session.me?.nickname.trim();
  await showVSheet<void>(
    context,
    expand: true,
    builder: (ctx) => _ShareSheet(
      build: build,
      lines: lines,
      nickname: nickname == null || nickname.isEmpty ? null : nickname,
      strecke: strecke,
      date: date,
    ),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.build,
    required this.lines,
    required this.nickname,
    required this.strecke,
    required this.date,
  });
  final TicketData Function({String? fahrgast, String? strecke, DateTime? date, String? line}) build;
  final List<String> lines;
  final String? nickname;
  final String? strecke;
  final DateTime? date;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _boundary = GlobalKey();
  int _line = 0;

  // The switches from docs/27 §5. The name is on by default; the rest is the ride's own facts.
  late bool _withName = widget.nickname != null;
  bool _withDate = true;
  bool _withRoute = true;
  bool _busy = false;

  TicketData get _data => widget.build(
        fahrgast: _withName ? widget.nickname : null,
        strecke: _withRoute ? widget.strecke : null,
        date: _withDate ? widget.date : null,
        line: widget.lines.isEmpty ? null : widget.lines[_line],
      );

  /// The widget on screen is the thing that gets shared — captured, not re-rendered, so what the
  /// passenger approved is exactly what goes out.
  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = png!.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = await _write(dir.path, bytes);
      if (!mounted) return;
      final text = widget.lines.isEmpty ? 'verspaetomat.de' : '${widget.lines[_line]} www.verspaetomat.de';
      await SharePlus.instance.share(ShareParams(text: text, files: [XFile(file)]));
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Teilen ging nicht: ${shortError(e)}')));
      }
    }
  }

  static Future<String> _write(String dir, Uint8List bytes) async {
    final path = '$dir/verspaetomat.png';
    final f = await File(path).create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
    return path;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VSheetHeader(title: 'Teilen'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
            children: [
              Center(
                child: RepaintBoundary(
                  key: _boundary,
                  child: Ticket(data: _data),
                ),
              ),
              const VGap.l(),
              if (widget.lines.length > 1) ...[
                const VSection('Text'),
                const VGap.xs(),
                for (var i = 0; i < widget.lines.length; i++)
                  _LineOption(
                    text: widget.lines[i],
                    selected: _line == i,
                    onTap: () => setState(() => _line = i),
                  ),
                const VGap.m(),
              ],
              const VSection('Auf der Karte'),
              if (widget.nickname != null)
                SwitchRow(
                  title: 'Dein Name',
                  subtitle: widget.nickname!,
                  value: _withName,
                  onChanged: (v) => setState(() => _withName = v),
                ),
              if (widget.strecke != null)
                SwitchRow(
                  title: 'Strecke',
                  subtitle: widget.strecke!,
                  value: _withRoute,
                  onChanged: (v) => setState(() => _withRoute = v),
                ),
              if (widget.date != null)
                SwitchRow(
                  title: 'Datum',
                  subtitle: 'Ohne Datum lässt sich die Karte nicht zuordnen',
                  value: _withDate,
                  onChanged: (v) => setState(() => _withDate = v),
                ),
              const VGap.m(),
              Text(
                'Die Karte entsteht auf deinem Telefon. Nichts davon geht an uns.',
                style: VText.caption,
              ),
              const VGap.l(),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.s, VSpace.page, VSpace.m),
            child: VPrimaryButton(label: _busy ? '…' : 'Teilen', icon: Icons.ios_share, onTap: _busy ? null : _share),
          ),
        ),
      ],
    );
  }
}

/// One of the four sentences. Radio marks, like every other set of options in the app (docs/22 §5).
class _LineOption extends StatelessWidget {
  const _LineOption({required this.text, required this.selected, required this.onTap});
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 22,
              color: selected ? VColors.red : VColors.ink3,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: selected ? VText.bodySStrong : VText.bodyS.copyWith(color: VColors.ink2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
