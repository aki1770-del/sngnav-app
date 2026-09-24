// The maneuver card must never again say she WAS told.
//
// `ManeuverNarration.shouldAnnounce` is set to `true` at construction in
// `ManeuverNarration._announce`, and `DriveHudController.narrateNextManeuver`
// dispatches `unawaited(_announcer.announce(...))` and returns immediately —
// its own doc comment says "Announcing is fire-and-forget". Nothing about
// arrival on either channel is known when the card renders.
//
// Until 2026-09-23 the card rendered 「音声＋振動で知らせました。」 /
// "Announced on audio + haptic." from that boolean: a past-tense delivery
// claim on two channels. The identical chain had already been corrected on
// the drive-HUD chips on 2026-08-22, after a device was measured dispatching
// speech and producing ZERO vibrations; this card was not swept with it.
//
// This guard fails on the old sentence. It is written so that restoring the
// past tense — in either language — is a red test, not a review comment.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';

void main() {
  final ja = AppL10n(const Locale('ja'));
  final en = AppL10n(const Locale('en'));

  test('the dispatch line states SENT, never told/announced', () {
    expect(ja.maneuverNarrationSent, '音声と振動に送りました。');
    expect(en.maneuverNarrationSent, 'Sent to audio + haptic.');

    // The exact sentences this guard exists to keep out.
    expect(ja.maneuverNarrationSent, isNot('音声＋振動で知らせました。'));
    expect(en.maneuverNarrationSent, isNot('Announced on audio + haptic.'));

    // And the shape, not just those two strings: no past-tense delivery verb.
    expect(ja.maneuverNarrationSent, isNot(contains('知らせました')));
    expect(ja.maneuverNarrationSent, isNot(contains('伝えました')));
    expect(en.maneuverNarrationSent.toLowerCase(), isNot(contains('announced')));
    expect(en.maneuverNarrationSent.toLowerCase(), isNot(contains('delivered')));
  });

  test('the unverified half names the channel that did not report', () {
    // Haptic alone — the only channel a deaf or hard-of-hearing driver has.
    expect(ja.maneuverNarrationDeliveryUnverified(speech: false, haptic: true),
        contains('振動'));
    expect(en.maneuverNarrationDeliveryUnverified(speech: false, haptic: true)
        .toLowerCase(), contains('vibration'));

    // Speech alone.
    expect(ja.maneuverNarrationDeliveryUnverified(speech: true, haptic: false),
        contains('音声'));
    expect(en.maneuverNarrationDeliveryUnverified(speech: true, haptic: false)
        .toLowerCase(), contains('voice'));

    // Both — one line, naming both, never silently dropping one.
    final jaBoth =
        ja.maneuverNarrationDeliveryUnverified(speech: true, haptic: true);
    expect(jaBoth, contains('音声'));
    expect(jaBoth, contains('振動'));

    // None of the three may read as a delivery confirmation.
    for (final s in [
      ja.maneuverNarrationDeliveryUnverified(speech: true, haptic: false),
      ja.maneuverNarrationDeliveryUnverified(speech: false, haptic: true),
      jaBoth,
    ]) {
      expect(s, contains('確認できていません'));
    }
  });
}
