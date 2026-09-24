/// Slice 2c — the driver's position, with honest uncertainty.
///
/// Why: the driver needs to see WHERE SHE IS, with the app telling the
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
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:geolocator/geolocator.dart';

sealed class PositionFix {
  const PositionFix();
}

class PositionAvailable extends PositionFix {
  final double latitude;
  final double longitude;

  /// The platform's measured horizontal accuracy, in metres, or `null` when it
  /// measured none (decided 2026-09-14). geolocator writes 0.0 where the platform
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
  /// Her ring only (decided 2026-09-14). The caution advisor is never given it:
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

/// What one position says about motion (decided 2026-09-14).
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

/// Whether the platform measured [value], a field of [p] whose geolocator flag
/// is [flag].
///
/// On Android the flag never arrives (measured 2026-09-17). geolocator_android
/// 4.6.2 parses every position with `AndroidPosition.fromMap`, which reads the
/// flags through `Position.fromMap` and then rebuilds the position from its
/// numbers alone, so `hasAccuracy`, `hasSpeed` and `hasSpeedAccuracy` are false
/// on every Android position. Read as "not measured", that made every GPS fix
/// on an Android phone a sample with no accuracy: never a fix, never on her
/// map, which said 現在地 不明 while the phone held a 30 m fix.
///
/// What the Android parser still carries is exact: `LocationMapper.toHashMap`
/// writes a value only when the platform measured it, and `Position.fromMap`
/// reads an omitted value as exactly 0.0. So on an [AndroidPosition] a value
/// other than 0.0 was measured. A measured 0.0 cannot be told from no
/// measurement there, and reads as none: no 0 m ring, and a speed of 0.0 never
/// concludes a stop. A flag that is set is believed as before.
bool _measured(Position p, bool flag, double value) =>
    flag || (p is AndroidPosition && value != 0);

/// The least rate her ring may grow at after [p]: the reported speed plus the
/// reported speed accuracy when that accuracy is usable, the speed alone when
/// it is not, and `null` when no usable speed was reported. A 0.0 without the
/// flag is a placeholder, never a stop.
double? groundSpeedFloorMps(Position p) {
  final speed = _reported(_measured(p, p.hasSpeed, p.speed), p.speed);
  if (speed == null) return null;
  return speed +
      (_reported(_measured(p, p.hasSpeedAccuracy, p.speedAccuracy),
              p.speedAccuracy) ??
          0);
}

/// What [p] measured about motion: see [GroundMotion]. Fail-closed by
/// construction: "stopped" needs both values reported and usable, on a
/// position whose horizontal accuracy was measured ([usableAccuracyMeters]),
/// and every ambiguous reading is [GroundMotion.unknown]. "Moving" needs no
/// measured horizontal accuracy: it only closes, and closing needs less
/// evidence than opening.
GroundMotion groundMotionOf(Position p) {
  final speed = _reported(_measured(p, p.hasSpeed, p.speed), p.speed);
  if (speed == null) return GroundMotion.unknown;
  final accuracy = _reported(
      _measured(p, p.hasSpeedAccuracy, p.speedAccuracy), p.speedAccuracy);
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
/// (decided 2026-09-14). A flagged 0.0 is believed. iOS writes its accuracy on
/// every fix, an invalid -1 included, so the flag alone is not enough.
double? usableAccuracyMeters(Position p) =>
    _reported(_measured(p, p.hasAccuracy, p.accuracy), p.accuracy);

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
  /// words (decided 2026-09-14).
  noLocationOnThisDevice,
}

/// The reasons [herPositionStream] gives for a denied permission, kept for
/// the log. The app acts on [PositionUnavailable.cause], never on these words,
/// and a reason with no cause never reads as a refusal (decided 2026-09-14).
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
/// Why: a degraded / NaN / Inf GPS fix must NEVER become a
/// confidently-wrong dot on the map. The accuracy field is the loom's
/// honesty (see library doc); a non-finite coordinate is the loom lying.
/// Worse: the app pins flutter_map 8.3.0, whose `Crs.checkLatLng` THROWS on
/// a non-finite `LatLng` (`Exception('LatLng is not finite: ...')`,
/// flutter_map issue #2178) — a single bad fix would crash the driver's entire map
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

/// Streams the driver's position with accuracy. Emits [PositionUnavailable] on
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
/// The ongoing-drive notification's words, resolved by the caller so they are
/// LOCALIZED (AAE-4: an English-only surface for a Japanese driver is a D4
/// breach). `her_position.dart` has no `BuildContext`, so `main.dart` passes
/// `AppLocalizations`' strings in rather than this file inventing English.
class DriveNotificationText {
  const DriveNotificationText({
    required this.title,
    required this.body,
    required this.channelName,
  });

  /// One line she reads at a glance in the shade.
  final String title;

  /// What it is doing and how to end it.
  final String body;

  /// The channel name as it appears in Android's own app-settings list.
  final String channelName;
}

/// The location settings for a live drive.
///
/// **Android: this is the ongoing-drive foreground service.** Passing a
/// [ForegroundNotificationConfig] is what makes geolocator's already-declared
/// `GeolocatorLocationService` call `startForeground` (StreamHandlerImpl.java:130
/// on listen, `disableBackgroundMode` at :155 on cancel). No Service is written
/// here: one already existed in the plugin and already merged into our APK —
/// the re-entrancy test (CLAUDE.md §11 test 3) says wire the primitive that
/// exists, do not invent a second one.
///
/// **Why it is needed at all.** Without it the drive is a plain background app:
/// Android throttles background location for apps with no foreground service,
/// the process sits at a cached/previous-app oom adjustment and is a kill
/// candidate, and Doze defers its timers. So the warning she needs reaches her
/// only while she is *holding the phone and looking at it* — the condition an
/// elderly rural driver fails most.
///
/// **What it deliberately does NOT do.** It does not survive her never having
/// started a drive, and it must not: `ACCESS_BACKGROUND_LOCATION` stays
/// withheld and the service exists only behind a notification she started and
/// can end.
///
/// [notification] null (or any non-Android target) yields plain
/// [LocationSettings] — desktop, web and tests are untouched, and the
/// render-SEE ceiling stays intact.
LocationSettings driveLocationSettings({DriveNotificationText? notification}) {
  const accuracy = LocationAccuracy.high;
  // 0, deliberately (was 5 m): a displacement filter suppresses delivery while
  // stationary, so "no fix arrived lately" would be ambiguous between a real
  // GPS blackout and a parked car. With time-cadence delivery, absence of fixes
  // MEANS blackout — which is what lets the app's blackout watchdog degrade the
  // honest dot (trusted → dead-reckoning → lost) instead of crying wolf at
  // every red light. Delivery-rate only: the GPS radio duty cycle is set by
  // accuracy, not by this filter.
  const distanceFilter = 0;

  if (notification == null ||
      defaultTargetPlatform != TargetPlatform.android) {
    return const LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );
  }

  return AndroidSettings(
    accuracy: accuracy,
    distanceFilter: distanceFilter,
    foregroundNotificationConfig: ForegroundNotificationConfig(
      notificationTitle: notification.title,
      notificationText: notification.body,
      notificationChannelName: notification.channelName,
      // TRUE, and the dignity reasoning runs the opposite way to the obvious
      // one. `setOngoing: false` would let her swipe the notification away —
      // and then location keeps being collected with NO visible indicator,
      // which is exactly the "silent, notification-less background location"
      // the manifest's dignity boundary forbids. Ongoing means the indicator
      // cannot be separated from the collection: for as long as we are
      // watching, she can see that we are watching. Ending it is a different
      // act and she has it — tap the notification (geolocator builds a
      // bring-to-front intent, BackgroundNotification.java:46) then 停止.
      setOngoing: true,
      // TRUE and load-bearing. geolocator's own doc: with this false "the
      // system can still sleep and all location events will be received at
      // once when the system wakes up again." A batch of hazard fixes
      // delivered after the pass is not a warning, it is a transcript.
      // WAKE_LOCK is already declared in AndroidManifest.xml.
      enableWakeLock: true,
      // FALSE: her worst case is the network being gone. We hold no Wi-Fi
      // radio for a drive that is designed to work without one.
      enableWifiLock: false,
    ),
  );
}

Stream<PositionFix> herPositionStream({
  Future<bool> Function()? isServiceEnabled,
  Future<LocationPermission> Function()? checkPermission,
  Future<LocationPermission> Function()? requestPermission,
  Stream<Position> Function()? positionStream,
  DriveNotificationText? driveNotification,
  Duration platformCallTimeout = const Duration(seconds: 10),
  Duration permissionRequestTimeout = const Duration(minutes: 2),
  void Function()? onPlatformStreamSubscribed,
}) {
  final controller = StreamController<PositionFix>();
  StreamSubscription<Position>? sub;
  // Set when the listener is gone. Every platform call below is awaited, and
  // a cancel that comes while one is awaited (停止 on the permission dialog)
  // finds no subscription to end; without this the start went on after her
  // answer and subscribed the platform stream with nothing left to cancel it
  // (measured 2026-09-15: subscribed once, never cancelled, after the app was
  // gone).
  var cancelled = false;

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
      if (cancelled) return;
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
      if (cancelled) return;
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
        if (cancelled) return;
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
      // The notification decision is NOT made here, and that is deliberate.
      //
      // It used to be: this line awaited NotificationPermission.request()
      // before subscribing. MEASURED 2026-09-24 under the widget-test binding,
      // an unmocked platform channel NEVER COMPLETES -- so the ask never
      // answered, the position stream was never subscribed, and eight existing
      // widget tests went from green to "subscribed 0 times". That is not a
      // test artefact. On a real phone the same shape is a channel that does
      // not answer (an activity torn down while the dialog is up), and the
      // consequence is that she taps the share control and HER DRIVE NEVER
      // STARTS, silently. A notification is a comfort; the position feed is the
      // safety function. The comfort must never be able to block the function.
      //
      // So the caller decides beforehand and passes either the words or null.
      // See resolveDriveNotification above and its caller in lib/main.dart.
      sub = (positionStream ??
              () => Geolocator.getPositionStream(
                    locationSettings: driveLocationSettings(
                      notification: driveNotification,
                    ),
                  ))()
          .listen(
        // Finite-coordinate chokepoint: a degraded/NaN/Inf fix becomes an
        // honest PositionUnavailable, never a confidently-wrong dot that
        // would also crash flutter_map 8.3.0's checkLatLng. See fixFromSample.
        // Accuracy and speed are read here, where the platform's flags are
        // still in hand: a value the platform did not measure is never read.
        // On Android the flags are lost in the plugin's parser; see _measured.
        (p) => controller.add(fixFromSample(
          latitude: p.latitude,
          longitude: p.longitude,
          accuracyMeters:
              _measured(p, p.hasAccuracy, p.accuracy) ? p.accuracy : null,
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
    cancelled = true;
    await sub?.cancel();
  };
  return controller.stream;
}
