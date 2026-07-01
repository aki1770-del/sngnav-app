/// WS6 — the escalation → announce path, with a recording fake actuator.
///
/// HER-trace: this proves the caution actually REACHES the actuator seam — a
/// rising rung speaks the correct Japanese guidance AND fires the haptic, ONCE
/// per rung rise (no nag), on the SINGLE injected actuator. It does NOT prove
/// she HEARS / FEELS it — that is on-device verification, DEFERRED
/// (docs/DEVICE_VERIFICATION.md, OPS-066 / AAE-1).
///
/// The announce is fired fire-and-forget (`unawaited`) inside the controller,
/// so each test settles the event queue before asserting on the fake channels.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization_fallback/localization_fallback.dart'
    show LocalizationMode;
import 'package:navigation_safety_enums/navigation_safety_enums.dart'
    show HapticCuePattern;
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/services/drive_hud_controller.dart';

import '../support/fake_alert_actuators.dart';

/// Drain pending microtasks so the fire-and-forget announce (speak → haptic)
/// completes before we read the fake actuator's recordings.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 8, 0, 0);
  PositionAvailable fix(DateTime t, {double acc = 20}) => PositionAvailable(
        latitude: 39.72,
        longitude: 140.10,
        accuracyMeters: acc,
        timestamp: t,
      );

  DriveHudController controllerWith(FakeAlertActuators fake) =>
      DriveHudController(actuators: fake, localeTag: 'ja');

  test(
      'rung rise (heightened → considerStopping) speaks JA + fires haptic, '
      'ONCE per rise', () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake);

    // Low visibility (300 m), no advisory, speed unknown.
    c.updateEnvironment(
      visibilityMeters: 300,
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
    );

    // Trusted position (pc 0) + low vis (vc 2) → heightenedCaution.
    c.onPositionFix(fix(t0), now: t0);
    await settle();
    expect(c.advice!.action, DriveAction.heightenedCaution);
    // AUDIO: the JA guidance, at the normalized ja-JP voice tag.
    expect(fake.spoken, hasLength(1));
    expect(fake.spoken.single.localeTag, 'ja-JP');
    expect(fake.spoken.single.text, contains('速度'));
    // HAPTIC: the deaf / can't-hear-over-the-wind driver gets the same warning.
    expect(fake.haptics, [HapticCuePattern.warning]);

    // Same rung again (fresh fix, same env) → NO new announce (de-dup / no nag).
    c.onPositionFix(fix(t0.add(const Duration(seconds: 5))),
        now: t0.add(const Duration(seconds: 5)));
    await settle();
    expect(c.advice!.action, DriveAction.heightenedCaution);
    expect(fake.spoken, hasLength(1));
    expect(fake.haptics, hasLength(1));

    // GPS blackout: poll 300 s out → dot degrades to lost (pc 3); vis still low
    // (vc 2) → compounding → considerStopping (rung RISES) → re-announce.
    c.poll(now: t0.add(const Duration(seconds: 300)));
    await settle();
    expect(c.advice!.action, DriveAction.considerStopping);
    expect(c.advice!.compounding, isTrue);
    expect(fake.spoken, hasLength(2));
    expect(fake.spoken.last.text, contains('停車'));
    expect(fake.haptics, [HapticCuePattern.warning, HapticCuePattern.critical]);
  });

  test('clear visibility + trusted position → continue, nothing announced',
      () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake);
    c.updateEnvironment(
      visibilityMeters: 1500,
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
    );
    c.onPositionFix(fix(t0), now: t0);
    await settle();
    expect(c.advice!.action, DriveAction.continueDriving);
    expect(fake.spoken, isEmpty);
    expect(fake.haptics, isEmpty);
  });

  test(
      'PositionUnavailable (revoked mid-drive) degrades toward lost — never a '
      'confident dot — and raises the compound caution', () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake);
    c.updateEnvironment(
      visibilityMeters: 300,
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
    );
    c.onPositionFix(fix(t0), now: t0); // trusted baseline
    // Permission revoked 200 s later → PositionUnavailable → honest degrade.
    c.onPositionFix(const PositionUnavailable('revoked'),
        now: t0.add(const Duration(seconds: 200)));
    await settle();
    expect(c.estimate!.mode, LocalizationMode.lost);
    expect(c.estimate!.isConfident, isFalse);
    expect(c.advice!.action, DriveAction.considerStopping);
  });

  test('the controller NEVER touches the wakelock (the app is the single owner)',
      () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake);
    c.updateEnvironment(
      visibilityMeters: 300,
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
    );
    c.onPositionFix(fix(t0), now: t0);
    await settle();
    // WS6 announces through the injected actuator, but the wakelock is owned by
    // the app (main.dart) on that SAME single actuator — the controller must
    // not be a second keep-awake owner.
    expect(fake.keepAwakeCalls, isEmpty);
  });
}
