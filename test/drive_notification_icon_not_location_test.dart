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
// So the icon must not be a location glyph, or a near copy of one. This test
// draws the icon from its own vector file and compares its shape with every
// location glyph of the Material Icons font the app ships, in all four
// styles, and with Android's own indicator. It is red when the icon is one of
// them.
//
// HOW IT COMPARES. Each shape is drawn at 96 px, cropped to its ink, scaled
// to 64x64 and compared by intersection over union (IoU) of the inked pixels.
// The red line is IoU >= 0.80. Measured with this test: Android's pin and the
// font's location_on_outlined are 0.98 alike although AOSP encodes the pin in
// its own path data, so a redrawn location glyph lands above the line. Two
// DIFFERENT location glyphs can be as little as about 0.4 alike, so a lower
// line would start failing icons that are not location marks.
//
// WHAT IT CANNOT SEE.
// - Meaning. It compares outlines, not what a driver reads into them. That an
//   icon reads as this app's drive is a glance question, and no timed glance
//   study exists.
// - Other system marks and other apps' icons. It knows only the location
//   family and Android's pin.
// - Rotation, <group> transforms and <clip-path> in the vector file. Scale and
//   position do not matter (every shape is cropped to its ink first).
// - How a phone's skin draws the icon. MIUI is not stock Android.
//
// If it cannot draw a shape, it fails: an empty or unread shape is never a
// pass.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The icon, as the app wires it (lib/her_position.dart, notificationIcon).
const _iconFile = 'android/app/src/main/res/drawable/ic_stat_sngnav.xml';

/// Android 14's own location indicator, `perm_group_location.xml`, read with
/// `aapt2 dump xmltree` from the API 34 emulator image's
/// /system/framework/framework-res.apk. Android Open Source Project, Apache
/// License 2.0. Used here only as a shape to compare against.
const _androidLocationIndicator = <String>[
  'M12,2C8.13,2 5,5.13 5,9c0,5.25 7,13 7,13s7,-7.75 7,-13C19,5.13 15.87,2 '
      '12,2zM7,9c0,-2.76 2.24,-5 5,-5s5,2.24 5,5c0,2.88 -2.88,7.19 -5,9.88'
      'C9.92,16.21 7,11.85 7,9z',
  'M12,9m-2.5,0a2.5,2.5 0,1 1,5 0a2.5,2.5 0,1 1,-5 0',
];

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the drive notification icon is not a location mark '
    '(IoU < $_redLine against every location glyph and Android\'s pin)',
    () async {
      final xml = File(_iconFile).readAsStringSync();
      final icon = await _shape(_vectorPaths(xml), _viewport(xml));
      expect(
        _inkShare(icon),
        greaterThan(0.05),
        reason: 'the icon drew almost nothing, so it was not compared',
      );

      final references = <String, List<bool>>{
        'Android 14 location indicator (perm_group_location)': await _shape(
          _androidLocationIndicator,
          24,
        ),
        for (final e in _locationGlyphs.entries)
          'Icons.${e.key}': await _glyph(e.value),
      };

      final scores = <String, double>{
        for (final r in references.entries) r.key: _iou(icon, r.value),
      };
      final worst = scores.entries.reduce((a, b) => a.value >= b.value ? a : b);
      // ignore: avoid_print
      print(
        'drive notification icon: closest location mark '
        '${worst.key} at IoU ${worst.value.toStringAsFixed(3)} '
        '(red at $_redLine; ${references.length} marks compared)',
      );
      final red = [
        for (final s in scores.entries)
          if (s.value >= _redLine) '${s.key} ${s.value.toStringAsFixed(3)}',
      ];
      expect(
        red,
        isEmpty,
        reason:
            'the status bar icon is shaped like a location mark. After '
            '停止 Android\'s own location indicator can stay in her bar, and '
            'she could take it for this app\'s drive still running.',
      );
    },
  );

  // The comparison must be able to fail. If the font did not load, every
  // glyph would draw as the same box; if the path reader broke, the pin would
  // draw wrong or not at all. Either would make the test above pass on
  // anything. So: Android's pin, drawn by the path reader, must match the
  // font's location_on_outlined, and must NOT match my_location.
  test('the comparison can see a location mark (controls)', () async {
    final pin = await _shape(_androidLocationIndicator, 24);
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
}

// ---------------------------------------------------------------- drawing --

/// The viewport width of a `<vector>`; the icon is drawn to fill [_draw] px.
double _viewport(String xml) {
  final m = RegExp(r'android:viewportWidth="([0-9.]+)"').firstMatch(xml);
  expect(m, isNotNull, reason: 'no viewportWidth in $_iconFile');
  return double.parse(m!.group(1)!);
}

/// Every android:pathData in the file, in order. An empty list fails.
List<String> _vectorPaths(String xml) {
  final paths = [
    for (final m in RegExp(r'android:pathData="([^"]*)"').allMatches(xml))
      m.group(1)!,
  ];
  expect(paths, isNotEmpty, reason: 'no pathData in $_iconFile');
  expect(
    xml.contains('fillType="evenOdd"'),
    isFalse,
    reason: 'this reader fills non-zero only; teach it evenOdd first',
  );
  return paths;
}

Future<List<bool>> _shape(List<String> pathData, double viewport) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec)..scale(_draw / viewport);
  for (final d in pathData) {
    canvas.drawPath(_parse(d), Paint()..color = const Color(0xFFFFFFFF));
  }
  return _normalise(await _pixels(rec.endRecording()));
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
        color: const Color(0xFFFFFFFF),
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
