import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../platform/geofence.dart';
import '../theme/tokens.dart';

/// The geofence set, drawn to scale (issue #29).
///
/// It answers "how are the fences set?" with a picture instead of a list of numbers, because the
/// thing that is actually wrong is usually a shape: a disc drawn around the wrong town, a station
/// that is nowhere near the others, a 300 m circle that does not reach the platform you stand on.
///
/// **There is no map under it, on purpose.** No tiles are fetched and no map package is linked in,
/// so nothing about where this phone has been leaves the device to draw this — which is the whole
/// point of the page. What is drawn is only what the phone itself reported: the circles it is
/// monitoring, at their true positions and their true radii, on an equirectangular projection
/// fitted to them. There are no streets, no coastlines and no labels from anywhere else.
///
/// **Nothing here is invented.** A region native did not give coordinates for is not drawn at all
/// and is counted in [unplaced] instead, and the disc centre is drawn as the disc centre — never
/// as the phone's position, which this app does not record.
class VGeofenceMap extends StatelessWidget {
  const VGeofenceMap({
    super.key,
    required this.regions,
    this.disc,
    this.nudgeRadiusM = GeofenceConfig.defaultNudgeRadiusM,
    this.focus,
    this.highlightId,
    this.height = 220,
  });

  /// Everything native is monitoring, including the umbrella.
  final List<GeofenceRegion> regions;

  /// The coverage disc: not a monitored region, but the thing that decides when the set is redrawn.
  final GeofenceDisc? disc;

  /// The tighter circle that actually decides whether a nudge is scheduled (docs/25 §3). Drawn
  /// only when the scale makes it a real circle rather than a dot pretending to be one.
  ///
  /// It comes from [GeofenceConfig] rather than a literal, so a change to the fence moves the
  /// drawing with it. `num`, not `double`, only because the constant is an int and a default
  /// value has to be a constant expression.
  final num nudgeRadiusM;

  /// A single station to fill the frame with, so its two radii can be read. Null shows everything.
  final GeofenceRegion? focus;

  /// One region to light *without* changing the scale — the station a replayed log line happened
  /// at. While it is set it is the only lit circle, because "the phone is in here now" and "this
  /// is where that line happened" are two different claims and must not share a mark.
  final String? highlightId;

  final double height;

  /// Regions native gave no coordinates for. They exist, and they are not on the picture.
  int get unplaced => regions.where((r) => !r.hasPosition).length;

  @override
  Widget build(BuildContext context) {
    final placed = regions.where((r) => r.hasPosition).toList();
    if (placed.isEmpty && disc == null) {
      // Two different facts, and telling them apart matters: an empty set means the fence is not
      // running, while a full set with no coordinates means it is running and this picture cannot
      // show it — which would otherwise contradict the region count printed right below.
      return Container(
        height: height,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: VSpace.m),
        decoration: BoxDecoration(border: Border.all(color: VColors.rule), borderRadius: BorderRadius.circular(4)),
        child: Text(
          regions.isEmpty
              ? 'Nichts registriert, nichts zu zeichnen.'
              : 'Keine der ${regions.length} Regionen hat Koordinaten geliefert — nichts zu zeichnen.',
          style: VText.caption,
          textAlign: TextAlign.center,
        ),
      );
    }
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: VColors.surfaceMuted,
        border: Border.all(color: VColors.rule),
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        key: const Key('geofence-map'),
        painter: _GeofencePainter(
          regions: placed,
          disc: disc,
          nudgeRadiusM: nudgeRadiusM,
          focus: focus != null && focus!.hasPosition ? focus : null,
          highlightId: highlightId,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// Equirectangular, which is wrong for a continent and exact enough for a disc a few hundred
/// kilometres wide — the error over the widest set this app ever registers is under a pixel.
///
/// Public because this is where a bug makes the picture lie: a station drawn in the wrong place
/// is worse than no picture at all, so it is tested directly.
class GeofenceProjection {
  GeofenceProjection({required this.centreLat, required this.centreLon, required this.metresPerPx, required this.size});

  final double centreLat;
  final double centreLon;
  final double metresPerPx;
  final Size size;

  static const metresPerDegreeLat = 111320.0;

  double get metresPerDegreeLon => metresPerDegreeLat * math.cos(centreLat * math.pi / 180);

  Offset toPx(double lat, double lon) => Offset(
        size.width / 2 + ((lon - centreLon) * metresPerDegreeLon) / metresPerPx,
        // North is up, and y grows downwards.
        size.height / 2 - ((lat - centreLat) * metresPerDegreeLat) / metresPerPx,
      );

  double radiusPx(double metres) => metres / metresPerPx;
}

/// The numbers a scale bar is allowed to say.
///
/// A bar labelled "3.7 km" is unreadable at a glance, so the label is always 1, 2 or 5 times a
/// power of ten. It rounds **down**: the bar is drawn from the number, so the label always
/// matches the line exactly, and rounding up would let a bar asked to be a third of the frame
/// come out at five sixths of it and run into whatever is drawn there.
class VGeofenceMapScale {
  const VGeofenceMapScale._();

  /// The largest 1/2/5 × 10ⁿ that is not longer than [metres].
  static double round(double metres) {
    if (metres <= 0) return 1;
    final magnitude = math.pow(10, (math.log(metres) / math.ln10).floor()).toDouble();
    for (final step in [5.0, 2.0, 1.0]) {
      if (metres >= step * magnitude) return step * magnitude;
    }
    return magnitude;
  }
}

class _GeofencePainter extends CustomPainter {
  _GeofencePainter({
    required this.regions,
    required this.disc,
    required this.nudgeRadiusM,
    required this.focus,
    required this.highlightId,
  });

  final List<GeofenceRegion> regions;
  final GeofenceDisc? disc;
  final num nudgeRadiusM;
  final GeofenceRegion? focus;
  final String? highlightId;

  /// A circle smaller than this is not drawn as a circle: at that size a stroke is thicker than
  /// the thing it describes, and a reader would take a 300 m region for a 3 km one.
  static const minHonestRadiusPx = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final proj = _fit(size);
    if (proj == null) return;

    final d = disc;
    if (d != null && focus == null) _paintDisc(canvas, proj, d);

    for (final r in regions) {
      if (r.isUmbrella) _paintUmbrella(canvas, proj, r);
    }
    for (final r in regions) {
      if (!r.isUmbrella) _paintStation(canvas, proj, r);
    }

    if (d != null) _paintDiscCentre(canvas, proj, d);
    _paintScaleBar(canvas, size, proj);
  }

  /// Frames everything that will be drawn, with room for the widest circle and a margin, so the
  /// picture is never cropped in a way that hides a region.
  GeofenceProjection? _fit(Size size) {
    final f = focus;
    if (f != null) {
      // One station, filling the frame: four times its own region, so both radii are readable
      // and there is space around them.
      final span = math.max(f.radiusM, nudgeRadiusM.toDouble()) * 4;
      return GeofenceProjection(
        centreLat: f.lat!,
        centreLon: f.lon!,
        metresPerPx: (span * 2) / math.min(size.width, size.height),
        size: size,
      );
    }

    final lats = <double>[], lons = <double>[];
    var reach = 0.0;
    for (final r in regions) {
      lats.add(r.lat!);
      lons.add(r.lon!);
      reach = math.max(reach, r.radiusM);
    }
    final d = disc;
    if (d != null) {
      lats.add(d.lat);
      lons.add(d.lon);
      reach = math.max(reach, d.radiusM);
    }
    if (lats.isEmpty) return null;

    final centreLat = (lats.reduce(math.max) + lats.reduce(math.min)) / 2;
    final centreLon = (lons.reduce(math.max) + lons.reduce(math.min)) / 2;
    final mPerLon = GeofenceProjection.metresPerDegreeLat * math.cos(centreLat * math.pi / 180);

    var halfWidthM = 0.0, halfHeightM = 0.0;
    for (var i = 0; i < lats.length; i++) {
      halfWidthM = math.max(halfWidthM, (lons[i] - centreLon).abs() * mPerLon);
      halfHeightM = math.max(halfHeightM, (lats[i] - centreLat).abs() * GeofenceProjection.metresPerDegreeLat);
    }
    halfWidthM += reach;
    halfHeightM += reach;

    // A set of one station has no extent at all; give it something to sit in.
    final perPxX = (halfWidthM * 2) / math.max(1, size.width - 24);
    final perPxY = (halfHeightM * 2) / math.max(1, size.height - 24);
    final metresPerPx = math.max(math.max(perPxX, perPxY), 1.0);

    return GeofenceProjection(centreLat: centreLat, centreLon: centreLon, metresPerPx: metresPerPx, size: size);
  }

  /// The coverage disc. Not monitored by iOS — it is the app's own bookkeeping about when to ask
  /// the backend again — so it is drawn as a dashed outline rather than a solid one.
  void _paintDisc(Canvas canvas, GeofenceProjection proj, GeofenceDisc d) {
    final centre = proj.toPx(d.lat, d.lon);
    final r = proj.radiusPx(d.radiusM);
    if (r < minHonestRadiusPx) return;
    canvas.drawCircle(centre, r, Paint()..color = VColors.greyFill.withValues(alpha: 0.55));
    _dashedCircle(canvas, centre, r, Paint()
      ..color = VColors.ink3
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
  }

  void _paintUmbrella(Canvas canvas, GeofenceProjection proj, GeofenceRegion r) {
    final centre = proj.toPx(r.lat!, r.lon!);
    final px = proj.radiusPx(r.radiusM);
    if (px < minHonestRadiusPx) return;
    _dashedCircle(canvas, centre, px, Paint()
      ..color = VColors.ink2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  /// A station: its monitored circle, its nudge circle when the scale can carry one, and always a
  /// dot — because at a country's scale a 300 m circle is smaller than a pixel and a station that
  /// is not drawn at all reads as a station that is not registered.
  void _paintStation(Canvas canvas, GeofenceProjection proj, GeofenceRegion r) {
    final centre = proj.toPx(r.lat!, r.lon!);
    final regionPx = proj.radiusPx(r.radiusM);

    // STYLE.md: `redBright` is the lit red and means *this one* — today's bar, the unread badge.
    // That is exactly what a highlighted region is. The deep `red` means *do this* or *this is
    // money*, which nothing on a diagnostics map ever does, and one token cannot carry both.
    //
    // A replay takes the mark over completely: while one is running the lit circle means "this
    // line happened here", and letting "the phone is inside" keep it too would put one colour on
    // two claims at the same moment.
    final highlighted = highlightId != null
        ? r.id == highlightId
        : r.inside || (focus != null && focus!.id == r.id);
    final ink = highlighted ? VColors.redBright : VColors.ink;

    if (regionPx >= minHonestRadiusPx) {
      canvas.drawCircle(centre, regionPx, Paint()..color = (highlighted ? VColors.redTint : VColors.greyCircle).withValues(alpha: 0.7));
      canvas.drawCircle(
          centre,
          regionPx,
          Paint()
            ..color = ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);

      final nudgePx = proj.radiusPx(nudgeRadiusM.toDouble());
      if (nudgePx >= minHonestRadiusPx) {
        _dashedCircle(
            canvas,
            centre,
            nudgePx,
            Paint()
              ..color = ink
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
      }
    }
    canvas.drawCircle(centre, highlighted ? 3.5 : 2.5, Paint()..color = ink);
  }

  /// Where the set was last drawn from — the last place the phone noticed it had moved, which can
  /// be hours old. Deliberately not a "you are here" pin: this app records no such thing.
  void _paintDiscCentre(Canvas canvas, GeofenceProjection proj, GeofenceDisc d) {
    final c = proj.toPx(d.lat, d.lon);
    final p = Paint()
      ..color = VColors.ink2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const arm = 5.0;
    canvas.drawLine(Offset(c.dx - arm, c.dy), Offset(c.dx + arm, c.dy), p);
    canvas.drawLine(Offset(c.dx, c.dy - arm), Offset(c.dx, c.dy + arm), p);
    canvas.drawCircle(c, 3, p);
  }

  /// Without this the picture has no size and every circle is a guess.
  void _paintScaleBar(Canvas canvas, Size size, GeofenceProjection proj) {
    final target = size.width / 3;
    final metres = VGeofenceMapScale.round(target * proj.metresPerPx);
    final px = proj.radiusPx(metres);
    if (px < 8 || px > size.width - 16) return;

    final label = metres >= 1000
        ? '${(metres / 1000).toStringAsFixed(metres % 1000 == 0 ? 0 : 1).replaceAll('.', ',')} km'
        : '${metres.round()} m';
    final tp = TextPainter(
      text: TextSpan(text: label, style: VText.caption.copyWith(color: VColors.ink2)),
      textDirection: TextDirection.ltr,
    )..layout();

    // A chip under it: the bar sits in a corner that a region circle may well be drawn through,
    // and a scale nobody can read is the same as no scale.
    final chip = Rect.fromLTWH(6, size.height - 26, math.max(px, tp.width) + 12, 22);
    canvas.drawRRect(
      RRect.fromRectAndRadius(chip, const Radius.circular(3)),
      Paint()..color = VColors.paper.withValues(alpha: 0.88),
    );

    final left = Offset(12, size.height - 18);
    final right = Offset(12 + px, size.height - 18);
    final p = Paint()
      ..color = VColors.ink2
      ..strokeWidth = 1;
    canvas.drawLine(left, right, p);
    canvas.drawLine(left, left.translate(0, -4), p);
    canvas.drawLine(right, right.translate(0, -4), p);
    tp.paint(canvas, Offset(12, size.height - 16));
  }

  void _dashedCircle(Canvas canvas, Offset centre, double radius, Paint paint) {
    const dash = 5.0, gap = 4.0;
    final circumference = 2 * math.pi * radius;
    if (circumference <= 0) return;
    final steps = math.max(4, (circumference / (dash + gap)).floor());
    final sweep = 2 * math.pi / steps;
    final rect = Rect.fromCircle(center: centre, radius: radius);
    for (var i = 0; i < steps; i++) {
      canvas.drawArc(rect, i * sweep, sweep * (dash / (dash + gap)), false, paint);
    }
  }

  @override
  bool shouldRepaint(_GeofencePainter old) =>
      old.regions != regions ||
      old.disc != disc ||
      old.focus?.id != focus?.id ||
      old.highlightId != highlightId ||
      old.nudgeRadiusM != nudgeRadiusM;
}
