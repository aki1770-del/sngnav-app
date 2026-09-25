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

    // 2026-09-25: the drive sentences (the drive keeps going, the notification
    // can vanish, 停止 ends it) were the tenth sentence of one paragraph, below
    // where the dialog opens while its agree button is always in view. They
    // are now their own block, FIRST.
    testWidgets('the act carries the drive sentences FIRST, verbatim',
        (tester) async {
      await _boot(tester);
      await _tapShare(tester);

      final drive = find.byKey(const Key('location-consent-drive'));
      final body = find.byKey(const Key('location-consent-body'));
      expect(drive, findsOneWidget);
      const l = AppL10n(Locale('ja'));
      final handle = tester.ensureSemantics();
      expect(
          find.descendant(
              of: find.byType(AlertDialog),
              matching: find.bySemanticsLabel(l.driveDisclosure)),
          findsOneWidget,
          reason: 'the drive sentences, as words, inside the act');
      handle.dispose();
      expect(tester.getRect(drive).bottom,
          lessThanOrEqualTo(tester.getRect(body).top),
          reason: 'what happens after a yes comes first');
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
      // Rendered as BLOCKS since 2026-09-23, so the assertion is on what she
      // READS rather than on one widget's `data`. The heading arrives without
      // its `#`, which is the whole point of the change.
      expect(
          find.descendant(
              of: t, matching: find.textContaining('プライバシーポリシー')),
          findsWidgets);
      expect(find.descendant(of: t, matching: find.textContaining('#')),
          findsNothing,
          reason: 'she used to read the markdown source');
      expect(find.descendant(
              of: t, matching: find.textContaining('A term she reads.')),
          findsOneWidget);
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

  _a8();

  test('the comment stripper removes authoring notes and nothing else', () {
    const raw = '# Title\n\n<!-- a note\nspanning lines -->\n\nA term she reads.\n';
    final out = renderPolicyForDisplay(raw);
    expect(out, contains('# Title'));
    expect(out, contains('A term she reads.'));
    expect(out, isNot(contains('a note')));
    expect(out, isNot(contains('<!--')));
  });
}

/// A8 — she can take our consent back, and the app names the route to the
/// platform permission it cannot revoke.
///
/// WHY. Until 2026-09-23 the store's only write was `true`. After one yes,
/// every later launch shared on one tap with no question and there was no way
/// inside the app to withdraw — a record about her she could not touch. The
/// argument that refused to persist a NO ("a remembered refusal would leave
/// her with a control that silently does nothing and no affordance to change
/// it") applies word for word to the remembered YES, and was not turned around
/// until AAA turned it.
///
/// THE TWO CONSENTS ARE SEPARATE CONTROLS — and the first version of this
/// paragraph claimed more than that, in our favour. It said ours covers what
/// the platform's permission cannot: the tile service, the voice vendor, a
/// cross-border query, a ten-minute fetch. Measured 2026-09-23:
/// `_locationConsent` gates exactly ONE thing, the position stream, and every
/// egress it authorizes needs the OS permission first. Ours is a subset by
/// effect. What survives, and what these tests assert, is that they are two
/// separate controls and only one of them was hers to withdraw — which was
/// enough, because it was the one she could never reach.
void _a8() {
  group('A8 — withdrawal, and the route we do not control', () {
    /// Boot with a stated consent answer. `null` = she has not been asked.
    /// `true` = she agreed earlier, which is the state A8 exists for.
    ///
    /// My first draft reached that state by accepting the dialog in one launch
    /// and re-booting to read the persisted answer. It failed: the persist is
    /// fire-and-forget by design, so under FakeAsync the write has not landed
    /// — the same flakiness I had already removed once from this file and then
    /// reintroduced. The seam states the precondition instead of racing for it.
    Future<_ShareCounter> boot(WidgetTester tester, {bool? consent,
        Future<bool> Function()? settings}) async {
      final c = _ShareCounter();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(SngnavApp(
        locale: const Locale('ja'),
        actuators: FakeAlertActuators(),
        clock: () => _start,
        jmaFetch: () async => const JmaFailure('test: no observation'),
        positionSource: c.call,
        locationConsent: consent,
        openPlatformSettings: settings,
      ));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return c;
    }

    const withdraw = Key('location-consent-withdraw');

    testWidgets('before she has consented there is nothing to take back, and '
        'no control pretending otherwise', (tester) async {
      final c = await boot(tester);
      expect(find.byKey(withdraw), findsNothing,
          reason: 'a control that undoes nothing is the defect it would fix');
      expect(c.starts, 0);
      await c.controller.close();
    });

    testWidgets('after a remembered yes, the way back is on her page',
        (tester) async {
      final c = await boot(tester, consent: true);
      expect(find.byKey(withdraw), findsOneWidget,
          reason: 'A8: a store whose only write is true is a record about her '
              'she cannot touch');
      await c.controller.close();
    });

    testWidgets('THE POINT OF A8: after withdrawing, the next tap ASKS AGAIN '
        'and shares nothing until she answers', (tester) async {
      final c = await boot(tester, consent: true);

      // Control, asserted FIRST: with the remembered yes still in force, a tap
      // shares on one tap with no question. That is the state A8 escapes, and
      // pinning it here stops this test passing on a broken remembered-yes.
      await _tapShare(tester);
      expect(find.byKey(const Key('location-consent-accept')), findsNothing,
          reason: 'control: a remembered yes is not re-asked');
      expect(c.starts, 1, reason: 'control: and it shares');
      await c.controller.close();

      // Now the real case.
      final c2 = await boot(tester, consent: true);
      final w = find.byKey(withdraw);
      await tester.ensureVisible(w);
      await tester.pump();
      await tester.tap(w);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('location-consent-withdrawn-note')),
          findsOneWidget,
          reason: 'the effect is SAID, not inferred from a vanished button');
      expect(find.byKey(withdraw), findsNothing,
          reason: 'and there is no longer anything to take back');

      final before = c2.starts;
      await _tapShare(tester);
      expect(find.byKey(const Key('location-consent-accept')), findsOneWidget,
          reason: 'A8: the next tap must ASK AGAIN');
      expect(c2.starts, before,
          reason: 'and share NOTHING until she answers. The share counter is '
              'asserted BESIDE the dialog, not instead of it — my own lesson '
              'this round was that silence satisfied an assertion');
      await c2.controller.close();
    });

    testWidgets('the app NAMES the platform route it cannot take for her, and '
        'opens it', (tester) async {
      var opened = 0;
      final c = await boot(tester, settings: () async {
        opened++;
        return true;
      });

      final line = find.byKey(const Key('location-os-permission-route'));
      expect(line, findsOneWidget,
          reason: 'our consent and the OS permission are different subject '
              'matters, and only one of them is ours to revoke');
      expect(tester.widget<Text>(line).data, contains('端末の設定'));

      final btn = find.byKey(const Key('location-open-os-settings'));
      await tester.ensureVisible(btn);
      await tester.pump();
      await tester.tap(btn);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(opened, 1, reason: 'offered directly — zero new dependencies, '
          'geolocator 13.0.4 already exposes it');
      expect(c.starts, 0, reason: 'naming the route starts no share');
      await c.controller.close();
    });

    testWidgets('withdrawing OURS does not touch the platform permission, and '
        'does not pretend to', (tester) async {
      var opened = 0;
      final c = await boot(tester, consent: true, settings: () async {
        opened++;
        return true;
      });
      final w = find.byKey(withdraw);
      await tester.ensureVisible(w);
      await tester.pump();
      await tester.tap(w);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(opened, 0,
          reason: 'silently opening settings would claim a power we do not '
              'have, and would hide that the OS permission still stands');
      await c.controller.close();
    });
  });
}
