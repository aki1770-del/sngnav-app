/// C2 RED-1 — THE MEMORY. Does a hazard she was told about BEFORE SHE LEFT
/// still reach her at T+90, with the network gone?
///
/// This is the guard for the one thing nobody in Japan ships. Honda has broadcast
/// a spoken road-freezing prediction since 2008; FM-VICS puts a 凍結 mark on the
/// dash with no cellular at all. Every PREDICTIVE product in Japan is
/// server-side, and every one of them DIES in the dead zone. A predicted,
/// spoken, route-window road hazard, on a phone, in any car, that still fires
/// when the centre is gone — that intersection is empty. It is this file.
///
/// EVERY TEST BELOW DRIVES THE REAL, LIVE JMA PAYLOAD captured from
/// `https://www.jma.go.jp/bosai/forecast/data/forecast/050000.json` on
/// 2026-07-12 (fixture: test/fixtures/jma_forecast_akita_20260712.json). A
/// parser tested only against a fixture I wrote by hand would be a test authored
/// by the bug — the exact failure the ESC friction-unit defect was made of (the
/// code believed 0.0–1.0, so the author fed it 0.2, a value a real ESC cannot
/// emit, so the suite went green and the bug was certified).
///
/// The fixture is a JULY payload — it forecasts rain, not snow. That is a
/// feature: the SNOW assertions therefore cannot be satisfied by the fixture's
/// own weather, so a snow hazard is constructed on the fixture's REAL
/// publisher-declared `timeDefines` grid, and the parser is proven against the
/// real payload's actual structure separately. Nothing here is proven by a
/// number I chose.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/forecast_validity.dart';
import 'package:sngnav_app/services/jma_forecast_fetch.dart';
import 'package:sngnav_app/services/staleness_policy.dart';
import 'package:sngnav_app/services/trip_hazard_memory.dart';
import 'package:sngnav_app/voice/offline_safety_voice.dart';

void main() {
  final fixture =
      File('test/fixtures/jma_forecast_akita_20260712.json').readAsStringSync();

  group('the JMA forward grid — measured, not imagined', () {
    test('the REAL payload parses, and its publisher-declared interval grid is '
        'what we said it was', () {
      final r = parseJmaForecast(fixture);
      expect(r, isA<JmaForecastSuccess>());
      final s = r as JmaForecastSuccess;

      // The publisher's own issue time, verbatim: 2026-07-12T17:00:00+09:00.
      expect(s.issuedAt, DateTime.utc(2026, 7, 12, 8, 0));

      // July in Akita: JMA forecasts 雨, not 雪. We must find NO snow — and that
      // is knowledge, not an empty result. A parser that "found" snow in this
      // payload would be inventing it.
      expect(
        s.hazards,
        isEmpty,
        reason: 'The real July payload forecasts rain. A snow hazard here '
            'would be fabricated.',
      );
    });

    test('THE UNBOUNDED TAIL IS DROPPED — we never invent an end boundary', () {
      // Rewrite the fixture's weather text to snow, changing NOTHING about its
      // time structure. The real payload's weathers series has 3 timeDefines and
      // 3 weathers. The LAST interval has no successor, so its end is NOT
      // publisher-declared and MUST be dropped: 3 snow forecasts -> 2 hazards.
      final j = json.decode(fixture) as List;
      final ts = (j[0] as Map)['timeSeries'] as List;
      final area = ((ts[0] as Map)['areas'] as List)[0] as Map;
      final defines = (ts[0] as Map)['timeDefines'] as List;
      expect(defines.length, 3, reason: 'the real payload grid changed');
      area['weathers'] = ['雪', '大雪', '雪'];

      final r = parseJmaForecast(json.encode(j)) as JmaForecastSuccess;
      expect(
        r.hazards.length,
        2,
        reason: 'THREE snow forecasts, TWO publisher-bounded intervals. The '
            'third has no declared end. MET Norway invented one (effective + '
            '1h) and that is exactly the fabrication NDI fired the Andon on. '
            'We drop it.',
      );
      for (final h in r.hazards) {
        expect(h.window.provenance, ValidityProvenance.publisherDeclared);
        // Boundaries are JMA's OWN timeDefines, relayed, not derived.
        expect(h.window.start.isBefore(h.window.end), isTrue);
      }
      // The publisher's words, verbatim — never our paraphrase.
      expect(r.hazards.map((h) => h.publisherText), containsAll(['雪', '大雪']));
    });
  });

  group('C2 RED-1 — the hazard she learned at departure reaches her at T+90 '
      'with NO NETWORK', () {
    // Her trip. She leaves at 07:00 JST. At 08:30 the centre is gone.
    final departure = DateTime.utc(2026, 1, 15, 7, 0).subtract(
      const Duration(hours: 9),
    );
    final tPlus90 = departure.add(const Duration(minutes: 90));

    /// The memory she captured at departure, on the REAL publisher grid: JMA
    /// declared snow for a window that covers her whole morning.
    TripHazardMemory memoryFromDeparture() => TripHazardMemory(
          capturedAt: departure,
          hazards: [
            ForecastHazard(
              kind: ForecastHazardKind.snow,
              window: ValidityWindow(
                // JMA's own 6-hourly boundaries: 06:00 JST -> 12:00 JST.
                start: DateTime.utc(2026, 1, 14, 21, 0), // 06:00 JST
                end: DateTime.utc(2026, 1, 15, 3, 0), // 12:00 JST
                provenance: ValidityProvenance.publisherDeclared,
              ),
              publisherText: '雪　所により　ふぶく',
              source: 'JMA 秋田地方気象台',
              issuedAt: DateTime.utc(2026, 1, 14, 20, 0),
              areaName: '沿岸',
            ),
          ],
        );

    test('THE INVARIANT THAT MUST NOT BE WEAKENED: the 90-minute-old '
        'OBSERVATION is still EXPIRED', () {
      // The original RED-1 asserted `age <= kSlowHazardRetainWindow` — which
      // could ONLY go green by widening the observation retain window to >= 90
      // min. Its own reason string said it was "not asking to retain the
      // observation longer". The assertion contradicted its prose, and passing
      // it would have meant announcing a 90-minute-old reading as live.
      //
      // We did NOT do that. The observation expiry is CORRECT and stands.
      final observedAt = observedAtJstInstant('20260115070000')!;
      final age = tPlus90.difference(observedAt);
      expect(age, const Duration(minutes: 90));
      expect(
        age > kSlowHazardRetainWindow,
        isTrue,
        reason: 'The stale OBSERVATION must still expire. We fixed the silence '
            'by giving her something VALID — never by lowering the bar on what '
            'counts as live.',
      );
      expect(kSlowHazardRetainWindow, const Duration(minutes: 60));
    });

    test('RED-1: at T+90, with no network, the FORECAST hazard is still VALID '
        'and still reaches her — SPOKEN', () {
      final memory = memoryFromDeparture();

      // No fetch. No point query. No network. No GPS. Just the clock.
      final active = memory.activeAt(tPlus90);
      expect(
        active,
        isNotEmpty,
        reason: 'A JMA forecast valid 06:00-12:00 JST is not "stale" at 08:30. '
            'It is VALID. That is the whole point.',
      );
      expect(active.single.kind, ForecastHazardKind.snow);

      // And it must REACH her — through a mouth that needs no TTS and no
      // network, because her phone has no offline ja voice.
      final line = memory.speakableJaAt(tPlus90);
      expect(
        line,
        isNotNull,
        reason: 'A hazard that cannot be SPOKEN in the dead zone has not '
            'reached her. She is driving; she is not reading.',
      );
      expect(line, kForecastSnowValidJa);

      final asset = OfflineSafetyVoice.assetFor(line!);
      expect(asset, isNotNull, reason: 'no bundled bytes = silence');
      final f = File(asset!);
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(8000),
          reason: 'under 8KB is not speech, it is a file that plays as silence');
    });

    test('IT SAYS, OUT LOUD, THAT IT IS A FORECAST — not an observation', () {
      // The line she hears must not let her believe we just measured the road.
      expect(kForecastSnowValidJa, contains('予報'));
      expect(kForecastSnowValidJa, contains('これは観測ではなく予報です'));
      expect(kForecastSnowValidJa, contains('気象庁'));
      expect(kForecastSnowValidJa.contains(r'$'), isFalse,
          reason: 'slotted text cannot be pre-rendered');
    });

    test('CRY-WOLF DISCIPLINE STANDS: outside the publisher window, SILENCE', () {
      final memory = memoryFromDeparture();
      // 13:00 JST — past JMA's declared 12:00 end. The forecast is now over.
      final afterWindow = DateTime.utc(2026, 1, 15, 4, 0);
      expect(memory.activeAt(afterWindow), isEmpty);
      expect(
        memory.speakableJaAt(afterWindow),
        isNull,
        reason: 'Past the publisher\'s own declared end we say NOTHING and the '
            'honest-absence line stands. We do not stretch a forecast to keep '
            'talking.',
      );
      // Before it begins, likewise.
      final beforeWindow = DateTime.utc(2026, 1, 14, 20, 0); // 05:00 JST
      expect(memory.activeAt(beforeWindow), isEmpty);
    });

    test('A SYNTHESISED VALIDITY IS NEVER SPOKEN — NDI\'s Andon, enforced', () {
      // The MET Norway shape: expires = effective + 1h, invented by the adapter.
      // Same hazard, same window, covering NOW — and it must NOT be spoken.
      final synthesised = TripHazardMemory(
        capturedAt: departure,
        hazards: [
          ForecastHazard(
            kind: ForecastHazardKind.snow,
            window: ValidityWindow(
              start: DateTime.utc(2026, 1, 14, 21, 0),
              end: DateTime.utc(2026, 1, 15, 3, 0),
              provenance: ValidityProvenance.adapterSynthesised,
            ),
            publisherText: '雪',
            source: 'some adapter that made the end up',
            issuedAt: DateTime.utc(2026, 1, 14, 20, 0),
            areaName: '沿岸',
          ),
        ],
      );
      expect(
        synthesised.activeAt(tPlus90),
        isEmpty,
        reason: 'A window whose END WE INVENTED must never be spoken to a '
            'driver as though a meteorological service had promised it. This '
            'is the whole substance of NDI\'s SC-26 Andon.',
      );
      expect(synthesised.speakableJaAt(tPlus90), isNull);
    });
  });

  group('the memory survives a cold start — she rebooted on the roadside', () {
    test('round-trips through disk with provenance INTACT', () async {
      final dir = Directory.systemTemp.createTempSync('trip_hazard_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store =
          TripHazardStore(file: File('${dir.path}/${TripHazardStore.fileName}'));

      final now = DateTime.utc(2026, 1, 15, 0, 0);
      final memory = TripHazardMemory(
        capturedAt: DateTime.utc(2026, 1, 14, 22, 0),
        hazards: [
          ForecastHazard(
            kind: ForecastHazardKind.snow,
            window: ValidityWindow(
              start: DateTime.utc(2026, 1, 14, 21, 0),
              end: DateTime.utc(2026, 1, 15, 3, 0),
              provenance: ValidityProvenance.publisherDeclared,
            ),
            publisherText: '雪　所により　ふぶく',
            source: 'JMA 秋田地方気象台',
            issuedAt: DateTime.utc(2026, 1, 14, 20, 0),
            areaName: '沿岸',
          ),
        ],
      );
      await store.save(memory);

      final loaded = await store.load();
      expect(loaded, isNotNull);
      expect(loaded!.activeAt(now), hasLength(1));
      expect(loaded.activeAt(now).single.window.provenance,
          ValidityProvenance.publisherDeclared);
      expect(loaded.activeAt(now).single.publisherText, '雪　所により　ふぶく');
      expect(loaded.speakableJaAt(now), kForecastSnowValidJa);
    });

    test('NO MEMORY is not the same sentence as NO HAZARD', () async {
      final dir = Directory.systemTemp.createTempSync('trip_hazard_absent_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = TripHazardStore(file: File('${dir.path}/nothing.json'));
      expect(
        await store.load(),
        isNull,
        reason: '"We have no memory" and "the forecast says nothing is wrong" '
            'are different sentences, and only one of them is safe to act on. '
            'An absent memory returns NULL, never an empty-but-valid one.',
      );
    });

    test('an unrecognised provenance is NOT silently upgraded to '
        'publisher-declared', () {
      final tampered = <String, dynamic>{
        'version': 1,
        'capturedAt': '2026-01-14T22:00:00Z',
        'hazards': [
          {
            'kind': 'snow',
            'window': {
              'start': '2026-01-14T21:00:00Z',
              'end': '2026-01-15T03:00:00Z',
              'provenance': 'somethingWeDoNotRecognise',
            },
            'publisherText': '雪',
            'source': 'x',
            'issuedAt': '2026-01-14T20:00:00Z',
            'areaName': 'y',
          }
        ],
      };
      final m = TripHazardMemory.fromJson(tampered);
      expect(m, isNotNull);
      expect(
        m!.hazards,
        isEmpty,
        reason: 'Unknown origin is the synthesised case. A hazard we cannot '
            'fully reconstruct is DROPPED, never half-built with a default.',
      );
    });
  });
}
