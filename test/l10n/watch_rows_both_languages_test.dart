/// The two watch rows on the Akita card, in both languages, for every verdict.
///
/// Why, written before the act (2026-09-19). These rows were drawn in Japanese
/// on every page. A driver reading English saw 該当なし ("none") and 判定不能
/// ("cannot judge") as two unreadable strings of the same shape, and those two
/// are the distinction the rows exist to make: a road nobody measured must
/// never read as a road with nothing on it. One state of the page shows one
/// verdict, so this test goes through every verdict instead.
///
/// For every verdict of each watch: the Japanese is exactly what the page drew
/// before (a driver who reads Japanese sees no change); the English has no
/// Japanese in it; and the English keeps the Japanese's distinctions, so that
/// ⚠ stays ⚠, 判定不能 is "cannot judge", 該当なし is "None", 判定していません is
/// "not judged", and two different Japanese verdicts are never one English
/// one.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/invisible_ice_watch.dart'
    show InvisibleIceWatchResult;
import 'package:sngnav_app/services/turmoil_watch.dart';

const _ja = AppL10n(Locale('ja'));
const _en = AppL10n(Locale('en'));

final _cjk = RegExp(
  '[\u3000-\u303F\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\uFF00-\uFFEF]',
);

/// The black-ice watch's Japanese as the page drew it before 2026-09-19.
const _iceJa = <InvisibleIceWatchResult, String>{
  InvisibleIceWatchResult.watch: '⚠ ブラックアイスバーンのおそれ（放射冷却の窓）',
  InvisibleIceWatchResult.clear: '該当なし',
  InvisibleIceWatchResult.outOfScope: '本ウォッチの対象外（この条件は判定していません）',
  InvisibleIceWatchResult.outsideModelEnvelope: '判定範囲外（この気象条件は判定していません）',
  InvisibleIceWatchResult.subZeroFrozen: '⚠ 路面凍結のおそれ（気温0°C以下）',
  InvisibleIceWatchResult.unknown: '判定不能（気温・湿度・降水の観測値が不足）',
};

/// The turmoil watch's Japanese as the page drew it before 2026-09-19, for
/// each (rain, wind) pair of channel verdicts.
const _turmoilJa = <(TurmoilChannel, TurmoilChannel), String>{
  (TurmoilChannel.caution, TurmoilChannel.caution): '⚠ 強い雨・強めの風を観測中',
  (TurmoilChannel.caution, TurmoilChannel.clear): '⚠ 強い雨を観測中',
  (TurmoilChannel.caution, TurmoilChannel.unknown): '⚠ 強い雨を観測中（風は判定不能）',
  (TurmoilChannel.clear, TurmoilChannel.caution): '⚠ 強めの風を観測中',
  (TurmoilChannel.unknown, TurmoilChannel.caution): '⚠ 強めの風を観測中（降水は判定不能）',
  (TurmoilChannel.clear, TurmoilChannel.clear): '該当なし',
  (TurmoilChannel.unknown, TurmoilChannel.clear): '該当なし（降水は判定不能）',
  (TurmoilChannel.clear, TurmoilChannel.unknown): '該当なし（風は判定不能）',
  (TurmoilChannel.unknown, TurmoilChannel.unknown): '判定不能（降水・風の観測値が不足）',
};

const _turmoilNothingJudgedJa = '判定不能（降水・風の観測値が不足）';

/// What must carry over from a Japanese verdict to its English one.
List<String> _distinctionsLost(String ja, String en) => [
      if (_cjk.hasMatch(en)) 'the English has Japanese in it',
      if (ja.startsWith('⚠') != en.startsWith('⚠'))
        'the warning sign is on one and not the other',
      if (ja.contains('判定不能') !=
          en.toLowerCase().contains('cannot judge'))
        '判定不能 and "cannot judge" do not go together',
      if (ja.startsWith('該当なし') != en.startsWith('None'))
        '該当なし and "None" do not go together',
      if (ja.contains('判定していません') != en.contains('not judged'))
        '判定していません and "not judged" do not go together',
    ];

void _holdTheSpace(String what, Map<Object?, String> ja, Map<Object?, String> en) {
  final problems = <String>[];
  for (final k in ja.keys) {
    for (final p in _distinctionsLost(ja[k]!, en[k]!)) {
      problems.add('$what $k: 「${ja[k]}」 / "${en[k]}": $p');
    }
  }
  // Two different Japanese verdicts are never one English verdict.
  final byEn = <String, Set<String>>{};
  for (final k in ja.keys) {
    byEn.putIfAbsent(en[k]!, () => {}).add(ja[k]!);
  }
  for (final e in byEn.entries) {
    if (e.value.length > 1) {
      problems.add('$what: "${e.key}" stands for ${e.value.join(' and ')}');
    }
  }
  expect(problems, isEmpty, reason: problems.join('\n'));
}

void main() {
  test('the labels: Japanese unchanged, English with no Japanese in it', () {
    expect(_ja.roadIceWatchLabel, '路面凍結ウォッチ');
    expect(_ja.turmoilWatchLabel, '荒天ウォッチ');
    expect(_ja.observationPrecipitation10mLabel, '降水量（10分間）');
    for (final en in [
      _en.roadIceWatchLabel,
      _en.turmoilWatchLabel,
      _en.observationPrecipitation10mLabel,
    ]) {
      expect(_cjk.hasMatch(en), isFalse, reason: '"$en" has Japanese in it');
    }
  });

  test('black-ice watch: every verdict, both languages', () {
    expect(_iceJa.keys.toSet(), InvisibleIceWatchResult.values.toSet(),
        reason: 'a verdict with no Japanese pinned here is a verdict nobody '
            'checked in either language');
    final ja = <Object?, String>{
      for (final r in InvisibleIceWatchResult.values) r: _ja.roadIceWatchVerdict(r),
      null: _ja.roadIceWatchVerdict(null),
    };
    final en = <Object?, String>{
      for (final r in InvisibleIceWatchResult.values) r: _en.roadIceWatchVerdict(r),
      null: _en.roadIceWatchVerdict(null),
    };
    for (final r in InvisibleIceWatchResult.values) {
      expect(ja[r], _iceJa[r], reason: 'the Japanese for $r moved');
    }
    expect(ja[null], _iceJa[InvisibleIceWatchResult.unknown],
        reason: 'no verdict yet is drawn as unknown');
    expect(en[null], en[InvisibleIceWatchResult.unknown],
        reason: 'no verdict yet is drawn as unknown in English too');
    // null and unknown are one verdict by design; hold the rest pairwise.
    _holdTheSpace('black-ice', {...ja}..remove(null), {...en}..remove(null));
  });

  test('turmoil watch: every pair of channel verdicts, and nothing judged, '
      'both languages', () {
    TurmoilWatchState state(TurmoilChannel rain, TurmoilChannel wind) =>
        TurmoilWatchState(
          rain: rain,
          wind: wind,
          precipitation10mMm: null,
          windMetersPerSecond: null,
        );
    final ja = <Object?, String>{};
    final en = <Object?, String>{};
    for (final rain in TurmoilChannel.values) {
      for (final wind in TurmoilChannel.values) {
        final s = state(rain, wind);
        ja[(rain, wind)] = _ja.turmoilWatchVerdict(s);
        en[(rain, wind)] = _en.turmoilWatchVerdict(s);
        expect(ja[(rain, wind)], _turmoilJa[(rain, wind)],
            reason: 'the Japanese for rain $rain, wind $wind moved');
        expect(turmoilRowText(s), _turmoilJa[(rain, wind)],
            reason: 'turmoilRowText without a language is still the Japanese');
      }
    }
    expect(ja.length, _turmoilJa.length);
    expect(_ja.turmoilWatchVerdict(null), _turmoilNothingJudgedJa);
    expect(_en.turmoilWatchVerdict(null),
        en[(TurmoilChannel.unknown, TurmoilChannel.unknown)],
        reason: 'nothing judged reads as both channels unknown in English '
            'too');
    _holdTheSpace('turmoil', ja, en);
  });
}
