/// Code 15's record: ONE clock for every kind, and the alive timer read from
/// its named constants, so the reading's bound is read from source and never
/// retyped.
///
/// Why, written before the act (2026-10-10). The binding bars for this reading
/// (section 16, items 3 and 4) require: every line that carries a share's t
/// takes it as code 13's fix lines did, the page's clock minus the share's
/// subscription time; a monotonic stopwatch for any kind is refused (a clock
/// that stops while the phone sleeps would shorten every interval across a
/// sleep); and the alive threshold and period are named constants, because the
/// bound B is computed from them. A behavioural test cannot see a retyped
/// `6000` that happens to equal the constant today, nor a second clock that
/// agrees with the first in a test binding. This reads the source.
///
/// HONEST BOUND. A grep over source text, not a call graph.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _code(String path) => File(path)
    .readAsStringSync()
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((l) {
      final t = l.trimLeft();
      if (t.startsWith('///') || t.startsWith('//')) return '';
      final i = l.indexOf('//');
      return i >= 0 ? l.substring(0, i) : l;
    })
    .join('\n');

const _recorder = 'lib/services/code15_fix_interval_record.dart';

/// The body of a method declared `<ret> <name>(...) {` at two-space indent.
String _body(String code, String signature) {
  final i = code.indexOf(signature);
  expect(i, isNot(-1), reason: '$signature not found');
  // The body opens after the parameter list closes.
  final open = code.indexOf(') {\n', i);
  final end = code.indexOf('\n  }\n', open);
  return code.substring(i, end);
}

void main() {
  final main = _code('lib/main.dart');
  final recorder = _code(_recorder);

  test('the alive timer runs on kCode15AliveTimerPeriod, in one place', () {
    expect(
      RegExp(r'Timer\.periodic\(kCode15AliveTimerPeriod,').allMatches(main).length,
      1,
    );
    final start = _body(main, 'void _code15ShareSubscribed() {');
    expect(start, contains('Timer.periodic(kCode15AliveTimerPeriod,'));
    expect(start, isNot(matches(RegExp(r'Duration\(\s*(milli)?seconds:'))),
        reason: 'the period retyped');
  });

  test('the threshold is kCode15AliveThreshold, read in recordAliveIfQuiet, '
      'and no number stands in for it', () {
    final alive = _body(recorder, 'bool recordAliveIfQuiet({');
    expect(alive, contains('kCode15AliveThreshold.inMilliseconds'));
    expect(alive, isNot(matches(RegExp(r'\b[1-9]\d{2,}\b'))),
        reason: 'a millisecond literal in the alive rule');
  });

  test('every code 15 writer in main.dart takes t from _now() minus '
      '_herPositionStreamSubscribedAt; no stopwatch, no second clock', () {
    final shareT = _body(main, 'int? _code15ShareT() {');
    expect(shareT, contains('_now().difference(since).inMilliseconds'));
    expect(shareT, contains('final since = _herPositionStreamSubscribedAt;'));
    final event = _body(main, 'void _code15RecordEvent(');
    expect(event, contains('final now = _now();'));
    expect(event, contains('final since = _herPositionStreamSubscribedAt;'));
    expect(event, contains('msSinceStreamStart: now.difference(since).inMilliseconds'));
    for (final sig in [
      'void _code15AliveTick() {',
      'void _code15RecordLifecycle(',
      'void _clearPositionAtHisTap() {',
      'void _endShareWithoutServiceAway() {',
    ]) {
      expect(_body(main, sig), contains('_code15ShareT()'), reason: sig);
    }
    final block = main.substring(
      main.indexOf('Timer? _code15AliveTicker;'),
      main.indexOf('void _clearPositionAtHisTap() {'),
    );
    // The record object's writes take t as given and read no clock of their
    // own (the share's export time, outside it, is the one disclosed time).
    final record = recorder.substring(
      recorder.indexOf('class Code15FixIntervalRecord {'),
      recorder.indexOf('class Code15MinimumCount {'),
    );
    for (final clock in ['Stopwatch', 'DateTime.now', 'elapsed', 'clock.now']) {
      expect(block, isNot(contains(clock)), reason: clock);
      expect(record, isNot(contains(clock)), reason: '$clock in the record');
    }
  });

  test('the page clock is the one code 13 used: the injected clock, else '
      'DateTime.now', () {
    expect(main, contains('DateTime _now() => (widget.clock ?? DateTime.now)();'));
  });
}
