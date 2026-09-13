/// On a platform with no location implementation, sharing still reaches her
/// map as words, at once.
///
/// Why this test exists. geolocator 13.0.4 declares android, ios, macos, web
/// and windows, and no linux, the platform class of an in-vehicle head unit.
/// Measured 2026-09-14 on a Linux desktop release build of this app, running
/// the shipped entrypoint: three seconds after the share tap the map said
/// 現在地不明, no mark was drawn, and the line under it read
/// 「GPS を取得できません — GPS初期化のエラー。…」. In English the line
/// carried the event itself: "GPS init error: MissingPluginException(No
/// implementation found for method isLocationServiceEnabled on channel
/// flutter.baseflow.com/geolocator)".
///
/// That was right, and nothing held it right. This pins it off-device, at
/// every platform call the stream makes, with the exception the platform
/// actually threw: whichever call has no implementation, the stream says so
/// with an event, and never goes quiet.
///
/// Amended 2026-09-14, as ruled that day. The line named a GPS fault and,
/// in English, carried the exception's text. Where the app knows from the
/// exception's type that it has no location implementation, the line is
/// 現在地不明 — この端末では、このアプリは位置を取得できません。地図は表示された
/// ままです。 This file used to identify the absence by the reason's text; the
/// type is checked in test/l10n/position_line_words_test.dart.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission, Position;
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

MissingPluginException _missing(String method) => MissingPluginException(
    'No implementation found for method $method on channel '
    'flutter.baseflow.com/geolocator');

/// The stream with the named call unimplemented, the calls before it
/// answering as a platform that allows location would.
Stream<PositionFix> _streamMissing(String call) => herPositionStream(
      isServiceEnabled: call == 'isServiceEnabled'
          ? () async => throw _missing('isLocationServiceEnabled')
          : () async => true,
      checkPermission: call == 'checkPermission'
          ? () async => throw _missing('checkPermission')
          : () async => call == 'requestPermission'
              ? LocationPermission.denied
              : LocationPermission.whileInUse,
      requestPermission: call == 'requestPermission'
          ? () async => throw _missing('requestPermission')
          : () async => LocationPermission.whileInUse,
      positionStream: switch (call) {
        'positionStream-throws' => () => throw _missing('getPositionStream'),
        'positionStream-errors' => () =>
            Stream<Position>.error(_missing('getPositionStream')),
        _ => () => const Stream<Position>.empty(),
      },
    );

void main() {
  group('the stream, when a platform call has no implementation', () {
    for (final call in const [
      'isServiceEnabled',
      'checkPermission',
      'requestPermission',
      'positionStream-throws',
      'positionStream-errors',
    ]) {
      test('$call: an unavailability arrives, not silence, and not a refusal',
          () async {
        final e = await _streamMissing(call)
            .first
            .timeout(const Duration(seconds: 2));
        expect(e, isA<PositionUnavailable>());
        expect(isLocationRefusal(e), isFalse,
            reason: 'no implementation is not her setting');
      });
    }
  });

  testWidgets(
      'in the app: the map says 現在地不明 and the line says this app gets no '
      'position on this device, with no exception text', (tester) async {
    await tester.pumpWidget(SngnavApp(
      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      clock: () => DateTime.utc(2026, 1, 14, 21),
      jmaFetch: () async => const JmaFailure('no network in this test'),
      positionSource: () => _streamMissing('isServiceEnabled'),
    ));
    await tester.pump();
    await tester.pump();
    final share = find.byKey(const Key('share-location-button'));
    await tester.ensureVisible(share);
    await tester.pump();
    await tester.tap(share);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('her-position-unknown-label')),
        findsOneWidget);
    final line = tester
        .widget<Text>(find.byKey(const Key('her-status-line')))
        .data;
    // Ruled bytes, 2026-09-14.
    expect(line,
        '現在地不明 — この端末では、このアプリは位置を取得できません。地図は表示されたままです。');
  });
}
