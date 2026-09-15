/// The live-drive card's description, demo controls and announce line follow
/// the app's locale.
///
/// Why this test exists. Measured 2026-09-14: the card's description, its
/// blackout button and counter, and its announce line were English literals in
/// Japanese mode, and its visibility demo label and bands were Japanese
/// literals in English mode. English keeps its bytes, and the Japanese label
/// and bands keep theirs. The new sentences are unruled candidates for a look
/// on a render.
///
/// The card's title and footer are asserted in live_drive_card_words_test.dart:
/// since 2026-09-14 they follow the app's locale too, once the instrument that
/// looks at her map found the card by the key on its description and compared
/// each language with itself. The English description's words that only the
/// team could read were removed on the same day; the rest keeps its bytes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/developer_page.dart';
import '../support/fake_alert_actuators.dart';

final _cjk = RegExp(r'[぀-ヿ㐀-鿿＀-￯]');

Future<void> _boot(WidgetTester tester, String lang) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: FakeAlertActuators(),
    locale: Locale(lang),
    clock: () => DateTime.utc(2026, 1, 14, 21),
    jmaFetch: () async => const JmaFailure('no network in this test'),
    developerPageEntry: true,
  ));
  await tester.pump();
  await tester.pump();
}

// The demo controls are on the development page (2026-09-15).
Future<void> _useMock(WidgetTester tester) =>
    tapOnDeveloperPage(tester, const Key('use-mock-button'));

Future<void> _blackout(WidgetTester tester) =>
    tapOnDeveloperPage(tester, const Key('drive-hud-blackout-button'));

String _textOf(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data ?? '';

const _englishLiterals = [
  'Combines your position',
  'Simulate GPS blackout',
  'blackout: ',
  'the app tells you by voice and vibration',
  'Raised to caution (shown in colour)',
  'nothing is announced by voice or vibration',
];

void main() {
  testWidgets('Japanese: no English literal left in these parts of the card',
      (tester) async {
    await _boot(tester, 'ja');
    await _useMock(tester);
    await _blackout(tester);
    for (final english in _englishLiterals) {
      expect(find.textContaining(english), findsNothing, reason: english);
    }
    for (final key in const [
      Key('drive-hud-description'),
      Key('drive-hud-announce-status'),
    ]) {
      expect(find.byKey(key), findsOneWidget, reason: '$key');
      expect(_cjk.hasMatch(_textOf(tester, key)), isTrue,
          reason: '$key: 「${_textOf(tester, key)}」');
    }
    // The demo controls and the counter are read where they are drawn.
    await openDeveloperPage(tester);
    for (final english in _englishLiterals) {
      expect(find.textContaining(english), findsNothing, reason: english);
    }
    for (final key in const [Key('drive-hud-blackout-seconds')]) {
      expect(find.byKey(key), findsOneWidget, reason: '$key');
      expect(_cjk.hasMatch(_textOf(tester, key)), isTrue,
          reason: '$key: 「${_textOf(tester, key)}」');
    }
    final button = find.byKey(const Key('drive-hud-blackout-button'));
    expect(
        find.descendant(of: button, matching: find.textContaining(_cjk)),
        findsOneWidget,
        reason: 'the blackout button reads Japanese');
  });

  testWidgets('English: no Japanese in the demo label and bands, and the '
      'English parts keep their bytes', (tester) async {
    await _boot(tester, 'en');
    await _useMock(tester);
    await _blackout(tester);
    expect(find.textContaining('Combines your position'), findsOneWidget);
    // The demo controls and the counter are read where they are drawn.
    await openDeveloperPage(tester);
    expect(find.textContaining('視程デモ上書き'), findsNothing);
    expect(find.textContaining('上書きなし'), findsNothing);
    final label = _textOf(tester, const Key('drive-hud-visibility-label'));
    expect(_cjk.hasMatch(label), isFalse, reason: label);
    expect(
        find.descendant(
            of: find.byKey(const Key('drive-hud-blackout-button')),
            matching: find.text('Simulate GPS blackout (+60 s)')),
        findsOneWidget);
    expect(find.text('blackout: 60s'), findsOneWidget);
  });
}
