/// Sends the app to the background without ending it: what Home does.
///
/// WHY THIS EXISTS (2026-09-25). Back pressed on the main page during a drive
/// ended the drive, and nothing told her. Measured on an Android 14 emulator:
/// the app's GPS registration was removed at the moment of Back and the drive
/// notification was withdrawn; when she reopened the app, the card read that
/// location had never been shared. Read at source: with no route to pop,
/// Flutter calls SystemNavigator.pop(), FlutterActivity then calls
/// activity.finish(), the engine is destroyed with the activity, and the
/// position subscription is cancelled with it. No Dart code gets a turn.
///
/// What she had been told is that the drive continues when she switches to
/// another app, and that 停止 ends it. A safety review ruled that no drive may
/// end, on anything she presses, without telling her at that moment through a
/// channel that works with her eyes off the screen, and it offered two
/// designs. This is the first: Back during a drive does not end it. The page
/// intercepts Back (lib/main.dart, PopScope) and asks the platform to move the
/// task to the back, exactly as Home does. The words she read become true of
/// Back as written, and nothing new has to be said.
///
/// Why not the second design (Back ends the drive, after a spoken line): an
/// accidental Back while moving, which on a phone is an edge swipe, would end
/// her warnings for the rest of the drive, and restarting needs a hands-on act
/// she should not make while driving. A spoken line also does not reach a
/// deaf or hard-of-hearing driver, and the screen that could show it is the
/// one being closed.
///
/// What this does not settle: location use continues after a Back she may
/// have meant as "close". That is within what the consent describes (the
/// drive continues when she switches away), and it is a consent question for
/// the dignity reviewers, not this file's.
library;

import 'package:flutter/services.dart';

/// Platform seam for moving the task to the back.
abstract final class AppTask {
  static const MethodChannel channel = MethodChannel('sngnav/app_task');

  /// Asks the platform to send the app to the background, as Home does. The
  /// activity is not finished, so the engine, the drive and its notification
  /// keep running.
  ///
  /// Answers true only when the platform says it moved. Answers false on a
  /// platform without this channel (desktop, the IVI build, tests) and on any
  /// platform error: the app then simply stays where it is, with the drive
  /// running and 停止 on the page. Never throws.
  ///
  /// ⚑ Under the widget-test binding an unmocked channel returns a Future
  /// that never completes (measured 2026-09-24, services/notification_
  /// permission.dart). No caller may await this on a path that must make
  /// progress.
  static Future<bool> moveToBackground() async {
    try {
      return await channel.invokeMethod<bool>('moveTaskToBack') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
