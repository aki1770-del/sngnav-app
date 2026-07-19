/// OPS-066 render-SEE capture for the CHOICE-NEUTRAL lowest-rung caution banner
/// (Design-Floor Refusal #1, Chair 2026-07-19). Session-scope; NOT a CI claim.
///
/// Produces a fresh ja-rendered PNG of the `drive-hud-caution-banner`
/// (Key('drive-hud-caution-banner') in lib/main.dart) in the LOWEST rung state,
/// so VAA can LOOK at the headline the fix changes:
///   13 — trusted position, MEASURED clear visibility, no watch → grey banner
///        reading 「特段の注意なし」 (was 「走行を継続」, which advocated GO).
///
/// HONESTY: the state is produced by the REAL `DriveHudController` driven
/// through its public seam (`updateEnvironment` + `onPositionFix`); the effective
/// rung is the REAL `controller.effectiveAction` — the SAME value main.dart's
/// banner reads. Only the Container styling is reproduced (verbatim from
/// `_driveHudPanel`); the rung decision is not re-implemented. The lowest rung
/// shows ONLY the headline (no guidance line) — parity with the voice channel's
/// silence. On-device / on-phone render is DEFERRED (no device); nobody affirms
/// this PNG as HER-phone evidence.
library;

import 'dart:io';

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show DriveAction;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/services/drive_hud_controller.dart';
import 'package:sngnav_app/services/drive_hud_localizer.dart';
import 'package:sngnav_app/services/measured_hazard_floor.dart';

import 'render_see_env.dart';
import '../support/fake_alert_actuators.dart';

const _text = DriveHudLocalizer();

/// Faithful reproduction of the `_driveHudPanel` lowest-rung banner: the grey
/// (bg, fg) pair, the headline, and NO guidance line (parity with voice
/// silence) — all verbatim with lib/main.dart.
Widget _panel({required DriveAction effective}) {
  final (Color bg, Color fg) = switch (effective) {
    DriveAction.considerStopping => (Colors.red.shade100, Colors.red.shade900),
    DriveAction.heightenedCaution => (Colors.amber.shade100, Colors.amber.shade900),
    _ => (Colors.grey.shade200, Colors.grey.shade800),
  };
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'The eyes-off compound caution rung, LOWEST state. Choice-neutral by '
        'Design-Floor Refusal #1: it states the honest absence of elevated '
        'caution, it does NOT tell her to continue and does NOT reassure. It '
        'reaches HER only on a measured, non-elevated read (advisor score 0).',
        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
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
    final tmp = await Directory.systemTemp.createTemp('fm_cache_neutral_see');
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

  testWidgets(
      '13 — trusted, measured clear, no watch → 特段の注意なし (grey, neutral)',
      (tester) async {
    final c = DriveHudController(
        actuators: FakeAlertActuators(), localeTag: 'ja');
    c.updateEnvironment(
      visibilityMeters: 1500, // measured & clear
      visibilityAgeSeconds: 0, // fresh
      advisorySeverity: null,
      speedMetersPerSecond: null,
      measuredHazard: MeasuredWeatherHazard.none,
    );
    c.onPositionFix(freshFix(t0), now: t0);
    // The REAL effective rung is the lowest one here.
    expect(c.effectiveAction, DriveAction.continueDriving);
    // And the headline it renders is the neutral wording.
    expect(_text.actionHeadline(c.effectiveAction!, 'ja'), '特段の注意なし');

    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(820 * 2, 200 * 2);
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
            child: _panel(effective: c.effectiveAction!),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('../../render_out/13_drive_hud_lowest_rung_neutral.png'));
  });
}
