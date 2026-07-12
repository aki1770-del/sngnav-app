/// W0 DETECTION-SURVIVAL LAYER — staleness policy (bounds + observed-at parse).
///
/// The physics rationale for the two retain/freshness windows lives here in one
/// auditable place (AAA-reviewable, device-tunable). See
/// SNGNav/docs/W0_DETECTION_SURVIVAL_DESIGN.md §2 + §4 + §6a.
///
/// Honest-absence discipline: a stale observation is NEVER read as live. These
/// helpers only decide RETAIN-vs-EXPIRE and compute the spoken hour stamp; the
/// caller (main.dart `_announceWatchTransitions`) frames every cached announce
/// as a past observation with an explicit not-live clause.
library;

/// SLOW-hazard (radiative-frost black ice) RETAIN-AND-ANNOUNCE window.
///
/// Rationale (meteorological): radiative-cooling / dew-point-driven icing is a
/// quasi-stationary pre-dawn synoptic condition — clear sky, calm air, the road
/// surface radiating heat to space, ambient a few degrees above zero with the
/// dew point at/below 0 °C. These driving forces evolve over HOURS, not minutes,
/// so a reading up to this old remains physically indicative of the SAME
/// black-ice window. 60 min balances "still physically valid" against "old
/// enough that dawn / a wind shift may have ended it". Past this bound we STOP
/// stale-announcing and fall to the honest absence-line — never a stale announce.
/// AAA-reviewable; device-tunable.
const Duration kSlowHazardRetainWindow = Duration(minutes: 60);

/// FAST-hazard (downpour / strong wind) FRESHNESS window.
///
/// Rationale: a convective downpour cell or a gust is transient (minutes); a
/// reading older than this may describe weather that is already gone. Per the
/// Chair's cry-wolf discipline, a fast hazard is NOT announced from a reading
/// older than this — on feed loss the cache is by definition pre-loss, so this
/// makes the fast lane effectively SILENT when the feed is dead. AAA-reviewable.
const Duration kFastHazardFreshWindow = Duration(minutes: 20);

/// App-local mirror of the catalog's `conditionsUnknownAnnouncement` (GAP-2).
///
/// The design (§5) wires the honest ABSENCE-LINE through this catalog string,
/// but the resolved `snow_rendering 0.2.7` (pub.dev) does NOT yet export that
/// symbol — it lands in a later catalog release (the local catalog source at
/// packages/snow_rendering/lib/src/models/road_surface_announcement.dart:200
/// has it; the published package this app resolves does not, and the core
/// ^0.10 cap forbids floating to it). These app-authored constants carry the
/// EXACT verbatim ja/en text so the honest absence-line reaches HER TODAY, on
/// the one night the feed dies in Akita. Replace with the catalog import once
/// snow_rendering republishes with the symbol against a reachable core range.
const String kConditionsUnknownJaSpokenText =
    '路面状況を取得できていません。見える範囲で運転してください。';
const String kConditionsUnknownEnSpokenText =
    'Road conditions unavailable — drive to what you can see.';

/// Parse a 14-digit JMA observedAtJstKey (yyyymmddHHMMSS, JST wall-clock) into a
/// LOCAL DateTime. Returns null if the key is not 14 digits (caller then treats
/// it as no-reading → absence-line). NOTE: parsed as LOCAL time — correct only on
/// a JST-clock device (HER phone in Akita); see design safety review #3.
DateTime? observedAtJstAsLocal(String key) {
  if (key.length != 14) return null;
  final y = int.tryParse(key.substring(0, 4));
  final mo = int.tryParse(key.substring(4, 6));
  final d = int.tryParse(key.substring(6, 8));
  final h = int.tryParse(key.substring(8, 10));
  final mi = int.tryParse(key.substring(10, 12));
  final s = int.tryParse(key.substring(12, 14));
  if ([y, mo, d, h, mi, s].contains(null)) return null;
  return DateTime(y!, mo!, d!, h!, mi!, s!);
}

/// The TRUE absolute instant of a 14-digit JMA observedAtJstKey.
///
/// Interprets the digits as JST wall-clock (UTC+9) and returns a UTC DateTime;
/// null on a malformed key. Use THIS (not [observedAtJstAsLocal]) for the
/// staleness retain/expire bound — compared against `now.toUtc()` it is correct
/// on ANY device timezone, closing the off-JST miscompute where a genuinely
/// fresh reading could read as within-bound (or a hours-old one retained) on a
/// non-JST phone (design safety review #3). [observedAtJstAsLocal] stays for the
/// spoken hour stamp, which is derived from the raw JST digits and is
/// timezone-independent.
DateTime? observedAtJstInstant(String key) {
  final local = observedAtJstAsLocal(key);
  if (local == null) return null;
  return DateTime.utc(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute,
    local.second,
  ).subtract(const Duration(hours: 9));
}

/// The spoken hour (0-23) for the 「○時頃」 stamp — the FLOOR (truncation) of the
/// observation's own JST hour, read from the raw JST digits so it is
/// timezone-independent.
///
/// FLOOR, not nearest: a floored hour is NEVER newer than the true observation
/// (06:50 → 「6時」, always sounds at-or-OLDER than reality), which is the safe
/// direction for a staleness stamp — HER, eyes on the ice, must never hear a
/// stale reading stamped with an hour that makes it sound fresher than it is
/// (nearest-rounding did the reverse: 06:31 → 「7時」 could sound near-live). The
/// retain/expire bound is computed on the exact instant ([observedAtJstInstant]),
/// never this stamp.
int spokenHourJst(DateTime observedAtLocal) => observedAtLocal.hour;
