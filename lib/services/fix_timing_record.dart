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
///   a share's stream starts, one when he ends the share (停止 or 閉じる:
///   `k=end`), and one when the app's process starts (`k=launch`). A share
///   with no `end` line followed by a `launch` line ended because the process
///   died (killed, crashed or swiped away), not by his tap: the record says so
///   itself, rather than leaving it to be inferred from share numbers. Each line: the share's number; milliseconds since
///   that share's stream subscribed; the kind (start, fine fix, coarse fix over
///   150 m, a sample with no measured accuracy, or unavailable); the reported
///   accuracy in tenths of a metre and the speed the phone reported in tenths
///   of a m/s, both TRUNCATED toward zero, with an exact zero speed written
///   apart (see [formatFixTimingLine]); how late the fix arrived after its own
///   timestamp, in ms; and whether the app was in front.
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

/// Every line in the record matches this, and nothing else is written: a
/// position-event line, an `end` line, or the one `launch` shape.
final RegExp kFixTimingLinePattern = RegExp(
  r'^(s=\d+ t=\d+ k=(start|fine|coarse|noacc|unavail) a=(\d+\.\d|-) '
  r'v=(0|\d+\.\d|-) late=(-?\d+|-) fg=[01]'
  r'|s=\d+ t=\d+ k=end'
  r'|s=0 t=0 k=launch)$',
);

/// The `launch` line: written once per process start, when the record opens.
const String kFixTimingLaunchLine = 's=0 t=0 k=launch';

/// The `end` line for [share], [msSinceStreamStart] after its stream started.
String formatFixTimingEnd({required int share, required int msSinceStreamStart}) =>
    's=${share < 0 ? 0 : share} '
    't=${msSinceStreamStart < 0 ? 0 : msSinceStreamStart} k=end';

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

  /// Appends [line] and flushes it, unless he has stopped the record or it is
  /// full. Returns whether it was written.
  bool _append(String line) {
    try {
      if (stopped || full) return false;
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// His ending of [share] (停止 or 閉じる), flushed before anything else of
  /// the share moves. Returns whether it was written.
  bool recordEnd({required int share, required int msSinceStreamStart}) =>
      _append(formatFixTimingEnd(
          share: share, msSinceStreamStart: msSinceStreamStart));

  /// The process started. Written by [openFixTimingRecord], the only way the
  /// app opens the record, so no launch can open it without one.
  bool recordLaunch() => _append(kFixTimingLaunchLine);

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
    return _append(formatFixTimingLine(
      share: share,
      msSinceStreamStart: msSinceStreamStart,
      kind: kind,
      accuracyMeters: accuracyMeters,
      reportedSpeedMps: reportedSpeedMps,
      lateMs: lateMs,
      appInFront: appInFront,
    ));
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
/// WHAT EACH NUMBER MEANS, stated so the reading's bars are exact (decided
/// 2026-10-06 against the binding bars, V16 and V99):
/// - SPEED (`v`): the reported speed TRUNCATED toward zero to 0.1 m/s, so a
///   recorded value is never more than the phone reported; a recorded 3.0 or
///   more means a reported speed of at least 3.0 m/s (MOVING is exact, and
///   never stands for 2.5). An EXACT reported zero is written `v=0`; any speed
///   above zero keeps its decimal, so a reported 0.03 is `v=0.0`, never `0`
///   (STOPPED, "reports 0", is exact too, and a creep is never read as a stop).
/// - ACCURACY (`a`): the reported accuracy TRUNCATED toward zero to 0.1 m. The
///   true value lies in [recorded, recorded + 0.1). The exit-accuracy criterion
///   ("at least twice the median of the 10 fixes before, and at least 15 m
///   worse") is read fail-closed: the fix after the gap at its recorded value,
///   each fix before it at its recorded value + 0.1. (Fine against coarse, over
///   150 m, is decided in the app from the exact value, never from `a`.)
/// - TIME (`t`): when the app RECEIVED the event, in ms since the share's
///   stream started, by the phone's own clock.
/// - LATENESS (`late`): receipt minus the fix's own timestamp, in ms. It
///   includes any offset between the phone's clock and the platform's fix
///   clock, so a constant offset over 2 s makes the no-batching criterion fail
///   for every gap: the fail-closed side.
/// Floating point can make a truncation read one tenth LOW, never high.
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
  String tenths(double x) => ((x * 10).floor() / 10).toStringAsFixed(1);
  final a = usable(accuracyMeters) ? tenths(accuracyMeters!) : '-';
  final v = !usable(reportedSpeedMps)
      ? '-'
      : reportedSpeedMps == 0
          ? '0'
          : tenths(reportedSpeedMps!);
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

/// Opens the record in the app-support directory at process start, and writes
/// its `launch` line; or null when it cannot be opened (the card then says so
/// and offers nothing). The app opens the record only here, once per process.
Future<FixTimingRecord?> openFixTimingRecord({Directory? directory}) async {
  try {
    final dir = directory ?? await getApplicationSupportDirectory();
    final record =
        FixTimingRecord(file: File('${dir.path}/$kFixTimingRecordFileName'));
    record.recordLaunch();
    return record;
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
