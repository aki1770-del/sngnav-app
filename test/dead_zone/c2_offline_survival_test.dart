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
///                      repo contains ZERO bundled audio.
///
///   => She has a map, and silence.
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
///   RED-2 (NO MOUTH) There is no bundled offline speech. Every judgement we
///     ever build is worthless if it cannot be spoken when the centre is gone.
///
/// GREEN CONDITION. RED-1 closes when the condition seam admits a source with NO
/// fetch and NO point-query — a trip-window-valid hazard bundle prefetched at
/// plan time (and, later, what the phone genuinely senses: clock, last fix,
/// dead-reckoned motion, the on-device bridge/elevation asset). RED-2 closes
/// when the finite ja SAFETY vocabulary is pre-rendered into bundled audio with
/// zero TTS and zero network dependency (Chair-ruled 2026-07-12: synth now,
/// human-record the safety core before winter).
///
/// This is also, exactly, the thing nobody ships as something another developer
/// can build on: a condition source that needs no source.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/staleness_policy.dart';

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

    test(
      'RED-2 (NO MOUTH): there is no bundled offline speech — every judgement we '
      'build is unspeakable with the centre gone',
      () {
        final audioDir = Directory('assets/audio');
        final bundled = audioDir.existsSync()
            ? audioDir
                .listSync(recursive: true)
                .whereType<File>()
                .where(
                  (f) => const ['.wav', '.mp3', '.ogg', '.m4a']
                      .any((e) => f.path.endsWith(e)),
                )
                .toList()
            : <File>[];

        expect(
          bundled,
          isNotEmpty,
          reason: '''
FAILS TODAY, AND MUST.

The repo contains ZERO bundled audio. Her only voice path is flutter_tts (system
TTS), which we measured on 2026-07-12 as silent-then-hung offline on her phone —
there is no offline ja voice on it.

W0 ("winter warnings survive the dead-zone", commit e2cd352) hardened the
DETECTION layer. It survives into a layer THAT HAS NO MOUTH.

GREEN when: the finite ja SAFETY vocabulary is pre-rendered into bundled audio
assets — zero TTS dependency, zero network dependency — and wired as the offline
speech path. Chair-ruled 2026-07-12: synth now, human-record the safety core
before winter.

Ordering note: this red is FIRST. Without a mouth, no amount of judgement reaches
her, however good it becomes.
''',
        );
      },
    );
  });
}
