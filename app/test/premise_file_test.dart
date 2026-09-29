import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/stations/premise_file.dart';
import 'package:verspaetomat/stations/station_extract.dart' show ExtractFormatException;

/// The shared fixture (`test/fixtures/umrisse-fixture.bin`) is rendered by the server
/// (`outlines.rs`, `fixture_set`); these are its numbers. Swift and Kotlin assert the same ones.
void main() {
  final bytes = File('test/fixtures/umrisse-fixture.bin').readAsBytesSync();

  test('the fixture reads to the numbers the server wrote', () {
    final f = PremiseFile.decode(bytes);
    expect(f.version, 1790700677);
    expect(f.generatedAt, DateTime.utc(2026, 9, 29));
    expect(f.premises.keys, [3, 17, 4711]);
    final small = f.premises[3]!;
    expect(small.ring.radiusM, 300);
    expect(small.touch.single.radiusM, 120);
    expect(small.corners, hasLength(3));
    final koeln = f.premises[17]!;
    expect(koeln.ring.lat, 50.943);
    expect(koeln.ring.lon, 6.9587);
    expect(koeln.ring.radiusM, 429);
    expect(koeln.touch.map((t) => t.radiusM), [150, 139, 135]);
    expect(koeln.touch.first.lat, 50.9435);
    expect(koeln.corners, hasLength(24));
    final big = f.premises[4711]!;
    expect(big.ring.radiusM, 1000);
    expect(big.touch, hasLength(6));
    expect(big.touch.last.radiusM, 125);
  });

  test('a gzipped body reads the same', () {
    final f = PremiseFile.decode(Uint8List.fromList(gzip.encode(bytes)));
    expect(f.premises.keys, [3, 17, 4711]);
    expect(f.byteLength, bytes.length);
  });

  test('one flipped byte, a short file, a wrong magic: refused whole', () {
    final flipped = Uint8List.fromList(bytes)..[bytes.length - 1] ^= 1;
    expect(() => PremiseFile.decode(flipped), throwsA(isA<ExtractFormatException>()));
    expect(() => PremiseFile.decode(Uint8List.sublistView(bytes, 0, bytes.length - 1)), throwsA(isA<ExtractFormatException>()));
    final magic = Uint8List.fromList(bytes)..[0] = 0x41;
    expect(() => PremiseFile.decode(magic), throwsA(isA<ExtractFormatException>()));
  });
}
