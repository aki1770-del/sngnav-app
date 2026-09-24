/// Which build is this, actually — read from the ARTIFACT, never hand-written.
///
/// WHY this exists (V15, poka-yoke tier 1 — *cannot be done wrong*):
/// `lib/build_info.dart` carries `const String appVersion = '0.0.5'`, a
/// hand-written mirror of pubspec.yaml. It is shown in HER footer and stamped
/// into every shared error log and drive diary. Two defects ride on it:
///
///  1. It is a COMPILE-TIME constant of the source tree, not a property of the
///     installed artifact. A dev `flutter run` and a release APK report the
///     same string. It is a claim about the tree, presented as a fact about
///     the build on her phone.
///  2. It carries only the versionNAME. `test/architectural/
///     build_info_matches_pubspec_test.dart` pins it with
///     `RegExp(r'^version:\s*([^\s+]+)')` — `[^\s+]` excludes `+`, so the
///     guard captures `0.0.5` from `version: 0.0.5+2` and the build number is
///     checked by nothing and displayed nowhere. BIS measured the cost of that
///     on 2026-09-23: versionCode 9 carried two distinct byte-sets and
///     versionCode 2 carried six. A tester's shared log naming only `0.0.5`
///     cannot say which of them she is running.
///
/// [BuildIdentity.fromPlatform] instead asks Android's PackageManager what the
/// INSTALLED package says about itself. The number cannot drift from the
/// artifact because it IS the artifact's.
///
/// THE THIRD STATE IS LOAD-BEARING (AAE-6). When the platform read fails this
/// returns [BuildIdentity.unknown] and NEVER substitutes [appVersion]. Folding
/// "I could not read my own identity" into "I am 0.0.5" is precisely the
/// provenance loss AAE-6 exists to prevent: once absence has been reduced to a
/// value, no downstream surface can recover it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../build_info.dart';

/// The running build's own identity, as the installed artifact reports it.
@immutable
class BuildIdentity {
  const BuildIdentity({
    required this.versionName,
    required this.versionCode,
    required this.packageName,
    this.selfSha256,
    this.gitSha,
    this.artifactCount,
  });

  /// The honest third state: the platform did not answer. Distinct from any
  /// real build, and never silently replaced by the compiled-in constant.
  const BuildIdentity.unknown()
      : versionName = null,
        versionCode = null,
        packageName = null,
        selfSha256 = null,
        gitSha = null,
        artifactCount = null;

  /// `versionName` from the installed package (e.g. `0.0.5`).
  final String? versionName;

  /// `versionCode` from the installed package (e.g. `2`). This is the integer
  /// whose whole job is to name one artifact, and the value an update check
  /// must compare on — never the versionName, which is not ordered and which
  /// ten different artifacts have shared.
  final int? versionCode;

  /// The applicationId the package is installed under.
  final String? packageName;

  /// BIS A-1 — SHA-256 of the installed APK's own bytes, from the native
  /// `sngnav/build_identity` channel. THE ONLY VALUE HERE THAT NAMES ONE
  /// BUILD: BIS measured seven distinct release-signed byte-sets at
  /// versionCode 2 on 2026-09-24, all under the same signer.
  final String? selfSha256;

  /// BIS A-2 — the commit gradle stamped into the manifest, read back through
  /// PackageManager. `UNKNOWN` when git was unavailable at build time;
  /// `<sha>-dirty` when the tree was not clean.
  final String? gitSha;

  /// How many APK files were hashed (base + splits). 1 on a plain APK.
  final int? artifactCount;

  /// First 12 hex of the self-hash, as BIS specified for display.
  String? get shortSelfSha => selfSha256 == null
      ? null
      : (selfSha256!.length >= 12 ? selfSha256!.substring(0, 12) : selfSha256);

  /// True only when the artifact answered with a usable versionCode.
  bool get isKnown => versionCode != null;

  /// V15 tier 2 — *detected instantly*. On a correctly built artifact the
  /// compiled-in [appVersion] and the artifact's own versionName are the same
  /// string, because gradle derives versionName from the same pubspec line the
  /// architectural test pins the constant to. When they DISAGREE, the
  /// hand-written mirror has gone stale against the build that actually
  /// shipped — the defect `build_info.dart` cannot detect about itself.
  ///
  /// Null when unknown: an unread identity is not evidence of agreement.
  bool? get agreesWithCompiledVersionName =>
      isKnown ? versionName == appVersion : null;

  /// THE IDENTITY TRIPLE. BIS ruled the version pair alone must NOT be
  /// presented as identity — "you are running build 2" is false, because 2
  /// names seven artifacts. So every surface shows
  /// `0.0.2 (10) · 7129d4a4bb1b · c1b2c28`, and falls back to the pair ONLY
  /// while labelled as not-an-identity by [isFullyIdentified].
  String get display {
    if (!isKnown) return 'unknown';
    final parts = <String>['$versionName ($versionCode)'];
    if (shortSelfSha != null) parts.add(shortSelfSha!);
    if (gitSha != null && gitSha != 'UNKNOWN') parts.add(gitSha!);
    return parts.join(' · ');
  }

  /// True only when the self-hash answered. When false the build is
  /// UNIDENTIFIED: the version pair is known but does not name one artifact,
  /// and no surface may present it as though it did (BIS §3.2, §3.6).
  bool get isFullyIdentified => isKnown && selfSha256 != null;

  /// Reads the identity from the installed package. NEVER THROWS — a build
  /// that cannot read its own name must still drive HER home, so every failure
  /// resolves to [BuildIdentity.unknown] (the `error_log.dart` house idiom).
  /// The native channel supplying BIS's two required alongside-values.
  static const MethodChannel _channel = MethodChannel('sngnav/build_identity');

  static Future<BuildIdentity> fromPlatform() async {
    try {
      final info = await PackageInfo.fromPlatform();
      // buildNumber is a String on the platform interface; on Android it is
      // the APK's versionCode. A non-integer (or empty, as on some desktop
      // targets) is NOT a build identity and must not be coerced to 0 — 0
      // would compare as "older than everything" and make the app announce an
      // update to every holder whose platform simply does not report one.
      final code = int.tryParse(info.buildNumber.trim());
      if (code == null) return const BuildIdentity.unknown();
      // BIS P2: versionName fails to the EMPTY STRING on API 33+, not to an
      // error. An empty name is UNIDENTIFIED, never rendered blank.
      final name = info.version.trim();
      if (name.isEmpty) return const BuildIdentity.unknown();

      // A-1 + A-2. Best-effort and separately caught: if the native side is
      // absent (desktop, a test harness, an older build of the app) we still
      // have the pair, and [isFullyIdentified] says honestly that we do not
      // have an identity.
      String? selfSha;
      String? gitSha;
      int? count;
      try {
        final m = await _channel.invokeMapMethod<String, dynamic>('read');
        if (m != null) {
          final v = m['selfSha256'];
          if (v is String && v.length == 64) selfSha = v;
          final g = m['gitSha'];
          if (g is String && g.trim().isNotEmpty) gitSha = g.trim();
          final c = m['artifactCount'];
          if (c is int) count = c;
        }
      } catch (_) {
        // No channel, no identity beyond the pair. Stated, not guessed.
      }

      return BuildIdentity(
        versionName: name,
        versionCode: code,
        packageName: info.packageName,
        selfSha256: selfSha,
        gitSha: gitSha,
        artifactCount: count,
      );
    } catch (_) {
      return const BuildIdentity.unknown();
    }
  }
}
