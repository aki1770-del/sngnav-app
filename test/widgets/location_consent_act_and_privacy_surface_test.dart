/// Two pre-ship surfaces that were measured ABSENT on 2026-09-23.
///
/// (1) THE CONSENT ACT. This app had never had an affirmative in-app consent
/// act attached to the location disclosure. The share control was a bare
/// button; the next thing after her tap was the operating system's own prompt,
/// and the disclosure was prose sitting near the button. Adjacency was doing
/// work adjacency cannot do. The app already shipped exactly the right pattern
/// — accept/decline — bolted to the SMALLER routing egress, while the larger,
/// repeating location share had none.
///
/// (2) THE PRIVACY POLICY. Google Play's User Data policy is unconditional and
/// ungated by any reasonable-expectation test: "a privacy policy link or text
/// within the app itself", and even an app accessing no personal data "must
/// still submit a privacy policy". Measured the same day, the only occurrence
/// of the phrase anywhere in the app was a COMMENT in AndroidManifest.xml.
///
/// WHAT THESE ASSERTIONS ARE NOT. Passing here is not a compliance
/// certification. AAA ruled the absence a material pre-ship RISK and said in as
/// many words that it has no authority to certify compliance; neither has the
/// seat that wrote this. These tests say the surface exists and cannot be
/// bypassed. They say nothing about whether it satisfies a reviewer.
///
/// Driven through `SngnavApp`, never through `AppL10n` directly: a guard that
/// calls the string layer goes blind to whether the widget renders the thing
/// the strings describe, which is how a sibling guard on this app stayed green
/// while the line it named was deleted from the card.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp, PrivacyPolicyPage;
import 'package:sngnav_app/services/privacy_policy.dart';

import '../support/fake_alert_actuators.dart';

final _start = DateTime.utc(2026, 1, 14, 21);

/// Counts how many times the app actually STARTED a position share. The share
/// is the thing consent gates, so this is the only honest observable.
class _ShareCounter {
  int starts = 0;
  final controller = StreamController<PositionFix>.broadcast();
  Stream<PositionFix> call() {
    starts++;
    return controller.stream;
  }
}

Future<_ShareCounter> _boot(WidgetTester tester, {String lang = 'ja'}) async {
  final c = _ShareCounter();
  // Tear the tree down FIRST. Without this, pumping another SngnavApp reuses
  // the same element and the same HomePage State, so a "second launch" is not
  // one: the previous share was still live and its control was gone from the
  // tree. That is what "Bad state: No element" meant, and it would have let a
  // persistence test pass for the wrong reason.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    locale: Locale(lang),
    actuators: FakeAlertActuators(),
    clock: () => _start,
    jmaFetch: () async => const JmaFailure('test: no observation'),
    positionSource: c.call,
  ));
  await tester.pump();
  await tester.pump();
  return c;
}

Future<void> _tapShare(WidgetTester tester) async {
  final b = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(b);
  await tester.pump();
  await tester.tap(b);
  // The act reads a persisted answer first, with a 2 s hang-bound. Pump past
  // it: a shorter pump was my first draft and the dialog had simply not been
  // built yet, which reads exactly like "there is no dialog".
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  // The consent store asks for the app documents directory. Under the test
  // binding that channel has no handler, so the call throws and would fail the
  // test on its own. Answer it with a temp directory rather than swallow it.
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sngnav_consent');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('the location share is gated on an affirmative act', () {
    testWidgets('her tap raises the act and starts NOTHING on its own',
        (tester) async {
      final c = await _boot(tester);
      await _tapShare(tester);

      expect(find.byKey(const Key('location-consent-accept')), findsOneWidget,
          reason: 'THE ACT: tapping share must ask, not act');
      expect(find.byKey(const Key('location-consent-decline')), findsOneWidget);
      expect(c.starts, 0,
          reason: 'NOT BYPASSABLE: nothing may start before she agrees — and '
              'the OS permission prompt sits AFTER this, so reaching it '
              'without the act is the bypass this guards');
    });

    testWidgets('the act CARRIES the disclosure, it does not merely sit near it',
        (tester) async {
      await _boot(tester);
      await _tapShare(tester);

      final body = find.byKey(const Key('location-consent-body'));
      expect(body, findsOneWidget);
      // The dialog's body is the reviewed disclosure itself, verbatim.
      const l = AppL10n(Locale('ja'));
      expect(tester.widget<Text>(body).data, l.locationDisclosure,
          reason: 'the thing consented to and the act are one surface');
    });

    testWidgets('DECLINE starts nothing', (tester) async {
      final c = await _boot(tester);
      await _tapShare(tester);
      await tester.tap(find.byKey(const Key('location-consent-decline')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(c.starts, 0);
      expect(find.byKey(const Key('location-consent-accept')), findsNothing,
          reason: 'the act closed');
    });

    testWidgets('ACCEPT starts the share', (tester) async {
      final c = await _boot(tester);
      await _tapShare(tester);
      await tester.tap(find.byKey(const Key('location-consent-accept')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(c.starts, 1, reason: 'a yes is honoured, once');
      await c.controller.close();
    });

    testWidgets('a DISMISSAL is not a yes', (tester) async {
      final c = await _boot(tester);
      await _tapShare(tester);
      // Tap the barrier, the way a stray touch dismisses a dialog.
      await tester.tapAt(const Offset(10, 10));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(c.starts, 0,
          reason: 'dismissed is not decided, and not decided is not consent');
    });

    testWidgets('a DECLINE does not trap her — she is asked again, never '
        'left with a button that silently does nothing', (tester) async {
      final c = await _boot(tester);
      await _tapShare(tester);
      await tester.tap(find.byKey(const Key('location-consent-decline')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(c.starts, 0);

      await _tapShare(tester);
      expect(find.byKey(const Key('location-consent-accept')), findsOneWidget,
          reason: 'only a YES is remembered. A remembered no would leave her '
              'with a control that does nothing and no affordance to change '
              'it — the route question has one beside its declined state, and '
              'this control has none');
      expect(c.starts, 0, reason: 'and still nothing has started');
    });

    testWidgets('a remembered YES is not re-asked within the session',
        (tester) async {
      final c = await _boot(tester);
      await _tapShare(tester);
      await tester.tap(find.byKey(const Key('location-consent-accept')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(c.starts, 1);
      expect(find.byKey(const Key('location-consent-accept')), findsNothing,
          reason: 'the act closed and does not re-raise itself');
      await c.controller.close();
    });

  });

  group('the privacy policy is inside the app', () {
    testWidgets('the page foot carries a privacy surface she can open',
        (tester) async {
      await _boot(tester);
      final link = find.byKey(const Key('privacy-policy-link'));
      await tester.ensureVisible(link);
      await tester.pump();
      expect(link, findsOneWidget,
          reason: 'THE SURFACE: Play requires a privacy policy link or text '
              'WITHIN the app, unconditionally, and measured 2026-09-23 this '
              'app had neither — the only occurrence of the phrase anywhere '
              'was a comment in AndroidManifest.xml');
      await tester.tap(link);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(PrivacyPolicyPage), findsOneWidget);
    });

    testWidgets('the page renders the text it is given, and names the '
        'published copy', (tester) async {
      const body = '# プライバシーポリシー\n\nA term she reads.';
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ja'), Locale('en')],
        home: PrivacyPolicyPage(loader: () async => body),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final t = find.byKey(const Key('privacy-policy-text'));
      expect(t, findsOneWidget);
      expect(tester.widget<SelectableText>(t).data, body);
      expect(find.byKey(const Key('privacy-policy-source')), findsOneWidget);
    });

    testWidgets('an unreadable asset says so and names where to read it',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ja'), Locale('en')],
        home: PrivacyPolicyPage(loader: () async => null),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final f = find.byKey(const Key('privacy-policy-unavailable'));
      expect(f, findsOneWidget,
          reason: 'an empty page reads as a policy with no terms');
      expect(tester.widget<Text>(f).data, contains(kPrivacyPolicyRepoUrl));
    });
  });

  test('the comment stripper removes authoring notes and nothing else', () {
    const raw = '# Title\n\n<!-- a note\nspanning lines -->\n\nA term she reads.\n';
    final out = renderPolicyForDisplay(raw);
    expect(out, contains('# Title'));
    expect(out, contains('A term she reads.'));
    expect(out, isNot(contains('a note')));
    expect(out, isNot(contains('<!--')));
  });
}
