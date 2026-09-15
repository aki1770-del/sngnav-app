/// The prefecture observations card at phone width with Roboto, Android's
/// face for its Latin values (Flutter's own copy of the file). The same checks
/// as prefecture_card_floor_and_units_test.dart, which reads it with
/// IPAGothic; see there for why.
library;

import '../support/prefecture_card_check.dart';

void main() => prefectureCardTests(
  face: 'Roboto',
  path:
      '/home/komada/flutter/bin/cache/artifacts/material_fonts/'
      'Roboto-Regular.ttf',
);
