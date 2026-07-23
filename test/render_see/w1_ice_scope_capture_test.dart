/// OPS-066 render-SEE captures for the 路面凍結ウォッチ verdicts
/// (session-scope; NOT a CI pixel assertion) — produces PNGs into
/// `ladder_out/w1_ice/` so a human LOOKS at each rendered verdict:
///
///   w1_ice_subzero_frozen_warning_ja.png — −2.4 °C / RH 95 % / no precip
///   w1_ice_out_of_scope_precip_ja.png    — measured precipitation
///   w1_ice_clear_ja.png                  — a genuine in-scope negative
///   w1_ice_watch_ja.png                  — the radiative-frost surprise
///
/// Run with:
///   flutter test --update-goldens test/render_see/w1_ice_scope_capture_test.dart
///
/// WHY FOUR FRAMES. The four render four DISTINCT verdicts the driver can now
/// see on the 路面凍結ウォッチ row, proving each is what we say:
///   1. sub-zero → 「⚠ 路面凍結のおそれ（気温氷点下）」 — the Chair-ruled
///      sub-zero WARNING (2026-07-23). This carries the exact measured
///      conditions of the Chuo Expressway nine-vehicle pileup of 2021-12-15
///      (−2.4 °C, clear morning, no visible snow): the case where this
///      surface first told HER 該当なし (Andon 2026-07-20T13:40Z), then
///      本ウォッチの対象外 (6c746be), and now WARNS. It is a DISTINCT string,
///      never the 「ブラックアイスバーン」 surprise line — below zero ice is
///      expected, not a radiative surprise.
///   2. precipitation → 本ウォッチの対象外 — the one remaining scope exclusion.
///   3. genuine in-scope negative → 該当なし — proof the all-clear was
///      NARROWED to a measured negative, not deleted.
///   4. above-zero radiative window → the surprise 「ブラックアイスバーン」 line.
///
/// HONEST BOUNDS — three, all measured on 2026-07-23, none narrated:
///
/// 1. A passing golden is NOT the OPS-066 evidence. On a host without CJK
///    fonts the comparator is a no-op that returns true for everything. The
///    evidence is a human viewing the PNG on a font-bearing desktop.
///    On-device render remains the emulator ladder / device hour's job.
///
/// 2. THE HARNESS CANNOT SEE NON-CJK SYMBOL DEFECTS — a blind spot in our own
///    instrument, found by looking at `w1_ice_watch_ja.png`. `loadCjkFamily`
///    installs IPAGothic + DroidSansFallback UNDER THE FAMILY NAME 'Roboto',
///    REPLACING it rather than supplementing it. Neither font maps U+26A0
///    WARNING SIGN (verified by cmap parse: ABSENT in both; the CJK controls
///    U+8DEF 路 / U+8A72 該 are PRESENT in both), so the ⚠ that opens the
///    black-ice row renders as TOFU in the capture. On HER Android device the
///    system stack is expected to supply it — but that is UNVERIFIED, and it
///    is exactly what this harness cannot distinguish: a symbol genuinely
///    broken on-device and a symbol merely missing from the test substitute
///    produce the SAME picture here. Every render_see capture we hold shares
///    this blind spot.
///
/// The injected [SngnavApp.jmaFetch] supplies a canned observation, so the
/// REAL `_jmaPanel` renders hermetically — the same code path a live fetch
/// drives.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';

import 'render_see_env.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart';

import '../support/fake_alert_actuators.dart';

/// A verbatim JMA observation. Every field the watch reads is supplied
/// explicitly; the rest mirror `w3_turmoil_capture_test.dart`'s canned shape.
JmaObservation _obs({
  required double temp,
  required int humidity,
  required double precip10m,
}) {
  return JmaObservation(
    stationId: '32402',
    stationName: '秋田',
    temperatureCelsius: temp,
    humidityPercent: humidity,
    windMetersPerSecond: 2.0,
    snowDepthCm: null,
    precipitation10mMm: precip10m,
    visibilityMeters: null,
    observedAtJstKey: '20260115063000',
    fetchedAt: DateTime(2026, 1, 15, 6, 30),
  );
}

void main() {
  const ipa = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf';
  const droid = '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cjkLoaded = await loadCjkFamily('Roboto', [ipa, droid]);
    if (!cjkLoaded) installNoopGoldenComparator();
    final tmp = await Directory.systemTemp.createTemp('fm_cache_w1ice');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  Future<void> capture(
    WidgetTester tester, {
    required JmaObservation observation,
    required String guardRowText,
    required String out,
  }) async {
    await tester.pumpWidget(SngnavApp(
      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      jmaFetch: () async => JmaSuccess(observation),
    ));
    await tester.pump();
    await tester.pump();
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(393 * 2, 852 * 2);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();
    // GUARD FIRST: assert the row actually says what this frame is named for,
    // so a capture can never quietly record the wrong verdict.
    //
    // The guard is scoped to the ice row's own `_kv` Row rather than to the
    // whole screen. A bare `find.text` would be both too weak and too
    // brittle: 該当なし is rendered by the ADJACENT 荒天ウォッチ row on the
    // same panel, so a screen-wide finder matches two widgets for the clear
    // frame — and, worse, would happily pass a frame whose ice row said
    // something else entirely as long as some other row carried the string.
    // Scoping asserts the verdict is in the row this capture is about.
    final iceRow = find
        .ancestor(
          of: find.text('路面凍結ウォッチ:'),
          matching: find.byType(Row),
        )
        .first;
    expect(
      find.descendant(of: iceRow, matching: find.text(guardRowText)),
      findsOneWidget,
    );
    // Then bring the ice row into view. Bottom-most ensureVisible wins the
    // final alignment (discipline inherited from w2_fixes_capture_test.dart),
    // so the ice row is scrolled LAST — it is the subject of this capture.
    await tester.ensureVisible(find.text('荒天ウォッチ:'));
    await tester.pump();
    await tester.ensureVisible(find.text('路面凍結ウォッチ:'));
    await tester.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile(out));
  }

  testWidgets('w1 — sub-zero frozen-surface WARNING (Chuo 2021-12-15) (ja)',
      (tester) async {
    // −2.4 °C / RH 95 % / no precipitation — the exact Chuo pileup reading.
    // It rendered 該当なし (Andon 2026-07-20), then 本ウォッチの対象外 (6c746be),
    // and now — on the Chair's calibration ruling (2026-07-23) — WARNS.
    await capture(
      tester,
      observation: _obs(temp: -2.4, humidity: 95, precip10m: 0.0),
      guardRowText: '⚠ 路面凍結のおそれ（気温0°C以下）',
      out: '../../ladder_out/w1_ice/w1_ice_subzero_frozen_warning_ja.png',
    );
  });

  testWidgets('w1 — scope exclusion, measured precipitation (ja)',
      (tester) async {
    // The visible-hazard lanes own precipitation; this watch covers the
    // no-precipitation radiative-frost window only. Same string, second cause
    // — the branch the harm-pinned incident test does not reach.
    await capture(
      tester,
      observation: _obs(temp: 2.0, humidity: 70, precip10m: 0.5),
      guardRowText: '本ウォッチの対象外（この条件は判定していません）',
      out: '../../ladder_out/w1_ice/w1_ice_out_of_scope_precip_ja.png',
    );
  });

  testWidgets('w1 — 該当なし survives for a genuine in-scope negative (ja)',
      (tester) async {
    // +8 °C / RH 70 % / no precipitation: every field reported, inside scope,
    // classifier says the radiative-frost window is absent. This is the ONLY
    // shape that may still render 該当なし — proof the split NARROWED the
    // all-clear rather than deleting it.
    await capture(
      tester,
      observation: _obs(temp: 8.0, humidity: 70, precip10m: 0.0),
      guardRowText: '該当なし',
      out: '../../ladder_out/w1_ice/w1_ice_clear_ja.png',
    );
  });

  testWidgets('w1 — the hazard still fires (ja)', (tester) async {
    // +2 °C / RH 70 % / no precipitation — HER founding scenario, the Akita
    // pre-dawn radiative-frost window. Captured so the split cannot be shown
    // to have muted the warning it exists to deliver.
    await capture(
      tester,
      observation: _obs(temp: 2.0, humidity: 70, precip10m: 0.0),
      guardRowText: '⚠ ブラックアイスバーンのおそれ（放射冷却の窓）',
      out: '../../ladder_out/w1_ice/w1_ice_watch_ja.png',
    );
  });
}
