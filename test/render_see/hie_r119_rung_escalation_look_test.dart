/// HIE R119 — LOOK at the REAL caution banner in all three rungs.
///
/// WHY, written before the act (OPS-070(B)). On 2026-09-23 I measured the three
/// rung fills at 1.200:1 (stop vs caution) and 1.011:1 (caution vs none) against
/// a 3.0:1 floor, and the Chair lane authorised a second, non-colour channel.
/// The escalating leading rule is that channel. This probe proves it the way
/// the defect was proved: on the rendered pixels, desaturated, not on constants.
///
/// ⚑ IT RENDERS main.dart's OWN BANNER. The two capture suites beside it
/// reproduce `_driveHudPanel`'s Container verbatim in their own file, and one of
/// them (`lowest_rung_neutral_banner_capture_test.dart:43`) has already drifted
/// from the original it claims to copy. An instrument built to a copy rewards
/// the copy (HIE-12). This one pumps the real `SngnavApp`, drives the real
/// `DriveHudController` through the app's own seams, and photographs the widget
/// carrying `Key('drive-hud-caution-banner')`.
///
/// BOUNDS. Host raster, not her panel: no phone or IVI gamma, backlight,
/// sunlight or dirty glass. Desaturation is a luminance projection and is NOT a
/// simulation of any colour-vision deficiency. The downsample is a proxy for
/// lost acuity with no psychophysics behind it. **There is no time in any of
/// this, which is the whole of the word glance.**
library;

import 'dart:async';
import 'dart:io';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';
import 'render_see_env.dart';

const String _out = String.fromEnvironment('HIE_R119_RUNG_OUT');

/// Her phone's page area, inherited from a device frame (HIE bylaws HIE-14) and
/// NOT re-measured here. The fold verdict this probe prints is stated against
/// it, and against the PAGE coordinate only.
const double _phoneFoldDp = 721;

final _start = DateTime.utc(2026, 1, 14, 21);
var _now = _start;
int? _visibility = 20000;
double _wind = 2;
double _temp = 5;
int _humidity = 50;

String _jstKey(DateTime utc) {
  final j = utc.add(const Duration(hours: 9));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${j.year}${two(j.month)}${two(j.day)}${two(j.hour)}${two(j.minute)}00';
}

Future<JmaResult> _jma() async => JmaSuccess(JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: _temp,
      humidityPercent: _humidity,
      windMetersPerSecond: _wind,
      snowDepthCm: null,
      precipitation10mMm: 0,
      visibilityMeters: _visibility,
      observedAtJstKey: _jstKey(_now),
      fetchedAt: _now,
    ));

Position _position(DateTime at) => Position(
      latitude: 39.7186,
      longitude: 140.1024,
      timestamp: at,
      accuracy: 10,
      hasAccuracy: true,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void _write(String name, Uint8List bytes) {
  if (_out.isEmpty) {
    // ignore: avoid_print
    print('R119rung: HIE_R119_RUNG_OUT unset — no frame for $name');
    return;
  }
  Directory(_out).createSync(recursive: true);
  File('$_out/$name').writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('R119rung: wrote $name (${bytes.length} bytes)');
}


/// ⚑⚑ THIS PROBE DOES NOT RUN IN THE SUITE, AND HERE IS WHY IT MUST NOT.
///
/// Measured 2026-09-23: run inside a bare `flutter test` this file times out —
/// `TimeoutException after 0:10:00`. Its stalls are real and recorded (a second
/// `pumpWidget` of the app in one file, and a `jumpTo` + `pump` loop that never
/// returns), and I worked around them by running each state in its own process.
/// **What I did not do was connect "it stalls" to "and therefore it fails the
/// suite I am committing it into."** It went in at `9a41c0f`, and the app's CI
/// job runs a bare `flutter test`, so it would have taken CI red and added ~10
/// minutes per case. Caught by reading the FINAL summary of a full run
/// (`+1348 -12`) after having reported a mid-run progress line (`-8`) as the
/// verdict — the same success-shaped-value family, in my own reporting.
///
/// It is a MEASUREMENT PROBE, not a guard: it asserts nothing about the app and
/// only produces frames and figures. So it is gated ON PURPOSE rather than
/// deleted, and it says out loud that it did not run:
///
///   flutter test THIS_FILE --dart-define=HIE_R119_PROBES=1
///
/// ⚑ The stall itself is NOT FIXED. Running it needs `--plain-name` for one case.
const bool _runProbes = bool.fromEnvironment('HIE_R119_PROBES');

void _announceSkipped(String what) {
  // ignore: avoid_print
  print('R119 PROBE NOT RUN: $what. This is a measurement probe, not a guard, '
      'and it STALLS in a shared process (measured: 10-minute timeout). '
      'It measured nothing here, which is not the same as passing. '
      'Re-run with --dart-define=HIE_R119_PROBES=1 and --plain-name for one case.');
}

void main() {
  setUpAll(() async {
    final cjk = await loadDiscoveredFace('Roboto', FaceSearch.japanese);
    if (!cjk) {
      throw StateError('R119rung REFUSES WITHOUT A JAPANESE FACE — '
          '${describeFaceSearch(FaceSearch.japanese)}');
    }
    if (!await loadMaterialIconsFont()) {
      throw StateError('R119rung REFUSES WITHOUT MaterialIcons.');
    }
    await loadBundledSymbolsFont();
    installNoopGoldenComparator();
  });

  // ⚑ NAMED BY THEIR INPUTS, NOT BY THE RUNG I EXPECT. My first pass named the
  // cases none/caution/stop and the first one came back 「注意して走行」 with a
  // 20,000 m visibility that the app does not read as clear -- a file name
  // asserting a rung would have made my own fixture look like the app's answer.
  // The rung each case produces is PRINTED from the app's own headline.
  // 1500 m is the measured-clear value this repo's own lowest-rung capture uses
  // (lowest_rung_neutral_banner_capture_test.dart:123); 80 m is the whiteout the
  // measured-whiteout suite uses; 12 m/s fires the app's measured wind watch.
  for (final (name, vis, wind, temp, humidity)
      in <(String, int?, double, double, int)>[
    ('A_vis1500_wind2', 1500, 2.0, 5.0, 50),
    ('B_vis1500_wind12', 1500, 12.0, 5.0, 50),
    ('C_vis80_wind2', 80, 2.0, 5.0, 50),
  ]) {
    testWidgets('REAL banner, rung state $name', (tester) async {
      if (!_runProbes) {
        _announceSkipped('hie_r119_rung_escalation_look_test.dart');
        return;
      }
      _now = _start;
      _visibility = vis;
      _wind = wind;
      _temp = temp;
      _humidity = humidity;
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(393 * 2, 852 * 2);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final platform = StreamController<Position>();
      addTearDown(platform.close);
      final actuators = FakeAlertActuators();
      // ⚑ The empty-frame reset first. Without it the SECOND app pump in this
      // file hung with no summary and no exit code -- HIE-13's two instances in
      // quick succession, a third time for me. This is the idiom the repo's own
      // her_no_position_measured_whiteout_test.dart:210 already uses.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(SngnavApp(
        actuators: actuators,
        locale: const Locale('ja'),
        clock: () => _now,
        jmaFetch: _jma,
        positionSource: () => herPositionStream(
              isServiceEnabled: () async => true,
              checkPermission: () async => LocationPermission.whileInUse,
              positionStream: () => platform.stream,
            ),
      ));
      await tester.pump();
      await tester.pump();

      final share = find.byKey(const Key('share-location-button'));
      await tester.ensureVisible(share);
      await tester.pump();
      await tester.tap(share);
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      platform.add(_position(_now));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      _now = _now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }

      final banner = find.byKey(const Key('drive-hud-caution-banner'));
      expect(banner, findsOneWidget,
          reason: 'control: the real caution banner is built in state $name');
      // The rung the app itself decided, printed BEFORE any pixel is believed.
      final headline = find.descendant(
          of: banner, matching: find.byKey(const Key('drive-hud-rung')));
      // ignore: avoid_print
      print('R119rung STATE $name: headline='
          '「${(tester.widget(headline) as Text).data}」  '
          'rule=${find.descendant(of: banner, matching: find.byKey(const Key('drive-hud-rung-rule'))).evaluate().isEmpty ? 'NONE' : '${tester.getRect(find.descendant(of: banner, matching: find.byKey(const Key('drive-hud-rung-rule'))).first).width.toStringAsFixed(0)}dp'}  '
          'banner=${tester.getRect(banner).width.toStringAsFixed(0)}x'
          '${tester.getRect(banner).height.toStringAsFixed(0)}dp');

      // Page coordinate FIRST, while nothing has scrolled.
      final scrollBefore = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      final pageTopBeforeScroll =
          tester.getRect(banner).top + scrollBefore;
      await tester.ensureVisible(banner);
      await tester.pump();
      final scrollAfter = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      final rb = tester.renderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary).first);
      final img = await rb.toImage(pixelRatio: 2.0);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      _write('screen_$name.png', png!.buffer.asUint8List());

      // ⚑ THE CROP IS DONE OUTSIDE THIS PROCESS. An in-Dart
      // ImageDescriptor.raw -> instantiateCodec hung this probe with no
      // summary and no exit code -- HIE-13's await, a third time. The screen
      // PNG plus the banner's measured rect, printed below, is everything the
      // crop needs, and a shell doing it cannot hang a test.
      // ⚑⚑ THIS BLOCK PRINTS A CROP RECTANGLE, AND IT MAY NEVER AGAIN PRINT
      // ANYTHING THAT READS AS A PAGE POSITION. The version before 2026-09-23
      // called `ensureVisible(banner)` and THEN printed `top=56.0dp`. That is a
      // SCROLLED coordinate — where the banner sits on screen after the rig
      // scrolled it into view — and it reads exactly like a fold measurement.
      // It is not one. AAA rendered the same banner without scrolling and found
      // the rung 125 dp BELOW her fold while this probe was printing 56.
      // A measurement wearing the costume of a different measurement is worse
      // than no measurement, because it is quoted.
      // So: the PAGE position is taken BEFORE any scrolling, the scroll offset
      // is printed beside the screen rect, and the screen rect is labelled as a
      // crop box and nothing else. The fold verdict comes from the page figure.
      // ignore: avoid_print
      print('R119rung PAGE $name: rung top='
          '${pageTopBeforeScroll.toStringAsFixed(0)}dp of her page '
          '(fold ${_phoneFoldDp.toStringAsFixed(0)}dp) -> '
          '${pageTopBeforeScroll < _phoneFoldDp ? "ON her first screen" : "BELOW her fold"}'
          '  [page coordinate, measured BEFORE any scroll]');
      final r2 = tester.getRect(banner);
      // ignore: avoid_print
      print('R119rung CROPBOX $name: left=${r2.left.toStringAsFixed(1)} '
          'top=${r2.top.toStringAsFixed(1)} right=${r2.right.toStringAsFixed(1)} '
          'bottom=${r2.bottom.toStringAsFixed(1)} dp AFTER ensureVisible, at '
          'scrollOffset=${scrollAfter.toStringAsFixed(0)}dp — THIS IS A CROP BOX '
          'FOR THE PNG, NOT A PAGE POSITION. Do not quote its top as a fold '
          'figure; the page figure is the line above.');
      img.dispose();

    });
  }
}
