/// The bundled privacy policy asset, read through the real bundle.
///
/// IN ITS OWN FILE ON PURPOSE. `rootBundle.loadString` does not complete under
/// the widget binding's FakeAsync: in a file that also contains `testWidgets`,
/// this check hung until the 30-second timeout, and wrapping it in `runAsync`
/// hung for ten minutes. With no widget binding installed it simply works.
/// The rendering half lives in
/// test/widgets/location_consent_act_and_privacy_surface_test.dart.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/privacy_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the asset is declared, bundled, and is the whole document', () async {
    final shown = await loadPrivacyPolicy();
    expect(shown, isNotNull,
        reason: 'declared in pubspec flutter/assets as '
            '$kPrivacyPolicyAsset — Play requires a privacy policy link or '
            'TEXT within the app itself, unconditionally');
    expect(shown!, contains('プライバシーポリシー'));
    expect(shown, contains('Privacy Policy'),
        reason: 'the document carries its full English translation');
    expect(shown.length, greaterThan(2000),
        reason: 'the whole document, not a fragment');
  });

  test('our authoring notes are not shown to her', () async {
    final shown = (await loadPrivacyPolicy())!;
    expect(shown, isNot(contains('<!--')));
    expect(shown, isNot(contains('OPS-062')),
        reason: 'an internal rule citation, inside a comment block');
    expect(shown, isNot(contains('AndroidManifest.xml')),
        reason: 'provenance for the permission table, addressed to us');
  });

  test('the asset is THE published document, not a copy that can drift', () {
    expect(kPrivacyPolicyAsset, 'docs/store/privacy_policy_ja.md',
        reason: 'the app bundles the source file itself, so the text she '
            'reads and the text on the published page are one file');
  });
}
