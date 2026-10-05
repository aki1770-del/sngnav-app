/// The GPS trust verdict as wired into the drive brain: what it holds back,
/// what it never takes away, and what stays in shadow.
///
/// Why, written before the act (2026-10-05). Until this date the drive brain
/// fed every finite fix to the position controller as `trusted`, so a jump no
/// car made, a fix the receiver put at ±400 m, or a replay read 「GPS 良好」 and
/// a turn on her press was read as given. The tests that a fix is assessed at
/// all are in drive_gps_trust_invariant_test.dart. This file holds the rules
/// the wiring adds around that verdict, each one a way the wiring could fail
/// her without any of those tests seeing it:
///  - a share's first fix has nothing to be judged against: it is held, it is
///    the base the next fix is judged against, and the next fix anchors;
///  - a doubtful fix withholds the turn instead of hedging it, and the verdict
///    is never made worse to get that silence;
///  - an assessor that cannot run makes every fix doubtful, never trusted, and
///    never stops the position feed;
///  - a share starts the verdict again;
///  - a coarse fix is never the base a later fix is judged against;
///  - the gates kept in shadow change nothing she is shown;
///  - the development page's test position is the only fix that skips the
///    verdict, and it has exactly one caller.
///
/// Every fix here is synthetic. Nothing here is a device reading.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:localization_fallback/localization_fallback.dart';
import 'package:position_integrity/position_integrity.dart' as pi;
import 'package:routing_engine/routing_engine.dart' show RouteManeuver;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/services/drive_hud_controller.dart';
import 'package:sngnav_app/services/drive_hud_localizer.dart';
import 'package:sngnav_app/services/drive_safety_fusion.dart';
import 'package:sngnav_app/services/gps_trust.dart';
import 'package:sngnav_app/services/maneuver_narration.dart';

import '../support/dart_source.dart';
import '../support/fake_alert_actuators.dart';

final _t0 = DateTime.utc(2026, 1, 15, 6, 30);
const double _lat0 = 39.72;
const double _lon0 = 140.10;
const double _mPerDegLat = 6371000.0 * math.pi / 180.0;
final double _mPerDegLon = _mPerDegLat * math.cos(_lat0 * math.pi / 180.0);

/// A fix [seconds] after [_t0], [northM] up the road and [eastM] across it.
PositionAvailable _at(double seconds,
        {double northM = 0, double eastM = 0, double acc = 5}) =>
    PositionAvailable(
      latitude: _lat0 + northM / _mPerDegLat,
      longitude: _lon0 + eastM / _mPerDegLon,
      accuracyMeters: acc,
      timestamp: _t0.add(Duration(microseconds: (seconds * 1e6).round())),
    );

RouteManeuver _rightTurn() => const RouteManeuver(
      index: 1,
      instruction: 'Right onto Route 13',
      type: 'right',
      lengthKm: 0.4,
      timeSeconds: 30,
      position: LatLng(39.73, 140.10),
    );

DriveHudController _clear(FakeAlertActuators fake) {
  final c = DriveHudController(actuators: fake, localeTag: 'ja');
  c.updateEnvironment(
    visibilityMeters: 10000,
    visibilityAgeSeconds: 0,
    advisorySeverity: null,
    speedMetersPerSecond: null,
  );
  return c;
}

/// Asked and held, as the app holds a share's first fix, then [fix] fed.
void _anchor(DriveHudController c, PositionAvailable held,
    PositionAvailable fix) {
  expect(c.wouldTrust(held), isFalse,
      reason: 'control: a share\'s first fix is held');
  c.onPositionFix(fix, now: fix.timestamp);
  expect(c.estimate!.mode, LocalizationMode.gpsTrusted,
      reason: 'control: the fix after it anchors');
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('a share\'s first fix: held, the base for the next, which anchors', () {
    test('a first fix is not trusted, asked or fed, and says why', () {
      final asking = DriveHudController(
          actuators: FakeAlertActuators(), localeTag: 'ja');
      expect(asking.wouldTrust(_at(0)), isFalse);
      expect(asking.awaitsComparison(_at(0)), isTrue,
          reason: 'nothing was found wrong with it: a normal start');

      final feeding = DriveHudController(
          actuators: FakeAlertActuators(), localeTag: 'ja');
      feeding.onPositionFix(_at(0), now: _at(0).timestamp);
      expect(feeding.estimate!.mode, isNot(LocalizationMode.gpsTrusted));
      expect(feeding.gpsTrustVerdict!.assessed, isFalse);
      expect(feeding.gpsTrustVerdict!.reasons.first, contains('first fix'));
    });

    test('the held fix is the base: a jump from it is not trusted', () {
      final c = DriveHudController(
          actuators: FakeAlertActuators(), localeTag: 'ja');
      expect(c.wouldTrust(_at(0)), isFalse, reason: 'control: held');
      // 300 m across the road one second after the held fix.
      c.onPositionFix(_at(1, eastM: 300), now: _at(1).timestamp);
      expect(c.estimate!.mode, isNot(LocalizationMode.gpsTrusted),
          reason: 'judged against the held fix, not taken as a first fix');
      expect(c.gpsTrustVerdict!.assessed, isTrue);
    });

    test(
        'the next consistent fix anchors within one fix interval: 5 s on, the '
        'fused provider\'s interval, 75 m up the road', () {
      final c = DriveHudController(
          actuators: FakeAlertActuators(), localeTag: 'ja');
      expect(c.wouldTrust(_at(0)), isFalse, reason: 'control: held');
      final next = _at(5, northM: 75);
      expect(c.wouldTrust(next), isTrue);
      c.onPositionFix(next, now: next.timestamp);
      expect(c.estimate!.mode, LocalizationMode.gpsTrusted);
      expect(c.estimate!.basis, EstimateBasis.trustedGpsFix);
    });

    test('a coarse first fix is a real doubt, not a normal start', () {
      final c = DriveHudController(
          actuators: FakeAlertActuators(), localeTag: 'ja');
      expect(c.awaitsComparison(_at(0, acc: 400)), isFalse);
      expect(c.wouldTrust(_at(0, acc: 400)), isFalse);
    });
  });

  group('a doubtful fix withholds the turn; the verdict stays true', () {
    test(
        'after a trusted fix, a ±400 m fix: 「GPS 不確か」, the turn withheld, '
        'nothing spoken, and never 「GPS 途絶（推測航法）」', () async {
      final fake = FakeAlertActuators();
      final c = _clear(fake);
      _anchor(c, _at(0), _at(1, northM: 15));
      c.onPositionFix(_at(2, northM: 30, acc: 400), now: _at(2).timestamp);
      final mode = c.estimate!.mode;
      expect(mode, LocalizationMode.gpsSuspect,
          reason: 'the verdict is suspect, and it is not made worse');
      const text = DriveHudLocalizer();
      expect(text.modeLabel(mode, 'ja'), 'GPS 不確か');
      expect(text.modeLabel(mode, 'ja'), isNot(contains('途絶')));

      expect(c.previewNextManeuver(_rightTurn(), icyTurn: false).confidence,
          NarrationConfidence.suppressed);
      // The rise to heightened caution this coarse fix gives is told on its
      // own; it is the accuracy gate's told event, and not a turn.
      await _settle();
      final spokenBefore = fake.spoken.length;
      final d = c.narrateNextManeuver(_rightTurn(), icyTurn: false);
      await _settle();
      expect(d.confidence, NarrationConfidence.suppressed);
      expect(d.mode, LocalizationMode.gpsSuspect,
          reason: 'the decision carries the true mode');
      expect(fake.spoken.skip(spokenBefore), isEmpty,
          reason: 'no turn, plain or hedged, reached the audio channel');
      expect(fake.spoken.map((l) => l.text).where((t) => t.contains('右折')),
          isEmpty,
          reason: 'no turn line at any time');
    });

    test('the narrator on its own still hedges, so the hedged line stays '
        'buildable for the day the flag comes off', () {
      expect(kSuspectWithholdsTurn, isTrue,
          reason: 'the flag stands until its three exits are met');
      final d = const ManeuverNarrator().decide(
        maneuver: _rightTurn(),
        mode: LocalizationMode.gpsSuspect,
        icyTurn: false,
      );
      expect(d.confidence, NarrationConfidence.hedge);
    });
  });

  group('an assessor that cannot run: every fix doubtful, the feed never '
      'stopped', () {
    test('cannot be constructed', () {
      final l = DriveLocalizer(
          assessor: GpsTrustAssessor(monitor: () => throw StateError('bad')));
      for (var s = 0; s < 5; s++) {
        expect(l.wouldTrust(_at(s.toDouble(), northM: 15.0 * s)), isFalse);
        final e = l.onPositionFix(_at(s.toDouble(), northM: 15.0 * s), _t0);
        expect(e.mode, isNot(LocalizationMode.gpsTrusted), reason: 'fix $s');
        expect(l.lastVerdict!.acting, TrustSignal.suspect, reason: 'fix $s');
      }
      expect(l.assessorFaults, greaterThan(0), reason: 'recorded');
    });

    test('throws on a fix', () {
      final l = DriveLocalizer(
          assessor: GpsTrustAssessor(monitor: () => _ThrowingMonitor()));
      final e = l.onPositionFix(_at(0), _t0);
      expect(e, isNotNull, reason: 'the feed still gives an estimate');
      expect(l.lastVerdict!.acting, TrustSignal.suspect);
      l.onPositionFix(_at(1, northM: 15), _t0);
      expect(l.lastVerdict!.acting, TrustSignal.suspect);
      expect(l.assessorFaults, 2);
    });
  });

  test(
      'a replay is failed: never the package\'s "skipped" suspect, never '
      'trusted, and nothing is advanced by it', () {
    // Found by mutation (2026-10-05): with this check deleted, the controller's
    // own stale guard still degrades the replay, so no test of what she is
    // shown went red, while the verdict on record read `trusted` for a fix
    // that carried no new position.
    final c = DriveHudController(
        actuators: FakeAlertActuators(), localeTag: 'ja');
    _anchor(c, _at(0), _at(1, northM: 15));
    c.onPositionFix(_at(1, northM: 15), now: _at(1).timestamp);
    expect(c.gpsTrustVerdict!.acting, TrustSignal.failed);
    expect(c.gpsTrustVerdict!.reasons.single, contains('not newer'));
    expect(c.estimate!.mode, isNot(LocalizationMode.gpsSuspect));
    // The next fix is judged against the last real fix, not the replay.
    c.onPositionFix(_at(2, northM: 30), now: _at(2).timestamp);
    expect(c.gpsTrustVerdict!.acting, TrustSignal.trusted);
    expect(c.estimate!.mode, LocalizationMode.gpsTrusted);
  });

  test(
      'a share starts the verdict again: its first fix is not judged against '
      'the last share\'s place, and the fix after it anchors', () {
    final c = DriveHudController(
        actuators: FakeAlertActuators(), localeTag: 'ja');
    _anchor(c, _at(0), _at(1, northM: 15));
    c.startShare();
    // 10 km away, 30 s later: an impossible speed, were it compared.
    final first = _at(31, northM: 10000);
    expect(c.wouldTrust(first), isFalse);
    expect(c.awaitsComparison(first), isTrue,
        reason: 'held as a first fix, not rejected as a jump');
    final next = _at(36, northM: 10075);
    c.onPositionFix(next, now: next.timestamp);
    expect(c.estimate!.mode, LocalizationMode.gpsTrusted);
  });

  test(
      'satellite and network fixes alternating once a second: every satellite '
      'fix is trusted, every network fix is suspect, none is failed', () {
    final c = DriveHudController(
        actuators: FakeAlertActuators(), localeTag: 'ja');
    _anchor(c, _at(0), _at(1, northM: 15));
    for (var s = 2; s < 20; s++) {
      final satellite = s.isEven;
      c.onPositionFix(
        satellite
            ? _at(s.toDouble(), northM: 15.0 * s)
            : _at(s.toDouble(), northM: 15.0 * s, eastM: 300, acc: 400),
        now: _at(s.toDouble()).timestamp,
      );
      expect(
        c.gpsTrustVerdict!.acting,
        satellite ? TrustSignal.trusted : TrustSignal.suspect,
        reason: 'fix $s (${satellite ? 'satellite' : 'network'})',
      );
    }
  });

  test(
      'the gates kept in shadow change nothing she is shown: a 40 m multipath '
      'onset is trusted, and only the shadow verdict says otherwise', () {
    final c = DriveHudController(
        actuators: FakeAlertActuators(), localeTag: 'ja');
    _anchor(c, _at(0), _at(1, northM: 15));
    for (var s = 2; s <= 5; s++) {
      c.onPositionFix(_at(s.toDouble(), northM: 15.0 * s),
          now: _at(s.toDouble()).timestamp);
    }
    c.onPositionFix(_at(6, northM: 90, eastM: 40, acc: 8),
        now: _at(6).timestamp);
    expect(c.gpsTrustVerdict!.acting, TrustSignal.trusted,
        reason: 'the acceleration gate is in shadow until plan F passes');
    expect(c.estimate!.mode, LocalizationMode.gpsTrusted);
    expect(c.shadowGpsTrust, isNot(TrustSignal.trusted));
  });

  test(
      'the development page\'s test position is the only fix that skips the '
      'verdict, and the app calls it from one place: its mock control', () {
    final mainCode =
        dartCodeOnly(File('lib/main.dart').readAsStringSync());
    final calls = RegExp(r'\.onTestPosition\(').allMatches(mainCode).toList();
    expect(calls, hasLength(1), reason: 'one call in main.dart');
    final mock = mainCode.indexOf('void _useMockPosition()');
    expect(mock, greaterThanOrEqualTo(0), reason: 'control: the mock control');
    final open = mainCode.indexOf('{', mock);
    final end = closingBracketEnd(mainCode, open)!;
    expect(calls.single.start, inInclusiveRange(open, end),
        reason: 'the call sits inside _useMockPosition');
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final code = dartCodeOnly(f.readAsStringSync());
      final n = RegExp(r'onTestPosition\(').allMatches(code).length;
      if (f.path.endsWith('main.dart')) continue;
      final allowed = f.path.endsWith('drive_hud_controller.dart') ||
          f.path.endsWith('drive_safety_fusion.dart');
      expect(n == 0 || allowed, isTrue,
          reason: '${f.path} calls onTestPosition');
    }
  });
}

/// position_integrity's monitor, throwing on every fix.
class _ThrowingMonitor extends pi.PositionIntegrityMonitor {
  @override
  pi.IntegrityVerdict update(pi.PositionFix fix, {Duration? deadReckoningAge}) =>
      throw StateError('monitor fault');
}
