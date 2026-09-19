/// Every station in the prefecture table is the place its row names.
///
/// Why, written before the act (2026-09-19). The row drawn as 横手 (south,
/// inland) fetched station 32466. JMA's own station table names 32466 角館
/// (Kakunodate), about 31 km north of Yokote. Yokote is 32596, at exactly the
/// position this table already gave for 横手, so only the id was wrong: the
/// row showed Kakunodate's snow depth, temperature and wind under Yokote's
/// name. Nothing compared a station's id with the place its row names.
///
/// The reference below is an extract of JMA's AMeDAS station table
/// (出典: 気象庁ホームページ,
/// https://www.jma.go.jp/bosai/amedas/const/amedastable.json, read 2026-09-19,
/// sha256 319d215c6c9243ccb794e925dded2f849a0202f1b2cd74ce607b232f2bc2ddc5).
/// Extracted: the kanji name, the English name and the position of each
/// station the table fetches, degrees and minutes converted to decimal
/// degrees, plus 32466, so the old id fails on the place it really is. It is a
/// copy: if JMA renumbers or moves a station, this test fails, and that is
/// the right answer.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';

const _jmaStations =
    <String, ({String kjName, String enName, double lat, double lon})>{
  '32286': (kjName: '男鹿', enName: 'Oga', lat: 39.912, lon: 139.900),
  '32402': (kjName: '秋田', enName: 'Akita', lat: 39.717, lon: 140.098),
  '32466': (kjName: '角館', enName: 'Kakunodate', lat: 39.603, lon: 140.557),
  '32551': (kjName: '大曲', enName: 'Omagari', lat: 39.490, lon: 140.495),
  '32596': (kjName: '横手', enName: 'Yokote', lat: 39.320, lon: 140.555),
  '32691': (kjName: '湯沢', enName: 'Yuzawa', lat: 39.187, lon: 140.463),
};

/// Each Japanese place description with the English it is drawn as. Pinned
/// as pairs, so the English for a station is held to that station's
/// Japanese and not only to having no Japanese in it: two English
/// descriptions swapped between stations would pass every other check here,
/// because the page and a check that reads the app's own words agree on a
/// swap.
const _placeInEnglish = <String, String>{
  '北・海沿い': 'North coast',
  '市街地': 'City',
  '中央内陸': 'Central inland',
  '南・内陸': 'South inland',
  '南・山間': 'South mountains',
};

final _cjk = RegExp(
  '[\u3000-\u303F\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\uFF00-\uFFEF]',
);

void main() {
  test('each row of the prefecture table fetches the station it names, at '
      'the position it gives', () {
    final problems = <String>[];
    for (final s in corridorStations) {
      final jma = _jmaStations[s.id];
      if (jma == null) {
        problems.add('${s.id} (${s.name}) is not in the JMA extract; add it '
            'from JMA\'s table before trusting this row');
        continue;
      }
      if (jma.kjName != s.name) {
        problems.add('${s.id} is ${jma.kjName} in JMA\'s table, but its row '
            'is drawn as ${s.name}');
      }
      // 0.01 degree is about 1.1 km: the table's own figures are rounded to
      // three places, and a wrong station is kilometres away, not metres.
      if ((jma.lat - s.lat).abs() > 0.01 || (jma.lon - s.lon).abs() > 0.01) {
        problems.add('${s.id} is at ${jma.lat}, ${jma.lon} in JMA\'s table, '
            'but its row gives ${s.lat}, ${s.lon}');
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('on an English page each station carries JMA\'s own English name, and '
      'its place in words with no Japanese in them; the Japanese page is '
      'unchanged', () {
    const ja = AppL10n(Locale('ja'));
    const en = AppL10n(Locale('en'));
    final problems = <String>[];
    for (final s in corridorStations) {
      final jma = _jmaStations[s.id];
      if (jma == null) continue; // reported by the test above
      if (en.stationName(s.id, s.name) != jma.enName) {
        problems.add('${s.id}: English name "${en.stationName(s.id, s.name)}", '
            'JMA says "${jma.enName}"');
      }
      if (ja.stationName(s.id, s.name) != s.name) {
        problems.add('${s.id}: the Japanese name moved');
      }
      final d = en.stationDescriptor(s.id, s.descriptor);
      if (_cjk.hasMatch(d)) problems.add('${s.id}: "$d" has Japanese in it');
      if (d != _placeInEnglish[s.descriptor]) {
        problems.add('${s.id}: 「${s.descriptor}」 is drawn as "$d" in English, '
            'not "${_placeInEnglish[s.descriptor]}"');
      }
      if (ja.stationDescriptor(s.id, s.descriptor) != s.descriptor) {
        problems.add('${s.id}: the Japanese place description moved');
      }
    }
    final akita = _jmaStations[akitaStationId]!;
    if (en.akitaStationMapLabel != akita.enName) {
      problems.add('map label "${en.akitaStationMapLabel}", JMA says '
          '"${akita.enName}"');
    }
    if (ja.akitaStationMapLabel != akita.kjName) {
      problems.add('ja map label "${ja.akitaStationMapLabel}", JMA says '
          '"${akita.kjName}"');
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('the table names five different stations', () {
    final ids = corridorStations.map((s) => s.id).toSet();
    expect(ids.length, corridorStations.length);
    expect(corridorStations.length, 5,
        reason: 'the extract above covers five rows; a new row needs its '
            'station added to it');
  });
}
