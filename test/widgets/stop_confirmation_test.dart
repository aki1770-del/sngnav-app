/// When a drive ends at 停止, she is told so eyes-off, and only once it has
/// ended.
///
/// Why, written before the act (2026-10-05). On her Android 10 phone a
/// floating window can take or misplace a tap over 停止. A drive that ends
/// when she did not mean it to ended in silence: nothing spoke and nothing
/// vibrated, and only a live region (heard with TalkBack on) said so. She could
/// drive on believing the app still warned her about where she was. The safety
/// review ruled the gap an evident one (the machine must catch it, not her
/// eyes) and accepted one short line and a distinct vibration, played only
/// when the drive has actually ended. The words are the HMI seat's.
///
/// Held here: the English line and its voice; a cancel that completes late
/// (nothing is said before the drive has ended, and nothing if a new share has
/// started by then); and that what she hears and what the card then reads
/// state one fact. Every other end she can press is held in
/// drive_back_is_never_a_silent_end_test.dart; the words, the bundled clip,
/// the vibration and the scope word in test/voice/share_ended_voice_test.dart.
///
/// The fake actuators prove the app asked to speak and vibrate, not that she
/// heard or felt it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

/// The words decided for the line, verbatim.
const _endedJa = '共有を終了しました。現在地の警告も止まりました。';
const _endedEn =
    'Sharing has ended, and warnings for your location have stopped.';

final _now = DateTime.utc(2026, 1, 14, 21, 40);

Future<JmaResult> _jma() async => JmaSuccess(JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 5,
      humidityPercent: 50,
      windMetersPerSecond: 2,
      snowDepthCm: null,
      precipitation10mMm: 0,
      visibilityMeters: 1500,
      observedAtJstKey: '202601150630',
      fetchedAt: _now,
    ));

/// The warning-channel check's line: a real announce at warning severity with
/// the warning cue, reachable on her page during a share. Held here as "a
/// warning in flight".
const _checkJa = 'これはテストです。警報の音と振動を確認しています。';

/// Holds the channel check's words in the air until [release] completes, so a
/// line queued behind it waits, as behind any warning still being spoken.
class _HeldWarningActuators extends FakeAlertActuators {
  final Completer<void> release = Completer<void>();
  bool inTheAir = false;

  @override
  Future<void> speak(String text, {required String localeTag}) async {
    await super.speak(text, localeTag: localeTag);
    if (text == _checkJa) {
      inTheAir = true;
      await release.future;
      inTheAir = false;
    }
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

Future<FakeAlertActuators> _boot(WidgetTester tester,
    {required Stream<PositionFix> Function() source,
    Locale locale = const Locale('ja'),
    FakeAlertActuators? actuators}) async {
  final a = actuators ?? FakeAlertActuators();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    locationConsent: true,
    actuators: a,
    locale: locale,
    clock: () => _now,
    jmaFetch: _jma,
    positionSource: source,
  ));
  await tester.pump();
  await tester.pump();
  return a;
}

Future<void> _tapKeyed(WidgetTester tester, Key key) async {
  final f = find.byKey(key);
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _settle(tester);
}

Future<void> _tapText(WidgetTester tester, String words) async {
  final f = find.widgetWithText(TextButton, words);
  expect(f, findsOneWidget, reason: 'control: $words is offered');
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _settle(tester);
  // One turn of the real event loop. A broadcast subscription's cancel() that
  // has nothing to wait for returns the SDK's completed future, which lives in
  // the root zone: code awaiting it resumes in a root-zone microtask, which
  // the test's fake async never runs (measured 2026-10-05: the line was told
  // only at teardown, to an unmounted page). On a phone the event loop runs it
  // at once.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await _settle(tester);
}

void main() {
  testWidgets(
      'in English: the English line, in the English voice, and the ended cue',
      (tester) async {
    const en = AppL10n(Locale('en'));
    final ctrl = StreamController<PositionFix>.broadcast();
    addTearDown(ctrl.close);
    final a = await _boot(tester,
        source: () => ctrl.stream, locale: const Locale('en'));
    await _tapKeyed(tester, const Key('share-location-button'));
    await _tapText(tester, en.stop);
    expect([for (final l in a.spoken) (l.text, l.localeTag)],
        [(_endedEn, 'en-US')]);
    expect(a.felt, ['ended']);
  });

  group('keyed on the end, never on the tap', () {
    testWidgets(
        'a cancel that completes late: nothing is said before it completes, '
        'and the line and the cue after', (tester) async {
      final cancelled = Completer<void>();
      final ctrl = StreamController<PositionFix>(
          onCancel: () => cancelled.future);
      final a = await _boot(tester, source: () => ctrl.stream);
      await _tapKeyed(tester, const Key('share-location-button'));
      await _tapText(tester, const AppL10n(Locale('ja')).stop);
      expect(a.spoken, isEmpty,
          reason: 'the cancel has not completed: the drive has not ended, '
              'and the line says it has');
      expect(a.felt, isEmpty);
      cancelled.complete();
      await _settle(tester);
      expect([for (final l in a.spoken) l.text], [_endedJa]);
      expect(a.felt, ['ended']);
    });

    testWidgets(
        'a new share started before the cancel completed: the line is not '
        'said, because the warnings for her location run again',
        (tester) async {
      final cancelled = Completer<void>();
      var shares = 0;
      final first = StreamController<PositionFix>(
          onCancel: () => cancelled.future);
      final second = StreamController<PositionFix>.broadcast();
      addTearDown(second.close);
      final a = await _boot(tester,
          source: () => ++shares == 1 ? first.stream : second.stream);
      await _tapKeyed(tester, const Key('share-location-button'));
      await _tapText(tester, const AppL10n(Locale('ja')).stop);
      await _tapKeyed(tester, const Key('share-location-button'));
      expect(second.hasListener, isTrue, reason: 'control: sharing again');
      cancelled.complete();
      await _settle(tester);
      expect(a.spoken.where((l) => l.text == _endedJa), isEmpty);
      expect(a.felt.where((f) => f == 'ended'), isEmpty);
    });
  });

  // F-1 (AAA bb2d2937 section 7, WDA 46e240b2 section 6, 2026-10-10). The
  // line can wait in the queue behind a warning still being spoken. What is
  // true when it PLAYS decides, on both channels.
  group('read when it plays, behind a warning in flight', () {
    Future<void> fireCheck(WidgetTester tester, _HeldWarningActuators a) async {
      final fire = find.byKey(const Key('channel-check-fire'));
      await tester.scrollUntilVisible(fire, 300);
      await tester.pump();
      await tester.tap(fire);
      await _settle(tester);
      expect(a.inTheAir, isTrue, reason: 'control: a warning is in the air');
    }

    Future<void> releaseAndSettle(
        WidgetTester tester, _HeldWarningActuators a) async {
      a.release.complete();
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await _settle(tester);
      }
    }

    testWidgets(
        'control: 停止 behind the warning, nothing else: the line and the '
        'ended cue, after the warning has finished', (tester) async {
      final a = _HeldWarningActuators();
      final ctrl = StreamController<PositionFix>.broadcast();
      addTearDown(ctrl.close);
      await _boot(tester, source: () => ctrl.stream, actuators: a);
      await _tapKeyed(tester, const Key('share-location-button'));
      await fireCheck(tester, a);
      await _tapText(tester, const AppL10n(Locale('ja')).stop);
      expect([for (final l in a.spoken) l.text], [_checkJa],
          reason: 'it waits behind the warning');
      await releaseAndSettle(tester, a);
      expect([for (final l in a.spoken) l.text], [_checkJa, _endedJa]);
      expect(a.felt, ['warning', 'ended']);
    });

    testWidgets(
        '(i) 停止, then a new share, while the warning is in the air: when it '
        'ends, no stop line and no ended cue, because her new share\'s '
        'warnings run', (tester) async {
      final a = _HeldWarningActuators();
      final ctrl = StreamController<PositionFix>.broadcast();
      addTearDown(ctrl.close);
      await _boot(tester, source: () => ctrl.stream, actuators: a);
      await _tapKeyed(tester, const Key('share-location-button'));
      await fireCheck(tester, a);
      await _tapText(tester, const AppL10n(Locale('ja')).stop);
      await _tapKeyed(tester, const Key('share-location-button'));
      expect(ctrl.hasListener, isTrue, reason: 'control: sharing again');
      await releaseAndSettle(tester, a);
      expect([for (final l in a.spoken) l.text], [_checkJa],
          reason: '「現在地の警告も止まりました」 would be false now');
      expect(a.felt, ['warning'], reason: 'never the pulse alone');
    });

    testWidgets(
        '(ii) 停止, a new share, 停止, while the warning is in the air: '
        'exactly one stop line and one ended cue', (tester) async {
      final a = _HeldWarningActuators();
      final ctrl = StreamController<PositionFix>.broadcast();
      addTearDown(ctrl.close);
      await _boot(tester, source: () => ctrl.stream, actuators: a);
      const ja = AppL10n(Locale('ja'));
      await _tapKeyed(tester, const Key('share-location-button'));
      await fireCheck(tester, a);
      await _tapText(tester, ja.stop);
      await _tapKeyed(tester, const Key('share-location-button'));
      expect(ctrl.hasListener, isTrue, reason: 'control: sharing again');
      await _tapText(tester, ja.stop);
      expect(ctrl.hasListener, isFalse, reason: 'control: ended again');
      await releaseAndSettle(tester, a);
      expect([for (final l in a.spoken) l.text], [_checkJa, _endedJa],
          reason: 'one line about where she stands now');
      expect(a.felt, ['warning', 'ended']);
    });
  });

  testWidgets(
      'screen and voice state one fact: after 停止 the card reads that '
      'location is not being shared, and the line she hears names the same '
      'act, 共有', (tester) async {
    const ja = AppL10n(Locale('ja'));
    final ctrl = StreamController<PositionFix>.broadcast();
    addTearDown(ctrl.close);
    final a = await _boot(tester, source: () => ctrl.stream);
    await _tapKeyed(tester, const Key('share-location-button'));
    await _tapText(tester, ja.stop);
    expect(find.text(ja.locationNotShared), findsOneWidget,
        reason: 'the card after 停止');
    expect(a.spoken, isNotEmpty, reason: 'the line was spoken');
    expect(a.spoken.single.text, contains('共有'),
        reason: 'what she hears and what she then reads use one verb');
  });
}
