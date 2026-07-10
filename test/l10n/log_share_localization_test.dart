// C6 ログを共有 — ja/en localization of the beta-feedback share-log surface.
//
// Proves the share-log card renders in HER language (ja) with the
// consent-framing disclosure (user-initiated only, no auto-telemetry, no
// accounts, error-records-only / no location history), and that the en
// surface carries the same honesty facts.
//
// HONESTY (OPS-066 / AAE env-bound): this verifies the WIDGET TREE renders
// localized text in the test binding. It does NOT verify the OS share sheet
// on-device — there is no Android device/emulator in this env. On-device
// observation is DEFERRED.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/error_log.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sngnav_log_share_l10n');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  LocalErrorLog makeLog() =>
      LocalErrorLog(file: File('${tmp.path}/error_log.txt'));

  // Strings asserted against the ACTUAL emitted l10n values where compared
  // across locales, so a copy change can't silently pass a stale assertion.
  const jaL10n = AppL10n(Locale('ja'));
  const enL10n = AppL10n(Locale('en'));

  group('Share-log card — Locale(ja)', () {
    testWidgets('button + status + disclosure render in Japanese, no EN leak',
        (tester) async {
      final log = makeLog();
      log.record(StateError('l10n boom'), null);

      await tester.pumpWidget(SngnavApp(
        locale: const Locale('ja'),
        errorLog: log,
        logShareSink: (_) async {},
      ));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('share-log-button')));
      await tester.pump();

      // The one-tap action is HER language (BETA_PLAN's ログを共有, verbatim).
      expect(find.text('ログを共有'), findsOneWidget);
      expect(find.text('Share log'), findsNothing);
      // Records-present status in ja.
      expect(find.text(jaL10n.logShareHasRecords), findsOneWidget);
      expect(find.text(enL10n.logShareHasRecords), findsNothing);

      // Disclosure carries the load-bearing consent facts, in ja.
      final disclosure = tester
          .widget<Text>(find.byKey(const Key('log-share-disclosure')))
          .data!;
      expect(disclosure, contains('押したときだけ')); // user-initiated only
      expect(disclosure, contains('自動送信・テレメトリはなく')); // no auto-telemetry
      expect(disclosure, contains('アカウントも不要')); // no accounts
      expect(disclosure, contains('エラーの記録のみ')); // error records only
      expect(disclosure, contains('位置情報の履歴は含まれません')); // no location history
    });

    testWidgets('empty-log status renders the honest ja empty line',
        (tester) async {
      await tester.pumpWidget(SngnavApp(
        locale: const Locale('ja'),
        errorLog: makeLog(), // nothing recorded
        logShareSink: (_) async {},
      ));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('share-log-button')));
      await tester.pump();

      expect(find.text(jaL10n.logShareEmpty), findsOneWidget);
    });
  });

  group('Share-log card — Locale(en)', () {
    testWidgets('button + disclosure render in English with the same '
        'honesty facts', (tester) async {
      await tester.pumpWidget(SngnavApp(
        locale: const Locale('en'),
        errorLog: makeLog(),
        logShareSink: (_) async {},
      ));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('share-log-button')));
      await tester.pump();

      expect(find.text('Share log'), findsOneWidget);
      expect(find.text('ログを共有'), findsNothing);

      final disclosure = tester
          .widget<Text>(find.byKey(const Key('log-share-disclosure')))
          .data!;
      expect(disclosure, contains('only when you tap')); // user-initiated
      expect(disclosure, contains('no automatic upload')); // no auto-telemetry
      expect(disclosure, contains('no account')); // no accounts
      expect(disclosure, contains('only error records')); // records only
      expect(disclosure, contains('no location history')); // no location
    });
  });

  group('AppL10n unit — share-log strings', () {
    test('ja/en resolution + fallback', () {
      expect(jaL10n.shareLog, 'ログを共有');
      expect(enL10n.shareLog, 'Share log');
      // Unknown locale falls back to English (honest default).
      expect(const AppL10n(Locale('fr')).shareLog, 'Share log');
      // Section title is localized too (the card is HER-facing).
      expect(jaL10n.logShareSectionTitle, contains('ログを共有'));
      expect(enL10n.logShareSectionTitle, contains('share log'));
    });
  });
}
