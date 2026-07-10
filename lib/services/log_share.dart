/// C6 ログを共有 — one-tap share of the local error log (BETA_PLAN fix #8).
///
/// HER-trace: the beta feedback path shaped for HER cohort — a tester sends
/// the on-device error log the way she sends a photo: one tap, the OS share
/// sheet, a receiver of her own choice. Without this action, tester-found
/// defects die on the device and never reach the loom.
///
/// Honest bounds (consent-preserving by construction):
/// - The share fires ONLY from the user's tap. NO auto-telemetry, NO
///   background upload, NO accounts (error_log.dart's contract carried
///   through to the exit door).
/// - The payload is strictly build-header + the error log text. The log
///   stores no location history (services/error_log.dart records only
///   timestamp + source + error + stack) and this composer adds NO position
///   or coordinate state of any kind.
/// - Empty log -> an honest "log is empty" line, never fabricated content.
/// - Large log -> the NEWEST tail is kept (aligned to a whole entry, same
///   idiom as LocalErrorLog._trimIfNeeded) behind an honest truncation note,
///   because some share receivers truncate very large ACTION_SEND text.
/// - The OS share sheet itself is on-device behaviour: HEAR/SEE of the real
///   chooser is OPS-066 DEFERRED until a device pass (AAE env-bound).
library;

import 'dart:io' show Platform;

import 'package:share_plus/share_plus.dart';

import '../build_info.dart';
import 'error_log.dart' show kErrorLogEntryMarker;

/// Injectable exit door for the composed payload. Production uses
/// [shareLogViaShareSheet]; tests inject a recording fake so no platform
/// channel is ever touched in the test binding.
typedef LogShareSink = Future<void> Function(String payload);

/// Cap on the shared log body. Measured in UTF-16 code units (~bytes for the
/// ASCII-dominant log content — the same honest approximation
/// LocalErrorLog's trim makes). ~100 KB keeps the ACTION_SEND text well
/// inside receiver limits while preserving the newest evidence.
const int kLogShareMaxChars = 100 * 1024;

/// Honest empty-log payload line (BETA_PLAN fix #8 — never fabricate
/// content; the ja line is HER cohort's tongue, the parenthetical keeps it
/// readable to an en-reading triager).
const String kLogShareEmptyLine = 'ログは空です（クラッシュ・エラーの記録はありません）';

/// Honest truncation note prepended when the newest tail was kept.
const String kLogShareTruncationNote =
    '※ ログが大きいため、新しい記録のみを共有しています（古い記録は省略）。\n'
    '(note: log truncated for sharing — newest entries kept, oldest omitted)';

/// Composes the share payload: identity header + the error log text.
///
/// Header = app version ([appVersion], the only version UI copy may show,
/// per build_info.dart) + operating system + export timestamp (UTC ISO8601,
/// matching LocalErrorLog.record's timestamp format).
///
/// [operatingSystem] / [exportedAt] are injectable for deterministic tests;
/// production leaves them null ([Platform.operatingSystem] / now-UTC).
///
/// The payload is strictly header + log: NO position, coordinate, route or
/// destination state is ever added here — the log's no-location-history
/// property must survive to the exit door.
String composeLogSharePayload({
  required String logText,
  String? operatingSystem,
  DateTime? exportedAt,
  int maxChars = kLogShareMaxChars,
}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  final ts = (exportedAt ?? DateTime.now()).toUtc().toIso8601String();
  final buf = StringBuffer()
    ..writeln('sngnav-app $appVersion')
    ..writeln('os: $os')
    ..writeln('exported: $ts')
    ..writeln('---');
  if (logText.isEmpty) {
    buf.writeln(kLogShareEmptyLine);
    return buf.toString();
  }
  var body = logText;
  if (body.length > maxChars) {
    // Keep the newest tail, then advance to the next entry marker so the
    // shared log starts at a whole entry (error_log.dart trim idiom).
    var start = body.length - maxChars;
    if (start < 0) start = 0;
    final aligned = body.indexOf(kErrorLogEntryMarker, start);
    body = aligned >= 0 ? body.substring(aligned) : body.substring(start);
    buf.writeln(kLogShareTruncationNote);
  }
  buf.write(body);
  return buf.toString();
}

/// Production [LogShareSink]: fires the platform share sheet with the
/// payload as plain text (share_plus 13.x `SharePlus.instance.share` +
/// `ShareParams(text:)` — ACTION_SEND / EXTRA_TEXT on Android; no
/// FileProvider, no manifest change). The subject feeds the email fallback
/// where the platform uses one.
Future<void> shareLogViaShareSheet(String payload) async {
  await SharePlus.instance.share(
    ShareParams(text: payload, subject: 'sngnav-app $appVersion — error log'),
  );
}
