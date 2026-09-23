/// HIE R119 PROBE 2 — MEASUREMENT ONLY. No images, no assertions about
/// legibility. Answers one question the first probe could not: how many dp of
/// her page are the two data-handling disclosures, and are they permanent?
///
/// WHY (OPS-070(B)): the R119 ledger was taken in the NOT-YET-SHARED state,
/// and `_herStatusLine()` puts `location-disclosure` + `egress-disclosure`
/// (359 + 277 ja characters) only in that branch. A cost that disappears after
/// one tap is a different finding from a permanent one, and reporting the
/// first as the second would be the pen overstating its own measurement.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';
import 'render_see_env.dart';

JmaObservation _obs() => JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 15.0,
      humidityPercent: 30,
      windMetersPerSecond: 1.0,
      snowDepthCm: null,
      precipitation10mMm: 0.0,
      visibilityMeters: null,
      observedAtJstKey: '20260115063000',
      fetchedAt: DateTime(2026, 7, 15, 6, 30),
    );

void main() {
  setUpAll(() async {
    final cjk = await loadDiscoveredFace('Roboto', FaceSearch.japanese);
    if (!cjk) throw StateError('R119b REFUSES WITHOUT A JAPANESE FACE');
    await loadMaterialIconsFont();
    installNoopGoldenComparator();
  });

  testWidgets('dp cost of the two disclosures, in the launch state',
      (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(393 * 2, 852 * 2);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(SngnavApp(
      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      jmaFetch: () async => JmaSuccess(_obs()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.byType(AkitaMap), findsOneWidget);

    final pos =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final extent = pos.maxScrollExtent + pos.viewportDimension;

    for (final k in ['location-disclosure', 'egress-disclosure']) {
      final f = find.byKey(Key(k));
      if (f.evaluate().isEmpty) {
        // ignore: avoid_print
        print('R119b $k: NOT PRESENT (UNMEASURED, never absence)');
        continue;
      }
      final r = tester.getRect(f);
      // ignore: avoid_print
      print('R119b $k: top=${(r.top + pos.pixels).toStringAsFixed(0)}dp '
          'height=${r.height.toStringAsFixed(0)}dp '
          '(${(100 * r.height / extent).toStringAsFixed(1)}% of a '
          '${extent.toStringAsFixed(0)}dp page)');
    }
    const ja = AppL10n(Locale('ja'));
    final hud = find.text(ja.driveHudTitle);
    // ignore: avoid_print
    print('R119b driveHud title top='
        '${(tester.getRect(hud).top + pos.pixels).toStringAsFixed(0)}dp; '
        'page extent=${extent.toStringAsFixed(0)}dp');
    // The banner too, for the same ledger.
    final b = find.text(ja.responsibilityBanner);
    // ignore: avoid_print
    print('R119b alpha banner height='
        '${tester.getRect(b).height.toStringAsFixed(0)}dp');

    // ⚑ THE TITLE IS NOT THE THING SHE READS. At launch, before any share, the
    // caution card carries no rung at all -- `advice` is null and the card
    // shows its no-position line where the banner would be. Measuring the
    // title's position and calling the caution card "above the fold" would be
    // the pen reporting a heading as a state. Both are printed.
    for (final k in ['drive-hud-no-position', 'drive-hud-caution-banner']) {
      final f = find.byKey(Key(k));
      if (f.evaluate().isEmpty) {
        // ignore: avoid_print
        print('R119b $k: NOT BUILT in the launch state '
            '(UNMEASURED, never absence)');
        continue;
      }
      final r = tester.getRect(f.first);
      // ignore: avoid_print
      print('R119b $k: top=${(r.top + pos.pixels).toStringAsFixed(0)}dp '
          'bottom=${(r.bottom + pos.pixels).toStringAsFixed(0)}dp');
    }
  });
}
