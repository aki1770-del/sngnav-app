/// The next-turn section tells her its state in her language, and the app's
/// own diagnostics are not drawn on her screen.
///
/// Why this test exists. Read on 6a72b41 in lib/main.dart, in source: with a
/// route that has a turn, the section drew English in every locale. A
/// paragraph named the routing class, its request flag and the gate's internal
/// state names; a row counted "Maneuvers parsed"; the banner named its state
/// SPEAK, HEDGE or SUPPRESSED; a label said "icy-turn advisory coupled"; the
/// button said "(gated)"; the line after her press carried the decision's enum
/// name and "honest silence"; and a note said hearing the line is not verified
/// in this env.
///
/// What she needs from those is status, and it is now in her language: the
/// banner's state, the button, what her press did, and the icy mark. The rest
/// is off her screen. The bounds the note stated are recorded for developers
/// in KNOWN_LIMITATIONS.md: hearing on a device is unverified, and there is no
/// deviation detection.
///
/// The bytes below are candidates for a look on a render; none is ruled.
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

import '../support/fake_alert_actuators.dart';

// Two of the banner's three states, the button, and what her press did. The
// third state, a position that is only suspect, is reached by no position the
// app gives the drive brain today; its words are pinned beside the others in
// test/l10n/maneuver_tier_words_test.dart.
const _tierSpeak = {'ja': 'そのまま読み上げます', 'en': 'Read aloud as given'};
const _tierSuppressed = {'ja': '読み上げません', 'en': 'Not read aloud'};
const _button = {'ja': '次の案内を読み上げる', 'en': 'Read the next maneuver aloud'};
const _announced = {'ja': '音声＋振動で知らせました。', 'en': 'Announced on audio + haptic.'};
const _notSpoken = {'ja': '何も読み上げていません。', 'en': 'Nothing was read aloud.'};
const _sectionTitle = {'ja': '次の案内', 'en': 'Next maneuver'};

/// Words that belong to the code and to the people who built it, never to her
/// screen.
const _diagnostics = [
  'OsrmRoutingEngine',
  'steps=true',
  'SPEAK',
  'HEDGE',
  'SUPPRESS',
  'Maneuvers parsed',
  'gated',
  'honest',
  'Turn-trigger',
  'HEARS',
  'this env',
  'icy-turn',
  'Announced (',
];

final _start = DateTime.utc(2026, 1, 14, 21);

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
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

Future<FakeAlertActuators> _boot(WidgetTester tester, String lang,
    {Stream<PositionFix> Function()? source}) async {
  final a = FakeAlertActuators();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: a,
    locale: Locale(lang),
    clock: () => _start,
    jmaFetch: () async => const JmaFailure('test: no observation'),
    positionSource: source,
    routingEngineFactory: () => _OneTurnEngine(),
  ));
  await tester.pump();
  await tester.pump();
  return a;
}

/// A route with one turn, set through the route act, with the send accepted.
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

/// The next-turn section's card, found from its banner.
Finder _card() => find
    .ancestor(
        of: find.byKey(const Key('maneuver-narration-banner')),
        matching: find.byType(Card))
    .first;

List<String> _cardTexts(WidgetTester tester) => [
      for (final e in find
          .descendant(of: _card(), matching: find.byType(Text))
          .evaluate())
        (e.widget as Text).data ??
            (e.widget as Text).textSpan?.toPlainText() ??
            '',
    ];

String _textOfKey(WidgetTester tester, String key) {
  final f = find.byKey(Key(key));
  expect(f, findsOneWidget, reason: '$key is drawn');
  return tester.widget<Text>(f).data ?? '';
}

void _expectNoDiagnostics(WidgetTester tester, String when) {
  final texts = _cardTexts(tester);
  expect(texts, isNotEmpty, reason: '$when: precondition: the card is read');
  for (final t in texts) {
    for (final d in _diagnostics) {
      expect(t.contains(d), isFalse, reason: '$when: 「$t」 carries "$d"');
    }
  }
}

Future<void> _pressNarrate(WidgetTester tester) async {
  final b = find.byKey(const Key('maneuver-narrate-button'));
  await tester.ensureVisible(b);
  await tester.pump();
  await tester.tap(b);
  await _settle(tester);
}

void main() {
  for (final lang in const ['ja', 'en']) {
    testWidgets(
        '$lang: before any position of this share the banner says the turn is '
        'not read aloud, her press is told nothing was, and no diagnostic is '
        'drawn', (tester) async {
      final a = await _boot(tester, lang);
      await _routeWithOneTurn(tester);

      expect(find.text(_sectionTitle[lang]!), findsOneWidget);
      expect(_textOfKey(tester, 'maneuver-narration-tier'),
          _tierSuppressed[lang]);
      expect(
          find.descendant(
              of: find.byKey(const Key('maneuver-narrate-button')),
              matching: find.text(_button[lang]!)),
          findsOneWidget);
      _expectNoDiagnostics(tester, '$lang before');

      final spokenBefore = a.spoken.length;
      await _pressNarrate(tester);
      expect(_textOfKey(tester, 'maneuver-narration-result'), _notSpoken[lang]);
      expect(a.spoken.length, spokenBefore,
          reason: 'control: a suppressed turn speaks nothing');
      _expectNoDiagnostics(tester, '$lang after the press');
    });

    testWidgets(
        '$lang: on a trusted fix of this share the banner says the turn is read '
        'as given, her press is told it was announced, and no diagnostic is '
        'drawn', (tester) async {
      final positions = StreamController<PositionFix>.broadcast();
      final a = await _boot(tester, lang, source: () => positions.stream);
      await _routeWithOneTurn(tester);
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

      expect(_textOfKey(tester, 'maneuver-narration-tier'), _tierSpeak[lang]);
      _expectNoDiagnostics(tester, '$lang trusted');

      final spokenBefore = a.spoken.length;
      await _pressNarrate(tester);
      expect(_textOfKey(tester, 'maneuver-narration-result'), _announced[lang]);
      expect(a.spoken.length, greaterThan(spokenBefore),
          reason: 'control: a trusted turn is announced');
      _expectNoDiagnostics(tester, '$lang after the press');
      await positions.close();
    });
  }
}
