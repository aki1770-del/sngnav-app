/// The next-turn panel, pumped as the app's own widget in each state the gate
/// can return.
///
/// Until 2026-10-04 the panel was a private method in `lib/main.dart`, so the
/// next-turn goldens drew a copy of it, and the copy drifted from the app
/// twice without a test going red. The panel is now `ManeuverNarrationPanel`
/// and these tests pump it directly. They run on CI, where the goldens are
/// not compared, so what they pin is checked there too.
///
/// What they pin is what she depends on in each state: the state's words in
/// the app's language, her line (and never the routing engine's English),
/// the position row only when the position is this drive's, where an icy
/// mark came from, a narrate button that works, what the last narration did,
/// and banner words at 4.5:1 or more against their fill. They do not pin
/// colours or layout, so the panel can change its look and stay green while
/// it keeps those.
///
/// The 4.5:1 floor is read from the PAINTED raster, not from the widgets'
/// declared colours: a style-reading check passes a word an `Opacity` has
/// faded, and that is how the glance-paint register
/// (test/widgets/glance_paint_coverage_test.dart) was founded. It is a floor,
/// not legibility: whether she can tell the three states apart at a glance,
/// and at her width, is not measured here, and this file does not certify the
/// panel legible.
library;

import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:localization_fallback/localization_fallback.dart'
    show LocalizationMode;
import 'package:routing_engine/routing_engine.dart' show RouteManeuver;
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/drive_hud_localizer.dart';
import 'package:sngnav_app/services/maneuver_narration.dart';
import 'package:sngnav_app/widgets/maneuver_narration_panel.dart';

import '../support/plain_words.dart';

const _text = DriveHudLocalizer();
const _narrator = ManeuverNarrator(text: _text);
const _ja = AppL10n(Locale('ja'));
const _en = AppL10n(Locale('en'));

/// Its English instruction must never reach her surface.
const _rightTurn = RouteManeuver(
  index: 1,
  instruction: 'Right onto Main St',
  type: 'right',
  lengthKm: 0.4,
  timeSeconds: 30,
  position: LatLng(39.72, 140.10),
);

ManeuverNarration _decide(
  LocalizationMode mode, {
  bool icyTurn = false,
  String localeTag = 'ja',
}) => _narrator.decide(
  maneuver: _rightTurn,
  mode: mode,
  icyTurn: icyTurn,
  localeTag: localeTag,
);

Future<void> _pump(
  WidgetTester tester, {
  required ManeuverNarration preview,
  LocalizationMode? mode,
  bool isMockPosition = false,
  IcyTurnSource icySource = IcyTurnSource.none,
  ManeuverNarration? lastNarration,
  bool speechUnverified = false,
  bool hapticUnverified = false,
  Locale locale = const Locale('ja'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: RepaintBoundary(
            key: _shot,
            child: ManeuverNarrationPanel(
              preview: preview,
              mode: mode,
              isMockPosition: isMockPosition,
              icySource: icySource,
              onNarrate: () {},
              lastNarration: lastNarration,
              speechUnverified: speechUnverified,
              hapticUnverified: hapticUnverified,
            ),
          ),
        ),
      ),
    ),
  );
}

const _bannerKey = Key('maneuver-narration-banner');
const _tierKey = Key('maneuver-narration-tier');

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

const _shot = Key('maneuver-panel-shot');

/// The panel's raster, read back at pixelRatio 1.0. `toImage` awaited inside
/// the fake-async zone never completes, so it runs in `runAsync` and the
/// bytes are carried out.
Future<({ByteData rgba, int width})> _raster(WidgetTester tester) async {
  final r = await tester.runAsync(() async {
    final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
    final img = await b.toImage(pixelRatio: 1.0);
    final d = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = img.width;
    img.dispose();
    return (rgba: d!, width: w);
  });
  return r!;
}

/// Every word in the banner, as painted, is at 4.5:1 or more against the
/// banner's fill as painted. The fill is read just inside the banner's left
/// edge, inside its padding; each word's ink is its pixel that contrasts most
/// with that fill.
Future<void> _expectBannerInkOnFill(WidgetTester tester) async {
  final r = await _raster(tester);
  Color px(int x, int y) {
    final i = (y * r.width + x) * 4;
    return Color.fromARGB(
      r.rgba.getUint8(i + 3),
      r.rgba.getUint8(i),
      r.rgba.getUint8(i + 1),
      r.rgba.getUint8(i + 2),
    );
  }

  final origin = tester.getTopLeft(find.byKey(_shot));
  final banner = tester.getRect(find.byKey(_bannerKey)).shift(-origin);
  final fill = px((banner.left + 4).round(), banner.center.dy.round());

  final words = find.descendant(
    of: find.byKey(_bannerKey),
    matching: find.byType(RichText),
  );
  expect(words, findsWidgets);
  for (final e in words.evaluate()) {
    final box = e.renderObject! as RenderBox;
    final rect = (box.localToGlobal(Offset.zero) - origin) & box.size;
    var best = 1.0;
    for (var y = rect.top.floor(); y < rect.bottom.ceil(); y++) {
      for (var x = rect.left.floor(); x < rect.right.ceil(); x++) {
        final c = _contrast(px(x, y), fill);
        if (c > best) best = c;
      }
    }
    final text = (e.widget as RichText).text.toPlainText();
    expect(
      best,
      greaterThanOrEqualTo(4.5),
      reason:
          '"$text" paints at ${best.toStringAsFixed(2)}:1 at most against '
          'its fill; she must be able to read it',
    );
  }
}

String? _tier(WidgetTester tester) =>
    wordsOf(tester.widget<Text>(find.byKey(_tierKey)));

void main() {
  testWidgets('speak: the state and her turn line, legible', (tester) async {
    final preview = _decide(LocalizationMode.gpsTrusted);
    expect(preview.confidence, NarrationConfidence.speak);
    await _pump(tester, preview: preview, mode: LocalizationMode.gpsTrusted);

    expect(_tier(tester), _ja.maneuverTierSpeak);
    expect(findWords(preview.text), findsOneWidget);
    expect(find.text('Right onto Main St'), findsNothing);
    await _expectBannerInkOnFill(tester);
  });

  testWidgets('hedge: the state and her softened line, legible', (
    tester,
  ) async {
    final preview = _decide(LocalizationMode.gpsSuspect);
    expect(preview.confidence, NarrationConfidence.hedge);
    await _pump(tester, preview: preview, mode: LocalizationMode.gpsSuspect);

    expect(_tier(tester), _ja.maneuverTierHedge);
    expect(findWords(preview.text), findsOneWidget);
    expect(find.text('Right onto Main St'), findsNothing);
    await _expectBannerInkOnFill(tester);
  });

  testWidgets('suppressed: no turn, the paused line instead, legible', (
    tester,
  ) async {
    final preview = _decide(LocalizationMode.lost, icyTurn: true);
    expect(preview.confidence, NarrationConfidence.suppressed);
    await _pump(
      tester,
      preview: preview,
      mode: LocalizationMode.lost,
      icySource: IcyTurnSource.measured,
    );

    expect(_tier(tester), _ja.maneuverTierSuppressed);
    expect(findWords(_ja.maneuverGuidancePaused), findsOneWidget);
    expect(find.text('Right onto Main St'), findsNothing);
    // No icy mark on a turn that is not spoken.
    expect(findWords(_ja.maneuverIcyMark), findsNothing);
    expect(find.byKey(const Key('maneuver-measured-road-ice')), findsNothing);
    await _expectBannerInkOnFill(tester);
  });

  testWidgets('the words follow the app\'s language', (tester) async {
    final preview = _decide(LocalizationMode.gpsSuspect, localeTag: 'en');
    await _pump(
      tester,
      preview: preview,
      mode: LocalizationMode.gpsSuspect,
      locale: const Locale('en'),
    );

    expect(_tier(tester), _en.maneuverTierHedge);
    expect(find.text('${_en.driveHudPositionTrustLabel}:'), findsOneWidget);
    expect(
      find.text(_text.modeLabel(LocalizationMode.gpsSuspect, 'en')),
      findsOneWidget,
    );
  });

  testWidgets('the position row is drawn only for this drive\'s position, '
      'and says when it is a test position', (tester) async {
    final preview = _decide(LocalizationMode.gpsTrusted);
    final label = '${_ja.driveHudPositionTrustLabel}:';

    await _pump(tester, preview: preview, mode: null);
    expect(find.text(label), findsNothing);

    await _pump(tester, preview: preview, mode: LocalizationMode.gpsTrusted);
    expect(find.text(label), findsOneWidget);
    expect(
      find.text(_text.modeLabel(LocalizationMode.gpsTrusted, 'ja')),
      findsOneWidget,
    );

    await _pump(
      tester,
      preview: preview,
      mode: LocalizationMode.gpsTrusted,
      isMockPosition: true,
    );
    expect(
      find.text(
        _text.modeLabel(LocalizationMode.gpsTrusted, 'ja', isMock: true),
      ),
      findsOneWidget,
    );
    expect(
      find.text(_text.modeLabel(LocalizationMode.gpsTrusted, 'ja')),
      findsNothing,
    );
  });

  testWidgets('an icy mark says where it came from', (tester) async {
    final preview = _decide(LocalizationMode.gpsTrusted, icyTurn: true);
    expect(preview.icyCoupled, isTrue);

    await _pump(
      tester,
      preview: preview,
      mode: LocalizationMode.gpsTrusted,
      icySource: IcyTurnSource.measured,
    );
    expect(findWords(_ja.maneuverIcyMark), findsOneWidget);
    expect(find.byKey(const Key('maneuver-measured-road-ice')), findsOneWidget);
    expect(find.byKey(const Key('maneuver-test-road-condition')), findsNothing);
    await _expectBannerInkOnFill(tester);

    await _pump(
      tester,
      preview: preview,
      mode: LocalizationMode.gpsTrusted,
      icySource: IcyTurnSource.testValue,
    );
    expect(find.byKey(const Key('maneuver-measured-road-ice')), findsNothing);
    expect(
      find.byKey(const Key('maneuver-test-road-condition')),
      findsOneWidget,
    );
  });

  testWidgets('the narrate button is there and narrates', (tester) async {
    var narrated = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
          body: ManeuverNarrationPanel(
            preview: _decide(LocalizationMode.gpsTrusted),
            mode: LocalizationMode.gpsTrusted,
            isMockPosition: false,
            icySource: IcyTurnSource.none,
            onNarrate: () => narrated++,
            lastNarration: null,
            speechUnverified: false,
            hapticUnverified: false,
          ),
        ),
      ),
    );
    final button = find.byKey(const Key('maneuver-narrate-button'));
    expect(button, findsOneWidget);
    expect(findWords(_ja.maneuverNarrateButton), findsOneWidget);
    await tester.tap(button);
    expect(narrated, 1);
    expect(find.byKey(const Key('maneuver-narration-result')), findsNothing);
  });

  testWidgets('what the last narration did: sent, unverified, or not spoken', (
    tester,
  ) async {
    final spoken = _decide(LocalizationMode.gpsTrusted);
    expect(spoken.shouldAnnounce, isTrue);

    await _pump(
      tester,
      preview: spoken,
      mode: LocalizationMode.gpsTrusted,
      lastNarration: spoken,
    );
    expect(findWords(_ja.maneuverNarrationSent), findsOneWidget);
    expect(
      find.byKey(const Key('maneuver-narration-delivery-unverified')),
      findsNothing,
    );

    await _pump(
      tester,
      preview: spoken,
      mode: LocalizationMode.gpsTrusted,
      lastNarration: spoken,
      speechUnverified: true,
    );
    expect(
      findWords(
        _ja.maneuverNarrationDeliveryUnverified(speech: true, haptic: false),
      ),
      findsOneWidget,
    );

    final silent = _decide(LocalizationMode.lost);
    expect(silent.shouldAnnounce, isFalse);
    await _pump(
      tester,
      preview: silent,
      mode: LocalizationMode.lost,
      lastNarration: silent,
      speechUnverified: true,
    );
    expect(findWords(_ja.maneuverNarrationNotSpoken), findsOneWidget);
    // Nothing was sent, so there is no delivery to call unverified.
    expect(
      find.byKey(const Key('maneuver-narration-delivery-unverified')),
      findsNothing,
    );
  });
}
