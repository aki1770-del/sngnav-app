/// What she is promised about a drive BEFORE it starts follows what the app
/// knows about posting her a notification.
///
/// WHY (ruled 2026-10-06). Only a drive with its foreground service keeps going
/// when she leaves the app, and that service needs a notification she can see.
/// A share without one now ENDS when the app leaves the screen
/// (lib/services/share_without_service.dart). The pre-share block and the
/// consent dialog's first block showed the drive-continues words ("keeps going
/// with the screen off, while you use another app, or when you go back")
/// unconditionally, and on a device they stood directly under the notice that
/// her warnings had stopped. Her screen must not promise what her phone will
/// not do.
///
/// PINS:
///   (i)   the pre-share block shows the drive-continues words only when the
///         app can post; never while its last reading says it cannot, and not
///         while it does not know yet;
///   (ii)  the same for the consent dialog's first block;
///   (iii) the screen she returns to after the app ended a share without its
///         service shows the notice and no drive-continues words.
///
/// The words for the two other cases are the HMI review's draft E and a
/// keyed placeholder; they are pinned here only as "not the drive-continues
/// words", and by key where they must appear. The channel name and the reply
/// shape are literals, so this file also runs on a build without the rule.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/location_consent.dart' show DrivePromise;

import '../support/fake_alert_actuators.dart';

const _notifications = MethodChannel('sngnav/notification_permission');
const _ja = AppL10n(Locale('ja'));
final _start = DateTime.utc(2026, 1, 14, 21);

/// The notification read the app gets. [_neverAnswers] is a read that never
/// answers (the app has no reading yet).
Map<String, Object>? _reading({
  required bool granted,
  required bool enabled,
  required bool needsRuntimeRequest,
}) => {
  'granted': granted,
  'enabled': enabled,
  'needsRuntimeRequest': needsRuntimeRequest,
};

final Map<String, Object>? _canPost = _reading(granted: true, enabled: true, needsRuntimeRequest: false);
final Map<String, Object>? _cannotPost =
    _reading(granted: false, enabled: false, needsRuntimeRequest: false);
final _beforeTheAsk =
    _reading(granted: false, enabled: false, needsRuntimeRequest: true);
final _neverAnswers = <String, Object>{'never': true};

Future<void> _settleIO(WidgetTester tester, {int rounds = 15}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

/// Mocks the notification channel with [reading] (null: never answers) and
/// path_provider; boots the app in Japanese.
Future<void> _boot(
  WidgetTester tester,
  Map<String, Object>? reading, {
  bool? locationConsent,
  Stream<PositionFix> Function()? positionSource,
  FakeAlertActuators? actuators,
  Map<String, Object>? storedConsent,
}) async {
  final tmp = Directory.systemTemp.createTempSync('sngnav_drive_promise');
  if (storedConsent != null) {
    File('${tmp.path}/location_consent.json')
        .writeAsStringSync(jsonEncode(storedConsent));
  }
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => tmp.path,
  );
  if (reading != null) {
    messenger.setMockMethodCallHandler(
      _notifications,
      identical(reading, _neverAnswers)
          ? (call) => Completer<Object?>().future
          : (call) async => call.method == 'read' ? reading : false,
    );
  }
  addTearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(_notifications, null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(SngnavApp(
    locale: const Locale('ja'),
    locationConsent: locationConsent,
    actuators: actuators ?? FakeAlertActuators(),
    clock: () => _start,
    jmaFetch: () async => const JmaFailure('test: no observation'),
    positionSource: positionSource,
  ));
  await _settleIO(tester);
}

/// The words a screen reader hears for [key] (KeepTogetherText's semantics
/// label is the words without the joiners).
String? _wordsAt(WidgetTester tester, Key key) {
  final f = find.byKey(key, skipOffstage: false);
  if (f.evaluate().isEmpty) return null;
  final w = tester.widget(f);
  return (w as dynamic).data as String?;
}

bool _driveContinuesShownAnywhere(WidgetTester tester) {
  final handle = tester.ensureSemantics();
  final shown =
      find.bySemanticsLabel(_ja.driveDisclosure, skipOffstage: false)
          .evaluate()
          .isNotEmpty;
  handle.dispose();
  return shown;
}

Future<void> _tapShare(WidgetTester tester) async {
  final share = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(share);
  await tester.pump();
  await tester.tap(share);
  await _settleIO(tester);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  group('(i) the pre-share block', () {
    testWidgets('can post: the drive-continues words', (tester) async {
      await _boot(tester, _canPost);
      expect(_wordsAt(tester, const Key('drive-disclosure')),
          _ja.driveDisclosure,
          reason: 'control: a drive with its service keeps going');
      await _end(tester);
    });

    testWidgets('cannot post: never the drive-continues words', (tester) async {
      await _boot(tester, _cannotPost);
      expect(
        _wordsAt(tester, const Key('drive-disclosure')),
        _ja.shareWithoutServiceDisclosure,
        reason: 'THE DEFECT: the app cannot post, so a drive ends when she '
            'leaves the app; promising it keeps going is false',
      );
      expect(_driveContinuesShownAnywhere(tester), isFalse);
      await _end(tester);
    });

    testWidgets('Android 13+ before she is asked: not the drive-continues '
        'words (her answer decides)', (tester) async {
      await _boot(tester, _beforeTheAsk);
      expect(_wordsAt(tester, const Key('drive-disclosure')),
          _ja.driveDisclosureIfNotificationsAllowed);
      await _end(tester);
    });

    testWidgets('no reading yet: not the drive-continues words',
        (tester) async {
      await _boot(tester, _neverAnswers);
      expect(_wordsAt(tester, const Key('drive-disclosure')),
          _ja.driveDisclosureIfNotificationsAllowed,
          reason: 'with no reading the app does not know: the words true '
              'either way, never the drive-continues words');
      await _end(tester);
    });
  });

  group('(ii) the consent dialog', () {
    testWidgets('can post: its first block is the drive-continues words',
        (tester) async {
      await _boot(tester, _canPost);
      await _tapShare(tester);
      expect(_wordsAt(tester, const Key('location-consent-drive')),
          _ja.driveDisclosure,
          reason: 'control: the act carries the promise the app can keep');
      await _end(tester);
    });

    testWidgets('cannot post: its first block is not the drive-continues '
        'words', (tester) async {
      await _boot(tester, _cannotPost);
      await _tapShare(tester);
      expect(
        _wordsAt(tester, const Key('location-consent-drive')),
        allOf(isNotNull, isNot(_ja.driveDisclosure)),
        reason: 'THE DEFECT: she would agree to a promise the app cannot keep',
      );
      await _end(tester);
    });

    testWidgets('Android 13+ before she is asked: not the drive-continues '
        'words', (tester) async {
      await _boot(tester, _beforeTheAsk);
      await _tapShare(tester);
      expect(_wordsAt(tester, const Key('location-consent-drive')),
          allOf(isNotNull, isNot(_ja.driveDisclosure)));
      await _end(tester);
    });
  });

  testWidgets(
    '(ii) cannot post: her yes records the words the dialog showed her, not '
    'the drive-continues words', (tester) async {
      final tmp = Directory.systemTemp.createTempSync('sngnav_promise_record');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });
      await _boot(tester, _cannotPost);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tmp.path,
      );
      await _tapShare(tester);
      final shownDrive = _wordsAt(tester, const Key('location-consent-drive'));
      expect(shownDrive, allOf(isNotNull, isNot(_ja.driveDisclosure)));
      await tester.tap(find.byKey(const Key('location-consent-accept')));
      await _settleIO(tester, rounds: 30);
      final file = File('${tmp.path}/location_consent.json');
      expect(file.existsSync(), isTrue, reason: 'control: the yes was stored');
      final words = (jsonDecode(file.readAsStringSync())
          as Map<String, dynamic>)['disclosureWords'] as List<dynamic>;
      expect(words, contains(shownDrive),
          reason: 'the record names the words she was shown');
      expect(words, isNot(contains(_ja.driveDisclosure)),
          reason: 'she was not shown, and did not agree to, a promise the app '
              'cannot keep');
      expect(
          (jsonDecode(file.readAsStringSync())
              as Map<String, dynamic>)['disclosureVariant'],
          'cannotPost',
          reason: 'the record says which variant she answered');
      await _end(tester);
    },
  );

  // A stored yes covers only the variants its own words cover (a dignity
  // review, 2026-10-06): uncertain covers all three; can-post covers can-post
  // and cannot-post; cannot-post covers only itself; a yes stored before
  // variants existed reads as can-post.
  group('a stored yes', () {
    Map<String, Object> yesTo(DrivePromise? variant) {
      final w = _ja.locationConsentDialogFor(variant ?? DrivePromise.keepsGoing);
      return {
        'schema': 2,
        'locationShareConsent': true,
        'decidedAt': '2026-10-06T00:00:00Z',
        'disclosureRevision': 1,
        'disclosureLocale': 'ja',
        'disclosureWords': [w.title, w.drive, w.body, w.decline, w.accept],
        if (variant != null) 'disclosureVariant': variant.recordName,
      };
    }

    bool asked(WidgetTester tester) => find
        .byKey(const Key('location-consent-drive'), skipOffstage: false)
        .evaluate()
        .isNotEmpty;

    String? askedAgainLine(WidgetTester tester) {
      final f = find.byKey(const Key('location-consent-asked-again'));
      return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
    }

    testWidgets(
      'to the cannot-post words, at a startup where the app CAN post: she is '
      'asked again, with the drive-continues words and the line saying why',
      (tester) async {
        await _boot(tester, _canPost,
            storedConsent: yesTo(DrivePromise.onScreenOnly));
        await _tapShare(tester);
        expect(asked(tester), isTrue,
            reason: 'THE DEFECT: a yes to a drive that runs only on screen '
                'would be honoured for a drive that keeps going with the '
                'screen off');
        expect(_wordsAt(tester, const Key('location-consent-drive')),
            _ja.driveDisclosure);
        expect(askedAgainLine(tester), _ja.locationConsentAskedAgainForVariant,
            reason: 'told why, in its own words, not "the description '
                'changed" (the revision did not)');
        await _end(tester);
      },
    );

    testWidgets(
      'to the cannot-post words, while it is not known yet: asked again, with '
      'the same line',
      (tester) async {
        await _boot(tester, _beforeTheAsk,
            storedConsent: yesTo(DrivePromise.onScreenOnly));
        await _tapShare(tester);
        expect(asked(tester), isTrue);
        expect(askedAgainLine(tester), _ja.locationConsentAskedAgainForVariant);
        await _end(tester);
      },
    );

    for (final (name, reading) in [
      ('can post', _canPost!),
      ('cannot post', _cannotPost!),
      ('not known yet', _beforeTheAsk!),
    ]) {
      testWidgets(
          'to the not-known-yet words: not asked again where the app $name '
          '(they state both outcomes)', (tester) async {
        await _boot(tester, reading,
            storedConsent: yesTo(DrivePromise.ifNotificationsAllowed));
        await _tapShare(tester);
        expect(asked(tester), isFalse);
        await _end(tester);
      });
    }

    for (final (name, variant) in [
      ('to the can-post words', DrivePromise.keepsGoing),
      ('stored before variants existed', null),
    ]) {
      testWidgets(
          'a yes $name, where the app cannot post: not asked again, and the '
          'pre-share block shows the cannot-post words', (tester) async {
        await _boot(tester, _cannotPost, storedConsent: yesTo(variant));
        expect(_wordsAt(tester, const Key('drive-disclosure')),
            _ja.shareWithoutServiceDisclosure);
        await _tapShare(tester);
        expect(asked(tester), isFalse,
            reason: 'the can-post words cover the cannot-post words, which '
                'describe less');
        await _end(tester);
      });
    }

    testWidgets('control: to the cannot-post words, where the app still cannot '
        'post: not asked again', (tester) async {
      await _boot(tester, _cannotPost,
          storedConsent: yesTo(DrivePromise.onScreenOnly));
      await _tapShare(tester);
      expect(asked(tester), isFalse);
      await _end(tester);
    });
  });

  testWidgets(
    '(iii) the screen she returns to after the app ended a share without its '
    'service: the notice, and no drive-continues words',
    (tester) async {
      final positions = StreamController<Position>.broadcast();
      addTearDown(positions.close);
      await _boot(
        tester,
        _cannotPost,
        locationConsent: true,
        positionSource: () => herPositionStream(
          isServiceEnabled: () async => true,
          checkPermission: () async => LocationPermission.whileInUse,
          positionStream: () => positions.stream,
        ),
      );
      await _tapShare(tester);
      expect(find.widgetWithText(TextButton, '停止'), findsOneWidget,
          reason: 'control: the share runs');
      for (final s in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
        await tester.pump();
      }
      await _settleIO(tester);
      for (final s in const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
        await tester.pump();
      }
      await _settleIO(tester);
      expect(find.byKey(const Key('share-away-notice')), findsOneWidget,
          reason: 'control: the app ended the share and says so');
      expect(
        _driveContinuesShownAnywhere(tester),
        isFalse,
        reason: 'THE DEFECT, seen on a device: under the notice that her '
            'warnings stopped, the words said a drive keeps going',
      );
      await _end(tester);
    },
  );
}
