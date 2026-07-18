/// #1≡#4 (HER-POV assessment 2026-07-18) — the silent-GPS-blackout bug.
///
/// On a silent drought (the raw geolocator stream stops emitting — no error,
/// no done) the last `_herFix` in main.dart still holds a confident point, so
/// the MAP DOT + 「現在地 ±Xm」 status line — the surface HER eyes snap to — kept
/// painting a confident "you are here" on a road she passed minutes ago, while
/// only the HUD *text* degraded. This is a false-confident wrong answer on the
/// exact compound-failure design target (whiteout, GPS blind).
///
/// The fix couples the map dot + status line to
/// [DriveHudController.positionUnlocatable] — the SAME honest signal the
/// maneuver-narration suppression contract uses. This test proves that signal
/// is correct: FALSE while trusted, TRUE after a silent drought.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:localization_fallback/localization_fallback.dart'
    show LocalizationMode;
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/services/drive_hud_controller.dart';

import '../support/fake_alert_actuators.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 8, 0, 0);
  PositionAvailable fix(DateTime t, {double acc = 20}) => PositionAvailable(
        latitude: 39.72,
        longitude: 140.10,
        accuracyMeters: acc,
        timestamp: t,
      );
  DriveHudController controller() =>
      DriveHudController(actuators: FakeAlertActuators(), localeTag: 'ja');

  test('positionUnlocatable is false before any fix — the surface shows no dot, '
      'never a stale one', () {
    final c = controller();
    expect(c.estimate, isNull);
    expect(c.positionUnlocatable, isFalse);
  });

  test('positionUnlocatable is false while GPS is trusted — a confident dot is '
      'honest here', () {
    final c = controller();
    c.onPositionFix(fix(t0), now: t0);
    expect(c.estimate!.mode, LocalizationMode.gpsTrusted);
    expect(c.positionUnlocatable, isFalse);
  });

  test('SILENT DROUGHT: after a trusted fix then a poll-forward with NO new '
      'fix, positionUnlocatable becomes TRUE and the honest radius grows — the '
      'map dot + status line must degrade off the confident last point', () {
    final c = controller();

    // Trusted baseline (this is the point `_herFix` would freeze on).
    c.onPositionFix(fix(t0), now: t0);
    expect(c.positionUnlocatable, isFalse);

    // The raw stream goes SILENT; only the watchdog polls forward. No new fix.
    c.poll(now: t0.add(const Duration(seconds: 300)));

    expect(c.estimate!.mode, LocalizationMode.lost);
    // The coupling signal main.dart binds the map dot + status line to.
    expect(c.positionUnlocatable, isTrue);
    // The confidence radius the map circle now grows to (was 20 m at the fix).
    expect(c.estimate!.confidenceRadiusMeters, greaterThan(20));
  });

  test('a revoked fix mid-drive also degrades to unlocatable (dead-reckoning '
      'or lost — both must degrade the surface)', () {
    final c = controller();
    c.onPositionFix(fix(t0), now: t0);
    c.onPositionFix(const PositionUnavailable('revoked'),
        now: t0.add(const Duration(seconds: 5)));
    expect(
      c.estimate!.mode,
      anyOf(LocalizationMode.deadReckoning, LocalizationMode.lost),
    );
    expect(c.positionUnlocatable, isTrue);
  });
}
