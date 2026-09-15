/// She shares, the platform stream subscribes, and no position event ever
/// arrives. The map must not stay silent, and must not alarm.
///
/// Why this test exists. Rendered 2026-09-13 from the real app: ten minutes
/// after sharing with no event, the map had no words and was 0.000% different
/// from the map of a driver who never shared, under a line still reading
/// 「現在地を取得しています…」. A platform stream that subscribes and never
/// delivers looks exactly like that, and an empty map can be read as nothing
/// to worry about.
///
/// The rule tested here is the one ruled 2026-09-14, with existing strings
/// only:
///
/// * Phase 1, from the subscription until 60 s with no event: the line says
///   現在地を取得しています… / "Locating you…", the map has no mark and no
///   words, the row offers 停止 / Stop.
/// * Phase 2, no event 60 s after the subscription: the map says 現在地不明 /
///   "Position unknown", the line says 現在地 不明 · 最後の位置 なし /
///   "Position unknown · no last position", the row offers 停止 / Stop. The
///   words change by 75 s at the latest (one 15 s watchdog tick).
/// * The clock starts when the platform stream is subscribed, after the
///   permission answer, never at the tap: time on the dialog is hers.
/// * Cleared by any position event, by 停止, and by a new share.
/// * A screen reader hears phase 2 once, as a live region.
/// * Nothing alarms: no voice, no haptic, no caution rung, exactly as for a
///   driver who never shared.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';
import '../support/rung_on_card.dart';

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

Future<FakeAlertActuators> _boot(
  WidgetTester tester, {
  Stream<PositionFix> Function()? source,
  String lang = 'ja',
}) async {
  _clockNow = DateTime.utc(2026, 1, 14, 21);
  final a = FakeAlertActuators();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: a,
    locale: Locale(lang),
    clock: () => _clockNow,
    jmaFetch: () async => const JmaFailure('no network in this test'),
    positionSource: source,
  ));
  await tester.pump();
  await tester.pump();
  return a;
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

bool _rowOffers(String label) =>
    find.widgetWithText(TextButton, label).evaluate().isNotEmpty;

void _expectPhase1(WidgetTester tester, String when) {
  expect(_status(tester), '現在地を取得しています…', reason: when);
  expect(find.byKey(_unknownWords), findsNothing, reason: when);
  expect(_anyMark(), isFalse, reason: when);
  expect(_rowOffers('停止'), isTrue, reason: when);
}

void _expectPhase2(WidgetTester tester, String when) {
  expect(find.byKey(_unknownWords), findsOneWidget,
      reason: '$when: the map is silent, line 「${_status(tester)}」');
  expect(find.text('現在地不明'), findsOneWidget, reason: when);
  expect(_status(tester), '現在地 不明 · 最後の位置 なし', reason: when);
  expect(_anyMark(), isFalse, reason: '$when: no position exists to mark');
  expect(_rowOffers('停止'), isTrue, reason: when);
  expect(find.textContaining('取得しています'), findsNothing,
      reason: '$when: no promise after 60 s');
  expect(find.textContaining('GPS を取得できません'), findsNothing,
      reason: '$when: no cause the app has not measured');
  expect(find.byKey(_locationOffWords), findsNothing,
      reason: '$when: permission was granted');
}

/// What she is given: every spoken line, every haptic, and every caution
/// headline the card can show.
String _given(WidgetTester tester, FakeAlertActuators a) {
  // The rung from the caution banner's own headline (2026-09-15), not every
  // text on the screen that names a rung.
  final rungs = [if (rungOnCard() case final rung?) rung.name];
  return 'spoken [${a.spoken.join(' | ')}] haptics [${a.haptics.join(' | ')}] '
      'rungs [${rungs.join(' | ')}]';
}

/// Semantics nodes, anywhere in the tree, that are live regions and whose
/// label carries [text]. The same measure as the refusal's live-region test.
int _liveRegionsSaying(WidgetTester tester, String text) {
  var node = tester.getSemantics(find.byType(Scaffold));
  while (node.parent != null) {
    node = node.parent!;
  }
  var n = 0;
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.flagsCollection.isLiveRegion && data.label.contains(text)) n++;
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(node);
  return n;
}

void main() {
  group('an injected stream that never emits (subscribed when the app listens)',
      () {
    testWidgets('phase 1 at 45 s; phase 2 by 75 s; still phase 2 at 10 min',
        (tester) async {
      final positions = StreamController<PositionFix>.broadcast();
      await _boot(tester, source: () => positions.stream);
      await _tapShare(tester);

      await _advance(tester, const Duration(seconds: 45));
      _expectPhase1(tester, 'at 45 s');

      await _advance(tester, const Duration(seconds: 30));
      _expectPhase2(tester, 'at 75 s');

      await _advance(tester, const Duration(minutes: 9));
      _expectPhase2(tester, 'at 10 min');
      await positions.close();
    });

    testWidgets('in English: "Position unknown", and the matching line',
        (tester) async {
      final positions = StreamController<PositionFix>.broadcast();
      await _boot(tester, source: () => positions.stream, lang: 'en');
      await _tapShare(tester);
      await _advance(tester, const Duration(seconds: 45));
      expect(_status(tester), 'Locating you…', reason: 'phase 1, English');
      expect(find.text('Position unknown'), findsNothing);

      await _advance(tester, const Duration(seconds: 30));
      expect(find.text('Position unknown'), findsOneWidget);
      expect(_status(tester), 'Position unknown · no last position');
      expect(_rowOffers('Stop'), isTrue);
      await positions.close();
    });

    testWidgets('a screen reader hears phase 2 once, as a live region',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final positions = StreamController<PositionFix>.broadcast();
      await _boot(tester, source: () => positions.stream);
      await _tapShare(tester);
      await _advance(tester, const Duration(seconds: 45));
      expect(_liveRegionsSaying(tester, '現在地不明'), 0, reason: 'phase 1');

      await _advance(tester, const Duration(seconds: 30));
      expect(find.byKey(_unknownWords), findsOneWidget,
          reason: 'precondition: phase 2');
      expect(_liveRegionsSaying(tester, '現在地不明'), 1,
          reason: 'exactly one live region carries the words');
      await positions.close();
      semantics.dispose();
    });

    testWidgets('a first fix after the words: her dot is drawn and the words go',
        (tester) async {
      final positions = StreamController<PositionFix>.broadcast();
      await _boot(tester, source: () => positions.stream);
      await _tapShare(tester);
      await _advance(tester, const Duration(seconds: 75));
      _expectPhase2(tester, 'precondition');

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

    testWidgets('停止, then share again: the clock restarts at the new '
        'subscription', (tester) async {
      final positions = StreamController<PositionFix>.broadcast();
      await _boot(tester, source: () => positions.stream);
      await _tapShare(tester);
      await _advance(tester, const Duration(seconds: 75));
      _expectPhase2(tester, 'precondition');

      final stop = find.widgetWithText(TextButton, '停止');
      await tester.ensureVisible(stop);
      await tester.pump();
      await tester.tap(stop);
      await tester.pump();
      expect(find.byKey(_unknownWords), findsNothing,
          reason: 'not sharing: nothing to say about her position');

      await _tapShare(tester);
      await _advance(tester, const Duration(seconds: 45));
      _expectPhase1(tester, '45 s after the new share');
      await positions.close();
    });

    testWidgets(
        'nothing alarms: at 10 min she is given exactly what a driver who '
        'never shared is given', (tester) async {
      var a = await _boot(tester);
      await _advance(tester, const Duration(minutes: 10));
      final neverShared = _given(tester, a);

      final positions = StreamController<PositionFix>.broadcast();
      a = await _boot(tester, source: () => positions.stream);
      await _tapShare(tester);
      await _advance(tester, const Duration(minutes: 10));
      expect(find.byKey(_statusKey), findsOneWidget,
          reason: 'precondition: she is sharing');

      expect(_given(tester, a), neverShared);
      await positions.close();
    });

    testWidgets(
        'CONTROL: a location refusal still says 位置情報オフ, not 現在地不明, '
        'however long it stands', (tester) async {
      final positions = StreamController<PositionFix>.broadcast();
      await _boot(tester, source: () => positions.stream);
      await _tapShare(tester);
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

  group('the app\'s own position stream, through the platform channels', () {
    const method = MethodChannel('flutter.baseflow.com/geolocator');
    const updates = EventChannel('flutter.baseflow.com/geolocator_updates');
    TestDefaultBinaryMessenger messenger() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger().setMockMethodCallHandler(method, null);
      messenger().setMockStreamHandler(updates, null);
    });

    testWidgets(
        'the clock starts at the subscription, never at the tap: 50 s on the '
        'permission dialog do not count', (tester) async {
      var listened = false;
      messenger().setMockMethodCallHandler(method, (call) async {
        switch (call.method) {
          case 'isLocationServiceEnabled':
            return true;
          case 'checkPermission':
            return 0; // denied: the app asks
          case 'requestPermission':
            // She reads the dialog for 50 s, then allows while in use.
            await Future<void>.delayed(const Duration(seconds: 50));
            return 2;
        }
        return null;
      });
      messenger().setMockStreamHandler(
        updates,
        MockStreamHandler.inline(onListen: (_, _) => listened = true),
      );

      await _boot(tester); // no injected source: the app's own stream
      await _tapShare(tester);

      await _advance(tester, const Duration(seconds: 45));
      expect(listened, isFalse, reason: 'still on the dialog at 45 s');
      _expectPhase1(tester, '45 s after the tap, on the dialog');

      await _advance(tester, const Duration(seconds: 30));
      expect(listened, isTrue,
          reason: 'precondition: the platform stream is subscribed');
      _expectPhase1(tester,
          '75 s after the tap, under 60 s since the subscription: a clock '
          'started at the tap would already have changed the words');

      await _advance(tester, const Duration(seconds: 30));
      _expectPhase1(tester, '105 s after the tap, under 60 s since the subscription');

      await _advance(tester, const Duration(seconds: 30));
      _expectPhase2(
          tester, '135 s after the tap, within 75 s of the subscription');
    });
  });
}
