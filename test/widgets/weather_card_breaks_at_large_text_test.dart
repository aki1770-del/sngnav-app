/// The weather card at her text sizes, read with IPAGothic, Japanese and
/// English: what is asserted, and why, is at the head of
/// test/support/weather_card_breaks_check.dart.
///
/// One face per file, as the prefecture card's checks do: a family loaded once
/// in a test process is not replaced by a second load of the same name. The
/// English heads are read with Roboto, Android's face, in
/// weather_card_breaks_at_large_text_roboto_test.dart, where 「Observe｜d」 split
/// at 1.5 and IPAGothic's wider Latin did not show it.
library;

import '../render_see/render_see_env.dart' show FaceSearch;
import '../support/weather_card_breaks_check.dart';

void main() => weatherCardBreakTests(
    face: 'IPAGothic', search: FaceSearch.ipaGothic, langs: const ['ja', 'en']);
