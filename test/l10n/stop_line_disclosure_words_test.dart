/// Before her yes, the can-post words tell her that 停止 is said once, by voice
/// and vibration, even during a call (W-2, 2026-10-10).
///
/// WHY. The stop confirmation speaks at 停止 whatever the drive's branch, and
/// through a refused audio focus, so over a call. The driver who cannot post a
/// notification is told before her yes that the app speaks once through a call
/// when a drive ends. The driver who can post was told nothing. One machine,
/// one act, two cohorts of one person, and one of them told: a dignity review
/// (WDA 46e240b2 section 3) ruled the advance word owed for the can-post words
/// and gave them. They are pinned here byte for byte, in the place the review
/// set: right after the sentence that names 停止 / Stop, in both places the
/// can-post facts are stated. The cannot-post words already say it and are
/// left as they are.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';

/// The dignity review's words, verbatim.
const _ja = '「停止」で終了すると、そのことを一度だけ声と振動でお知らせします（通話中でも話します）。';
const _en =
    'When you end it with Stop, the app says so once, by voice and vibration, '
    'even during a call.';

/// The sentence each must follow, as the words already had it.
const _stopJa = '「停止」を押してください。';
const _stopEn = 'then Stop.';

void main() {
  const ja = AppL10n(Locale('ja'));
  const en = AppL10n(Locale('en'));

  test('can post: the sentence follows the one that names 停止, and ends the '
      'words', () {
    expect(ja.driveDisclosure, endsWith('$_stopJa$_ja'));
    expect(en.driveDisclosure, endsWith('$_stopEn $_en'));
  });

  test('not known yet: the same sentence, byte for byte, ends the half about '
      'a drive with notifications allowed', () {
    expect(ja.driveDisclosureIfNotificationsAllowed, endsWith('$_stopJa$_ja'));
    expect(en.driveDisclosureIfNotificationsAllowed, endsWith('$_stopEn $_en'));
    // Once each: the half about a drive without them is not given it.
    expect(_ja.allMatches(ja.driveDisclosureIfNotificationsAllowed),
        hasLength(1));
    expect(_en.allMatches(en.driveDisclosureIfNotificationsAllowed),
        hasLength(1));
  });

  test('cannot post: unchanged; it already says the app speaks once through a '
      'call when a drive ends', () {
    expect(ja.shareWithoutServiceDisclosure, isNot(contains(_ja)));
    expect(en.shareWithoutServiceDisclosure, isNot(contains(_en)));
    expect(ja.shareWithoutServiceDisclosure,
        contains('一度だけ声と振動でお知らせします（通話中でも話します）。'),
        reason: 'control: the words the sentence takes its tail from');
  });

  test('the words that must stay whole are on the lists those words use', () {
    // 通話中でも話します is protected with its brackets, as 「停止」 is: the
    // bracketed unit is what must fit on one line.
    for (final w in const ['一度だけ', '声と振動', '（通話中でも話します）']) {
      expect(ja.driveDisclosureKeepTogether, contains(w));
      expect(ja.driveDisclosureIfNotificationsAllowedKeepTogether, contains(w));
    }
    for (final w in const ['by voice and vibration', 'even during a call']) {
      expect(en.driveDisclosureKeepTogether, contains(w));
      expect(en.driveDisclosureIfNotificationsAllowedKeepTogether, contains(w));
    }
  });
}
