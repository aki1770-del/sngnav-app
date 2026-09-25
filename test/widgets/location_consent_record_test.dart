/// A stored yes is honoured only for the words she agreed to, and nothing on
/// disk can stop her being asked (2026-09-25).
///
/// WHY, in two parts.
///
/// (1) A remembered yes skipped the dialog for good, and the store kept no
/// record of which words it answered. The words had already changed in
/// substance between builds: "only while the app is open" became "keeps going
/// with the screen off". A yes to the first would have been held against the
/// second. Her yes now records the words, and a yes to other words is asked
/// once more, saying why.
///
/// (2) Withdrawing wrote `locationShareConsent: false`, and the next launch
/// read that false back as her answer. Measured in this harness on the tree
/// before this file: after a withdrawal and a relaunch her tap on 現在地を共有
/// raised no dialog and started no share, while the card had told her 「次に
/// 共有するときにもう一度おたずねします」. The last test below is that
/// measurement, kept.
///
/// Real file IO is used throughout: the store is the thing under test. IO
/// completes only in real time, and its continuations only when the test zone
/// flushes, so [_settleIO] interleaves the two without advancing the fake
/// clock (which would fire the act's 2-second hang-bounds early).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/location_consent.dart';
import 'package:sngnav_app/widgets/keep_together.dart';

import '../support/fake_alert_actuators.dart';

final _start = DateTime.utc(2026, 1, 14, 21);

Future<void> _settleIO(WidgetTester tester, {int rounds = 25}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

/// Counts how many times the app actually started a position share: the
/// thing consent gates.
class _ShareCounter {
  int starts = 0;
  final controller = StreamController<PositionFix>.broadcast();
  Stream<PositionFix> call() {
    starts++;
    return controller.stream;
  }
}

const _accept = Key('location-consent-accept');
const _askedAgain = Key('location-consent-asked-again');
const _withdraw = Key('location-consent-withdraw');

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sngnav_consent_record');
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

  File consentFile() => File('${tmp.path}/${LocationConsentStore.fileName}');

  Future<void> write(WidgetTester tester, Map<String, Object> record) =>
      tester.runAsync(() => consentFile().writeAsString(json.encode(record)));

  Future<Map<String, dynamic>> read(WidgetTester tester) async =>
      json.decode((await tester.runAsync(() => consentFile().readAsString()))!)
          as Map<String, dynamic>;

  /// A launch: the tree is torn down first, so this is a new session that
  /// reads the store, not the previous one continuing.
  Future<_ShareCounter> launch(WidgetTester tester, {String lang = 'ja'}) async {
    final c = _ShareCounter();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(SngnavApp(
      locale: Locale(lang),
      actuators: FakeAlertActuators(),
      clock: () => _start,
      jmaFetch: () async => const JmaFailure('test: no observation'),
      positionSource: c.call,
    ));
    await _settleIO(tester);
    return c;
  }

  Future<void> tapShare(WidgetTester tester) async {
    final b = find.byKey(const Key('share-location-button'));
    await tester.ensureVisible(b);
    await tester.pump();
    await tester.tap(b);
    await _settleIO(tester);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tapAccept(WidgetTester tester) async {
    await tester.tap(find.byKey(_accept));
    await _settleIO(tester);
  }

  List<String> currentWords(String lang) {
    final d = AppL10n(Locale(lang)).locationConsentDialog;
    return [d.title, d.drive, d.body, d.decline, d.accept];
  }

  testWidgets('her yes records exactly the words the dialog showed her',
      (tester) async {
    const l = AppL10n(Locale('ja'));
    final c = await launch(tester);
    await tapShare(tester);
    expect(find.byKey(_accept), findsOneWidget);
    expect(find.byKey(_askedAgain), findsNothing,
        reason: 'a first question needs no explanation');

    // What is on the screen, read from the widgets rather than the strings.
    final dialog = find.byType(AlertDialog);
    final shown = [
      tester.widget<Text>(find.descendant(
          of: dialog, matching: find.text(l.locationConsentTitle))).data!,
      tester
          .widget<KeepTogetherText>(
              find.byKey(const Key('location-consent-drive')))
          .data,
      tester.widget<Text>(find.byKey(const Key('location-consent-body'))).data!,
      tester.widget<Text>(find.descendant(
          of: find.byKey(const Key('location-consent-decline')),
          matching: find.byType(Text))).data!,
      tester.widget<Text>(find.descendant(
          of: find.byKey(_accept), matching: find.byType(Text))).data!,
    ];

    await tapAccept(tester);
    expect(c.starts, 1);
    final rec = await read(tester);
    expect(rec['locationShareConsent'], isTrue);
    expect(rec['disclosureRevision'], kLocationConsentRevision);
    expect(rec['disclosureLocale'], 'ja');
    expect(rec['disclosureWords'], shown,
        reason: 'the record names the words she was shown, no others');
    expect(rec['disclosureWords'], currentWords('ja'));
    await c.controller.close();
  });

  testWidgets('control: a yes to the current words is honoured on a later '
      'launch, with no question', (tester) async {
    await write(tester, {
      'schema': 2,
      'locationShareConsent': true,
      'decidedAt': '2026-09-25T00:00:00.000Z',
      'disclosureRevision': kLocationConsentRevision,
      'disclosureLocale': 'ja',
      'disclosureWords': currentWords('ja'),
    });
    final c = await launch(tester);
    expect(find.byKey(_withdraw), findsOneWidget,
        reason: 'a yes that is held can be taken back');
    await tapShare(tester);
    expect(find.byKey(_accept), findsNothing,
        reason: 'control: without this, every test below passes on a store '
            'that never honours anything');
    expect(c.starts, 1);
    await c.controller.close();
  });

  for (final (what, record) in <(String, Map<String, Object>)>[
    (
      'a yes written before revisions existed',
      {
        'schema': 1,
        'locationShareConsent': true,
        'decidedAt': '2026-09-24T00:00:00.000Z',
      },
    ),
    (
      'a yes to another revision',
      {
        'schema': 2,
        'locationShareConsent': true,
        'decidedAt': '2026-09-25T00:00:00.000Z',
        'disclosureRevision': kLocationConsentRevision + 1,
        'disclosureLocale': 'ja',
        'disclosureWords': ['other', 'words', 'she', 'was', 'shown'],
      },
    ),
  ]) {
    testWidgets('$what: she is asked once more, told why, and nothing starts '
        'until she answers', (tester) async {
      await write(tester, record);
      final c = await launch(tester);
      expect(find.byKey(_withdraw), findsNothing,
          reason: 'nothing is held, so there is nothing to take back');
      await tapShare(tester);
      expect(find.byKey(_accept), findsOneWidget, reason: 'asked once more');
      expect(find.byKey(_askedAgain), findsOneWidget, reason: 'and told why');
      expect(c.starts, 0, reason: 'the old yes starts nothing');

      await tapAccept(tester);
      expect(c.starts, 1);
      final rec = await read(tester);
      expect(rec['disclosureRevision'], kLocationConsentRevision);
      expect(rec['disclosureWords'], currentWords('ja'),
          reason: 'her new yes replaces the old one, with these words');
      await c.controller.close();

      // And once answered, she is not asked again.
      final c2 = await launch(tester);
      await tapShare(tester);
      expect(find.byKey(_accept), findsNothing);
      expect(c2.starts, 1);
      await c2.controller.close();
    });
  }

  // A DAMAGED RECORD IS NOT A CHANGE (2026-09-25, a dignity review). A yes
  // that names the current revision but whose words are missing or
  // unreadable is not honoured, so she is asked; but the words she was shown
  // have not changed, and the line 「この説明が変わりました」 would tell her
  // they had. She is asked plainly.
  for (final (what, record) in <(String, Map<String, Object>)>[
    (
      'no words',
      {
        'schema': 2,
        'locationShareConsent': true,
        'decidedAt': '2026-09-25T00:00:00.000Z',
        'disclosureRevision': kLocationConsentRevision,
      },
    ),
    (
      'an empty list of words',
      {
        'schema': 2,
        'locationShareConsent': true,
        'decidedAt': '2026-09-25T00:00:00.000Z',
        'disclosureRevision': kLocationConsentRevision,
        'disclosureLocale': 'ja',
        'disclosureWords': <String>[],
      },
    ),
    (
      'words that cannot be read',
      {
        'schema': 2,
        'locationShareConsent': true,
        'decidedAt': '2026-09-25T00:00:00.000Z',
        'disclosureRevision': kLocationConsentRevision,
        'disclosureLocale': 'ja',
        'disclosureWords': [1, 2, 3],
      },
    ),
  ]) {
    testWidgets('a yes to the current revision with $what: she is asked, '
        'and never told the description changed', (tester) async {
      await write(tester, record);
      final c = await launch(tester);
      await tapShare(tester);
      expect(find.byKey(_accept), findsOneWidget,
          reason: 'the record is not honoured, so she is asked');
      expect(find.byKey(_askedAgain), findsNothing,
          reason: 'nothing changed: the record is damaged, and saying '
              '「この説明が変わりました」 would be false');
      expect(c.starts, 0, reason: 'nothing starts until she answers');
      await c.controller.close();
    });
  }

  for (final (what, record) in <(String, Map<String, Object>)>[
    (
      'as written until 2026-09-25',
      {
        'schema': 1,
        'locationShareConsent': false,
        'decidedAt': '2026-09-24T00:00:00.000Z',
      },
    ),
    (
      'as written now',
      {
        'schema': 2,
        'locationShareConsent': false,
        'decidedAt': '2026-09-25T00:00:00.000Z',
      },
    ),
  ]) {
    testWidgets('a withdrawal on disk ($what) never leaves her with a share '
        'button that does nothing', (tester) async {
      await write(tester, record);
      final c = await launch(tester);
      await tapShare(tester);
      expect(find.byKey(_accept), findsOneWidget,
          reason: 'her tap must ASK. Before this change it did nothing at '
              'all: no dialog and no share');
      expect(find.byKey(_askedAgain), findsNothing,
          reason: 'she withdrew; a question after that needs no preface');
      expect(c.starts, 0);
      await c.controller.close();
    });
  }

  testWidgets('withdraw, relaunch, tap: she is asked, as the note promised',
      (tester) async {
    const l = AppL10n(Locale('ja'));
    await write(tester, {
      'schema': 2,
      'locationShareConsent': true,
      'decidedAt': '2026-09-25T00:00:00.000Z',
      'disclosureRevision': kLocationConsentRevision,
      'disclosureLocale': 'ja',
      'disclosureWords': currentWords('ja'),
    });
    final c = await launch(tester);
    final w = find.byKey(_withdraw);
    await tester.ensureVisible(w);
    await tester.pump();
    await tester.tap(w);
    await _settleIO(tester);
    expect(
        tester
            .widget<Text>(
                find.byKey(const Key('location-consent-withdrawn-note')))
            .data,
        l.locationConsentWithdrawnNote,
        reason: 'the note that makes the promise');
    expect((await read(tester))['locationShareConsent'], isFalse,
        reason: 'precondition: the withdrawal reached the disk');
    await c.controller.close();

    final c2 = await launch(tester);
    await tapShare(tester);
    expect(find.byKey(_accept), findsOneWidget,
        reason: 'the note said she would be asked again; on the next launch '
            'she must be');
    expect(c2.starts, 0);
    await c2.controller.close();
  });
}
