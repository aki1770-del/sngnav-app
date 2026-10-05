/// What her press did reaches her: the narrate button and the lines under it,
/// at her phone's width and at every text size she may choose, read from the
/// painted pixels.
///
/// WHY. Until 2026-10-04 the button and the lines saying what her press did
/// shared one Row, and a Row lays out the button first, at its own width, and
/// gives the lines what is left. At her width nothing was left at the large
/// text sizes, so the lines were laid out 0 dp wide. A Text 0 dp wide is not
/// clipped: its painter's width is clamped to the same 0, so the paragraph
/// never sees an overflow. Each line was drawn one character per line down
/// the right edge of her card, the row grew to fit them, and the button she
/// had just pressed moved down with it. One of those lines is the warning
/// that neither the voice nor the vibration could be confirmed, written for
/// the driver for whom one channel is the only channel. And in English the
/// button itself ran past the banner and off her screen.
///
/// No test drew those lines at her width, and no guard read their pixels: the
/// floor in maneuver_narration_panel_test.dart holds the banner's words, and
/// maneuver_delivery_unverified_renders_test.dart reads the declared colour
/// at the test's default width.
///
/// What each case holds, at 1080 px at 2.75 (the panel 328.7 dp wide on her
/// card, painted on the card's own colour, in the app's theme, with a
/// Japanese face), in Japanese and English, at text sizes 1.0, 1.15, 1.3, 1.5
/// and 2.0, after a press, for each thing the card can say about it (sent;
/// sent with the voice, the vibration or both unconfirmed; nothing read):
///
///  P1  No exception of any kind: nothing in the panel overflows.
///  P2  The button lies inside the panel, both edges, and does not move when
///      the lines appear under it.
///  P3  Each line under the button is found (not finding it FAILS), is laid
///      out wider than zero, every character it draws lies inside its own
///      box, and the box lies inside the panel. A character outside its box
///      is drawn where she was never meant to look. (Spaces are not counted:
///      the engine places a space that ends a wrapped line past the width.)
///  P4  Each line is painted at 4.5:1 or more against the ground painted
///      behind it, read from the raster: the ground is the commonest colour
///      in the line's box, the ink the pixel that contrasts most with it. A
///      line with no pixel apart from its ground is UNMEASURED, and a FAIL.
///  P5  Controls, so that P4 can fail: the same measure, on a line painted
///      in grey.shade500 on her card (ink distinct from the ground and below
///      the floor), must read above 1.0 and below 4.5; and on a line painted
///      in the ground's own colour it must report no ink at all.
///
/// And the button itself is offered only when the turn will be read aloud
/// (O1 to O5, at the test that holds them; under 「読み上げません」 it was
/// enabled and said 「次の案内を読み上げる」), and a line about an earlier press
/// is drawn only while it agrees with the banner (O6).
///
/// What this file cannot see: her phone's own fonts (a host Japanese face
/// stands in, and the file refuses to run without one), a real panel, glare,
/// distance, and time. A line held at the floor is a line that can be read;
/// whether she reads it, and when, is not measured. No timed glance study
/// exists.
library;

import 'dart:io' show Directory;
import 'dart:math' as math;
import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderParagraph, RenderRepaintBoundary;
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
import '../support/plain_words.dart';

/// Her phone: 1080 x 2340 px at 2.75.
const double _dpr = 2.75;

/// The panel's width on her card at that geometry, measured in the app
/// 2026-10-04 (the banner spans the panel).
const double _panelWidthDp = 328.7;

const _scales = [1.0, 1.15, 1.3, 1.5, 2.0];

/// The app's floor for text (WCAG 2.x AA, 1.4.3).
const double _floor = 4.5;

const _shotKey = Key('maneuver-press-result-shot');
const _panelKey = Key('maneuver-press-result-panel');
const _buttonKey = Key('maneuver-narrate-button');
const _resultKey = Key('maneuver-narration-result');
const _deliveryKey = Key('maneuver-narration-delivery-unverified');

const _rightTurn = RouteManeuver(
  index: 1,
  instruction: 'Right onto Main St',
  type: 'right',
  lengthKm: 0.4,
  timeSeconds: 30,
  position: LatLng(39.72, 140.10),
);

/// What the card can say about her press.
enum _Said {
  sent,
  voiceUnconfirmed,
  vibrationUnconfirmed,
  bothUnconfirmed,
  notRead,
}

class _Case {
  const _Case(this.said);
  final _Said said;
  LocalizationMode get mode => said == _Said.notRead
      ? LocalizationMode.lost
      : LocalizationMode.gpsTrusted;
  bool get speech =>
      said == _Said.voiceUnconfirmed || said == _Said.bothUnconfirmed;
  bool get haptic =>
      said == _Said.vibrationUnconfirmed || said == _Said.bothUnconfirmed;

  /// The keys of the lines this case must draw under the button.
  List<Key> get lines => [
        _resultKey,
        if (said != _Said.notRead && (speech || haptic)) _deliveryKey,
      ];
}

ManeuverNarration _decide(LocalizationMode mode, String lang) =>
    const ManeuverNarrator(text: DriveHudLocalizer()).decide(
      maneuver: _rightTurn,
      mode: mode,
      icyTurn: false,
      localeTag: lang,
    );

Widget _host({required Locale locale, required Widget child}) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      debugShowCheckedModeBanner: false,
      theme: sngnavTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: _shotKey,
              // Her card's own colour, as the app's section card paints it.
              child: Builder(
                builder: (context) => ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child:
                      Padding(padding: const EdgeInsets.all(4), child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );

Widget _panel(_Case c, String lang, {required bool pressed}) {
  final preview = _decide(c.mode, lang);
  return SizedBox(
    key: _panelKey,
    width: _panelWidthDp,
    child: ManeuverNarrationPanel(
      preview: preview,
      mode: c.mode,
      isMockPosition: false,
      icySource: IcyTurnSource.none,
      onNarrate: () {},
      // The decision her press was dispatched with is the gate's decision for
      // the same turn and position, as in the app.
      lastNarration: pressed ? preview : null,
      speechUnverified: c.speech,
      hapticUnverified: c.haptic,
    ),
  );
}

final List<double> _toLinear = [
  for (var i = 0; i < 256; i++)
    i / 255 <= 0.04045
        ? (i / 255) / 12.92
        : math.pow(((i / 255) + 0.055) / 1.055, 2.4).toDouble(),
];

double _lum(int rgb) =>
    0.2126 * _toLinear[rgb >> 16] +
    0.7152 * _toLinear[(rgb >> 8) & 0xFF] +
    0.0722 * _toLinear[rgb & 0xFF];

double _ratio(double a, double b) =>
    (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);

class _Raster {
  _Raster(this.rgba, this.width, this.height);
  final ByteData rgba;
  final int width, height;
  int at(int x, int y) {
    final i = (y * width + x) * 4;
    return (rgba.getUint8(i) << 16) |
        (rgba.getUint8(i + 1) << 8) |
        rgba.getUint8(i + 2);
  }
}

Future<_Raster> _raster(WidgetTester tester) async {
  final r = await tester.runAsync(() async {
    final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
    final img = await b.toImage(pixelRatio: _dpr);
    final d = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final out = _Raster(d!, img.width, img.height);
    img.dispose();
    return out;
  });
  return r!;
}

/// [f]'s rect in the shot's device pixels.
Rect _px(WidgetTester tester, Finder f) {
  final origin = tester.getTopLeft(find.byKey(_shotKey));
  final r = tester.getRect(f).shift(-origin);
  return Rect.fromLTRB(
      r.left * _dpr, r.top * _dpr, r.right * _dpr, r.bottom * _dpr);
}

/// What P4 reads in [box]: the ground (the commonest colour), and the
/// contrast of the pixel that differs most from it. A null [best]: no pixel
/// in the box differs from the ground at all.
({int ground, double? best, int pixels}) _inkOnGround(_Raster r, Rect box) {
  final x0 = math.max(0, box.left.floor()), y0 = math.max(0, box.top.floor());
  final x1 = math.min(r.width, box.right.ceil());
  final y1 = math.min(r.height, box.bottom.ceil());
  final counts = <int, int>{};
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final c = r.at(x, y);
      counts[c] = (counts[c] ?? 0) + 1;
    }
  }
  if (counts.isEmpty) return (ground: -1, best: null, pixels: 0);
  final ground =
      counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  final g = _lum(ground);
  double? best;
  for (final c in counts.keys) {
    if (c == ground) continue;
    final k = _ratio(_lum(c), g);
    if (best == null || k > best) best = k;
  }
  return (ground: ground, best: best, pixels: (x1 - x0) * (y1 - y0));
}

String _hex(int c) => '#${c.toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// P4 on [key]'s line: at the floor or above, never unmeasured.
void _expectAtFloor(_Raster r, WidgetTester tester, Key key, String where) {
  final read = _inkOnGround(r, _px(tester, find.byKey(key)));
  expect(read.pixels, greaterThan(0),
      reason: '$where: $key has no pixels in the shot. UNMEASURED, a FAIL.');
  expect(read.best, isNotNull,
      reason: '$where: $key paints no pixel apart from its ground '
          '${_hex(read.ground)}: nothing of it can be seen. UNMEASURED, a '
          'FAIL.');
  expect(read.best!, greaterThanOrEqualTo(_floor),
      reason: '$where: $key paints at ${read.best!.toStringAsFixed(2)}:1 at '
          'most against its ground ${_hex(read.ground)}, below $_floor:1');
}

/// P3 on [key]'s line: wider than zero, every character inside its own box,
/// the box inside the panel.
void _expectWhole(WidgetTester tester, Key key, Rect panel, String where) {
  final f = find.byKey(key);
  expect(f, findsOneWidget,
      reason: '$where: $key is not drawn. Not finding it is a FAIL.');
  final rp = tester.renderObject<RenderParagraph>(
      find.descendant(of: f, matching: find.byType(RichText)).first);
  final words = wordsOf(tester.widget<Text>(f));
  expect(rp.size.width, greaterThan(0),
      reason: '$where: 「$words」 is laid out 0 dp wide');
  final text = rp.text.toPlainText();
  final outside = <String>[];
  for (var i = 0; i < text.length; i++) {
    // A space draws nothing, and a space that ends a wrapped line is placed
    // past the line's width by the engine itself (TextPainter.width's own
    // documentation): it is not a character she cannot see. A word joiner
    // draws nothing either.
    if (text[i].trim().isEmpty || text[i] == '\u2060') continue;
    for (final b in rp.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
        boxHeightStyle: ui.BoxHeightStyle.max)) {
      final q = b.toRect();
      if (q.left < -0.5 ||
          q.right > rp.size.width + 0.5 ||
          q.top < -0.5 ||
          q.bottom > rp.size.height + 0.5) {
        outside.add(text[i]);
      }
    }
  }
  expect(outside, isEmpty,
      reason: '$where: in 「$words」, ${outside.length} characters lie '
          'outside the line\'s own ${rp.size.width.toStringAsFixed(1)} dp box '
          '(${outside.take(8).join()}…): they are drawn where she was never '
          'meant to look');
  final box = tester.getRect(f);
  expect(box.left >= panel.left - 0.5 && box.right <= panel.right + 0.5, isTrue,
      reason: '$where: 「$words」 ($box) is not inside the panel ($panel)');
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // A Japanese face under 'Roboto', the family the app's theme draws in.
    // Without one, kanji are drawn as boxes and wrap where boxes wrap: the
    // layout would be measured, not hers. The file refuses to run.
    final ok = await loadCjkFamily('Roboto', [
      '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf',
      '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf',
    ]);
    if (!ok) {
      throw StateError('no Japanese face on this host: the lines under the '
          'button would be measured on boxes, not on her words. Not a pass.');
    }
    final tmp = await Directory.systemTemp.createTemp('maneuver_press');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  for (final lang in ['ja', 'en']) {
    for (final scale in _scales) {
      testWidgets(
          '$lang at text size $scale: after her press the button stays in the '
          'panel and every line under it is whole and at the floor',
          (tester) async {
        tester.view.devicePixelRatio = _dpr;
        tester.view.physicalSize = const Size(1080, 2340);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        for (final said in _Said.values) {
          final c = _Case(said);
          final where = '$lang x$scale ${said.name}';
          // A fresh tree for each case: Flutter reports a RenderFlex overflow
          // once per render object, so a reused tree would let a second
          // overflow pass in silence.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(_host(
              locale: Locale(lang), child: _panel(c, lang, pressed: false)));
          await tester.pump();
          // P1, before the press.
          expect(tester.takeException(), isNull,
              reason: '$where: an exception before the press');
          final before = tester.getRect(find.byKey(_buttonKey));

          await tester.pumpWidget(_host(
              locale: Locale(lang), child: _panel(c, lang, pressed: true)));
          await tester.pump();
          // P1, after it.
          expect(tester.takeException(), isNull,
              reason: '$where: an exception after the press');

          // P2. The button inside the panel, and where it was.
          final panel = tester.getRect(find.byKey(_panelKey));
          final button = tester.getRect(find.byKey(_buttonKey));
          expect(
              button.left >= panel.left - 0.5 &&
                  button.right <= panel.right + 0.5,
              isTrue,
              reason: '$where: the button ($button) runs past the panel '
                  '($panel) by '
                  '${(button.right - panel.right).toStringAsFixed(1)} dp');
          expect((button.topLeft - before.topLeft).distance, lessThan(0.5),
              reason: '$where: the button moved from ${before.topLeft} to '
                  '${button.topLeft} when the lines appeared under it');

          // P3 and P4, each line this case must draw.
          final r = await _raster(tester);
          for (final key in c.lines) {
            _expectWhole(tester, key, panel, where);
            _expectAtFloor(r, tester, key, where);
          }
          if (!c.lines.contains(_deliveryKey)) {
            expect(find.byKey(_deliveryKey), findsNothing,
                reason: '$where: a delivery line with nothing unconfirmed');
          }
        }
      });
    }
  }

  // The narrate button is offered only when the turn will be read aloud
  // (2026-10-04). Under 「読み上げません」 it was enabled and said
  // 「次の案内を読み上げる」: the same card offered what its banner had just
  // said would not happen. The criteria it is held to:
  //  O1 the words: under not read aloud, nothing on the panel offers to read
  //     the turn, and the button says reading is on hold, in the word her
  //     line uses (保留); under read aloud, it still says what it does;
  //  O2 the state: not offered (no press handler) exactly when the banner
  //     says not read aloud, from the same decision, in every position mode;
  //  O3 a screen reader hears the on-hold words and that it is not enabled;
  //  O4 a channel that survives losing colour and words: a different glyph;
  //  O5 a press on it does nothing.
  for (final lang in ['ja', 'en']) {
    testWidgets(
        '$lang: the narrate button is offered only when the turn will be read '
        'aloud, and says so in words, state and mark', (tester) async {
      final handle = tester.ensureSemantics();
      tester.view.devicePixelRatio = _dpr;
      tester.view.physicalSize = const Size(1080, 2340);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final l = AppL10n(Locale(lang));
      final seen = <NarrationConfidence>{};
      for (final mode in LocalizationMode.values) {
        final preview = _decide(mode, lang);
        seen.add(preview.confidence);
        var pressed = 0;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(_host(
          locale: Locale(lang),
          child: SizedBox(
            key: _panelKey,
            width: _panelWidthDp,
            child: ManeuverNarrationPanel(
              preview: preview,
              mode: mode,
              isMockPosition: false,
              icySource: IcyTurnSource.none,
              onNarrate: () => pressed++,
              lastNarration: null,
              speechUnverified: false,
              hapticUnverified: false,
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$lang ${mode.name}');
        final where = '$lang ${mode.name} (${preview.confidence.name})';
        final offered = preview.confidence != NarrationConfidence.suppressed;
        final button = find.byKey(_buttonKey);
        expect(button, findsOneWidget, reason: where);
        // O2.
        expect(tester.widget<ButtonStyleButton>(button).onPressed != null,
            offered,
            reason: '$where: offered must follow the banner\'s decision');
        // O1.
        final words = offered ? l.maneuverNarrateButton : l.maneuverNarrateButtonOnHold;
        expect(
            find.descendant(of: button, matching: findWords(words)),
            findsOneWidget,
            reason: '$where: the button does not say 「$words」');
        expect(findWords(l.maneuverNarrateButton),
            offered ? findsOneWidget : findsNothing,
            reason: '$where: the offer to read the turn');
        // O3.
        final node = tester.getSemantics(button);
        expect(node.label, contains(words), reason: where);
        expect(
            node,
            isSemantics(
                isButton: true, hasEnabledState: true, isEnabled: offered),
            reason: '$where: a screen reader must hear whether it is enabled');
        // O4.
        expect(
            tester
                .widget<Icon>(
                    find.descendant(of: button, matching: find.byType(Icon)))
                .icon,
            offered ? Icons.record_voice_over : Icons.voice_over_off,
            reason: where);
        // O5.
        await tester.tap(button, warnIfMissed: false);
        await tester.pump();
        expect(pressed, offered ? 1 : 0, reason: '$where: the press');
      }
      // Every decision was met: the file did not pass by meeting one.
      expect(seen, NarrationConfidence.values.toSet(), reason: lang);
      handle.dispose();
    });

    // O6. What an earlier press did is not drawn under a banner that now
    // says the opposite: a 「送りました」 from a press made while the turn was
    // read aloud stayed under 「読み上げません」 after 停止, and with the button
    // withdrawn nothing could replace it.
    testWidgets(
        '$lang: a line about an earlier press is drawn only while it agrees '
        'with the banner', (tester) async {
      tester.view.devicePixelRatio = _dpr;
      tester.view.physicalSize = const Size(1080, 2340);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final spoken = _decide(LocalizationMode.gpsTrusted, lang);
      final silent = _decide(LocalizationMode.lost, lang);
      for (final (now, earlier, drawn) in [
        (spoken, spoken, true),
        (silent, silent, true),
        (silent, spoken, false),
        (spoken, silent, false),
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(_host(
          locale: Locale(lang),
          child: SizedBox(
            width: _panelWidthDp,
            child: ManeuverNarrationPanel(
              preview: now,
              mode: LocalizationMode.gpsTrusted,
              isMockPosition: false,
              icySource: IcyTurnSource.none,
              onNarrate: () {},
              lastNarration: earlier,
              speechUnverified: true,
              hapticUnverified: true,
            ),
          ),
        ));
        await tester.pump();
        final where = '$lang: banner ${now.confidence.name}, earlier press '
            '${earlier.confidence.name}';
        expect(find.byKey(_resultKey), drawn ? findsOneWidget : findsNothing,
            reason: where);
        if (!drawn) {
          expect(find.byKey(_deliveryKey), findsNothing, reason: where);
        }
      }
    });
  }

  testWidgets(
      'P5 controls: ink distinct from the ground but below the floor reads '
      'below it, and ink in the ground\'s colour reads as no ink',
      (tester) async {
    tester.view.devicePixelRatio = _dpr;
    tester.view.physicalSize = const Size(1080, 2340);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const key = Key('maneuver-press-result-control');
    Future<({int ground, double? best, int pixels})> read(
        Color Function(BuildContext) ink) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_host(
        locale: const Locale('ja'),
        child: SizedBox(
          width: _panelWidthDp,
          child: Builder(
            builder: (context) => Text(
              key: key,
              '音声も振動も、届いたか確認できていません。',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ink(context)),
            ),
          ),
        ),
      ));
      await tester.pump();
      return _inkOnGround(await _raster(tester), _px(tester, find.byKey(key)));
    }

    final faint = await read((_) => Colors.grey.shade500);
    // ignore: avoid_print
    print('P5 control, grey.shade500 on her card: '
        '${faint.best?.toStringAsFixed(3)}:1 on ${_hex(faint.ground)}');
    expect(faint.best, isNotNull,
        reason: 'the faint control painted nothing: P4 could not see ink');
    expect(faint.best!, greaterThan(1.0));
    expect(faint.best!, lessThan(_floor),
        reason: 'a line painted below the floor read '
            '${faint.best!.toStringAsFixed(2)}:1, at or above $_floor: P4 '
            'cannot fail');

    final none = await read(
        (context) => Theme.of(context).colorScheme.surfaceContainerLow);
    expect(none.best, isNull,
        reason: 'a line in the ground\'s own colour read ${none.best}:1: P4 '
            'would take nothing for ink');
  });
}
