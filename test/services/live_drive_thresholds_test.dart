/// The thresholds a live drive gives her, pinned; and proof that nothing on the
/// development page changes what a live drive gives her.
///
/// WHY, written before the act (2026-09-15). The driver-type and vehicle
/// selectors left her home page for the development page. Before they moved,
/// the question was whether either changes what reaches her in a live drive.
/// Read in source on 6d530fc, neither does: the live drive's controller is
/// built with no driver type and no vehicle (main.dart:1268-1275), and the app
/// gives it position, visibility, the advisory level and the measured hazard
/// only. So both moved. This file holds that answer as a test that fails if it
/// stops being true, in two parts:
///
/// 1. The rung the live drive gives her along each of its inputs, built the
///    way the app builds the controller: visibility, its age, the advisory
///    level, the measured hazard, the fix's accuracy and the seconds without a
///    fix. A change to any threshold changes a table here and fails.
/// 2. The real app, with every driver type, vehicle type, driver-state input
///    and simulated road condition set on the development page: her card's rung
///    and every spoken line and vibration along one scripted drive are the same
///    as with nothing set.
///
/// When the live drive's thresholds are meant to change (changes to the rung
/// and to warnings in a whiteout are under way), the tables in part 1 change
/// in the same commit, and the diff shows which edges moved.
library;

import 'dart:async';

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show AdvisoryLevel, DriveAction;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart'
    show
        CircadianPhase,
        Confidence,
        CumulativeFatigueClass,
        DriverProfile,
        RoadSurfaceCondition;
import 'package:sngnav_app/actuators/alert_announcer.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/drive_hud_controller.dart';
import 'package:sngnav_app/services/measured_hazard_floor.dart';

import '../support/developer_page.dart';
import '../support/fake_alert_actuators.dart';
import '../support/rung_on_card.dart';

final _t0 = DateTime.utc(2026, 1, 15, 21, 0, 0);

/// One live drive as the app builds it: one actuator layer, one announcer over
/// it, the ja surface, no speed; the environment, one trusted fix at t0, then
/// a poll [secondsWithoutFix] later when that is above zero.
({String? mode, DriveAction? rung}) _drive({
  double? visibility,
  double? visibilityAge = 0,
  AdvisoryLevel? advisory,
  MeasuredWeatherHazard hazard = MeasuredWeatherHazard.none,
  double accuracy = 15,
  int secondsWithoutFix = 0,
}) {
  final actuators = FakeAlertActuators();
  final c = DriveHudController(
    actuators: actuators,
    announcer: AlertAnnouncer(actuators: actuators),
    localeTag: 'ja',
  );
  c.updateEnvironment(
    visibilityMeters: visibility,
    visibilityAgeSeconds: visibility == null ? null : visibilityAge,
    advisorySeverity: advisory,
    speedMetersPerSecond: null,
    measuredHazard: hazard,
  );
  c.onPositionFix(
    PositionAvailable(
      latitude: 39.7167,
      longitude: 140.0983,
      accuracyMeters: accuracy,
      timestamp: _t0,
    ),
    now: _t0,
  );
  if (secondsWithoutFix > 0) {
    c.poll(now: _t0.add(Duration(seconds: secondsWithoutFix)));
  }
  final out = (mode: c.estimate?.mode.name, rung: c.effectiveAction);
  c.dispose();
  return out;
}

String _rung(({String? mode, DriveAction? rung}) d) => d.rung?.name ?? 'none';

/// [from]..[to] in whole steps, with runs of the same answer joined.
List<String> _runs(int from, int to, String Function(int) at) {
  final out = <String>[];
  var start = from;
  var current = at(from);
  for (var x = from + 1; x <= to; x++) {
    final v = at(x);
    if (v != current) {
      out.add('$start-${x - 1} $current');
      start = x;
      current = v;
    }
  }
  out.add('$start-$to $current');
  return out;
}

/// The live drive's rung along each input, measured now.
Map<String, List<String>> _measuredTables() => {
      'visibility m, fresh, trusted fix': _runs(
          0, 2000, (v) => _rung(_drive(visibility: v.toDouble()))),
      'visibility m, fresh, 60 s without a fix': _runs(0, 2000,
          (v) => _rung(_drive(visibility: v.toDouble(), secondsWithoutFix: 60))),
      'visibility m, fresh, 180 s without a fix': _runs(0, 2000,
          (v) => _rung(_drive(visibility: v.toDouble(), secondsWithoutFix: 180))),
      'visibility age s at 100 m, trusted fix': _runs(0, 900,
          (s) => _rung(_drive(visibility: 100, visibilityAge: s.toDouble()))),
      'fix accuracy m, visibility 1500 m (mode rung)': _runs(0, 1000, (a) {
        final d = _drive(visibility: 1500, accuracy: a.toDouble());
        return '${d.mode} ${_rung(d)}';
      }),
      'seconds without a fix, visibility 1500 m (mode rung)': _runs(0, 900, (s) {
        final d = _drive(visibility: 1500, secondsWithoutFix: s);
        return '${d.mode} ${_rung(d)}';
      }),
      'seconds without a fix, no visibility reading (mode rung)':
          _runs(0, 900, (s) {
        final d = _drive(visibility: null, secondsWithoutFix: s);
        return '${d.mode} ${_rung(d)}';
      }),
      'advisory level x visibility, trusted fix': [
        for (final a in <AdvisoryLevel?>[null, ...AdvisoryLevel.values])
          '${a?.name ?? 'none'}: ${[
            for (final v in const <double?>[null, 1500, 700, 300, 100])
              '${v?.toInt() ?? 'no reading'}=${_rung(_drive(visibility: v, advisory: a))}'
          ].join(' ')}',
      ],
      'measured hazard x seconds without a fix, visibility 1500 m': [
        for (final h in MeasuredWeatherHazard.values)
          '${h.name}: ${[
            for (final s in const [0, 60, 180])
              '${s}s=${_rung(_drive(visibility: 1500, hazard: h, secondsWithoutFix: s))}'
          ].join(' ')}',
      ],
    };

/// Measured on 2026-09-15 on the live drive of sngnav-app 6d530fc, whose drive
/// brain this lane did not change, and pinned here.
///
/// Read in the tables, named and not changed here (the live drive's own logic
/// is outside this change): a fix taken as trusted gives the lowest rung whatever its
/// accuracy up to 500 m, because the advisor gives a trusted position no
/// concern at any radius; its 150 m neighbourhood radius applies to suspect
/// and degraded positions only (compound_failure_advisor 0.1.2,
/// in_drive_advisor.dart:203-229).
const Map<String, List<String>> _pinned = {
  'visibility m, fresh, trusted fix': [
    '0-199 considerStopping',
    '200-999 heightenedCaution',
    '1000-2000 continueDriving',
  ],
  'visibility m, fresh, 60 s without a fix': [
    '0-499 considerStopping',
    '500-2000 heightenedCaution',
  ],
  'visibility m, fresh, 180 s without a fix': [
    '0-2000 considerStopping',
  ],
  'visibility age s at 100 m, trusted fix': [
    '0-300 considerStopping',
    '301-900 heightenedCaution',
  ],
  'fix accuracy m, visibility 1500 m (mode rung)': [
    '0-500 gpsTrusted continueDriving',
    '501-1000 lost considerStopping',
  ],
  'seconds without a fix, visibility 1500 m (mode rung)': [
    '0-0 gpsTrusted continueDriving',
    '1-60 deadReckoning heightenedCaution',
    '61-120 deadReckoning considerStopping',
    '121-900 lost considerStopping',
  ],
  'seconds without a fix, no visibility reading (mode rung)': [
    '0-0 gpsTrusted heightenedCaution',
    '1-60 deadReckoning heightenedCaution',
    '61-120 deadReckoning considerStopping',
    '121-900 lost considerStopping',
  ],
  'advisory level x visibility, trusted fix': [
    'none: no reading=heightenedCaution 1500=continueDriving 700=heightenedCaution 300=heightenedCaution 100=considerStopping',
    'minor: no reading=heightenedCaution 1500=continueDriving 700=heightenedCaution 300=heightenedCaution 100=considerStopping',
    'moderate: no reading=heightenedCaution 1500=heightenedCaution 700=heightenedCaution 300=heightenedCaution 100=considerStopping',
    'severe: no reading=heightenedCaution 1500=heightenedCaution 700=heightenedCaution 300=considerStopping 100=considerStopping',
    'extreme: no reading=considerStopping 1500=considerStopping 700=considerStopping 300=considerStopping 100=considerStopping',
  ],
  'measured hazard x seconds without a fix, visibility 1500 m': [
    'none: 0s=continueDriving 60s=heightenedCaution 180s=considerStopping',
    'blackIce: 0s=heightenedCaution 60s=considerStopping 180s=considerStopping',
    'turmoil: 0s=heightenedCaution 60s=considerStopping 180s=considerStopping',
  ],
};

// ---------------------------------------------------------------------------
// Part 2: the real app, with the development page's inputs set.

JmaObservation _obsWithoutVisibility() => JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 5.0,
      humidityPercent: 50,
      windMetersPerSecond: 1.0,
      snowDepthCm: null,
      precipitation10mMm: 0.0,
      visibilityMeters: null,
      observedAtJstKey: '20260116060000',
      fetchedAt: _t0,
    );

/// A setting on the development page: its name, and how to make it.
typedef _Setting = (String, Future<void> Function(WidgetTester));

Future<void> _choose<T>(WidgetTester tester, Finder dropdown, T value) async {
  await tester.ensureVisible(dropdown);
  await tester.pump();
  await tester.tap(dropdown);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find
      .byWidgetPredicate((w) => w is DropdownMenuItem<T> && w.value == value)
      .last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  // A choice that did not take would leave the drive below unchanged and pass
  // for the wrong reason, so each one is read back from the control.
  expect(tester.widget<DropdownButton<T>>(dropdown).value, value,
      reason: 'the choice $value did not take on $dropdown');
}

List<_Setting> _settings() => [
      ('nothing set', (_) async {}),
      for (final p in DriverProfile.values)
        (
          'driver type ${p.name}',
          (t) => _choose<DriverProfile>(
              t, find.byType(DropdownButton<DriverProfile>), p)
        ),
      for (final v in const ['kei-car', 'compact-sedan', '4wd', 'commercial-light'])
        (
          'vehicle type $v',
          (t) => _choose<String?>(t, find.byType(DropdownButton<String?>), v)
        ),
      for (final c in RoadSurfaceCondition.values)
        (
          'simulated road condition ${c.name}',
          (t) => _choose<RoadSurfaceCondition>(
              t, find.byType(DropdownButton<RoadSurfaceCondition>), c)
        ),
      for (final c in CircadianPhase.values)
        (
          'circadian phase ${c.name}',
          (t) => _choose<CircadianPhase?>(
              t, find.byType(DropdownButton<CircadianPhase?>), c)
        ),
      for (final f in CumulativeFatigueClass.values)
        (
          'fatigue ${f.name}',
          (t) => _choose<CumulativeFatigueClass>(
              t, find.byType(DropdownButton<CumulativeFatigueClass>), f)
        ),
      (
        'confidence high, confirmed',
        (t) async {
          await _choose<Confidence?>(
              t, find.byType(DropdownButton<Confidence?>), Confidence.high);
          final toggle = find.byType(SwitchListTile);
          await t.ensureVisible(toggle);
          await t.pump();
          await t.tap(toggle);
          await t.pump();
          expect(t.widget<SwitchListTile>(toggle).value, isTrue,
              reason: 'the confirmation did not take');
        }
      ),
    ];

/// One scripted drive on her page, after [setting] on the development page:
/// what her card's rung reads and what reaches her ears and hands at each step.
Future<List<String>> _scriptedDrive(
    WidgetTester tester, _Setting setting) async {
  final actuators = FakeAlertActuators();
  final positions = StreamController<PositionFix>.broadcast();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(SngnavApp(
    key: UniqueKey(),
    locale: const Locale('ja'),
    actuators: actuators,
    developerPageEntry: true,
    clock: () => _t0,
    jmaFetch: () async => JmaSuccess(_obsWithoutVisibility()),
    positionSource: () => positions.stream,
  ));
  await tester.pump();
  await tester.pump();

  await openDeveloperPage(tester);
  await setting.$2(tester);
  await tester.tap(find.byType(BackButton));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));

  final transcript = <String>[];
  var heard = 0;
  var felt = 0;
  void note(String step) {
    transcript.add('$step: rung ${rungOnCard()?.name ?? 'none'}');
    for (; heard < actuators.spoken.length; heard++) {
      final s = actuators.spoken[heard];
      transcript.add('  spoken [${s.localeTag}] ${s.text}');
    }
    for (; felt < actuators.haptics.length; felt++) {
      transcript.add('  vibration ${actuators.haptics[felt].name}');
    }
  }

  final share = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(share);
  await tester.pump();
  await tester.tap(share);
  await tester.pump();
  positions.add(PositionAvailable(
    latitude: 39.7167,
    longitude: 140.0983,
    accuracyMeters: 15,
    timestamp: _t0,
  ));
  await tester.pump();
  await tester.pump();
  note('trusted fix, no visibility reading');

  for (final band in const <double?>[1500, 700, 300, 80, null, 300]) {
    await _choose<double?>(
        tester, find.byKey(const Key('drive-hud-visibility')), band);
    note('visibility band ${band?.toInt() ?? 'none'}');
  }
  final blackout = find.byKey(const Key('drive-hud-blackout-button'));
  for (var i = 1; i <= 3; i++) {
    await tester.ensureVisible(blackout);
    await tester.pump();
    await tester.tap(blackout);
    await tester.pump();
    await tester.pump();
    note('blackout +${i * 60} s');
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await positions.close();
  return transcript;
}

void main() {
  test('the rung a live drive gives her along each input is the pinned table',
      () {
    final measured = _measuredTables();
    final changed = <String>[
      for (final e in measured.entries)
        if (_pinned[e.key]?.join('\n') != e.value.join('\n'))
          '${e.key}\n  pinned:\n    ${(_pinned[e.key] ?? const ['(none)']).join('\n    ')}'
              '\n  measured:\n    ${e.value.join('\n    ')}',
      for (final k in _pinned.keys)
        if (!measured.containsKey(k)) '$k: pinned, no longer measured',
    ];
    expect(changed, isEmpty, reason: changed.join('\n\n'));
  });

  testWidgets('no input on the development page changes her rung, her speech '
      'or her vibration along a live drive', (tester) async {
    final settings = _settings();
    final baseline = await _scriptedDrive(tester, settings.first);
    expect(baseline.where((l) => l.startsWith('  spoken')), isNotEmpty,
        reason: 'precondition: the scripted drive speaks to her:\n'
            '${baseline.join('\n')}');
    expect(
        baseline.map((l) => l.split(': rung ').last).toSet().length,
        greaterThanOrEqualTo(2),
        reason: 'precondition: the scripted drive moves her rung:\n'
            '${baseline.join('\n')}');
    final differ = <String>[];
    for (final s in settings.skip(1)) {
      final got = await _scriptedDrive(tester, s);
      if (got.join('\n') != baseline.join('\n')) {
        differ.add('${s.$1}:\n${got.join('\n')}');
      }
    }
    expect(differ, isEmpty,
        reason: 'baseline:\n${baseline.join('\n')}\n\n${differ.join('\n\n')}');
  });
}
