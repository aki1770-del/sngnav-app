/// W2 — crash boundary + LOCAL on-device error log.
///
/// A top-level error boundary (FlutterError.onError +
/// PlatformDispatcher.onError) that appends every uncaught error to a
/// size-capped local log file under the app-support directory.
///
/// HER-trace: when the app misbehaves on HER phone on a snow morning, the
/// evidence of WHY must survive on the device so she (or a beta tester) can
/// share it deliberately — the W3 "ログを共有" action. Honest bounds:
/// - NO network, NO telemetry, NO auto-upload. The log leaves the device
///   ONLY via the user-initiated ログを共有 share action
///   (services/log_share.dart; BETA_PLAN fix #8, consent-preserving by
///   construction).
/// - Size-capped (~200 KB): when the cap is exceeded the OLDEST entries are
///   dropped at an entry boundary (ring-buffer discipline) — the log can
///   never grow to fill her storage.
/// - The boundary never masks errors in debug (developers still see red
///   screens / consoles) and never lets a logging failure take the app down
///   (every file op is wrapped; a broken log is dropped, not thrown).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Marker line that starts every entry — also the boundary the trim
/// respects, so rotation never leaves half an entry at the top.
const String kErrorLogEntryMarker = '--- sngnav error ';

/// Size-capped append-only error log ("ring buffer" at entry granularity).
class LocalErrorLog {
  LocalErrorLog({required this.file, this.maxBytes = 200 * 1024});

  /// The on-device log file (app-support dir in production; a temp dir in
  /// tests — the file, not path_provider, is the dependency).
  final File file;

  /// Cap on the log size. When an append pushes the file past this, the
  /// oldest entries are dropped until it fits in [maxBytes] ~/ 2 (halving
  /// avoids re-trimming on every subsequent write).
  final int maxBytes;

  /// Appends one entry. Never throws — a logging failure must never become
  /// a second crash (the boundary sits inside the error handlers).
  void record(Object error, StackTrace? stack, {String source = 'unhandled'}) {
    try {
      final ts = DateTime.now().toUtc().toIso8601String();
      final buf = StringBuffer()
        ..writeln('$kErrorLogEntryMarker$ts [$source] ---')
        ..writeln(error.toString());
      if (stack != null) buf.writeln(stack.toString());
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(buf.toString(), mode: FileMode.append, flush: true);
      _trimIfNeeded();
    } catch (_) {
      // Swallow: see doc comment. There is deliberately no rethrow and no
      // secondary reporting channel (NO network by design).
    }
  }

  /// Whole log as text (newest entries at the end). Empty string when no
  /// log exists yet. This is the read surface for the W3 "ログを共有" action.
  String readAll() {
    try {
      if (!file.existsSync()) return '';
      return file.readAsStringSync();
    } catch (_) {
      return '';
    }
  }

  void _trimIfNeeded() {
    if (file.lengthSync() <= maxBytes) return;
    final text = file.readAsStringSync();
    final target = maxBytes ~/ 2;
    // Keep the newest tail, then advance to the next entry marker so the
    // retained log starts at a whole entry.
    var start = text.length - target;
    if (start < 0) start = 0;
    final aligned = text.indexOf(kErrorLogEntryMarker, start);
    final kept = aligned >= 0 ? text.substring(aligned) : text.substring(start);
    file.writeAsStringSync(kept, flush: true);
  }
}

/// Installs the top-level error boundary. Call once from `main()` before
/// `runApp`. Returns the installed log (null when the app-support directory
/// could not be resolved — the app still boots; the boundary never blocks
/// startup).
Future<LocalErrorLog?> installCrashBoundary({LocalErrorLog? log}) async {
  LocalErrorLog? resolved = log;
  if (resolved == null) {
    try {
      final dir = await getApplicationSupportDirectory();
      resolved = LocalErrorLog(file: File('${dir.path}/error_log.txt'));
    } catch (_) {
      // No path_provider on this platform/harness — boot without a log
      // rather than crash at the crash boundary.
      resolved = null;
    }
  }

  final previousFlutterHandler = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    resolved?.record(details.exception, details.stack,
        source: 'FlutterError');
    // Preserve the default behaviour (red screen / console in debug).
    if (previousFlutterHandler != null) {
      previousFlutterHandler(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    resolved?.record(error, stack, source: 'PlatformDispatcher');
    // Debug: return false so the error stays loudly unhandled for the
    // developer. Release: absorb after logging — the boundary keeps a
    // recoverable async error from hard-killing the app on HER phone,
    // and the log preserves the evidence.
    return !kDebugMode;
  };

  return resolved;
}
