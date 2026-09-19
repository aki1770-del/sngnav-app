/// A driver whose phone is set to English reads no Japanese on her page.
///
/// Why, written before the act (2026-09-19). The app follows the device's
/// language, so a driver reading English gets the English page. Measured on
/// that page before this test existed: twelve strings were still Japanese,
/// among them the two watch rows' labels and their verdicts. 該当なし ("none")
/// and 判定不能 ("cannot judge") are the one distinction those rows exist to
/// make, and to a reader of English they were two unreadable strings of the
/// same shape. The station names and place descriptions of the prefecture
/// table, the station on the Akita card and the station label on the map were
/// kanji too.
///
/// What is read: every Text and every RichText on the whole page (it is one
/// scroll view, so every card is built), with the Akita observation answered,
/// three stations of the prefecture table answered and two failed, so both
/// kinds of row are drawn. Any character from the CJK blocks, including
/// full-width punctuation, is a failure, unless its string is named in
/// [_allowed] with the reason it may stay.
///
/// Bound: one state of the page on a host test. Text drawn by a painter, the
/// map's own tiles and screen-reader labels are outside it; the screen-reader
/// labels are counted and printed, not held.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sngnav_app/corridor_row.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

/// Hiragana, katakana, CJK ideographs, CJK symbols and punctuation, and
/// full-width forms. Wider than a kana-and-kanji scan, so a stray （ or 、 in
/// an English string is found as well.
final _cjk = RegExp(
  '[\u3000-\u303F\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\uFF00-\uFFEF]',
);

/// Strings that may carry CJK on the English page, each with its reason.
/// Empty: nothing on this page in this state has a reason to.
const _allowed = <String, String>{};

/// Three stations answer, two fail, as the prefecture checks do.
http.Client _jmaNetwork() => MockClient((req) async {
      final u = req.url.toString();
      if (u.endsWith('/amedas/data/latest_time.txt')) {
        return http.Response('2026-01-15T06:00:00+09:00', 200);
      }
      final m = RegExp(r'/point/(\d+)/').firstMatch(u);
      if (m != null) {
        const ok = {
          '32286': (-2.1, 30, 7.5),
          '32402': (-1.0, 12, 6.0),
          '32551': (-4.3, 58, 2.1),
        };
        final v = ok[m.group(1)];
        if (v == null) return http.Response('', 500);
        return http.Response(
          '{"20260115060000":{"temp":[${v.$1},0],"snow":[${v.$2},0],'
          '"wind":[${v.$3},0],"humidity":[88,0]}}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('', 404);
    });

Future<JmaResult> _akita() async => JmaSuccess(
      JmaObservation(
        stationId: '32402',
        stationName: '秋田',
        temperatureCelsius: -1.0,
        humidityPercent: 88,
        windMetersPerSecond: 6.0,
        snowDepthCm: 12,
        precipitation10mMm: 0.5,
        visibilityMeters: null,
        observedAtJstKey: '20260115060000',
        fetchedAt: DateTime.utc(2026, 1, 14, 21, 1),
      ),
    );

Future<void> _settleReal(WidgetTester tester, [int n = 30]) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    final tmp = await Directory.systemTemp.createTemp('english_page');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  testWidgets('en: no Japanese anywhere on her page, with the Akita card '
      'answered and the prefecture table part answered, part failed',
      (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(393 * 2.0, 852 * 2.0);
    addTearDown(tester.view.reset);

    await http.runWithClient(() async {
      await tester.pumpWidget(SngnavApp(
        actuators: FakeAlertActuators(),
        locale: const Locale('en'),
        clock: () => DateTime.utc(2026, 1, 14, 21, 2),
        jmaFetch: _akita,
      ));
      await _settleReal(tester);

      // Controls: the page is the English page, and the rows this test is
      // about are drawn, so an empty result cannot come from a missing card.
      expect(find.text('Share my location'), findsWidgets,
          reason: 'control: the page is in English');
      expect(find.byType(CorridorRow), findsNWidgets(corridorStations.length),
          reason: 'control: the prefecture table has all its rows');
      expect(find.byKey(const Key('corridor-station-fetch-failed')),
          findsNWidgets(2),
          reason: 'control: two rows are the failed kind');
      expect(find.byKey(const Key('jma-refetch-button')), findsOneWidget,
          reason: 'control: the Akita card is in its answered state');

      final hits = <String>{};
      for (final e in find.byType(Text).evaluate()) {
        final d = (e.widget as Text).data;
        if (d != null && _cjk.hasMatch(d)) hits.add(d);
      }
      for (final e in find.byType(RichText).evaluate()) {
        final d = (e.widget as RichText).text.toPlainText();
        if (_cjk.hasMatch(d)) hits.add(d);
      }
      final allowed = hits.where(_allowed.containsKey).toList();
      final unexplained = hits.where((h) => !_allowed.containsKey(h)).toList()
        ..sort();

      // Screen-reader labels: counted and printed, not held (see the bound).
      final semantics = tester.ensureSemantics();
      await tester.pump();
      final srLabels = <String>{
        for (final e in find.bySemanticsLabel(_cjk).evaluate())
          e.renderObject?.debugSemantics?.label ?? '?',
      }.toList()
        ..sort();
      semantics.dispose();

      // ignore: avoid_print
      print('EN_PAGE[cjk] unexplained=${unexplained.length} '
          'allowed=${allowed.length} texts=$unexplained');
      // ignore: avoid_print
      print('EN_PAGE[screen_reader_labels_with_cjk] count=${srLabels.length} '
          'labels=$srLabels');
      expect(unexplained, isEmpty,
          reason: 'Japanese on the English page:\n${unexplained.join('\n')}');
    }, _jmaNetwork);
  });
}
