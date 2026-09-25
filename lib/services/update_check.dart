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

/// What the ADDRESS READER did on one check ([UpdateChecker.check]). Closed
/// vocabulary for the debug line and the tests; none of it reaches a pixel.
///
/// Every state but [learned] leaves the stored address exactly as it was.
enum ManifestAddress {
  /// No manifest describing this app was read on this check (no answer,
  /// unknown self, or a manifest for another app), so no address could be
  /// learned. Deliberately NOT [unchanged]: "I did not read one" is not "it
  /// named no new address", and a step that did not run must not report a
  /// result that looks like it ran and found nothing.
  notAsked,

  /// The manifest named no address, or named the one it was served from.
  unchanged,

  /// The manifest named an address that is not an absolute https URL with a
  /// host. It was not fetched and nothing was stored.
  refused,

  /// The manifest named a new https address, and that address did not verify:
  /// it did not answer 200 in time, its body did not parse, the manifest there
  /// did not name ITSELF, or it described a different app. Nothing was stored.
  unverified,

  /// The new address verified, but storing it failed. Nothing was stored; the
  /// next check will fetch the old address and try again.
  unsaved,

  /// The new address verified and was stored. It is used from the NEXT check
  /// on, which in this app is the next launch.
  learned,
}

@immutable
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    required this.running,
    this.available,
    this.runningIsPublished,
    this.address = ManifestAddress.notAsked,
  });

  final UpdateCheckStatus status;

  /// What the address reader did on this check. Never shown to the holder.
  final ManifestAddress address;

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

  UpdateCheckResult _withAddress(ManifestAddress a) => UpdateCheckResult(
        status: status,
        running: running,
        available: available,
        runningIsPublished: runningIsPublished,
        address: a,
      );
}

/// One check's version answer, plus the manifest it came from when that
/// manifest describes this app (the only kind whose address may be learned).
typedef _Answer = ({UpdateCheckResult result, UpdateManifest? ours, Uri? from});

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
  /// persisted address (see [resolveManifestUrl]).
  ///
  /// ⚑ CORRECTED 2026-09-25. This comment used to end "so the route survives a
  /// change of host WITHOUT a new build, which is the point." Nothing wrote the
  /// persisted address: [persistManifestUrl] had no caller and the parser read
  /// no address field. In every build before this one, a change of host needs a
  /// new build, and a holder of such a build cannot be told where to find one.
  ///
  /// What is true from this build on, and only within these bounds:
  ///  - a manifest may name the address it will be served from
  ///    (`manifest_url`). [check] stores a NEW address only after fetching it
  ///    and finding that the manifest there names itself and describes this
  ///    app (`_goAndSee`);
  ///  - a stored address is used from the NEXT check, and this app checks once
  ///    per launch, so it takes effect at the next launch;
  ///  - the OLD address must keep answering, and naming the new one, until the
  ///    holder has launched once. A holder who does not launch inside that
  ///    window is stranded exactly as before, and nothing here can tell him;
  ///  - builds WITHOUT this reader cannot follow a move at all. Their only
  ///    address is the one they were compiled with.
  static const String defaultManifestUrl = String.fromEnvironment(
    'SNGNAV_UPDATE_MANIFEST_URL',
    defaultValue:
        'https://raw.githubusercontent.com/aki1770-del/sngnav-app/main/tool/update_manifest.json',
  );

  static const String _overrideFileName = 'update_manifest_url.txt';

  /// Reads the persisted manifest address, falling back to the compiled
  /// default when none is stored (or the stored one is not https). Never
  /// throws.
  ///
  /// A stored address that later stops answering does NOT fall back to the
  /// compiled default, and that is deliberate: an address we moved away from
  /// may later be served by someone else (a released account or repository
  /// name, a lapsed domain), and falling back would hand them this channel.
  /// The cost is stated, not hidden: a DEAD stored address strands its holder
  /// exactly as a dead compiled default would. The only way off any address
  /// is a manifest still served THERE that names the next one, so an address
  /// may be given up only after its holders have had time to learn where it
  /// went.
  static Future<Uri?> resolveManifestUrl() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/$_overrideFileName');
      if (f.existsSync()) {
        // https only, for the same reason the manifest's artifact URL is:
        // see UpdateManifest._httpUri. A persisted override is not a reason to
        // drop to plaintext.
        final u = _httpsOnly(f.readAsStringSync());
        if (u != null) {
          return u;
        }
      }
    } catch (_) {
      // Fall through to the compiled default.
    }
    // The compiled default is checked too, and for a reason found while
    // closing the gap above: this value is overridable at BUILD time with
    // `--dart-define=SNGNAV_UPDATE_MANIFEST_URL=...`, and this return
    // originally handed back whatever parsed. Refusing a plaintext artifact URL
    // while a `--dart-define` could still point the manifest fetch itself at
    // `http://` would have left the published "all traffic is https" statement
    // resting on a build flag nobody checks.
    return _httpsOnly(defaultManifestUrl);
  }

  /// An absolute https URL with a host, or null. Same predicate as
  /// `UpdateManifest._httpUri`, applied to the manifest location rather than to
  /// the artifact.
  static Uri? _httpsOnly(String raw) {
    final u = Uri.tryParse(raw.trim());
    if (u == null || !u.isAbsolute) return null;
    if (u.scheme != 'https') return null;
    if (u.host.isEmpty) return null;
    return u;
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

  /// Stores a new manifest address. Returns true only when it was written.
  /// Never throws.
  ///
  /// Its caller is [check], which calls it only after `_goAndSee` has fetched
  /// the new address and its manifest has named itself. (Until 2026-09-25 it
  /// had no caller at all, and its comment cited a `manifestUrl` field the
  /// parser never read.) It refuses anything that is not an absolute https URL
  /// with a host, by the same predicate [resolveManifestUrl] reads with, so
  /// this code cannot store an address that the read side would then refuse.
  static Future<bool> persistManifestUrl(Uri url) async {
    final safe = _httpsOnly(url.toString());
    if (safe == null) return false;
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/$_overrideFileName');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(safe.toString(), flush: true);
      return true;
    } catch (_) {
      // A failed write costs us the migration, not the drive.
      return false;
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

    final _Answer answer;
    try {
      answer = await _run(running, manifestUrl).timeout(timeout);
    } catch (_) {
      // Offline, DNS failure, TLS failure, timeout, anything at all. The
      // driver is told NOTHING and nothing downstream is affected.
      return UpdateCheckResult(
        status: UpdateCheckStatus.noAnswer,
        running: running,
      );
    }

    final ours = answer.ours;
    final from = answer.from;
    if (ours == null || from == null) return answer.result;

    // THE ADDRESS READER runs only AFTER this check's answer is fixed, and on
    // a budget of its own. Nothing it does can change what this check says: a
    // new address that hangs, lies or 404s costs the move, never the news of a
    // newer build. Its one cost is time, and only when the manifest names a
    // new address: this check can then return up to one more [timeout] later.
    //
    // Only the NETWORK half runs under that budget. `.timeout` abandons the
    // Future, not the work, so a write made inside it could land seconds
    // after this check had already reported "unverified". The write is made
    // here instead, on this path, and only when verification finished in time.
    //
    // ⚑ WDA SEAM: these lines are the only ones that act on the location fact.
    ({ManifestAddress outcome, Uri? store}) seen;
    try {
      seen = await _goAndSee(ours, from, running).timeout(timeout);
    } catch (_) {
      seen = (outcome: ManifestAddress.unverified, store: null);
    }
    final store = seen.store;
    final address = store == null
        ? seen.outcome
        : await persistManifestUrl(store)
            ? ManifestAddress.learned
            : ManifestAddress.unsaved;
    return answer.result._withAddress(address);
  }

  /// Goes and looks at a new manifest address. Writes nothing: it returns the
  /// address to store (`store`), or why there is none (`outcome`).
  ///
  /// [ours] was served from [from] and describes this app. If it names a
  /// DIFFERENT https address, that address is fetched, and it may be stored
  /// only when the manifest found THERE parses, names that same address as its
  /// own and describes this app. One hop only: a manifest that points on again
  /// is not followed further, so a chain of addresses cannot run this check
  /// long.
  Future<({ManifestAddress outcome, Uri? store})> _goAndSee(
    UpdateManifest ours,
    Uri from,
    BuildIdentity running,
  ) async {
    const unverified = (outcome: ManifestAddress.unverified, store: null);
    if (ours.manifestUrlRefused) {
      return (outcome: ManifestAddress.refused, store: null);
    }
    final named = ours.manifestUrl;
    if (named == null || named.toString() == from.toString()) {
      return (outcome: ManifestAddress.unchanged, store: null);
    }

    final res = await _client.get(named, headers: const {
      'Accept': 'application/json',
      'Cache-Control': 'no-cache',
    });
    if (res.statusCode != 200) return unverified;
    final there = UpdateManifest.tryParse(utf8.decode(res.bodyBytes));
    if (there == null) return unverified;
    // It must NAME ITSELF. A manifest that says it lives somewhere else is not
    // a home; storing its address would move him to a place that disowns it.
    if (there.manifestUrl?.toString() != named.toString()) return unverified;
    // And it must describe THIS app, or every later check would end in
    // packageMismatch: a move that silences him instead of moving him.
    final pkg = running.packageName;
    if (pkg != null && there.latest.package != pkg) return unverified;
    return (outcome: ManifestAddress.learned, store: named);
  }

  static _Answer _noManifest(UpdateCheckResult r) =>
      (result: r, ours: null, from: null);

  Future<_Answer> _run(BuildIdentity running, Uri? override) async {
    final url = override ?? await resolveManifestUrl();
    if (url == null) {
      return _noManifest(UpdateCheckResult(
        status: UpdateCheckStatus.noAnswer,
        running: running,
      ));
    }

    final res = await _client.get(url, headers: const {
      'Accept': 'application/json',
      'Cache-Control': 'no-cache',
    });
    if (res.statusCode != 200) {
      return _noManifest(UpdateCheckResult(
        status: UpdateCheckStatus.noAnswer,
        running: running,
      ));
    }

    final manifest = UpdateManifest.tryParse(utf8.decode(res.bodyBytes));
    if (manifest == null) {
      // Unparseable or unknown schema. NOT "up to date" — we did not
      // understand the answer, so we have no answer.
      return _noManifest(UpdateCheckResult(
        status: UpdateCheckStatus.noAnswer,
        running: running,
      ));
    }

    // The manifest must describe THIS app. A different applicationId is not
    // an update to him; it is a second app that would sit beside his. Nor is
    // it a manifest whose address he should ever learn.
    final pkg = running.packageName;
    if (pkg != null && manifest.latest.package != pkg) {
      return _noManifest(UpdateCheckResult(
        status: UpdateCheckStatus.packageMismatch,
        running: running,
        available: manifest.latest,
      ));
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
      return (
        result: UpdateCheckResult(
          status: UpdateCheckStatus.upToDate,
          running: running,
          available: manifest.latest,
          runningIsPublished: true,
        ),
        ours: manifest,
        from: url,
      );
    }

    // (b) Otherwise order by versionCode ALONE -- never by versionName, which
    //     is unordered and which BIS measured running the opposite way to the
    //     codes on this very tree. versionCode is the axis Android itself
    //     orders installs by, so it is the one integer that means something
    //     here, and it is the only one compared.
    if (manifest.latest.versionCode <= running.versionCode!) {
      return (
        result: UpdateCheckResult(
          status: UpdateCheckStatus.upToDate,
          running: running,
          available: manifest.latest,
          runningIsPublished: published,
        ),
        ours: manifest,
        from: url,
      );
    }

    // Constraint 2: prove we can deliver before we announce.
    final reachable = await _artifactReachable(manifest.latest.artifactUrl);
    return (
      result: UpdateCheckResult(
        status: reachable
            ? UpdateCheckStatus.updateAvailable
            : UpdateCheckStatus.newerButUnreachable,
        running: running,
        available: manifest.latest,
        runningIsPublished: published,
      ),
      ours: manifest,
      from: url,
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
      // ⚑ THE BODY IS NEVER READ (2026-09-25, AAE). This used to be
      // `_client.get(artifact, headers: {'Range': 'bytes=0-0'})`, and `get`
      // reads EVERY byte of the response before it returns. A host that
      // ignores Range answers with 200 and the whole artifact, so on exactly
      // the host this fallback exists for, the "probe" downloaded ~95 MB --
      // over her rural cell, and past the 6 s budget, because `.timeout` in
      // [check] abandons the Future, not the transfer. The published policy
      // says this step is an existence check and "never a download"
      // (docs/store/privacy_policy_ja.md, flow 5). The status line is the
      // whole answer, so the stream is cancelled unread and that sentence is
      // true by construction rather than by the host's good manners.
      final request = http.Request('GET', artifact)
        ..headers['Range'] = 'bytes=0-0';
      final ranged = await _client.send(request);
      final reachable = ranged.statusCode == 206 ||
          (ranged.statusCode >= 200 && ranged.statusCode < 300);
      try {
        await ranged.stream.listen(null).cancel();
      } catch (_) {
        // Closing an abandoned body must not turn "reachable" into "not".
      }
      return reachable;
    } catch (_) {
      return false;
    }
  }

  void dispose() => _client.close();
}
