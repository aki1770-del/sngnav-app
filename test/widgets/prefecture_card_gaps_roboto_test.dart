/// The prefecture table at 393 px in Roboto, Android's face for these Latin
/// values (Flutter's own copy of the file). See
/// test/support/prefecture_gap_check.dart for why.
///
/// Roboto is found inside the Flutter SDK running this test, not at a fixed
/// path. Until 2026-09-19 this file named a path under one developer's home
/// directory, which no CI runner has, so the guard failed closed on every
/// runner (run 35437798281) while passing on that one machine. Search order in
/// `render_see_env.dart`, `robotoSearchOrder`.
library;

import '../render_see/render_see_env.dart' show FaceSearch;
import '../support/prefecture_gap_check.dart';

void main() => prefectureGapTests(face: 'Roboto', search: FaceSearch.roboto);
