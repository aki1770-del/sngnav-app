/// The next-turn banner's words, as the app holds them, in both languages.
///
/// Why this test exists. Since 2026-09-15 the banner names its state in the
/// app's language instead of the gate's internal names. One of the three
/// states, a position that is only suspect, is reached by no position the app
/// gives the drive brain today, so no widget test draws it; its words are held
/// here beside the other two.
///
/// It also holds a property that tests which read a state from the screen
/// depend on: no state's words contain another's. A test that looks for the
/// trusted state by its words would otherwise pass on the suspect one.
///
/// The bytes are candidates for a look on a render; none is decided.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';

void main() {
  test('the three banner states, the icy mark, the control and what her press '
      'did, byte for byte', () {
    const ja = AppL10n(Locale('ja'));
    const en = AppL10n(Locale('en'));
    expect(ja.maneuverTierSpeak, 'そのまま読み上げます');
    expect(ja.maneuverTierHedge, '確認をお願いして読み上げます');
    expect(ja.maneuverTierSuppressed, '読み上げません');
    expect(ja.maneuverIcyMark, '❄ 凍結のおそれ');
    expect(ja.maneuverNarrateButton, '次の案内を読み上げる');
    expect(ja.maneuverNarrationAnnounced, '音声＋振動で知らせました。');
    expect(ja.maneuverNarrationNotSpoken, '何も読み上げていません。');
    expect(en.maneuverTierSpeak, 'Read aloud as given');
    expect(en.maneuverTierHedge, 'Read aloud with a check');
    expect(en.maneuverTierSuppressed, 'Not read aloud');
    expect(en.maneuverIcyMark, '❄ May be icy');
    expect(en.maneuverNarrateButton, 'Read the next maneuver aloud');
    expect(en.maneuverNarrationAnnounced, 'Announced on audio + haptic.');
    expect(en.maneuverNarrationNotSpoken, 'Nothing was read aloud.');
  });

  test('no banner state\'s words contain another\'s, in either language', () {
    for (final lang in const ['ja', 'en']) {
      final l = AppL10n(Locale(lang));
      final tiers = [
        l.maneuverTierSpeak,
        l.maneuverTierHedge,
        l.maneuverTierSuppressed,
      ];
      expect(tiers.toSet(), hasLength(3), reason: '$lang: three states');
      for (final a in tiers) {
        for (final b in tiers) {
          if (a == b) continue;
          expect(b.toLowerCase().contains(a.toLowerCase()), isFalse,
              reason: '$lang: 「$b」 contains 「$a」');
        }
      }
    }
  });
}
