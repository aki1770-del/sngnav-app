/// CAUTION JOURNAL — the record of what the app DECIDED, so her diary entry
/// can be acted on.
///
/// WHY this exists (the gap measured 2026-07-28): `drive_diary.dart` records
/// what SHE observed on the road; `error_log.dart` records errors. Nothing
/// recorded what the app *decided*. So a diary entry reading
/// 「路面は凍結・アイスバーン。警告は来なかった」 was indistinguishable across four
/// different realities:
///
///   1. the controller evaluated and correctly stayed quiet (the data said dry)
///   2. it rose, and the rise was DELIBERATELY not spoken (measured-floor-only,
///      or visibility-unknown-only — both real, documented mute rules)
///   3. it rose and should have spoken, but the guidance line came back empty
///   4. the code path was dead
///
/// Only (4) is a defect; (1) and (2) are the design working. Without this
/// record we could not tell them apart, so **her testimony could not be acted
/// on** — the diary-writer is the beneficiary of this file.
///
/// HER-trace (3 hops, stated honestly — this does not help her at the wheel):
/// diary-writer's words become falsifiable → the real defect is found instead
/// of guessed → the warning that failed her is fixed. Ring 2 of the three-month
/// plan depends on entries a reader can actually act on.
///
/// Honest bounds (error_log.dart's contract carried through, unchanged):
/// - ZERO telemetry. Entries go to the SAME local, size-capped file as the
///   crash log and leave the device ONLY via her explicit ログを共有 tap.
/// - NO position, coordinate, route, destination or speed value is ever
///   written here — only the rung name and which gate decided. The
///   no-location-history property of the log survives.
/// - Written ONLY on a transition or an announce decision — never per tick.
///   A steady drive writes nothing, so the journal cannot become a firehose
///   that evicts crash evidence from the shared cap.
/// - A journal failure must never take the drive down: every write is wrapped
///   twice (here and in [LocalErrorLog.record], which already never throws).
/// - Entries share the crash log's entry marker with a distinct `[caution]`
///   source tag, so the existing rotation and share-truncation stay
///   entry-aligned with no change to the crash boundary. (Wart, recorded
///   honestly: the marker line reads `--- sngnav error … [caution] ---` for a
///   non-error. The source tag disambiguates; renaming the marker would mean
///   editing the crash-boundary file, which is not worth the risk today.)
/// - On-device behaviour is OPS-066 DEFERRED until a device pass (AAE
///   env-bound), same bound as log_share.dart and drive_diary.dart.
library;

import 'error_log.dart';

/// The `[source]` tag every journal entry carries in the shared log.
const String kCautionJournalSource = 'caution';

/// Records the caution controller's decisions to the local log.
///
/// Deliberately takes plain [String] rung names rather than the domain enum:
/// the journal has no opinion about the caution model, cannot drift with it,
/// and is testable without constructing advice.
class CautionJournal {
  CautionJournal({required LocalErrorLog log}) : _log = log;

  final LocalErrorLog _log;

  /// The effective rung changed (including the first evaluation of a session,
  /// where [from] is null). This is what proves the evaluator was ALIVE — the
  /// difference between reality (1) and reality (4) above.
  void rungChanged({String? from, required String to}) =>
      _write('rung ${from ?? 'none'}->$to');

  /// A rise was announced: the line fired on voice + haptic.
  void spoke(String rung) => _write('spoke $rung');

  /// A rise was DELIBERATELY not spoken, and which mute rule decided.
  /// [reason] is a stable token (`measured-floor-only` /
  /// `visibility-unknown-only`), not prose — a reader collates on it.
  void suppressed({required String rung, required String reason}) =>
      _write('not-spoken $rung reason=$reason');

  /// A rise passed every gate but the localized guidance line came back empty,
  /// so nothing fired and the spoken tracker did not advance. This is the
  /// silent-failure case (3) — a real defect that today leaves no trace at all.
  void emptyGuidanceLine(String rung) =>
      _write('not-spoken $rung reason=empty-guidance-line');

  void _write(String entry) {
    try {
      _log.record(entry, null, source: kCautionJournalSource);
    } catch (_) {
      // Belt-and-braces: LocalErrorLog.record already swallows, but a journal
      // must never be the reason a drive surface dies.
    }
  }
}
