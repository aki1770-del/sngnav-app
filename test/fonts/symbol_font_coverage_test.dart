/// 1b tofu drift-guard (plan 2026-07-25 §1) — the bundled symbols subset
/// must cover every symbol-class character the app's string literals carry.
///
/// WHY THIS EXISTS: HER-facing safety strings carry symbols (⚠ ❄ ※ → …)
/// that the ja system font stack does not guarantee — measured 2026-07-30:
/// Noto Sans CJK JP lacks U+2744 ❄, and the render-see harness fonts lack
/// U+26A0 ⚠ (memory: RENDER-SEE BLIND TO NON-CJK SYMBOLS). A warning row
/// that renders as tofu (□) has not reached her. The fix bundles a 14-glyph
/// subset (assets/fonts/SnGNavSymbols.ttf) wired as app-wide
/// `ThemeData.fontFamilyFallback`.
///
/// THE LOOM: this test re-derives the symbol inventory from lib/ string
/// literals ON EVERY RUN and parses the shipped font's cmap directly. Adding
/// a new symbol to any UI string WITHOUT re-cutting the subset fails the
/// suite — the break stops the line instead of shipping tofu to HER device.
/// Re-cut procedure: tool/subset_symbols_font.md.
///
/// HONEST BOUNDS: this proves the SHIPPED FONT BYTES cover the inventory and
/// the theme names the family. It does NOT prove on-device glyph rendering
/// (OPS-066 — device leg DEFERRED, no device in this env); the render-see
/// capture (test/render_see/symbol_glyphs_capture_test.dart) is the
/// host-level render evidence.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_app/main.dart';

const String kFontPath = 'assets/fonts/SnGNavSymbols.ttf';
const String kLicensePath = 'assets/fonts/LICENSE-SnGNavSymbols.txt';
const String kFamily = 'SnGNavSymbols';

/// Characters above 0x7F whose rendering the ja system font stack is trusted
/// for (CJK ideographs, kana, CJK punctuation, fullwidth forms). Everything
/// else non-ASCII in a string literal is symbol-class RISK and must be in
/// the bundled subset.
bool _isRisk(int cp) {
  if (cp <= 0x7F) return false;
  if (cp >= 0x3000 && cp <= 0x30FF) return false; // CJK punct + kana
  if (cp >= 0x3400 && cp <= 0x4DBF) return false; // CJK ext A
  if (cp >= 0x4E00 && cp <= 0x9FFF) return false; // CJK unified
  if (cp >= 0xFF00 && cp <= 0xFFEF) return false; // fullwidth forms
  return true;
}

/// Collect symbol-class codepoints from string literals in lib/**.dart.
/// Line-based: full-line comments are skipped; quoted spans are matched with
/// a non-greedy regex. Deliberately errs toward INCLUDING a char (a trailing
/// comment can contribute) — over-inclusion fails toward bundling more
/// glyphs, never toward shipping tofu.
Set<int> _libLiteralRiskSet() {
  final literal = RegExp("'(?:[^'\\\\]|\\\\.)*'|\"(?:[^\"\\\\]|\\\\.)*\"");
  final risk = <int>{};
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
  for (final f in files) {
    for (final line in f.readAsLinesSync()) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//')) continue;
      for (final m in literal.allMatches(line)) {
        for (final cp in m.group(0)!.runes) {
          if (_isRisk(cp)) risk.add(cp);
        }
      }
    }
  }
  return risk;
}

/// Minimal TTF cmap reader (formats 4 and 12) over the actual shipped bytes.
/// Returns the set of codepoints the font maps to a real (non-.notdef) glyph.
Set<int> _cmapCoverage(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final numTables = data.getUint16(4);
  int? cmapOffset;
  for (var i = 0; i < numTables; i++) {
    final rec = 12 + i * 16;
    final tag = String.fromCharCodes(bytes.sublist(rec, rec + 4));
    if (tag == 'cmap') cmapOffset = data.getUint32(rec + 8);
  }
  if (cmapOffset == null) {
    fail('no cmap table in $kFontPath — the font file is broken');
  }
  final n = data.getUint16(cmapOffset + 2);
  final subtables = <int>[];
  for (var i = 0; i < n; i++) {
    subtables.add(cmapOffset + data.getUint32(cmapOffset + 4 + i * 8 + 4));
  }
  final covered = <int>{};
  for (final st in subtables) {
    final format = data.getUint16(st);
    if (format == 4) {
      final segCount = data.getUint16(st + 6) ~/ 2;
      final endBase = st + 14;
      final startBase = endBase + segCount * 2 + 2;
      final deltaBase = startBase + segCount * 2;
      final rangeBase = deltaBase + segCount * 2;
      for (var s = 0; s < segCount; s++) {
        final end = data.getUint16(endBase + s * 2);
        final start = data.getUint16(startBase + s * 2);
        if (start == 0xFFFF) continue;
        final idDelta = data.getUint16(deltaBase + s * 2);
        final idRange = data.getUint16(rangeBase + s * 2);
        for (var c = start; c <= end; c++) {
          int glyph;
          if (idRange == 0) {
            glyph = (c + idDelta) & 0xFFFF;
          } else {
            final gi = rangeBase + s * 2 + idRange + (c - start) * 2;
            if (gi + 1 >= bytes.length) continue;
            glyph = data.getUint16(gi);
            if (glyph != 0) glyph = (glyph + idDelta) & 0xFFFF;
          }
          if (glyph != 0) covered.add(c);
        }
      }
    } else if (format == 12) {
      final numGroups = data.getUint32(st + 12);
      for (var g = 0; g < numGroups; g++) {
        final rec = st + 16 + g * 12;
        final startChar = data.getUint32(rec);
        final endChar = data.getUint32(rec + 4);
        for (var c = startChar; c <= endChar; c++) {
          covered.add(c);
        }
      }
    }
  }
  return covered;
}

void main() {
  test('bundled symbols font exists beside its license, and pubspec ships it',
      () {
    expect(File(kFontPath).existsSync(), isTrue,
        reason: '$kFontPath missing — the tofu backstop is gone');
    expect(File(kLicensePath).existsSync(), isTrue,
        reason: '$kLicensePath missing — the Bitstream Vera license requires '
            'the notice to accompany the font');
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: $kFamily'),
        reason: 'pubspec no longer declares the $kFamily font family');
    expect(pubspec, contains('asset: $kFontPath'),
        reason: 'pubspec no longer ships $kFontPath');
  });

  test(
      'every symbol-class char in lib/ string literals is covered by the '
      'shipped font bytes (re-cut via tool/subset_symbols_font.md on failure)',
      () {
    final needed = _libLiteralRiskSet();
    expect(needed, contains(0x26A0),
        reason: 'sanity: the ⚠ warning rows should be in the inventory — if '
            'they vanished, this scan is broken, not done');
    final covered = _cmapCoverage(File(kFontPath).readAsBytesSync());
    final missing = needed.difference(covered).toList()..sort();
    expect(
      missing,
      isEmpty,
      reason: 'symbol-class chars in lib/ literals NOT in the bundled subset '
          '(would tofu on a device whose system fonts lack them): '
          '${missing.map((c) => 'U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')} '
              '"${String.fromCharCode(c)}"').join(', ')} — '
          're-cut the subset per tool/subset_symbols_font.md',
    );
  });

  testWidgets('the app theme names $kFamily as app-wide fontFamilyFallback',
      (tester) async {
    await tester.pumpWidget(SngnavApp(
      locale: const Locale('ja'),
      logShareSink: (_) async {},
    ));
    await tester.pump();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final fallback = app.theme!.textTheme.bodyMedium!.fontFamilyFallback;
    expect(fallback, isNotNull);
    expect(fallback, contains(kFamily),
        reason: 'ThemeData.fontFamilyFallback no longer names $kFamily — '
            'the bundled glyphs would never be consulted');
  });
}
