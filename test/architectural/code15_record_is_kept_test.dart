/// Code 15's fix-interval record is deleted by HIS TAP and by nothing else in
/// lib/, and nothing in this build writes it.
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
/// It also fails on any WRITER of these names in lib/. The left-behind card
/// says 「この版は記録しません」 / "This version does not record". A build that
/// records (code 15) must replace that card with its own; this test failing is
/// how the person building it is told.
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
      // Keep URLs and string contents that hold '//' only when they are not
      // comments; every line this guard reads has no such string.
      return i >= 0 ? l.substring(0, i) : l;
    })
    .join('\n');

const _keeper = 'lib/services/fix_interval_record_keeper.dart';

List<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  test('code 15\'s names appear in exactly one file of lib/: the keeper', () {
    final names = RegExp(
      r'kCode15RecordFileName|kCode15StoppedFileName|kCode15RecordFileNames'
      r'|fix_interval_record_15',
    );
    final where = <String>[];
    for (final f in _libFiles()) {
      if (names.hasMatch(_code(f.path))) {
        where.add(f.path.replaceAll(r'\', '/'));
      }
    }
    expect(
      where,
      [_keeper],
      reason:
          'Code 15\'s file names (or the literal) are used outside the '
          'keeper: $where. Every use outside it is a route to a deletion or '
          'a write that the keeper\'s rule cannot see. Use '
          'LeftBehindFixIntervalRecord instead.',
    );
  });

  test('the keeper deletes in exactly ONE place, and that place is '
      'deleteOnHisTap', () {
    final code = _code(_keeper);
    expect(
      RegExp(r'\.deleteSync\(').allMatches(code).length,
      1,
      reason: 'one deleteSync, inside deleteOnHisTap',
    );
    expect(
      RegExp(r'\.delete\(').allMatches(code).length,
      0,
      reason: 'no async delete in the keeper',
    );
    final body = RegExp(
      r'bool deleteOnHisTap\(\) \{(.*?)\n  \}',
      dotAll: true,
    ).firstMatch(code);
    expect(body, isNotNull, reason: 'deleteOnHisTap not found');
    expect(body!.group(1), contains('.deleteSync('));
  });

  test('deleteOnHisTap has ONE caller in lib/, inside the 記録を消す button\'s '
      'onPressed', () {
    var calls = 0;
    for (final f in _libFiles()) {
      final code = _code(f.path);
      final n = RegExp(r'\bdeleteOnHisTap\b').allMatches(code).length;
      calls += f.path.replaceAll(r'\', '/') == _keeper ? n - 1 : n;
    }
    expect(
      calls,
      1,
      reason:
          'Expected the declaration plus exactly one call: the Delete '
          'record button. A second call is a deletion he did not ask for.',
    );
    final main = _code('lib/main.dart');
    final button = RegExp(
      r"Key\('left-behind-record-delete-button'\),(.*?)child:",
      dotAll: true,
    ).firstMatch(main);
    expect(button, isNotNull, reason: 'the Delete record button is gone');
    expect(button!.group(1), contains('onPressed'));
    expect(button.group(1), contains('deleteOnHisTap'));
  });

  test('main() reaches the records only through launchRecordHousekeeping, '
      'which calls no delete of code 15\'s', () {
    final main = _code('lib/main.dart');
    final body = RegExp(
      r'Future<void> main\(\) async \{(.*?)\n\}',
      dotAll: true,
    ).firstMatch(main);
    expect(body, isNotNull);
    expect(body!.group(1), contains('launchRecordHousekeeping('));
    expect(body.group(1), isNot(contains('deleteOnHisTap')));
    // What it found reaches the app. Dropping it is how code 13's deletion
    // went silent: the count was returned and thrown away at this call site.
    expect(
      body.group(1),
      contains('code13Deletion: records.code13'),
      reason:
          'main() calls the housekeeping but does not hand its deletion '
          'to the app: a lost reading would be silent again',
    );
    expect(
      body.group(1),
      contains('leftBehindRecord: records.leftBehind'),
      reason:
          'main() does not hand code 15\'s record to the app: his card '
          'would never show, and he could not see or delete his data',
    );
    final keeper = _code(_keeper);
    final housekeeping = RegExp(
      r'Future<LaunchRecordsState> launchRecordHousekeeping\((.*?)\n\}',
      dotAll: true,
    ).firstMatch(keeper);
    expect(housekeeping, isNotNull);
    expect(housekeeping!.group(1), isNot(contains('deleteOnHisTap')));
    expect(housekeeping.group(1), isNot(contains('deleteSync')));
  });

  test('nothing in this build WRITES code 15\'s record: the left-behind card '
      'says this version does not record', () {
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
      expect(
        code,
        isNot(contains(writer)),
        reason:
            'The keeper now writes ($writer). If this is code 15, its '
            'own recording card must replace the left-behind card, whose '
            'words say 「この版は記録しません」, and this guard is updated '
            'with that change in view.',
      );
    }
  });

  test('no recursive delete anywhere in lib/ (it would take code 15\'s record '
      'without naming it)', () {
    for (final f in _libFiles()) {
      final code = _code(f.path);
      expect(
        RegExp(r'delete(Sync)?\(\s*recursive:\s*true').hasMatch(code),
        isFalse,
        reason: '${f.path} deletes recursively',
      );
    }
  });
}
