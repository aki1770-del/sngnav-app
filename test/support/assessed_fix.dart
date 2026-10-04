/// A fix the GPS trust verdict can judge: the same fix one interval earlier.
///
/// Why, written before the act (2026-10-05). The drive brain judges every fix
/// against the fix before it, and the first fix of a share has nothing to be
/// judged against, so it is held and never trusted
/// (`lib/services/gps_trust.dart`). A test that means "a trusted fix" now
/// gives that fix one predecessor: [justBefore] is the same place, one second
/// earlier, the shortest honest history after which the fix can be judged.
/// The fix the test asserts on, its timestamp and every expected value stay
/// as they were.
///
/// How the predecessor reaches the drive brain matters. Before a share has
/// anchored, the app ASKS about a fix (`wouldTrust`) and holds it; it does not
/// feed it (main.dart `_onPositionEvent`). A test of the drive brain itself
/// does the same: `controller.wouldTrust(justBefore(fix))`, then feeds [fix].
/// Feeding the predecessor instead would give the brain a fix it cannot
/// place, and the caution rung that goes with it, which the app never does
/// with a held fix. A test through the app's position stream simply emits it
/// first, and the app holds it.
///
/// Use it only where a test is about what a TRUSTED fix does. A test about a
/// share's first fix itself must feed that fix alone and expect it held.
library;

import 'package:sngnav_app/her_position.dart';

/// [fix] at the same place, [by] earlier, carrying the same measurements.
PositionAvailable justBefore(
  PositionAvailable fix, {
  Duration by = const Duration(seconds: 1),
}) =>
    PositionAvailable(
      latitude: fix.latitude,
      longitude: fix.longitude,
      accuracyMeters: fix.accuracyMeters,
      timestamp: fix.timestamp.subtract(by),
      speedFloorMps: fix.speedFloorMps,
      motion: fix.motion,
      speedLowerBoundMps: fix.speedLowerBoundMps,
    );
