/// The surface that TELLS the holder a newer build exists.
///
/// ⛑ PROVISIONAL. WDA holds the veto on this surface and is measuring in
/// parallel. What is built here is deliberately the quietest thing that can
/// still be called telling him, so that her verdict has somewhere to move FROM
/// rather than a dialog to tear out.
///
/// WHAT IT IS NOT, by construction — each of these is the intrusion PDS's
/// third constraint forbids, and none of them is reachable from this file:
///   - NOT a dialog, a bottom sheet, a banner, a snackbar or any overlay. It
///     is a widget in a scrolled panel; he reaches it by scrolling to it.
///   - NOT audible and NOT haptic. It never touches the TTS or vibration
///     actuators — those belong to the road, and spending her one eyes-off
///     channel on a software update would be exactly the dignity failure AAE-2
///     exists to prevent.
///   - NOT shown while the live position stream is running. If she is driving,
///     this does not exist.
///   - NOT an installer. There is no download button and no
///     REQUEST_INSTALL_PACKAGES. It shows him where the build is; his browser
///     and the OS do the rest. Our hand does not touch his device.
///
/// It renders ONLY on [UpdateCheckStatus.updateAvailable], which the checker
/// reaches only after proving the artifact answers. A build we cannot deliver
/// is never named here.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/update_check.dart';

class UpdateNotice extends StatelessWidget {
  const UpdateNotice({
    super.key,
    required this.result,
    required this.driving,
    required this.dismissedVersionCode,
    required this.onDismiss,
  });

  /// The last check's result. Null = no check has completed yet.
  final UpdateCheckResult? result;

  /// The versionCode the holder has already dismissed, if any. Dismissal is
  /// keyed to the VERSION, not to the session: once he has said "not this
  /// one", this build never asks him again. WDA Item 1 forbids anything that
  /// reappears after dismissal in the same version.
  final int? dismissedVersionCode;

  /// True while the live position stream is active. When true this renders
  /// nothing at all — not a smaller thing, nothing.
  final bool driving;

  final VoidCallback onDismiss;

  /// The single predicate. Kept public and pure so the widget test can assert
  /// the gate directly, and so WDA can read the whole rule in one expression.
  static bool shouldShow({
    required UpdateCheckResult? result,
    required bool driving,
    required int? dismissedVersionCode,
  }) {
    if (driving) return false;
    if (result == null) return false;
    if (!result.shouldAnnounce) return false;
    if (dismissedVersionCode != null &&
        dismissedVersionCode == result.available?.versionCode) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!shouldShow(
      result: result,
      driving: driving,
      dismissedVersionCode: dismissedVersionCode,
    )) {
      return const SizedBox.shrink();
    }
    final l10n = AppL10n.of(context);
    final entry = result!.available!;
    final running = result!.running;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.updateSectionTitle,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: onDismiss,
                  child: Text(l10n.updateDismiss),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(l10n.updateAvailableLine(entry.display)),
            const SizedBox(height: 6),
            // The bound rides the announcement (OPS-069(B)): existence is all
            // this channel can attest, and it says so in the same glance.
            Text(
              l10n.updateExistenceBound,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
            const SizedBox(height: 4),
            // The running build's identity, from the ARTIFACT. When it could
            // not be read this says so rather than printing the compiled-in
            // constant (AAE-6: the abstention survives to the pixel).
            // The running build's IDENTITY TRIPLE, from the artifact. BIS
            // ruled the version pair alone must not be shown as an identity —
            // versionCode 2 named seven distinct artifacts on 2026-09-24 — so
            // this renders `0.0.2 (10) · 7129d4a4bb1b · 5794d0c`, and when the
            // self-hash did not answer it says UNIDENTIFIED rather than
            // printing a pair that names nothing (AAE-6: the abstention
            // survives to the pixel).
            Text(
              !running.isKnown
                  ? l10n.updateRunningBuildUnknown
                  : running.isFullyIdentified
                      ? l10n.updateRunningBuild(running.display)
                      : l10n.updateRunningBuildUnidentified(running.display),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.updateHowToGet,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
            const SizedBox(height: 4),
            // Selectable, not tappable: we do not launch anything, and we do
            // not hide where he is being sent behind a label.
            SelectableText(
              entry.artifactUrl.toString(),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 6),
            // Android's refusal of a differently-signed update is silent. This
            // app cannot read the installed signer, so it cannot pre-check it
            // — it warns him instead of leaving him at a bare failure.
            Text(
              l10n.updateSignerBound,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

