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
/// And what must NOT change: a real GPS failure at drive start still reaches
/// the drive brain, and so does an unavailability whose reason merely says
/// "Location permission denied": the class is read from the typed cause, never
/// from free text. Location services off is not a denial and is unchanged.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

/// What she is given, as recorded: every spoken line, every haptic, and the
/// caution panel's rung. Joined into strings so two records compare by value:
/// a record compares a List field by identity, and two equal lists would
/// never be equal.
typedef _Given = ({String spoken, String haptics, String panel});

String _panel(WidgetTester tester) {
  bool has(List<String> texts) =>
      texts.any((t) => find.textContaining(t).evaluate().isNotEmpty);
  if (has(['停車の検討', 'Consider stopping'])) return 'considerStopping';
  if (has(['注意して走行', 'Heightened caution'])) return 'heightenedCaution';
  if (has(['特段の注意なし', 'No elevated caution'])) return 'continueDriving';
  // The card's no-position line follows the app's locale (2026-09-14); both
  // locales' words come from the app, so neither is hardcoded here.
  if (find.text(const AppL10n(Locale('ja')).driveHudNoPositionFed).evaluate().isNotEmpty ||
      find.text(const AppL10n(Locale('en')).driveHudNoPositionFed).evaluate().isNotEmpty) {
    return 'no rung (no position fed yet)';
  }
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
}) async {
  final a = FakeAlertActuators();
  _clockNow = DateTime.utc(2026, 1, 14, 21);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: a,
    locale: Locale(lang),
    clock: () => _clockNow,
    jmaFetch: () async => const JmaFailure('probe'),
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
/// (ruled 2026-09-13), with the same action as 停止.
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

  group('not silenced', () {
    Future<_Given> firstEvent(WidgetTester tester, PositionFix event) async {
      final positions = StreamController<PositionFix>.broadcast();
      final a = await _boot(tester, source: () => positions.stream);
      await _tapShare(tester);
      positions.add(event);
      await tester.pump();
      await _advance(tester, const Duration(seconds: 1));
      final given = _given(tester, a);
      await positions.close();
      return given;
    }

    testWidgets('a real GPS failure at drive start still reaches the drive '
        'brain', (tester) async {
      final given =
          await firstEvent(tester, const PositionUnavailable('GPS init error: x'));
      expect(given.panel, isNot('no rung (no position fed yet)'));
    });

    testWidgets(
        'an unavailability whose reason merely SAYS "Location permission '
        'denied" still reaches the drive brain: free text is never read',
        (tester) async {
      final given = await firstEvent(
          tester, const PositionUnavailable('Location permission denied'));
      expect(given.panel, isNot('no rung (no position fed yet)'));
    });

    testWidgets(
        'location services off is not a denial: unchanged here (measured and '
        'handed on, not ruled)', (tester) async {
      final given = await firstEvent(
          tester, const PositionUnavailable('Location services disabled'));
      expect(given.panel, isNot('no rung (no position fed yet)'));
    });
  });
}
