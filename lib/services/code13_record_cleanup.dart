/// Deletes code 13's fix-timing record, if this phone still holds one, and
/// says so when a reading may have been lost.
///
/// Why (2026-10-06). Code 13 was a test build that wrote down how far apart
/// GPS fixes arrived, to read one number on one phone. Its card told the man
/// driving it that the record "is deleted when the next build is installed".
/// Code 13 was built on a branch that is never merged, so no later build knows
/// the record exists unless it is told here. Without this, the promise on his
/// screen would be false the day the next build arrives, and a file of his
/// drives would stay on his phone with no card left to delete it.
///
/// Why it now reports what it deleted (2026-10-09). Code 13's reading WAS lost
/// this way: code 14 deleted the record at its first launch, and the count this
/// function returned was thrown away at the call site, so the deletion left no
/// trace anywhere. A deletion that leaves no trace is a success-shaped silence
/// (Sakichi Vision 14). So the result now carries whether the record that went
/// held a fix line, and the app tells him once (see [Code13RecordDeletion]).
/// This does NOT protect code 15's record: that is
/// services/fix_interval_record_keeper.dart, which no launch path deletes.
///
/// What it does: on launch, deletes the two files code 13 wrote in the
/// app-support directory, by name, if they are there. Before deleting the
/// record it reads it once, only to learn whether it held a fix line. Nothing
/// else is read, moved or deleted: the error log, the drive diary and code 15's
/// record are untouched. It never throws; a file that cannot be deleted is
/// left, and launch goes on.
library;

import 'dart:io' show Directory, File;

import 'package:path_provider/path_provider.dart';

/// The files code 13 wrote (its `kFixTimingRecordFileName` and
/// `kFixTimingStoppedFileName`), in the app-support directory. Kept out of
/// Android backup by android/app/src/main/res/xml (test/architectural/
/// backup_exclusion_rules_test.dart holds the two lists together).
const List<String> kCode13RecordFileNames = [
  'fix_timing_record.txt',
  'fix_timing_record.stopped',
];

/// What one launch's deletion of code 13's files did.
///
/// [mustTell] is the only thing the app reads to decide whether to tell him:
/// the record that was deleted held a fix line, or existed and could not be
/// read (a record that cannot be read is told, never assumed empty: Vision
/// 16's fail-closed side, at the cost of one line, once).
class Code13RecordDeletion {
  const Code13RecordDeletion({
    required this.deletedFiles,
    required this.recordHeldFixLines,
  });

  /// Nothing was there to delete: the usual launch.
  static const Code13RecordDeletion none = Code13RecordDeletion(
    deletedFiles: 0,
    recordHeldFixLines: false,
  );

  /// How many of [kCode13RecordFileNames] were deleted (0, 1 or 2).
  final int deletedFiles;

  /// Whether the deleted record held a fix line (`k=fine` or `k=coarse`), or
  /// existed and could not be read.
  final bool recordHeldFixLines;

  /// Whether the app tells him, once, that this version deleted the record.
  bool get mustTell => recordHeldFixLines;
}

/// Whether [text] holds one of code 13's fix lines. Code 13's own test
/// (`fixTimingTextHasFixLines`, branch code13-fix-timing-record), restated
/// here because that branch is never merged.
bool code13TextHasFixLines(String text) =>
    RegExp(r'(^|\n)s=\d+ t=\d+ k=(fine|coarse) ').hasMatch(text);

/// Deletes code 13's files from [directory] (default: the app-support
/// directory), and returns what it deleted. Never throws.
Future<Code13RecordDeletion> deleteCode13FixTimingRecord({
  Directory? directory,
}) async {
  var deleted = 0;
  var heldFixLines = false;
  var recordDeleted = false;
  try {
    final dir = directory ?? await getApplicationSupportDirectory();
    for (final name in kCode13RecordFileNames) {
      try {
        final f = File('${dir.path}/$name');
        if (!f.existsSync()) continue;
        final isRecord = name == kCode13RecordFileNames.first;
        if (isRecord) {
          try {
            heldFixLines = code13TextHasFixLines(f.readAsStringSync());
          } catch (_) {
            // Present but unreadable: told, never assumed empty.
            heldFixLines = true;
          }
        }
        f.deleteSync();
        deleted++;
        if (isRecord) recordDeleted = true;
      } catch (_) {}
    }
  } catch (_) {}
  return Code13RecordDeletion(
    deletedFiles: deleted,
    // Told only when the RECORD itself went. If its delete failed, the file is
    // still there and nothing was lost; the stopped marker alone holds no
    // reading.
    recordHeldFixLines: heldFixLines && recordDeleted,
  );
}
