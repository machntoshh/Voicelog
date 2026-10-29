import 'package:flutter/material.dart';

/// VoiceLog palette: soft black and graphite, a soft red for recording.
abstract final class VL {
  static const bg = Color(0xFF111214);
  static const surface = Color(0xFF17181B);
  static const panel = Color(0xFF1F2024);
  static const panelHigh = Color(0xFF292A2F);
  static const border = Color(0xFF303237);
  static const text = Color(0xFFE8E8EA);
  static const textDim = Color(0xFFA1A3A9);
  static const textFaint = Color(0xFF6E7178);
  static const red = Color(0xFFE0584F);
  static const redSoft = Color(0x33E0584F);
  static const success = Color(0xFF5DB88A);
  static const warning = Color(0xFFD5A54C);
  static const error = Color(0xFFE2716A);

  static const radius = 14.0;
  static const tabular = [FontFeature.tabularFigures()];
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: VL.text,
    onPrimary: VL.bg,
    secondary: VL.red,
    onSecondary: VL.text,
    // Tonal buttons stay neutral; red is reserved for recording.
    secondaryContainer: VL.panelHigh,
    onSecondaryContainer: VL.text,
    error: VL.error,
    surface: VL.surface,
    onSurface: VL.text,
    onSurfaceVariant: VL.textDim,
    surfaceContainerLowest: VL.bg,
    surfaceContainerLow: VL.surface,
    surfaceContainer: VL.panel,
    surfaceContainerHigh: VL.panelHigh,
    surfaceContainerHighest: VL.panelHigh,
    outline: VL.border,
    outlineVariant: VL.border,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(VL.radius));
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: VL.bg,
    textTheme: base.textTheme.apply(bodyColor: VL.text, displayColor: VL.text),
    cardTheme: CardThemeData(
      color: VL.panel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: shape.copyWith(side: const BorderSide(color: VL.border, width: 0.6)),
    ),
    dialogTheme: DialogThemeData(backgroundColor: VL.panel, shape: shape),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: VL.panel,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    popupMenuTheme: PopupMenuThemeData(color: VL.panelHigh, shape: shape),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VL.panel,
      isDense: true,
      hintStyle: const TextStyle(color: VL.textFaint),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: VL.textFaint),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: VL.panelHigh,
      contentTextStyle: const TextStyle(color: VL.text),
      shape: shape,
    ),
    dividerTheme: const DividerThemeData(color: VL.border, thickness: 0.6, space: 1),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
