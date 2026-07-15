/// WS6+ — the measured-weather fusion into the compound caution rung.
///
/// HER-trace: a MEASURED black-ice / turmoil watch (from live JMA) must RAISE
/// the eyes-off rung she reacts to — so the banner cannot read 「走行を継続」while
/// a measured hazard is firing on-screen — AND, when the hazard cannot even be
/// located (untrusted position), compound to 「停車の検討」. The rung must NOT
/// double-speak the specific hazard line (the watch lane already speaks it), and
/// must NOT cry wolf. On-device HEAR/FEEL is DEFERRED (OPS-066 / AAE-1).
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization_fallback/localization_fallback.dart'
    show LocalizationMode;
import 'package:navigation_safety_core/navigation_safety_core.dart'
    show AlertSeverity;
import 'package:navigation_safety_enums/navigation_safety_enums.dart'
    show HapticCuePattern;
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/services/drive_hud_controller.dart';
import 'package:sngnav_app/services/measured_hazard_floor.dart';

import '../support/fake_alert_actuators.dart';

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
      'a firing measured watch RAISES the banner (continue → heightened) but is '
      'NOT spoken by the rung — the watch lane owns that line (no double-speak)',
      () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake);

    // Trusted GPS, clear visibility → the advisor alone says continue.
    c.updateEnvironment(
      visibilityMeters: 1500,
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
      measuredHazard: MeasuredWeatherHazard.blackIce,
    );
    c.onPositionFix(fix(t0), now: t0);
    await settle();

    // Advisor per-axis read is unchanged (continue), but the EFFECTIVE rung the
    // banner + severity reflect is heightened — the measured hazard raised it.
    expect(c.advice!.action, DriveAction.continueDriving);
    expect(c.effectiveAction, DriveAction.heightenedCaution);
    expect(c.currentSeverity, AlertSeverity.warning);

    // The rung did NOT speak (the invisible-ice watch lane already speaks its
    // own specific line) and did NOT double-buzz.
    expect(fake.spoken, isEmpty,
        reason: 'no generic rung line over the watch\'s specific hazard line');
    expect(fake.haptics, isEmpty);
  });

  test(
      'a measured hazard while the position is LOST compounds to considerStopping '
      '— and THAT is spoken (its invitation is additive, not a duplicate)',
      () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake);
    c.updateEnvironment(
      visibilityMeters: 1500, // clear — so the escalation is NOT from visibility
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
      measuredHazard: MeasuredWeatherHazard.blackIce,
    );
    c.onPositionFix(fix(t0), now: t0); // trusted baseline
    await settle();
    // Trusted + clear + hazard → heightened, shown-not-spoken.
    expect(c.effectiveAction, DriveAction.heightenedCaution);
    expect(fake.spoken, isEmpty);

    // GPS blackout 300 s → dot degrades to lost; a measured hazard she cannot
    // locate → considerStopping (RISES) → the calm stopping invitation speaks.
    c.poll(now: t0.add(const Duration(seconds: 300)));
    await settle();
    expect(c.estimate!.mode, LocalizationMode.lost);
    expect(c.effectiveAction, DriveAction.considerStopping);
    expect(c.currentSeverity, AlertSeverity.critical);
    expect(fake.spoken, hasLength(1));
    expect(fake.spoken.single.text, contains('停車'));
    expect(fake.haptics, [HapticCuePattern.critical]);
  });

  test('the floor NEVER lowers a rung the advisor already raised higher',
      () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake);
    // Whiteout visibility (80 m) + lost position would be considerStopping;
    // a heightened-only floor must not pull it down.
    c.updateEnvironment(
      visibilityMeters: 80,
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
      measuredHazard: MeasuredWeatherHazard.turmoil,
    );
    c.onPositionFix(fix(t0), now: t0);
    await settle();
    // pc0 + vc3 (whiteout) → advisor considerStopping already; floor (heightened,
    // trusted) does not lower it.
    expect(c.advice!.action, DriveAction.considerStopping);
    expect(c.effectiveAction, DriveAction.considerStopping);
  });

  test(
      'no cry-wolf, no regression: no measured hazard + clear + trusted stays '
      'continue and silent (measuredHazard defaults to none)', () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake);
    c.updateEnvironment(
      visibilityMeters: 1500,
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
      // measuredHazard omitted → stays none
    );
    c.onPositionFix(fix(t0), now: t0);
    await settle();
    expect(c.effectiveAction, DriveAction.continueDriving);
    expect(fake.spoken, isEmpty);
    expect(fake.haptics, isEmpty);
  });

  test(
      'a GROUNDED heightened (real low visibility) still speaks even with a '
      'measured hazard also present — the announce gate only mutes floor-only '
      'and unknown-visibility-only rises', () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake);
    c.updateEnvironment(
      visibilityMeters: 300, // real low-vis reading → grounded heightened
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
      measuredHazard: MeasuredWeatherHazard.blackIce,
    );
    c.onPositionFix(fix(t0), now: t0);
    await settle();
    expect(c.advice!.action, DriveAction.heightenedCaution);
    expect(c.effectiveAction, DriveAction.heightenedCaution);
    // Grounded by a real low-visibility reading → the rung DOES speak.
    expect(fake.spoken, hasLength(1));
    expect(fake.spoken.single.text, contains('速度'));
    expect(fake.haptics, [HapticCuePattern.warning]);
  });

  test(
      'MUST (OPS-068): a MUTED floor-only rise does NOT swallow a later GROUNDED '
      'caution at the same rung — it still speaks + buzzes', () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake);
    // Cycle 1: firing black-ice, trusted, clear → effective heightened, MUTED
    // (advisor alone = continue; the watch lane owns the spoken line).
    c.updateEnvironment(
      visibilityMeters: 1500,
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
      measuredHazard: MeasuredWeatherHazard.blackIce,
    );
    c.onPositionFix(fix(t0), now: t0);
    await settle();
    expect(c.effectiveAction, DriveAction.heightenedCaution);
    expect(fake.spoken, isEmpty);
    expect(fake.haptics, isEmpty);

    // Cycle 2: a real MODERATE area advisory now GROUNDS the same heightened
    // rung. Before the fix the muted rise had advanced the announce tracker, so
    // this reached neither audio nor the OPS-059 haptic. It MUST speak now.
    c.updateEnvironment(
      visibilityMeters: 1500,
      visibilityAgeSeconds: 0,
      advisorySeverity: AdvisoryLevel.moderate,
      speedMetersPerSecond: null,
      measuredHazard: MeasuredWeatherHazard.blackIce,
    );
    await settle();
    expect(c.advice!.action, DriveAction.heightenedCaution);
    expect(fake.spoken, hasLength(1),
        reason: 'the grounded caution must reach the voice — the muted floor '
            'must not have consumed the announce slot');
    expect(fake.haptics, [HapticCuePattern.warning]);
  });

  test('de-escalation: clearing the measured hazard drops the rung back — the '
      'floor is not latched', () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake);
    c.updateEnvironment(
      visibilityMeters: 1500,
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
      measuredHazard: MeasuredWeatherHazard.blackIce,
    );
    c.onPositionFix(fix(t0), now: t0);
    await settle();
    expect(c.effectiveAction, DriveAction.heightenedCaution);
    // The JMA watch turns OFF.
    c.updateEnvironment(
      visibilityMeters: 1500,
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
      measuredHazard: MeasuredWeatherHazard.none,
    );
    await settle();
    expect(c.effectiveAction, DriveAction.continueDriving);
  });

  test(
      'immediate-recompute: setting the measured hazard via updateEnvironment '
      'raises the rung with NO new position fix', () async {
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
    expect(c.effectiveAction, DriveAction.continueDriving);
    // A JMA reading turns the watch ON — pushed via updateEnvironment, no fix.
    c.updateEnvironment(
      visibilityMeters: 1500,
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
      measuredHazard: MeasuredWeatherHazard.blackIce,
    );
    await settle();
    expect(c.effectiveAction, DriveAction.heightenedCaution);
  });

  test(
      'unknown visibility ALONE is shown (heightened) but SILENT; a moderate '
      'advisory then grounds it and it SPEAKS', () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake);
    // null visibility, no hazard, no advisory, trusted → advisor heightened via
    // the unknown-visibility floor → MUTED (no cry-wolf).
    c.updateEnvironment(
      visibilityMeters: null,
      visibilityAgeSeconds: null,
      advisorySeverity: null,
      speedMetersPerSecond: null,
    );
    c.onPositionFix(fix(t0), now: t0);
    await settle();
    expect(c.advice!.action, DriveAction.heightenedCaution);
    expect(c.effectiveAction, DriveAction.heightenedCaution);
    expect(fake.spoken, isEmpty,
        reason: 'unknown-visibility-only must never blare on a sensorless drive');
    // A real moderate advisory now grounds the same rung → SPEAK.
    c.updateEnvironment(
      visibilityMeters: null,
      visibilityAgeSeconds: null,
      advisorySeverity: AdvisoryLevel.moderate,
      speedMetersPerSecond: null,
    );
    await settle();
    expect(fake.spoken, hasLength(1));
    expect(fake.haptics, [HapticCuePattern.warning]);
  });

  test(
      'NON-VACUOUS compound: dead-reckoning (advisor = heightened) + a measured '
      'hazard → the FLOOR lifts it to considerStopping', () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake);
    c.updateEnvironment(
      visibilityMeters: 1500, // clear — so the escalation is NOT visibility
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
      measuredHazard: MeasuredWeatherHazard.blackIce,
    );
    c.onPositionFix(fix(t0), now: t0); // trusted baseline
    // Short blackout → dead-reckoning (NOT yet lost): the advisor alone is
    // heightened (degraded position, clear vis), so considerStopping here can
    // ONLY come from the compound floor — the assertion the vacuous LOST case
    // could not make.
    c.poll(now: t0.add(const Duration(seconds: 45)));
    await settle();
    expect(c.estimate!.mode, LocalizationMode.deadReckoning);
    expect(c.advice!.action, DriveAction.heightenedCaution);
    expect(c.effectiveAction, DriveAction.considerStopping);
  });
}
