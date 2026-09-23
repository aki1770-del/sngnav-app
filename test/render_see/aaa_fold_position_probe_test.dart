/// FOLD PROBE — MEASUREMENT ONLY. No assertions, no goldens, no images.
///
/// WHY, written before the act. Two records in this repository state that the
/// 2026-09-23 card reorder puts a road-state rung above the driver's first
/// screen. Neither figure was rendered. The rung capture that exists calls
/// `ensureVisible(banner)` FIRST, so its `top=56.0dp` is a scrolled coordinate
/// and says nothing about page position. The one page-scale figure that does
/// exist says `drive-hud-no-position: top=809dp` against a 721 dp fold — i.e.
/// BELOW it, and the caution banner is a LATER sibling of that line.
///
/// This probe renders the two states that decide the question — first launch
/// with a clear reading, and first launch with a measured whiteout and no
/// share — and prints page coordinates for every element against both folds.
///
/// BOUNDS, riding the output. Host raster, not her panel: no phone gamma,
/// backlight, sunlight or windscreen. NO TIME — nothing here is a glance.
/// 721 dp is INHERITED from an earlier device frame and is not re-measured
/// here. The offline basemap is unavailable under flutter_test, so the map
/// draws its chrome over blank ground; no map-tile judgement is made.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';
import 'render_see_env.dart';

const double _phoneFoldDp = 721; // inherited device frame, not re-measured
const double _rasterFoldDp = 852;

String _jstKey(DateTime utc) {
  final j = utc.add(const Duration(hours: 9));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${j.year}${two(j.month)}${two(j.day)}${two(j.hour)}${two(j.minute)}00';
}

/// FRESH against the real clock: the whiteout window only opens on a reading
/// whose AGE is inside the freshness limit, so a fixture dated in the past
/// silently produces a state with no rung — which is exactly what the first
/// run of this probe did, and it was reported as UNMEASURED, not as absence.
JmaObservation _obs(int? visibility) {
  final now = DateTime.now().toUtc();
  return JmaObservation(
    stationId: '32402',
    stationName: '秋田',
    temperatureCelsius: 5.0,
    humidityPercent: 50,
    windMetersPerSecond: 2.0,
    snowDepthCm: null,
    precipitation10mMm: 0.0,
    visibilityMeters: visibility,
    observedAtJstKey: _jstKey(now),
    fetchedAt: now,
  );
}

void main() {
  setUpAll(() async {
    final cjk = await loadDiscoveredFace('Roboto', FaceSearch.japanese);
    if (!cjk) throw StateError('FOLD PROBE REFUSES WITHOUT A JAPANESE FACE');
    await loadMaterialIconsFont();
    await loadBundledSymbolsFont();
    installNoopGoldenComparator();
  });

  for (final (label, vis) in <(String, int?)>[
    ('LAUNCH_clear_noshare', 1500),
    ('WHITEOUT_vis80_noshare', 80),
  ]) {
    testWidgets('page coordinates, $label', (tester) async {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(393 * 2, 852 * 2);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(SngnavApp(
        actuators: FakeAlertActuators(),
        locale: const Locale('ja'),
        jmaFetch: () async => JmaSuccess(_obs(vis)),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.byType(AkitaMap), findsOneWidget);

      final pos =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      final extent = pos.maxScrollExtent + pos.viewportDimension;
      const ja = AppL10n(Locale('ja'));

      void report(String what, Finder f) {
        if (f.evaluate().isEmpty) {
          // ignore: avoid_print
          print('[$label] $what: NOT BUILT (UNMEASURED, never absence)');
          return;
        }
        final r = tester.getRect(f.first);
        final top = r.top + pos.pixels;
        final bottom = r.bottom + pos.pixels;
        // ignore: avoid_print
        print('[$label] $what: top=${top.toStringAsFixed(0)}dp '
            'bottom=${bottom.toStringAsFixed(0)}dp '
            'h=${r.height.toStringAsFixed(0)}dp '
            '| on her 721dp first screen? '
            '${top < _phoneFoldDp ? (bottom <= _phoneFoldDp ? "FULLY" : "PARTLY") : "NO"}'
            ' | on the 852dp raster screen? '
            '${top < _rasterFoldDp ? (bottom <= _rasterFoldDp ? "FULLY" : "PARTLY") : "NO"}');
      }

      // ignore: avoid_print
      print('[$label] page extent=${extent.toStringAsFixed(0)}dp');
      report('driveHud TITLE', find.text(ja.driveHudTitle));
      report('drive-hud-no-position',
          find.byKey(const Key('drive-hud-no-position')));
      report('drive-hud-caution-banner',
          find.byKey(const Key('drive-hud-caution-banner')));
      report('drive-hud-rung', find.byKey(const Key('drive-hud-rung')));
      report('share-location-button',
          find.byKey(const Key('share-location-button')));
      report('location-disclosure',
          find.byKey(const Key('location-disclosure')));
      report('egress-disclosure', find.byKey(const Key('egress-disclosure')));
      report('alpha responsibility banner', find.text(ja.responsibilityBanner));
      report('map ground', find.byType(AkitaMap));

      // What the rung actually says, read from the app's own text — never from
      // the fixture's name.
      final rung = find.byKey(const Key('drive-hud-rung'));
      if (rung.evaluate().isNotEmpty) {
        final w = tester.widget(rung.first);
        if (w is Text) {
          // ignore: avoid_print
          print('[$label] rung headline = 「${w.data}」');
        }
      }
    });
  }
}
