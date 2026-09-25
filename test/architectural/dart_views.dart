/// Two views of Dart source for the tests that READ THE TREE, so a word in a
/// comment or inside a string is never taken for code.
///
/// Both views have exactly the length of the file, with every newline in
/// place, so an offset or a line number means the same in the file and in
/// either view:
///  - [DartViews.code]: comments blanked to spaces, strings kept, so a key
///    written as a string literal can still be read;
///  - [DartViews.shape]: comments AND the contents of every string blanked,
///    the quotes kept, and the code inside `${…}` and `$name`
///    interpolations kept, because that code runs.
///
/// Why not the house `_code()` helper (test/architectural/
/// location_share_has_one_gated_caller_test.dart): it cuts a line at its
/// first `//`, and in lib/main.dart that is often the `//` of an `https://`
/// inside a string, which would hide the rest of the line from a scan.
///
/// HONEST BOUND. A hand-written scanner, not the Dart parser. It knows '…',
/// "…", '''…''', """…""", raw r'…', `\` escapes, `${…}` with strings nested
/// inside it, `$name`, // comments and nested /* */ comments. It does not
/// know which code is live.
library;

import 'dart:io';

class DartViews {
  DartViews(this.text) {
    _code(0, false);
    code = _c.toString();
    shape = _s.toString();
    assert(code.length == text.length && shape.length == text.length);
  }

  factory DartViews.read(String path) =>
      DartViews(File(path).readAsStringSync());

  final String text;
  late final String code;
  late final String shape;

  final _c = StringBuffer();
  final _s = StringBuffer();

  static final _identStart = RegExp(r'[A-Za-z_]');
  static final _identPart = RegExp(r'[A-Za-z0-9_$]');

  String _blank(String s) {
    final b = StringBuffer();
    for (final unit in s.split('')) {
      b.write(unit == '\n' ? '\n' : ' ');
    }
    return b.toString();
  }

  void _keep(int a, int b) {
    final s = text.substring(a, b);
    _c.write(s);
    _s.write(s);
  }

  void _comment(int a, int b) {
    final s = _blank(text.substring(a, b));
    _c.write(s);
    _s.write(s);
  }

  void _stringChars(int a, int b) {
    final s = text.substring(a, b);
    _c.write(s);
    _s.write(_blank(s));
  }

  /// Scans code from [i]. Inside an interpolation it returns at the `}` that
  /// closes it, without consuming it.
  int _code(int i, bool interpolation) {
    final t = text;
    var depth = 0;
    while (i < t.length) {
      if (t.startsWith('//', i)) {
        final e = t.indexOf('\n', i);
        final end = e < 0 ? t.length : e;
        _comment(i, end);
        i = end;
        continue;
      }
      if (t.startsWith('/*', i)) {
        var j = i, nest = 0;
        do {
          if (t.startsWith('/*', j)) {
            nest++;
            j += 2;
          } else if (t.startsWith('*/', j)) {
            nest--;
            j += 2;
          } else {
            j++;
          }
        } while (nest > 0 && j < t.length);
        _comment(i, j);
        i = j;
        continue;
      }
      final ch = t[i];
      if (ch == "'" || ch == '"') {
        final raw = i > 0 &&
            t[i - 1] == 'r' &&
            (i < 2 || !_identPart.hasMatch(t[i - 2]));
        i = _string(i, raw);
        continue;
      }
      if (interpolation) {
        if (ch == '{') depth++;
        if (ch == '}') {
          if (depth == 0) return i;
          depth--;
        }
      }
      _keep(i, i + 1);
      i++;
    }
    return i;
  }

  int _string(int i, bool raw) {
    final t = text;
    final q = t[i];
    final delim = t.startsWith(q * 3, i) ? q * 3 : q;
    _keep(i, i + delim.length);
    i += delim.length;
    while (i < t.length) {
      if (t.startsWith(delim, i)) {
        _keep(i, i + delim.length);
        return i + delim.length;
      }
      if (delim.length == 1 && t[i] == '\n') return i;
      if (!raw && t[i] == r'\' && i + 1 < t.length) {
        _stringChars(i, i + 2);
        i += 2;
        continue;
      }
      if (!raw && t.startsWith(r'${', i)) {
        _stringChars(i, i + 2);
        i = _code(i + 2, true);
        if (i < t.length) {
          _stringChars(i, i + 1);
          i++;
        }
        continue;
      }
      if (!raw &&
          t[i] == r'$' &&
          i + 1 < t.length &&
          _identStart.hasMatch(t[i + 1])) {
        _stringChars(i, i + 1);
        var j = i + 1;
        while (j < t.length && _identPart.hasMatch(t[j]) && t[j] != r'$') {
          j++;
        }
        _keep(i + 1, j);
        i = j;
        continue;
      }
      _stringChars(i, i + 1);
      i++;
    }
    return i;
  }

  /// The offset of the `}` that closes the `{` at [open], counted in
  /// [shape], where no brace inside a string or a comment remains.
  int closingBrace(int open) {
    var depth = 0;
    for (var i = open; i < shape.length; i++) {
      if (shape[i] == '{') depth++;
      if (shape[i] == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// 1-based line number of [offset].
  int lineOf(int offset) => '\n'.allMatches(text.substring(0, offset)).length + 1;
}
