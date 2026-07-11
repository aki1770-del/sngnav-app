/// A1 pre-drive voice-lane readiness check.
///
/// Answers ONE question before HER drive: *if she loses signal in the
/// mountains, can this phone still speak Japanese?* Android TTS voices are
/// per-voice network-bound; a device can pass every in-signal test and go
/// silent exactly where the warning matters most (the no-signal pass where
/// GPS + Maps die too — the compound-failure scenario).
///
/// Voice-map shape — verified against the REAL flutter_tts 4.2.5 source
/// (clone /home/komada/work/flutter_tts-serve):
/// - `getVoices` (lib/flutter_tts.dart:519-526) returns a `List` of maps.
/// - Android builds each map in FlutterTtsPlugin.kt:618-626
///   (`readVoiceProperties`): keys `name`, `locale`
///   (Java `Locale.toLanguageTag()`, e.g. `"ja-JP"`), `quality`, `latency`,
///   `network_required`, `features`. `network_required` is the STRING
///   `"1"` when `voice.isNetworkConnectionRequired` else `"0"` (kt:623) —
///   never a bool.
/// - On engine failure Android replies null (kt:553-566 catches the NPE).
/// - iOS maps have NO `network_required` key (flutter_tts.dart:521 — iOS
///   adds quality/gender/identifier instead); a missing key is treated as
///   offline-capable here, because a FALSE "voice not installed" warning
///   off-Android is the failure this surface must never produce.
///
/// Honest-null posture (matches the rest of the app): anything we cannot
/// read — non-mobile platform, test binding, plugin error, empty/absent
/// voice list — is [VoiceLaneVerdict.unknown], and the pre-drive surface
/// shows NOTHING for unknown. Never a fabricated warning off-device.
library;

import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import '../actuators/mobile_alert_actuators.dart' show isMobileActuatorPlatform;

/// Pre-drive verdict on the Japanese voice lane.
enum VoiceLaneVerdict {
  /// At least one ja voice is installed that does NOT require the network:
  /// the spoken lane survives a signal blackout.
  offlineJaReady,

  /// ja voices exist but every one requires the network: the lane goes
  /// SILENT exactly in the no-signal compound-failure case. Cautioned.
  jaNetworkOnly,

  /// The engine reports voices, none of them Japanese. Cautioned.
  noJaVoice,

  /// Could not read the voice list (non-mobile, test binding, engine
  /// error, empty list). The surface shows nothing — honest unknown.
  unknown,
}

/// Injectable voices source. Production wraps `FlutterTts().getVoices`;
/// tests supply canned lists in the real map shape.
typedef VoicesProvider = Future<Object?> Function();

/// Reads the voice list and renders the [VoiceLaneVerdict].
///
/// With no [voicesProvider], a real read is attempted ONLY on a genuine
/// android/ios target ([isMobileActuatorPlatform] — which is false under
/// the flutter_test binding); everywhere else the verdict is [unknown]
/// without ever constructing the plugin.
Future<VoiceLaneVerdict> readVoiceLaneReadiness({
  VoicesProvider? voicesProvider,
  Duration timeout = const Duration(seconds: 10),
}) async {
  var provider = voicesProvider;
  if (provider == null) {
    if (!isMobileActuatorPlatform) return VoiceLaneVerdict.unknown;
    final tts = FlutterTts();
    provider = () async => tts.getVoices;
  }

  Object? raw;
  try {
    raw = await provider().timeout(timeout);
  } catch (_) {
    // MissingPluginException, platform fault, or timeout: unreadable.
    return VoiceLaneVerdict.unknown;
  }
  if (raw is! List) return VoiceLaneVerdict.unknown;

  var sawAnyVoice = false;
  var sawJa = false;
  for (final entry in raw) {
    if (entry is! Map) continue;
    final locale = entry['locale']?.toString() ?? '';
    if (locale.isEmpty) continue;
    sawAnyVoice = true;
    // BCP-47 primary subtag ("ja-JP" → "ja"); tolerate "_" separators too.
    final language = locale.split(RegExp('[-_]')).first.toLowerCase();
    if (language != 'ja') continue;
    sawJa = true;
    final networkRequired = entry['network_required']?.toString();
    // "0" = offline-capable (FlutterTtsPlugin.kt:623). A missing key (iOS
    // shape) counts as offline-capable — never false-warn, see library doc.
    if (networkRequired == null || networkRequired == '0') {
      return VoiceLaneVerdict.offlineJaReady;
    }
  }
  if (sawJa) return VoiceLaneVerdict.jaNetworkOnly;
  if (sawAnyVoice) return VoiceLaneVerdict.noJaVoice;
  // Empty (or all-unreadable) list: a healthy engine always reports voices,
  // so this is an unreadable state, not a proven absence — unknown.
  return VoiceLaneVerdict.unknown;
}
