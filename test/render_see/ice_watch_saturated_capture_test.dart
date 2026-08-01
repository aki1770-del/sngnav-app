/// STAGE 1, OPS-066 render-SEE — what the 路面凍結ウォッチ row ACTUALLY prints
/// on Akita's ordinary saturated near-freezing morning.
///
/// Session-scope capture, NOT a CI pixel assertion (same contract as
/// `subzero_chip_capture_test.dart`). It pumps the REAL `SngnavApp` with a
/// real `JmaObservation` at +0.5 °C / 98 % RH and reads the REAL
/// `_kv('路面凍結ウォッチ', …)` row, so the pixels are the app's own.
///
/// WHAT THE GOLDEN ACTUALLY CONTAINS (corrected 2026-08-01 after review —
/// the first version of this comment was wrong about its own artifact):
/// `matchesGoldenFile` on a Finder does NOT image that Finder's widget. It
/// walks UP to the nearest ancestor `RepaintBoundary` (flutter_test
/// `_matchers_io.dart` -> `captureImage`), and `_kv` returns a bare `Row` with
/// no boundary of its own. The Row is ~329x20; the committed PNG is 393x796 —
/// the whole JMA card: BOTH watch rows, the source caption, the Re-fetch
/// button, the corridor table and the advisories card.
/// The wider frame is kept deliberately: it is what showed three independent
/// reviewers that 荒天ウォッチ prints a SECOND 該当なし directly beneath the
/// first. The text assertion below, not the pixels, is what pins the verdict.
///
/// RH FIGURES CITED HONESTLY: the five corridor stations were re-measured live
/// on 2026-08-01 by three reviewers (97/97/100/97/100 % RH) — but at 21.7-25.6
/// °C. That establishes a humid corridor, NOT that saturated air within a
/// degree of freezing is ordinary here. The winter co-occurrence is UNMEASURED
/// (see the scope-envelope test's header). This fixture asserts a CONTRACT
/// defect, which does not depend on how often the cell occurs.
///
/// WHY (OPS-070(B), written before the act): the envelope test
/// `test/services/ice_watch_scope_envelope_test.dart` proves at the LOGIC
/// layer that this cell returns `InvisibleIceWatchResult.clear`, whose own
/// dartdoc reserves that value for a MEASURED negative "inside this watch's
/// scope". The calibration package documents this cell as OUTSIDE the model's
/// coverage. A logic proof is not observation-grade: OPS-066 requires going
/// and SEEING what she reads, and this project has three prior fabricated-
/// clear incidents that were each argued from source before anyone looked.
///
/// The text assertion below is the machine-checkable half; the PNG is for the
/// human eye. Both are needed — a string can match while the row renders
/// tofu, and a PNG can look fine while the string drifted.
///
/// HONEST BOUND: this is a widget-layer render on a desktop test host, not
/// HER phone. Non-CJK symbols (⚠) are a known blind spot of this harness
/// (see subzero_chip_capture_test.dart) — the CJK words are the load-bearing
/// content here and they render through the installed IPA/Droid family. On-
/// device render remains the emulator ladder / device hour's job (AAE-1);
/// nobody may affirm this PNG as HER-phone evidence.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';

import 'render_see_env.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart';

import '../support/fake_alert_actuators.dart';

/// +0.5 °C, 98 % RH, precipitation MEASURED at 0.0 mm.
///
/// Dew point +0.22 °C — saturated air a half-degree above freezing, i.e. the
/// freezing-fog / rime regime the radiative-frost classifier documents that it
/// does NOT cover. Precip is a measured zero (never null) so the observation
/// stays inside the watch's no-precipitation scope and the above-zero branch
/// is the one exercised.
JmaObservation _saturatedNearFreezingObs() => JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 0.5,
      humidityPercent: 98,
      windMetersPerSecond: 1.5,
      snowDepthCm: null,
      precipitation10mMm: 0.0,
      visibilityMeters: null,
      observedAtJstKey: '20260115063000',
      fetchedAt: DateTime(2026, 1, 15, 6, 30),
    );

void main() {
  const ipa = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf';
  const droid = '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cjkLoaded = await loadCjkFamily('Roboto', [ipa, droid]);
    if (!cjkLoaded) installNoopGoldenComparator();
    final tmp = await Directory.systemTemp.createTemp('fm_cache_ice_watch');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  testWidgets(
      'the 路面凍結ウォッチ row at +0.5C / 98% RH, from the real app tree',
      (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(393 * 2, 852 * 2);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(SngnavApp(
      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      jmaFetch: () async => JmaSuccess(_saturatedNearFreezingObs()),
    ));
    await tester.pump();
    await tester.pump();

    final label = find.text('路面凍結ウォッチ:');
    expect(label, findsOneWidget,
        reason: 'the watch row must be present in the real app tree');
    await tester.ensureVisible(label);
    await tester.pump();

    // The `_kv` Row: label on the left, verdict on the right.
    final row = find.ancestor(of: label, matching: find.byType(Row)).first;

    // MACHINE-CHECKABLE HALF — pins the VERDICT, not just the label.
    // The first version asserted only `rendered.first`, which the finder at
    // :96 had already matched — a tautology that could not fail, leaving the
    // load-bearing content (該当なし) merely printed. This assertion fails
    // loudly the moment the Stage-2 countermeasure changes what she is told,
    // which is the correct behaviour for a file whose job is to record a
    // defect.
    final rendered = tester
        .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    // ignore: avoid_print
    print('\n  路面凍結ウォッチ ROW AS RENDERED at +0.5C / 98% RH:\n'
        '    ${rendered.join('  |  ')}\n');
    expect(
      rendered,
      <String>['路面凍結ウォッチ:', '判定範囲外（この気象条件は判定していません）'],
      reason: 'STAGE 2 LANDED 2026-08-01. At +0.5 C / 98 % RH the classifier '
          'DECLINES (estimate +0.22 C — above the 0 C surface threshold, under '
          'the 3.0 C ambient ceiling: the band cal:112-115 says verbatim it '
          '"does not cover"). The row previously printed a bare 該当なし here, '
          'which is the fabricated-clear failure class; it must now say the '
          'watch did not judge. This expectation was updated DELIBERATELY when '
          'the countermeasure landed, not silently — the Stage-1 version of '
          'this file asserted 該当なし and is the recorded before-state.',
    );

    await expectLater(
      row,
      matchesGoldenFile('../../ladder_out/ice_watch/ice_watch_saturated_ja.png'),
    );
  });
}
