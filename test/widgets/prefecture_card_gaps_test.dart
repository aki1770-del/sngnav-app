/// The prefecture table at 393 px in IPAGothic, the face HIE's look used:
/// values drawn at 11 px or more, 4 px or more between columns. See
/// test/support/prefecture_gap_check.dart for why.
library;

import '../support/prefecture_gap_check.dart';

void main() => prefectureGapTests(
  face: 'IPAGothic',
  path: '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf',
);
