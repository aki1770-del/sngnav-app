/// C2 — OFFLINE SURVIVAL. The red test.
///
/// BETA_PLAN.md:24
///   | C2 | Offline survival: map + alerts through airplane-mode mid-drive,
///          device-verified | ⬜ | — |
///
/// C2 has been written since 2026-07-08 and has bound NOTHING: no CI job, no
/// hook, no test ever consumed its ⬜. Nobody attempted it — and that is what
/// concealed that it is currently UNSATISFIABLE BY CONSTRUCTION. This file makes
/// C2 cross a tool boundary for the first time (L34: a guard is not INSERTED
/// until it has been PROVEN to FAIL; §11 WHY-9: a verdict that crosses no tool
/// boundary is optional exactly when it is most needed).
///
/// THE GENBA (measured 2026-07-12, not designed). HER phone, 90 minutes into the
/// drive to her mother in Akita, network gone, GPS degraded:
///
///   MAP      present — assets/tiles/akita_offline.mbtiles (16 MB, bundled)
///   HAZARD   absent  — kSlowHazardRetainWindow = 60 min; at T+90 the last
///                      observation has EXPIRED. She gets the honest absence
///                      line. Nothing else exists to say.
///   VOICE    absent  — the speech path is flutter_tts (system TTS), measured
///                      this day as silent-then-hung offline on her device. The
///                      repo contained ZERO bundled audio.
///
///   => She has a map, and silence.
///
/// VOICE, SECOND PASS (2026-07-12 evening). A first mouth shipped that morning
/// and was WRONG: its 10 phrases were picked by grepping source trees — including
/// packages this app never calls — so it covered 2 of the 37 safety lines the app
/// can actually emit, and 8 of its 10 WAVs matched no emittable string at all. It
/// could not say a single hazard line. RE-DERIVED from the runtime emissions:
/// 37/37 covered, 0 dead, proven present in the built APK. NOBODY HAS HEARD IT
/// PLAY ON HER PHONE YET — that is still owed.
///
/// WHAT THIS TEST DOES NOT ASK FOR. It does NOT ask us to announce a stale
/// reading as if it were live. Honest-absence and the cry-wolf discipline stand
/// verbatim. The defect is not that we refuse to lie to her — it is that
/// refusing to lie is the ONLY thing we do. "Honest silence" is a correct answer
/// to a claim-question and a NULL answer to a service-question; we solved the
/// ethics of the silence and then filed the silence as done. The andon cord
/// stops the loom SO THE THREAD GETS FIXED AND WEAVING RESUMES. We built the
/// stop and never the fix.
///
/// WHAT IT ASKS FOR. That at T+90, with no network, a winter hazard she could
/// have been told about BEFORE she left still reaches her — grounded in
/// something genuinely VALID, and spoken by a mouth that works with the centre
/// gone.
///
/// TWO INDEPENDENT REDS. Each is a separate missing organ; fixing either alone
/// leaves her unserved.
///
///   RED-1 (NO MEMORY) The hazard layer is OBSERVATION-stamped only
///     (`observedAtJstKey`). A FORECAST has a VALIDITY WINDOW — a JMA forecast
///     fetched at 07:00 covering 12:00–18:00 is not "stale" at 08:30 — but no
///     validity concept exists anywhere in the app. So a forecast fetched at
///     departure, still perfectly valid for the whole trip, is DISCARDED at 60
///     minutes to protect the honesty of a claim, at the cost of the service.
///
///   RED-2 (THE MOUTH) — CLOSED 2026-07-12 (evening, second pass). Every
///     safety-class line the app can EMIT at runtime now has bundled bytes that
///     need no TTS and no network. The assertion below is COVERAGE-shaped, not
///     file-exists-shaped: the first version went green on ten files that said
///     almost nothing the app says.
///
/// GREEN CONDITION. RED-1 closes when the condition seam admits a source with NO
/// fetch and NO point-query — a trip-window-valid hazard bundle prefetched at
/// plan time (and, later, what the phone genuinely senses: clock, last fix,
/// dead-reckoned motion, the on-device bridge/elevation asset). RED-2 closes
/// when the finite ja SAFETY vocabulary is pre-rendered into bundled audio with
/// zero TTS and zero network dependency (Chair-ruled 2026-07-12: synth now,
/// human-record the safety core before winter). RED-2 is GREEN as of the
/// re-derived 37-phrase mouth; RED-1 remains RED and is left RED deliberately.
///
/// This is also, exactly, the thing nobody ships as something another developer
/// can build on: a condition source that needs no source.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/staleness_policy.dart';
import 'package:sngnav_app/voice/offline_safety_voice.dart';

import '../voice/runtime_emissions.dart';

void main() {
  group('C2 — offline survival at T+90 in the dead zone', () {
    // The trip: she leaves at 07:00 JST. The last thing the network ever gave
    // her was a 07:00 reading. At 08:30 she is on the road, the centre is gone,
    // and a bridge on her route is icing.
    final departure = DateTime.utc(2026, 1, 15, 7, 0).subtract(
      const Duration(hours: 9),
    ); // 07:00 JST as a true instant
    const observedAtDepartureJstKey = '20260115070000';
    final tPlus90 = departure.add(const Duration(minutes: 90));

    test('the map survives — this half of C2 is real', () {
      final tiles = File('assets/tiles/akita_offline.mbtiles');
      expect(
        tiles.existsSync(),
        isTrue,
        reason: 'The offline Akita basemap must be bundled. This is the one '
            'half of C2 that was made real (2026-07-10).',
      );
    });

    test(
      'RED-1 (NO MEMORY): a hazard she could have been warned about before she '
      'left no longer reaches her at T+90 — because we model observation AGE '
      'and never forecast VALIDITY',
      () {
        final observedAt = observedAtJstInstant(observedAtDepartureJstKey);
        expect(observedAt, isNotNull);

        final age = tPlus90.difference(observedAt!);
        expect(age, const Duration(minutes: 90));

        // This is the whole defect, in one line of arithmetic.
        final retained = age <= kSlowHazardRetainWindow;
        expect(
          retained,
          isTrue,
          reason: '''
FAILS TODAY, AND MUST.

At T+90 the only hazard knowledge she has is a 07:00 OBSERVATION, and it is 90
minutes old — past kSlowHazardRetainWindow (60 min). We expire it and fall to
the honest absence line. That expiry is CORRECT for an observation and it is the
right call: we will not announce a stale reading as live.

But it is the wrong QUESTION. A forecast fetched at 07:00 and valid through the
afternoon is not "90 minutes stale" — it is VALID. She could have been told, before
she ever left the house, that the bridge would ice by 09:00. That knowledge needs
no network at 08:30. We simply have nowhere to put it: the app models observation
AGE and has no concept of forecast VALIDITY at all.

This assertion is not asking to retain the observation longer. It is asserting that
SOMETHING VALID must still reach her at T+90 — and today nothing can, because no
source exists that carries validity across the dead zone.

GREEN when: AdvisoryProvider admits an implementation with no fetch and no
point-query — a trip-window-valid hazard bundle prefetched at plan time.
''',
        );
      },
    );

    // RED-2, RE-WRITTEN 2026-07-12 (second pass, same day). The FIRST version of
    // this assertion asked only whether ANY audio file existed on OUR DISK. It
    // went green the moment ten WAVs landed — EIGHT of which corresponded to no
    // string the app can emit, and NOT ONE of which was a hazard line the app
    // actually speaks. A test of our disk is not a test of her hearing.
    //
    // The honest assertion is COVERAGE: every SAFETY-class string the app can
    // pass to speak() at runtime must have real bytes on the phone. The runtime
    // enumeration itself lives in test/voice/runtime_emissions.dart (it CALLS
    // the production emitters); here we assert the bytes exist and are speech.
    test(
      'RED-2 (THE MOUTH): every SAFETY-class line the app can EMIT at runtime '
      'has bundled bytes — with no TTS and no network',
      () {
        final safety = emittableSafetyStaticJa();
        expect(safety, isNotEmpty, reason: 'no emissions — test is vacuous');

        final unspeakable = <String>[];
        for (final line in safety) {
          final asset = OfflineSafetyVoice.assetFor(line);
          if (asset == null) {
            unspeakable.add('NO CATALOG ENTRY: $line');
            continue;
          }
          final f = File(asset);
          // A RIFF header alone is ~44 bytes; under 8 KB is not speech, it is a
          // file that plays as silence and looks fine in a listing.
          if (!f.existsSync() || f.lengthSync() < 8000) {
            unspeakable.add('NO BYTES: $asset ($line)');
          }
        }

        expect(
          unspeakable,
          isEmpty,
          reason: '''
${unspeakable.length} of ${safety.length} safety-class lines the app EMITS cannot
be spoken with the centre gone:
${unspeakable.join('\n')}

Her only other voice path is flutter_tts (system TTS), measured 2026-07-12 as
silent-then-hung offline on her phone — there is no offline ja voice on it.

HONEST BOUND (not closed by this test): these bytes are proven to be in the APK
(unzip -l | grep audio/ja) and proven to match the emitted strings. NOBODY HAS
YET HEARD THEM PLAY ON HER PHONE. On-device hearing verification is still owed
and is NOT claimed here.
''',
        );
      },
    );
  });
}
