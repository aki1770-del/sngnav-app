/// The second line must actually REACH her screen when a channel goes silent.
///
/// WHY THIS FILE EXISTS (VDE, 2026-09-23). The 2026-09-23 maneuver-card fix
/// added `Key('maneuver-narration-delivery-unverified')` to lib/main.dart and
/// its three sentences to app_localizations.dart, and shipped ONE guard:
/// test/l10n/maneuver_delivery_claim_is_not_past_tense_test.dart. That guard
/// calls `AppL10n` directly. It proves the SENTENCES are right. It cannot see
/// the widget, so it would stay green if the second line were never built,
/// never rebuilt, or built with a condition that can never be true on her
/// device — which is the same class of hole the fix itself was written to
/// close: a surface asserting a state nothing on the render path checks
/// (Sakichi Vision 14, and Vision 9 — the machine must catch it, not the
/// operator).
///
/// The author said so plainly and asked for this: "I have no device and wrote
/// no widget test that drives `_speechUnverified`/`_hapticUnverified` true and
/// asserts the line appears on the maneuver card."
///
/// So this drives the real widget tree through the real route -> consent ->
/// share -> trusted-fix -> press path that `maneuver_panel_words_test.dart`
/// already uses, then toggles the two injected notifiers and looks at what is
/// on the card.
///
/// BOUNDS, so nobody reads this for more than it is:
/// * This is the framework's render tree, not a phone. Panel brightness,
///   glare, sunlight and antialiasing are not in here. On-device remains
///   UNVERIFIED and is owed to HIE.
/// * It drives the notifiers directly. It does NOT prove the hardened TTS or
///   haptic channel flips them on a real failure; that seam has its own tests.
///   What it proves is the half that had nothing: notifier -> her screen.
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
import '../support/painted_text_contrast.dart';

const _kResult = Key('maneuver-narration-result');
const _kUnverified = Key('maneuver-narration-delivery-unverified');

const _sent = {'ja': '音声と振動に送りました。', 'en': 'Sent to audio + haptic.'};

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

Future<void> _boot(
  WidgetTester tester,
  String lang, {
  required ValueNotifier<bool> speech,
  required ValueNotifier<bool> haptic,
  required Stream<PositionFix> Function() source,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: FakeAlertActuators(),
    locale: Locale(lang),
    clock: () => _start,
    jmaFetch: () async => const JmaFailure('test: no observation'),
    positionSource: source,
    routingEngineFactory: () => _OneTurnEngine(),
    speechUnverified: speech,
    hapticUnverified: haptic,
  ));
  await tester.pump();
  await tester.pump();
}

/// A route with one turn, set through the route act, with the send accepted.
/// Lifted verbatim from maneuver_panel_words_test.dart so this file drives the
/// same path her finger drives, not a shortcut into private state.
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

/// Share location and feed one trusted fix, so the narration gate is SPEAK and
/// `shouldAnnounce` is true — the only state in which the new line can render.
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

Future<void> _pressNarrate(WidgetTester tester) async {
  final b = find.byKey(const Key('maneuver-narrate-button'));
  await tester.ensureVisible(b);
  await tester.pump();
  await tester.tap(b);
  await _settle(tester);
}

String _unverifiedText(WidgetTester tester) {
  final f = find.byKey(_kUnverified);
  expect(f, findsOneWidget, reason: 'the unverified line is drawn');
  return tester.widget<Text>(f).data ?? '';
}

void main() {
  testWidgets(
      'ja: CONTROL — with both channels reporting nothing wrong, the card says '
      'SENT and draws NO unverified line', (tester) async {
    final speech = ValueNotifier(false);
    final haptic = ValueNotifier(false);
    final positions = StreamController<PositionFix>.broadcast();
    await _boot(tester, 'ja',
        speech: speech, haptic: haptic, source: () => positions.stream);
    await _routeWithOneTurn(tester);
    await _trustedFix(tester, positions);
    await _pressNarrate(tester);

    expect(tester.widget<Text>(find.byKey(_kResult)).data, _sent['ja']);
    expect(find.byKey(_kUnverified), findsNothing,
        reason: 'a line that is always drawn tells her nothing');
    await positions.close();
  });

  testWidgets(
      'ja: the haptic channel goes silent AFTER her press — the line appears '
      'on this card, names 振動, and does not blame the voice', (tester) async {
    final speech = ValueNotifier(false);
    final haptic = ValueNotifier(false);
    final positions = StreamController<PositionFix>.broadcast();
    await _boot(tester, 'ja',
        speech: speech, haptic: haptic, source: () => positions.stream);
    await _routeWithOneTurn(tester);
    await _trustedFix(tester, positions);
    await _pressNarrate(tester);
    expect(find.byKey(_kUnverified), findsNothing, reason: 'baseline');

    // This is the real ordering: the announce is fire-and-forget, so the
    // channel's verdict lands after the card has already been drawn. If the
    // widget did not rebuild on the notifier, she would never see this.
    haptic.value = true;
    await tester.pump();

    final t = _unverifiedText(tester);
    expect(t, contains('振動'));
    expect(t, contains('確認できていません'));
    expect(t, isNot(contains('音声')),
        reason: 'the voice reported fine; do not accuse it');
    // The first line is unchanged and still says SENT, never told.
    expect(tester.widget<Text>(find.byKey(_kResult)).data, _sent['ja']);
    await positions.close();
  });

  testWidgets(
      'ja: the voice channel goes silent — the line names 音声, not the '
      'vibration', (tester) async {
    final speech = ValueNotifier(false);
    final haptic = ValueNotifier(false);
    final positions = StreamController<PositionFix>.broadcast();
    await _boot(tester, 'ja',
        speech: speech, haptic: haptic, source: () => positions.stream);
    await _routeWithOneTurn(tester);
    await _trustedFix(tester, positions);
    await _pressNarrate(tester);

    speech.value = true;
    await tester.pump();

    final t = _unverifiedText(tester);
    expect(t, contains('音声'));
    expect(t, isNot(contains('振動')));
    await positions.close();
  });

  testWidgets(
      'ja: both channels silent — one line naming BOTH, never silently '
      'dropping one', (tester) async {
    final speech = ValueNotifier(false);
    final haptic = ValueNotifier(false);
    final positions = StreamController<PositionFix>.broadcast();
    await _boot(tester, 'ja',
        speech: speech, haptic: haptic, source: () => positions.stream);
    await _routeWithOneTurn(tester);
    await _trustedFix(tester, positions);
    await _pressNarrate(tester);

    speech.value = true;
    haptic.value = true;
    await tester.pump();

    final t = _unverifiedText(tester);
    expect(t, contains('音声'));
    expect(t, contains('振動'));
    await positions.close();
  });

  testWidgets(
      'ja: the channel recovers — the line CLEARS, so a transient fault does '
      'not pin a warning on her screen for the rest of the drive',
      (tester) async {
    final speech = ValueNotifier(false);
    final haptic = ValueNotifier(false);
    final positions = StreamController<PositionFix>.broadcast();
    await _boot(tester, 'ja',
        speech: speech, haptic: haptic, source: () => positions.stream);
    await _routeWithOneTurn(tester);
    await _trustedFix(tester, positions);
    await _pressNarrate(tester);

    haptic.value = true;
    await tester.pump();
    expect(find.byKey(_kUnverified), findsOneWidget);

    haptic.value = false;
    await tester.pump();
    expect(find.byKey(_kUnverified), findsNothing);
    await positions.close();
  });

  testWidgets(
      'ja: the channel was ALREADY silent before she pressed — the line is '
      'there on the very first frame after the press', (tester) async {
    final speech = ValueNotifier(false);
    final haptic = ValueNotifier(true); // failed on an earlier hazard alert
    final positions = StreamController<PositionFix>.broadcast();
    await _boot(tester, 'ja',
        speech: speech, haptic: haptic, source: () => positions.stream);
    await _routeWithOneTurn(tester);
    await _trustedFix(tester, positions);
    await _pressNarrate(tester);

    expect(_unverifiedText(tester), contains('振動'));
    await positions.close();
  });

  testWidgets(
      'en: the same line reaches an English reader, in English',
      (tester) async {
    final speech = ValueNotifier(false);
    final haptic = ValueNotifier(false);
    final positions = StreamController<PositionFix>.broadcast();
    await _boot(tester, 'en',
        speech: speech, haptic: haptic, source: () => positions.stream);
    await _routeWithOneTurn(tester);
    await _trustedFix(tester, positions);
    await _pressNarrate(tester);

    expect(tester.widget<Text>(find.byKey(_kResult)).data, _sent['en']);
    haptic.value = true;
    await tester.pump();
    expect(_unverifiedText(tester).toLowerCase(), contains('vibration'));
    expect(_unverifiedText(tester).toLowerCase(), isNot(contains('voice')));
    await positions.close();
  });

  testWidgets(
      'ja: the line she is meant to read is painted above the app accessibility '
      'floor on the surface it lands on', (tester) async {
    final speech = ValueNotifier(false);
    final haptic = ValueNotifier(false);
    final positions = StreamController<PositionFix>.broadcast();
    await _boot(tester, 'ja',
        speech: speech, haptic: haptic, source: () => positions.stream);
    await _routeWithOneTurn(tester);
    await _trustedFix(tester, positions);
    await _pressNarrate(tester);
    haptic.value = true;
    await tester.pump();

    final painted = paintedTextOutsideMap(tester)
        .where((p) => p.text.contains('確認できていません'))
        .toList();
    expect(painted, isNotEmpty,
        reason: 'precondition: the line is in the render tree');
    for (final p in painted) {
      expect(p.ratio, isNotNull,
          reason: 'ground unknown is a failure, never an assumption: '
              '${p.describe()}');
      expect(p.belowFloor, isFalse, reason: p.describe());
    }
    await positions.close();
  });
}
