/// The fonts the app ships, loaded into every test.
///
/// `flutter test` starts the test engine with `--disable-asset-fonts`
/// (flutter_tools `lib/src/test/flutter_tester_device.dart`), so a widget test
/// does not get the fonts the app declares. On her phone those fonts are in
/// the APK and the engine registers them before the first frame. In a test
/// they are absent, and every glyph they carry is drawn as an empty box: the
/// app bar's icons, the icon that opens a warning row, and the ⚠ that opens
/// a watch verdict. A golden cut in that state passes while it shows a box
/// where she sees a symbol.
///
/// [loadShippedFonts] undoes exactly that, and nothing else. It reads the
/// font manifest that `flutter test` itself builds into the test asset bundle
/// (`build/unit_test_assets/FontManifest.json`, named by the UNIT_TEST_ASSETS
/// environment variable). That manifest is made by the same code that makes
/// the APK's: the `fonts:` section of pubspec.yaml (SnGNavSymbols), the
/// MaterialIcons font that `uses-material-design: true` adds, and the fonts of
/// packages the app depends on. Each family is loaded under the name the
/// manifest gives it, from the bytes in the bundle, so a font added to
/// pubspec.yaml later is loaded here without anyone remembering to.
///
/// What it does NOT load: any system font. Her phone draws Japanese and
/// Latin text with its own system fonts, which are not in the APK. Suites
/// that need real Japanese glyphs still load a host face under 'Roboto'
/// themselves (test/render_see/render_see_env.dart), and that stand-in is
/// still theirs to state.
///
/// One difference from the APK, stated: a release build tree-shakes
/// MaterialIcons down to the icons the app uses. The glyphs it keeps are the
/// same outlines as the full font loaded here.
///
/// test/shipped_fonts_in_tests_test.dart fails if this stops being true.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;

/// The font families [loadShippedFonts] loaded in this test isolate, in
/// manifest order. Empty until it has run, or when it found no manifest.
final List<String> shippedFontFamiliesLoaded = <String>[];

/// Where the test asset bundle's font manifest is, or null when this run has
/// none (`flutter test --no-test-assets`, or a runner that is not
/// `flutter test`).
File? shippedFontManifest() {
  final dir = Platform.environment['UNIT_TEST_ASSETS'];
  if (dir == null) return null;
  final f = File('$dir/FontManifest.json');
  return f.existsSync() ? f : null;
}

/// The entries of [manifest]: one per font family, each with its assets.
List<Map<String, dynamic>> _entries(File manifest) =>
    (jsonDecode(manifest.readAsStringSync()) as List<dynamic>)
        .cast<Map<String, dynamic>>();

/// The font family names [manifest] lists, in its order.
List<String> shippedFontFamilies(File manifest) =>
    [for (final e in _entries(manifest)) e['family'] as String];

/// Loads every family in the test asset bundle's font manifest.
///
/// Without a manifest it loads nothing and says so on one line; the guard
/// test then fails, and so does any golden whose stored image carries one of
/// these glyphs. It does not stop the run: a test that draws no icon or
/// symbol is still a valid test without them.
Future<void> loadShippedFonts() async {
  final manifest = shippedFontManifest();
  if (manifest == null) {
    // ignore: avoid_print
    print('shipped fonts: no FontManifest.json in the test asset bundle '
        '(UNIT_TEST_ASSETS=${Platform.environment['UNIT_TEST_ASSETS']}); '
        'icons and symbols the app ships will draw as boxes in this run');
    return;
  }
  final root = manifest.parent.path;
  for (final entry in _entries(manifest)) {
    final family = entry['family'] as String;
    final loader = FontLoader(family);
    for (final font in (entry['fonts'] as List<dynamic>)
        .cast<Map<String, dynamic>>()) {
      final asset = Uri.decodeFull(font['asset'] as String);
      final bytes = File('$root/$asset').readAsBytesSync();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
    shippedFontFamiliesLoaded.add(family);
  }
}
