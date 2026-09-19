// AAE 2026-09-02, re-landed on `0bc7351` 2026-09-19 — the LAST HOP:
// a mid-drive mute at a NON-ZERO volume index.
//
// `streamMuted` exists precisely because index and mute are two different
// Android facts (audio_readiness.dart, MainActivity.kt `sngnav/audio_readiness`).
// This test asks the only question that matters for HER: when the platform
// flips STREAM_MUSIC to muted WITHOUT moving the volume index, does the
// caution reach her screen?
//
// On `0bc7351` — the signed 0.0.2+3 build — it did NOT. The 45 s poll-dedup in
// main.dart compared mediaVolume / mediaVolumeMax / ttsServiceVisible by hand
// and omitted streamMuted, so the reading returned early and `_audioReadiness`
// kept its old value. She drove on believing the spoken ja warning would sound.
//
// The pre-existing fake probe returns ONE fixed reading, so no existing test
// could ever express a SECOND, different poll — the instrument could not have
// surfaced this counter-example. That is why this file adds a sequence probe.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/audio_readiness.dart';

import '../support/fake_alert_actuators.dart';

/// A probe whose answer CHANGES between polls — what the real device does.
final class _SequenceProbe implements AudioReadinessProbe {
  _SequenceProbe(this._readings);
  final List<AudioReadiness?> _readings;
  int _i = 0;
  int get reads => _i;
  @override
  Future<AudioReadiness?> read() async {
    final r = _readings[_i < _readings.length ? _i : _readings.length - 1];
    _i++;
    return r;
  }
}

void main() {
  const cautionKey = Key('media-muted-caution');

  // Index 5 of 15 the WHOLE time. Only the platform mute bit moves.
  const audibleAtIndex5 = AudioReadiness(
    mediaVolume: 5,
    mediaVolumeMax: 15,
    ttsServiceVisible: true,
    streamMuted: false,
  );
  const mutedAtIndex5 = AudioReadiness(
    mediaVolume: 5,
    mediaVolumeMax: 15,
    ttsServiceVisible: true,
    streamMuted: true,
  );

  testWidgets('MID-DRIVE mute at an UNCHANGED index reaches HER screen',
      (tester) async {
    final probe = _SequenceProbe([audibleAtIndex5, mutedAtIndex5]);
    await tester.pumpWidget(SngnavApp(
      locale: const Locale('ja'),
      actuators: FakeAlertActuators(),
      audioReadinessProbe: probe,
    ));
    await tester.pump();
    await tester.pump();

    // Poll 1: audible. Nothing shown — correct.
    expect(find.byKey(cautionKey), findsNothing,
        reason: 'poll 1 is audible; nothing should render');

    // The 45 s ticker fires -> poll 2 reports MUTED at the same index.
    await tester.pump(const Duration(seconds: 46));
    await tester.pump();
    await tester.pump();

    expect(probe.reads, greaterThanOrEqualTo(2),
        reason: 'the ticker must actually have re-polled');

    // HER screen must now say the spoken lane is silent.
    expect(find.byKey(cautionKey), findsOneWidget,
        reason: 'STREAM_MUSIC went MUTED at an unchanged volume index — the '
            'exact case streamMuted was added for. She is driving toward a '
            'whiteout believing the ja warning will sound.');
  });

  test('the value carries every field, so the next one added is covered too',
      () {
    expect(audibleAtIndex5 == mutedAtIndex5, isFalse,
        reason: 'the ONLY differing field is streamMuted; a hand-written '
            'three-field compare called these equal');
    expect(audibleAtIndex5 == audibleAtIndex5, isTrue);
    expect(audibleAtIndex5.hashCode == mutedAtIndex5.hashCode, isFalse);
  });
}
