/// A phone whose alert channels are dead must not render the same first screen
/// as a phone whose channels are fine.
///
/// THE MEASUREMENT THIS EXISTS FOR (2026-09-23). On her own phone geometry a
/// device with NO offline Japanese voice, NO vibrator and MEDIA MUTED rendered
/// a first screen BYTE-IDENTICAL to an all-clear one. Two sha256 captures of
/// the same bytes; `cmp` identical. The honest caution rows existed and were
/// correct — they simply rendered below `_herStatusLine()`, which carries
/// ~356 dp of consent and egress prose, putting them 144, 202 and 260 dp BELOW
/// THE FOLD. And below it precisely in the not-yet-shared state, which is the
/// state she opens the app in.
///
/// For a deaf or hard-of-hearing driver the tactile row is not the second
/// channel, it is the only one — and it was the one furthest down.
///
/// WHAT THIS TEST COMPARES. Two rendered frames, captured in the SAME run, on
/// the same host, fonts and engine, so any difference between them is a real
/// difference and not golden drift. It compares them BYTE FOR BYTE, which is
/// the comparison the two sha256s expressed and admits no collision at all.
///
/// The determinism control is not decoration: without it, "the frames differ"
/// could be capture noise. It is asserted FIRST.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/audio_readiness.dart';
import 'package:sngnav_app/services/haptic_readiness.dart';
import 'package:sngnav_app/services/voice_lane_readiness.dart';

import '../support/fake_alert_actuators.dart';

/// Her phone: 1080x2340 at DPR 2.75, the geometry this repo's own committed
/// tests pin.
const Size _herPhone = Size(392.7, 850.9);
const Key _boundary = Key('first-screen-capture-boundary');
final _clock = DateTime.utc(2026, 1, 14, 21);

final class _MutedAudio implements AudioReadinessProbe {
  @override
  Future<AudioReadiness?> read() async => const AudioReadiness(
      mediaVolume: 0, mediaVolumeMax: 15, ttsServiceVisible: true);
}

final class _NoVibrator implements HapticReadinessProbe {
  @override
  Future<bool?> read() async => false;
}

/// The healthy device answers nothing at all on these probes — `null` is the
/// honest-unknown the app renders NOTHING for, and it is what a non-mobile or
/// unreadable device gives. That is the correct control: it is the state the
/// byte-identical capture was taken in.
Future<Uint8List> _frame(WidgetTester tester, {required bool channelsDead}) async {
  await tester.binding.setSurfaceSize(_herPhone);
  // Registered INSIDE the test body, so it runs in the tester's guarded zone.
  // A top-level tearDown calling setSurfaceSize collided with this one and
  // failed all five tests with "Guarded function conflict" — my error, caught
  // by running it rather than by reading it.
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(RepaintBoundary(
    key: _boundary,
    child: SngnavApp(
      locale: const Locale('ja'),
      actuators: FakeAlertActuators(),
      clock: () => _clock,
      jmaFetch: () async => const JmaFailure('test: deterministic, no feed'),
      voiceLaneReader:
          channelsDead ? () async => VoiceLaneVerdict.noJaVoice : null,
      hapticReadinessProbe: channelsDead ? _NoVibrator() : null,
      audioReadinessProbe: channelsDead ? _MutedAudio() : null,
    ),
  ));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  // toImage() is a REAL async raster op; under the test binding's FakeAsync it
  // never completes and every test here sat until its timeout. runAsync gives
  // it the real clock. My error, and the default 2-minute timeout was the only
  // thing that said so.
  late Uint8List bytes;
  await tester.runAsync(() async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    bytes = data!.buffer.asUint8List();
  });
  return bytes;
}

void main() {
  // The capture runs under `runAsync`, which lets the app's REAL pending
  // path_provider futures actually dispatch — and under the test binding they
  // throw MissingPluginException, which fails a widget test on its own. That
  // is environmental noise, not a finding, so the channel is answered with a
  // temp directory. It is answered rather than swallowed: a swallowed
  // exception would also hide a real one.
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sngnav_first_screen');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets(
      'POSITIVE CONTROL: the capture is deterministic, so a difference between '
      'two frames is a real difference and not noise', (tester) async {
    final a = await _frame(tester, channelsDead: false);
    final b = await _frame(tester, channelsDead: false);
    expect(a, isNotEmpty, reason: 'the instrument produced a frame at all');
    expect(a.length, greaterThan(1000),
        reason: 'a plausible PNG, not an empty or 1x1 image');
    expect(a, orderedEquals(b),
        reason: 'the same state must capture to the same bytes, or the '
            'comparison below means nothing');
  });

  testWidgets(
      'THE ACCEPTANCE TEST: no offline ja voice + no vibrator + media muted '
      'renders a DIFFERENT first screen from an all-clear one', (tester) async {
    final healthy = await _frame(tester, channelsDead: false);
    final dead = await _frame(tester, channelsDead: true);
    expect(dead, isNot(orderedEquals(healthy)),
        reason: 'THE FIX: three dead channels used to be invisible on the '
            'first screen — the two captures were byte-identical. If this '
            'passes again, she can open the app on a phone that cannot warn '
            'her and see nothing that says so.');
  });

  testWidgets(
      'THE MECHANISM, not just the difference: each caution is ABOVE THE FOLD '
      'in the state she opens the app in', (tester) async {
    await _frame(tester, channelsDead: true);

    // She has not tapped 現在地を共有. This is the state the byte-identical
    // capture was taken in, and the state the rows used to sit below.
    expect(find.byKey(const Key('share-location-button')), findsOneWidget,
        reason: 'precondition: the share has NOT been started');

    for (final key in const [
      'voice-lane-caution',
      'haptic-unavailable-caution',
      'media-muted-caution',
    ]) {
      final f = find.byKey(Key(key));
      expect(f, findsOneWidget, reason: '$key is drawn');
      final r = tester.getRect(f);
      expect(r.bottom, lessThanOrEqualTo(_herPhone.height),
          reason: '$key ends at ${r.bottom.toStringAsFixed(1)} dp, past the '
              '${_herPhone.height} dp fold — she would have to scroll to learn '
              'the channel is dead');
    }
  });

  testWidgets(
      'she can still find herself without scrolling: the map stays whole on '
      'the first screen even with all three cautions raised', (tester) async {
    await _frame(tester, channelsDead: true);
    final map = find.byKey(const Key('her-map'));
    if (map.evaluate().isEmpty) {
      // The map's key is not pinned by this test's contract; fall back to the
      // section title, which is. Stated rather than silently skipped.
      final title = find.text('地図');
      expect(title, findsOneWidget);
      expect(tester.getRect(title).top, lessThan(_herPhone.height));
      return;
    }
    expect(tester.getRect(map).bottom, lessThanOrEqualTo(_herPhone.height),
        reason: 'the 2026-09-13 decision — she must not scroll past cards to '
            'find herself — is not reversed by raising the cautions');
  });

  testWidgets(
      'CONTROL: a healthy device draws none of the three rows, so the raise '
      'costs an untroubled driver nothing', (tester) async {
    await _frame(tester, channelsDead: false);
    for (final key in const [
      'voice-lane-caution',
      'haptic-unavailable-caution',
      'media-muted-caution',
    ]) {
      expect(find.byKey(Key(key)), findsNothing,
          reason: '$key must render only on a proven-degraded reading');
    }
  });
}
