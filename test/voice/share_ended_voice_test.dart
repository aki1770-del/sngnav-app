/// The stop confirmation's words, its bundled clip, and its vibration.
///
/// Why, written before the act (2026-10-05). When a drive ends at 停止 she
/// hears 「共有を終了しました。現在地の警告も止まりました。」 and feels one long pulse
/// (test/widgets/stop_confirmation_test.dart and the drive-end group in
/// drive_back_is_never_a_silent_end_test.dart hold when). This file holds
/// what, four ways a later change could break it without any of those failing:
///  - the clip: the line must play from the bundled mouth, or it is silent on
///    a phone with no Japanese voice, offline;
///  - the opening: its first sounds must start no line the app speaks, or its
///    first half-second can be heard as a warning;
///  - the scope word: 現在地の警告 / "warnings for your location", because a
///    whiteout is still told at the next refresh after 停止;
///  - the vibration: one pulse no warning uses, because a confirmation felt as
///    a warning teaches her warnings can be ignored.
///
/// The words are the HMI seat's
/// (outputs/hie/r136_…/PART1_STOP_CONFIRMATION_WORDS.md).
library;

import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:localization_fallback/localization_fallback.dart'
    show LocalizationMode;
import 'package:navigation_safety_core/navigation_safety_core.dart'
    show AlertSeverity, AlertExplainer, DriverProfile, RoadSurfaceCondition;
import 'package:navigation_safety_enums/navigation_safety_enums.dart'
    show HapticCuePattern;
import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show DriveAction;
import 'package:routing_engine/routing_engine.dart' show RouteManeuver;
import 'package:snow_rendering/snow_rendering.dart' as snow_rendering;
import 'package:sngnav_app/actuators/alert_announcer.dart';
import 'package:sngnav_app/actuators/hardened_haptic_channel.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/drive_hud_localizer.dart';
import 'package:sngnav_app/services/invisible_ice_watch.dart'
    show staleInvisibleBlackIceSpokenText, subZeroFrozenSpokenText;
import 'package:sngnav_app/services/maneuver_narration.dart';
import 'package:sngnav_app/services/staleness_policy.dart'
    show kConditionsUnknownEnSpokenText;
import 'package:sngnav_app/services/turmoil_watch.dart';
import 'package:sngnav_app/voice/offline_safety_voice.dart';

import '../support/fake_alert_actuators.dart';
import 'runtime_emissions.dart';

const _ja = AppL10n(Locale('ja'));
const _en = AppL10n(Locale('en'));

void main() {
  group('the clip: heard offline', () {
    test('the catalog holds the line the app speaks, byte for byte', () {
      expect(kOfflineSafetyVoiceJa['share_ended'], _ja.shareEndedSpokenLine,
          reason: 'the line is its own lookup key: a byte changed in the app '
              'or the catalog and the clip is never found');
      expect(OfflineSafetyVoice.assetFor(_ja.shareEndedSpokenLine),
          'assets/audio/ja/share_ended.wav');
      expect(File('assets/audio/ja/share_ended.wav').lengthSync(),
          greaterThan(0),
          reason: 'the clip is rendered (tool/render_offline_voice.sh)');
    });

    test('the emissions census counts it among what the app speaks', () {
      expect(emittableSafetyStaticJa(), contains(_ja.shareEndedSpokenLine));
    });
  });

  group('the words', () {
    test(
        'the scope word stays: the warnings that stop are those for her '
        'location', () {
      const why = 'W2b (whiteout_family_audit_vectors_dialog_test.dart) holds '
          'that a whiteout is still told at the next refresh after 停止. A '
          'flat "the warnings have stopped" would be contradicted ten minutes '
          'later, in the same voice.';
      expect(_ja.shareEndedSpokenLine, contains('現在地の警告'), reason: why);
      expect(_en.shareEndedSpokenLine, contains('warnings for your location'),
          reason: why);
    });

    test('the line names her own act, as the card does', () {
      expect(_ja.shareEndedSpokenLine, startsWith('共有'));
      expect(_ja.locationNotShared, contains('共有'));
      expect(_en.shareEndedSpokenLine, startsWith('Sharing'));
      expect(_en.locationNotShared.toLowerCase(), contains('shar'));
    });

    test(
        'English: its first word opens no English line the app speaks, so '
        'it is not heard as the start of a warning', () {
      final first = _firstWord(_en.shareEndedSpokenLine);
      final clashes = [
        for (final l in _englishLines())
          if (l != _en.shareEndedSpokenLine && _firstWord(l) == first) l,
      ];
      expect(clashes, isEmpty, reason: 'lines opening with "$first"');
    });

    test(
        'Japanese: its opening shares no sound with the opening of any line '
        'the app speaks (open_jtalk phonemes)', () {
      final jtalk = _OpenJtalk.find();
      if (jtalk == null) {
        markTestSkipped('open_jtalk, its dictionary or an HTS voice is not '
            'on this host: the opening is NOT checked here. Re-run where '
            'open_jtalk is installed.');
        return;
      }
      final mine = jtalk.phonemes(_ja.shareEndedSpokenLine);
      expect(mine, isNotEmpty, reason: 'control: open_jtalk read the line');
      final population = <String>{
        ...emittableSafetyStaticJa(),
        ...emittableNavStaticJa(),
        for (var h = 0; h < 24; h++)
          staleInvisibleBlackIceSpokenText(hourJst: h, ja: true),
      }..remove(_ja.shareEndedSpokenLine);
      expect(population.length, greaterThan(100),
          reason: 'control: the population is the app\'s lines');
      final shared = <String, int>{};
      for (final l in population) {
        final n = _commonPrefix(mine, jtalk.phonemes(l));
        if (n > 0) shared[l] = n;
      }
      expect(shared, isEmpty,
          reason: 'opening ${mine.take(6).join(' ')} shares a sound with '
              'these lines\' openings (count of shared phonemes)');
    });
  });

  group('the vibration: one pulse no warning uses', () {
    List<int> on(List<int> wave) =>
        [for (var i = 1; i < wave.length; i += 2) wave[i]];

    test('it differs from both warnings by count and by length', () {
      final ended = on(kEndedWaveformMs);
      final warning = on(waveformFor(HapticCuePattern.warning));
      final critical = on(waveformFor(HapticCuePattern.critical));
      expect(ended, hasLength(1));
      expect(ended.length, isNot(warning.length));
      expect(ended.length, isNot(critical.length));
      expect(ended.single, greaterThan([...warning, ...critical].reduce(
          (a, b) => a > b ? a : b)),
          reason: 'longer than any warning pulse');
    });

    test('the announcer gives the ended cue, never a warning\'s, and still '
        'speaks', () async {
      final a = FakeAlertActuators();
      await AlertAnnouncer(actuators: a).announce(
        severity: AlertSeverity.warning,
        text: _ja.shareEndedSpokenLine,
        localeTag: 'ja',
        cue: AnnounceCue.ended,
      );
      expect(a.felt, ['ended']);
      expect(a.haptics, isEmpty);
      expect([for (final l in a.spoken) l.text], [_ja.shareEndedSpokenLine]);
    });

    test('the channel fires that waveform and reports it by name', () async {
      final driver = _RecordingDriver();
      final channel = HardenedHapticChannel(driver: driver);
      expect(await channel.fireEnded(), HapticDelivery.delivered);
      expect(driver.waves, [kEndedWaveformMs]);
    });
  });
}

String _firstWord(String line) =>
    RegExp(r'[A-Za-z]+').firstMatch(line)!.group(0)!.toLowerCase();

int _commonPrefix(List<String> a, List<String> b) {
  var n = 0;
  while (n < a.length && n < b.length && a[n] == b[n]) {
    n++;
  }
  return n;
}

/// The English lines the app can speak, built by calling its builders with
/// English. Bound: unlike the Japanese census, no test checks that this set is
/// complete.
Set<String> _englishLines() {
  const hud = DriveHudLocalizer();
  final out = <String>{
    for (final a in DriveAction.values) hud.spokenGuidance(a, 'en'),
    hud.testValueSpokenPrefix('en'),
    _en.channelCheckSpokenLine,
    _en.shareEndedSpokenLine,
    snow_rendering.invisibleBlackIceAnnouncement.enSpokenText,
    subZeroFrozenSpokenText(ja: false),
    kConditionsUnknownEnSpokenText,
    for (var h = 0; h < 24; h++)
      staleInvisibleBlackIceSpokenText(hourJst: h, ja: false),
  }..removeWhere((s) => s.isEmpty);
  for (final rain in TurmoilChannel.values) {
    for (final wind in TurmoilChannel.values) {
      final s = turmoilSpokenText(
        TurmoilWatchState(
          rain: rain,
          wind: wind,
          precipitation10mMm: null,
          windMetersPerSecond: null,
        ),
        ja: false,
      );
      if (s != null) out.add(s);
    }
  }
  for (final c in RoadSurfaceCondition.values) {
    for (final p in DriverProfile.values) {
      final e = AlertExplainer.forConditionAndProfile(c, p);
      if (e.localeTag.toLowerCase().startsWith('en')) out.add(e.action);
    }
  }
  const narrator = ManeuverNarrator();
  for (final t in const ['depart', 'arrive', 'straight', 'left', 'right',
      'slight_left', 'slight_right', 'sharp_left', 'sharp_right', 'uturn',
      'merge', 'roundabout', 'ramp_left', 'ramp_right', 'unknown']) {
    for (final mode in [LocalizationMode.gpsTrusted, LocalizationMode.gpsSuspect]) {
      for (final icy in [false, true]) {
        final d = narrator.decide(
          maneuver: RouteManeuver(
            index: 0,
            instruction: '',
            type: t,
            lengthKm: 0,
            timeSeconds: 0,
            position: const LatLng(39.72, 140.10),
          ),
          mode: mode,
          icyTurn: icy,
          localeTag: 'en',
        );
        if (d.shouldAnnounce && d.text.isNotEmpty) out.add(d.text);
      }
    }
  }
  return out;
}

class _RecordingDriver implements HapticDriver {
  final waves = <List<int>>[];
  @override
  Future<bool> hasVibrator() async => true;
  @override
  Future<void> vibrate(List<int> waveformMs) async => waves.add(waveformMs);
}

/// open_jtalk, found the way the repo's own phoneme oracle finds it
/// (offline_voice_readable_phonemes_test.dart), at the catalog's settings.
class _OpenJtalk {
  _OpenJtalk(this.bin, this.dict, this.voice);
  final String bin;
  final String dict;
  final String voice;
  final Map<String, List<String>> _cache = {};

  static _OpenJtalk? find() {
    String? bin;
    for (final p in const ['/usr/bin/open_jtalk', '/usr/local/bin/open_jtalk']) {
      if (File(p).existsSync()) bin = p;
    }
    const dictRoot = '/var/lib/mecab/dic/open-jtalk';
    const voiceRoot = '/usr/share/hts-voice';
    if (bin == null ||
        !Directory(dictRoot).existsSync() ||
        !Directory(voiceRoot).existsSync()) {
      return null;
    }
    final dicts = Directory(dictRoot)
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path)
        .toList()
      ..sort();
    final voices = Directory(voiceRoot)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.htsvoice'))
        .map((f) => f.path)
        .toList()
      ..sort();
    if (dicts.isEmpty || voices.isEmpty) return null;
    return _OpenJtalk(bin, dicts.last, voices.first);
  }

  /// Non-silence phonemes of [text], from the first `[Output label]` block.
  List<String> phonemes(String text) => _cache.putIfAbsent(text, () {
        final tmp = Directory.systemTemp.createTempSync('share_ended_oracle');
        try {
          final trace = '${tmp.path}/trace.txt';
          final inFile = File('${tmp.path}/in.txt')..writeAsStringSync(text);
          Process.runSync('bash', [
            '-lc',
            '${_sq(bin)} -x ${_sq(dict)} -m ${_sq(voice)} -r 0.9 '
                '-ot ${_sq(trace)} -ow ${_sq('${tmp.path}/o.wav')} '
                '< ${_sq(inFile.path)}'
          ]);
          final labs = File(trace).readAsStringSync();
          final block = RegExp(r'\[Output label\](.*?)(?:\n\[|\Z)',
                      dotAll: true)
                  .firstMatch(labs)
                  ?.group(1) ??
              labs;
          return RegExp(r'-([a-zA-Z]+)\+')
              .allMatches(block)
              .map((m) => m.group(1)!)
              .where((p) => p != 'sil' && p != 'pau')
              .toList();
        } finally {
          tmp.deleteSync(recursive: true);
        }
      });

  static String _sq(String s) => "'${s.replaceAll("'", r"'\''")}'";
}
