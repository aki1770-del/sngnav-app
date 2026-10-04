/// The next-turn goldens draw a COPY of her panel; this test goes red when the
/// copy and the app's panel differ.
///
/// Why this test exists. `maneuver_narration_capture_test.dart` cannot draw
/// the app's `_maneuverNarrationPanel`: the method is private to the app's
/// state, and the hedge state that golden 09 shows is reached by no position
/// the app gives the drive brain. So the three goldens 07, 08 and 09 draw a
/// copy, and the copy said it was "copied verbatim from lib/main.dart". Read
/// on dee79bd, it was not. Its hedge arm painted `Colors.amber.shade900`
/// (2.38:1 on `amber.shade100`), where the app has painted
/// `kCautionTextOnAmber` (7.16:1) since 2026-09-15. Its `_kv` row had a fixed
/// 110 px label column where the app measures the label. It drew the
/// position row even with no position, never the test-position label, and
/// none of the lines that say where an icy mark came from. Golden 09 passed
/// the whole time, because a golden compares the copy with an image of the
/// copy. Nothing compared the copy with the app.
///
/// What this test compares. It reads both files as source and compares, after
/// comments and layout are removed:
///  1. the drawn region of the panel, from the `switch` on
///     `preview.confidence` to the end of the banner `Container`;
///  2. the `_kv` helper that draws the position row;
///  3. the localizer the position row is worded by.
/// It also pins what the copy leaves out on purpose: after the banner the app
/// draws only the narrate-button row, and nothing after that. A new line
/// drawn under the banner would otherwise be missing from every golden
/// without a word.
///
/// Why source and not pixels. The app's panel cannot be pumped in the hedge
/// state, so for that arm the app's source is the only first-hand reference
/// there is. And CI does not compare these goldens at all (see
/// `goldenPixelsComparableHere`); this test runs there.
///
/// What it does not see: the theme and the card the app sets the panel in,
/// and the narrate-button row. Those are named in the copy's own comment.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _appPath = 'lib/main.dart';
const _copyPath = 'test/render_see/maneuver_narration_capture_test.dart';

const _remedy =
    'Re-copy the region from $_appPath into '
    '_ManeuverNarrationPanelCopy in $_copyPath, then re-render 07, 08 and 09 '
    '(flutter test --update-goldens $_copyPath) and LOOK at them before you '
    'commit: they are the images a reviewer takes for her panel.';

/// Index just past the end of the string literal that starts at [i].
/// Handles '...', "...", their triple-quoted forms, raw strings, and
/// `${...}` interpolation in non-raw strings.
int _skipString(String s, int i) {
  var raw = false;
  if (s[i] == 'r') {
    raw = true;
    i++;
  }
  final q = s[i];
  final triple = s.startsWith('$q$q$q', i);
  final close = triple ? '$q$q$q' : q;
  i += close.length;
  while (i < s.length) {
    if (!raw && s[i] == r'\') {
      i += 2;
      continue;
    }
    if (!raw && s.startsWith(r'${', i)) {
      i = _matchClose(s, i + 1) + 1;
      continue;
    }
    if (s.startsWith(close, i)) return i + close.length;
    i++;
  }
  throw StateError('unterminated string literal');
}

bool _startsString(String s, int i) {
  final c = s[i];
  if (c == "'" || c == '"') return true;
  if (c == 'r' && i + 1 < s.length && (s[i + 1] == "'" || s[i + 1] == '"')) {
    // `r'` starts a raw string only when `r` is not the tail of an identifier.
    return i == 0 || !RegExp(r'[A-Za-z0-9_$]').hasMatch(s[i - 1]);
  }
  return false;
}

/// Index of the bracket that closes the one at [open], skipping strings and
/// comments.
int _matchClose(String s, int open) {
  const pairs = {'(': ')', '[': ']', '{': '}'};
  final stack = <String>[pairs[s[open]]!];
  var i = open + 1;
  while (i < s.length) {
    if (s.startsWith('//', i)) {
      i = s.indexOf('\n', i);
      if (i < 0) break;
      continue;
    }
    if (s.startsWith('/*', i)) {
      i = s.indexOf('*/', i) + 2;
      continue;
    }
    if (_startsString(s, i)) {
      i = _skipString(s, i);
      continue;
    }
    final c = s[i];
    if (pairs.containsKey(c)) {
      stack.add(pairs[c]!);
    } else if (c == stack.last) {
      stack.removeLast();
      if (stack.isEmpty) return i;
    }
    i++;
  }
  throw StateError('unbalanced bracket at $open');
}

/// The code in [src] without comments or layout: comments go, whitespace
/// collapses and is dropped next to punctuation, and trailing commas go.
/// String literals are kept byte for byte.
String _normalize(String src) {
  final out = StringBuffer();
  var i = 0;
  while (i < src.length) {
    if (src.startsWith('//', i)) {
      final nl = src.indexOf('\n', i);
      i = nl < 0 ? src.length : nl;
      continue;
    }
    if (src.startsWith('/*', i)) {
      i = src.indexOf('*/', i) + 2;
      out.write(' ');
      continue;
    }
    if (_startsString(src, i)) {
      final end = _skipString(src, i);
      out.write(src.substring(i, end));
      i = end;
      continue;
    }
    out.write(src[i]);
    i++;
  }
  final ident = RegExp(r'[A-Za-z0-9_$]');
  final collapsed = out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  final b = StringBuffer();
  for (var k = 0; k < collapsed.length; k++) {
    final c = collapsed[k];
    if (c == ' ') {
      final prev = b.isEmpty ? '' : b.toString()[b.length - 1];
      final next = k + 1 < collapsed.length ? collapsed[k + 1] : '';
      if (prev.isNotEmpty &&
          next.isNotEmpty &&
          ident.hasMatch(prev) &&
          ident.hasMatch(next)) {
        b.write(' ');
      }
      continue;
    }
    b.write(c);
  }
  return b.toString().replaceAllMapped(RegExp(r',([)\]}])'), (m) => m[1]!);
}

/// A regex that matches [code] with any whitespace between its tokens.
RegExp _flexible(String code) {
  final tokens = RegExp(
    r'[A-Za-z0-9_$]+|\S',
  ).allMatches(code).map((m) => RegExp.escape(m[0]!));
  return RegExp(tokens.join(r'\s*'));
}

int _find(String src, String code, {required String file, int from = 0}) {
  final m = _flexible(code).firstMatch(src.substring(from));
  if (m == null) {
    fail(
      '$file does not contain `$code`, so this test cannot find the '
      'region it compares. That is drift too: the panel changed shape. '
      '$_remedy',
    );
  }
  return from + m.start;
}

const _switchAnchor =
    'final (Color bg, Color fg, String tier) = switch (preview.confidence)';
const _bannerAnchor = "Container( key: const Key('maneuver-narration-banner')";

/// Source of the drawn region: from the confidence switch to the closing
/// paren of the banner `Container`.
({String text, int end}) _drawnRegion(String src, {required String file}) {
  final start = _find(src, _switchAnchor, file: file);
  final banner = _find(src, _bannerAnchor, file: file, from: start);
  final open = src.indexOf('(', banner);
  final end = _matchClose(src, open) + 1;
  return (text: src.substring(start, end), end: end);
}

String _kvHelper(String src, {required String file}) {
  final start = _find(src, 'Widget _kv(String k, String v) {', file: file);
  final open = src.indexOf('{', start);
  return src.substring(start, _matchClose(src, open) + 1);
}

/// Where the normalized texts first part, with enough on each side to read.
String _firstDifference(String app, String copy) {
  var i = 0;
  while (i < app.length && i < copy.length && app[i] == copy[i]) {
    i++;
  }
  String around(String s) {
    final a = (i - 80).clamp(0, s.length);
    final z = (i + 80).clamp(0, s.length);
    return '${s.substring(a, i)}⟦HERE⟧${s.substring(i, z)}';
  }

  return 'first difference at normalized offset $i of '
      '${app.length} (app) / ${copy.length} (copy):\n'
      '  app : ${around(app)}\n'
      '  copy: ${around(copy)}';
}

void main() {
  late String app;
  late String copy;

  setUpAll(() {
    app = File(_appPath).readAsStringSync();
    copy = File(_copyPath).readAsStringSync();
  });

  test('the copy draws what the app draws, from the confidence switch to the '
      'end of the banner', () {
    final a = _normalize(_drawnRegion(app, file: _appPath).text);
    final c = _normalize(_drawnRegion(copy, file: _copyPath).text);
    expect(
      c,
      a,
      reason:
          'The goldens show this copy as her panel, and it no longer '
          'draws what the app draws. ${_firstDifference(a, c)}\n$_remedy',
    );
  });

  test('the position row is drawn by the app\'s own _kv', () {
    final a = _normalize(_kvHelper(app, file: _appPath));
    final c = _normalize(_kvHelper(copy, file: _copyPath));
    expect(
      c,
      a,
      reason:
          'The copy lays out the position row differently from the '
          'app. ${_firstDifference(a, c)}\n$_remedy',
    );
  });

  test('the position row is worded by the app\'s own localizer', () {
    const decl =
        'static const DriveHudLocalizer _driveHudText = DriveHudLocalizer();';
    for (final (file, src) in [(_appPath, app), (_copyPath, copy)]) {
      expect(
        _flexible(decl).hasMatch(src),
        isTrue,
        reason: '$file does not declare `$decl`. $_remedy',
      );
    }
  });

  test('after the banner the app draws only the narrate-button row, which the '
      'copy leaves out on purpose', () {
    final region = _drawnRegion(app, file: _appPath);
    final row = _find(app, 'Row(', file: _appPath, from: region.end);
    final between = _normalize(app.substring(region.end, row));
    expect(
      between,
      ',const SizedBox(height:8),',
      reason:
          'The app now draws something between the banner and the '
          'narrate-button row, and no golden shows it. $_remedy',
    );

    final rowOpen = app.indexOf('(', row);
    final rowEnd = _matchClose(app, rowOpen) + 1;
    expect(
      _normalize(app.substring(row, rowEnd)),
      startsWith(
        "Row(children:[ElevatedButton.icon(key:const Key('maneuver-narrate-button')",
      ),
      reason:
          'The row after the banner is no longer the narrate-button row. '
          '$_remedy',
    );

    // The panel's Column must close right after that row: `], );` then the
    // method's `}`.
    final methodEnd = app.indexOf('}', rowEnd);
    expect(
      _normalize(app.substring(rowEnd, methodEnd)),
      ']);',
      reason:
          'The app draws something after the narrate-button row, and no '
          'golden shows it. $_remedy',
    );
  });
}
