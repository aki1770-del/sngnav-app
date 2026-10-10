/// Code 15's card words: exactly the drafted words, the numbers read from
/// source, and NO sentence nobody drafted.
///
/// Why, written before the act (2026-10-10). The card tells the man carrying
/// the phone what is recorded about him, where it stays and how it ends. Those
/// words were drafted and read before the build: the 2026-10-09 boundary
/// ruling's card draft, with the 2026-10-09 dignity read's two required
/// changes and its later widening. A paraphrase here would be a sentence
/// nobody read. The numbers in them (the cap, the fix period, the hours) must
/// come from the code that does what they say, never from a typed number.
///
/// THE SECOND GROUP IS RED BY DESIGN. The count line has no drafted words in
/// either language; the build carries a placeholder there, and this test
/// refuses it, so code 15 cannot pass its own suite until the words are
/// drafted and ruled (Sakichi Vision 15: cannot be done wrong).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/code15_fix_interval_record.dart';

// The drafted words, as literals, with the three numbers left as fields so the
// test fills them from source exactly as the app must.
String _drafted({required bool ja}) {
  final cap = kCode15RecordCapKbText;
  final period = kCode15DesignFixPeriod.inSeconds;
  final hours = kCode15RecordHoursText;
  return ja
      ? '共有は「記録を共有」を押したときだけ行われます。自動送信・テレメトリはなく、'
          'アカウントも不要です。このテスト版は、現在地を共有している間だけ、GPS の測位が'
          '届いた間隔を記録します（届いた時刻の間隔と遅れ・測位の種類と精度・速度・'
          'アプリが前面にあったか）。共有を止めたとき、アプリが起動したとき、'
          'アプリを離れたときと戻ったとき、測位が届かない間はアプリが動いていること'
          '（数秒ごと）も記録します（時刻は書きません）。'
          'アプリを離れた・戻った印と、動いている印は、端末がアプリを止めたかどうかを'
          '見分けるためだけに使います。'
          '記録を止めたときと再開したときも、その印だけを残します。緯度経度や地名は'
          '記録しません。共有する内容には書き出した時刻が入ります。'
          '記録はこの端末に残り、Google のバックアップや、新しい端末へのデータ移行には'
          '含まれません（スマートフォンのメーカー独自のバックアップや移行アプリについては'
          '確かめていません）。押すまで送られません。'
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
          'sharing, when the app starts, when you leave the app and come back, '
          'and, while no fix arrives, that the app is still running (every few '
          'seconds). No clock time. The leave, return and still-running marks '
          'are used only to tell whether the phone stopped the app. It marks '
          'when you stop and restart recording. It records no coordinates and '
          'no place names. The shared text includes the time it was exported. '
          'The record stays on this phone. It is not included in Google\'s '
          'backup or in a transfer to a new phone (a phone maker\'s own backup '
          'or transfer app has not been checked). It is sent only when you '
          'tap. You choose the destination in your device\'s share sheet; the '
          'app cannot tell whether it arrived. Stop recording stops it; Delete '
          'record deletes it. Unlike code 13, installing a newer version does '
          'not delete it. It is deleted when you tap Delete record, clear the '
          'app\'s data, or uninstall the app. Its cap is about $cap KB (about '
          '$hours hours if fixes arrive every $period s); when reached, '
          'recording stops.';
}

const _ja = AppL10n(Locale('ja'));
const _en = AppL10n(Locale('en'));

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

    test('the code 13 promise this build reverses is not carried: no "the '
        'next build deletes it"', () {
      expect(_ja.code15RecordDisclosure, isNot(contains('次の版を入れると消えます')));
      expect(_en.code15RecordDisclosure,
          isNot(contains('deleted when the next build is installed')));
    });
  });

  group('NO UNDRAFTED SENTENCE (red until the count line\'s words are ruled)',
      () {
    test('no card text carries the placeholder', () {
      for (final l in [_ja, _en]) {
        final texts = <String, String>{
          'code15RecordSectionTitle': l.code15RecordSectionTitle,
          'code15RecordUnavailable': l.code15RecordUnavailable,
          'code15RecordEmpty': l.code15RecordEmpty,
          'code15RecordPresent': l.code15RecordPresent,
          'code15RecordStoppedNote': l.code15RecordStoppedNote,
          'code15RecordFullNote': l.code15RecordFullNote,
          'code15RecordDisclosure': l.code15RecordDisclosure,
          'code15RecordCount': l.code15RecordCount(
              movingMinutes: 31, stoppedMinutes: 6, minimumReached: true),
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
