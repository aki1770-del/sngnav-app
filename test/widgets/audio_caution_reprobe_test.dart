// B32 — the audio cautions are no longer a one-shot initState read.
//
// Before this, the media-volume-zero and offline-voice cautions were probed
// ONCE at app open: a mute at minute 3 of a 2-hour drive was invisible for
// the whole drive — the app kept believing its ja warning would sound while
// the platform played it into silence. Now both probes re-run on a ~45 s
// ticker and on drive start. These tests pin:
//   (a) a MID-SESSION mute is detected on the next tick (row appears);
//   (b) an un-mute clears the row (the reading is live, not sticky);
//   (c) a NEW mute after an acknowledged one re-arms the full-strength row
//       (an hour-old acknowledgment must not pre-dismiss a new event);
//   (d) a voice-lane verdict that degrades mid-session surfaces, and a later
//       failed read (unknown) does NOT clear the proven caution;
//   (e) drive start (mock-position tap) re-probes without waiting for the
//       tick.
//
// HONESTY (OPS-066 / AAE env-bound): widget-tree + fake probes only. The
// real Kotlin channel reporting a real mid-drive mute is an on-device fact,
// DEFERRED to the next APK build.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/audio_readiness.dart';
import 'package:sngnav_app/services/voice_lane_readiness.dart';

import '../support/fake_alert_actuators.dart';

/// A probe whose reading the test can CHANGE between ticks.
final class _MutableProbe implements AudioReadinessProbe {
  AudioReadiness? reading;
  int reads = 0;
  @override
  Future<AudioReadiness?> read() async {
    reads++;
    return reading;
  }
}

const _muted = AudioReadiness(
    mediaVolume: 0, mediaVolumeMax: 15, ttsServiceVisible: true);
const _audible = AudioReadiness(
    mediaVolume: 8, mediaVolumeMax: 15, ttsServiceVisible: true);

const _mutedCautionKey = Key('media-muted-caution');
const _ackButtonKey = Key('media-muted-ack-button');
const _ackedKey = Key('media-muted-acked');
const _voiceCautionKey = Key('voice-lane-caution');

// One re-probe tick (the ticker fires at 45 s).
const _tick = Duration(seconds: 45);

void main() {
  late _MutableProbe probe;
  VoiceLaneVerdict verdict = VoiceLaneVerdict.unknown;

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(SngnavApp(
      locale: const Locale('ja'),
      actuators: FakeAlertActuators(),
      audioReadinessProbe: probe,
      voiceLaneReader: () async => verdict,
    ));
    await tester.pump();
    await tester.pump();
  }

  setUp(() {
    probe = _MutableProbe();
    verdict = VoiceLaneVerdict.unknown;
  });

  testWidgets('a MID-SESSION mute is detected on the next re-probe tick',
      (tester) async {
    probe.reading = _audible;
    await pumpApp(tester);
    expect(find.byKey(_mutedCautionKey), findsNothing);

    // She mutes the phone mid-session; the next tick must see it.
    probe.reading = _muted;
    await tester.pump(_tick);
    await tester.pump();

    await tester.ensureVisible(find.byKey(_mutedCautionKey));
    expect(find.byKey(_mutedCautionKey), findsOneWidget);
  });

  testWidgets('an un-mute clears the caution on the next tick — the reading '
      'is live, not sticky', (tester) async {
    probe.reading = _muted;
    await pumpApp(tester);
    expect(find.byKey(_mutedCautionKey), findsOneWidget);

    probe.reading = _audible;
    await tester.pump(_tick);
    await tester.pump();

    expect(find.byKey(_mutedCautionKey), findsNothing);
    expect(find.byKey(_ackedKey), findsNothing);
  });

  testWidgets('a NEW mute after an acknowledged one re-arms the full row: '
      'an old acknowledgment never pre-dismisses a new event',
      (tester) async {
    probe.reading = _muted;
    await pumpApp(tester);
    await tester.ensureVisible(find.byKey(_ackButtonKey));
    await tester.tap(find.byKey(_ackButtonKey));
    await tester.pump();
    expect(find.byKey(_ackedKey), findsOneWidget);

    // Unmute (tick 1), then a FRESH mute (tick 2).
    probe.reading = _audible;
    await tester.pump(_tick);
    await tester.pump();
    probe.reading = _muted;
    await tester.pump(_tick);
    await tester.pump();

    await tester.ensureVisible(find.byKey(_mutedCautionKey));
    expect(find.byKey(_mutedCautionKey), findsOneWidget,
        reason: 'A new mute is a new event and must surface at full '
            'strength.');
    expect(find.byKey(_ackedKey), findsNothing);
  });

  testWidgets('a mute that PERSISTS across ticks keeps the acknowledgment '
      '(no re-nag on the same event)', (tester) async {
    probe.reading = _muted;
    await pumpApp(tester);
    await tester.ensureVisible(find.byKey(_ackButtonKey));
    await tester.tap(find.byKey(_ackButtonKey));
    await tester.pump();

    await tester.pump(_tick);
    await tester.pump();

    expect(find.byKey(_ackedKey), findsOneWidget);
    expect(find.byKey(_mutedCautionKey), findsNothing);
  });

  testWidgets('voice lane: a verdict that degrades mid-session surfaces on '
      'the next tick, and a later failed read (unknown) does NOT clear the '
      'proven caution', (tester) async {
    verdict = VoiceLaneVerdict.offlineJaReady;
    await pumpApp(tester);
    expect(find.byKey(_voiceCautionKey), findsNothing);

    // The offline ja voice pack is removed mid-session.
    verdict = VoiceLaneVerdict.jaNetworkOnly;
    await tester.pump(_tick);
    await tester.pump();
    await tester.ensureVisible(find.byKey(_voiceCautionKey));
    expect(find.byKey(_voiceCautionKey), findsOneWidget);

    // A later read fails (engine hiccup): unknown must not hide the caution.
    verdict = VoiceLaneVerdict.unknown;
    await tester.pump(_tick);
    await tester.pump();
    expect(find.byKey(_voiceCautionKey), findsOneWidget,
        reason: 'A failed READ is not a proof of health; the proven caution '
            'stays until a proven verdict replaces it.');
  });

  testWidgets('drive start (mock-position tap) re-probes immediately — '
      'no 45 s wait while she pulls out of the driveway', (tester) async {
    probe.reading = _audible;
    await pumpApp(tester);
    final readsBefore = probe.reads;
    probe.reading = _muted;

    await tester.ensureVisible(find.byKey(const Key('use-mock-button')));
    await tester.tap(find.byKey(const Key('use-mock-button')));
    await tester.pump();
    await tester.pump();

    expect(probe.reads, greaterThan(readsBefore),
        reason: 'Drive start must re-read the probes.');
    await tester.ensureVisible(find.byKey(_mutedCautionKey));
    expect(find.byKey(_mutedCautionKey), findsOneWidget);
  });
}
