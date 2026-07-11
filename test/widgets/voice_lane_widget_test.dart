// Tier-1 voice-lane hardening — widget wiring:
// (a) the A1 pre-drive caution row shows ONLY on a proven-degraded verdict
//     (jaNetworkOnly / noJaVoice) and NEVER on offlineJaReady/unknown —
//     unknown must render nothing (no false warning off-device);
// (b) the in-drive HUD chip 「音声警告を確認できませんでした」 toggles with the
//     injected speech-verification flag (set on unverified, cleared on the
//     next verified speak).
//
// HONESTY (OPS-066 / AAE env-bound): verifies the WIDGET TREE. Whether the
// caution matches a real device's installed voices, and whether an
// unverified announce is really inaudible, are on-device facts — DEFERRED.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/voice_lane_readiness.dart';

import '../support/fake_alert_actuators.dart';

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    VoiceLaneVerdict? verdict,
    ValueNotifier<bool>? speechUnverified,
    Locale locale = const Locale('ja'),
  }) async {
    await tester.pumpWidget(SngnavApp(
      locale: locale,
      actuators: FakeAlertActuators(),
      voiceLaneReader: verdict == null ? null : () async => verdict,
      speechUnverified: speechUnverified,
    ));
    // Two pumps: one for first build, one for the async verdict setState.
    await tester.pump();
    await tester.pump();
  }

  const cautionKey = Key('voice-lane-caution');
  const chipKey = Key('speech-unverified-chip');

  testWidgets('jaNetworkOnly -> the pre-drive caution row renders with the '
      'ja text', (tester) async {
    await pumpApp(tester, verdict: VoiceLaneVerdict.jaNetworkOnly);

    await tester.ensureVisible(find.byKey(cautionKey));
    expect(find.byKey(cautionKey), findsOneWidget);
    expect(
      find.text('オフライン音声が未インストールです。'
          '電波のない場所では音声警告が出ない可能性があります。'),
      findsOneWidget,
    );
  });

  testWidgets('noJaVoice -> caution row renders; en locale gets the en '
      'fallback line', (tester) async {
    await pumpApp(tester,
        verdict: VoiceLaneVerdict.noJaVoice, locale: const Locale('en'));

    await tester.ensureVisible(find.byKey(cautionKey));
    expect(find.byKey(cautionKey), findsOneWidget);
    expect(
      find.text('Offline Japanese voice not installed — voice alerts may '
          'not sound where there is no signal.'),
      findsOneWidget,
    );
  });

  testWidgets('offlineJaReady -> NO caution row', (tester) async {
    await pumpApp(tester, verdict: VoiceLaneVerdict.offlineJaReady);
    expect(find.byKey(cautionKey), findsNothing);
  });

  testWidgets('no reader injected (real read under the test binding -> '
      'unknown) -> NOTHING rendered, never a false warning', (tester) async {
    await pumpApp(tester, verdict: null);
    expect(find.byKey(cautionKey), findsNothing);
  });

  testWidgets('HUD chip: absent while verified, appears when the flag sets, '
      'clears when the next verified speak resets it', (tester) async {
    final flag = ValueNotifier<bool>(false);
    await pumpApp(tester, speechUnverified: flag);

    expect(find.byKey(chipKey), findsNothing);

    flag.value = true; // hardened engine reported an unverified delivery
    await tester.pump();
    await tester.ensureVisible(find.byKey(chipKey));
    expect(find.byKey(chipKey), findsOneWidget);
    expect(find.text('音声警告を確認できませんでした'), findsOneWidget);

    flag.value = false; // next verified speak clears it
    await tester.pump();
    expect(find.byKey(chipKey), findsNothing);
  });
}
