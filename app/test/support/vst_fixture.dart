import 'dart:convert';
import 'dart:typed_data';

import 'package:verspaetomat/stations/station_extract.dart';
import 'package:verspaetomat/stations/station_rules.dart';

/// Writes the `.vst` bytes the backend's `stations::extract::render` writes, so the reader can be
/// tested against files it did not produce itself.
///
/// It is deliberately able to write broken ones too — a grown header, a name outside the blob, a
/// flipped byte after the checksum — because every one of those is a way a phone could be handed
/// something plausible and wrong.
class VstStation {
  const VstStation(this.id, this.name, this.lat, this.lon, this.rank, {this.flags});
  final int id;
  final String name;
  final double lat;
  final double lon;
  final int rank;

  /// Defaults to what `looks_like_station` says, which is what the builder bakes in.
  final int? flags;
}

Uint8List buildVst(
  List<VstStation> stations, {
  int version = 12,
  DateTime? generatedAt,
  int format = 1,
  int headerLen = 32,
  int recordLen = 20,
  List<int> magic = StationExtract.magic,
  int? countOverride,
  int? blobLenOverride,
  Uint8List Function(Uint8List body)? patchBody,
  int? flipByteAfterCrc,
  int? truncateTo,
}) {
  final blob = BytesBuilder();
  final offsets = <String, int>{};
  final records = BytesBuilder();
  for (final s in stations) {
    final name = utf8.encode(s.name);
    final off = offsets.putIfAbsent(s.name, () {
      final at = blob.length;
      blob.add(name);
      return at;
    });
    final r = ByteData(recordLen);
    r.setUint32(0, s.id, Endian.little);
    r.setInt32(4, (s.lat * 1000000.0).round(), Endian.little);
    r.setInt32(8, (s.lon * 1000000.0).round(), Endian.little);
    r.setUint8(12, s.rank);
    r.setUint8(13, s.flags ?? (looksLikeStation(s.name) ? kFlagLooksLikeStation : 0));
    r.setUint8(14, name.length);
    r.setUint8(15, 0);
    r.setUint32(16, off, Endian.little);
    records.add(r.buffer.asUint8List());
  }
  final blobBytes = blob.toBytes();
  var body = Uint8List.fromList([...records.toBytes(), ...blobBytes]);
  if (patchBody != null) body = patchBody(body);

  final header = ByteData(headerLen);
  final h = header.buffer.asUint8List();
  h.setRange(0, 4, magic);
  header.setUint16(4, format, Endian.little);
  header.setUint16(6, headerLen, Endian.little);
  header.setUint32(8, countOverride ?? stations.length, Endian.little);
  header.setUint32(12, recordLen, Endian.little);
  header.setUint32(16, blobLenOverride ?? blobBytes.length, Endian.little);
  header.setUint32(20, (generatedAt ?? DateTime.utc(2026, 9, 18, 2)).millisecondsSinceEpoch ~/ 1000, Endian.little);
  header.setUint32(24, version, Endian.little);
  header.setUint32(28, crc32Of(body), Endian.little);

  var out = Uint8List.fromList([...h, ...body]);
  if (flipByteAfterCrc != null) out[flipByteAfterCrc] = out[flipByteAfterCrc] ^ 0xFF;
  if (truncateTo != null) out = Uint8List.sublistView(out, 0, truncateTo);
  return out;
}

/// The five stations the Rust's own `extract.rs` tests use, plus the duplicate name that proves
/// the blob shares a slice.
const kSampleStations = [
  VstStation(3, 'Köln Hbf', 50.9430, 6.9586, 3),
  VstStation(11, 'Kißlegg Bahnhof', 47.7914, 9.8921, 2),
  VstStation(12, 'Wangen im Allgäu', 47.6874, 9.8255, 2),
  VstStation(20, 'Neustadt', 53.1000, 10.8000, 1),
  VstStation(21, 'Neustadt', 49.3500, 8.1400, 1),
];

/// A table big enough to pass `StationStore.minPlausibleCount`, scattered over Germany with a
/// fixed sequence so two runs produce the same file.
List<VstStation> plausibleTable({int count = 1200, int startId = 1}) {
  var seed = 0x2F6E2B1;
  double next() {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    return seed / 0x7FFFFFFF;
  }

  return [
    for (var i = 0; i < count; i++)
      VstStation(
        startId + i,
        i.isEven ? 'Musterstadt $i Hbf' : 'Musterstadt $i, Markt',
        47.3 + next() * 7.6,
        5.9 + next() * 9.1,
        (i % 3) + 1,
      ),
  ];
}
