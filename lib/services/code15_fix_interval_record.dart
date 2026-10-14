/// THE FIX-INTERVAL RECORD: CODE 15's LINE (2026-10-10; code 16, 2026-10-14).
///
/// Code 16 writes into the same file, under the same name, which is a key and
/// not a claim about who wrote its lines: each build that writes puts its own
/// `k=build` line first ([RecordWriter], [kRecordBuildLinePattern]), and the
/// lines before the first such line are code 15's.
///
/// Why this exists. The tunnel-exit and weak-GPS fix (C-110 + TC-8) is held
/// until one reading of how far apart his phone delivers GPS fixes is taken.
/// Code 13 took it, and code 14 deleted it at launch, so the reading is taken
/// again. Main now keeps code 15's file names
/// (services/fix_interval_record_keeper.dart, `87199c9`): no later build
/// deletes them; only his tap does. This file is the hand that writes them.
///
/// What it is, stated so no surface can claim more:
/// - CODE 13's RECORD, every old line kind in its EXACT format (89ed430
///   lib/services/fix_timing_record.dart): one line per position event while
///   現在地を共有 is on, a `start` line when a share's stream subscribes, an
///   `end` line at his own ending of the share, a `launch` line at each process
///   start, and `pause`/`resume` at his stop and restart of the record. The
///   format functions below are ported from that file with no changed
///   character in their bodies; test/services/code15_fix_interval_record_test
///   .dart pins every shape code 13's own tests pinned.
/// - FOUR NEW KINDS, and no others (the 2026-10-09 and 2026-10-10 rulings on
///   this reading, and sections 16 and 17 of the binding decision bars for it):
///   - `s=N t=N k=alive`: written by a timer every [kCode15AliveTimerPeriod]
///     only when the share has written no line for [kCode15AliveThreshold] or
///     more. While fixes arrive every 5 s nothing is added. In a gap, it shows
///     the app was alive with no fix; its absence before a `launch` bounds a
///     death.
///   - `s=N t=N k=leave` / `s=N t=N k=back`: when the app stops being visible
///     and when it is visible again, while a share runs.
///   - `s=N t=N k=appstop`: the APP ended the share itself (a share without its
///     foreground service, when the app left the screen; main b970dec), written
///     before anything of the share moves. Never `end`, which is his tap.
///   The marks are read only for how the app and the phone behaved: the
///   ending class, the clock checks, and whether the app was in front or
///   behind. Never as what he did (the 2026-10-10 dignity read, which widened
///   the 2026-10-09 one).
/// - ONE CLOCK FOR EVERY KIND (the bars, section 16 item 3): every line that
///   carries a share's `t` takes it as code 13's fix lines do, the page's
///   `_now()` minus the share's stream-subscription time, in ms. No monotonic
///   stopwatch is used for any kind.
/// - NO coordinates, no place, no clock time of day. A line takes no free text.
/// - Its OWN files, [kCode15RecordFileNames], imported from the keeper and
///   never retyped, in the app-support directory (Android's getFilesDir()).
///   They are not code 13's names, which main deletes on every launch.
/// - On by default. The stopped marker means what code 13's meant: present
///   while he has stopped the record, and the stop holds across launches.
///   Deleting the record keeps whether it records (code 13's rule).
/// - Its own cap, [kCode15RecordMaxBytes], sized against his measured day.
///   At the cap it STOPS and says so on its card; it never drops a line.
///
/// A record failure must never take the app down: every file operation is
/// wrapped; a broken write is dropped, never thrown.
///
/// Scope on this branch, named: main's keeper says its deleteOnHisTap is the
/// only deletion of these names in lib/. On code 15 that card is not shown
/// and its deleteOnHisTap has no caller; the one deletion his tap reaches is
/// [Code15FixIntervalRecord.deleteRecordOnHisTap], which deletes the record
/// and keeps the stopped marker. test/architectural/
/// code15_record_is_kept_test.dart holds the census for this branch.
library;

import 'dart:async' show Completer, unawaited;
import 'dart:convert' show utf8;
import 'dart:io' show Directory, File, FileMode, Platform;

import 'package:flutter/foundation.dart'
    show Listenable, ValueNotifier, immutable;
import 'package:path_provider/path_provider.dart';

import '../build_info.dart';
import 'build_identity.dart' show BuildIdentity;
import 'record_share_file.dart' show RecordFileShareSink, shareRecordFileViaShareSheet;
import 'fix_interval_record_keeper.dart'
    show kCode15RecordFileName, kCode15StoppedFileName, kCode15RecordFileNames;

export 'fix_interval_record_keeper.dart' show kCode15RecordFileNames;

// ---------------------------------------------------------------------------
// The alive timer. The reading's bound B = threshold + period + j (the bars,
// section 16 item 4) is READ from these two constants; j is written in the
// bars from an emulator measurement (1.0 s, so B = 10.0 s: IDV c62d5113, the
// bars at 24f8a83a). With a 6 s threshold checked on a 3 s tick, an `alive`
// line comes about 9 s at most after the line before it: nominally the first
// tick at least 6 s after that line, in [6, 9) s. Measured on the emulator up
// to 9,009 ms, because a tick that reads 5,999 ms or less skips to the next
// one, so about-9 s steps fall between two `alive` lines too; j absorbs it.
// [Until 2026-10-10 this said "just under 9 s": wrong as written.]
// ---------------------------------------------------------------------------

/// No line from the share for this long, and the next tick writes `alive`.
const Duration kCode15AliveThreshold = Duration(seconds: 6);

/// How often the alive timer checks.
const Duration kCode15AliveTimerPeriod = Duration(seconds: 3);

// ---------------------------------------------------------------------------
// The cap, sized against his measured day.
// ---------------------------------------------------------------------------

/// The fix period the app is delivered at when it sets none: geolocator_android
/// 4.6.2 (the locked version) uses 5000 ms when no interval is passed
/// (android/src/main/java/com/baseflow/geolocator/location/LocationOptions.java
/// :59), and her_position.dart's driveLocationSettings passes none. The
/// "5 s" in the card's cap sentence is this constant.
const Duration kCode15DesignFixPeriod = Duration(seconds: 5);

/// His measured day: about 4 h 50 min of share time on 2026-10-08 (JST), as
/// read from his phone's usage statistics on 2026-10-09. The cap must hold at
/// least this much sharing at [kCode15DesignFixPeriod].
const Duration kCode15HisMeasuredShareDay = Duration(hours: 4, minutes: 50);

/// The record's own cap, in bytes: twice code 13's 96 KB. Holds his measured
/// day at the conservative line size [kCode15NominalLineBytes]; see
/// test/services/code15_fix_interval_record_test.dart. The share text is the
/// whole record under a header, so it is about this size. Code 13 kept its cap
/// under the 100 KB the error log's share holds to; this one is over it, and
/// whether every share target takes a text this long is UNVERIFIED until it is
/// shown on an emulator.
const int kCode15RecordMaxBytes = 192 * 1024;

/// The longest line a write can add, in bytes (code 13's kFixTimingMaxLineBytes).
/// The cap check keeps one of these in hand, so the file never passes the cap.
const int kCode15MaxLineBytes = 96;

/// Room kept for the share header over the cap.
const int kCode15HeaderBudget = 512;

/// The line the hours in the card's cap sentence are computed with: a fine fix
/// late in a share of his measured day's length, with a two-digit accuracy and
/// speed and a four-digit lateness. Longer than most lines a share writes
/// (a short share has a shorter `t`), so the hours are on the low side.
String get kCode15NominalLine => formatFixTimingLine(
      share: 9,
      msSinceStreamStart: kCode15HisMeasuredShareDay.inMilliseconds,
      kind: FixEventKind.fine,
      accuracyMeters: 12.3,
      reportedSpeedMps: 13.4,
      lateMs: 1234,
      appInFront: false,
    );

/// Bytes per line used for the hours: [kCode15NominalLine] plus its newline.
int get kCode15NominalLineBytes => utf8.encode(kCode15NominalLine).length + 1;

/// Hours of sharing the cap holds at [kCode15DesignFixPeriod], rounded DOWN to
/// the half hour. This is the hours figure in the words: read from here, never
/// retyped.
double get kCode15RecordHours {
  final linesPerHour = 3600 / kCode15DesignFixPeriod.inSeconds;
  final hours = kCode15RecordMaxBytes / (kCode15NominalLineBytes * linesPerHour);
  return (hours * 2).floorToDouble() / 2;
}

/// The hours as the words show them: "5" or "5.5".
String get kCode15RecordHoursText {
  final h = kCode15RecordHours;
  return h == h.truncateToDouble() ? h.toInt().toString() : h.toString();
}

/// The cap as the words show it, in KB: "192".
String get kCode15RecordCapKbText => (kCode15RecordMaxBytes ~/ 1024).toString();

// ---------------------------------------------------------------------------
// LINE SHAPES. Everything from here to [kCode15LinePattern] is code 13's,
// ported from 89ed430 lib/services/fix_timing_record.dart (:79-123 and
// :269-316) with no changed character in a body, so the binding bars read
// every old line as before.
// ---------------------------------------------------------------------------

/// Code 13's whitelist, verbatim (89ed430 :81-86): a position-event line, an
/// `end` line, or the one `launch`/`pause`/`resume` shape.
final RegExp kFixTimingLinePattern = RegExp(
  r'^(s=\d+ t=\d+ k=(start|fine|coarse|noacc|unavail) a=(\d+\.\d|-) '
  r'v=(0|\d+\.\d|-) late=(-?\d+|-) fg=[01]'
  r'|s=\d+ t=\d+ k=end'
  r'|s=0 t=0 k=(launch|pause|resume))$',
);

/// The `pause` line: written at his 記録を止める, before the stop takes effect.
const String kFixTimingPauseLine = 's=0 t=0 k=pause';

/// The `resume` line: written at his 記録を再開, after recording resumes.
const String kFixTimingResumeLine = 's=0 t=0 k=resume';

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

/// One line of the record. Pure, so its shape is pinned without a file.
///
/// WHAT EACH NUMBER MEANS, stated so the reading's bars are exact (decided
/// 2026-10-06 against the binding bars):
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

/// Whether [text] holds a fix line (`k=fine` or `k=coarse`).
bool fixTimingTextHasFixLines(String text) =>
    RegExp(r'(^|\n)s=\d+ t=\d+ k=(fine|coarse) ').hasMatch(text);

// ---------------------------------------------------------------------------
// Code 15's four new kinds. Same shape as `end`: the share and its t, nothing
// else (the reading's ending classifier parses exactly this shape).
// ---------------------------------------------------------------------------

/// The four kinds code 15 adds, and no others.
enum Code15MarkKind {
  /// The app was alive while the share had written nothing for the threshold.
  alive('alive'),

  /// The app stopped being visible while a share ran.
  leave('leave'),

  /// The app was visible again while a share ran.
  back('back'),

  /// The app ended the share itself: a share without its foreground service,
  /// when the app left the screen (main b970dec). Never his tap.
  appstop('appstop');

  const Code15MarkKind(this.token);

  /// The token written in the line.
  final String token;
}

/// One `alive`, `leave`, `back` or `appstop` line.
String formatCode15Mark({
  required int share,
  required int msSinceStreamStart,
  required Code15MarkKind kind,
}) =>
    's=${share < 0 ? 0 : share} '
    't=${msSinceStreamStart < 0 ? 0 : msSinceStreamStart} k=${kind.token}';

/// Code 15's whitelist: code 13's, plus exactly one alternative for the four
/// new kinds, plus (code 16) exactly one for the boundary line
/// [kRecordBuildLinePattern]. Every line written matches it, and nothing else
/// is written.
final RegExp kCode15LinePattern = RegExp(
  '${kFixTimingLinePattern.pattern.substring(0, kFixTimingLinePattern.pattern.length - 2)}'
  r'|s=\d+ t=\d+ k=(alive|leave|back|appstop)'
  r'|s=0 t=0 k=build vc=[1-9][0-9]* sha=([0-9a-f]{7}|-) apk=([0-9a-f]{12}|-) launch=engine)$',
);

// ---------------------------------------------------------------------------
// CODE 16: THE BOUNDARY LINE (2026-10-14). The file keeps code 15's name, as a
// key; which build wrote which lines is carried in the bytes.
// ---------------------------------------------------------------------------

/// What a `launch` line means in every line after this build's boundary: an
/// ENGINE start. Code 16 carries no process gate, so a launch is written at
/// each opening of the record, which is each start of the app's engine. A
/// constant, never inferred from a version.
const String kRecordLaunchMeaning = 'engine';

/// The boundary line, exactly, single spaces, in this order, lowercase hex:
/// `s=0 t=0 k=build vc=V sha=S apk=A launch=engine`, where V is the
/// versionCode, S the first 7 hex of the commit or `-`, and A the first 12 hex
/// of the installed APK's hash or `-`. The groups are vc, sha, apk.
final RegExp kRecordBuildLinePattern = RegExp(
  r'^s=0 t=0 k=build vc=([1-9][0-9]*) sha=([0-9a-f]{7}|-) apk=([0-9a-f]{12}|-) launch=engine$',
);

/// Who writes into the record: the running build, as it reads itself from
/// the installed package. Never from a version literal or [appVersion].
@immutable
class RecordWriter {
  const RecordWriter._(this.versionCode, this.sha, this.apk);

  /// From what the platform answered. [versionCode] null or not positive: the
  /// build cannot name itself and writes no line of any kind ([canWrite]).
  /// [gitSha]: the first 7 lowercase hex, or `-` when null, `UNKNOWN`,
  /// `UNREADABLE`, carrying `-dirty`, or not beginning with 7 hex: a declared
  /// gap, never a match. [selfSha256]: the first 12 lowercase hex of the
  /// installed APK's hash, or `-`.
  factory RecordWriter({int? versionCode, String? gitSha, String? selfSha256}) =>
      RecordWriter._(
        versionCode != null && versionCode > 0 ? versionCode : null,
        _token(gitSha, 7, gapIfDirty: true),
        _token(selfSha256, 12),
      );

  /// The running build's identity, as [BuildIdentity] read it.
  factory RecordWriter.fromIdentity(BuildIdentity id) => RecordWriter(
      versionCode: id.versionCode, gitSha: id.gitSha, selfSha256: id.selfSha256);

  /// A build that could not read its own versionCode.
  static final RecordWriter unreadable = RecordWriter();

  final int? versionCode;
  final String sha;
  final String apk;

  /// Only a build that knows its versionCode writes: a line it wrote without
  /// naming itself would be read as the previous writer's (Sakichi Vision 14).
  bool get canWrite => versionCode != null;

  /// This build's boundary line.
  String get boundaryLine =>
      's=0 t=0 k=build vc=$versionCode sha=$sha apk=$apk launch=$kRecordLaunchMeaning';

  /// This build's share-header line: the same tokens, and `-` for a versionCode
  /// it could not read.
  String get headerLine => 'build: ${versionCode ?? '-'} $sha $apk';

  /// Whether the boundary [line] names this writer: the same versionCode and
  /// the same APK, falling back to the versionCode alone when either APK is
  /// `-`. A same-code build with other bytes is a new writer.
  bool isNamedBy(RegExpMatch line) {
    final vc = int.parse(line.group(1)!);
    final apk = line.group(3)!;
    return vc == versionCode && (apk == '-' || this.apk == '-' || apk == this.apk);
  }

  static String _token(String? v, int n, {bool gapIfDirty = false}) {
    if (v == null) return '-';
    final t = v.trim();
    if (gapIfDirty && t.contains('-dirty')) return '-';
    final m = RegExp('^[0-9a-fA-F]{$n}').matchAsPrefix(t);
    return m == null ? '-' : m.group(0)!.toLowerCase();
  }
}

/// How many lines may wait for the writer to be named. The platform answers
/// in about a second; past this, nothing is kept and nothing is written.
const int kRecordMaxHeldLines = 512;

class _Held {
  const _Held(this.line, this.evenIfStopped, this.share, this.t);
  final String line;
  final bool evenIfStopped;
  final int? share;
  final int? t;
}

// ---------------------------------------------------------------------------
// The record.
// ---------------------------------------------------------------------------

/// The app-support directory's code 15 record. Size-capped, append-only, on by
/// default, never throws.
class Code15FixIntervalRecord {
  /// [writer] is the build that writes, or null until the platform has named
  /// it ([nameWriter]); until then every line waits, in order, and nothing is
  /// written.
  Code15FixIntervalRecord({
    required Directory directory,
    required RecordWriter? writer,
    this.maxBytes = kCode15RecordMaxBytes,
  })  : file = File('${directory.path}/$kCode15RecordFileName'),
        stoppedFile = File('${directory.path}/$kCode15StoppedFileName') {
    if (writer != null) nameWriter(writer);
  }

  RecordWriter? _writer;
  final List<_Held> _held = [];
  bool _heldOverflow = false;
  final Completer<void> _named = Completer<void>();
  final ValueNotifier<int> _changes = ValueNotifier<int>(0);

  /// The build that writes, once named.
  RecordWriter? get writer => _writer;

  /// Completes once the writer is named.
  Future<void> get named => _named.future;

  /// Fires when the writer is named and its waiting lines are written: what
  /// the card says may have changed without a tap.
  Listenable get changes => _changes;

  /// Named, and it cannot name itself: it writes no line of any kind, and its
  /// card says it is not recording.
  bool get cannotNameItself =>
      _heldOverflow || (_writer != null && !_writer!.canWrite);

  /// Whether this build's boundary line is still owed: decided from the
  /// file's bytes when the writer is named, after his delete, and AT THE
  /// WRITE whenever it may have changed (see [_append]). True until the
  /// writer is named (the stricter side for [full]).
  bool _boundaryOwed = true;

  /// The file's length after this object's last write. A shorter file means
  /// another writer of this build (a second page's engine) deleted it.
  int _lengthAtLastWrite = 0;

  /// The boundary is owed when the file holds no `k=build` line, at any
  /// versionCode, 15 included (a file without one was written only by builds
  /// that write none), or when its last one names another writer.
  bool _owedFromFile() {
    final w = _writer;
    if (w == null || !w.canWrite) return false;
    RegExpMatch? last;
    for (final line in readAll().split('\n')) {
      final m = kRecordBuildLinePattern.firstMatch(line);
      if (m != null) last = m;
    }
    return last == null || !w.isNamedBy(last);
  }

  /// Names the build that writes, once: decides whether its boundary is owed
  /// from the file's bytes, then writes the lines that waited, in order,
  /// through the same guards as any line. A build that cannot read its
  /// versionCode drops them all: no line of any kind.
  void nameWriter(RecordWriter writer) {
    if (_writer != null) return;
    _writer = writer;
    _boundaryOwed = _owedFromFile();
    final held = List<_Held>.of(_held);
    _held.clear();
    if (writer.canWrite && !_heldOverflow) {
      for (final h in held) {
        _append(h.line, evenIfStopped: h.evenIfStopped, share: h.share, t: h.t);
      }
    }
    if (!_named.isCompleted) _named.complete();
    _changes.value++;
  }

  /// The record ([kCode15RecordFileName]).
  final File file;

  /// Present while he has stopped the record ([kCode15StoppedFileName]).
  final File stoppedFile;

  /// The record's own cap: [kCode15RecordMaxBytes] in the app.
  final int maxBytes;

  /// The names this record can create, from the keeper.
  static const List<String> fileNames = kCode15RecordFileNames;

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

  /// Whether any line is held, a marker included. Never the card's status.
  bool get hasLines => lengthBytes > 0;

  /// Whether any FIX line (`k=fine` or `k=coarse`) is held: what the card and
  /// the share text call a fix-interval record. One scan at open, then kept
  /// by the writes and the delete this object makes.
  bool get hasFixLines => _hasFixLines;
  static final RegExp _fixKind = RegExp(r'^s=\d+ t=\d+ k=(fine|coarse) ');
  late bool _hasFixLines = fixTimingTextHasFixLines(readAll());

  /// The bars' data minimum, counted from the lines on disk: one scan at open,
  /// then fed every line this object writes.
  Code15MinimumCount get count => _count;
  late Code15MinimumCount _count = Code15MinimumCount.ofText(readAll());

  /// Whether the record has reached its cap and so stopped recording. While
  /// this build's boundary is owed, the boundary and one more line must fit,
  /// or no line of any kind is written.
  bool get full =>
      lengthBytes + (_boundaryOwed ? 2 : 1) * kCode15MaxLineBytes > maxBytes;

  /// The share the last t-carrying line was written for, and its t: what the
  /// alive timer measures the quiet against.
  int? _lastShare;
  int _lastShareT = 0;

  /// Appends [line] and flushes it, unless he has stopped the record or it is
  /// full. When the line carries a share's t, it is remembered for the alive
  /// timer. Returns whether it was written.
  bool _append(String line, {bool evenIfStopped = false, int? share, int? t}) {
    final w = _writer;
    // Not yet named: the line waits, in order. Nothing is written until the
    // build that writes it is known. His stop is read NOW, when the line is
    // made, as it always was: a line his stop refuses is not kept, and a line
    // made while he was recording is written even if he stops before the
    // build is named.
    if (w == null) {
      if (!evenIfStopped && stopped) return false;
      if (_held.length < kRecordMaxHeldLines) {
        _held.add(_Held(line, true, share, t));
      } else {
        _held.clear();
        _heldOverflow = true;
      }
      return false;
    }
    // A build that cannot name itself writes no line of any kind.
    if (!w.canWrite || _heldOverflow) return false;
    // The count starts from the file BEFORE the first write, so the line about
    // to be written is counted once, never twice (the 2026-10-10 boundary
    // ruling, section 1.2: a lazy start after the write read it, then added it).
    final count = _count;
    try {
      // His stop holds for every line, the boundary included.
      if (!evenIfStopped && stopped) return false;
      // DECIDED FROM THE FILE'S BYTES AT THE WRITE (2026-10-14, the safety
      // reader's W-2 as amended). One process can hold two writers of this
      // build (a second page's engine), each with its own object. While a
      // boundary is owed, another may have written it since; and a file
      // shorter than at this object's last write was deleted by another, so
      // a boundary is owed again. In neither case is the decision kept from
      // the naming: it is read again from the file. A full read happens only
      // then: while owed, once; after another writer's delete, once.
      if (_boundaryOwed || lengthBytes < _lengthAtLastWrite) {
        _boundaryOwed = _owedFromFile();
      }
      if (full) return false;
      file.parent.createSync(recursive: true);
      if (_boundaryOwed) {
        // Immediately before this build's first line. [full] above has
        // already made sure the boundary and this line both fit. It carries
        // no share and no t: the alive timer's state does not move.
        file.writeAsStringSync('${w.boundaryLine}\n',
            mode: FileMode.append, flush: true);
        _boundaryOwed = false;
        count.add(w.boundaryLine);
      }
      file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
      _lengthAtLastWrite = lengthBytes;
    } catch (_) {
      return false;
    }
    if (share != null && t != null) {
      _lastShare = share;
      _lastShareT = t;
    }
    if (_fixKind.hasMatch(line)) _hasFixLines = true;
    count.add(line);
    return true;
  }

  /// His ending of [share] (停止, 閉じる, or the clear action), flushed before
  /// anything else of the share moves. Returns whether it was written.
  bool recordEnd({required int share, required int msSinceStreamStart}) =>
      _append(
        formatFixTimingEnd(share: share, msSinceStreamStart: msSinceStreamStart),
        share: share,
        t: msSinceStreamStart,
      );

  /// The process started. Written by [openCode15FixIntervalRecord], the only
  /// way the app opens the record, so no launch can open it without one.
  bool recordLaunch() {
    _lastShare = null;
    return _append(kFixTimingLaunchLine);
  }

  /// Appends one position-event line (code 13's format), unless he has stopped
  /// the record or it is full. Takes no free text.
  bool record({
    required int share,
    required int msSinceStreamStart,
    required FixEventKind kind,
    double? accuracyMeters,
    double? reportedSpeedMps,
    int? lateMs,
    required bool appInFront,
  }) {
    final wrote = _append(
      formatFixTimingLine(
        share: share,
        msSinceStreamStart: msSinceStreamStart,
        kind: kind,
        accuracyMeters: accuracyMeters,
        reportedSpeedMps: reportedSpeedMps,
        lateMs: lateMs,
        appInFront: appInFront,
      ),
      share: share,
      t: msSinceStreamStart,
    );
    if (wrote && (kind == FixEventKind.fine || kind == FixEventKind.coarse)) {
      _hasFixLines = true;
    }
    return wrote;
  }

  /// The app stopped being visible ([Code15MarkKind.leave]) or is visible again
  /// ([Code15MarkKind.back]) while [share] runs. Returns whether it was written.
  bool recordLifecycle({
    required int share,
    required int msSinceStreamStart,
    required Code15MarkKind kind,
  }) {
    // alive is the timer's alone, and appstop is [recordAppStop]'s alone.
    if (kind == Code15MarkKind.alive || kind == Code15MarkKind.appstop) {
      return false;
    }
    return _append(
      formatCode15Mark(
          share: share, msSinceStreamStart: msSinceStreamStart, kind: kind),
      share: share,
      t: msSinceStreamStart,
    );
  }

  /// The app's own ending of [share] (a share without its foreground service,
  /// the app off the screen). Written before the share's stream or number
  /// moves. Never `end`, which is his tap. Returns whether it was written.
  bool recordAppStop({required int share, required int msSinceStreamStart}) =>
      _append(
        formatCode15Mark(
          share: share,
          msSinceStreamStart: msSinceStreamStart,
          kind: Code15MarkKind.appstop,
        ),
        share: share,
        t: msSinceStreamStart,
      );

  /// The alive timer's tick: writes `alive` when [share] has written no line
  /// for [kCode15AliveThreshold] or more by [msSinceStreamStart]. A share with
  /// no line yet in this process is measured from its stream's start (t = 0).
  /// Returns whether a line was written.
  bool recordAliveIfQuiet({
    required int share,
    required int msSinceStreamStart,
  }) {
    final since = _lastShare == share ? _lastShareT : 0;
    if (msSinceStreamStart - since < kCode15AliveThreshold.inMilliseconds) {
      return false;
    }
    return _append(
      formatCode15Mark(
        share: share,
        msSinceStreamStart: msSinceStreamStart,
        kind: Code15MarkKind.alive,
      ),
      share: share,
      t: msSinceStreamStart,
    );
  }

  /// The whole record, or '' when absent or unreadable.
  String readAll() {
    try {
      return file.existsSync() ? file.readAsStringSync() : '';
    } catch (_) {
      return '';
    }
  }

  /// Stops recording; the lines held are kept. Writes the `pause` line first,
  /// past the stop guard but never past the cap. Nothing if already stopped.
  void stop() {
    if (stopped) return;
    _append(kFixTimingPauseLine, evenIfStopped: true);
    try {
      stoppedFile.parent.createSync(recursive: true);
      stoppedFile.writeAsStringSync('stopped\n', flush: true);
    } catch (_) {}
  }

  /// Records again, then writes the `resume` line through the ordinary guard,
  /// so the line is written only if recording did resume (never past the cap).
  /// Nothing if it was not stopped.
  void resume() {
    if (!stopped) return;
    try {
      if (stoppedFile.existsSync()) stoppedFile.deleteSync();
    } catch (_) {}
    _append(kFixTimingResumeLine);
  }

  /// HIS TAP on 記録を消す, and nothing else, calls this. Deletes every line
  /// held. Whether it records afterwards is unchanged (code 13's rule): the
  /// stopped marker is kept.
  void deleteRecordOnHisTap() {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
    _hasFixLines = fixTimingTextHasFixLines(readAll());
    _count = Code15MinimumCount.ofText(readAll());
    _lastShare = null;
    _lengthAtLastWrite = 0;
    // Lines made before his tap and still waiting for the naming are his
    // record too: they go with it (2026-10-14). Kept, they were written into
    // the fresh file at the naming, after his delete, where code 15 had them
    // on disk at his tap and deleted them with it.
    _held.clear();
    // A fresh file holds no boundary: the next line this build writes is
    // preceded by one (decided from the file's bytes, as at naming). Until
    // the writer is named it stays owed.
    if (_writer != null) _boundaryOwed = _owedFromFile();
  }
}

// ---------------------------------------------------------------------------
// THE COUNT: built on the binding bars' own definitions, and it says only
// whether the data MINIMUM is reached. It never says clean, passed or done:
// clean depends on endings and exclusions only the reading decides (Sakichi
// Vision 14). The bars' line numbers are cited as of their 2026-10-09 text.
// ---------------------------------------------------------------------------

/// MOVING: both bounding fixes at 3.0 m/s or more (bars :30-31).
const double kBarsMovingMinMps = 3.0;

/// MOVING: and at most 50 m/s (bars :31-32).
const double kBarsMovingMaxMps = 50.0;

/// STOPPED: both bounding fixes under 0.1 m/s (bars :31).
const double kBarsStoppedBelowMps = 0.1;

/// T = 12 s (bars :14). An interval over this is never counted toward the
/// moving minimum here: it may be a tunnel the reading excludes (the
/// conservative side). An over-12 STOPPED interval stays in its run, as the
/// bars count it (the 2026-10-10 safety ruling, item 2 (iii)).
const int kBarsOver12Ms = 12000;

/// A or B minimum: 30 minutes of open-sky MOVING time (bars :160).
const int kBarsMinMovingMs = 30 * 60 * 1000;

/// A or B minimum: and 300 open-sky MOVING intervals (bars :160).
const int kBarsMinMovingIntervals = 300;

/// A or B minimum: UNCLASSIFIED at most 20% (bars :160-161). Read here on the
/// stricter side: at most a fifth of the MOVING intervals counted.
const double kBarsMaxUnclassifiedFraction = 0.2;

/// Stopped minimum: 5 minutes (bars :164).
const int kBarsMinStoppedMs = 5 * 60 * 1000;

/// Stopped minimum: and 30 stopped intervals (bars :164).
const int kBarsMinStoppedIntervals = 30;

/// Stopped intervals count only inside runs of at least 6 consecutive STOPPED
/// ones (bars :33, :136-137).
const int kBarsStoppedRunMin = 6;

final RegExp _fixLine = RegExp(
    r'^s=(\d+) t=(\d+) k=(fine|coarse) a=(\d+\.\d) v=(0|\d+\.\d|-) ');
final RegExp _shareLine = RegExp(r'^s=(\d+) t=(\d+) k=([a-z]+)');

/// The bars' data minimum, counted from the record's lines. Pure and
/// incremental: [add] takes one line at a time, in file order.
class Code15MinimumCount {
  Code15MinimumCount();

  /// The count of a whole record text.
  factory Code15MinimumCount.ofText(String text) {
    final c = Code15MinimumCount();
    for (final line in text.split('\n')) {
      if (line.isNotEmpty) c.add(line);
    }
    return c;
  }

  int _movingMs = 0;
  int _movingIntervals = 0;
  int _unclassified = 0;
  int _stoppedMs = 0;
  int _stoppedIntervals = 0;

  // The open segment.
  int? _segShare;
  int? _lastFixT;
  double? _lastFixV;
  int? _lastLineT;
  // A line's t went back since the segment's last fix: the interval to the
  // next fix holds a CLOCK STEP (the bars, section 16 item 3), even when the
  // fixes alone step forward (the 2026-10-10 safety ruling, item 2).
  bool _stepBackSinceLastFix = false;
  int _runIntervals = 0;
  int _runMs = 0;

  /// Open-sky MOVING time counted, in ms (intervals of 12 s or less).
  int get movingMs => _movingMs;

  /// MOVING intervals counted.
  int get movingIntervals => _movingIntervals;

  /// UNCLASSIFIED intervals counted, the open segment's trailing span included.
  int get unclassifiedIntervals => _unclassified + (_openTrailingOver12 ? 1 : 0);

  /// STOPPED time inside runs of [kBarsStoppedRunMin] or more, in ms.
  int get stoppedMs =>
      _stoppedMs + (_runIntervals >= kBarsStoppedRunMin ? _runMs : 0);

  /// STOPPED intervals inside runs of [kBarsStoppedRunMin] or more.
  int get stoppedIntervals =>
      _stoppedIntervals +
      (_runIntervals >= kBarsStoppedRunMin ? _runIntervals : 0);

  bool get _openTrailingOver12 =>
      _lastFixT != null &&
      _lastLineT != null &&
      (_lastLineT! - _lastFixT! > kBarsOver12Ms || _stepBackSinceLastFix);

  /// Whether the data MINIMUM of the bars is reached. Only that: never clean,
  /// passed or done.
  bool get minimumReached =>
      movingMs >= kBarsMinMovingMs &&
      movingIntervals >= kBarsMinMovingIntervals &&
      unclassifiedIntervals <= kBarsMaxUnclassifiedFraction * movingIntervals &&
      stoppedMs >= kBarsMinStoppedMs &&
      stoppedIntervals >= kBarsMinStoppedIntervals;

  void _closeRun() {
    if (_runIntervals >= kBarsStoppedRunMin) {
      _stoppedIntervals += _runIntervals;
      _stoppedMs += _runMs;
    }
    _runIntervals = 0;
    _runMs = 0;
  }

  void _closeSegment() {
    _closeRun();
    // A share's trailing span over 12 s counts as one UNCLASSIFIED interval
    // (the bars, section 16 item 2).
    if (_openTrailingOver12) _unclassified++;
    _stepBackSinceLastFix = false;
    _segShare = null;
    _lastFixT = null;
    _lastFixV = null;
    _lastLineT = null;
  }

  static double? _speed(String v) => v == '-' ? null : double.tryParse(v);

  /// One line, in file order. A marker (`launch`, `pause`, `resume`), an
  /// `end`, an `appstop`, or a change of share ends a segment; no interval or
  /// run crosses one (the bars, section 14 item 2, and section 17).
  void add(String line) {
    final m = _shareLine.firstMatch(line);
    if (m == null || line.startsWith('s=0 t=0 k=')) {
      _closeSegment();
      return;
    }
    final share = int.parse(m.group(1)!);
    final t = int.parse(m.group(2)!);
    final kind = m.group(3)!;
    if (_segShare != null && share != _segShare) _closeSegment();
    _segShare = share;
    if (_lastLineT != null && t < _lastLineT!) _stepBackSinceLastFix = true;
    _lastLineT = t;
    final f = _fixLine.firstMatch(line);
    if (f != null) {
      final v = _speed(f.group(5)!);
      final lastT = _lastFixT;
      if (lastT != null) {
        final ms = t - lastT;
        final a = _lastFixV;
        final moving = a != null &&
            v != null &&
            a >= kBarsMovingMinMps &&
            a <= kBarsMovingMaxMps &&
            v >= kBarsMovingMinMps &&
            v <= kBarsMovingMaxMps;
        final stoppedPair = a != null &&
            v != null &&
            a < kBarsStoppedBelowMps &&
            v < kBarsStoppedBelowMps;
        if (ms < 0 || _stepBackSinceLastFix) {
          // A clock step: counted as UNCLASSIFIED (the bars, section 16 item 3).
          _closeRun();
          _unclassified++;
        } else if (moving) {
          _closeRun();
          if (ms <= kBarsOver12Ms) {
            _movingIntervals++;
            _movingMs += ms;
          }
        } else if (stoppedPair) {
          _runIntervals++;
          _runMs += ms;
        } else {
          _closeRun();
          _unclassified++;
        }
      }
      _lastFixT = t;
      _lastFixV = v;
      _stepBackSinceLastFix = false;
    }
    if (kind == 'end' || kind == 'appstop') _closeSegment();
  }
}

// ---------------------------------------------------------------------------
// Opening and sharing.
// ---------------------------------------------------------------------------

/// Opens the record in the app-support directory at process start, and writes
/// its `launch` line; or null when it cannot be opened (the card then says so).
/// The app opens the record only here, once per process.
///
/// The build that writes is named when the platform answers ([identity],
/// production [BuildIdentity.fromPlatform]), without holding the app's start:
/// the APK's self-hash takes about a second. Until then the `launch` line and
/// anything after it wait, in order. An identity that does not answer within
/// [identityTimeout] names a build that cannot name itself: no line of any
/// kind, and the card says so.
Future<Code15FixIntervalRecord?> openCode15FixIntervalRecord({
  Directory? directory,
  Future<BuildIdentity> Function()? identity,
  Duration identityTimeout = const Duration(seconds: 30),
}) async {
  try {
    final dir = directory ?? await getApplicationSupportDirectory();
    final record = Code15FixIntervalRecord(directory: dir, writer: null);
    record.recordLaunch();
    // The one scan, here where the record opens.
    record.hasFixLines;
    record.count;
    unawaited(() async {
      BuildIdentity id;
      try {
        id = await (identity ?? BuildIdentity.fromPlatform)()
            .timeout(identityTimeout);
      } catch (_) {
        id = const BuildIdentity.unknown();
      }
      record.nameWriter(RecordWriter.fromIdentity(id));
    }());
    return record;
  } catch (_) {
    return null;
  }
}

/// The share header's line for a build not (yet) named: every token a
/// declared gap, never a guess.
const String kRecordUnnamedBuildHeader = 'build: - - -';

/// The record's share payload: an identity header (code 13's three lines, plus
/// the record's line and byte counts so a receiver that cut the text is seen
/// at the reading end), `---`, then every line as written. Never cut. When the
/// record holds no fix line, it says so before any markers it does hold.
///
/// Code 16 (2026-10-14): the header carries exactly one `build: V S A` line
/// (versionCode, commit, APK), right after `exported:`, naming the EXPORTING
/// build in the boundary line's tokens ([RecordWriter.headerLine]); `-` for anything it
/// could not read, and all three when it is not named. It names the build
/// that shares, never the builds that wrote: those are the boundary lines'.
/// The title line and `lines:`/`bytes:` are as before, and sharing writes no
/// byte of the record.
String composeCode15SharePayload({
  required String recordText,
  required RecordWriter? exportingBuild,
  String? operatingSystem,
  DateTime? exportedAt,
}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  final ts = (exportedAt ?? DateTime.now()).toUtc().toIso8601String();
  final lines = '\n'.allMatches(recordText).length;
  final bytes = utf8.encode(recordText).length;
  final buf = StringBuffer()
    ..writeln('sngnav-app $appVersion fix-timing record (test build)')
    ..writeln('os: $os')
    ..writeln('exported: $ts')
    ..writeln(exportingBuild?.headerLine ?? kRecordUnnamedBuildHeader)
    ..writeln('lines: $lines')
    ..writeln('bytes: $bytes')
    ..writeln('---');
  if (!fixTimingTextHasFixLines(recordText)) {
    buf.writeln('測位間隔の記録はありません (no fix-interval lines)');
  }
  buf.write(recordText);
  return buf.toString();
}

/// Injectable exit door: hands the FILE at its path (the payload above,
/// written by [RecordShareFile.stage]) to the share sheet.
typedef Code15RecordShareSink = RecordFileShareSink;

/// Production [Code15RecordShareSink]: the platform share sheet with the
/// record as a FILE, never as text in the intent: at the cap the text could
/// not be delivered (an emulator read on API 30 and 34, 2026-10-10), and the
/// file goes as a link the receiver reads (services/record_share_file.dart).
/// The share sheet reports at most the chosen target, never that the record
/// arrived, so nothing is deleted on its result.
Future<void> shareCode15RecordViaShareSheet(String path) =>
    shareRecordFileViaShareSheet(path,
        subject: 'sngnav-app $appVersion — fix-timing record');
