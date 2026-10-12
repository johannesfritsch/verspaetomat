import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:verspaetomat/api/client.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/api/token_store.dart';
import 'package:verspaetomat/state/puzzle_video_store.dart';

/// docs/51 §9b: a finished picture's film is fetched once, with the token, written whole or not
/// at all, and never asked for before the picture is finished.
void main() {
  final film = List<int>.generate(1000, (i) => i % 251);

  ApiPuzzle puzzle(String id, {bool complete = true, int bytes = 1000, bool video = true, String sha = 'abcdef0123456789'}) => ApiPuzzle(
        imageId: id,
        rows: 4,
        cols: 3,
        owned: complete ? [for (var i = 0; i < 12; i++) i] : const [0],
        complete: complete,
        title: 'Bild $id',
        ngoId: 'wald',
        ngoName: 'Wald für morgen e.V.',
        imageUrl: '/v1/puzzle-images/$id',
        hasVideo: video,
        video: complete && video ? ApiPuzzleVideo(url: '/v1/puzzle-videos/$id?v=${sha.substring(0, 8)}', bytes: bytes, seconds: 20, sha256: sha, width: 900, height: 1200) : null,
      );

  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('films'));
  tearDown(() => dir.delete(recursive: true));

  /// A store whose server answers with [answer] for each request, in turn, and records them.
  (PuzzleVideoStore, List<(String, int)>) store(List<http.StreamedResponse Function(int from)> answers) {
    final asked = <(String, int)>[];
    var n = 0;
    final s = PuzzleVideoStore(
      directory: () async => dir,
      fetch: (url, {from = 0}) async {
        asked.add((url, from));
        return answers[n++ < answers.length ? n - 1 : answers.length - 1](from);
      },
    );
    return (s, asked);
  }

  http.StreamedResponse whole(int from) => http.StreamedResponse(Stream.fromIterable([film.sublist(0, 400), film.sublist(400)]), 200, contentLength: film.length);

  Future<PuzzleVideoState> settled(PuzzleVideoStore s, ApiPuzzle p) async {
    for (var i = 0; i < 200; i++) {
      final v = s.stateOf(p).phase;
      if (v == VideoPhase.ready || v == VideoPhase.failed) return s.stateOf(p);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return s.stateOf(p);
  }

  test('fetched once, through .part, under its id and digest', () async {
    final (s, asked) = store([whole]);
    final p = puzzle('w1');
    final seen = <VideoPhase>[];
    s.watch(p).addListener(() => seen.add(s.stateOf(p).phase));
    s.ensure(p);
    final state = await settled(s, p);
    expect(state.phase, VideoPhase.ready);
    expect(state.file!.path, endsWith('/puzzle-videos/w1-abcdef01.mp4'));
    expect(await state.file!.readAsBytes(), film);
    expect(File('${state.file!.path}.part').existsSync(), isFalse);
    expect(seen, containsAllInOrder([VideoPhase.queued, VideoPhase.downloading, VideoPhase.ready]));
    // Once: a second ask finds it here.
    s.ensure(p);
    await settled(s, p);
    expect(asked, hasLength(1));
    final again = PuzzleVideoStore(directory: () async => dir, fetch: (url, {from = 0}) => throw StateError('no second download'));
    for (var i = 0; i < 20 && again.stateOf(p).phase != VideoPhase.ready; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(again.stateOf(p).phase, VideoPhase.ready, reason: 'a new start finds the file on disk');
  });

  test('a replaced film is fetched anew, and the old one goes', () async {
    final (s, asked) = store([whole, whole]);
    final first = puzzle('w8');
    s.ensure(first);
    final a = await settled(s, first);
    expect(a.file!.path, endsWith('/w8-abcdef01.mp4'));
    // The same picture, a new film: the server names another digest and another url.
    final second = puzzle('w8', sha: '99887766aabbccdd');
    s.ensure(second);
    final b = await settled(s, second);
    expect(b.phase, VideoPhase.ready);
    expect(b.file!.path, endsWith('/w8-99887766.mp4'));
    expect(asked.map((x) => x.$1), ['/v1/puzzle-videos/w8?v=abcdef01', '/v1/puzzle-videos/w8?v=99887766']);
    expect(a.file!.existsSync(), isFalse, reason: 'the replaced film is not kept');
  });

  test('never before the picture is finished', () async {
    final (s, asked) = store([whole]);
    final p = puzzle('w2', complete: false);
    s.ensure(p);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(asked, isEmpty);
    expect(s.stateOf(p).phase, VideoPhase.none);
    // And a picture without a film has nothing to fetch.
    s.ensure(puzzle('w3', video: false));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(asked, isEmpty);
  });

  test('the wrong size is thrown away and fetched once more, then given up', () async {
    http.StreamedResponse short(int from) => http.StreamedResponse(Stream.value(film.sublist(0, 700)), 200);
    final (s, asked) = store([short, whole]);
    final p = puzzle('w4');
    s.ensure(p);
    expect((await settled(s, p)).phase, VideoPhase.ready);
    expect(asked, hasLength(2));

    final (s2, asked2) = store([short, short, short]);
    final q = puzzle('w5');
    s2.ensure(q);
    expect((await settled(s2, q)).phase, VideoPhase.failed);
    expect(asked2, hasLength(2), reason: 'one retry, not more');
    expect(Directory('${dir.path}/puzzle-videos').listSync().where((f) => f.path.contains('w5')), isEmpty, reason: 'nothing broken left behind');
  });

  test('a broken connection resumes from where it stopped', () async {
    http.StreamedResponse broken(int from) {
      final c = StreamController<List<int>>();
      c.add(film.sublist(0, 600));
      c.addError(const SocketException('gone'));
      c.close();
      return http.StreamedResponse(c.stream, 200);
    }

    http.StreamedResponse rest(int from) => http.StreamedResponse(Stream.value(film.sublist(from)), 206);
    final (s, asked) = store([broken, rest]);
    final p = puzzle('w6');
    s.ensure(p);
    final state = await settled(s, p);
    expect(state.phase, VideoPhase.ready);
    expect(asked.map((a) => a.$2), [0, 600]);
    expect(await state.file!.readAsBytes(), film);
  });

  test('a connection that goes quiet (a tunnel) counts as broken, and the rest is fetched', () async {
    var n = 0;
    final s = PuzzleVideoStore(
      directory: () async => dir,
      idle: const Duration(milliseconds: 60),
      fetch: (url, {from = 0}) async {
        if (n++ == 0) {
          // 600 bytes, then nothing, and never an end.
          final c = StreamController<List<int>>();
          c.add(film.sublist(0, 600));
          return http.StreamedResponse(c.stream, 200);
        }
        return http.StreamedResponse(Stream.value(film.sublist(from)), 206);
      },
    );
    final p = puzzle('t1');
    s.ensure(p);
    final state = await settled(s, p);
    expect(state.phase, VideoPhase.ready);
    expect(await state.file!.readAsBytes(), film);
    expect(n, 2);
  });

  test('a 404 asks for the list again, and fetches the film it names now', () async {
    final asked = <String>[];
    final replaced = puzzle('r1', sha: '1122334455667788');
    final s = PuzzleVideoStore(
      directory: () async => dir,
      reload: () async => ApiPuzzles(puzzles: [replaced]),
      fetch: (url, {from = 0}) async {
        asked.add(url);
        return url.contains('v=11223344') ? whole(from) : http.StreamedResponse(const Stream.empty(), 404);
      },
    );
    final old = puzzle('r1');
    s.ensure(old);
    // The old film's state is the picture's: it ends where the new one does.
    final state = await settled(s, replaced);
    expect(state.phase, VideoPhase.ready);
    expect(state.file!.path, endsWith('/r1-11223344.mp4'));
    expect(asked, ['/v1/puzzle-videos/r1?v=abcdef01', '/v1/puzzle-videos/r1?v=11223344']);
  });

  test('a 404 that names nothing new is a failure, not a loop', () async {
    var reloads = 0;
    final s = PuzzleVideoStore(
      directory: () async => dir,
      reload: () async {
        reloads++;
        return ApiPuzzles(puzzles: [puzzle('r2')]);
      },
      fetch: (url, {from = 0}) async => http.StreamedResponse(const Stream.empty(), 404),
    );
    final p = puzzle('r2');
    s.ensure(p);
    expect((await settled(s, p)).phase, VideoPhase.failed);
    expect(reloads, 1);
  });

  test('one film that throws does not stop the ones behind it', () async {
    final s = PuzzleVideoStore(
      directory: () async => dir,
      fetch: (url, {from = 0}) async => url.contains('/bad') ? throw const FileSystemException('disk') : whole(from),
    );
    final bad = puzzle('bad'), good = puzzle('good');
    s.ensure(bad);
    s.ensure(good);
    expect((await settled(s, good)).phase, VideoPhase.ready);
    expect(s.stateOf(bad).phase, VideoPhase.failed);
  });

  test('a replaced film leaves no half of the old one either', () async {
    final films = Directory('${dir.path}/puzzle-videos')..createSync(recursive: true);
    File('${films.path}/p9-abcdef01.mp4.part').writeAsBytesSync([1, 2, 3]);
    File('${films.path}/p9-0ld0ld00.mp4').writeAsBytesSync([1, 2, 3]);
    File('${films.path}/other-abcdef01.mp4').writeAsBytesSync([1, 2, 3]);
    final (s, _) = store([whole]);
    final p = puzzle('p9', sha: '99887766aabbccdd');
    s.ensure(p);
    await settled(s, p);
    final left = films.listSync().map((f) => f.uri.pathSegments.last).toSet();
    expect(left, {'p9-99887766.mp4', 'other-abcdef01.mp4'});
  });

  test('clearing forgets every film, on disk and in the states', () async {
    final (s, _) = store([whole]);
    final p = puzzle('c1');
    s.ensure(p);
    await settled(s, p);
    await s.clear();
    expect(Directory('${dir.path}/puzzle-videos').existsSync(), isFalse);
    expect(s.stateOf(puzzle('c1', video: false)).phase, VideoPhase.none);
  });

  test('a 403 is no film, and says so', () async {
    final (s, asked) = store([(from) => http.StreamedResponse(const Stream.empty(), 403)]);
    final p = puzzle('w7');
    s.ensure(p);
    expect((await settled(s, p)).phase, VideoPhase.failed);
    expect(asked, hasLength(1), reason: 'refused is refused: no second try');
    // Again, by hand.
    s.retry(p);
    await settled(s, p);
    expect(asked, hasLength(2));
  });

  test('one at a time, in the order asked for', () async {
    final order = <String>[];
    var running = 0, most = 0;
    final s = PuzzleVideoStore(
      directory: () async => dir,
      fetch: (url, {from = 0}) async {
        running++;
        most = running > most ? running : most;
        order.add(url);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        running--;
        return whole(from);
      },
    );
    final a = puzzle('a'), b = puzzle('b'), c = puzzle('c');
    s.ensure(a);
    s.ensure(b);
    s.ensure(c);
    expect(s.stateOf(c).phase, VideoPhase.queued);
    await settled(s, c);
    expect(order, ['/v1/puzzle-videos/a?v=abcdef01', '/v1/puzzle-videos/b?v=abcdef01', '/v1/puzzle-videos/c?v=abcdef01']);
    expect(most, 1);
  });

  test('Demo: the bundled film is ready at once', () async {
    final (s, asked) = store([whole]);
    final p = ApiPuzzle(
      imageId: 'demo-wald',
      rows: 4,
      cols: 3,
      owned: [for (var i = 0; i < 12; i++) i],
      complete: true,
      title: 'Die erste Reihe am Hang',
      ngoId: 'wald',
      ngoName: 'Wald für morgen e.V.',
      imageUrl: 'assets/demo/puzzles/wald.webp',
      hasVideo: true,
      video: const ApiPuzzleVideo(url: 'assets/demo/puzzles/wald.mp4', bytes: 0),
    );
    s.ensure(p);
    expect(s.stateOf(p).ready, isTrue);
    expect(s.stateOf(p).asset, 'assets/demo/puzzles/wald.mp4');
    expect(asked, isEmpty);
  });

  test('the client asks with the token, and for the rest with a range', () async {
    final headers = <Map<String, String>>[];
    final seen = <Uri>[];
    final client = ApiClient(
      baseUrl: 'https://api.example',
      tokens: TokenStore.over(_Keychain()),
      inner: MockClient.streaming((req, body) async {
        headers.add(req.headers);
        seen.add(req.url);
        return http.StreamedResponse(Stream.value(const [1, 2, 3]), 200);
      }),
    );
    await (await client.puzzleVideo('/v1/puzzle-videos/x?v=abcdef01')).stream.drain<void>();
    await (await client.puzzleVideo('/v1/puzzle-videos/x?v=abcdef01', from: 600)).stream.drain<void>();
    expect(headers[0]['authorization'], 'Bearer tok');
    expect(seen.first.toString(), 'https://api.example/v1/puzzle-videos/x?v=abcdef01', reason: 'the url exactly as named');
    expect(headers[0].containsKey('range'), isFalse);
    expect(headers[1]['range'], 'bytes=600-');
  });

  test('the token goes only to the API\'s own host', () async {
    final headers = <Map<String, String>>[];
    final client = ApiClient(
      baseUrl: 'https://api.example',
      tokens: TokenStore.over(_Keychain()),
      inner: MockClient.streaming((req, body) async {
        headers.add(req.headers);
        return http.StreamedResponse(Stream.value(const [1]), 200);
      }),
    );
    await (await client.puzzleVideo('https://api.example/v1/puzzle-videos/x?v=1')).stream.drain<void>();
    await (await client.puzzleVideo('https://cdn.elsewhere.example/x.mp4')).stream.drain<void>();
    expect(headers[0]['authorization'], 'Bearer tok');
    expect(headers[1].containsKey('authorization'), isFalse);
  });

  test('a 401 re-registers, as every other call does, and asks once more', () async {
    var calls = 0, reauths = 0;
    final client = ApiClient(
      baseUrl: 'https://api.example',
      tokens: TokenStore.over(_Keychain()),
      inner: MockClient.streaming((req, body) async => http.StreamedResponse(Stream.value(const [1]), calls++ == 0 ? 401 : 200)),
    )..onUnauthorized = () async => reauths++;
    final r = await client.puzzleVideo('/v1/puzzle-videos/x?v=1');
    await r.stream.drain<void>();
    expect(r.statusCode, 200);
    expect(reauths, 1);
    expect(calls, 2);
  });
}

/// A keychain with one token in it.
class _Keychain extends FlutterSecureStorage {
  @override
  Future<String?> read({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async =>
      key.endsWith('device_token') ? 'tok' : null;
}
