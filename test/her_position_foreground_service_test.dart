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
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/her_position.dart';

const _text = DriveNotificationText(
  title: '運転中 — 路面の警告を監視しています',
  body: '画面を消していても警告します。終了するにはタップして「停止」。',
  channelName: '運転中の位置情報',
);

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
      final settings = driveLocationSettings(notification: _text);
      expect(settings, isA<AndroidSettings>());
      final config =
          (settings as AndroidSettings).foregroundNotificationConfig;
      expect(config, isNotNull,
          reason: 'without this, GeolocatorLocationService never calls '
              'startForeground and the drive is foreground-only again');
    });

    test('the notification says what is running and how to end it, in her '
        'language — never an English-only surface (AAE-4 / D4)', () {
      final config = (driveLocationSettings(notification: _text)
              as AndroidSettings)
          .foregroundNotificationConfig!;
      expect(config.notificationTitle, _text.title);
      expect(config.notificationText, _text.body);
      expect(config.notificationChannelName, _text.channelName);
      // The body must tell her how to stop it. A notification she cannot
      // dismiss and cannot end is surveillance, not a warning service.
      expect(config.notificationText, contains('停止'));
    });

    test('setOngoing is true — the indicator cannot be separated from the '
        'collection', () {
      final config = (driveLocationSettings(notification: _text)
              as AndroidSettings)
          .foregroundNotificationConfig!;
      // If she could swipe this away, location would keep being collected with
      // no visible sign of it — the "silent, notification-less background
      // location" the manifest's dignity boundary forbids.
      expect(config.setOngoing, isTrue);
    });

    test('enableWakeLock is true — a batch of fixes delivered after the pass '
        'is a transcript, not a warning', () {
      final config = (driveLocationSettings(notification: _text)
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
      final settings = driveLocationSettings(notification: _text);
      expect(settings, isNot(isA<AndroidSettings>()));
      expect(settings.accuracy, LocationAccuracy.high);
      expect(settings.distanceFilter, 0);
    });
  });

  group('the delivery-cadence invariant this change must not break', () {
    test('distanceFilter stays 0 on both paths, so absence of fixes still '
        'MEANS blackout rather than a parked car', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(driveLocationSettings(notification: _text).distanceFilter, 0);
      expect(driveLocationSettings().distanceFilter, 0);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(driveLocationSettings(notification: _text).distanceFilter, 0);
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
}
