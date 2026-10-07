/// The app's focus request for the phone's own voice is the navigation-guidance
/// request, on the channel Dart sends it on (2026-10-06).
///
/// WHY. flutter_tts asks for focus with no attributes, which the system reads
/// as media (read on an Android 14 emulator: AA=USAGE_MEDIA), so during a call
/// a non-ja driver's voice behaved as music. The app now asks itself
/// (lib/actuators/voice_focus.dart, MainActivity.kt). What the system does
/// with the request is read on a device; this holds that the request the app
/// builds is the right one and that both sides name the same channel.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/actuators/voice_focus.dart';

void main() {
  final kt = File(
    'android/app/src/main/kotlin/dev/aki1770del/sngnav_app/MainActivity.kt',
  ).readAsStringSync();

  test('both sides name the same channel and methods', () {
    expect(kt, contains('"${PlatformVoiceFocus.channel.name}"'),
        reason: 'a rename on one side would silently drop the request');
    expect(kt, contains('"request" -> result.success(requestVoiceFocus('));
    expect(kt, contains('"abandon" -> {'));
  });

  test('the request is transient, duckable, and navigation guidance', () {
    final start = kt.indexOf('private fun requestVoiceFocus(');
    final end = kt.indexOf('private fun abandonVoiceFocus(');
    expect(start, isNonNegative);
    expect(end, greaterThan(start));
    final body = kt.substring(start, end);
    expect(body, contains('AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK'),
        reason: 'her call or music ducks; it is never silenced');
    expect(body, contains('USAGE_ASSISTANCE_NAVIGATION_GUIDANCE'),
        reason: 'the same usage the words are played with');
    expect(body, contains('CONTENT_TYPE_SPEECH'));
    expect(body, isNot(contains('AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE')));
  });
}
