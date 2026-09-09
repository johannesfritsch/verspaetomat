import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: VColors.paper,
    colorScheme: const ColorScheme.light(
      primary: VColors.ink,
      onPrimary: VColors.paper,
      secondary: VColors.red,
      onSecondary: VColors.paper,
      surface: VColors.paper,
      onSurface: VColors.ink,
      error: VColors.red,
      onError: VColors.paper,
      outline: VColors.rule,
    ),
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    textTheme: GoogleFonts.archivoTextTheme(base.textTheme).apply(
      bodyColor: VColors.ink,
      displayColor: VColors.ink,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: VColors.paper,
      foregroundColor: VColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: VText.title,
      iconTheme: const IconThemeData(color: VColors.ink, size: 22),
    ),
    dividerTheme: const DividerThemeData(color: VColors.rule, thickness: 1, space: 1),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: VColors.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      showDragHandle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VColors.paperElevated,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
        borderSide: BorderSide(color: VColors.rule),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
        borderSide: BorderSide(color: VColors.rule),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
        borderSide: BorderSide(color: VColors.ink, width: 1.5),
      ),
      hintStyle: VText.body.copyWith(color: VColors.ink3),
      labelStyle: VText.caption,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? VColors.paper : VColors.ink2,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? VColors.ink : VColors.ruleSoft,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: VColors.ink,
      contentTextStyle: VText.bodyS.copyWith(color: VColors.paper),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
