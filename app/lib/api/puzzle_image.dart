import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// A puzzle picture (docs/51 §8), fetched once and kept in `<Application Support>/puzzles/`.
///
/// A picture never changes — a new one gets a new id — so a file that is there is never asked
/// about again, and the id is the whole cache key. Flutter's own image cache keeps the decoded
/// picture in memory on top of that, keyed by the same id.
@immutable
class PuzzleImageFile extends ImageProvider<PuzzleImageFile> {
  const PuzzleImageFile(this.imageId, this.fetch, {this.directory});

  final String imageId;

  /// The bytes from the server, for when the file is not on disk yet.
  final Future<Uint8List> Function() fetch;

  /// Where `puzzles/` lives. Application Support unless a test says otherwise.
  final Future<Directory> Function()? directory;

  /// The id as a file name: the server's are uuids, and anything else loses what a path cannot hold.
  String get fileName => imageId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  /// The picture's bytes: from disk when it was fetched before, else fetched and written. A write
  /// that fails costs a second download next time, never the picture.
  Future<Uint8List> bytes() async {
    final base = await (directory ?? getApplicationSupportDirectory)();
    final dir = Directory('${base.path}/puzzles');
    final file = File('${dir.path}/$fileName');
    if (file.existsSync()) return file.readAsBytes();
    final data = await fetch();
    try {
      await dir.create(recursive: true);
      // Through a temporary name, so a picture cut off half-written is never mistaken for one.
      final part = File('${file.path}.part');
      await part.writeAsBytes(data, flush: true);
      await part.rename(file.path);
    } catch (_) {}
    return data;
  }

  @override
  Future<PuzzleImageFile> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(PuzzleImageFile key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _decode(decode), scale: 1.0, debugLabel: 'puzzle $imageId');

  Future<ui.Codec> _decode(ImageDecoderCallback decode) async => decode(await ui.ImmutableBuffer.fromUint8List(await bytes()));

  @override
  bool operator ==(Object other) => other is PuzzleImageFile && other.imageId == imageId;

  @override
  int get hashCode => imageId.hashCode;
}
