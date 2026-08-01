/// STAGE 1 — does 路面凍結ウォッチ print an all-clear on a road the model
/// never judged?
///
/// `InvisibleIceWatchResult.clear` carries an explicit contract in its own
/// dartdoc (lib/services/invisible_ice_watch.dart:44-49):
///
///   "This is a MEASURED negative: every required field was reported, the
///    conditions were inside this watch's scope, and the shared classifier
///    determined the radiative-frost window is absent. Only this value may
///    ever be rendered as 該当なし."
///
/// `isRadiativeFrostBlackIce` returns a bare `bool`, so structurally different
/// `false`s collapse into one value. Citations are to
/// navigation_safety_calibration-0.1.3/lib/src/humidity_dependent_temperature.dart
/// (cited below as cal:NNN):
///
///   cal:158  non-finite ambient        -> false   DECLINE (rejected input, cal:153)
///   cal:159  ambient > 3.0 C ceiling   -> false   DETERMINATION — see below
///   cal:163  RH outside [5,105]        -> false   DECLINE (rejected input, cal:146-151)
///   cal:174  fires only when est <= 0  -> false   DECLINE (documented non-coverage)
///
/// N3 is documented verbatim (cal:112-115): "near-zero SATURATED FREEZING FOG
/// above ~+1 C (dew point >= 0) is therefore NOT detected by this model — a
/// genuine hazard this function does not cover."
/// N2 is the cleaner instance: the package calls sub-5% RH "almost certainly a
/// mis-wired FRACTION" (cal:146-151) and REJECTS it — and the app renders that
/// rejection to her as an all-clear.
///
/// ── WHY THE CEILING IS A DETERMINATION, NOT A DECLINE (the contested line) ──
/// Ruled 2026-08-01 after a depth audit; five independent lenses converged.
/// Three grounds, all in the package's own text:
///   * cal:88-90 gives the ceiling an AFFIRMATIVE reason — "This ceiling keeps
///     the classification inside the physics the calibration documents" — and
///     names the false positive it prevents (20 C at 25 % RH; measured dew
///     -0.64, so that probe value is real).
///   * cal:117-121 makes the ceiling a CONJUNCT of what the function AFFIRMS
///     ("Returns `true` when [ambient] is within [ceiling] AND ...").
///     A term inside the fire condition is part of the determination.
///   * cal:135-153 enumerates EVERY rejected input class — null/NaN/inf RH,
///     (100,105], >105, <5, non-finite ambient. The ceiling is NOT among them.
/// Contrast the three speech acts: N1 asserts about the world, N3 confesses a
/// hole, N2 refuses an input. "The model equally cannot fire above the ceiling"
/// proves too much — EVERY negative determination is a region where a model
/// cannot fire; that is what a negative determination looks like.
/// HONEST BOUND: ground 3 rests on prose that is itself internally
/// inconsistent — the (100,105] bullet sits under "EVERY rejected input class
/// returns false" and measurably does not (isRadiativeFrostBlackIce(-1.0, 102)
/// returns TRUE). Grounds 1 and 2 carry the ruling alone. FALSIFIER: if
/// upstream moves the ceiling into the decline list or ships a tri-state, this
/// ruling flips. Cheap to re-check on every version bump.
/// The DISCONTINUITY at the ceiling is real and is GUARD 3's, not this
/// predicate's.
///
/// ── WHAT THIS FILE IS (OPS-070(B): the reason, written before the act) ──
/// It measures the boundary and guards it. Authored in Stage 1 with all three
/// guards PROVEN RED against the unfixed app (L34 — a guard is not INSERTED
/// until it has been proven to fail), then UNSKIPPED in Stage 2 when the
/// countermeasure landed and turned them green.
///
/// STATUS 2026-08-01: Stage 2 SHIPPED. `outsideModelEnvelope` now carries the
/// declined cells and the row prints 「判定範囲外（この気象条件は判定していません）」
/// (render-SEEN, ladder_out/ice_watch/ice_watch_saturated_ja.png). These guards
/// are now REGRESSION guards: if any goes red again, a declined reading has
/// started printing a bare 該当なし on a road the model never judged.
///
/// ── SCOPE OF THE GUARDS, AND WHY THEY ARE BOUNDED ──
/// The FIRST draft selected on `t > 0 && dewPoint >= 0` with NO upper bound.
/// Five review lenses measured that forbidding 該当なし up to +35 C, across
/// ~66% of every above-zero all-clear — the Chair's 2026-07-23 cry-wolf
/// calibration inverted into over-abstention. Its apparent narrowness was an
/// artifact of the fixture list stopping at +3.0. Bounding it cost ZERO
/// offenders on this fixture and removed the entire unbounded reach.
///
/// ── A COMMITTED TEST THIS CONTRADICTS ──
/// test/services/invisible_ice_watch_test.dart:141-145 asserts
/// `temp 2.0 / humidity 90 / precip 0 == clear` (measured estimate +0.5320 ->
/// an N3 decline). That is GUARD 1 offender #8, and CI actively defends it.
/// Stage 2 rewrites it; Stage 1 annotates it in place. Its sibling at :136-139
/// (8.0 C / 70 %, above the ceiling) must SURVIVE unchanged — it is the proof
/// that Stage 2 did not re-import over-abstention.
///
/// ── HONEST BOUND ON PRIORITY (OPS-070(C)) ──
/// Live JMA reads on 2026-08-01 confirmed the app's five `corridorStations` at
/// 96-100 % RH — but at 21.7-25.6 C. An August reading establishes a humid
/// corridor; it does NOT establish that saturated air within a degree of
/// freezing is Akita's ordinary morning. The WINTER co-occurrence of RH >= 97 %
/// with T in (0, +3 C] is UNMEASURED — the place we have not gone and seen is
/// JMA's 過去の気象データ archive. The JMA-emitted humidity RANGE is likewise
/// unmeasured (see GUARD 1's REACHABLE/DEFENSIVE split). The contract defect
/// stands regardless of frequency; no priority claim is made here.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_calibration/navigation_safety_calibration.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/services/invisible_ice_watch.dart';

/// The JMA AMeDAS temperature reporting step, °C.
///
/// DELIBERATELY A SECOND, INDEPENDENT LITERAL. Production owns
/// `kJmaTemperatureStepCelsius` in lib/services/invisible_ice_watch.dart, and
/// this guard does NOT import it: a guard that reads its bound from the code it
/// audits cannot catch that bound being widened (OPS-065(A), advocate ≠
/// verifier).
///
/// CORRECTED 2026-08-01 (review MUST-10, CONFIRMED). An earlier version of this
/// dartdoc claimed "if the two ever diverge, GUARD 3 goes red — which is the
/// point." That was FALSE, and measurably one-sided: mutating THIS literal
/// 0.1 → 0.5 went red, but mutating PRODUCTION's 0.1 → 0.5 stayed GREEN, as did
/// 5.0 and 35.0. GUARD 3 only ever samples at ceiling and ceiling+step, so a
/// WIDER production band still contains both sample points and nothing fails.
/// That hole is why a 4.9 mutation, left in the tree by a peer reviewer, was
/// committed green on 2026-08-01 — the suite could not see it.
/// A false contract claim, inside the artifact whose purpose is to police false
/// contract claims.
///
/// `BAND WIDTH PIN` below is the two-sided detector that actually closes it.
const double kGuardJmaTemperatureStepCelsius = 0.1;

/// Is (t, rh) a cell the radiative-frost classifier DECLINED to judge?
///
/// A FAITHFUL mirror of `isRadiativeFrostBlackIce`'s guards (cal:158-174),
/// preserving BRANCH ORDER — the ceiling is tested before the humidity domain,
/// exactly as cal:159 precedes cal:163, so an out-of-domain humidity ABOVE the
/// ceiling is not reported as a decline (the classifier never read it).
///
/// It carries NO app policy: no `t <= 0` gate, and a non-finite ambient is a
/// DECLINE (cal:153/158), not "covered". App-scope filtering is done at the
/// call site by `r == clear`, which already excludes `subZeroFrozen`,
/// `unknown` and `outOfScope`. (An earlier version smuggled app policy in here
/// while its docstring claimed an exact mirror — a false contract claim inside
/// the artifact whose purpose is to police false contract claims.)
///
/// The RH domain bounds 5.0 / 105.0 are MIRRORED LITERALS, not imports: the
/// package exports named constants for the temperature thresholds but leaves
/// the humidity domain inline at cal:163. The drift-identity test below is
/// what actually catches a change to them — not this comment.
bool classifierDeclinedToJudge({
  required double t,
  required double? rhPercent,
}) {
  if (!t.isFinite) return true; // cal:158 — rejected input
  if (t > radiativeFrostAmbientCeilingCelsius) return false; // cal:159 — N1
  final rh = rhPercent;
  if (rh == null || !rh.isFinite) return true; // cal:162
  if (rh < 5.0 || rh > 105.0) return true; // cal:163 — N2
  // cal:165 — the >100 clamp. NOT optional: computeEffectiveTemperatureCelsius
  // THROWS ArgumentError on any humidityRH > 1.0 (cal:65-71), so omitting this
  // line makes the guard CRASH across (100,105], not merely disagree.
  final fraction = rh > 100.0 ? 1.0 : rh / 100.0;
  final dew = computeEffectiveTemperatureCelsius(
    ambientCelsius: t,
    humidityRH: fraction,
  );
  return dew > radiativeFrostSurfaceTempCelsius; // cal:174 — N3
}

/// Dew point via the calibration primitive, or null OUTSIDE the classifier's
/// own accepted domain — so it can never hand back a number the classifier
/// never computed (the fabricated-number class this file exists to catch).
double? dewPointOrNull(double t, double? rhPercent) {
  final rh = rhPercent;
  if (rh == null || !rh.isFinite || rh < 5.0 || rh > 105.0) return null;
  final fraction = rh > 100.0 ? 1.0 : rh / 100.0;
  return computeEffectiveTemperatureCelsius(
    ambientCelsius: t,
    humidityRH: fraction,
  );
}

JmaObservation obsAt({required double tempC, required int? rh}) =>
    JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: tempC,
      humidityPercent: rh,
      windMetersPerSecond: 2.0,
      snowDepthCm: null,
      // MEASURED zero, not absent: keeps the observation inside the watch's
      // no-precipitation scope so the above-zero branch is the one exercised
      // (a null here would abstain as `unknown` and prove nothing).
      precipitation10mMm: 0.0,
      visibilityMeters: null,
      observedAtJstKey: '20260115063000',
      fetchedAt: DateTime(2026, 1, 15, 6, 30),
    );

void main() {
  // Temperatures deliberately span the ceiling: 3.1 / 8.0 / 20.0 / 25.5 exist
  // so the guards can DEMONSTRATE that they do not reach above it.
  // 25.5 is a real live Akita reading (2026-08-01).
  const temps = <double>[-0.5, 0.0, 0.5, 1.0, 2.0, 3.0, 3.1, 8.0, 20.0, 25.5];
  // RH deliberately spans the classifier's [5,105] domain: 0/4 below, 102 in
  // the clamped band, 106/120 above.
  const humidities = <int>[0, 4, 5, 25, 86, 90, 93, 96, 97, 98, 100, 102, 106, 120];

  test('ENVELOPE (diagnostic, always passes) — every sampled verdict, with why',
      () {
    final b = StringBuffer()
      ..writeln('')
      ..writeln('路面凍結ウォッチ verdict — precip MEASURED 0.0mm on every cell')
      ..writeln('  ! = the classifier DECLINED to judge (RH out of domain, or')
      ..writeln('      estimate > 0 under the ceiling). Bare 該当なし here is')
      ..writeln('      the defect under test.')
      ..writeln('  d = above the 3.0C ambient ceiling — a DETERMINATION')
      ..writeln('      (cal:88-90), so 該当なし is EARNED. The STEP from WATCH')
      ..writeln('      into this region is GUARD 3, not GUARD 1.')
      ..writeln('');
    b.write('   T\\RH |');
    for (final rh in humidities) {
      b.write(' ${rh.toString().padLeft(4)}%');
    }
    b.writeln();
    for (final t in temps) {
      b.write('  ${t.toStringAsFixed(1).padLeft(5)} |');
      for (final rh in humidities) {
        final r = evaluateInvisibleIceWatch(obsAt(tempC: t, rh: rh));
        final declined =
            classifierDeclinedToJudge(t: t, rhPercent: rh.toDouble());
        final tag = switch (r) {
          InvisibleIceWatchResult.watch => 'WATCH',
          InvisibleIceWatchResult.clear => declined
              ? '*CLR!'
              : (t > radiativeFrostAmbientCeilingCelsius ? ' CLRd' : ' clr '),
          InvisibleIceWatchResult.subZeroFrozen => 'FROZN',
          InvisibleIceWatchResult.outOfScope => 'scope',
          InvisibleIceWatchResult.unknown => ' unk ',
          // The Stage-2 countermeasure. Every cell that previously printed a
          // bare 該当なし while the classifier had DECLINED now lands here.
          InvisibleIceWatchResult.outsideModelEnvelope => 'DECLN',
        };
        b.write(' $tag');
      }
      b.writeln();
    }
    // ignore: avoid_print
    print(b.toString());
  });

  test(
    'IN-BAND SIGN PIN (permanent, must stay GREEN) — inside the band, a cell '
    'declines regardless of the estimate\'s sign',
    () {
      // ADDED 2026-08-01 (build-track review, SDE MUST). The in-band branch
      // originally abstained only when the estimate was <= 0, which left 20
      // reachable cells at 3.1 C / RH 81-100 printing a bare 該当なし with the
      // estimate ABOVE freezing — cal:112-115's non-coverage band verbatim.
      // That was fixed, and the fix SHIPPED WITHOUT A GUARD: reverting the
      // branch to `dew <= 0` restored all 20 cells with the suite still GREEN.
      // Third instance in this file's history of a fix arriving without its
      // loom; this closes it.
      const inBand = radiativeFrostAmbientCeilingCelsius +
          kGuardJmaTemperatureStepCelsius; // 3.1 C, the top of the band
      // Estimate ABOVE freezing here (saturated air): the sign-dependent form
      // returned "judged" and printed 該当なし. It must decline.
      expect(
        radiativeFrostJudgementDeclined(t: inBand, rhPercent: 90),
        isTrue,
        reason: 'In the ceiling band with the estimate ABOVE freezing, BOTH '
            'in-band reasons are declines: the constant ended the warning, AND '
            'this is the documented non-coverage band. If this is false, the '
            'in-band branch has been made sign-dependent again and the '
            'fabricated-clear is back inside its own countermeasure.',
      );
      // And below freezing in the same band — the other in-band reason.
      expect(
        radiativeFrostJudgementDeclined(t: inBand, rhPercent: 25),
        isTrue,
      );
      // CLASS B — the out-of-domain humidities. Added after the build-track
      // review (SDE SHOULD, CT MUST): the first version of this pin looped
      // rh 5..105 only, so it covered the 20 in-domain cells (Class A) and was
      // BLIND to a second, disjoint class of 98 cells.
      //
      // Before the short-circuit, the RH-domain branch returned `!aboveCeiling`
      // — so an IN-BAND cell whose humidity was null, non-finite, or outside
      // [5,105] answered "judged" and printed a bare 該当なし: a DOUBLE-BLIND
      // all-clear, where the ceiling constant was untrustworthy AND there was
      // no humidity evidence at all. Restoring that form leaves the rh 5..105
      // loop entirely green, which is why it must be listed explicitly.
      const humidities = <double?>[
        null, 0, 4, 4.999, 5, 25, 80, 81, 90, 97, 100, 102, 105, 106, 120,
      ];
      final judged = <String>[
        for (final rh in humidities)
          if (!radiativeFrostJudgementDeclined(t: inBand, rhPercent: rh))
            'rh=$rh',
      ];
      expect(judged, isEmpty,
          reason: 'EVERY humidity at ${inBand}C must decline — in-domain '
              '(the estimate is untrustworthy) and out-of-domain (there is no '
              'humidity evidence at all, on top of an untrustworthy ceiling). '
              'These did not: $judged');
    },
  );

  test(
    'BAND WIDTH PIN (permanent, must stay GREEN) — production must not widen '
    'the declined band beyond one feed step',
    () {
      // THE HOLE THIS CLOSES. GUARD 3 samples only at the ceiling and at
      // ceiling+step, so a WIDER production band still contains both sample
      // points and GUARD 3 stays green. Measured 2026-08-01: mutating
      // production's kJmaTemperatureStepCelsius to 0.5 / 5.0 / 10.0 / 35.0 left
      // GUARD 1 at 0 hits, GUARD 3 at 0 hits and the whole suite GREEN, while
      // over-abstention grew to as many as 9,343 cells. That blindness is why a
      // 4.9 mutation was committed green.
      //
      // This pin samples the one place that distinguishes the widths: just
      // OUTSIDE the band, in DRY air where the model's estimate is still well
      // below freezing — the region an unbounded band swallows first. It uses
      // the GUARD's own literal, never production's, so it cannot be defeated
      // by editing the constant it exists to police.
      const justOutside = radiativeFrostAmbientCeilingCelsius +
          2 * kGuardJmaTemperatureStepCelsius; // 3.2 C
      expect(
        radiativeFrostJudgementDeclined(t: justOutside, rhPercent: 25),
        isFalse,
        reason: 'At ${justOutside}C / 25% RH the classifier made a '
            'DETERMINATION (above the ceiling, clear of the one-step band) and '
            'a bare 該当なし is EARNED. If this is true, the declined band has '
            'been widened past one JMA reporting step and the app is '
            'over-abstaining — the failure the first draft of this guard set '
            'caused, which forbade 該当なし up to +35 C.',
      );
      // And the far field must stay judged too — cheap, and it fails loudly if
      // the band upper bound is deleted outright.
      expect(
        radiativeFrostJudgementDeclined(t: 20.0, rhPercent: 25),
        isFalse,
        reason: '20 C / 25 % RH is the calibration package\'s own named '
            'cry-wolf probe (cal:84-89). It must never be reported as declined.',
      );
    },
  );

  test(
    'DRIFT IDENTITY (permanent, must stay GREEN) — the mirror is the exact '
    'complement of the real classifier',
    () {
      // cal:123-129 forbids a second copy of this threshold logic BY NAME.
      // Importing the constants covers the VALUES but not the BRANCH STRUCTURE;
      // snow_rendering 0.2.8 records a wind/time-of-day gate that does not
      // exist YET. When it lands, the mirror silently diverges and every other
      // test stays green. This is the only thing standing in the way.
      var mismatches = 0;
      String? first;
      for (var ti = 1; ti <= 300; ti++) {
        final t = ti / 100.0; // (0, 3.0] — the in-domain band
        for (var rh = 5; rh <= 105; rh++) {
          final declined =
              classifierDeclinedToJudge(t: t, rhPercent: rh.toDouble());
          final fires = isRadiativeFrostBlackIce(
            ambientCelsius: t,
            humidityRHPercent: rh.toDouble(),
          );
          if (declined != !fires) {
            mismatches++;
            first ??= 'T=$t RH=$rh declined=$declined fires=$fires';
          }
        }
      }
      expect(mismatches, 0, reason: 'mirror diverged from the classifier: $first');
    },
  );

  test(
    'GUARD 1 (the loom) — a cell the classifier DECLINED to judge must never '
    'render as a bare 該当なし',
    // UNSKIPPED 2026-08-01: the Stage-2 countermeasure landed; these must be GREEN.
    () {
      final reachable = <String>[];
      final defensive = <String>[];
      for (final t in temps) {
        for (final rh in humidities) {
          if (!classifierDeclinedToJudge(t: t, rhPercent: rh.toDouble())) {
            continue;
          }
          final r = evaluateInvisibleIceWatch(obsAt(tempC: t, rh: rh));
          if (r != InvisibleIceWatchResult.clear) continue;
          final String why;
          if (rh < 5 || rh > 105) {
            why = 'RH outside the classifier domain [5,105] — input REJECTED, '
                'the model never looked (cal:163)';
          } else if (rh > 100) {
            why = 'RH $rh% CLAMPED to 100% by cal:165 (supersaturation); at '
                'saturation the modelled estimate equals ambient by '
                'construction, so this cell can never fire — the model did NOT '
                'evaluate the reported humidity';
          } else {
            why = 'estimate ${dewPointOrNull(t, rh.toDouble())!.toStringAsFixed(2)}'
                'C > 0 under the ${radiativeFrostAmbientCeilingCelsius}C '
                'ceiling — documented non-coverage (cal:112-115)';
          }
          final row = 'T=${t.toStringAsFixed(1)}C RH=$rh% -> 該当なし  ($why)';
          // Reachability through the real feed: jma_fetch.dart:186-197 gates on
          // QC flag == 0 and returns an integer percent with no range clamp, so
          // 106/120 cannot occur on that path. Whether JMA ever emits <5 is
          // UNMEASURED. Both classes stay under the guard — the contract defect
          // is identical — but they are reported separately so the record does
          // not overstate exposure.
          (rh < 5 || rh > 105 ? defensive : reachable).add(row);
        }
      }

      expect(
        [...reachable, ...defensive],
        isEmpty,
        reason: 'The watch rendered a bare 該当なし — a MEASURED negative — '
            'where the classifier DECLINED to judge.\n'
            'REACHABLE through the JMA feed (${reachable.length}):\n'
            '  ${reachable.join('\n  ')}\n'
            'DEFENSIVE — not reachable through jma_fetch\'s QC-gated integer '
            'path, held against a future non-JMA feed (${defensive.length}):\n'
            '  ${defensive.join('\n  ')}',
      );
    },
  );

  test(
    'GUARD 2 (constant-free) — for a fixed above-zero temperature, if the '
    'watch WARNS in drier air it must not print 該当なし in wetter air',
    // UNSKIPPED 2026-08-01: the Stage-2 countermeasure landed; these must be GREEN.
    () {
      // Needs no physics claim: it fires only where the watch ITSELF already
      // warned at a lower humidity, so it cannot be over-broad by
      // construction. (It does read the 5/105 domain literals to skip
      // rejected inputs — GUARD 1's territory, not this one's.)
      final inversions = <String>[];
      for (final t in temps) {
        if (t <= 0) continue;
        int? warnedAt;
        for (final rh in humidities) {
          if (rh < 5 || rh > 105) continue;
          final r = evaluateInvisibleIceWatch(obsAt(tempC: t, rh: rh));
          if (r == InvisibleIceWatchResult.watch) {
            warnedAt ??= rh;
          } else if (r == InvisibleIceWatchResult.clear && warnedAt != null) {
            inversions.add('T=${t.toStringAsFixed(1)}C: WARNS at RH=$warnedAt% '
                'but prints 該当なし at RH=$rh% (wetter air)');
          }
        }
      }
      expect(
        inversions,
        isEmpty,
        reason: 'The hazard gradient INVERTS with humidity: the watch warns in '
            'drier air and falls silent as the air saturates — which is where '
            'freezing fog and rime live.\n'
            'Inversions:\n  ${inversions.join('\n  ')}',
      );
    },
  );

  test(
    'GUARD 3 (the ceiling cliff) — a hazard WARNING must not become an '
    'affirmative 該当なし across one feed step, while the model\'s own '
    'estimate is still at or below freezing',
    // UNSKIPPED 2026-08-01: the Stage-2 countermeasure landed; these must be GREEN.
    () {
      // The ceiling is a DETERMINATION (see header), so a bare 該当なし ABOVE it
      // is earned — GUARD 1 is correctly silent there. But EXACTLY at the
      // ceiling the determination is the CONSTANT, not the evidence: measured
      // 2026-08-01 at 3.0C/30% the estimate is -12.914C and the row WARNS; at
      // the NEXT REPRESENTABLE DOUBLE the estimate is unchanged to 15
      // significant figures (-12.914063344967174 -> -12.914063344967172;
      // delta 1.8e-15 C — nothing physical changed) and the row printed
      // 該当なし. Do not record that as "0.01C" — nothing physical changed at
      // all.
      //
      // The band is ONE feed step wide DELIBERATELY. Unbounded ("estimate <= 0
      // above the ceiling") re-imports the over-abstention this file already
      // removed once: the estimate stays <= 0 up to 17.81C at 30% RH, covering
      // ~95,000 cells including 20.0C/25% — the exact cry-wolf the ceiling
      // exists to prevent. Banded, it covers ~760.
      const below = radiativeFrostAmbientCeilingCelsius;
      // The GUARD's own step constant, not production's — see its dartdoc.
      const above = radiativeFrostAmbientCeilingCelsius +
          kGuardJmaTemperatureStepCelsius; // == 3.1 exactly in IEEE doubles
      final cliffs = <String>[];
      for (var rh = 5; rh <= 100; rh++) {
        final lo = evaluateInvisibleIceWatch(obsAt(tempC: below, rh: rh));
        final hi = evaluateInvisibleIceWatch(obsAt(tempC: above, rh: rh));
        if (lo != InvisibleIceWatchResult.watch ||
            hi != InvisibleIceWatchResult.clear) {
          continue;
        }
        // Only a CONSTANT crossing: the model's own estimate is still at or
        // below freezing on the 該当なし side, so the evidence did not change —
        // the ceiling ended the warning. A genuine model crossing (estimate
        // rises above 0) is correctly ignored.
        final dewHi = dewPointOrNull(above, rh.toDouble());
        if (dewHi == null || dewHi > radiativeFrostSurfaceTempCelsius) continue;
        cliffs.add('RH=$rh%: ${below}C -> ⚠警告 but ${above}C -> 該当なし '
            '(estimate ${dewHi.toStringAsFixed(2)}C, still at/below freezing)');
      }

      expect(
        cliffs,
        isEmpty,
        reason: 'A hazard WARNING became an affirmative ALL-CLEAR across one '
            'JMA reporting step, with the model\'s own estimate unchanged and '
            'still at or below freezing. The constant, not the evidence, '
            'ended the warning — and `watch` is SPOKEN and HAPTIC '
            '(main.dart:2016-2017) while `clear` is silent AND re-arms the '
            'announce latch (main.dart:2028-2032), so a station oscillating '
            'across this step re-speaks the black-ice line every fetch.\n'
            'Cliffs (${cliffs.length}):\n  ${cliffs.join('\n  ')}',
      );
    },
  );
}
