// HIE R116-22 — the WCAG AA text floor on the advisory card, measured from the
// pixels the card actually paints.
//
// WHY, before the act: on 2026-09-20 (R116-17) I ruled the two-clock emphasis
// on this surface and named three runs I did NOT fix — the severity pill at
// 3.45:1, the 開始 timestamp at 4.17:1 and the publisher attribution at
// 2.42:1, all below the 4.5:1 floor for text below 18pt. Those were measured
// on ONE severity, the `minor` of that fixture. Re-measured here across all
// five, the pill is below the floor at EVERY severity and the worst is
// `moderate` at 1.843:1 — the level a 大雪警報 carries. The severity word on a
// snow warning is the word she is least able to read.
//
// WHAT THIS GUARD PINS — the PROPERTY, never a constant. It reads no colour
// name from the app. For every paragraph the card paints it takes:
//   ink    = the colour the render tree resolved for that run, and
//   ground = the modal pixel under that run's rect in the REAL rasterised
//            frame, excluding pixels near the ink (those are glyph and
//            anti-alias), so the ground is the composite she sees and not a
//            constant anyone declared,
// and asserts WCAG 2.1 contrast >= the floor that run's size and weight earn
// (4.5:1 normally, 3.0:1 for large text: >=24 px, or >=18.66 px bold).
// A palette change that keeps the numbers passes. A prettier palette that
// drops a run below the floor fails, whatever it is named.
//
// WHAT IT CANNOT SEE (HIE-5 tooth 2, the bound rides the claim):
//  - HOST RASTER, NOT THE PHONE. Only the geometry is the phone's (1080x2340,
//    DPR 2.75, insets 73/130, measured on the real device 2026-09-19).
//    flutter_test draws a black card stroke where the phone draws a faint
//    shadow, and the panel's gamma and backlight are not here.
//  - CONTRAST IS A PROXY. It says nothing about glare, a dirty screen, motion,
//    viewing distance, or colour-vision deficiency, which is not desaturation.
//  - NO TIMED GLANCE STUDY EXISTS. Clearing a floor is not evidence that a
//    driver reads the right meaning in the time she has. Still owed, still
//    not claimed.
//  - It measures text. It does not measure whether the RIGHT text is loudest;
//    that is the two-clock rule in advisory_two_clocks_hierarchy_test.dart.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/widgets/advisory_cards.dart';

const Key _shot = Key('hie-r116-22-shot');

/// WCAG 2.1 relative luminance from an sRGB triple.
double _lin(int c) {
  final v = c / 255.0;
  return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
}

double _lum(int r, int g, int b) =>
    0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b);

double _contrast(int a, int b) {
  final la = _lum((a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF);
  final lb = _lum((b >> 16) & 0xFF, (b >> 8) & 0xFF, b & 0xFF);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

String _hex(int rgb) =>
    '#${(rgb & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

/// WCAG 2.1 SC 1.4.3: large text is >=18pt (24 px) or >=14pt (18.66 px) bold.
double _floorFor(double? size, FontWeight? weight) {
  final s = size ?? 14.0;
  final bold = (weight?.value ?? 400) >= 700;
  return (s >= 24.0 || (bold && s >= 18.66)) ? 3.0 : 4.5;
}

int _rgbOf(Color c) =>
    ((c.r * 255).round() << 16) | ((c.g * 255).round() << 8) | (c.b * 255).round();

/// The composite behind a run: the most common pixel under its rect that is
/// NOT the ink and not an anti-alias blend close to it.
///
/// ⚑ Taken from the rasterised frame, never from a colour constant. A check
/// that reads its expectation from the app's own words agrees with the app
/// (HIE-14). Returns null when the rect holds no such pixel, and a null is
/// UNMEASURED, never a pass — the caller fails on it.
int? _groundUnder(Uint32List px, int w, int h, Rect r, int ink) {
  final x0 = r.left.floor().clamp(0, w - 1);
  final x1 = r.right.ceil().clamp(0, w);
  final y0 = r.top.floor().clamp(0, h - 1);
  final y1 = r.bottom.ceil().clamp(0, h);
  final counts = <int, int>{};
  final ir = (ink >> 16) & 0xFF, ig = (ink >> 8) & 0xFF, ib = ink & 0xFF;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final p = px[y * w + x];
      // toByteData(rawRgba) is R,G,B,A little-endian in a Uint32.
      final rr = p & 0xFF, gg = (p >> 8) & 0xFF, bb = (p >> 16) & 0xFF;
      final d = (rr - ir).abs() + (gg - ig).abs() + (bb - ib).abs();
      if (d < 96) continue; // glyph body and its anti-alias ramp
      final rgb = (rr << 16) | (gg << 8) | bb;
      counts[rgb] = (counts[rgb] ?? 0) + 1;
    }
  }
  if (counts.isEmpty) return null;
  var best = counts.keys.first;
  for (final e in counts.entries) {
    if (e.value > (counts[best] ?? 0)) best = e.key;
  }
  return best;
}

/// The DARKEST pixel actually painted under a run — the ink as the raster has
/// it, after every Opacity, blend and filter above it.
///
/// ⚑ A resolved TextStyle colour is what the app INTENDED; an ancestor
/// `Opacity` leaves it untouched and changes only the pixels. Measuring the
/// style would agree with the app and pass a card washed to 1.5:1.
int? _paintedInkUnder(Uint32List px, int w, int h, Rect r, int? ground) {
  if (ground == null) return null;
  final x0 = r.left.floor().clamp(0, w - 1);
  final x1 = r.right.ceil().clamp(0, w);
  final y0 = r.top.floor().clamp(0, h - 1);
  final y1 = r.bottom.ceil().clamp(0, h);
  final gl = _lum((ground >> 16) & 0xFF, (ground >> 8) & 0xFF, ground & 0xFF);
  int? best;
  var bestL = gl;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final p = px[y * w + x];
      final rr = p & 0xFF, gg = (p >> 8) & 0xFF, bb = (p >> 16) & 0xFF;
      final l = _lum(rr, gg, bb);
      if (l < bestL) {
        bestL = l;
        best = (rr << 16) | (gg << 8) | bb;
      }
    }
  }
  return best;
}

AdvisoryAggregateResult _result(AdvisorySeverity sev, {required bool stale,
        AdvisorySource source = AdvisorySource.jmaJapan}) =>
    AdvisoryAggregateResult(
      advisories: [
        Advisory(
          source: source,
          eventClass: '大雪警報',
          severity: sev,
          certainty: AdvisoryCertainty.likely,
          urgency: AdvisoryUrgency.expected,
          areaDescription: '秋田県',
          effective: DateTime.utc(2026, 5, 28, 5),
          expires: DateTime.utc(2026, 5, 29, 5),
          headline: '大雪警報',
          description: '大雪による交通障害に警戒してください。',
        ),
      ],
      providerErrors: const [],
      sourcesQueried: 1,
      staleSources: stale
          ? const [
              AdvisoryFeedStaleness(
                source: AdvisorySource.jmaJapan,
                age: Duration(days: 88),
                detail: '050000',
              ),
            ]
          : const [],
    );

/// The app's own section chrome, lib/main.dart — Card > Padding(12) > Column.
Widget _host(String lang, AdvisoryAggregateResult r, int? retained) =>
    RepaintBoundary(
      key: _shot,
      child: MaterialApp(
        locale: Locale(lang),
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
          useMaterial3: true,
          fontFamilyFallback: const ['SnGNavSymbols'],
        ),
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: AdvisoryCards(
                    loading: false,
                    result: r,
                    errorMessage: null,
                    onRefresh: () {},
                    retainedAgeMinutes: retained,
                    pointCovered: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 2.75;
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.padding = const FakeViewPadding(top: 73, bottom: 130);
  tester.view.viewPadding = const FakeViewPadding(top: 73, bottom: 130);
}

void main() {
  for (final lang in const ['ja', 'en']) {
    for (final sev in AdvisorySeverity.values) {
      testWidgets(
          'every run the advisory card paints clears its WCAG floor — '
          '$lang / ${sev.name}', (tester) async {
        _phone(tester);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_host(lang, _result(sev, stale: true), 10));
        await tester.pumpAndSettle();

        final raw = await tester.runAsync(() async {
          final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
          final img = await b.toImage(pixelRatio: 1.0);
          final d = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
          final out = (d!.buffer.asUint32List(), img.width, img.height);
          img.dispose();
          return out;
        });
        final (px, w, h) = raw!;

        // C3 — if the gate cannot find what it checks, it FAILS. An empty
        // match is UNMEASURED, never absence (HIE-3 C3).
        final paragraphs = <RenderParagraph>[];
        void walk(RenderObject o) {
          if (o is RenderParagraph) paragraphs.add(o);
          o.visitChildren(walk);
        }

        walk(tester.renderObject(find.byType(AdvisoryCards)));
        expect(paragraphs.length, greaterThan(4),
            reason: 'found ${paragraphs.length} paragraphs on the card — the '
                'guard measured nothing, which is not a pass');

        final failures = <String>[];
        var measured = 0;
        for (final p in paragraphs) {
          final style = p.text.style;
          final col = style?.color;
          final text = p.text.toPlainText().trim();
          if (col == null || text.isEmpty) continue;
          // An invisible spacer (the subline's reserved glyph box) paints no
          // ink; it is excluded by construction, not by name.
          if (col.a == 0) continue;
          final ink = _rgbOf(col);
          final o = p.localToGlobal(Offset.zero);
          final rect = Rect.fromLTWH(o.dx, o.dy, p.size.width, p.size.height);
          if (rect.bottom <= 0 || rect.top >= h) continue;
          final ground = _groundUnder(px, w, h, rect, ink);
          if (ground == null) {
            failures.add('「$text」 UNMEASURED — no ground pixel under its rect');
            continue;
          }
          measured++;
          final ratio = _contrast(ink, ground);
          final floor = _floorFor(style?.fontSize, style?.fontWeight);
          // ignore: avoid_print
          print('FLOOR[$lang/${sev.name}] 「$text」 ink=${_hex(ink)} '
              'ground=${_hex(ground)} ${ratio.toStringAsFixed(3)}:1 '
              'floor=$floor size=${style?.fontSize} w=${style?.fontWeight?.value}');
          if (ratio < floor) {
            failures.add('「$text」 ${_hex(ink)} on ${_hex(ground)} = '
                '${ratio.toStringAsFixed(3)}:1, below $floor:1 at '
                '${style?.fontSize} px w${style?.fontWeight?.value ?? 400}');
          }
        }
        expect(measured, greaterThan(4),
            reason: 'only $measured runs could be measured — UNMEASURED is '
                'never a pass');
        expect(failures, isEmpty,
            reason: 'runs below their WCAG floor on the advisory card '
                '($lang/${sev.name}):\n  ${failures.join('\n  ')}');
      });
    }
  }

  // ⚑ THE ENGLISH REFERENCE CARD, WHICH HAD NO GUARD AND WAS THE WORST CARD
  // ON THE SURFACE. An NWS advisory on the Japanese page is drawn
  // de-emphasized. Until 2026-09-20 that de-emphasis was `Opacity(0.55)` over
  // the whole card, which washed every run toward the surface behind it: the
  // event class to 3.753:1, the area and description to 2.290:1, the
  // attribution to 1.567:1 — every word naming a hazard below the floor. No
  // opacity under about 0.95 keeps the floor, so the channel itself was the
  // defect, not its setting. This case exists so that channel cannot come
  // back: it fails on ANY de-emphasis that spends her contrast budget,
  // whatever it is called.
  testWidgets(
      'the de-emphasized English reference card clears the floor too',
      (tester) async {
    _phone(tester);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(
        'ja',
        _result(AdvisorySeverity.severe,
            stale: false, source: AdvisorySource.nwsUnitedStates),
        null));
    await tester.pumpAndSettle();

    final raw = await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
      final img = await b.toImage(pixelRatio: 1.0);
      final d = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      final out = (d!.buffer.asUint32List(), img.width, img.height);
      img.dispose();
      return out;
    });
    final (px, w, h) = raw!;

    final paragraphs = <RenderParagraph>[];
    void walk(RenderObject o) {
      if (o is RenderParagraph) paragraphs.add(o);
      o.visitChildren(walk);
    }

    walk(tester.renderObject(find.byType(AdvisoryCards)));
    // C3 — the de-emphasis caption must be on screen, or this is not the
    // state under test and the run measured nothing.
    expect(find.text(AppL10n(const Locale('ja')).englishReferenceNote),
        findsOneWidget,
        reason: 'the reference caption is absent — this is not the '
            'de-emphasized card, so nothing here was measured');

    final failures = <String>[];
    var measured = 0;
    for (final p in paragraphs) {
      final style = p.text.style;
      final col = style?.color;
      final text = p.text.toPlainText().trim();
      if (col == null || text.isEmpty || col.a == 0) continue;
      final ink = _rgbOf(col);
      final o = p.localToGlobal(Offset.zero);
      final rect = Rect.fromLTWH(o.dx, o.dy, p.size.width, p.size.height);
      if (rect.bottom <= 0 || rect.top >= h) continue;
      // ⚑ The ink is taken from the RASTER here, not from the style. An
      // Opacity ancestor does not change a resolved TextStyle colour — it
      // changes the pixels. Reading the style would have agreed with the app
      // and passed the very defect this case exists for (HIE-14).
      final ground = _groundUnder(px, w, h, rect, ink);
      final painted = _paintedInkUnder(px, w, h, rect, ground);
      if (ground == null || painted == null) {
        failures.add('「$text」 UNMEASURED — no ground or no painted ink');
        continue;
      }
      measured++;
      final ratio = _contrast(painted, ground);
      final floor = _floorFor(style?.fontSize, style?.fontWeight);
      // ignore: avoid_print
      print('DEEMPH 「$text」 styleInk=${_hex(ink)} paintedInk=${_hex(painted)} '
          'ground=${_hex(ground)} ${ratio.toStringAsFixed(3)}:1 floor=$floor');
      if (ratio < floor) {
        failures.add('「$text」 painted ${_hex(painted)} on ${_hex(ground)} = '
            '${ratio.toStringAsFixed(3)}:1, below $floor:1');
      }
    }
    expect(measured, greaterThan(4),
        reason: 'only $measured runs measured — UNMEASURED is never a pass');
    expect(failures, isEmpty,
        reason: 'the de-emphasized reference card is below the floor:\n  '
            '${failures.join('\n  ')}');
  });
}
