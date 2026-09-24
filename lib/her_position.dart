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
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:geolocator/geolocator.dart';

sealed class PositionFix {
  const PositionFix();
}

class PositionAvailable extends PositionFix {
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime timestamp;
  const PositionAvailable({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
  });
}

class PositionUnavailable extends PositionFix {
  final String reason;
  const PositionUnavailable(this.reason);
}

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
/// as a wrong dot. Zero accuracy is suspicious but `isFinite`, so it is left
/// to flow (the accuracy circle tells that truth) — only non-finite is
/// guarded, matching the sibling pattern.
PositionFix fixFromSample({
  required double latitude,
  required double longitude,
  required double accuracyMeters,
  required DateTime timestamp,
}) {
  if (!(latitude.isFinite && longitude.isFinite && accuracyMeters.isFinite)) {
    return PositionUnavailable(
      'Degraded GPS fix — non-finite coordinate '
      '(lat=$latitude, lon=$longitude, acc=$accuracyMeters)',
    );
  }
  return PositionAvailable(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: accuracyMeters,
    timestamp: timestamp,
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
          controller.add(const PositionUnavailable('Location permission denied'));
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        controller.add(const PositionUnavailable(
          'Location permission permanently denied — change in OS settings',
        ));
        return;
      }
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
        (p) => controller.add(fixFromSample(
          latitude: p.latitude,
          longitude: p.longitude,
          accuracyMeters: p.accuracy,
          timestamp: p.timestamp,
        )),
        onError: (Object e) =>
            controller.add(PositionUnavailable('GPS stream error: $e')),
        // Platform stream termination is a REAL end-state (provider torn
        // down, service killed) — surfaced as honest unavailability, never
        // as silence with the last dot frozen on screen.
        onDone: () => controller.add(const PositionUnavailable(
          'GPS stream ended by the platform',
        )),
      );
    } catch (e) {
      controller.add(PositionUnavailable('GPS init error: $e'));
    }
  }

  controller.onListen = start;
  controller.onCancel = () async {
    await sub?.cancel();
  };
  return controller.stream;
}
