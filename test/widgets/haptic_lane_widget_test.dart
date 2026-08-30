// OPS-059 tactile lane — widget wiring:
// (a) the in-drive HUD chip 「振動警告を確認できませんでした」 toggles with the
//     injected haptic-verification flag (set when an OWED tactile cue does
//     not land, cleared on the next cue the platform accepts);
// (b) while the media-muted caution is up — the surface that tells HER
//     「振動でお知らせします」 and asks her to continue in haptics-only mode —
//     an unverified tactile channel WITHDRAWS that promise in the same row.
//
// WHY THIS FILE EXISTS. On 2026-08-21 the app was measured on AVD
// `sngnav_api30`: an announce at severity `critical` dispatched Japanese TTS
// and registered ZERO vibrations in `dumpsys vibrator` (recording capability
// proven by a negative control). Nobody was told. The channel that is not the
// second channel but the ONLY channel for a deaf or hard-of-hearing driver was
// the one channel with no probe, no caution and no delivery report — while the
// app was simultaneously offering her a button that says
// 「承知しました（音声なしで続行）」.
//
// HONESTY (OPS-066 / AAE-1): this verifies the WIDGET TREE against injected
// flags. Whether a real vibrator moves on a real phone is an on-device fact,
// verified separately on the emulator and recorded there.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/audio_readiness.dart';

import '../support/fake_alert_actuators.dart';

final class _FakeProbe implements AudioReadinessProbe {
  _FakeProbe(this.reading);
  final AudioReadiness? reading;
  @override
  Future<AudioReadiness?> read() async => reading;
}

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    ValueNotifier<bool>? hapticUnverified,
    AudioReadinessProbe? probe,
    Locale locale = const Locale('ja'),
  }) async {
    await tester.pumpWidget(SngnavApp(
      locale: locale,
      actuators: FakeAlertActuators(),
      hapticUnverified: hapticUnverified,
      audioReadinessProbe: probe,
    ));
    // Two pumps: one for first build, one for the async setState.
    await tester.pump();
    await tester.pump();
  }

  const chipKey = Key('haptic-unverified-chip');
  const noteKey = Key('haptic-unverified-note');
  const mutedKey = Key('media-muted-caution');

  const muted = AudioReadiness(
      mediaVolume: 0, mediaVolumeMax: 15, ttsServiceVisible: true);

  testWidgets('HUD chip: absent while the tactile cue lands, appears when an '
      'owed cue does not, clears on the next accepted cue', (tester) async {
    final flag = ValueNotifier<bool>(false);
    await pumpApp(tester, hapticUnverified: flag);

    expect(find.byKey(chipKey), findsNothing);

    flag.value = true; // HardenedHapticChannel reported an owed cue lost
    await tester.pump();
    await tester.ensureVisible(find.byKey(chipKey));
    expect(find.byKey(chipKey), findsOneWidget);
    expect(find.text('振動警告を確認できませんでした'), findsOneWidget);

    flag.value = false; // the platform accepted the next waveform
    await tester.pump();
    expect(find.byKey(chipKey), findsNothing);
  });

  testWidgets('en locale gets the en chip line', (tester) async {
    final flag = ValueNotifier<bool>(true);
    await pumpApp(
        tester, hapticUnverified: flag, locale: const Locale('en'));

    await tester.ensureVisible(find.byKey(chipKey));
    expect(find.text('Vibration alert could not be verified'), findsOneWidget);
  });

  testWidgets('media-muted + unverified haptic -> the haptics-only promise is '
      'WITHDRAWN in the same row she consents in', (tester) async {
    final flag = ValueNotifier<bool>(true);
    await pumpApp(
        tester, hapticUnverified: flag, probe: _FakeProbe(muted));

    await tester.ensureVisible(find.byKey(mutedKey));
    expect(find.byKey(mutedKey), findsOneWidget);
    // The standing promise she is asked to accept.
    expect(
      find.text('音声警告は聞こえません（メディア音声が無音です）。'
          '警告は画面に表示され、振動も試みますが、この端末では未確認です。'),
      findsOneWidget,
    );
    // ...and the withdrawal, in the same glance.
    await tester.ensureVisible(find.byKey(noteKey));
    expect(find.byKey(noteKey), findsOneWidget);
    expect(
      find.text('振動も確認できませんでした。警告は画面表示のみです。'),
      findsOneWidget,
    );
  });

  testWidgets('CONTROL: media-muted with a LANDING haptic shows no withdrawal '
      '— reporting must not cry wolf', (tester) async {
    final flag = ValueNotifier<bool>(false);
    await pumpApp(
        tester, hapticUnverified: flag, probe: _FakeProbe(muted));

    await tester.ensureVisible(find.byKey(mutedKey));
    expect(find.byKey(mutedKey), findsOneWidget);
    expect(find.byKey(noteKey), findsNothing);
  });

  testWidgets('CONTROL: no flag injected -> the page owns one and renders '
      'NOTHING before any cue is fired', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(chipKey), findsNothing);
    expect(find.byKey(noteKey), findsNothing);
  });
}
