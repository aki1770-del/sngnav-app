/// Which caution rung a failed start is given under a measured condition,
/// before her first trusted fix of a share (decided 2026-09-15).
///
/// Why, written before the act. Ruled 2026-09-14: before a share's first
/// trusted fix a position failure does not reach the caution rung by itself,
/// and it never takes away a caution a measured condition raises. The app met
/// both by giving the failure to the drive brain whenever a measured condition
/// raises caution. The brain rates "no position at all" its top concern, which
/// stands alone at the ceiling, so from that moment the failure's own concern
/// sets the rung. Measured through the app on 6a72b41: a failed start is given
/// nothing at a measured 1,000 m and the top rung (停車の検討, the invitation to
/// stop, the critical haptic) at every measured visibility from 999 m down. A
/// driver with a trusted position is given heightened caution from 999 m to
/// 200 m, and the top rung below 200 m. A driver 31 s into a GPS blackout, her
/// ring 72 m, is given heightened caution from 999 m to 500 m and the top rung
/// below 500 m: the app compounds an uncertain position with a low visibility.
///
/// Ruled. The failure is an unlocated position, and it compounds as one; it is
/// never a concern standing alone at the ceiling. So:
/// * From 999 m to 500 m nothing compounds, for any driver whose position is
///   uncertain but not lost. The top rung there was the failure standing alone:
///   she is given heightened caution, as a positioned driver there is. An alarm
///   the road does not earn spends her attention.
/// * From 499 m to 200 m an uncertain position compounds with the low
///   visibility. Giving her what a positioned driver is given would give the
///   driver who knows least where she is less caution than a driver whose ring
///   is 72 m: she keeps the top rung. Doubt routes toward caution.
/// * Below 200 m, and at 1,000 m and above, nothing changes.
/// * A firing measured watch compounds with an unlocated position already
///   (measured_hazard_floor.dart): she keeps the top rung.
///
/// Over time: a rise is told when it comes. Once given, the rung does not fall
/// within the share, as on 6a72b41. A reading the app counts stale must not
/// lower it: lowered, it is told again when the next reading arrives, with no
/// change on the road. Recorded and not decided: a later measured clear reading
/// does not release it either. Whether it should is its own question.
///
/// Read without the card's words or colours: every spoken line and every
/// haptic, and the rung from the caution banner's own headline, mapped back
/// through the app's own localizer. Every JMA reading is stamped at the moment
/// the app fetches it, so it is fresh for the app's 300 s window after each
/// 10-minute refresh. A measured whiteout is also told to a driver before she
/// shares (decided 2026-09-15), so what a share is given is read from her tap.
library;

import 'dart:async';

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show DriveAction;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/drive_hud_localizer.dart';

import '../support/fake_alert_actuators.dart';

const _hud = DriveHudLocalizer();
final _stopLine = _hud.spokenGuidance(DriveAction.considerStopping, 'ja');
final _slowLine = _hud.spokenGuidance(DriveAction.heightenedCaution, 'ja');
const _critical = 'HapticCuePattern.critical';
const _warning = 'HapticCuePattern.warning';

final _start = DateTime.utc(2026, 1, 14, 21);
var _clockNow = _start;

typedef _Given = ({String panel, List<String> spoken, List<String> haptics});

/// The caution banner's rung, from its own headline mapped back through the
/// app's localizer: 'no rung' when no banner is built, and a headline no rung
/// produces fails loudly.
String _panel(WidgetTester tester) {
  final banner = find.byKey(const Key('drive-hud-caution-banner'));
  if (banner.evaluate().isEmpty) return 'no rung';
  final texts = [
    for (final e in find
        .descendant(of: banner, matching: find.byType(Text))
        .evaluate())
      (e.widget as Text).data ?? '',
  ];
  final rungs = <String>{
    for (final s in texts)
      for (final r in DriveAction.values)
        for (final advisory in const [false, true])
          for (final measured in const [false, true])
            for (final calm in const [false, true])
              if (s ==
                  _hud.actionHeadline(r, 'ja',
                      advisoryUnconfirmed: advisory,
                      measuredUnconfirmed: measured,
                      calmNoteInForce: calm))
                r.name,
  };
  return rungs.length == 1 ? rungs.single : 'UNREADABLE $texts';
}

_Given _given(WidgetTester tester, FakeAlertActuators a,
        {int spokenFrom = 0, int hapticsFrom = 0}) =>
    (
      panel: _panel(tester),
      spoken: [for (final s in a.spoken.skip(spokenFrom)) s.text],
      haptics: [for (final h in a.haptics.skip(hapticsFrom)) '$h'],
    );

String _jstKey(DateTime utc) {
  final j = utc.add(const Duration(hours: 9));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${j.year}${two(j.month)}${two(j.day)}${two(j.hour)}${two(j.minute)}00';
}

/// Warm and dry, stamped when the app fetches it. Wind 2 m/s fires no watch.
JmaResult _observedNow(int? visibilityMeters, {double wind = 2}) =>
    JmaSuccess(JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 5,
      humidityPercent: 50,
      windMetersPerSecond: wind,
      snowDepthCm: null,
      precipitation10mMm: 0,
      visibilityMeters: visibilityMeters,
      observedAtJstKey: _jstKey(_clockNow),
      fetchedAt: _clockNow,
    ));

Future<void> _advance(WidgetTester tester, Duration d) async {
  var left = d;
  while (left > Duration.zero) {
    final step =
        left > const Duration(seconds: 15) ? const Duration(seconds: 15) : left;
    _clockNow = _clockNow.add(step);
    await tester.pump(step);
    left -= step;
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

Future<FakeAlertActuators> _boot(
  WidgetTester tester, {
  Stream<PositionFix> Function()? source,
  required Future<JmaResult> Function() jma,
}) async {
  final a = FakeAlertActuators();
  _clockNow = _start;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: a,
    locale: const Locale('ja'),
    clock: () => _clockNow,
    jmaFetch: jma,
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
  await _settle(tester);
  expect(find.byKey(const Key('share-location-button')), findsNothing,
      reason: 'control: sharing started');
}

Position _position(DateTime t) => Position(
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

Stream<PositionFix> _granted(StreamController<Position> platform) =>
    herPositionStream(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      positionStream: () => platform.stream,
    );

/// A share whose platform start throws: the stream's "GPS init error".
Stream<PositionFix> _failedStart() => herPositionStream(
      isServiceEnabled: () async => throw StateError('no location provider'),
    );

/// A share with location services off.
Stream<PositionFix> _servicesOff() =>
    herPositionStream(isServiceEnabled: () async => false);

const _causes = <(String, Stream<PositionFix> Function())>[
  ('a failed start', _failedStart),
  ('location services off', _servicesOff),
];

/// A driver with a trusted position, given a fresh fix before every step, read
/// after 1 s.
Future<_Given> _positionedAt(WidgetTester tester, int visibility,
    {double wind = 2}) async {
  final platform = StreamController<Position>();
  final a = await _boot(tester,
      source: () => _granted(platform),
      jma: () async => _observedNow(visibility, wind: wind));
  await _tapShare(tester);
  platform.add(_position(_clockNow));
  await _settle(tester);
  _clockNow = _clockNow.add(const Duration(seconds: 1));
  platform.add(_position(_clockNow));
  await tester.pump(const Duration(seconds: 1));
  await _settle(tester);
  return _given(tester, a);
}

/// A driver with one trusted fix and then silence, read at [at]: the app's own
/// watchdog degrades her position.
Future<_Given> _blackoutAt(
    WidgetTester tester, int visibility, Duration at) async {
  final platform = StreamController<Position>();
  final a = await _boot(tester,
      source: () => _granted(platform),
      jma: () async => _observedNow(visibility));
  await _tapShare(tester);
  platform.add(_position(_clockNow));
  await _settle(tester);
  await _advance(tester, at);
  return _given(tester, a);
}

void main() {
  // ------------------------------------------------------------ the band ----

  group('the band, from 999 m to 500 m: heightened caution, as a positioned '
      'driver there', () {
    for (final vis in [999, 700, 500]) {
      for (final (name, cause) in _causes) {
        testWidgets('$name under a measured $vis m, at 1 s and 61 s',
            (tester) async {
          final positioned = await _positionedAt(tester, vis);
          expect(positioned.panel, 'heightenedCaution',
              reason: 'control: a positioned driver under $vis m');
          expect(positioned.spoken, [_slowLine],
              reason: 'control: the caution $vis m raises is spoken');
          expect(positioned.haptics, [_warning],
              reason: 'control: the caution $vis m raises is felt');

          final a = await _boot(tester,
              source: cause, jma: () async => _observedNow(vis));
          await _tapShare(tester);
          for (final (label, step) in [
            ('1 s', const Duration(seconds: 1)),
            ('61 s', const Duration(seconds: 60)),
          ]) {
            await _advance(tester, step);
            final g = _given(tester, a);
            expect(g.panel, 'heightenedCaution',
                reason: 'at $label: nothing compounds at $vis m for a position '
                    'that is uncertain but not lost');
            expect(g.spoken, positioned.spoken,
                reason: 'at $label: spoken to as a positioned driver under '
                    '$vis m is');
            expect(g.haptics, positioned.haptics,
                reason: 'at $label: felt as a positioned driver under $vis m '
                    'is; a critical haptic here is the failure standing alone');
          }
        });
      }
    }
  });

  group('the band, from 499 m to 200 m: the top rung, an unlocated position '
      'compounding with a low visibility', () {
    for (final vis in [499, 300, 200]) {
      for (final (name, cause) in _causes) {
        testWidgets('$name under a measured $vis m, at 1 s and 61 s',
            (tester) async {
          final positioned = await _positionedAt(tester, vis);
          expect(positioned.panel, 'heightenedCaution',
              reason: 'control: the road alone raises heightened caution at '
                  '$vis m for a positioned driver');

          final a = await _boot(tester,
              source: cause, jma: () async => _observedNow(vis));
          await _tapShare(tester);
          for (final (label, step) in [
            ('1 s', const Duration(seconds: 1)),
            ('61 s', const Duration(seconds: 60)),
          ]) {
            await _advance(tester, step);
            final g = _given(tester, a);
            expect(g.panel, 'considerStopping', reason: 'at $label');
            expect(g.spoken, [_stopLine],
                reason: 'at $label: the invitation to stop, once');
            expect(g.haptics, [_critical],
                reason: 'at $label: the critical haptic, once');
          }
        });
      }
    }
  });

  group('the band edges, unchanged', () {
    for (final (name, cause) in _causes) {
      testWidgets('$name under a measured 199 m whiteout: the top rung',
          (tester) async {
        final a = await _boot(tester,
            source: cause, jma: () async => _observedNow(199));
        final spokenBefore = a.spoken.length;
        final hapticsBefore = a.haptics.length;
        await _tapShare(tester);
        await _advance(tester, const Duration(seconds: 1));
        final g = _given(tester, a,
            spokenFrom: spokenBefore, hapticsFrom: hapticsBefore);
        expect(g.panel, 'considerStopping');
        expect(g.spoken, [_stopLine]);
        expect(g.haptics, [_critical]);
      });

      testWidgets(
          '$name under a measured 1,000 m: what the never-shared driver is '
          'given, at 1 s and 61 s', (tester) async {
        final never = await _boot(tester, jma: () async => _observedNow(1000));
        await _advance(tester, const Duration(seconds: 1));
        final n1 = _given(tester, never);
        await _advance(tester, const Duration(seconds: 60));
        final n61 = _given(tester, never);

        final a = await _boot(tester,
            source: cause, jma: () async => _observedNow(1000));
        await _tapShare(tester);
        await _advance(tester, const Duration(seconds: 1));
        final g1 = _given(tester, a);
        await _advance(tester, const Duration(seconds: 60));
        final g61 = _given(tester, a);
        for (final (label, g, n) in [('1 s', g1, n1), ('61 s', g61, n61)]) {
          expect(g.panel, n.panel, reason: 'panel at $label');
          expect(g.spoken, n.spoken, reason: 'spoken at $label');
          expect(g.haptics, n.haptics, reason: 'haptics at $label');
        }
      });
    }
  });

  // ------------------------------------------- the compounding reference ----

  testWidgets(
      'the reference is the app\'s own: a failed start is given the '
      'rung a driver 46 s into a blackout is given, at 300 m and at 700 m',
      (tester) async {
    for (final vis in [300, 700]) {
      final blackout = await _blackoutAt(tester, vis, const Duration(seconds: 46));
      final a = await _boot(tester,
          source: _failedStart, jma: () async => _observedNow(vis));
      await _tapShare(tester);
      await _advance(tester, const Duration(seconds: 46));
      final g = _given(tester, a);
      expect(g.panel, blackout.panel,
          reason: 'at $vis m the failed start\'s rung is not the rung of a '
              'position that is uncertain but not lost');
      final felt = blackout.haptics.contains(_critical) ? _critical : _warning;
      expect(g.haptics, [felt],
          reason: 'at $vis m: felt once, at the strength the blackout driver\'s '
              'rung is felt');
    }
  });

  // ------------------------------------------------------- a firing watch ----

  testWidgets(
      'a firing wind watch under a measured clear 1,500 m: a failed '
      'start keeps the top rung, compounding with an unlocated position',
      (tester) async {
    final positioned = await _positionedAt(tester, 1500, wind: 12);
    expect(positioned.panel, 'heightenedCaution',
        reason: 'control: the watch alone floors a positioned driver at '
            'heightened caution');

    final a = await _boot(tester,
        source: _failedStart, jma: () async => _observedNow(1500, wind: 12));
    await _tapShare(tester);
    await _advance(tester, const Duration(seconds: 1));
    final g = _given(tester, a);
    expect(g.panel, 'considerStopping');
    expect(g.spoken, contains(_stopLine));
    expect(g.haptics, contains(_critical));
  });

  // -------------------------------------------------------------- over time ----

  group('over time', () {
    // Between refreshes the drive brain is only polled, and a poll recomputes
    // with the visibility age set at the last feed or refresh: a given failure
    // never sees its reading go stale that way. A refresh that fails pushes the
    // retained reading's real age (main.dart, _refreshJma), so that is how
    // these two tests show the brain a stale reading. A failed refresh speaks
    // its own feed-loss line, so only the rung's own lines and the critical
    // haptic are read after it.
    for (final (vis, rung, line) in [
      (300, 'considerStopping', _stopLine),
      (700, 'heightenedCaution', _slowLine),
    ]) {
      testWidgets(
          'a stale reading does not lower the rung: given at a measured '
          '$vis m, a failed refresh at 10 min and $vis m again at 20 min',
          (tester) async {
        var calls = 0;
        final a = await _boot(tester,
            source: _failedStart,
            jma: () async => ++calls == 2
                ? const JmaFailure('test: the 10-minute refresh failed')
                : _observedNow(vis));
        await _tapShare(tester);
        await _advance(tester, const Duration(seconds: 1));
        final first = _given(tester, a);
        expect(first.panel, rung, reason: 'given at 1 s under $vis m');
        for (final (label, step, wantCalls) in [
          ('10 min 15 s, the reading now 615 s old',
              const Duration(minutes: 10, seconds: 14), 2),
          ('20 min 15 s, refreshed', const Duration(minutes: 10), 3),
        ]) {
          await _advance(tester, step);
          await _settle(tester);
          expect(calls, greaterThanOrEqualTo(wantCalls),
              reason: 'control: the refresh ran by $label');
          final g = _given(tester, a,
              spokenFrom: first.spoken.length,
              hapticsFrom: first.haptics.length);
          expect(g.panel, rung, reason: 'at $label');
          expect(g.spoken.where((s) => s == _stopLine || s == _slowLine),
              isEmpty,
              reason: 'at $label: the rung was lowered and told again ($line)');
          expect(g.haptics, isNot(contains(_critical)), reason: 'at $label');
        }
      });
    }

    testWidgets(
        'a rise is told when it comes: 700 m at share start, 300 m from the '
        '10-minute refresh', (tester) async {
      var calls = 0;
      final a = await _boot(tester,
          source: _failedStart,
          jma: () async => _observedNow(++calls == 1 ? 700 : 300));
      await _tapShare(tester);
      await _advance(tester, const Duration(seconds: 1));
      final before = _given(tester, a);
      expect(before.panel, 'heightenedCaution', reason: 'under 700 m');
      expect(before.spoken, [_slowLine], reason: 'under 700 m');
      expect(before.haptics, [_warning], reason: 'under 700 m');
      await _advance(tester, const Duration(minutes: 10, seconds: 15));
      await _settle(tester);
      expect(calls, greaterThanOrEqualTo(2),
          reason: 'control: the refresh fetched 300 m');
      final after = _given(tester, a,
          spokenFrom: before.spoken.length, hapticsFrom: before.haptics.length);
      expect(after.panel, 'considerStopping', reason: 'under 300 m');
      expect(after.spoken, [_stopLine],
          reason: 'the invitation to stop is told when 300 m arrives');
      expect(after.haptics, [_critical],
          reason: 'the critical haptic is felt when 300 m arrives');
    });

    testWidgets(
        'recorded, not decided: given at a measured 300 m, a measured clear '
        '1,500 m from the refresh does not release the top rung', (tester) async {
      var calls = 0;
      final a = await _boot(tester,
          source: _failedStart,
          jma: () async => _observedNow(++calls == 1 ? 300 : 1500));
      await _tapShare(tester);
      await _advance(tester, const Duration(seconds: 1));
      final first = _given(tester, a);
      await _advance(tester, const Duration(minutes: 11));
      expect(calls, greaterThanOrEqualTo(2),
          reason: 'control: the refresh fetched 1,500 m');
      final g = _given(tester, a,
          spokenFrom: first.spoken.length, hapticsFrom: first.haptics.length);
      expect(g.panel, 'considerStopping');
      expect(g.spoken, isEmpty);
      expect(g.haptics, isEmpty);
    });
  });
}
