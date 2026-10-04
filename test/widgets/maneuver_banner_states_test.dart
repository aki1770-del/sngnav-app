/// The next-turn banner's three states, told apart with the words masked and
/// colour taken away.
///
/// WHY. Until 2026-10-04 the banner drew read aloud, read aloud with a check
/// and not read aloud as one rounded block, told apart by fill alone. The
/// fills were 1.08 to 1.23:1 apart in luminance, so with colour gone (a
/// colour-vision deficiency, glare, a dim panel) the three were one grey
/// block and only the words told them apart. Words are read; they are not
/// glanced. The panel now gives each state a mark at the head of its line, and
/// draws the state she is not told the turn in as an empty frame.
///
/// What each test holds, at her phone's width (1080 px at 2.75, the banner
/// 328.7 dp wide on the card), at text sizes 1.0, 1.3 and 2.0, in Japanese and
/// English, with the panel's words MASKED (painted over with the banner's own
/// ground) before anything is measured:
///
///  1. One mark per banner, and the three marks are three different glyphs.
///     A banner with no mark FAILS; not finding a mark is never a pass.
///  2. Each mark is drawn: at least 3:1 against its own ground, as a glyph and
///     not as an empty box. "Drawn" is measured against the same glyph drawn
///     alone in the same ink and size, not against a number chosen here.
///  3. Every pair of states differs in SHAPE: their contrasting pixels, with
///     the words masked, overlap at no more than half (intersection over union
///     at most 0.50, the banners aligned at their top-left corner). A speaker
///     and a crossed speaker alone overlap more than that, so the frame around
///     the state that is not read aloud is what lets that pair pass.
///  4. The mark sits inside the banner, before the words, on the state's first
///     line, at every text size.
///  5. A control: the same glyph drawn from a font that was never loaded must
///     NOT pass check 2. A missing glyph draws as a box, and a box at the head
///     of a line looks like a control she could press.
///
/// Colour vision. Checks 2 and 3 run under three models: normal, deuteranopia
/// and protanopia (Machado, Oliveira and Fernandes 2009, severity 1.0, applied
/// in linear RGB). These are models, not people. Desaturation is NOT a fourth
/// check here: a contrast ratio is computed from luminance, which desaturation
/// keeps, so it would repeat the normal-vision numbers and count them twice.
///
/// What this file cannot see: her phone's own fonts (a host Japanese face
/// stands in, and the file refuses to run without one), a real panel, glare,
/// distance, and time. It shows the states are DIFFERENT SHAPES; it does not
/// show that she takes the right meaning from a shape in the time she has.
/// No timed glance study exists.
library;

import 'dart:io' show Directory;
import 'dart:math' as math;
import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph, RenderRepaintBoundary;
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

/// Her phone: 1080 x 2340 px at 2.75.
const double _dpr = 2.75;

/// The banner's width on her card at that geometry, measured in the app
/// 2026-10-04 (outputs/hie/r128_golden_09_her_panel_2026_10_04/).
const double _bannerWidthDp = 328.7;

/// KNOWN, NOT THIS FILE'S, AND NOT HIDDEN. At her width the narrate button's
/// row overflows the panel at text size 2.0, before and after the state marks
/// (measured 2026-10-04 on both): in Japanese its trailing 8 dp gap runs
/// 2.3 dp past the banner, in English the button itself runs 108 dp past it
/// (and 22 dp at 1.5, a size this file does not render). Found by this file,
/// not fixed by it; it is a surface change of its own.
///
/// This file tolerates that overflow ONLY in the cases named here, and only
/// when the button's row is measured to be the one past the banner. Any other
/// exception fails. A named case that no longer overflows fails too, so the
/// day the row is fixed this entry has to be deleted rather than left behind.
///
/// In those cases Flutter's debug overflow label ("RIGHT OVERFLOWED BY ...",
/// dark red #900000 on a white box, drawn turned on its side at the row's
/// right edge) reaches up over the banner. She never sees it: a release build
/// does not paint it. It is found by its own two colours and what lies between
/// them, which no banner fill or ink is, and painted over with the banner's
/// ground before anything is measured; the count is printed. Anywhere else, or
/// touching the mark, it FAILS.
final _knownButtonRowOverflow = {('ja', 2.0), ('en', 2.0)};

/// Whether [c] is one of the debug overflow label's pixels: white, #900000, or
/// a blend of the two, on which green equals blue and red rises with them.
bool _isDebugLabelPixel((int, int, int) c) {
  final (r, g, b) = c;
  if ((g - b).abs() > 2) return false;
  return (r - (144 + 111 * g / 255)).abs() <= 3;
}

/// Paints the debug label's pixels inside [banner] over with [ground], and
/// returns how many there were. Fails if their box touches [mark].
int _maskDebugLabel(_Raster r, Rect banner, (int, int, int) ground, Rect? mark) {
  var n = 0, x0 = 1 << 30, y0 = 1 << 30, x1 = -1, y1 = -1;
  final bx0 = banner.left.ceil(), by0 = banner.top.ceil();
  final bx1 = math.min(banner.right.floor(), r.width);
  final by1 = math.min(banner.bottom.floor(), r.height);
  for (var y = by0; y < by1; y++) {
    for (var x = bx0; x < bx1; x++) {
      if (!_isDebugLabelPixel(r.at(x, y))) continue;
      n++;
      x0 = math.min(x0, x);
      y0 = math.min(y0, y);
      x1 = math.max(x1, x);
      y1 = math.max(y1, y);
    }
  }
  if (n == 0) return 0;
  final box = Rect.fromLTRB(x0 - 2.0, y0 - 2.0, x1 + 3.0, y1 + 3.0)
      .intersect(Rect.fromLTRB(bx0.toDouble(), by0.toDouble(), bx1.toDouble(),
          by1.toDouble()));
  expect(mark == null || !box.overlaps(mark), isTrue,
      reason: 'the debug overflow label ($box) touches the mark ($mark): the '
          'mark cannot be measured here');
  for (var y = box.top.toInt(); y < box.bottom.toInt(); y++) {
    for (var x = box.left.toInt(); x < box.right.toInt(); x++) {
      r.paint(x, y, ground);
    }
  }
  return n;
}

const _markKey = Key('maneuver-narration-state-mark');
const _bannerKey = Key('maneuver-narration-banner');
const _tierKey = Key('maneuver-narration-tier');
const _shotKey = Key('maneuver-banner-states-shot');

const _rightTurn = RouteManeuver(
  index: 1,
  instruction: 'Right onto Main St',
  type: 'right',
  lengthKm: 0.4,
  timeSeconds: 30,
  position: LatLng(39.72, 140.10),
);

enum _State { speak, hedge, paused }

const _modeOf = {
  _State.speak: LocalizationMode.gpsTrusted,
  // No position the app gives the drive brain reaches this state today; the
  // narrator is asked directly, as the next-turn capture test does.
  _State.hedge: LocalizationMode.gpsSuspect,
  _State.paused: LocalizationMode.lost,
};

/// The models every pixel is judged under (linear-RGB matrices).
const Map<String, List<double>?> _models = {
  'normal': null,
  'deuteranopia': [
    0.367322, 0.860646, -0.227968, //
    0.280085, 0.672501, 0.047413, //
    -0.011820, 0.042940, 0.968881,
  ],
  'protanopia': [
    0.152286, 1.052583, -0.204868, //
    0.114503, 0.786281, 0.099216, //
    -0.003882, -0.048116, 1.051998,
  ],
};

final List<double> _toLinear = [
  for (var i = 0; i < 256; i++)
    i / 255 <= 0.04045
        ? (i / 255) / 12.92
        : math.pow(((i / 255) + 0.055) / 1.055, 2.4).toDouble(),
];

/// Relative luminance of an sRGB pixel as [model] would see it.
double _lum(int r, int g, int b, List<double>? m) {
  var lr = _toLinear[r], lg = _toLinear[g], lb = _toLinear[b];
  if (m != null) {
    final nr = m[0] * lr + m[1] * lg + m[2] * lb;
    final ng = m[3] * lr + m[4] * lg + m[5] * lb;
    final nb = m[6] * lr + m[7] * lg + m[8] * lb;
    lr = nr.clamp(0.0, 1.0);
    lg = ng.clamp(0.0, 1.0);
    lb = nb.clamp(0.0, 1.0);
  }
  return 0.2126 * lr + 0.7152 * lg + 0.0722 * lb;
}

double _ratio(double a, double b) =>
    (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);

/// A device-pixel raster of the shot, opaque everywhere the shot paints.
class _Raster {
  _Raster(this.rgba, this.width, this.height);
  final ByteData rgba;
  final int width, height;
  int _i(int x, int y) => (y * width + x) * 4;
  (int, int, int) at(int x, int y) {
    final i = _i(x, y);
    return (rgba.getUint8(i), rgba.getUint8(i + 1), rgba.getUint8(i + 2));
  }

  void paint(int x, int y, (int, int, int) c) {
    final i = _i(x, y);
    rgba.setUint8(i, c.$1);
    rgba.setUint8(i + 1, c.$2);
    rgba.setUint8(i + 2, c.$3);
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

/// A rect in the shot's device pixels.
Rect _px(WidgetTester tester, Finder f) {
  final origin = tester.getTopLeft(find.byKey(_shotKey));
  final r = tester.getRect(f).shift(-origin);
  return Rect.fromLTRB(r.left * _dpr, r.top * _dpr, r.right * _dpr,
      r.bottom * _dpr);
}

/// A boolean mask of the pixels in [box] that contrast with [ground] at 3:1
/// or more under [model].
List<List<bool>> _inkMask(
    _Raster r, Rect box, (int, int, int) ground, List<double>? model) {
  final g = _lum(ground.$1, ground.$2, ground.$3, model);
  final x0 = box.left.floor(), y0 = box.top.floor();
  final x1 = math.min(box.right.ceil(), r.width);
  final y1 = math.min(box.bottom.ceil(), r.height);
  return [
    for (var y = y0; y < y1; y++)
      [
        for (var x = x0; x < x1; x++)
          () {
            final (pr, pg, pb) = r.at(x, y);
            return _ratio(_lum(pr, pg, pb, model), g) >= 3.0;
          }(),
      ],
  ];
}

int _count(List<List<bool>> m) =>
    m.fold(0, (s, row) => s + row.where((v) => v).length);

/// Intersection over union of two masks aligned at their top-left corner.
double _iou(List<List<bool>> a, List<List<bool>> b) {
  final h = math.max(a.length, b.length);
  final w = math.max(a.isEmpty ? 0 : a.first.length,
      b.isEmpty ? 0 : b.first.length);
  var inter = 0, uni = 0;
  bool at(List<List<bool>> m, int x, int y) =>
      y < m.length && x < m[y].length && m[y][x];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = at(a, x, y), q = at(b, x, y);
      if (p && q) inter++;
      if (p || q) uni++;
    }
  }
  return uni == 0 ? double.nan : inter / uni;
}

/// [m] cropped to its own ink, so two glyphs drawn at slightly different
/// sub-pixel offsets are compared shape to shape.
List<List<bool>> _cropToInk(List<List<bool>> m) {
  var top = -1, bottom = -1, left = 1 << 30, right = -1;
  for (var y = 0; y < m.length; y++) {
    for (var x = 0; x < m[y].length; x++) {
      if (!m[y][x]) continue;
      if (top < 0) top = y;
      bottom = y;
      left = math.min(left, x);
      right = math.max(right, x);
    }
  }
  if (top < 0) return const [];
  return [
    for (var y = top; y <= bottom; y++) m[y].sublist(left, right + 1),
  ];
}

class _Shot {
  _Shot(this.raster, this.banner, this.mark, this.ground, this.markIcon,
      this.markSize, this.ink, this.textRects, this.firstLine, this.tierLeft);
  final _Raster raster;
  final Rect banner;
  final Rect? mark;
  final (int, int, int) ground;
  final IconData? markIcon;
  final double markSize;
  final Color? ink;
  final List<Rect> textRects;
  final Rect? firstLine;
  final double tierLeft;
}

Widget _host({
  required Locale locale,
  required Widget child,
}) =>
    MaterialApp(
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
        body: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: _shotKey,
            // Her card's own colour, as the app's section card paints it.
            child: Builder(
              builder: (context) => ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: Padding(padding: const EdgeInsets.all(4), child: child),
              ),
            ),
          ),
        ),
      ),
    );

Future<_Shot> _shoot(
    WidgetTester tester, _State s, String lang, double scale) async {
  final preview = const ManeuverNarrator(text: DriveHudLocalizer()).decide(
    maneuver: _rightTurn,
    mode: _modeOf[s]!,
    icyTurn: false,
    localeTag: lang,
  );
  // A fresh tree for every state. Flutter reports a RenderFlex overflow once
  // per render object, so a reused tree would let the second state's
  // overflow pass in silence.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(_host(
    locale: Locale(lang),
    child: SizedBox(
      width: _bannerWidthDp,
      child: ManeuverNarrationPanel(
        preview: preview,
        mode: _modeOf[s],
        isMockPosition: false,
        icySource: IcyTurnSource.none,
        onNarrate: () {},
        lastNarration: null,
        speechUnverified: false,
        hapticUnverified: false,
      ),
    ),
  ));
  await tester.pump();
  final thrown = tester.takeException();
  final known = _knownButtonRowOverflow.contains((lang, scale));
  if (thrown != null || known) {
    final bannerRight = tester.getRect(find.byKey(_bannerKey)).right;
    final buttonRowRight =
        tester.getRect(find.byKey(const Key('maneuver-narrate-button'))).right +
            8;
    final pastBy = buttonRowRight - bannerRight;
    expect(known, isTrue,
        reason: '$s, $lang at $scale: an exception no entry names: $thrown');
    expect(thrown, isA<FlutterError>(),
        reason: '$s, $lang at $scale: the named button-row overflow did not '
            'happen. If the row is fixed, delete this case from '
            '_knownButtonRowOverflow.');
    expect('$thrown', contains('A RenderFlex overflowed by'));
    expect(pastBy, greaterThan(0),
        reason: '$s, $lang at $scale: an overflow, but the button row is '
            'inside the banner: something else overflowed: $thrown');
    // ignore: avoid_print
    print('KNOWN button-row overflow $lang x$scale $s: '
        '${pastBy.toStringAsFixed(1)} dp past the banner');
  }
  final raster = await _raster(tester);
  final banner = _px(tester, find.byKey(_bannerKey));
  // The banner's own ground, inside its padding at mid-height: the fill a
  // filled banner paints, the card colour an outlined one paints.
  final ground = raster.at(
      (banner.left + 4 * _dpr).round(), banner.center.dy.round());

  final markFinder =
      find.descendant(of: find.byKey(_bannerKey), matching: find.byKey(_markKey));
  final markCount = markFinder.evaluate().length;
  final debugPx = _maskDebugLabel(raster, banner, ground,
      markCount == 1 ? _px(tester, markFinder) : null);
  if (debugPx > 0) {
    expect(known, isTrue,
        reason: '$s, $lang at $scale: $debugPx px of a debug overflow label '
            'in the banner, in a case no entry names');
    // ignore: avoid_print
    print('KNOWN $lang x$scale $s: the debug overflow label covered $debugPx '
        'banner px; painted over with the banner ground before measuring');
  }
  final markIconFinder = find.descendant(
      of: find.byKey(_markKey), matching: find.byType(RichText));
  final markRichTexts = markIconFinder.evaluate().map((e) => e.widget).toSet();

  // Every run of text in the banner, the mark's own glyph excepted.
  final shotOrigin = tester.getTopLeft(find.byKey(_shotKey));
  final textRects = <Rect>[
    for (final e in find
        .descendant(of: find.byKey(_bannerKey), matching: find.byType(RichText))
        .evaluate())
      if (!markRichTexts.contains(e.widget))
        () {
          final box = e.renderObject! as RenderBox;
          final r = (box.localToGlobal(Offset.zero) - shotOrigin) & box.size;
          return Rect.fromLTRB(r.left * _dpr, r.top * _dpr, r.right * _dpr,
              r.bottom * _dpr);
        }(),
  ];

  Rect? firstLine;
  final tierFinder = find.byKey(_tierKey);
  final tierRect = _px(tester, tierFinder);
  final para = tester.renderObject<RenderParagraph>(
      find.descendant(of: tierFinder, matching: find.byType(RichText)));
  final boxes = para.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 1));
  if (boxes.isNotEmpty) {
    final o = para.localToGlobal(Offset.zero) -
        tester.getTopLeft(find.byKey(_shotKey));
    final b = boxes.first.toRect().shift(o);
    firstLine = Rect.fromLTRB(
        b.left * _dpr, b.top * _dpr, b.right * _dpr, b.bottom * _dpr);
  }

  Icon? icon;
  if (markCount == 1) icon = tester.widget<Icon>(markFinder);
  return _Shot(
    raster,
    banner,
    markCount == 1 ? _px(tester, markFinder) : null,
    ground,
    icon?.icon,
    icon?.size ?? 0,
    icon?.color,
    textRects,
    firstLine,
    tierRect.left,
  );
}

/// The words, painted over with the banner's own ground (1 px wider on each
/// side, for anti-aliasing), so that only marks and forms are left to measure.
void _maskWords(_Shot s) {
  for (final r in s.textRects) {
    for (var y = math.max(0, r.top.floor() - 1);
        y < math.min(s.raster.height, r.bottom.ceil() + 1);
        y++) {
      for (var x = math.max(0, r.left.floor() - 1);
          x < math.min(s.raster.width, r.right.ceil() + 1);
          x++) {
        s.raster.paint(x, y, s.ground);
      }
    }
  }
}

/// The same glyph, drawn alone in the same ink and size on the same ground,
/// from [family] (the glyph's own font, or one never loaded).
Future<List<List<bool>>> _referenceMask(WidgetTester tester, IconData icon,
    double size, Color ink, (int, int, int) ground, List<double>? model,
    {String? family}) async {
  final data = family == null
      ? icon
      // A glyph from a family that never loads is this control's whole point,
      // and it is test code: nothing here reaches the app's icon tree-shaking.
      // ignore: non_const_argument_for_const_parameter
      : IconData(icon.codePoint, fontFamily: family);
  await tester.pumpWidget(_host(
    locale: const Locale('ja'),
    child: ColoredBox(
      color: Color.fromARGB(255, ground.$1, ground.$2, ground.$3),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(data, key: _markKey, size: size, color: ink),
      ),
    ),
  ));
  await tester.pump();
  final r = await _raster(tester);
  return _inkMask(r, _px(tester, find.byKey(_markKey)), ground, model);
}

/// Check 2's shape half: [mark] is [reference]'s glyph if, cropped to their
/// ink, their sizes agree within 2 px and they overlap at 0.8 or more.
(bool, String) _isGlyph(List<List<bool>> mark, List<List<bool>> reference) {
  final a = _cropToInk(mark), b = _cropToInk(reference);
  if (a.isEmpty) return (false, 'no pixel of the mark reaches 3:1');
  if (b.isEmpty) return (false, 'the reference glyph drew nothing');
  final dh = (a.length - b.length).abs();
  final dw = (a.first.length - b.first.length).abs();
  final iou = _iou(a, b);
  final ok = dh <= 2 && dw <= 2 && iou >= 0.8;
  return (
    ok,
    'ink ${a.first.length}x${a.length} px vs the glyph alone '
        '${b.first.length}x${b.length} px, overlap ${iou.toStringAsFixed(3)}',
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // A Japanese face under 'Roboto', the family the app's theme draws in.
    // Without one, kanji are drawn as boxes and every line wraps where boxes
    // wrap: the layout would be measured, not hers. The file refuses to run.
    final ok = await loadCjkFamily('Roboto', [
      '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf',
      '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf',
    ]);
    if (!ok) {
      throw StateError('no Japanese face on this host: the banner states '
          'would be measured on boxes, not on her words. Not a pass.');
    }
    final tmp = await Directory.systemTemp.createTemp('maneuver_states');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  for (final lang in ['ja', 'en']) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets(
          'three states, words masked, $lang at text size $scale: '
          'a mark each, drawn, apart in shape, on the first line',
          (tester) async {
        tester.view.devicePixelRatio = _dpr;
        tester.view.physicalSize = const Size(1080, 2340);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final shots = <_State, _Shot>{};
        for (final s in _State.values) {
          shots[s] = await _shoot(tester, s, lang, scale);
        }

        // 1. One mark per banner, three different glyphs.
        for (final s in _State.values) {
          expect(shots[s]!.mark, isNotNull,
              reason: '$s: no state mark found in the banner. Not finding '
                  'the mark is a FAIL, never a pass: with no mark, the '
                  'states differ by colour and words alone.');
        }
        final glyphs = {for (final s in _State.values) shots[s]!.markIcon};
        expect(glyphs.length, 3,
            reason: 'the three states must carry three different marks; '
                'found $glyphs');

        for (final s in _State.values) {
          final shot = shots[s]!;
          // 4. Inside the banner, before the words, on the first line.
          expect(shot.banner.contains(shot.mark!.topLeft) &&
                  shot.banner.contains(shot.mark!.bottomRight - const Offset(1, 1)),
              isTrue,
              reason: '$s: the mark ${shot.mark} is not inside the banner '
                  '${shot.banner}');
          expect(shot.mark!.right, lessThanOrEqualTo(shot.tierLeft + 0.5),
              reason: '$s: the mark must come before the state\'s words');
          expect(shot.firstLine, isNotNull,
              reason: '$s: the state\'s first line could not be measured');
          final cy = shot.mark!.center.dy;
          expect(cy >= shot.firstLine!.top && cy <= shot.firstLine!.bottom,
              isTrue,
              reason: '$s: the mark\'s middle (y $cy px) is not on the '
                  'state\'s first line (${shot.firstLine!.top}-'
                  '${shot.firstLine!.bottom} px)');
          _maskWords(shot);
        }

        for (final entry in _models.entries) {
          final model = entry.value;
          final silhouettes = <_State, List<List<bool>>>{};
          for (final s in _State.values) {
            final shot = shots[s]!;
            // 2. The mark is drawn: as its glyph, at 3:1 against its ground.
            final mark = _inkMask(shot.raster, shot.mark!, shot.ground, model);
            final reference = await _referenceMask(tester, shot.markIcon!,
                shot.markSize, shot.ink!, shot.ground, model);
            final (ok, how) = _isGlyph(mark, reference);
            expect(ok, isTrue,
                reason: '$s under ${entry.key}: the mark is not drawn as '
                    'its glyph at 3:1 against its ground ($how)');
            // 3's input: the whole banner, words masked.
            silhouettes[s] =
                _inkMask(shot.raster, shot.banner, shot.ground, model);
            expect(_count(silhouettes[s]!), greaterThan(0),
                reason: '$s under ${entry.key}: nothing in the banner '
                    'contrasts with its ground once the words are masked. '
                    'An empty silhouette is unmeasured, and a FAIL.');
          }
          // 3. Apart in shape, every pair.
          for (final (a, b) in [
            (_State.speak, _State.hedge),
            (_State.speak, _State.paused),
            (_State.hedge, _State.paused),
          ]) {
            final iou = _iou(silhouettes[a]!, silhouettes[b]!);
            // ignore: avoid_print
            print('R3-3 $lang x$scale ${entry.key} $a|$b overlap '
                '${iou.toStringAsFixed(3)}');
            expect(iou, lessThanOrEqualTo(0.50),
                reason: '$a and $b, words masked, under ${entry.key}, '
                    'overlap at ${iou.toStringAsFixed(3)}: with colour and '
                    'words gone they are nearly one shape');
          }
        }
      });
    }
  }

  testWidgets(
      'control: a mark from a font never loaded is NOT taken for its glyph',
      (tester) async {
    tester.view.devicePixelRatio = _dpr;
    tester.view.physicalSize = const Size(1080, 2340);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const ground = (0xC8, 0xE6, 0xC9);
    final ink = Colors.green.shade900;
    for (final icon in [Icons.volume_up, Icons.help_outline, Icons.volume_off]) {
      final real = await _referenceMask(tester, icon, 18, ink, ground, null);
      final missing = await _referenceMask(tester, icon, 18, ink, ground, null,
          family: 'HieNeverLoadedFamily');
      final (ok, how) = _isGlyph(missing, real);
      // ignore: avoid_print
      print('R3-5 control ${icon.codePoint.toRadixString(16)}: $how');
      expect(ok, isFalse,
          reason: 'a glyph from a font that never loaded was measured as the '
              'glyph itself ($how): check 2 could not tell a box from a mark');
      expect(_count(real), greaterThan(0),
          reason: 'the real glyph drew nothing: MaterialIcons did not load');
    }
  });
}
