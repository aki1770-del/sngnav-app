// G-3 — the PRE-DRIVE tactile caution, per AAA's 2026-08-22 PUSHBACK.
//
// AAA's finding, verbatim from its verdict: *"the channel with the higher
// dignity load has the weaker instrument."* Audio was probed at four triggers
// and cautioned before the drive; the tactile channel was probed only when a
// warning was already owed. This file asserts the tactile half now exists on
// HER pre-drive surface — and, as importantly, that it stays SILENT on the two
// answers that do not earn a caution.
//
// HONESTY (OPS-066 / AAE-1): verifies the WIDGET TREE against an injected
// probe. Whether a real phone vibrates is an on-device fact, verified
// separately and recorded there.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/audio_readiness.dart';
import 'package:sngnav_app/services/haptic_readiness.dart';

import '../support/fake_alert_actuators.dart';

final class _FixedHaptic implements HapticReadinessProbe {
  _FixedHaptic(this.answer);
  final bool? answer;
  @override
  Future<bool?> read() async => answer;
}

final class _FixedAudio implements AudioReadinessProbe {
  _FixedAudio(this.reading);
  final AudioReadiness? reading;
  @override
  Future<AudioReadiness?> read() async => reading;
}

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    bool? haptic,
    AudioReadiness? audio,
    ValueNotifier<bool>? hapticUnverified,
    Locale locale = const Locale('ja'),
  }) async {
    await tester.pumpWidget(SngnavApp(
      locale: locale,
      actuators: FakeAlertActuators(),
      hapticReadinessProbe: _FixedHaptic(haptic),
      audioReadinessProbe: audio == null ? null : _FixedAudio(audio),
      hapticUnverified: hapticUnverified,
    ));
    await tester.pump();
    await tester.pump();
  }

  const cautionKey = Key('haptic-unavailable-caution');
  const noteKey = Key('haptic-unverified-note');
  const mutedKey = Key('media-muted-caution');

  const muted = AudioReadiness(
      mediaVolume: 0, mediaVolumeMax: 15, ttsServiceVisible: true);

  testWidgets('the platform reports NO vibrator -> the pre-drive caution '
      'renders with the ja text', (tester) async {
    await pumpApp(tester, haptic: false);

    await tester.ensureVisible(find.byKey(cautionKey));
    expect(find.byKey(cautionKey), findsOneWidget);
    expect(
      find.text('この端末は振動に対応していません。'
          '音が聞こえない場合、警告は画面表示のみになります。'),
      findsOneWidget,
    );
  });

  testWidgets('en locale gets the en line', (tester) async {
    await pumpApp(tester, haptic: false, locale: const Locale('en'));

    await tester.ensureVisible(find.byKey(cautionKey));
    expect(
      find.text('This device reports no vibration. If you cannot hear the '
          'sound, warnings will be on screen only.'),
      findsOneWidget,
    );
  });

  testWidgets('CONTROL: a vibrator IS present -> NOTHING', (tester) async {
    await pumpApp(tester, haptic: true);
    expect(find.byKey(cautionKey), findsNothing);
  });

  testWidgets('CONTROL: the answer is UNKNOWN (unreadable channel, off-mobile, '
      'test binding) -> NOTHING — never a caution about a device that may '
      'vibrate perfectly well', (tester) async {
    await pumpApp(tester, haptic: null);
    expect(find.byKey(cautionKey), findsNothing);
  });

  testWidgets('a device with NO vibrator does not ALSO get the weaker '
      'in-muted note — the caution already said the stronger, measured thing',
      (tester) async {
    await pumpApp(
      tester,
      haptic: false,
      audio: muted,
      hapticUnverified: ValueNotifier<bool>(true),
    );

    await tester.ensureVisible(find.byKey(mutedKey));
    expect(find.byKey(mutedKey), findsOneWidget);
    await tester.ensureVisible(find.byKey(cautionKey));
    expect(find.byKey(cautionKey), findsOneWidget);
    expect(
      find.byKey(noteKey),
      findsNothing,
      reason: '"could not be verified" is strictly weaker than "has none", and '
          'saying both on one glance surface is noise, not honesty',
    );
  });

  testWidgets('but a device that HAS a vibrator and lost the cue still gets '
      'the note — suppression must not swallow a real delivery failure',
      (tester) async {
    await pumpApp(
      tester,
      haptic: true,
      audio: muted,
      hapticUnverified: ValueNotifier<bool>(true),
    );

    expect(find.byKey(cautionKey), findsNothing);
    await tester.ensureVisible(find.byKey(noteKey));
    expect(find.byKey(noteKey), findsOneWidget);
  });
}
