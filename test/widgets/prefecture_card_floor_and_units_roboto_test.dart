/// The prefecture observations card at phone width with Roboto, Android's
/// face for its Latin values (Flutter's own copy of the file). The same checks
/// as prefecture_card_floor_and_units_test.dart, which reads it with
/// IPAGothic; see there for why.
///
/// Roboto is found inside the Flutter SDK running this test, not at a fixed
/// path: this file named a path in one developer's home directory (`$HOME/flutter/...`) until 2026-09-18, which is
/// why it failed on the first CI run (35300438549). Search order in
/// `render_see_env.dart`, `robotoSearchOrder`.
library;

import '../render_see/render_see_env.dart' show FaceSearch;
import '../support/prefecture_card_check.dart';

void main() => prefectureCardTests(face: 'Roboto', search: FaceSearch.roboto);
