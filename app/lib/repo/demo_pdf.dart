import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;

/// The example form, signed with whatever was drawn on the board.
///
/// Demo has no server, so it cannot render the real form; it ships one rendered once
/// (`assets/beispiel-antrag.pdf`). That file was the reason a demo signature never showed up on the
/// Senden step: the board worked, the step showed the ink, and the attachment opened a PDF that
/// could not possibly contain it.
///
/// So the example page is redrawn with the ink in it. The page is rasterised and laid full-bleed
/// on a fresh A4 page, the placeholder „elektronisch, Name eingegeben" is covered, and the drawing
/// is set where the real template sets it — the same field, the same 34 pt height as
/// `backend/templates/eu_form.typ`. The result is a real PDF, so the preview and the full-screen
/// viewer need no special case.
class DemoPdf {
  DemoPdf._();

  /// Where the signature field's value sits on the example page, in PDF points from the top-left.
  /// Measured on the rendered asset: the label „Unterschrift" at x 404, y 764–769; the placeholder
  /// line at x 404–515, y 775–781.
  static const _fieldLeft = 404.0;
  static const _valueTop = 772.0;
  static const _signatureHeight = 34.0; // as eu_form.typ: box(height: 34pt)
  static const _signatureMaxWidth = 170.0;

  static Uint8List? _cachedFor;
  static Uint8List? _cached;

  /// The example PDF with [signature] in its field. Rebuilt only when the signature changes.
  static Future<Uint8List> signed(Uint8List example, Uint8List signature) async {
    if (identical(signature, _cachedFor) && _cached != null) return _cached!;

    final doc = await pdfx.PdfDocument.openData(example);
    final page = await doc.getPage(1);
    // 3x: sharp enough that the form's small print survives zooming in the full-screen viewer.
    final raster = await page.render(width: page.width * 3, height: page.height * 3, format: pdfx.PdfPageImageFormat.png, backgroundColor: '#FFFFFF');
    final width = page.width;
    final height = page.height;
    await page.close();
    await doc.close();
    if (raster == null) return example;

    final out = pw.Document();
    final pageImage = pw.MemoryImage(raster.bytes);
    final ink = pw.MemoryImage(signature);
    out.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(width, height),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(
          children: [
            pw.Positioned.fill(child: pw.Image(pageImage, fit: pw.BoxFit.fill)),
            // The placeholder text the unsigned form prints in this field.
            pw.Positioned(
              left: _fieldLeft - 2,
              top: _valueTop,
              child: pw.Container(width: _signatureMaxWidth, height: 12, color: PdfColors.white),
            ),
            pw.Positioned(
              left: _fieldLeft,
              top: _valueTop - 2,
              child: pw.SizedBox(
                width: _signatureMaxWidth,
                height: _signatureHeight,
                child: pw.Image(ink, fit: pw.BoxFit.contain, alignment: pw.Alignment.centerLeft),
              ),
            ),
          ],
        ),
      ),
    );
    final bytes = await out.save();
    _cachedFor = signature;
    _cached = bytes;
    return bytes;
  }
}
