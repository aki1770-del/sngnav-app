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
      const real = 'ブラックアイスバーンに注意。路面が凍結しているおそれがあります。';
      expect(OfflineSafetyVoice.assetFor(real), isNotNull);

      // A single inserted space, a truncation, a different warning: all null.
      expect(OfflineSafetyVoice.assetFor('ブラックアイスバーン に注意。'), isNull);
      expect(OfflineSafetyVoice.assetFor('ブラックアイスバーンに注意。'), isNull);
      expect(OfflineSafetyVoice.assetFor('圧雪路面です。'), isNull);
      expect(OfflineSafetyVoice.assetFor(''), isNull);
    });

    test('whitespace around a real phrase still finds it', () {
      expect(
        OfflineSafetyVoice.assetFor('  $kConditionsUnknownJaSpokenText \n'),
        isNotNull,
      );
    });

    test('NO INVENTED PHRASES: every catalog string exists verbatim in shipping '
        'source', () {
      // Search this app's lib/ and the sibling catalog packages it depends on.
      final roots = <Directory>[
        Directory('lib'),
        Directory('/home/komada/SNGNav/packages'),
      ].where((d) => d.existsSync());

      final sources = <String>[
        for (final root in roots)
          for (final f in root
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))
              // Don't let the catalog vouch for itself.
              .where((f) => !f.path.endsWith('offline_safety_voice.dart')))
            f.readAsStringSync(),
      ];
      expect(sources, isNotEmpty, reason: 'no source read — test is vacuous');

      for (final e in kOfflineSafetyVoiceJa.entries) {
        expect(
          sources.any((s) => s.contains(e.value)),
          isTrue,
          reason: 'INVENTED PHRASE "${e.key}": «${e.value}» appears in no '
              'shipping source. The mouth may only speak what the app says.',
        );
      }
    });
  });
}
