/// Code 15's fix-interval record is deleted by HIS TAP and by nothing else in
/// lib/, ON CODE 15, where it is also written.
///
/// WHY A SOURCE-LEVEL GUARD. test/services/fix_interval_record_keeper_test.dart
/// runs the launch path main() runs and proves it leaves code 15's files. It
/// cannot see a SECOND deletion being added somewhere else: a cleanup on
/// resume, a "tidy test files" step, the record's names added to a delete
/// list. Each would pass every behavioural test and lose the reading the way
/// code 13's was lost. That is Sakichi Vision 9: "The operator must not be the
/// last line of defense against defects — the machine itself must catch
/// them." Without this file, a reviewer is that last line.
///
/// WHAT CHANGED FROM MAIN, AND WHY (code 15's branch only, never merged).
/// On main this file fails on any WRITER of these names, because main's
/// left-behind card says 「この版は記録しません」 / "This version does not
/// record". Code 15 records, so here:
/// - the names may appear in exactly two files: the keeper (main's, unchanged
///   here) and the recorder, which imports them and never retypes them;
/// - the keeper still deletes in one place (deleteOnHisTap), and on this build
///   NOTHING calls it: the left-behind card is not drawn;
/// - the recorder deletes in one place, deleteRecordOnHisTap, which keeps the
///   stopped marker (code 13's rule), and its one caller is code 15's
///   記録を消す button;
/// - the left-behind card's words are referenced nowhere in lib/ but their
///   definition, so no surface of this build can show them;
/// - the recorder writes `end` only at his tap: in one function, reached only
///   from the two buttons that end a share at his hand.
///
/// HONEST BOUND. This is a grep over source text, not a call graph. It cannot
/// see a deletion reached through a path built at run time from other
/// strings, through reflection, or by a plugin's native code; and it cannot
/// see Android clearing the app's data or an uninstall, which delete every
/// file of the app and are named on the card. It catches the shapes a future
/// edit is most likely to take, and nothing wider is claimed for it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source with comments removed, so a mention in prose — including in the
/// comments that explain this guard — cannot satisfy or break a count.
String _code(String path) => File(path)
    .readAsStringSync()
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((l) {
      final t = l.trimLeft();
      if (t.startsWith('///') || t.startsWith('//')) return '';
      final i = l.indexOf('//');
      return i >= 0 ? l.substring(0, i) : l;
    })
    .join('\n');

const _keeper = 'lib/services/fix_interval_record_keeper.dart';
const _recorder = 'lib/services/code15_fix_interval_record.dart';

List<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

String _norm(File f) => f.path.replaceAll(r'\', '/');

void main() {
  test('code 15\'s names appear in exactly two files of lib/: the keeper, and '
      'the recorder that imports them', () {
    final names = RegExp(
      r'kCode15RecordFileName|kCode15StoppedFileName|kCode15RecordFileNames'
      r'|fix_interval_record_15',
    );
    final where = <String>[
      for (final f in _libFiles())
        if (names.hasMatch(_code(f.path))) _norm(f),
    ]..sort();
    expect(where, [_recorder, _keeper]..sort());
    expect(_code(_recorder), isNot(contains('fix_interval_record_15')),
        reason: 'the recorder retyped a name instead of importing it');
    expect(_code(_recorder), contains("import 'fix_interval_record_keeper.dart'"));
  });

  test('the keeper deletes in exactly ONE place, and that place is '
      'deleteOnHisTap (main\'s keeper, unchanged)', () {
    final code = _code(_keeper);
    expect(RegExp(r'\.deleteSync\(').allMatches(code).length, 1);
    expect(RegExp(r'\.delete\(').allMatches(code).length, 0);
    final body = RegExp(
      r'bool deleteOnHisTap\(\) \{(.*?)\n  \}',
      dotAll: true,
    ).firstMatch(code);
    expect(body, isNotNull);
    expect(body!.group(1), contains('.deleteSync('));
  });

  test('on this build the keeper\'s deleteOnHisTap has NO caller: the '
      'left-behind card is not drawn', () {
    var calls = 0;
    for (final f in _libFiles()) {
      final n = RegExp(r'\bdeleteOnHisTap\b').allMatches(_code(f.path)).length;
      calls += _norm(f) == _keeper ? n - 1 : n;
    }
    expect(calls, 0);
  });

  test('the recorder deletes in exactly two places: its record, in '
      'deleteRecordOnHisTap, and the stopped marker, in resume', () {
    final code = _code(_recorder);
    expect(RegExp(r'\.deleteSync\(').allMatches(code).length, 2);
    expect(RegExp(r'\.delete\(').allMatches(code).length, 0);
    final del = RegExp(
      r'void deleteRecordOnHisTap\(\) \{(.*?)\n  \}',
      dotAll: true,
    ).firstMatch(code);
    expect(del, isNotNull);
    expect(del!.group(1), contains('file.deleteSync('));
    expect(del.group(1), isNot(contains('stoppedFile')),
        reason: 'his delete must keep whether it records (code 13\'s rule)');
    final resume =
        RegExp(r'void resume\(\) \{(.*?)\n  \}', dotAll: true).firstMatch(code);
    expect(resume!.group(1), contains('stoppedFile.deleteSync('));
  });

  test('deleteRecordOnHisTap has ONE caller in lib/, inside code 15\'s '
      '記録を消す button\'s onPressed', () {
    var calls = 0;
    for (final f in _libFiles()) {
      final n =
          RegExp(r'\bdeleteRecordOnHisTap\b').allMatches(_code(f.path)).length;
      calls += _norm(f) == _recorder ? n - 1 : n;
    }
    expect(calls, 1);
    final main = _code('lib/main.dart');
    final button = RegExp(
      r"Key\('code15-record-delete-button'\),(.*?)child:",
      dotAll: true,
    ).firstMatch(main);
    expect(button, isNotNull, reason: 'the Delete record button is gone');
    expect(button!.group(1), contains('onPressed'));
    expect(button.group(1), contains('deleteRecordOnHisTap'));
  });

  test('main() reaches the records through launchRecordHousekeeping, then '
      'opens code 15\'s record, and hands both to the app', () {
    final main = _code('lib/main.dart');
    final body = RegExp(
      r'Future<void> main\(\) async \{(.*?)\n\}',
      dotAll: true,
    ).firstMatch(main);
    expect(body, isNotNull);
    final b = body!.group(1)!;
    expect(b, contains('launchRecordHousekeeping('));
    expect(b, contains('openCode15FixIntervalRecord('));
    expect(b.indexOf('launchRecordHousekeeping('),
        lessThan(b.indexOf('openCode15FixIntervalRecord(')));
    expect(b, isNot(contains('deleteOnHisTap')));
    expect(b, isNot(contains('deleteRecordOnHisTap')));
    expect(b, contains('code13Deletion: records.code13'));
    expect(b, contains('code15Record: code15Record'));
    expect(b, isNot(contains('leftBehind')),
        reason: 'the left-behind view reached the app on a recording build');
  });

  test('the left-behind card\'s words are referenced nowhere in lib/ but '
      'their definition', () {
    final words = RegExp(r'\bleftBehindRecord(Status|SectionTitle|Share|Delete)\b');
    for (final f in _libFiles()) {
      if (_norm(f) == 'lib/l10n/app_localizations.dart') continue;
      expect(words.hasMatch(_code(f.path)), isFalse, reason: _norm(f));
    }
  });

  test('the keeper itself still writes nothing; the recorder is the only '
      'writer of these names', () {
    final code = _code(_keeper);
    for (final writer in [
      'writeAsString',
      'writeAsBytes',
      'openWrite',
      'FileMode',
      'createSync',
      '.create(',
      'rename',
      'copySync',
      '.copy(',
    ]) {
      expect(code, isNot(contains(writer)), reason: writer);
    }
    expect(_code(_recorder), contains('writeAsStringSync('));
  });

  test('`end` is written only at his tap: one call of recordEnd in lib/, in '
      'the function the two share-ending buttons call, and nowhere else', () {
    final main = _code('lib/main.dart');
    var calls = 0;
    for (final f in _libFiles()) {
      final n = RegExp(r'\.recordEnd\(').allMatches(_code(f.path)).length;
      calls += n;
    }
    expect(calls, 1);
    final wrapper = RegExp(
      r'void _clearPositionAtHisTap\(\) \{(.*?)\n  \}',
      dotAll: true,
    ).firstMatch(main);
    expect(wrapper, isNotNull);
    expect(wrapper!.group(1), contains('.recordEnd('));
    expect(
      RegExp(r'onPressed: _clearPositionAtHisTap,').allMatches(main).length,
      2,
      reason: 'the clear action and 停止/閉じる',
    );
    expect(RegExp(r'\b_clearPositionAtHisTap\b').allMatches(main).length, 3,
        reason: 'the declaration and the two buttons');
    final clear = RegExp(
      r'void _clearPosition\(\) \{(.*?)\n  \}',
      dotAll: true,
    ).firstMatch(main);
    expect(clear!.group(1), isNot(contains('recordEnd')),
        reason: 'the app also ends shares through _clearPosition');
  });

  test('no recursive delete anywhere in lib/', () {
    for (final f in _libFiles()) {
      expect(
        RegExp(r'delete(Sync)?\(\s*recursive:\s*true').hasMatch(_code(f.path)),
        isFalse,
        reason: f.path,
      );
    }
  });
}
