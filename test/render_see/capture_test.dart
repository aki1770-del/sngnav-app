/// Render-and-look capture harness (session-scope; NOT a CI assertion).
///
/// Produces fresh render PNGs of the driver-facing JA surfaces into
/// `render_out/` via golden capture so a reviewer can LOOK at them. Run with:
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

import 'dart:async';
import 'dart:io';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_see_env.dart';
import 'package:sngnav_app/akita_map.dart' show akitaStation;
import 'package:sngnav_app/her_position.dart';

import '../support/consent_composition.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/advisory_service.dart';
import 'package:sngnav_app/services/provider_coverage.dart';
import 'package:sngnav_app/widgets/advisory_cards.dart';

import '../support/assessed_fix.dart';
import '../support/fake_alert_actuators.dart';
import '../support/developer_page.dart';

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
    // 2026-10-06: this phone CAN post her a notification. The card's drive
    // words now follow what the app knows about posting
    // (test/widgets/drive_promise_follows_can_post_test.dart); these captures
    // record the card under the can-post promise, the words they were taken
    // with. Unmocked, the frame is taken before the notification read
    // answers, so the app has no reading and draws the not-known-yet words
    // (measured 2026-10-07; given real async time, an unmocked read answers
    // "cannot post").
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('sngnav/notification_permission'),
      (call) async => call.method == 'read'
          ? <String, Object>{
              'granted': true,
              'enabled': true,
              'needsRuntimeRequest': false,
            }
          : true,
    );
    TestWidgetsFlutterBinding.ensureInitialized();
    // Register the font under BOTH the app's default family (Roboto) and an
    // explicit family, so (a) the real SngnavApp tree renders CJK+Latin and
    // (b) the harness-built advisory surface can request it directly.
    final cjkLoaded = await loadCjkFamily('Roboto', [ipa, droid]);
    if (!cjkLoaded || !goldenPixelsComparableHere()) {
      installNoopGoldenComparator();
    }
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

  /// Starts sharing her position the way she does: the consent she gave, then
  /// 現在地を共有 on her card. The fixes come from the test's stream, standing
  /// in for the platform GPS stream through the seam the app keeps for it
  /// ([SngnavApp.positionSource]).
  ///
  /// 02 and 03 are frames of her drive screen, so they are reached the way a
  /// release build reaches it. Until 2026-10-02 they were reached from the
  /// development page (the Akita mock, the blackout simulator). A release
  /// build never offers that page (`_developerPageOffered` requires
  /// `!kReleaseMode`), and its entry stood in her app bar in both stored
  /// images, drawn as an empty box.
  Future<void> shareHerPosition(WidgetTester tester) async {
    await tester.ensureVisible(find.text('現在地を共有'));
    await tester.pump();
    await tester.tap(find.text('現在地を共有'));
    await tester.pump();
  }

  /// A fix where the Akita mock put her: the station, ±35 m.
  PositionAvailable fixAtAkita(DateTime at) => PositionAvailable(
        latitude: akitaStation.latitude,
        longitude: akitaStation.longitude,
        accuracyMeters: 35,
        timestamp: at,
      );

  // The subject of this frame is ASSERTED, not taken by position. Its finder
  // takes the nearest Column above the disclosure. When the disclosure was
  // moved to a card of its own (2026-09-23, withdrawn 2026-10-07) that Column
  // held the paragraphs alone, and the finder rebound to it and kept capturing:
  // nothing failed for the reason this capture exists, and a golden sweep would
  // have recut it under a name that had become false. The page's declaration
  // (test/support/consent_composition.dart) now decides what this frame must
  // hold, and the test fails instead of photographing a different picture.
  testWidgets('01 — JA consent gate (deny-by-default)', (tester) async {
    await tester.pumpWidget(const SngnavApp(locale: Locale('ja')));
    await tester.pump();
    // The consent gate = the Column that holds the disclosure paragraph
    // (buttons row + disclosure). Nothing tapped: deny-by-default.
    // It holds the control exactly when the page is declared `together`; if
    // the two disagree, this frame became a different picture and the test
    // says so instead of photographing it.
    final gate = find
        .ancestor(
          of: find.byKey(const Key('location-disclosure')),
          matching: find.byType(Column),
        )
        .first;
    final controlInFrame = find
        .descendant(
          of: gate,
          matching: find.byKey(const Key('share-location-button')),
        )
        .evaluate()
        .isNotEmpty;
    expect(
      controlInFrame,
      kDeclaredConsentComposition == ConsentComposition.together,
      reason: 'this capture\'s subject no longer matches its name.\n'
          '  declared: ${kDeclaredConsentComposition.name}\n'
          '  the share control is ${controlInFrame ? '' : 'NOT '}inside the '
          'Column this capture photographs.\n'
          'Rename this test and recut its golden together, or re-target it so '
          'it holds the control and the words at once. Recutting the pixels '
          'while this sentence still says something else produces a green '
          'suite over a false description.',
    );
    await captureApp(
      tester,
      target: gate,
      logical: const Size(800, 320),
      out: '../../render_out/01_ja_consent_gate.png',
    );
  });

  testWidgets('02 — JA drive HUD, lowest neutral rung (特段の注意なし)', (tester) async {
    final fake = FakeAlertActuators();
    // The lowest rung comes from a measured clear reading (2026-09-16): a demo
    // value may add caution and never clear it, so the station reads 1500 m.
    final at = DateTime.now();
    final positions = StreamController<PositionFix>.broadcast();
    addTearDown(positions.close);
    await tester.pumpWidget(
      SngnavApp(
          actuators: fake,
          locale: const Locale('ja'),
          clock: () => at,
          jmaFetch: () async => JmaSuccess(JmaObservation(
                stationId: '32402',
                stationName: '秋田',
                temperatureCelsius: 5,
                humidityPercent: 50,
                windMetersPerSecond: 2,
                snowDepthCm: null,
                precipitation10mMm: 0,
                visibilityMeters: 1500,
                observedAtJstKey: '20260115060000',
                fetchedAt: at,
              )),
          locationConsent: true,
          positionSource: () => positions.stream,
          developerPageEntry: false),
    );
    await tester.pump();
    await tester.pump();

    // She shares her position and the GPS gives a fix.
    await shareHerPosition(tester);
    // A share's first fix is held (decided 2026-10-05): the same place one
    // second earlier comes first, and the fix after it is judged and trusted.
    positions.add(justBefore(fixAtAkita(at)));
    await tester.pump();
    positions.add(fixAtAkita(at));
    await tester.pump();
    await tester.pump();

    // The honest default is UNKNOWN (未計測 → heightened); the only truthful way
    // to reach the lowest, choice-neutral rung (特段の注意なし) is an actual clear
    // reading, which the station above measured.

    final banner = find.byKey(const Key('drive-hud-caution-banner'));
    // Confirm we are in the lowest, choice-neutral rung before capturing —
    // and that the claim is SCOPED to what this harness actually measured.
    //
    // Nothing here feeds an advisory result, so at capture time the advisory
    // lookup cannot prove completeness. (Until 2026-09-16 no JMA observation
    // was fed either, and a demo value stood in for the clear reading; the
    // station's reading is fed now, so only the advisory axis is unconfirmed.) The bare 「特段の注意なし」 is
    // therefore a claim about a picture we did not look at, and it is
    // correctly unreachable in this state. This expectation used to pin the
    // unscoped string — the same fabricated-clear shape B04-2 removed from the
    // advisory CARD, still standing on the GLANCE.
    //
    // The rung is unchanged: an outage is an unknown, not a hazard, and
    // raising it would cry wolf (decided 2026-07-23). Only the reassurance is
    // withheld.
    expect(
      find.descendant(of: banner, matching: find.text('特段の注意なし')),
      findsNothing,
      reason: 'the unscoped global all-clear must not survive an unmeasured '
          'advisory axis and an unread weather feed',
    );
    expect(
      find.descendant(
          of: banner, matching: find.text('特段の注意なし（警報・注意報は未確認）')),
      findsOneWidget,
      reason: 'the honest STATE is kept; the CLAIM is scoped to it',
    );
    // Her app bar, as a release build draws it: no developer entry.
    expect(find.byKey(kDeveloperPageEntryKey), findsNothing);
    await captureApp(
      tester,
      target: banner,
      logical: const Size(800, 260),
      out: '../../render_out/02_drive_hud_continue.png',
    );
  });

  testWidgets('03 — JA drive HUD, RISEN to STOP (停車の検討)', (tester) async {
    final fake = FakeAlertActuators();
    final t0 = DateTime.now();
    var now = t0;
    final positions = StreamController<PositionFix>.broadcast();
    addTearDown(positions.close);
    await tester.pumpWidget(
      SngnavApp(
          actuators: fake,
          locale: const Locale('ja'),
          clock: () => now,
          locationConsent: true,
          positionSource: () => positions.stream,
          developerPageEntry: false),
    );
    await tester.pump();

    // She shares her position and the GPS gives one fix.
    await shareHerPosition(tester);
    // A share's first fix is held (decided 2026-10-05): the same place one
    // second earlier comes first, and the fix after it is judged and trusted.
    positions.add(justBefore(fixAtAkita(t0)));
    await tester.pump();
    positions.add(fixAtAkita(t0));
    await tester.pump();
    await tester.pump();

    // Then the GPS goes silent for 180 s, past the 120 s honesty horizon. The
    // blackout watchdog's next tick reads the clock, her position degrades to
    // `lost`, and the caution rung RISES to 停車の検討.
    now = t0.add(const Duration(seconds: 180));
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();

    final banner = find.byKey(const Key('drive-hud-caution-banner'));
    expect(
      find.descendant(of: banner, matching: find.text('停車の検討')),
      findsOneWidget,
    );
    // Her app bar, as a release build draws it: no developer entry.
    expect(find.byKey(kDeveloperPageEntryKey), findsNothing);
    await captureApp(
      tester,
      target: banner,
      logical: const Size(800, 300),
      out: '../../render_out/03_drive_hud_stop.png',
    );
  });

  testWidgets('04 — JA advisory ordering (気象庁 leads, NWS de-emphasized)',
      (tester) async {
    // A JMA (Japanese) advisory + an English NWS advisory. On the ja surface
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
        // She never sees the debug ribbon: a release build does not draw it.
        debugShowCheckedModeBanner: false,
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
    // No debug ribbon over the top-end corner of the stored render: a
    // release build never draws it, so the golden must not either.
    expect(find.byType(CheckedModeBanner), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../render_out/04_advisory_ja_ordering.png'),
    );
  });

  testWidgets('06 — JA advisory, Akita point → JMA only, NO NWS error',
      (tester) async {
    // Region-gate proof, rendered. The result is produced by the REAL
    // AdvisoryService + REAL coverage predicates (nwsCoverage / jmaCoverage)
    // at the Akita point — so NWS (which would throw HTTP 400) is never even
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
        reason: 'NWS must not be queried for the Akita point (no error card)');
    expect(result.advisories.single.source, AdvisorySource.jmaJapan);

    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(440 * 2, 720 * 2);
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
    // No debug ribbon over the top-end corner of the stored render.
    expect(find.byType(CheckedModeBanner), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../render_out/06_advisory_jp_jma_only.png'),
    );
  });

  testWidgets(
      '13 — road-surface default is UNKNOWN, not a fabricated ice hazard '
      '(路面状況不明)', (tester) async {
    // The road-condition names card is on the development page (2026-09-15);
    // this capture is of that page now. A release build never offers that
    // page, so this golden documents a developer surface, not her screen.
    await tester.pumpWidget(
        const SngnavApp(locale: Locale('ja'), developerPageEntry: true));
    await tester.pump();
    await openDeveloperPage(tester);
    // The road-surface condition defaults to RoadSurfaceCondition.unknown (no
    // sensor wired), so the per-profile glossary renders 路面状況不明 — never a
    // synthetic ice hazard. Scroll that section into view and capture it so a
    // human can SEE the honest default.
    final section =
        find.text(const AppL10n(Locale('ja')).roadConditionNamesSectionTitle);
    await captureApp(
      tester,
      target: section,
      logical: const Size(820, 520),
      out: '../../render_out/13_condition_unknown_default.png',
    );
    // Prove the default is the honest unknown, not the old fabricated ice.
    expect(find.text('路面状況不明'), findsWidgets);
  });

  testWidgets(
      '17 — JA consent disclosure names the FULL JMA egress + stationary '
      'cadence (disclosure fix)', (tester) async {
    // The card the driver reads BEFORE sharing her location must match the measured
    // wire: three region/prefecture-keyed JMA endpoints (prefecture warning +
    // regional AMeDAS + prefecture forecast — precise coords NOT sent),
    // fetched about once per ~1 km AND about every 10 minutes while open,
    // including stopped. The old copy said "都道府県コードのみを（走行約1kmごとに）"
    // — false-exhaustive + cadence-incomplete. Capture the disclosure so a
    // human can SEE the corrected honest text.
    await tester.pumpWidget(const SngnavApp(locale: Locale('ja')));
    await tester.pump();
    final disclosure = find.byKey(const Key('location-disclosure'));
    // Render guard: the corrected terms are actually on the surface the driver reads.
    final rendered = tester.widget<Text>(disclosure).data ?? '';
    expect(rendered, contains('アメダス'));
    expect(rendered, contains('予報'));
    expect(rendered, contains('10分'));
    expect(rendered, contains('停車'));
    expect(rendered, isNot(contains('都道府県コードのみ')));
    await captureApp(
      tester,
      target: disclosure,
      logical: const Size(800, 460),
      out: '../../render_out/17_ja_consent_disclosure_full_jma_egress.png',
    );
  });
}
