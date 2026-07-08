/// OPS-066 render-SEE capture harness for the (e) confidence-gated maneuver
/// narration panel (session-scope; NOT a CI assertion).
///
/// Produces fresh render PNGs of the `_maneuverNarrationPanel` banner
/// (`Key('maneuver-narration-banner')` in `lib/main.dart`) in each
/// confidence-gate state, so VAA can LOOK at them:
///   07 — SPEAK    (gpsTrusted, a right turn)   → the JA turn line
///   08 — SUPPRESS (lost / dead-reckoning)      → the honest 保留 silence line
///   09 — HEDGE    (gpsSuspect, DRY road)       → the softened line, NO icy coupling
///
/// HONESTY — how each state's decision is produced (stated so the reader can
/// trust the render):
///  - 07 SPEAK + 08 SUPPRESS use the REAL, live `DriveHudController` driven into
///    the mode through its public seam (a fresh accurate fix → gpsTrusted; a
///    fix then a 300 s blackout `poll` → lost/dead-reckoning), then the REAL
///    `controller.previewNextManeuver(...)` produces the decision.
///  - 09 HEDGE: `gpsSuspect` is NOT reachable through `DriveHudController`'s
///    public `onPositionFix`/`poll` seam (a `PositionAvailable` is always fed as
///    `TrustSignal.trusted`; only a suspect trust signal — which the app-level
///    seam never emits — yields gpsSuspect). So the HEDGE decision is produced
///    by calling `ManeuverNarrator.decide(mode: gpsSuspect, ...)` DIRECTLY —
///    which is the EXACT delegate `previewNextManeuver` calls internally
///    (`_narrator.decide(maneuver, mode, icyTurn, localeTag)`). Same code, same
///    output; only the mode-seeding differs.
///
/// The banner widget below reproduces `_maneuverNarrationPanel` faithfully: the
/// (bg, fg, tier) switch on `preview.confidence`, the suppressed→保留 `herLine`
/// substitution, the icy-coupled row gate, and the mode-honesty `_kv` line — all
/// copied verbatim from `lib/main.dart`. The raw ENGLISH engine instruction is
/// deliberately NOT rendered (matching the panel), and a test-time assertion
/// confirms it never appears.
///
/// Real Japanese glyphs: a system CJK font (IPAGothic + DroidSansFallback) is
/// loaded under both `Roboto` (the Material default family) and `NotoCJK`; the
/// harness theme uses `NotoCJK` (proven to render CJK+Latin in the sibling
/// `capture_test.dart`). If the font failed to load these would render tofu —
/// the produced PNGs are inspected visually to confirm real glyphs.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';

import 'render_see_env.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:localization_fallback/localization_fallback.dart'
    show LocalizationMode;
import 'package:routing_engine/routing_engine.dart' show RouteManeuver;
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/services/drive_hud_controller.dart';
import 'package:sngnav_app/services/drive_hud_localizer.dart';
import 'package:sngnav_app/services/maneuver_narration.dart';

import '../support/fake_alert_actuators.dart';



/// The driver-facing localizer, exactly as the panel uses it (JA for HER).
const _text = DriveHudLocalizer();

/// A single right-turn maneuver (the same shape `capture_test`'s siblings use).
/// Its ENGLISH `instruction` is the string that MUST NOT reach HER's surface.
const _rightTurn = RouteManeuver(
  index: 1,
  instruction: 'Right onto Main St',
  type: 'right',
  lengthKm: 0.4,
  timeSeconds: 30,
  position: LatLng(39.72, 140.10),
);

/// Faithful reproduction of `_maneuverNarrationPanel` (lib/main.dart) around the
/// banner: the (bg, fg, tier) switch, the suppressed→保留 herLine substitution,
/// the mode-honesty `_kv` line, and the icy-coupled row gate — all verbatim. The
/// raw English `maneuver.instruction` is deliberately NOT rendered.
Widget _panel({
  required ManeuverNarration preview,
  required LocalizationMode mode,
  required int maneuverCount,
  required int nextIndex,
}) {
  final (Color bg, Color fg, String tier) = switch (preview.confidence) {
    NarrationConfidence.speak => (
        Colors.green.shade100,
        Colors.green.shade900,
        'SPEAK — GPS trusted',
      ),
    NarrationConfidence.hedge => (
        Colors.amber.shade100,
        Colors.amber.shade900,
        'HEDGE — GPS suspect',
      ),
    NarrationConfidence.suppressed => (
        Colors.blueGrey.shade100,
        Colors.blueGrey.shade900,
        'SUPPRESSED — position not trusted',
      ),
  };

  final herLine = preview.confidence == NarrationConfidence.suppressed
      ? 'この曲がり角の案内は保留しています（現在地が信頼できません）。'
      : preview.text;

  Widget kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text('$k:', style: TextStyle(color: Colors.grey.shade700)),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'The NEXT maneuver (parsed by OsrmRoutingEngine, steps=true), narrated '
        'ONLY when the honest position allows it. A turn is never spoken '
        'against a drifting or lost dot — the confidently-wrong instruction '
        'this gate refuses. Simulate a GPS blackout in the drive panel above '
        'to watch SPEAK → SUPPRESS.',
        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
      ),
      const SizedBox(height: 8),
      kv('現在地の信頼度', _text.modeLabel(mode, 'ja')),
      kv('Maneuvers parsed', '$maneuverCount (next: $nextIndex)'),
      const SizedBox(height: 8),
      Container(
        key: const Key('maneuver-narration-banner'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tier,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(herLine, style: TextStyle(color: fg, fontSize: 15)),
            if (preview.icyCoupled &&
                preview.confidence != NarrationConfidence.suppressed) ...[
              const SizedBox(height: 4),
              Text(
                '❄ icy-turn advisory coupled',
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

void main() {
  const ipa = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf';
  const droid = '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cjkLoaded = await loadCjkFamily('Roboto', [ipa, droid]);
    if (!cjkLoaded) installNoopGoldenComparator();
    await loadCjkFamily('NotoCJK', [ipa, droid]);
    final tmp = await Directory.systemTemp.createTemp('fm_cache_maneuver_see');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  final t0 = DateTime.utc(2026, 1, 1, 8, 0, 0);

  PositionAvailable freshFix(DateTime t) => PositionAvailable(
        latitude: 39.72,
        longitude: 140.10,
        accuracyMeters: 20,
        timestamp: t,
      );

  Future<void> capture(
    WidgetTester tester, {
    required Widget panel,
    required String out,
  }) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(820 * 2, 380 * 2);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'NotoCJK',
          fontFamilyFallback: const ['NotoCJK', 'Roboto'],
        ),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: panel,
          ),
        ),
      ),
    );
    await tester.pump();
    // The raw English engine instruction must NEVER reach HER's surface.
    expect(find.text('Right onto Main St'), findsNothing,
        reason: 'raw English maneuver instruction must not be rendered to HER');
    await expectLater(find.byType(MaterialApp), matchesGoldenFile(out));
  }

  testWidgets('07 — SPEAK (gpsTrusted): the JA right-turn line', (tester) async {
    // REAL live controller → gpsTrusted → REAL previewNextManeuver.
    final c = DriveHudController(actuators: FakeAlertActuators(), localeTag: 'ja');
    c.onPositionFix(freshFix(t0), now: t0);
    expect(c.estimate?.mode, LocalizationMode.gpsTrusted);

    final preview = c.previewNextManeuver(_rightTurn, icyTurn: false);
    expect(preview.confidence, NarrationConfidence.speak);
    expect(preview.text, contains('右折'));

    await capture(
      tester,
      panel: _panel(
        preview: preview,
        mode: c.estimate!.mode,
        maneuverCount: 1,
        nextIndex: _rightTurn.index + 1,
      ),
      out: '../../render_out/07_maneuver_speak_trusted.png',
    );
  });

  testWidgets('08 — SUPPRESS (lost): the honest 保留 silence line',
      (tester) async {
    // REAL live controller → fix then a 300 s blackout poll → lost / DR →
    // REAL previewNextManeuver → SUPPRESS.
    final c = DriveHudController(actuators: FakeAlertActuators(), localeTag: 'ja');
    c.onPositionFix(freshFix(t0), now: t0);
    c.poll(now: t0.add(const Duration(seconds: 300)));
    final mode = c.estimate!.mode;
    expect(
      mode == LocalizationMode.lost || mode == LocalizationMode.deadReckoning,
      isTrue,
      reason: 'a 300 s blackout must degrade off a trusted dot',
    );

    final preview = c.previewNextManeuver(_rightTurn, icyTurn: false);
    expect(preview.confidence, NarrationConfidence.suppressed);
    expect(preview.text, isEmpty,
        reason: 'a suppressed decision carries NO turn phrase by construction');

    await capture(
      tester,
      panel: _panel(
        preview: preview,
        mode: mode,
        maneuverCount: 1,
        nextIndex: _rightTurn.index + 1,
      ),
      out: '../../render_out/08_maneuver_suppress_lost.png',
    );
  });

  testWidgets('09 — HEDGE (gpsSuspect, DRY road): softened, NO icy coupling',
      (tester) async {
    // gpsSuspect is unreachable through DriveHudController's public seam, so the
    // decision comes from ManeuverNarrator.decide DIRECTLY — the EXACT delegate
    // previewNextManeuver calls internally. icyTurn:false = DRY road.
    const narrator = ManeuverNarrator(text: _text);
    final preview = narrator.decide(
      maneuver: _rightTurn,
      mode: LocalizationMode.gpsSuspect,
      icyTurn: false,
      localeTag: 'ja',
    );
    expect(preview.confidence, NarrationConfidence.hedge);
    // The MUST fix: a DRY-road suspect must NOT raise a false icy/CRITICAL warn.
    expect(preview.icyCoupled, isFalse);
    expect(preview.text.contains('凍結'), isFalse,
        reason: 'dry-road suspect must not mention ice (凍結)');
    expect(preview.severity.name, isNot('critical'),
        reason: 'dry-road suspect must not escalate to CRITICAL');

    await capture(
      tester,
      panel: _panel(
        preview: preview,
        mode: LocalizationMode.gpsSuspect,
        maneuverCount: 1,
        nextIndex: _rightTurn.index + 1,
      ),
      out: '../../render_out/09_maneuver_hedge_suspect.png',
    );
  });
}
