/// The weather publisher's name on the advisory card, rendered and looked at.
///
/// Why, written before the act (2026-09-18). The publisher label was the
/// literal 気象庁 in every locale, while the nine other English strings that
/// name the same body all say "JMA". On the English page that produced a card
/// headed 気象庁 above a sentence reading "Could not fetch from 気象庁." — an
/// English sentence whose only subject was in another script.
///
/// A widget tree is not a screen, so this file renders the real card to real
/// pixels and crops the region the publisher's name is painted into, so a
/// person can look at it.
///
/// Two font stacks, and the pair is the whole point:
///   * `cjk`   — a Japanese face loaded as the app's family. Her Akita phone.
///   * `latin` — a Latin-only face loaded as the app's family and nothing else.
///     A stack with no Japanese face is the honest worst case for an English
///     reader, and it is what decides this item: a glyph with no face to draw
///     it renders as a box or as nothing, and nothing looks like a clean
///     design.
///
/// Select with `HIE_R105_FACE=cjk|latin`; frames land in `$HIE_R105_OUT`.
///
/// Every check below is a verdict, not a note. A look that cannot go red has
/// never caught anything:
///   * the face must load, or the run fails — an unloaded face makes every
///     frame the test font's and the whole look is about the test font;
///   * the frame must carry more than a handful of distinct pixel values, or
///     the run fails — a blank PNG looks exactly like a drawn one in a file
///     listing;
///   * the crop of the label's own paint rectangle must not be a single flat
///     colour, or the run fails — that is the case where the name drew nothing
///     at all;
///   * the label's painted width is printed for both faces, so a name that
///     collapsed to zero advance is visible as a number and not only as an
///     absence.
///
/// Bounds: a host raster at device pixel ratio 2, not a phone and not an
/// in-vehicle panel. No timed glance. Which characters a box holds is read from
/// the text layer; that ink was laid down is read from the pixels.
library;

import 'dart:io';
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

final _outDir =
    Platform.environment['HIE_R105_OUT'] ?? '${Directory.systemTemp.path}/r105';
final _faceName = Platform.environment['HIE_R105_FACE'] ?? 'cjk';
final _libTag = Platform.environment['HIE_R105_LIB'] ?? 'unknown';

FaceSearch get _search =>
    _faceName == 'latin' ? FaceSearch.roboto : FaceSearch.ipaGothic;

final _jma = Advisory(
  source: AdvisorySource.jmaJapan,
  eventClass: '大雪警報',
  severity: AdvisorySeverity.severe,
  certainty: AdvisoryCertainty.unknown,
  urgency: AdvisoryUrgency.unknown,
  areaDescription: '秋田中央',
  effective: DateTime.utc(2026, 1, 15, 4, 23),
  expires: null,
  headline: '秋田県では、大雪に警戒してください。',
  description: '秋田県では、大雪に警戒してください。',
);

const _shotKey = Key('publisher-name-shot');

Widget _page(String lang, {required bool withError}) => MaterialApp(
  locale: Locale(lang),
  localizationsDelegates: const [
    AppL10n.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppL10n.supportedLocales,
  home: Scaffold(
    backgroundColor: Colors.white,
    body: RepaintBoundary(
      key: _shotKey,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: AdvisoryCards(
          loading: false,
          result: AdvisoryAggregateResult(
            advisories: withError ? const [] : [_jma],
            providerErrors: withError
                ? const [
                    AdvisoryProviderError(
                      source: AdvisorySource.jmaJapan,
                      message: 'HTTP 503',
                    ),
                  ]
                : const [],
            sourcesQueried: withError ? 0 : 1,
          ),
          errorMessage: null,
          onRefresh: () {},
        ),
      ),
    ),
  ),
);

class _Raw {
  _Raw(this.px, this.w, this.h);
  final Uint32List px;
  final int w;
  final int h;
  int distinct([Rect? r]) {
    final seen = <int>{};
    final x0 = (r?.left ?? 0).floor().clamp(0, w);
    final x1 = (r?.right ?? w.toDouble()).ceil().clamp(0, w);
    final y0 = (r?.top ?? 0).floor().clamp(0, h);
    final y1 = (r?.bottom ?? h.toDouble()).ceil().clamp(0, h);
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        seen.add(px[y * w + x]);
        if (seen.length > 4096) return seen.length;
      }
    }
    return seen.length;
  }
}

Future<_Raw> _raw(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_shotKey),
  );
  return (await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 1.0);
    final d = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final r = _Raw(d!.buffer.asUint32List(), img.width, img.height);
    img.dispose();
    return r;
  }))!;
}

Future<void> _writePng(
  WidgetTester tester,
  String path, {
  double scale = 2.0,
}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_shotKey),
  );
  final bytes = await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: scale);
    final d = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return d!.buffer.asUint8List();
  });
  File(path).writeAsBytesSync(bytes!);
  // ignore: avoid_print
  print('LOOK wrote ${path.split('/').last} ${bytes.length} bytes');
}

/// The label's paint rectangle, in the shot boundary's own coordinates.
Rect _rectOf(WidgetTester tester, Finder f) {
  final ro = tester.renderObject<RenderBox>(f);
  final boundary = tester.renderObject<RenderBox>(find.byKey(_shotKey));
  final tl = ro.localToGlobal(Offset.zero, ancestor: boundary);
  return tl & ro.size;
}

void main() {
  setUpAll(() => Directory(_outDir).createSync(recursive: true));

  for (final lang in const ['en', 'ja']) {
    for (final withError in const [false, true]) {
      final what = withError ? 'error-line' : 'card-head';
      testWidgets('$lang $what, face=$_faceName, lib=$_libTag', (tester) async {
        final loaded =
            await tester.runAsync(
              () => loadDiscoveredFace('Roboto', _search),
            ) ??
            false;
        expect(
          loaded,
          isTrue,
          reason:
              'face $_faceName did not load — every frame would be the test '
              'font\'s (searched ${describeFaceSearch(_search)})',
        );
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = const Size(393 * 2.0, 700 * 2.0);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_page(lang, withError: withError));
        await tester.pumpAndSettle();

        // The label is read from what the card DREW, never from the name the
        // code gives it. The harness has to render both the state before this
        // item and the state after it, and a harness pinned to the new code's
        // own vocabulary cannot compile against the old code — which would
        // leave the defect unrenderable and the comparison unmade.
        final l = AppL10n.of(tester.element(find.byType(AdvisoryCards)));
        final drawn = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .whereType<String>()
            .toList();
        // The card head is the Text that IS the publisher's name; the error
        // line is the sentence built around it. Exact match first, so the
        // card's attribution footer — which contains both spellings — cannot
        // be mistaken for the head.
        final head = drawn.where((t) => t == 'JMA' || t == '気象庁').toList();
        final sentence = drawn
            .where(
              (t) =>
                  t != 'JMA' &&
                  t != '気象庁' &&
                  (t.contains('JMA') || t.contains('気象庁')) &&
                  !t.startsWith('Source:'),
            )
            .toList();
        final target = withError
            ? (sentence.isEmpty ? '' : sentence.first)
            : (head.isEmpty ? '' : head.first);
        expect(
          target,
          isNotEmpty,
          reason: 'precondition: the surface names the publisher in the '
              '$what — drew ${drawn.map((t) => '「$t」').join(' ')}',
        );
        // Kept live so a locale whose composed sentence stops containing the
        // label is caught rather than silently measured.
        if (withError && head.isEmpty) {
          final inner = target.contains('JMA') ? 'JMA' : '気象庁';
          expect(
            l.advisoryPublisherErrored(inner),
            target,
            reason: 'the drawn error line must be the composed sentence',
          );
        }
        final finder = find.text(target);
        expect(
          finder,
          findsOneWidget,
          reason: 'precondition: the surface draws 「$target」',
        );

        final texts = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .whereType<String>()
            .toList();
        // ignore: avoid_print
        print(
          'LOOK $lang $what face=$_faceName lib=$_libTag TEXTS '
          '${texts.map((t) => '「$t」').join(' ')}',
        );

        final paragraph = tester.renderObject<RenderParagraph>(finder);
        final natural = paragraph.getMaxIntrinsicWidth(double.infinity);
        // ignore: avoid_print
        print(
          'LOOK $lang $what face=$_faceName lib=$_libTag '
          'STRING 「$target」 painted width ${paragraph.size.width.toStringAsFixed(1)} '
          'natural ${natural.toStringAsFixed(1)} px',
        );

        final raw = await _raw(tester);
        final whole = raw.distinct();
        // ignore: avoid_print
        print(
          'LOOK $lang $what face=$_faceName lib=$_libTag PIXELS '
          '${raw.w}x${raw.h} distinct=$whole',
        );
        expect(
          whole,
          greaterThan(8),
          reason:
              'the frame is blank or near-blank — a file that exists is not a '
              'surface that drew',
        );

        final rect = _rectOf(tester, finder);
        final inRect = raw.distinct(rect);
        // ignore: avoid_print
        print(
          'LOOK $lang $what face=$_faceName lib=$_libTag LABEL-RECT '
          '${rect.left.toStringAsFixed(1)},${rect.top.toStringAsFixed(1)} '
          '${rect.width.toStringAsFixed(1)}x${rect.height.toStringAsFixed(1)} '
          'distinct=$inRect',
        );
        expect(
          inRect,
          greaterThan(1),
          reason:
              'the rectangle the publisher\'s name is painted into is one flat '
              'colour — the name drew no ink at all in face $_faceName',
        );

        await _writePng(
          tester,
          '$_outDir/${lang}_${what}_${_faceName}_$_libTag.png',
        );
      });
    }
  }
}
