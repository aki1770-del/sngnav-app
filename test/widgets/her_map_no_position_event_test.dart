/// She shares, and no position event ever arrives. The map must not stay
/// silent.
///
/// Why this test exists. Rendered 2026-09-13 from the real app: ten minutes
/// after sharing with no event, the map had no words and was 0.000% different
/// from the map of a driver who never shared, under a line still reading
/// 「現在地を取得しています…」. A platform stream that subscribes and never
/// delivers (no sky, a head unit with no receiver, a source that stalls) looks
/// exactly like that. An empty map can be read as nothing to worry about.
///
/// Two causes. The blackout watchdog never polls before a first event, on
/// purpose: before one, the permission dialog may still be on screen. And the
/// stream has no first-fix timeout.
///
/// The rule tested here. While the position stream can still be waiting on
/// the platform's answers or on her permission dialog, the map and the line
/// stay as they are. The real stream bounds that wait by its own timeouts:
/// two platform reads of 10 s each and a permission request of 2 minutes,
/// 140 s in all. Past that, a stream that has said nothing is not waiting on
/// her, and the map says 現在地不明 with the line under it saying her position
/// is unknown and there is no last position. No new sentence: both are the
/// app's existing words for a position that is unknown with no trusted fix.
///
/// The watchdog ticks every 15 s and reads the app's clock, so the words
/// arrive on the first tick at or past 140 s: 150 s here.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

const _unknownWords = ValueKey('her-position-unknown-label');
const _locationOffWords = ValueKey('her-location-off-label');
const _statusKey = Key('her-status-line');
const _marks = [
  ValueKey('her-dot-real-fix'),
  ValueKey('her-dot-degraded'),
  ValueKey('her-dot-mock'),
];

var _clockNow = DateTime.utc(2026, 1, 14, 21);

/// Advance the app clock and fake time together, one watchdog tick at a time.
Future<void> _advance(WidgetTester tester, Duration d) async {
  var left = d;
  while (left > Duration.zero) {
    final step =
        left < const Duration(seconds: 15) ? left : const Duration(seconds: 15);
    _clockNow = _clockNow.add(step);
    await tester.pump(step);
    left -= step;
  }
  await tester.pump();
}

Future<StreamController<PositionFix>> _bootAndShare(
  WidgetTester tester, {
  String lang = 'ja',
}) async {
  _clockNow = DateTime.utc(2026, 1, 14, 21);
  final positions = StreamController<PositionFix>.broadcast();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: FakeAlertActuators(),
    locale: Locale(lang),
    clock: () => _clockNow,
    jmaFetch: () async => const JmaFailure('no network in this test'),
    positionSource: () => positions.stream,
  ));
  await tester.pump();
  await tester.pump();
  await _tapShare(tester);
  return positions;
}

Future<void> _tapShare(WidgetTester tester) async {
  final b = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(b);
  await tester.pump();
  await tester.tap(b);
  await tester.pump();
  await tester.pump();
}

String? _status(WidgetTester tester) {
  final f = find.byKey(_statusKey);
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

bool _anyMark() => _marks.any((k) => find.byKey(k).evaluate().isNotEmpty);

void main() {
  group('shared, and no position event arrives', () {
    testWidgets(
        'ten minutes on, the map says 現在地不明 and the line no longer says '
        'it is locating', (tester) async {
      final positions = await _bootAndShare(tester);
      await _advance(tester, const Duration(minutes: 10));

      expect(find.byKey(_unknownWords), findsOneWidget,
          reason: 'the map is silent: ${_status(tester)}');
      expect(_status(tester), '現在地 不明 · 最後の位置 なし');
      expect(_anyMark(), isFalse, reason: 'no position exists to mark');
      await positions.close();
    });

    testWidgets('in English: "Position unknown", and the matching line',
        (tester) async {
      final positions = await _bootAndShare(tester, lang: 'en');
      await _advance(tester, const Duration(minutes: 10));

      expect(find.byKey(_unknownWords), findsOneWidget);
      expect(find.text('Position unknown'), findsOneWidget);
      expect(_status(tester), 'Position unknown · no last position');
      await positions.close();
    });

    testWidgets(
        'at 150 s, the first watchdog tick past the 140 s the real stream can '
        'spend waiting on the platform and on her dialog, the words are there',
        (tester) async {
      final positions = await _bootAndShare(tester);
      await _advance(tester, const Duration(seconds: 150));
      expect(find.byKey(_unknownWords), findsOneWidget);
      await positions.close();
    });

    testWidgets(
        'CONTROL: at 135 s the permission dialog may still be on screen, so '
        'the map has no words and the line still says it is locating',
        (tester) async {
      final positions = await _bootAndShare(tester);
      await _advance(tester, const Duration(seconds: 135));
      expect(find.byKey(_unknownWords), findsNothing);
      expect(_status(tester), '現在地を取得しています…');
      await positions.close();
    });

    testWidgets('a first fix after the words: her dot is drawn and the words go',
        (tester) async {
      final positions = await _bootAndShare(tester);
      await _advance(tester, const Duration(minutes: 10));
      expect(find.byKey(_unknownWords), findsOneWidget,
          reason: 'precondition: the words were shown');

      positions.add(PositionAvailable(
        latitude: 39.7167,
        longitude: 140.0983,
        accuracyMeters: 15,
        timestamp: _clockNow,
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('her-dot-real-fix')), findsOneWidget);
      expect(find.byKey(_unknownWords), findsNothing);
      expect(_status(tester), '現在地 · ±15 m');
      await positions.close();
    });

    testWidgets('Stop, then share again: the wait starts over', (tester) async {
      final positions = await _bootAndShare(tester);
      await _advance(tester, const Duration(minutes: 10));
      expect(find.byKey(_unknownWords), findsOneWidget,
          reason: 'precondition: the words were shown');

      final stop = find.widgetWithText(TextButton, '停止');
      await tester.ensureVisible(stop);
      await tester.pump();
      await tester.tap(stop);
      await tester.pump();
      expect(find.byKey(_unknownWords), findsNothing,
          reason: 'not sharing: nothing to say about her position');

      await _tapShare(tester);
      await _advance(tester, const Duration(seconds: 30));
      expect(find.byKey(_unknownWords), findsNothing);
      expect(_status(tester), '現在地を取得しています…');
      await positions.close();
    });

    testWidgets(
        'CONTROL: a location refusal still says 位置情報オフ, not 現在地不明, '
        'however long it stands', (tester) async {
      final positions = await _bootAndShare(tester);
      final refusal = await tester.runAsync(() => herPositionStream(
            isServiceEnabled: () async => true,
            checkPermission: () async => LocationPermission.denied,
            requestPermission: () async => LocationPermission.denied,
          ).first);
      positions.add(refusal!);
      await tester.pump();
      await tester.pump();
      await _advance(tester, const Duration(minutes: 10));

      expect(find.byKey(_locationOffWords), findsOneWidget);
      expect(find.byKey(_unknownWords), findsNothing);
      await positions.close();
    });
  });
}
