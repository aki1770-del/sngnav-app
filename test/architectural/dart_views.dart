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
/// ONE LEXER (2026-09-25, round 5a). This file had its own hand-written
/// scanner, and test/support/dart_source.dart had another. Both were compared
/// with the Dart front end (package:analyzer) over every tracked .dart file of
/// this tree and the Flutter SDK's, and neither ever misread code, comment or
/// string text; they differed only in how they drew an interpolation's markers.
/// So this file keeps its views and its API and holds no scanner: [code] and
/// [shape] come from [dartCodeOnly], [shape] with the markers blanked as this
/// file always drew them. Both are byte-identical to what the old scanner
/// produced on every file measured. The one place the old scanner differed
/// from the Dart grammar, a lone carriage return (no file here holds one),
/// now reads as the grammar reads it.
///
/// HONEST BOUND. A hand-written lexer, not the Dart parser (see
/// [dartCodeOnly]). It does not know which code is live.
library;

import 'dart:io';

import '../support/dart_source.dart';

class DartViews {
  DartViews(this.text)
      : code = dartCodeOnly(text, keepStrings: true),
        shape = dartCodeOnly(text, keepInterpolationMarkers: false) {
    assert(code.length == text.length && shape.length == text.length);
  }

  factory DartViews.read(String path) =>
      DartViews(File(path).readAsStringSync());

  final String text;
  final String code;
  final String shape;

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
