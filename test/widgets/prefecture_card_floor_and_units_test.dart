/// The prefecture observations card at phone width: the station failure line
/// and the descriptors read above the floor, and each value keeps its unit on
/// its line.
///
/// Why, written before the act (2026-09-15). Seen on b0f74e7 at 393 px with
/// real glyphs, two of five stations failed and three answered:
/// * the failure line under a failed station was red.shade700 at 10 px on the
///   card, 4.51:1, at the 4.5:1 floor (the source line under the table is
///   11 px);
/// * the descriptors (北・海沿い, 市街地, 中央内陸) were grey.shade600 at 10 px,
///   4.17:1, under the floor, while the card's other secondary lines use
///   grey.shade700;
/// * "7.5 m/s" and "-2.1 °C" broke across two lines, the unit split from its
///   value.
/// Now: the failure line is red.shade900 at 11 px; the descriptors are
/// grey.shade700; a value and its unit are laid out on one line and scaled
/// down only when the cell is narrower than that line.
///
/// Read with two faces, one per file (a face loaded once in a test process is
/// not replaced): IPAGothic, the face the look at her page used, here; Roboto,
/// Android's face for these Latin values, in
/// prefecture_card_floor_and_units_roboto_test.dart. Each value's drawn scale
/// is printed. Bound: neither face is measured on a phone.
library;

import '../support/prefecture_card_check.dart';

void main() => prefectureCardTests(
  face: 'IPAGothic',
  path: '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf',
);
