// The spoken dead-zone forecast says whose forecast it is.
//
// WHY THIS TEST EXISTS
// In the dead zone, when the app holds a snow forecast that is valid for this
// hour, the forecast line is the one thing she hears about the road: it is
// spoken instead of 「路面状況を取得できていません。」. That forecast is always
// Akita Prefecture's. It is fetched before departure from JMA area 050000,
// wherever she is, and snow in any part of that forecast raises the line.
// Until 2026-09-25 the line named the publisher and when it was fetched, but
// not the place, so a driver in unexpected snow outside Akita heard Akita's
// forecast as if it were for her road. The line now names 秋田県, the same
// words the card's caption uses, and this test ties that name to the area the
// app actually fetches, to the words the offline clip is rendered from, and to
// the visible English line.
//
// If the forecast fetch ever follows her position, the first test fails, and
// the spoken line, its clip and the caption change together.
//
// BOUNDS
// - Lexical. It checks words and call sites, not what she hears. Whether the
//   clip says these words is checked byte for byte by
//   tool/offline_voice_render_guard.sh, and a person listens to every
//   re-rendered clip.
// - Naming the place does not make the line true for a driver outside Akita.
//   It lets her judge it. Speaking only inside the forecast area, or fetching
//   her own area, is a separate decision.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/jma_forecast_fetch.dart'
    show akitaForecastAreaCode;
import 'package:sngnav_app/services/trip_hazard_memory.dart'
    show kForecastSnowValidEn, kForecastSnowValidJa;
import 'package:sngnav_app/voice/offline_safety_voice.dart'
    show kOfflineSafetyVoiceJa, offlineSafetyRenderTextFor;

/// Every Dart file under lib/, with its source text.
Map<String, String> _libSources() => {
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        f.path: f.readAsStringSync(),
    };

void main() {
  group('The spoken dead-zone forecast says whose forecast it is', () {
    test("the forecast the app keeps is Akita Prefecture's: one call, no area",
        () {
      expect(akitaForecastAreaCode, '050000');

      final calls = <String>[];
      final seamSuppliers = <String>[];
      for (final e in _libSources().entries) {
        // A call site, not the definition (`fetchJmaForecast({`).
        for (final m in RegExp(r'fetchJmaForecast\((?!\{)[^)]*\)')
            .allMatches(e.value)) {
          calls.add('${e.key}: ${m.group(0)}');
        }
        // Production code must not hand the page a different forecast fetch;
        // only the pass-through `jmaForecastFetch: jmaForecastFetch` is allowed.
        for (final m
            in RegExp(r'jmaForecastFetch:\s*([^,)\s]+)').allMatches(e.value)) {
          if (m.group(1) != 'jmaForecastFetch') {
            seamSuppliers.add('${e.key}: ${m.group(0)}');
          }
        }
      }
      expect(
        calls,
        ['lib/main.dart: fetchJmaForecast(userAgent: kSngnavAppUserAgent)'],
        reason: 'The spoken line says the forecast is 秋田県の. That is true only '
            'while the one forecast fetch uses the default area 050000. A second '
            'call, or an area argument, means the line and its clip must change '
            'in the same change-set.',
      );
      expect(seamSuppliers, isEmpty,
          reason: 'production code supplies its own forecast fetch; the spoken '
              'place may no longer match what is fetched');
    });

    test('the spoken line names 秋田県 beside its publisher', () {
      expect(kForecastSnowValidJa, contains('秋田県の予報'),
          reason: 'she must hear whose forecast this is, not only who made it');
      expect(kForecastSnowValidJa, contains('気象庁'));
      // It says the forecast was fetched earlier, not when: 「出発前に」 is not
      // pinned here, because a memory refreshed during a drive was not
      // fetched before departure.
      expect(kForecastSnowValidJa, contains('取得した'));
      expect(kForecastSnowValidJa, contains('これは観測ではなく予報です'));
    });

    test('the offline clip is rendered from exactly these words', () {
      expect(kOfflineSafetyVoiceJa['forecast_snow_valid'], kForecastSnowValidJa,
          reason: 'the words are the lookup key for the clip; if they differ, '
              'the forecast is not spoken at all');
      expect(offlineSafetyRenderTextFor('forecast_snow_valid'),
          kForecastSnowValidJa,
          reason: 'a render override would let the clip say other words');
    });

    test('the visible English line names Akita Prefecture too', () {
      expect(kForecastSnowValidEn, contains('Akita Prefecture'));
      expect(kForecastSnowValidEn, contains('fetched'));
      expect(kForecastSnowValidEn,
          contains('This is a forecast, not an observation.'));
    });
  });
}
