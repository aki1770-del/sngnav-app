// Tier-2 audio readiness — widget wiring:
// (a) a proven-muted probe reading renders the media-muted caution row in
//     the pre-drive voice-lane region (ja primary; en fallback);
// (b) tapping 承知しました collapses it to the compact acknowledged line
//     (informed acknowledgment — never a block, never a volume touch);
// (c) unmuted reading and null probe result render NOTHING (honest-unknown
//     is never a guess).
//
// HONESTY (OPS-066 / AAE env-bound): verifies the WIDGET TREE against a
// fake probe. Whether the real Kotlin channel reports the device's actual
// media volume is an on-device fact — verified separately on the emulator.

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
    AudioReadinessProbe? probe,
    Locale locale = const Locale('ja'),
  }) async {
    await tester.pumpWidget(SngnavApp(
      locale: locale,
      actuators: FakeAlertActuators(),
      audioReadinessProbe: probe,
    ));
    // Two pumps: one for first build, one for the async reading setState.
    await tester.pump();
    await tester.pump();
  }

  const cautionKey = Key('media-muted-caution');
  const ackButtonKey = Key('media-muted-ack-button');
  const ackedKey = Key('media-muted-acked');

  const muted = AudioReadiness(
      mediaVolume: 0, mediaVolumeMax: 15, ttsServiceVisible: true);
  const audible = AudioReadiness(
      mediaVolume: 8, mediaVolumeMax: 15, ttsServiceVisible: true);

  testWidgets('muted reading -> the media-muted caution row renders with '
      'the ja text + acknowledge action', (tester) async {
    await pumpApp(tester, probe: _FakeProbe(muted));

    await tester.ensureVisible(find.byKey(cautionKey));
    expect(find.byKey(cautionKey), findsOneWidget);
    expect(
      find.text('メディア音量がゼロです。音声警告が聞こえません。振動でお知らせします。'),
      findsOneWidget,
    );
    expect(find.byKey(ackButtonKey), findsOneWidget);
    expect(find.text('承知しました（振動のみで続行）'), findsOneWidget);
    expect(find.byKey(ackedKey), findsNothing);
  });

  testWidgets('muted, en locale -> en fallback line', (tester) async {
    await pumpApp(tester,
        probe: _FakeProbe(muted), locale: const Locale('en'));

    await tester.ensureVisible(find.byKey(cautionKey));
    expect(
      find.text('Media volume is zero — spoken alerts cannot be heard. '
          'Haptic alerts will still notify you.'),
      findsOneWidget,
    );
  });

  testWidgets('acknowledge tap -> caution collapses to the compact '
      'acknowledged line', (tester) async {
    await pumpApp(tester, probe: _FakeProbe(muted));

    await tester.ensureVisible(find.byKey(ackButtonKey));
    await tester.tap(find.byKey(ackButtonKey));
    await tester.pump();

    expect(find.byKey(cautionKey), findsNothing);
    expect(find.byKey(ackedKey), findsOneWidget);
    expect(find.text('振動のみモード承知済み'), findsOneWidget);
  });

  testWidgets('audible reading -> NOTHING rendered', (tester) async {
    await pumpApp(tester, probe: _FakeProbe(audible));
    expect(find.byKey(cautionKey), findsNothing);
    expect(find.byKey(ackedKey), findsNothing);
  });

  testWidgets('null probe result (probe unavailable) -> NOTHING rendered, '
      'never a guessed warning', (tester) async {
    await pumpApp(tester, probe: _FakeProbe(null));
    expect(find.byKey(cautionKey), findsNothing);
    expect(find.byKey(ackedKey), findsNothing);
  });

  testWidgets('no probe injected (real channel probe under the test '
      'binding -> null) -> NOTHING rendered', (tester) async {
    await pumpApp(tester, probe: null);
    expect(find.byKey(cautionKey), findsNothing);
    expect(find.byKey(ackedKey), findsNothing);
  });
}
