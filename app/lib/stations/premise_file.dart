import 'dart:typed_data';

import 'station_extract.dart' show ExtractFormatException, crc32Of;
import 'dart:io' show gzip;

/// `umrisse-<version>.bin`, the station premises (issue #64, docs/48): per station the ring the
/// phone watches for arriving and leaving, the touch points whose entry is the nudge, and the
/// premise itself. Derived from OpenStreetMap, ODbL.
///
/// Bytes in, records out, and every check refuses the whole file — the reader mirrors
/// `backend/src/stations/outlines.rs` (`parse_file`) check for check, and all four readers (Rust,
/// Dart, Swift, Kotlin) read `test/fixtures/umrisse-fixture.bin` to the same numbers.
///
/// Layout, little-endian: a 32-byte header (`VSOL`, format u16, header_len u16, count u32,
/// record_len u32, blob_len u32, generated u32, version u32, crc32 u32 over records and blob),
/// `count` records of `record_len` bytes sorted by station id (id u32, ring lat i32 and lon i32
/// in micro-degrees, ring radius u16, touch count u8, corner count u8, blob offset u32), then the
/// blob: at each offset the touch points (lat i32, lon i32, r u16) and the corners (lat i32,
/// lon i32). A longer header or record is skipped, as in the station extract.
class PremiseFile {
  PremiseFile._({
    required this.version,
    required this.generatedAt,
    required this.crc32,
    required this.byteLength,
    required this.premises,
  });

  static const int format = 1;
  static const int minHeaderLen = 32;
  static const int minRecordLen = 20;

  /// The import on the server, as unix seconds. Compared only with the website's pointer.
  final int version;

  /// The day of the OpenStreetMap extract.
  final DateTime generatedAt;
  final int crc32;

  /// The size of the file itself, after any gzip wrapper came off.
  final int byteLength;

  /// By our station id (the number behind `vs:`).
  final Map<int, Premise> premises;

  int get count => premises.length;

  static PremiseFile decode(Uint8List input) {
    final b = _gunzipIfNeeded(input);
    if (b.length < minHeaderLen) throw ExtractFormatException('${b.length} bytes is no header');
    final d = ByteData.sublistView(b);
    if (b[0] != 0x56 || b[1] != 0x53 || b[2] != 0x4f || b[3] != 0x4c) {
      throw const ExtractFormatException('not a VSOL file');
    }
    final fmt = d.getUint16(4, Endian.little);
    if (fmt != format) throw ExtractFormatException('format $fmt');
    final hl = d.getUint16(6, Endian.little);
    final count = d.getUint32(8, Endian.little);
    final rl = d.getUint32(12, Endian.little);
    final bl = d.getUint32(16, Endian.little);
    if (hl < minHeaderLen || rl < minRecordLen) throw ExtractFormatException('header $hl, record $rl');
    if (hl + rl * count + bl != b.length) throw const ExtractFormatException('length does not add up');
    final crc = crc32Of(b, hl);
    if (crc != d.getUint32(28, Endian.little)) throw const ExtractFormatException('crc32 does not match');
    final blob0 = hl + rl * count;
    final out = <int, Premise>{};
    var last = 0;
    for (var i = 0; i < count; i++) {
      final o = hl + i * rl;
      final id = d.getUint32(o, Endian.little);
      if (id <= last) throw ExtractFormatException('record $i out of order');
      last = id;
      final nt = b[o + 14];
      final nc = b[o + 15];
      final off = d.getUint32(o + 16, Endian.little);
      if (off + nt * 10 + nc * 8 > bl) throw ExtractFormatException('record $i points past the blob');
      final at = blob0 + off;
      final touch = [
        for (var k = 0; k < nt; k++)
          PremiseCircle(
            lat: d.getInt32(at + k * 10, Endian.little) / 1e6,
            lon: d.getInt32(at + k * 10 + 4, Endian.little) / 1e6,
            radiusM: d.getUint16(at + k * 10 + 8, Endian.little).toDouble(),
          ),
      ];
      final c0 = at + nt * 10;
      final corners = [
        for (var k = 0; k < nc; k++) (d.getInt32(c0 + k * 8, Endian.little) / 1e6, d.getInt32(c0 + k * 8 + 4, Endian.little) / 1e6),
      ];
      final ring = PremiseCircle(
        lat: d.getInt32(o + 4, Endian.little) / 1e6,
        lon: d.getInt32(o + 8, Endian.little) / 1e6,
        radiusM: d.getUint16(o + 12, Endian.little).toDouble(),
      );
      // The same shape the server refuses to import (`check_row`): a file that breaks it was not
      // made by us.
      if (corners.length < 3 || corners.length > 24) throw ExtractFormatException('record $i: ${corners.length} corners');
      if (ring.radiusM < 300 || ring.radiusM > 1000) throw ExtractFormatException('record $i: ring ${ring.radiusM} m');
      if (touch.isEmpty || touch.length > 6 || touch.any((t) => t.radiusM < 120)) {
        throw ExtractFormatException('record $i: touch points');
      }
      out[id] = Premise(ring: ring, touch: touch, corners: corners);
    }
    return PremiseFile._(
      version: d.getUint32(24, Endian.little),
      generatedAt: DateTime.fromMillisecondsSinceEpoch(d.getUint32(20, Endian.little) * 1000, isUtc: true),
      crc32: crc,
      byteLength: b.length,
      premises: out,
    );
  }

  static Uint8List _gunzipIfNeeded(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      try {
        final out = gzip.decode(bytes);
        return out is Uint8List ? out : Uint8List.fromList(out);
      } catch (e) {
        throw ExtractFormatException('the gzip wrapper is damaged: $e');
      }
    }
    return bytes;
  }
}

class PremiseCircle {
  const PremiseCircle({required this.lat, required this.lon, required this.radiusM});
  final double lat;
  final double lon;
  final double radiusM;
}

class Premise {
  const Premise({required this.ring, required this.touch, required this.corners});
  final PremiseCircle ring;
  final List<PremiseCircle> touch;

  /// (lat, lon), counter-clockwise.
  final List<(double, double)> corners;
}
