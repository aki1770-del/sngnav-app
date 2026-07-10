// C6 ログを共有 — payload composition (services/log_share.dart).
//
// Pins the share payload's contract WITHOUT a device: identity header
// (appVersion + os + UTC export timestamp), the error-log text verbatim,
// the honest empty-log line (never fabricated content), newest-tail
// truncation aligned to a whole entry, and — load-bearing for consent —
// the ABSENCE of any position state (the log stores no location history;
// the composer must add none).
//
// The File is injected into LocalErrorLog per the error_log_test pattern —
// path_provider is a production-only concern.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_app/build_info.dart';
import 'package:sngnav_app/services/error_log.dart';
import 'package:sngnav_app/services/log_share.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sngnav_log_share_test');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  LocalErrorLog makeLog({int maxBytes = 200 * 1024}) =>
      LocalErrorLog(file: File('${tmp.path}/error_log.txt'), maxBytes: maxBytes);

  test('payload: header (appVersion + os + UTC ISO8601 export) + seeded '
      'log verbatim', () {
    final log = makeLog();
    log.record(StateError('share boom'), StackTrace.current,
        source: 'FlutterError');

    final exportedAt = DateTime.utc(2026, 7, 10, 12, 34, 56);
    final payload = composeLogSharePayload(
      logText: log.readAll(),
      operatingSystem: 'testos',
      exportedAt: exportedAt,
    );

    // Identity header — the app's own version is the ONLY version the
    // payload names (build_info.dart discipline).
    expect(payload, contains('sngnav-app $appVersion'));
    expect(payload, contains('os: testos'));
    expect(payload, contains('exported: 2026-07-10T12:34:56.000Z'));
    // The log text made it through verbatim.
    expect(payload, contains(kErrorLogEntryMarker));
    expect(payload, contains('[FlutterError]'));
    expect(payload, contains('share boom'));
    // Not the empty line, not the truncation note — the log was small+real.
    expect(payload, isNot(contains(kLogShareEmptyLine)));
    expect(payload, isNot(contains('省略')));
  });

  test('payload defaults: real Platform.operatingSystem + a real UTC '
      'timestamp when none injected', () {
    final payload = composeLogSharePayload(logText: '');
    expect(payload, contains('os: ${Platform.operatingSystem}'));
    // ISO8601 UTC ends in Z; the header line must carry one.
    expect(RegExp(r'exported: .*Z\n').hasMatch(payload), isTrue,
        reason: 'export timestamp must be UTC ISO8601 (trailing Z)');
  });

  test('empty log: honest empty line, never fabricated content', () {
    final log = makeLog(); // nothing ever recorded
    final payload = composeLogSharePayload(logText: log.readAll());

    expect(payload, contains(kLogShareEmptyLine));
    // No fabricated entries: the entry marker must be absent.
    expect(payload, isNot(contains(kErrorLogEntryMarker)));
  });

  test('large log: newest tail kept, aligned to a whole entry, behind an '
      'honest truncation note', () {
    final log = makeLog();
    final filler = 'y' * 1200;
    // ~150 KB of entries (within the 200 KB LocalErrorLog cap, above the
    // ~100 KB share cap).
    for (var i = 0; i < 120; i++) {
      log.record(StateError('share-entry-$i $filler'), null);
    }
    final logText = log.readAll();
    expect(logText.length, greaterThan(kLogShareMaxChars),
        reason: 'precondition: the seeded log must exceed the share cap');

    final payload = composeLogSharePayload(logText: logText);

    // Honest note present; newest entry survived; the oldest was dropped.
    expect(payload, contains(kLogShareTruncationNote));
    expect(payload, contains('share-entry-119'));
    expect(payload, isNot(contains('share-entry-0 ')));
    // The kept tail starts at a WHOLE entry (marker directly after the
    // truncation note line — never mid-entry).
    final afterNote = payload
        .substring(payload.indexOf(kLogShareTruncationNote) +
            kLogShareTruncationNote.length)
        .trimLeft();
    expect(afterNote.startsWith(kErrorLogEntryMarker), isTrue,
        reason: 'truncation must align to an entry boundary');
    // And the shared body actually shrank to ~the cap.
    expect(payload.length, lessThan(logText.length));
    expect(payload.length, lessThanOrEqualTo(kLogShareMaxChars + 1024),
        reason: 'payload must be near/below the cap (+ header/note slack)');
  });

  test('consent: payload carries NO position state — Akita mock coordinates '
      'absent', () {
    final log = makeLog();
    log.record(StateError('a crash while the mock dot was on'), null);

    final payload = composeLogSharePayload(logText: log.readAll());

    // The akitaStation mock (akita_map.dart: 39.7167, 140.0983) must never
    // leak into the share payload — the composer takes ONLY the log text.
    expect(payload, isNot(contains('39.7167')));
    expect(payload, isNot(contains('140.0983')));
  });
}
