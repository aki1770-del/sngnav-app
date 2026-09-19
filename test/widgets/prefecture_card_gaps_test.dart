/// The prefecture table at 393 px in IPAGothic, the face the look that found
/// this defect used: values drawn at 11 px or more, 4 px or more between
/// columns. See test/support/prefecture_gap_check.dart for why.
///
/// IPAGothic is found by `render_see_env.dart`, `ipaGothicSearchOrder`, not
/// at a fixed path. On a Debian host it resolves to the same file this test
/// named before 2026-09-19; where IPAGothic is absent the test fails closed,
/// which is the right answer for a test named after its face.
library;

import '../render_see/render_see_env.dart' show FaceSearch;
import '../support/prefecture_gap_check.dart';

void main() =>
    prefectureGapTests(face: 'IPAGothic', search: FaceSearch.ipaGothic);
