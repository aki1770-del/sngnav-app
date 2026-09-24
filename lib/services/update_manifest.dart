/// The version manifest the app fetches, and its strict parse.
///
/// THE FORMAT IS NOT OURS TO INVENT. This parses the schema PDS's
/// `scripts/pds_app_route_guard.py` already EMITS from the artifact
/// (`sngnav-update-manifest/1`). A hand-typed manifest is the defect that guard
/// exists to prevent, and a second client-side format would be a second place
/// for the truth to drift. Generate with `--emit`; parse here; never type one.
///
/// WHY STRICT: PDS's binding constraint is that the app must NEVER announce a
/// version it cannot deliver — PDS-3's retraction defect, "it pushes a consumer
/// off a version and hands him nothing" — and on a sideloaded app that is worse
/// because there is no recall vehicle at all. A tolerant parser that defaults a
/// missing field is exactly how a manifest naming nothing downloadable becomes
/// an announcement. So every field below is REQUIRED, and anything unparseable
/// yields null, which the checker treats as "no answer" and never as "no
/// update".
///
/// ⚑ WDA ITEM 6 — THE CHANNEL CARRIES VERSION FACTS AND NOTHING ELSE.
/// No `message`, `title`, `html`, `notes`, `notes_url` or `bounds` field is
/// read by this parser, and [UpdateManifestEntry] has nowhere to put one. A
/// channel that CANNOT carry a sentence cannot later carry one by accident —
/// which is a structural property, not a promise, and
/// `update_check_test.dart` asserts it by feeding a manifest stuffed with such
/// fields and proving none of them survives the parse.
/// The ONLY string that reaches a pixel from this channel is the version
/// display (`0.0.2+11`) and the artifact URL itself, shown verbatim.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The exact schema token the guard emits. An unknown schema is refused
/// forward: a future schema could mean something we would mis-announce.
const String kUpdateManifestSchema = 'sngnav-update-manifest/1';

/// The one build a manifest advertises. Version facts only.
@immutable
class UpdateManifestEntry {
  const UpdateManifestEntry({
    required this.versionCode,
    required this.versionName,
    required this.artifactUrl,
    required this.package,
    required this.sha256,
    required this.sizeBytes,
    required this.signerSha256,
  });

  /// The integer the running build compares against. A versionName is not
  /// ordered and ten distinct artifacts have shared one (BIS, 2026-09-23), so
  /// it is never the comparison key.
  final int versionCode;

  /// Display name only.
  final String versionName;

  /// Where the holder can actually GET it — probed before anything is said.
  final Uri artifactUrl;

  /// The applicationId. A mismatch against the running package would install
  /// BESIDE his app and leave his old build broken, so a mismatch is refused.
  final String package;

  /// So he can verify what he got. Carried, displayed nowhere, never trusted
  /// as proof by this app (we do not download the artifact).
  final String sha256;

  final int sizeBytes;

  /// If this differs from the signer of the build he holds, Android refuses
  /// the update and the refusal does not explain itself. ⛑ THIS APP CANNOT
  /// COMPARE IT — `package_info_plus` does not expose the installed signing
  /// certificate, and no platform channel for it exists in this build. It is
  /// carried and REQUIRED-TO-BE-PRESENT so a malformed manifest is refused,
  /// and the bound is stated rather than papered over (OPS-069(B)).
  final String signerSha256;

  String get display => '$versionName+$versionCode';
}

/// One row of the published ledger: a build that has existed, keyed the only
/// way BIS's ruling permits — `(versionCode, sha256)`.
@immutable
class LedgerRow {
  const LedgerRow({required this.versionCode, required this.sha256});
  final int versionCode;
  final String sha256;
}

@immutable
class UpdateManifest {
  const UpdateManifest({required this.latest, this.history = const []});

  final UpdateManifestEntry latest;

  /// The published line, oldest-to-newest as the guard emits it. BIS §3.1:
  /// a direction of travel is NOT computable from the version pair alone
  /// ("codes say behind, names say ahead" — both correctly derived), so the
  /// running build is placed against THIS ledger by its own bytes.
  final List<LedgerRow> history;

  /// Parses manifest JSON. Returns null on ANYTHING it does not fully
  /// understand. Never throws.
  static UpdateManifest? tryParse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['schema'] != kUpdateManifestSchema) return null;

      final latest = decoded['latest'];
      if (latest is! Map<String, dynamic>) return null;

      final code = latest['versionCode'];
      if (code is! int || code <= 0) return null;

      final name = latest['versionName'];
      if (name is! String || name.trim().isEmpty) return null;

      final artifact = _httpUri(latest['artifact_url']);
      if (artifact == null) return null;

      final pkg = latest['package'];
      if (pkg is! String || pkg.trim().isEmpty) return null;

      final sha = latest['sha256'];
      if (sha is! String || !_isHex64(sha.trim())) return null;

      final size = latest['size_bytes'];
      if (size is! int || size <= 0) return null;

      final signer = latest['signer_sha256'];
      if (signer is! String || !_isHex64(signer.trim())) return null;

      final rows = <LedgerRow>[];
      final hist = decoded['history'];
      if (hist is List) {
        for (final r in hist) {
          if (r is! Map) continue;
          final c = r['versionCode'];
          final h = r['sha256'];
          if (c is int && h is String && _isHex64(h.trim())) {
            rows.add(LedgerRow(versionCode: c, sha256: h.trim()));
          }
        }
      }

      return UpdateManifest(
        history: rows,
        latest: UpdateManifestEntry(
          versionCode: code,
          versionName: name.trim(),
          artifactUrl: artifact,
          package: pkg.trim(),
          sha256: sha.trim(),
          sizeBytes: size,
          signerSha256: signer.trim(),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static bool _isHex64(String s) =>
      s.length == 64 && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(s);

  /// Accepts only an absolute http/https URL with a host. A relative, `file:`,
  /// `intent:` or `javascript:` URL is refused rather than resolved.
  static Uri? _httpUri(Object? raw) {
    if (raw is! String) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    final uri = Uri.tryParse(s);
    if (uri == null || !uri.isAbsolute) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri;
  }
}
