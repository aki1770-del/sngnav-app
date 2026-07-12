/// THE HONEST GUARD — does the MOUTH cover what the APP ACTUALLY SAYS?
///
/// The enumeration lives in `runtime_emissions.dart` (it is shared with
/// `offline_safety_voice_test.dart`, whose provenance check now re-derives from
/// the SAME runtime emitters instead of grepping source trees).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/voice/offline_safety_voice.dart';

import 'runtime_emissions.dart';

void main() {
  test('MEASURE: the real emittable ja surface', () {
    final safety = emittableSafetyStaticJa();
    final nav = emittableNavStaticJa();
    final covered = safety.where(OfflineSafetyVoice.covers).length;
    final dead = kOfflineSafetyVoiceJa.values
        .where((t) => !safety.contains(t) && !nav.contains(t))
        .toList();
    // ignore: avoid_print
    print('SAFETY-class static emittable: ${safety.length}\n'
        'NAV-class static emittable (network-route only): ${nav.length}\n'
        'covered by the bundled mouth: $covered / ${safety.length}\n'
        'bundled phrases matching NO emittable string: ${dead.length} '
        '-> $dead');
  });

  test('THE HONEST GUARD: every SAFETY-class static string the app can EMIT '
      'at runtime is speakable offline', () {
    final safety = emittableSafetyStaticJa();
    final uncovered = safety.where((s) => !OfflineSafetyVoice.covers(s)).toList();
    expect(
      uncovered,
      isEmpty,
      reason: 'THE MOUTH CANNOT SAY ${uncovered.length} of ${safety.length} '
          'SAFETY-class lines the app EMITS at runtime:\n'
          '${uncovered.map((s) => '  - $s').join('\n')}',
    );
  });

  test('NO DEAD WEIGHT: every bundled phrase is a string the app can emit', () {
    final emittable = emittableSafetyStaticJa()..addAll(emittableNavStaticJa());
    final dead = kOfflineSafetyVoiceJa.entries
        .where((e) => !emittable.contains(e.value))
        .map((e) => '${e.key}: ${e.value}')
        .toList();
    expect(dead, isEmpty,
        reason: '${dead.length} bundled WAV(s) correspond to NO string the app '
            'can emit — dead weight in HER APK:\n${dead.join('\n')}');
  });
}
