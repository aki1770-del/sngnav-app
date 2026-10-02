// The version gate's pass must reach the output of `flutter build`.
//
// android/app/build.gradle.kts registers assertVersionIdentity, which fails a
// release or profile build whose versionCode differs from pubspec.yaml. The
// flutter tool runs gradle with -q unless it is verbose, and -q drops every
// lifecycle line. The gate printed its pass at lifecycle level, so under
// `flutter build apk --release` a gate that passed looked the same as a gate
// that never ran. Quiet is the level -q keeps.
//
// A test cannot run gradle, so this pins the level in the source. The build
// output before and after the change is in the change's description.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the version gate prints its pass at a level `gradle -q` keeps', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final start = gradle.indexOf('tasks.register("assertVersionIdentity")');
    expect(start, isNot(-1),
        reason: 'the gate was renamed or removed; re-point this test');
    final end = gradle.indexOf('\n}\n', start);
    expect(end, isNot(-1), reason: 'could not find the end of the gate task');
    final task = gradle.substring(start, end);

    final pass =
        RegExp(r'logger\.(\w+)\(\s*"VERSION IDENTITY OK').firstMatch(task);
    expect(pass, isNotNull, reason: 'the gate no longer prints a pass line');
    expect(
      pass!.group(1),
      'quiet',
      reason: 'a pass printed below quiet level is dropped by `gradle -q`, '
          'which is how `flutter build` runs gradle',
    );
  });
}
