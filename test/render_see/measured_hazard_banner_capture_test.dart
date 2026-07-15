/// OPS-066 render-SEE capture for the measured-hazard fusion into the compound
/// caution banner (session-scope; NOT a CI assertion).
///
/// Produces fresh ja-rendered PNGs of the `_driveHudPanel` caution banner
/// (`Key('drive-hud-caution-banner')` in lib/main.dart) so VAA can LOOK at the
/// thing the fix changes:
///   10 — no measured hazard, trusted, clear   → grey  「走行を継続」
///   11 — MEASURED black-ice firing, trusted    → amber 「注意して走行」  ← the fix
///        (the advisor ALONE says 走行を継続; the measured watch RAISES the banner)
///   12 — measured hazard + position LOST        → red   「停車の検討」  (compound)
///
/// HONESTY (so the reader can trust the render): every state is produced by the
/// REAL `DriveHudController` driven through its public seam (`updateEnvironment`
/// + `onPositionFix`/`poll`), and the effective rung comes from the REAL
/// `controller.effectiveAction` — the SAME value main.dart's banner reads. Only
/// the Container styling is reproduced (verbatim from `_driveHudPanel`'s switch
/// + `actionHeadline` + `spokenGuidance`); the raised-rung decision is not
/// re-implemented here. The caption states the advisor-alone rung beside the
/// effective rung, so the RAISE is legible in the pixels. On-device HEAR/FEEL +
/// on-phone render remain the emulator ladder / device hour's job (OPS-066 /
/// AAE-1): NOBODY affirms these PNGs as HER-phone evidence.
library;

import 'dart:io';

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show DriveAction;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:localization_fallback/localization_fallback.dart'
    show LocalizationMode;
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/services/drive_hud_controller.dart';
import 'package:sngnav_app/services/drive_hud_localizer.dart';
import 'package:sngnav_app/services/measured_hazard_floor.dart';

import 'render_see_env.dart';
import '../support/fake_alert_actuators.dart';

const _text = DriveHudLocalizer();

/// Faithful reproduction of the `_driveHudPanel` caution banner (lib/main.dart):
/// the (bg, fg) switch on the EFFECTIVE rung, the headline, and the guidance
/// line for a raised rung — all verbatim. The caption is capture-only, to make
/// the fusion visible.
Widget _panel({
  required DriveAction effective,
  required DriveAction advisorBase,
  required String measuredLabel,
}) {
  final (Color bg, Color fg) = switch (effective) {
    DriveAction.considerStopping => (Colors.red.shade100, Colors.red.shade900),
    DriveAction.heightenedCaution => (
        Colors.amber.shade100,
        Colors.amber.shade900
      ),
    _ => (Colors.grey.shade200, Colors.grey.shade800),
  };
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'The eyes-off compound caution rung. A MEASURED JMA watch (black-ice / '
        'turmoil) now RAISES this banner so it cannot read 「走行を継続」while a '
        'measured hazard is firing — and compounds to 「停車の検討」when the hazard '
        'cannot even be located (position lost).',
        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
      ),
      const SizedBox(height: 6),
      Text(
        '（compound_failure_advisor 単独: ${_text.actionHeadline(advisorBase, 'ja')}'
        '／実測ウォッチ: $measuredLabel'
        ' → 実効: ${_text.actionHeadline(effective, 'ja')}）',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
      ),
      const SizedBox(height: 8),
      Container(
        key: const Key('drive-hud-caution-banner'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _text.actionHeadline(effective, 'ja'),
              style: TextStyle(
                color: fg,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (effective != DriveAction.continueDriving) ...[
              const SizedBox(height: 4),
              Text(
                _text.spokenGuidance(effective, 'ja'),
                style: TextStyle(color: fg, fontSize: 14),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

void main() {
  const ipa = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf';
  const droid = '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cjkLoaded = await loadCjkFamily('Roboto', [ipa, droid]);
    if (!cjkLoaded) installNoopGoldenComparator();
    await loadCjkFamily('NotoCJK', [ipa, droid]);
    final tmp = await Directory.systemTemp.createTemp('fm_cache_measured_see');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  final t0 = DateTime.utc(2026, 1, 1, 8, 0, 0);
  PositionAvailable freshFix(DateTime t) => PositionAvailable(
        latitude: 39.72,
        longitude: 140.10,
        accuracyMeters: 20,
        timestamp: t,
      );

  /// Drive the REAL controller into a state and return (advisorBase, effective).
  (DriveAction, DriveAction, LocalizationMode) drive({
    required MeasuredWeatherHazard hazard,
    required double? vis,
    bool blackout = false,
  }) {
    final c = DriveHudController(
        actuators: FakeAlertActuators(), localeTag: 'ja');
    c.updateEnvironment(
      visibilityMeters: vis,
      visibilityAgeSeconds: vis == null ? null : 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
      measuredHazard: hazard,
    );
    c.onPositionFix(freshFix(t0), now: t0);
    if (blackout) c.poll(now: t0.add(const Duration(seconds: 300)));
    return (c.advice!.action, c.effectiveAction!, c.estimate!.mode);
  }

  Future<void> capture(
    WidgetTester tester, {
    required Widget panel,
    required String out,
  }) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(820 * 2, 300 * 2);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'NotoCJK',
          fontFamilyFallback: const ['NotoCJK', 'Roboto'],
        ),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: panel,
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile(out));
  }

  testWidgets('10 — no measured hazard, trusted, clear → 走行を継続 (grey)',
      (tester) async {
    final (base, eff, _) =
        drive(hazard: MeasuredWeatherHazard.none, vis: 1500);
    expect(base, DriveAction.continueDriving);
    expect(eff, DriveAction.continueDriving);
    await capture(
      tester,
      panel: _panel(effective: eff, advisorBase: base, measuredLabel: 'なし'),
      out: '../../render_out/10_drive_hud_measured_continue.png',
    );
  });

  testWidgets(
      '11 — MEASURED black-ice firing, trusted, clear → banner RISES to 注意して走行',
      (tester) async {
    final (base, eff, _) =
        drive(hazard: MeasuredWeatherHazard.blackIce, vis: 1500);
    // The advisor ALONE would say continue; the measured watch RAISED it.
    expect(base, DriveAction.continueDriving);
    expect(eff, DriveAction.heightenedCaution);
    await capture(
      tester,
      panel: _panel(
          effective: eff,
          advisorBase: base,
          measuredLabel: 'ブラックアイスバーンのおそれ'),
      out: '../../render_out/11_drive_hud_measured_blackice_rise.png',
    );
  });

  testWidgets(
      '12 — measured hazard + position LOST → 停車の検討 (compound ceiling)',
      (tester) async {
    final (base, eff, mode) = drive(
        hazard: MeasuredWeatherHazard.blackIce, vis: 1500, blackout: true);
    expect(mode, LocalizationMode.lost);
    expect(eff, DriveAction.considerStopping);
    await capture(
      tester,
      panel: _panel(
          effective: eff,
          advisorBase: base,
          measuredLabel: 'ブラックアイスバーンのおそれ'),
      out: '../../render_out/12_drive_hud_measured_compound_stop.png',
    );
  });
}
