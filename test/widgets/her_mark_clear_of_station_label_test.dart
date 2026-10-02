/// Her position mark and the 秋田 station marker never sit on each other.
///
/// Why this test exists. Seen 2026-10-02 in release builds on Android 14 and
/// Android 11 emulators, with the emulator's fix 390 m from the JMA station
/// (39.718498, 140.102498) and the camera following her at zoom 12: her blue
/// dot was drawn over the station's 秋田 label and hid half of 田. The same
/// shape was already in two goldens: on render_out/15 the hollow ring that
/// says "we are not sure where you are" cut the bottom of 秋田 and held the
/// station's red pin inside its hole, so the ring read as a target on a named
/// place, which is a confident reading of a degraded state.
///
/// Measured at the time, at text scale 1.0: the station's label box sits
/// 8-30 px above the station point and its pin's tip 17 px below it, at
/// EVERY zoom (a marker is drawn in pixels). The zone where her 22 px dot
/// covers the label is about 58 x 44 px, which is 1.7 x 1.3 km at zoom 12
/// and 27 x 21 km at zoom 8. Following her keeps zoom 8-12 and centres her,
/// so anywhere in central Akita the two are drawn together.
///
/// The rules held here, in order of what she must see first:
///
/// 1. Her mark is drawn above every station mark. Nothing covers it.
/// 2. Nothing of the station pin shows under her mark or inside her ring. A
///    pin inside the hollow ring would answer "where in here?" with a point
///    the position does not have. Where she covers the pin, her mark marks
///    that place. The pin is hidden there and nowhere else.
/// 3. The 秋田 label is always drawn, never within 4 px of her mark, inside
///    the map, and near the station's place, so she reads both.
/// 4. With her mark away from the station, the marker is laid out exactly as
///    with no position at all.
///
/// What this cannot see. A host raster at device pixel ratio 1.0 with a
/// Japanese face found on this host, not Noto on her phone; box geometry is
/// read from layout, and only the pin's red and the dot's blue are read as
/// pixels. The ring and the mock square are told from the label by geometry,
/// not by pixels, because their dark ink is the label text's darkness. The
/// tiles here are blank, so nothing here sees what the label covers on her
/// map: which place the label takes when it moves was chosen from renders on
/// the bundled Akita basemap, where the pin's right side holds the map's own
/// 秋田市 and its left the Route 13 shield. There is no timed glance in any
/// of it.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';

import '../render_see/render_see_env.dart';

/// The emulator's fix in the release-build frames.
const _liveFix = LatLng(39.718498, 140.102498);

const double _mapW = 360;
const double _mapH = 320;

/// The label stays this far from her mark's drawn box.
const double _labelGap = 4;

/// The pin's red stays this far from her mark's drawn box.
const double _pinGap = 3;

/// The label's nearest edge stays within this distance of the station point,
/// so a label pushed away to pass rule 3 still fails here.
const double _labelReach = 64;

final _blankTile = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00, //
  0x00, 0x05, 0x00, 0x01, 0x7A, 0x5E, 0xAB, 0x3F, 0x00, 0x00, 0x00, 0x00, //
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

class _BlankTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_blankTile);
}

enum _State { realFix, mock, degraded }

const _markKey = {
  _State.realFix: ValueKey('her-dot-real-fix'),
  _State.mock: ValueKey('her-dot-mock'),
  _State.degraded: ValueKey('her-dot-degraded'),
};

const _crs = Epsg3857();

/// The point [offset] logical px from the station at [zoom], north up.
LatLng _offsetFromStation(Offset offset, double zoom) => _crs.offsetToLatLng(
    _crs.latLngToOffset(akitaStation, zoom) + offset, zoom);

double _distanceToRect(Offset p, Rect r) {
  final dx = p.dx < r.left ? r.left - p.dx : (p.dx > r.right ? p.dx - r.right : 0.0);
  final dy = p.dy < r.top ? r.top - p.dy : (p.dy > r.bottom ? p.dy - r.bottom : 0.0);
  return Offset(dx, dy).distance;
}

bool _overlaps(Rect a, Rect b) =>
    a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;

void main() {
  var japaneseFace = false;
  var iconFont = false;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    japaneseFace = await loadCjkFamily('Roboto', japaneseFontSearchOrder(),
        searched: 'japaneseFontSearchOrder()');
    iconFont = await loadMaterialIconsFont();
    final tmp = await Directory.systemTemp.createTemp('her_mark_station');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  final boundary = GlobalKey();

  Widget app({
    required LatLng? her,
    required _State state,
    double textScale = 1.0,
    Locale locale = const Locale('ja'),
    MapController? controller,
  }) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Roboto'),
        locale: locale,
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ja'), Locale('en')],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              key: boundary,
              child: SizedBox(
                width: _mapW,
                child: AkitaMap(
                  height: _mapH,
                  baseTileProvider: _BlankTileProvider(),
                  mapController: controller,
                  herPosition: her,
                  herAccuracyMeters: state == _State.degraded ? 380 : 20,
                  isHerPositionMock: state == _State.mock,
                  positionDegraded: state == _State.degraded,
                ),
              ),
            ),
          ),
        ),
      );

  Finder labelBox(String word) => find.ancestor(
        of: find.text(word),
        matching: find.byWidgetPredicate(
            (w) => w is Container && w.decoration is BoxDecoration),
      );

  /// Printed, never counted as a pass: the station is off this map, so the
  /// map rightly draws no station marker and rule 3 has nothing to hold.
  const offMap = 'N/A: the station is off this map';

  /// Rule 3, read from layout. Null when it holds, [offMap] when it cannot
  /// apply, else what broke.
  String? labelRule(WidgetTester tester, _State state, String word,
      Offset station) {
    final map = tester.getRect(find.byType(FlutterMap));
    final labels = labelBox(word).evaluate().length;
    if (labels == 0 && !map.contains(station)) return offMap;
    if (labels != 1) return 'the $word label is drawn $labels times, not once';
    final label = tester.getRect(labelBox(word).first);
    final mark = tester.getRect(find.byKey(_markKey[state]!));
    if (_overlaps(label, mark.inflate(_labelGap))) {
      final o = label.intersect(mark);
      final covered = (o.width > 0 && o.height > 0) ? o.width * o.height : 0.0;
      return 'label within ${_labelGap}px of her mark '
          '(${covered.toStringAsFixed(0)} px² under it)';
    }
    if (!(map.contains(label.topLeft) && map.contains(label.bottomRight))) {
      return 'label cut by the map edge';
    }
    final reach = _distanceToRect(station, label);
    if (reach > _labelReach) {
      return 'label ${reach.toStringAsFixed(0)} px from the station';
    }
    return null;
  }

  testWidgets(
      'rule 3 by layout: the 秋田 label is clear of her mark, swept around the '
      'station in every state and at text scale 1.0 and 2.0', (tester) async {
    expect(japaneseFace, isTrue,
        reason: 'the label box is measured with a real Japanese face; with the '
            'test font a kanji is a uniform box and the geometry is not hers');
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(_mapW + 40, _mapH + 40);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final failures = <String>[];
    var cases = 0;
    for (final (locale, word) in [
      (const Locale('ja'), '秋田'),
      (const Locale('en'), 'Akita'),
    ]) {
      for (final scale in [1.0, 2.0]) {
        for (final state in _State.values) {
          var bad = 0;
          for (var dy = -48.0; dy <= 48; dy += 8) {
            for (var dx = -48.0; dx <= 48; dx += 8) {
              await tester.pumpWidget(app(
                her: _offsetFromStation(Offset(dx, dy), 12),
                state: state,
                textScale: scale,
                locale: locale,
              ));
              final map = tester.getRect(find.byType(FlutterMap));
              final station = map.center; // initialCenter, zoom 12
              cases++;
              final broke = labelRule(tester, state, word, station);
              if (broke != null) {
                bad++;
                if (failures.length < 12) {
                  failures.add('${locale.languageCode} x$scale ${state.name} '
                      'her at (${dx.toInt()},${dy.toInt()}) px: $broke');
                }
              }
            }
          }
          // ignore: avoid_print
          print('[sweep] ${locale.languageCode} text x$scale ${state.name}: '
              '$bad of 169 positions break rule 3');
        }
      }
    }
    expect(failures, isEmpty,
        reason: 'of $cases positions, these (first 12) break rule 3:\n'
            '${failures.join('\n')}');
  });

  testWidgets(
      'rule 4: with her mark away from the station, the station marker is laid '
      'out exactly as with no position at all', (tester) async {
    expect(japaneseFace, isTrue, reason: 'see the sweep');
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(_mapW + 40, _mapH + 40);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final failures = <String>[];
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
          app(her: null, state: _State.realFix, textScale: scale));
      final label0 = tester.getRect(labelBox('秋田').first);
      final pin0 = tester.getRect(find.byIcon(Icons.place));
      for (final state in _State.values) {
        // 100 px is beyond every place the marker can draw at either scale.
        for (final offset in const [
          Offset(0, -100), Offset(100, 0), Offset(0, 100), Offset(-100, 0),
          Offset(120, 120), Offset(-150, -90),
        ]) {
          await tester.pumpWidget(app(
              her: _offsetFromStation(offset, 12),
              state: state,
              textScale: scale));
          final label = tester.getRect(labelBox('秋田').first);
          final pins = find.byIcon(Icons.place).evaluate().length;
          final tag = 'x$scale ${state.name} her at $offset';
          if (label != label0) {
            failures.add('$tag: label at $label, not $label0');
          }
          if (pins != 1) {
            failures.add('$tag: pin drawn $pins times');
          } else if (tester.getRect(find.byIcon(Icons.place)) != pin0) {
            failures.add('$tag: pin moved');
          }
        }
      }
    }
    // ignore: avoid_print
    print('[far] ${failures.length} breaks');
    expect(failures, isEmpty, reason: failures.take(12).join('\n'));
  });

  testWidgets(
      'rule 3 at the emulator\'s fix, camera on her as follow puts it, at every '
      'zoom from the hand\'s 5 to 18', (tester) async {
    expect(japaneseFace, isTrue, reason: 'see the sweep');
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(_mapW + 40, _mapH + 40);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final failures = <String>[];
    var measured = 0;
    for (final state in _State.values) {
      for (final zoom in [5.0, 8.0, 10.0, 12.0, 13.0, 18.0]) {
        final controller = MapController();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
            app(her: _liveFix, state: state, controller: controller));
        await tester.pump();
        controller.move(_liveFix, zoom);
        await tester.pump();
        final map = tester.getRect(find.byType(FlutterMap));
        final station =
            map.topLeft + controller.camera.latLngToScreenOffset(akitaStation);
        final broke = labelRule(tester, state, '秋田', station);
        // ignore: avoid_print
        print('[live] ${state.name} zoom $zoom: ${broke ?? 'clear'}');
        if (broke == offMap) continue;
        measured++;
        if (broke != null) failures.add('${state.name} zoom $zoom: $broke');
      }
    }
    // The follow band (8-12) and both hand limits' neighbours must be measured,
    // not all N/A: 5, 8, 10, 12 and 13 hold the station on this map.
    expect(measured, greaterThanOrEqualTo(5 * _State.values.length),
        reason: 'only $measured cases had the station on the map');
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  testWidgets(
      'rules 1 and 2 by pixels: her mark is on top, no pin red under it or in '
      'her ring, no dot blue in the label', (tester) async {
    expect(japaneseFace, isTrue, reason: 'see the sweep');
    expect(iconFont, isTrue,
        reason: 'the pin is a MaterialIcons glyph; without the font it draws '
            'a hollow box and its red is not the pin');
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(_mapW + 40, _mapH + 40);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Her at the station (goldens 14 and 15), at the emulator's fix at zoom 12
    // and 10, and at eight compass points close enough to touch the marker.
    final where = <String, Offset>{
      'on the station': Offset.zero,
      'emulator fix z12': _crs.latLngToOffset(_liveFix, 12) -
          _crs.latLngToOffset(akitaStation, 12),
      'emulator fix z10': _crs.latLngToOffset(_liveFix, 10) -
          _crs.latLngToOffset(akitaStation, 10),
      'N 22': const Offset(0, -22),
      'S 24': const Offset(0, 24),
      'W 22': const Offset(-22, -4),
      'E 22': const Offset(22, -14),
      'NW 30': const Offset(-30, -30),
      'SE 30': const Offset(30, 30),
    };

    bool isPinRed(int r, int g, int b) => r > 150 && g < 90 && b < 90;

    final failures = <String>[];
    for (final scale in [1.0, 2.0]) {
      // The pin's red with no position on the map, found in the pixels: the
      // only place it may be hidden is where her mark comes near this.
      Rect? pinRed;
      for (final state in [null, ..._State.values]) {
        for (final MapEntry(key: name, value: offset) in (state == null
                ? const {'no position': Offset.zero}
                : where)
            .entries) {
          late Uint8List rgba;
          late int w;
          late Offset origin;
          await tester.runAsync(() async {
            await tester.pumpWidget(app(
                her: state == null ? null : _offsetFromStation(offset, 12),
                state: state ?? _State.realFix,
                textScale: scale));
            await tester.pump();
            final ro = boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final img = await ro.toImage(pixelRatio: 1.0);
            rgba = (await img.toByteData(
                    format: ui.ImageByteFormat.rawStraightRgba))!
                .buffer
                .asUint8List();
            w = img.width;
            origin = ro.localToGlobal(Offset.zero);
            img.dispose();
          });
          final h = rgba.length ~/ (4 * w);
          if (state == null) {
            var l = w, t = h, r = -1, b = -1;
            for (var y = 0; y < h; y++) {
              for (var x = 0; x < w; x++) {
                final p = (y * w + x) * 4;
                if (isPinRed(rgba[p], rgba[p + 1], rgba[p + 2])) {
                  if (x < l) l = x;
                  if (x > r) r = x;
                  if (y < t) t = y;
                  if (y > b) b = y;
                }
              }
            }
            expect(r, greaterThanOrEqualTo(0),
                reason: 'x$scale: no pin red with no position, so the pin '
                    'checks below would measure nothing');
            pinRed = Rect.fromLTRB(l.toDouble(), t.toDouble(),
                    (r + 1).toDouble(), (b + 1).toDouble())
                .shift(origin);
            // ignore: avoid_print
            print('[pixels] x$scale pin red, no position: $pinRed');
            continue;
          }
          (int, int, int) px(int x, int y) {
            final p = (y * w + x) * 4;
            return (rgba[p], rgba[p + 1], rgba[p + 2]);
          }

          int count(Rect global, bool Function(int r, int g, int b) hit) {
            final r = global.shift(-origin);
            var n = 0;
            for (var y = r.top.floor().clamp(0, h); y < r.bottom.ceil().clamp(0, h); y++) {
              for (var x = r.left.floor().clamp(0, w); x < r.right.ceil().clamp(0, w); x++) {
                final (pr, pg, pb) = px(x, y);
                if (hit(pr, pg, pb)) n++;
              }
            }
            return n;
          }

          final mark = tester.getRect(find.byKey(_markKey[state]!));
          final label = tester.getRect(labelBox('秋田').first);
          final tag = 'x$scale ${state.name} $name';

          // Rule 2: the station pin's red (red.shade700) under or in her mark.
          final red = count(mark.inflate(_pinGap), isPinRed);
          if (red > 0) failures.add('$tag: $red px of pin red at her mark');

          // Rule 2's cost, bounded: the pin is hidden only where it must be.
          // 2 px of slack beyond the gap, for the red's anti-aliased edge.
          final pinDrawn = find.byIcon(Icons.place).evaluate().isNotEmpty;
          if (!pinDrawn && !pinRed!.overlaps(mark.inflate(_pinGap + 2))) {
            failures.add('$tag: pin hidden, though her mark is clear of its '
                'red at $pinRed');
          }

          // Rule 3 in pixels, for the dot: its blue (blue.shade600) in the label.
          if (state == _State.realFix) {
            final blue = count(label.deflate(1),
                (r, g, b) => b > 150 && b - r > 90);
            if (blue > 0) failures.add('$tag: $blue px of her dot in the label');
          }

          // Rule 1: her mark's own paint is what is on top of it.
          final c = mark.center - origin;
          bool near((int, int, int) got, (int, int, int) want) =>
              (got.$1 - want.$1).abs() <= 8 &&
              (got.$2 - want.$2).abs() <= 8 &&
              (got.$3 - want.$3).abs() <= 8;
          switch (state) {
            case _State.realFix:
              final got = px(c.dx.round(), c.dy.round());
              if (!near(got, (0x1E, 0x88, 0xE5))) {
                failures.add('$tag: dot centre is $got, not her blue');
              }
            case _State.mock:
              final got = px(c.dx.round(), c.dy.round());
              if (!near(got, (0xFF, 0xF8, 0xE1))) {
                failures.add('$tag: mock centre is $got, not her fill');
              }
            case _State.degraded:
              for (final d in const [
                Offset(0, -15), Offset(15, 0), Offset(0, 15), Offset(-15, 0)
              ]) {
                final (r, g, b) = px((c.dx + d.dx).round(), (c.dy + d.dy).round());
                if (0.299 * r + 0.587 * g + 0.114 * b > 80) {
                  failures.add('$tag: ring at $d is ($r,$g,$b), not her ring');
                }
              }
          }
        }
      }
    }
    // ignore: avoid_print
    print('[pixels] ${failures.length} breaks over '
        '${2 * _State.values.length * where.length} frames');
    for (final f in failures) {
      // ignore: avoid_print
      print('[pixels] $f');
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
