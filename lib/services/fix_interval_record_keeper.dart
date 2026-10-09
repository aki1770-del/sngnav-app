/// THE KEEPER: code 15's fix-interval record outlives every build of main
/// until HE deletes it (2026-10-09).
///
/// Why. Code 13 took one reading of how far apart his phone delivers GPS
/// fixes, and the reading was lost: code 14 deleted the record at its first
/// launch, and keeping it rested on him remembering to tap 記録を共有 before the
/// update. That is the operator as the last line of defence (Sakichi Vision 9).
/// Code 15 takes the reading again. Its record must survive every later build
/// WITHOUT anyone remembering anything, so main must know its file names
/// before code 15 exists, and must never delete them.
///
/// What this file holds, and the rule it keeps:
/// - Code 15's file names, [kCode15RecordFileNames]. They are NOT code 13's
///   ([kCode13RecordFileNames]): main deletes those on every launch.
///   test/services/fix_interval_record_keeper_test.dart pins the two lists as
///   disjoint.
/// - NO LAUNCH PATH DELETES THEM. The only deletion of these names anywhere in
///   lib/ is [LeftBehindFixIntervalRecord.deleteOnHisTap], and its only caller
///   is the 記録を消す button on the left-behind card.
///   test/architectural/code15_record_is_kept_test.dart holds that by census.
/// - The left-behind card: on a build that does not record (main), while the
///   record file exists, his page shows a card that says so, with 記録を共有 and
///   記録を消す (the 2026-10-09 dignity read, WDA W3). A build must not remove
///   that card while a file may exist: he would be left with data he cannot
///   see or delete short of clearing all the app's data, his diary included
///   (Vision 24, the machine yields to the person).
/// - Out of Google's backup and device transfer, per file
///   (android/app/src/main/res/xml/backup_rules.xml for Android 11 and lower,
///   data_extraction_rules.xml for 12 and later). A phone maker's own backup
///   has not been checked, and the card's words say so.
///
/// What it does NOT do: record anything. Code 15's recording (its line kinds
/// and its own card) is built on code 15's branch, cut from main after this
/// keeper. A build that writes these files must replace the left-behind card,
/// whose words say "this version does not record"; the census test above
/// fails on any writer in lib/ so that no one can add one without seeing it.
///
/// A failure here must never take the app down: every file operation is
/// wrapped, and nothing throws.
library;

import 'dart:io' show Directory, File, Platform;

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../build_info.dart';
import 'code13_record_cleanup.dart';

/// Code 15's record, in the app-support directory.
const String kCode15RecordFileName = 'fix_interval_record_15.txt';

/// Code 15's "recording stopped" marker, beside the record.
const String kCode15StoppedFileName = 'fix_interval_record_15.stopped';

/// Every file code 15 writes. No build deletes these by name; only his tap.
const List<String> kCode15RecordFileNames = [
  kCode15RecordFileName,
  kCode15StoppedFileName,
];

/// A fix-interval record left on this phone by an earlier test build (code 15),
/// seen from a build that does not record. Reads, shares and deletes ONLY on
/// his tap; never writes.
class LeftBehindFixIntervalRecord {
  LeftBehindFixIntervalRecord({required this.directory});

  /// The app-support directory the record lives in.
  final Directory directory;

  /// The record.
  File get file => File('${directory.path}/$kCode15RecordFileName');

  /// Code 15's stopped marker.
  File get stoppedFile => File('${directory.path}/$kCode15StoppedFileName');

  /// Whether the record file is on this phone. A failure to look routes to
  /// PRESENT: a card shown in error costs him a glance, a card hidden in error
  /// leaves his data where he cannot see or delete it (Vision 24).
  bool get present {
    try {
      return file.existsSync();
    } catch (_) {
      return true;
    }
  }

  /// The whole record, or '' when absent or unreadable.
  String readAll() {
    try {
      return file.existsSync() ? file.readAsStringSync() : '';
    } catch (_) {
      return '';
    }
  }

  /// HIS TAP on 記録を消す, and nothing else, calls this: the only deletion of
  /// code 15's names in lib/. Deletes the record and its stopped marker.
  /// Returns whether the record is gone afterwards.
  bool deleteOnHisTap() {
    for (final f in [file, stoppedFile]) {
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    return !present;
  }
}

/// Opens the left-behind record view on the app-support directory, or null
/// when the directory cannot be resolved. Never throws, never writes.
Future<LeftBehindFixIntervalRecord?> openLeftBehindFixIntervalRecord({
  Directory? directory,
}) async {
  try {
    final dir = directory ?? await getApplicationSupportDirectory();
    return LeftBehindFixIntervalRecord(directory: dir);
  } catch (_) {
    return null;
  }
}

/// What a launch did to the test builds' records, for the app to show.
class LaunchRecordsState {
  const LaunchRecordsState({required this.code13, required this.leftBehind});

  /// Code 13's deletion this launch (its promise kept), and whether to tell.
  final Code13RecordDeletion code13;

  /// Code 15's record, kept.
  final LeftBehindFixIntervalRecord? leftBehind;
}

/// THE LAUNCH PATH for the test builds' records: everything main() does to
/// them before runApp, in one place, so a test can run exactly this on a
/// directory holding both builds' files. It deletes code 13's files (their
/// promise) and opens code 15's view. It deletes nothing of code 15's.
Future<LaunchRecordsState> launchRecordHousekeeping({
  Directory? directory,
}) async {
  final code13 = await deleteCode13FixTimingRecord(directory: directory);
  final leftBehind = await openLeftBehindFixIntervalRecord(
    directory: directory,
  );
  return LaunchRecordsState(code13: code13, leftBehind: leftBehind);
}

/// The left-behind record's share payload: an identity header in code 13's
/// shape (header lines, then `---`), then every line as written. When the
/// record holds no fix line, it says so before any markers it does hold.
String composeLeftBehindRecordSharePayload({
  required String recordText,
  String? operatingSystem,
  DateTime? exportedAt,
}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  final ts = (exportedAt ?? DateTime.now()).toUtc().toIso8601String();
  final buf = StringBuffer()
    ..writeln(
      'sngnav-app $appVersion fix-interval record left by an earlier '
      'test build (this build does not record)',
    )
    ..writeln('os: $os')
    ..writeln('exported: $ts')
    ..writeln('---');
  if (!RegExp(r'(^|\n)s=\d+ t=\d+ k=(fine|coarse) ').hasMatch(recordText)) {
    buf.writeln('測位間隔の記録はありません (no fix-interval lines)');
  }
  buf.write(recordText);
  return buf.toString();
}

/// Injectable exit door for the left-behind record's payload.
typedef LeftBehindRecordShareSink = Future<void> Function(String payload);

/// Production [LeftBehindRecordShareSink]: the platform share sheet, as plain
/// text. The share sheet reports at most the chosen target, never that the
/// text arrived, so nothing is deleted on its result.
Future<void> shareLeftBehindRecordViaShareSheet(String payload) async {
  await SharePlus.instance.share(
    ShareParams(
      text: payload,
      subject: 'sngnav-app $appVersion — fix-interval record',
    ),
  );
}
