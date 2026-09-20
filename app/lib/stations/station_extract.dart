import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

/// The station table as the phone holds it (issue #39).
///
/// Bytes in, records out: no Flutter, no file and no network access, `dart:io` only for `gzip`.
/// That shape is what lets [decode] move into `compute()` unchanged if a device ever needs it to —
/// it is a pure function of a [Uint8List] returning a value.
///
/// The byte layout is the contract with `backend/src/stations/extract.rs`; it is written out
/// field by field below and in docs/45. All integers are little-endian, always, never the host's.
class StationExtract {
  const StationExtract({
    required this.formatVersion,
    required this.headerLen,
    required this.recordLen,
    required this.tableVersion,
    required this.generatedAt,
    required this.crc32,
    required this.byteLength,
    required this.ids,
    required this.names,
    required this.lat,
    required this.lon,
    required this.rank,
    required this.flags,
  });

  /// `"VSST"`, the four bytes a station extract starts with.
  static const List<int> magic = [0x56, 0x53, 0x53, 0x54];

  /// The only format this reader knows. A file that says anything else is refused whole: the
  /// extract in hand is better than a file whose bytes mean something we can only guess at.
  static const int supportedFormatVersion = 1;

  /// The header this reader needs. A longer one is fine — bytes `[minHeaderLen, headerLen)` are a
  /// future field and are skipped, which is how the format grows without breaking a phone that is
  /// already in the field.
  static const int minHeaderLen = 32;

  /// The bytes of a record this reader reads. A longer record is fine and is strided over.
  static const int minRecordLen = 20;

  /// The header's `format`.
  final int formatVersion;

  /// The header's `header_len` and `record_len`, as read. Kept so a caller can tell a grown file
  /// from a plain format-1 one, and so nothing here has to assume 32 or 20 anywhere.
  final int headerLen;
  final int recordLen;

  /// The header's `version`: the id of the `station_imports` row this extract was cut from. It
  /// only means something inside its own database, which is why only `--prod` may publish one.
  final int tableVersion;

  /// The header's `generated`, unix seconds UTC.
  final DateTime generatedAt;

  /// The header's `crc32`, as read and as verified over `bytes[headerLen..]`.
  final int crc32;

  /// The size of the extract itself, after any gzip wrapper came off.
  ///
  /// Not the size of what arrived: `Content-Length` is the compressed length whenever Caddy
  /// serves the `.gz` sibling, so this is the only number that can be compared against the
  /// pointer's `bytes`.
  final int byteLength;

  /// Ascending, the order `stations::load` reads the table in (`order by id`,
  /// backend/src/stations/mod.rs:284). Both sorts in `StationIndex` lean on it: Rust's sorts are
  /// stable and Dart's is not, so the id is what reproduces the Rust's residual order.
  final Int32List ids;
  final List<String> names;
  final Float64List lat;
  final Float64List lon;
  final Uint8List rank;

  /// Record byte 13. Bit 0 is `looks_like_station` of the name, decided at build time.
  final Uint8List flags;

  int get count => ids.length;

  /// True when this station's name says „railway station" — `kFlagLooksLikeStation` of [flags].
  bool namedLikeStation(int i) => flags[i] & 1 != 0;

  /// Gunzips when the bytes begin `1f 8b`, then parses.
  ///
  /// The sniff is not a convenience. Whether these bytes are still compressed depends on headers
  /// the app does not control: an HTTP client transparently decodes a `Content-Encoding: gzip`
  /// response, and Caddy's `precompressed gzip` (deploy/caddy/Caddyfile) hands out the `.vst.gz`
  /// sibling under exactly that header. The bundled asset, meanwhile, is a plain `.vst`. Both
  /// arrive here and both have to work.
  ///
  /// Throws [ExtractFormatException] for every failure in §1.6's order — a bad magic, an
  /// unsupported [formatVersion], a length that does not add up, a checksum that does not match,
  /// a name outside the blob. There is no partial read: either the whole file parses or nothing
  /// is returned.
  static StationExtract decode(Uint8List bytes) {
    final raw = _gunzipIfNeeded(bytes);
    if (raw.length < minHeaderLen) {
      throw ExtractFormatException('${raw.length} bytes is shorter than the header');
    }
    final b = ByteData.view(raw.buffer, raw.offsetInBytes, raw.length);
    for (var i = 0; i < magic.length; i++) {
      if (raw[i] != magic[i]) {
        throw ExtractFormatException('not a station extract: the magic is ${raw.sublist(0, 4)}');
      }
    }
    final format = b.getUint16(4, Endian.little);
    if (format != supportedFormatVersion) {
      throw ExtractFormatException('extract format $format, this reader knows $supportedFormatVersion');
    }
    final headerLen = b.getUint16(6, Endian.little);
    if (headerLen < minHeaderLen) {
      throw ExtractFormatException('header_len $headerLen is shorter than $minHeaderLen');
    }
    final count = b.getUint32(8, Endian.little);
    if (count < 1) throw const ExtractFormatException('an extract of nothing');
    final recordLen = b.getUint32(12, Endian.little);
    if (recordLen < minRecordLen) {
      throw ExtractFormatException('record_len $recordLen is shorter than $minRecordLen');
    }
    final blobLen = b.getUint32(16, Endian.little);
    final generated = b.getUint32(20, Endian.little);
    final tableVersion = b.getUint32(24, Endian.little);
    final crc = b.getUint32(28, Endian.little);

    // As a double, because `headerLen + recordLen * count` overflows nothing here but a file
    // claiming four billion records would wrap a 64-bit int on the web's number type.
    final want = headerLen + recordLen.toDouble() * count + blobLen;
    if (want != raw.length) {
      throw ExtractFormatException('the file says ${want.toStringAsFixed(0)} bytes and is ${raw.length}');
    }

    // Over `[headerLen, EOF)`, never over a literal 32: a grown header keeps `format` at 1, and a
    // reader that hardcodes the offset breaks on the first field anybody adds.
    final actual = crc32Of(raw, headerLen);
    if (actual != crc) {
      throw ExtractFormatException('the checksum does not match: the file is damaged');
    }

    final blobAt = headerLen + recordLen * count;
    final ids = Int32List(count);
    final lat = Float64List(count);
    final lon = Float64List(count);
    final rank = Uint8List(count);
    final flags = Uint8List(count);
    final names = List<String>.filled(count, '', growable: false);
    for (var i = 0; i < count; i++) {
      final at = headerLen + i * recordLen;
      ids[i] = b.getUint32(at, Endian.little);
      lat[i] = b.getInt32(at + 4, Endian.little) / 1000000.0;
      lon[i] = b.getInt32(at + 8, Endian.little) / 1000000.0;
      rank[i] = raw[at + 12];
      flags[i] = raw[at + 13];
      final nameLen = raw[at + 14];
      // Byte 15 is `reserved`. It is ignored rather than checked for zero, because that is where
      // the next field goes and a reader that asserts it is 0 refuses the first grown file.
      final nameOff = b.getUint32(at + 16, Endian.little);
      if (nameLen < 1) throw ExtractFormatException('record $i has no name');
      if (nameOff + nameLen > blobLen) {
        throw ExtractFormatException('record $i names bytes outside the blob');
      }
      names[i] = utf8.decode(Uint8List.sublistView(raw, blobAt + nameOff, blobAt + nameOff + nameLen));
    }
    return StationExtract(
      formatVersion: format,
      headerLen: headerLen,
      recordLen: recordLen,
      tableVersion: tableVersion,
      generatedAt: DateTime.fromMillisecondsSinceEpoch(generated * 1000, isUtc: true),
      crc32: crc,
      byteLength: raw.length,
      ids: ids,
      names: names,
      lat: lat,
      lon: lon,
      rank: rank,
      flags: flags,
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

/// CRC-32/ISO-HDLC over `bytes[from..]` — the ordinary zlib/PNG CRC: reflected polynomial
/// `0xEDB88320`, init `0xFFFFFFFF`, final XOR `0xFFFFFFFF`. The same number `crc32fast` produces
/// on the server and `java.util.zip.CRC32` produces on Android.
int crc32Of(Uint8List bytes, [int from = 0]) {
  final table = _crcTable;
  var crc = 0xFFFFFFFF;
  for (var i = from; i < bytes.length; i++) {
    crc = table[(crc ^ bytes[i]) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

final Uint32List _crcTable = _buildCrcTable();

Uint32List _buildCrcTable() {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}

class ExtractFormatException implements Exception {
  const ExtractFormatException(this.message);
  final String message;
  @override
  String toString() => 'ExtractFormatException: $message';
}
