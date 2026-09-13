/// Slice 2c — HER's position, with honest uncertainty.
///
/// HER-trace: HER needs to see WHERE SHE IS, with the loom telling the
/// truth about what it knows and what it doesn't. The accuracy field IS
/// the loom's honesty. A small accuracy circle says "I'm sure"; a big
/// accuracy circle says "I'm not sure"; no dot at all says "I don't know,
/// and I will not pretend." That is V14 (silent-failure-anti-Jidoka)
/// applied to position.
///
/// V96 cohort dignity: the permission ask is gated on a deliberate user
/// gesture (tap "Share my location"). Auto-grabbing GPS on app open is
/// disrespectful and — as a practical matter — modern browsers refuse
/// to prompt for permission outside a user gesture, so the auto-grab
/// path also fails technically. Two reasons, one solution.
///
/// What this slice does NOT yet do (deferred):
/// - Dead-reckoning fallback when GPS drops (the `kalman_dr` package in
///   the SNGNav family is the substrate; not wired yet).
/// - Cohort-respectful permission rationale UI tailored per DriverProfile
///   (the button label is the same for all cohorts; ageingRural deserves
///   pre-rationale context — future slice).
/// - Cross-trip memory of GPS-weak zones (the anti-cortisol loom from
///   the conversation that produced this slice).
///
/// All three are named here so the future-slice scope is honest.
library;

import 'dart:async';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:geolocator/geolocator.dart';

sealed class PositionFix {
  const PositionFix();
}

class PositionAvailable extends PositionFix {
  final double latitude;
  final double longitude;

  /// The platform's measured horizontal accuracy, in metres, or `null` when it
  /// measured none (ruled 2026-09-14). geolocator writes 0.0 where the platform
  /// has no accuracy and says so only in `Position.hasAccuracy`; read as a
  /// number, that placeholder was a 0 m ring, "exactly here", which nothing
  /// measured. A sample with `null` here is not a fix: the drive brain polls
  /// at its timestamp, it never anchors, and the map never draws it.
  final double? accuracyMeters;
  final DateTime timestamp;

  /// The least rate, in m/s, her ring may grow at after this fix, read by
  /// [groundSpeedFloorMps] from what the platform reported with it: `null`
  /// when it reported no usable speed.
  ///
  /// Her ring only (ruled 2026-09-14). The caution advisor is never given it:
  /// with no visibility reading it counts the missing reading as a degraded
  /// condition, so a known speed above 13.4 m/s would speak a caution on an
  /// ordinary drive.
  final double? speedFloorMps;

  /// What this fix measured about motion ([groundMotionOf]). It describes this
  /// fix only; whether a stop is still current is not decided here.
  final GroundMotion motion;

  const PositionAvailable({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
    this.speedFloorMps,
    this.motion = GroundMotion.unknown,
  });
}

/// What one position says about motion (ruled 2026-09-14).
enum GroundMotion {
  /// A usable speed whose lower bound, less its usable accuracy, is above
  /// [kStoppedAtMostMps].
  moving,

  /// A usable speed AND a usable speed accuracy whose sum is at most
  /// [kStoppedAtMostMps]. Never concluded without a reported accuracy.
  stopped,

  /// Everything else, including a reading whose bounds straddle the limit.
  unknown,
}

/// The stop limit, in m/s. PROVISIONAL and UNVERIFIED: no reading of platform
/// speed and speed accuracy at a real stop on a real phone exists. Until one
/// does it may be lowered, never raised: raising it opens route setting while
/// she creeps, lowering it keeps route setting closed while she is parked.
const double kStoppedAtMostMps = 0.5;

/// A platform value the app may read: reported by its flag, finite and not
/// negative; otherwise `null`, whatever the field holds. geolocator writes 0.0
/// where the platform measured nothing, and only the flag tells the two apart
/// (Android omits the key; iOS writes speed and speed accuracy only when both
/// are non-negative; geolocator_linux 0.2.5 sets no flag).
double? _reported(bool flagged, double value) =>
    flagged && value.isFinite && value >= 0 ? value : null;

/// The least rate her ring may grow at after [p]: the reported speed plus the
/// reported speed accuracy when that accuracy is usable, the speed alone when
/// it is not, and `null` when no usable speed was reported. A 0.0 without the
/// flag is a placeholder, never a stop.
double? groundSpeedFloorMps(Position p) {
  final speed = _reported(p.hasSpeed, p.speed);
  if (speed == null) return null;
  return speed + (_reported(p.hasSpeedAccuracy, p.speedAccuracy) ?? 0);
}

/// What [p] measured about motion: see [GroundMotion]. Fail-closed by
/// construction: "stopped" needs both values reported and usable, on a
/// position whose horizontal accuracy was measured ([usableAccuracyMeters]),
/// and every ambiguous reading is [GroundMotion.unknown]. "Moving" needs no
/// measured horizontal accuracy: it only closes, and closing needs less
/// evidence than opening.
GroundMotion groundMotionOf(Position p) {
  final speed = _reported(p.hasSpeed, p.speed);
  if (speed == null) return GroundMotion.unknown;
  final accuracy = _reported(p.hasSpeedAccuracy, p.speedAccuracy);
  if (speed - (accuracy ?? 0) > kStoppedAtMostMps) return GroundMotion.moving;
  if (accuracy != null &&
      speed + accuracy <= kStoppedAtMostMps &&
      usableAccuracyMeters(p) != null) {
    return GroundMotion.stopped;
  }
  return GroundMotion.unknown;
}

/// [p]'s horizontal accuracy, only when the platform flags it as measured and
/// it is finite and not negative; otherwise `null`, whatever the field holds
/// (ruled 2026-09-14). A flagged 0.0 is believed. iOS writes its accuracy on
/// every fix, an invalid -1 included, so the flag alone is not enough.
double? usableAccuracyMeters(Position p) =>
    _reported(p.hasAccuracy, p.accuracy);

class PositionUnavailable extends PositionFix {
  final String reason;

  /// Why, for the causes the app acts on. Never derived from [reason].
  final PositionUnavailableCause cause;

  const PositionUnavailable(
    this.reason, {
    this.cause = PositionUnavailableCause.other,
  });
}

/// Why a position is unavailable, for the causes the app acts on. Everything
/// else is [other], whatever its free-text reason says: a reason can carry
/// exception text (`'GPS stream error: $e'`), and acting on words inside it
/// could silence a real failure. Only [herPositionStream] sets a cause, from
/// the platform's own permission result or the type of what the platform
/// threw, never from text.
enum PositionUnavailableCause {
  /// Anything the app does not act on by cause.
  other,

  /// Location permission is denied for this app: the dialog's "no", a denial
  /// the platform applied without her taking any action, or the platform's
  /// typed denial when the position stream subscribes.
  permissionDenied,

  /// Denied for good: the platform no longer shows the dialog.
  permissionDeniedForever,

  /// This app has no location implementation on this platform: one of the
  /// stream's platform calls has none (`MissingPluginException`, wherever it
  /// arrives, including as a stream error). Known from the exception's type.
  /// Not a refusal, and it changes nothing the drive brain is given: only the
  /// words (ruled 2026-09-14).
  noLocationOnThisDevice,
}

/// The reasons [herPositionStream] gives for a denied permission, kept for
/// the log. The app acts on [PositionUnavailable.cause], never on these words,
/// and a reason with no cause never reads as a refusal (ruled 2026-09-14).
const String _permissionDeniedReason = 'Location permission denied';
const String _permissionPermanentlyDeniedReason =
    'Location permission permanently denied — change in OS settings';
const String _permissionDeniedAtSubscribeReason =
    'Location permission denied when the position stream subscribed';

/// Whether [fix] says location is off for this app: permission denied, now or
/// for good. Not a timeout, not location services off, not a stream error
/// other than the platform's typed permission denial: those are the platform
/// failing. Read from the typed cause only.
bool isLocationRefusal(PositionFix? fix) =>
    fix is PositionUnavailable &&
    (fix.cause == PositionUnavailableCause.permissionDenied ||
        fix.cause == PositionUnavailableCause.permissionDeniedForever);

/// Whether [fix] says this app has no location on this device, from the type
/// of what the platform threw.
bool isNoLocationOnThisDevice(PositionFix? fix) =>
    fix is PositionUnavailable &&
    fix.cause == PositionUnavailableCause.noLocationOnThisDevice;

/// Whether [fix] is a denial for good, where the platform no longer asks.
bool isPermanentLocationRefusal(PositionFix? fix) =>
    fix is PositionUnavailable &&
    fix.cause == PositionUnavailableCause.permissionDeniedForever;

/// Finite-coordinate chokepoint guard.
///
/// HER-trace: a degraded / NaN / Inf GPS fix must NEVER become a
/// confidently-wrong dot on the map. The accuracy field is the loom's
/// honesty (see library doc); a non-finite coordinate is the loom lying.
/// Worse: the app pins flutter_map 8.3.0, whose `Crs.checkLatLng` THROWS on
/// a non-finite `LatLng` (`Exception('LatLng is not finite: ...')`,
/// flutter_map issue #2178) — a single bad fix would crash HER entire map
/// subtree. So this single ingest chokepoint converts any non-finite sample
/// into the honest "position unavailable" state INSTEAD of a position.
///
/// This is the same #161 NaN-GPS class the sibling SNGNav repo guards at its
/// LocationBloc chokepoint (fixed 2026-06-27). It drops NO valid coordinate
/// and masks nothing: a real bad fix surfaces as honestly-unavailable, never
/// as a wrong dot.
///
/// [accuracyMeters] is `null` when the platform did not flag an accuracy as
/// measured; that sample keeps its coordinates and carries no accuracy. A
/// negative accuracy is no measurement either, and becomes `null` here. A
/// flagged 0.0 flows: the platform says it measured it.
///
/// Corrected 2026-09-14. This comment said zero accuracy "is suspicious but
/// `isFinite`, so it is left to flow (the accuracy circle tells that truth)".
/// That reasoning let the unflagged placeholder through as a 0 m ring. The
/// circle tells the truth only about a value somebody measured.
PositionFix fixFromSample({
  required double latitude,
  required double longitude,
  required double? accuracyMeters,
  required DateTime timestamp,
  double? speedFloorMps,
  GroundMotion motion = GroundMotion.unknown,
}) {
  if (!(latitude.isFinite &&
      longitude.isFinite &&
      (accuracyMeters?.isFinite ?? true))) {
    return PositionUnavailable(
      'Degraded GPS fix — non-finite coordinate '
      '(lat=$latitude, lon=$longitude, acc=$accuracyMeters)',
    );
  }
  return PositionAvailable(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters:
        accuracyMeters != null && accuracyMeters >= 0 ? accuracyMeters : null,
    timestamp: timestamp,
    speedFloorMps: speedFloorMps,
    motion: motion,
  );
}

/// Streams HER position with accuracy. Emits [PositionUnavailable] on
/// permission denial, service-disabled, stream error, platform-call
/// timeout, or platform stream termination — never silently stalls on a
/// stale fix, and never hangs waiting on a platform call that will not
/// answer (a hang is not a throw: it is SILENCE, the one thing this
/// stream exists to refuse).
///
/// Every raw platform await is timeout-wrapped (the codebase's own rule —
/// see HardenedTtsEngine: "a timeout is the only recovery" from a platform
/// Future that never completes). [platformCallTimeout] bounds the
/// programmatic reads (service-enabled / permission check), which a healthy
/// platform answers in milliseconds. [permissionRequestTimeout] bounds the
/// permission REQUEST separately and generously — a human is reading a
/// system dialog there; timing her out at 10 s would convert her
/// deliberation into a false "unavailable".
///
/// The injectable seams ([isServiceEnabled] / [checkPermission] /
/// [requestPermission] / [positionStream]) default to the real Geolocator
/// statics; tests inject hanging/canned fakes so every timeout + onDone
/// path is verifiable off-device (same idiom as PlayAsset /
/// VoicesProvider).
///
/// MUST be called from a user-gesture handler (button onPressed). Modern
/// browsers refuse permission prompts outside a user gesture; calling
/// this from initState() will silently fail without prompting.
Stream<PositionFix> herPositionStream({
  Future<bool> Function()? isServiceEnabled,
  Future<LocationPermission> Function()? checkPermission,
  Future<LocationPermission> Function()? requestPermission,
  Stream<Position> Function()? positionStream,
  Duration platformCallTimeout = const Duration(seconds: 10),
  Duration permissionRequestTimeout = const Duration(minutes: 2),
  void Function()? onPlatformStreamSubscribed,
}) {
  final controller = StreamController<PositionFix>();
  StreamSubscription<Position>? sub;

  Future<void> start() async {
    try {
      final bool serviceEnabled;
      try {
        serviceEnabled = await (isServiceEnabled ??
                Geolocator.isLocationServiceEnabled)()
            .timeout(platformCallTimeout);
      } on TimeoutException {
        controller.add(const PositionUnavailable(
          'Location service check timed out — platform did not answer',
        ));
        return;
      }
      if (!serviceEnabled) {
        controller.add(const PositionUnavailable('Location services disabled'));
        return;
      }
      LocationPermission permission;
      try {
        permission = await (checkPermission ?? Geolocator.checkPermission)()
            .timeout(platformCallTimeout);
      } on TimeoutException {
        controller.add(const PositionUnavailable(
          'Location permission check timed out — platform did not answer',
        ));
        return;
      }
      if (permission == LocationPermission.denied) {
        try {
          permission =
              await (requestPermission ?? Geolocator.requestPermission)()
                  .timeout(permissionRequestTimeout);
        } on TimeoutException {
          controller.add(const PositionUnavailable(
            'Location permission request timed out — no answer from the '
            'platform dialog',
          ));
          return;
        }
        if (permission == LocationPermission.denied) {
          controller.add(const PositionUnavailable(
            _permissionDeniedReason,
            cause: PositionUnavailableCause.permissionDenied,
          ));
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        controller.add(const PositionUnavailable(
          _permissionPermanentlyDeniedReason,
          cause: PositionUnavailableCause.permissionDeniedForever,
        ));
        return;
      }
      sub = (positionStream ??
              () => Geolocator.getPositionStream(
                    locationSettings: const LocationSettings(
                      accuracy: LocationAccuracy.high,
                      // 0, deliberately (was 5 m): a displacement filter
                      // suppresses delivery while stationary, so "no fix
                      // arrived lately" would be ambiguous between a real
                      // GPS blackout and a parked car. With time-cadence
                      // delivery, absence of fixes MEANS blackout — which is
                      // what lets the app's blackout watchdog degrade the
                      // honest dot (trusted → dead-reckoning → lost) instead
                      // of crying wolf at every red light. Delivery-rate
                      // only: the GPS radio duty cycle is set by accuracy,
                      // not by this filter.
                      distanceFilter: 0,
                    ),
                  ))()
          .listen(
        // Finite-coordinate chokepoint: a degraded/NaN/Inf fix becomes an
        // honest PositionUnavailable, never a confidently-wrong dot that
        // would also crash flutter_map 8.3.0's checkLatLng. See fixFromSample.
        // Accuracy and speed are read here, where the platform's flags are
        // still in hand: a value the platform did not flag is never read.
        (p) => controller.add(fixFromSample(
          latitude: p.latitude,
          longitude: p.longitude,
          accuracyMeters: p.hasAccuracy ? p.accuracy : null,
          timestamp: p.timestamp,
          speedFloorMps: groundSpeedFloorMps(p),
          motion: groundMotionOf(p),
        )),
        // By the error's type, never its text. geolocator_android 4.6.2 checks
        // the permission again when the stream is listened to and, when it is
        // not held, sends PERMISSION_DENIED (`StreamHandlerImpl.java:93-98`),
        // which the plugin types as PermissionDeniedException: her "no", not a
        // failure. It was shown as a stream error, and a failure after her
        // "no" reached the critical caution rung (measured 2026-09-14).
        onError: (Object e) => controller.add(switch (e) {
          PermissionDeniedException() => const PositionUnavailable(
              _permissionDeniedAtSubscribeReason,
              cause: PositionUnavailableCause.permissionDenied,
            ),
          MissingPluginException() => PositionUnavailable(
              'GPS stream error: $e',
              cause: PositionUnavailableCause.noLocationOnThisDevice,
            ),
          _ => PositionUnavailable('GPS stream error: $e'),
        }),
        // Platform stream termination is a REAL end-state (provider torn
        // down, service killed) — surfaced as honest unavailability, never
        // as silence with the last dot frozen on screen.
        onDone: () => controller.add(const PositionUnavailable(
          'GPS stream ended by the platform',
        )),
      );
      // The platform has answered the permission question and its position
      // stream is subscribed. From here on, silence is the platform's, not
      // time she spends on a dialog.
      onPlatformStreamSubscribed?.call();
    } catch (e) {
      // A platform call with no implementation is this device's absence of
      // location, known by type. Anything else keeps no cause.
      controller.add(PositionUnavailable(
        'GPS init error: $e',
        cause: e is MissingPluginException
            ? PositionUnavailableCause.noLocationOnThisDevice
            : PositionUnavailableCause.other,
      ));
    }
  }

  controller.onListen = start;
  controller.onCancel = () async {
    await sub?.cancel();
  };
  return controller.stream;
}
