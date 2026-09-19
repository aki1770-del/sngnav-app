/// The position mapping the app runs is the mapping a render review drew.
///
/// Why this test exists. That review's lost-mode harness (kept outside this
/// repository) renders
/// [AkitaMap] from a REPLICA of the candidate mapping, its `_Cand` class,
/// because the app's mapping was private to its State. A replica is a
/// description: its frames prove nothing about the app unless the app computes
/// the same inputs. So this test builds the review's six scenarios through the real
/// [DriveHudController] and [fixFromSample], exactly as the harness's `_cands()`
/// does, and requires [herMapInputs] to equal the harness's rule.
///
/// It also pins what the harness does not model: stopping the feed, the dev
/// mock, and a sample the controller refuses after a trusted fix.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:localization_fallback/localization_fallback.dart';
import 'package:sngnav_app/akita_map.dart' show akitaStation;
import 'package:sngnav_app/her_map_inputs.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/services/drive_hud_controller.dart';

import 'support/fake_alert_actuators.dart';

// The harness's constants, verbatim.
final _t0 = DateTime.utc(2026, 1, 14, 21, 0);
const _her = LatLng(39.7195, 140.1180);

DriveHudController _hud() =>
    DriveHudController(actuators: FakeAlertActuators(), localeTag: 'ja');

PositionFix _sample(double acc, {LatLng at = _her, DateTime? t}) =>
    fixFromSample(
      latitude: at.latitude,
      longitude: at.longitude,
      accuracyMeters: acc,
      timestamp: t ?? _t0,
    );

class _Scenario {
  _Scenario(this.id, this.herFix, this.hud);
  final String id;
  final PositionFix? herFix;
  final DriveHudController hud;
}

/// The review harness's `_cands()`, the same event sequences in the same order.
List<_Scenario> _hieScenarios() {
  _Scenario drought(String id, Duration d) {
    final h = _hud();
    final fix = _sample(15);
    h.onPositionFix(fix, now: _t0);
    h.poll(now: _t0.add(d));
    return _Scenario(id, fix, h);
  }

  _Scenario streamError(String id, Duration d) {
    final h = _hud();
    h.onPositionFix(_sample(15), now: _t0);
    const u = PositionUnavailable('GPS stream error');
    h.onPositionFix(u, now: _t0.add(d));
    return _Scenario(id, u, h);
  }

  final never = _hud();
  final bad = _sample(-1);
  never.onPositionFix(bad, now: _t0);

  return [
    drought('c1_dead_reckoning_60s', const Duration(seconds: 60)),
    drought('c2_lost_180s', const Duration(seconds: 180)),
    drought('c3_lost_90min', const Duration(minutes: 90)),
    _Scenario('c4_lost_never_trusted', bad, never),
    streamError('c5_stream_error_5s', const Duration(seconds: 5)),
    streamError('c6_stream_error_10min', const Duration(minutes: 10)),
  ];
}

/// The harness's `_Cand.her` / `_Cand.accuracy` / render flags, restated.
/// The harness passes `degraded: deadReckoning` and `lost: lost`.
({LatLng? her, double? accuracy, bool deadReckoning, bool lost}) _hieRule(
    _Scenario s) {
  final e = s.hud.estimate;
  final lost = e?.mode == LocalizationMode.lost;
  final deadReckoning = e?.mode == LocalizationMode.deadReckoning;
  final LatLng? her;
  if ((lost || deadReckoning) && e != null) {
    her = e.latitude.isFinite && e.longitude.isFinite
        ? LatLng(e.latitude, e.longitude)
        : null;
  } else {
    her = switch (s.herFix) {
      PositionAvailable(:final latitude, :final longitude) =>
        LatLng(latitude, longitude),
      _ => null,
    };
  }
  final double? accuracy;
  if ((deadReckoning || lost) && e != null) {
    accuracy = e.confidenceRadiusMeters;
  } else {
    accuracy = switch (s.herFix) {
      PositionAvailable(:final accuracyMeters) => accuracyMeters,
      _ => null,
    };
  }
  return (
    her: her,
    accuracy: accuracy,
    deadReckoning: deadReckoning,
    lost: lost,
  );
}

/// What `main.dart` passed the map at bd6ebc4 (`herPosition` from `_herFix`,
/// `_herMapAccuracyMeters`, `_herPositionDegraded`), for the unchanged states.
({LatLng? her, double? accuracy, bool degraded}) _bd6ebc4Rule(
  PositionFix? fix,
  DriveHudController hud, {
  bool isMock = false,
}) {
  final fixAccuracy = switch (fix) {
    PositionAvailable(:final accuracyMeters) => accuracyMeters,
    _ => null,
  };
  final degraded = !isMock && hud.positionUnlocatable;
  return (
    her: switch (fix) {
      PositionAvailable(:final latitude, :final longitude) =>
        LatLng(latitude, longitude),
      _ => null,
    },
    accuracy: degraded
        ? (hud.estimate?.confidenceRadiusMeters ?? fixAccuracy)
        : fixAccuracy,
    degraded: degraded,
  );
}

HerMapInputs _app(_Scenario s, {bool isMock = false}) =>
    herMapInputs(
        fix: s.herFix,
        estimate: s.hud.estimate,
        isMock: isMock,
        anchoredThisSession: true);

void main() {
  group('herMapInputs equals the reviewed candidate mapping on its scenarios', () {
    for (final s in _hieScenarios()) {
      test(s.id, () {
        final app = _app(s);
        final hie = _hieRule(s);
        expect(app.position, hie.her, reason: 'position');
        expect(app.lost, hie.lost, reason: 'lost');
        // The widget draws the hollow ring for `positionDegraded ||
        // positionLost`. The harness passes degraded for dead reckoning only;
        // the app passes it for dead reckoning OR lost, which is the widget's
        // documented contract and what main.dart passed at bd6ebc4. In lost
        // the only other reader of `positionDegraded`, the circle, is not
        // built, so the ring state is the comparison that decides the frame.
        expect(app.degraded || app.lost, hie.deadReckoning || hie.lost,
            reason: 'ring state');
        if (!app.lost) {
          expect(app.accuracyMeters, hie.accuracy, reason: 'circle radius');
        }
      });
    }
  });

  group('what each scenario hands the map', () {
    final byId = {for (final s in _hieScenarios()) s.id: s};

    test('dead reckoning 60 s: ring at her last trusted point, 135 m circle, '
        'not lost — the same inputs main.dart passed at bd6ebc4', () {
      final s = byId['c1_dead_reckoning_60s']!;
      final app = _app(s);
      expect(app.position, _her);
      expect(app.accuracyMeters, 135);
      expect(app.degraded, isTrue);
      expect(app.lost, isFalse);
      final old = _bd6ebc4Rule(s.herFix, s.hud);
      expect(app.position, old.her);
      expect(app.accuracyMeters, old.accuracy);
      expect(app.degraded, old.degraded);
    });

    test('lost 90 min: still marked at the last trusted point, and lost', () {
      final app = _app(byId['c3_lost_90min']!);
      expect(app.position, _her);
      expect(app.lost, isTrue);
      expect(app.accuracyMeters, 10815,
          reason: 'handed over, and never drawn: the map draws no circle '
              'in lost');
    });

    test('never trusted: no position mark at the refused sample, and lost',
        () {
      final app = _app(byId['c4_lost_never_trusted']!);
      expect(app.position, isNull);
      expect(app.lost, isTrue);
      expect(app.accuracyMeters, double.infinity);
    });

    test('stream error 5 s after a trusted fix: the map is NOT empty — the '
        'ring stays at the last trusted point', () {
      final s = byId['c5_stream_error_5s']!;
      expect(s.herFix, isA<PositionUnavailable>());
      final app = _app(s);
      expect(app.position, _her);
      expect(app.degraded, isTrue);
      expect(app.lost, isFalse);
      expect(_bd6ebc4Rule(s.herFix, s.hud).her, isNull,
          reason: 'control: at bd6ebc4 this state drew nothing — if this '
              'fails, the scenario no longer reaches the defect');
    });

    test('stream error 10 min after a trusted fix: lost, still marked', () {
      final app = _app(byId['c6_stream_error_10min']!);
      expect(app.position, _her);
      expect(app.lost, isTrue);
    });
  });

  group('states the harness does not model', () {
    test('no event this session (stopped, or not yet shared): nothing, even '
        'while the controller still holds a lost estimate', () {
      final h = _hud();
      h.onPositionFix(_sample(15), now: _t0);
      h.poll(now: _t0.add(const Duration(minutes: 90)));
      expect(h.estimate!.mode, LocalizationMode.lost,
          reason: 'control: the controller really is lost here');

      final app = herMapInputs(
          fix: null,
          estimate: h.estimate,
          isMock: false,
          anchoredThisSession: true);
      expect(app.position, isNull);
      expect(app.accuracyMeters, isNull);
      expect(app.degraded, isFalse);
      expect(app.lost, isFalse,
          reason: 'a feed she turned off makes no claim about where she is');
    });

    test('mock: the mock point, never degraded or lost, even after the demo '
        'blackout degraded the controller', () {
      final h = _hud();
      final mock = PositionAvailable(
        latitude: akitaStation.latitude,
        longitude: akitaStation.longitude,
        accuracyMeters: 35,
        timestamp: _t0,
      );
      h.onPositionFix(mock, now: _t0);
      h.poll(now: _t0.add(const Duration(minutes: 3)));
      expect(h.estimate!.mode, LocalizationMode.lost);

      final app = herMapInputs(
          fix: mock,
          estimate: h.estimate,
          isMock: true,
          anchoredThisSession: false);
      expect(app.position, akitaStation);
      expect(app.accuracyMeters, 35);
      expect(app.degraded, isFalse);
      expect(app.lost, isFalse);
    });

    test('a real trusted fix draws where the fix is, unchanged', () {
      final h = _hud();
      final fix = _sample(15);
      h.onPositionFix(fix, now: _t0);
      final app = herMapInputs(
          fix: fix,
          estimate: h.estimate,
          isMock: false,
          anchoredThisSession: true);
      final old = _bd6ebc4Rule(fix, h);
      expect(app.position, old.her);
      expect(app.accuracyMeters, old.accuracy);
      expect(app.degraded, isFalse);
      expect(app.lost, isFalse);
    });

    test('a sample the controller refuses AFTER a trusted fix: the ring stays '
        'where the controller last trusted, not at the refused sample', () {
      final h = _hud();
      h.onPositionFix(_sample(15), now: _t0);
      final t = _t0.add(const Duration(seconds: 30));
      final refused =
          _sample(-1, at: const LatLng(39.8000, 140.3000), t: t);
      expect(refused, isA<PositionAvailable>(),
          reason: 'the chokepoint passes a finite negative accuracy');
      h.onPositionFix(refused, now: t);
      expect(h.positionUnlocatable, isTrue,
          reason: 'the controller refused it and degraded');

      final app =
          herMapInputs(
              fix: refused,
              estimate: h.estimate,
              isMock: false,
              anchoredThisSession: true);
      expect(app.position, _her);
      expect(_bd6ebc4Rule(refused, h).her, const LatLng(39.8000, 140.3000),
          reason: 'control: at bd6ebc4 the ring went to the refused sample');
    });

    test(
        'an unanchored guess — finite coordinates the controller never '
        'trusted — gets no ring either', () {
      // Not reachable through today's DriveLocalizer, which passes every fix
      // with the controller's default `trusted` verdict. Pinned because a
      // real trust verdict (position_integrity) wired later reaches it: a
      // `suspect` first fix becomes a lost estimate AT the sample's own
      // coordinates, and a check on finite coordinates alone would put the
      // ring there. Found by mutation: without this test, dropping the basis
      // check changed no test outcome.
      final controller = LocalizationController();
      final estimate = controller.onFix(
        RawFix(
          latitude: 39.8000,
          longitude: 140.3000,
          accuracyMeters: 30,
          timestamp: _t0,
        ),
        trust: TrustSignal.suspect,
      );
      expect(estimate.mode, LocalizationMode.lost, reason: 'control');
      expect(estimate.basis, EstimateBasis.unanchoredGuess, reason: 'control');
      expect(estimate.hasPosition, isTrue,
          reason: 'control: the guess carries finite coordinates');

      final app = herMapInputs(
        fix: PositionAvailable(
          latitude: 39.8000,
          longitude: 140.3000,
          accuracyMeters: 30,
          timestamp: _t0,
        ),
        estimate: estimate,
        isMock: false,
        anchoredThisSession: true,
      );
      expect(app.position, isNull);
      expect(app.lost, isTrue);
    });
  });

  // ---- 2026-09-13: an anchor must be this session's ----------------------
  //
  // The controller is not reset when she stops sharing. On a re-share with
  // location services off it degrades from the previous drive's anchor, and
  // the map drew that ring; the dev mock did the same at the station. The
  // app-level renders of those states are pinned in
  // test/widgets/her_position_session_anchor_test.dart.

  group('an anchor not set in this session draws no ring', () {
    test('lost from a previous session\'s anchor: no position, the words', () {
      final h = _hud();
      h.onPositionFix(_sample(15), now: _t0);
      const u = PositionUnavailable('Location services disabled');
      h.onPositionFix(u, now: _t0.add(const Duration(hours: 20)));
      expect(h.estimate!.mode, LocalizationMode.lost, reason: 'control');
      expect(h.estimate!.hasPosition, isTrue,
          reason: 'control: the controller still holds the old anchor');

      final app = herMapInputs(
          fix: u,
          estimate: h.estimate,
          isMock: false,
          anchoredThisSession: false);
      expect(app.position, isNull);
      expect(app.lost, isTrue);
      expect(app.accuracyMeters, isNull,
          reason: 'no radius from a feed she turned off');

      final same = herMapInputs(
          fix: u,
          estimate: h.estimate,
          isMock: false,
          anchoredThisSession: true);
      expect(same.position, _her,
          reason: 'control: the same estimate in its own session keeps the '
              'ring');
    });

    test('dead reckoning from a previous session\'s anchor: still no ring, '
        'and the words rather than silence', () {
      final h = _hud();
      h.onPositionFix(_sample(15), now: _t0);
      const u = PositionUnavailable('Location services disabled');
      h.onPositionFix(u, now: _t0.add(const Duration(seconds: 5)));
      expect(h.estimate!.mode, LocalizationMode.deadReckoning,
          reason: 'control');

      final app = herMapInputs(
          fix: u,
          estimate: h.estimate,
          isMock: false,
          anchoredThisSession: false);
      expect(app.position, isNull);
      expect(app.lost, isTrue,
          reason: 'with no ring, dead reckoning would leave the map silent');
    });

    test(
        'no trusted fix this session and an unavailability that is not a '
        'refusal: 現在地不明, even with no estimate at all (decided 2026-09-13)',
        () {
      for (final fix in const [
        PositionUnavailable('GPS stream error: platform failed'),
        PositionUnavailable('Location services disabled'),
      ]) {
        final app = herMapInputs(
            fix: fix, estimate: null, isMock: false, anchoredThisSession: false);
        expect(app.lost, isTrue, reason: '${fix.reason}: words, not silence');
        expect(app.position, isNull);
        expect(app.refused, isFalse);
      }
    });

    test('a trusted fix is drawn where it is, whatever the flag says', () {
      final h = _hud();
      final fix = _sample(15);
      h.onPositionFix(fix, now: _t0);
      final app = herMapInputs(
          fix: fix,
          estimate: h.estimate,
          isMock: false,
          anchoredThisSession: false);
      expect(app.position, _her);
      expect(app.lost, isFalse);
    });
  });

  group('anchorsThisSession: which event sets the anchor', () {
    test('a trusted fix does', () {
      final h = _hud();
      final fix = _sample(15);
      h.onPositionFix(fix, now: _t0);
      expect(anchorsThisSession(fix: fix, estimate: h.estimate, isMock: false),
          isTrue);
    });

    test('a trusted fix too imprecise to be confident is adopted, and does',
        () {
      final h = _hud();
      final fix = _sample(900);
      h.onPositionFix(fix, now: _t0);
      expect(h.estimate!.mode, LocalizationMode.lost, reason: 'control');
      expect(anchorsThisSession(fix: fix, estimate: h.estimate, isMock: false),
          isTrue);
    });

    test('a fix no newer than the anchor does not: the old anchor stays', () {
      final h = _hud();
      h.onPositionFix(_sample(15), now: _t0);
      final stale =
          _sample(15, at: const LatLng(39.7300, 140.1000), t: _t0);
      h.onPositionFix(stale, now: _t0);
      expect(h.estimate!.latitude, _her.latitude,
          reason: 'control: the controller kept the old anchor');
      expect(
          anchorsThisSession(fix: stale, estimate: h.estimate, isMock: false),
          isFalse);
    });

    test('an unavailability does not', () {
      final h = _hud();
      h.onPositionFix(_sample(15), now: _t0);
      const u = PositionUnavailable('GPS stream error');
      h.onPositionFix(u, now: _t0.add(const Duration(seconds: 5)));
      expect(anchorsThisSession(fix: u, estimate: h.estimate, isMock: false),
          isFalse);
    });

    test('a sample the controller refuses does not', () {
      final h = _hud();
      final bad = _sample(-1);
      h.onPositionFix(bad, now: _t0);
      expect(anchorsThisSession(fix: bad, estimate: h.estimate, isMock: false),
          isFalse);
    });

    test('the dev mock never does, even though the controller took it', () {
      final h = _hud();
      final mock = PositionAvailable(
        latitude: akitaStation.latitude,
        longitude: akitaStation.longitude,
        accuracyMeters: 35,
        timestamp: _t0,
      );
      h.onPositionFix(mock, now: _t0);
      expect(h.estimate!.basis, EstimateBasis.trustedGpsFix,
          reason: 'control: the controller did adopt it');
      expect(anchorsThisSession(fix: mock, estimate: h.estimate, isMock: true),
          isFalse);
    });

    test('no estimate: no', () {
      expect(
          anchorsThisSession(fix: _sample(15), estimate: null, isMock: false),
          isFalse);
    });
  });
}
