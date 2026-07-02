/// (e) End-to-end: the confidence gate wired through the LIVE DriveHudController
/// and its SINGLE announcer, with a recording fake actuator.
///
/// This proves the gate reaches the actuator seam correctly:
///   - a TRUSTED dot speaks the JA turn on audio + haptic;
///   - a LOST dot SUPPRESSES — the announcer is NOT fired for the maneuver, so
///     no "turn now" is ever spoken against a position we do not trust;
///   - with no position fed yet, the fail-safe is SUPPRESS.
/// It does NOT prove HER hears/feels it — device-observable, DEFERRED (OPS-066).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:navigation_safety_enums/navigation_safety_enums.dart'
    show HapticCuePattern;
import 'package:routing_engine/routing_engine.dart' show RouteManeuver;
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/services/drive_hud_controller.dart';
import 'package:sngnav_app/services/maneuver_narration.dart';

import '../support/fake_alert_actuators.dart';

/// Drain the fire-and-forget announce (haptic → speak) before reading the fake.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 8, 0, 0);

  PositionAvailable fix(DateTime t, {double acc = 20}) => PositionAvailable(
        latitude: 39.72,
        longitude: 140.10,
        accuracyMeters: acc,
        timestamp: t,
      );

  RouteManeuver rightTurn() => const RouteManeuver(
        index: 1,
        instruction: 'Right onto Main St',
        type: 'right',
        lengthKm: 0.4,
        timeSeconds: 30,
        position: LatLng(39.72, 140.10),
      );

  DriveHudController controllerWith(FakeAlertActuators fake) =>
      DriveHudController(actuators: fake, localeTag: 'ja');

  // Good visibility + no advisory keeps the caution rung at `continueDriving`,
  // so the ONLY thing the announcer speaks is the maneuver — no caution noise.
  void clearEnvironment(DriveHudController c) => c.updateEnvironment(
        visibilityMeters: 10000,
        visibilityAgeSeconds: 0,
        advisorySeverity: null,
        speedMetersPerSecond: null,
      );

  test('no position fed yet → SUPPRESS (fail-safe), announcer NOT fired',
      () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake);

    final d = c.narrateNextManeuver(rightTurn(), icyTurn: false);
    await settle();

    expect(d.confidence, NarrationConfidence.suppressed);
    expect(d.shouldAnnounce, isFalse);
    expect(fake.spoken, isEmpty);
    expect(fake.haptics, isEmpty);
  });

  test('gpsTrusted → SPEAK the JA turn on audio + haptic', () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake);
    clearEnvironment(c);

    // A fresh accurate fix → gpsTrusted; good vis → no caution auto-announce.
    c.onPositionFix(fix(t0), now: t0);
    await settle();
    expect(fake.spoken, isEmpty, reason: 'no caution noise before we narrate');

    final d = c.narrateNextManeuver(rightTurn(), icyTurn: false);
    await settle();

    expect(d.confidence, NarrationConfidence.speak);
    expect(d.shouldAnnounce, isTrue);
    expect(fake.spoken, hasLength(1));
    expect(fake.spoken.single.text, contains('右折'));
    expect(fake.spoken.single.localeTag, 'ja-JP');
    expect(fake.haptics, [HapticCuePattern.warning]);
  });

  test('LOST → SUPPRESS: the maneuver announcer is NOT fired, no turn spoken',
      () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake);
    clearEnvironment(c);

    c.onPositionFix(fix(t0), now: t0);
    // GPS blackout: poll 300 s out with no fresh fix → mode degrades to `lost`.
    c.poll(now: t0.add(const Duration(seconds: 300)));
    await settle();
    // A caution about the uncertain position may have auto-announced, but it is
    // NEVER a turn — snapshot how many lines exist before we try to narrate.
    final beforeSpoken = fake.spoken.length;

    final d = c.narrateNextManeuver(rightTurn(), icyTurn: false);
    await settle();

    expect(d.confidence, NarrationConfidence.suppressed);
    expect(d.shouldAnnounce, isFalse);
    expect(d.text, isEmpty);
    // The maneuver added NOTHING to the audio channel.
    expect(fake.spoken.length, beforeSpoken);
    // And NO line anywhere is the turn — the confidently-wrong instruction is
    // absent, not merely deprioritized.
    expect(fake.spoken.any((s) => s.text.contains('右折')), isFalse);
  });

  test('gpsTrusted + icy coincidence → coupled advisory at CRITICAL haptic',
      () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake);
    clearEnvironment(c);

    c.onPositionFix(fix(t0), now: t0);
    await settle();

    final d = c.narrateNextManeuver(rightTurn(), icyTurn: true);
    await settle();

    expect(d.icyCoupled, isTrue);
    expect(fake.spoken.single.text, contains('凍結'));
    expect(fake.haptics, [HapticCuePattern.critical]);
  });

  test('previewNextManeuver reflects the gate WITHOUT firing the announcer',
      () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake);
    clearEnvironment(c);

    c.onPositionFix(fix(t0), now: t0);
    await settle();

    final preview = c.previewNextManeuver(rightTurn(), icyTurn: false);
    await settle();

    expect(preview.confidence, NarrationConfidence.speak);
    expect(preview.text, contains('右折'));
    // No side effect: the preview did not speak.
    expect(fake.spoken, isEmpty);
  });
}
