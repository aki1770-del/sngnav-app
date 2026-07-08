// Pins lib/build_info.dart's appVersion to pubspec.yaml so the UI can
// never display a stale app version (the OPS-062 rot this replaces:
// three UI strings hardcoding package versions that silently diverged
// from the resolved tree on upgrade).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/build_info.dart';

void main() {
  test('appVersion constant matches pubspec.yaml version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*([^\s+]+)', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml must declare a version');
    expect(
      appVersion,
      match!.group(1),
      reason: 'Bump lib/build_info.dart appVersion together with '
          'pubspec.yaml — the footer displays it.',
    );
  });

  test('no package-version literals hardcoded in UI copy', () {
    // The rule: UI copy names packages, never their versions. This guard
    // greps main.dart for the "name X.Y.Z" shape that rotted before.
    final main = File('lib/main.dart').readAsStringSync();
    final offenders = RegExp(
      r"(navigation_safety_core|navigation_safety|voice_guidance|"
      r"driving_conditions|offline_tiles|snow_rendering|map_viewport_bloc|"
      r"routing_engine)\s+\d+\.\d+\.\d+",
    ).allMatches(main).map((m) => m.group(0)).toList();
    expect(
      offenders,
      isEmpty,
      reason: 'UI copy must not hardcode package versions (they go stale '
          'on pub upgrade); found: $offenders',
    );
  });
}
