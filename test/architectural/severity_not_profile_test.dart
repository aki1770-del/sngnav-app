/// Architectural test — the load-bearing invariant for Slice 4.
///
/// AlertSurfaceController is the only place severity-tier classification
/// happens. The widget tree (lib/widgets/) and screens (none yet) MUST
/// NOT branch on DriverProfile or DriverState. The differentiation lives
/// upstream in the threshold values carried by NavigationSafetyConfig;
/// the widgets render the same severity output identically for every
/// driver.
///
/// Two narrow, deliberate exceptions are allowed in lib/widgets/ — the
/// state chip rail and the profile picker themselves — because they are
/// the user-facing input surfaces for those values, not consumers of
/// them. This test enforces a strict allowlist of files where the names
/// may appear under lib/widgets/.
///
/// AlertSurfaceController is allowed to import NavigationSafetyConfig
/// (it is constructed from one). It is NOT allowed to import
/// DriverProfile or DriverState; this test asserts that.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _widgetAllowlist = <String>{
  // The state chip rail IS the input surface for DriverState, so it
  // unavoidably names the type. It does NOT branch on the value (the
  // visual treatment iterates DriverState.values uniformly).
  'lib/widgets/driver_state_chip_rail.dart',
  // The profile picker IS the input surface for DriverProfile. Same
  // structure — iterates DriverProfile.values uniformly.
  'lib/widgets/driver_profile_picker.dart',
};

bool _mentions(String content, String identifier) {
  // Match identifier as a whole-word reference. The simple substring
  // check is sufficient because Dart identifiers are unique tokens
  // and the names DriverProfile / DriverState do not appear inside
  // unrelated strings in this codebase.
  return content.contains(identifier);
}

Future<List<File>> _dartFilesUnder(Directory dir) async {
  if (!dir.existsSync()) return const [];
  final out = <File>[];
  await for (final entry in dir.list(recursive: true, followLinks: false)) {
    if (entry is File && entry.path.endsWith('.dart')) {
      out.add(entry);
    }
  }
  return out;
}

void main() {
  test('lib/widgets/ does not branch on DriverProfile or DriverState '
      '(allowlist exempts the input-surface widgets)', () async {
    final files = await _dartFilesUnder(Directory('lib/widgets'));
    final offenders = <String>[];
    for (final f in files) {
      final relative = f.path.replaceFirst('${Directory.current.path}/', '');
      if (_widgetAllowlist.contains(relative)) continue;
      final content = f.readAsStringSync();
      if (_mentions(content, 'DriverProfile') ||
          _mentions(content, 'DriverState')) {
        offenders.add(relative);
      }
    }
    expect(offenders, isEmpty,
        reason: 'These widget files reference DriverProfile or DriverState '
            'outside the input-surface allowlist: $offenders');
  });

  test('lib/screens/ does not branch on DriverProfile or DriverState',
      () async {
    final files = await _dartFilesUnder(Directory('lib/screens'));
    final offenders = <String>[];
    for (final f in files) {
      final relative = f.path.replaceFirst('${Directory.current.path}/', '');
      final content = f.readAsStringSync();
      if (_mentions(content, 'DriverProfile') ||
          _mentions(content, 'DriverState')) {
        offenders.add(relative);
      }
    }
    expect(offenders, isEmpty,
        reason: 'Screens must consume NavigationSafetyConfig only: $offenders');
  });

  test('AlertSurfaceController source does not import DriverProfile or DriverState',
      () {
    final controller =
        File('lib/services/alert_surface_controller.dart').readAsStringSync();
    // The dartdoc names the types in prose to explain the ban; we
    // assert on the import line and on type usage in code, not on the
    // doc comments. Strip block + line comments and then check.
    final code = controller
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('///'))
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(code.contains('DriverProfile'), isFalse,
        reason:
            'AlertSurfaceController must not branch on DriverProfile in code.');
    expect(code.contains('DriverState'), isFalse,
        reason:
            'AlertSurfaceController must not branch on DriverState in code.');
  });
}
