/// The weather card at her text sizes, read with Roboto, Android's face for
/// Latin, English only (Roboto draws no Japanese). What is asserted, and why,
/// is at the head of test/support/weather_card_breaks_check.dart.
library;

import '../render_see/render_see_env.dart' show FaceSearch;
import '../support/weather_card_breaks_check.dart';

void main() => weatherCardBreakTests(
    face: 'Roboto', search: FaceSearch.roboto, langs: const ['en']);
