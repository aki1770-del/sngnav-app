/// Every word and icon on her home page is drawn at or above the app's
/// accessibility floor: 4.5:1 for text, 3:1 for an icon (WCAG 2.x AA).
///
/// WHY, written before the act (2026-09-15). The speech-unverified and
/// haptic-unverified chips are for the driver who has lost a channel: the
/// haptic chip is written for a deaf or hard-of-hearing driver, the speech chip
/// tells her the voice may not have sounded. On 8b445ad they drew their words
/// in amber.shade900 on amber.shade100 at 2.38:1. Read over the whole painted
/// page, the same amber also sat under the pre-drive voice caution (2.63:1)
/// and the mock position line (2.52:1), grey text on the live-drive card and
/// the page foot measured 4.17:1 and 4.39:1, and the GPS blackout counter drew
/// orange.shade900 at 3.43:1. A caution she cannot read has not reached her.
///
/// So this test reads what is painted, not a list of colour constants: every
/// paragraph's own colour against the fill behind it (see
/// `support/painted_text_contrast.dart` for how, and for its bounds). It
/// raises every caution the app can draw without a device, in both languages,
/// then the mock position, then a raised rung, and holds the whole page to the
/// floor in each state. It first proves each named surface is on the screen,
/// so it cannot pass by not reaching them.
///
/// Not covered: states that need a network answer or a route (advisory and
/// weather rows with data, the next-turn banner), the map's own labels, and a
/// phone panel. Inactive controls are listed by the helper and not held to the
/// floor, as WCAG exempts them.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/audio_readiness.dart';
import 'package:sngnav_app/services/haptic_readiness.dart';
import 'package:sngnav_app/services/voice_lane_readiness.dart';

import '../support/developer_page.dart';
import '../support/fake_alert_actuators.dart';
import '../support/painted_text_contrast.dart';

final class _MutedAudio implements AudioReadinessProbe {
  @override
  Future<AudioReadiness?> read() async => const AudioReadiness(
      mediaVolume: 0, mediaVolumeMax: 15, ttsServiceVisible: true);
}

final class _Tactile implements HapticReadinessProbe {
  const _Tactile(this.available);
  final bool available;
  @override
  Future<bool?> read() async => available;
}

/// What is wrong with the page in [state], as lines; empty when it holds.
///
/// [named] are the surfaces this state exists to reach: each must have at
/// least one measured run on a known ground, so the floor check cannot pass on
/// a page that did not draw them or a reader that did not see them. Findings
/// are gathered across every state and asserted once, so one failing run
/// shows every state that is below the floor.
List<String> _pageBelowFloor(WidgetTester tester, String state,
    {required Map<String, bool Function(PaintedText)> named}) {
  final painted = paintedTextOutsideMap(tester);
  final held = painted.where((p) => !p.inactive).toList();
  return [
    for (final e in named.entries)
      if (!held.any((p) => e.value(p) && p.ground != null))
        '$state: nothing measured on ${e.key}',
    for (final line in {
      for (final p in held.where((p) => p.ground == null))
        '$state: ground unknown, contrast unmeasured: ${p.describe()}',
      for (final p in held.where((p) => p.belowFloor))
        '$state: below the floor: ${p.describe()}',
    })
      line,
  ];
}

/// Lets Material's state colour transitions finish (200 ms) before a
/// measurement: a button that has just become enabled is still painted in its
/// disabled colour on the next frame, and the floor is about the settled screen.
Future<void> _settle(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 500));

void main() {
  for (final lang in const ['ja', 'en']) {
    for (final tactileAvailable in const [false, true]) {
      testWidgets(
          '$lang, tactile ${tactileAvailable ? 'available' : 'unavailable'}: '
          'every caution raised, then the mock position, then a raised rung, '
          'all at or above the floor', (tester) async {
        final l = AppL10n(Locale(lang));
        await tester.pumpWidget(SngnavApp(
          locale: Locale(lang),
          actuators: FakeAlertActuators(),
          voiceLaneReader: () async => VoiceLaneVerdict.jaNetworkOnly,
          speechUnverified: ValueNotifier<bool>(true),
          hapticUnverified: ValueNotifier<bool>(true),
          audioReadinessProbe: _MutedAudio(),
          hapticReadinessProbe: _Tactile(tactileAvailable),
          developerPageEntry: true,
        ));
        await tester.pump();
        await tester.pump();
        await _settle(tester);

        for (final k in [
          'speech-unverified-chip',
          'haptic-unverified-chip',
          'voice-lane-caution',
          'media-muted-caution',
          tactileAvailable ? 'haptic-unverified-note' : 'haptic-unavailable-caution',
        ]) {
          expect(find.byKey(Key(k)), findsOneWidget,
              reason: 'precondition: $k is on the screen');
        }
        bool keyed(PaintedText p, String k) => p.key == k;
        final problems = <String>[];
        problems.addAll(_pageBelowFloor(tester, '$lang launch', named: {
          'the speech chip': (p) => keyed(p, 'speech-unverified-chip'),
          'the tactile chip': (p) => keyed(p, 'haptic-unverified-chip'),
          'the voice caution': (p) => keyed(p, 'voice-lane-caution'),
          'the muted caution': (p) => keyed(p, 'media-muted-caution'),
          'the share hint': (p) => keyed(p, 'drive-hud-share-hint'),
          'the no-position line': (p) => p.text == l.driveHudNoPositionFed,
          // By its key: the app bar's title also starts with "sngnav-app ",
          // so a prefix could pass without the foot (found 2026-09-15).
          'the page foot': (p) => keyed(p, 'page-foot'),
        }));

        // The announce helper moved with its card to the development page
        // (2026-09-15), and is held to the floor where it is drawn now. The
        // page under it is read in the same pass.
        await openDeveloperPage(tester);
        await _settle(tester);
        problems.addAll(_pageBelowFloor(tester, '$lang development page', named: {
          'the announce helper': (p) => p.text == l.announceInfoHelper,
        }));
        await tester.tap(find.byType(BackButton));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await _settle(tester);

        final mock = find.byKey(const Key('use-mock-button'));
        await tester.ensureVisible(mock);
        await tester.tap(mock);
        await tester.pump();
        await tester.pump();
        await _settle(tester);
        expect(find.text(l.mockPositionStatus('35')), findsOneWidget,
            reason: 'precondition: the mock position line is on the screen');
        problems.addAll(_pageBelowFloor(tester, '$lang mock position', named: {
          'the mock position line': (p) => p.text == l.mockPositionStatus('35'),
        }));

        final blackout = find.byKey(const Key('drive-hud-blackout-button'));
        for (var i = 0; i < 3; i++) {
          await tester.ensureVisible(blackout);
          await tester.tap(blackout);
          await tester.pump();
          await tester.pump();
        }
        await _settle(tester);
        expect(find.byKey(const Key('drive-hud-caution-banner')), findsOneWidget,
            reason: 'precondition: a rung is on the card');
        expect(find.byKey(const Key('drive-hud-blackout-seconds')),
            findsOneWidget,
            reason: 'precondition: the blackout counter is on the card');
        problems.addAll(_pageBelowFloor(tester, '$lang raised rung', named: {
          'the rung banner': (p) => keyed(p, 'drive-hud-caution-banner'),
          'the blackout counter': (p) => keyed(p, 'drive-hud-blackout-seconds'),
        }));
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    }
  }

  for (final lang in const ['ja', 'en']) {
    testWidgets(
        '$lang: the line under the map while the app is locating her is at or '
        'above the floor', (tester) async {
      final l = AppL10n(Locale(lang));
      final positions = StreamController<PositionFix>.broadcast();
      addTearDown(positions.close);
      await tester.pumpWidget(SngnavApp(
        locale: Locale(lang),
        actuators: FakeAlertActuators(),
        positionSource: () => positions.stream,
      ));
      await tester.pump();
      await tester.pump();
      final share = find.byKey(const Key('share-location-button'));
      await tester.ensureVisible(share);
      await tester.tap(share);
      await tester.pump();
      await _settle(tester);
      expect(find.text(l.locatingYou), findsOneWidget,
          reason: 'precondition: the app is locating her');
      final problems = _pageBelowFloor(tester, '$lang locating', named: {
        'the locating line': (p) => p.text == l.locatingYou,
      });
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }
}
