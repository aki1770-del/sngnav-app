/// Code 15's record card: each keep list is drawn on its own widget and holds
/// its words whole across line breaks, in every state the widget draws.
///
/// Why, written before the act (2026-10-10). Laid out at the line-break
/// guard's widths and text sizes, the failure line broke inside its own
/// negations, ending a line 「…何も送られて」 ("was sent") at 392.7 dp and text
/// size 1.0, and 「…渡せ」 at 2.0; the unavailable line ended 「…記録を開け」
/// ("can open"); the disclosure reversed one of its promises at a line end at
/// 12 of 21 sizes. The words that guarded the failure line sat on the count
/// line, which never draws it. The display review then gave one list per
/// widget: these pin that each list is on the widget that draws its words.
///
/// WHAT A PASS MEANS. In Japanese, at 360, 392.7 and 411.4 dp and text sizes
/// 0.85 to 2.0, with the share failed: the status (with a record, with an
/// empty record, and with none), the count line and the disclosure each lay
/// out so that no line break falls inside a word of that widget's list. Each
/// widget's screen-reader label is its plain words. A control lays the same
/// words out as plain Text at the same width and must split a listed word
/// somewhere in the sweep, for each widget, so a pass is not a blind reader;
/// and the split finder itself must report a planted split.
///
/// BOUNDS. Drawn with the Japanese face this host and CI discover
/// (render_see_env.dart); her phone's face is unmeasured. Laid out, not seen
/// on a device.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/app_theme.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/code15_fix_interval_record.dart';
import 'package:sngnav_app/widgets/keep_together.dart';

import '../render_see/render_see_env.dart';
import '../support/fake_alert_actuators.dart';

const _dpr = 2.75;
const _widths = [360.0, 1080 / _dpr, 411.4285714];
const _scales = [0.85, 1.0, 1.1, 1.15, 1.3, 1.5, 2.0];

/// The lines [p] draws: glyphs sharing one box top, joiners dropped.
List<String> _lines(RenderParagraph p) {
  final text = p.text.toPlainText(includeSemanticsLabels: false);
  final out = <String>[];
  final buf = StringBuffer();
  double? top;
  for (var i = 0; i < text.length; i++) {
    final b = p.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (b.isNotEmpty && b.first.right - b.first.left > 0.01) {
      if (top != null && b.first.top > top + 1) {
        out.add(buf.toString());
        buf.clear();
      }
      top = b.first.top;
    }
    if (text[i] != kWordJoiner) buf.write(text[i] == kNoBreakSpace ? ' ' : text[i]);
  }
  if (buf.isNotEmpty) out.add(buf.toString());
  return out;
}

/// Every break in [lines] that falls inside one of [words].
List<String> _splits(List<String> lines, List<String> words) {
  final text = lines.join();
  final out = <String>[];
  var at = 0;
  for (var k = 0; k < lines.length - 1; k++) {
    at += lines[k].length;
    for (final w in words) {
      for (var s = text.indexOf(w); s >= 0; s = text.indexOf(w, s + 1)) {
        if (s < at && at < s + w.length) {
          out.add('$w split: ${lines[k]}|${lines[k + 1]}'.replaceAll('\n', '⏎'));
        }
      }
    }
  }
  return out;
}

RenderParagraph _under(WidgetTester t, Finder f) => t.renderObject<RenderParagraph>(
    find.descendant(of: f, matching: find.byType(RichText), matchRoot: true).first);

JmaObservation _clear() => JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 8.0,
      humidityPercent: 50,
      windMetersPerSecond: 1.0,
      snowDepthCm: null,
      precipitation10mMm: 0.0,
      visibilityMeters: 20000,
      observedAtJstKey: '20260115060000',
      fetchedAt: DateTime.utc(2026, 1, 14, 21),
    );

void main() {
  setUpAll(() async {
    final ok = await loadDiscoveredFace('Roboto', FaceSearch.japanese);
    if (!ok) fail('no Japanese face on this host:\n  ${describeFaceSearch(FaceSearch.japanese)}');
  });

  const l = AppL10n(Locale('ja'));
  final controlSplits = <String, int>{};

  test('control: the split finder reports a planted split, and none on whole words', () {
    expect(_splits(['記録を端末の共有画面に渡せませんでした。何も送られて', 'いません。'],
        l.code15RecordStatusKeepTogether), hasLength(1));
    expect(_splits(['記録を端末の共有画面に渡せませんでした。何も', '送られていません。'],
        l.code15RecordStatusKeepTogether), isEmpty);
  });

  for (final w in _widths) {
    for (final s in _scales) {
      testWidgets('ja ${w.toStringAsFixed(1)} dp x$s: each list holds its words '
          'on its widget', (t) async {
        t.view.devicePixelRatio = _dpr;
        t.view.physicalSize = Size(w * _dpr, 2340);
        t.platformDispatcher.textScaleFactorTestValue = s;
        addTearDown(t.view.reset);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final bad = <String>[];
        final widths = <String, double>{};

        Future<void> pumpCard(String state, Code15FixIntervalRecord? record, Directory tmp) async {
          await t.pumpWidget(SngnavApp(
            key: ValueKey('$state $w $s'),
            locationConsent: true,
            actuators: FakeAlertActuators(),
            locale: const Locale('ja'),
            clock: () => DateTime.utc(2026, 1, 14, 21),
            jmaFetch: () async => JmaSuccess(_clear()),
            code15Record: record,
            code15RecordShareSink: (_) async => throw Exception('Share failed'),
            code15ShareCacheDirectory: Directory('${tmp.path}/cache'),
          ));
          for (var i = 0; i < 5; i++) {
            await t.pump();
          }
          if (record != null) {
            final b = find.byKey(const Key('code15-record-share-button'));
            await t.ensureVisible(b);
            await t.pump();
            await t.tap(b);
            for (var i = 0; i < 5; i++) {
              await t.pump();
            }
          }
        }

        void read(String name, Key key, List<String> words, String plain) {
          final f = find.byKey(key);
          final p = _under(t, f);
          widths[name] = p.constraints.maxWidth;
          bad.addAll(_splits(_lines(p), words).map((x) => '$name: $x'));
          final drawn = t.widget<Text>(find.descendant(of: f, matching: find.byType(Text), matchRoot: true));
          if (plainOf(drawn.data!) != plain) bad.add('$name: draws other words');
          if (drawn.data != plain && drawn.semanticsLabel != plain) {
            bad.add('$name: a screen reader is given ${drawn.semanticsLabel}');
          }
          if (words.isNotEmpty && drawn.data == plain && words.any(plain.contains)) {
            bad.add('$name: drawn without its keep list');
          }
        }

        final tmp = Directory.systemTemp.createTempSync('code15_keep_lists');
        addTearDown(() => tmp.deleteSync(recursive: true));

        // A record with fix lines, the share failed: failure line + present.
        final full = Code15FixIntervalRecord(directory: Directory('${tmp.path}/a')..createSync());
        for (var i = 1; i <= 20; i++) {
          full.record(
              share: 1,
              msSinceStreamStart: i * 5000,
              kind: FixEventKind.fine,
              accuracyMeters: 5,
              reportedSpeedMps: 13.4,
              lateMs: 200,
              appInFront: false);
        }
        await pumpCard('present', full, tmp);
        await t.ensureVisible(find.byKey(const Key('code15-record-disclosure')));
        await t.pump();
        read('status present', const Key('code15-record-status'), l.code15RecordStatusKeepTogether,
            '${l.code15RecordShareFailed}\n${l.code15RecordPresent}');
        final c = full.count;
        read(
            'count line',
            const Key('code15-record-count'),
            l.code15RecordCountKeep(
                movingMinutes: c.movingMs ~/ 60000, stoppedMinutes: c.stoppedMs ~/ 60000),
            l.code15RecordCount(
                movingMinutes: c.movingMs ~/ 60000,
                stoppedMinutes: c.stoppedMs ~/ 60000,
                minimumReached: c.minimumReached,
                full: full.full));
        read('disclosure', const Key('code15-record-disclosure'),
            l.code15RecordDisclosureKeepTogether, l.code15RecordDisclosure);

        // A record with no fix lines, the share failed: failure line + empty.
        final empty = Code15FixIntervalRecord(directory: Directory('${tmp.path}/b')..createSync());
        await pumpCard('empty', empty, tmp);
        await t.ensureVisible(find.byKey(const Key('code15-record-status')));
        await t.pump();
        read('status empty', const Key('code15-record-status'), l.code15RecordStatusKeepTogether,
            '${l.code15RecordShareFailed}\n${l.code15RecordEmpty}');

        // No record at all: the unavailable line.
        await pumpCard('unavailable', null, tmp);
        await t.ensureVisible(find.byKey(const Key('code15-record-status')));
        await t.pump();
        read('status unavailable', const Key('code15-record-status'),
            l.code15RecordStatusKeepTogether, l.code15RecordUnavailable);

        // Controls: the same words as plain Text, same theme, width and size.
        for (final (name, words, plain, size) in [
          ('status', l.code15RecordStatusKeepTogether,
              '${l.code15RecordShareFailed}\n${l.code15RecordPresent}', 12.0),
          ('status unavailable', l.code15RecordStatusKeepTogether, l.code15RecordUnavailable, 12.0),
          ('disclosure', l.code15RecordDisclosureKeepTogether, l.code15RecordDisclosure, 11.0),
        ]) {
          final width = widths[name == 'status' ? 'status present' : name]!;
          await t.pumpWidget(MaterialApp(
            theme: sngnavTheme(),
            home: Material(
              child: Center(
                child: SizedBox(
                  width: width,
                  child: Text(plain,
                      key: const Key('control'),
                      style: TextStyle(fontSize: size, color: Colors.grey.shade700)),
                ),
              ),
            ),
          ));
          controlSplits[name] = (controlSplits[name] ?? 0) +
              _splits(_lines(_under(t, find.byKey(const Key('control')))), words).length;
        }
        expect(bad, isEmpty, reason: 'at ${w.toStringAsFixed(1)} dp x$s');
      });
    }
  }

  tearDownAll(() {
    for (final name in ['status', 'status unavailable', 'disclosure']) {
      expect(controlSplits[name] ?? 0, greaterThan(0),
          reason: 'the plain-text control never split a word of the $name list: '
              'the reader is blind to it');
    }
  });
}
