/// The driver's position dot's three states, read from the laid-out map.
///
/// Rendered desaturated, the dot's real-fix, mock and degraded states used to
/// be one grey disc: a single 22px circle told apart by fill colour alone.
/// They now differ in fill, shape and size. These tests pin what a glance
/// without colour depends on, and what a refactor could quietly undo:
///
/// * each state keeps its own shape and fill: solid and round for a real fix,
///   square for mock, a hollow ring for degraded;
/// * each state keeps its own SIZE inside the composed [AkitaMap].
///   flutter_map lays a marker child out under tight constraints, so a marker
///   box smaller than the largest state squeezes every state to one size on
///   the map, while the dot widget still looks right on its own.
///
/// The rendered pixels are measured in
/// `test/render_see/her_dot_glance_capture_test.dart`.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';

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

const _realFix = ValueKey('her-dot-real-fix');
const _mock = ValueKey('her-dot-mock');
const _degraded = ValueKey('her-dot-degraded');

const _her = LatLng(39.7273, 140.1395);

Future<void> _pumpMap(
  WidgetTester tester, {
  LatLng? her = _her,
  bool mock = false,
  bool degraded = false,
  bool lost = false,
  double? accuracy,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      // The map's words go through AppL10n, as in the app. Without the
      // delegate AppL10n.of falls back to English and 現在地不明 is not built.
      locale: const Locale('ja'),
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 600,
            child: AkitaMap(
              height: 340,
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

const _unknownLabel = ValueKey('her-position-unknown-label');

final _circleLayer = find.byWidgetPredicate((w) => w is CircleLayer);

BoxDecoration _decoration(WidgetTester tester, Key key) =>
    tester.widget<Container>(find.byKey(key)).decoration! as BoxDecoration;

/// The size the state asks for is the size the composed map gave it.
void _expectNotSqueezed(WidgetTester tester, Key key) {
  final asked = tester.widget<Container>(find.byKey(key)).constraints!;
  expect(
    tester.getSize(find.byKey(key)),
    Size(asked.maxWidth, asked.maxHeight),
    reason: 'the marker box squeezed the $key state: on the map it no longer '
        'has the size that tells it apart',
  );
}

void main() {
  testWidgets('a real fix is SOLID and ROUND — the only solid state',
      (tester) async {
    await _pumpMap(tester);

    expect(find.byKey(_realFix), findsOneWidget);
    expect(find.byKey(_mock), findsNothing);
    expect(find.byKey(_degraded), findsNothing);
    final dot = _decoration(tester, _realFix);
    expect(dot.shape, BoxShape.circle);
    expect(dot.color, isNotNull);
    _expectNotSqueezed(tester, _realFix);
  });

  testWidgets('a mock position is SQUARE — never round, so never a fix',
      (tester) async {
    await _pumpMap(tester, mock: true);

    expect(find.byKey(_mock), findsOneWidget);
    expect(find.byKey(_realFix), findsNothing);
    expect(find.byKey(_degraded), findsNothing);
    final square = _decoration(tester, _mock);
    expect(square.shape, BoxShape.rectangle);
    expect(square.borderRadius, isNull);
    _expectNotSqueezed(tester, _mock);
  });

  testWidgets(
      'a degraded position is a HOLLOW ring, larger than a real fix, and the '
      'map does not squeeze it back to one size', (tester) async {
    await _pumpMap(tester);
    final fix = tester.getSize(find.byKey(_realFix));

    await _pumpMap(tester, degraded: true);

    expect(find.byKey(_degraded), findsOneWidget);
    expect(find.byKey(_realFix), findsNothing);
    expect(find.byKey(_mock), findsNothing);
    final ring = _decoration(tester, _degraded);
    expect(ring.shape, BoxShape.circle);
    expect(ring.color, isNull, reason: 'a filled ring reads as a point');
    expect(ring.boxShadow, isNull, reason: 'a shadow paints the hole in');
    _expectNotSqueezed(tester, _degraded);
    expect(tester.getSize(find.byKey(_degraded)).width,
        greaterThan(fix.width));
  });

  testWidgets('degraded wins over mock: both flags resolve toward "not known"',
      (tester) async {
    await _pumpMap(tester, mock: true, degraded: true);

    expect(find.byKey(_degraded), findsOneWidget);
    expect(find.byKey(_mock), findsNothing);
    expect(find.byKey(_realFix), findsNothing);
  });

  testWidgets('no position, no dot', (tester) async {
    await _pumpMap(tester, her: null);

    expect(find.byKey(_realFix), findsNothing);
    expect(find.byKey(_mock), findsNothing);
    expect(find.byKey(_degraded), findsNothing);
    expect(find.byKey(_unknownLabel), findsNothing);
  });

  // ---- lost (2026-09-13): the map SAYS it does not know -----------------
  //
  // A render review drew bd6ebc4 in every mode: lost was the dead-reckoning ring pixel
  // for pixel, and its circle was the only mark that grew. These pin the
  // structure the fix depends on; the review's harness pins the pixels.

  testWidgets(
      'lost with a last trusted position: the ring, the words, and NO accuracy '
      'circle however large the radius', (tester) async {
    await _pumpMap(tester, degraded: true, lost: true, accuracy: 10815);

    expect(find.byKey(_degraded), findsOneWidget);
    expect(find.byKey(_unknownLabel), findsOneWidget);
    expect(find.text('現在地不明'), findsOneWidget);
    expect(_circleLayer, findsNothing,
        reason: 'past its horizon the controller vouches for no radius');
    _expectNotSqueezed(tester, _degraded);
  });

  testWidgets('lost with no trusted position: the words alone, no ring',
      (tester) async {
    await _pumpMap(tester,
        her: null, degraded: true, lost: true, accuracy: double.infinity);

    expect(find.byKey(_unknownLabel), findsOneWidget);
    expect(find.byKey(_degraded), findsNothing);
    expect(find.byKey(_realFix), findsNothing);
    expect(_circleLayer, findsNothing);
  });

  testWidgets('dead reckoning is not lost: ring and circle, no words',
      (tester) async {
    await _pumpMap(tester, degraded: true, accuracy: 135);

    expect(find.byKey(_degraded), findsOneWidget);
    expect(_circleLayer, findsOneWidget);
    expect(find.byKey(_unknownLabel), findsNothing);
  });

  testWidgets(
      'a non-finite radius is never handed to the painter: no circle, and no '
      'swallowed paint exception', (tester) async {
    await _pumpMap(tester, degraded: true, accuracy: double.infinity);

    expect(_circleLayer, findsNothing);
    expect(find.byKey(_degraded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'in lost, positionDegraded true or false builds the same state (the app '
      'passes true; the review harness passed false)', (tester) async {
    for (final degraded in [true, false]) {
      await _pumpMap(tester, degraded: degraded, lost: true, accuracy: 375);

      expect(find.byKey(_degraded), findsOneWidget, reason: '$degraded');
      expect(find.byKey(_unknownLabel), findsOneWidget, reason: '$degraded');
      expect(_circleLayer, findsNothing, reason: '$degraded');
      expect(find.byKey(_realFix), findsNothing, reason: '$degraded');
    }
  });
}
