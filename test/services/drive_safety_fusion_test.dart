/// WS6 — pure-fusion tests: the honest position seam + the compound-failure
/// caution, provable NOW off a device (no Flutter, no IO).
///
/// HER-trace: the two load-bearing honesty properties are asserted here — a
/// dropped/denied GPS fix NEVER becomes a confident dot, and a lost position at
/// the same time as low visibility raises the caution to its ceiling (the
/// compounding rule this package exists for).
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization_fallback/localization_fallback.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/services/drive_safety_fusion.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 8, 0, 0);
  PositionAvailable fix(DateTime t, {double acc = 15}) => PositionAvailable(
        latitude: 39.72,
        longitude: 140.10,
        accuracyMeters: acc,
        timestamp: t,
      );

  group('positionTrustFromMode — the one seam mapping', () {
    test('maps every honest mode to its trust mirror', () {
      expect(positionTrustFromMode(LocalizationMode.gpsTrusted),
          PositionTrust.trusted);
      expect(positionTrustFromMode(LocalizationMode.gpsSuspect),
          PositionTrust.suspect);
      expect(positionTrustFromMode(LocalizationMode.deadReckoning),
          PositionTrust.degraded);
      expect(positionTrustFromMode(LocalizationMode.lost), PositionTrust.lost);
    });
  });

  group('DriveLocalizer.onPositionFix — honest position, never a wrong dot', () {
    test('a trusted PositionAvailable → gpsTrusted, confident, plottable', () {
      final loc = DriveLocalizer();
      final e = loc.onPositionFix(fix(t0), t0);
      expect(e.mode, LocalizationMode.gpsTrusted);
      expect(e.isConfident, isTrue);
      expect(e.hasPosition, isTrue);
    });

    test('PositionUnavailable before any fix → lost, NO position, not confident',
        () {
      final loc = DriveLocalizer();
      final e = loc.onPositionFix(const PositionUnavailable('denied'), t0);
      expect(e.mode, LocalizationMode.lost);
      // Bootstrap "nothing seen yet": NaN coords — must NOT be plotted.
      expect(e.hasPosition, isFalse);
      expect(e.isConfident, isFalse);
    });

    test(
        'trusted fix then PositionUnavailable 200 s later (revoked mid-drive) → '
        'lost, held last-known, never confident', () {
      final loc = DriveLocalizer();
      loc.onPositionFix(fix(t0), t0);
      final e = loc.onPositionFix(
        const PositionUnavailable('revoked'),
        t0.add(const Duration(seconds: 200)),
      );
      // 200 s > maxDeadReckoning 120 s → honestly lost.
      expect(e.mode, LocalizationMode.lost);
      expect(e.isConfident, isFalse);
      // Still holds the last-known position (not NaN) — an honest guess, not a
      // blank; but flagged lost so the app never presents it as confident.
      expect(e.hasPosition, isTrue);
    });

    test('a blackout poll grows the confidence radius (never shrinks)', () {
      final loc = DriveLocalizer();
      loc.onPositionFix(fix(t0, acc: 20), t0);
      final r30 = loc.poll(t0.add(const Duration(seconds: 30)))
          .confidenceRadiusMeters;
      final r90 = loc.poll(t0.add(const Duration(seconds: 90)))
          .confidenceRadiusMeters;
      expect(r90, greaterThan(r30));
    });
  });

  group('adviseFromEstimate — the compound-failure caution', () {
    test('lost position + whiteout visibility TOGETHER → considerStopping '
        '(compounding)', () {
      const est = LocalizationEstimate(
        latitude: 39.72,
        longitude: 140.10,
        confidenceRadiusMeters: 400,
        mode: LocalizationMode.lost,
        secondsSinceTrustedFix: 200,
        basis: EstimateBasis.lastKnownPosition,
      );
      final advice = adviseFromEstimate(
        est,
        visibilityMeters: 100, // whiteout band
        visibilityAgeSeconds: 0,
      );
      expect(advice.action, DriveAction.considerStopping);
      expect(advice.compounding, isTrue);
      expect(advice.positionUncertain, isTrue);
      expect(advice.reasons, contains(CautionReason.positionUncertain));
      expect(advice.reasons, contains(CautionReason.lowVisibility));
    });

    test('trusted position + clear visibility → continueDriving, no compounding',
        () {
      const est = LocalizationEstimate(
        latitude: 39.72,
        longitude: 140.10,
        confidenceRadiusMeters: 15,
        mode: LocalizationMode.gpsTrusted,
        secondsSinceTrustedFix: 0,
        basis: EstimateBasis.trustedGpsFix,
      );
      final advice = adviseFromEstimate(
        est,
        visibilityMeters: 1500,
        visibilityAgeSeconds: 0,
      );
      expect(advice.action, DriveAction.continueDriving);
      expect(advice.compounding, isFalse);
    });

    test('the ceiling is considerStopping — there is structurally no turn-back',
        () {
      // Every DriveAction the fusion can emit is one of the three advisory
      // rungs; there is no "abort / turn back" rung to reach.
      expect(DriveAction.values, [
        DriveAction.continueDriving,
        DriveAction.heightenedCaution,
        DriveAction.considerStopping,
      ]);
    });
  });
}
