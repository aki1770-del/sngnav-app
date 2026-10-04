// THE SMALL ICON OF THE DRIVE NOTIFICATION MUST NOT BE A LOCATION MARK.
//
// Why. While any app uses location, Android 14 draws its own location
// indicator in the status bar: the outlined pin `perm_group_location`, read
// from an API 34 emulator's framework-res.apk. Seen on that emulator
// (sdk_gphone64_x86_64, 1080x2340 at 440 dpi, ja-JP), 2026-10-04, with Google
// Maps navigating in the background: during a drive the bar held this app's
// icon at the left and Android's pin at the right. One second after 停止 this
// app's icon was gone and Android's pin stayed, because Maps still used
// location. Until this check, this app's icon was itself a location glyph
// (Icons.my_location). A driver who learned "the location mark is my drive"
// would, after 停止, see a location mark still there and could believe her
// drive, and its warnings, still run.
//
// So the icon must not be a location glyph, and must not carry one as a
// separate piece of a larger drawing. This test draws the icon from its own
// vector file the way Android draws it (fills and strokes, with their paint
// attributes), finds its separate pieces, and compares the whole drawing and
// every combination of its pieces with every location glyph of the Material
// Icons font the app ships, in all four styles, and with Android's own
// indicator. It is red when any of them is a location mark.
//
// HOW IT COMPARES. Each shape is drawn at 96 px, cropped to its ink, scaled
// to 64x64 and compared by intersection over union (IoU) of the inked pixels.
// The red line is IoU >= 0.80. Measured with this test: Android's pin and the
// font's location_on_outlined are 0.98 alike although AOSP encodes the pin in
// its own path data, so a redrawn location glyph lands above the line. Two
// DIFFERENT location glyphs can be as little as about 0.4 alike, so a lower
// line would start failing icons that are not location marks.
//
// WHY PIECES. Cropping to the ink makes size and position irrelevant, and it
// also lets one far-off speck move the frame. Android's pin plus a 1x1 square
// in a corner of the viewport read 0.318 against the whole drawing, and
// passed. So every combination of separate pieces (ink that does not touch)
// is also cropped and compared on its own, and the pin is compared without
// the speck. A combination is compared on its own only if it spans at least
// half of the drawing: compared at its own size, any small round dot reads as
// the disc of Icons.assistant_navigation (measured, see the controls), and a
// mark under half the drawing is a detail of the icon, not the icon.
//
// WHAT IT CANNOT SEE.
// - Meaning. It compares outlines, not what a driver reads into them. That an
//   icon reads as this app's drive is a glance question, and no timed glance
//   study exists.
// - Other system marks and other apps' icons. It knows only the location
//   family and Android's pin. A location glyph from another icon set is red
//   only if its outline is close to one of these.
// - A location glyph whose ink TOUCHES another shape. The two are one piece
//   and are cropped together, so the other shape moves the frame as the speck
//   did. Measured: Android's pin with a 2-unit bar joined to its side and
//   running to the edge of the viewport reads 0.351, and passes.
// - A location glyph spanning less than half of the drawing, beside other
//   pieces (above).
// - How a phone's skin draws the icon. MIUI is not stock Android.
//
// WHAT IT REFUSES rather than guesses. Each of these FAILS the test, never
// passes it: an element other than <vector> and <path> (so <group>
// transforms, <clip-path> and gradients); an attribute it does not know (so
// trim paths, tint, alpha and mirroring); a colour that is not a literal
// (a resource reference); an icon that is not square; more than 10
// separate pieces; and an icon that draws almost nothing.
//
// Two choices that err toward red, stated: any fill or stroke whose alpha is
// above zero is drawn as full ink, because a faint path still shows in her
// bar; and a path with no fill colour and no stroke colour draws nothing,
// because that is what Android does with it.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'third_party/aosp/perm_group_location.dart';

/// The icon, as the app wires it (lib/her_position.dart, notificationIcon).
const _iconFile = 'android/app/src/main/res/drawable/ic_stat_sngnav.xml';

/// Android 14's own location indicator, `perm_group_location.xml`: Android
/// Open Source Project, Apache License 2.0. The strings, their source and the
/// licence are in test/third_party/aosp/. Used here only as a shape to
/// compare against.
const _androidLocationIndicator = kPermGroupLocationPathData;

/// Every location glyph of the Material Icons font, in its four styles.
const _locationGlyphs = <String, IconData>{
  'my_location': Icons.my_location,
  'my_location_outlined': Icons.my_location_outlined,
  'my_location_rounded': Icons.my_location_rounded,
  'my_location_sharp': Icons.my_location_sharp,
  'location_searching': Icons.location_searching,
  'location_searching_outlined': Icons.location_searching_outlined,
  'location_searching_rounded': Icons.location_searching_rounded,
  'location_searching_sharp': Icons.location_searching_sharp,
  'gps_fixed': Icons.gps_fixed,
  'gps_fixed_outlined': Icons.gps_fixed_outlined,
  'gps_fixed_rounded': Icons.gps_fixed_rounded,
  'gps_fixed_sharp': Icons.gps_fixed_sharp,
  'gps_not_fixed': Icons.gps_not_fixed,
  'gps_not_fixed_outlined': Icons.gps_not_fixed_outlined,
  'gps_not_fixed_rounded': Icons.gps_not_fixed_rounded,
  'gps_not_fixed_sharp': Icons.gps_not_fixed_sharp,
  'location_on': Icons.location_on,
  'location_on_outlined': Icons.location_on_outlined,
  'location_on_rounded': Icons.location_on_rounded,
  'location_on_sharp': Icons.location_on_sharp,
  'location_pin': Icons.location_pin,
  'place': Icons.place,
  'place_outlined': Icons.place_outlined,
  'place_rounded': Icons.place_rounded,
  'place_sharp': Icons.place_sharp,
  'pin_drop': Icons.pin_drop,
  'pin_drop_outlined': Icons.pin_drop_outlined,
  'pin_drop_rounded': Icons.pin_drop_rounded,
  'pin_drop_sharp': Icons.pin_drop_sharp,
  'near_me': Icons.near_me,
  'near_me_outlined': Icons.near_me_outlined,
  'near_me_rounded': Icons.near_me_rounded,
  'near_me_sharp': Icons.near_me_sharp,
  'navigation': Icons.navigation,
  'navigation_outlined': Icons.navigation_outlined,
  'navigation_rounded': Icons.navigation_rounded,
  'navigation_sharp': Icons.navigation_sharp,
  'assistant_navigation': Icons.assistant_navigation,
  'explore': Icons.explore,
  'explore_outlined': Icons.explore_outlined,
  'explore_rounded': Icons.explore_rounded,
  'explore_sharp': Icons.explore_sharp,
  'share_location': Icons.share_location,
  'share_location_outlined': Icons.share_location_outlined,
  'share_location_rounded': Icons.share_location_rounded,
  'share_location_sharp': Icons.share_location_sharp,
  'person_pin_circle': Icons.person_pin_circle,
  'person_pin_circle_outlined': Icons.person_pin_circle_outlined,
  'person_pin_circle_rounded': Icons.person_pin_circle_rounded,
  'person_pin_circle_sharp': Icons.person_pin_circle_sharp,
  'add_location': Icons.add_location,
  'add_location_outlined': Icons.add_location_outlined,
  'add_location_rounded': Icons.add_location_rounded,
  'add_location_sharp': Icons.add_location_sharp,
  'add_location_alt': Icons.add_location_alt,
  'add_location_alt_outlined': Icons.add_location_alt_outlined,
  'add_location_alt_rounded': Icons.add_location_alt_rounded,
  'add_location_alt_sharp': Icons.add_location_alt_sharp,
  'edit_location': Icons.edit_location,
  'edit_location_outlined': Icons.edit_location_outlined,
  'edit_location_rounded': Icons.edit_location_rounded,
  'edit_location_sharp': Icons.edit_location_sharp,
  'wrong_location': Icons.wrong_location,
  'wrong_location_outlined': Icons.wrong_location_outlined,
  'wrong_location_rounded': Icons.wrong_location_rounded,
  'wrong_location_sharp': Icons.wrong_location_sharp,
  'not_listed_location': Icons.not_listed_location,
  'not_listed_location_outlined': Icons.not_listed_location_outlined,
  'not_listed_location_rounded': Icons.not_listed_location_rounded,
  'not_listed_location_sharp': Icons.not_listed_location_sharp,
  'location_disabled': Icons.location_disabled,
  'location_disabled_outlined': Icons.location_disabled_outlined,
  'location_disabled_rounded': Icons.location_disabled_rounded,
  'location_disabled_sharp': Icons.location_disabled_sharp,
  'location_off': Icons.location_off,
  'location_off_outlined': Icons.location_off_outlined,
  'location_off_rounded': Icons.location_off_rounded,
  'location_off_sharp': Icons.location_off_sharp,
  'crisis_alert': Icons.crisis_alert,
};

/// IoU at or above this is a location mark.
const _redLine = 0.80;

const _draw = 96; // px a shape is drawn at
const _cell = 64; // px a shape is compared at

/// A combination of pieces is compared on its own only if its larger side is
/// at least this share of the whole drawing's larger side.
const _pieceFloor = 0.5;

/// Above this many separate pieces the test refuses, rather than compare
/// some combinations and not others (2^10 - 1 = 1023 combinations).
const _maxPieces = 10;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the drive notification icon is not a location mark, whole or in part '
    '(IoU < $_redLine against every location glyph and Android\'s pin)',
    () async {
      final icon = await _drawVector(File(_iconFile).readAsStringSync());
      expect(
        _inkShare(_normalise(icon)),
        greaterThan(0.05),
        reason: 'the icon drew almost nothing, so it was not compared',
      );

      final references = await _references();
      final m = _closest(icon, references);
      // ignore: avoid_print
      print(
        'drive notification icon: closest location mark '
        '${m.mark} at IoU ${m.iou.toStringAsFixed(3)} '
        '(red at $_redLine; ${references.length} marks compared). '
        'From ${m.where}; ${m.compared} of ${m.combinations} combination(s) '
        'of its ${m.pieces} separate piece(s) compared, '
        '${m.combinations - m.compared} under half the drawing not compared '
        'on their own',
      );
      expect(
        m.red,
        isEmpty,
        reason:
            'the status bar icon is shaped like a location mark, or carries '
            'one. After 停止 Android\'s own location indicator can stay in '
            'her bar, and she could take it for this app\'s drive still '
            'running.',
      );
    },
  );

  group('the comparison can fail, and reads what Android draws (controls)', () {
    // If the font did not load, every glyph would draw as the same box; if
    // the path reader broke, the pin would draw wrong or not at all. Either
    // would make the test above pass on anything. So: Android's pin, drawn
    // by the path reader, must match the font's location_on_outlined, and
    // must NOT match my_location.
    test('it sees a location mark: Android\'s pin is the font\'s pin, and is '
        'not the crosshair', () async {
      final pin = _normalise(await _fill(_androidLocationIndicator, 24));
      final fontPin = await _glyph(Icons.location_on_outlined);
      final crosshair = await _glyph(Icons.my_location);
      expect(_inkShare(pin), inInclusiveRange(0.10, 0.60));
      expect(
        _inkShare(fontPin),
        inInclusiveRange(0.10, 0.60),
        reason: 'a missing glyph draws as an empty or full box',
      );
      expect(
        _iou(pin, fontPin),
        greaterThanOrEqualTo(_redLine),
        reason: 'the path reader and the font no longer draw the same pin',
      );
      expect(
        _iou(pin, crosshair),
        lessThan(_redLine),
        reason: 'two different glyphs compared as the same shape',
      );
    });

    // The trap that passed on 2026-10-04: one speck in a corner moves the
    // frame of the whole drawing, and Android's own pin read 0.318.
    test('it sees a location mark beside a far-off speck', () async {
      final drawing = await _drawVector(
        _vectorXml([
          for (final d in _androidLocationIndicator) _filled(d),
          _filled('M0,0 L1,0 L1,1 L0,1 Z'),
        ]),
      );
      final references = await _references();
      final whole = _normalise(drawing);
      final wholeBest = references.values.map((r) => _iou(whole, r)).reduce(
        math.max,
      );
      expect(
        wholeBest,
        lessThan(_redLine),
        reason:
            'the fixture no longer sets the trap: against the whole drawing '
            'the pin already reads ${wholeBest.toStringAsFixed(3)}',
      );
      final m = _closest(drawing, references);
      // ignore: avoid_print
      print('control: Android\'s pin beside a speck reads '
          '${wholeBest.toStringAsFixed(3)} as a whole drawing and '
          '${m.iou.toStringAsFixed(3)} (${m.mark}) from ${m.where}');
      expect(
        m.iou,
        greaterThanOrEqualTo(_redLine),
        reason:
            'Android\'s pin beside one speck read ${m.iou.toStringAsFixed(3)} '
            '(${m.mark}): the frame moved with the speck',
      );
    });

    // A crosshair written with strokes. A reader that fills every path draws
    // the stroked ring as a solid disc, and the disc matches
    // assistant_navigation: red, but for the wrong reason.
    test('it reads strokes as strokes: a stroked crosshair is a crosshair, not '
        'a disc', () async {
      final drawing = await _drawVector(
        _vectorXml([
          _stroked('M12,1 L12,4 M12,20 L12,23 M1,12 L4,12 M20,12 L23,12', 2),
          _stroked('M12,12 m-8,0 a8,8 0,1 1,16 0 a8,8 0,1 1,-16 0', 2),
          _filled('M12,12 m-4,0 a4,4 0,1 1,8 0 a4,4 0,1 1,-8 0'),
        ]),
      );
      final m = _closest(drawing, await _references());
      expect(m.iou, greaterThanOrEqualTo(_redLine));
      expect(
        _crosshairs.any(m.mark.contains),
        isTrue,
        reason:
            'the closest mark was ${m.mark} at ${m.iou.toStringAsFixed(3)}: '
            'the reader did not draw the ring as a ring',
      );
    });

    test('it draws what Android draws: a transparent or unpainted path draws '
        'nothing, and evenOdd cuts a hole', () async {
      final edges = [for (final d in _twoEdges) _filled(d)];
      final alone = await _drawVector(_vectorXml(edges));
      final withHidden = await _drawVector(
        _vectorXml([
          ...edges,
          for (final d in _androidLocationIndicator)
            '<path android:fillColor="#00FFFFFF" android:pathData="$d"/>',
          '<path android:pathData="${_androidLocationIndicator.first}"/>',
          '<path android:strokeColor="#FFFFFFFF" android:strokeWidth="0" '
              'android:pathData="${_androidLocationIndicator.first}"/>',
        ]),
      );
      expect(
        _differing(alone, withHidden),
        0,
        reason:
            'a pin with a transparent fill, a path with no paint and a stroke '
            'of width 0 each drew something; Android draws none of them',
      );

      // Two squares wound the same way: non-zero fills the inner one,
      // evenOdd leaves it empty.
      const squares =
          'M2,2 L22,2 L22,22 L2,22 Z M8,8 L16,8 L16,16 L8,16 Z';
      final nonZero = await _drawVector(_vectorXml([_filled(squares)]));
      final evenOdd = await _drawVector(
        _vectorXml([
          '<path android:fillColor="#FFFFFFFF" android:fillType="evenOdd" '
              'android:pathData="$squares"/>',
        ]),
      );
      expect(
        _differing(nonZero, evenOdd),
        greaterThan(500),
        reason: 'fillType="evenOdd" drew the same as non-zero',
      );
    });

    test('it refuses what it cannot draw, and never passes it', () async {
      final refusals = <String, String>{
        'a <group> that rotates':
            _vectorXml(['<group android:rotation="90">', _filled(_square),
              '</group>']),
        'a <clip-path>': _vectorXml([
          '<clip-path android:pathData="$_square"/>',
          _filled(_square),
        ]),
        'a trimmed path':
            _vectorXml(['<path android:fillColor="#FFFFFFFF" '
                'android:trimPathEnd="0.5" android:pathData="$_square"/>']),
        'a colour given as a resource': _vectorXml([
          '<path android:fillColor="@android:color/white" '
              'android:pathData="$_square"/>',
        ]),
        'an attribute it does not know':
            _vectorXml(['<path android:fillColor="#FFFFFFFF" '
                'android:pathDatx="$_square" android:pathData="$_square"/>']),
        'a path with no pathData':
            _vectorXml(['<path android:fillColor="#FFFFFFFF"/>']),
        'a tint on the vector': _vectorXml([
          _filled(_square),
        ]).replaceFirst('<vector ', '<vector android:tint="#FF000000" '),
        'an icon that is not square': _vectorXml([
          _filled(_square),
        ]).replaceFirst('android:height="24dp"', 'android:height="20dp"'),
      };
      for (final e in refusals.entries) {
        await expectLater(
          _drawVector(e.value),
          throwsA(isA<_CannotDraw>()),
          reason: '${e.key} was drawn as if the reader understood it',
        );
      }
      final eleven = await _drawVector(
        _vectorXml([
          for (var i = 0; i < 11; i++)
            _filled('M${i * 2},${i * 2} L${i * 2 + 1},${i * 2} '
                'L${i * 2 + 1},${i * 2 + 1} L${i * 2},${i * 2 + 1} Z'),
        ]),
      );
      expect(
        () => _closest(eleven, {'box': List<bool>.filled(_cell * _cell, true)}),
        throwsA(isA<_CannotDraw>()),
        reason: 'eleven separate pieces were compared in part, not refused',
      );
    });

    // The floor's reason, measured: compared at its own size, a round dot
    // fills the cell and reads as assistant_navigation's disc.
    test('a small round dot beside two edges is not taken for a location '
        'mark',
        () async {
      final dot = await _drawVector(
        _vectorXml([_filled('M12,12 m-2,0 a2,2 0,1 1,4 0 a2,2 0,1 1,-4 0')]),
      );
      final navigation = await _glyph(Icons.assistant_navigation);
      final dotAlone = _iou(_normalise(dot), navigation);
      // ignore: avoid_print
      print('control: a round dot alone reads ${dotAlone.toStringAsFixed(3)} '
          'against Icons.assistant_navigation');
      expect(
        dotAlone,
        greaterThanOrEqualTo(_redLine),
        reason:
            'a dot alone no longer reads as assistant_navigation, so this '
            'control no longer shows why the floor exists',
      );
      final m = _closest(
        await _drawVector(
          _vectorXml([
            for (final d in _twoEdges) _filled(d),
            _filled('M20,4 m-2,0 a2,2 0,1 1,4 0 a2,2 0,1 1,-4 0'),
          ]),
        ),
        await _references(),
      );
      expect(
        m.red,
        isEmpty,
        reason: 'a 4-unit dot beside two edges was compared on its own and '
            'read as ${m.mark}',
      );
    });

    test('the AOSP shape this test borrows carries its licence and notice', () {
      final license = File('test/third_party/aosp/LICENSE').readAsStringSync();
      expect(license.trimLeft(), startsWith('Apache License'));
      expect(license, contains('Version 2.0, January 2004'));
      expect(license, contains('END OF TERMS AND CONDITIONS'));
      final notice = File('test/third_party/aosp/NOTICE').readAsStringSync();
      expect(notice, contains('perm_group_location.xml'));
      expect(notice, contains('The Android Open Source Project'));
      final source = File(
        'test/third_party/aosp/perm_group_location.dart',
      ).readAsStringSync();
      expect(
        source,
        contains('Copyright (C) 2015 The Android Open Source Project'),
      );
      expect(source, contains('Licensed under the Apache License, Version 2.0'));
    });
  });
}

/// Glyph names that are crosshairs.
const _crosshairs = ['my_location', 'gps_fixed', 'gps_not_fixed',
  'location_searching'];

const _square = 'M4,4 L20,4 L20,20 L4,20 Z';

/// Two converging edges, a fixed shape like the icon's road. The controls
/// use this and never the icon file, so a control does not move when the
/// icon does.
const _twoEdges = [
  'M8.4,2.5 L10.4,2.5 L6.2,21.5 L2.2,21.5 Z',
  'M13.6,2.5 L15.6,2.5 L21.8,21.5 L17.8,21.5 Z',
];

String _filled(String d) =>
    '<path android:fillColor="#FFFFFFFF" android:pathData="$d"/>';

String _stroked(String d, double width) =>
    '<path android:strokeColor="#FFFFFFFF" android:strokeWidth="$width" '
    'android:pathData="$d"/>';

String _vectorXml(List<String> body) =>
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<vector xmlns:android="http://schemas.android.com/apk/res/android" '
    'android:width="24dp" android:height="24dp" '
    'android:viewportWidth="24" android:viewportHeight="24">\n'
    '${body.join('\n')}\n</vector>\n';

// ------------------------------------------------------------- comparing --

class _Match {
  _Match(this.mark, this.iou, this.where, this.pieces, this.combinations,
      this.compared, this.red);
  final String mark;
  final double iou;
  final String where;
  final int pieces;
  final int combinations;
  final int compared;
  final List<String> red;
}

/// The closest location mark to [drawing] (an uncropped [_draw]-px mask),
/// over the whole drawing and every combination of its separate pieces that
/// spans at least [_pieceFloor] of it.
_Match _closest(List<bool> drawing, Map<String, List<bool>> references) {
  final pieces = _pieces(drawing);
  if (pieces.isEmpty) throw _CannotDraw('the icon drew nothing');
  if (pieces.length > _maxPieces) {
    throw _CannotDraw(
      'the icon has ${pieces.length} separate pieces; this test compares '
      'every combination of up to $_maxPieces and will not compare some and '
      'skip others',
    );
  }
  final wholeSide = _side(drawing);
  final combinations = (1 << pieces.length) - 1;
  var compared = 0;
  var best = _Match('', -1, '', pieces.length, combinations, 0, const []);
  final redByMark = <String, String>{};
  for (var bits = combinations; bits >= 1; bits--) {
    final sub = List<bool>.filled(_draw * _draw, false);
    final names = <int>[];
    for (var p = 0; p < pieces.length; p++) {
      if (bits & (1 << p) == 0) continue;
      names.add(p + 1);
      for (final i in pieces[p]) {
        sub[i] = true;
      }
    }
    if (bits != combinations && _side(sub) < _pieceFloor * wholeSide) continue;
    compared++;
    final where = bits == combinations
        ? 'the whole drawing'
        : 'piece${names.length > 1 ? 's' : ''} ${names.join('+')}';
    final norm = _normalise(sub);
    for (final r in references.entries) {
      final v = _iou(norm, r.value);
      if (v > best.iou) {
        best = _Match(r.key, v, where, pieces.length, combinations, 0, const []);
      }
      if (v >= _redLine && !redByMark.containsKey(r.key)) {
        redByMark[r.key] = '${r.key} ${v.toStringAsFixed(3)} ($where)';
      }
    }
  }
  return _Match(best.mark, best.iou, best.where, pieces.length, combinations,
      compared, redByMark.values.toList());
}

/// Separate pieces of a mask: 8-connected ink, numbered in reading order.
List<List<int>> _pieces(List<bool> m) {
  final seen = List<bool>.filled(m.length, false);
  final out = <List<int>>[];
  for (var start = 0; start < m.length; start++) {
    if (!m[start] || seen[start]) continue;
    final piece = <int>[];
    final stack = [start];
    seen[start] = true;
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      piece.add(i);
      final x = i % _draw, y = i ~/ _draw;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= _draw || ny >= _draw) continue;
          final j = ny * _draw + nx;
          if (m[j] && !seen[j]) {
            seen[j] = true;
            stack.add(j);
          }
        }
      }
    }
    out.add(piece);
  }
  return out;
}

/// The larger side of a mask's ink, in px; 0 for an empty mask.
int _side(List<bool> m) {
  var x0 = _draw, y0 = _draw, x1 = -1, y1 = -1;
  for (var i = 0; i < m.length; i++) {
    if (!m[i]) continue;
    final x = i % _draw, y = i ~/ _draw;
    x0 = math.min(x0, x);
    y0 = math.min(y0, y);
    x1 = math.max(x1, x);
    y1 = math.max(y1, y);
  }
  return x1 < 0 ? 0 : math.max(x1 - x0 + 1, y1 - y0 + 1);
}

int _differing(List<bool> a, List<bool> b) {
  var n = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) n++;
  }
  return n;
}

Future<Map<String, List<bool>>>? _referencesOnce;

/// Android's pin and every location glyph, each cropped and scaled.
Future<Map<String, List<bool>>> _references() =>
    _referencesOnce ??= () async {
      return <String, List<bool>>{
        'Android 14 location indicator (perm_group_location)': _normalise(
          await _fill(_androidLocationIndicator, 24),
        ),
        for (final e in _locationGlyphs.entries)
          'Icons.${e.key}': await _glyph(e.value),
      };
    }();

// ---------------------------------------------------------------- drawing --

/// The test cannot draw the icon as Android would, so it cannot clear it.
class _CannotDraw implements Exception {
  _CannotDraw(this.why);
  final String why;
  @override
  String toString() =>
      'this test cannot draw the icon as Android would, so it cannot clear '
      'it: $why';
}

class _VectorPath {
  _VectorPath(this.d, this.fill, this.evenOdd, this.strokeWidth, this.cap,
      this.join, this.miter);
  final String d;
  final bool fill;
  final bool evenOdd;
  final double strokeWidth; // 0 = no stroke
  final StrokeCap cap;
  final StrokeJoin join;
  final double miter;
}

const _vectorAttributes = {
  'xmlns:android',
  'android:name',
  'android:width',
  'android:height',
  'android:viewportWidth',
  'android:viewportHeight',
};

const _pathAttributes = {
  'android:name',
  'android:pathData',
  'android:fillColor',
  'android:fillAlpha',
  'android:fillType',
  'android:strokeColor',
  'android:strokeWidth',
  'android:strokeAlpha',
  'android:strokeLineCap',
  'android:strokeLineJoin',
  'android:strokeMiterLimit',
};

/// Draws a `<vector>` file the way Android draws it, uncropped, as a
/// [_draw]-px mask. Throws [_CannotDraw] on anything it does not read.
Future<List<bool>> _drawVector(String xml) async {
  final body = xml
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
      .replaceFirst(RegExp(r'^\s*<\?xml[^>]*\?>'), '');
  final tagRe = RegExp(
    r'''<(/?)([A-Za-z][\w:.-]*)((?:[^>"']|"[^"]*"|'[^']*')*)>''',
  );
  final residue = body.replaceAll(tagRe, '').trim();
  if (residue.isNotEmpty) {
    throw _CannotDraw('it does not read "$residue"');
  }
  final tags = tagRe.allMatches(body).toList();
  if (tags.isEmpty || tags.first.group(2) != 'vector' ||
      tags.first.group(1)!.isNotEmpty) {
    throw _CannotDraw('the file does not start with <vector>');
  }
  late double viewportWidth, viewportHeight;
  final paths = <_VectorPath>[];
  for (final t in tags) {
    final name = t.group(2)!;
    if (name != 'vector' && name != 'path') {
      throw _CannotDraw(
        '<$name> is not read (no group transforms, clip paths or gradients)',
      );
    }
    if (t.group(1)!.isNotEmpty) continue; // a closing tag
    final a = _attributes(t.group(3)!, name);
    final known = name == 'vector' ? _vectorAttributes : _pathAttributes;
    for (final k in a.keys) {
      if (!known.contains(k)) throw _CannotDraw('$k on <$name> is not read');
    }
    if (name == 'vector') {
      if (a['android:width'] != a['android:height']) {
        throw _CannotDraw(
          'the icon is ${a['android:width']} by ${a['android:height']}, '
          'not square',
        );
      }
      viewportWidth = _number(a, 'android:viewportWidth', null);
      viewportHeight = _number(a, 'android:viewportHeight', null);
      if (viewportWidth <= 0 || viewportHeight <= 0) {
        throw _CannotDraw('the viewport is empty');
      }
      continue;
    }
    final d = a['android:pathData'];
    if (d == null || d.trim().isEmpty) {
      throw _CannotDraw('a <path> has no pathData');
    }
    final fillAlpha = a.containsKey('android:fillColor')
        ? _alpha(a['android:fillColor']!) * _number(a, 'android:fillAlpha', 1)
        : 0.0;
    final strokeAlpha = a.containsKey('android:strokeColor')
        ? _alpha(a['android:strokeColor']!) *
              _number(a, 'android:strokeAlpha', 1)
        : 0.0;
    final width = _number(a, 'android:strokeWidth', 0);
    if (width < 0) throw _CannotDraw('a negative strokeWidth');
    final fillType = a['android:fillType'] ?? 'nonZero';
    if (fillType != 'nonZero' && fillType != 'evenOdd') {
      throw _CannotDraw('fillType="$fillType"');
    }
    paths.add(
      _VectorPath(
        d,
        fillAlpha > 0,
        fillType == 'evenOdd',
        strokeAlpha > 0 ? width : 0,
        _choose(a, 'android:strokeLineCap', const {
          'butt': StrokeCap.butt,
          'round': StrokeCap.round,
          'square': StrokeCap.square,
        }, StrokeCap.butt),
        _choose(a, 'android:strokeLineJoin', const {
          'miter': StrokeJoin.miter,
          'round': StrokeJoin.round,
          'bevel': StrokeJoin.bevel,
        }, StrokeJoin.miter),
        _number(a, 'android:strokeMiterLimit', 4),
      ),
    );
  }
  if (paths.isEmpty) throw _CannotDraw('the file has no <path>');

  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec)
    ..scale(_draw / viewportWidth, _draw / viewportHeight);
  for (final p in paths) {
    final path = _parse(p.d)
      ..fillType = p.evenOdd ? PathFillType.evenOdd : PathFillType.nonZero;
    if (p.fill) canvas.drawPath(path, Paint()..color = _ink);
    if (p.strokeWidth > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = p.strokeWidth
          ..strokeCap = p.cap
          ..strokeJoin = p.join
          ..strokeMiterLimit = p.miter,
      );
    }
  }
  return _pixels(rec.endRecording());
}

const _ink = Color(0xFFFFFFFF);

Map<String, String> _attributes(String text, String element) {
  final re = RegExp(r'''([A-Za-z_][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')''');
  final out = <String, String>{};
  for (final m in re.allMatches(text)) {
    if (out.containsKey(m.group(1))) {
      throw _CannotDraw('${m.group(1)} twice on <$element>');
    }
    out[m.group(1)!] = m.group(2) ?? m.group(3)!;
  }
  final rest = text.replaceAll(re, '').trim();
  if (rest.isNotEmpty && rest != '/') {
    throw _CannotDraw('it does not read "$rest" on <$element>');
  }
  return out;
}

double _number(Map<String, String> a, String key, double? fallback) {
  final raw = a[key];
  if (raw == null) {
    if (fallback == null) throw _CannotDraw('no $key');
    return fallback;
  }
  final v = double.tryParse(raw.trim());
  if (v == null) throw _CannotDraw('$key="$raw" is not a number');
  return v;
}

T _choose<T>(Map<String, String> a, String key, Map<String, T> by, T fallback) {
  final raw = a[key];
  if (raw == null) return fallback;
  final v = by[raw];
  if (v == null) throw _CannotDraw('$key="$raw"');
  return v;
}

/// The alpha of a literal colour, 0 to 1. A reference cannot be resolved here.
double _alpha(String colour) {
  final m = RegExp(
    r'^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$',
  ).firstMatch(colour.trim());
  if (m == null) {
    throw _CannotDraw(
      'the colour "$colour" is not a literal (#RGB, #ARGB, #RRGGBB, '
      '#AARRGGBB), and this test does not resolve references',
    );
  }
  final h = m.group(1)!;
  return switch (h.length) {
    4 => int.parse(h[0], radix: 16) * 17 / 255,
    8 => int.parse(h.substring(0, 2), radix: 16) / 255,
    _ => 1.0,
  };
}

/// Fills path data in a square viewport, uncropped. For the reference pin.
Future<List<bool>> _fill(List<String> pathData, double viewport) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec)..scale(_draw / viewport);
  for (final d in pathData) {
    canvas.drawPath(_parse(d), Paint()..color = _ink);
  }
  return _pixels(rec.endRecording());
}

Future<List<bool>> _glyph(IconData icon) async {
  final rec = ui.PictureRecorder();
  final tp = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: _draw.toDouble(),
        height: 1.0,
        color: _ink,
      ),
    ),
  )..layout();
  tp.paint(Canvas(rec), Offset.zero);
  tp.dispose();
  return _normalise(await _pixels(rec.endRecording()));
}

Future<List<bool>> _pixels(ui.Picture picture) async {
  final image = await picture.toImage(_draw, _draw);
  final bytes = (await image.toByteData())!;
  image.dispose();
  picture.dispose();
  return [
    for (var i = 0; i < _draw * _draw; i++) bytes.getUint8(i * 4 + 3) >= 128,
  ];
}

/// Crops a mask to its ink and scales it, aspect kept and centred, to
/// [_cell] x [_cell]. An empty mask stays empty.
List<bool> _normalise(List<bool> m) {
  var x0 = _draw, y0 = _draw, x1 = -1, y1 = -1;
  for (var y = 0; y < _draw; y++) {
    for (var x = 0; x < _draw; x++) {
      if (m[y * _draw + x]) {
        x0 = math.min(x0, x);
        y0 = math.min(y0, y);
        x1 = math.max(x1, x);
        y1 = math.max(y1, y);
      }
    }
  }
  final out = List<bool>.filled(_cell * _cell, false);
  if (x1 < 0) return out;
  final w = x1 - x0 + 1, h = y1 - y0 + 1, side = math.max(w, h);
  final ox = x0 - (side - w) / 2, oy = y0 - (side - h) / 2;
  for (var y = 0; y < _cell; y++) {
    for (var x = 0; x < _cell; x++) {
      final sx = (ox + (x + 0.5) * side / _cell).floor();
      final sy = (oy + (y + 0.5) * side / _cell).floor();
      if (sx >= 0 && sy >= 0 && sx < _draw && sy < _draw) {
        out[y * _cell + x] = m[sy * _draw + sx];
      }
    }
  }
  return out;
}

double _inkShare(List<bool> m) => m.where((b) => b).length / m.length;

double _iou(List<bool> a, List<bool> b) {
  var both = 0, either = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] && b[i]) both++;
    if (a[i] || b[i]) either++;
  }
  expect(either, greaterThan(0), reason: 'two empty shapes were compared');
  return both / either;
}

// ----------------------------------------------------------- path reader --

/// Reads SVG / VectorDrawable path data (M L H V C S Q T A Z, absolute and
/// relative) into a [Path]. An unknown command throws.
Path _parse(String d) {
  final tokens = RegExp(
    r'[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
  ).allMatches(d).map((m) => m.group(0)!).toList();
  final p = Path();
  var i = 0;
  var cmd = '';
  var x = 0.0, y = 0.0, sx = 0.0, sy = 0.0;
  Offset? lastC, lastQ;
  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double n() => double.parse(tokens[i++]);
  bool flag() {
    final t = tokens[i];
    if (t.length > 1 && (t[0] == '0' || t[0] == '1') && t[1] != '.') {
      tokens[i] = t.substring(1);
      return t[0] == '1';
    }
    i++;
    return t == '1';
  }

  while (i < tokens.length) {
    if (isCmd(tokens[i])) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
    switch (cmd.toUpperCase()) {
      case 'Z':
        p.close();
        x = sx;
        y = sy;
        lastC = lastQ = null;
        continue;
      case 'M':
        x = ox + n();
        y = oy + n();
        sx = x;
        sy = y;
        p.moveTo(x, y);
        cmd = rel ? 'l' : 'L';
        lastC = lastQ = null;
      case 'L':
        x = ox + n();
        y = oy + n();
        p.lineTo(x, y);
        lastC = lastQ = null;
      case 'H':
        x = ox + n();
        p.lineTo(x, y);
        lastC = lastQ = null;
      case 'V':
        y = oy + n();
        p.lineTo(x, y);
        lastC = lastQ = null;
      case 'C':
        final c1 = Offset(ox + n(), oy + n());
        final c2 = Offset(ox + n(), oy + n());
        x = ox + n();
        y = oy + n();
        p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, x, y);
        lastC = c2;
        lastQ = null;
      case 'S':
        final c1 = lastC == null
            ? Offset(x, y)
            : Offset(2 * x - lastC.dx, 2 * y - lastC.dy);
        final c2 = Offset(ox + n(), oy + n());
        x = ox + n();
        y = oy + n();
        p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, x, y);
        lastC = c2;
        lastQ = null;
      case 'Q':
        final c1 = Offset(ox + n(), oy + n());
        x = ox + n();
        y = oy + n();
        p.quadraticBezierTo(c1.dx, c1.dy, x, y);
        lastQ = c1;
        lastC = null;
      case 'T':
        final c1 = lastQ == null
            ? Offset(x, y)
            : Offset(2 * x - lastQ.dx, 2 * y - lastQ.dy);
        x = ox + n();
        y = oy + n();
        p.quadraticBezierTo(c1.dx, c1.dy, x, y);
        lastQ = c1;
        lastC = null;
      case 'A':
        final rx = n(), ry = n(), rot = n();
        final large = flag(), sweep = flag();
        x = ox + n();
        y = oy + n();
        p.arcToPoint(
          Offset(x, y),
          radius: Radius.elliptical(rx, ry),
          rotation: rot,
          largeArc: large,
          clockwise: sweep,
        );
        lastC = lastQ = null;
      default:
        throw FormatException('path command "$cmd" in "$d"');
    }
  }
  return p;
}
