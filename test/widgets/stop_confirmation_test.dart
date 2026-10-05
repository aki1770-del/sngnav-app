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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

Future<FakeAlertActuators> _boot(WidgetTester tester,
    {required Stream<PositionFix> Function() source,
    Locale locale = const Locale('ja')}) async {
  final a = FakeAlertActuators();
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
