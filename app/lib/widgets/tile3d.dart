import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../api/models.dart' show PieceTier;
import '../platform/diagnose_log.dart';
import '../theme/tokens.dart';

// ---------------------------------------------------------------------------
// The piece in the hand (docs/51 §9a)
// ---------------------------------------------------------------------------
//
// A flat thing with a body, the way Apple's Fitness badges are — but 2.5D, not a model: the outline
// stands on a wall of stacked copies of itself, the whole is turned through a perspective matrix,
// and the front is lit by a fragment shader (shaders/tile.frag) that rounds its edge off from a
// blurred copy of the outline. One renderer for a piece and, later, for a whole finished picture.

/// `--dart-define=NO_ANIM=1`: still frames. The screenshot tour sets it.
const _still = String.fromEnvironment('NO_ANIM') == '1';

/// The angles a tile is turned by, in radians: [x] tips the top away, [y] turns the right edge away.
@immutable
class TileTilt {
  const TileTilt(this.x, this.y);
  final double x;
  final double y;

  static const flat = TileTilt(0, 0);

  /// Where a tile settles: turned a little, so it reads as a thing and not as a picture.
  static const rest = TileTilt(0.14, -0.14);

  /// The front faces the eye, or the back does.
  bool get front => math.cos(x) * math.cos(y) >= 0;

  @override
  bool operator ==(Object other) => other is TileTilt && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'TileTilt(${(x * 180 / math.pi).toStringAsFixed(1)}°, ${(y * 180 / math.pi).toStringAsFixed(1)}°)';
}

/// Drag, a fling, inertia and the spring back to rest — pure arithmetic, so it can be stepped in a
/// test. Angles in radians, speeds in radians per second.
class TiltPhysics {
  TiltPhysics({this.rest = TileTilt.rest, TileTilt start = TileTilt.flat})
      : x = start.x,
        y = start.y;

  final TileTilt rest;
  double x;
  double y;
  double vx = 0;
  double vy = 0;
  bool dragging = false;

  /// Which side the tile rests on: false the front, true the back (turned half a circle about y).
  bool back = false;

  /// How far a finger turns it before it resists: 60°.
  static const limit = math.pi / 3;

  /// A swipe this fast across turns it over (radians per second of y).
  static const flipSpeed = 9.0;

  static const _stiffness = 90.0;
  static const _damping = 13.0;

  double get _restY => rest.y + (back ? math.pi : 0);

  TileTilt get tilt => TileTilt(x, y);

  /// Past [limit] from where it rests, a finger moves it by less and less.
  static double _resist(double offset) {
    if (offset.abs() <= limit) return offset;
    final over = offset.abs() - limit;
    return offset.sign * (limit + over / (1 + over * 3));
  }

  /// A finger moved by [delta] over a tile [width] wide: half a turn for a full width.
  void drag(Offset delta, double width) {
    dragging = true;
    final k = math.pi / math.max(width, 1);
    // Unwind the resistance, move, wind it up again: so the finger feels it at the limit.
    final ry = _restY;
    y = ry + _resist(_unresist(y - ry) + delta.dx * k);
    x = rest.x + _resist(_unresist(x - rest.x) - delta.dy * k);
    vx = 0;
    vy = 0;
  }

  static double _unresist(double offset) {
    if (offset.abs() <= limit) return offset;
    // Inverse of [_resist] past the limit: s = o / (1 + 3o)  ⇔  o = s / (1 − 3s).
    final s = math.min(offset.abs() - limit, 0.33);
    return offset.sign * (limit + s / (1 - 3 * s));
  }

  /// The finger left with [velocity] (pixels per second) over a tile [width] wide.
  void release(Offset velocity, double width) {
    dragging = false;
    final k = math.pi / math.max(width, 1);
    vy = velocity.dx * k;
    vx = -velocity.dy * k;
    if (vy.abs() > flipSpeed) back = !back;
  }

  /// One step of [dt] seconds towards rest.
  void step(double dt) {
    if (dragging) return;
    // Small steps keep the spring stable whatever the frame rate.
    var left = dt.clamp(0.0, 0.1);
    while (left > 0) {
      final h = math.min(left, 1 / 240);
      final ax = -_stiffness * (x - rest.x) - _damping * vx;
      final ay = -_stiffness * (y - _restY) - _damping * vy;
      vx += ax * h;
      vy += ay * h;
      x += vx * h;
      y += vy * h;
      left -= h;
    }
  }

  /// Stand still where it would come to rest.
  void settle() {
    dragging = false;
    x = rest.x;
    y = _restY;
    vx = 0;
    vy = 0;
  }

  bool get settled => !dragging && (x - rest.x).abs() < 1e-3 && (y - _restY).abs() < 1e-3 && vx.abs() < 1e-2 && vy.abs() < 1e-2;
}

/// The shader, loaded once, and whether it can be used here.
///
/// The shader reads its position from `FlutterFragCoord()`, which is the tile's own coordinate on
/// Impeller and a device pixel on the Skia backend — under a perspective turn those are different
/// things. So the first load draws one probe and reads it back; where the coordinate is not local
/// (Skia: the test bench, an old Android phone), tiles are lit by a gradient instead, and the log
/// says so once.
class TileShading {
  TileShading._(this.program, this.blank, this.matcaps, this.cardboard);

  final ui.FragmentProgram program;

  /// One white pixel for every sampler that has no texture: a shader must have all of them bound.
  final ui.Image blank;

  /// `assets/puzzle/matcap_{minute,quarter,hour}.png`, those that exist.
  final Map<PieceTier, ui.Image> matcaps;

  /// `assets/puzzle/cardboard_normal.png`, if it exists.
  final ui.Image? cardboard;

  static Future<TileShading?>? _loading;
  static TileShading? _ready;

  /// The shading once it has loaded, null before and wherever it cannot be used.
  static TileShading? get ready => _ready;

  /// Draw every tile without the shader — a test of the fallback, or a device that misdraws it.
  @visibleForTesting
  static bool disabled = false;

  @visibleForTesting
  static void debugReset() {
    _loading = null;
    _ready = null;
  }

  static Future<TileShading?> load() => _loading ??= _load();

  static Future<TileShading?> _load() async {
    if (disabled) return null;
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/tile.frag');
      final blank = await _blank();
      if (!await _localCoordinates(program, blank)) {
        DiagnoseLog.instance.add('3d', 'Shader zeichnet in Gerätekoordinaten (Skia) · Teile mit Verlauf statt Licht');
        return null;
      }
      final matcaps = <PieceTier, ui.Image>{};
      for (final t in PieceTier.values) {
        final m = await _asset('assets/puzzle/matcap_${t.name}.png');
        if (m != null) matcaps[t] = m;
      }
      final cardboard = await _asset('assets/puzzle/cardboard_normal.png');
      DiagnoseLog.instance.add('3d', 'Shader geladen · ${matcaps.length} Matcaps · Normal-Map ${cardboard == null ? 'nein' : 'ja'}');
      return _ready = TileShading._(program, blank, matcaps, cardboard);
    } catch (e) {
      DiagnoseLog.instance.add('3d', 'Shader nicht geladen · Teile mit Verlauf statt Licht · $e', bad: true);
      return null;
    }
  }

  static Future<ui.Image> _blank() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint()..color = VColors.paperElevated);
    return recorder.endRecording().toImage(1, 1);
  }

  /// A texture from the bundle, or null when the file is not there.
  static Future<ui.Image?> _asset(String path) async {
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    }
  }

  /// Draws the probe at (8, 8) and reads pixel (9, 9): about 1.5 when the coordinate is local,
  /// about 9.5 when it is the device's.
  static Future<bool> _localCoordinates(ui.FragmentProgram program, ui.Image blank) async {
    final shader = program.fragmentShader();
    for (var i = 0; i < _floats; i++) {
      shader.setFloat(i, 0);
    }
    shader.setFloat(_probe, 1);
    for (var i = 0; i < 4; i++) {
      shader.setImageSampler(i, blank);
    }
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..translate(8, 8)
      ..drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..shader = shader);
    final image = await recorder.endRecording().toImage(16, 16);
    final data = await image.toByteData();
    image.dispose();
    shader.dispose();
    if (data == null) return false;
    return data.getUint8((9 * 16 + 9) * 4) < 5;
  }

  // The float uniforms of tile.frag, in declaration order.
  static const _floats = 21;
  static const _probe = 20;
}

/// The surface normal of the front and the light, both in the tile's own frame (x right, y down,
/// z out of the front), for a tile turned by [t]. The light stays where it is in the room: above
/// and to the left of the person holding the phone.
@visibleForTesting
({List<double> light, List<double> view}) tileLight(TileTilt t) {
  List<double> local(double wx, double wy, double wz) {
    // Into the tile's frame: undo rotateX, then rotateY (Flutter's z points away from the eye).
    final ca = math.cos(t.x), sa = math.sin(t.x), cb = math.cos(t.y), sb = math.sin(t.y);
    final y1 = wy * ca + wz * sa;
    final z1 = -wy * sa + wz * ca;
    final x2 = wx * cb - z1 * sb;
    final z2 = wx * sb + z1 * cb;
    final len = math.sqrt(x2 * x2 + y1 * y1 + z2 * z2);
    return [x2 / len, y1 / len, -z2 / len];
  }

  return (light: local(-0.45, -0.75, -1.0), view: local(0, 0, -1));
}

/// A blurred mask of each outline, once per tile: the shader's height map. Kept for the last few
/// tiles, so opening the same piece twice costs nothing.
final Map<String, ui.Image> _heights = {};

ui.Image _heightMap(String key, Path outline, Size box) {
  final hit = _heights.remove(key);
  if (hit != null) return _heights[key] = hit;
  const longest = 192.0;
  final s = longest / box.longestSide;
  final w = (box.width * s).ceil(), h = (box.height * s).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(s);
  canvas.drawRect(Offset.zero & box, Paint()..color = VColors.ink);
  canvas.drawPath(
    outline,
    Paint()
      ..color = VColors.paperElevated
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, box.shortestSide * 0.045),
  );
  final image = recorder.endRecording().toImageSync(w, h);
  _heights[key] = image;
  while (_heights.length > 24) {
    _heights.remove(_heights.keys.first)?.dispose();
  }
  return image;
}

/// A thing with a front, a back and a body between them, that a finger can turn (docs/51 §9a).
class Tile3D extends StatefulWidget {
  const Tile3D({
    super.key,
    required this.cacheKey,
    required this.outline,
    required this.image,
    required this.source,
    required this.back,
    required this.width,
    this.tier,
    this.depth = 0.05,
    this.overlay,
    this.onTap,
    this.tilt,
    this.start = TileTilt.flat,
  });

  /// Names the outline for the height-map cache: the picture and the slot.
  final String cacheKey;

  /// The shape, in any coordinates: its bounds are the tile. A piece is `PuzzleCut.slotPath`, a
  /// whole picture a rounded rectangle.
  final Path outline;

  /// The picture, or null while it loads (the face is then plain card).
  final ui.Image? image;

  /// The part of [image], in its pixels, that lies over the outline's bounds.
  final Rect source;

  /// The other side, laid out at the tile's size and clipped to its outline.
  final WidgetBuilder back;

  /// How wide the tile is drawn.
  final double width;

  /// The material. Null is a whole picture: board, a little satin, no lip.
  final PieceTier? tier;

  /// How thick, as a share of [width].
  final double depth;

  /// Laid on the front and turned with it — the play button of a picture with a video (§9b).
  final Widget? overlay;

  /// A tap, as opposed to a drag: a finished picture plays its film (§9b).
  final VoidCallback? onTap;

  /// A fixed tilt: no finger, no sensor, no spring. For still frames.
  final TileTilt? tilt;

  /// Where an interactive tile starts before it springs to rest — flat when it rises out of its slot.
  final TileTilt start;

  /// The phone's lean, as a fraction of full tilt in x and y (−1 … 1). Null: no sensor — tests set it.
  static Stream<Offset> Function()? motion = _accelerometer;

  static Stream<Offset> _accelerometer() {
    // `flutter test` has no sensors, and a channel nobody answers is reported as an error.
    if (Platform.environment.containsKey('FLUTTER_TEST')) return const Stream.empty();
    return accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).map((e) => Offset((e.x / 9.81).clamp(-1.0, 1.0), (e.y / 9.81).clamp(-1.0, 1.0)));
  }

  /// The lean the phone adds, at most this much each way: about 7°.
  static const parallax = 0.12;

  @override
  State<Tile3D> createState() => _Tile3DState();
}

class _Tile3DState extends State<Tile3D> with SingleTickerProviderStateMixin {
  late final TiltPhysics _physics = TiltPhysics(start: widget.start);
  late final Ticker _ticker;
  final _frame = _Frame();
  Duration _last = Duration.zero;
  StreamSubscription<Offset>? _motion;
  Offset _lean = Offset.zero;
  Offset _leanTarget = Offset.zero;
  bool _wasFront = true;
  bool _calm = false;

  ui.FragmentShader? _shader;
  late Path _outline;
  late Path _mirrored;
  late Size _box;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _layout();
    final ready = TileShading.ready;
    if (ready != null) {
      _shader = ready.program.fragmentShader();
    } else {
      TileShading.load().then((s) {
        if (!mounted || s == null) return;
        setState(() => _shader = s.program.fragmentShader());
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _calm = _still || MediaQuery.disableAnimationsOf(context);
    final interactive = widget.tilt == null;
    if (!interactive) return;
    if (_calm) {
      _physics.settle();
      _motion?.cancel();
      _motion = null;
      if (_ticker.isActive) _ticker.stop();
    } else {
      _listen();
      _kick();
    }
  }

  @override
  void didUpdateWidget(Tile3D old) {
    super.didUpdateWidget(old);
    if (old.outline != widget.outline || old.width != widget.width) _layout();
  }

  void _layout() {
    final b = widget.outline.getBounds();
    final s = widget.width / b.width;
    final m = Matrix4.identity()
      ..scaleByDouble(s, s, 1, 1)
      ..translateByDouble(-b.left, -b.top, 0, 1);
    _outline = widget.outline.transform(m.storage);
    _box = Size(b.width * s, b.height * s);
    // The back is seen from behind: its outline is the front's, mirrored left to right.
    final flip = Matrix4.identity()
      ..translateByDouble(_box.width, 0, 0, 1)
      ..scaleByDouble(-1, 1, 1, 1);
    _mirrored = _outline.transform(flip.storage);
  }

  void _listen() {
    if (_motion != null) return;
    final source = Tile3D.motion;
    if (source == null) return;
    try {
      _motion = source().listen((v) {
        _leanTarget = v;
        _kick();
      }, onError: (_) {});
    } catch (_) {}
  }

  void _kick() {
    if (!_ticker.isActive && widget.tilt == null && !_calm) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration now) {
    final dt = _last == Duration.zero ? 1 / 60 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    _physics.step(dt);
    // The phone's lean, smoothed: a hand is never still and the picture should not shiver.
    _lean = Offset.lerp(_lean, _leanTarget, (dt * 6).clamp(0.0, 1.0))!;
    _frame.tick();
    final front = _current.front;
    if (front != _wasFront) {
      _wasFront = front;
      HapticFeedback.lightImpact();
    }
    final leaning = (_lean - _leanTarget).distance > 1e-3;
    // At rest and level: no frames until a finger or the phone moves it again.
    if (_physics.settled && !leaning) _ticker.stop();
  }

  TileTilt get _current {
    final fixed = widget.tilt;
    if (fixed != null) return fixed;
    final t = _physics.tilt;
    // Leaning the phone forward tips the top towards you; sideways, turns it towards the low side.
    return TileTilt(t.x - _lean.dy * Tile3D.parallax, t.y + _lean.dx * Tile3D.parallax);
  }

  @override
  void dispose() {
    _motion?.cancel();
    _ticker.dispose();
    _shader?.dispose();
    _frame.dispose();
    super.dispose();
  }

  /// Turned about the tile's centre and seen in perspective, [z] behind the front face; [flip]
  /// turns it about once more, for the back. Written into [into], or a new matrix.
  Matrix4 _matrix(TileTilt t, {double z = 0, bool flip = false, Matrix4? into}) {
    final cx = _box.width / 2, cy = _box.height / 2;
    _perspective.setEntry(3, 2, 0.0012 * 300 / math.max(_box.longestSide, 1));
    final m = (into ?? Matrix4.zero())
      ..setIdentity()
      ..translateByDouble(cx, cy, 0, 1)
      ..multiply(_perspective)
      ..rotateX(t.x)
      ..rotateY(t.y)
      ..translateByDouble(0, 0, z, 1);
    if (flip) m.rotateY(math.pi);
    m.translateByDouble(-cx, -cy, 0, 1);
    return m;
  }

  static final _perspective = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    final painter = _TilePainter(
      state: this,
      outline: _outline,
      box: _box,
      shader: _shader,
      shading: TileShading.ready,
      image: widget.image,
      source: widget.source,
      tier: widget.tier,
      depth: widget.depth * widget.width,
      heights: () => _heightMap('${widget.cacheKey}@${_box.width.round()}', _outline, _box),
      repaint: _frame,
    );
    Widget tile = SizedBox.fromSize(
      size: _box,
      child: AnimatedBuilder(
        animation: _frame,
        builder: (context, _) {
          final t = _current;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: CustomPaint(painter: painter)),
              if (!t.front)
                Positioned.fill(
                  child: Transform(
                    transform: _matrix(t, z: widget.depth * widget.width, flip: true),
                    child: ClipPath(clipper: _PathClipper(_mirrored), child: widget.back(context)),
                  ),
                ),
              if (t.front && widget.overlay != null) Positioned.fill(child: Transform(transform: _matrix(t), child: widget.overlay)),
            ],
          );
        },
      ),
    );
    if (widget.tilt != null) return tile;
    tile = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onPanStart: (_) => _physics.dragging = true,
      onPanUpdate: (d) {
        _physics.drag(d.delta, _box.width);
        _frame.tick();
        final front = _current.front;
        if (front != _wasFront) {
          _wasFront = front;
          HapticFeedback.lightImpact();
        }
      },
      onPanEnd: (d) {
        // Still frames keep the swipe that turns it over, and skip the motion that gets it there.
        _physics.release(d.velocity.pixelsPerSecond, _box.width);
        if (_calm) {
          _physics.settle();
          _frame.tick();
        } else {
          _kick();
        }
      },
      child: tile,
    );
    return tile;
  }
}

/// A listenable that says „draw again", without a value to compare.
class _Frame extends ChangeNotifier {
  void tick() => notifyListeners();
}

class _PathClipper extends CustomClipper<Path> {
  _PathClipper(this.path);
  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(_PathClipper old) => old.path != path;
}

/// The body and the front of a tile. The back, when it shows, is a widget laid over this.
class _TilePainter extends CustomPainter {
  _TilePainter({
    required this.state,
    required this.outline,
    required this.box,
    required this.shader,
    required this.shading,
    required this.image,
    required this.source,
    required this.tier,
    required this.depth,
    required this.heights,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final _Tile3DState state;
  final Path outline;
  final Size box;
  final ui.FragmentShader? shader;
  final TileShading? shading;
  final ui.Image? image;
  final Rect source;
  final PieceTier? tier;
  final double depth;
  final ui.Image Function() heights;

  static const _layers = 14;

  // Reused from frame to frame: a frame allocates no paints.
  static final _wall = Paint();
  static final _m = Matrix4.zero();
  static final _face = Paint()..filterQuality = FilterQuality.medium;
  static final _shadow = Paint();

  Color get _lip => switch (tier) {
        PieceTier.quarter => VColors.ink,
        PieceTier.hour => VColors.red,
        _ => VColors.hairlineStrong,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final t = state._current;
    final front = t.front;

    // The shadow of a thing held above a surface, flat under all of it.
    canvas.save();
    canvas.transform(state._matrix(t, z: depth, into: _m).storage);
    final s = VShadow.cardRaised.first;
    _shadow
      ..color = s.color.withValues(alpha: (s.color.a * 2.5).clamp(0.0, 1.0))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, Shadow.convertRadiusToSigma(s.blurRadius * 1.6));
    canvas.translate(s.offset.dx * 3, s.offset.dy * 3);
    canvas.drawPath(outline, _shadow);
    canvas.restore();

    // The wall: the outline stacked from the far face to the near one, darker towards the back.
    // The two layers at the front carry the lip's colour on a rare piece.
    for (var k = 0; k <= _layers; k++) {
      final i = front ? _layers - k : k;
      final f = i / _layers;
      final lip = tier != null && tier != PieceTier.minute && i <= 1;
      _wall.color = lip ? _lip : Color.lerp(VColors.hairlineStrong, VColors.ink3, f)!;
      canvas.save();
      canvas.transform(state._matrix(t, z: depth * f, into: _m).storage);
      canvas.drawPath(outline, _wall);
      canvas.restore();
    }

    if (!front) return;
    canvas.save();
    canvas.transform(state._matrix(t, into: _m).storage);
    canvas.clipPath(outline);
    final sh = shader, sd = shading, img = image;
    if (sh != null && sd != null && img != null) {
      _shade(canvas, sh, sd, img, t);
    } else {
      _flat(canvas, img, t);
    }
    canvas.restore();
  }

  void _shade(Canvas canvas, ui.FragmentShader sh, TileShading sd, ui.Image img, TileTilt t) {
    final height = heights();
    final l = tileLight(t);
    final rim = _lip;
    var i = 0;
    void f(double v) => sh.setFloat(i++, v);
    f(box.width);
    f(box.height);
    f(source.left / img.width);
    f(source.top / img.height);
    f(source.width / img.width);
    f(source.height / img.height);
    l.light.forEach(f);
    l.view.forEach(f);
    f(rim.r);
    f(rim.g);
    f(rim.b);
    f(switch (tier) { PieceTier.minute => 0, PieceTier.quarter => 1, PieceTier.hour => 2, null => 3 });
    f(1 / height.width);
    f(1 / height.height);
    final matcap = tier == null ? null : sd.matcaps[tier];
    f(matcap == null ? 0 : 1);
    f(sd.cardboard == null ? 0 : 1);
    f(0);
    sh.setImageSampler(0, img);
    sh.setImageSampler(1, height);
    sh.setImageSampler(2, matcap ?? sd.blank);
    sh.setImageSampler(3, sd.cardboard ?? sd.blank);
    _face.shader = sh;
    canvas.drawRect(Offset.zero & box, _face);
    _face.shader = null;
  }

  /// Without the shader: the photo, and a wash of light and shade across it that turns with the
  /// tile, and the lip as a line.
  void _flat(Canvas canvas, ui.Image? img, TileTilt t) {
    if (img != null) {
      canvas.drawImageRect(img, source, Offset.zero & box, _face);
    } else {
      canvas.drawRect(Offset.zero & box, _face..color = VColors.track);
    }
    final l = tileLight(t).light;
    final dir = Offset(l[0], l[1]);
    final c = box.center(Offset.zero);
    final reach = box.longestSide / 2;
    final from = c + dir * reach, to = c - dir * reach;
    canvas.drawRect(
      Offset.zero & box,
      Paint()
        ..shader = ui.Gradient.linear(from, to, [
          VColors.paperElevated.withValues(alpha: 0.28),
          VColors.paperElevated.withValues(alpha: 0),
          VColors.ink.withValues(alpha: 0.22),
        ], [0, 0.5, 1]),
    );
    if (tier == PieceTier.quarter || tier == PieceTier.hour) {
      canvas.drawPath(
        outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = box.shortestSide * 0.05
          ..color = _lip,
      );
    }
  }

  @override
  bool shouldRepaint(_TilePainter old) =>
      old.shader != shader || old.shading != shading || old.image != image || old.source != source || old.tier != tier || old.depth != depth || old.outline != outline;
}
