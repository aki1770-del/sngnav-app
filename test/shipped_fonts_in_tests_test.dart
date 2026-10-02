// The icons and symbols the app ships must reach every test, including the
// goldens nobody has written yet. test/flutter_test_config.dart loads the
// app's fonts (test/support/shipped_fonts.dart). These tests fail if that
// stops being true.
//
// How a missing font is seen. `flutter test` draws a family nobody loaded
// with its own test font, so a glyph from an unloaded family comes out the
// same as a glyph from a family that does not exist. Each check draws one
// glyph twice, once in the shipped family and once in a family nobody
// registered, and the two must differ. The first test shows the comparison
// can tell a loaded font from a missing one, so a pass below is not the
// instrument failing to look.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'support/shipped_fonts.dart';

/// One glyph from each font the app ships, drawn on her screen where it can
/// be. A font added to pubspec.yaml fails the second test until it has a
/// glyph here.
final Map<String, int> _probe = <String, int>{
  // Opens the stale black-ice row on her weather card
  // (Key('stale-ice-visible') in lib/main.dart).
  'MaterialIcons': Icons.warning_amber.codePoint,
  // ⚠, which opens 路面凍結のおそれ and 強い雨・強めの風を観測中.
  'SnGNavSymbols': 0x26A0,
  // A dependency's font. The app draws none of its glyphs today; it ships in
  // the APK all the same, so it is loaded and checked like the others.
  'packages/cupertino_icons/CupertinoIcons':
      CupertinoIcons.exclamationmark_triangle.codePoint,
};

const String _nobody = 'a family nobody registered';

Future<Uint8List> _draw(int codePoint, String family) async {
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(codePoint),
      style: TextStyle(
        fontFamily: family,
        fontSize: 48,
        color: const Color(0xFF000000),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), Offset.zero);
  final picture = recorder.endRecording();
  final image = await picture.toImage(64, 64);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  painter.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  test('the comparison tells a loaded font from a missing one', () async {
    // A family this test loads itself, from the shipped bytes, under a name
    // no other code uses.
    const control = 'shipped fonts guard control';
    final bytes = File('assets/fonts/SnGNavSymbols.ttf').readAsBytesSync();
    await (FontLoader(control)
          ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes))))
        .load();
    expect(listEquals(await _draw(0x26A0, control), await _draw(0x26A0, _nobody)),
        isFalse,
        reason: 'a font loaded in this test draws the same as no font, so '
            'the checks below cannot see a missing one');
    expect(
        listEquals(await _draw(0x26A0, _nobody),
            await _draw(0x26A0, 'another family nobody registered')),
        isTrue,
        reason: 'two missing families draw differently, so "differs from a '
            'missing family" would not mean "loaded"');
  });

  test('every font the app ships is loaded for this test', () async {
    final manifest = shippedFontManifest();
    expect(manifest, isNotNull,
        reason: 'no FontManifest.json in the test asset bundle; run '
            '`flutter test` without --no-test-assets');
    final families = shippedFontFamilies(manifest!);
    expect(families, isNotEmpty);
    for (final family in families) {
      final cp = _probe[family];
      expect(cp, isNotNull,
          reason: 'the app ships the font family "$family" and this guard '
              'has no glyph to check it with; add one to _probe');
      expect(listEquals(await _draw(cp!, family), await _draw(cp, _nobody)),
          isFalse,
          reason: '"$family" draws U+${cp.toRadixString(16).toUpperCase()} '
              'the same as a family nobody registered: the app ships this '
              'font and this test does not have it, so a golden would store '
              'an empty box where she sees the glyph. '
              'test/flutter_test_config.dart must call loadShippedFonts().');
    }
  });

  test('every flutter_test_config.dart under test/ loads the shipped fonts',
      () {
    expect(File('test/flutter_test_config.dart').existsSync(), isTrue);
    // flutter_tools uses only the nearest config above a test file, so a
    // config added in a subdirectory would replace the root one for every
    // test below it. Each one must load the fonts itself.
    final loadsThem = RegExp(r'^\s*await\s+loadShippedFonts\(\)\s*;',
        multiLine: true);
    final configs = Directory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last == 'flutter_test_config.dart');
    for (final f in configs) {
      expect(loadsThem.hasMatch(f.readAsStringSync()), isTrue,
          reason: '${f.path} replaces the root config for the tests below it '
              'and does not load the fonts the app ships');
    }
  });
}
