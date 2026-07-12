/// The mouth, held to its own contract.
///
/// Three things must stay true, or the offline voice quietly becomes a liability
/// instead of a safeguard:
///
///   1. NO INVENTED PHRASES. Every string in the catalog must be a verbatim
///      string that already exists in shipping source (this app, or the packages
///      it depends on). A phrase authored here and rendered to audio would be
///      words this app never actually says — spoken into a car, on ice.
///   2. NO MISSING BYTES. Every catalog entry must have a rendered, non-empty
///      asset, and every asset must be declared to the bundler. A phrase with no
///      file is silence wearing a warning's name.
///   3. NO WRONG WORDS. Lookup is exact-match. A fuzzy match could answer one
///      warning with the audio of another, which on a road the driver cannot see
///      is worse than saying nothing.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/staleness_policy.dart';
import 'package:sngnav_app/voice/offline_safety_voice.dart';

import 'runtime_emissions.dart';

void main() {
  group('offline safety voice — the finite mouth', () {
    test('the catalog is non-empty and every entry is slotless', () {
      expect(kOfflineSafetyVoiceJa, isNotEmpty);
      for (final e in kOfflineSafetyVoiceJa.entries) {
        expect(
          e.value.contains(r'$'),
          isFalse,
          reason: 'Slotted text cannot be pre-rendered: ${e.key}',
        );
        expect(e.value.trim(), e.value, reason: 'untrimmed: ${e.key}');
      }
    });

    test('every phrase has a rendered, non-trivial audio asset', () {
      for (final e in kOfflineSafetyVoiceJa.entries) {
        final f = File('${OfflineSafetyVoice.assetDir}/${e.key}.wav');
        expect(
          f.existsSync(),
          isTrue,
          reason: 'MISSING AUDIO for "${e.key}". '
              'Re-render: bash tool/render_offline_voice.sh',
        );
        // A RIFF header alone is ~44 bytes. Anything under a few KB is not
        // speech — it is a file that would play as silence and look fine.
        expect(
          f.lengthSync(),
          greaterThan(8000),
          reason: 'Audio for "${e.key}" is too small to be speech '
              '(${f.lengthSync()} bytes) — it would play as silence.',
        );
      }
    });

    test('the assets directory is declared to the bundler', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        pubspec.contains('- assets/audio/ja/'),
        isTrue,
        reason: 'Rendered audio that is not declared in pubspec ships as '
            'NOTHING — the files exist on the bench and not on the phone.',
      );
    });

    test('the honest-absence line is in the mouth — it is the one she hears '
        'when we know nothing', () {
      expect(
        OfflineSafetyVoice.covers(kConditionsUnknownJaSpokenText),
        isTrue,
        reason: 'The absence line was spoken through a TTS that is silent with '
            'no network. It is the single most likely thing to be said in the '
            'dead zone, and it must be bundled.',
      );
    });

    test('lookup is exact — a near-miss resolves to NOTHING, never to the '
        'wrong warning', () {
      // The REAL live black-ice line the app emits (snow_rendering
      // invisibleBlackIceAnnouncement.jaSpokenText, main.dart:1161).
      final real = kOfflineSafetyVoiceJa['black_ice_live']!;
      expect(OfflineSafetyVoice.assetFor(real), isNotNull);

      // A truncation, an inserted space, a different warning: all null.
      expect(OfflineSafetyVoice.assetFor('ブラックアイスバーンに注意。'), isNull);
      expect(OfflineSafetyVoice.assetFor('ブラックアイスバーン に注意。'), isNull);
      expect(OfflineSafetyVoice.assetFor('圧雪路面です。'), isNull);
      expect(OfflineSafetyVoice.assetFor(''), isNull);
    });

    test('whitespace around a real phrase still finds it', () {
      expect(
        OfflineSafetyVoice.assetFor('  $kConditionsUnknownJaSpokenText \n'),
        isNotNull,
      );
    });

    // PROVENANCE, RE-GROUNDED (2026-07-12). The previous version of this test
    // grepped `lib/` and the SNGNav monorepo WORKING TREE for each phrase. That
    // is exactly how the fabricated 10-phrase mouth passed: the monorepo source
    // is NOT what this app resolves (it resolves snow_rendering 0.2.7 /
    // navigation_safety_core 0.10.5 from pub.dev), so a string that lives only
    // in an unpublished package the app never calls was blessed as "shipping
    // source" — while not one line the app actually emits was in the mouth.
    //
    // Provenance is now proven the only honest way: every catalog phrase must
    // be a string produced BY CALLING the production emitters at the resolved
    // package versions. Strictly stronger than the grep — a grep can match text
    // in code no call path reaches; this cannot.
    test('NO INVENTED PHRASES: every catalog string is produced by a real '
        'runtime emitter', () {
      final emittable = emittableSafetyStaticJa();
      expect(emittable, isNotEmpty, reason: 'no emissions — test is vacuous');
      for (final e in kOfflineSafetyVoiceJa.entries) {
        expect(
          emittable.contains(e.value),
          isTrue,
          reason: 'INVENTED PHRASE "${e.key}": «${e.value}» is emitted by no '
              'runtime call path. The mouth may only speak what the app says.',
        );
      }
    });
  });
}
