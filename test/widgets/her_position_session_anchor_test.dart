/// The map draws a ring only from a position seen in THIS sharing session.
///
/// WHY, written before the act. The position controller is not reset when she
/// stops sharing. Rendered 2026-09-13 in the real app: she re-shares with
/// location services off, the first event is an unavailability, the
/// controller degrades from the PREVIOUS drive's last trusted fix, and the map
/// drew the ring there, 20 hours old, pixel-identical to a 3-minute loss. The
/// dev mock did the same around the station pin, a position never measured.
/// The map's own rule already said "a feed she turned off makes no claim about
/// where she is now"; it guarded the clock and not the anchor.
///
/// The rule pinned here: a session flag, false when sharing starts, true only
/// when an event in this session becomes the controller's trusted anchor. Not
/// on any fix: a fix the controller refuses as no newer than its anchor leaves
/// the previous session's anchor in force, so it cannot count. Without an
/// anchor from this session the map draws no ring and says 現在地不明, and the
/// line under it claims no last position.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/developer_page.dart';
import '../support/fake_alert_actuators.dart';

const _ringKey = ValueKey('her-dot-degraded');
const _realDotKey = ValueKey('her-dot-real-fix');
const _unknownKey = ValueKey('her-position-unknown-label');
const _statusKey = Key('her-status-line');

/// The previous drive's last trusted fix, and a different place for this one.
const _a = LatLng(39.7195, 140.1180);
const _b = LatLng(39.7300, 140.1000);

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

PositionAvailable _fixAt(LatLng p, DateTime t) => PositionAvailable(
  latitude: p.latitude,
  longitude: p.longitude,
  accuracyMeters: 15,
  timestamp: t,
);

void main() {
  late StreamController<PositionFix> positions;

  Future<void> pumpApp(WidgetTester tester) async {
    positions = StreamController<PositionFix>.broadcast();
    await tester.pumpWidget(
      SngnavApp(
        actuators: FakeAlertActuators(),
        locale: const Locale('ja'),
        clock: DateTime.now,
        jmaFetch: () async => JmaSuccess(_clearObs()),
        positionSource: () => positions.stream,
        developerPageEntry: true,
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pump();
    await tester.tap(find.text(text));
    await tester.pump();
  }

  Future<void> send(WidgetTester tester, PositionFix fix) async {
    positions.add(fix);
    await tester.pump();
    await tester.pump();
  }

  AkitaMap map(WidgetTester tester) =>
      tester.widget<AkitaMap>(find.byType(AkitaMap));

  String? statusLine(WidgetTester tester) {
    final f = find.byKey(_statusKey);
    return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
  }

  void expectWordsOnMap(WidgetTester tester) {
    final words = find.byKey(_unknownKey);
    expect(words, findsOneWidget, reason: 'the map must say 現在地不明');
    expect(
      tester.getRect(find.byType(AkitaMap)).overlaps(tester.getRect(words)),
      isTrue,
    );
  }

  testWidgets(
    're-share with location services off, after a previous drive: no ring at '
    'the previous drive\'s place, and the map says 現在地不明',
    (tester) async {
      await pumpApp(tester);
      await tapText(tester, '現在地を共有');
      // A fix stamped 20 hours ago: the previous drive.
      await send(
        tester,
        _fixAt(_a, DateTime.now().subtract(const Duration(hours: 20))),
      );
      expect(
        map(tester).herPosition,
        _a,
        reason: 'control: the drive happened',
      );
      await tapText(tester, '停止');

      await tapText(tester, '現在地を共有');
      await send(
        tester,
        const PositionUnavailable('Location services disabled'),
      );

      expect(
        find.byKey(_ringKey),
        findsNothing,
        reason: 'no ring from an anchor not seen in this session',
      );
      expect(map(tester).herPosition, isNull);
      expectWordsOnMap(tester);
      expect(statusLine(tester), contains('位置情報サービスが無効です'));
      await positions.close();
    },
  );

  testWidgets(
    're-share moments after stopping, services off: the controller is only '
    'dead-reckoning from the old anchor, and still no ring there',
    (tester) async {
      await pumpApp(tester);
      await tapText(tester, '現在地を共有');
      await send(tester, _fixAt(_a, DateTime.now()));
      await tapText(tester, '停止');

      await tapText(tester, '現在地を共有');
      await send(
        tester,
        const PositionUnavailable('Location services disabled'),
      );

      expect(
        find.byKey(_ringKey),
        findsNothing,
        reason:
            'dead reckoning from the previous session is not a claim '
            'about where she is now',
      );
      expect(map(tester).herPosition, isNull);
      expectWordsOnMap(tester);
      await positions.close();
    },
  );

  testWidgets(
    'dev mock, Clear, then share with services off: no ring around the '
    'station pin',
    (tester) async {
      await pumpApp(tester);
      // The mock is on the development page (2026-09-15).
      await tapOnDeveloperPage(tester, const Key('use-mock-button'));
      expect(map(tester).herPosition, akitaStation, reason: 'control: mock');
      await tapText(tester, 'クリア');

      await tapText(tester, '現在地を共有');
      await send(
        tester,
        const PositionUnavailable('Location services disabled'),
      );

      expect(
        find.byKey(_ringKey),
        findsNothing,
        reason: 'the mock was never a measured position',
      );
      expect(map(tester).herPosition, isNull);
      expectWordsOnMap(tester);
      await positions.close();
    },
  );

  testWidgets(
    're-share, and the first fix is no newer than the previous anchor: the '
    'controller refuses it, so no ring at the previous place and no radius '
    'on the line',
    (tester) async {
      final t = DateTime.now();
      await pumpApp(tester);
      await tapText(tester, '現在地を共有');
      await send(tester, _fixAt(_a, t));
      await tapText(tester, '停止');

      await tapText(tester, '現在地を共有');
      // Same timestamp, a different place: a re-delivered or clock-skewed fix.
      await send(tester, _fixAt(_b, t));

      expect(find.byKey(_ringKey), findsNothing);
      expect(
        map(tester).herPosition,
        isNull,
        reason: 'the controller still holds the previous drive as its anchor',
      );
      expectWordsOnMap(tester);
      expect(
        statusLine(tester),
        '現在地 不明 · 最後の位置 なし',
        reason: 'no last position from this session',
      );
      await positions.close();
    },
  );

  testWidgets(
      'dev mock, Clear, then share and a GPS stream error: no ring, and the '
      'map says 現在地不明 (never silent)', (tester) async {
    await pumpApp(tester);
    // The mock is on the development page (2026-09-15).
    await tapOnDeveloperPage(tester, const Key('use-mock-button'));
    await tapText(tester, 'クリア');

    await tapText(tester, '現在地を共有');
    positions.addError(StateError('platform GPS stream failed'));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(_ringKey), findsNothing);
    expect(map(tester).herPosition, isNull);
    expectWordsOnMap(tester);
    await positions.close();
  });

  group('controls: what a real anchor in this session still draws', () {
    testWidgets(
      're-share and a fresh fix elsewhere: the dot at the new place',
      (tester) async {
        final t = DateTime.now();
        await pumpApp(tester);
        await tapText(tester, '現在地を共有');
        await send(tester, _fixAt(_a, t));
        await tapText(tester, '停止');

        await tapText(tester, '現在地を共有');
        await send(tester, _fixAt(_b, t.add(const Duration(seconds: 30))));

        expect(map(tester).herPosition, _b);
        expect(find.byKey(_realDotKey), findsOneWidget);
        expect(find.byKey(_unknownKey), findsNothing);
        await positions.close();
      },
    );

    testWidgets(
      'a fix in this session, then a stream error: the ring stays at her '
      'last trusted point',
      (tester) async {
        await pumpApp(tester);
        await tapText(tester, '現在地を共有');
        await send(tester, _fixAt(_a, DateTime.now()));
        positions.addError(StateError('platform GPS stream failed'));
        await tester.pump();
        await tester.pump();

        expect(find.byKey(_ringKey), findsOneWidget);
        expect(map(tester).herPosition, _a);
        await positions.close();
      },
    );

    testWidgets(
      'the first session ever, services off: no anchor at all, the words '
      'alone (unchanged)',
      (tester) async {
        await pumpApp(tester);
        await tapText(tester, '現在地を共有');
        await send(
          tester,
          const PositionUnavailable('Location services disabled'),
        );

        expect(find.byKey(_ringKey), findsNothing);
        expectWordsOnMap(tester);
        await positions.close();
      },
    );
  });
}
