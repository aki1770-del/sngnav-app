/// The bundled privacy policy carries no unfilled placeholder.
///
/// WHY (2026-10-10). The policy is bundled into the app (pubspec.yaml, flutter/
/// assets) so a driver with no network can still read it. On 2026-10-09 a
/// change to it was committed with two marked placeholders still in the text,
/// 「⟨この変更を含む最初の版⟩」 and "⟨the first version with this change⟩", left
/// for whoever owned the version to fill. Every store and policy test passed
/// with them in place, so nothing would have stopped them reaching her screen.
/// The page's placeholders are written in ⟨ ⟩ (U+27E8, U+27E9), which nothing
/// else in the policy uses; this test refuses either one anywhere in the
/// bundled asset, comments included, because the asset is also the published
/// page.
///
/// IN ITS OWN FILE ON PURPOSE, as privacy_policy_asset_test.dart explains:
/// `rootBundle.loadString` does not complete under the widget binding's
/// FakeAsync, so this file holds no `testWidgets`.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/privacy_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled policy holds no ⟨ or ⟩ placeholder mark', () async {
    final raw = await rootBundle.loadString(kPrivacyPolicyAsset);
    expect(raw.length, greaterThan(2000),
        reason: 'the whole bundled document was read, not an empty asset');
    final marks = <String>[];
    final lines = raw.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      for (final mark in const ['⟨', '⟩']) {
        var at = line.indexOf(mark);
        while (at >= 0) {
          final from = at - 20 < 0 ? 0 : at - 20;
          final to = at + 20 > line.length ? line.length : at + 20;
          marks.add('$kPrivacyPolicyAsset:${i + 1} $mark …${line.substring(from, to)}…');
          at = line.indexOf(mark, at + 1);
        }
      }
    }
    expect(marks, isEmpty,
        reason: 'an unfilled placeholder would be shown to her in the app '
            'and published on the page; fill it before this ships');
  });
}
