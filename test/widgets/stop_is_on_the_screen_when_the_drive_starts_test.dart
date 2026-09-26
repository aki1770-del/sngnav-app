/// R122-STOP-VISIBLE (FSE): drive-start alone must put 停止 on her screen.
///
/// WHY, written before the act (FSE, R122). The resume path already brings 停止
/// onto the screen — _bringDriveStopIntoView is wired to _onAppResumed. But the
/// FIRST moment 停止 must be reachable is drive-start itself. On a phone whose
/// alert channels are dead (no offline ja voice, no vibrator, media muted) the
/// app raises caution rows that push the status line — the row that carries the
/// drive-stop 停止 — down the page. At drive-start, with no resume, 停止 could
/// sit under the system navigation bar or below the fold, and only a later
/// app-resume corrected it. The drive she just started is exactly when a 停止
/// she can reach matters most.
///
/// THE INVARIANT: in the drive-active state, one frame after drive-start and
/// BEFORE any resume, at HER geometry, the drive-stop 停止 render box bottom
/// lies at or above the fold less an 8 dp clearance of the navigation bar.
///
/// HER geometry: DPR 2.75, 1080x2340 px, viewPadding bottom 130 px = 47.3 dp.
/// Fold = 850.9 - 47.3. Clearance = 8 dp (main.dart clearOfNavigationBar).
///
/// This test FAILS at a8c8bee without Fix 1 (drive-start does not scroll 停止
/// into view) and PASSES with it. Proven red->green by stashing the main.dart
/// change.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/audio_readiness.dart';
import 'package:sngnav_app/services/haptic_readiness.dart';
import 'package:sngnav_app/services/voice_lane_readiness.dart';

import '../support/fake_alert_actuators.dart';

const _ja = AppL10n(Locale('ja'));
final _now = DateTime.utc(2026, 1, 14, 21, 40);

const _dpr = 2.75;
const _physical = Size(1080, 2340);
const _insetBottom = 130.0;
// The fold, less the navigation-bar clearance the fix keeps (main.dart's
// clearOfNavigationBar). 850.9 - 47.3 - 8.0.
final double _foldLessClearance =
    _physical.height / _dpr - _insetBottom / _dpr - 8.0;

Future<JmaResult> _jma() async => JmaSuccess(JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 5,
      humidityPercent: 50,
      windMetersPerSecond: 2,
      snowDepthCm: null,
      precipitation10mMm: 0,
      visibilityMeters: 1500,
      observedAtJstKey: '202601150630',
      fetchedAt: _now,
    ));

/// The healthy device answers nothing on these probes; the dead one answers
/// no-voice, no-vibrator, muted — the same three-dead-channel setup the
/// first-screen tests use, which is what raises the caution rows above 停止.
final class _MutedAudio implements AudioReadinessProbe {
  @override
  Future<AudioReadiness?> read() async => const AudioReadiness(
      mediaVolume: 0, mediaVolumeMax: 15, ttsServiceVisible: true);
}

final class _NoVibrator implements HapticReadinessProbe {
  @override
  Future<bool?> read() async => false;
}

/// The drive-stop 停止: the TextButton carried in the status-line row, the one
/// main.dart keys with _driveStopKey. Located through her-status-line rather
/// than that private key, as the return-to-screen test anchors.
Finder _driveStop() {
  final row = find
      .ancestor(
        of: find.byKey(const Key('her-status-line')),
        matching: find.byType(Row),
      )
      .first;
  return find.descendant(
      of: row, matching: find.widgetWithText(TextButton, _ja.stop));
}

void main() {
  testWidgets(
      'R122-STOP-VISIBLE: with dead alert channels, one frame after drive-start '
      'the 停止 bottom is at or above the fold less the 8 dp nav-bar clearance',
      (tester) async {
    tester.view.devicePixelRatio = _dpr;
    tester.view.physicalSize = _physical;
    tester.view.padding =
        const FakeViewPadding(top: 73, bottom: _insetBottom);
    tester.view.viewPadding =
        const FakeViewPadding(top: 73, bottom: _insetBottom);
    addTearDown(tester.view.reset);

    final ctrl = StreamController<PositionFix>.broadcast();
    addTearDown(ctrl.close);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(SngnavApp(
      locationConsent: true,
      actuators: FakeAlertActuators(),
      locale: const Locale('ja'),
      clock: () => _now,
      jmaFetch: _jma,
      positionSource: () => ctrl.stream,
      // All three eyes-off channels dead: the caution rows that occlude 停止.
      voiceLaneReader: () async => VoiceLaneVerdict.noJaVoice,
      hapticReadinessProbe: _NoVibrator(),
      audioReadinessProbe: _MutedAudio(),
    ));
    await tester.pump();
    await tester.pump();

    // She starts the drive from her first screen. NO resume is sent: the fix
    // under test must bring 停止 onto the screen at drive-start on its own.
    final share = find.byKey(const Key('share-location-button'));
    await tester.ensureVisible(share);
    await tester.pump();

    // The page's own Scrollable, captured through the share control while it is
    // still on screen (the status line the fix targets does not exist until a
    // drive runs). The same Scrollable persists across the drive-active
    // rebuild, so this state ref stays valid.
    final page = tester.state<ScrollableState>(
        find.ancestor(of: share, matching: find.byType(Scrollable)).first);

    // tester.tap does NOT pump: _shareLocation runs and schedules the
    // post-frame bring-into-view, but no frame has rendered yet. Put the page
    // at the top — the first-screen scroll she taps share from — so the
    // drive-start frame renders with 停止 below the fold. This is the occlusion
    // the fix exists for; at HER font on her device the dead-channel banner
    // reaches it without a scroll, but the test font is smaller (the
    // return-to-screen test records the same font caveat).
    await tester.tap(share);
    page.position.jumpTo(0);
    ctrl.add(PositionAvailable(
      latitude: 39.7186,
      longitude: 140.1024,
      accuracyMeters: 8,
      timestamp: _now,
    ));

    // One frame after drive-start: the frame the post-frame bring-into-view
    // runs on.
    await tester.pump();
    await tester.pump();

    expect(_driveStop(), findsOneWidget,
        reason: 'the drive-stop 停止 is drawn while a drive runs');
    final bottom = tester.getRect(_driveStop()).bottom;
    // The fix scrolls 停止 so its bottom lands EXACTLY at the fold less the 8 dp
    // clearance, so this is a boundary equality; the 1e-9 absorbs only the
    // float representation of that boundary (795.6363636363637 vs ...636).
    // WITHOUT the fix the page stays at scroll 0 and 停止 sits at 848.5 dp —
    // 52.9 dp below the fold, under the navigation bar — so this expectation
    // is genuinely red at a8c8bee and green with Fix 1 (proven by stashing
    // lib/main.dart).
    expect(bottom, lessThanOrEqualTo(_foldLessClearance + 1e-9),
        reason: 'drive-start must leave 停止 at or above the fold less 8 dp '
            '(${_foldLessClearance.toStringAsFixed(1)} dp); it is at '
            '${bottom.toStringAsFixed(1)} dp. Without the drive-start '
            'bring-into-view she cannot reach 停止 on the drive she just '
            'started.');
  });
}
