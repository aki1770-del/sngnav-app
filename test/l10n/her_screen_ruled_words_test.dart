/// Her screen's words, as ruled for both languages on 2026-09-15: the live
/// drive card, the Akita observation card, the prefecture table, the
/// responsibility banner and the low-visibility reason. Literals, so a change
/// of words is a red, not a silent pass. Generated from the ruled table; the
/// consent body is pinned in route_consent_withdraw_test.dart.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/drive_hud_localizer.dart';
import 'package:compound_failure_advisor/compound_failure_advisor.dart' show CautionReason;

void main() {
  const ja = AppL10n(Locale('ja'));
  const en = AppL10n(Locale('en'));

  test('every ruled string, whole, in both languages', () {
    expect(ja.driveHudDescription, '現在地（GPS → 推測航法 → 現在地 不明。自信のある誤った点は出しません）を、視界と実際の地域の警報・注意報と組み合わせます。注意の段階が上がった瞬間に、音声＋振動で自動的に知らせます（手動のボタンは不要です）。', reason: 'row 2');
    expect(en.driveHudDescription, 'Combines your position (GPS → dead reckoning → position unknown; never a confident wrong dot) with visibility and the area\'s actual warnings and advisories. The moment the caution level rises, it tells you by voice and vibration automatically; no button is needed.', reason: 'row 3');
    expect(ja.driveHudShareHint, '上の「現在地を共有」を押すと、現在地も使って注意を判断します。', reason: 'row 4');
    expect(en.driveHudShareHint, 'Tap "Share my location" above and the caution also uses your position.', reason: 'row 5');
    expect(ja.driveHudFooter, '位置は端末の GPS です。GPS が弱まると、そのことを表示します。地域の警報・注意報は、気象庁と米国の NWS が実際に出したものです。視界は、気象庁の秋田の観測点（アメダス）が視程を出しているときはその値です。この道路に視界のセンサーはありません。値がないときはそう表示し、クリアとは扱いません。この注意では、速度は不明として扱います。助言だけで、運転するのはいつもドライバーです。引き返すようには伝えません。', reason: 'row 7');
    expect(en.driveHudFooter, 'Position is this device\'s GPS; when GPS weakens, the card says so. The area advisory is what JMA and the US NWS actually issued. Visibility is the JMA Akita station\'s (AMeDAS) reading when the station reports one; there is no visibility sensor on this road. With no reading the card says so and never treats it as clear. This caution treats speed as unknown. Advisory only: the driver always drives, and the card never says to turn back.', reason: 'row 8');
    expect(ja.prefectureHeadStation, '観測点', reason: 'row 9');
    expect(en.prefectureHeadStation, 'Station', reason: 'row 10');
    expect(ja.prefectureHeadSnow, '積雪深', reason: 'row 11');
    expect(en.prefectureHeadSnow, 'Snow', reason: 'row 12');
    expect(ja.prefectureHeadTemp, '気温', reason: 'row 13');
    expect(en.prefectureHeadTemp, 'Temp', reason: 'row 14');
    expect(ja.prefectureHeadWind, '風速', reason: 'row 15');
    expect(en.prefectureHeadWind, 'Wind', reason: 'row 16');
    expect(ja.prefectureHeadObserved, '観測時刻', reason: 'row 17');
    expect(en.prefectureHeadObserved, 'Observed', reason: 'row 18');
    expect(ja.prefectureRefetchAll, 'すべて再取得', reason: 'row 19');
    expect(en.prefectureRefetchAll, 'Re-fetch all', reason: 'row 20');
    expect(ja.observationStationLabel, '観測点', reason: 'row 21');
    expect(en.observationStationLabel, 'Station', reason: 'row 22');
    expect(ja.observationObservedAtLabel, '観測時刻', reason: 'row 23');
    expect(en.observationObservedAtLabel, 'Observed at', reason: 'row 24');
    expect(ja.observationTemperatureLabel, '気温', reason: 'row 25');
    expect(en.observationTemperatureLabel, 'Temperature', reason: 'row 26');
    expect(ja.observationHumidityLabel, '湿度', reason: 'row 27');
    expect(en.observationHumidityLabel, 'Humidity', reason: 'row 28');
    expect(ja.observationWindLabel, '風速', reason: 'row 29');
    expect(en.observationWindLabel, 'Wind', reason: 'row 30');
    expect(ja.observationSnowDepthLabel, '積雪深', reason: 'row 31');
    expect(en.observationSnowDepthLabel, 'Snow depth', reason: 'row 32');
    expect(ja.observationFetchedLabel, '取得時刻', reason: 'row 33');
    expect(en.observationFetchedLabel, 'Fetched', reason: 'row 34');
    expect(ja.akitaObservationSource, '観測の各行は、気象庁アメダスの発表値です。\nウォッチ2行は気象庁ではなく、このアプリの判断です。', reason: 'row 37');
    expect(en.akitaObservationSource, 'The observation rows are the values JMA AMeDAS published.\nThe two watch rows are this app\'s judgement, not JMA\'s.', reason: 'row 38');
    expect(ja.driveHudAnnounceCritical, '段階が上がると、音声＋振動で知らせます。', reason: 'row 40');
    expect(en.driveHudAnnounceCritical, 'When the caution level rises, the app tells you by voice and vibration.', reason: 'row 41');
    expect(ja.driveHudAnnounceWarning, '段階が上がると、音声＋振動で知らせます。', reason: 'row 42');
    expect(en.driveHudAnnounceWarning, 'When the caution level rises, the app tells you by voice and vibration.', reason: 'row 43');
    expect(ja.driveHudAnnounceContinue, 'この段階では、音声や振動では知らせません。', reason: 'row 45');
    expect(en.driveHudAnnounceContinue, 'At this level, nothing is announced by voice or vibration.', reason: 'row 46');
    expect(ja.responsibilityBanner, '開発中のアルファ版です。本番のナビゲーション用ではありません。運転の判断はすべて、ドライバーの責任です。このアプリは情報を表示するだけで、車を操作しません。', reason: 'row 47');
    expect(en.responsibilityBanner, 'Alpha software. Not for production navigation. The driver remains responsible for all driving decisions. This app surfaces information; it does not control the vehicle.', reason: 'row 48');
    expect(en.driveHudNoPositionFed, '(no position received yet)', reason: 'row 6');
    expect(en.driveHudAnnounceRaisedNotSpoken, 'Raised to caution (shown in colour). This level is not read aloud.', reason: 'row 44');
  });

  test('the low-visibility reason reads very poor in English, Japanese unchanged', () {
    const t = DriveHudLocalizer();
    expect(t.reasonLabel(CautionReason.lowVisibility, 'en'), 'Visibility is very poor');
    expect(t.reasonLabel(CautionReason.lowVisibility, 'ja'), '視界が非常に悪い');
  });

  test('the fetched time: under a minute, minutes, and hours with minutes', () {
    expect(ja.observationFetchedAt('09:05', 0), '09:05（1分以内）');
    expect(en.observationFetchedAt('09:05', 0), '09:05 (within 1 min)');
    expect(ja.observationFetchedAt('09:05', 12), '09:05（12分前）');
    expect(en.observationFetchedAt('09:05', 12), '09:05 (12 min ago)');
    expect(ja.observationFetchedAt('09:05', 75), '09:05（1時間15分前）');
    expect(en.observationFetchedAt('09:05', 75), '09:05 (1h 15m ago)');
  });

  test('the page source no longer carries the English literals these words replace', () {
    final main = File('lib/main.dart').readAsStringSync();
    for (final old in const [
      'child: Text(\'Station\',',
      'child: Text(\'Snow\',',
      'child: Text(\'Temp\',',
      'child: Text(\'Wind\',',
      'child: Text(\'Observed\',',
      'child: const Text(\'Re-fetch all\'),',
      '_kv(\'Station\', ',
      '_kv(\'Observed at\', ',
      '_kv(\'Temperature\', ',
      '_kv(\'Humidity\', ',
      '_kv(\'Wind\', ',
      '_kv(\'Snow depth\', ',
      '_kv(\'Fetched\', ',
      'return \'\${fmt.format(fetchedAt)} (\$minutesStale min ago)\';',
      '\'Source: JMA AMeDAS — observation fields are verbatim relay. \'\n              \'路面凍結ウォッチ is DERIVED from them (shared radiative-frost \'\n              \'classifier) — an inference, not a JMA statement. 荒天ウォッチ \'\n              \'likewise: derived from the measured 10-min precipitation \'\n              \'(×6 hourly-equivalent is this app\\\'s conversion) and 10-min \'\n              \'mean wind, judged against JMA\\\'s published intensity tables \'\n              \'(雨の強さと降り方 / 風の強さと吹き方) — an inference, not a \'\n              \'JMA statement. JMA\\\'s own 警報・注意報 arrive separately, \'\n              \'verbatim, as advisory cards below.\',',
      '\'Alpha software. Not for production navigation. The driver remains \'\n        \'responsible for all driving decisions. This app surfaces information; \'\n        \'it does not control the vehicle.\',',
    ]) {
      expect(main.contains(old), isFalse, reason: old);
    }
  });
}
