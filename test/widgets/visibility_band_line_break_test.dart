/// The Japanese "no override" band never leaves a dash alone on a line.
///
/// Why this test exists. On a phone-width frame of the real app (393 logical
/// px, IPAGothic), the visibility demo control drew
/// 「— 上書きなし：ライブ／未計測（既定）」 and then its closing 「—」 alone on a
/// second line. A dash alone on a line says nothing, and beside Japanese text
/// a long dash reads like the kanji 一.
///
/// Two checks. The first lays the band out in the real app at that width with
/// that font, in the closed control and in the open menu, and fails on a line
/// that is only a dash. The second holds whatever the font or width: the
/// Japanese band neither begins nor ends with a dash, so no dash can be left
/// alone. English keeps its bytes.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../render_see/render_see_env.dart';
import '../support/developer_page.dart';
import '../support/fake_alert_actuators.dart';

// IPAGothic is searched for by name (render_see_env.dart,
// ipaGothicSearchOrder), not taken from the absolute path that lived here
// until 2026-09-18 — the path a runner does not have, which is why this failed
// on the first CI run, 35300438549. The face is named in this suite's own
// title and in the finding above, so it is IPAGothic or a red: the dash was
// seen breaking against IPAGothic's metrics and another Japanese face would
// wrap somewhere else.

final _onlyDashes = RegExp(r'^[—–―\-]+$');
final _dashAtEnd = RegExp(r'^\s*[—–―\-]|[—–―\-]\s*$');

/// The lines [p] draws, each as its text.
List<String> _lines(RenderParagraph p) {
  final tp = TextPainter(
    text: p.text,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    maxLines: p.maxLines,
  )..layout(maxWidth: p.constraints.maxWidth);
  final plain = p.text.toPlainText();
  final out = <String>[];
  for (final m in tp.computeLineMetrics()) {
    final pos = tp.getPositionForOffset(Offset(1, m.baseline));
    final range = tp.getLineBoundary(pos);
    out.add(plain.substring(range.start, range.end));
  }
  tp.dispose();
  return out;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // A real directory: the map's tile cache asks for one, and a null answer
    // throws while the test runs.
    final tmp = Directory.systemTemp.createTempSync('visibility_band_break');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  testWidgets('phone width, real glyphs: no line of the Japanese band is only '
      'a dash, closed or open', (tester) async {
    final fontsLoaded = await tester.runAsync(
            () => loadDiscoveredFace('Roboto', FaceSearch.ipaGothic)) ??
        false;
    expect(fontsLoaded, isTrue,
        reason: 'without real glyph metrics this test cannot fail');
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(393 * 2.0, 852 * 2.0);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(SngnavApp(
      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      clock: () => DateTime.utc(2026, 1, 14, 21),
      jmaFetch: () async => const JmaFailure('no network in this test'),
      developerPageEntry: true,
    ));
    await tester.pump();
    await tester.pump();
    // The band is on the development page since 2026-09-15.
    await openDeveloperPage(tester);

    final band = const AppL10n(Locale('ja')).driveHudVisibilityBand(null);
    final control = find.byKey(const Key('drive-hud-visibility'));
    await tester.ensureVisible(control);
    await tester.pump();

    void expectNoLoneDash(String where) {
      final found = find.text(band);
      expect(found, findsWidgets, reason: '$where: the band is drawn');
      for (var i = 0; i < found.evaluate().length; i++) {
        final lines = _lines(tester.renderObject<RenderParagraph>(
            find.descendant(of: found.at(i), matching: find.byType(RichText))));
        expect(lines, isNotEmpty, reason: where);
        for (final line in lines) {
          expect(_onlyDashes.hasMatch(line.trim()), isFalse,
              reason: '$where: lines $lines');
        }
      }
    }

    expectNoLoneDash('closed');
    await tester.tap(control);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expectNoLoneDash('open');
  });

  test('whatever the font or width: the Japanese band neither begins nor ends '
      'with a dash, and English keeps its bytes', () {
    final ja = const AppL10n(Locale('ja')).driveHudVisibilityBand(null);
    expect(_dashAtEnd.hasMatch(ja), isFalse, reason: ja);
    expect(const AppL10n(Locale('en')).driveHudVisibilityBand(null),
        '— No override: live / not measured (default) —');
  });
}
