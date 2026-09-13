/// A touch on her map sets no route point and clears none, and a route is set
/// only through a deliberate route act, closed on the IVI.
///
/// Why this test exists. Measured at bb02b98 in the real widget tree: a touch
/// on her map set route points, and one more touch after a route was set threw
/// it away, with no confirmation and no undo. That touch is also the gesture
/// ruled on 2026-09-13 to pause follow, so the gesture she uses to look around
/// could take her route away, found only downstream.
///
/// The rules tested here, as ruled 2026-09-14 (route setting by touch, and
/// the route section's title):
///
/// * A touch on her map sets no route point and clears none.
/// * On a phone with no motion signal (every phone state today: the platform's
///   speed is discarded), route setting is open only through a route act she
///   starts from a control, with ルートは停車中に設定できます。 beside it.
/// * On the IVI, with no vehicle signal, route setting is closed: the words
///   stand alone, and no line under the map says the route panel works.
/// * No sound and no haptic for a touch.
/// * Closing the act keeps the points she chose.
/// * The section title says ルート（雪を考慮しません）.
///
/// Not built, so not tested: closing an open act when motion is measured. The
/// app has no motion signal to measure it with.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

// Ruled bytes, 2026-09-14.
const _whenStoppedJa = 'ルートは停車中に設定できます。';
const _whenStoppedEn = 'Routes can be set when the car is stopped.';
const _titleJa = 'ルート（雪を考慮しません）';
const _titleEn = 'Route (does not consider snow)';
const _oldTitle = 'Route — tap A then B (driving, no snow-aware yet)';

const _routeClauseJa = 'ルート欄はタップで引き続き使えます。';
const _routeClauseEn = 'the route panel still works by tap';

/// A reason the app writes on a path it measured, whose line keeps its words
/// and so carries the route-panel sentence where route setting is open. (An
/// exception while starting no longer does: with no typed cause its line
/// names no cause and has no route sentence, ruled 2026-09-14.)
const _servicesOff = 'Location services disabled';

const _openAct = Key('route-act-open');
const _panelWords = Key('route-setting-when-stopped');

Future<FakeAlertActuators> _boot(
  WidgetTester tester, {
  String lang = 'ja',
  Stream<PositionFix> Function()? source,
}) async {
  final a = FakeAlertActuators();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: a,
    locale: Locale(lang),
    clock: () => DateTime.utc(2026, 1, 14, 21),
    jmaFetch: () async => const JmaFailure('no network in this test'),
    positionSource: source,
  ));
  await tester.pump();
  await tester.pump();
  return a;
}

/// A touch at [offset] from the centre of her map. flutter_map holds a tap
/// about 300 ms to tell it from a double tap, so the pump waits past that.
Future<void> _touchHerMap(WidgetTester tester, Offset offset) async {
  final map = find.byType(AkitaMap);
  await tester.ensureVisible(map);
  await tester.pump();
  await tester.tapAt(tester.getRect(map).center + offset);
  await tester.pump(const Duration(milliseconds: 350));
}

Finder _onHerMap(String letter) =>
    find.descendant(of: find.byType(AkitaMap), matching: find.text(letter));

Finder get _actMap => find.descendant(
    of: find.byType(Dialog), matching: find.byType(AkitaMap));

Future<void> _open(WidgetTester tester) async {
  expect(find.byKey(_openAct), findsOneWidget,
      reason: 'the route panel offers the route act');
  await tester.ensureVisible(find.byKey(_openAct));
  await tester.pump();
  await tester.tap(find.byKey(_openAct));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tapActMap(WidgetTester tester, Offset offset) async {
  await tester.tapAt(tester.getRect(_actMap).center + offset);
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('route-act-close')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

String? _line(WidgetTester tester) {
  final f = find.byKey(const Key('her-status-line'));
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

Future<void> _shareAndSend(WidgetTester tester,
    StreamController<PositionFix> positions, PositionFix event) async {
  final share = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(share);
  await tester.pump();
  await tester.tap(share);
  await tester.pump();
  positions.add(event);
  await tester.pump();
  await tester.pump();
}

Future<PositionFix> _refusal(WidgetTester tester) async =>
    (await tester.runAsync(() => herPositionStream(
          isServiceEnabled: () async => true,
          checkPermission: () async => LocationPermission.denied,
          requestPermission: () async => LocationPermission.denied,
        ).first))!;

void main() {
  group('a touch on her map sets no route point and clears none', () {
    testWidgets('two touches set no A and no B, ask nothing, and give nothing',
        (tester) async {
      final a = await _boot(tester);
      final givenBefore = '${a.spoken} ${a.haptics}';

      await _touchHerMap(tester, const Offset(-100, -40));
      await _touchHerMap(tester, const Offset(100, 40));
      // A route question waits out a 2 s store timeout before it shows.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));

      expect(_onHerMap('A'), findsNothing, reason: 'a touch set route start A');
      expect(_onHerMap('B'), findsNothing, reason: 'a touch set route end B');
      expect(find.byKey(const Key('route-consent-body')), findsNothing,
          reason: 'a touch raised the route question');
      expect('${a.spoken} ${a.haptics}', givenBefore,
          reason: 'no sound and no haptic for a touch');
    });

    testWidgets('A and B chosen in the route act stay after touches on her map',
        (tester) async {
      await _boot(tester);
      await _open(tester);
      await _tapActMap(tester, const Offset(-80, -30));
      await _tapActMap(tester, const Offset(80, 30));
      await _close(tester);
      expect(_onHerMap('A'), findsOneWidget, reason: 'precondition: A chosen');
      expect(_onHerMap('B'), findsOneWidget, reason: 'precondition: B chosen');
      // Where A sits on her map, not on the screen: bringing the map into
      // view scrolls the page.
      Offset aOnMap() =>
          tester.getRect(_onHerMap('A')).center -
          tester.getRect(find.byType(AkitaMap)).topLeft;
      final aAt = aOnMap();

      await _touchHerMap(tester, const Offset(0, 60));
      await _touchHerMap(tester, const Offset(-60, -60));

      expect(_onHerMap('A'), findsOneWidget, reason: 'a touch cleared A');
      expect(_onHerMap('B'), findsOneWidget, reason: 'a touch cleared B');
      expect(aOnMap(), aAt, reason: 'a touch moved A');
    });
  });

  group('on a phone with no motion signal: only through the route act', () {
    testWidgets(
        'the route card has the ruled title, the ruled words and the act; the '
        'act opens with the words', (tester) async {
      await _boot(tester);
      expect(find.text(_titleJa), findsOneWidget, reason: 'ruled title');
      expect(find.text(_oldTitle), findsNothing);
      final card =
          find.ancestor(of: find.text(_titleJa), matching: find.byType(Card));
      expect(
          find.descendant(of: card, matching: find.byKey(_panelWords)),
          findsOneWidget,
          reason: 'the words are beside the act');
      expect(tester.widget<Text>(find.byKey(_panelWords)).data, _whenStoppedJa);
      expect(find.descendant(of: card, matching: find.byKey(_openAct)),
          findsOneWidget);

      await _open(tester);
      expect(_actMap, findsOneWidget, reason: 'the act has its own map');
      expect(
          tester.widget<Text>(find.byKey(const Key('route-act-when-stopped'))).data,
          _whenStoppedJa);
    });

    testWidgets('English: the ruled title and words', (tester) async {
      await _boot(tester, lang: 'en');
      expect(find.text(_titleEn), findsOneWidget);
      expect(find.text(_oldTitle), findsNothing);
      expect(tester.widget<Text>(find.byKey(_panelWords)).data, _whenStoppedEn);
      await _open(tester);
      expect(
          tester.widget<Text>(find.byKey(const Key('route-act-when-stopped'))).data,
          _whenStoppedEn);
    });

    testWidgets(
        'in the act: A, then B; a further tap changes nothing; 選び直す clears '
        'both', (tester) async {
      await _boot(tester);
      await _open(tester);
      final getRoute = find.byKey(const Key('route-act-get-route'));
      bool enabled(Finder f) =>
          tester.widget<ButtonStyleButton>(f).onPressed != null;

      await _tapActMap(tester, const Offset(-80, -30));
      expect(find.descendant(of: _actMap, matching: find.text('A')),
          findsOneWidget);
      expect(find.descendant(of: _actMap, matching: find.text('B')),
          findsNothing);
      expect(enabled(getRoute), isFalse, reason: 'B not chosen yet');

      await _tapActMap(tester, const Offset(80, 30));
      expect(find.descendant(of: _actMap, matching: find.text('B')),
          findsOneWidget);
      expect(enabled(getRoute), isTrue);
      final aAt = tester
          .getRect(find.descendant(of: _actMap, matching: find.text('A')))
          .center;
      final bAt = tester
          .getRect(find.descendant(of: _actMap, matching: find.text('B')))
          .center;

      await _tapActMap(tester, const Offset(0, 70));
      expect(
          tester
              .getRect(find.descendant(of: _actMap, matching: find.text('A')))
              .center,
          aAt,
          reason: 'a third tap moved A');
      expect(
          tester
              .getRect(find.descendant(of: _actMap, matching: find.text('B')))
              .center,
          bAt,
          reason: 'a third tap moved B');
      expect(find.byKey(const Key('route-consent-body')), findsNothing,
          reason: 'nothing is fetched by a tap');

      await tester.tap(find.byKey(const Key('route-act-choose-again')));
      await tester.pump();
      expect(find.descendant(of: _actMap, matching: find.text('A')),
          findsNothing);
      expect(find.descendant(of: _actMap, matching: find.text('B')),
          findsNothing);
      expect(enabled(getRoute), isFalse);
    });

    testWidgets('closing the act keeps the point chosen; reopened, it resumes',
        (tester) async {
      await _boot(tester);
      await _open(tester);
      await _tapActMap(tester, const Offset(-80, -30));
      await _close(tester);

      expect(find.byType(Dialog), findsNothing);
      expect(_onHerMap('A'), findsOneWidget,
          reason: 'her map shows the start she chose');
      expect(_onHerMap('B'), findsNothing);

      await _open(tester);
      expect(find.descendant(of: _actMap, matching: find.text('A')),
          findsOneWidget,
          reason: 'the act resumes where she left off');
      await _tapActMap(tester, const Offset(80, 30));
      expect(find.descendant(of: _actMap, matching: find.text('B')),
          findsOneWidget);
    });

    testWidgets(
        'CONTROL: on the phone the lines under the map still say the route '
        'panel works', (tester) async {
      final positions = StreamController<PositionFix>.broadcast();
      await _boot(tester, source: () => positions.stream);
      await _shareAndSend(
          tester, positions, const PositionUnavailable(_servicesOff));
      expect(_line(tester), contains(_routeClauseJa));

      final refusalPositions = StreamController<PositionFix>.broadcast();
      await _boot(tester, source: () => refusalPositions.stream);
      await _shareAndSend(tester, refusalPositions, await _refusal(tester));
      expect(_line(tester), contains('位置情報オフ'),
          reason: 'precondition: refusal');
      expect(_line(tester), contains(_routeClauseJa));
      await positions.close();
      await refusalPositions.close();
    });
  });

  group('on the IVI, with no vehicle signal: route setting is closed', () {
    final ivi = TargetPlatformVariant.only(TargetPlatform.linux);

    testWidgets('the ruled words stand alone: no route act, and touches set '
        'nothing', (tester) async {
      final a = await _boot(tester);
      final givenBefore = '${a.spoken} ${a.haptics}';
      expect(find.text(_titleJa), findsOneWidget);
      expect(find.byKey(_panelWords), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(_panelWords)).data, _whenStoppedJa);
      expect(find.byKey(_openAct), findsNothing,
          reason: 'no route act where route setting is closed');

      await _touchHerMap(tester, const Offset(-100, -40));
      await _touchHerMap(tester, const Offset(100, 40));
      await tester.pump(const Duration(seconds: 3));
      expect(_onHerMap('A'), findsNothing);
      expect(_onHerMap('B'), findsNothing);
      expect('${a.spoken} ${a.haptics}', givenBefore,
          reason: 'the words only: no sound, no haptic');
    }, variant: ivi);

    testWidgets('no line under the map says the route panel works',
        (tester) async {
      final positions = StreamController<PositionFix>.broadcast();
      await _boot(tester, source: () => positions.stream);
      await _shareAndSend(
          tester, positions, const PositionUnavailable(_servicesOff));
      final unavailable = _line(tester);
      expect(unavailable, contains('地図は表示されたままです。'),
          reason: 'precondition: the unavailable line');
      expect(unavailable, isNot(contains('ルート欄')));

      final refusalPositions = StreamController<PositionFix>.broadcast();
      await _boot(tester, source: () => refusalPositions.stream);
      await _shareAndSend(tester, refusalPositions, await _refusal(tester));
      final refused = _line(tester);
      expect(refused, contains('位置情報オフ'), reason: 'precondition: refusal');
      expect(refused, contains('地図は表示されたままです。'));
      expect(refused, isNot(contains('ルート欄')));

      final enPositions = StreamController<PositionFix>.broadcast();
      await _boot(tester, lang: 'en', source: () => enPositions.stream);
      await _shareAndSend(tester, enPositions, await _refusal(tester));
      final refusedEn = _line(tester);
      expect(refusedEn, contains('No location access'),
          reason: 'precondition: English refusal');
      expect(refusedEn, contains('The map remains.'));
      expect(refusedEn, isNot(contains(_routeClauseEn)));
      await positions.close();
      await refusalPositions.close();
      await enPositions.close();
    }, variant: ivi);
  });
}
