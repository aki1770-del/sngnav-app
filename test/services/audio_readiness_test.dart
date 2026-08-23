// Tier-2 AudioReadinessProbe — host-side verification:
// (a) the AudioReadiness model's pct/muted edges (incl. the max==0 divide
//     guard);
// (b) ChannelAudioReadinessProbe decode over a mocked
//     sngnav/audio_readiness channel: success map -> reading,
//     MissingPluginException (old-APK-skew) -> null, malformed map -> null,
//     and the isMobileActuatorPlatform guard -> null WITHOUT invoking the
//     channel.
//
// HONESTY (OPS-066 / AAE env-bound): this verifies the DART side against a
// mocked messenger. Whether the Kotlin side replies with the real device
// volume is an on-device fact — verified separately on the emulator.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_app/services/audio_readiness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioReadiness model', () {
    test('pct: 0/15 -> 0, muted', () {
      const r = AudioReadiness(
          mediaVolume: 0, mediaVolumeMax: 15, ttsServiceVisible: true);
      expect(r.mediaVolumePct, 0);
      expect(r.mediaMuted, isTrue);
    });

    test('pct: 8/15 -> 53, not muted', () {
      const r = AudioReadiness(
          mediaVolume: 8, mediaVolumeMax: 15, ttsServiceVisible: true);
      expect(r.mediaVolumePct, 53);
      expect(r.mediaMuted, isFalse);
    });

    test('pct: full volume -> 100', () {
      const r = AudioReadiness(
          mediaVolume: 15, mediaVolumeMax: 15, ttsServiceVisible: true);
      expect(r.mediaVolumePct, 100);
    });

    test('max == 0 guard: no divide-by-zero, pct 0, muted', () {
      const r = AudioReadiness(
          mediaVolume: 0, mediaVolumeMax: 0, ttsServiceVisible: false);
      expect(r.mediaVolumePct, 0);
      expect(r.mediaMuted, isTrue);
    });

    test('volume 1 (lowest non-zero) is NOT muted', () {
      const r = AudioReadiness(
          mediaVolume: 1, mediaVolumeMax: 15, ttsServiceVisible: true);
      expect(r.mediaMuted, isFalse);
      expect(r.mediaVolumePct, 7);
    });
  });

  group('ChannelAudioReadinessProbe', () {
    const channel = MethodChannel('sngnav/audio_readiness');
    final messenger = TestWidgetsFlutterBinding.instance
        .defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('success map -> reading with all three fields', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'read');
        return <String, Object?>{
          'mediaVolume': 0,
          'mediaVolumeMax': 15,
          'ttsServiceVisible': true,
        };
      });
      const probe = ChannelAudioReadinessProbe(platformSupported: true);
      final reading = await probe.read();
      expect(reading, isNotNull);
      expect(reading!.mediaVolume, 0);
      expect(reading.mediaVolumeMax, 15);
      expect(reading.ttsServiceVisible, isTrue);
      expect(reading.mediaMuted, isTrue);
    });

    test('MissingPluginException (old APK without the channel) -> null, '
        'never throws', () async {
      // No mock handler registered -> invokeMethod throws
      // MissingPluginException.
      const probe = ChannelAudioReadinessProbe(platformSupported: true);
      await expectLater(probe.read(), completion(isNull));
    });

    test('PlatformException -> null, never throws', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'boom');
      });
      const probe = ChannelAudioReadinessProbe(platformSupported: true);
      await expectLater(probe.read(), completion(isNull));
    });

    test('malformed map (wrong types) -> null', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        return <String, Object?>{
          'mediaVolume': 'zero', // wrong type
          'mediaVolumeMax': 15,
          'ttsServiceVisible': true,
        };
      });
      const probe = ChannelAudioReadinessProbe(platformSupported: true);
      await expectLater(probe.read(), completion(isNull));
    });

    test('missing keys -> null', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        return <String, Object?>{'mediaVolume': 3};
      });
      const probe = ChannelAudioReadinessProbe(platformSupported: true);
      await expectLater(probe.read(), completion(isNull));
    });

    test('non-map reply -> null', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => 42);
      const probe = ChannelAudioReadinessProbe(platformSupported: true);
      await expectLater(probe.read(), completion(isNull));
    });

    test('platform guard (default: test binding is non-mobile) -> null '
        'WITHOUT invoking the channel', () async {
      var invoked = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        invoked = true;
        return <String, Object?>{
          'mediaVolume': 0,
          'mediaVolumeMax': 15,
          'ttsServiceVisible': true,
        };
      });
      // No platformSupported override: isMobileActuatorPlatform is false
      // under the FLUTTER_TEST binding, so the channel must never be hit.
      const probe = ChannelAudioReadinessProbe();
      await expectLater(probe.read(), completion(isNull));
      expect(invoked, isFalse);
    });
  });

  // ⚑ MEASURED ON A DEVICE 2026-08-22, AVD sngnav_api30 running -no-audio:
  //   `dumpsys audio` -> "STREAM_MUSIC: Muted: true"
  //   the app's probe   -> mediaVolume 5 of 15 -> mediaMuted FALSE
  // Nothing came out of that device, and HER caution row said nothing. Index
  // and mute are two different platform facts and Android exposes them
  // through two different calls; reading only the index reports a muted
  // stream as audible. The same shape as every other defect in this tree:
  // an absent measurement rendered as the safe value.
  group('a stream can be MUTED at a non-zero index', () {
    test('muted stream with volume 5 of 15 -> mediaMuted', () {
      const r = AudioReadiness(
        mediaVolume: 5,
        mediaVolumeMax: 15,
        ttsServiceVisible: true,
        streamMuted: true,
      );
      expect(r.mediaMuted, isTrue);
      expect(r.mediaVolumePct, 33, reason: 'the index is unchanged and honest');
    });

    test('CONTROL: not muted at volume 5 -> audible, no cry-wolf', () {
      const r = AudioReadiness(
        mediaVolume: 5,
        mediaVolumeMax: 15,
        ttsServiceVisible: true,
        streamMuted: false,
      );
      expect(r.mediaMuted, isFalse);
    });

    test('CONTROL: mute state UNKNOWN (older APK sends no key) falls back to '
        'the index alone — honest-unknown, never a guess', () {
      const r = AudioReadiness(
        mediaVolume: 5,
        mediaVolumeMax: 15,
        ttsServiceVisible: true,
      );
      expect(r.streamMuted, isNull);
      expect(r.mediaMuted, isFalse);
    });

    test('a zero index is still muted regardless of the mute flag', () {
      const r = AudioReadiness(
        mediaVolume: 0,
        mediaVolumeMax: 15,
        ttsServiceVisible: true,
        streamMuted: false,
      );
      expect(r.mediaMuted, isTrue);
    });
  });

  group('ChannelAudioReadinessProbe carries the mute flag', () {
    const channel = MethodChannel('sngnav/audio_readiness');
    final messenger =
        TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('streamMuted: true decodes and mutes at a non-zero index', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        return <String, Object?>{
          'mediaVolume': 5,
          'mediaVolumeMax': 15,
          'ttsServiceVisible': true,
          'streamMuted': true,
        };
      });
      const probe = ChannelAudioReadinessProbe(platformSupported: true);
      final reading = await probe.read();
      expect(reading, isNotNull);
      expect(reading!.streamMuted, isTrue);
      expect(reading.mediaMuted, isTrue);
    });

    test('an APK that predates the key still decodes — skew tolerance is not '
        'traded away for the new field', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        return <String, Object?>{
          'mediaVolume': 5,
          'mediaVolumeMax': 15,
          'ttsServiceVisible': true,
        };
      });
      const probe = ChannelAudioReadinessProbe(platformSupported: true);
      final reading = await probe.read();
      expect(reading, isNotNull, reason: 'a missing key is unknown, not junk');
      expect(reading!.streamMuted, isNull);
      expect(reading.mediaMuted, isFalse);
    });

    test('a WRONG-TYPED streamMuted is junk, not unknown -> null', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        return <String, Object?>{
          'mediaVolume': 5,
          'mediaVolumeMax': 15,
          'ttsServiceVisible': true,
          'streamMuted': 'yes',
        };
      });
      const probe = ChannelAudioReadinessProbe(platformSupported: true);
      await expectLater(probe.read(), completion(isNull));
    });
  });
}
