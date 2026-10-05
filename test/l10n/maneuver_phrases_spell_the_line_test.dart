/// The phrase lists the next-turn banner draws with are the pinned ones, and
/// joined they spell, byte for byte, the line she hears and reads.
///
/// WHY. The banner draws each Japanese line so that it breaks only between two
/// phrases (lib/widgets/keep_together.dart). The voice and the screen reader
/// get the plain line, built as it always was; the lists are a second source
/// beside it, so this file holds them to it, for every maneuver type the
/// localizer names, read as given and with a check, icy or not. A list that
/// stopped spelling its line would be drawn plain, never as other words;
/// this file is what notices.
///
/// R4-3 is here too: a line drawn through the app's own span, in the app's
/// own theme, paints exactly the pixels of the plain line. Its control is the
/// same joiners written into a plain string, which the theme's letter spacing
/// (0.25 after every character, joiners included) makes wider: the reason
/// each joiner is a span of its own.
library;

import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/app_theme.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/drive_hud_localizer.dart';
import 'package:sngnav_app/widgets/keep_together.dart'
    show keepPhrasesTogether, plainOf, kWordJoiner;

import '../render_see/render_see_env.dart' show loadCjkFamily;
import '../support/maneuver_phrase_spec.dart';

const _text = DriveHudLocalizer();
const _ja = AppL10n(Locale('ja'));
const _en = AppL10n(Locale('en'));

void main() {
  setUpAll(() async {
    // A Japanese face under 'Roboto', the family the app's theme draws in;
    // without one R4-3 would compare boxes. The file refuses to run.
    final ok = await loadCjkFamily('Roboto', [
      '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf',
      '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf',
    ]);
    if (!ok) {
      throw StateError('no Japanese face on this host: R4-3 would compare '
          'boxes, not her words. Not a pass.');
    }
  });

  test(
      'her line: for every maneuver type, as given and with a check, icy or '
      'not, the list spells what the voice says and is the pinned one', () {
    var n = 0;
    for (final type in kManeuverTypes) {
      for (final hedged in [false, true]) {
        for (final icy in [false, true]) {
          var spoken = hedged
              ? _text.hedgedManeuverInstruction(type, 'ja')
              : _text.maneuverInstruction(type, 'ja');
          if (icy) spoken = _text.icyManeuverCoupling(spoken, 'ja');
          final list =
              _text.maneuverLinePhrases(type, 'ja', hedged: hedged, icy: icy);
          final spec = herLinePhrasesSpec(type, hedged: hedged, icy: icy);
          final where = '$type, hedged $hedged, icy $icy';
          expect(list, spec, reason: '$where: not the pinned phrases');
          expect(list!.join(), spoken,
              reason: '$where: the phrases do not spell the spoken line');
          expect(spoken.contains(kWordJoiner), isFalse,
              reason: '$where: a word joiner reached the spoken line');
          expect(
              _text.maneuverLinePhrases(type, 'en', hedged: hedged, icy: icy),
              isNull,
              reason: '$where: English breaks at its spaces; no list');
          n++;
        }
      }
    }
    expect(n, 76);
  });

  test(
      "the panel's own words: each list spells its line and is the pinned "
      'one; none in English', () {
    final lines = [
      _ja.maneuverTierSpeak,
      _ja.maneuverTierHedge,
      _ja.maneuverTierSuppressed,
      _ja.maneuverGuidancePaused,
      _ja.maneuverIcyMark,
      _ja.maneuverTestRoadConditionInForce,
      _ja.maneuverMeasuredRoadIceInForce,
      // Under the banner (2026-10-04).
      _ja.maneuverNarrateButton,
      _ja.maneuverNarrateButtonOnHold,
      _ja.maneuverNarrationSent,
      _ja.maneuverNarrationNotSpoken,
      for (final (speech, haptic) in [(true, false), (false, true), (true, true)])
        _ja.maneuverNarrationDeliveryUnverified(speech: speech, haptic: haptic),
    ];
    expect(lines.toSet(), kPanelPhrasesSpec.keys.toSet(),
        reason: 'the pinned lines are not the lines the panel draws');
    for (final line in lines) {
      expect(_ja.maneuverPanelPhrases(line), kPanelPhrasesSpec[line],
          reason: '"$line": not the pinned phrases');
      expect(_ja.maneuverPanelPhrases(line)!.join(), line);
    }
    for (final line in [
      _en.maneuverTierSpeak,
      _en.maneuverTierHedge,
      _en.maneuverTierSuppressed,
      _en.maneuverGuidancePaused,
      _en.maneuverIcyMark,
      _en.maneuverTestRoadConditionInForce,
      _en.maneuverMeasuredRoadIceInForce,
      _en.maneuverNarrateButton,
      _en.maneuverNarrateButtonOnHold,
      _en.maneuverNarrationSent,
      _en.maneuverNarrationNotSpoken,
      for (final (speech, haptic) in [(true, false), (false, true), (true, true)])
        _en.maneuverNarrationDeliveryUnverified(speech: speech, haptic: haptic),
    ]) {
      expect(_en.maneuverPanelPhrases(line), isNull, reason: line);
    }
  });

  test('a list that does not spell its line draws the line plain', () {
    const line = 'この先、右折 です。';
    expect(keepPhrasesTogether(line, null), isNull);
    expect(keepPhrasesTogether(line, ['この先、', '左折 ', 'です。']), isNull);
    expect(keepPhrasesTogether(line, ['この先、', '右折 ']), isNull);
    final drawn = keepPhrasesTogether(line, ['この先、', '右折 ', 'です。'])!;
    expect(drawn.toPlainText(), joinedSpec(['この先、', '右折 ', 'です。']));
    expect(plainOf(drawn.toPlainText()), line);
  });

  testWidgets(
      'R4-3 a line drawn through the app\'s span paints the pixels of the '
      'plain line, in the app\'s theme', (tester) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(4000, 400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const shot = Key('phrase-line-shot');
    const style = TextStyle(fontSize: 15, color: Color(0xFF1B5E20));
    Future<(ByteData, int, int)> paint(Widget text) async {
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: sngnavTheme(),
        home: Scaffold(
          body: UnconstrainedBox(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(key: shot, child: text),
          ),
        ),
      ));
      await tester.pump();
      final r = await tester.runAsync(() async {
        final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(shot));
        final img = await b.toImage(pixelRatio: 2.75);
        final d = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        final out = (d!, img.width, img.height);
        img.dispose();
        return out;
      });
      return r!;
    }

    int diff((ByteData, int, int) a, (ByteData, int, int) b) {
      if (a.$2 != b.$2 || a.$3 != b.$3) return -1;
      var n = 0;
      for (var i = 0; i < a.$1.lengthInBytes; i++) {
        if (a.$1.getUint8(i) != b.$1.getUint8(i)) n++;
      }
      return n;
    }

    final lines = <List<String>>{
      for (final type in kManeuverTypes)
        for (final hedged in [false, true])
          for (final icy in [false, true])
            herLinePhrasesSpec(type, hedged: hedged, icy: icy),
      ...kPanelPhrasesSpec.values,
    }.toList();
    var n = 0, controlsDiffer = 0;
    for (final phrases in lines) {
      final line = phrases.join();
      final plain = await paint(Text(line, softWrap: false, style: style));
      final joined = await paint(Text.rich(keepPhrasesTogether(line, phrases)!,
          softWrap: false, style: style));
      expect(diff(plain, joined), 0,
          reason: '"$line": drawn through the span, it does not paint the '
              'plain line (${plain.$2}x${plain.$3} vs ${joined.$2}x${joined.$3})');
      // Control: the same joiners in a plain string, in the same theme.
      final control = await paint(
          Text(joinedSpec(phrases), softWrap: false, style: style));
      if (diff(plain, control) != 0) controlsDiffer++;
      n++;
    }
    // ignore: avoid_print
    print('R4-3: $n lines drawn through the span, 0 differing bytes each; '
        'control (joiners in a plain string): $controlsDiffer of $n differ');
    expect(controlsDiffer, n,
        reason: 'the control drew the plain line on some lines: if the theme '
            'no longer adds letter spacing, this control cannot fail and must '
            'be replaced by another known difference');
  });
}
