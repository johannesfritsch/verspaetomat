import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/stations/station_extract.dart';

import 'support/vst_fixture.dart';

/// The reader, against bytes written from the format spec rather than from itself where that is
/// possible — and against every way a file can be plausible and wrong.
void main() {
  test('an extract reads back as the stations it was written from', () {
    final x = StationExtract.decode(buildVst(kSampleStations, version: 12));

    expect(x.formatVersion, 1);
    expect(x.headerLen, 32);
    expect(x.recordLen, 20);
    expect(x.tableVersion, 12);
    expect(x.generatedAt, DateTime.utc(2026, 9, 18, 2));
    expect(x.count, 5);

    expect(x.ids, [3, 11, 12, 20, 21]);
    expect(x.names, ['Köln Hbf', 'Kißlegg Bahnhof', 'Wangen im Allgäu', 'Neustadt', 'Neustadt']);
    expect(x.rank, [3, 2, 2, 1, 1]);
    // Micro-degrees, so six decimals survive and nothing beyond them is claimed.
    expect(x.lat[0], closeTo(50.9430, 5e-7));
    expect(x.lon[0], closeTo(6.9586, 5e-7));
    expect(x.lat[4], closeTo(49.3500, 5e-7));

    // `looks_like_station`, baked into byte 13 at build time. Not trivially constant.
    expect(x.namedLikeStation(0), isTrue, reason: 'Köln Hbf');
    expect(x.namedLikeStation(1), isTrue, reason: 'Kißlegg Bahnhof');
    expect(x.namedLikeStation(2), isFalse, reason: 'Wangen im Allgäu');
  });

  test('two records with the same name share one slice of the blob', () {
    final bytes = buildVst(kSampleStations);
    final x = StationExtract.decode(bytes);
    expect(x.names[3], 'Neustadt');
    expect(x.names[4], 'Neustadt');
    // 'Köln Hbf' 9 + 'Kißlegg Bahnhof' 16 + 'Wangen im Allgäu' 17 + 'Neustadt' 8 = 50 bytes,
    // written once each. A blob that stored the duplicate would be eight bytes longer.
    expect(bytes.length, 32 + 5 * 20 + 50);
  });

  test('the same table twice is the same bytes', () {
    expect(buildVst(kSampleStations), buildVst(kSampleStations));
  });

  test('gzipped and raw are the same extract', () {
    final raw = buildVst(kSampleStations);
    final zipped = Uint8List.fromList(gzip.encode(raw));
    expect(zipped.sublist(0, 2), [0x1f, 0x8b]);
    final a = StationExtract.decode(raw);
    final b = StationExtract.decode(zipped);
    expect(b.names, a.names);
    expect(b.crc32, a.crc32);
    expect(b.tableVersion, a.tableVersion);
  });

  group('a file that is not the file it claims to be is refused whole', () {
    void refuses(String what, Uint8List bytes, {String? because}) {
      test(what, () {
        expect(
          () => StationExtract.decode(bytes),
          throwsA(isA<ExtractFormatException>().having((e) => e.message, 'message', because == null ? anything : contains(because))),
        );
      });
    }

    refuses('a wrong magic', buildVst(kSampleStations, magic: const [0x56, 0x53, 0x54, 0x4E]), because: 'magic');
    refuses('a format this reader does not know', buildVst(kSampleStations, format: 2), because: 'format 2');
    refuses('a count that overruns the buffer', buildVst(kSampleStations, countOverride: 9), because: 'bytes');
    refuses('a truncated file', buildVst(kSampleStations, truncateTo: 90), because: 'bytes');
    refuses('a header shorter than the format allows', buildVst(kSampleStations, truncateTo: 12));
    refuses('a flipped byte after the checksum was taken', buildVst(kSampleStations, flipByteAfterCrc: 40), because: 'checksum');
    refuses(
      'a name that starts outside the blob',
      buildVst(kSampleStations, patchBody: (body) {
        // Record 0's `name_off` at body offset 16, pushed past the end of the blob.
        ByteData.view(body.buffer, body.offsetInBytes, body.length).setUint32(16, 9999, Endian.little);
        return body;
      }),
      because: 'outside the blob',
    );
    refuses(
      'a name of no length at all',
      buildVst(kSampleStations, patchBody: (body) {
        body[14] = 0;
        return body;
      }),
      because: 'no name',
    );
    refuses('a blob shorter than the names in it', buildVst(kSampleStations, blobLenOverride: 20), because: 'bytes');
  });

  test('a grown header and a grown record still read, because the lengths come out of the file', () {
    // This is the additive rule written for a binary file: `format` stays 1, a new header field
    // raises `header_len`, a new record field raises `record_len`, and a phone already in the
    // field keeps reading. A reader that assumed 32 and 20 would refuse this.
    final x = StationExtract.decode(buildVst(kSampleStations, headerLen: 40, recordLen: 24));
    expect(x.headerLen, 40);
    expect(x.recordLen, 24);
    expect(x.ids, [3, 11, 12, 20, 21]);
    expect(x.names.first, 'Köln Hbf');
    expect(x.lat[0], closeTo(50.9430, 5e-7));
  });

  test('byte 15 is reserved, and a reader that asserts it is zero would refuse the next format', () {
    final x = StationExtract.decode(buildVst(kSampleStations, patchBody: (body) {
      body[15] = 0x7F;
      return body;
    }));
    expect(x.count, 5);
    expect(x.names.first, 'Köln Hbf');
  });

  test('the checksum is the ordinary zlib CRC-32', () {
    // "123456789" → 0xCBF43926, the standard check value for CRC-32/ISO-HDLC.
    expect(crc32Of(Uint8List.fromList('123456789'.codeUnits)), 0xCBF43926);
  });
}
