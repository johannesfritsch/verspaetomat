import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

/// Getting a picture of a ticket off the phone, with nothing else attached to it.
///
/// **Why this file exists at all.** The app's one printed promise is *Dein Standort bleibt am
/// Bahnhof* (docs/14): coordinates leave the phone as a query for nearby stations and, at check-in,
/// as the fix stored on that ride, and *nothing else stores or derives position*. A photograph
/// carries GPS in its EXIF, and the most likely photograph here is one taken on the platform of a
/// paper ticket. Attaching it to a mail to a railway would be a third channel for a passenger's
/// position, which that sentence forecloses. So the picture is re-encoded before it is uploaded,
/// and what reaches the railway is pixels and nothing else.
///
/// Stripping happens here rather than on the server on purpose: by the time the bytes have left the
/// phone the coordinates have already left with them.
class TicketPhoto {
  TicketPhoto._();

  /// True where no picker may open: the screenshot tour and the workflow E2E drive a simulator
  /// that has no camera and a photo library of Apple's sample wallpapers, and a system sheet there
  /// is a test that hangs rather than fails. The same define already keeps the geofence quiet
  /// (platform/geofence_sync.dart).
  static const automation = String.fromEnvironment('E2E') == 'true' ||
      String.fromEnvironment('NO_LOCATION') == '1' ||
      String.fromEnvironment('NO_LOCATION') == 'true';

  /// The longest edge we keep. A Deutschlandticket barcode has to stay scannable and a railway
  /// clerk has to be able to read the ticket number; 2000 px does both and turns a 12 MP photo
  /// into a few hundred kilobytes.
  static const _maxEdge = 2000;

  /// JPEG quality. High enough that a barcode survives, low enough that three months of tickets
  /// fit in one mail (the server refuses a message over about 9 MB).
  static const _quality = 88;

  /// Pick a picture and make it safe to send. Null means the person backed out of the sheet,
  /// which is not an error and must not be reported as one.
  static Future<Uint8List?> pick(ImageSource source) async {
    final picker = ImagePicker();
    // requestFullMetadata: false is load-bearing twice. It keeps iOS on PHPickerViewController,
    // which runs out of process, shows no permission alert and hands back only the one asset the
    // person chose; and it stops the plugin reading the asset's own location and creation date, so
    // the coordinates never enter this process at all, whatever the file happens to contain.
    final picked = await picker.pickImage(source: source, requestFullMetadata: false);
    if (picked == null) return null;
    return sanitize(await picked.readAsBytes());
  }

  /// Re-encode to JPEG: no EXIF, no XMP, no maker notes, no GPS, bounded size.
  ///
  /// A re-encode rather than a tag deletion, which matters: a photo often carries a *second* copy
  /// of its location in an XMP or IPTC block, so removing the EXIF IFD alone is not enough. Here
  /// nothing is removed — a new file is written from the pixels, and only the pixels come across.
  /// It also solves HEIC, which is what an iPhone actually shoots and which nothing downstream
  /// reads.
  static Future<Uint8List> sanitize(Uint8List raw) async {
    final out = await FlutterImageCompress.compressWithList(
      raw,
      minWidth: _maxEdge,
      minHeight: _maxEdge,
      quality: _quality,
      format: CompressFormat.jpeg,
      // The default, and it must stay: a portrait photo carries its rotation as an EXIF tag, and
      // dropping the tag without applying it would deliver every upright ticket on its side.
      autoCorrectionAngle: true,
      // keepExif defaults to false. Naming it anyway, because this line is the promise.
      keepExif: false,
    );
    return Uint8List.fromList(out);
  }
}
