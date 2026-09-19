/// The whole rendered words of the two test-value lines, per
/// locale. Literals, so a change of words is a red, not a silent pass.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';

void main() {
  test('the card line, ja and en', () {
    expect(const AppL10n(Locale('ja')).driveHudTestValueInForce,
        'テスト値を使った表示です（測定ではありません）');
    expect(const AppL10n(Locale('en')).driveHudTestValueInForce,
        'This card uses a test value, not a measurement.');
  });

  test('the ice mark line, ja and en', () {
    expect(const AppL10n(Locale('ja')).maneuverTestRoadConditionInForce,
        '凍結の表示はテスト値です（路面は測定していません）');
    expect(const AppL10n(Locale('en')).maneuverTestRoadConditionInForce,
        'The ice mark is a test value; the road was not measured.');
  });
}
