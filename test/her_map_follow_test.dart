/// The follow rules, as the app runs them (`lib/her_map_follow.dart`).
///
/// The app-level behaviour is pinned in `test/widgets/her_map_follow_test.dart`.
/// This pins what a real drive cannot show: while the camera follows, the ring
/// in dead reckoning sits where the camera already is, so a camera that moved
/// on dead reckoning would look identical there. The rule must hold anyway,
/// because a dead-reckoning source that moves the ring is the next thing to be
/// wired.
library;

import 'package:flutter_map/flutter_map.dart' show MapEventSource;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:localization_fallback/localization_fallback.dart';
import 'package:sngnav_app/her_map_follow.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/services/drive_hud_controller.dart';

import 'support/fake_alert_actuators.dart';

final _t0 = DateTime.utc(2026, 1, 14, 21, 0);
const _her = LatLng(39.6714637, 140.1586867);

DriveHudController _hud() =>
    DriveHudController(actuators: FakeAlertActuators(), localeTag: 'ja');

PositionAvailable _fix(double acc, {LatLng at = _her, DateTime? t}) =>
    PositionAvailable(
      latitude: at.latitude,
      longitude: at.longitude,
      accuracyMeters: acc,
      timestamp: t ?? _t0,
    );

void main() {
  group('followTargetAfter: trusted fixes only', () {
    test('a trusted fix: the camera goes to it', () {
      final h = _hud();
      final f = _fix(15);
      h.onPositionFix(f, now: _t0);
      expect(followTargetAfter(fix: f, estimate: h.estimate, isMock: false),
          _her);
    });

    test('dead reckoning: holds', () {
      final h = _hud();
      h.onPositionFix(_fix(15), now: _t0);
      const u = PositionUnavailable('GPS stream error');
      h.onPositionFix(u, now: _t0.add(const Duration(seconds: 30)));
      expect(h.estimate!.mode, LocalizationMode.deadReckoning,
          reason: 'control');
      expect(h.estimate!.hasPosition, isTrue,
          reason: 'control: there is a position it could have moved to');
      expect(followTargetAfter(fix: u, estimate: h.estimate, isMock: false),
          isNull);
    });

    test('lost: holds', () {
      final h = _hud();
      h.onPositionFix(_fix(15), now: _t0);
      const u = PositionUnavailable('GPS stream error');
      h.onPositionFix(u, now: _t0.add(const Duration(minutes: 5)));
      expect(h.estimate!.mode, LocalizationMode.lost, reason: 'control');
      expect(followTargetAfter(fix: u, estimate: h.estimate, isMock: false),
          isNull);
    });

    test('a trusted fix too imprecise to be confident (lost on arrival): holds',
        () {
      final h = _hud();
      final f = _fix(900);
      h.onPositionFix(f, now: _t0);
      expect(h.estimate!.mode, LocalizationMode.lost, reason: 'control');
      expect(followTargetAfter(fix: f, estimate: h.estimate, isMock: false),
          isNull);
    });

    test('a fix no newer than the anchor (the old anchor stays): holds', () {
      final h = _hud();
      h.onPositionFix(_fix(15), now: _t0);
      final stale = _fix(15, at: const LatLng(39.70, 140.20), t: _t0);
      h.onPositionFix(stale, now: _t0);
      expect(
          followTargetAfter(fix: stale, estimate: h.estimate, isMock: false),
          isNull);
    });

    test('a refused sample: holds', () {
      final h = _hud();
      final bad = _fix(-1);
      h.onPositionFix(bad, now: _t0);
      expect(followTargetAfter(fix: bad, estimate: h.estimate, isMock: false),
          isNull);
    });

    test('the dev mock: holds, even though the controller trusts it', () {
      final h = _hud();
      final mock = _fix(35);
      h.onPositionFix(mock, now: _t0);
      expect(h.estimate!.mode, LocalizationMode.gpsTrusted, reason: 'control');
      expect(followTargetAfter(fix: mock, estimate: h.estimate, isMock: true),
          isNull);
    });

    test('no estimate: holds', () {
      expect(
          followTargetAfter(fix: _fix(15), estimate: null, isMock: false),
          isNull);
    });
  });

  group('followZoom: inside the offline archive', () {
    test('z12 stays z12; zooms inside z8 to z12 are hers and unchanged', () {
      for (final z in [8.0, 9.5, 11.0, 12.0]) {
        expect(followZoom(z), z);
      }
    });

    test('above z12 comes back to z12, below z8 to z8', () {
      expect(followZoom(12.5), 12);
      expect(followZoom(18), 12);
      expect(followZoom(7.99), 8);
      expect(followZoom(5), 8);
    });

    test('a non-finite zoom is not handed to the camera', () {
      expect(followZoom(double.nan), 12);
      expect(followZoom(double.infinity), 12);
    });
  });

  group('isHandMovingMap', () {
    const hands = {
      MapEventSource.dragStart,
      MapEventSource.onDrag,
      MapEventSource.dragEnd,
      MapEventSource.flingAnimationController,
      MapEventSource.multiFingerGestureStart,
      MapEventSource.onMultiFinger,
      MapEventSource.multiFingerEnd,
      MapEventSource.doubleTap,
      MapEventSource.doubleTapHold,
      MapEventSource.doubleTapZoomAnimationController,
      MapEventSource.scrollWheel,
      MapEventSource.cursorKeyboardRotation,
      MapEventSource.keyboard,
    };

    test('every source is decided, and only hands that move the map pause', () {
      for (final s in MapEventSource.values) {
        expect(isHandMovingMap(s), hands.contains(s), reason: s.name);
      }
    });

    test('the camera\'s own moves never pause it', () {
      expect(isHandMovingMap(MapEventSource.mapController), isFalse);
      expect(isHandMovingMap(MapEventSource.nonRotatedSizeChange), isFalse);
    });

    test('a tap sets a route point and does not take the camera', () {
      expect(isHandMovingMap(MapEventSource.tap), isFalse);
      expect(isHandMovingMap(MapEventSource.longPress), isFalse);
    });
  });
}
