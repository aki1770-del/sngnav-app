/// The permission that decides whether the ongoing-drive service is honest.
///
/// WHY THIS EXISTS, measured rather than reasoned.
///
/// On 2026-09-24 the app gained a foreground location service so a warning
/// still reaches the driver with her phone in her pocket. It was verified on
/// AVD sng_arc (API 34, Android 14), this app at targetSdk 36, and the service
/// ran perfectly: `dumpsys activity services` showed `isForeground=true`,
/// `types=00000008` (location), no SecurityException.
///
/// The notification did not exist. `dumpsys notification` gave
/// `numEnqueuedByApp=1, numPostedByApp=0, numBlocked=1`; the package appeared
/// zero times in the Notification List; and the expanded shade held no entry
/// from this app. The status bar showed the location pin. So the device told
/// her that SOMETHING held her location and nothing told her what, or how to
/// stop it.
///
/// Since API 33, an app targeting 33+ must hold POST_NOTIFICATIONS at runtime.
/// Declaring it in the manifest is not enough, and the failure is silent: the
/// service start succeeds and the notification is dropped.
///
/// THE RULE THIS FILE EXISTS TO ENFORCE: a denied notification means **no
/// foreground service**, never a silent one. Degrading to a screen-on-only
/// drive is a smaller loss than running location behind an indicator she
/// cannot see, and the second is the exact thing the manifest, the privacy
/// policy and the 2026-07-10 removal all promised would never happen.
library;

import 'package:flutter/services.dart';

/// What the platform says about our ability to put a notification in front of
/// her. Two separate ways to be silenced, kept separate because they need
/// different answers.
class NotificationPermissionState {
  const NotificationPermissionState({
    required this.granted,
    required this.enabled,
    required this.needsRuntimeRequest,
  });

  /// The API-33 runtime permission (or true below 33, where none exists).
  final bool granted;

  /// Notifications switched off for the app in Settings. Possible at ANY API
  /// level, and invisible to a permission check alone.
  final bool enabled;

  /// Whether this device has a runtime permission to ask for at all.
  final bool needsRuntimeRequest;

  /// The only question the drive actually cares about.
  bool get canPostToHer => granted && enabled;
}

/// Platform seam for the notification permission.
///
/// `read` never prompts. `request` prompts at most once and answers what she
/// said; a dismissed dialog is a denial, not a retry.
abstract final class NotificationPermission {
  static const MethodChannel channel =
      MethodChannel('sngnav/notification_permission');

  /// Non-prompting read. On a thrown channel error it answers "cannot post":
  /// a platform we cannot ask is never read as a platform that said yes.
  ///
  /// ⚑ IT CAN ALSO NEVER ANSWER AT ALL, and that is measured, not assumed.
  /// Under the widget-test binding an UNMOCKED channel returns a Future that
  /// simply never completes -- no value, no error (probed 2026-09-24). The same
  /// shape is reachable on a device when nothing replies. So no caller may
  /// await this on a path that must make progress: lib/main.dart reads it in
  /// the background and keeps its own `false` until an answer arrives, which is
  /// why a silent platform costs her a notification and never her drive.
  static Future<NotificationPermissionState> read() async {
    try {
      final map = await channel.invokeMapMethod<String, dynamic>('read');
      if (map == null) return _cannot;
      return NotificationPermissionState(
        granted: map['granted'] as bool? ?? false,
        enabled: map['enabled'] as bool? ?? false,
        needsRuntimeRequest: map['needsRuntimeRequest'] as bool? ?? false,
      );
    } on MissingPluginException {
      // Desktop / test binding: no Android notification surface at all.
      return _cannot;
    } on PlatformException {
      return _cannot;
    }
  }

  /// Ask her. Answers false on any failure, for the same reason as [read]:
  /// the fallback must be the honest, less-capable drive, never the silent
  /// service.
  static Future<bool> request() async {
    try {
      return await channel.invokeMethod<bool>('request') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static const _cannot = NotificationPermissionState(
    granted: false,
    enabled: false,
    needsRuntimeRequest: false,
  );
}
