import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colours of the "Bahnhofsuhr" look. Paper, ink, one red.
class VColors {
  VColors._();

  static const paper = Color(0xFFF3F3F0);
  static const paperElevated = Color(0xFFFFFFFF);
  static const ink = Color(0xFF111111);
  static const ink2 = Color(0xFF6B6B66);
  static const ink3 = Color(0xFF9C9C96);
  static const rule = Color(0xFFD2D2CC);
  static const ruleSoft = Color(0xFFE6E6E1);
  static const red = Color(0xFFD92B1E);
  static const redSoft = Color(0xFFF8E3E0);
  static const green = Color(0xFF2E7D4F);
  static const greenSoft = Color(0xFFE1F0E6);
}

/// Spacing scale. Use these instead of ad-hoc numbers.
class VSpace {
  VSpace._();
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 16.0;
  static const l = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
  static const page = 24.0;
}

const _tabular = [FontFeature.tabularFigures()];

/// Text styles. Archivo everywhere.
class VText {
  VText._();

  static TextStyle _a({
    required double size,
    FontWeight weight = FontWeight.w400,
    double height = 1.3,
    double letterSpacing = 0,
    Color color = VColors.ink,
    bool tabular = false,
  }) =>
      GoogleFonts.archivo(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
        fontFeatures: tabular ? _tabular : null,
      );

  /// The huge delay number on the arrival screen.
  static TextStyle get display => _a(
        size: 168,
        weight: FontWeight.w800,
        height: 0.88,
        letterSpacing: -8,
        tabular: true,
      );

  /// Large numbers: home figures, ledger header, community.
  static TextStyle get number => _a(
        size: 56,
        weight: FontWeight.w800,
        height: 1.0,
        letterSpacing: -2,
        tabular: true,
      );

  /// Medium numbers: euro amounts in rows, points.
  static TextStyle get numberM => _a(
        size: 28,
        weight: FontWeight.w800,
        height: 1.0,
        letterSpacing: -0.8,
        tabular: true,
      );

  static TextStyle get h1 => _a(size: 34, weight: FontWeight.w800, height: 1.08, letterSpacing: -1);
  static TextStyle get h2 => _a(size: 24, weight: FontWeight.w700, height: 1.15, letterSpacing: -0.5);
  static TextStyle get title => _a(size: 19, weight: FontWeight.w700, height: 1.25);
  static TextStyle get body => _a(size: 17, height: 1.45);
  static TextStyle get bodyStrong => _a(size: 17, weight: FontWeight.w600, height: 1.45);
  static TextStyle get bodyS => _a(size: 15, height: 1.4);
  static TextStyle get bodySStrong => _a(size: 15, weight: FontWeight.w600, height: 1.4);
  static TextStyle get caption => _a(size: 13, weight: FontWeight.w500, height: 1.35, color: VColors.ink2);
  static TextStyle get captionInk => _a(size: 13, weight: FontWeight.w500, height: 1.35);
  static TextStyle get eyebrow => _a(size: 12, weight: FontWeight.w600, height: 1.2, letterSpacing: 0.6, color: VColors.ink2);
  static TextStyle get button => _a(size: 17, weight: FontWeight.w700, height: 1.2);
  static TextStyle get tab => _a(size: 12, weight: FontWeight.w600, height: 1.2);
  static TextStyle get mono => _a(size: 15, weight: FontWeight.w500, height: 1.4, tabular: true);
}
