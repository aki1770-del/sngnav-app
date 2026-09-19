/// Render capture — the driver's position dot: real fix / mock / degraded, normal and
/// desaturated, MEASURED in the rendered pixels.
///
/// WHY, written before the act. On `14f3699` the dot carried its three states
/// on fill colour alone; rendered desaturated they were one grey disc
/// (measured 2026-09-13). The frames that first showed it came from render
/// tests that died after writing their PNGs — a directory of images over a
/// failed run. So this capture:
///
/// 1. renders the REAL [AkitaMap] over the bundled OFFLINE basemap (the pale
///    surface the dot actually sits on), never the dot widget in isolation —
///    flutter_map lays a marker child out under tight constraints, which can
///    erase a size difference the widget has on its own;
/// 2. MEASURES the rendered pixels and prints every number: where the dot
///    landed, its footprint, whether two states share one footprint, what is
///    left of their difference once colour is removed, and the luminance
///    contrast between the pixels each state changed most;
/// 3. writes PNGs ONLY after every check has passed, then `MANIFEST.txt`.
///    A directory without `MANIFEST.txt` is a failed run and is not evidence.
///
/// The station pin is a MaterialIcons glyph, which `flutter test` does not
/// load by itself: unloaded, it renders as a hollow red box — a square
/// outline, the very form the mock state uses. The capture loads the SDK's
/// own font and, before it writes any frame, checks that the pin came out as
/// a pin.
///
/// Negative control on the real file: against `14f3699` this test FAILS.
///
///   flutter test test/render_see/her_dot_glance_capture_test.dart \
///     --dart-define=HER_DOT_GLANCE_OUT=/absolute/path/to/an/empty/dir
///
/// Without the define it measures and asserts, and writes nothing.
///
/// BOUND — what this cannot see: a host raster at devicePixelRatio 1.0, not
/// the IVI panel, its gamma, its backlight, or sunlight on it. Desaturation is
/// a relative-luminance projection, not a simulation of colour-vision
/// deficiency. Discriminable is not understood: no driver has looked at these
/// under a timed glance.
library;

// The printed numbers ARE the evidence this capture exists to produce.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_map/flutter_map.dart' show Epsg3857;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:offline_tiles/offline_tiles.dart';
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/services/offline_basemap.dart';

import 'render_see_env.dart';

const _outDir = String.fromEnvironment('HER_DOT_GLANCE_OUT');

// AkitaMap's own initial camera: centred on the station, zoom 12.
const _mapWidth = 600;
const _mapHeight = 340;
const _zoom = 12.0;

/// Her position for the three-state comparison: inland, clear of the station
/// marker and the attribution bar, so the dot is the only thing two frames
/// can differ by.
const _her = LatLng(39.7273, 140.1395);

/// A pixel belongs to a dot when some channel moved at least this far from the
/// same pixel of the no-position control.
const _strong = 40;

/// Half-side of the window around her position that a dot may touch.
const _window = 40;

/// WCAG 2.1 contrast floor for non-text UI components.
const _floor = 3.0;

final List<double> _linear = List<double>.generate(256, (i) {
  final c = i / 255.0;
  return c <= 0.03928
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
});

double _luminance(int r, int g, int b) =>
    0.2126 * _linear[r] + 0.7152 * _linear[g] + 0.0722 * _linear[b];

double _contrast(double a, double b) =>
    (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);

int _srgb(double y) {
  final v = y <= 0.0031308 ? 12.92 * y : 1.055 * math.pow(y, 1 / 2.4) - 0.055;
  return (v * 255).round().clamp(0, 255);
}

class _Frame {
  _Frame(this.name, this.width, this.height, this.rgba, this.png);

  final String name;
  final int width;
  final int height;

  /// Straight (unpremultiplied) RGBA8888, row-primary.
  final Uint8List rgba;
  final Uint8List png;

  double luminanceAt(int p) =>
      _luminance(rgba[p * 4], rgba[p * 4 + 1], rgba[p * 4 + 2]);

  int greyAt(int p) => _srgb(luminanceAt(p));

  /// Largest per-channel difference from [other] at pixel index [p].
  int deltaAt(_Frame other, int p) {
    var d = 0;
    for (var c = 0; c < 4; c++) {
      final v = (rgba[p * 4 + c] - other.rgba[p * 4 + c]).abs();
      if (v > d) d = v;
    }
    return d;
  }

  /// A relative-luminance greyscale copy (alpha kept).
  Uint8List desaturatedRgba() {
    final out = Uint8List(rgba.length);
    for (var p = 0; p < width * height; p++) {
      final g = greyAt(p);
      out[p * 4] = g;
      out[p * 4 + 1] = g;
      out[p * 4 + 2] = g;
      out[p * 4 + 3] = rgba[p * 4 + 3];
    }
    return out;
  }
}

/// What one state changed in the frame, relative to the no-position control.
class _Footprint {
  _Footprint(this.state, this.pixels, this.outside, this.frame);

  final String state;

  /// Pixel indices inside the window where the dot moved the frame by at
  /// least [_strong].
  final Set<int> pixels;

  /// Pixels OUTSIDE the window that differ from the control at all.
  final int outside;
  final _Frame frame;

  int get minX => pixels.map((p) => p % frame.width).reduce(math.min);
  int get maxX => pixels.map((p) => p % frame.width).reduce(math.max);
  int get minY => pixels.map((p) => p ~/ frame.width).reduce(math.min);
  int get maxY => pixels.map((p) => p ~/ frame.width).reduce(math.max);
  int get boxW => maxX - minX + 1;
  int get boxH => maxY - minY + 1;
  double get centreX => (minX + maxX) / 2 + 0.5;
  double get centreY => (minY + maxY) / 2 + 0.5;

  /// Median luminance of the quarter of footprint pixels this state changed
  /// MOST — the pixels that carry the state, not its glow or anti-aliasing.
  double stateLuminance(_Frame control) {
    final byDelta = pixels.toList()
      ..sort((a, b) =>
          frame.deltaAt(control, b).compareTo(frame.deltaAt(control, a)));
    final core = byDelta.take(math.max(1, byDelta.length ~/ 4)).toList()
      ..sort((a, b) => frame.luminanceAt(a).compareTo(frame.luminanceAt(b)));
    return frame.luminanceAt(core[core.length ~/ 2]);
  }
}

_Footprint _footprintOf(
  String state,
  _Frame frame,
  _Frame control,
  Offset at,
) {
  final pixels = <int>{};
  var outside = 0;
  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      final p = y * frame.width + x;
      final d = frame.deltaAt(control, p);
      if (d == 0) continue;
      final inWindow = (x + 0.5 - at.dx).abs() <= _window &&
          (y + 0.5 - at.dy).abs() <= _window;
      if (!inWindow) {
        outside++;
      } else if (d >= _strong) {
        pixels.add(p);
      }
    }
  }
  return _Footprint(state, pixels, outside, frame);
}

double _overlap(Set<int> a, Set<int> b) {
  final inter = a.intersection(b).length;
  final union = a.length + b.length - inter;
  return union == 0 ? 1.0 : inter / union;
}

/// Pixels inside the window whose desaturated grey level differs by >= 64
/// between two frames — what is left of a difference once colour is gone.
int _greySeparation(_Frame a, _Frame b, Offset at) {
  var n = 0;
  for (var y = (at.dy - _window).floor(); y <= (at.dy + _window).ceil(); y++) {
    for (var x = (at.dx - _window).floor();
        x <= (at.dx + _window).ceil();
        x++) {
      if (x < 0 || y < 0 || x >= a.width || y >= a.height) continue;
      final p = y * a.width + x;
      if ((a.greyAt(p) - b.greyAt(p)).abs() >= 64) n++;
    }
  }
  return n;
}

Offset _pixelOf(LatLng point) {
  const crs = Epsg3857();
  final centre = crs.latLngToOffset(akitaStation, _zoom);
  final here = crs.latLngToOffset(point, _zoom);
  return here - centre + const Offset(_mapWidth / 2, _mapHeight / 2);
}

Future<Uint8List> _encodePng(Uint8List rgba, int width, int height) async {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      rgba, width, height, ui.PixelFormat.rgba8888, done.complete);
  final image = await done.future;
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// The red station pin inside the station marker, measured: how many red
/// pixels it has, and how wide its lowest red row is. A pin glyph tapers to a
/// point; a missing-font box ends in a full-width edge.
({int red, int bottomRow}) _stationPin(_Frame f) {
  final at = _pixelOf(akitaStation);
  var red = 0;
  var lowest = -1;
  final widths = <int, int>{};
  for (var y = (at.dy - 15).round(); y <= (at.dy + 25).round(); y++) {
    for (var x = (at.dx - 20).round(); x <= (at.dx + 20).round(); x++) {
      final i = (y * f.width + x) * 4;
      if (f.rgba[i] >= 150 && f.rgba[i + 1] <= 90 && f.rgba[i + 2] <= 90) {
        red++;
        widths[y] = (widths[y] ?? 0) + 1;
        if (y > lowest) lowest = y;
      }
    }
  }
  return (red: red, bottomRow: lowest < 0 ? 0 : widths[lowest]!);
}

const _crop = 96;
const _gap = 8;

/// Unmagnified crops around [at], side by side, separated by white gaps.
Uint8List _strip(List<_Frame> frames, Offset at, {required bool grey}) {
  final width = frames.length * _crop + (frames.length - 1) * _gap;
  final out = Uint8List(width * _crop * 4)..fillRange(0, width * _crop * 4, 255);
  final left = (at.dx - _crop / 2).round();
  final top = (at.dy - _crop / 2).round();
  for (var i = 0; i < frames.length; i++) {
    final f = frames[i];
    final src = grey ? f.desaturatedRgba() : f.rgba;
    final ox = i * (_crop + _gap);
    for (var y = 0; y < _crop; y++) {
      for (var x = 0; x < _crop; x++) {
        final sx = left + x, sy = top + y;
        if (sx < 0 || sy < 0 || sx >= f.width || sy >= f.height) continue;
        final s = (sy * f.width + sx) * 4, d = (y * width + ox + x) * 4;
        out.setRange(d, d + 4, src, s);
      }
    }
  }
  return out;
}

void main() {
  const ipa = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf';
  const droid = '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

  late Directory tmp;
  late OfflineTileProvider provider;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The station label. The pin's icon font is loaded inside the test, AFTER
    // a first render without it — that render is the glyph check's negative
    // control. The dot itself is geometry and needs no font.
    await loadCjkFamily('Roboto', [ipa, droid]);
    tmp = await Directory.systemTemp.createTemp('her_dot_glance');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
    // Hermetic: the bundled archive, no network fallback. A missing archive
    // FAILS here rather than rendering the dot over nothing.
    provider = await buildOfflineTileProviderFromBytes(
      Uint8List.fromList(await File(akitaOfflineMbtilesAsset).readAsBytes()),
      tempDir: tmp,
      archiveFilename: 'akita_offline.mbtiles',
      allowOnlineFallback: false,
    );
  });

  tearDownAll(() async {
    await provider.dispose();
  });

  testWidgets(
    'the three position-dot states stay distinct once colour is removed, '
    'measured in the pixels of the real AkitaMap',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize =
          Size(_mapWidth.toDouble() + 40, _mapHeight.toDouble() + 40);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final boundary = GlobalKey();

      Future<_Frame> render(
        String name, {
        LatLng? her,
        double? accuracy,
        bool mock = false,
        bool degraded = false,
      }) async {
        final app = MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Roboto'),
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: RepaintBoundary(
                key: boundary,
                child: SizedBox(
                  width: _mapWidth.toDouble(),
                  child: AkitaMap(
                    height: _mapHeight.toDouble(),
                    baseTileProvider: provider,
                    herPosition: her,
                    herAccuracyMeters: accuracy,
                    isHerPositionMock: mock,
                    positionDegraded: degraded,
                  ),
                ),
              ),
            ),
          ),
        );
        late _Frame frame;
        await tester.runAsync(() async {
          await tester.pumpWidget(app);
          await tester.pump();
          for (var i = 0; i < 25; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            await tester.pump(const Duration(milliseconds: 40));
          }
          final ro = boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await ro.toImage(pixelRatio: 1.0);
          final raw = await image.toByteData(
              format: ui.ImageByteFormat.rawStraightRgba);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          frame = _Frame(name, image.width, image.height,
              raw!.buffer.asUint8List(), png!.buffer.asUint8List());
          image.dispose();
        });
        print('[capture] $name ${frame.width}x${frame.height}');
        return frame;
      }

      final results = <String>[];
      var failed = 0;
      void check(String label, bool ok, String detail) {
        if (!ok) failed++;
        final line = '${ok ? 'PASS' : 'FAIL'}  $label — $detail';
        results.add(line);
        print('[check] $line');
      }

      final at = _pixelOf(_her);
      print('[setup] her position $_her -> expected pixel '
          '(${at.dx.toStringAsFixed(2)}, ${at.dy.toStringAsFixed(2)})');

      // ---- the station pin's font: negative control first ------------------
      final withoutIconFont = await render('control_without_icon_font');
      final iconFont = await tester.runAsync(loadMaterialIconsFont) ?? false;

      // ---- measurement frames: the dot alone (no accuracy circle) ----------
      final control = await render('control_no_position');
      final real = await render('measure_real_fix', her: _her);
      final mock = await render('measure_mock', her: _her, mock: true);
      final degraded =
          await render('measure_degraded', her: _her, degraded: true);
      final controlAgain = await render('control_no_position_again');

      final colours = <int>{};
      for (var p = 0; p < control.width * control.height; p++) {
        colours.add((control.rgba[p * 4] << 16) |
            (control.rgba[p * 4 + 1] << 8) |
            control.rgba[p * 4 + 2]);
      }
      check('RENDERED the control drew a basemap, not an empty canvas',
          colours.length >= 50, '${colours.length} distinct colours');

      var drift = 0;
      for (var p = 0; p < control.width * control.height; p++) {
        if (control.deltaAt(controlAgain, p) != 0) drift++;
      }
      check('STABLE the basemap did not change during the run', drift == 0,
          '$drift pixels differ between the first and last control');

      // Frames a person will look at must not show a missing-font box where
      // the station pin is. It does not move a single dot number, so a run
      // that writes nothing only reports it.
      bool isPin(({int red, int bottomRow}) m) =>
          m.red >= 120 && m.bottomRow <= 6;
      final pin = _stationPin(control);
      final noFontPin = _stationPin(withoutIconFont);
      final pinDetail = 'icon font ${iconFont ? 'loaded' : 'NOT loaded'}; '
          'with it ${pin.red} red pixels, lowest red row ${pin.bottomRow}px '
          'wide; without it ${noFontPin.red} red pixels, lowest red row '
          '${noFontPin.bottomRow}px wide';
      final pinOk = iconFont && isPin(pin) && !isPin(noFontPin);
      if (_outDir.isEmpty) {
        print('[measure] station pin: $pinDetail — '
            '${pinOk ? 'a pin glyph, and the no-font control is not' : 'NOT established'} '
            '(checked only when frames are written)');
      } else {
        check(
            'GLYPH the station pin rendered as a pin, and the same render '
            'without its font did not',
            pinOk,
            pinDetail);
      }

      final prints = <_Footprint>[
        _footprintOf('real fix', real, control, at),
        _footprintOf('mock', mock, control, at),
        _footprintOf('degraded', degraded, control, at),
      ];
      for (final f in prints) {
        check('DREW the ${f.state} dot', f.pixels.isNotEmpty,
            '${f.pixels.length} footprint pixels');
        check(
            'ISOLATED the ${f.state} frame differs from the control only '
            'around her position',
            f.outside == 0,
            '${f.outside} differing pixels outside the window');
        if (f.pixels.isEmpty) continue;
        final off =
            math.max((f.centreX - at.dx).abs(), (f.centreY - at.dy).abs());
        check(
            'PLACED the ${f.state} dot sits on her position',
            off <= 2.0,
            'footprint ${f.boxW}x${f.boxH}px centred '
                '(${f.centreX.toStringAsFixed(1)}, '
                '${f.centreY.toStringAsFixed(1)}), '
                '${off.toStringAsFixed(2)}px from expected');
      }

      if (prints.every((f) => f.pixels.isNotEmpty)) {
        final lum = {
          for (final f in prints) f.state: f.stateLuminance(control),
        };
        for (final f in prints) {
          final centre = f.centreY.floor() * f.frame.width + f.centreX.floor();
          print('[measure] ${f.state}: footprint ${f.pixels.length}px, '
              'box ${f.boxW}x${f.boxH}, state luminance '
              '${lum[f.state]!.toStringAsFixed(4)}, centre pixel moved '
              '${f.frame.deltaAt(control, centre)} from the map');
        }
        for (var i = 0; i < prints.length; i++) {
          for (var j = i + 1; j < prints.length; j++) {
            final a = prints[i], b = prints[j];
            final overlap = _overlap(a.pixels, b.pixels);
            check('SHAPE ${a.state} vs ${b.state} do not share one footprint',
                overlap < 0.5,
                'footprint overlap (intersection over union) '
                    '${overlap.toStringAsFixed(3)}');
            final grey = _greySeparation(a.frame, b.frame, at);
            check('NO-COLOUR ${a.state} vs ${b.state} still differ '
                'desaturated', grey >= 50,
                '$grey pixels differ by >=64 grey levels');
          }
        }
        final absence = _contrast(lum['real fix']!, lum['degraded']!);
        check('LUMINANCE degraded (position not known) vs real fix',
            absence >= _floor,
            '${absence.toStringAsFixed(3)}:1, floor $_floor:1');
        final simulated = _contrast(lum['real fix']!, lum['mock']!);
        check('LUMINANCE mock (never measured) vs real fix', simulated >= _floor,
            '${simulated.toStringAsFixed(3)}:1, floor $_floor:1');
        print('[measure] mock vs degraded luminance '
            '${_contrast(lum['mock']!, lum['degraded']!).toStringAsFixed(3)}:1 '
            '(not asserted: shape carries that pair)');
      }

      // ---- composed frames: what her screen shows -------------------------
      final composedReal =
          await render('01_real_fix', her: _her, accuracy: 15);
      final composedMock =
          await render('02_mock', her: _her, accuracy: 35, mock: true);
      final composedDegraded = await render('03_degraded',
          her: _her, accuracy: 380, degraded: true);
      final mockAtStation = await render('04_mock_at_station_as_shipped',
          her: akitaStation, accuracy: 35, mock: true);
      for (final f in [composedReal, composedMock, composedDegraded]) {
        final n = _footprintOf(f.name, f, control, at).pixels.length;
        check('DREW composed ${f.name}', n > 0, '$n pixels');
      }
      final n = _footprintOf(mockAtStation.name, mockAtStation, control,
              _pixelOf(akitaStation))
          .pixels
          .length;
      check('DREW composed ${mockAtStation.name}', n > 0, '$n pixels');

      // ---- write ONLY after every check passed ------------------------------
      final total = results.length;
      if (failed > 0) {
        print('HER_DOT_GLANCE: $failed of $total CHECKS FAILED — '
            'wrote NOTHING.');
      } else if (_outDir.isEmpty) {
        print('HER_DOT_GLANCE: ALL $total CHECKS PASSED — no '
            'HER_DOT_GLANCE_OUT given, wrote nothing.');
      } else {
        final dir = Directory(_outDir);
        expect(dir.existsSync() && dir.listSync().isNotEmpty, isFalse,
            reason: 'HER_DOT_GLANCE_OUT $_outDir is not empty — refusing to '
                'mix this run with another.');

        final files = <String, Uint8List>{
          '00_control_no_position.png': control.png,
          '00_control_without_icon_font_NEGATIVE_CONTROL.png':
              withoutIconFont.png,
        };
        final composed = [
          composedReal,
          composedMock,
          composedDegraded,
          mockAtStation,
        ];
        await tester.runAsync(() async {
          for (final f in composed) {
            files['${f.name}.png'] = f.png;
            files['${f.name}_DESATURATED.png'] =
                await _encodePng(f.desaturatedRgba(), f.width, f.height);
          }
          final crops = [composedReal, composedMock, composedDegraded];
          final stripWidth = crops.length * _crop + (crops.length - 1) * _gap;
          files['05_three_states_crop_1x.png'] = await _encodePng(
              _strip(crops, at, grey: false), stripWidth, _crop);
          files['05_three_states_crop_1x_DESATURATED.png'] = await _encodePng(
              _strip(crops, at, grey: true), stripWidth, _crop);
        });
        for (final f in [real, mock, degraded]) {
          files['measure/${f.name}.png'] = f.png;
        }

        for (final entry in files.entries) {
          final file = File('${dir.path}/${entry.key}');
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(entry.value, flush: true);
        }
        final manifest = StringBuffer()
          ..writeln('HER-dot glance capture — written only after every check '
              'below passed.')
          ..writeln('UTC ${DateTime.now().toUtc().toIso8601String()}')
          ..writeln('devicePixelRatio 1.0 · map ${_mapWidth}x$_mapHeight · '
              'zoom $_zoom · bundled offline basemap, no network')
          ..writeln('her position $_her; composed accuracy radii: real fix '
              '15 m, mock 35 m, degraded 380 m; mock at the station 35 m')
          ..writeln('measure/ holds the dot-alone frames (no accuracy circle) '
              'every number below was taken from')
          ..writeln('The exit code of this run cannot be known from inside '
              'it; the caller records it.')
          ..writeln()
          ..writeln('CHECKS ($total, all PASS):');
        for (final r in results) {
          manifest.writeln('  $r');
        }
        manifest
          ..writeln()
          ..writeln('FILES:');
        final names = files.keys.toList()..sort();
        for (final name in names) {
          manifest.writeln('  $name  ${files[name]!.length} bytes');
        }
        File('${dir.path}/MANIFEST.txt')
            .writeAsStringSync(manifest.toString(), flush: true);
        print('HER_DOT_GLANCE: ALL $total CHECKS PASSED — wrote '
            '${files.length} PNGs + MANIFEST.txt to $_outDir');
      }

      expect(failed, 0,
          reason: '$failed of $total glance checks failed:\n'
              '${results.where((r) => r.startsWith('FAIL')).join('\n')}');
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
