import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// A puzzle picture (docs/51 §8), fetched once and kept in `<Application Support>/puzzles/`.
///
/// A picture never changes — a new one gets a new id — so a file that is there is never asked
/// about again, and the id is the whole cache key. Flutter's own image cache keeps the decoded
/// picture in memory on top of that, keyed by the same id, at one size: no longer than
/// [maxSide] on its longest side, which is all a board on a 3x phone ever needs.
///
/// A file that does not decode is deleted, so the next look fetches it again rather than failing
/// on the same bytes for ever.
@immutable
class PuzzleImageFile extends ImageProvider<PuzzleImageFile> {
  const PuzzleImageFile(this.imageId, this.fetch, {this.directory});

  final String imageId;

  /// The bytes from the server, for when the file is not on disk yet.
  final Future<Uint8List> Function() fetch;

  /// Where `puzzles/` lives. Application Support unless a test says otherwise.
  final Future<Directory> Function()? directory;

  /// The longest side the picture is decoded at. A Verein may upload a camera's full size.
  static const maxSide = 1200;

  /// The id as a file name: the server's are uuids, and anything else loses what a path cannot hold.
  String get fileName => imageId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  /// The picture's bytes: from disk when it was fetched before, else fetched and written. A write
  /// that fails costs a second download next time, never the picture.
  Future<Uint8List> bytes() async {
    final file = await _file();
    final dir = file.parent;
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

  Future<File> _file() async {
    final base = await (directory ?? getApplicationSupportDirectory)();
    return File('${base.path}/puzzles/$fileName');
  }

  /// The picture as a codec, at most [maxSide] long. Bytes that will not decode leave the disk
  /// with the error.
  @visibleForTesting
  Future<ui.Codec> codec(ImageDecoderCallback decode) async {
    final data = await bytes();
    try {
      return await decode(await ui.ImmutableBuffer.fromUint8List(data), getTargetSize: boundedSize);
    } catch (_) {
      try {
        final file = await _file();
        if (file.existsSync()) await file.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// Scaled down to fit [maxSide], proportions kept; the intrinsic size when it already does.
  static ui.TargetImageSize boundedSize(int width, int height) {
    final longest = width > height ? width : height;
    if (longest <= maxSide) return const ui.TargetImageSize();
    return width >= height ? const ui.TargetImageSize(width: maxSide) : const ui.TargetImageSize(height: maxSide);
  }

  Future<ui.Codec> _decode(ImageDecoderCallback decode) => codec(decode);

  @override
  bool operator ==(Object other) => other is PuzzleImageFile && other.imageId == imageId;

  @override
  int get hashCode => imageId.hashCode;
}
