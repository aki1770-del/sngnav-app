// HIE R116-30 PROBE — measurement only, not a guard. Renders the stacked
// honesty-banner states on the APP'S OWN chrome at HER phone geometry, writes
// the PNG for a human to look at, and prints the composited fills.
library;

import 'dart:io';
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

import 'render_see_env.dart';

const Key _shot = Key('hie-r116-30-shot');
const String _out = '/home/komada/Documents/LLMnotebooks/toyota flutter '
    'masterplan/outputs/hie/r116_30_glance_and_her_ground_2026_09_20/frames';

double _lin(int c) {
  final v = c / 255.0;
  return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
}

double _lum(int r, int g, int b) =>
    0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b);

double _contrastRgb(int a, int b) {
  final la = _lum((a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF);
  final lb = _lum((b >> 16) & 0xFF, (b >> 8) & 0xFF, b & 0xFF);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

String _hex(int rgb) =>
    '#${(rgb & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

/// Modal pixel inside a rect, inset to avoid borders/rounded corners.
int _modal(Uint32List px, int w, int h, Rect r, {double inset = 6}) {
  final x0 = (r.left + inset).floor().clamp(0, w - 1);
  final x1 = (r.right - inset).ceil().clamp(1, w);
  final y0 = (r.top + inset).floor().clamp(0, h - 1);
  final y1 = (r.bottom - inset).ceil().clamp(1, h);
  final counts = <int, int>{};
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final p = px[y * w + x];
      final rgb = ((p & 0xFF) << 16) | (((p >> 8) & 0xFF) << 8) | ((p >> 16) & 0xFF);
      counts[rgb] = (counts[rgb] ?? 0) + 1;
    }
  }
  var best = counts.keys.first;
  for (final e in counts.entries) {
    if (e.value > (counts[best] ?? 0)) best = e.key;
  }
  return best;
}

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 2.75;
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.padding = const FakeViewPadding(top: 73, bottom: 130);
  tester.view.viewPadding = const FakeViewPadding(top: 73, bottom: 130);
}

/// The app's real section chrome (lib/main.dart): Card > Padding(12) > Column.
Widget _host(String lang, AdvisoryAggregateResult r,
        {int? retained, String? err}) =>
    RepaintBoundary(
      key: _shot,
      child: MaterialApp(
        locale: Locale(lang),
        debugShowCheckedModeBanner: false,
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
                    errorMessage: err,
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

/// Stale feed AND an incomplete lookup: the two-banner stack.
const _staleAndIncomplete = AdvisoryAggregateResult(
  advisories: [],
  providerErrors: [],
  sourcesQueried: 0, // cannot prove the lookup was complete
  staleSources: [
    AdvisoryFeedStaleness(
      source: AdvisorySource.jmaJapan,
      age: Duration(days: 88),
      detail: '050000',
    ),
  ],
);

/// Stale feed AND a provider error: stale banner + degraded banner.
const _staleAndDegraded = AdvisoryAggregateResult(
  advisories: [],
  providerErrors: [
    AdvisoryProviderError(
      source: AdvisorySource.jmaJapan,
      message: 'SocketException: timeout',
      reason: AdvisoryUnavailableReason.timedOut,
    ),
  ],
  sourcesQueried: 1,
  staleSources: [
    AdvisoryFeedStaleness(
      source: AdvisorySource.jmaJapan,
      age: Duration(days: 88),
      detail: '050000',
    ),
  ],
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadCjkFamily('Roboto', japaneseFontSearchOrder());
    await loadBundledSymbolsFont();
    await loadMaterialIconsFont();
    Directory(_out).createSync(recursive: true);
  });

  Future<void> shoot(WidgetTester tester, String name) async {
    final raw = await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
      final img = await b.toImage(pixelRatio: 1.0);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      final rgba = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      final out = (rgba!.buffer.asUint32List(), img.width, img.height);
      img.dispose();
      return out;
    });
    final (px, w, h) = raw!;

    // Every honesty banner Container on this surface, by key.
    const keys = [
      'advisory_stale_feed_banner',
      'advisory-lookup-incomplete',
      'advisory-unknown-degraded',
      'advisory-fetch-failed-banner',
      'advisory-no-covering-publisher',
    ];
    // ⚑ C3: if the probe cannot find what it measures, it must SAY SO loudly.
    final allKeys = <String>[];
    void walkW(Element e) {
      final k = e.widget.key;
      if (k != null) allKeys.add('$k<${e.widget.runtimeType}>');
      e.visitChildren(walkW);
    }
    tester.allElements.first.visitAncestorElements((e) => false);
    walkW(tester.element(find.byType(AdvisoryCards)));
    // ignore: avoid_print
    print('  KEYS IN TREE: $allKeys');

    final found = <String, (Rect, int)>{};
    for (final k in keys) {
      final f = find.byKey(Key(k));
      if (f.evaluate().isEmpty) continue;
      final ro = tester.renderObject<RenderBox>(f);
      final tl = ro.localToGlobal(Offset.zero);
      final rect = tl & ro.size;
      found[k] = (rect, _modal(px, w, h, rect));
    }
    // The card surface itself, sampled well below the banners.
    final cardRo = tester.renderObject<RenderBox>(find.byType(Card).first);
    final cardRect = cardRo.localToGlobal(Offset.zero) & cardRo.size;

    // ignore: avoid_print
    print('=== $name  ${w}x$h  cardRect=$cardRect');
    for (final e in found.entries) {
      // ignore: avoid_print
      print('  ${e.key.padRight(34)} fill=${_hex(e.value.$2)}  '
          'rect=${e.value.$1.top.toStringAsFixed(1)}..'
          '${e.value.$1.bottom.toStringAsFixed(1)}');
    }
    final ks = found.keys.toList();
    for (var i = 0; i < ks.length; i++) {
      for (var j = i + 1; j < ks.length; j++) {
        final c = _contrastRgb(found[ks[i]]!.$2, found[ks[j]]!.$2);
        // ignore: avoid_print
        print('  PAIR ${ks[i]} / ${ks[j]} = ${c.toStringAsFixed(3)}:1');
      }
    }
    // The vertical gap between consecutive banner rects, and what is in it.
    for (var i = 0; i + 1 < ks.length; i++) {
      final a = found[ks[i]]!.$1, b = found[ks[i + 1]]!.$1;
      final gap = b.top - a.bottom;
      // ignore: avoid_print
      print('  GAP ${ks[i]} -> ${ks[i + 1]} = ${gap.toStringAsFixed(1)} px');
    }
  }

  testWidgets('P1 ja stale + lookup-incomplete', (tester) async {
    _phone(tester);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host('ja', _staleAndIncomplete));
    await tester.pumpAndSettle();
    await shoot(tester, 'P1_ja_stale_plus_incomplete');
  });

  testWidgets('P2 ja stale + degraded', (tester) async {
    _phone(tester);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host('ja', _staleAndDegraded));
    await tester.pumpAndSettle();
    await shoot(tester, 'P2_ja_stale_plus_degraded');
  });

  testWidgets('P3 en stale + lookup-incomplete', (tester) async {
    _phone(tester);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host('en', _staleAndIncomplete));
    await tester.pumpAndSettle();
    await shoot(tester, 'P3_en_stale_plus_incomplete');
  });
}
