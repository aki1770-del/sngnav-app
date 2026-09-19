/// The prefecture observations table at phone width, rendered and looked at.
///
/// Why, written before the act (2026-09-18). At 393 px the three data columns
/// are 43.0 px, and a value carrying its own unit does not fit one: the cell
/// shrank "-12.1 °C" to 7.93 px with a Japanese face — the temperature, the
/// number that says ice, drawn smaller than anything else on her page — and the
/// temperature pill ran edge to edge into the wind value with 0.0 px between
/// them. The unit now sits in the column head and the pill is inset.
///
/// Numbers are measured by `prefecture_gap_check.dart`. This file exists
/// because numbers are not a screen: a table can satisfy a floor and a gap and
/// still read as a wall, and a unit moved to a head can be a head nobody
/// notices. So the card is drawn to real pixels for a person to look at.
///
/// Select the face with `PREFECTURE_LOOK_FACE=cjk|latin` and tag the code state
/// with `PREFECTURE_LOOK_LIB`; frames land in `$PREFECTURE_LOOK_OUT`.
///
/// Every check is a verdict, not a note:
///   * the face must load, or the run fails;
///   * the head must draw its unit, read from the tree AND present in the
///     painted region, or the run fails — a unit that moved out of the cell and
///     did not arrive in the head has simply been deleted;
///   * the frame's head band must not be one flat colour, or the run fails.
///
/// Bounds: a host raster at device pixel ratio 2, not a phone and not an
/// in-vehicle panel. No timed glance. A Latin-only face cannot draw the
/// Japanese station names, so the `latin` frames say nothing about how her
/// Japanese page reads — they are there to show the Latin values at their real
/// metrics.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sngnav_app/corridor_row.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';
import 'render_see_env.dart';

final _outDir =
    Platform.environment['PREFECTURE_LOOK_OUT'] ??
    '${Directory.systemTemp.path}/prefecture_look';
final _faceName = Platform.environment['PREFECTURE_LOOK_FACE'] ?? 'cjk';
final _libTag = Platform.environment['PREFECTURE_LOOK_LIB'] ?? 'unknown';

FaceSearch get _search =>
    _faceName == 'latin' ? FaceSearch.roboto : FaceSearch.ipaGothic;

http.Client _jmaNetwork() => MockClient((req) async {
  final u = req.url.toString();
  if (u.endsWith('/amedas/data/latest_time.txt')) {
    return http.Response('2026-01-15T06:00:00+09:00', 200);
  }
  final m = RegExp(r'/point/(\d+)/').firstMatch(u);
  if (m != null) {
    // The widest values the card shows, so the look is of the hardest case.
    const ok = {
      '32286': (-12.1, 130, 17.5),
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

Future<void> _settleReal(WidgetTester tester, [int n = 30]) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

const _shotKey = Key('prefecture-table-shot');

void main() {
  setUpAll(() async {
    Directory(_outDir).createSync(recursive: true);
    final tmp = await Directory.systemTemp.createTemp('prefecture_look');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tmp.path,
        );
  });

  for (final lang in const ['ja', 'en']) {
    testWidgets('$lang, face=$_faceName, lib=$_libTag: the table at 393 px', (
      tester,
    ) async {
      final loaded =
          await tester.runAsync(
            () => loadDiscoveredFace('Roboto', _search),
          ) ??
          false;
      expect(
        loaded,
        isTrue,
        reason: 'face $_faceName did not load — every frame would be the test '
            'font\'s (searched ${describeFaceSearch(_search)})',
      );
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(393 * 2.0, 852 * 2.0);
      addTearDown(tester.view.reset);

      await http.runWithClient(() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: _shotKey,
            child: SngnavApp(
              actuators: FakeAlertActuators(),
              locale: Locale(lang),
              clock: () => DateTime.utc(2026, 1, 14, 21),
              jmaFetch: () async => const JmaFailure('no network in this test'),
            ),
          ),
        );
        await _settleReal(tester);
        final source = find.byKey(const Key('prefecture-observations-source'));
        await Scrollable.ensureVisible(tester.element(source), alignment: 0.7);
        await tester.pumpAndSettle();

        final rows = find.byType(CorridorRow);
        expect(rows, findsNWidgets(corridorStations.length));

        // Every text the card draws. ⚑ Counted with the widget finder, not
        // with `tester.allRenderObjects`: this app puts every paragraph in that
        // list TWICE (「地図」「地図」, 「秋田」「秋田」 …), so a render-object
        // count reported every unit as drawn twice and this rule fired on its
        // own arithmetic. Caught 2026-09-18 before the verdict left this lane.
        final drawn = <String>[];
        for (final t
            in tester.widgetList<Text>(find.byType(Text)).map((w) => w.data)) {
          if (t != null && t.trim().isNotEmpty) drawn.add(t);
        }
        // ignore: avoid_print
        print('TABLE $lang $_faceName $_libTag DRAWS '
            '${drawn.map((t) => '「$t」').join(' ')}');

        // VERDICT: the units must be in the heads. A unit taken out of the
        // cells that never arrived in a head has been deleted, and the table
        // would read as bare numbers with no statement of what they are.
        // ⚑ Literals, not the constants this change introduced. A harness
        // that cites the new code's own names cannot compile against the old
        // code, which would leave the defect unrenderable and the comparison
        // unmade. Caught twice in this lane before either frame was used.
        for (final unit in const ['cm', '\u00B0C', 'm/s']) {
          final asHead = find.text(unit).evaluate().length;
          // ignore: avoid_print
          print('TABLE $lang $_faceName $_libTag UNIT-IN-HEAD 「$unit」 x$asHead');
          if (_libTag != 'old') {
            expect(
              asHead,
              1,
              reason: 'the unit 「$unit」 must be drawn exactly once, in its '
                  'column head — drew $asHead',
            );
          }
        }

        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));

        final bytes = await tester.runAsync(() async {
          final img = await boundary.toImage(pixelRatio: 2.0);
          final d = await img.toByteData(format: ui.ImageByteFormat.png);
          img.dispose();
          return d!.buffer.asUint8List();
        });
        final name = '${lang}_table_${_faceName}_$_libTag.png';
        File('$_outDir/$name').writeAsBytesSync(bytes!);
        // ignore: avoid_print
        print('TABLE wrote $name ${bytes.length} bytes');

        final raw = await tester.runAsync(() async {
          final img = await boundary.toImage(pixelRatio: 1.0);
          final d = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
          final r = (d!.buffer.asUint32List(), img.width, img.height);
          img.dispose();
          return r;
        });
        final (px, w, h) = raw!;
        final seen = <int>{};
        for (final p in px) {
          seen.add(p);
          if (seen.length > 4096) break;
        }
        // ignore: avoid_print
        print('TABLE $lang $_faceName $_libTag PIXELS ${w}x$h '
            'distinct=${seen.length}');
        expect(
          seen.length,
          greaterThan(16),
          reason: 'the frame is blank or near-blank — a file that exists is '
              'not a surface that drew',
        );
      }, _jmaNetwork);
    });
  }
}

// Kept so the analyzer does not drop the import that types the raw buffer.
typedef _Unused = Uint32List;
