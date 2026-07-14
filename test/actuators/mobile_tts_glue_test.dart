/// B31 — a delivered warning must clear the "delivery unverified" caution
/// regardless of WHICH mouth delivered it.
///
/// The 「音声警告を確認できませんでした」 chip was cleared only by the TTS
/// engine's onSpeechVerified — but the finite ja safety core deliberately
/// never routes to TTS (it plays from bundled bytes). So one unverified TTS
/// phrase left the chip stuck on screen through every later bundled warning
/// that DID reach her: the screen said "voice unverified" while the voice was
/// verifiably speaking. [buildMobileTtsEngine] now wires
/// BundledAudioEngine.onBundledSpoken to the same onSpeechVerified callback;
/// these tests pin that glue through the REAL production factory (with only
/// the platform play seam injected).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/actuators/mobile_alert_actuators.dart';
import 'package:sngnav_app/services/staleness_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildMobileTtsEngine — onSpeechVerified glue (B31)', () {
    test('a successful bundled play fires onSpeechVerified (clears the chip)',
        () async {
      var verified = 0;
      var unverified = 0;
      final engine = buildMobileTtsEngine(
        onSpeechVerified: () => verified++,
        onSpeechUnverified: () => unverified++,
        playAsset: (_, _) async => true, // playback completed
      );
      await engine.speak(kConditionsUnknownJaSpokenText);
      expect(verified, 1,
          reason: 'The bundled mouth verifiably delivered the phrase; the '
              'unverified chip must clear exactly as it does on a verified '
              'TTS utterance.');
      expect(unverified, 0);
    });

    test('a bundled play the platform did NOT complete does not claim '
        'verification', () async {
      var verified = 0;
      final engine = buildMobileTtsEngine(
        onSpeechVerified: () => verified++,
        playAsset: (_, _) async => false, // never completed
      );
      await engine.speak(kConditionsUnknownJaSpokenText);
      expect(verified, 0,
          reason: 'False from the platform means she was not verifiably '
              'spoken to; the chip must NOT be cleared on a claim.');
    });
  });
}
