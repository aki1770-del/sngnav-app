/// The next-turn banner's Japanese lines break between two phrases, never
/// inside one, at her phone's width and at every text size she may choose.
///
/// WHY. Until 2026-10-04 they broke inside words at her width (可能｜性,
/// ご判｜断, （現｜在地), and where they broke moved with every text size: clean
/// at 1.15 by luck, broken at 1.0, 1.3, 1.5 and 2.0. A word split across two
/// lines is read twice or misread, and she has a glance. The banner now draws
/// each line with a word joiner (U+2060) between the characters of each
/// phrase; what she hears and what a screen reader reads stay the plain line.
///
/// What this file holds, at 1080 px at 2.75 (the banner 328.7 dp on her card):
///
///  R4-1  at text sizes 1.0, 1.15, 1.3, 1.5 and 2.0, for every maneuver type
///        the localizer names (19), read as given and with a check, with no
///        ice, measured ice and a test value, and the paused state (115
///        cases): every line of the state, her line, the icy mark and the line
///        saying where it came from begins at a phrase boundary. A phrase wider
///        than its line is listed and FAILS; none is declared today.
///  R4-2  the voice never meets a joiner: in every case the line she hears is
///        the pinned plain line, byte for byte.
///  R4-3  (in test/l10n/maneuver_phrases_spell_the_line_test.dart, because it
///        draws through the app's own span) a joined line paints the pixels
///        of the plain line.
///  R4-4  a screen reader reads the plain line: no semantics label on the
///        banner carries a joiner, and each carries its line.
///  R4-5  without a Japanese face the file refuses to run: kanji drawn as
///        boxes break where boxes break, and that measures character counts.
///
/// The phrase boundaries come from test/support/maneuver_phrase_spec.dart,
/// pinned apart from lib/, never from the app's own lists.
///
/// What this file cannot see: her phone's own Japanese face (a host face
/// stands in), which moves WHERE among the boundaries a line breaks but not
/// whether a boundary is honoured; English, which breaks at its spaces; and
/// whether a line break in a phrase boundary reads well to her. No timed
/// glance study exists.
library;

import 'dart:io' show Directory;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:localization_fallback/localization_fallback.dart'
    show LocalizationMode;
import 'package:routing_engine/routing_engine.dart' show RouteManeuver;
import 'package:sngnav_app/app_theme.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/drive_hud_localizer.dart';
import 'package:sngnav_app/services/maneuver_narration.dart';
import 'package:sngnav_app/widgets/maneuver_narration_panel.dart';

import '../render_see/render_see_env.dart' show loadCjkFamily;
import '../support/maneuver_phrase_spec.dart';

/// Her phone: 1080 x 2340 px at 2.75; the banner 328.7 dp on her card.
const double _dpr = 2.75;
const double _bannerWidthDp = 328.7;
const _scales = [1.0, 1.15, 1.3, 1.5, 2.0];

/// Phrases allowed to break inside because they are wider than their line,
/// each with a reason. None today; a phrase that is too wide and not named
/// here FAILS.
const Map<String, String> _declaredTooWide = {};

const _bannerKey = Key('maneuver-narration-banner');
const _markKey = Key('maneuver-narration-state-mark');
const _narrator = ManeuverNarrator(text: DriveHudLocalizer());
const _ja = AppL10n(Locale('ja'));

String _plain(String drawn) => drawn.replaceAll(kSpecWordJoiner, '');

class _Case {
  _Case(this.type, this.mode, this.ice);
  final String type;
  final LocalizationMode mode;
  final IcyTurnSource ice;
  bool get hedged => mode == LocalizationMode.gpsSuspect;
  bool get paused => mode == LocalizationMode.lost;
  @override
  String toString() => paused ? 'paused' : '$type ${mode.name} ice=${ice.name}';
}

final List<_Case> _cases = [
  for (final type in kManeuverTypes)
    for (final mode in [LocalizationMode.gpsTrusted, LocalizationMode.gpsSuspect])
      for (final ice in IcyTurnSource.values) _Case(type, mode, ice),
  _Case('right', LocalizationMode.lost, IcyTurnSource.measured),
];

ManeuverNarration _decide(_Case c) => _narrator.decide(
      maneuver: RouteManeuver(
        index: 1,
        instruction: 'English from the routing engine',
        type: c.type,
        lengthKm: 0.4,
        timeSeconds: 30,
        position: const LatLng(39.72, 140.10),
      ),
      mode: c.mode,
      icyTurn: c.ice != IcyTurnSource.none,
      localeTag: 'ja',
    );

/// The pinned phrases of every line [c] puts on the banner, by plain line.
Map<String, List<String>> _expectedLines(_Case c) {
  final out = <String, List<String>>{};
  void add(List<String> p) => out[p.join()] = p;
  final tier = c.paused
      ? _ja.maneuverTierSuppressed
      : c.hedged
          ? _ja.maneuverTierHedge
          : _ja.maneuverTierSpeak;
  add(kPanelPhrasesSpec[tier]!);
  if (c.paused) {
    add(kPanelPhrasesSpec[_ja.maneuverGuidancePaused]!);
    return out;
  }
  add(herLinePhrasesSpec(c.type,
      hedged: c.hedged, icy: c.ice != IcyTurnSource.none));
  if (c.ice != IcyTurnSource.none) {
    add(kPanelPhrasesSpec[_ja.maneuverIcyMark]!);
    add(kPanelPhrasesSpec[c.ice == IcyTurnSource.measured
        ? _ja.maneuverMeasuredRoadIceInForce
        : _ja.maneuverTestRoadConditionInForce]!);
  }
  return out;
}

Widget _host(Widget child) => MaterialApp(
      locale: const Locale('ja'),
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      debugShowCheckedModeBanner: false,
      theme: sngnavTheme(),
      // The panel sits in a page that scrolls, as it does on her card: at
      // text size 2.0 the longest banner is most of her screen tall.
      home: Scaffold(
        body: SingleChildScrollView(
          child: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    );

Future<void> _pumpCase(WidgetTester tester, _Case c) async {
  final preview = _decide(c);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(_host(SizedBox(
    width: _bannerWidthDp,
    child: ManeuverNarrationPanel(
      preview: preview,
      mode: c.mode,
      isMockPosition: false,
      icySource: c.ice,
      onNarrate: () {},
      lastNarration: null,
      speechUnverified: false,
      hapticUnverified: false,
    ),
  )));
  await tester.pump();
  // The narrate button's row overflows the panel at large text sizes; that is
  // named and held in test/widgets/maneuver_banner_states_test.dart, not here.
  // Only that overflow is let through.
  final e = tester.takeException();
  if (e != null) {
    expect('$e', contains('A RenderFlex overflowed by'),
        reason: '$c: an exception other than the known button-row overflow');
  }
}

/// The first offset, in the PLAIN line, of every line [rp] lays out.
///
/// Each character's box is asked for at the LINE's full height
/// ([ui.BoxHeightStyle.max]), so every box on one line has the same top,
/// whichever font drew it. With glyph-tight boxes, the ❄ from the bundled
/// symbol font sat higher than the kanji beside it, and at text size 2.0 that
/// read as a line break that was not there.
List<int> _lineStarts(RenderParagraph rp) {
  final drawn = rp.text.toPlainText();
  final starts = <int>[];
  double? lastTop;
  var plainAt = 0;
  for (var i = 0; i < drawn.length; i++) {
    if (drawn[i] == kSpecWordJoiner) continue;
    final boxes = rp.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
        boxHeightStyle: ui.BoxHeightStyle.max);
    if (boxes.isNotEmpty) {
      final top = boxes.first.top;
      if (lastTop == null || top > lastTop + 1.0) {
        starts.add(plainAt);
        lastTop = top;
      }
    }
    plainAt++;
  }
  return starts;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // R4-5. A Japanese face under 'Roboto', the family the app's theme draws
    // in. Without one the file refuses: it would measure boxes.
    final ok = await loadCjkFamily('Roboto', [
      '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf',
      '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf',
    ]);
    if (!ok) {
      throw StateError('no Japanese face on this host: line breaks would be '
          'measured on boxes, not on her words. Not a pass.');
    }
    final tmp = await Directory.systemTemp.createTemp('phrase_breaks');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  test('the pinned phrases spell the lines the app draws and says', () {
    expect(_cases.length, 115);
    for (final c in _cases) {
      final preview = _decide(c);
      final lines = _expectedLines(c);
      final her = c.paused ? _ja.maneuverGuidancePaused : preview.text;
      expect(lines.keys, contains(her),
          reason: '$c: her line "$her" is not the pinned one');
    }
  });

  for (final scale in _scales) {
    testWidgets(
        'R4-1 at text size $scale, every line on the banner begins between '
        'two phrases (${_cases.length} cases)', (tester) async {
      tester.view.devicePixelRatio = _dpr;
      tester.view.physicalSize = const Size(1080, 2340);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      var lines = 0;
      var tallest = 0.0;
      var tallestCase = '';
      final inside = <String>[];
      final tooWide = <String>[];
      for (final c in _cases) {
        await _pumpCase(tester, c);
        final expected = _expectedLines(c);
        final markTexts = find
            .descendant(of: find.byKey(_markKey), matching: find.byType(RichText))
            .evaluate()
            .map((e) => e.widget)
            .toSet();
        final seen = <String>{};
        for (final e in find
            .descendant(of: find.byKey(_bannerKey), matching: find.byType(RichText))
            .evaluate()) {
          if (markTexts.contains(e.widget)) continue;
          final rp = e.renderObject! as RenderParagraph;
          final plain = _plain(rp.text.toPlainText());
          final phrases = expected[plain];
          expect(phrases, isNotNull,
              reason: '$c at $scale: the banner draws "$plain", a line the '
                  'pinned spec does not know. Not measured is a FAIL.');
          seen.add(plain);
          final ok = phraseBoundaries(phrases!);
          final starts = _lineStarts(rp);
          lines += starts.length;
          for (final s in starts.skip(1)) {
            if (ok.contains(s)) continue;
            // Which phrase does the line begin inside, and is it wider than
            // the line?
            var at = 0;
            final p = phrases.firstWhere((p) {
              final hit = s > at && s < at + p.length;
              at += p.length;
              return hit;
            });
            final style = rp.text.style;
            final tp = TextPainter(
              text: TextSpan(text: p.trimRight(), style: style),
              textDirection: TextDirection.ltr,
              textScaler: rp.textScaler,
            )..layout();
            final wide = tp.width > rp.constraints.maxWidth;
            tp.dispose();
            final shown =
                '${plain.substring(0, s)}｜${plain.substring(s)}';
            if (wide && !_declaredTooWide.containsKey(p)) {
              tooWide.add('$c: "$p" is wider than its line: $shown');
            } else if (!wide) {
              inside.add('$c: $shown');
            }
          }
        }
        expect(seen, expected.keys.toSet(),
            reason: '$c at $scale: a pinned line was not found on the banner');
        final h = tester.getSize(find.byKey(_bannerKey)).height;
        if (h > tallest) {
          tallest = h;
          tallestCase = '$c';
        }
      }
      // ignore: avoid_print
      print('R4-1 x$scale: ${_cases.length} cases, $lines lines, '
          '${inside.length} begin inside a phrase, ${tooWide.length} phrases '
          'too wide; tallest banner ${tallest.toStringAsFixed(1)} dp '
          '($tallestCase)');
      if (inside.isNotEmpty || tooWide.isNotEmpty) {
        // ignore: avoid_print
        print('lines that begin inside a phrase, as she reads them '
            '(｜ marks a line break):\n  ${[...inside, ...tooWide].take(40).join('\n  ')}');
      }
      expect(inside, isEmpty,
          reason: 'at text size $scale, ${inside.length} lines begin inside a '
              'phrase');
      expect(tooWide, isEmpty,
          reason: 'at text size $scale, ${tooWide.length} phrases are wider '
              'than their line and are not declared');
    });
  }

  testWidgets('R4-2 the voice never meets a joiner, and says the pinned line',
      (tester) async {
    for (final c in _cases) {
      final preview = _decide(c);
      if (c.paused) {
        expect(preview.text, isEmpty,
            reason: 'a paused turn carries no spoken line');
        continue;
      }
      expect(preview.text.contains(kSpecWordJoiner), isFalse, reason: '$c');
      expect(
          preview.text,
          herLinePhrasesSpec(c.type,
                  hedged: c.hedged, icy: c.ice != IcyTurnSource.none)
              .join(),
          reason: '$c: the spoken line is not the pinned one');
    }
  });

  testWidgets('R4-4 a screen reader reads plain words on the banner',
      (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.devicePixelRatio = _dpr;
    tester.view.physicalSize = const Size(1080, 2340);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final c in _cases) {
      await _pumpCase(tester, c);
      for (final line in _expectedLines(c).keys) {
        final node = tester.getSemantics(find.bySemanticsLabel(line));
        expect(node.label, line, reason: '$c');
      }
      for (final e in find
          .descendant(of: find.byKey(_bannerKey), matching: find.byType(Text))
          .evaluate()) {
        final label = tester.getSemantics(find.byWidget(e.widget)).label;
        expect(label.contains(kSpecWordJoiner), isFalse,
            reason: '$c: a semantics label carries a word joiner: "$label"');
      }
    }
    handle.dispose();
  });
}
