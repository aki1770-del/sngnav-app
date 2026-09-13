/// What HER map SAYS about her position, wherever the camera is.
///
/// WHY, written before the act. Measured 2026-09-13 in the real app: 8.2 km
/// out along Route 13 the map held no mark of her in any mode, while the line
/// under it read 「現在地 · ±15 m」. The interface review of the same day found
/// the lost words pinned to her last position, so they left the screen with
/// her, and set the rule these tests pin: no position claim may be silent on
/// the map. Until the map can follow her, the answer is words, at the top of
/// the map, and at the edge an unclear case resolves toward the words.
///
/// Pinned on [AkitaMap] alone, at its default camera (station, z12), where no
/// follow can hide it:
/// * lost → 現在地不明 at the top of the map, wherever her last position is;
/// * a mark the map edge cuts, in part or whole → 現在地は地図の外 at the top;
/// * a mark wholly inside → no words; the translucent attribution bar is not
///   an edge (a dot rendered under it stayed readable);
/// * the words follow the app's locale.
///
/// And, in the real app, the line under the map in dead reckoning and lost:
/// at `blueGrey.shade400` it was the palest text on the surface (3.03:1, the
/// only place the age of her last position appears); rendered at `shade700`
/// it measured 6.55:1.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

/// A 1x1 transparent PNG, so the basemap never reaches for the network.
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

const _unknownKey = ValueKey('her-position-unknown-label');
const _offMapKey = ValueKey('her-position-off-map-label');

/// The app's map on a 393 px phone: 16 px page padding each side.
const _mapSize = Size(361, 320);

/// The point at map-local logical offset [local], for the default camera.
LatLng _atLocal(Offset local) {
  const crs = Epsg3857();
  final c = crs.latLngToOffset(akitaStation, 12);
  return crs.offsetToLatLng(c + (local - _mapSize.center(Offset.zero)), 12);
}

/// Her fix 32 km east of the station: far outside a z12 phone map.
const _far = LatLng(39.7167, 140.4700);

Future<void> _pumpMap(
  WidgetTester tester, {
  LatLng? her,
  bool mock = false,
  bool degraded = false,
  bool lost = false,
  double? accuracy,
  Locale locale = const Locale('ja'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: _mapSize.width,
            child: AkitaMap(
              height: _mapSize.height,
              baseTileProvider: _BlankTileProvider(),
              herPosition: her,
              herAccuracyMeters: accuracy,
              isHerPositionMock: mock,
              positionDegraded: degraded,
              positionLost: lost,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The words are built, wholly inside the map, at its top, and say [text].
void _expectWordsAtTop(WidgetTester tester, Key key, String text) {
  final words = find.byKey(key);
  expect(words, findsOneWidget,
      reason: 'the map must say it in words; nothing was built under $key');
  final map = tester.getRect(find.byType(AkitaMap));
  final box = tester.getRect(words);
  expect(
    map.contains(box.topLeft) && map.contains(box.bottomRight),
    isTrue,
    reason: 'the words must sit wholly inside the map she sees '
        '(map $map, words $box)',
  );
  expect(box.top - map.top, lessThanOrEqualTo(16),
      reason: 'the words stand at the top of the map, not beside her mark');
  expect(find.descendant(of: words, matching: find.text(text)),
      findsOneWidget);
}

void _expectNoWords() {
  expect(find.byKey(_unknownKey), findsNothing);
  expect(find.byKey(_offMapKey), findsNothing);
}

// ---- the real app, for the line under the map ----------------------------

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

double _luminance(Color c) {
  double lin(double v) => v <= 0.03928
      ? v / 12.92
      : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('lost: the words stand at the top of the map, wherever she was', () {
    testWidgets('her last position 32 km away: 現在地不明 is still on the map',
        (tester) async {
      await _pumpMap(tester,
          her: _far, degraded: true, lost: true, accuracy: 10815);
      _expectWordsAtTop(tester, _unknownKey, '現在地不明');
      expect(find.byKey(_offMapKey), findsNothing,
          reason: 'lost says lost; it is not also "off this map"');
    });

    testWidgets('her last position on screen: the same words, the same place',
        (tester) async {
      await _pumpMap(tester,
          her: _atLocal(const Offset(180, 200)),
          degraded: true,
          lost: true,
          accuracy: 375);
      _expectWordsAtTop(tester, _unknownKey, '現在地不明');
    });

    testWidgets('no trusted position ever: the words alone', (tester) async {
      await _pumpMap(tester,
          her: null, degraded: true, lost: true, accuracy: double.infinity);
      _expectWordsAtTop(tester, _unknownKey, '現在地不明');
    });
  });

  group('a mark the map edge cuts: 現在地は地図の外 at the top', () {
    testWidgets('a real fix 32 km away: the words, not a silent map',
        (tester) async {
      await _pumpMap(tester, her: _far, accuracy: 15);
      _expectWordsAtTop(tester, _offMapKey, '現在地は地図の外');
    });

    testWidgets('a real fix whose dot the right edge cuts (1 px inside)',
        (tester) async {
      await _pumpMap(tester,
          her: _atLocal(Offset(_mapSize.width - 1, _mapSize.height / 2)),
          accuracy: 15);
      _expectWordsAtTop(tester, _offMapKey, '現在地は地図の外');
    });

    testWidgets('a real fix whose dot the bottom edge cuts by 1 px',
        (tester) async {
      await _pumpMap(tester,
          her: _atLocal(Offset(_mapSize.width / 2, _mapSize.height - 10)),
          accuracy: 15);
      _expectWordsAtTop(tester, _offMapKey, '現在地は地図の外');
    });

    testWidgets('a dead-reckoning ring the top edge cuts', (tester) async {
      await _pumpMap(tester,
          her: _atLocal(Offset(_mapSize.width / 2, 10)),
          degraded: true,
          accuracy: 135);
      _expectWordsAtTop(tester, _offMapKey, '現在地は地図の外');
    });
  });

  group('a mark wholly inside: no words', () {
    testWidgets('a real fix at the centre', (tester) async {
      await _pumpMap(tester,
          her: _atLocal(_mapSize.center(Offset.zero)), accuracy: 15);
      expect(find.byKey(const ValueKey('her-dot-real-fix')), findsOneWidget,
          reason: 'control: the dot is drawn');
      _expectNoWords();
    });

    testWidgets(
        'a real fix 12 px inside the bottom edge, under the attribution bar: '
        'the whole dot is inside, so no words', (tester) async {
      await _pumpMap(tester,
          her: _atLocal(Offset(_mapSize.width / 2, _mapSize.height - 12)),
          accuracy: 15);
      _expectNoWords();
    });

    testWidgets('a dead-reckoning ring 30 px inside the top edge',
        (tester) async {
      await _pumpMap(tester,
          her: _atLocal(Offset(_mapSize.width / 2, 30)),
          degraded: true,
          accuracy: 135);
      _expectNoWords();
    });

    testWidgets('no position at all: nothing to say', (tester) async {
      await _pumpMap(tester, her: null);
      _expectNoWords();
    });
  });

  group('the words follow the app locale', () {
    testWidgets('English, lost: "Position unknown"', (tester) async {
      await _pumpMap(tester,
          her: _far,
          degraded: true,
          lost: true,
          accuracy: 10815,
          locale: const Locale('en'));
      _expectWordsAtTop(tester, _unknownKey, 'Position unknown');
      expect(find.text('現在地不明'), findsNothing);
    });

    testWidgets('English, off the map: "Position off this map"',
        (tester) async {
      await _pumpMap(tester,
          her: _far, accuracy: 15, locale: const Locale('en'));
      _expectWordsAtTop(tester, _offMapKey, 'Position off this map');
    });
  });

  group('the line under the map, in the real app', () {
    // The ground under that line as rendered on 2026-09-13.
    const ground = Color(0xFFF0F4F8);

    testWidgets(
        'dead reckoning and lost: the line is blueGrey.shade700, not the '
        'palest text on the surface', (tester) async {
      var now = DateTime.utc(2026, 1, 15, 6, 30);
      final start = now;
      final positions = StreamController<PositionFix>.broadcast();
      await tester.pumpWidget(SngnavApp(
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
      positions.add(PositionAvailable(
        latitude: 39.7195,
        longitude: 140.1180,
        accuracyMeters: 15,
        timestamp: start,
      ));
      await tester.pump();

      Text line() =>
          tester.widget<Text>(find.byKey(const Key('her-status-line')));

      now = start.add(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(line().data, startsWith('GPS 途絶（推測航法）'),
          reason: 'control: dead reckoning reached');
      expect(line().style!.color, Colors.blueGrey.shade700);

      now = start.add(const Duration(seconds: 180));
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(line().data, startsWith('現在地 不明'),
          reason: 'control: lost reached');
      expect(line().style!.color, Colors.blueGrey.shade700);

      expect(_contrast(Colors.blueGrey.shade700, ground),
          greaterThanOrEqualTo(4.5),
          reason: 'shade700 rendered at 6.55:1 on this ground');
      await positions.close();
    });
  });
}
