import 'dart:typed_data';

import 'package:verspaetomat/stations/station_extract.dart' show crc32Of;

/// A `umrisse-<version>.bin` for tests, written by the layout in `premise_file.dart` — `count`
/// premises with one touch point and a triangle each, stations 1, 2, 3, …
Uint8List buildVsol({required int count, required int version, int generated = 1790640000}) {
  const hl = 32, rl = 20;
  final recs = BytesBuilder();
  final blob = BytesBuilder();
  for (var i = 1; i <= count; i++) {
    final lat = 50.0 + i * 0.001, lon = 7.0 + i * 0.001;
    final r = ByteData(rl)
      ..setUint32(0, i, Endian.little)
      ..setInt32(4, (lat * 1e6).round(), Endian.little)
      ..setInt32(8, (lon * 1e6).round(), Endian.little)
      ..setUint16(12, 300, Endian.little)
      ..setUint8(14, 1)
      ..setUint8(15, 3)
      ..setUint32(16, blob.length, Endian.little);
    recs.add(r.buffer.asUint8List());
    final t = ByteData(10)
      ..setInt32(0, (lat * 1e6).round(), Endian.little)
      ..setInt32(4, (lon * 1e6).round(), Endian.little)
      ..setUint16(8, 120, Endian.little);
    blob.add(t.buffer.asUint8List());
    for (final (dl, dn) in [(0.0, 0.0), (0.0005, 0.0), (0.0, 0.0005)]) {
      final c = ByteData(8)
        ..setInt32(0, ((lat + dl) * 1e6).round(), Endian.little)
        ..setInt32(4, ((lon + dn) * 1e6).round(), Endian.little);
      blob.add(c.buffer.asUint8List());
    }
  }
  final body = BytesBuilder()
    ..add(recs.toBytes())
    ..add(blob.toBytes());
  final bodyBytes = body.toBytes();
  final h = ByteData(hl)
    ..setUint8(0, 0x56)
    ..setUint8(1, 0x53)
    ..setUint8(2, 0x4f)
    ..setUint8(3, 0x4c)
    ..setUint16(4, 1, Endian.little)
    ..setUint16(6, hl, Endian.little)
    ..setUint32(8, count, Endian.little)
    ..setUint32(12, rl, Endian.little)
    ..setUint32(16, blob.length, Endian.little)
    ..setUint32(20, generated, Endian.little)
    ..setUint32(24, version, Endian.little);
  final out = Uint8List(hl + bodyBytes.length)
    ..setAll(0, h.buffer.asUint8List())
    ..setAll(hl, bodyBytes);
  ByteData.sublistView(out).setUint32(28, crc32Of(out, hl), Endian.little);
  return out;
}
