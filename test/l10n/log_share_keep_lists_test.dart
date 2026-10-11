/// Code 15's error-log card: its keep lists, and its words unchanged.
///
/// Why, written before the act (2026-10-11). On an emulator frame at text
/// size 2.0 the card's disclosure ended a line 「…については確かめてい」 with
/// 「ません）。」 on the next, which reads "is being checked", the reverse of
/// the clause. Code 15 carried none of the 2026-10-09 lists for this card. The
/// lists here are those lists cut to the words code 15's lines hold, plus the
/// one loanword they missed by their own rule; code 15's words are not changed.
///
/// WHAT A PASS MEANS. Each list is exactly as written below; every listed
/// phrase occurs in the line it guards; by the lists' own rule, every katakana
/// word and every ません in each Japanese line lies inside a listed phrase; the
/// English lists are empty; and the card's Japanese and English lines are the
/// words code 15 had before the lists (eebfd48f), letter for letter.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';

const _ja = AppL10n(Locale('ja'));
const _en = AppL10n(Locale('en'));

// Code 15's lines at eebfd48f, written out so a changed word fails here.
const _disclosureJa = '共有はこのボタンを押したときだけ行われます。自動送信・テレメトリはなく、'
    'アカウントも不要です。ログに含まれるのはエラーの記録のみで、'
    '位置情報の履歴は含まれません。送信先は端末の共有画面で自分で選べます。'
    'ログは Google のバックアップや、新しい端末へのデータ移行には含まれません'
    '（スマートフォンのメーカー独自のバックアップについては確かめていません）。';
const _recordsJa = 'エラー記録があります。共有ボタンでベータ・フィードバックとして送れます。';
const _emptyJa = 'ログは空です（クラッシュ・エラーの記録はありません）。';
const _unavailableJa = 'エラーログはこの環境では利用できません。';
const _disclosureEn = 'Sharing happens only when you tap this button — no automatic '
    'upload, no telemetry, and no account. The log contains only '
    'error records; it holds no location history. You choose the '
    "destination in your device's share sheet. The log is not included "
    "in Google's backup or in a transfer to a new phone (a phone "
    "maker's own backup has not been checked).";
const _recordsEn =
    'Error records are present. Use the share button to send them as beta feedback.';
const _emptyEn = 'The log is empty (no crash or error records).';
const _unavailableEn = 'The error log is unavailable in this environment.';

// The lists, as this round sets them. Against the 2026-10-09 lists (bf346b34):
// the disclosure's drops 移行アプリ, which code 15's line does not hold; the
// records-present line's adds エラー, a loanword that list missed.
const _disclosureList = [
  'ボタン', 'ログ', 'テレメトリ', 'アカウント', 'エラー', 'バックアップ', 'データ移行',
  'スマートフォン', 'メーカー', '含まれません', '確かめていません',
];
const _recordsList = ['エラー', 'ボタン', 'ベータ・フィードバック', '送れます'];
const _emptyList = ['ログ', 'クラッシュ', 'エラー', 'ありません'];
const _unavailableList = ['エラーログ', '利用できません'];

bool _katakanaLetter(int r) => (r >= 0x30A1 && r <= 0x30FA) || r == 0x30FC;

/// Each katakana word (a run of katakana letters and ー) and each ません in
/// [line] that no occurrence of a word in [list] covers.
List<String> _uncovered(String line, List<String> list) {
  final covered = List<bool>.filled(line.length, false);
  for (final w in list) {
    for (var s = line.indexOf(w); s >= 0; s = line.indexOf(w, s + 1)) {
      for (var i = s; i < s + w.length; i++) {
        covered[i] = true;
      }
    }
  }
  final out = <String>[];
  var i = 0;
  while (i < line.length) {
    if (_katakanaLetter(line.codeUnitAt(i))) {
      var j = i;
      while (j < line.length && _katakanaLetter(line.codeUnitAt(j))) {
        j++;
      }
      if (covered.sublist(i, j).contains(false)) out.add(line.substring(i, j));
      i = j;
    } else {
      i++;
    }
  }
  for (var s = line.indexOf('ません'); s >= 0; s = line.indexOf('ません', s + 1)) {
    // The negation with its stem: the ません and the two characters before it.
    final from = s >= 2 ? s - 2 : 0;
    if (covered.sublist(from, s + 3).contains(false)) {
      out.add(line.substring(from, s + 3));
    }
  }
  return out;
}

void main() {
  group('code 15 log card: words unchanged', () {
    test('Japanese lines are code 15\'s own, letter for letter', () {
      expect(_ja.logShareDisclosure, _disclosureJa);
      expect(_ja.logShareHasRecords, _recordsJa);
      expect(_ja.logShareEmpty, _emptyJa);
      expect(_ja.logShareUnavailable, _unavailableJa);
      expect(_ja.logShareSectionTitle, 'フィードバック — ログを共有');
      expect(_ja.shareLog, 'ログを共有');
    });

    test('English lines are code 15\'s own, letter for letter', () {
      expect(_en.logShareDisclosure, _disclosureEn);
      expect(_en.logShareHasRecords, _recordsEn);
      expect(_en.logShareEmpty, _emptyEn);
      expect(_en.logShareUnavailable, _unavailableEn);
      expect(_en.logShareSectionTitle, 'Feedback — share log');
      expect(_en.shareLog, 'Share log');
    });
  });

  group('code 15 log card: keep lists', () {
    for (final (name, list, ruled, line) in [
      ('disclosure', _ja.logShareKeepTogether, _disclosureList, _disclosureJa),
      ('records-present status', _ja.logShareStatusKeepTogether, _recordsList, _recordsJa),
      ('empty status', _ja.logShareEmptyKeepTogether, _emptyList, _emptyJa),
      ('unavailable status', _ja.logShareUnavailableKeepTogether, _unavailableList,
          _unavailableJa),
    ]) {
      test('$name: the list is as written, and every phrase is in its line', () {
        expect(list, ruled);
        for (final w in list) {
          expect(line.contains(w), isTrue, reason: '$w is not in the $name line');
        }
      });

      test('$name: every katakana word and every ません lies inside a listed phrase',
          () {
        expect(_uncovered(line, list), isEmpty);
      });
    }

    test('the dropped 2026-10-09 entry is not in code 15\'s disclosure', () {
      expect(_disclosureJa.contains('移行アプリ'), isFalse);
    });

    test('the rule check finds a missed loanword and a missed negation', () {
      expect(_uncovered(_recordsJa, const ['ボタン', 'ベータ・フィードバック', '送れます']),
          ['エラー']);
      expect(_uncovered(_disclosureJa, _disclosureList.where((w) => w != '確かめていません').toList()),
          ['ていません']);
    });

    test('English lists are empty', () {
      expect(_en.logShareKeepTogether, isEmpty);
      expect(_en.logShareStatusKeepTogether, isEmpty);
      expect(_en.logShareEmptyKeepTogether, isEmpty);
      expect(_en.logShareUnavailableKeepTogether, isEmpty);
    });
  });
}
