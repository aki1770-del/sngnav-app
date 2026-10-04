/// Render-and-look capture harness for the (e) confidence-gated maneuver
/// narration panel (session-scope; NOT a CI assertion).
///
/// Produces fresh render PNGs of the `_maneuverNarrationPanel` banner
/// (`Key('maneuver-narration-banner')` in `lib/main.dart`) in each
/// confidence-gate state, so a reviewer can LOOK at them:
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
///  - 09 HEDGE: the drive brain's own gate does not hedge. `gpsSuspect` is
///    reachable through `onPositionFix` since 2026-10-05 (a fix whose accuracy
///    is over 150 m), but while `kSuspectWithholdsTurn` stands the gate
///    withholds the turn there instead of hedging it. Until 2026-10-05 no
///    `PositionAvailable` reached gpsSuspect at all (every one was fed as
///    `TrustSignal.trusted`). So the HEDGE decision is produced
///    by calling `ManeuverNarrator.decide(mode: gpsSuspect, ...)` DIRECTLY —
///    which is the EXACT delegate `previewNextManeuver` calls internally
///    (`_narrator.decide(maneuver, mode, icyTurn, localeTag)`). Same code, same
///    output; only the mode-seeding differs.
///
/// The panel below is a copy of `_maneuverNarrationPanel` in `lib/main.dart`,
/// because that method is private to the app's state and cannot be pumped
/// here. The (bg, fg, tier) switch on `preview.confidence`, the
/// suppressed→保留 `herLine` substitution, the position row and its `_kv`
/// helper, the banner and its icy-coupled rows are the app's own source,
/// token for token, and `maneuver_panel_copy_is_the_app_panel_test.dart`
/// goes red when they are not. The raw ENGLISH engine instruction is
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
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/drive_hud_controller.dart';
import 'package:sngnav_app/services/drive_hud_localizer.dart';
import 'package:sngnav_app/services/maneuver_narration.dart';
import 'package:sngnav_app/widgets/advisory_cards.dart' show kCautionTextOnAmber;

import '../support/assessed_fix.dart';
import '../support/fake_alert_actuators.dart';



/// The driver-facing localizer the narrator words its line with (JA by default).
const _text = DriveHudLocalizer();

/// A single right-turn maneuver (the same shape `capture_test`'s siblings use).
/// Its ENGLISH `instruction` is the string that MUST NOT reach the driver's surface.
const _rightTurn = RouteManeuver(
  index: 1,
  instruction: 'Right onto Main St',
  type: 'right',
  lengthKm: 0.4,
  timeSeconds: 30,
  position: LatLng(39.72, 140.10),
);

/// The values the app's panel reads from its own state, which the copy takes
/// as fields. Mirrors the app's private `_IcyTurnSource` (lib/main.dart): the
/// copied rows below name `_IcyTurnSource.measured`, so a renamed member in
/// the app turns the copy-drift test red.
enum _IcyTurnSource {
  none,
  measured,
  // Kept so the copy has every member the app has; no golden draws an icy
  // mark yet, so nothing here names it.
  // ignore: unused_field
  testValue,
}

/// A copy of `_maneuverNarrationPanel` (lib/main.dart). The raw English
/// `maneuver.instruction` is deliberately NOT rendered.
///
/// Re-copied 2026-09-15, when the panel stopped drawing English in every
/// language: the banner's state and the icy mark now come from the app's own
/// strings, and the paragraph and the parsed-maneuver count are no longer
/// drawn. Until then this copy still drew them, so its three frames showed a
/// panel the app no longer had.
///
/// Re-copied 2026-10-04, when the same thing was found again. The app's
/// hedge arm had painted its words in `kCautionTextOnAmber` (7.16:1 on
/// `amber.shade100`) since 2026-09-15, and this copy still painted
/// `amber.shade900` (2.38:1), so golden 09 showed a contrast the app no
/// longer had. The copy also differed from the app in four places no golden
/// showed yet: a fixed 110 px label column where the app measures the label,
/// a position row drawn even with no position, no test-position label, and no
/// line saying where an icy mark came from. From the confidence `switch` to
/// the end of the banner, and in `_kv`, the code below is now the app's own,
/// and `maneuver_panel_copy_is_the_app_panel_test.dart` compares the two.
///
/// What the copy still leaves out, on purpose and named here: the
/// narrate-button row under the banner, the `_section` card and title the
/// app sets the panel in, and the app's theme (a blueGrey-seeded colour
/// scheme with the bundled symbol font as fallback). The goldens draw the
/// panel bare on white.
///
/// And the width. These goldens draw the banner 788 dp wide (820 less 16 on
/// each side). On a phone 392.7 dp wide (1080 x 2340 px at 2.75) the app
/// draws it 328.7 dp wide, and there its lines wrap. The hedge line takes
/// three lines and breaks inside words (可能|性, ご判|断); the paused line
/// takes two and breaks inside （現|在地. Measured 2026-10-04 on the app's own
/// panel at that size, with this harness's fonts; a phone's own fonts may
/// break elsewhere. So 07, 08 and 09 pin the panel's code (colours, words,
/// padding, the `_kv` column). They are not what she reads at a glance, and
/// a reviewer must not judge that from them.
class _ManeuverNarrationPanelCopy {
  const _ManeuverNarrationPanelCopy({
    required this.preview,
    required this.mode,
    bool isMockPosition = false,
    // No golden draws an icy mark yet, so no caller passes this; it is here
    // so the copy can draw every state the app's panel can.
    // ignore: unused_element_parameter
    this.icySource = _IcyTurnSource.none,
  }) : _isMockPosition = isMockPosition;

  final ManeuverNarration preview;
  final LocalizationMode? mode;
  final bool _isMockPosition;
  final _IcyTurnSource icySource;

  static const DriveHudLocalizer _driveHudText = DriveHudLocalizer();

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: LayoutBuilder(builder: (context, constraints) {
        final labelStyle = TextStyle(color: Colors.grey.shade700);
        final painter = TextPainter(
          text: TextSpan(
            text: '$k:',
            style: DefaultTextStyle.of(context).style.merge(labelStyle),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        var labelWidth = painter.width + 8; // breathing room before value
        painter.dispose();
        if (labelWidth < 110) labelWidth = 110;
        if (constraints.hasBoundedWidth &&
            labelWidth > constraints.maxWidth * 0.6) {
          labelWidth = constraints.maxWidth * 0.6;
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: labelWidth, child: Text('$k:', style: labelStyle)),
            Expanded(child: Text(v)),
          ],
        );
      }),
    );
  }

  Widget build() {
    const l = AppL10n(Locale('ja'));
    final mode = this.mode;
    // From here to the end of the banner `Container`, the app's own code.
    final (Color bg, Color fg, String tier) = switch (preview.confidence) {
      NarrationConfidence.speak => (
          Colors.green.shade100,
          Colors.green.shade900,
          l.maneuverTierSpeak,
        ),
      NarrationConfidence.hedge => (
          Colors.amber.shade100,
          kCautionTextOnAmber,
          l.maneuverTierHedge,
        ),
      NarrationConfidence.suppressed => (
          Colors.blueGrey.shade100,
          Colors.blueGrey.shade900,
          l.maneuverTierSuppressed,
        ),
    };

    final herLine = preview.confidence == NarrationConfidence.suppressed
        ? l.maneuverGuidancePaused
        : preview.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mode != null)
          _kv(
              l.driveHudPositionTrustLabel,
              _driveHudText.modeLabel(mode, l.locale.languageCode,
                  isMock: _isMockPosition)),
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
                key: const Key('maneuver-narration-tier'),
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
                  l.maneuverIcyMark,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (icySource == _IcyTurnSource.measured)
                  Text(
                    key: const Key('maneuver-measured-road-ice'),
                    l.maneuverMeasuredRoadIceInForce,
                    style: TextStyle(color: fg, fontSize: 12),
                  )
                else
                  Text(
                    key: const Key('maneuver-test-road-condition'),
                    l.maneuverTestRoadConditionInForce,
                    style: TextStyle(color: fg, fontSize: 12),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The copy above, in the state each golden shows.
Widget _panel({
  required ManeuverNarration preview,
  required LocalizationMode mode,
}) =>
    _ManeuverNarrationPanelCopy(preview: preview, mode: mode).build();

void main() {
  const ipa = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf';
  const droid = '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cjkLoaded = await loadCjkFamily('Roboto', [ipa, droid]);
    if (!cjkLoaded || !goldenPixelsComparableHere()) {
      installNoopGoldenComparator();
    }
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
        // She never sees the debug ribbon: a release build does not draw it.
        debugShowCheckedModeBanner: false,
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
    // The raw English engine instruction must NEVER reach the driver's surface.
    expect(find.text('Right onto Main St'), findsNothing,
        reason: 'raw English maneuver instruction must not be rendered to the driver');
    // No debug ribbon over the top-end corner of the stored render: a
    // release build never draws it, so the golden must not either.
    expect(find.byType(CheckedModeBanner), findsNothing);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile(out));
  }

  testWidgets('07 — SPEAK (gpsTrusted): the JA right-turn line', (tester) async {
    // REAL live controller → gpsTrusted → REAL previewNextManeuver.
    final c = DriveHudController(actuators: FakeAlertActuators(), localeTag: 'ja');
    c.wouldTrust(justBefore(freshFix(t0)));
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
      ),
      out: '../../render_out/07_maneuver_speak_trusted.png',
    );
  });

  testWidgets('08 — SUPPRESS (lost): the honest 保留 silence line',
      (tester) async {
    // REAL live controller → fix then a 300 s blackout poll → lost / DR →
    // REAL previewNextManeuver → SUPPRESS.
    final c = DriveHudController(actuators: FakeAlertActuators(), localeTag: 'ja');
    c.wouldTrust(justBefore(freshFix(t0)));
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
      ),
      out: '../../render_out/09_maneuver_hedge_suspect.png',
    );
  });
}
