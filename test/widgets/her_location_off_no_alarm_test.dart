/// When location is off for this app, the app raises no alarm about it.
///
/// WHY, written before the act. Measured 2026-09-13 with recording actuators:
/// after a permission denial the app vibrated its CRITICAL pattern, said its
/// line inviting her to stop (「安全にできるときは、安全な場所での停車も選べ
/// ます。」), and put 停車の検討 on the caution panel: exactly its response
/// to a GPS failure. A driver who never pressed share got none of it. The app
/// has no position for either driver, and only the one who asked, and was
/// denied, was alarmed. Cause, in source: every position event went to the
/// drive brain, and with no fix ever it rates "no position at all" its top
/// concern, which always speaks at critical severity.
///
/// What must be true, in the shape of the probe that measured it: after either
/// denial, the recorded speak and haptic calls and the panel's rung equal the
/// never-shared driver's, in the same environment (the weather feed failing,
/// so both hear the same feed-loss line). The same after 停止. Checked at 1 s
/// and again 60 s later, past the blackout watchdog's cadence, because a
/// watchdog polling a refused feed would raise the same alarm later. The app's
/// clock ADVANCES with the pumps: under a fixed clock the watchdog measures no
/// elapsed time and can never poll, so the 60 s check would prove nothing (a
/// mutation that armed the watchdog passed under a fixed clock).
///
/// And what must NOT change: a real failure is never silenced, an
/// unavailability whose reason merely says "Location permission denied" is not
/// a refusal (the class is read from the typed cause, never from free text),
/// and location services off is not a denial. Until 2026-09-14 this paragraph
/// said a failure at drive start "still reaches the drive brain". Ruled that
/// day: before a share's first trusted fix it does not, by itself. The pins at
/// the foot of this file say what is kept, and where.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';
import '../support/rung_on_card.dart';

/// What she is given, as recorded: every spoken line, every haptic, and the
/// caution panel's rung. Joined into strings so two records compare by value:
/// a record compares a List field by identity, and two equal lists would
/// never be equal.
typedef _Given = ({String spoken, String haptics, String panel});

String _panel(WidgetTester tester) {
  // The rung from the caution banner's own headline (2026-09-15). A search of
  // the whole screen for rung words read any text naming a rung as the rung.
  final rung = rungOnCard();
  if (rung != null) return rung.name;
  // The card's no-position line, read by its key in either language.
  if (noPositionLineOnCard()) return 'no rung (no position fed yet)';
  return 'UNREADABLE';
}

_Given _given(WidgetTester tester, FakeAlertActuators a) => (
      spoken: [for (final s in a.spoken) '$s'].join(' | '),
      haptics: [for (final h in a.haptics) '$h'].join(' | '),
      panel: _panel(tester),
    );

/// The app's clock, advanced together with the test's fake time.
var _clockNow = DateTime.utc(2026, 1, 14, 21);

Future<void> _advance(WidgetTester tester, Duration d) async {
  _clockNow = _clockNow.add(d);
  await tester.pump(d);
}

Future<FakeAlertActuators> _boot(
  WidgetTester tester, {
  Stream<PositionFix> Function()? source,
  String lang = 'ja',
  JmaResult? weather,
}) async {
  final a = FakeAlertActuators();
  _clockNow = DateTime.utc(2026, 1, 14, 21);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: a,
    locale: Locale(lang),
    clock: () => _clockNow,
    jmaFetch: () async => weather ?? const JmaFailure('probe'),
    positionSource: source,
  ));
  await tester.pump();
  await tester.pump();
  return a;
}

Future<void> _tapShare(WidgetTester tester) async {
  final b = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(b);
  await tester.pump();
  await tester.tap(b);
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

/// The row's end-sharing control. After a denial it reads 閉じる / "Close"
/// (decided 2026-09-13), with the same action as 停止.
Future<void> _tapStop(WidgetTester tester, String lang) async {
  final s = find.text(lang == 'ja' ? '閉じる' : 'Close');
  await tester.ensureVisible(s.first);
  await tester.pump();
  await tester.tap(s.first);
  await tester.pump();
}

Stream<PositionFix> _denied() => herPositionStream(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.denied,
      requestPermission: () async => LocationPermission.denied,
    );

Stream<PositionFix> _deniedForever() => herPositionStream(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.deniedForever,
    );

/// The never-shared driver, in the same environment, read at the same times.
Future<(_Given, _Given)> _neverShared(WidgetTester tester, String lang) async {
  final a = await _boot(tester, lang: lang);
  await _advance(tester, const Duration(seconds: 1));
  final at1s = _given(tester, a);
  await _advance(tester, const Duration(seconds: 60));
  return (at1s, _given(tester, a));
}

void main() {
  for (final (name, source, lang) in [
    ('denied', _denied, 'ja'),
    ('denied for good', _deniedForever, 'ja'),
    ('denied, English device', _denied, 'en'),
  ]) {
    testWidgets('$name: what she is given equals the never-shared driver\'s',
        (tester) async {
      final (control1s, control61s) = await _neverShared(tester, lang);
      expect(control1s.panel, 'no rung (no position fed yet)',
          reason: 'control: the never-shared driver has no rung');

      final a = await _boot(tester, source: source, lang: lang);
      await _tapShare(tester);
      expect(find.byKey(const ValueKey('her-location-off-label')),
          findsOneWidget,
          reason: 'control: the denial reached the app');
      await _advance(tester, const Duration(seconds: 1));
      expect(_given(tester, a), control1s, reason: 'at 1 s');
      await _advance(tester, const Duration(seconds: 60));
      expect(_given(tester, a), control61s,
          reason: 'at 61 s, past the watchdog cadence');
    });
  }

  testWidgets('denied, then 閉じる (formerly 停止): still the never-shared '
      'driver\'s',
      (tester) async {
    final (_, control61s) = await _neverShared(tester, 'ja');

    final a = await _boot(tester, source: _denied);
    await _tapShare(tester);
    await _advance(tester, const Duration(seconds: 1));
    await _tapStop(tester, 'ja');
    await _advance(tester, const Duration(seconds: 60));
    expect(_given(tester, a), control61s);
  });

  // Re-expressed 2026-09-14. These three pins said a failure at drive start
  // "still reaches the drive brain", read as "the panel has a rung". Ruled the
  // same day: before a share's first trusted fix, a position failure does not
  // reach the caution rung by itself, so all three went red on the decided
  // landing, as the decision's author and its auditor both predicted. What they
  // protected is kept here in the decision's terms: a real failure is never
  // silenced (her map says so at once, and a measured condition still reaches
  // the drive brain with it); free text is never read, pinned where the words
  // could still decide something, after a trusted fix in the same share; and
  // location services off is still not a denial.
  group('not silenced', () {
    Position trustedFix(DateTime t) => Position(
          latitude: 39.7186,
          longitude: 140.1024,
          timestamp: t,
          accuracy: 10,
          hasAccuracy: true,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );

    Future<FakeAlertActuators> firstEvent(WidgetTester tester, PositionFix event,
        {JmaResult? weather}) async {
      final positions = StreamController<PositionFix>.broadcast();
      final a = await _boot(tester,
          source: () => positions.stream, weather: weather);
      await _tapShare(tester);
      positions.add(event);
      await tester.pump();
      await _advance(tester, const Duration(seconds: 1));
      await positions.close();
      return a;
    }

    testWidgets(
        'a real GPS failure at drive start is not silenced: her map says '
        '現在地不明 at once, and under a measured 80 m whiteout it still '
        'reaches the drive brain', (tester) async {
      await firstEvent(tester, const PositionUnavailable('GPS init error: x'));
      expect(find.byKey(const ValueKey('her-position-unknown-label')),
          findsOneWidget,
          reason: 'the map says it does not know where she is');

      final a = await firstEvent(
          tester, const PositionUnavailable('GPS init error: x'),
          weather: _observed(80));
      expect(_given(tester, a).panel, 'considerStopping',
          reason: 'a measured whiteout keeps its caution for a failed start');
      expect(a.haptics.map((h) => '$h'), contains('HapticCuePattern.critical'));
    });

    testWidgets(
        'after a trusted fix in the same share, an unavailability whose reason '
        'merely SAYS "Location permission denied" still degrades the drive '
        'brain and is not shown as location off: free text is never read',
        (tester) async {
      final platform = StreamController<Position>();
      final a = await _boot(tester,
          source: () => herPositionStream(
                isServiceEnabled: () async => true,
                checkPermission: () async => LocationPermission.whileInUse,
                positionStream: () => platform.stream,
              ));
      await _tapShare(tester);
      platform.add(trustedFix(_clockNow));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('GPS 良好'), findsWidgets,
          reason: 'control: the fix reached the drive brain as trusted');
      expect(_given(tester, a).panel, isNot('no rung (no position fed yet)'));

      platform.addError(StateError('Location permission denied'));
      await tester.pump();
      await _advance(tester, const Duration(seconds: 1));
      expect(find.textContaining('GPS 良好'), findsNothing,
          reason: 'the event reached the drive brain and degraded it');
      expect(find.byKey(const ValueKey('her-location-off-label')), findsNothing,
          reason: 'words in an error are not her setting');
      await platform.close();
    });

    testWidgets(
        'location services off is not a denial: her map says 現在地不明, not '
        '位置情報オフ, and the row still offers 停止', (tester) async {
      await firstEvent(
          tester, const PositionUnavailable('Location services disabled'));
      expect(find.byKey(const ValueKey('her-position-unknown-label')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('her-location-off-label')), findsNothing);
      expect(find.text('停止'), findsWidgets);
      expect(find.text('閉じる'), findsNothing);
    });
  });
}

/// A JMA observation read at boot. Warm and calm, so no measured-weather watch
/// fires: only visibility differs.
JmaResult _observed(int visibilityMeters) => JmaSuccess(JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 5,
      humidityPercent: 50,
      windMetersPerSecond: 2,
      snowDepthCm: null,
      precipitation10mMm: 0,
      visibilityMeters: visibilityMeters,
      observedAtJstKey: '20260115060000',
      fetchedAt: _clockNow,
    ));
