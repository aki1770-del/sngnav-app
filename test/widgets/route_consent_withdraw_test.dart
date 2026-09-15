/// After she agrees to send her route points, she can take the yes back.
///
/// Why this test exists. Until 2026-09-16 the routing choice was written in
/// three places only (the dialog's answer, and the re-ask after a no), and the
/// control that asks again, 選択を変更 / "Change choice", was drawn only after a
/// no. A remembered yes could not be changed anywhere in the app, while the
/// consent text said the choice could be changed later.
///
/// The rules tested here:
///
/// * After a yes, 選択を変更 is in the route panel.
/// * Pressing it asks the question again; a no shows the declined state.
/// * After she withdraws, asking for the route sends nothing.
/// * The consent text says where the choice is changed, in both languages.
///
/// Test binding only: no device, no real send (the routing engine is a fake
/// that counts requests).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routing_engine/routing_engine.dart' as re;
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

class _CountingEngine implements re.RoutingEngine {
  var requests = 0;

  @override
  Future<re.RouteResult> calculateRoute(re.RouteRequest request) async {
    requests++;
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

Future<_CountingEngine> _boot(WidgetTester tester) async {
  final engine = _CountingEngine();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: FakeAlertActuators(),
    locale: const Locale('ja'),
    clock: () => DateTime.utc(2026, 1, 14, 21),
    jmaFetch: () async => const JmaFailure('no network in this test'),
    routingEngineFactory: () => engine,
  ));
  await tester.pump();
  await tester.pump();
  return engine;
}

/// Opens the route act, chooses A and B where not yet chosen, and asks for the
/// route. Pumps past the 2 s consent-store timeout and the dialog animation.
Future<void> _askForRoute(WidgetTester tester) async {
  final open = find.byKey(const Key('route-act-open'));
  await tester.ensureVisible(open);
  await tester.pump();
  await tester.tap(open);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  final actMap =
      find.descendant(of: find.byType(Dialog), matching: find.byType(AkitaMap));
  final r = tester.getRect(actMap);
  for (final (letter, offset) in const [
    ('A', Offset(-80, -30)),
    ('B', Offset(80, 30)),
  ]) {
    if (find.descendant(of: actMap, matching: find.text(letter))
        .evaluate()
        .isEmpty) {
      await tester.tapAt(r.center + offset);
      await tester.pump(const Duration(milliseconds: 350));
    }
  }
  await tester.tap(find.byKey(const Key('route-act-get-route')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tapAndSettle(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pump();
  await tester.tap(find.byKey(key));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  test('the consent text says where the choice is changed', () {
    expect(
        const AppL10n(Locale('ja')).routeConsentBody,
        '出発地と目的地の座標が、経路計算のため公開OSRMデモサーバー'
        '（router.project-osrm.org）に送信されます。よろしいですか。'
        'この選択は記憶され、ルート欄の「選択を変更」から変更できます。');
    expect(
        const AppL10n(Locale('en')).routeConsentBody,
        'The origin and destination coordinates you tapped will be sent to the '
        'public OSRM demo server (router.project-osrm.org) to calculate the '
        'route. Is that OK? Your choice is remembered and can be changed with '
        '"Change choice" in the route panel.');
  });

  testWidgets('after a yes she can change it, and after she withdraws no '
      'route is sent', (tester) async {
    final engine = await _boot(tester);
    expect(find.byKey(const Key('route-consent-change')), findsNothing,
        reason: 'no answer yet, nothing to change');

    await _askForRoute(tester);
    await _tapAndSettle(tester, const Key('route-consent-accept'));
    expect(engine.requests, 1, reason: 'control: the yes sent the route');
    expect(find.byKey(const Key('route-summary')), findsOneWidget);

    final change = find.byKey(const Key('route-consent-change'));
    expect(change, findsOneWidget, reason: 'after a yes, 選択を変更 is offered');
    expect(
        find.descendant(of: change, matching: find.text('選択を変更')),
        findsOneWidget);

    // Withdraw: the question comes back, and she answers no.
    await tester.ensureVisible(change);
    await tester.pump();
    await tester.tap(change);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('route-consent-body')), findsOneWidget);
    await _tapAndSettle(tester, const Key('route-consent-decline'));
    expect(find.byKey(const Key('route-consent-declined')), findsOneWidget);
    expect(find.byKey(const Key('route-summary')), findsNothing);
    expect(engine.requests, 1, reason: 'withdrawing sends nothing');

    // Ask for the route again: the remembered no holds, nothing is sent and
    // the question is not put to her as if she had never answered.
    await _askForRoute(tester);
    expect(find.byKey(const Key('route-consent-body')), findsNothing);
    expect(find.byKey(const Key('route-consent-declined')), findsOneWidget);
    expect(engine.requests, 1, reason: 'after she withdraws no route is sent');

    // Drain the fire-and-forget persist timers.
    await tester.pump(const Duration(seconds: 3));
  });
}
