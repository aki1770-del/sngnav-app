/// Asks Android to keep another app's floating window off a control.
///
/// WHY THIS EXISTS (2026-10-04). On an Android 14 emulator at her geometry,
/// Google Maps navigated in picture-in-picture while a drive ran. Android put
/// Maps' window at the bottom right of the screen, over 停止. Her tap on 停止
/// went to Maps' window (logcat: com.android.wm.shell.pip.phone.PipTouchHandler)
/// and opened Maps' menu, and the drive kept running. Where Android places that
/// window varies, so it does not cover 停止 every time.
///
/// Android 13 (API 33) added View.setPreferKeepClearRects: an app names rects it
/// would like kept clear of floating windows above its own window. On Android
/// 14 the picture-in-picture code moves its window off such a rect: up first,
/// then left, down and right, as far as the screen allows
/// (PhonePipKeepClearAlgorithm.findUnoccludedPosition).
///
/// WHAT IT DOES NOT DO, stated so nothing above reads as a promise:
/// - Below API 33 there is no such call. On Android 8 to 12 (API 26 to 32),
///   which have picture-in-picture, nothing here keeps 停止 clear.
/// - On API 33 the phone picture-in-picture code reads these rects only from
///   the Android 13 QPR3 update on; before it, the feature was off by default.
/// - Android's own words: "The system will try to respect this preference,
///   but when not possible will ignore it." When there is no room to move,
///   the window stays where it is.
/// - Only picture-in-picture is read here. Other floating windows (chat
///   heads, screen filters drawn over other apps) are not moved by it.
/// - A phone maker's own system UI may handle picture-in-picture differently.
///   That has not been measured.
library;

import 'package:flutter/services.dart';

/// Platform seam for View.setPreferKeepClearRects on the Flutter view.
abstract final class KeepClear {
  static const MethodChannel channel = MethodChannel('sngnav/keep_clear');

  /// Replaces the rects this app asks Android to keep clear. [physicalRects]
  /// are in physical pixels, in the Flutter view's own coordinates (the same
  /// space as a global logical rect times the device pixel ratio). An empty
  /// list asks for nothing to be kept clear.
  ///
  /// Answers true only when the platform says it handed the rects to Android,
  /// which is API 33 and later. True does not mean the rects are clear: Android
  /// may still ignore them (see the library comment). Answers false below API
  /// 33, on a platform without this channel (desktop, the IVI build, tests),
  /// and on any platform error. Never throws.
  ///
  /// ⚑ Under the widget-test binding an unmocked channel returns a Future
  /// that never completes (measured 2026-09-24, services/notification_
  /// permission.dart). No caller may await this on a path that must make
  /// progress.
  static Future<bool> setRects(List<Rect> physicalRects) async {
    try {
      return await channel.invokeMethod<bool>(
            'setPreferKeepClearRects',
            <List<int>>[
              for (final r in physicalRects)
                <int>[
                  r.left.floor(),
                  r.top.floor(),
                  r.right.ceil(),
                  r.bottom.ceil(),
                ],
            ],
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
