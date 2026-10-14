/// Code 15's card words: exactly the drafted words, the numbers read from
/// source, and NO sentence nobody drafted.
///
/// Why, written before the act (2026-10-10). The card tells the man carrying
/// the phone what is recorded about him, where it stays and how it ends, and
/// its count line tells him when to send. Those words were drafted and read
/// before the build: the 2026-10-09 boundary ruling's card draft with the
/// 2026-10-09 dignity read's changes and widening, then the 2026-10-10 dignity
/// read's three disclosure changes and the count line's four forms (English by
/// the boundary ruling, Japanese by the display review, both read by the
/// dignity review). A paraphrase here would be a sentence nobody read. The
/// numbers in them (the cap, the fix period, the hours, the two marks) must
/// come from the code that does what they say, never from a typed number.
///
/// Before the count words were ruled (b186452b), the last group was red by
/// design, refusing the placeholder the card then carried. It now passes, and
/// it stays: a future placeholder is refused the same way (Sakichi Vision 15).
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/code15_fix_interval_record.dart';

// The drafted words, as literals, with the three numbers left as fields so the
// test fills them from source exactly as the app must.
//
// CODE 16 (2026-10-14): the disclosure's middle changed. The start mark is
// named as what it is on this build, the purpose list takes it, and the
// version line and the header's build: line are named. Drafted by the app
// engineer with the code; the screen review and the dignity review read it
// before the build goes to him. Until they do, this pins a draft, and says so.
String _drafted({required bool ja}) {
  final cap = kCode15RecordCapKbText;
  final period = kCode15DesignFixPeriod.inSeconds;
  final hours = kCode15RecordHoursText;
  return ja
      ? '共有は「記録を共有」を押したときだけ行われます。自動送信・テレメトリはなく、'
          'アカウントも不要です。このテスト版は、現在地を共有している間だけ、GPS の測位が'
          '届いた間隔を記録します（届いた時刻の間隔と遅れ・測位の種類と精度・速度・'
          'アプリが前面にあったか）。共有を止めたとき、アプリ自身が共有を終えたとき、'
          'アプリを離れたときと戻ったとき、測位が届かない間は'
          'アプリが動いていること（数秒ごと）も記録します（時刻は書きません）。'
          'また、共有しているかどうかにかかわらず、アプリの画面が新しく開くたびに'
          '印を残します（起動したときや、戻る操作で離れたあとにもう一度開いたときなど）。'
          '版が初めてこの記録に書くとき（新しい版を入れたあとや、「記録を消す」のあと）は、'
          'その版を示す一行（「k=build」で始まり、版番号と、版を見分ける短い英数字が'
          '入ります）を最初に残します。'
          'アプリが開いた印、アプリを離れた・戻った印、動いている印、アプリが共有を終えた印は、'
          '端末がアプリを止めたかどうかなど、アプリと端末がどう動いたかを見るためだけに'
          '使い、あなたが何をしたかを見るためには使いません。'
          '版を示す行は、どの版が書いたかを見るためだけに使います。'
          '記録を止めたときと再開したときも、その印だけを残します。緯度経度や地名は'
          '記録しません。共有する内容には、書き出した時刻と、'
          '共有した版を示す「build:」の行が入ります。'
          '記録はこの端末に残り、Google のバックアップや、新しい端末へのデータ移行には'
          '含まれません（スマートフォンのメーカー独自のバックアップや移行アプリについては'
          '確かめていません）。アプリから送られるのは、「記録を共有」を押したときだけです。'
          '送信先は端末の共有画面で自分で選べますが、届いたかどうかはアプリにはわかりません。'
          '「記録を止める」で止まり、「記録を消す」で消えます。'
          'コード13と違い、新しい版を入れても消えません。消えるのは「記録を消す」を押した'
          'とき、アプリのデータを消去したとき、アプリを削除したときです。'
          '上限は約$cap KB（$period秒ごとに届けば約$hours時間分）で、達すると記録を止めます。'
      : 'Sharing happens only when you tap Share record — no automatic '
          'upload, no telemetry, and no account. This test build records, only '
          'while you share your location, how far apart GPS fixes arrive (the '
          'interval and delay of each, its kind and accuracy, your speed, and '
          'whether the app was in front). It also records when you stop '
          'sharing, when the app itself ends a share, when you leave the app '
          'and come back, and, while no fix arrives, that the app is still '
          'running (every few seconds). No clock time. It also marks each time '
          'the app opens its screen anew, such as when it starts or when you '
          'open it again after going back out of it, whether or not you share. '
          'When a version first writes to this record (after a newer version '
          'is installed, or after Delete record), it first writes one line '
          'naming that version: it begins with k=build and holds the version '
          'number and short codes that tell builds apart. The start, leave, '
          'return, still-running and app-ended marks are used only to read how '
          'the app and the phone behaved, such as whether the phone stopped the '
          'app, never to read what you did. The version line is used only to '
          'read which version wrote which lines. It marks when you stop and '
          'restart recording. It records no coordinates and no place names. '
          'The shared text includes the time it was exported and a build: line '
          'naming the version that shared it. '
          'The record stays on this phone. It is not included in Google\'s '
          'backup or in a transfer to a new phone (a phone maker\'s own backup '
          'or transfer app has not been checked). The app sends it only when '
          'you tap Share record. You choose the destination in your device\'s '
          'share sheet; the app cannot tell whether it arrived. Stop recording '
          'stops it; Delete record deletes it. Unlike code 13, installing a '
          'newer version does not delete it. It is deleted when you tap Delete '
          'record, clear the app\'s data, or uninstall the app. Its cap is '
          'about $cap KB (about $hours hours if fixes arrive every $period s); '
          'when reached, recording stops.';
}

// The count line's eight strings, as drafted, with the minutes and the marks
// left as fields. The marks are filled from source below, never typed here.
String _form(String f, {required bool ja, required int m, required int s}) {
  final mm = kBarsMinMovingMs ~/ 60000;
  final sm = kBarsMinStoppedMs ~/ 60000;
  switch (f) {
    case 'R':
      return ja
          ? '最低限に達しました（アプリの数え方で）。修正版を出せるかどうかは、これだけでは'
              'まだわかりません。駐車中に「記録を共有」を押して送り、欠けずに届いたと'
              '知らされるまで、記録は消さずに残しておいてください。'
          : 'The minimum is reached, by this card\'s count. That does not yet '
              'say whether the fix can come. When you are parked, tap Share '
              'record and send it, and keep the record until you are told it '
              'arrived whole.';
    case 'N1':
      return ja
          ? 'まだ最低限に達していません（アプリの数え方で）。これまでに数えたのは、'
              '走行$m分（$mm分以上必要）、停車$s分（$sm分以上必要）です。'
          : 'Not yet, by this card\'s count. So far: driving $m minutes (at least '
              '$mm needed), standing still $s minutes (at least $sm needed).';
    case 'N2':
      return ja
          ? 'まだ最低限に達していません（アプリの数え方で）。走行$m分と停車$s分は数えましたが、'
              'のろのろ運転の割合など、最低限のほかの条件をまだ満たしていません。'
          : 'Not yet, by this card\'s count. Driving $m minutes and standing still '
              '$s minutes are counted; another part of the minimum, such as how '
              'much of the driving was a slow crawl, is not yet met.';
    case 'F':
      return ja
          ? '記録が上限に達しました。最低限には達していません（アプリの数え方で）。'
              '駐車中に「記録を共有」を押して送り、欠けずに届いたと知らされるまで、'
              '記録は消さずに残しておいてください。'
          : 'The record filled before the minimum was reached, by this card\'s '
              'count. When you are parked, tap Share record and send it, and keep '
              'the record until you are told it arrived whole.';
  }
  throw ArgumentError(f);
}

const _ja = AppL10n(Locale('ja'));
const _en = AppL10n(Locale('en'));

// Sentinel minutes, so a typed number cannot pass for a filled one.
const _m = 777;
const _s = 888;

String _count(AppL10n l, {int m = _m, int s = _s, bool reached = false,
        bool full = false}) =>
    l.code15RecordCount(
        movingMinutes: m, stoppedMinutes: s, minimumReached: reached, full: full);

/// Every form the card can draw, in both languages.
Map<String, String> _allForms() => {
      for (final l in [_ja, _en]) ...{
        'R ${l.locale.languageCode}': _count(l, reached: true),
        'R full ${l.locale.languageCode}': _count(l, reached: true, full: true),
        'F ${l.locale.languageCode}': _count(l, full: true),
        'N1 ${l.locale.languageCode}': _count(l, m: 7),
        'N2 ${l.locale.languageCode}': _count(l),
      },
    };

void main() {
  group('the drafted words, exactly', () {
    test('the disclosure, Japanese', () {
      expect(_ja.code15RecordDisclosure, _drafted(ja: true));
    });

    test('the disclosure, English', () {
      expect(_en.code15RecordDisclosure, _drafted(ja: false));
    });

    test('the numbers are the source\'s: 192 KB, 5 s, 5 hours, and none of '
        'code 13\'s 96 KB or 3 hours survives', () {
      for (final d in [_ja.code15RecordDisclosure, _en.code15RecordDisclosure]) {
        expect(d, isNot(contains('96 KB')));
        expect(d, isNot(contains('約3時間')));
        expect(d, isNot(contains('3 hours')));
      }
      expect(_ja.code15RecordDisclosure, contains('上限は約192 KB（5秒ごとに届けば約5時間分）'));
      expect(_en.code15RecordDisclosure,
          contains('about 192 KB (about 5 hours if fixes arrive every 5 s)'));
      expect(_ja.code15RecordFullNote, '上限（約192 KB）に達したため、記録を止めています。');
      expect(_en.code15RecordFullNote,
          'The record reached its cap (about 192 KB), so recording has stopped.');
    });

    test('code 13\'s status and action words, carried unchanged', () {
      expect(_ja.code15RecordSectionTitle, '測位間隔の記録（テスト版）');
      expect(_en.code15RecordSectionTitle, 'Fix-interval record (test build)');
      expect(_ja.code15RecordEmpty, '測位間隔の記録はありません。');
      expect(_ja.code15RecordPresent, '測位間隔の記録があります。「記録を共有」で送れます。');
      expect(_ja.code15RecordStoppedNote, '記録は止めています。');
      expect(_ja.code15RecordUnavailable, 'この端末では測位間隔の記録を開けません。');
      expect([_ja.code15RecordShare, _ja.code15RecordStop, _ja.code15RecordResume,
          _ja.code15RecordDelete], ['記録を共有', '記録を止める', '記録を再開', '記録を消す']);
      expect([_en.code15RecordShare, _en.code15RecordStop, _en.code15RecordResume,
          _en.code15RecordDelete],
          ['Share record', 'Stop recording', 'Record again', 'Delete record']);
    });

    test('the share-failed line (R-D3-4), exactly as ruled, its last sentence '
        'dropped (the dignity follow-up, 2026-10-10)', () {
      expect(_ja.code15RecordShareFailed,
          '記録を端末の共有画面に渡せませんでした。何も送られていません。');
      expect(_en.code15RecordShareFailed,
          'The record could not be handed to the share screen. Nothing was '
          'sent.');
    });

    test('the code 13 promise this build reverses is not carried, and the '
        'passive "only" is gone', () {
      expect(_ja.code15RecordDisclosure, isNot(contains('次の版を入れると消えます')));
      expect(_en.code15RecordDisclosure,
          isNot(contains('deleted when the next build is installed')));
      expect(_ja.code15RecordDisclosure, isNot(contains('押すまで送られません')));
      expect(_en.code15RecordDisclosure, isNot(contains('It is sent only')));
    });

    test('the card names the app\'s own ending (appstop) if and only if the '
        'record can write it', () {
      final writes = Code15MarkKind.values.any((k) => k.token == 'appstop');
      expect(_ja.code15RecordDisclosure.contains('アプリ自身が共有を終えたとき'), writes);
      expect(_ja.code15RecordDisclosure.contains('アプリが共有を終えた印'), writes);
      expect(_en.code15RecordDisclosure.contains('when the app itself ends a share'),
          writes);
      expect(_en.code15RecordDisclosure.contains('app-ended marks'), writes);
      expect(writes, isTrue, reason: 'control: this build writes appstop');
    });
  });

  group('the count line: four forms, drafted, chosen as ruled', () {
    test('the eight strings, character for character, the marks from source',
        () {
      for (final ja in [true, false]) {
        final l = ja ? _ja : _en;
        expect(_count(l, reached: true), _form('R', ja: ja, m: _m, s: _s));
        expect(_count(l, full: true), _form('F', ja: ja, m: _m, s: _s));
        expect(_count(l, m: 7), _form('N1', ja: ja, m: 7, s: _s));
        expect(_count(l), _form('N2', ja: ja, m: _m, s: _s));
      }
    });

    test('which form: R whenever reached (full or not), F when full and not '
        'reached, N1 when a minute is under its mark, N2 otherwise', () {
      final mm = kBarsMinMovingMs ~/ 60000;
      final sm = kBarsMinStoppedMs ~/ 60000;
      for (final l in [_ja, _en]) {
        expect(_count(l, reached: true, full: true),
            _count(l, reached: true), reason: 'R even when full');
        expect(_count(l, m: mm - 1, s: sm), _form('N1', ja: l == _ja, m: mm - 1, s: sm));
        expect(_count(l, m: mm, s: sm - 1), _form('N1', ja: l == _ja, m: mm, s: sm - 1));
        expect(_count(l, m: mm, s: sm), _form('N2', ja: l == _ja, m: mm, s: sm));
        expect(_count(l, m: 0, s: 0, full: true), _form('F', ja: l == _ja, m: 0, s: 0),
            reason: 'F even with minutes under the marks');
      }
    });

    test('never clean, passed or done; never minutes remaining', () {
      final badJa = ['完了', '合格', 'クリア', '十分', 'OK', 'ＯＫ', '達成', 'たまりました', '残り', 'あと'];
      final badEn = RegExp(
          r'\b(clean|pass(ed)?|done|ready|complete[d]?|remaining|left to go|to go|OK)\b',
          caseSensitive: false);
      for (final e in _allForms().entries) {
        if (e.key.endsWith('ja')) {
          for (final w in badJa) {
            expect(e.value.contains(w), isFalse, reason: '${e.key}: $w');
          }
        } else {
          expect(badEn.hasMatch(e.value), isFalse, reason: e.key);
        }
      }
    });

    test('every form carries the qualifier', () {
      for (final e in _allForms().entries) {
        expect(
            e.value,
            contains(e.key.endsWith('ja') ? '（アプリの数え方で）' : 'by this card\'s count'),
            reason: e.key);
      }
    });

    test('only R opens on the reached phrase', () {
      for (final e in _allForms().entries) {
        final isR = e.key.startsWith('R');
        expect(
            e.value.startsWith(e.key.endsWith('ja') ? '最低限に達' : 'The minimum is reached'),
            isR,
            reason: e.key);
      }
    });

    test('the keep-until-whole and send sentence is in R and F only, always '
        'behind "parked"', () {
      for (final e in _allForms().entries) {
        final asksSend = e.key.startsWith('R') || e.key.startsWith('F');
        final ja = e.key.endsWith('ja');
        expect(
            e.value.contains(ja ? '欠けずに届いたと知らされるまで' : 'keep the record until you are told it arrived whole'),
            asksSend,
            reason: e.key);
        expect(e.value.contains(ja ? '「記録を共有」' : 'Share record'), asksSend,
            reason: e.key);
        if (asksSend) {
          expect(e.value, contains(ja ? '駐車中に「記録を共有」' : 'When you are parked, tap Share record'),
              reason: e.key);
        }
      }
    });

    test('N1 and N2 show the counted minutes, and the marks are not typed in '
        'the source', () {
      for (final l in [_ja, _en]) {
        expect(_count(l), allOf(contains('777'), contains('888')));
        expect(_count(l, m: 7), allOf(contains('7'), contains('888')));
      }
      final src = File('lib/l10n/app_localizations.dart').readAsStringSync();
      final body = src.substring(src.indexOf('String code15RecordCount({'),
          src.indexOf('List<String> code15RecordCountKeep({'));
      expect(body, contains('kBarsMinMovingMs ~/ 60000'));
      expect(body, contains('kBarsMinStoppedMs ~/ 60000'));
      expect(RegExp(r'(?<![$\w])(30|5)(分| needed| minutes)').hasMatch(body), isFalse,
          reason: 'a mark typed into the count words');
    });

    test('the Japanese keep list is the display review\'s, with each number '
        'and its 分; the English keeps none', () {
      final keep = _ja.code15RecordCountKeep(movingMinutes: 12, stoppedMinutes: 3);
      expect(
          keep,
          containsAll([
            '最低限', '達していません', '満たしていません', '「記録を共有」', 'わかりません',
            '欠けずに', '駐車中',
            '消さずに', '修正版', 'のろのろ運転', '上限', '必要', '出せるかどうか',
            '届いたと知らされるまで', '残しておいてください', '（アプリの数え方で）',
            '12分', '3分', '${kBarsMinMovingMs ~/ 60000}分', '${kBarsMinStoppedMs ~/ 60000}分',
          ]));
      expect(keep, isNot(contains('残っています')),
          reason: 'the failure line no longer says 記録は残っています (dropped '
              '2026-10-10), so the list keeps no word of it');
      expect(keep, hasLength(20), reason: 'the display review\'s 20 entries');
      // A word kept on a widget that never draws it guards nothing (the
      // display review, 2026-10-10: the failure line's two negations sat
      // here while the status that draws them had no list).
      final forms = [
        _ja.code15RecordCount(movingMinutes: 12, stoppedMinutes: 3, minimumReached: true, full: false),
        _ja.code15RecordCount(movingMinutes: 12, stoppedMinutes: 3, minimumReached: false, full: true),
        _ja.code15RecordCount(movingMinutes: 12, stoppedMinutes: 3, minimumReached: false, full: false),
        _ja.code15RecordCount(
            movingMinutes: kBarsMinMovingMs ~/ 60000,
            stoppedMinutes: kBarsMinStoppedMs ~/ 60000,
            minimumReached: false,
            full: false),
      ];
      for (final w in keep) {
        expect(forms.any((f) => f.contains(w)), isTrue,
            reason: '$w is in no count form, so keeping it on the count line keeps nothing');
      }
      expect(_en.code15RecordCountKeep(movingMinutes: 12, stoppedMinutes: 3),
          isEmpty);
    });
  });

  group('the keep lists for the status and the disclosure (the display '
      'review, 2026-10-10), Japanese only', () {
    test('the status\'s list, exactly, and each word is in a state it draws', () {
      // Code 16 (2026-10-14): two words for the note a build that cannot name
      // itself draws.
      expect(_ja.code15RecordStatusKeepTogether,
          ['渡せませんでした', '送られていません', '「記録を共有」', '開けません', 'ありません',
           '読み取れなかった', '記録していません']);
      final states = [
        _ja.code15RecordCannotNameBuildNote,
        _ja.code15RecordShareFailed,
        _ja.code15RecordPresent,
        _ja.code15RecordEmpty,
        _ja.code15RecordUnavailable,
        _ja.code15RecordFullNote,
        _ja.code15RecordStoppedNote,
      ];
      for (final w in _ja.code15RecordStatusKeepTogether) {
        expect(states.any((t) => t.contains(w)), isTrue, reason: '$w is drawn by no state');
      }
      expect(_en.code15RecordStatusKeepTogether, isEmpty);
    });

    test('the disclosure\'s list, exactly (27 words), each in the disclosure', () {
      // Code 16 (2026-10-14): the two quoted tokens the card now names.
      expect(_ja.code15RecordDisclosureKeepTogether, [
        '「k=build」', '「build:」',
        'テレメトリ', 'アカウント', 'テスト版', 'アプリ', 'バックアップ', 'データ移行',
        'スマートフォン', 'メーカー', '移行アプリ', 'コード13', '書きません', '使いません',
        '記録しません', '含まれません', '確かめていません', 'わかりません', '消えません',
        '不要', '届いたかどうか', '「記録を共有」', '「記録を止める」', '「記録を消す」',
        'ときだけ', '間だけ', 'ためだけに',
      ]);
      for (final w in _ja.code15RecordDisclosureKeepTogether) {
        expect(_ja.code15RecordDisclosure, contains(w), reason: '$w is not in the disclosure');
      }
      expect(_en.code15RecordDisclosureKeepTogether, isEmpty);
    });
  });

  group('no undrafted sentence', () {
    test('no card text carries the placeholder', () {
      for (final l in [_ja, _en]) {
        final texts = <String, String>{
          'code15RecordSectionTitle': l.code15RecordSectionTitle,
          'code15RecordUnavailable': l.code15RecordUnavailable,
          'code15RecordEmpty': l.code15RecordEmpty,
          'code15RecordPresent': l.code15RecordPresent,
          'code15RecordStoppedNote': l.code15RecordStoppedNote,
          'code15RecordFullNote': l.code15RecordFullNote,
          'code15RecordShareFailed': l.code15RecordShareFailed,
          'code15RecordCannotNameBuildNote': l.code15RecordCannotNameBuildNote,
          'code15RecordDisclosure': l.code15RecordDisclosure,
          for (final e in _allForms().entries) 'code15RecordCount ${e.key}': e.value,
        };
        final undrafted = [
          for (final e in texts.entries)
            if (e.value.contains(AppL10n.kWordsNotDraftedMark)) e.key,
        ];
        expect(undrafted, isEmpty,
            reason: '${l.locale.languageCode}: words not yet drafted by a '
                'ruling seat: $undrafted');
      }
    });
  });
}
