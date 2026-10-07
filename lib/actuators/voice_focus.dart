/// Audio focus for the phone's own voice (the flutter_tts lane), asked for by
/// the app as NAVIGATION GUIDANCE, the same request the bundled voice makes.
///
/// WHY (2026-10-06, a safety review and a dignity review). flutter_tts 4.2.5
/// builds its focus request with no audio attributes
/// (FlutterTtsPlugin.kt:795-806), so the system reads it as MEDIA, while the
/// engine plays the words as navigation guidance. Read on an Android 14
/// emulator: the app's request carried AA=USAGE_MEDIA. The system decides
/// ducking and denial from the request's attributes, so during a call a
/// driver whose language is not the bundled one had a voice that behaved as
/// music, while the bundled voice behaves as navigation guidance. Every driver
/// is owed the same lane.
///
/// So the app turns the plugin's own request off (speak with focus: false) and
/// asks through `sngnav/voice_focus` (MainActivity.kt), with
/// USAGE_ASSISTANCE_NAVIGATION_GUIDANCE and TRANSIENT_MAY_DUCK, before each
/// utterance, and gives it back after. A local override of the plugin's
/// behaviour, not a fork: the locked plugin is unchanged.
///
/// The request's answer is not waited for and does not gate speech: a refused
/// focus does not stop a safety line (the bundled voice's rule, MainActivity).
library;

import 'dart:async';

import 'package:flutter/services.dart';

/// Asks for, and gives back, audio focus for one utterance.
abstract class VoiceFocus {
  /// Asks for transient, duckable focus as navigation guidance. Never throws,
  /// never waits.
  void request();

  /// Gives back what [request] asked for. Never throws, never waits.
  void abandon();
}

/// [VoiceFocus] through the app's own channel to MainActivity.
class PlatformVoiceFocus implements VoiceFocus {
  const PlatformVoiceFocus();

  static const MethodChannel channel = MethodChannel('sngnav/voice_focus');

  @override
  void request() => _send('request');

  @override
  void abandon() => _send('abandon');

  /// Fire and forget. A platform without the channel (desktop, the IVI build,
  /// tests) answers with an error, which is dropped: there is no focus to ask
  /// for there. Under the widget-test binding an unmocked channel may never
  /// answer; nothing waits on it.
  static void _send(String method) {
    unawaited(
      channel.invokeMethod<Object?>(method).then<void>((_) {}, onError: (_) {}),
    );
  }
}
