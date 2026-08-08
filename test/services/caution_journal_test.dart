/// CAUTION JOURNAL — proving the app's DECISIONS leave a trace, so a diary
/// entry can be acted on.
///
/// HER-trace (3 hops, honest): a Ring-2 diary-writer writes
/// 「路面は凍結・アイスバーン。警告は来なかった」. Until this journal existed, that entry
/// was indistinguishable across four realities — correctly quiet / deliberately
/// muted / decided-but-empty-line / dead code path. Only one is a defect. These
/// tests pin that the three non-obvious ones now leave a distinguishable trace,
/// so the real defect is FOUND instead of guessed, and the warning that failed
/// her gets fixed.
///
/// Each test is written to FAIL if the journal call it pins is removed.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/services/caution_journal.dart';
import 'package:sngnav_app/services/drive_hud_controller.dart';
import 'package:sngnav_app/services/error_log.dart';
import 'package:sngnav_app/services/measured_hazard_floor.dart';

import '../support/fake_alert_actuators.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 8, 0, 0);

  PositionAvailable fix(DateTime t, {double acc = 20}) => PositionAvailable(
        latitude: 39.72,
        longitude: 140.10,
        accuracyMeters: acc,
        timestamp: t,
      );

  late Directory tmp;
  late File logFile;
  late LocalErrorLog log;
  late CautionJournal journal;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('caution_journal_test');
    logFile = File('${tmp.path}/log.txt');
    log = LocalErrorLog(file: logFile);
    journal = CautionJournal(log: log);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  DriveHudController controllerWith(
    FakeAlertActuators fake, {
    CautionJournal? j,
  }) =>
      DriveHudController(actuators: fake, localeTag: 'ja', journal: j);

  test(
      'the FIRST evaluation journals a transition from none — the entry that '
      'proves the evaluator was ALIVE (dead code path vs correctly quiet)',
      () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake, j: journal);

    c.updateEnvironment(
      visibilityMeters: 1500,
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
      measuredHazard: MeasuredWeatherHazard.none,
    );
    c.onPositionFix(fix(t0), now: t0);
    await settle();

    final text = log.readAll();
    expect(text, contains('[caution]'));
    expect(text, contains('rung none->continueDriving'));
  });

  test('a STEADY rung does not re-journal — the journal is not a per-tick '
      'firehose that could evict crash evidence from the shared cap', () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake, j: journal);

    for (var i = 0; i < 5; i++) {
      c.updateEnvironment(
        visibilityMeters: 1500,
        visibilityAgeSeconds: 0,
        advisorySeverity: null,
        speedMetersPerSecond: null,
        measuredHazard: MeasuredWeatherHazard.none,
      );
      c.onPositionFix(fix(t0.add(Duration(seconds: i))), now: t0);
      await settle();
    }

    final transitions = 'rung none->continueDriving'.allMatches(log.readAll());
    expect(transitions.length, 1,
        reason: 'a steady drive must write exactly one transition entry');
  });

  test(
      'a MEASURED-FLOOR-ONLY rise is journalled as deliberately not-spoken — '
      'the mute that was previously indistinguishable from a dead path',
      () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake, j: journal);

    // Clear visibility + trusted fix => the advisor alone says continue; the
    // firing measured watch raises the rung, and the watch lane owns the line.
    c.updateEnvironment(
      visibilityMeters: 1500,
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
      measuredHazard: MeasuredWeatherHazard.blackIce,
    );
    c.onPositionFix(fix(t0), now: t0);
    await settle();

    final text = log.readAll();
    expect(text, contains('rung none->heightenedCaution'));
    expect(
      text,
      contains('not-spoken heightenedCaution reason=measured-floor-only'),
      reason: 'the WHY of the silence must be recorded, not just the silence',
    );
  });

  test(
      'a STEADY MUTED caution is journalled ONCE, not once per tick — the '
      'firehose that would evict crash evidence from the shared cap',
      () async {
    // Regression: `_lastSpokenRung` deliberately does NOT advance on a
    // suppressed rise (OPS-068), so `risesAboveSpoken` stays true on every
    // later evaluation while the rung holds. Before the de-dup this wrote one
    // entry PER POSITION FIX — thousands on a long drive. Found by reading a
    // real sample, not by a green suite.
    final fake = FakeAlertActuators();
    final c = controllerWith(fake, j: journal);

    for (var i = 0; i < 6; i++) {
      c.updateEnvironment(
        visibilityMeters: 1500,
        visibilityAgeSeconds: 0,
        advisorySeverity: null,
        speedMetersPerSecond: null,
        measuredHazard: MeasuredWeatherHazard.blackIce,
      );
      c.onPositionFix(fix(t0.add(Duration(seconds: i))), now: t0);
      await settle();
    }

    final muted = 'not-spoken heightenedCaution reason=measured-floor-only'
        .allMatches(log.readAll());
    expect(muted.length, 1,
        reason: 'a steady muted caution must write exactly ONE entry');
  });

  test('a rise that DOES speak is journalled as spoken', () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake, j: journal);

    // Low MEASURED visibility grounds the advisor itself (not unknown/stale),
    // so the rung speaks its own line.
    c.updateEnvironment(
      visibilityMeters: 30,
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
      measuredHazard: MeasuredWeatherHazard.none,
    );
    c.onPositionFix(fix(t0), now: t0);
    await settle();

    final text = log.readAll();
    expect(text, contains('spoke '),
        reason: 'an announce that fired must be distinguishable from silence');
    expect(fake.spoken, isNotEmpty,
        reason: 'sanity: the journal must agree with what actually fired');
  });

  test('a null journal changes NOTHING — the default is record-nothing, so '
      'every existing caller and off-device test is unaffected', () async {
    final withNone = FakeAlertActuators();
    final a = controllerWith(withNone);
    a.updateEnvironment(
      visibilityMeters: 30,
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
      measuredHazard: MeasuredWeatherHazard.none,
    );
    a.onPositionFix(fix(t0), now: t0);
    await settle();

    final withJournal = FakeAlertActuators();
    final b = controllerWith(withJournal, j: journal);
    b.updateEnvironment(
      visibilityMeters: 30,
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
      measuredHazard: MeasuredWeatherHazard.none,
    );
    b.onPositionFix(fix(t0), now: t0);
    await settle();

    // SpokenLine has no `==` override, so compare by VALUE (its toString
    // carries text + locale) rather than by identity.
    expect(
      withJournal.spoken.map((s) => s.toString()).toList(),
      equals(withNone.spoken.map((s) => s.toString()).toList()),
      reason: 'journalling must not alter what reaches HER',
    );
    expect(withNone.spoken, isNotEmpty, reason: 'sanity: something did fire');
    expect(a.effectiveAction, equals(b.effectiveAction));
  });

  test('a BROKEN log never takes the drive down — a journal failure must not '
      'become the reason a caution surface dies', () async {
    // A path whose parent is a FILE, so every write attempt fails.
    final blocker = File('${tmp.path}/blocker')..writeAsStringSync('x');
    final doomed = CautionJournal(
      log: LocalErrorLog(file: File('${blocker.path}/nope/log.txt')),
    );

    final fake = FakeAlertActuators();
    final c = controllerWith(fake, j: doomed);

    c.updateEnvironment(
      visibilityMeters: 30,
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
      measuredHazard: MeasuredWeatherHazard.none,
    );

    expect(() => c.onPositionFix(fix(t0), now: t0), returnsNormally);
    await settle();
    expect(fake.spoken, isNotEmpty,
        reason: 'the announce must still reach HER when the journal is broken');
  });

  test('the journal records NO position, coordinate or route state — the '
      'no-location-history property of the log must survive', () async {
    final fake = FakeAlertActuators();
    final c = controllerWith(fake, j: journal);

    c.updateEnvironment(
      visibilityMeters: 30,
      visibilityAgeSeconds: 0,
      advisorySeverity: null,
      speedMetersPerSecond: null,
      measuredHazard: MeasuredWeatherHazard.blackIce,
    );
    c.onPositionFix(fix(t0), now: t0);
    await settle();

    final text = log.readAll();
    // Guard against a VACUOUS pass: an empty log trivially "contains no
    // coordinates". Assert first that something WAS written, so this test
    // genuinely constrains the payload rather than the absence of one.
    expect(text, contains('[caution]'),
        reason: 'precondition: the journal must have written something');
    expect(text, isNot(contains('39.72')));
    expect(text, isNot(contains('140.10')));
    expect(text, isNot(contains('latitude')));
    expect(text, isNot(contains('longitude')));
  });
}
