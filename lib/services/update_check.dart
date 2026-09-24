/// The ANNOUNCING half of the update route: does a newer build exist, and can
/// the holder actually get it?
///
/// This app is sideloaded. Nothing hands its holder a new build, and there is
/// no store, no auto-update and NO RECALL VEHICLE AT ALL. Until something in
/// the app tells him, a fix we shipped reaches him only if he happens to look.
/// V45 — "Invention that does not reach the market is not yet complete."
///
/// FOUR BINDING CONSTRAINTS (PDS), each mechanised here rather than promised:
///
/// 1. **Fails silent and harmless offline.** This app's whole promise to HER is
///    that it works when the network is gone. Every path through [check]
///    returns an [UpdateCheckResult]; none throws, none retries, none blocks a
///    frame and none is awaited on the startup path. Offline resolves to
///    [UpdateCheckStatus.noAnswer] and the driver is shown nothing — exactly
///    the behaviour of a build with no checker in it at all.
///
/// 2. **Never announces what it cannot deliver.** A manifest naming a build
///    whose artifact 404s would tell the holder something exists that he
///    cannot get. So before announcing, the artifact URL is PROBED, and a
///    newer build whose artifact does not answer resolves to
///    [UpdateCheckStatus.newerButUnreachable] — recorded, not announced.
///
/// 3. **Never intrudes while driving.** The checker does not decide when to
///    run; its caller does, and gates it on not-driving. WDA holds the veto on
///    the surface; this file holds no UI.
///
/// 4. **No new permission.** INTERNET is already declared. Nothing here
///    installs anything: `REQUEST_INSTALL_PACKAGES` is deliberately NOT
///    requested. The holder's own browser and the OS installer are sufficient,
///    and they are not our hand.
///
/// THE COMPARISON IS ON versionCode, NEVER versionName. BIS measured on
/// 2026-09-23 that versionCode 9 carried two distinct byte-sets and
/// versionCode 2 carried six, all under one versionName. A name comparison
/// would be a string comparison on an unordered value.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'build_identity.dart';
import 'update_manifest.dart';

/// Closed vocabulary. `noAnswer` is a distinct state and is NEVER collapsed
/// into `upToDate`: "I could not ask" is not "there is nothing newer" (AAE-6 —
/// the abstention survives to the surface).
enum UpdateCheckStatus {
  /// The manifest answered and names nothing newer than the running build.
  upToDate,

  /// The manifest names a newer build AND its artifact answered a probe.
  /// The ONLY status that may be announced.
  updateAvailable,

  /// A newer build is named but its artifact did not answer. Deliberately not
  /// announced (constraint 2).
  newerButUnreachable,

  /// The manifest describes a DIFFERENT applicationId than the one running.
  /// Never announced: installing it would place a second app BESIDE his and
  /// leave the build he depends on broken (PDS). Refused, not resolved.
  packageMismatch,

  /// We could not ask, or could not understand the answer: offline, timeout,
  /// DNS failure, non-200, malformed or unknown-schema manifest. The normal
  /// state in a snow dead-zone, and it is silent.
  noAnswer,

  /// The running build could not read its own identity, so no comparison is
  /// possible (BuildIdentity.unknown). Never guessed around.
  unknownSelf,
}

@immutable
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    required this.running,
    this.available,
    this.runningIsPublished,
  });

  final UpdateCheckStatus status;

  /// What the running build says it is, read from the artifact.
  final BuildIdentity running;

  /// Whether the RUNNING build's own bytes appear in the published ledger
  /// (as `latest`, or as a `history` row). Null when the self-hash is absent
  /// so the question could not be asked. False means this build was never
  /// published — normal for a local or dev build, and the reason the surface
  /// must not tell him he is "on" any published version.
  final bool? runningIsPublished;

  /// The manifest's entry, when one was parsed. Present on
  /// [UpdateCheckStatus.updateAvailable], [UpdateCheckStatus.upToDate] and
  /// [UpdateCheckStatus.newerButUnreachable].
  final UpdateManifestEntry? available;

  /// The single question a surface may ask. True ONLY when a newer build
  /// exists and has been proven fetchable this check.
  bool get shouldAnnounce => status == UpdateCheckStatus.updateAvailable;
}

/// Fetches a version manifest and compares it to the running build.
class UpdateChecker {
  UpdateChecker({
    http.Client? client,
    this.timeout = const Duration(seconds: 6),
    Future<BuildIdentity> Function()? readIdentity,
  })  : _client = client ?? http.Client(),
        _readIdentity = readIdentity ?? BuildIdentity.fromPlatform;

  final http.Client _client;
  final Future<BuildIdentity> Function() _readIdentity;

  /// Total budget for the whole check. Short on purpose: this runs on a phone
  /// that may be on a dying rural cell, and nothing downstream waits for it.
  final Duration timeout;

  /// The compile-time DEFAULT manifest location. Overridable at build time with
  /// `--dart-define=SNGNAV_UPDATE_MANIFEST_URL=...`, and at RUNTIME by a
  /// persisted override (see [resolveManifestUrl]) — so the route survives a
  /// change of host WITHOUT a new build, which is the point.
  static const String defaultManifestUrl = String.fromEnvironment(
    'SNGNAV_UPDATE_MANIFEST_URL',
    defaultValue:
        'https://raw.githubusercontent.com/aki1770-del/sngnav-app/main/tool/update_manifest.json',
  );

  static const String _overrideFileName = 'update_manifest_url.txt';

  /// Reads the persisted manifest-URL override, falling back to the compiled
  /// default. Never throws.
  static Future<Uri?> resolveManifestUrl() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/$_overrideFileName');
      if (f.existsSync()) {
        final u = Uri.tryParse(f.readAsStringSync().trim());
        if (u != null && u.isAbsolute && (u.scheme == 'https' || u.scheme == 'http')) {
          return u;
        }
      }
    } catch (_) {
      // Fall through to the compiled default.
    }
    return Uri.tryParse(defaultManifestUrl);
  }

  static const String _dismissedFileName = 'update_dismissed_code.txt';

  /// Reads the versionCode the holder has already dismissed. Never throws.
  ///
  /// WDA Item 1 forbids anything that reappears after dismissal in the same
  /// version. Holding that in memory only would have honoured it for one
  /// session and broken it on the next launch -- he would have dismissed it
  /// and been asked again, which is the intrusion, just slower. So it is on
  /// disk, keyed to the versionCode.
  static Future<int?> readDismissedVersionCode() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/$_dismissedFileName');
      if (!f.existsSync()) return null;
      return int.tryParse(f.readAsStringSync().trim());
    } catch (_) {
      return null;
    }
  }

  /// Records that he has dismissed this versionCode. Never throws.
  static Future<void> persistDismissedVersionCode(int code) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/$_dismissedFileName');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('$code', flush: true);
    } catch (_) {
      // A failed write costs him one extra sighting, never the drive.
    }
  }

  /// Persists a new manifest location (from a manifest's own `manifestUrl`).
  /// Never throws.
  static Future<void> persistManifestUrl(Uri url) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/$_overrideFileName');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(url.toString(), flush: true);
    } catch (_) {
      // A failed write costs us the migration, not the drive.
    }
  }

  /// Runs one check. NEVER THROWS.
  Future<UpdateCheckResult> check({Uri? manifestUrl}) async {
    // Read our own identity FIRST. Without it there is nothing to compare and
    // we must not guess (V15: better to detect than to invent).
    final running = await _readIdentity().catchError(
      (_) => const BuildIdentity.unknown(),
    );
    if (!running.isKnown) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.unknownSelf,
        running: running,
      );
    }

    try {
      return await _run(running, manifestUrl).timeout(timeout);
    } catch (_) {
      // Offline, DNS failure, TLS failure, timeout, anything at all. The
      // driver is told NOTHING and nothing downstream is affected.
      return UpdateCheckResult(
        status: UpdateCheckStatus.noAnswer,
        running: running,
      );
    }
  }

  Future<UpdateCheckResult> _run(BuildIdentity running, Uri? override) async {
    final url = override ?? await resolveManifestUrl();
    if (url == null) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.noAnswer,
        running: running,
      );
    }

    final res = await _client.get(url, headers: const {
      'Accept': 'application/json',
      'Cache-Control': 'no-cache',
    });
    if (res.statusCode != 200) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.noAnswer,
        running: running,
      );
    }

    final manifest = UpdateManifest.tryParse(utf8.decode(res.bodyBytes));
    if (manifest == null) {
      // Unparseable or unknown schema. NOT "up to date" — we did not
      // understand the answer, so we have no answer.
      return UpdateCheckResult(
        status: UpdateCheckStatus.noAnswer,
        running: running,
      );
    }

    // The manifest must describe THIS app. A different applicationId is not
    // an update to him; it is a second app that would sit beside his.
    final pkg = running.packageName;
    if (pkg != null && manifest.latest.package != pkg) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.packageMismatch,
        running: running,
        available: manifest.latest,
      );
    }

    // ---- THE COMPARISON, under BIS's ruling of 2026-09-24 ----
    //
    // A versionCode does not name a build: seven distinct release-signed
    // byte-sets shared versionCode 2 that day. So the STRONGEST question is
    // asked first and it is about bytes, not integers.
    final selfSha = running.selfSha256;
    final published = selfSha == null
        ? null
        : selfSha.toLowerCase() == manifest.latest.sha256.toLowerCase() ||
            manifest.history.any(
              (r) => r.sha256.toLowerCase() == selfSha.toLowerCase(),
            );

    // (a) Our bytes ARE the latest artifact. Exact, and immune to the
    //     collision. Nothing newer exists, whatever the integers say.
    if (selfSha != null &&
        selfSha.toLowerCase() == manifest.latest.sha256.toLowerCase()) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.upToDate,
        running: running,
        available: manifest.latest,
        runningIsPublished: true,
      );
    }

    // (b) Otherwise order by versionCode ALONE -- never by versionName, which
    //     is unordered and which BIS measured running the opposite way to the
    //     codes on this very tree. versionCode is the axis Android itself
    //     orders installs by, so it is the one integer that means something
    //     here, and it is the only one compared.
    if (manifest.latest.versionCode <= running.versionCode!) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.upToDate,
        running: running,
        available: manifest.latest,
        runningIsPublished: published,
      );
    }

    // Constraint 2: prove we can deliver before we announce.
    final reachable = await _artifactReachable(manifest.latest.artifactUrl);
    return UpdateCheckResult(
      status: reachable
          ? UpdateCheckStatus.updateAvailable
          : UpdateCheckStatus.newerButUnreachable,
      running: running,
      available: manifest.latest,
      runningIsPublished: published,
    );
  }

  /// Probes the artifact WITHOUT downloading it (it is ~95 MB). HEAD first;
  /// some object stores answer 403/405 to HEAD, so fall back to a one-byte
  /// ranged GET. Any non-success, or any throw, means UNREACHABLE — the safe
  /// direction, because the cost of a false "reachable" is a holder told to go
  /// get something that is not there.
  Future<bool> _artifactReachable(Uri artifact) async {
    try {
      final head = await _client.head(artifact);
      if (head.statusCode >= 200 && head.statusCode < 300) return true;
      if (head.statusCode != 403 && head.statusCode != 405) return false;
    } catch (_) {
      return false;
    }
    try {
      final ranged = await _client.get(artifact, headers: const {
        'Range': 'bytes=0-0',
      });
      return ranged.statusCode == 206 ||
          (ranged.statusCode >= 200 && ranged.statusCode < 300);
    } catch (_) {
      return false;
    }
  }

  void dispose() => _client.close();
}
