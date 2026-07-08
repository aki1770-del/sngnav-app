/// Single source of truth for the app version shown in UI copy.
///
/// WHY this exists: three UI strings used to hardcode package versions
/// ('snow_rendering 0.2.5' etc.) that silently went stale on every
/// `pub upgrade` — a small OPS-062 rot (displayed claims diverging from
/// resolved reality). The rule now: UI copy names PACKAGES, never their
/// versions (the pubspec/lockfile is the version authority); the only
/// version the UI shows is the app's own, from this constant.
///
/// `test/architectural/build_info_matches_pubspec_test.dart` pins this
/// constant to pubspec.yaml — bumping one without the other fails the
/// suite.
library;

/// The app version, mirrored from pubspec.yaml (test-enforced).
const String appVersion = '0.0.5';
