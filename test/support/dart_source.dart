/// Reads Dart source the way the compiler does for one purpose only: telling
/// code apart from comments and from the literal text inside strings.
///
/// WHY (2026-09-25). Two architectural guards in this suite read source as
/// text, and an independent mutation corpus, written by a hand other than the
/// guards' author, showed both passing real defects because of it:
///
/// - a release voice's only call was removed and its name was left in a
///   trailing comment, or inside a debug string, and the voice census still
///   counted it as a call (it skipped only lines that START with `//`);
/// - an import wrapped in a `/* */` block still counted as an import for the
///   pubspec citation guard.
///
/// A name inside a comment, or inside a string's literal text, is not a
/// reference, and a guard that counts it has measured the page rather than
/// the program. Both guards now read [dartCodeOnly] instead.
///
/// HONEST BOUND. This is a lexer, not a parser: it knows comments (including
/// nested block comments), the four quote forms, raw strings, escapes and
/// interpolation, and nothing about types or scopes. A source file the Dart
/// compiler rejects may be read differently here; an unterminated one-line
/// string is ended at its line break so it cannot swallow the rest of a file.
library;

const int _nl = 0x0A;
const int _cr = 0x0D;
const int _space = 0x20;
const int _dq = 0x22;
const int _dollar = 0x24;
const int _sq = 0x27;
const int _star = 0x2A;
const int _slash = 0x2F;
const int _backslash = 0x5C;
const int _r = 0x72;
const int _lbrace = 0x7B;
const int _rbrace = 0x7D;

bool _isIdentPart(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    c == 0x5F ||
    c == _dollar;

/// An interpolated identifier (`$name`) never contains `$` itself.
bool _isInterpolationStart(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F;

bool _isInterpolationPart(int c) =>
    _isInterpolationStart(c) || (c >= 0x30 && c <= 0x39);

class _Frame {
  _Frame.code()
      : isString = false,
        quote = 0,
        triple = false,
        raw = false;
  _Frame.string(this.quote, {required this.triple, required this.raw})
      : isString = true;

  final bool isString;
  final int quote;
  final bool triple;
  final bool raw;

  /// Open `{` inside this code frame. A `}` at depth 0 in an interpolation
  /// frame returns to the enclosing string.
  int braceDepth = 0;
}

/// [source] with every comment and the literal text of every string replaced
/// by spaces.
///
/// Line breaks are kept and every other code unit keeps its offset, so an
/// offset or a line number in the result names the same place in [source].
/// String delimiters are kept, and interpolations (`$name`, `${expression}`)
/// are kept as code, because they are code: `'${_speak()}'` calls `_speak`.
///
/// With [keepStrings] only comments are blanked, for a reader that needs a
/// string's value (an import's URI) but must not read a commented-out line.
String dartCodeOnly(String source, {bool keepStrings = false}) {
  final cu = source.codeUnits;
  final out = List<int>.of(cu);
  final n = cu.length;
  final stack = <_Frame>[_Frame.code()];

  void blank(int from, int to) {
    for (var k = from; k < to && k < n; k++) {
      if (out[k] != _nl && out[k] != _cr) out[k] = _space;
    }
  }

  var i = 0;
  while (i < n) {
    final f = stack.last;
    final c = cu[i];
    if (!f.isString) {
      if (c == _slash && i + 1 < n && cu[i + 1] == _slash) {
        var j = i;
        while (j < n && cu[j] != _nl && cu[j] != _cr) {
          j++;
        }
        blank(i, j);
        i = j;
        continue;
      }
      if (c == _slash && i + 1 < n && cu[i + 1] == _star) {
        var depth = 1;
        var j = i + 2;
        while (j < n && depth > 0) {
          if (cu[j] == _slash && j + 1 < n && cu[j + 1] == _star) {
            depth++;
            j += 2;
          } else if (cu[j] == _star && j + 1 < n && cu[j + 1] == _slash) {
            depth--;
            j += 2;
          } else {
            j++;
          }
        }
        blank(i, j);
        i = j;
        continue;
      }
      if (c == _sq || c == _dq) {
        final raw = i > 0 && cu[i - 1] == _r && (i < 2 || !_isIdentPart(cu[i - 2]));
        final triple = i + 2 < n && cu[i + 1] == c && cu[i + 2] == c;
        stack.add(_Frame.string(c, triple: triple, raw: raw));
        i += triple ? 3 : 1;
        continue;
      }
      if (c == _lbrace) {
        f.braceDepth++;
      } else if (c == _rbrace) {
        if (f.braceDepth == 0 && stack.length > 1) {
          stack.removeLast(); // the `}` closing `${` returns to the string
        } else {
          f.braceDepth--;
        }
      }
      i++;
      continue;
    }

    // Inside a string.
    if (c == f.quote) {
      if (!f.triple) {
        stack.removeLast();
        i++;
        continue;
      }
      if (i + 2 < n && cu[i + 1] == c && cu[i + 2] == c) {
        stack.removeLast();
        i += 3;
        continue;
      }
    }
    if (!f.triple && (c == _nl || c == _cr)) {
      stack.removeLast(); // unterminated: end it at the line break
      i++;
      continue;
    }
    if (!f.raw && c == _backslash) {
      final end = i + 2 <= n ? i + 2 : n;
      if (!keepStrings) blank(i, end);
      i = end;
      continue;
    }
    if (!f.raw && c == _dollar && i + 1 < n) {
      if (cu[i + 1] == _lbrace) {
        stack.add(_Frame.code());
        i += 2;
        continue;
      }
      if (_isInterpolationStart(cu[i + 1])) {
        var j = i + 1;
        while (j < n && _isInterpolationPart(cu[j])) {
          j++;
        }
        i = j;
        continue;
      }
    }
    if (!keepStrings) blank(i, i + 1);
    i++;
  }
  return String.fromCharCodes(out);
}

/// Offsets of the first code unit of every line in [text]; `\r\n`, `\n` and
/// `\r` each end a line, as `LineSplitter` and `readAsLinesSync` read them.
List<int> lineStartsOf(String text) {
  final starts = <int>[0];
  final cu = text.codeUnits;
  for (var i = 0; i < cu.length; i++) {
    if (cu[i] == _cr) {
      if (i + 1 < cu.length && cu[i + 1] == _nl) i++;
      starts.add(i + 1);
    } else if (cu[i] == _nl) {
      starts.add(i + 1);
    }
  }
  return starts;
}

/// The 0-based line holding [offset], given [lineStarts] from [lineStartsOf].
int lineOfOffset(List<int> lineStarts, int offset) {
  var lo = 0;
  var hi = lineStarts.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (lineStarts[mid] <= offset) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}

/// The offset just past the bracket that closes the one at [open] in [code]
/// (code-only text), counting `(`, `[` and `{` together; null if unclosed.
int? closingBracketEnd(String code, int open) {
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    final ch = code[i];
    if (ch == '(' || ch == '[' || ch == '{') {
      depth++;
    } else if (ch == ')' || ch == ']' || ch == '}') {
      depth--;
      if (depth == 0) return i + 1;
      if (depth < 0) return null;
    }
  }
  return null;
}
