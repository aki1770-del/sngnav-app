// W2 — crash boundary + local error log (services/error_log.dart).
//
// Verifies the on-device logger's contract: write (append, timestamped,
// stack included), rotate (size cap enforced, OLDEST entries dropped at an
// entry boundary, newest preserved), read (empty-safe), and the
// never-throws discipline (a broken file must not become a second crash).
// The File is injected — path_provider is a production-only concern.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_app/services/error_log.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sngnav_error_log_test');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  LocalErrorLog makeLog({int maxBytes = 200 * 1024}) =>
      LocalErrorLog(file: File('${tmp.path}/error_log.txt'), maxBytes: maxBytes);

  test('write: appends timestamped entries with error + stack', () {
    final log = makeLog();
    log.record(StateError('first boom'), StackTrace.current,
        source: 'FlutterError');
    log.record(ArgumentError('second boom'), null,
        source: 'PlatformDispatcher');

    final text = log.readAll();
    expect(text, contains(kErrorLogEntryMarker));
    expect(text, contains('[FlutterError]'));
    expect(text, contains('first boom'));
    expect(text, contains('error_log_test.dart')); // the stack made it in
    expect(text, contains('[PlatformDispatcher]'));
    expect(text, contains('second boom'));
    // Order: oldest first, newest at the end.
    expect(text.indexOf('first boom'), lessThan(text.indexOf('second boom')));
  });

  test('read: empty string when nothing was ever logged', () {
    expect(makeLog().readAll(), isEmpty);
  });

  test('rotate: cap enforced, oldest dropped at an entry boundary, '
      'newest kept', () {
    final log = makeLog(maxBytes: 4 * 1024);
    final filler = 'x' * 300;
    for (var i = 0; i < 40; i++) {
      log.record(StateError('entry-$i $filler'), null);
    }
    final file = File('${tmp.path}/error_log.txt');
    expect(file.lengthSync(), lessThanOrEqualTo(4 * 1024),
        reason: 'the log must never exceed its cap after a write');

    final text = log.readAll();
    // Newest entry survived; the oldest was dropped.
    expect(text, contains('entry-39'));
    expect(text, isNot(contains('entry-0 ')));
    // Ring-buffer trim starts the retained log at a WHOLE entry.
    expect(text.startsWith(kErrorLogEntryMarker), isTrue,
        reason: 'trim must align to an entry boundary, never mid-entry');
  });

  test('never throws: unwritable path is swallowed, read degrades to empty',
      () {
    // A directory where the log FILE should be → every write fails inside.
    final clash = Directory('${tmp.path}/error_log.txt')..createSync();
    final log = LocalErrorLog(file: File(clash.path));
    expect(() => log.record(StateError('boom'), StackTrace.current),
        returnsNormally);
    expect(log.readAll(), isEmpty);
  });

  test('installCrashBoundary wires FlutterError.onError to the injected log '
      'and preserves the previous handler', () async {
    final log = makeLog();
    var previousHandlerRan = false;
    final original = FlutterError.onError;
    FlutterError.onError = (details) => previousHandlerRan = true;

    await installCrashBoundary(log: log);
    FlutterError.reportError(
        FlutterErrorDetails(exception: StateError('boundary boom')));

    expect(log.readAll(), contains('boundary boom'));
    expect(previousHandlerRan, isTrue,
        reason: 'the boundary logs AND forwards — it never masks');

    FlutterError.onError = original;
  });
}
