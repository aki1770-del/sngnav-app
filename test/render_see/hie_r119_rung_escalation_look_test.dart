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

      await tester.ensureVisible(banner);
      await tester.pump();
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
      final r2 = tester.getRect(banner);
      // ignore: avoid_print
      print('R119rung RECT $name: left=${r2.left.toStringAsFixed(1)}dp '
          'top=${r2.top.toStringAsFixed(1)}dp '
          'right=${r2.right.toStringAsFixed(1)}dp '
          'bottom=${r2.bottom.toStringAsFixed(1)}dp (screen coords, dpr2)');
      img.dispose();

    });
  }
}
