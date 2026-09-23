/// The map and the status line under it, in the REAL app, in every position
/// state a dead GPS reaches: checked always, rendered to PNG on request.
///
/// WHY, written before the act. The render review's harnesses render [AkitaMap] alone, from
/// a replica of `main.dart`'s mapping, and derive the status line as text
/// without rendering it. Neither can see whether the app is wired. This drives
/// `SngnavApp` itself, through its injected position stream and clock, the way
/// a real feed and the blackout watchdog drive it, and reads what the app
/// built: the status line's own Text, the map's own markers.
///
/// Checks (always, no fonts needed): the exact status line in each state, the
/// ring, the words 現在地不明, the circle, and no 「Infinity」 anywhere on screen.
///
/// Frames (only with `--dart-define=HER_LOST_STATUS_OUT=/absolute/empty/dir`
/// and the CJK fonts present): each state cropped to the map plus the status
/// line, normal and desaturated, written at the END of a test whose checks all
/// passed. Use them only from a run that exited 0.
///
/// BOUNDS. Host raster, not a phone panel: no gamma, backlight, sunlight or
/// physical size. Desaturation is a luminance projection, not a colour-vision
/// simulation. A string that renders is not a string read in a glance; no
/// driver has looked at this. The app feeds its drive brain wall-clock time on
/// position EVENTS (`_feedDriveHud` does not pass the injected clock), so the
/// stream-error state here reaches `lost`; the 5 s dead-reckoning case is
/// pinned in `test/her_map_inputs_test.dart` with an explicit clock.
///
///   flutter test test/render_see/her_position_lost_status_capture_test.dart \
///     --dart-define=HER_LOST_STATUS_OUT=/absolute/empty/dir
library;

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_map/flutter_map.dart' show CircleLayer;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';
import 'render_see_env.dart';

const _out = String.fromEnvironment('HER_LOST_STATUS_OUT');

// 06:00 JST on a January morning, as in the render review's harness.
final _t0 = DateTime.utc(2026, 1, 14, 21, 0);
const _lat = 39.7195;
const _lon = 140.1180;

const _statusKey = Key('her-status-line');
const _ringKey = ValueKey('her-dot-degraded');
const _realDotKey = ValueKey('her-dot-real-fix');
const _wordsKey = ValueKey('her-position-unknown-label');

JmaObservation _clearObs() => JmaObservation(
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

PositionAvailable _fix(double acc) => PositionAvailable(
      latitude: _lat,
      longitude: _lon,
      accuracyMeters: acc,
      timestamp: _t0,
    );

final _manifest = <String>[];
var _cjk = false;

void main() {
  const ipa = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf';
  const droid = '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _cjk = await loadCjkFamily('Roboto', [ipa, droid]);
    await loadMaterialIconsFont();
    await loadBundledSymbolsFont();
    final tmp = await Directory.systemTemp.createTemp('her_lost_status');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
    if (_out.isNotEmpty) {
      final dir = Directory(_out);
      expect(dir.existsSync() && dir.listSync().isNotEmpty, isFalse,
          reason: 'HER_LOST_STATUS_OUT is not empty; refusing to mix runs.');
    }
  });

  tearDownAll(() {
    if (_out.isEmpty || _manifest.isEmpty) return;
    File('$_out/MANIFEST.txt').writeAsStringSync(
      [
        'HER map + status line, rendered from the real SngnavApp.',
        'UTC ${DateTime.now().toUtc().toIso8601String()} · logical 393x852 · '
            'devicePixelRatio 2.0 · locale ja · CJK font loaded: $_cjk',
        'Each frame was written at the end of a test whose checks passed. '
            'The exit code is recorded by the caller.',
        '',
        ..._manifest,
      ].join('\n'),
      flush: true,
    );
  });

  var now = _t0;

  Future<StreamController<PositionFix>> pumpSharing(WidgetTester tester) async {
    now = _t0;
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(393 * 2, 852 * 2);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Broadcast, as in position_watchdog_test.dart: after 停止 cancels the
    // app's subscription, closing a single-subscription controller never
    // completes, and the stop test timed out at 10 minutes on exactly that.
    final positions = StreamController<PositionFix>.broadcast();
    await tester.pumpWidget(SngnavApp(
      // Not about the consent act; that is guarded in
      // test/widgets/location_consent_act_and_privacy_surface_test.dart.
      locationConsent: true,

      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      clock: () => now,
      jmaFetch: () async => JmaSuccess(_clearObs()),
      positionSource: () => positions.stream,
    ));
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(find.text('現在地を共有'));
    await tester.pump();
    await tester.tap(find.text('現在地を共有'));
    await tester.pump();
    return positions;
  }

  /// No fix for [silence] while sharing stays on: the blackout watchdog's next
  /// 15 s tick polls the drive brain at the injected clock.
  Future<void> silentDrought(WidgetTester tester, Duration silence) async {
    now = _t0.add(silence);
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
  }

  String? statusLine(WidgetTester tester) {
    final f = find.byKey(_statusKey);
    return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
  }

  void expectNoInfinityOnScreen() {
    expect(find.textContaining('Infinity'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
  }

  final circle = find.byWidgetPredicate((w) => w is CircleLayer);

  /// Crop the screen to the map and the line under it, write normal and
  /// desaturated PNGs, and record what was checked.
  Future<void> capture(
    WidgetTester tester,
    String name,
    List<String> checked,
  ) async {
    if (_out.isEmpty || !_cjk) {
      print('[capture] $name not written (out="${_out.isEmpty ? '' : _out}" '
          'cjk=$_cjk)');
      return;
    }
    await Scrollable.ensureVisible(tester.element(find.byType(AkitaMap)),
        alignment: 0.2);
    // Let the offline basemap's real IO finish, then paint.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    var rect = tester.getRect(find.byType(AkitaMap));
    final status = find.byKey(_statusKey);
    final below = status.evaluate().isNotEmpty
        ? status
        : find.text('位置情報はまだ共有されていません。');
    if (below.evaluate().isNotEmpty) {
      rect = rect.expandToInclude(tester.getRect(below));
    }
    rect = rect.inflate(8);

    await tester.runAsync(() async {
      final image =
          await captureImage(tester.element(find.byType(MaterialApp)));
      final scale = image.width / 393.0;
      final raw =
          (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!
              .buffer
              .asUint8List();
      final left = math.max(0, (rect.left * scale).floor());
      final top = math.max(0, (rect.top * scale).floor());
      final right = math.min(image.width, (rect.right * scale).ceil());
      final bottom = math.min(image.height, (rect.bottom * scale).ceil());
      final w = right - left, h = bottom - top;
      final crop = Uint8List(w * h * 4);
      final grey = Uint8List(w * h * 4);
      final colours = <int>{};
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final s = ((top + y) * image.width + left + x) * 4;
          final d = (y * w + x) * 4;
          crop.setRange(d, d + 4, raw, s);
          final lum = 0.2126 * _lin[raw[s]] +
              0.7152 * _lin[raw[s + 1]] +
              0.0722 * _lin[raw[s + 2]];
          final g = _grey8(lum);
          grey[d] = g;
          grey[d + 1] = g;
          grey[d + 2] = g;
          grey[d + 3] = raw[s + 3];
          colours.add((raw[s] << 16) | (raw[s + 1] << 8) | raw[s + 2]);
        }
      }
      image.dispose();
      File('$_out/$name.png')
          .writeAsBytesSync(await _png(crop, w, h), flush: true);
      File('$_out/${name}_DESATURATED.png')
          .writeAsBytesSync(await _png(grey, w, h), flush: true);
      _manifest
        ..add('$name  ${w}x$h px  distinct colours in crop: ${colours.length}')
        ..addAll(checked.map((c) => '  PASS  $c'));
      print('[capture] $name ${w}x$h written');
    });
  }

  testWidgets('control — a trusted fix: the solid dot and 「現在地 · ±15 m」',
      (tester) async {
    final positions = await pumpSharing(tester);
    positions.add(_fix(15));
    await tester.pump();

    expect(statusLine(tester), '現在地 · ±15 m');
    expect(find.byKey(_realDotKey), findsOneWidget);
    expect(find.byKey(_wordsKey), findsNothing);
    expectNoInfinityOnScreen();
    await capture(tester, '01_real_fix', [
      'status line "現在地 · ±15 m"',
      'solid dot drawn, no words',
    ]);
    await positions.close();
  });

  testWidgets('dead reckoning 60 s: ring and circle, no words, line unchanged',
      (tester) async {
    final positions = await pumpSharing(tester);
    positions.add(_fix(15));
    await tester.pump();
    await silentDrought(tester, const Duration(seconds: 60));

    expect(statusLine(tester), 'GPS 途絶（推測航法） · 最後の位置 ±135m',
        reason: 'byte-identical to what bd6ebc4 built here');
    expect(find.byKey(_ringKey), findsOneWidget);
    expect(circle, findsOneWidget);
    expect(find.byKey(_wordsKey), findsNothing);
    expectNoInfinityOnScreen();
    await capture(tester, '02_dead_reckoning_60s', [
      'status line "GPS 途絶（推測航法） · 最後の位置 ±135m"',
      'ring and circle drawn, no words',
    ]);
    await positions.close();
  });

  testWidgets('lost 180 s: the words, the ring, no circle, and the age',
      (tester) async {
    final positions = await pumpSharing(tester);
    positions.add(_fix(15));
    await tester.pump();
    await silentDrought(tester, const Duration(seconds: 180));

    expect(statusLine(tester), '現在地 不明 · 最後の位置 3分前');
    expect(find.byKey(_wordsKey), findsOneWidget);
    expect(find.byKey(_ringKey), findsOneWidget);
    expect(circle, findsNothing);
    expectNoInfinityOnScreen();
    await capture(tester, '03_lost_180s', [
      'status line "現在地 不明 · 最後の位置 3分前"',
      'words 現在地不明 and ring drawn, no circle',
    ]);
    await positions.close();
  });

  testWidgets('lost 90 min: the same map, and an age in hours', (tester) async {
    final positions = await pumpSharing(tester);
    positions.add(_fix(15));
    await tester.pump();
    await silentDrought(tester, const Duration(minutes: 90));

    expect(statusLine(tester), '現在地 不明 · 最後の位置 1時間30分前');
    expect(find.byKey(_wordsKey), findsOneWidget);
    expect(find.byKey(_ringKey), findsOneWidget);
    expect(circle, findsNothing,
        reason: 'at bd6ebc4 a ±10.8 km circle tinted the whole map');
    expectNoInfinityOnScreen();
    await capture(tester, '04_lost_90min', [
      'status line "現在地 不明 · 最後の位置 1時間30分前"',
      'words 現在地不明 and ring drawn, no circle',
    ]);
    await positions.close();
  });

  testWidgets(
      'lost with no trusted fix ever: the words alone, no ring, no Infinity',
      (tester) async {
    final positions = await pumpSharing(tester);
    // A finite negative accuracy passes the chokepoint; the controller
    // refuses it and has no trusted baseline.
    positions.add(_fix(-1));
    await tester.pump();

    expect(statusLine(tester), '現在地 不明 · 最後の位置 なし',
        reason: 'at bd6ebc4 this line read 「… 最後の位置 ±Infinitym」');
    expect(find.byKey(_wordsKey), findsOneWidget);
    expect(find.byKey(_ringKey), findsNothing,
        reason: 'no ring at a sample the controller refused');
    expect(find.byKey(_realDotKey), findsNothing);
    expectNoInfinityOnScreen();
    await capture(tester, '05_lost_never_trusted', [
      'status line "現在地 不明 · 最後の位置 なし"',
      'words 現在地不明 alone, no ring',
    ]);
    await positions.close();
  });

  testWidgets(
      'the GPS stream errors after a trusted fix: the map is NOT empty',
      (tester) async {
    final positions = await pumpSharing(tester);
    positions.add(_fix(15));
    await tester.pump();
    positions.addError(StateError('platform GPS stream failed'));
    await tester.pump();

    expect(find.byKey(_ringKey), findsOneWidget,
        reason: 'at bd6ebc4 this frame was byte-identical to no position');
    expect(statusLine(tester), contains('GPSストリームのエラー'));
    final words = find.byKey(_wordsKey).evaluate().isNotEmpty;
    print('[measure] stream error: words on the map = $words '
        '(the drive brain was fed wall-clock time on the event)');
    expectNoInfinityOnScreen();
    await capture(tester, '06_stream_error_after_fix', [
      'status line "${statusLine(tester)}"',
      'ring drawn at the last trusted point; words on map: $words',
    ]);
    await positions.close();
  });

  testWidgets('she stops sharing while lost: no ring and no words remain',
      (tester) async {
    final positions = await pumpSharing(tester);
    positions.add(_fix(15));
    await tester.pump();
    await silentDrought(tester, const Duration(seconds: 180));
    expect(find.byKey(_wordsKey), findsOneWidget, reason: 'control');

    await tester.ensureVisible(find.text('停止'));
    await tester.pump();
    await tester.tap(find.text('停止'));
    await tester.pump();

    expect(find.byKey(_wordsKey), findsNothing,
        reason: 'a feed she turned off makes no claim about where she is');
    expect(find.byKey(_ringKey), findsNothing);
    expect(find.byKey(_statusKey), findsNothing);
    expect(find.text('位置情報はまだ共有されていません。'), findsOneWidget);
    expectNoInfinityOnScreen();
    await capture(tester, '07_stopped_while_lost', [
      'consent line "位置情報はまだ共有されていません。"',
      'no ring, no words',
    ]);
    await positions.close();
  });
}

final List<double> _lin = List<double>.generate(256, (i) {
  final c = i / 255.0;
  return c <= 0.03928
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
});

int _grey8(double y) {
  final v = y <= 0.0031308 ? 12.92 * y : 1.055 * math.pow(y, 1 / 2.4) - 0.055;
  return (v * 255).round().clamp(0, 255);
}

Future<Uint8List> _png(Uint8List rgba, int w, int h) async {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, done.complete);
  final image = await done.future;
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}
