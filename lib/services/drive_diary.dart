/// RING-2 DRIVE DIARY — the season's consented evidence instrument.
///
/// The three-month plan (outputs/plans/three_month_plan_2026_08_10.md §2,
/// Ring 2) binds the remote-beta evidence path: a consented in-app ja
/// post-drive diary → local file → share sheet. Ten active diary-writers in
/// real snow = a successful season; dated entries are cross-checked against
/// AMeDAS / あきたのみち情報 by the reader — never by the app.
///
/// HER-trace: after the drive, parked, she writes three taps and a line —
/// what the road was, whether the warning helped, in her own words. That
/// entry is the only instrument that can prove the season's falsifier #1
/// (real people, real snow, real use) without surveillance.
///
/// Honest bounds (consent-preserving by construction, error_log.dart's
/// contract carried through):
/// - ZERO telemetry. Entries persist ONLY to a local file; they leave the
///   device ONLY via the user's explicit 日記を共有 tap (OS share sheet,
///   receiver of her own choice).
/// - NO position, coordinate, route or destination state is recorded. The
///   only place is the one SHE TYPES (free-text area), which is her words,
///   not a sensor read.
/// - Timestamps are LOCAL time with UTC offset — the reader's AMeDAS
///   cross-check runs on JST wall-clock, so recording UTC-only would shift
///   a pre-dawn ice entry onto the wrong calendar day.
/// - Size-capped (ring-buffer at entry granularity, error_log.dart idiom):
///   the diary can never grow to fill her storage. The cap (~512 KB,
///   roughly a thousand entries) is far beyond a season's writing, so in
///   practice nothing is ever dropped.
/// - A diary failure must never take the app down: every file op is
///   wrapped; a broken write is dropped, not thrown.
/// - The OS share sheet itself is on-device behaviour: OPS-066 DEFERRED
///   until a device pass (AAE env-bound), same bound as log_share.dart.
library;

import 'dart:convert' show utf8;
import 'dart:io' show File, FileMode, Platform;

import 'package:japanese_snow_vocabulary/japanese_snow_vocabulary.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../build_info.dart';

/// Marker line that starts every entry — also the boundary trim/count
/// respect, so rotation never leaves half an entry at the top.
const String kDiaryEntryMarker = '--- sngnav diary ';

/// What she saw on the road — human-observed, never sensor-fabricated.
/// The file records the ja label plus a stable en token so a dated entry
/// stays machine-collatable across app versions.
///
/// VOCABULARY SOURCE (2026-08-10): the ja labels are no longer app-local
/// translations-from-English. Where a chip IS exactly one term of the
/// catalog's `japanese_snow_vocabulary`, [vocabulary] names that term and a
/// drift guard pins the label to the package's `termJa`
/// (test/services/drive_diary_vocabulary_test.dart). Where a chip
/// deliberately spans more than one package term (see [ice], [wet]) or has
/// no package term at all (see [snow], [whiteout], [dry]), [vocabulary] is
/// null and the reason is recorded on the case. That package exists to stop
/// *"the silent erasure of finer-grained JA vocabulary by English-language
/// collapse"* — which is exactly what a hand-authored chip list inside an
/// app becomes as the app drifts.
///
/// TOKEN STABILITY IS LOAD-BEARING: entries already written to a beta
/// driver's device carry these tokens. Existing tokens are never renamed or
/// re-meaninged — new distinctions arrive as NEW cases, so a reader can
/// always tell a pre-split entry from a post-split one.
enum DiaryRoadCondition {
  // No package term: 乾燥 is the absence of the winter surface classes,
  // not a member of the taxonomy.
  dry('乾燥', 'dry', null),
  // SPANS two package terms (シャーベット + plain wet). Deliberately not
  // split: the season's load-bearing distinction is ice-that-looks-wet
  // (see [blackIce]), and every extra chip costs a cold-handed elderly
  // driver a target. If a reader later needs 濡れ and シャーベット apart,
  // it arrives as a NEW case, never by re-meaning this token.
  wet('濡れ・シャーベット', 'wet-slush', null),
  // No package term: 積雪 (accumulated snow ON the surface) is a different
  // word from the package's 雪道 (snow ROAD). The chip asks what the
  // surface was, so 積雪 is the honest label and no 1:1 binding exists.
  snow('積雪', 'snow', null),
  // 圧雪 sits between fresh snow and ice — the most common hazardous
  // surface on Akita/Niigata winter roads (adversarial domain review).
  compacted('圧雪', 'compacted-snow', JapaneseSnowSurfaceClass.compactedSnow),
  // SPANS 凍結 + アイスバーン: ice she could SEE. Kept as one chip because
  // the distinction that decides the season is visible-vs-invisible, and
  // that is [blackIce] below — not 凍結-vs-アイスバーン.
  ice('凍結・アイスバーン', 'ice', null),
  // ADDED 2026-08-10 — the gap that made the season's flagship warning
  // unfalsifiable. The app's most-hardened in-drive advisory is the
  // invisible-ice / radiative-cooling warning, spoken and drawn as
  // 「ブラックアイスバーン」 (lib/services/invisible_ice_watch.dart,
  // lib/voice/offline_safety_voice.dart, main.dart's caution card) — yet
  // the diary offered her no way to report that surface. Her only
  // neighbouring chip was 凍結・アイスバーン, which is ice she could SEE;
  // black ice is DEFINED by being invisible ("一見すると濡れたアスファルト
  // 路面のように黒く見えるのに、実は表面が凍りついている" — JAF, verbatim in
  // the package). So "the warning fired and the road was visibly frozen"
  // and "the warning fired and the road looked merely wet" collapsed into
  // one entry, and the reader could not tell a TRUE POSITIVE from a
  // near-miss. Falsifier #2 of the season turns on exactly that.
  blackIce('ブラックアイスバーン', 'black-ice', JapaneseSnowSurfaceClass.blackIceBahn),
  // No package term: 吹雪・視界不良 is a visibility state, not a surface.
  whiteout('吹雪・視界不良', 'whiteout', null),
  // Never a package term, and deliberately the default: an unanswered
  // chip must read as "she did not say", never as an observation.
  unknown('わからない', 'unknown', null);

  const DiaryRoadCondition(this.ja, this.token, this.vocabulary);

  /// The ja label she reads on the chip.
  final String ja;

  /// Stable machine token written to the file. NEVER renamed (see enum doc).
  final String token;

  /// The `japanese_snow_vocabulary` term this chip IS, when it is exactly
  /// one. Null for spanning or non-taxonomy chips — see each case's note.
  /// The drift guard asserts [ja] == the package's `termJa` for every
  /// non-null binding, so a catalog vocabulary change can never leave HER
  /// chip reading a stale word.
  final JapaneseSnowSurfaceClass? vocabulary;
}

/// Whether the app's advisory fired and whether it helped — the season
/// falsifier #2's raw material, in her judgement, not ours.
enum DiaryAdvisoryExperience {
  firedHelpful('警告あり・役立った', 'fired-helpful'),
  // The too-late vs false-alarm disambiguation lives in the note-field
  // hint, NOT here: the longer parenthesized label render-SEEN clipped at
  // dialog width (ladder_out/drive_diary/, 2026-07-27).
  firedNotHelpful('警告あり・役立たなかった', 'fired-not-helpful'),
  didNotFire('警告なし', 'did-not-fire'),
  notSure('わからない・使わなかった', 'not-sure');

  const DiaryAdvisoryExperience(this.ja, this.token);
  final String ja;
  final String token;
}

/// Injectable exit door for the composed payload. Production uses
/// [shareDiaryViaShareSheet]; tests inject a recording fake so no platform
/// channel is ever touched in the test binding.
typedef DiaryShareSink = Future<void> Function(String payload);

/// Cap on the shared diary body (log_share.dart idiom; same honest UTF-16
/// approximation). A season of entries sits far below this.
const int kDiaryShareMaxChars = 100 * 1024;

/// Honest empty-diary payload line — never fabricated content.
const String kDiaryShareEmptyLine = '日記はまだありません（運転日記の記録はありません）';

/// Honest truncation note prepended when the newest tail was kept.
const String kDiaryShareTruncationNote =
    '※ 日記が大きいため、新しい記録のみを共有しています（古い記録は省略）。\n'
    '(note: diary truncated for sharing — newest entries kept, oldest omitted)';

/// Size-capped append-only drive diary (ring buffer at entry granularity).
class DriveDiary {
  DriveDiary({required this.file, this.maxBytes = 512 * 1024, this.clock});

  /// The on-device diary file (app documents dir in production; a temp dir
  /// in tests — the file, not path_provider, is the dependency).
  final File file;

  /// Cap on the diary size. When an append pushes the file past this, the
  /// oldest entries are dropped until it fits in [maxBytes] ~/ 2
  /// (error_log.dart halving idiom).
  final int maxBytes;

  /// Injectable clock (null -> [DateTime.now], LOCAL — see library doc on
  /// why local wall-clock is load-bearing for the AMeDAS cross-check).
  final DateTime Function()? clock;

  /// Appends one post-drive entry. Never throws — a diary failure must
  /// never become a crash. Returns true when the entry was persisted.
  bool record({
    required DiaryRoadCondition road,
    required DiaryAdvisoryExperience advisory,
    String area = '',
    String note = '',
  }) {
    try {
      final now = (clock ?? DateTime.now)();
      final buf = StringBuffer()
        ..writeln('$kDiaryEntryMarker${_localIso8601(now)} ---')
        ..writeln('路面: ${road.ja} (${road.token})')
        ..writeln('警告: ${advisory.ja} (${advisory.token})');
      final cleanArea = _sanitize(area);
      final cleanNote = _sanitize(note);
      if (cleanArea.isNotEmpty) buf.writeln('地域: $cleanArea');
      if (cleanNote.isNotEmpty) buf.writeln('メモ: $cleanNote');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(buf.toString(),
          mode: FileMode.append, flush: true);
    } catch (_) {
      // Swallow: see class doc. NO secondary channel (NO network by design).
      return false;
    }
    // The entry IS persisted at this point: a rotation failure must not
    // report the save as failed (a false 「保存できませんでした」 invites a
    // retry that duplicates the entry). _trimIfNeeded never throws.
    _trimIfNeeded();
    return true;
  }

  /// Whole diary as text (newest entries at the end). Empty string when no
  /// diary exists yet — the read surface for the 日記を共有 action.
  String readAll() {
    try {
      if (!file.existsSync()) return '';
      return file.readAsStringSync();
    } catch (_) {
      return '';
    }
  }

  /// Number of persisted entries (marker count). Reads the file — call on
  /// demand (save/share), not per frame; use [hasEntries] for status lines.
  int entryCount() {
    final text = readAll();
    if (text.isEmpty) return 0;
    var count = 0;
    var idx = text.indexOf(kDiaryEntryMarker);
    while (idx >= 0) {
      count++;
      idx = text.indexOf(kDiaryEntryMarker, idx + kDiaryEntryMarker.length);
    }
    return count;
  }

  /// O(1) stat (not a full read) — safe for per-build status lines
  /// (log_share panel idiom). A stat failure degrades to "no entries"
  /// honestly, matching readAll()'s empty-on-error contract.
  bool hasEntries() {
    try {
      return file.existsSync() && file.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }

  /// User text is her words verbatim — EXCEPT the entry marker, which
  /// would corrupt entry-boundary integrity (trim alignment + counting) if
  /// it appeared inside a note. Neutralized, not silently dropped.
  String _sanitize(String s) =>
      s.trim().replaceAll(kDiaryEntryMarker, '--- (diary) ');

  /// Trims in BYTES (the cap is a storage promise; ja text is ~3 UTF-8
  /// bytes per UTF-16 code unit, so trimming on String indices would keep
  /// up to ~1.5× the cap). The marker is pure ASCII, so byte-search finds
  /// exact entry boundaries and the kept slice always starts on a whole
  /// entry — never mid-rune. Never throws (see [record]).
  void _trimIfNeeded() {
    try {
      if (file.lengthSync() <= maxBytes) return;
      final bytes = file.readAsBytesSync();
      final target = maxBytes ~/ 2;
      var start = bytes.length - target;
      if (start < 0) start = 0;
      final marker = utf8.encode(kDiaryEntryMarker);
      var aligned = _indexOfBytes(bytes, marker, start);
      // No marker after the cut point (one huge newest entry): fall back to
      // the last marker anywhere so a whole entry is still kept.
      if (aligned < 0) aligned = _lastIndexOfBytes(bytes, marker);
      if (aligned <= 0) return;
      file.writeAsBytesSync(bytes.sublist(aligned), flush: true);
    } catch (_) {
      // A failed trim leaves an over-cap but valid diary; never a crash.
    }
  }

  static int _indexOfBytes(List<int> haystack, List<int> needle, int from) {
    for (var i = from; i <= haystack.length - needle.length; i++) {
      var hit = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          hit = false;
          break;
        }
      }
      if (hit) return i;
    }
    return -1;
  }

  static int _lastIndexOfBytes(List<int> haystack, List<int> needle) {
    for (var i = haystack.length - needle.length; i >= 0; i--) {
      var hit = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          hit = false;
          break;
        }
      }
      if (hit) return i;
    }
    return -1;
  }

  /// ISO8601 local wall-clock WITH UTC offset (+09:00 in HER geography) —
  /// Dart's toIso8601String() on a local DateTime omits the offset, which
  /// would make the entry's day ambiguous to the AMeDAS cross-checker.
  static String _localIso8601(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final off = local.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final abs = off.abs();
    return '${local.year}-${two(local.month)}-${two(local.day)}'
        'T${two(local.hour)}:${two(local.minute)}:${two(local.second)}'
        '$sign${two(abs.inHours)}:${two(abs.inMinutes % 60)}';
  }
}

/// Opens the production diary under the app DOCUMENTS directory (it is
/// user-authored content, not app support state). Null when the directory
/// cannot be resolved — the app still boots; the diary card renders its
/// action honestly disabled (errorLog idiom).
Future<DriveDiary?> openDriveDiary() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    return DriveDiary(file: File('${dir.path}/drive_diary.txt'));
  } catch (_) {
    return null;
  }
}

/// Composes the share payload: identity header + the diary text.
///
/// The payload is strictly header + diary: NO position, coordinate, route
/// or destination state is ever added here — the diary's no-location
/// property must survive to the exit door (log_share.dart contract).
String composeDiarySharePayload({
  required String diaryText,
  String? operatingSystem,
  DateTime? exportedAt,
  int maxChars = kDiaryShareMaxChars,
}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  final ts = (exportedAt ?? DateTime.now()).toUtc().toIso8601String();
  final buf = StringBuffer()
    ..writeln('sngnav-app $appVersion — 運転日記 (drive diary)')
    ..writeln('os: $os')
    ..writeln('exported: $ts')
    ..writeln('---');
  if (diaryText.isEmpty) {
    buf.writeln(kDiaryShareEmptyLine);
    return buf.toString();
  }
  var body = diaryText;
  if (body.length > maxChars) {
    var start = body.length - maxChars;
    if (start < 0) start = 0;
    final aligned = body.indexOf(kDiaryEntryMarker, start);
    body = aligned >= 0 ? body.substring(aligned) : body.substring(start);
    buf.writeln(kDiaryShareTruncationNote);
  }
  buf.write(body);
  return buf.toString();
}

/// Production [DiaryShareSink]: the platform share sheet with the payload
/// as plain text (share_plus 13.x idiom, matching shareLogViaShareSheet).
Future<void> shareDiaryViaShareSheet(String payload) async {
  await SharePlus.instance.share(
    ShareParams(text: payload, subject: 'sngnav-app $appVersion — 運転日記'),
  );
}
