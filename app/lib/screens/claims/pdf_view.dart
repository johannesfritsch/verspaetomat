import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../repo/repo_scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';

/// The filled EU claim form, rendered from the backend's PDF. Inline: the first
/// page as an image in a fixed-height paper box with "Vollbild". [reloadKey]
/// changes force a fresh load (after signing, the signature appears).
class ClaimPdfPreview extends StatefulWidget {
  const ClaimPdfPreview({super.key, required this.claimId, this.reloadKey, this.height = 420});
  final String claimId;
  final Object? reloadKey;
  final double height;

  @override
  State<ClaimPdfPreview> createState() => _ClaimPdfPreviewState();
}

class _ClaimPdfPreviewState extends State<ClaimPdfPreview> {
  Uint8List? _bytes;
  Uint8List? _firstPage;
  int _pages = 0;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ClaimPdfPreview old) {
    super.didUpdateWidget(old);
    if (old.reloadKey != widget.reloadKey || old.claimId != widget.claimId) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await RepoScope.read(context).repo.claimPdf(widget.claimId);
      final doc = await PdfDocument.openData(bytes);
      final page = await doc.getPage(1);
      final img = await page.render(width: page.width * 2, height: page.height * 2, format: PdfPageImageFormat.png, backgroundColor: '#FFFFFF');
      await page.close();
      final count = doc.pagesCount;
      await doc.close();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _firstPage = img?.bytes;
        _pages = count;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'PDF konnte nicht geladen werden.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          height: widget.height,
          decoration: BoxDecoration(color: VColors.paperElevated, border: Border.all(color: VColors.rule)),
          child: _loading
              ? Center(child: Text('Formular wird erzeugt …', style: VText.caption))
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, style: VText.caption),
                          const SizedBox(height: 8),
                          VGhostButton(label: 'Erneut versuchen', onTap: _load),
                        ],
                      ),
                    )
                  : GestureDetector(
                      onTap: () => _openFull(context),
                      child: Image.memory(_firstPage!, fit: BoxFit.contain, alignment: Alignment.topCenter, gaplessPlayback: true),
                    ),
        ),
        if (!_loading && _error == null)
          Row(
            children: [
              Expanded(child: Text(_pages > 1 ? 'Seite 1 von $_pages · EU-Antragsformular' : 'EU-Antragsformular', style: VText.caption)),
              TextButton(
                onPressed: () => _openFull(context),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Text('Vollbild', style: VText.bodySStrong.copyWith(color: VColors.red)),
              ),
            ],
          ),
      ],
    );
  }

  void _openFull(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ClaimPdfPage(bytes: bytes)));
  }
}

/// Full-screen PDF with pinch zoom.
class ClaimPdfPage extends StatefulWidget {
  const ClaimPdfPage({super.key, required this.bytes, this.title = 'EU-Antragsformular'});
  final Uint8List bytes;
  final String title;

  /// Loads the PDF for [claimId] and opens the viewer. Shows a snackbar on failure.
  static Future<void> open(BuildContext context, String claimId) async {
    try {
      final bytes = await RepoScope.read(context).repo.claimPdf(claimId);
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ClaimPdfPage(bytes: bytes)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF konnte nicht geladen werden.')));
    }
  }

  @override
  State<ClaimPdfPage> createState() => _ClaimPdfPageState();
}

class _ClaimPdfPageState extends State<ClaimPdfPage> {
  late final PdfControllerPinch _controller = PdfControllerPinch(document: PdfDocument.openData(widget.bytes));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VColors.paper,
      appBar: AppBar(title: Text(widget.title), backgroundColor: VColors.paper, foregroundColor: VColors.ink, elevation: 0),
      body: PdfViewPinch(
        controller: _controller,
        backgroundDecoration: const BoxDecoration(color: VColors.paper),
        builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
          options: const DefaultBuilderOptions(),
          documentLoaderBuilder: (_) => Center(child: Text('Lädt …', style: VText.caption)),
          pageLoaderBuilder: (_) => const SizedBox.shrink(),
          errorBuilder: (_, e) => Center(child: Text('PDF konnte nicht angezeigt werden.', style: VText.caption)),
        ),
      ),
    );
  }
}
