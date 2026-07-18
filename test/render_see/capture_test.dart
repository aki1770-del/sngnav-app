/// OPS-066 render-SEE capture harness (session-scope; NOT a CI assertion).
///
/// Produces fresh render PNGs of the HER-facing JA surfaces into
/// `render_out/` via golden capture so VAA can LOOK at them. Run with:
///
///   flutter test --update-goldens test/render_see/capture_test.dart
///
/// Real Japanese glyphs: a system CJK font is loaded via [FontLoader] under
/// the `Roboto` family (the Material default family the real app's text
/// resolves to, since SngnavApp's ThemeData sets no fontFamily) AND under an
/// explicit `NotoCJK` family for the surfaces this harness builds itself. If
/// the CJK font failed to load, these captures would render tofu/boxes — the
/// produced PNGs are inspected visually to confirm real glyphs.
library;

import 'dart:io';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_see_env.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/advisory_service.dart';
import 'package:sngnav_app/services/provider_coverage.dart';
import 'package:sngnav_app/widgets/advisory_cards.dart';

import '../support/fake_alert_actuators.dart';

/// Fake JMA provider returning one 大雪警報 (renders as the JMA card).
class _FakeJma implements AdvisoryProvider {
  @override
  AdvisorySource get source => AdvisorySource.jmaJapan;
  @override
  Future<void> init() async {}
  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async =>
      [
        Advisory(
          source: AdvisorySource.jmaJapan,
          eventClass: '大雪警報',
          severity: AdvisorySeverity.severe,
          certainty: AdvisoryCertainty.likely,
          urgency: AdvisoryUrgency.expected,
          areaDescription: '秋田中央',
          effective: DateTime.utc(2026, 1, 15, 4, 23),
          expires: DateTime.utc(2026, 1, 16, 4, 23),
          headline: '秋田県では、大雪による交通障害に警戒してください。',
          description: '秋田県では、15日夜遅くにかけて大雪となる見込みです。',
        ),
      ];
}

/// Fake NWS provider that THROWS if ever fetched — its absence from the
/// captured surface is the proof it was region-gated out for the JP point.
class _ThrowingNws implements AdvisoryProvider {
  @override
  AdvisorySource get source => AdvisorySource.nwsUnitedStates;
  @override
  Future<void> init() async {}
  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async =>
      throw Exception('HTTP 400 — NWS has no Japan coverage');
}



void main() {
  // IPAGothic is a single-face TTF covering BOTH Latin/ASCII and Japanese
  // (kanji + kana) — so nothing renders as tofu. DroidSansFallbackFull is a
  // pan-CJK backup for any glyph IPA lacks.
  const ipa = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf';
  const droid = '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Register the font under BOTH the app's default family (Roboto) and an
    // explicit family, so (a) the real SngnavApp tree renders CJK+Latin and
    // (b) the harness-built advisory surface can request it directly.
    final cjkLoaded = await loadCjkFamily('Roboto', [ipa, droid]);
    if (!cjkLoaded) installNoopGoldenComparator();
    await loadCjkFamily('NotoCJK', [ipa, droid]);
    // flutter_map's built-in tile cache calls path_provider on first build;
    // there is no plugin in a widget test, so it throws an intermittent
    // unhandled async error. Give it a real temp dir so the call succeeds.
    final tmp = await Directory.systemTemp.createTemp('fm_cache_render_see');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  /// Size the surface + capture the whole app frame after scrolling [target]
  /// to the top of the viewport.
  Future<void> captureApp(
    WidgetTester tester, {
    required Finder target,
    required Size logical,
    required String out,
  }) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = Size(logical.width * 2, logical.height * 2);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();
    await tester.ensureVisible(target);
    await tester.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile(out));
  }

  testWidgets('01 — JA consent gate (deny-by-default)', (tester) async {
    await tester.pumpWidget(const SngnavApp(locale: Locale('ja')));
    await tester.pump();
    // The consent gate = the Column that holds the disclosure paragraph
    // (buttons row + disclosure). Nothing tapped: deny-by-default.
    final gate = find
        .ancestor(
          of: find.byKey(const Key('location-disclosure')),
          matching: find.byType(Column),
        )
        .first;
    await captureApp(
      tester,
      target: gate,
      logical: const Size(800, 320),
      out: '../../render_out/01_ja_consent_gate.png',
    );
  });

  testWidgets('02 — JA drive HUD, CONTINUE (走行を継続)', (tester) async {
    final fake = FakeAlertActuators();
    await tester.pumpWidget(
      SngnavApp(actuators: fake, locale: const Locale('ja')),
    );
    await tester.pump();

    final mockBtn = find.byKey(const Key('use-mock-button'));
    await tester.ensureVisible(mockBtn);
    await tester.pump();
    await tester.tap(mockBtn);
    await tester.pump();
    await tester.pump();

    // The honest default is UNKNOWN (未計測 → heightened); the only truthful way
    // to reach 走行を継続 is an actual clear reading, so select the CLEAR demo
    // visibility override before capturing the continue state.
    final visDropdown = find.byKey(const Key('drive-hud-visibility'));
    await tester.ensureVisible(visDropdown);
    await tester.pump();
    await tester.tap(visDropdown);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('クリア ~1.5 km').last);
    await tester.pump(const Duration(milliseconds: 400));

    final banner = find.byKey(const Key('drive-hud-caution-banner'));
    // Confirm we are in the CONTINUE state before capturing.
    expect(
      find.descendant(of: banner, matching: find.text('走行を継続')),
      findsOneWidget,
    );
    await captureApp(
      tester,
      target: banner,
      logical: const Size(800, 260),
      out: '../../render_out/02_drive_hud_continue.png',
    );
  });

  testWidgets('03 — JA drive HUD, RISEN to STOP (停車の検討)', (tester) async {
    final fake = FakeAlertActuators();
    await tester.pumpWidget(
      SngnavApp(actuators: fake, locale: const Locale('ja')),
    );
    await tester.pump();

    final mockBtn = find.byKey(const Key('use-mock-button'));
    await tester.ensureVisible(mockBtn);
    await tester.pump();
    await tester.tap(mockBtn);
    await tester.pump();
    await tester.pump();

    // Simulate GPS blackout: 3 × +60 s → past the 120 s honesty horizon →
    // honest dot degrades to `lost` → the caution rung RISES to 停車の検討.
    final blackoutBtn = find.byKey(const Key('drive-hud-blackout-button'));
    for (var i = 0; i < 3; i++) {
      await tester.ensureVisible(blackoutBtn);
      await tester.pump();
      await tester.tap(blackoutBtn);
      await tester.pump();
      await tester.pump();
    }

    final banner = find.byKey(const Key('drive-hud-caution-banner'));
    expect(
      find.descendant(of: banner, matching: find.text('停車の検討')),
      findsOneWidget,
    );
    await captureApp(
      tester,
      target: banner,
      logical: const Size(800, 300),
      out: '../../render_out/03_drive_hud_stop.png',
    );
  });

  testWidgets('04 — JA advisory ordering (気象庁 leads, NWS de-emphasized)',
      (tester) async {
    // A JMA (Japanese) advisory + an English NWS advisory. On HER ja surface
    // AdvisoryCards must (a) order 気象庁 FIRST and (b) de-emphasize + caption
    // the English NWS card as 英語の情報（参考）. Passing [NWS, JMA] proves the
    // reorder is real (input order is NWS-first).
    final jma = Advisory(
      source: AdvisorySource.jmaJapan,
      eventClass: '大雪警報',
      severity: AdvisorySeverity.severe,
      certainty: AdvisoryCertainty.likely,
      urgency: AdvisoryUrgency.expected,
      areaDescription: '秋田中央',
      effective: DateTime.utc(2026, 1, 15, 4, 23),
      expires: DateTime.utc(2026, 1, 16, 4, 23),
      headline: '秋田県では、大雪による交通障害に警戒してください。',
      description: '秋田県では、15日夜遅くにかけて大雪となる見込みです。',
    );
    final nws = Advisory(
      source: AdvisorySource.nwsUnitedStates,
      eventClass: 'Winter Storm Warning',
      severity: AdvisorySeverity.severe,
      certainty: AdvisoryCertainty.likely,
      urgency: AdvisoryUrgency.expected,
      areaDescription: 'Upper Peninsula of Michigan',
      effective: DateTime.utc(2026, 1, 15, 4, 23),
      expires: DateTime.utc(2026, 1, 16, 4, 23),
      headline: 'Heavy snow expected.',
      description: 'Total snow accumulations of 8 to 14 inches.',
    );

    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(440 * 2, 720 * 2);
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
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ja'), Locale('en')],
        home: Scaffold(
          backgroundColor: Colors.white,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: AdvisoryCards(
              loading: false,
              result: AdvisoryAggregateResult(
                advisories: [nws, jma],
                providerErrors: const [],
              ),
              errorMessage: null,
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../render_out/04_advisory_ja_ordering.png'),
    );
  });

  testWidgets('06 — JA advisory, Akita point → JMA only, NO NWS error',
      (tester) async {
    // Region-gate proof, rendered. The result is produced by the REAL
    // AdvisoryService + REAL coverage predicates (nwsCoverage / jmaCoverage)
    // at HER Akita point — so NWS (which would throw HTTP 400) is never even
    // queried. The captured surface therefore shows the JMA 大雪警報 card and
    // NO NWS error banner / NWS card at all.
    final svc = AdvisoryService(providers: [
      CoveredProvider(provider: _ThrowingNws(), covers: nwsCoverage),
      CoveredProvider(provider: _FakeJma(), covers: jmaCoverage),
    ]);
    await svc.init();
    final result = await svc.fetchAtPoint(
      latitude: 39.7167,
      longitude: 140.0983,
    );
    // Guard the render: if gating regressed, this fails LOUDLY before capture.
    expect(result.providerErrors, isEmpty,
        reason: 'NWS must not be queried for HER Akita point (no error card)');
    expect(result.advisories.single.source, AdvisorySource.jmaJapan);

    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(440 * 2, 720 * 2);
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
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ja'), Locale('en')],
        home: Scaffold(
          backgroundColor: Colors.white,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: AdvisoryCards(
              loading: false,
              result: result,
              errorMessage: null,
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // The captured surface must NOT contain any NWS marker (label or error).
    expect(find.textContaining('NWS'), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../render_out/06_advisory_jp_jma_only.png'),
    );
  });

  testWidgets(
      '13 — road-surface default is UNKNOWN, not a fabricated ice hazard '
      '(路面状況不明)', (tester) async {
    await tester.pumpWidget(const SngnavApp(locale: Locale('ja')));
    await tester.pump();
    // The road-surface condition defaults to RoadSurfaceCondition.unknown (no
    // sensor wired), so the per-profile glossary renders 路面状況不明 — never a
    // synthetic ice hazard. Scroll that section into view and capture it so a
    // human can SEE the honest default (OPS-066).
    final section = find.text('Glossary (per profile)');
    await captureApp(
      tester,
      target: section,
      logical: const Size(820, 520),
      out: '../../render_out/13_condition_unknown_default.png',
    );
    // Prove the default is the honest unknown, not the old fabricated ice.
    expect(find.text('路面状況不明'), findsWidgets);
  });
}
