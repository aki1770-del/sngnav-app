/// The measured ice verdict reaches the card that narrates her next turn.
///
/// WHY THIS TEST EXISTS. Her page already painted a MEASURED ice verdict —
/// 路面凍結のおそれ from a live JMA reading — on the drive card. The maneuver
/// hazard check one card below read a DIFFERENT variable entirely: `_condition`,
/// the simulated road surface, whose only setter lives inside
/// `_developerSections()` behind a `!kReleaseMode` gate. In the signed build
/// that value is permanently `unknown`, so the icy mark was structurally
/// unreachable: her page could show a risk of road icing on one card and
/// narrate the next turn with no ice mark on the card below it.
///
/// That was not a missing feature. It was two things that were already true
/// failing to meet.
///
/// WHY IT IS A WIDGET TEST AND NOT AN l10n ONE. On 2026-09-23 VDE proved, on
/// this same card, that a guard which calls the string layer directly stays
/// GREEN when the widget stops rendering the thing the strings describe. A test
/// of `AppL10n` could not see this wire at all. Every assertion below is driven
/// through `SngnavApp` from an injected JMA observation, so it fails if the
/// wire is absent — which was confirmed by removing it and watching this file
/// go red before it was allowed to go green.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart' as re;
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/drive_hud_localizer.dart';

import '../support/fake_alert_actuators.dart';

final _start = DateTime.utc(2026, 1, 14, 21);
const _hud = DriveHudLocalizer();

/// The founding radiative-frost scenario, pinned in
/// test/services/invisible_ice_watch_test.dart: +2 C, 70% RH, measured no
/// precipitation -> InvisibleIceWatchResult.watch. Above zero, so it is the
/// SURPRISE case and not subZeroFrozen.
JmaObservation _obs({
  required double temp,
  required int humidity,
  double? precip10m = 0,
}) =>
    JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: temp,
      humidityPercent: humidity,
      windMetersPerSecond: 2,
      snowDepthCm: null,
      precipitation10mMm: precip10m,
      visibilityMeters: null,
      observedAtJstKey: '20260115060000',
      fetchedAt: _start,
    );

class _OneTurnEngine implements re.RoutingEngine {
  @override
  Future<re.RouteResult> calculateRoute(re.RouteRequest request) async =>
      re.RouteResult(
        shape: [request.origin, request.destination],
        maneuvers: const [
          re.RouteManeuver(
            index: 0,
            instruction: 'Depart',
            type: 'depart',
            lengthKm: 0.3,
            timeSeconds: 30,
            position: LatLng(39.70, 140.09),
          ),
          re.RouteManeuver(
            index: 1,
            instruction: 'Turn right',
            type: 'right',
            lengthKm: 1.2,
            timeSeconds: 90,
            position: LatLng(39.71, 140.10),
          ),
        ],
        totalDistanceKm: 1.5,
        totalTimeSeconds: 120,
        summary: 'fake',
        engineInfo: const re.EngineInfo(name: 'mock'),
      );

  @override
  Future<bool> isAvailable() async => true;

  @override
  re.EngineInfo get info => const re.EngineInfo(name: 'mock');

  @override
  Future<void> dispose() async {}
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

Future<FakeAlertActuators> _boot(
  WidgetTester tester, {
  required Future<JmaResult> Function() jma,
  required Stream<PositionFix> Function() source,
  String lang = 'ja',
}) async {
  final a = FakeAlertActuators();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
      // Not about the consent act; that is guarded in
      // test/widgets/location_consent_act_and_privacy_surface_test.dart.
      locationConsent: true,

    actuators: a,
    locale: Locale(lang),
    clock: () => _start,
    jmaFetch: jma,
    positionSource: source,
    routingEngineFactory: () => _OneTurnEngine(),
  ));
  await tester.pump();
  await tester.pump();
  return a;
}

Future<void> _routeWithOneTurn(WidgetTester tester) async {
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
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byKey(const Key('route-consent-accept')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 3));
  expect(find.byKey(const Key('maneuver-narration-banner')), findsOneWidget,
      reason: 'precondition: the route has a next maneuver');
}

/// Start the share and give the brain one trusted fix, so the narration gate
/// is SPEAK and the mark is allowed to draw at all.
Future<void> _trustedFix(
    WidgetTester tester, StreamController<PositionFix> positions) async {
  final share = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(share);
  await tester.pump();
  await tester.tap(share);
  await _settle(tester);
  positions.add(PositionAvailable(
      latitude: 39.7186,
      longitude: 140.1024,
      accuracyMeters: 10,
      timestamp: _start));
  await _settle(tester);
}

Finder _card() => find
    .ancestor(
        of: find.byKey(const Key('maneuver-narration-banner')),
        matching: find.byType(Card))
    .first;

/// The icy mark, found INSIDE the next-turn card so another card's words can
/// never satisfy it.
Finder _icyMark(String words) =>
    find.descendant(of: _card(), matching: find.text(words));

const _icyJa = '❄ 凍結のおそれ';
const _icyEn = '❄ May be icy';

Future<({FakeAlertActuators actuators, StreamController<PositionFix> pos})>
    _driveTo(WidgetTester tester,
        {required Future<JmaResult> Function() jma, String lang = 'ja'}) async {
  final positions = StreamController<PositionFix>.broadcast();
  final a = await _boot(tester, jma: jma, source: () => positions.stream,
      lang: lang);
  await _routeWithOneTurn(tester);
  await _trustedFix(tester, positions);
  return (actuators: a, pos: positions);
}

void main() {
  testWidgets(
      'a MEASURED radiative-frost watch marks her next turn icy, and the card '
      'says the mark came from an observation', (tester) async {
    final d = await _driveTo(tester,
        jma: () async => JmaSuccess(_obs(temp: 2.0, humidity: 70)));

    expect(_icyMark(_icyJa), findsOneWidget,
        reason: 'THE WIRE: a measured watch reaches the turn card. Without it '
            '_condition is unknown in a signed build and this never draws.');
    expect(find.byKey(const Key('maneuver-measured-road-ice')), findsOneWidget,
        reason: 'the mark states its provenance');
    expect(find.byKey(const Key('maneuver-test-road-condition')), findsNothing,
        reason: 'a measured watch must NOT be labelled a test value');

    // The provenance line still tells her the road itself was not measured.
    final line = tester
        .widget<Text>(find.byKey(const Key('maneuver-measured-road-ice')))
        .data!;
    expect(line, contains('気温'));
    expect(line, contains('路面は測定していません'),
        reason: 'the watch is an inference from air temperature and humidity; '
            'no instrument touched the road');

    await d.pos.close();
  });

  testWidgets(
      'the spoken line carries the icy coupling and NOT the test-value prefix',
      (tester) async {
    final d = await _driveTo(tester,
        jma: () async => JmaSuccess(_obs(temp: 2.0, humidity: 70)));

    final before = d.actuators.spoken.length;
    final b = find.byKey(const Key('maneuver-narrate-button'));
    await tester.ensureVisible(b);
    await tester.pump();
    await tester.tap(b);
    await _settle(tester);

    expect(d.actuators.spoken.length, greaterThan(before),
        reason: 'control: a trusted turn is announced');
    final said = d.actuators.spoken.last.text;
    // This assertion is what makes the test discriminate. Without it the test
    // passed with the wire REMOVED too — no coupling means no test-value
    // prefix either, so the isFalse below was satisfied by silence. Caught by
    // running the falsification and reading which cases stayed green; it is
    // the same "a guard that passes both ways is not a guard" VDE found on
    // this card hours earlier.
    expect(said, contains('この曲がり角は路面が凍結している可能性があります。'),
        reason: 'THE WIRE, on the VOICE: the measured watch couples the icy '
            'line onto the spoken maneuver');
    expect(said.startsWith(_hud.testValueSpokenPrefix('ja')), isFalse,
        reason: 'prefixing a MEASURED observation with "test value" is the '
            'same defect as calling a test value measured');
    // A haptic rides it too: the coupling is critical, and for a deaf or
    // hard-of-hearing driver that channel is the only one.
    expect(d.actuators.haptics, isNotEmpty);

    await d.pos.close();
  });

  testWidgets(
      'CONTROL: a measured reading with no frost window leaves the turn '
      'unmarked, and draws no provenance line at all', (tester) async {
    final d = await _driveTo(tester,
        jma: () async => JmaSuccess(_obs(temp: 5.0, humidity: 50)));

    expect(_icyMark(_icyJa), findsNothing,
        reason: 'no watch fired, and nothing else may mark the turn icy');
    expect(find.byKey(const Key('maneuver-measured-road-ice')), findsNothing);
    expect(find.byKey(const Key('maneuver-test-road-condition')), findsNothing);

    await d.pos.close();
  });

  testWidgets(
      'CONTROL: sub-zero is measured ice and is deliberately NOT coupled — the '
      'cry-wolf decision of 2026-07-23 is not reversed here', (tester) async {
    final d = await _driveTo(tester,
        jma: () async => JmaSuccess(_obs(temp: -3.0, humidity: 80)));

    // The calm chip IS drawn — this proves the verdict really is subZeroFrozen
    // and the control is not passing because the feed was silent.
    expect(find.byKey(const Key('subzero-frozen-chip')), findsOneWidget,
        reason: 'precondition: the sub-zero verdict is in force');
    expect(_icyMark(_icyJa), findsNothing,
        reason: 'below zero the ice is EXPECTED, not the radiative surprise; '
            'coupling it would raise a CRITICAL voice+haptic on every turn of '
            'every cold morning');

    await d.pos.close();
  });

  testWidgets(
      'CONTROL: a FAILED read cannot hold the mark — no stale hazard reaches '
      'her turn', (tester) async {
    final d = await _driveTo(tester,
        jma: () async => const JmaFailure('test: this refresh failed'));

    expect(_icyMark(_icyJa), findsNothing,
        reason: '_refreshJma sets the live verdict to unknown on feed loss, so '
            'a stale watch can never mark a turn');
    expect(find.byKey(const Key('maneuver-measured-road-ice')), findsNothing);

    await d.pos.close();
  });

  testWidgets('the English page says it in English', (tester) async {
    final d = await _driveTo(tester,
        jma: () async => JmaSuccess(_obs(temp: 2.0, humidity: 70)),
        lang: 'en');

    expect(_icyMark(_icyEn), findsOneWidget);
    final line = tester
        .widget<Text>(find.byKey(const Key('maneuver-measured-road-ice')))
        .data!;
    expect(line.toLowerCase(), contains('inferred'));
    expect(line.toLowerCase(), contains('not measured'));

    await d.pos.close();
  });
}
