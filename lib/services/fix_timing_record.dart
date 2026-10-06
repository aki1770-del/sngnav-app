/// THE FIX-TIMING RECORD: CODE 13 ONLY (2026-10-06).
///
/// Why this exists. One number nobody has read decides what the driver in
/// unexpected snow hears from the app's next change: how far apart her phone
/// actually delivers GPS fixes while she drives. The 5 s the app designs to is
/// what the location plugin asks for; what the phone delivers on her roads has
/// never been seen. Her installed build records no fix times, and the
/// platform's own dumps describe requests and the receiver chip, not what the
/// app is handed. So this test build writes down, per position event, when it
/// arrived, and nothing more; and only the person driving can send it.
///
/// What it is, stated so no surface can claim more:
/// - One line per position event while 現在地を共有 is on, plus one line when
///   a share's stream starts. Each line: the share's number; milliseconds since
///   that share's stream subscribed; the kind (start, fine fix, coarse fix over
///   150 m, a sample with no measured accuracy, or unavailable); the reported
///   accuracy rounded to 10 m; the speed the phone reported, in tenths of a
///   m/s, TRUNCATED toward zero (see [formatFixTimingLine]); how late the fix
///   arrived after its own timestamp, in ms; and whether the app was in front.
///   The milliseconds are the time the app RECEIVED the event, so two fixes a
///   phone delivers together read the same time, and their lateness differs.
/// - NO coordinates, no place, no wall-clock time. An unavailable event is
///   recorded by its kind ALONE: no exception or error text can enter, because
///   [FixTimingRecord.record] takes none. Every line matches
///   [kFixTimingLinePattern], and nothing else is ever written.
/// - Its own file, never the error log: the error log's promise ("only error
///   records") stays true, and its 200 KB trim never touches these lines.
/// - Its own cap, [kFixTimingRecordMaxBytes]. At the cap it STOPS recording and
///   says so; it never drops a line, so a share is the whole record. The cap
///   sits under the share size [kLogShareMaxChars] the app already holds to,
///   with the header, so a share is never cut either.
/// - It yields to him: one tap stops it (and the stop holds across launches),
///   one tap starts it again, one tap deletes it. It leaves the phone only by
///   his tap on its own share action.
/// - It lives only in code 13, on a branch that is never merged. The next build
///   deletes its file on first launch.
///
/// A record failure must never take the app down: every file operation is
/// wrapped; a broken write is dropped, never thrown.
library;

import 'dart:io' show Directory, File, FileMode, Platform;

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../build_info.dart';
import 'log_share.dart' show kLogShareMaxChars;

/// The record's file name in the app-support directory. The next build deletes
/// this file (and [kFixTimingStoppedFileName]) on first launch.
const String kFixTimingRecordFileName = 'fix_timing_record.txt';

/// Present while he has stopped the record; absent while it records.
const String kFixTimingStoppedFileName = 'fix_timing_record.stopped';

/// The record's own cap, in bytes. About 3 hours of driving at one fix every
/// 5 s. Under [kLogShareMaxChars] with room for the header, so the whole
/// record always goes in one share.
const int kFixTimingRecordMaxBytes = 96 * 1024;

/// Room kept for the share header under [kLogShareMaxChars].
const int kFixTimingHeaderBudget = 512;

/// The longest line [FixTimingRecord.record] can write, in bytes. The cap
/// check keeps one of these in hand, so the file never passes the cap.
const int kFixTimingMaxLineBytes = 96;

/// Every line in the record matches this, and nothing else is written.
final RegExp kFixTimingLinePattern = RegExp(
  r'^s=\d+ t=\d+ k=(start|fine|coarse|noacc|unavail) a=(\d+|-) v=(\d+\.\d|-) '
  r'late=(-?\d+|-) fg=[01]$',
);

/// What kind of position event a line records.
enum FixEventKind {
  /// The share's position stream subscribed: not a fix.
  start('start'),

  /// A fix whose reported accuracy is at most 150 m.
  fine('fine'),

  /// A fix whose reported accuracy is over 150 m (a network-grade fix).
  coarse('coarse'),

  /// A sample with no measured accuracy: an event, not a fix.
  noAccuracy('noacc'),

  /// No position: an unavailability or a stream error. The kind alone.
  unavailable('unavail');

  const FixEventKind(this.token);

  /// The token written in the line.
  final String token;
}

/// The app-support directory's fix-timing record. Size-capped, append-only,
/// never throws.
class FixTimingRecord {
  FixTimingRecord({
    required this.file,
    File? stoppedFile,
    this.maxBytes = kFixTimingRecordMaxBytes,
  }) : stoppedFile = stoppedFile ??
            File('${file.parent.path}/$kFixTimingStoppedFileName');

  /// The record.
  final File file;

  /// Present while he has stopped the record.
  final File stoppedFile;

  /// The record's own cap: [kFixTimingRecordMaxBytes] in the app.
  final int maxBytes;

  /// Whether he has stopped the record. A failure to read routes to stopped:
  /// a record that cannot tell whether it may write does not write.
  bool get stopped {
    try {
      return stoppedFile.existsSync();
    } catch (_) {
      return true;
    }
  }

  /// The record's size in bytes, or 0 when absent or unreadable.
  int get lengthBytes {
    try {
      return file.existsSync() ? file.lengthSync() : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Whether any line is held.
  bool get hasLines => lengthBytes > 0;

  /// Whether the record has reached its cap and so stopped recording.
  bool get full => lengthBytes + kFixTimingMaxLineBytes > maxBytes;

  /// Appends one line, unless he has stopped the record or it is full. Returns
  /// whether a line was written. Takes no free text: an unavailable event is
  /// its kind alone.
  bool record({
    required int share,
    required int msSinceStreamStart,
    required FixEventKind kind,
    double? accuracyMeters,
    double? reportedSpeedMps,
    int? lateMs,
    required bool appInFront,
  }) {
    try {
      if (stopped || full) return false;
      final line = formatFixTimingLine(
        share: share,
        msSinceStreamStart: msSinceStreamStart,
        kind: kind,
        accuracyMeters: accuracyMeters,
        reportedSpeedMps: reportedSpeedMps,
        lateMs: lateMs,
        appInFront: appInFront,
      );
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
      return true;
    } catch (_) {
      return false;
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

  /// Stops recording; the lines held are kept.
  void stop() {
    try {
      stoppedFile.parent.createSync(recursive: true);
      stoppedFile.writeAsStringSync('stopped\n', flush: true);
    } catch (_) {}
  }

  /// Records again.
  void resume() {
    try {
      if (stoppedFile.existsSync()) stoppedFile.deleteSync();
    } catch (_) {}
  }

  /// Deletes every line held. Whether it records afterwards is unchanged.
  void delete() {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}

/// One line of the record. Pure, so its shape is pinned without a file.
///
/// SPEED ROUNDING, stated so the reading's 3 m/s moving line is well defined
/// (decided 2026-10-06, V16): the reported speed is TRUNCATED toward zero to
/// 0.1 m/s, so a recorded value is never more than the phone reported. A
/// recorded 3.0 or more therefore means a reported speed of at least 3.0 m/s,
/// strictly over 2.5. Round-half-up would let a recorded 3 stand for exactly
/// 2.5. Floating point can make the truncation read one tenth LOW, never high:
/// an ambiguity routes toward "not moving", which counts against release.
/// Accuracy is rounded to the nearest 10 m (it only sorts fine from coarse
/// against 150 m, which no rounding moves).
String formatFixTimingLine({
  required int share,
  required int msSinceStreamStart,
  required FixEventKind kind,
  double? accuracyMeters,
  double? reportedSpeedMps,
  int? lateMs,
  required bool appInFront,
}) {
  bool usable(double? v) => v != null && v.isFinite && v >= 0;
  final a = usable(accuracyMeters)
      ? '${(accuracyMeters! / 10).round() * 10}'
      : '-';
  final v = usable(reportedSpeedMps)
      ? ((reportedSpeedMps! * 10).floor() / 10).toStringAsFixed(1)
      : '-';
  final t = msSinceStreamStart < 0 ? 0 : msSinceStreamStart;
  return 's=${share < 0 ? 0 : share} t=$t k=${kind.token} a=$a v=$v '
      'late=${lateMs ?? '-'} fg=${appInFront ? 1 : 0}';
}

/// The record's share payload: an identity header, then every line. Never cut:
/// the record's cap keeps it under [kLogShareMaxChars].
String composeFixTimingSharePayload({
  required String recordText,
  String? operatingSystem,
  DateTime? exportedAt,
}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  final ts = (exportedAt ?? DateTime.now()).toUtc().toIso8601String();
  final buf = StringBuffer()
    ..writeln('sngnav-app $appVersion fix-timing record (test build)')
    ..writeln('os: $os')
    ..writeln('exported: $ts')
    ..writeln('---');
  if (recordText.isEmpty) {
    buf.writeln('測位間隔の記録はありません (no fix-interval lines)');
    return buf.toString();
  }
  buf.write(recordText);
  return buf.toString();
}

/// Opens the record in the app-support directory, or null when it cannot be
/// opened (the card then says so and offers nothing).
Future<FixTimingRecord?> openFixTimingRecord({Directory? directory}) async {
  try {
    final dir = directory ?? await getApplicationSupportDirectory();
    return FixTimingRecord(file: File('${dir.path}/$kFixTimingRecordFileName'));
  } catch (_) {
    return null;
  }
}

/// Injectable exit door for the record's payload.
typedef FixTimingShareSink = Future<void> Function(String payload);

/// Production [FixTimingShareSink]: the platform share sheet, as plain text.
Future<void> shareFixTimingViaShareSheet(String payload) async {
  await SharePlus.instance.share(
    ShareParams(
      text: payload,
      subject: 'sngnav-app $appVersion — fix-timing record',
    ),
  );
}
