/// Render-and-look capture harness for the (e) confidence-gated maneuver
/// narration panel. Its pixels are compared only on a host that cut these
/// goldens; its word checks run everywhere, CI included.
///
/// Produces fresh render PNGs of the app's own `ManeuverNarrationPanel`
/// (`lib/widgets/maneuver_narration_panel.dart`) in each confidence-gate
/// state, so a reviewer can LOOK at them:
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
///    output; only the mode-seeding differs. No position the app has today
///    reaches this state, so 09 shows a state she cannot see yet.
///
/// The panel is the app's own widget, not a copy. Until 2026-10-04 it was a
/// private method in `lib/main.dart`, so this file drew a copy of it, and the
/// copy drifted from the app twice (2026-09-15 and 2026-10-04) while 07, 08
/// and 09 passed, because a golden compares a drawing with an image of the
/// same drawing. The raw ENGLISH engine instruction is deliberately NOT
/// rendered (matching the panel), and a test-time assertion confirms it
/// never appears.
///
/// The panel takes its words from `AppL10n.of(context)`, which falls back to
/// English when no `AppL10n` delegate is installed. So the harness installs
/// the app's delegates and locales, and every test checks the state's words
/// in Japanese. Those checks are not pixel comparisons, so they run on CI too.
///
/// The panel is drawn in the app's own theme (`sngnavTheme`), so its text and
/// the narrate button are in her colours. What these goldens still leave out,
/// named here: the `_section` card and title the app sets the panel in; the
/// goldens draw the panel bare on white. flutter_test also draws a shadow as
/// a solid outline, which she does not see.
///
/// And the width. These goldens draw the banner 788 dp wide (820 less 16 on
/// each side). On a phone 392.7 dp wide (1080 x 2340 px at 2.75) the app
/// draws it 328.7 dp wide, and there its lines wrap. The hedge line takes
/// three lines and breaks inside words (可能|性, ご判|断); the paused line
/// takes two and breaks inside （現|在地. Measured 2026-10-04 on the app's own
/// panel at that size, with this harness's fonts; a phone's own fonts may
/// break elsewhere. So 07, 08 and 09 pin the panel's drawing (colours, words,
/// padding, the position row's column). They are not what she reads at a
/// glance, and a reviewer must not judge that from them.
///
/// Real Japanese glyphs: a system CJK font (IPAGothic + DroidSansFallback) is
/// loaded under `Roboto`, the Material default family the app's theme uses.
/// If the font failed to load these would render tofu — the produced PNGs
/// are inspected visually to confirm real glyphs.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_see_env.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:localization_fallback/localization_fallback.dart'
    show LocalizationMode;
import 'package:routing_engine/routing_engine.dart' show RouteManeuver;
import 'package:sngnav_app/app_theme.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/drive_hud_controller.dart';
import 'package:sngnav_app/services/drive_hud_localizer.dart';
import 'package:sngnav_app/services/maneuver_narration.dart';
import 'package:sngnav_app/widgets/maneuver_narration_panel.dart';

import '../support/assessed_fix.dart';
import '../support/fake_alert_actuators.dart';
import '../support/plain_words.dart';

/// The driver-facing localizer the narrator words its line with (JA by default).
const _text = DriveHudLocalizer();

/// The app's own strings, in the language these goldens are drawn in.
const _ja = AppL10n(Locale('ja'));

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

/// The app's panel in the state each golden shows: no test position, no icy
/// mark, before any narration, with both channels verified.
Widget _panel({
  required ManeuverNarration preview,
  required LocalizationMode mode,
}) =>
    ManeuverNarrationPanel(
      preview: preview,
      mode: mode,
      isMockPosition: false,
      icySource: IcyTurnSource.none,
      onNarrate: () {},
      lastNarration: null,
      speechUnverified: false,
      hapticUnverified: false,
    );

void main() {
  const ipa = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf';
  const droid = '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cjkLoaded = await loadCjkFamily('Roboto', [ipa, droid]);
    if (!cjkLoaded || !goldenPixelsComparableHere()) {
      installNoopGoldenComparator();
    }
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
    required String tier,
    required String herLine,
    required String positionLabel,
    required String button,
    required String out,
  }) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(820 * 2, 380 * 2);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        // The app's own delegates and locales: without the AppL10n delegate
        // the panel would draw its English fallback.
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppL10n.supportedLocales,
        // She never sees the debug ribbon: a release build does not draw it.
        debugShowCheckedModeBanner: false,
        // The app's own theme. Its text is in Material's 'Roboto', which
        // setUpAll loads with the CJK fonts above.
        theme: sngnavTheme(),
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
    // The words this golden shows, checked as words, so a harness that drew
    // another language or another state goes red on CI too.
    expect(
        wordsOf(tester
            .widget<Text>(find.byKey(const Key('maneuver-narration-tier')))),
        tier);
    expect(findWords(herLine), findsOneWidget);
    expect(find.text('${_ja.driveHudPositionTrustLabel}:'), findsOneWidget);
    expect(find.text(positionLabel), findsOneWidget);
    // The button's words follow the state (2026-10-04): it is not offered,
    // and says reading is on hold, while the turn is not read aloud.
    expect(findWords(button), findsOneWidget);
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
      tier: _ja.maneuverTierSpeak,
      herLine: preview.text,
      positionLabel: _text.modeLabel(c.estimate!.mode, 'ja'),
      button: _ja.maneuverNarrateButton,
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
      tier: _ja.maneuverTierSuppressed,
      herLine: _ja.maneuverGuidancePaused,
      positionLabel: _text.modeLabel(mode, 'ja'),
      button: _ja.maneuverNarrateButtonOnHold,
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
      tier: _ja.maneuverTierHedge,
      herLine: preview.text,
      positionLabel: _text.modeLabel(LocalizationMode.gpsSuspect, 'ja'),
      button: _ja.maneuverNarrateButton,
      out: '../../render_out/09_maneuver_hedge_suspect.png',
    );
  });
}
