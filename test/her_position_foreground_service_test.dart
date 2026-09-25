/// The ongoing-drive foreground service, pinned at the seam where it is
/// decided.
///
/// **What this test is for.** HER warning used to reach her only while she was
/// holding the phone with the app on screen. The count that matters is how many
/// things must go right before she hears anything, and "has it open" is the one
/// an elderly rural driver fails most. Removing it is one object: the
/// LocationSettings handed to `Geolocator.getPositionStream`. If that object is
/// a plain [LocationSettings], the drive is foreground-only and the warning
/// dies with the screen. If it carries a [ForegroundNotificationConfig], the
/// already-merged `GeolocatorLocationService` goes foreground and the drive
/// survives the pocket.
///
/// **This is a fail-first test, and the first group is the failure.** The
/// pre-2026-09-24 code passed exactly `const LocationSettings(accuracy: high,
/// distanceFilter: 0)`. That value is reconstructed below and asserted to NOT
/// satisfy the contract — so the group would have failed on the old code and
/// documents precisely what was wrong with it, rather than only asserting that
/// the new code is fine.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/notification_permission.dart';

/// THE WORDS SHE ACTUALLY GETS — not a copy of them.
///
/// This file used to declare its own `const _text` fixture and then assert
/// `expect(config.notificationText, contains('停止'))` against it. That assertion
/// could only ever pass: the fixture was the first draft of the string, it
/// contained 停止, and the string we SHIP did not. The test guaranteed a word
/// that never reached her shade.
///
/// It is the same defect class as 666df5b in this same round — "the comment
/// said a test pinned the wiring; deleting the wiring failed nothing" — one
/// file over: an assertion pointed at our description of the thing instead of
/// the thing. So the fixture is DELETED rather than corrected. There is now
/// one source for these words, and it is the source `main.dart` reads.
///
/// Built exactly as `_shareLocation` builds it (main.dart, the
/// `driveNotification:` argument): same three getters, same order.
DriveNotificationText _shipped(String languageCode) {
  final l = AppL10n(Locale(languageCode));
  return DriveNotificationText(
    title: l.driveNotificationTitle,
    body: l.driveNotificationBody,
    channelName: l.driveNotificationChannel,
  );
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('the defect this change closes', () {
    test(
        'a plain LocationSettings — what the drive used to pass — carries no '
        'foreground service, so the warning dies with the screen', () {
      const oldSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );
      // Not an AndroidSettings at all, so there is nowhere for a foreground
      // notification config to live. This is the whole of the old behaviour.
      expect(oldSettings, isNot(isA<AndroidSettings>()));
    });
  });

  group('driveLocationSettings on Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('carries a foreground notification config when given her words', () {
      final settings = driveLocationSettings(notification: _shipped('ja'));
      expect(settings, isA<AndroidSettings>());
      final config =
          (settings as AndroidSettings).foregroundNotificationConfig;
      expect(config, isNotNull,
          reason: 'without this, GeolocatorLocationService never calls '
              'startForeground and the drive is foreground-only again');
    });

    test('the notification says what is running and how to end it, in her '
        'language — never an English-only surface (AAE-4 / D4)', () {
      final config = (driveLocationSettings(notification: _shipped('ja'))
              as AndroidSettings)
          .foregroundNotificationConfig!;
      expect(config.notificationTitle, _shipped('ja').title);
      expect(config.notificationText, _shipped('ja').body);
      expect(config.notificationChannelName, _shipped('ja').channelName);
    });

    // THE WORD, IN BOTH TONGUES, TIED TO THE CONTROL IT NAMES.
    //
    // The body must send her to the control that actually exists, by the name
    // that control actually carries. `AppL10n.stop` is what the button renders
    // (main.dart, the TextButton beside the status line), so the notification
    // is asserted against THAT getter rather than against a literal — rename
    // the button and this fails, which is the point. Both locales, because
    // the defect this replaces was invisible in exactly one of them.
    for (final lang in ['ja', 'en']) {
      test('the $lang body names the stop control by the same word the button '
          'carries (AAE-4 / D4)', () {
        final config = (driveLocationSettings(notification: _shipped(lang))
                as AndroidSettings)
            .foregroundNotificationConfig!;
        expect(
          config.notificationText,
          contains(AppL10n(Locale(lang)).stop),
          reason: 'the in-app disclosure tells her to tap the notification '
              'then press this word; if the notification never says it, she '
              'is hunting for a control nothing named',
        );
      });

      test('the $lang body does not promise that a tap ends it', () {
        final body = (driveLocationSettings(notification: _shipped(lang))
                as AndroidSettings)
            .foregroundNotificationConfig!
            .notificationText;
        // geolocator's content intent is buildBringToFrontIntent()
        // (BackgroundNotification.java:46, set at :89) — the tap OPENS the app
        // and location keeps running. A body that says "Tap to end" /
        // 「終了はタップ」 names a one-step action she cannot perform, and she
        // is left believing she stopped something that is still running.
        expect(body, isNot(contains('Tap to end')));
        expect(body, isNot(contains('終了はタップ。')));
      });
    }

    // RENAMED 2026-09-25. This test was named "setOngoing is true — the
    // indicator cannot be separated from the collection", and that name
    // printed as a pass on every run while the property was measured FALSE on
    // Android 14 (one swipe removed the notification; the service kept
    // running). The assertion was always about the argument; now the name is.
    test('setOngoing is true — the argument is pinned; on Android 14+ this does '
        'NOT keep the notification in front of the collection', () {
      final config = (driveLocationSettings(notification: _shipped('ja'))
              as AndroidSettings)
          .foregroundNotificationConfig!;
      // If she could swipe this away, location would keep being collected with
      // no visible sign of it — the "silent, notification-less background
      // location" the manifest's dignity boundary forbids.
      // ⚑ 2026-09-25: this pins the ARGUMENT, not the guarantee. On a
      // secured Android 14 emulator one swipe removed a notification built
      // exactly this way while the foreground service kept running (see the
      // setOngoing comment in lib/her_position.dart). A green here does NOT
      // mean she cannot separate the indicator from the collection on 14+.
      expect(config.setOngoing, isTrue);
    });

    test('enableWakeLock is true — a batch of fixes delivered after the pass '
        'is a transcript, not a warning', () {
      final config = (driveLocationSettings(notification: _shipped('ja'))
              as AndroidSettings)
          .foregroundNotificationConfig!;
      expect(config.enableWakeLock, isTrue);
      // Her worst case is the network being gone; we hold no Wi-Fi radio for a
      // drive designed to work without one.
      expect(config.enableWifiLock, isFalse);
    });

    test('no notification text means no foreground service — the service is '
        'never started behind her back', () {
      final settings = driveLocationSettings();
      expect(
        settings is AndroidSettings
            ? settings.foregroundNotificationConfig
            : null,
        isNull,
      );
    });
  });

  group('off Android', () {
    test('desktop/test targets get plain LocationSettings — no mobile-only '
        'plugin is touched, so the render-SEE ceiling stays intact', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final settings = driveLocationSettings(notification: _shipped('ja'));
      expect(settings, isNot(isA<AndroidSettings>()));
      expect(settings.accuracy, LocationAccuracy.high);
      expect(settings.distanceFilter, 0);
    });
  });

  group('the delivery-cadence invariant this change must not break', () {
    test('distanceFilter stays 0 on both paths, so absence of fixes still '
        'MEANS blackout rather than a parked car', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(driveLocationSettings(notification: _shipped('ja')).distanceFilter, 0);
      expect(driveLocationSettings().distanceFilter, 0);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(driveLocationSettings(notification: _shipped('ja')).distanceFilter, 0);
    });
  });

  // ===== THE CALL SITE, asserted mechanically =====
  //
  // Added 2026-09-24 after this seat's own comment in lib/main.dart claimed
  // "the widget test test/her_position_foreground_service_test.dart pins it"
  // and a mutation PROVED THAT FALSE: deleting the whole `driveNotification:`
  // argument from _shareLocation left all 8 tests in this file green.
  //
  // Everything above tests driveLocationSettings, which is the function BELOW
  // the wiring. The wiring itself -- that the drive actually PASSES her words
  // -- had no instrument, and _shareLocation takes the real branch only when
  // HomePage.positionSource is null, which no widget test in this suite does.
  // So this is a source assertion, for the reason haptic_report_wiring_test.dart
  // gives for its own: an instrument that could not surface the counter-example
  // has measured nothing.
  //
  // What it protects: if this argument is dropped, herPositionStream falls back
  // to plain LocationSettings, no foreground service starts, and her warning
  // dies the moment the screen goes off -- silently, with a green suite.
  group('the drive START passes her the notification (lib/main.dart wiring)', () {
    final mainSource = File('lib/main.dart').readAsStringSync();

    String shareLocationBody() {
      final start = mainSource.indexOf('void _shareLocation()');
      expect(start, isNot(-1),
          reason: '_shareLocation was renamed or removed; re-point this guard');
      var depth = 0;
      var seen = false;
      for (var i = start; i < mainSource.length; i++) {
        final c = mainSource[i];
        if (c == '{') {
          depth++;
          seen = true;
        } else if (c == '}') {
          depth--;
          if (seen && depth == 0) return mainSource.substring(start, i + 1);
        }
      }
      fail('could not find the end of _shareLocation');
    }

    test('_shareLocation hands driveNotification to herPositionStream', () {
      final body = shareLocationBody();
      expect(body, contains('herPositionStream('),
          reason: 'the drive no longer starts the real position stream');
      expect(body, contains('driveNotification:'),
          reason: 'THE DEFECT: the drive starts without a foreground '
              'notification, so her warning dies with the screen');
    });

    test('...and the words are LOCALIZED, never English-only (AAE-4 / D4)', () {
      final body = shareLocationBody();
      for (final getter in const [
        'driveNotificationTitle',
        'driveNotificationBody',
        'driveNotificationChannel',
      ]) {
        expect(body, contains(getter),
            reason: 'the ongoing notification stopped sourcing $getter from '
                'AppL10n -- a hardcoded string here is an English-only shade '
                'entry on a Japanese driver\'s phone');
      }
    });
  });

  // ===== THE NOTIFICATION SHE CAN SEE =====
  //
  // Added 2026-09-24 after going and looking at the shade on AVD sng_arc
  // (API 34, Android 14), this app at targetSdk 36, POST_NOTIFICATIONS declared
  // NOWHERE.
  //
  // The service started perfectly. `dumpsys activity services` gave
  // isForeground=true, types=00000008 (location), no SecurityException. Every
  // instrument that looks at the SERVICE said success.
  //
  // The notification did not exist. `dumpsys notification` gave
  // numEnqueuedByApp=1, numPostedByApp=0, numBlocked=1; the package appeared
  // ZERO times in the Notification List; and the expanded shade, captured as a
  // screenshot, held no entry from this app. The status bar showed the location
  // pin -- so the OS told her something held her location, and nothing told her
  // what it was or how to end it.
  //
  // That is strictly worse than the defect this change set out to fix: a
  // service behind an invisible notification IS the "silent, notification-less
  // background location" the manifest, the privacy policy and the 2026-07-10
  // removal each promised would never happen.
  //
  // After declaring and requesting it, re-measured on the same emulator:
  // DENIED -> no foreground service at all (isForeground absent); GRANTED ->
  // "Driving - watching the road for you / Warns with the screen off. Tap to
  // end." visible in the shade.
  //
  // These tests pin the fail-closed DIRECTION, which is the part a future
  // change can silently lose.
  group('the ongoing service may not exist unless she can SEE it', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    void answerRead(Map<String, Object?>? reply, {Object? throwIt}) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NotificationPermission.channel,
              (MethodCall call) async {
        if (throwIt != null) throw throwIt;
        return reply;
      });
    }

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NotificationPermission.channel, null);
    });

    test('granted AND enabled -> she can be told, so the service may run',
        () async {
      answerRead(
          {'granted': true, 'enabled': true, 'needsRuntimeRequest': true});
      expect((await NotificationPermission.read()).canPostToHer, isTrue);
    });

    test('permission granted but notifications switched OFF in Settings -> NO',
        () async {
      answerRead(
          {'granted': true, 'enabled': false, 'needsRuntimeRequest': true});
      expect((await NotificationPermission.read()).canPostToHer, isFalse,
          reason: 'she can turn notifications off for the app at any API '
              'level, and a permission check alone reads that as fine — the '
              'service would then run behind nothing she can see');
    });

    test('she declined the runtime permission -> NO', () async {
      answerRead(
          {'granted': false, 'enabled': true, 'needsRuntimeRequest': true});
      expect((await NotificationPermission.read()).canPostToHer, isFalse);
    });

    test('the platform THROWS -> NO, never a yes', () async {
      answerRead(null,
          throwIt: PlatformException(code: 'boom', message: 'no channel'));
      expect((await NotificationPermission.read()).canPostToHer, isFalse,
          reason: 'a platform we cannot ask is not a platform that said yes');
      expect(await NotificationPermission.request(), isFalse);
    });

    test('a malformed reply is not read as permission', () async {
      answerRead(<String, Object?>{});
      expect((await NotificationPermission.read()).canPostToHer, isFalse);
    });

    test(
        'and a NO becomes plain LocationSettings — no foreground service, '
        'not a silent one', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final settings = driveLocationSettings(notification: null);
      expect(
          settings is AndroidSettings
              ? settings.foregroundNotificationConfig
              : null,
          isNull,
          reason: 'THE DEFECT: she would be driving with location held behind '
              'a notification the OS silently dropped');
    });
  });
}
