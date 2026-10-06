/// Deletes code 13's fix-timing record, if this phone still holds one.
///
/// Why (2026-10-06). Code 13 was a test build that wrote down how far apart
/// GPS fixes arrived, to read one number on one phone. Its card told the man
/// driving it that the record "is deleted when the next build is installed".
/// Code 13 was built on a branch that is never merged, so no later build knows
/// the record exists unless it is told here. Without this, the promise on his
/// screen would be false the day the next build arrives, and a file of his
/// drives would stay on his phone with no card left to delete it.
///
/// What it does: on launch, deletes the two files code 13 wrote in the
/// app-support directory, by name, if they are there. Nothing else is read,
/// moved or deleted: the error log and the drive diary are untouched. It
/// never throws; a file that cannot be deleted is left, and launch goes on.
library;

import 'dart:io' show Directory, File;

import 'package:path_provider/path_provider.dart';

/// The files code 13 wrote (its `kFixTimingRecordFileName` and
/// `kFixTimingStoppedFileName`), in the app-support directory.
const List<String> kCode13RecordFileNames = [
  'fix_timing_record.txt',
  'fix_timing_record.stopped',
];

/// Deletes code 13's files from [directory] (default: the app-support
/// directory). Returns how many were deleted. Never throws.
Future<int> deleteCode13FixTimingRecord({Directory? directory}) async {
  var deleted = 0;
  try {
    final dir = directory ?? await getApplicationSupportDirectory();
    for (final name in kCode13RecordFileNames) {
      try {
        final f = File('${dir.path}/$name');
        if (f.existsSync()) {
          f.deleteSync();
          deleted++;
        }
      } catch (_) {}
    }
  } catch (_) {}
  return deleted;
}
