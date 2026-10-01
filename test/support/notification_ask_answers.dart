/// The app's notification-permission channel, answering at once.
///
/// WHY. The drive start asks for the notification permission and requests
/// location only after that ask has answered, within a bound (see
/// lib/services/permission_ask_order.dart). Under the widget-test binding an
/// unmocked channel never answers, which is a SILENT PLATFORM: the drive then
/// waits its 10 s bound before location is asked. On a device the app's own
/// handler always answers (android/.../MainActivity.kt, "request"), so a test
/// of the real position path that is not about a silent platform says what
/// the notification platform answers. Left silent, a test that presses 停止
/// "on the location dialog at 5 s" would press it before any location
/// dialog exists, and pass without measuring what it was written for.
///
/// It answers "not allowed": the drive then runs without the notification,
/// which is exactly what these tests saw before, when the ask never answered
/// and the app kept its own `false`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/notification_permission.dart';

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void answerNotificationAskAtOnce() {
  _messenger.setMockMethodCallHandler(NotificationPermission.channel,
      (call) async {
    switch (call.method) {
      case 'read':
        return <String, Object>{
          'granted': false,
          'enabled': true,
          'needsRuntimeRequest': true,
        };
      case 'request':
        return false;
    }
    return null;
  });
}

void stopAnsweringNotificationAsk() =>
    _messenger.setMockMethodCallHandler(NotificationPermission.channel, null);
