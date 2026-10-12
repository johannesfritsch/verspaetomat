import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../api/models.dart';
import '../../state/puzzle_video_store.dart';
import '../../theme/tokens.dart';
import 'puzzle_widgets.dart';

/// Plays a finished picture's film over everything (docs/51 §9b), then fades back to the picture.
Future<void> showPuzzleVideo(BuildContext context, ApiPuzzle puzzle, PuzzleVideoState film) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      // Opaque: what is under the film stops drawing (and the tile under it stops turning).
      opaque: true,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (context, animation, _) => FadeTransition(opacity: animation, child: PuzzleVideoPage(puzzle: puzzle, film: film)),
    ),
  );
}

/// The film full-screen on the dark ground: it starts at once; a tap pauses it and shows the way
/// out, a swipe down or the cross leaves, and at its end it hands back to the picture.
class PuzzleVideoPage extends StatefulWidget {
  const PuzzleVideoPage({super.key, required this.puzzle, required this.film});
  final ApiPuzzle puzzle;
  final PuzzleVideoState film;

  /// The phone's audio session (ios/Runner/AppDelegate.swift): sound only when it is not muted.
  static const audio = MethodChannel('de.verspaetomat/audio');

  @override
  State<PuzzleVideoPage> createState() => _PuzzleVideoPageState();
}

class _PuzzleVideoPageState extends State<PuzzleVideoPage> {
  VideoPlayerController? _c;
  bool _failed = false;
  bool _controls = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  /// Android has no silent switch an audio session obeys: a phone on silent or vibrate starts the
  /// film without sound, with a button to turn it on.
  bool _muted = false;

  Future<void> _audio(String method) async {
    if (!Platform.isIOS) return;
    try {
      await PuzzleVideoPage.audio.invokeMethod<void>(method);
    } catch (_) {}
  }

  Future<bool> _phoneSilent() async {
    if (!Platform.isAndroid) return false;
    try {
      return await PuzzleVideoPage.audio.invokeMethod<String>('ringerMode') != 'normal';
    } catch (_) {
      return false;
    }
  }

  Future<void> _start() async {
    final f = widget.film;
    // Mixing with others keeps video_player from taking the session over; the session is then set
    // to follow the ring/silent switch once the player has set it up its own way.
    final options = VideoPlayerOptions(mixWithOthers: true);
    final c = f.asset != null
        ? VideoPlayerController.asset(f.asset!, videoPlayerOptions: options)
        : VideoPlayerController.file(f.file!, videoPlayerOptions: options);
    // Closed before it started: nothing to start.
    bool gone() {
      if (mounted) return false;
      c.dispose().catchError((_) {});
      return true;
    }

    try {
      await _audio('remember');
      if (gone()) return;
      final silent = await _phoneSilent();
      if (gone()) return;
      _c = c;
      await c.initialize();
      if (!mounted) return;
      await _audio('ambient');
      if (!mounted) return;
      if (silent) {
        _muted = true;
        await c.setVolume(0);
        if (!mounted) return;
      }
      c.addListener(_onTick);
      await c.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _toggleSound() async {
    final c = _c;
    if (c == null) return;
    setState(() => _muted = !_muted);
    await c.setVolume(_muted ? 0 : 1);
  }

  /// At the end, back to the picture.
  void _onTick() {
    final v = _c?.value;
    if (v == null || !v.isInitialized || _closing) return;
    if (v.duration > Duration.zero && v.position >= v.duration && !v.isPlaying) _close();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).maybePop();
  }

  void _toggle() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
        _controls = true;
      } else {
        c.play();
        _controls = false;
      }
    });
  }

  @override
  void dispose() {
    final c = _c;
    c?.removeListener(_onTick);
    c?.dispose().catchError((_) {});
    unawaited(_audio('restore'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.puzzle;
    final v = p.video;
    final c = _c;
    final playing = c != null && c.value.isInitialized;
    final seconds = (v?.seconds ?? 0).round();
    final aspect = playing ? c.value.aspectRatio : (v?.aspectRatio ?? p.aspectRatio);

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Video: ${p.title}, $seconds Sekunden',
      onDismiss: _close,
      child: Material(
        color: VColors.surfaceDark,
        child: GestureDetector(
          key: const Key('puzzle-video'),
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 300) _close();
          },
          child: Stack(
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: aspect,
                  // The picture stands until the film's first frame, which is the same picture.
                  child: playing ? VideoPlayer(c) : PuzzleBoardOf(p, complete: true),
                ),
              ),
              if (_failed)
                Positioned(
                  left: VSpace.l,
                  right: VSpace.l,
                  bottom: VSpace.xxl,
                  child: Text('Das Video lässt sich gerade nicht abspielen.', style: VText.body.copyWith(color: VColors.inkOnDark2), textAlign: TextAlign.center),
                ),
              // Only where the film started silent because the phone is: a way to hear it.
              if (playing && Platform.isAndroid && (_muted || _controls))
                Positioned(
                  top: 0,
                  left: VSpace.s,
                  child: SafeArea(
                    child: IconButton(
                      key: const Key('puzzle-video-sound'),
                      tooltip: _muted ? 'Ton an' : 'Ton aus',
                      constraints: const BoxConstraints.tightFor(width: VControl.touch, height: VControl.touch),
                      icon: Icon(_muted ? Icons.volume_off : Icons.volume_up, color: VColors.inkOnDark),
                      onPressed: _toggleSound,
                    ),
                  ),
                ),
              if (_controls || _failed || !playing) ...[
                Positioned(
                  top: 0,
                  right: VSpace.s,
                  child: SafeArea(
                    child: Semantics(
                      label: 'Schließen',
                      button: true,
                      excludeSemantics: true,
                      onTap: _close,
                      child: IconButton(
                        key: const Key('puzzle-video-close'),
                        tooltip: 'Schließen',
                        constraints: const BoxConstraints.tightFor(width: VControl.touch, height: VControl.touch),
                        icon: const Icon(Icons.close, color: VColors.inkOnDark),
                        onPressed: _close,
                      ),
                    ),
                  ),
                ),
              ],
              if (playing)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: AnimatedOpacity(
                      opacity: _controls ? 1 : 0.35,
                      duration: const Duration(milliseconds: 200),
                      child: SizedBox(
                        height: 2,
                        child: VideoProgressIndicator(
                          c,
                          allowScrubbing: false,
                          padding: EdgeInsets.zero,
                          colors: const VideoProgressColors(playedColor: VColors.inkOnDark, bufferedColor: VColors.trackOnDark, backgroundColor: VColors.trackOnDark),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
