import 'package:flutter/material.dart';

/// The app's theme.
///
/// A function of its own (2026-10-04), moved from `SngnavApp.build`, so that a
/// test drawing one of the app's widgets can draw it in her colours rather than
/// in a copy of them or in Flutter's defaults.
ThemeData sngnavTheme() => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
    useMaterial3: true,
    // Tofu fix (2026-07-25): driver-facing strings carry a small
    // symbol set (⚠ ❄ ※ → ° …) the ja system font stack does not
    // guarantee (measured 2026-07-30: Noto Sans CJK JP lacks U+2744 ❄).
    // This 15.7 KB bundled subset covers it for every theme-derived
    // TextStyle. The shaper tries the requested families (Material's
    // 'Roboto', then this one) before any system fallback (Skia
    // 8df24be6, pinned by Flutter 3.47.5: OneLineShaper::
    // matchResolvedFonts). Read 2026-10-02 from a stock Android 14
    // system image: no family answers to 'Roboto' and its Roboto face
    // lacks U+26A0, so ⚠ comes from this subset there. Her phone is
    // UNVERIFIED: a system whose 'Roboto' covers U+26A0 draws its own.
    // Tests load this font (test/flutter_test_config.dart); coverage is
    // drift-guarded by test/fonts/symbol_font_coverage_test.dart.
    fontFamilyFallback: const ['SnGNavSymbols'],
  );
