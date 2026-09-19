/// A route fetched through the route act, rendered in the real app: it stays
/// when her map is touched.
///
/// Why this test exists. Until 2026-09-14 no test path could give the app a
/// route: the router was built inside the fetch, and the test binding answers
/// every HTTP request with 400. So no test ever rendered a route result, and
/// the decision that a touch on her map clears no route could not be held for a
/// fetched one. The app now takes an injected routing engine; production still
/// builds the OSRM demo engine.
///
/// The rules tested here (decided 2026-09-14):
///
/// * A touch on her map clears no route, including a fetched one, and fetches
///   nothing.
/// * Before any route, the maneuver panel names no gesture on the map.
/// * The page footer makes no promise about snow ("yet").
/// * A failed request says the app's own words and nothing after them: no
///   server reply, no exception, no address with her chosen points (decided
///   2026-09-14).
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show PolylineLayer;
import 'package:flutter_test/flutter_test.dart';
import 'package:routing_engine/routing_engine.dart' as re;
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

class _FakeEngine implements re.RoutingEngine {
  _FakeEngine({this.fail = false, this.error = const re.RoutingException('HTTP 503')});
  final bool fail;

  /// What a failed request throws: the router's own exception, or anything
  /// else the app wraps itself.
  final Object error;
  var requests = 0;

  @override
  Future<re.RouteResult> calculateRoute(re.RouteRequest request) async {
    requests++;
    if (fail) throw error;
    return re.RouteResult(
      shape: [request.origin, request.destination],
      maneuvers: const [],
      totalDistanceKm: 12.34,
      totalTimeSeconds: 1500,
      summary: 'fake',
      engineInfo: const re.EngineInfo(name: 'mock'),
    );
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  re.EngineInfo get info => const re.EngineInfo(name: 'mock');

  @override
  Future<void> dispose() async {}
}

Future<_FakeEngine> _boot(WidgetTester tester,
    {String lang = 'ja',
    bool fail = false,
    Object error = const re.RoutingException('HTTP 503')}) async {
  final engine = _FakeEngine(fail: fail, error: error);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: FakeAlertActuators(),
    locale: Locale(lang),
    clock: () => DateTime.utc(2026, 1, 14, 21),
    jmaFetch: () async => const JmaFailure('no network in this test'),
    routingEngineFactory: () => engine,
  ));
  await tester.pump();
  await tester.pump();
  return engine;
}

/// Opens the act, chooses A and B, asks for the route and accepts the send.
Future<void> _fetchThroughAct(WidgetTester tester) async {
  final open = find.byKey(const Key('route-act-open'));
  await tester.ensureVisible(open);
  await tester.pump();
  await tester.tap(open);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  final actMap =
      find.descendant(of: find.byType(Dialog), matching: find.byType(AkitaMap));
  final r = tester.getRect(actMap);
  await tester.tapAt(r.center + const Offset(-80, -30));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tapAt(r.center + const Offset(80, 30));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(find.byKey(const Key('route-act-get-route')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  // The consent question waits out a 2 s store timeout.
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byKey(const Key('route-consent-accept')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 1));
}

/// The consent answer is persisted fire-and-forget behind a 2 s timeout.
Future<void> _drain(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 3));

void main() {
  testWidgets('a fetched route stays after touches on her map', (tester) async {
    final engine = await _boot(tester);
    await _fetchThroughAct(tester);
    expect(engine.requests, 1, reason: 'precondition: one fetch');
    expect(find.byKey(const Key('route-summary')), findsOneWidget,
        reason: 'precondition: the route is shown');
    final herMap = find.byType(AkitaMap);
    Finder onHerMap(Finder f) => find.descendant(of: herMap, matching: f);
    expect(onHerMap(find.text('A')), findsOneWidget);
    expect(onHerMap(find.byType(PolylineLayer)), findsOneWidget);

    await tester.ensureVisible(herMap);
    await tester.pump();
    final r = tester.getRect(herMap);
    await tester.tapAt(r.center + const Offset(0, 60));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tapAt(r.center + const Offset(-60, -60));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const Key('route-summary')), findsOneWidget,
        reason: 'a touch threw the route away');
    expect(onHerMap(find.text('A')), findsOneWidget);
    expect(onHerMap(find.text('B')), findsOneWidget);
    expect(onHerMap(find.byType(PolylineLayer)), findsOneWidget);
    expect(engine.requests, 1, reason: 'a touch fetched again');
    await _drain(tester);
  });

  testWidgets('before any route, the maneuver panel names no gesture on the '
      'map, in either locale', (tester) async {
    for (final lang in const ['ja', 'en']) {
      await _boot(tester, lang: lang);
      final line = find.byKey(const Key('maneuver-placeholder'));
      expect(line, findsOneWidget, reason: lang);
      expect(tester.widget<Text>(line).data, isNot(contains('Tap A then B')),
          reason: lang);
    }
  });

  testWidgets('the page footer promises nothing about snow', (tester) async {
    await _boot(tester);
    expect(find.textContaining('snow-aware yet'), findsNothing);
  });

  // The route panel's words follow the app's locale. Found at bb02b98 in the
  // real widget tree: they were English literals in Japanese mode. English
  // keeps its bytes; the Japanese is new and unruled.
  group('the route panel follows the locale', () {
    Finder inRouteCard(Finder f) =>
        find.descendant(of: find.byKey(const Key('route-panel')), matching: f);

    testWidgets('Japanese: no English left in the route card', (tester) async {
      await _boot(tester);
      await _fetchThroughAct(tester);
      expect(find.byKey(const Key('route-summary')), findsOneWidget,
          reason: 'precondition: a route is shown');
      for (final english in const [
        'Distance',
        'Duration',
        'min',
        'Source: OSRM',
        'NOT snow-aware',
        'NOT for production',
        'Reset',
      ]) {
        expect(inRouteCard(find.textContaining(english)), findsNothing,
            reason: english);
      }
      expect(inRouteCard(find.text('距離:')), findsOneWidget);
      expect(inRouteCard(find.text('12.3 km')), findsOneWidget);
      expect(inRouteCard(find.text('所要時間:')), findsOneWidget);
      expect(inRouteCard(find.text('25分')), findsOneWidget);
      expect(
          tester.widget<Text>(find.byKey(const Key('maneuver-placeholder'))).data,
          isNot(contains('No turn-by-turn')));
      await _drain(tester);
    });

    testWidgets('English keeps its bytes', (tester) async {
      await _boot(tester, lang: 'en');
      await _fetchThroughAct(tester);
      expect(inRouteCard(find.text('Distance:')), findsOneWidget);
      expect(inRouteCard(find.text('12.3 km')), findsOneWidget);
      expect(inRouteCard(find.text('Duration:')), findsOneWidget);
      expect(inRouteCard(find.text('25 min')), findsOneWidget);
      expect(
          inRouteCard(find.text('Source: OSRM public demo '
              '(router.project-osrm.org). NOT snow-aware. NOT for production '
              'navigation.')),
          findsOneWidget);
      expect(inRouteCard(find.text('Reset')), findsOneWidget);
      expect(
          tester.widget<Text>(find.byKey(const Key('maneuver-placeholder'))).data,
          'No turn-by-turn maneuvers in this route.');
      await _drain(tester);
    });

    testWidgets('Japanese: a failed fetch is said in Japanese', (tester) async {
      await _boot(tester, fail: true);
      await _fetchThroughAct(tester);
      final failed = find.byKey(const Key('route-fetch-failed'));
      expect(failed, findsOneWidget, reason: 'precondition: the fetch failed');
      expect(
          find.descendant(
              of: failed, matching: find.textContaining('Route fetch failed')),
          findsNothing);
      // Ruled 2026-09-14: the app's own words, closed, and nothing after them.
      expect(
          find.descendant(
              of: failed, matching: find.text('ルートを取得できませんでした。')),
          findsOneWidget);
      expect(find.textContaining('HTTP 503'), findsNothing);
      await _drain(tester);
    });

    testWidgets('English: a failed fetch says the app\'s own words and nothing '
        'after them', (tester) async {
      await _boot(tester, lang: 'en', fail: true);
      await _fetchThroughAct(tester);
      expect(
          find.descendant(
              of: find.byKey(const Key('route-fetch-failed')),
              matching: find.text('Route fetch failed.')),
          findsOneWidget);
      expect(find.textContaining('HTTP 503'), findsNothing);
      await _drain(tester);
    });

    // A reason carrying a marker, as the real router's reasons carry a
    // server's reply or a request address holding both chosen points. The
    // marker must reach no widget, in either language, whether the router
    // threw its own exception or the app wrapped another one.
    const marker = 'MARKER-5c1e';
    const address = 'uri=https://router.example/route/v1/driving/'
        '140.10000,39.70000;140.20000,39.80000';
    for (final lang in const ['ja', 'en']) {
      for (final error in <Object>[
        const re.RoutingException('OSRM network error: $marker $address'),
        StateError('$marker $address'),
      ]) {
        testWidgets('$lang: no part of a failure\'s reason reaches the screen '
            '(${error.runtimeType})', (tester) async {
          final semantics = tester.ensureSemantics();
          await _boot(tester, lang: lang, fail: true, error: error);
          await _fetchThroughAct(tester);
          expect(find.byKey(const Key('route-fetch-failed')), findsOneWidget,
              reason: 'precondition: the fetch failed');
          expect(find.textContaining(marker), findsNothing);
          expect(find.textContaining('140.10000'), findsNothing);
          expect(find.textContaining('router.example'), findsNothing);
          // Nor what a screen reader is given (nowhere in the tree).
          expect(find.bySemanticsLabel(RegExp(marker)), findsNothing);
          expect(find.bySemanticsLabel(RegExp('140\\.10000')), findsNothing);
          expect(
              find.bySemanticsLabel(
                  RegExp(lang == 'ja' ? 'ルートを取得できませんでした' : 'Route fetch failed')),
              findsWidgets,
              reason: 'control: the semantics tree is read, and it holds the '
                  'failure words');
          await _drain(tester);
          semantics.dispose();
        });
      }
    }
  });
}
