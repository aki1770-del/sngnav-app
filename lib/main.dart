/// sngnav-app — alpha-stage navigation companion for snow-zone commuting.
///
/// Slice 0 of #67 from the SPA Actuator unit's HER-pivot 100-insights work.
/// The unit's first edge-developer use of the navigation_safety packages.
///
/// Default profile = ageingRural (per V21 substance — HER's mother in Akita
/// is the named first customer; the most-vulnerable cohort member shapes
/// the default).
///
/// **This is alpha software in active development.** Not for production
/// navigation. The driver remains responsible for all driving decisions.
/// The app surfaces information; it does not control the vehicle.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show
        DriveAction,
        DriveAdvice,
        DriveSituation,
        PositionTrust,
        adviseInDrive,
        kVisLowM,
        kVisStaleSeconds;
import 'package:condition_aggregator/condition_aggregator.dart'
    show
        Advisory,
        AdvisoryAggregateResult,
        AdvisoryProviderError,
        AdvisorySource;
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:map_viewport_bloc/map_viewport_bloc.dart'
    show
        RenderFidelity,
        ViewportBudgetReset,
        ViewportRenderBudgetBloc,
        ViewportRenderConfig,
        ViewportRenderState;
import 'package:navigation_safety/navigation_safety.dart'
    show
        AlertExplainerExpandableSheet,
        BudgetExhausted,
        BudgetResetReason,
        BudgetWarning,
        GlanceBudgetEvent,
        GlanceBudgetTracker,
        GlanceEvent,
        GlanceModalClass;
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:noaa_nws_adapter/noaa_nws_adapter.dart' show NoaaNwsClient;
import 'package:routing_engine/routing_engine.dart'
    show
        OsrmRoutingEngine,
        RouteManeuver,
        RouteRequest,
        RoutingEngine,
        RoutingException;
import 'package:offline_tiles/offline_tiles.dart' as offline_tiles;
import 'package:snow_rendering/snow_rendering.dart' as snow_rendering;
import 'package:voice_guidance/voice_guidance.dart'
    show BudgetAwarePaceProfile, VoiceGuidanceConfig;

import 'dart:async';
import 'dart:io' show File;
import 'dart:ui' show FrameTiming;

import 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory;

import 'package:flutter_map/flutter_map.dart' show MapController, MapEvent;
import 'package:latlong2/latlong.dart';
import 'package:localization_fallback/localization_fallback.dart'
    show LocalizationMode;

import 'actuators/alert_actuators.dart';
import 'actuators/alert_announcer.dart';
import 'actuators/mobile_alert_actuators.dart';
import 'akita_map.dart';
import 'her_map_follow.dart';
import 'her_map_inputs.dart';
import 'services/offline_basemap.dart';
import 'l10n/app_localizations.dart';
import 'corridor_row.dart';
import 'her_position.dart';
import 'jma_fetch.dart';
import 'route_act.dart';
import 'route_fetch.dart';
import 'services/advisory_axis.dart';
import 'services/advisory_service.dart';
import 'services/app_unknowns.dart';
import 'services/drive_hud_controller.dart';
import 'services/drive_safety_fusion.dart' show measuredConditionRaisesCaution;
import 'services/visibility_for_caution.dart';
import 'services/error_log.dart';
import 'services/log_share.dart';
import 'services/drive_diary.dart';
import 'services/drive_hud_localizer.dart';
import 'services/maneuver_narration.dart';
import 'services/invisible_ice_watch.dart';
import 'services/turmoil_watch.dart';
import 'services/measured_hazard_floor.dart';
import 'services/jma_forecast_fetch.dart';
import 'services/staleness_policy.dart';
import 'services/forecast_validity.dart' show ForecastHazardKind;
import 'services/trip_hazard_memory.dart';
import 'services/route_consent.dart';
import 'services/jma_advisory_provider_factory.dart';
import 'services/audio_readiness.dart';
import 'services/haptic_readiness.dart';
import 'services/voice_lane_readiness.dart';
import 'package:snow_rendering/snow_rendering.dart'
    show invisibleBlackIceAnnouncement;

import 'build_info.dart';
import 'services/noaa_advisory_provider.dart';
import 'services/provider_coverage.dart';
import 'widgets/advisory_cards.dart';

/// Shared User-Agent for publisher-facing HTTP — concrete contact
/// substring is required by both NWS (api.weather.gov) and JMA
/// (data.jma.go.jp) best-practice. The publisher uses it only for
/// rate-limit accounting + security contact.
const String kSngnavAppUserAgent =
    '(sngnav-app, https://github.com/aki1770-del/sngnav)';

/// Whether this build offers the development page: the cards built to test the
/// app, which are not on her home page (2026-09-15). Only a non-release build
/// launched with
///
///     flutter run --dart-define=SNGNAV_DEVELOPER_PAGE=true
///
/// draws the entry to that page in her app bar. A release build never does,
/// whatever it was built with, and nothing else on her page leads there.
const bool kDeveloperPageFromEnvironment =
    !kReleaseMode && bool.fromEnvironment('SNGNAV_DEVELOPER_PAGE');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // W2 — crash boundary + local error log (services/error_log.dart): every
  // uncaught error is appended to a size-capped on-device file. NO network,
  // NO telemetry — the log leaves the device only via the user-initiated
  // ログを共有 action (C6, the feedback card near the footer). Never blocks
  // boot (best-effort install; a null log renders the action honestly
  // disabled).
  final errorLog = await installCrashBoundary();
  // Ring-2 運転日記 — consented post-drive diary (services/drive_diary.dart):
  // local file only, zero telemetry, leaves the device only via the
  // user-initiated 日記を共有 action. Best-effort open (errorLog idiom); a
  // null diary renders the card's actions honestly disabled.
  final diary = await openDriveDiary();
  runApp(SngnavApp(errorLog: errorLog, diary: diary));
}

/// WS5 — app-level severity for a mocked road-surface condition, used to gate
/// the audio+haptic announcement. ice / wet-ice (アイスバーン — the most
/// slippery, HER's whiteout worst-case) are `critical`; snow / slush / wet /
/// loose-gravel are `warning`; dry / unknown are `info` (announced on neither
/// channel, matching the voice gate). Top-level + public so the WS5 tests can
/// assert the mapping directly.
AlertSeverity severityForCondition(RoadSurfaceCondition condition) {
  switch (condition) {
    case RoadSurfaceCondition.ice:
    case RoadSurfaceCondition.wetIce:
      return AlertSeverity.critical;
    case RoadSurfaceCondition.snow:
    case RoadSurfaceCondition.slush:
    case RoadSurfaceCondition.wet:
    case RoadSurfaceCondition.looseGravel:
      return AlertSeverity.warning;
    case RoadSurfaceCondition.unknown:
    case RoadSurfaceCondition.dry:
      return AlertSeverity.info;
  }
}

/// The result the app synthesizes when [AdvisoryService.fetchAtPoint] THROWS.
///
/// The throw fired before any provider answered, so ZERO sources were
/// successfully asked. Stating that explicitly makes `isUnavailable` true (we
/// did not look) rather than leaving the result to be read as a partial one,
/// and keeps `canAssertNoAdvisory` false on its OWN arithmetic instead of only
/// via the synthetic error entry below.
///
/// Named + top-level because the provenance was previously an untested literal
/// at the call site: a mutant that dropped `sourcesQueried: 0` survived the
/// suite. It is pinned in
/// `test/services/advisory_thrown_path_provenance_test.dart`.
AdvisoryAggregateResult advisoryResultForThrownFetch(Object error) =>
    AdvisoryAggregateResult(
      advisories: const [],
      providerErrors: [
        AdvisoryProviderError(
          source: AdvisorySource.other,
          message: error.toString(),
        ),
      ],
      sourcesQueried: 0,
    );

/// The single "is this hazard still in force at [now]?" predicate shared by
/// [retainAdvisoriesOnFailure] and [cullExpiredRetainedAdvisories], so the
/// admit-bound and the stationary-cull-bound can never drift apart.
///
///   • expires-bearing (NWS/CAP, DigiTraffic, MET Norway) → the publisher's
///     OWN declared bound (`now < expires`). Unchanged — the N10 core.
///   • null-expires (JMA warnings, OWM road-risk — no publisher bound) → a
///     BOUNDED SYNTHETIC window: `now < lastFreshAt + kSlowHazardRetainWindow`.
///     A null [lastFreshAt] means no anchor is available → NOT in force (so a
///     null-expires hazard is neither admitted to retention nor synthetically
///     kept without an anchor).
///
/// The synthetic bound is deliberately NOT written into [Advisory.expires]
/// (that field has no provenance contract and the card renders it verbatim);
/// it lives only here, and the retained card carries the honest stale-age
/// label instead.
bool _advisoryInForce(Advisory a, DateTime now, DateTime? lastFreshAt) {
  final expires = a.expires;
  if (expires != null) return now.isBefore(expires);
  if (lastFreshAt == null) return false;
  return now.isBefore(lastFreshAt.add(kSlowHazardRetainWindow));
}

/// N10 — asymmetric overwrite: trust the hazard, expire the clear.
///
/// A fetch that FAILED (provider errors, no advisories) must not silently
/// erase hazards a publisher declared in force: [prior] advisories whose
/// publisher-declared [Advisory.expires] has not yet passed are RETAINED
/// (`retained: true`) — the caller keeps rendering them (with a visible
/// stale-age label) and keeps feeding the drive brain. A retained advisory
/// past its expires drops on every cycle (the publisher's own validity bound
/// is honored). The clear side is never retained: a genuine clear (fetch
/// succeeded, no advisories) overwrites immediately.
///
/// NULL-EXPIRES hazards (JMA warnings — `condition_aggregator_jma`'s mapper
/// emits `expires: null` as its ONLY value — and OWM road-risk) have NO
/// publisher validity bound. Previously they were dropped on a failed fetch
/// entirely, which meant an in-force JMA 大雪/暴風/特別警報 in Akita (where the
/// region-gate leaves JMA the ONLY answering provider, so its failure is a
/// TOTAL failure) vanished from the drive brain AND the card on the first
/// errored refresh — a surface indistinguishable from a clear sky, on HER
/// exact compound-failure target. They are now retained inside a BOUNDED
/// SYNTHETIC window anchored to [lastFreshAt] (the last successful fetch) +
/// [kSlowHazardRetainWindow] (60 min — the JMA reading's own decay bound).
/// This is the same shape as the black-ice `FeedLossStaleIce` lane: a
/// stale-stamped re-warning, never as live, DROPPED past the bound (N10 —
/// a parked driver never keeps a null-expires hazard forever). Without a
/// [lastFreshAt] anchor there is no verifiable bound and a null-expires
/// advisory is NOT retained (the prior behavior). We do NOT stamp the
/// synthetic bound into [Advisory.expires]: that field has no provenance
/// contract (see `forecast_validity.dart` / `trip_hazard_memory.dart`) and
/// the card renders it verbatim as "expires …"; the synthetic bound lives
/// only in this retention arithmetic, and the card carries the honest
/// retained stale-age label instead (`retainedAgeMinutes`).
///
/// PARTIAL failure (fresh advisories from a surviving provider PLUS at least
/// one provider error) retains PER PROVIDER: the errored provider's prior
/// unexpired advisories are kept and merged after the fresh ones. Without
/// this, the fresh branch would win outright and a failed fetch would erase
/// a declared hazard through the partial-failure seam. A provider that
/// answered — even with an empty result — is a genuine per-provider clear
/// and its prior advisories are dropped.
///
/// Top-level + public so the tests can pin the asymmetry directly.
({AdvisoryAggregateResult result, bool retained}) retainAdvisoriesOnFailure({
  required AdvisoryAggregateResult? prior,
  required AdvisoryAggregateResult fresh,
  required DateTime now,
  DateTime? lastFreshAt,
}) {
  if (prior == null || fresh.providerErrors.isEmpty) {
    return (result: fresh, retained: false);
  }
  // TOTAL failure (nothing delivered this cycle): retain every unexpired
  // prior hazard regardless of source — the whole cycle produced no
  // publisher statement to overwrite any of them with. This also covers the
  // thrown-exception path (init failure), where no provider was reached.
  final totalFailure = fresh.advisories.isEmpty;
  final erroredSources = {for (final e in fresh.providerErrors) e.source};
  final retained = <Advisory>[
    for (final a in prior.advisories)
      if ((totalFailure || erroredSources.contains(a.source)) &&
          _advisoryInForce(a, now, lastFreshAt))
        a,
  ];
  if (retained.isEmpty) return (result: fresh, retained: false);
  return (
    result: AdvisoryAggregateResult(
      advisories: [...fresh.advisories, ...retained],
      providerErrors: fresh.providerErrors,
      // B04-2 — carry the fresh cycle's provenance through the rebuild.
      // `canAssertNoAdvisory` is computed from `sourcesQueried`; a rebuild
      // that drops it destroys the evidence the all-clear gate reads.
      // Retention changes WHAT was seen, never WHO was asked.
      sourcesQueried: fresh.sourcesQueried,
    ),
    retained: true,
  );
}

/// N10 (stationary-expiry) — the retain doc-comment promises "a retained
/// advisory past its expires drops on every cycle", but cycles fire only on
/// ~1 km movement or a manual tap. A driver PARKED in a dead zone would keep
/// an expired retained hazard indefinitely. This is the time-based cull the
/// expiry ticker applies to a RETAINED result between fetches: returns the
/// culled result, or null when nothing expired (caller skips the rebuild).
/// Culling to empty leaves `advisories: [] + providerErrors` — which renders
/// the honest degraded-unknown banner, never a fabricated all-clear.
///
/// [lastFreshAt] anchors the SYNTHETIC window for null-expires hazards (JMA
/// warnings): once `lastFreshAt + kSlowHazardRetainWindow` passes, a
/// synthetically-retained null-expires hazard drops here too — so a PARKED
/// driver never keeps it forever (the N10 promise, extended to the
/// null-expires lane that retention now admits). When [lastFreshAt] is null
/// (or absent) a null-expires advisory is KEPT: with no anchor it is treated
/// as a FRESH publisher statement (a partial-retention survivor), and culling
/// it would erase a live warning.
///
/// Top-level + public so the tests can pin the cull directly.
AdvisoryAggregateResult? cullExpiredRetainedAdvisories(
  AdvisoryAggregateResult result,
  DateTime now, {
  DateTime? lastFreshAt,
}) {
  // expires-bearing → the publisher's own bound (unchanged). null-expires →
  // the synthetic window when an anchor exists; kept when it does not.
  bool stillInForce(Advisory a) {
    final expires = a.expires;
    if (expires != null) return now.isBefore(expires);
    if (lastFreshAt == null) return true; // fresh-partial survivor, no anchor.
    return now.isBefore(lastFreshAt.add(kSlowHazardRetainWindow));
  }

  final kept = <Advisory>[
    for (final a in result.advisories)
      if (stillInForce(a)) a,
  ];
  if (kept.length == result.advisories.length) return null;
  return AdvisoryAggregateResult(
    advisories: kept,
    providerErrors: result.providerErrors,
    // B04-2 — the cull drops EXPIRED hazards; it does not re-run the
    // lookup. Who was asked is unchanged, so the provenance rides through.
    sourcesQueried: result.sourcesQueried,
  );
}

/// N8 — the real-GPS-blackout watchdog decision: should the drive brain be
/// [DriveHudController.poll]ed this tick, and with what clock?
///
/// The degradation machine (trusted → dead-reckoning → lost) only progresses
/// when `poll` is called during a fix drought; until now the ONLY production
/// caller was the demo blackout button, so a REAL blackout froze the honest
/// dot at "trusted" forever. This function is the production driver: called on
/// a short periodic tick, it answers `null` (no poll — a fresh fix arrived
/// within [cadence], or nothing has ever been fed so there is no baseline to
/// degrade) or the timestamp to poll with.
///
/// [demoClock] is the simulated blackout clock (last trusted fix + simulated
/// seconds) when the demo button has been pressed; when it sits AHEAD of the
/// real [now], the poll uses it — the localizer's clock must never run
/// backwards mid-degradation (a regressing `now` would un-degrade the dot the
/// demo honestly degraded).
///
/// Top-level + public so the decision table is testable off-device.
DateTime? positionWatchdogPollTime({
  required DateTime now,
  required DateTime? lastPositionEventAt,
  required DateTime? demoClock,
  Duration cadence = kPositionDrought,
}) {
  // Nothing ever fed: polling would fabricate a degradation for a drive that
  // has not started (e.g. the permission dialog is still up).
  if (lastPositionEventAt == null) return null;
  if (now.difference(lastPositionEventAt) < cadence) return null;
  if (demoClock != null && demoClock.isAfter(now)) return demoClock;
  return now;
}

/// The time a simulated GPS blackout press polls the drive brain at: the later
/// of the [simulated] clock and the real [now]. A regressing clock would
/// un-degrade a dot a real drought degraded (AAA R52, S6).
DateTime blackoutPollTime({required DateTime simulated, required DateTime now}) =>
    simulated.isAfter(now) ? simulated : now;

/// How long after the platform position stream is subscribed, with no
/// position event of any kind, the words for "locating" stop being said
/// (ruled 2026-09-14). A GPS receiver with no network assistance waits on the
/// satellites' navigation message, broadcast at 50 bit/s in 1500-bit frames,
/// 30 s a frame; 60 s is two frames. Past that, 「現在地を取得しています…」 /
/// "Locating you…" is a promise the app has no evidence for. The watchdog
/// ticks every 15 s, so the words change by 75 s at the latest.
const Duration kFirstPositionWait = Duration(seconds: 60);

/// Whether the position stream subscribed at [subscribedAt] has now gone
/// [wait] with no position event at all ([eventArrived] false).
///
/// The watchdog above never polls before a first event. That left one state
/// with no words on her map: she shares, the platform stream subscribes, and
/// nothing ever arrives. Measured 2026-09-13: ten minutes on, the map was
/// 0.000% different from the map of a driver who never shared.
///
/// The clock is the SUBSCRIPTION, never the tap: [subscribedAt] is null until
/// the platform has answered the permission question and its stream is
/// subscribed, so the time she spends on the permission dialog is hers and
/// never counts.
///
/// Top-level + public so the decision is testable off-device.
bool positionFirstEventOverdue({
  required DateTime now,
  required DateTime? subscribedAt,
  required bool eventArrived,
  Duration wait = kFirstPositionWait,
}) =>
    !eventArrived &&
    subscribedAt != null &&
    now.difference(subscribedAt) >= wait;

/// N15 — the FEED-LOSS decision (JmaFailure / no successful fetch this cycle),
/// extracted to ONE function so the VOICE path (`_announceWatchTransitions`)
/// and the VISIBLE panel (`_jmaPanel`) compute the SAME verdict from the same
/// inputs. Everything spoken must have a visible counterpart, and the two
/// layers must never disagree: before this extraction the panel said "Cached
/// data is NOT shown" while the voice was speaking FROM that cache — a screen
/// that contradicted the speaker on a safety surface.
sealed class FeedLossVerdict {
  const FeedLossVerdict();
}

/// True no-reading dead zone (no cache / unparseable stamp / past the retain
/// bound), but the plan-time forecast memory holds a hazard the publisher
/// declared VALID FOR NOW — shown instead of rendering nothing, and spoken
/// when the bundled mouth can say it.
final class FeedLossForecastMemory extends FeedLossVerdict {
  const FeedLossForecastMemory({
    required this.line,
    required this.capturedAt,
    required this.spokenAloud,
  });

  /// The hazard line in the surface locale. When [spokenAloud] is true this
  /// is the EXACT line the voice speaks ([TripHazardMemory.speakableJaAt]);
  /// when false it is the VISIBLE-only counterpart ([kForecastSnowValidEn],
  /// or the ja line when the bundled mouth lacks the bytes) — locale or a
  /// missing mouth must not delete a publisher-declared-valid hazard from
  /// the screen a deaf / HoH / en-reading driver depends on.
  final String line;

  /// When WE captured the forecast (before departure) — the timestamp the
  /// visible card must carry so she knows this is plan-time knowledge.
  final DateTime capturedAt;

  /// True when the voice channel utters [line] (ja surface + bundled mouth
  /// covers it). False = screen-only: the voice keeps the honest absence
  /// line instead (an en forecast voice is a recorded, unclaimed bound; TTS
  /// was measured silent-then-hung offline on her phone).
  final bool spokenAloud;
}

/// True no-reading dead zone with nothing valid to say: the honest absence.
final class FeedLossAbsence extends FeedLossVerdict {
  const FeedLossAbsence();
}

/// Retained observation within the slow bound with the black-ice window
/// present: re-warn, honestly time-stamped, never as live.
final class FeedLossStaleIce extends FeedLossVerdict {
  const FeedLossStaleIce({required this.hourJst, required this.ageMinutes});

  /// FLOORED JST hour of the retained observation (`spokenHourJst`) — the
  /// stamp in the spoken line, and in its visible counterpart.
  final int hourJst;

  /// Age of the retained observation in whole minutes — the staleness label.
  final int ageMinutes;
}

/// Retained observation within the slow bound, no slow hazard: honest spoken
/// SILENCE (the absence line here would be false — we hold a ≤60-min reading).
/// The panel still shows the retained fields with the staleness label; it
/// deliberately does NOT re-render a watch verdict from stale data (a stale
/// 「該当なし」 would read as current calm).
final class FeedLossRetainedQuiet extends FeedLossVerdict {
  const FeedLossRetainedQuiet({required this.ageMinutes});

  /// Age of the retained observation in whole minutes — the staleness label.
  final int ageMinutes;
}

/// Decide what a feed-loss cycle says and shows. Pure; the announce gating
/// (once-per-entry absence / forecast, re-warn-per-cycle stale ice) stays in
/// the caller — this is the CONTENT decision only.
FeedLossVerdict feedLossVerdict({
  required JmaObservation? cached,
  required TripHazardMemory? memory,
  required DateTime now,
  required bool spokenJa,
}) {
  final observedAt =
      cached == null ? null : observedAtJstAsLocal(cached.observedAtJstKey);
  // The retain/expire bound uses the TRUE absolute instant (JST digits → UTC)
  // compared against now-as-UTC, so it is correct on ANY device timezone, not
  // only a JST-clock phone (design safety review #3). The stamped hour still
  // comes from observedAt (raw JST digits) — timezone-independent.
  final observedInstant =
      cached == null ? null : observedAtJstInstant(cached.observedAtJstKey);

  // (1) NO reading at all: no cache, unparseable stamp, or PAST the slow
  //     bound (`>` = past the window; exactly 60 min old is still RETAINED).
  if (cached == null ||
      observedAt == null ||
      observedInstant == null ||
      now.toUtc().difference(observedInstant) > kSlowHazardRetainWindow) {
    // The MEMORY, before the silence (C2 RED-1): a hazard the publisher
    // declared valid for THIS hour, captured before she left. The VISIBLE
    // channel carries it regardless of locale — locale (or a mouth missing
    // its bytes) is not data, and must not delete a held hazard from the
    // screen. The SPOKEN channel stays bounded by the bundled ja mouth
    // (en forecast voice not rendered — recorded, not claimed): when the
    // mouth cannot say it, spokenAloud is false and the caller speaks the
    // honest absence line instead, while the card shows what the voice
    // cannot say — labeled as plan-time forecast (its caption carries the
    // capture time), so the channels differ only by the screen showing MORE.
    final activeSnow = memory != null &&
        memory
            .activeAt(now)
            .any((h) => h.kind == ForecastHazardKind.snow);
    if (activeSnow) {
      final jaSpeakable = memory.speakableJaAt(now);
      return FeedLossForecastMemory(
        line: spokenJa
            ? (jaSpeakable ?? kForecastSnowValidJa)
            : kForecastSnowValidEn,
        capturedAt: memory.capturedAt,
        spokenAloud: spokenJa && jaSpeakable != null,
      );
    }
    return const FeedLossAbsence();
  }

  final ageMinutes = now.toUtc().difference(observedInstant).inMinutes;
  // SLOW hazard (black ice): recomputed from the retained observation.
  if (evaluateInvisibleIceWatch(cached) == InvisibleIceWatchResult.watch) {
    return FeedLossStaleIce(
      hourJst: spokenHourJst(observedAt),
      ageMinutes: ageMinutes,
    );
  }
  return FeedLossRetainedQuiet(ageMinutes: ageMinutes);
}

class SngnavApp extends StatelessWidget {
  /// [actuators] is injectable so tests (and future device harnesses) can
  /// supply a fake/real actuator layer; production leaves it null and the app
  /// picks [defaultAlertActuators] (mobile -> real, everywhere else -> no-op).
  ///
  /// [locale] overrides the device locale (null = follow the device). It is a
  /// testability + future device-harness hook: the WS7 tests pump the consent
  /// gate under `Locale('ja')` to prove HER surface renders in Japanese.
  ///
  /// [jmaFetch] overrides the live JMA observation fetch (null = the real
  /// AMeDAS fetch). Same idiom as [actuators]: it lets tests drive the
  /// measured-watch surfaces (路面凍結 / 荒天) with a canned observation so
  /// their render + transition-announce behavior is verifiable without a
  /// network or a device.
  ///
  /// [errorLog] is the crash-boundary log handle from [installCrashBoundary]
  /// (main() passes it in; tests inject a temp-dir-backed log). It feeds the
  /// C6 ログを共有 action; null renders that action honestly disabled.
  ///
  /// [logShareSink] overrides the share exit door (production null ->
  /// [shareLogViaShareSheet]; widget tests inject a recording fake so the
  /// platform share channel is never touched in the test binding).
  /// [voiceLaneReader] overrides the A1 pre-drive voice-lane readiness read
  /// (null = the real [readVoiceLaneReadiness], which is honestly `unknown`
  /// off-mobile/under-test). Same idiom as [jmaFetch]: tests drive the
  /// caution row with a canned verdict, no plugin, no device.
  ///
  /// [speechUnverified] overrides the HUD speech-verification flag holder
  /// (null = the page owns one, fed by the hardened TTS engine's callbacks).
  /// Tests inject a notifier and toggle it to pin the chip's show/clear.
  ///
  /// [hapticUnverified] is the exact tactile twin, fed by
  /// [HardenedHapticChannel]'s callbacks. It exists because on 2026-08-21 the
  /// app was measured on a device firing a critical announce that dispatched
  /// speech and produced zero vibrations, with nothing on HER screen saying
  /// so — the only channel a deaf or hard-of-hearing driver has was the one
  /// channel with no delivery report.
  ///
  /// [hapticReadinessProbe] overrides the pre-drive TACTILE readiness probe
  /// (null = the real [DriverHapticReadinessProbe], honestly `null` off-mobile
  /// and under test — and `null` renders NOTHING). Built 2026-08-22 on AAA's
  /// G-3 PUSHBACK: the audio channel was probed at four triggers and the
  /// tactile channel at none, so the app could warn her before the drive that
  /// speech would not reach her and only after a lost warning that vibration
  /// had not.
  ///
  /// [audioReadinessProbe] overrides the Tier-2 pre-drive media-volume probe
  /// (null = the real [ChannelAudioReadinessProbe], which is honestly `null`
  /// off-mobile/under-test — null renders NOTHING). Same idiom as
  /// [voiceLaneReader]: tests drive the media-muted caution with a canned
  /// reading, no channel, no device.
  ///
  /// [developerPageEntry] asks for the entry to the development page in her app
  /// bar (null = [kDeveloperPageFromEnvironment]). A release build ignores it.
  const SngnavApp({
    super.key,
    this.actuators,
    this.locale,
    this.jmaFetch,
    this.jmaForecastFetch,
    this.errorLog,
    this.logShareSink,
    this.diary,
    this.diaryShareSink,
    this.voiceLaneReader,
    this.speechUnverified,
    this.hapticUnverified,
    this.audioReadinessProbe,
    this.hapticReadinessProbe,
    this.clock,
    this.positionSource,
    this.routingEngineFactory,
    this.advisoryProviders,
    this.developerPageEntry,
  });

  final AlertActuators? actuators;
  final Locale? locale;
  final Future<JmaResult> Function()? jmaFetch;

  /// Injectable JMA FORWARD-FORECAST fetch (null -> live forecast fetch). This
  /// is the source of HER dead-zone memory; tests drive it with a real captured
  /// JMA payload, never a hand-written one.
  final Future<JmaForecastResult> Function()? jmaForecastFetch;
  final LocalErrorLog? errorLog;
  final LogShareSink? logShareSink;

  /// Ring-2 post-drive diary handle (運転日記; null -> actions disabled).
  final DriveDiary? diary;

  /// Injectable diary share exit door (null -> [shareDiaryViaShareSheet]).
  final DiaryShareSink? diaryShareSink;
  final Future<VoiceLaneVerdict> Function()? voiceLaneReader;
  final ValueNotifier<bool>? speechUnverified;
  final ValueNotifier<bool>? hapticUnverified;
  final AudioReadinessProbe? audioReadinessProbe;
  final HapticReadinessProbe? hapticReadinessProbe;

  /// W0 detection-survival: injectable clock for host-deterministic staleness
  /// (null -> [DateTime.now]). Tests inject a fixed `now` consistent with the
  /// retained observation's observedAt so the feed-loss decision table is
  /// verifiable without a device (OPS-066).
  final DateTime Function()? clock;

  /// Injectable position source (null -> the real [herPositionStream]). Same
  /// idiom as [jmaFetch]: lets tests drive the share-location → watchdog →
  /// stop lifecycle with a controlled stream, no geolocator plugin.
  final Stream<PositionFix> Function()? positionSource;

  /// Injectable routing engine, built once per route request (null -> the
  /// OSRM public demo engine). Lets tests render a fetched route: the test
  /// binding answers every HTTP request with 400.
  final RoutingEngine Function()? routingEngineFactory;

  /// Injectable advisory publishers, each with the area it covers (null -> the
  /// real NWS and JMA providers). Lets tests read the point the app asks
  /// advisories for, which no surface shows.
  final List<CoveredProvider>? advisoryProviders;

  /// Asks for the development page's entry in her app bar (null ->
  /// [kDeveloperPageFromEnvironment]). A release build ignores it.
  final bool? developerPageEntry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'sngnav-app (alpha)',
      // WS7 — force locale when supplied (tests / device harness); otherwise
      // follow the device. supportedLocales lists ja FIRST so a device set to
      // neither ja nor en falls back to HER tongue, not English.
      locale: locale,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
        // 1b tofu fix (plan 2026-07-25 §1): HER-facing strings carry a small
        // symbol set (⚠ ❄ ※ → ° …) the ja system font stack does not
        // guarantee — measured 2026-07-30: Noto Sans CJK JP lacks U+2744 ❄,
        // and U+26A0 ⚠ coverage is fallback-dependent (the render-see
        // harness tofus it). A 15.7 KB bundled subset backstops every
        // theme-derived TextStyle: system fonts still resolve first, the
        // fallback only fills their holes, so a warning row can never
        // render as tofu. Coverage drift-guarded by
        // test/fonts/symbol_font_coverage_test.dart.
        fontFamilyFallback: const ['SnGNavSymbols'],
      ),
      // HER reads Japanese. The Global*Localizations delegates localize the
      // Material/Cupertino/Widgets chrome (date pickers, tooltips, semantics)
      // for ja + en; AppL10n (WS7) localizes the app's own dignity-bearing
      // consent / status / disclosure strings. Catalog driver-facing prose
      // (AlertExplainer / glossary / DriveHudLocalizer) localizes itself.
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ja'), Locale('en')],
      home: HomePage(
        actuators: actuators,
        locale: locale,
        jmaFetch: jmaFetch,
        jmaForecastFetch: jmaForecastFetch,
        errorLog: errorLog,
        logShareSink: logShareSink,
        diary: diary,
        diaryShareSink: diaryShareSink,
        voiceLaneReader: voiceLaneReader,
        speechUnverified: speechUnverified,
        hapticUnverified: hapticUnverified,
        audioReadinessProbe: audioReadinessProbe,
        hapticReadinessProbe: hapticReadinessProbe,
        clock: clock,
        positionSource: positionSource,
        routingEngineFactory: routingEngineFactory,
        advisoryProviders: advisoryProviders,
        developerPageEntry: developerPageEntry,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.actuators,
    this.locale,
    this.jmaFetch,
    this.jmaForecastFetch,
    this.errorLog,
    this.logShareSink,
    this.diary,
    this.diaryShareSink,
    this.voiceLaneReader,
    this.speechUnverified,
    this.hapticUnverified,
    this.audioReadinessProbe,
    this.hapticReadinessProbe,
    this.clock,
    this.positionSource,
    this.routingEngineFactory,
    this.advisoryProviders,
    this.developerPageEntry,
  });

  /// Injectable actuator layer (null -> [defaultAlertActuators]).
  final AlertActuators? actuators;

  /// The same locale override [SngnavApp] hands to MaterialApp, so the
  /// SPOKEN lane resolves from the identical inputs as the screen (AAA F1:
  /// the eyes-off channel must never silently diverge from the eyes-on one).
  final Locale? locale;

  /// Injectable JMA observation fetch (null -> live AMeDAS fetch).
  final Future<JmaResult> Function()? jmaFetch;

  /// Injectable JMA FORWARD-FORECAST fetch (null -> live forecast fetch). This
  /// is the source of HER dead-zone memory; tests drive it with a real captured
  /// JMA payload, never a hand-written one.
  final Future<JmaForecastResult> Function()? jmaForecastFetch;

  /// Crash-boundary log handle (C6 ログを共有; null -> action disabled).
  final LocalErrorLog? errorLog;

  /// Injectable share exit door (null -> [shareLogViaShareSheet]).
  final LogShareSink? logShareSink;

  /// Ring-2 post-drive diary handle (運転日記; null -> actions disabled).
  final DriveDiary? diary;

  /// Injectable diary share exit door (null -> [shareDiaryViaShareSheet]).
  final DiaryShareSink? diaryShareSink;

  /// Injectable A1 voice-lane readiness read (null ->
  /// [readVoiceLaneReadiness]).
  final Future<VoiceLaneVerdict> Function()? voiceLaneReader;

  /// Injectable speech-verification flag (null -> page-owned notifier fed by
  /// the hardened TTS engine's callbacks).
  final ValueNotifier<bool>? speechUnverified;

  /// Injectable tactile-verification flag (null -> page-owned notifier fed by
  /// [HardenedHapticChannel]'s callbacks). The OPS-059 twin of
  /// [speechUnverified].
  final ValueNotifier<bool>? hapticUnverified;

  /// Injectable Tier-2 audio readiness probe (null ->
  /// [ChannelAudioReadinessProbe]).
  final AudioReadinessProbe? audioReadinessProbe;

  /// Injectable pre-drive tactile readiness probe (null ->
  /// [DriverHapticReadinessProbe]). The OPS-059 twin of the audio probe, on
  /// the same cadence by construction — see [_probeAlertChannelReadiness].
  final HapticReadinessProbe? hapticReadinessProbe;

  /// W0 detection-survival: injectable clock (null -> [DateTime.now]). Makes the
  /// feed-loss staleness age computation host-deterministic (OPS-066).
  final DateTime Function()? clock;

  /// Injectable position source (null -> the real [herPositionStream]).
  final Stream<PositionFix> Function()? positionSource;

  /// Injectable routing engine (null -> the OSRM public demo engine).
  final RoutingEngine Function()? routingEngineFactory;

  /// Injectable advisory publishers (null -> the real NWS and JMA providers).
  final List<CoveredProvider>? advisoryProviders;

  /// Asks for the development page's entry in her app bar (null ->
  /// [kDeveloperPageFromEnvironment]). A release build ignores it.
  final bool? developerPageEntry;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // The development page (2026-09-15) is a route of its own, above this page,
  // and its cards read this state. A rebuild of this page does not reach that
  // route, so every setState here also ticks this notifier, which the route
  // listens to. The values stay here so a choice made there reaches the same
  // code it reached when the cards were on this page.
  final ValueNotifier<int> _developerPageRevision = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _developerPageRevision.value++;
  }

  /// Whether her app bar draws the entry to the development page.
  bool get _developerPageOffered =>
      !kReleaseMode &&
      (widget.developerPageEntry ?? kDeveloperPageFromEnvironment);

  /// Opens the development page: the cards that exist for the people who build
  /// the app. It is reached only from the entry [_developerPageOffered] draws.
  void _openDeveloperPage() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/development'),
      builder: (routeContext) => Scaffold(
        appBar: AppBar(
          title: Text(AppL10n.of(routeContext).developerPageTitle),
          backgroundColor: Theme.of(routeContext).colorScheme.inversePrimary,
        ),
        body: ListenableBuilder(
          listenable: _developerPageRevision,
          builder: (_, _) => SingleChildScrollView(
            key: const Key('developer-page'),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _developerSections(),
            ),
          ),
        ),
      ),
    ));
  }

  // V21: ageingRural is the default — HER's mother is the named first customer.
  DriverProfile _profile = DriverProfile.ageingRural;

  // Road-surface condition. Default UNKNOWN (路面状況不明) — the app has no
  // road-surface sensor wired (Slice 0), so it must NOT fabricate a condition:
  // absence reads as "unknown — drive carefully" (路面状況不明。慎重に運転して
  // ください), NEVER a synthetic ice hazard. A fabricated ICE default is the
  // cry-wolf twin of a fabricated clear (same fabrication family as the
  // visibility fix 3d5106d): it over-warns when nothing was measured, and an
  // instrument that raises alarm it cannot ground only separates a daughter
  // from her mother. The "Mocked road condition" demo dropdown overrides it.
  RoadSurfaceCondition _condition = RoadSurfaceCondition.unknown;

  // Vehicle-class state for NSC #3 wiring (0.9.0). null = unknown / no
  // signal (per VehicleClassProvider library doc convention; thresholds
  // fall back to per-profile baseline). Demo dropdown lets the
  // edge-developer reviewer surface the kei-car-at-65 cohort default
  // override that NSC ships pre-loaded.
  String? _vehicleClassToken;

  // VehicleThresholdOverrides registry pre-loaded with HER kei-car-at-65
  // cohort default per NSC 0.9.0. Selecting 'kei-car' in the dropdown
  // produces a +50m / +1°C caution-adding-only delta vs baseline.
  // Other tokens (compact-sedan / 4wd / commercial-light) demonstrate
  // no-op fallback when no override is registered.
  final VehicleThresholdOverrides _vehicleOverrides =
      VehicleThresholdOverrides.withKeiCarDefault();

  // WS5 — the actuator layer that makes a hazard alert REACH HER (audio +
  // haptic) and holds the screen awake. On desktop/test this is a no-op, so
  // the render-SEE ceiling stays intact; on android/ios it drives the real
  // plugins. Until WS5 the app never spoke: voice_guidance reached her as
  // silence. _announcer enforces the OPS-059 floor (audio AND haptic on the
  // same severity gate).
  late final AlertActuators _actuators;
  late final AlertAnnouncer _announcer;

  // Tier-1 voice-lane hardening — the HUD chip flag: true while the LAST
  // announce could not be verified as delivered (hardened engine reported
  // unverified), cleared on the next verified speak. Page-owned unless a
  // test injects its own notifier. Never disposed here when injected.
  late final ValueNotifier<bool> _speechUnverified;

  // OPS-059 tactile twin — true while the LAST tactile cue that was OWED did
  // not land (no vibrator / fault / the platform never answered), cleared on
  // the next cue the platform accepts. Same ownership rule as the speech
  // flag: page-owned unless a test injects one, never disposed when injected.
  //
  // Until 2026-08-22 this did not exist, and the comment on the speech chip
  // below asserted the tactile channel was "unaffected either way" — an
  // assumption about a channel nothing had ever measured. Measured on device
  // 2026-08-21, it was firing nothing.
  late final ValueNotifier<bool> _hapticUnverified;

  // A1 pre-drive voice-lane verdict. Starts (and off-device stays) unknown —
  // unknown renders NOTHING (never a false warning where we cannot read the
  // voice list). Resolved async in initState.
  VoiceLaneVerdict _voiceLaneVerdict = VoiceLaneVerdict.unknown;

  // Tier-2 pre-drive audio readiness (media-volume-zero probe). null = probe
  // unavailable (non-Android / test / old-APK-skew) and renders NOTHING —
  // honest-unknown, never a guess. Resolved async in initState alongside the
  // A1 read.
  AudioReadiness? _audioReadiness;

  // Pre-drive tactile readiness. true = the platform reports a vibrator ·
  // false = it reports none (the caution-worthy answer) · null = it did not
  // answer, and null renders NOTHING — same honest-unknown discipline as
  // _audioReadiness and _voiceLaneVerdict. Resolved async on the SAME cadence
  // as the audio probe (_probeAlertChannelReadiness), which is the whole
  // point of AAA's G-3: the two eyes-off channels are probed together or the
  // asymmetry comes back.
  bool? _hapticAvailable;

  // True once HER has tapped 承知しました on the media-muted caution: the
  // strong row collapses to the compact acknowledged line. Informed
  // acknowledgment only — NO behavior gating, haptics stay unconditional,
  // and we NEVER touch her volume (the Tier-3 dignity boundary).
  bool _mediaMutedAcked = false;

  // WS6 — the live in-drive compound-failure caution brain. It is fed HER real
  // position samples (from the GPS listener below), the mocked visibility band
  // (no real visibility sensor yet — honestly labeled in the panel), and the
  // REAL area advisory the app already fetched; it raises an advisory-only
  // caution rung and — the MOMENT the rung RISES — auto-announces on the SAME
  // single _actuators / _announcer as WS5 (injected, so there is exactly ONE
  // actuator + ONE wakelock owner for the whole app). Rendered below in
  // Japanese for HER, so it is on-screen (render-SEE on desktop) AND reaches
  // her eyes-off on a phone. On-device HEAR/FEEL is DEFERRED (OPS-066).
  late final DriveHudController _driveHud;
  static const DriveHudLocalizer _driveHudText = DriveHudLocalizer();
  // EXPLICIT demo override for the visibility band (the panel dropdown), in
  // metres. `null` = NO override → the drive brain reads the LIVE measured
  // reading (JMA AMeDAS, usually null at these stations) and honestly falls to
  // a first-class UNKNOWN (視程 未計測) — NEVER a synthetic "clear". A default
  // of `1500` would be a fabricated clear the road has no sensor to justify:
  // unknown ≠ clear, and only a measured value may clear her.
  double? _mockVisibilityMeters;
  // Simulated GPS-blackout clock: the timestamp of the last fed trusted fix,
  // advanced by _blackoutSeconds each "simulate blackout" press so the honest
  // dot can degrade trusted → dead-reckoning → lost off a device.
  DateTime? _driveHudBaseTime;
  int _blackoutSeconds = 0;

  // Throttle behavior trace.
  final List<_FireAttempt> _attempts = [];

  // LoomFitTelemetry — emit-only stream owned at the integrator boundary.
  // Per loom_fit_telemetry.dart class-doc: the package observes its own
  // firing decisions; the integrator owns storage / display / consent.
  // sngnav-app's role is to subscribe + render development-class
  // observability (calibration substrate, NOT driver-facing advice).
  late final LoomFitTelemetry _telemetry;
  StreamSubscription<LoomFitTelemetryRecord>? _telemetrySub;
  // Rolling list of recent telemetry records, bounded to last 16.
  final List<LoomFitTelemetryRecord> _telemetryRecords = [];
  // Rolling fired-timestamp window for the alertSequence schema field.
  // Maintained at the integrator boundary because AlertDensityThrottle
  // does not expose its internal window (and per the package's
  // emit-only / no-data-harvest design, it should not).
  final List<DateTime> _firedTimestampsWindow = [];

  // JMA observation state.
  JmaResult? _jmaResult;
  bool _jmaLoading = false;

  // W0 detection-survival — last-known GOOD observation, retained across a feed
  // loss so slow-varying winter hazards survive the network dying. Set ONLY on
  // JmaSuccess; NEVER cleared on JmaFailure (that is the whole point). Distinct
  // from _jmaResult, which is overwritten by a JmaFailure.
  JmaObservation? _lastGoodObservation;

  // W0 detection-survival — absence-line announce gate. The ABSENCE-LINE fires
  // ONCE per entry into a dead-zone so a persistent no-reading does not spam;
  // re-armed on the next JmaSuccess (see _announceWatchTransitions). The SLOW
  // stale-ice hazard is deliberately NOT gated (Chair: keep announcing) — it
  // re-warns each feed-loss cycle, rate-limited only by the JMA ticker.
  bool _absenceActive = false; // absence-line announce currently active

  // C2 RED-1 — THE MEMORY. The trip-window-valid hazard bundle, captured at
  // PLAN time (network alive) and consulted in the DEAD ZONE (network gone).
  // This is the source that needs no source: no fetch, no point-query, just the
  // publisher's declared validity window against the clock. It is what stands
  // between HER and silence at T+90.
  TripHazardMemory? _tripHazardMemory;

  // Rise-gate for the forecast line, mirroring _absenceActive: a persistent
  // dead-zone announces the valid forecast ONCE on entry, not every tick.
  // Cry-wolf discipline — the same restraint the absence line gets.
  bool _forecastAnnounceActive = false;

  // BETA_PLAN W1 — invisible-ice (radiative-frost) watch state over the
  // live JMA observation. _lastAnnouncedIceResult is the transition gate: the
  // ice VERDICT last spoken (watch / subZeroFrozen), or null when the channel
  // is not firing — so re-entry re-announces and a cross-0 °C tier change
  // (watch <-> subZeroFrozen) re-speaks the correct distinct line.
  InvisibleIceWatchResult? _invisibleIceResult;
  InvisibleIceWatchResult? _lastAnnouncedIceResult;

  /// Liveness of the measured-weather lane, tracked SEPARATELY from the watch
  /// verdicts.
  ///
  /// The verdicts alone cannot carry this: a feed LOSS clears them to
  /// unknown/null and a cold START leaves them null, and both then look
  /// EXACTLY like a measured all-clear at [_currentMeasuredHazard] — which
  /// feeds the drive brain a not-firing floor. The brain has no channel to say
  /// "we could not look" (see services/advisory_axis.dart for the same
  /// asymmetry on the advisory axis), so the app carries it here and states it
  /// as a first-class unknown on the glance instead. It never raises the rung:
  /// an outage is an unknown, not a hazard (no cry-wolf, Chair 2026-07-23).
  MeasuredWatchFeed _measuredWatchFeed = MeasuredWatchFeed.notYetRead;

  // BETA_PLAN W3 — measured-turmoil (downpour / strong-wind) watch over the
  // same live observation (Chair-ratified 2026-07-09: measured actual
  // weather, never historical assumption). Same transition-gate discipline.
  TurmoilWatchState? _turmoilState;
  bool _turmoilAnnounced = false;

  // W3 in-drive refresh loom: AMeDAS publishes 10-minutely; without a
  // periodic re-fetch the watches only re-evaluate on manual taps — not an
  // in-drive surface. The same tick re-pulls area advisories so a PARKED
  // driver still receives a newly issued JMA warning (movement-gated
  // refresh alone never re-fetches while stationary).
  Timer? _jmaTicker;

  // N8 — real-GPS-blackout watchdog. The degradation machine's poll() was
  // production-wired ONLY to the demo blackout button; in a REAL blackout
  // (tunnel, mountain pass — exactly the compound-failure scenario) no fix
  // events arrive, nothing calls poll, and the dot stays "trusted" forever.
  // This ticker runs while real position sharing is active and, when no fix
  // arrived within the expected cadence, polls the drive brain so trusted →
  // dead-reckoning → lost actually progresses. Decision logic is the
  // top-level [positionWatchdogPollTime] (testable); the demo button stays.
  Timer? _positionWatchdog;
  DateTime? _lastPositionEventAt;
  static const Duration _watchdogTickEvery = Duration(seconds: 15);

  /// The reason carried by the absence held for the brain when no position
  /// event has come. Never shown.
  static const String _noPositionEventYet =
      'No position event since the position stream subscribed';

  /// When the position stream of the current sharing session was subscribed,
  /// by [_now]: for the real stream, once the platform has answered the
  /// permission question; for an injected [HomePage.positionSource], when the
  /// app listens to it, since that stream is the source itself. Null before
  /// then and when she is not sharing.
  DateTime? _herPositionStreamSubscribedAt;

  /// Which sharing session a subscription callback belongs to. A stream from a
  /// session she already stopped can still finish its permission wait and
  /// subscribe; its callback must not start the clock of the next session.
  int _herShareSession = 0;

  /// She is sharing and no position event has arrived within
  /// [kFirstPositionWait] of the subscription ([positionFirstEventOverdue]).
  /// Set by the watchdog tick; the map then says 現在地不明 instead of
  /// nothing, announced once to a screen reader.
  bool _herFirstEventOverdue = false;

  // B32 — the voice-lane + media-volume cautions were probed ONCE in
  // initState: a mid-drive mute (or a mid-drive voice-pack removal) was
  // invisible for the whole drive. This ticker re-probes both (~45 s, and on
  // drive start) so the pre-drive cautions stay TRUE during the drive.
  // Read-only, unchanged dignity boundary: we inform, we never touch her
  // volume.
  Timer? _audioReadinessTicker;

  // AAA F1 — the spoken-lane locale, resolved ONCE from the same inputs the
  // screen uses (widget.locale override first, else device locales against
  // the same ja-first supported list). 'ja' | 'en'.
  late final String _spokenLanguageCode;
  bool get _spokenJa => _spokenLanguageCode == 'ja';

  // Slice 3 — corridor stations along Akita prefecture's inhabited spine.
  List<JmaResult>? _corridorResults;
  bool _corridorLoading = false;

  // Routing state — Slice 2b: A and B → fetch → polyline. Chosen in the route
  // act, never by a touch on her map (ruled 2026-09-14).
  LatLng? _origin;
  LatLng? _destination;
  RouteResult? _routeResult;
  bool _routeLoading = false;

  // B27/B26 — pre-send consent for the OSRM coordinate egress. null =
  // undecided (ask before the first send); true/false = HER remembered
  // choice (persisted via RouteConsentStore when a documents dir exists).
  //
  // SCOPE (B26, honest): full driving_consent wiring is a larger design —
  // its ConsentPurpose vocabulary upstream cannot yet name a
  // coordinate-query (routing) egress; catalog follow-up. Until then THIS
  // app-local persisted consent IS the gate at the app's only coordinate
  // egress outside the location-share disclosure: route coordinates come
  // from map taps, not GPS, so the location-share gate never covered them
  // (JMA receives only an on-device-derived prefecture code; the NWS point
  // query already sits behind the location-share gate).
  bool? _osrmConsent;
  bool _osrmConsentLoaded = false;

  // (e) honest maneuver narration — the NEXT actionable maneuver from the real
  // step list parsed by the ALREADY-BUILT OsrmRoutingEngine pipeline
  // (steps=true), surfaced in the drive flow. `_lastManeuverNarration` holds
  // the most recent gated decision (spoken / hedged / suppressed) so the panel
  // can show what the announcer did. The whole list is not kept: its only
  // reader was a parsed-maneuver count, no longer drawn (2026-09-15).
  RouteManeuver? _nextManeuver;
  ManeuverNarration? _lastManeuverNarration;

  // HER position — Slice 2c. The passenger sits down quietly.
  PositionFix? _herFix;
  StreamSubscription<PositionFix>? _herSub;

  /// Whether an event in THIS sharing session became the position
  /// controller's trusted anchor ([anchorsThisSession]). False when sharing
  /// starts; set only in [_onPositionEvent]. The controller is not reset on
  /// stop, so without this the map drew rings from the previous drive and
  /// from the dev mock (2026-09-13).
  bool _herAnchoredThisSession = false;

  /// The last event of THIS sharing session that the drive brain was not
  /// given, or `null`. Before the session's first trusted fix, an event that
  /// would not be that fix is held back unless a measured condition raises
  /// caution (ruled 2026-09-14): a failure that has not measured the road does
  /// not reach the caution rung by itself. Held, not dropped: a measured
  /// condition that arrives later still gives it to the drive brain.
  PositionFix? _herHeldEvent;

  /// Whether the drive brain has been given any event of THIS sharing session.
  /// The brain is not reset between sessions (a replayed fix must keep meeting
  /// the anchor it is no newer than), so until this is true what it holds is
  /// an earlier session's, and no surface shows it as this one's.
  bool _herFedThisShare = false;

  // Ruled 2026-09-15: the driver with no
  // position in a measured whiteout.

  /// Whether the caution rung the drive brain holds is this drive's: the dev
  /// mock, or a share she is running that has given the brain an event and
  /// that she has not refused. An ended share's estimate is not, and nothing
  /// is told or shown from it.
  bool get _driveHudRungIsThisDrives =>
      _isMockPosition ||
      (_herSub != null && _herFedThisShare && !isLocationRefusal(_herFix));

  /// Whether the position the drive brain holds is this drive's, for every
  /// surface that reads it: the caution card's position lines and the next
  /// turn. As [_driveHudRungIsThisDrives], and not while the rung is the
  /// road's own because no position event has come. Until 2026-09-15 the next
  /// turn read the brain whenever no share ran, so after 停止 a turn was read
  /// aloud from the position she had ended, 10 minutes later as at once.
  bool get _driveHudPositionIsThisDrives =>
      _driveHudRungIsThisDrives && _driveHud.startRung != StartRung.road;

  /// No share is running: she never shared, ended it with 停止, or refused.
  bool get _noShareRunning =>
      (_herSub == null && !_isMockPosition) || isLocationRefusal(_herFix);

  /// This share's platform stream is subscribed and no position event has come
  /// by the first watchdog tick after the subscription. Cleared by any event.
  bool _herNoEventYet = false;

  /// A measured whiteout is open: a fresh reading under 200 m came, and no
  /// fresh reading at or above 200 m has come since. A failed or stale reading
  /// neither opens nor closes it.
  bool _whiteoutOpen = false;

  /// This opening of the whiteout has been told to her, by a share or with no
  /// share running. Only a new opening clears it.
  bool _whiteoutTold = false;

  /// What THIS sharing session has measured about motion, for route setting
  /// (ruled 2026-09-14). A new session starts with none, and so does her "no"
  /// to location: with no session there is no motion evidence, and a driver
  /// who needs to plan in a GPS drought can end sharing to do it.
  ShareMotion _shareMotion = ShareMotion.none;

  /// How many moving readings have arrived. An open route act closes itself
  /// when this changes: only measured motion closes an act she is in.
  final ValueNotifier<int> _movingReadings = ValueNotifier<int>(0);

  /// [_routeSettingOpen] as the route panel was last built, so the watchdog's
  /// tick rebuilds only when a stop has aged out.
  bool? _routeSettingOpenBuilt;

  /// HER map's camera. Until 2026-09-13 nothing moved it but a hand: 8.2 km
  /// out along Route 13 the map held no mark of her in any mode. The rules are
  /// in `her_map_follow.dart`.
  final MapController _herMapController = MapController();

  /// The map has rendered once, so [_herMapController] can move the camera.
  bool _herMapReady = false;

  /// Whether the camera follows her. True from the start; a hand on the map
  /// pauses it, and only her return control resumes it.
  bool _herMapFollowing = true;

  /// Her last trusted fix in THIS sharing session: where follow last put the
  /// camera, and where her return control takes it. Reset when sharing starts,
  /// so a return never goes to a previous session's place.
  LatLng? _herLastTrustedThisSession;

  // Offline basemap (2026-07-01; real tiles 2026-07-10).
  // Loaded once at init from the bundled MBTiles asset, then handed to
  // AkitaMap so Akita renders OFFLINE-FIRST (network only for uncovered
  // tiles) — the basemap no longer goes blank when the network is gone. Null
  // until loaded / on any failure ⇒ plain network basemap (honest
  // degradation). The bundled tiles are REAL OpenStreetMap cartography in a
  // minimal style (see services/offline_basemap.dart honest bound).
  offline_tiles.OfflineTileProvider? _offlineBaseProvider;

  // Slice 2d — dev-only mock position. Amber dot, never blue, so
  // mock cannot be visually mistaken for real GPS.
  bool _isMockPosition = false;

  // Sub-bundle 2 — DriverState-axis scaffolding inputs (NSC 0.10.0 #28/#29/#30).
  // All three are advisory inputs to forDriverContext; null means
  // "integrator has no signal" and the factory falls back to the
  // per-profile + live-context baseline.
  CircadianPhase? _circadianPhase;
  SessionState? _sessionState;
  Confidence? _confidence;
  // Driver-always-drives invariant: high-confidence cap-loosening is
  // ONLY permitted with affirmative driver confirmation. Default false.
  bool _isHighConfidenceConfirmed = false;
  // Sub-bundle 2 sliders for SessionState compose-fields.
  int _consecutiveDrivingDays = 0;
  CumulativeFatigueClass _cumulativeFatigue = CumulativeFatigueClass.rested;

  // Sub-bundle 3 — GlanceBudgetTracker + voice-pace + alert-explainer-sheet.
  // The tracker accumulates simulated glance events; integrator owns the
  // event source per package contract.
  late final GlanceBudgetTracker _glanceBudget;
  StreamSubscription<GlanceBudgetEvent>? _glanceBudgetSub;
  // Most-recent budget-event observed (for surface rendering).
  GlanceBudgetEvent? _lastGlanceEvent;
  // Voice-guidance config with budget-aware pace opt-in (see voice_guidance
  // 0.6.0 budget_aware_pace_profile.dart). Held for display-only; this
  // demo does NOT wire a TTS engine (sngnav-app is alpha visual surface).
  final VoiceGuidanceConfig _voiceConfig = const VoiceGuidanceConfig(
    budgetAwarePace: BudgetAwarePaceProfile(),
  );
  // Number of glance events recorded so far in the simulation.
  int _glanceEventsRecorded = 0;

  // Sub-bundle 4 — PerformanceBudget + DataBudget + ViewportRenderBudgetBloc.
  // Per the package contracts: integrator constructs all three with
  // per-profile config; bloc subscribes to the two budget streams via
  // attachPerformanceBudgetStream / attachDataBudgetStream and emits
  // a composed ViewportRenderState with RenderFidelity.
  offline_tiles.PerformanceBudget? _perfBudget;
  snow_rendering.DataBudget? _dataBudget;
  ViewportRenderBudgetBloc? _viewportBloc;
  // Counts of simulated frames / fetches recorded in the panel.
  int _framesRecorded = 0;
  int _fetchesRecorded = 0;

  // Slice — multi-source advisory ingestion (NWS + JMA).
  late final AdvisoryService _advisoryService;
  late final NoaaNwsClient _nwsClient;
  Future<void>? _advisoryInitFuture;
  AdvisoryAggregateResult? _advisoryResult;
  bool _advisoryLoading = false;
  String? _advisoryErrorMessage;

  /// Wall-clock instant of the fetch that produced the advisories currently
  /// in [_advisoryResult] (i.e. the last fetch whose data we display as
  /// its own). Feeds the visible stale-age label while retained.
  DateTime? _advisoryFetchedAt;

  /// True when [_advisoryResult]'s advisories were RETAINED from a prior
  /// successful fetch because the latest fetch failed with provider errors
  /// and no advisories. Retained hazards render with a stale label and
  /// still feed the drive brain; the all-clear is never retained.
  bool _advisoryRetained = false;

  /// N10 (stationary-expiry) — minute ticker that culls a RETAINED advisory
  /// past its publisher-declared expires while NO fetch cycle is firing
  /// (fetches are movement-gated at ~1 km; a parked driver gets none). See
  /// [cullExpiredRetainedAdvisories].
  Timer? _advisoryExpiryTicker;

  /// False when the LAST advisory fetch was for a point NO registered
  /// publisher covers ([AdvisoryService.coversPoint]) — the empty result is
  /// then "nobody was asked", not a publisher all-clear, and AdvisoryCards
  /// renders the honest cannot-check-here line instead of calm.
  bool _advisoryPointCovered = true;
  // Last (lat, lon) used for an advisory fetch — refresh-only-on-change.
  double? _lastAdvisoryLat;
  double? _lastAdvisoryLon;

  @override
  void initState() {
    super.initState();
    // WS5 — construct the actuator layer + announcer. Hold the screen awake
    // while this navigation surface is active so a driver glancing at a live
    // hazard never finds a dark screen. Foreground-only: released in dispose;
    // NO background wakelock. (Product tension noted in AndroidManifest.xml:
    // a true multi-hour screen-off drive would need a foreground Service —
    // its perms return to the manifest only when that Service is actually
    // built, user-visible and driver-initiated — never silent background
    // location tracking, which we refuse for dignity, hence NO
    // ACCESS_BACKGROUND_LOCATION.)
    // Tier-1 voice-lane hardening — the speech-verification flag + its feed.
    // The hardened engine (inside defaultAlertActuators) reads the platform's
    // own utterance-completion report and drives these callbacks; unverified
    // deliveries also land one line in the same LocalErrorLog as crashes.
    // `mounted` guard: TTS completion callbacks are async and can outlive
    // this state.
    _speechUnverified = widget.speechUnverified ?? ValueNotifier<bool>(false);
    _speechUnverified.addListener(_onSpeechVerificationChanged);
    _hapticUnverified = widget.hapticUnverified ?? ValueNotifier<bool>(false);
    _hapticUnverified.addListener(_onHapticVerificationChanged);
    _actuators = widget.actuators ??
        defaultAlertActuators(
          errorLog: widget.errorLog,
          onSpeechUnverified: () {
            if (mounted) _speechUnverified.value = true;
          },
          onSpeechVerified: () {
            if (mounted) _speechUnverified.value = false;
          },
          // The tactile half. Both directions are wired deliberately: without
          // the verified path a single transient fault would pin the chip on
          // HER screen for the rest of the drive, which is its own dishonesty.
          onHapticUnverified: () {
            if (mounted) _hapticUnverified.value = true;
          },
          onHapticVerified: () {
            if (mounted) _hapticUnverified.value = false;
          },
        );
    _announcer = AlertAnnouncer(actuators: _actuators);
    // A1 + Tier-2 — pre-drive voice-lane + media-volume reads (honest
    // unknown/null off-mobile; fail-soft). B32: no longer once-only — the
    // same probes re-run on a ticker + on drive start (_probeAudioCautions)
    // so a MID-DRIVE mute or voice-pack change is detected, not just a
    // pre-drive one.
    _probeAlertChannelReadiness();
    _audioReadinessTicker = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _probeAlertChannelReadiness(),
    );
    // AAA F1 — resolve the spoken-lane locale ONCE, from the same inputs
    // MaterialApp resolves the screen from: the injected override first,
    // else the device locale list against the identical ja-first supported
    // list (basicLocaleListResolution is Flutter's default resolver). The
    // screen and the voice can therefore never diverge.
    final resolvedSpoken = widget.locale ??
        basicLocaleListResolution(
          WidgetsBinding.instance.platformDispatcher.locales,
          const [Locale('ja'), Locale('en')],
        );
    _spokenLanguageCode = resolvedSpoken.languageCode == 'ja' ? 'ja' : 'en';
    unawaited(_actuators.keepAwake(true));
    // Offline basemap — load the bundled Akita MBTiles archive and
    // hand the resulting OfflineTileProvider to AkitaMap. Async + fail-soft:
    // a null result leaves the basemap on the plain network layer.
    unawaited(_loadOfflineBasemap());
    // COLD START in the dead zone: she rebooted on the roadside. The memory must
    // come back from DISK, before any network is attempted — because there may
    // never be one. This is the load that makes the map stop being silent.
    unawaited(_loadTripHazardMemory());
    // WS6 — inject the app's SINGLE actuator + announcer into the drive brain
    // (it never resolves its own — one actuator, one wakelock owner). A rising
    // caution rung fires _announcer.announce (audio + haptic). Listen so the
    // on-screen WS6 panel repaints when the estimate / caution changes.
    _driveHud = DriveHudController(
      actuators: _actuators,
      announcer: _announcer,
      text: _driveHudText,
      // AAA F1: was a hardcoded 'ja' — DriveHudLocalizer ships full ja+en
      // pairs, so the HUD's spoken lane follows the resolved locale.
      localeTag: _spokenLanguageCode,
    );
    // AQ4: a line raised by a value nobody measured is spoken as a test value.
    _driveHud.spokenFromTestValue = _spokenFromTestValue;
    _driveHud.addListener(_onDriveHudChanged);
    _telemetry = LoomFitTelemetry();
    _telemetrySub = _telemetry.records.listen((record) {
      if (!mounted) return;
      setState(() {
        _telemetryRecords.add(record);
        // Bound to last 16 records (rolling).
        if (_telemetryRecords.length > 16) {
          _telemetryRecords.removeAt(0);
        }
      });
    });
    // Sub-bundle 3: GlanceBudgetTracker (default 12s NHTSA budget).
    _glanceBudget = GlanceBudgetTracker();
    _glanceBudgetSub = _glanceBudget.budgetEvents.listen((event) {
      if (!mounted) return;
      setState(() => _lastGlanceEvent = event);
    });
    // Sub-bundle 4: PerformanceBudget + DataBudget + viewport bloc.
    // Construct per the active default profile (ageingRural per V21).
    _rebuildSubBundle4For(_profile);
    _nwsClient = NoaaNwsClient(userAgent: kSngnavAppUserAgent);
    // Region-gate each provider to the geography its publisher actually
    // covers, so HER Akita point goes ONLY to JMA and the US NWS endpoint
    // is never called (no HTTP-400 error card, and no coordinate leaked to
    // a service that cannot help her). See services/provider_coverage.dart.
    _advisoryService =
        AdvisoryService(providers: widget.advisoryProviders ?? [
      CoveredProvider(
        provider: NoaaAdvisoryProvider(client: _nwsClient),
        covers: nwsCoverage,
      ),
      CoveredProvider(
        provider: buildJmaAdvisoryProvider(userAgent: kSngnavAppUserAgent),
        covers: jmaCoverage,
      ),
    ]);
    _advisoryInitFuture = _advisoryService.init();
    _refreshJma();
    _refreshCorridor();
    // W3 — in-drive refresh loom (see the _jmaTicker field note). 10-minute
    // cadence matches AMeDAS's own publication interval: one station GET +
    // one advisory refresh per tick — polite by construction. Foreground
    // only in practice (Android freezes a cached app's timers; the wakelock
    // keeps the surface — and so this ticker — alive during a drive).
    _jmaTicker = Timer.periodic(const Duration(minutes: 10), (_) {
      _refreshJma();
      _onAdvisoryRefreshTapped();
    });
    // N10 (stationary-expiry) — honor the publisher's validity bound between
    // movement-gated fetch cycles: a retained advisory whose expires passes
    // while she is parked must drop, not render as current indefinitely.
    _advisoryExpiryTicker =
        Timer.periodic(const Duration(minutes: 1), (_) => _advisoryExpiryTick());
  }

  /// N10 (stationary-expiry) — one tick: cull expired advisories from a
  /// RETAINED result. Culling to empty leaves the empty+providerErrors shape,
  /// which renders the honest degraded-unknown banner (never all-clear), and
  /// the drive brain stops being fed the expired hazard on the next fix.
  void _advisoryExpiryTick() {
    if (!mounted || !_advisoryRetained) return;
    final result = _advisoryResult;
    if (result == null) return;
    final culled = cullExpiredRetainedAdvisories(
      result,
      _now(),
      lastFreshAt: _advisoryFetchedAt,
    );
    if (culled == null) return;
    setState(() => _advisoryResult = culled);
  }

  /// B32 — run BOTH audio-caution probes (A1 voice-lane + Tier-2 media
  /// volume). Called from initState, from the ~45 s re-probe ticker, and on
  /// drive start (share-location / mock-position), so a mid-drive mute is
  /// detected while the warning still matters.
  ///
  /// Retention discipline (D3: absence must never render as calm — and its
  /// dual, a proven caution must never be CLEARED by a failed read):
  /// - voice lane: `unknown` (read failed / unreadable) NEVER overwrites a
  ///   prior proven verdict — only a proven verdict (ready / degraded)
  ///   replaces one. A transient engine hiccup must not hide the caution.
  /// - media volume: a `null` probe result keeps the prior reading, same
  ///   reason. A fresh UNMUTED→MUTED transition re-arms the acknowledgment
  ///   (`_mediaMutedAcked = false`): a NEW mid-drive mute is a new event and
  ///   must surface at full strength, not arrive pre-acknowledged from a
  ///   mute she dismissed an hour ago.
  /// Probes BOTH eyes-off channels on one cadence.
  ///
  /// ⚑ Was `_probeAudioCautions` until 2026-08-22. AAA's verdict §2.1 found
  /// the audio channel probed at four triggers and the tactile channel at
  /// none — *"the channel with the higher dignity load has the weaker
  /// instrument."* Giving the tactile probe four call sites of ITS OWN would
  /// have recreated that defect the first time someone added a fifth audio
  /// trigger and forgot this one. One method, one cadence; the anti-drift
  /// test in `test/actuators/haptic_report_wiring_test.dart` fails if either
  /// probe is lifted out.

  /// The shape every eyes-off readiness probe must have — held in ONE place so
  /// the next one cannot be written without it.
  ///
  /// ⚑ **Why a helper and not a convention.** `haptic_report_wiring_test.dart`
  /// fails if a probe is *lifted out* of [_probeAlertChannelReadiness], which
  /// protects the CADENCE. Nothing protected the SHAPE: a fourth channel added
  /// with a missing [isUnknown] test would render *"could not tell"* as a real
  /// answer, and the surface would show a verdict nobody measured.
  ///
  /// That is the exact cause class measured 2026-08-30 in AGL's shipped
  /// `ondemandnavi`: `guidance()` discards `system()`'s return and backgrounds
  /// the call, so a failed announcement is indistinguishable from a delivered
  /// one. A driver-facing channel has THREE outcomes — ready, not-ready and
  /// UNKNOWN — and every defect of this family is the third collapsing into
  /// one of the other two (V16: ambiguity must not route toward pass).
  ///
  /// The five invariants, now structural rather than repeated:
  ///  1. `unawaited` — a probe never blocks a frame.
  ///  2. `!mounted` — no `setState` after dispose.
  ///  3. **[isUnknown] — an unmeasured answer changes NOTHING on screen.**
  ///  4. [unchanged] — no rebuild churn on the 45 s tick.
  ///  5. `catchError` — a probe that throws degrades the probe, never the app.
  ///
  /// Behaviour is identical to the three inlined blocks this replaced; only
  /// the structure moved.
  void _applyProbe<T>(
    Future<T> probe, {
    required bool Function(T) isUnknown,
    required bool Function(T) unchanged,
    required void Function(T) apply,
  }) {
    unawaited(
      probe.then((value) {
        if (!mounted || isUnknown(value)) return;
        if (unchanged(value)) return;
        setState(() => apply(value));
      }).catchError((Object _) {}),
    );
  }

  void _probeAlertChannelReadiness() {
    _applyProbe<VoiceLaneVerdict>(
      (widget.voiceLaneReader ?? readVoiceLaneReadiness)(),
      isUnknown: (v) => v == VoiceLaneVerdict.unknown,
      unchanged: (v) => v == _voiceLaneVerdict,
      apply: (v) => _voiceLaneVerdict = v,
    );
    unawaited(
      (widget.audioReadinessProbe ?? const ChannelAudioReadinessProbe())
          .read()
          .then((reading) {
        if (!mounted || reading == null) return;
        final prior = _audioReadiness;
        if (prior != null &&
            prior.mediaVolume == reading.mediaVolume &&
            prior.mediaVolumeMax == reading.mediaVolumeMax &&
            prior.ttsServiceVisible == reading.ttsServiceVisible) {
          return; // unchanged — no rebuild churn on the 45 s tick
        }
        final wasMuted = prior?.mediaMuted ?? false;
        setState(() {
          _audioReadiness = reading;
          if (!wasMuted && reading.mediaMuted) _mediaMutedAcked = false;
        });
      }).catchError((Object _) {}),
    );
    // The tactile half — the same shape, the same fail-soft, the same
    // honest-unknown. A null answer changes nothing on screen.
    _applyProbe<bool?>(
      (widget.hapticReadinessProbe ?? const DriverHapticReadinessProbe()).read(),
      isUnknown: (v) => v == null,
      unchanged: (v) => v == _hapticAvailable,
      apply: (v) => _hapticAvailable = v,
    );
  }

  /// Sub-bundle 4 — (re)build PerformanceBudget + DataBudget +
  /// ViewportRenderBudgetBloc for the active profile. Called from
  /// initState and from the profile dropdown when the cohort changes
  /// (per-cohort budgets and floor differ; the bloc must be reconfigured).
  void _rebuildSubBundle4For(DriverProfile profile) {
    // Tear down prior instances if any (profile change path).
    _perfBudget?.dispose();
    _dataBudget?.dispose();
    _viewportBloc?.close();
    final perf = offline_tiles.PerformanceBudget(
      config: offline_tiles.PerformanceBudgetConfig.forProfile(profile),
    );
    final data = snow_rendering.DataBudget(
      config: snow_rendering.DataBudgetConfig.forProfile(profile),
    );
    final bloc = ViewportRenderBudgetBloc(
      config: ViewportRenderConfig.forProfile(profile),
    );
    bloc.attachPerformanceBudgetStream(perf.budgetEvents);
    bloc.attachDataBudgetStream(data.budgetEvents);
    _perfBudget = perf;
    _dataBudget = data;
    _viewportBloc = bloc;
    _framesRecorded = 0;
    _fetchesRecorded = 0;
  }

  Future<void> _loadOfflineBasemap() async {
    final provider = await loadAkitaOfflineTileProvider();
    if (!mounted) {
      // Widget gone before load finished — release the archive we opened.
      await provider?.dispose();
      return;
    }
    if (provider != null) {
      setState(() => _offlineBaseProvider = provider);
    }
  }

  @override
  void dispose() {
    // WS5 — release the screen wakelock when this surface leaves (foreground-
    // only contract). No-op on desktop/test.
    unawaited(_actuators.keepAwake(false));
    _jmaTicker?.cancel();
    _positionWatchdog?.cancel();
    _audioReadinessTicker?.cancel();
    _advisoryExpiryTicker?.cancel();
    // Close the offline MBTiles archive (sqlite3) + its network provider.
    unawaited(_offlineBaseProvider?.dispose());
    _speechUnverified.removeListener(_onSpeechVerificationChanged);
    _hapticUnverified.removeListener(_onHapticVerificationChanged);
    _driveHud.removeListener(_onDriveHudChanged);
    _driveHud.dispose();
    _herSub?.cancel();
    _telemetrySub?.cancel();
    _telemetry.dispose();
    _glanceBudgetSub?.cancel();
    _glanceBudget.dispose();
    _perfBudget?.dispose();
    _dataBudget?.dispose();
    _viewportBloc?.close();
    _nwsClient.close();
    _herMapController.dispose();
    _movingReadings.dispose();
    _developerPageRevision.dispose();
    super.dispose();
  }

  void _shareLocation() {
    if (_herSub != null) return;
    setState(() {
      _herFix = null;
      _isMockPosition = false;
      _herAnchoredThisSession = false;
      _herLastTrustedThisSession = null;
      _herPositionStreamSubscribedAt = null;
      _herFirstEventOverdue = false;
      _herHeldEvent = null;
      _herFedThisShare = false;
      _shareMotion = ShareMotion.none;
    });
    // Ruled 2026-09-15: a share she starts
    // herself begins with nothing told and no rung held.
    _herNoEventYet = false;
    _driveHud.startShare();
    final session = ++_herShareSession;
    // B32 — drive start: re-probe BOTH eyes-off channels NOW (the initState
    // read may be app-open-hours old; the drive is when a mute matters — and
    // equally when a dead vibrator matters, for the driver who has nothing
    // else).
    _probeAlertChannelReadiness();
    final injected = widget.positionSource;
    _herSub = (injected ??
            () => herPositionStream(
                  onPlatformStreamSubscribed: () {
                    if (mounted && session == _herShareSession) {
                      _herPositionStreamSubscribedAt = _now();
                    }
                  },
                ))()
        .listen(
      _onPositionEvent,
      // D10 — an ERRORED event must land on the same honest surface an
      // honest unavailability does.
      //
      // [herPositionStream]'s own library doc promises it emits
      // PositionUnavailable on a stream error and "never silently stalls on a
      // stale fix". Today that promise is kept by ONE implementation and
      // enforced by nothing — and this is the app's only position ingest,
      // over a SWAPPABLE source ([HomePage.positionSource]; the dead-reckoning
      // fallback her_position.dart names as deferred). An error arriving here
      // with no handler goes to the zone, which is invisible to her in a
      // release build, while her last dot stays on screen looking measured
      // until the N8 watchdog degrades it up to a 30 s cadence later. The
      // abstention must reach her pixel at the instant the loom knows it,
      // not a cadence after (AAE-6/AAE-7).
      //
      // The reason string matches her_position.dart's own wrapper verbatim, so
      // AppL10n.gpsUnavailable renders it in her language
      // ('GPSストリームのエラー'), and the exception text after the wrapper
      // never reaches her line (ruled 2026-09-14). An error here has no typed
      // cause: this source is swappable, and only herPositionStream types
      // what the platform said.
      //
      // Deliberately NOT cancelOnError: an error is one bad event, not the end
      // of the drive. Dart leaves the subscription live by default, so a feed
      // that recovers can still tell her she is found again.
      onError: (Object e) =>
          _onPositionEvent(PositionUnavailable('GPS stream error: $e')),
    );
    // An injected source is the position stream itself: it is subscribed now.
    // The real stream reports its own subscription, after the permission
    // answer, through the callback above.
    if (injected != null) _herPositionStreamSubscribedAt = _now();
    // N8 — start the blackout watchdog for the real position feed.
    _positionWatchdog ??=
        Timer.periodic(_watchdogTickEvery, (_) => _watchdogTick());
  }

  /// One event from HER position feed: a fix, an honest unavailability, or a
  /// stream error converted into one by [_shareLocation]'s onError. Single
  /// path, so all three keep the watchdog fed and reach the same surfaces.
  void _onPositionEvent(PositionFix fix) {
    if (!mounted) return;
    // Ruled 2026-09-15: an event came.
    _herNoEventYet = false;
    // Location is off for this app (permission denied, now or for good): her
    // setting, not a GPS failure. It is NOT fed to the drive brain, which,
    // with no fix ever, rates "no position at all" its top concern and speaks
    // it at critical severity: measured 2026-09-13, a denial got the critical
    // haptic, the line inviting her to stop, and 停車の検討, while a driver
    // who never shared got none of it. It does not arm the blackout watchdog
    // either: that exists to degrade a feed that claims to be live, and a
    // denied feed never will be; polling it would raise the same alarm 30 s
    // later. The map and the line under it still say so (位置情報オフ). Read
    // from the typed cause only: a reason's free text can carry exception
    // text, and acting on it could silence a real failure.
    if (isLocationRefusal(fix)) {
      // Ruled 2026-09-15: what this share
      // told stays told. Nothing is told here: nothing answers her no.
      _noteShareToldWhiteout();
      _forgetAdvisoryPointOfTheShare();
      _positionWatchdog?.cancel();
      _positionWatchdog = null;
      _lastPositionEventAt = null;
      _herHeldEvent = null;
      setState(() {
        _herFix = fix;
        _shareMotion = ShareMotion.none;
      });
      return;
    }
    // Before this session's first trusted fix, an event that would not be
    // that fix is not given to the drive brain, unless a measured condition
    // raises caution (ruled 2026-09-14). With no trusted fix ever, the brain
    // rates "no position at all" its top concern and always speaks it: a
    // failed start or location services off got the critical haptic, the line
    // inviting her to stop and 停車の検討, identically in a measured clear
    // 1,500 m and a measured 80 m whiteout, while a driver who never shared
    // got none of it. The map still says 現在地不明.
    //
    // Keyed on the session having no trusted fix, never on the event's type:
    // a sample the brain would refuse (an iOS accuracy of -1) or a fix no
    // newer than an earlier session's anchor is no position either, and a
    // gate that asked only "is it an unavailability?" would still give both
    // to the drive brain, which refuses them. The watchdog stays armed; its
    // clock is started only by an event the brain is given.
    if (!_herAnchoredThisSession &&
        !_driveHud.wouldTrust(fix) &&
        !_measuredConditionRaisesCaution()) {
      _herHeldEvent = fix;
      setState(() => _herFix = fix);
      _maybeRefreshAdvisoriesForFix(fix);
      _readMotion(fix, onTrustedFix: false);
      return;
    }
    _herHeldEvent = null;
    // N8 — any event (fix OR honest unavailability) proves the position
    // pipeline is alive and feeding the drive brain itself; the watchdog
    // only covers the SILENT drought where nothing arrives at all.
    _lastPositionEventAt = _now();
    setState(() => _herFix = fix);
    _maybeRefreshAdvisoriesForFix(fix);
    // Ruled 2026-09-15: asked before feeding.
    _driveHud.startRung =
        !_herAnchoredThisSession && !_driveHud.wouldTrust(fix)
            ? StartRung.unlocated
            : StartRung.none;
    _feedDriveHud(fix);
    _herFedThisShare = true;
    // After the drive brain has taken the event: did it become the anchor?
    final trusted = anchorsThisSession(
      fix: fix,
      estimate: _driveHud.estimate,
      isMock: _isMockPosition,
    );
    if (trusted) {
      setState(() => _herAnchoredThisSession = true);
    }
    _readMotion(fix, onTrustedFix: trusted);
    // Follow: only a trusted fix is a place to move the camera to.
    final target = followTargetAfter(
      fix: fix,
      estimate: _driveHud.estimate,
      isMock: _isMockPosition,
    );
    if (target != null) {
      _herLastTrustedThisSession = target;
      if (_herMapFollowing) _moveHerMapTo(target);
    }
  }

  /// Move HER map's camera to [target], at a zoom inside the offline archive.
  /// Called from event and button handlers only, never during build.
  void _moveHerMapTo(LatLng target) {
    if (!_herMapReady) return;
    _herMapController.move(
      target,
      followZoom(_herMapController.camera.zoom),
    );
  }

  void _onHerMapReady() {
    _herMapReady = true;
    final target = _herLastTrustedThisSession;
    if (_herMapFollowing && target != null) _moveHerMapTo(target);
  }

  /// A finger landing on the map pauses follow at that moment, before any
  /// gesture resolves: a trusted fix arriving under her finger must not move
  /// the map she is touching (ruled 2026-09-13). A touch does nothing else: it
  /// sets no route point and clears none (ruled 2026-09-14). Only her return
  /// control resumes follow.
  void _onHerMapTouched() {
    if (_herMapFollowing) setState(() => _herMapFollowing = false);
  }

  /// A hand on the map pauses follow: the machine yields to the person.
  void _onHerMapEvent(MapEvent event) {
    if (_herMapFollowing && isHandMovingMap(event.source)) {
      setState(() => _herMapFollowing = false);
    }
  }

  /// Her return control: follow resumes, and the camera goes back to her last
  /// trusted fix in this session, where her dot or ring is. With none yet it
  /// stays, and the next trusted fix moves it.
  void _returnHerMapToPosition() {
    setState(() => _herMapFollowing = true);
    final target = _herLastTrustedThisSession;
    if (target != null) _moveHerMapTo(target);
  }

  /// The return control shows while a hand has paused follow and she shares
  /// her real position. Never in mock: using the mock ends sharing.
  bool get _showHerMapReturnControl => !_herMapFollowing && _herSub != null;

  /// N8 — one watchdog tick: poll the drive brain iff no position event
  /// arrived within the expected cadence (decision table:
  /// [positionWatchdogPollTime]), so a REAL GPS blackout degrades the honest
  /// dot exactly like the demo button does.
  void _watchdogTick() {
    if (!mounted) return;
    // Nothing has arrived for 60 s since the stream subscribed: the map stops
    // being silent. The drive brain is not fed anything, so nothing alarms:
    // no event exists to feed it, and whether a first fix that never comes
    // should reach the alarm is not decided here (ruled 2026-09-14: landing
    // these words must not make this state louder than it was).
    var overdueNow = false;
    if (!_herFirstEventOverdue &&
        positionFirstEventOverdue(
          now: _now(),
          subscribedAt: _herPositionStreamSubscribedAt,
          eventArrived: _herFix != null,
        )) {
      setState(() => _herFirstEventOverdue = true);
      overdueNow = true;
    }
    // Ruled 2026-09-15: the first fix never
    // arrives. At the first tick after the platform stream is subscribed with
    // no event, the absence is held as an event the brain has not been given,
    // and it reaches the brain where a measured condition raises caution: the
    // road's own rung inside 60 s, an unlocated position from 60 s. The tick,
    // not the subscription callback: a platform that refuses at subscribe
    // reports it after the callback (her_position.dart, the typed
    // PermissionDeniedException), and nothing may answer her no.
    final subscribedAt = _herPositionStreamSubscribedAt;
    if (_herSub != null &&
        subscribedAt != null &&
        _herFix == null &&
        !_herNoEventYet) {
      _herNoEventYet = true;
      _herHeldEvent = const PositionUnavailable(_noPositionEventYet);
      _giveHeldEventIfMeasured();
    } else if (overdueNow &&
        _herNoEventYet &&
        _herHeldEvent == null &&
        _driveHud.startRung == StartRung.road) {
      _driveHud.startRung = StartRung.unlocated;
      _driveHud.poll(now: _now());
    }
    final pollAt = positionWatchdogPollTime(
      now: _now(),
      lastPositionEventAt: _lastPositionEventAt,
      demoClock: _driveHudBaseTime
          ?.add(Duration(seconds: _blackoutSeconds)),
    );
    if (pollAt != null) _driveHud.poll(now: pollAt);
    // A stop is current for no longer than the drought cadence (ruled
    // 2026-09-14), checked here on the same tick, so route setting closes
    // when a stop ages out even if no event arrives to rebuild the page.
    if (_routeSettingOpenBuilt != null &&
        _routeSettingOpenBuilt != _routeSettingOpen) {
      setState(() {});
    }
  }

  void _useMockPosition() {
    // A position nobody measured never replaces a share she is running
    // (2026-09-16): under a measured 300 m her failed share is the top rung,
    // and a trusted mock fix in its place was the middle one. The control is
    // offered only with no share running; this holds it whatever calls it.
    if (_herSub != null) return;
    _herSub?.cancel();
    _herSub = null;
    // N8 — the mock dot is a static dev tool: the watchdog would "honestly"
    // degrade a position that is not claiming to be live. The demo blackout
    // button is the degradation driver in mock mode.
    _positionWatchdog?.cancel();
    _positionWatchdog = null;
    _lastPositionEventAt = null;
    _herPositionStreamSubscribedAt = null;
    _herFirstEventOverdue = false;
    _herHeldEvent = null;
    _herShareSession++;
    // B32 — the dev drive start re-probes too (symmetry with real start).
    _probeAlertChannelReadiness();
    final mockFix = PositionAvailable(
      latitude: akitaStation.latitude,
      longitude: akitaStation.longitude,
      accuracyMeters: 35,
      timestamp: DateTime.now(),
    );
    setState(() {
      _isMockPosition = true;
      _herFix = mockFix;
    });
    _maybeRefreshAdvisoriesForFix(mockFix);
    _herNoEventYet = false;
    _driveHud.startRung = StartRung.none;
    _feedDriveHud(mockFix);
  }

  // ===== WS6 — feed the live drive brain + the on-screen caution panel =====

  void _onDriveHudChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onSpeechVerificationChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onHapticVerificationChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// Push the app's live environment (real advisory + mocked visibility; speed
  /// is unknown — the fix carries none) onto the drive brain, then feed the
  /// position sample. [DriveHudController.onPositionFix] recomputes the caution
  /// and, if the rung RISES, auto-announces on the single _announcer.
  /// Visibility metres fed to the drive brain. Honest source of truth, in order:
  ///   1. an explicit DEMO override (the band dropdown), when set; else
  ///   2. the LIVE measured reading (JMA AMeDAS — usually null here); else
  ///   3. null — a first-class UNKNOWN the advisor honours (視程 未計測).
  /// NEVER a synthetic clear: the road carries no visibility sensor, so absence
  /// of a reading is reported as unknown, never as "clear".
  ///
  /// Ruled 2026-09-15, invariant 2026-09-16: the demo value is read only where
  /// it ADDS caution ([visibilityForCaution]). Until then it won outright, and
  /// under a measured 80 m a demo 1500 m took the top rung, its cause and its
  /// announce line off her card.
  VisibilityForCaution get _visibilityForCaution => visibilityForCaution(
        measuredMeters: _measuredVisibilityMeters,
        measuredAgeSeconds: _measuredVisibilityAgeSeconds(),
        testMeters: _mockVisibilityMeters,
      );

  double? get _effectiveVisibilityMeters => _visibilityForCaution.meters;

  /// Age (seconds) of the visibility reading actually fed, or null = unknown age.
  /// A demo value, when it is read, counts as fresh (0). A live reading carries
  /// its REAL staleness from `fetchedAt` — the advisor treats an over-window
  /// age as stale→unknown, so an old reading can never masquerade as fresh.
  double? _effectiveVisibilityAgeSeconds() => _visibilityForCaution.ageSeconds;

  /// The station's reading alone, never a demo value.
  double? get _measuredVisibilityMeters =>
      _lastGoodObservation?.visibilityMeters?.toDouble();

  double? _measuredVisibilityAgeSeconds() {
    final obs = _lastGoodObservation;
    if (obs == null || obs.visibilityMeters == null) return null;
    return _now().difference(obs.fetchedAt).inSeconds.toDouble();
  }

  void _feedDriveHud(PositionFix fix) {
    // Set the environment fields directly (no recompute yet), so onPositionFix
    // does the single recompute+announce with the current environment.
    _driveHud.visibilityMeters = _effectiveVisibilityMeters;
    _driveHud.visibilityAgeSeconds = _effectiveVisibilityAgeSeconds();
    _driveHud.advisorySeverity = readAdvisoryAxis(_advisoryResult).level;
    // Never her speed (ruled 2026-09-14): with no visibility reading the
    // advisor counts the missing reading as a degraded condition, and a known
    // speed above 13.4 m/s spoke a caution with a haptic on an ordinary drive.
    // Her ring takes the speed from the fix itself.
    _driveHud.speedMetersPerSecond = null;
    _driveHud.measuredHazard = _currentMeasuredHazard();
    // A fresh trusted fix resets the blackout clock; a PositionUnavailable
    // (denied / revoked / error / non-finite) degrades honestly toward lost,
    // and so does a sample with no measured accuracy (ruled 2026-09-14).
    if (fix is PositionAvailable && fix.accuracyMeters != null) {
      _driveHudBaseTime = fix.timestamp;
      _blackoutSeconds = 0;
    }
    _driveHud.onPositionFix(fix);
  }

  /// The current measured-weather hazard floor from the app's own JMA watches.
  /// Null-safe by construction: a feed-loss cycle leaves both watches
  /// non-firing (`_refreshJma` sets the live verdicts to unknown/null), so no
  /// STALE hazard keeps the rung raised — the dead-zone memory lane handles the
  /// offline case separately.
  ///
  /// HONEST BOUND — this floor CANNOT distinguish "measured, and clear" from
  /// "we could not look". A cold start, a failed read and a genuine all-clear
  /// all produce [MeasuredWeatherHazard.none]. That is deliberate on the RUNG
  /// (an outage is an unknown, not a hazard — raising it would cry wolf every
  /// time the network hiccuped, Chair 2026-07-23), and it is why the liveness
  /// is tracked separately in [_measuredWatchFeed] and reported as a
  /// first-class unknown by [_appUnknowns]. Do not read a `none` here as
  /// evidence about the road.
  MeasuredWeatherHazard _currentMeasuredHazard() => measuredWeatherHazardFrom(
        blackIceFiring: _invisibleIceResult == InvisibleIceWatchResult.watch,
        turmoilFiring: _turmoilState?.anyCaution ?? false,
      );

  /// Push the freshly-evaluated measured-weather floor onto the drive brain and
  /// recompute NOW (not only on the next position event), so a JMA reading that
  /// turns a watch ON raises the eyes-off rung immediately. A no-op before a
  /// baseline fix exists (updateEnvironment recomputes only with an estimate).
  void _pushMeasuredHazardToDriveHud() {
    // Ruled 2026-09-15: only a brain that
    // holds this drive recomputes. An ended share's estimate is not asked, so
    // nothing is told or shown from it.
    if (_driveHudRungIsThisDrives) {
      _driveHud.updateEnvironment(
        visibilityMeters: _effectiveVisibilityMeters,
        visibilityAgeSeconds: _effectiveVisibilityAgeSeconds(),
        advisorySeverity: readAdvisoryAxis(_advisoryResult).level,
        speedMetersPerSecond: null,
        measuredHazard: _currentMeasuredHazard(),
      );
    }
    _giveHeldEventIfMeasured();
  }

  /// Ruled 2026-09-15. Reads the measured
  /// whiteout at a weather refresh or a visibility band change, then tells it
  /// to a driver with no share running. A fresh reading under 200 m opens it;
  /// a fresh reading at or above 200 m closes it; no reading, a stale one or a
  /// failed fetch changes nothing, so a reading whose age flickers past the
  /// freshness window does not open it again.
  void _updateWhiteoutWindow() {
    // The measured whiteout is the station's: a demo value neither opens nor
    // closes it (2026-09-16), so a whiteout a measurement opened is not closed
    // by a test value and told again as new.
    final v = _measuredVisibilityMeters;
    final age = _measuredVisibilityAgeSeconds();
    final fresh =
        v != null && !v.isNaN && age != null && age <= kVisStaleSeconds;
    if (fresh && v < kVisLowM) {
      if (!_whiteoutOpen) {
        _whiteoutOpen = true;
        _whiteoutTold = false;
      }
    } else if (fresh) {
      _whiteoutOpen = false;
    }
    _noteShareToldWhiteout();
    if (_whiteoutOpen && !_whiteoutTold && _noShareRunning) {
      _whiteoutTold = true;
      _driveHud.tellWithNoShare(DriveAction.considerStopping);
    }
    if (mounted) setState(() {});
  }

  /// A share running this drive that has told the top rung while a whiteout
  /// is open has told that opening: stopping or refusing afterwards does not
  /// tell it again.
  void _noteShareToldWhiteout() {
    if (_whiteoutOpen &&
        _driveHudRungIsThisDrives &&
        _driveHud.spokenRung == DriveAction.considerStopping) {
      _whiteoutTold = true;
    }
  }

  /// The road's own caution as the app holds it now, when it is the top rung;
  /// otherwise null. Read for the panel of a driver with no share running, so
  /// a reading that has gone stale shows no rung.
  DriveAdvice? _roadAdviceIfTopRung() {
    final road = adviseInDrive(DriveSituation(
      positionTrust: PositionTrust.trusted,
      confidenceRadiusMeters: 0,
      secondsSinceTrustedFix: 0,
      hasPosition: true,
      visibilityMeters: _effectiveVisibilityMeters,
      visibilityAgeSeconds: _effectiveVisibilityAgeSeconds(),
      advisorySeverity: readAdvisoryAxis(_advisoryResult).level,
      speedMetersPerSecond: null,
    ));
    return road.action == DriveAction.considerStopping ? road : null;
  }

  /// Whether a measured condition, as the app holds it now, raises caution on
  /// its own ([measuredConditionRaisesCaution]).
  bool _measuredConditionRaisesCaution() => measuredConditionRaisesCaution(
        // Measured means measured (2026-09-16): a demo value does not hold back
        // or give a held event.
        visibilityMeters: _measuredVisibilityMeters,
        visibilityAgeSeconds: _measuredVisibilityAgeSeconds(),
        advisorySeverity: readAdvisoryAxis(_advisoryResult).level,
        measuredHazard: _currentMeasuredHazard(),
      );

  /// A held event reaches the drive brain the moment a measured condition
  /// raises caution, not only when the next event arrives: a failure never
  /// takes away a caution a measured condition raises (ruled 2026-09-14), and
  /// a failed share may send no further event at all. Called wherever the
  /// app's measured environment changes: the weather refresh, the visibility
  /// band, and an advisory result.
  void _giveHeldEventIfMeasured() {
    final held = _herHeldEvent;
    if (!mounted || held == null || _herSub == null) return;
    if (_herAnchoredThisSession || !_measuredConditionRaisesCaution()) return;
    _herHeldEvent = null;
    // From here the brain holds this session's event, so the watchdog may
    // degrade it on a drought, as it does after any event it is given.
    _lastPositionEventAt = _now();
    // Ruled 2026-09-15: the absence of any
    // event is the road's own rung inside 60 s; a failure, or the absence from
    // 60 s, is an unlocated position.
    _driveHud.startRung = _herNoEventYet && !_herFirstEventOverdue
        ? StartRung.road
        : StartRung.unlocated;
    _feedDriveHud(held);
    setState(() => _herFedThisShare = true);
  }

  /// Route setting reads what [fix] measured about motion (ruled 2026-09-14):
  /// a moving reading from any sample closes it, and only a current stop
  /// measured on a fix the drive brain took as trusted ([onTrustedFix]) opens
  /// it again ([ShareMotion]). An open route act closes itself on a moving
  /// reading, keeping its points.
  void _readMotion(PositionFix fix, {required bool onTrustedFix}) {
    if (fix is! PositionAvailable || _isMockPosition) return;
    final next = _shareMotion.after(
      reading: fix.motion,
      onTrustedFix: onTrustedFix,
      fixAt: fix.timestamp,
      receivedAt: _now(),
    );
    if (fix.motion == GroundMotion.moving) _movingReadings.value++;
    if (next == _shareMotion) return;
    setState(() => _shareMotion = next);
  }

  /// Recompute the caution when the mocked visibility band changes (no new
  /// position). [DriveHudController.updateEnvironment] recomputes + re-announces
  /// on a rung rise if an estimate already exists. The measured-hazard floor is
  /// left unchanged (this control does not re-evaluate the JMA watches).
  void _onVisibilityChanged(double? meters) {
    setState(() => _mockVisibilityMeters = meters);
    // Ruled 2026-09-15: as at a refresh.
    if (_driveHudRungIsThisDrives) {
      _driveHud.updateEnvironment(
        visibilityMeters: _effectiveVisibilityMeters,
        visibilityAgeSeconds: _effectiveVisibilityAgeSeconds(),
        advisorySeverity: readAdvisoryAxis(_advisoryResult).level,
        speedMetersPerSecond: null,
      );
    }
    _giveHeldEventIfMeasured();
    _updateWhiteoutWindow();
  }

  /// Simulate +60 s of GPS blackout: advance the honest position with [poll] so
  /// the dot degrades trusted → dead-reckoning → lost off a device (defaults:
  /// lost past 120 s or a 500 m radius). Combined with a low-visibility band,
  /// this is the compound failure that raises the caution to its ceiling and
  /// auto-announces. Enabled only once a trusted baseline fix exists.
  void _simulateGpsBlackout() {
    final base = _driveHudBaseTime;
    if (base == null) return;
    _blackoutSeconds += 60;
    // The simulated clock never runs behind the real one (AAA R52, S6): when
    // her real drought is already past the simulated seconds, polling at the
    // simulated time moved the advisor's clock backwards and a degraded dot
    // dropped a caution step. The same later-of rule the watchdog holds
    // ([positionWatchdogPollTime]).
    _driveHud.poll(now: blackoutPollTime(
      simulated: base.add(Duration(seconds: _blackoutSeconds)),
      now: _now(),
    ));
  }

  /// Whether the simulated blackout clock sits ahead of the real one, so the
  /// drought the brain holds is one nobody measured.
  bool get _blackoutClockIsTest {
    final base = _driveHudBaseTime;
    if (base == null || _blackoutSeconds == 0) return false;
    return base.add(Duration(seconds: _blackoutSeconds)).isAfter(_now());
  }

  // Visibility bands for the mocked in-drive control. metres, or null =
  // "no reading" (a first-class unknown). Labels follow the app's locale
  // (AppL10n.driveHudVisibilityBand); they were Japanese on every device.
  static const List<double?> _visibilityBands = [null, 1500, 700, 300, 80];

  /// Whether the rung drawn on her card was computed from a value nobody
  /// measured. False when the card draws no rung ([effective] null).
  bool _rungOnCardFromTestValue({
    required DriveAction? effective,
    required bool brainIsThisShares,
    required bool noShareWhiteout,
  }) {
    if (effective == null) return false;
    final visibilityIsTest = _visibilityForCaution.isTestValue &&
        (brainIsThisShares || noShareWhiteout);
    final mockWithBrain = _isMockPosition && brainIsThisShares;
    return visibilityIsTest || mockWithBrain;
  }

  /// Whether a line the drive brain speaks now was raised by a value nobody
  /// measured: a demo visibility the brain reads, the Akita mock position, or
  /// the simulated blackout clock ahead of the real one (AQ4). Read by the
  /// brain at the moment it speaks.
  bool _spokenFromTestValue() =>
      _visibilityForCaution.isTestValue ||
      _isMockPosition ||
      _blackoutClockIsTest;

  /// The unknowns the app owns because the drive brain has no channel for
  /// them — an unprovable advisory lookup, and an unread/failed weather feed.
  /// Rendered into the SAME 「不明な点」 row as the package's own unknowns.
  List<AppUnknown> _appUnknowns() => appUnknownsFor(
        advisoryCompletenessProven:
            readAdvisoryAxis(_advisoryResult).completenessProven,
        measuredWatchFeed: _measuredWatchFeed,
      );

  Widget _driveHudPanel() {
    // A share is judged by itself (ruled 2026-09-14): while this session has
    // given the drive brain nothing, the panel shows nothing the brain still
    // holds from an earlier session or the dev mock. A failed re-share's event
    // is held back from the brain, so without this the panel would go on
    // reading the previous drive's GPS 良好 while the map says 現在地不明.
    // The brain is scoped here, never reset: reset, a replayed fix from
    // another place became a trusted position.
    //
    // Ruled 2026-09-15: nothing from a share
    // she ended or refused. With no share running and a measured whiteout in
    // hand, the road's own rung and its cause. Inside 60 s of a subscription
    // with no event, the road's rung without a position line.
    //
    // Her tap does not take a measured whiteout off her card (2026-09-15):
    // while a share runs and has not yet given the brain anything (the
    // permission dialog, or the seconds before the first check), the card
    // shows the road's top rung and its cause as it did before her tap.
    // Showing is not telling: nothing here speaks or vibrates.
    final brainIsThisShares = _driveHudRungIsThisDrives;
    final DriveAdvice? noShareWhiteout =
        !brainIsThisShares && _whiteoutOpen ? _roadAdviceIfTopRung() : null;
    final estimate = _driveHudPositionIsThisDrives ? _driveHud.estimate : null;
    final advice =
        noShareWhiteout ?? (brainIsThisShares ? _driveHud.advice : null);
    final l = AppL10n.of(context);
    final appUnknowns = _appUnknowns();
    // Scoping inputs for the lowest-rung reassurance. None of these raises the
    // rung; they qualify the CLAIM so it never says more than was measured.
    final advisoryUnconfirmed =
        appUnknowns.contains(AppUnknown.advisoryLookupIncomplete);
    final measuredUnconfirmed = appUnknowns.any((u) =>
        u == AppUnknown.measuredWatchFeedLost ||
        u == AppUnknown.measuredWatchNotYetRead);
    // The sub-zero frozen-surface chip (Chair 2026-07-23) renders directly
    // above this banner and deliberately does NOT raise the rung. A chip
    // reading 路面凍結のおそれ beside an unscoped 「特段の注意なし」 is a
    // glance-level contradiction; the chip is correct, so the headline yields.
    final calmNoteInForce =
        _invisibleIceResult == InvisibleIceWatchResult.subZeroFrozen;
    // The EFFECTIVE rung after the measured-weather floor is fused in — so this
    // WS6 caution section cannot show a 「走行を継続」banner while a measured
    // black-ice / turmoil watch is firing on-screen (a full-screen driver HUD is
    // BETA_PLAN; this is the alpha app's live-drive caution section). Falls back
    // to the advisor's action before the first recompute.
    final effective = noShareWhiteout != null
        ? DriveAction.considerStopping
        : brainIsThisShares
            ? _driveHud.effectiveAction ?? advice?.action
            : null;
    final hasBaseline = _herFix is PositionAvailable;
    final rungFromTestValue = _rungOnCardFromTestValue(
      effective: effective,
      brainIsThisShares: brainIsThisShares,
      noShareWhiteout: noShareWhiteout != null,
    );

    final (Color bannerColor, Color textColor) = switch (effective) {
      DriveAction.considerStopping => (Colors.red.shade100, Colors.red.shade900),
      DriveAction.heightenedCaution => (
          Colors.amber.shade100,
          // amber.shade900 on amber.shade100 measures ~2.4:1 — below the app's
          // own 4.5:1 floor, render-SEEN faint on the MIDDLE caution rung
          // (注意して走行) a black-ice / reduced-visibility watch raises. The
          // already-defined dark amber-brown measures ~7.9:1 on the amber tint,
          // so headline + body both clear ≥4.5:1 at one glance.
          kCautionTextOnAmber
        ),
      _ => (Colors.grey.shade200, Colors.grey.shade800),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tier-1 voice-lane hardening — shown while the LAST announce could
        // not be verified as delivered (the platform never reported the
        // utterance complete). Cleared on the next verified speak. This chip
        // tells HER the AUDIO half may not have sounded.
        //
        // ⚑ CORRECTED 2026-08-22. This comment used to end: "Haptic parity is
        // unconditional in the announcer, so the tactile channel is unaffected
        // either way." The announcer does fire haptic unconditionally — and on
        // 2026-08-21 that call was measured on a device producing ZERO
        // vibrations while dispatching speech. "Fired unconditionally" was
        // read as "arrives", on the one channel nothing could report. The
        // tactile chip below is the other half; neither speaks for the other.
        //
        // Words and icon in kCautionTextOnAmber (2026-09-15): amber.shade900 on
        // this amber.shade100 measured 2.38:1, under the 4.5:1 floor, on the
        // chip meant for the driver who has lost a channel. Now 7.16:1.
        if (_speechUnverified.value) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              key: const Key('speech-unverified-chip'),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.volume_off_outlined,
                      size: 14, color: kCautionTextOnAmber),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      AppL10n.of(context).speechUnverifiedChip,
                      style: const TextStyle(
                        color: kCautionTextOnAmber,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        // OPS-059 tactile lane — shown while the LAST tactile cue that was
        // OWED did not land. Independent of the speech chip above: the two
        // channels fail independently and the deaf / hard-of-hearing driver
        // this one is written for reads no meaning at all in the other.
        // Same colours as the speech chip, and the same 2.38:1 until 2026-09-15.
        if (_hapticUnverified.value) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              key: const Key('haptic-unverified-chip'),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.vibration,
                      size: 14, color: kCautionTextOnAmber),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        AppL10n.of(context).hapticUnverifiedChip,
                        style: const TextStyle(
                          color: kCautionTextOnAmber,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        // Sub-zero frozen-surface CHIP — a calm, persistent glance-surface
        // WHAT for the driver who cannot hear the spoken warning (deaf / HoH /
        // ears useless in a roaring whiteout). Chair ruling 2026-07-23:
        // "add a calm glance chip" — give the frozen-road meaning on the
        // surface she watches WITHOUT raising the caution banner/rung (that
        // stays gated on `watch` alone, so this does not cry-wolf every cold
        // morning). Read-only mirror of the sub-zero verdict; `Icons.ac_unit`
        // is a Material glyph, so it never tofus like the ⚠ emoji. Blue.900 on
        // lightBlue.50 measures ~7.7:1, clearing the 4.5:1 accessibility floor.
        if (_invisibleIceResult == InvisibleIceWatchResult.subZeroFrozen) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              key: const Key('subzero-frozen-chip'),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.lightBlue.shade50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.ac_unit,
                      size: 14, color: Colors.blue.shade900),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      _spokenJa ? '路面凍結のおそれ' : 'Road may be frozen',
                      style: TextStyle(
                        color: Colors.blue.shade900,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          key: const Key('drive-hud-description'),
          l.driveHudDescription,
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        ),
        // The visibility band and the GPS blackout simulator are on the
        // development page (2026-09-15): on her card, one tap on the band's
        // clear setting took a measured whiteout's rung, cause and announce
        // line off it, and a release build had no condition on either.
        // An instruction to share, so shown only while she is not sharing.
        // Until 2026-09-14 it was keyed on "no fix" alone, and after a GPS
        // stream error, while she was sharing, it told her to share.
        // grey.shade600 measured 4.17:1 on the card for this line and the
        // no-position line below (2026-09-15); shade700 is 5.60:1.
        if (!hasBaseline && _herSub == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              key: const Key('drive-hud-share-hint'),
              l.driveHudShareHint,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
            ),
          ),
        const SizedBox(height: 12),
        if (estimate == null)
          Text(
              // Keyed (2026-09-15) so a test reads the rung's place on the
              // card, not every text on the screen.
              key: const Key('drive-hud-no-position'),
              l.driveHudNoPositionFed,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12))
        else ...[
          // The honest position line. The whole panel follows the app's
          // resolved locale (2026-09-13; every value was 'ja' and every label
          // a Japanese literal): the same locale as the line under the map.
          _kv(l.driveHudPositionTrustLabel,
              _driveHudText.modeLabel(estimate.mode, l.locale.languageCode)),
          _kv(
              l.driveHudUncertaintyLabel,
              _driveHudText.radiusLabel(
                  estimate.confidenceRadiusMeters, l.locale.languageCode)),
        ],
        // A test value is what the card shows (2026-09-16): drawn only where
        // the rung on the card was computed from it (AAA R52, P2) — a demo
        // visibility read by the brain holding this share or by the no-share
        // whiteout card, or the Akita mock position with the brain. With no
        // rung on the card, nothing on it came from a test value.
        // Directly above the rung banner (HIE R57 L1, 2026-09-16): below the
        // position rows the step and the fact that a test value set it were
        // ~90 px apart, and a glance at the banner did not reach the line.
        if (rungFromTestValue)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              key: const Key('drive-hud-test-value'),
              l.driveHudTestValueInForce,
              style: const TextStyle(
                  fontSize: 12,
                  color: kCautionTextOnAmber,
                  fontWeight: FontWeight.w600),
            ),
          ),
        if (advice != null) ...[
          SizedBox(height: rungFromTestValue ? 4 : 8),
          // The caution headline banner, coloured by rung.
          Container(
            key: const Key('drive-hud-caution-banner'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bannerColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // The rung itself, keyed (2026-09-15): tests that searched
                  // the whole screen for rung words read any text naming a
                  // rung as the rung.
                  key: const Key('drive-hud-rung'),
                  _driveHudText.actionHeadline(
                    effective ?? advice.action,
                    l.locale.languageCode,
                    advisoryUnconfirmed: advisoryUnconfirmed,
                    measuredUnconfirmed: measuredUnconfirmed,
                    calmNoteInForce: calmNoteInForce,
                  ),
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if ((effective ?? advice.action) !=
                    DriveAction.continueDriving) ...[
                  const SizedBox(height: 4),
                  Text(
                    _driveHudText.spokenGuidance(
                        effective ?? advice.action, l.locale.languageCode),
                    style: TextStyle(color: textColor, fontSize: 14),
                  ),
                ],
                if (advice.compounding) ...[
                  const SizedBox(height: 6),
                  Text(
                    l.driveHudCompoundingNote,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Why (reasons) + first-class unknowns, localized for HER.
          if (advice.reasons.isNotEmpty)
            _kv(
              l.driveHudReasonsLabel,
              [
                for (final r in advice.reasons)
                  _driveHudText.reasonLabel(r, l.locale.languageCode)
              ].join(' · '),
            ),
          // The package's own unknowns PLUS the app-owned ones it has no
          // channel for (advisory-lookup completeness, measured-feed
          // liveness). One row, one convention — an outage is STATED here, not
          // left to be inferred from a silent hazard floor.
          if (advice.unknowns.isNotEmpty || appUnknowns.isNotEmpty)
            _kv(
              l.driveHudUnknownsLabel,
              [
                for (final u in advice.unknowns)
                  _driveHudText.unknownLabel(u, l.locale.languageCode),
                for (final u in appUnknowns) appUnknownLabel(u, l),
              ].join(' · '),
            ),
          if (advice.sightStoppingSpeedHintMps != null)
            _kv(
              l.driveHudGuideSpeedLabel,
              _driveHudText.sightHintLabel(
                  advice.sightStoppingSpeedHintMps!, l.locale.languageCode),
            ),
          const SizedBox(height: 8),
          // Announce status — honest reach bounds, keyed on the EFFECTIVE rung
          // AND on whether the rung LANE actually speaks it. A measured-hazard
          // floor (or an unknown-visibility-only heightened) is shown+coloured
          // but NOT spoken by this lane — the watch lane speaks the specific
          // hazard — so it must not falsely claim it auto-fired (OPS-068).
          Text(
            key: const Key('drive-hud-announce-status'),
            switch (effective ?? advice.action) {
              DriveAction.considerStopping => l.driveHudAnnounceCritical,
              DriveAction.heightenedCaution =>
                _driveHud.effectiveRungIsSpokenByRung
                    ? l.driveHudAnnounceWarning
                    : l.driveHudAnnounceRaisedNotSpoken,
              DriveAction.continueDriving => l.driveHudAnnounceContinue,
            },
            style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
          ),
        ],
        const SizedBox(height: 6),
        // Where each thing on the card comes from, in the app's language.
        Text(
          key: const Key('drive-hud-footer'),
          l.driveHudFooter,
          style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
        ),
      ],
    );
  }

  /// Re-fetches advisories when the caller's lat/lon changes
  /// materially (>=0.01 degree, ~1 km). Avoids re-fetching every GPS
  /// tick — the publisher's record cadence is minutes-class, not
  /// seconds-class. Also gates re-fetch on init completing.
  void _maybeRefreshAdvisoriesForFix(PositionFix fix) {
    if (fix is! PositionAvailable) return;
    final lat = fix.latitude;
    final lon = fix.longitude;
    if (_lastAdvisoryLat != null && _lastAdvisoryLon != null) {
      if ((lat - _lastAdvisoryLat!).abs() < 0.01 &&
          (lon - _lastAdvisoryLon!).abs() < 0.01) {
        return;
      }
    }
    _lastAdvisoryLat = lat;
    _lastAdvisoryLon = lon;
    _refreshAdvisories(lat, lon);
  }

  Future<void> _refreshAdvisories(double latitude, double longitude) async {
    setState(() {
      _advisoryLoading = true;
      _advisoryErrorMessage = null;
    });
    try {
      await _advisoryInitFuture;
      // Read coverage BEFORE interpreting the result: an empty result from
      // an uncovered point is "nobody was asked", never a publisher
      // all-clear (see _advisoryPointCovered).
      final covered = _advisoryService.coversPoint(latitude, longitude);
      final result = await _advisoryService.fetchAtPoint(
        latitude: latitude,
        longitude: longitude,
      );
      if (!mounted) return;
      final now = _now();
      setState(() {
        _advisoryPointCovered = covered;
        _applyAdvisoryResult(result, now);
        _advisoryLoading = false;
      });
      _giveHeldEventIfMeasured();
    } catch (e) {
      if (!mounted) return;
      // The THROWN path (init failure, unexpected error) must take the SAME
      // retention shape as a provider-errored fetch: before this, setting
      // only _advisoryErrorMessage made AdvisoryCards early-return the error
      // banner ALONE — prior in-force hazard cards vanished from the visible
      // surface while the advisory axis kept feeding them to the drive brain
      // (a spoken warning with no visible counterpart). Synthesizing a
      // failed aggregate result renders retained hazards under the honest
      // degraded/stale banners instead, and applies the expiry cull.
      final now = _now();
      setState(() {
        // B04-2 provenance lives in the named builder so the call site carries
        // no untested literal (see advisoryResultForThrownFetch).
        _applyAdvisoryResult(advisoryResultForThrownFetch(e), now);
        _advisoryErrorMessage = null;
        _advisoryLoading = false;
      });
      _giveHeldEventIfMeasured();
    }
  }

  /// Applies [retainAdvisoriesOnFailure] to the state trio. Must be called
  /// inside setState.
  void _applyAdvisoryResult(AdvisoryAggregateResult fresh, DateTime now) {
    final applied = retainAdvisoriesOnFailure(
      prior: _advisoryResult,
      fresh: fresh,
      now: now,
      // Anchor the null-expires synthetic window to the last successful fetch.
      // On a retained cycle _advisoryFetchedAt is NOT advanced, so the window
      // keeps shrinking against the real last-fresh instant and a null-expires
      // JMA warning drops at +kSlowHazardRetainWindow — never stale-forever.
      lastFreshAt: _advisoryFetchedAt,
    );
    _advisoryResult = applied.result;
    _advisoryRetained = applied.retained;
    if (!applied.retained) {
      _advisoryFetchedAt = now;
    }
    // When retained, _advisoryFetchedAt is NOT touched: it stays the instant
    // the retained data was actually fetched, so the stale label is honest.
  }

  /// A share she ended with 停止, or refused, leaves no point behind for the
  /// advisories (2026-09-15). The 10-minute refresh and her refresh button
  /// then ask where they ask for a driver who never shared, not at the last
  /// place the ended share was, for the life of the app. The next share's
  /// first position asks at her position again, even at the same place.
  void _forgetAdvisoryPointOfTheShare() {
    _lastAdvisoryLat = null;
    _lastAdvisoryLon = null;
  }

  void _onAdvisoryRefreshTapped() {
    final lat = _lastAdvisoryLat;
    final lon = _lastAdvisoryLon;
    if (lat == null || lon == null) {
      // No fix yet — fall back to Akita station (consistent with
      // mock-position default).
      _refreshAdvisories(akitaStation.latitude, akitaStation.longitude);
    } else {
      _refreshAdvisories(lat, lon);
    }
  }

  void _clearPosition() {
    // Ruled 2026-09-15: what this share told
    // stays told. Nothing is told at her tap: a whiteout this share did not
    // tell is told at the next refresh.
    _noteShareToldWhiteout();
    _forgetAdvisoryPointOfTheShare();
    _herNoEventYet = false;
    _herSub?.cancel();
    _herSub = null;
    // N8 — she deliberately ENDED the feed: the blackout watchdog must stop
    // with it (same treatment as _useMockPosition, a fortiori — there is no
    // live position claim left to degrade). Leaving it running would keep
    // polling with the LAST drive's _lastPositionEventAt and, ~30 s later,
    // speak escalating "blackout" warnings about a feed she turned off.
    // Nulling _lastPositionEventAt also protects a RE-share: the first tick
    // must not poll against the previous drive's stale timestamp before the
    // first fresh fix arrives.
    _positionWatchdog?.cancel();
    _positionWatchdog = null;
    _lastPositionEventAt = null;
    _herHeldEvent = null;
    _herShareSession++;
    setState(() {
      _herFix = null;
      _isMockPosition = false;
      _herPositionStreamSubscribedAt = null;
      _herFirstEventOverdue = false;
    });
  }

  /// W0 detection-survival — wall-clock read, injectable for host-deterministic
  /// staleness (OPS-066).
  DateTime _now() => (widget.clock ?? DateTime.now)();

  /// Build the on-disk store, or null when this platform/harness has no
  /// documents dir (tests, desktop harnesses). A null store means the memory is
  /// in-RAM only for this run — it is NOT an error and must never be reported as
  /// one.
  Future<TripHazardStore?> _tripHazardStore() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return TripHazardStore(
        file: File('${dir.path}/${TripHazardStore.fileName}'),
      );
    } catch (_) {
      return null;
    }
  }

  /// COLD START. She rebooted on the roadside, in the dead zone. The memory must
  /// come back from disk with no network — that is the entire promise.
  Future<void> _loadTripHazardMemory() async {
    final store = await _tripHazardStore();
    final loaded = await store?.load();
    if (!mounted || loaded == null) return;
    setState(() => _tripHazardMemory = loaded);
  }

  /// PLAN TIME — the network is alive, so we learn what the publisher declares
  /// for the hours ahead and WRITE IT DOWN. This is the only moment the memory
  /// can be formed; in the dead zone it is too late.
  ///
  /// Refreshed at most every 3 hours: JMA reissues the forecast a few times a
  /// day, and re-fetching a forward grid on every 10-minute observation tick
  /// would spend HER battery and JMA's bandwidth for nothing.
  Future<void> _captureTripHazardMemory() async {
    final existing = _tripHazardMemory;
    if (existing != null &&
        _now().toUtc().difference(existing.capturedAt) <
            const Duration(hours: 3)) {
      return;
    }
    final result = await (widget.jmaForecastFetch?.call() ??
        fetchJmaForecast(userAgent: kSngnavAppUserAgent));
    if (!mounted) return;
    // A FAILED forecast fetch must NOT erase a memory we already hold. The old
    // memory may still be perfectly valid for this hour — and "we could not
    // reach JMA just now" is not evidence that the road is clear.
    if (result is! JmaForecastSuccess) return;
    final memory = TripHazardMemory(
      hazards: result.hazards,
      capturedAt: _now().toUtc(),
    );
    setState(() => _tripHazardMemory = memory);
    final store = await _tripHazardStore();
    await store?.save(memory);
  }

  Future<void> _refreshJma() async {
    setState(() => _jmaLoading = true);
    final result = await (widget.jmaFetch?.call() ??
        fetchLatestObservation(userAgent: kSngnavAppUserAgent));
    if (!mounted) return;
    setState(() {
      _jmaResult = result;
      _jmaLoading = false;
      if (result is JmaSuccess) {
        // W0: RETAIN the last GOOD observation for the feed-loss survival path.
        _lastGoodObservation = result.observation;
        // The network is ALIVE — so this is PLAN TIME, and the only moment the
        // dead-zone memory can be formed. Fire-and-forget: a forecast fetch must
        // never delay or wedge the live observation lane.
        unawaited(_captureTripHazardMemory());
        _invisibleIceResult = evaluateInvisibleIceWatch(result.observation);
        _turmoilState = evaluateTurmoilWatch(result.observation);
        // The lane is LIVE: the non-firing verdicts below are now MEASURED
        // negatives, and the glance may stop reporting the lane as unknown.
        _measuredWatchFeed = MeasuredWatchFeed.live;
      } else {
        // W0 feed loss: do NOT discard _lastGoodObservation — that retention is
        // the whole point. The LIVE verdicts become unknown/null (the live
        // surfaces must not read a stale reading as live); the stale/absence
        // decision is made in _announceWatchTransitions from the retained obs.
        _invisibleIceResult = InvisibleIceWatchResult.unknown;
        _turmoilState = null;
        // A READ THAT FAILED — distinct from the cold start this session began
        // in. Both leave the watches non-firing, and a not-firing watch is
        // indistinguishable from a measured all-clear at the hazard floor; the
        // difference is carried here and STATED on the glance, never inferred
        // from the floor's silence.
        _measuredWatchFeed = MeasuredWatchFeed.lost;
      }
    });
    // Raise (or clear) the eyes-off compound rung from the just-evaluated
    // measured watches immediately — before the next position event — so the
    // banner she reacts to reflects the measured hazard the same cycle the
    // watch row does. Recomputes only if a baseline fix already exists.
    _pushMeasuredHazardToDriveHud();
    // Ruled 2026-09-15: the measured whiteout, read at every refresh.
    _updateWhiteoutWindow();
    _announceWatchTransitions();
  }

  /// BETA_PLAN W1+W3 — transition-gated announces for BOTH measured watches
  /// over the live JMA observation. Each watch announces ONCE when its
  /// measured window turns on, never repeating on every fetch while the
  /// window persists (the cry-wolf discipline the SNGNav status bar uses).
  ///
  /// - Invisible ice: the catalog's possibility-graded looks-wet line,
  ///   VERBATIM in the resolved spoken locale (AAA Article 17 β — the app
  ///   does not paraphrase catalog strings; jaSpokenText/enSpokenText are
  ///   both the catalog publisher's own strings). Warning tier, not
  ///   critical, because the detection is a dew-point inference, not a
  ///   surface measurement.
  /// - Turmoil (W3): app-authored possibility-graded line over the measured
  ///   rain/wind thresholds (services/turmoil_watch.dart documents the
  ///   JMA-table grounding). Warning tier for the same reason: a derived
  ///   caution from a point measurement, not a surface statement.
  ///
  /// The two announces are CHAINED inside one async block: the shared TTS
  /// engine holds a single global language state, and two concurrently
  /// un-awaited announces could interleave setLanguage/speak (the actuator
  /// seam noted in mobile_alert_actuators.dart) — sequential delivery keeps
  /// each line in its own voice.
  void _announceWatchTransitions() {
    final ttsTag = _spokenJa ? 'ja-JP' : 'en-US';
    final result = _jmaResult;

    // FRESH-LIVE path — a successful fetch this cycle. UNCHANGED rise-gated
    // behavior: each watch announces ONCE when its live window turns on.
    if (result is JmaSuccess) {
      // The ice channel now has two mutually-exclusive firing verdicts: `watch`
      // (above-zero radiative SURPRISE) and `subZeroFrozen` (below-zero
      // EXPECTED frozen surface). Track WHICH last announced, not a bool, so:
      // (a) the sub-zero verdict folds into `iceRose` and is NOT silently
      // dropped by the `!iceRose` guard below — on a calm sub-zero morning the
      // above-zero `watch` cannot fire, so a separate latch would return at
      // :1882 and mute the whole feature (critic Finding 1, 2026-07-23); and
      // (b) crossing 0 °C (watch <-> subZeroFrozen) re-speaks the correct
      // distinct line rather than staying silent on the transition.
      final iceResult = _invisibleIceResult;
      final iceFired = iceResult == InvisibleIceWatchResult.watch ||
          iceResult == InvisibleIceWatchResult.subZeroFrozen;
      final iceRose = iceFired && iceResult != _lastAnnouncedIceResult;
      // Update the latch. A firing verdict is remembered (rise-gate). A
      // MEASURED `clear` is a genuine all-clear exit → re-arm so a later
      // re-entry warns again. But `outOfScope` (a passing snow band owns the
      // road for a few minutes) and `unknown` (a dropped leaf) are NOT
      // all-clears: hold the latch STICKY across them, or the 14 s sub-zero
      // line + haptic re-fires every time a snow band clears and returns to
      // sub-zero — cry-wolf on the live feed, breaking the once-per-entry
      // discipline. (impl-review SHOULD, 2026-07-23.) Dead-zone re-arm is
      // handled separately in the feed-loss cases below.
      // `outsideModelEnvelope` (2026-08-01) falls through BOTH branches and is
      // therefore STICKY. That is a DECISION, not an omission — recorded here so
      // the next reader does not "fix" it into a re-arm:
      //   * Doctrine: only positive evidence clears a safety latch. The
      //     `_lost` latch states it outright — "The ONLY way to clear it is a
      //     trusted fix" — and holds even for a QUALIFIED positive ("an
      //     imprecise, beyond-horizon trusted fix is adopted as the baseline
      //     but we remain honestly `lost`"). A non-judgement is not evidence.
      //   * A first warning still fires. The gate below is
      //     `iceFired && iceResult != _lastAnnouncedIceResult`, so an armed
      //     latch announces a genuine hazard, and
      //     `watch → outsideModelEnvelope → subZeroFrozen` DOES announce.
      //   * NAMED COST, not hidden — TWO sequences, both measured through this
      //     latch (review 2026-08-01, both CONFIRMED under refutation):
      //       `watch → outsideModelEnvelope → watch` is NOT re-announced, and
      //       that is exactly the radiative-frost morning; and
      //       `subZeroFrozen → outsideModelEnvelope → subZeroFrozen` loses the
      //       14-second sub-zero spoken line AND its haptic across a 0 °C
      //       oscillation into saturated air (measured: subZero=1 with the
      //       envelope between, subZero=2 with `clear` between).
      //     Accepted because the alternative re-speaks the black-ice line on
      //     0.1 °C feed jitter — the cry-wolf the 2026-07-23 calibration ruling
      //     exists to prevent. A time-bounded re-arm was considered and
      //     rejected as a periodic nag that reconstructs that cry-wolf.
      //   * Benefit and cost are ONE mechanism, and it is stronger than
      //     "narrowing". Measured over the whole above-zero sub-ceiling domain
      //     (0.1–3.0 °C × 5–100 % RH, 2880 cells): watch 2554,
      //     outsideModelEnvelope 326, `clear` ZERO. Below the 3.0 °C ceiling
      //     `clear` is now UNREACHABLE, so this does not narrow the live
      //     re-arm path in that range — it ELIMINATES it (326 → 0). An earlier
      //     version of this comment said "narrows"; that understated it.
      if (iceFired) {
        _lastAnnouncedIceResult = iceResult;
      } else if (iceResult == InvisibleIceWatchResult.clear) {
        _lastAnnouncedIceResult = null;
      }

      final turmoil = _turmoilState;
      final turmoilFired = turmoil != null && turmoil.anyCaution;
      final turmoilRose = turmoilFired && !_turmoilAnnounced;
      _turmoilAnnounced = turmoilFired;

      // W0: re-arm the absence gate so a LATER dead-zone re-announces the
      // absence line once on entry. Same for the forecast-memory gate: a LATER
      // dead-zone must be free to speak the valid forecast once on entry.
      _absenceActive = false;
      _forecastAnnounceActive = false;

      if (!iceRose && !turmoilRose) return;
      unawaited(() async {
        if (iceRose) {
          final String iceText;
          if (iceResult == InvisibleIceWatchResult.subZeroFrozen) {
            // Below-zero expected-frozen line — possibility-graded, NOT the
            // 「ブラックアイスバーン」 surprise wording (Chair calibration
            // 2026-07-23). Bundled offline (id sub_zero_frozen_live).
            iceText = subZeroFrozenSpokenText(ja: _spokenJa);
          } else {
            iceText = _spokenJa
                ? invisibleBlackIceAnnouncement.jaSpokenText
                : invisibleBlackIceAnnouncement.enSpokenText;
          }
          await _announcer.announce(
            severity: AlertSeverity.warning,
            text: iceText,
            localeTag: ttsTag,
          );
        }
        if (turmoilRose) {
          final line = turmoilSpokenText(turmoil, ja: _spokenJa);
          if (line != null) {
            await _announcer.announce(
              severity: AlertSeverity.warning,
              text: line,
              localeTag: ttsTag,
            );
          }
        }
      }());
      return;
    }

    // FEED-LOSS path — JmaFailure or null (no successful fetch this cycle).
    // The CONTENT decision (stale-vs-forecast-vs-absence-vs-quiet) is the
    // shared, testable [feedLossVerdict] — the SAME function `_jmaPanel`
    // renders from, so the screen can never contradict the speaker (N15).
    // The announce GATING (once-per-entry vs re-warn-per-cycle) stays here.
    final verdict = feedLossVerdict(
      cached: _lastGoodObservation,
      memory: _tripHazardMemory,
      now: _now(),
      spokenJa: _spokenJa,
    );
    switch (verdict) {
      // ── (1) TRUE no-reading dead zone ────────────────────────────────────
      // Both cases reset the LIVE rise-gates on entry. Here — and ONLY here —
      // continuity of the spoken channel is genuinely broken: HER just heard
      // "conditions unavailable" (or the forecast memory). Without this reset,
      // a live hazard that RETURNS on feed-recovery is silently suppressed
      // (iceRose = fired && !alreadyAnnounced stays false), so HER's last
      // spoken word about the road would remain "unavailable" while a live
      // black-ice warning is swallowed exactly in the recovery-from-dead-zone
      // case. NOT reset on every feed-loss cycle (per-blip cry-wolf) and NOT
      // in the stale-ice case (it is actively re-warning via the stamped line).
      case FeedLossForecastMemory(:final line, :final spokenAloud):
        _lastAnnouncedIceResult = null;
        _turmoilAnnounced = false;
        // C2 RED-1: THE MEMORY, BEFORE THE SILENCE. We have no live reading,
        // but we KNOW something TRUE: a hazard the publisher declared VALID
        // FOR THIS VERY HOUR, captured before she left. Not a stale
        // observation dressed up as live — a forecast, inside its own
        // publisher-declared window, and the spoken line says so out loud
        // (これは観測ではなく予報です). Consulted BEFORE the absence line,
        // because "we know nothing" is FALSE when we know this. Announce is
        // gated once per entry (mirrors the absence gate).
        if (spokenAloud) {
          _absenceActive = false;
          if (!_forecastAnnounceActive) {
            _forecastAnnounceActive = true;
            unawaited(_announcer.announce(
              severity: AlertSeverity.warning,
              text: line,
              localeTag: ttsTag,
            ));
          }
        } else {
          // Screen-only forecast card (en surface, or the ja mouth lacks the
          // bytes): the VOICE keeps the honest absence line — "current
          // conditions cannot be retrieved" stays TRUE, and the eyes-off
          // driver must not get silence just because the forecast line is
          // not renderable by the mouth. The screen shows MORE (the labeled
          // forecast card), never less. Once-per-entry gate as at
          // FeedLossAbsence.
          _forecastAnnounceActive = false;
          if (!_absenceActive) {
            _absenceActive = true;
            unawaited(_announcer.announce(
              severity: AlertSeverity.warning,
              text: _spokenJa
                  ? kConditionsUnknownJaSpokenText
                  : kConditionsUnknownEnSpokenText,
              localeTag: ttsTag,
            ));
          }
        }

      case FeedLossAbsence():
        _lastAnnouncedIceResult = null;
        _turmoilAnnounced = false;
        // The honest ABSENCE-LINE (GAP-2). Fires ONCE per entry (gate), so a
        // persistent dead-zone does not spam; re-arms via the JmaSuccess reset.
        _forecastAnnounceActive = false;
        if (!_absenceActive) {
          _absenceActive = true;
          unawaited(_announcer.announce(
            severity: AlertSeverity.warning,
            text: _spokenJa
                ? kConditionsUnknownJaSpokenText
                : kConditionsUnknownEnSpokenText,
            localeTag: ttsTag,
          ));
        }

      // ── (2) Within the slow bound, black-ice window present ─────────────
      // KEEP announcing HONESTLY TIME-STAMPED (Chair: retain + keep
      // announcing, never as live). NOT gated once-per-entry (unlike the
      // absence line): a persistent black-ice dead-zone re-warns each
      // feed-loss cycle, honestly re-stamped. The JMA ticker cadence
      // (~10-min AMeDAS) is the rate-limiter (one announce per _refreshJma).
      // A hazard beats the absence line, so ice takes precedence.
      case FeedLossStaleIce(:final hourJst):
        _absenceActive = false;
        unawaited(_announcer.announce(
          severity: AlertSeverity.warning,
          text:
              staleInvisibleBlackIceSpokenText(hourJst: hourJst, ja: _spokenJa),
          localeTag: ttsTag,
        ));

      // ── (3) Within the slow bound, no slow hazard ────────────────────────
      // FAST hazard (turmoil): SILENT when stale — never announced from the
      // cache (cry-wolf discipline). No-op by construction (the fast watch is
      // NOT invoked on the cache).
      //
      // KNOWN LIMITATION — DROPPED SUSTAINED GALE (design §3 caveat + §8 attack
      // #2; review finding #2, OPS-068 fail-toward-keeping). Wind is lumped
      // into the FAST lane, so on feed loss a still-valid SUSTAINED synoptic
      // gale (measured mean wind ≥ kWindCautionMeanMs, 暴風-class) is silently
      // dropped even at ~0 min staleness — a gale is slow-varying (persists for
      // HOURS), unlike a convective downpour cell, so a 10-60-min-old gale
      // reading is still physically indicative, exactly the property that
      // justified retaining black ice. This is a RECORDED, deliberately-
      // deferred gap, not an invisible one: the 暴風警報 JMA-warnings lane
      // (turmoil_watch.dart:33-36) is likewise not cached by W0. A fix would
      // give wind its own longer retain window + a stale-stamped, past-framed
      // line reusing the not-live clause (mirror the black-ice path); deferred
      // as too large for this pass + needs AAA/NDI review. Pinned by the
      // "KNOWN LIMITATION … sustained wind" test so the drop stays a recorded
      // decision. See unresolved_safety_items.
      //
      // Within-bound, non-watch (cache says clear, or the ice channel
      // abstained): honest SILENCE. We hold a reading ≤60 min old, so firing
      // the absence-line here would be FALSE — the absence-line fires ONLY on
      // true no-reading, handled at (1). We do NOT flip the gates here: a
      // within-bound clear does not end an active stale/absence state (only a
      // JmaSuccess re-arm does).
      case FeedLossRetainedQuiet():
        break;
    }
  }

  Future<void> _refreshCorridor() async {
    setState(() => _corridorLoading = true);
    final results = await fetchCorridorObservations();
    if (!mounted) return;
    setState(() {
      _corridorResults = results;
      _corridorLoading = false;
    });
  }

  /// Whether a route may be set here, and then only through the route act
  /// (ruled 2026-09-14). Read at build, from the platform this build runs on
  /// and the motion this phone has measured.
  bool get _routeSettingOpen => routeSettingOpen(
        routeSettingHost(),
        motion: _herSub == null ? null : _shareMotion,
        now: _now(),
      );

  /// Opens the route act. Points she chooses there reach the page as she
  /// chooses them, so closing the act keeps them; the route is asked for only
  /// when the act returns from its get-route control.
  Future<void> _openRouteAct() async {
    if (!_routeSettingOpen) return;
    final getRoute = await showDialog<bool>(
      context: context,
      builder: (_) => RouteActDialog(
        origin: _origin,
        destination: _destination,
        baseTileProvider: _offlineBaseProvider,
        onPointsChanged: _onRouteActPointsChanged,
        movingReadings: _movingReadings,
        movingReadingsAtOpen: _movingReadings.value,
      ),
    );
    if (!mounted || getRoute != true) return;
    _fetchRoute();
  }

  /// A point chosen or cleared in the route act. A route is for its own two
  /// points, so any change ends the one shown.
  void _onRouteActPointsChanged(LatLng? origin, LatLng? destination) {
    if (!mounted) return;
    setState(() {
      _origin = origin;
      _destination = destination;
      _routeResult = null;
      _clearManeuverState();
    });
  }

  void _resetRoute() {
    setState(() {
      _origin = null;
      _destination = null;
      _routeResult = null;
      _clearManeuverState();
    });
  }

  /// Clear the next maneuver + last narration decision.
  /// Called inside a `setState` when the route is reset/replaced.
  void _clearManeuverState() {
    _nextManeuver = null;
    _lastManeuverNarration = null;
  }

  /// Build the on-disk consent store, or null when this platform/harness has
  /// no documents dir (tests, desktop harnesses). Null = the choice is
  /// in-RAM only for this run — not an error (same idiom as _tripHazardStore).
  ///
  /// TIMEOUT (load-bearing): the consent QUESTION must never hang behind a
  /// wedged path_provider — a hang here would make tap-route silently do
  /// nothing forever, which is worse than forgetting the choice. Measured:
  /// getApplicationDocumentsDirectory() never completes (not even an error)
  /// in the flutter_test zone, so an unbounded await deadlocks there too.
  /// On timeout the choice degrades honestly to in-RAM for this run (she is
  /// asked again next launch — a repeated question, never a hung screen).
  Future<RouteConsentStore?> _routeConsentStore() async {
    try {
      final dir = await getApplicationDocumentsDirectory()
          .timeout(const Duration(seconds: 2));
      return RouteConsentStore(
        file: File('${dir.path}/${RouteConsentStore.fileName}'),
      );
    } catch (_) {
      return null;
    }
  }

  /// B27 — the pre-send gate at the OSRM coordinate egress. Resolves HER
  /// remembered choice, asking ONCE (dialog) when undecided. Returns true
  /// only when she has agreed; anything else means NOTHING may be sent.
  ///
  /// A dismissed dialog (barrier tap / back) is treated as "not now": no
  /// fetch, but NOT persisted — she is asked again on the next tap-route,
  /// because a dismissal is not a decision.
  Future<bool> _ensureRouteConsent() async {
    if (!_osrmConsentLoaded) {
      final store = await _routeConsentStore();
      bool? persisted;
      try {
        // Same hang-bound as the store construction: the question must
        // never wait forever on a wedged read.
        persisted = await store?.load().timeout(const Duration(seconds: 2));
      } catch (_) {
        persisted = null;
      }
      if (persisted != null) _osrmConsent = persisted;
      _osrmConsentLoaded = true;
    }
    final existing = _osrmConsent;
    if (existing != null) return existing;
    if (!mounted) return false;
    final granted = await _promptRouteConsent();
    if (granted == null) return false; // dismissed — not a decision.
    _osrmConsent = granted;
    // Fire-and-forget persist: her ANSWER takes effect now, in RAM; a slow
    // or wedged disk write must not hold the route (or the honest decline
    // render) hostage. Worst case the write is lost and she is asked again
    // next launch — a repeated question, never a hung screen.
    unawaited(_routeConsentStore().then((store) => store?.save(granted)));
    return granted;
  }

  /// Asks the routing question again after she agreed to send. With both
  /// points chosen the question goes through the fetch, as the re-ask after a
  /// no does: a yes fetches, a no shows the declined state and sends nothing.
  /// With no points chosen the answer is asked and remembered on its own. A
  /// dismissal remembers nothing, so she is asked before the next send.
  Future<void> _changeRouteConsentAfterYes() async {
    _osrmConsent = null;
    if (_origin != null && _destination != null) {
      await _fetchRoute();
      return;
    }
    final granted = await _promptRouteConsent();
    if (!mounted) return;
    setState(() => _osrmConsent = granted);
    if (granted != null) {
      unawaited(_routeConsentStore().then((store) => store?.save(granted)));
    }
  }

  /// The pre-send disclosure dialog (ja-primary via AppL10n). States what
  /// leaves the device and where it goes BEFORE anything is sent.
  Future<bool?> _promptRouteConsent() {
    final l = AppL10n.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.routeConsentTitle),
        content: Text(
          l.routeConsentBody,
          key: const Key('route-consent-body'),
        ),
        actions: [
          TextButton(
            key: const Key('route-consent-decline'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.routeConsentDecline),
          ),
          FilledButton(
            key: const Key('route-consent-accept'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.routeConsentAccept),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchRoute() async {
    final o = _origin;
    final d = _destination;
    if (o == null || d == null) return;

    // B27 — consent BEFORE the wire. The OSRM demo server receives HER
    // full-precision tapped coordinates; nothing may be sent until she has
    // read the pre-send disclosure and agreed. Decline/dismiss → no fetch,
    // honest neutral state (never rendered as an error).
    final consented = await _ensureRouteConsent();
    if (!mounted) return;
    if (!consented) {
      setState(() {
        _routeResult = const RouteConsentDeclined();
        _clearManeuverState();
        _routeLoading = false;
      });
      return;
    }

    setState(() => _routeLoading = true);

    // Route via the ALREADY-BUILT OsrmRoutingEngine maneuver pipeline: it
    // requests `steps=true` and parses the real maneuver list. ONE fetch yields
    // BOTH the polyline (for the map, via `result.shape`) and the honest
    // maneuver list (for (e) narration). We keep the app's own `RouteSuccess`
    // shape so the existing map + forecast wiring is untouched. No new feature
    // is added to routing_engine — it stays in maintenance-mode; this is pure
    // app-layer wiring to its existing surface.
    final engine = widget.routingEngineFactory?.call() ??
        OsrmRoutingEngine(baseUrl: _osrmDemoBaseUrl);
    RouteResult result;
    var maneuvers = const <RouteManeuver>[];
    try {
      final r = await engine.calculateRoute(
        // AAA F1: follow the resolved spoken locale (was hardcoded ja-JP);
        // routing_engine's maneuver localizer supports both primary subtags.
        RouteRequest(
          origin: o,
          destination: d,
          language: _spokenJa ? 'ja-JP' : 'en-US',
        ),
      );
      result = RouteSuccess(
        points: r.shape,
        distanceMeters: r.totalDistanceKm * 1000.0,
        durationSeconds: r.totalTimeSeconds,
        fetchedAt: DateTime.now(),
      );
      maneuvers = r.maneuvers;
    } on RoutingException catch (e) {
      // Surface the failure reason; never fall back to a stale cached route.
      result = RouteFailure(e.message);
    } catch (e) {
      result = RouteFailure('network/parse error: $e');
    } finally {
      await engine.dispose();
    }

    if (!mounted) return;
    setState(() {
      _routeResult = result;
      _nextManeuver = nextActionableManeuver(maneuvers);
      _lastManeuverNarration = null;
      _routeLoading = false;
    });
  }

  /// Public OSRM demo base — same server the app has always used, now driven
  /// through OsrmRoutingEngine so we get the parsed maneuver list too.
  static const String _osrmDemoBaseUrl = 'https://router.project-osrm.org';

  /// Whether the next maneuver coincides with an ice / low-visibility hazard, so
  /// the icy-turn advisory should be coupled onto the narration. Reuses the
  /// app's existing road-surface condition AND the live drive-HUD advice
  /// (visibility + area-advisory fusion) — no new hazard source.
  bool _maneuverCoincidesWithHazard() {
    // Couple the icy-turn advisory ONLY on a genuinely slippery surface — NOT
    // on any heightened-caution state. A dry-road gpsSuspect must never raise a
    // false CRITICAL "the turn may be icy / 路面が凍結"; low visibility is warned
    // separately by the drive HUD, not mis-narrated as ice here.
    return isSlipperySurface(_condition);
  }

  /// Narrate the next maneuver through the drive HUD's announcer, GATED on the
  /// live honest position mode (SPEAK / HEDGE / SUPPRESS). Records the decision
  /// so the panel can show what actually happened.
  void _narrateNextManeuver() {
    final next = _nextManeuver;
    if (next == null) return;
    final decision = _driveHud.narrateNextManeuver(
      next,
      icyTurn: _maneuverCoincidesWithHazard(),
      positionIsThisShares: _driveHudPositionIsThisDrives,
      // Nothing measured reaches the icy coupling: its one input is the
      // simulated road condition (2026-09-16; AAA R52, AQ4).
      icyTurnFromTestValue: true,
    );
    setState(() => _lastManeuverNarration = decision);
  }

  /// WS5 — deliver the current (condition, profile) hazard to the driver on
  /// the audio + haptic channels. This is the seam that ends the silence:
  /// the guidance the driver hears/feels is the catalog's action-coupled
  /// [AlertExplainer] string, spoken VERBATIM (AAA Article 17 β; the app must
  /// not paraphrase). Severity is derived from the road-surface condition;
  /// [AlertAnnouncer.announce] gates BOTH channels on `>= warning` so a
  /// whiteout-class critical fires audio AND haptic (OPS-059 floor).
  void _announceCurrentAlert() {
    final explainer = AlertExplainer.forConditionAndProfile(
      _condition,
      _profile,
    );
    unawaited(
      _announcer.announce(
        severity: severityForCondition(_condition),
        text: explainer.action,
        localeTag: explainer.localeTag,
      ),
    );
  }

  void _fireAlertSequence() {
    final throttle = AlertDensityThrottle.forProfile(_profile);
    final now = DateTime.now();
    // Reset the window for this new burst; last-burst observation
    // gives the cleanest per-burst telemetry trace.
    _firedTimestampsWindow.clear();
    setState(() {
      _attempts.clear();
      // Fire 8 attempts in rapid sequence.
      for (var i = 0; i < 8; i++) {
        final t = now.add(Duration(seconds: i * 5));
        final fired = throttle.shouldFire(t, AlertSeverity.warning);
        _attempts.add(_FireAttempt(
          index: i + 1,
          relativeSeconds: i * 5,
          fired: fired,
        ));
        if (fired) {
          _firedTimestampsWindow.add(t);
        }
        // Emit one telemetry record per shouldFire decision. Outcome
        // disambiguation rule (per LoomFitOutcome doc-comments):
        //   - i == 0 + fired → coldStart (first alert in session).
        //   - severity == critical + fired → criticalBypass. The burst
        //     uses warning, so this branch does not fire here.
        //   - fired non-cold-start non-critical → fired.
        //   - !fired → droppedByThrottle.
        final LoomFitOutcome outcome;
        if (fired && i == 0) {
          outcome = LoomFitOutcome.coldStart;
        } else if (fired) {
          outcome = LoomFitOutcome.fired;
        } else {
          outcome = LoomFitOutcome.droppedByThrottle;
        }
        _telemetry.record(LoomFitTelemetryRecord(
          profileClass: _profile,
          ambientThreshold: 'rapid-burst-${i + 1}',
          alertSequence: List<DateTime>.unmodifiable(_firedTimestampsWindow),
          responseLatency: null,
          outcome: outcome,
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // What HER map draws about her position: from the position controller's
    // estimate when it is dead-reckoning or lost, so a GPS stream error never
    // blanks the map and `lost` says so in words (see her_map_inputs.dart).
    final herMap = herMapInputs(
      fix: _herFix,
      estimate: _driveHud.estimate,
      isMock: _isMockPosition,
      anchoredThisSession: _herAnchoredThisSession,
      noPositionYet: _herFirstEventOverdue,
      notGivenToDriveBrain: _herFixNotGivenToDriveBrain,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('sngnav-app (alpha)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Drawn only in a build that asks for it (kDeveloperPageFromEnvironment).
          if (_developerPageOffered)
            IconButton(
              key: const Key('developer-page-entry'),
              icon: const Icon(Icons.developer_mode),
              tooltip: AppL10n.of(context).developerPageTitle,
              onPressed: _openDeveloperPage,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Banner(),
            // HER map first, directly under the banner (2026-09-13): below the
            // developer panels it sat at 4314 px of an 852 px phone screen,
            // and she would have scrolled past fourteen cards to find herself.
            const SizedBox(height: 16),
            _section(
              title: AppL10n.of(context).mapSectionTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AkitaMap(
                    baseTileProvider: _offlineBaseProvider,
                    origin: _origin,
                    destination: _destination,
                    routePoints: switch (_routeResult) {
                      RouteSuccess(:final points) => points,
                      _ => const [],
                    },
                    // No onTap: a touch on her map sets no route point and
                    // clears none (ruled 2026-09-14). One more tap used to
                    // throw a set route away, and a tap is also the gesture
                    // that pauses follow.
                    herPosition: herMap.position,
                    herAccuracyMeters: herMap.accuracyMeters,
                    isHerPositionMock: _isMockPosition,
                    positionDegraded: herMap.degraded,
                    positionLost: herMap.lost,
                    positionRefused: herMap.refused,
                    positionNoneYet: herMap.noPositionYet,
                    mapController: _herMapController,
                    onMapEvent: _onHerMapEvent,
                    onMapReady: _onHerMapReady,
                    onTouchDown: _onHerMapTouched,
                  ),
                  // Under the map, not on it: a control on the map could hide
                  // her mark while follow is paused.
                  if (_showHerMapReturnControl) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton.icon(
                        key: const Key('her-map-return-to-position'),
                        onPressed: _returnHerMapToPosition,
                        icon: const Icon(Icons.my_location),
                        label: Text(AppL10n.of(context).returnToMyPosition),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _herStatusLine(),
                  // A1 — pre-drive voice-lane caution, in the consent/status
                  // region she reads BEFORE driving. Rendered ONLY on a
                  // proven-degraded verdict (jaNetworkOnly / noJaVoice);
                  // unknown and offlineJaReady show nothing.
                  if (_voiceLaneVerdict == VoiceLaneVerdict.jaNetworkOnly ||
                      _voiceLaneVerdict == VoiceLaneVerdict.noJaVoice) ...[
                    const SizedBox(height: 8),
                    _voiceLaneCautionRow(),
                  ],
                  // G-3 (AAA 2026-08-22) — pre-drive TACTILE caution, in the
                  // same region she reads BEFORE driving, on a `false` answer
                  // only. `null` (unreadable / off-mobile / test) renders
                  // NOTHING: a caution about a device that may vibrate
                  // perfectly well is a false alarm on the channel that can
                  // least afford one.
                  if (_hapticAvailable == false) ...[
                    const SizedBox(height: 8),
                    _hapticUnavailableCautionRow(),
                  ],
                  // Tier-2 — media-volume-zero caution, same pre-drive
                  // voice-lane region. Rendered ONLY on a proven-muted probe
                  // reading (null probe = NOTHING). Acknowledgment collapses
                  // it to a compact line; it never blocks the drive and we
                  // never touch her volume.
                  if (_audioReadiness?.mediaMuted ?? false) ...[
                    const SizedBox(height: 8),
                    if (_mediaMutedAcked)
                      _mediaMutedAckedLine()
                    else
                      _mediaMutedCautionRow(),
                    // ⚑ The muted caution names vibration as attempted, and
                    // she taps a button to continue without spoken alerts. If
                    // the tactile channel is not landing either, say so in the
                    // same glance — and after her tap too, since the state
                    // outlives the row she accepted it in.
                    //
                    // SUPPRESSED when the pre-drive caution already told her
                    // this device has NO vibrator: "could not be verified" is
                    // strictly weaker than "has none", and saying both on one
                    // glance surface is noise, not honesty. A device that HAS
                    // a vibrator and lost the cue still gets this line.
                    if (_hapticUnverified.value && _hapticAvailable != false) ...[
                      const SizedBox(height: 6),
                      _hapticUnverifiedInMutedNote(),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: AppL10n.of(context).driveHudTitle,
              child: _driveHudPanel(),
            ),
            const SizedBox(height: 16),
            _section(
              title: AppL10n.of(context).routeSectionTitle,
              child: _routePanel(),
            ),
            const SizedBox(height: 16),
            _section(
              title: AppL10n.of(context).maneuverSectionTitle,
              child: _maneuverNarrationPanel(),
            ),
            const SizedBox(height: 16),
            _section(
              title: AppL10n.of(context).akitaObservationSectionTitle,
              child: _jmaPanel(),
            ),
            const SizedBox(height: 16),
            _section(
              title: AppL10n.of(context).prefectureObservationsSectionTitle,
              child: _corridorPanel(),
            ),
            const SizedBox(height: 16),
            _section(
              title: AppL10n.of(context).advisoriesSectionTitle,
              child: AdvisoryCards(
                loading: _advisoryLoading,
                result: _advisoryResult,
                errorMessage: _advisoryErrorMessage,
                onRefresh: _onAdvisoryRefreshTapped,
                retainedAgeMinutes:
                    _advisoryRetained && _advisoryFetchedAt != null
                        ? _now().difference(_advisoryFetchedAt!).inMinutes
                        : null,
                pointCovered: _advisoryPointCovered,
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: AppL10n.of(context).logShareSectionTitle,
              child: _logSharePanel(),
            ),
            const SizedBox(height: 16),
            _section(
              title: AppL10n.of(context).diarySectionTitle,
              child: _diaryPanel(),
            ),
            const SizedBox(height: 16),
            const _Footer(),
          ],
        ),
      ),
    );
  }

  /// The cards that exist for the people who build the app, in the order they
  /// had on her home page until 2026-09-15. They read and write this page's
  /// state, so a choice made on the development page reaches the same code it
  /// reached before; the one such value her own page reads is the simulated
  /// road condition, which marks a possibly icy turn on her next-maneuver card.
  /// Last comes a card naming the packages the app is built on, which her page
  /// foot and live-drive card named until the same day.
  List<Widget> _developerSections() {
    final cap = AlertDensityThrottle.defaultCapFor(_profile);
    final glossary = RoadSurfaceConditionGlossary.forConditionAndProfile(
      _condition,
      _profile,
    );
    // Action-coupled explainer for current (condition, profile) tuple.
    // Action string is rendered VERBATIM per AAA Article 17 (β) — the
    // package owns the wording (advisory mood, road-surface vocabulary,
    // per-profile verbosity). The app must not paraphrase or restyle.
    // The wording is navigation_safety_core's own; it was described here
    // as JAF/MLIT vocabulary until that package's 0.11.8 entry recorded
    // that it never came from those sources.
    final explainer = AlertExplainer.forConditionAndProfile(
      _condition,
      _profile,
    );
    return [
      _section(
        title: AppL10n.of(context).driverTypeSectionTitle,
        child: DropdownButton<DriverProfile>(
          value: _profile,
          isExpanded: true,
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _profile = v;
                // Sub-bundle 4: per-cohort budgets + floor change
                // when the profile changes; tear down + rebuild
                // the trio so the active demo reflects the new
                // cohort defaults.
                _rebuildSubBundle4For(v);
              });
            }
          },
          items: DriverProfile.values
              .map((p) => DropdownMenuItem(
                    value: p,
                    child: Text(p.name),
                  ))
              .toList(),
        ),
      ),
      const SizedBox(height: 16),
      _section(
        title: AppL10n.of(context).simulatedRoadConditionSectionTitle,
        child: DropdownButton<RoadSurfaceCondition>(
          value: _condition,
          isExpanded: true,
          onChanged: (v) {
            if (v != null) setState(() => _condition = v);
          },
          items: RoadSurfaceCondition.values
              .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c.name),
                  ))
              .toList(),
        ),
      ),
      const SizedBox(height: 16),
      _section(
        title: AppL10n.of(context).vehicleTypeSectionTitle,
        child: DropdownButton<String?>(
          value: _vehicleClassToken,
          isExpanded: true,
          onChanged: (v) {
            setState(() => _vehicleClassToken = v);
          },
          items: const [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('unknown / no signal (baseline)'),
            ),
            DropdownMenuItem<String?>(
              value: 'kei-car',
              child: Text(
                'kei-car (HER cohort default — overrides registered)',
              ),
            ),
            DropdownMenuItem<String?>(
              value: 'compact-sedan',
              child: Text('compact-sedan (no override registered)'),
            ),
            DropdownMenuItem<String?>(
              value: '4wd',
              child: Text('4wd (no override registered)'),
            ),
            DropdownMenuItem<String?>(
              value: 'commercial-light',
              child: Text('commercial-light (no override registered)'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _section(
        title: AppL10n.of(context).driverStateInputsSectionTitle,
        child: _driverStateInputs(),
      ),
      const SizedBox(height: 16),
      _section(
        title: AppL10n.of(context).warningThresholdsSectionTitle,
        child: _ThresholdPreview(
          profile: _profile,
          vehicleClassToken: _vehicleClassToken,
          vehicleOverrides: _vehicleOverrides,
          circadianPhase: _circadianPhase,
          sessionState: _sessionState,
          confidence: _confidence,
          isHighConfidenceConfirmed: _isHighConfidenceConfirmed,
          kvBuilder: _kv,
        ),
      ),
      const SizedBox(height: 16),
      _section(
        title: AppL10n.of(context).roadConditionNamesSectionTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _kv('JA name', glossary.jaName),
            _kv('EN name', glossary.enName),
            _kv('JA speak', glossary.jaSpeakString),
            _kv('EN speak', glossary.enSpeakString),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _section(
        title: AppL10n.of(context).roadConditionGuidanceSectionTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Verbatim per AAA Article 17 (β): publisher voice
            // preserved; no app-side paraphrase or truncation.
            Text(
              explainer.action,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 6),
            _kv('Verbosity', explainer.verbosity.name),
            _kv('Locale', explainer.localeTag),
            const SizedBox(height: 4),
            Text(
              'Source: navigation_safety_core AlertExplainer — the '
              "package's own wording, rendered verbatim. It is not taken "
              'from JAF, MLIT or NEXCO, and the speeds it names are its '
              'own advisory reference points.',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 10),
            // WS5 — the button that ends the silence. Speaks the guidance
            // aloud AND fires the tactile cue (OPS-059 floor: audio for
            // eyes-off, haptic for deaf/HoH or roaring-wind whiteout).
            // On desktop/test this is a no-op (NoOpAlertActuators).
            // Label + helper are localized (D4 — HER reads Japanese).
            ElevatedButton.icon(
              key: const Key('announce-alert-button'),
              onPressed: _announceCurrentAlert,
              icon: const Icon(Icons.campaign_outlined),
              label: Text(AppL10n.of(context).announceToDriver),
            ),
            Text(
              severityForCondition(_condition).index >=
                      AlertSeverity.warning.index
                  ? AppL10n.of(context).announceFiresHelper(
                      severityForCondition(_condition).name)
                  : AppL10n.of(context).announceInfoHelper,
              // shade600 measured 4.17:1 on the card (2026-09-15).
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _section(
        title: AppL10n.of(context).alertRateLimitSectionTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _kv('Per-profile cap', '${cap.toStringAsFixed(1)} alerts/min'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _fireAlertSequence,
              child: const Text('Fire 8 sequential warning alerts'),
            ),
            const SizedBox(height: 4),
            // AAE-7: this control evaluates AlertDensityThrottle and
            // records telemetry. It does NOT call _announcer — no audio,
            // no haptic, nothing reaches HER from this button. It is a
            // throttle-decision simulation, and it says so, because the
            // 2026-07-09 on-device walk read its green result word as
            // proof the alert path actuates. It is not that proof.
            Text(
              'Throttle decision only — this control does not announce '
              '(no audio, no haptic).',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            if (_attempts.isEmpty)
              const Text('(no attempts yet)')
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _attempts
                    .map((a) => Text(
                          'Attempt ${a.index} '
                          '(t+${a.relativeSeconds}s): '
                          '${a.fired ? "WOULD FIRE" : "throttled"}',
                          style: TextStyle(
                            color: a.fired
                                ? Colors.green.shade700
                                : Colors.grey.shade600,
                          ),
                        ))
                    .toList(),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _section(
        title: AppL10n.of(context).tuningRecordSectionTitle,
        child: _loomFitTelemetryPanel(),
      ),
      const SizedBox(height: 16),
      _section(
        title: AppL10n.of(context).glanceAndVoicePacingSectionTitle,
        child: _glanceBudgetPanel(),
      ),
      const SizedBox(height: 16),
      _section(
        title: AppL10n.of(context).mapDrawingAndDataSectionTitle,
        child: _renderBudgetPanel(),
      ),
      const SizedBox(height: 16),
      // The live-drive card's demo controls, on her card until 2026-09-15:
      // the Akita mock position, the visibility band and the GPS blackout
      // simulator. They drive the same state as before; her card shows what
      // they set, and this page is the only place that sets it.
      _section(
        title: AppL10n.of(context).developerLiveDriveDemosSectionTitle,
        child: _liveDriveDemoControls(),
      ),
      const SizedBox(height: 16),
      // The package names that were on her page foot and her live-drive card
      // (2026-09-15).
      _section(
        title: AppL10n.of(context).developerPackagesSectionTitle,
        child: Text(
          key: const Key('developer-packages'),
          AppL10n.of(context).developerPackagesBody,
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        ),
      ),
    ];
  }

  /// The live-drive demos: controls that put a position or a condition on her
  /// card that nothing measured. Drawn only on the development page.
  Widget _liveDriveDemoControls() {
    final l = AppL10n.of(context);
    final hasBaseline = _herFix is PositionAvailable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            key: const Key('use-mock-button'),
            // Offered while no share and no mock runs, as it was on her card.
            onPressed: _herSub == null && !_isMockPosition
                ? _useMockPosition
                : null,
            child: Text(l.useAkitaMock),
          ),
        ),
        const SizedBox(height: 8),
        // Demo OVERRIDE for the visibility band. Default (null) = live/unknown;
        // the road has no visibility sensor, so absence reads as 未計測, never clear.
        Text(
          key: const Key('drive-hud-visibility-label'),
          l.driveHudVisibilityOverrideLabel,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        DropdownButton<double?>(
          key: const Key('drive-hud-visibility'),
          value: _mockVisibilityMeters,
          isExpanded: true,
          onChanged: _onVisibilityChanged,
          items: [
            for (final meters in _visibilityBands)
              DropdownMenuItem<double?>(
                value: meters,
                child: Text(l.driveHudVisibilityBand(meters)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // Wrap, not Row: at phone width the long button label + the live
        // blackout counter cannot both be honored at natural size — a fixed
        // Row overflows (caught by the w2 phone-geometry capture on CI).
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              key: const Key('drive-hud-blackout-button'),
              onPressed: hasBaseline ? _simulateGpsBlackout : null,
              icon: const Icon(Icons.gps_off),
              label: Text(l.driveHudSimulateBlackout),
            ),
            // orange.shade900 measured 3.43:1 on the card (2026-09-15); the
            // staleness colour already defined for orange grounds is 7.02:1.
            if (_blackoutSeconds > 0)
              Text(
                  key: const Key('drive-hud-blackout-seconds'),
                  l.driveHudBlackoutSeconds(_blackoutSeconds),
                  style: const TextStyle(
                      fontSize: 12, color: kCautionTextOnOrange)),
          ],
        ),
      ],
    );
  }

  Widget _section({required String title, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  /// C6 ログを共有 — the beta feedback card (BETA_PLAN fix #8, criterion C6).
  ///
  /// A tester sends the local error log the way she sends a photo: one tap,
  /// the OS share sheet, a receiver of her own choice. Consent-preserving by
  /// construction: the share fires ONLY from the tap (no auto-telemetry, no
  /// accounts), and the payload is strictly build-header + error log — the
  /// log stores no location history and the action adds none
  /// (services/log_share.dart). Styled like the location-consent card:
  /// liveRegion status line above, actions Wrap-ped below (phone-width
  /// overflow discipline), disclosure last.
  Widget _logSharePanel() {
    final l = AppL10n.of(context);
    final log = widget.errorLog;
    final status = log == null
        ? l.logShareUnavailable
        : (_logHasRecords(log) ? l.logShareHasRecords : l.logShareEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // liveRegion: assistive tech announces the log-state line when it
        // changes (OPS-059 floor — parity with the consent card). A node of
        // its own, or the flag merges into the card and the whole card is
        // announced (measured 2026-09-14).
        Semantics(
          container: true,
          liveRegion: true,
          child: Text(
            status,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                key: const Key('share-log-button'),
                onPressed: log == null ? null : _shareLog,
                child: Text(l.shareLog),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          key: const Key('log-share-disclosure'),
          l.logShareDisclosure,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
      ],
    );
  }

  /// O(1) stat (not a full read) — the status line re-renders on every
  /// build; reading the whole 200 KB log each frame would be waste. A stat
  /// failure degrades to "no records" honestly (matching readAll()'s
  /// empty-on-error contract).
  bool _logHasRecords(LocalErrorLog log) {
    try {
      return log.file.existsSync() && log.file.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }

  /// Composes header + log text and hands it to the injected sink
  /// (production: the platform share sheet). Payload composition is pure
  /// (services/log_share.dart) so tests pin it without a device; the OS
  /// share sheet itself is on-device verify DEFERRED (OPS-066, AAE
  /// env-bound).
  Future<void> _shareLog() async {
    final log = widget.errorLog;
    if (log == null) return;
    final payload = composeLogSharePayload(logText: log.readAll());
    try {
      await (widget.logShareSink ?? shareLogViaShareSheet)(payload);
    } catch (_) {
      // A share-sheet failure must never take the app down — the log
      // itself still holds the evidence for a later retry (parity with
      // LocalErrorLog's never-throws discipline).
    }
  }

  /// Ring-2 運転日記 — the season's consented evidence card (three-month
  /// plan §2). Same shape as the log-share panel: liveRegion status line,
  /// actions Wrap-ped (phone-width overflow discipline), disclosure last.
  /// Consent-preserving by construction: entries persist only to a local
  /// file (services/drive_diary.dart), no coordinates are recorded, and the
  /// diary leaves the device only via the explicit 日記を共有 tap.
  Widget _diaryPanel() {
    final l = AppL10n.of(context);
    final diary = widget.diary;
    final status = diary == null
        ? l.diaryUnavailable
        : (diary.hasEntries() ? l.diaryHasEntries : l.diaryEmpty);
    return Column(
      key: const Key('diary-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // liveRegion: assistive tech announces the diary-state line when it
        // changes (OPS-059 floor — parity with the log-share card). A node of
        // its own, as for the log-share line.
        Semantics(
          container: true,
          liveRegion: true,
          child: Text(
            status,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                key: const Key('diary-write-button'),
                onPressed: diary == null ? null : _writeDiaryEntry,
                child: Text(l.diaryWriteButton),
              ),
              TextButton(
                key: const Key('diary-share-button'),
                onPressed: diary == null ? null : _shareDiary,
                child: Text(l.diaryShareButton),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          key: const Key('diary-disclosure'),
          l.diaryDisclosure,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
      ],
    );
  }

  /// Opens the post-drive entry form (three taps and a line — parked, never
  /// while driving; this card lives below the fold, off the drive HUD).
  Future<void> _writeDiaryEntry() async {
    final diary = widget.diary;
    if (diary == null) return;
    final l = AppL10n.of(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _DiaryEntryDialog(diary: diary),
    );
    if (!mounted || saved == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(saved ? l.diarySavedLine : l.diarySaveFailedLine)),
    );
    if (saved) setState(() {}); // status line: empty -> has-entries
  }

  /// Composes header + diary text and hands it to the injected sink
  /// (production: the platform share sheet). Payload composition is pure
  /// (services/drive_diary.dart) so tests pin it without a device; the OS
  /// share sheet itself is on-device verify DEFERRED (OPS-066, AAE
  /// env-bound).
  Future<void> _shareDiary() async {
    final diary = widget.diary;
    if (diary == null) return;
    final payload = composeDiarySharePayload(diaryText: diary.readAll());
    try {
      await (widget.diaryShareSink ?? shareDiaryViaShareSheet)(payload);
    } catch (_) {
      // A share-sheet failure must never take the app down — the diary
      // itself still holds the entries for a later retry.
    }
  }

  /// Key/value row with an adaptive label column.
  ///
  /// W2 ladder fix (a) — the old fixed 110-px label column mangled long
  /// labels: 路面凍結ウォッチ wrapped MID-WORD (ladder_out/api30/03_jma_card.png)
  /// and the threshold-preview labels stacked one word per line
  /// (05b_airplane_top.png). The label is now measured at the live text
  /// scale: short labels keep the exact 110-px column (no visual change),
  /// longer ones take their natural single-line width, capped at 60% of the
  /// row so the value column always keeps room (word-boundary wrap beyond
  /// the cap — never a forced mid-word break at 110).
  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: LayoutBuilder(builder: (context, constraints) {
        final labelStyle = TextStyle(color: Colors.grey.shade700);
        final painter = TextPainter(
          text: TextSpan(
            text: '$k:',
            style: DefaultTextStyle.of(context).style.merge(labelStyle),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        var labelWidth = painter.width + 8; // breathing room before value
        painter.dispose();
        if (labelWidth < 110) labelWidth = 110;
        if (constraints.hasBoundedWidth &&
            labelWidth > constraints.maxWidth * 0.6) {
          labelWidth = constraints.maxWidth * 0.6;
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: labelWidth, child: Text('$k:', style: labelStyle)),
            Expanded(child: Text(v)),
          ],
        );
      }),
    );
  }

  /// Renders the rolling LoomFitTelemetry record list as
  /// development-class observability. AAA Article 17 (β) discipline:
  /// this panel is calibration substrate (insight #105), NOT
  /// driver-facing-class advice — section header + body framing must
  /// keep that boundary visible.
  Widget _loomFitTelemetryPanel() {
    if (_telemetryRecords.isEmpty) {
      return Text(
        'No records yet. Fire alerts via the throttle panel above to '
        'populate this calibration trace.',
        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'For developer / calibration use only — NOT driver-facing. '
          'Schema per loom_fit_telemetry.dart: profileClass × '
          'ambientThreshold × outcome × first 2 fired-window timestamps.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
        ),
        const SizedBox(height: 6),
        for (final r in _telemetryRecords) _telemetryRecordRow(r),
        const SizedBox(height: 4),
        Text(
          'Source: navigation_safety_core LoomFitTelemetry — emit-only '
          'broadcast stream; no data leaves this app surface.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
        ),
      ],
    );
  }

  Widget _telemetryRecordRow(LoomFitTelemetryRecord r) {
    final fmt = DateFormat('HH:mm:ss');
    final firstTwo = r.alertSequence.take(2).map(fmt.format).join(', ');
    final seqText = r.alertSequence.isEmpty ? '(empty window)' : firstTwo;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        '${r.outcome.name} · ${r.profileClass.name} · '
        '${r.ambientThreshold ?? "(no threshold)"} · seq=[$seqText]',
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
      ),
    );
  }

  Widget _jmaPanel() {
    if (_jmaLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final result = _jmaResult;
    if (result == null) {
      final l = AppL10n.of(context);
      return Row(children: [
        Text(l.advisoryNoFetchYet),
        const Spacer(),
        TextButton(onPressed: _refreshJma, child: Text(l.advisoryFetch)),
      ]);
    }
    switch (result) {
      case JmaSuccess(:final observation):
        final stale = observation.minutesStale(DateTime.now());
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ..._observationFieldRows(observation),
            _kv(AppL10n.of(context).observationFetchedLabel, _formatFetched(observation.fetchedAt, stale)),
            // BETA_PLAN W1 — the invisible-ice watch verdict, rendered with
            // the same honest-unknown discipline as the fields above.
            _kv(
              '路面凍結ウォッチ',
              switch (_invisibleIceResult) {
                InvisibleIceWatchResult.watch =>
                  '⚠ ブラックアイスバーンのおそれ（放射冷却の窓）',
                InvisibleIceWatchResult.clear => '該当なし',
                // The classifier DECLINED to judge this reading — every field
                // was measured and in range, and it still produced no verdict.
                // Deliberately distinguishable from `outOfScope`'s
                // 「本ウォッチの対象外」: that says another lane owns these
                // conditions, which is false here — no lane covers it (the app
                // has no fog concept at all). Not spoken: it is the absence of
                // a judgement, not a hazard (see the enum's dartdoc).
                InvisibleIceWatchResult.outsideModelEnvelope =>
                  '判定範囲外（この気象条件は判定していません）',
                // Sub-zero ambient, no precip: expected-frozen regime. Distinct,
                // possibility-graded, NOT the surprise wording (Chair
                // calibration 2026-07-23; Andon 2026-07-20T13:40Z).
                InvisibleIceWatchResult.subZeroFrozen =>
                  '⚠ 路面凍結のおそれ（気温0°C以下）',
                // A scope exclusion is NOT an all-clear. Say plainly that
                // this watch does not cover these conditions, and never
                // imply the surface is safe (Andon 2026-07-20T13:40Z).
                InvisibleIceWatchResult.outOfScope =>
                  '本ウォッチの対象外（この条件は判定していません）',
                InvisibleIceWatchResult.unknown || null =>
                  '判定不能（気温・湿度・降水の観測値が不足）',
              },
            ),
            // BETA_PLAN W3 — the measured-turmoil watch verdict, same
            // honest-unknown discipline (per-channel 判定不能 named).
            _kv(
              '荒天ウォッチ',
              _turmoilState == null
                  ? '判定不能（降水・風の観測値が不足）'
                  : turmoilRowText(_turmoilState!),
            ),
            const SizedBox(height: 8),
            // Honesty split (CT Joel-Test catch, 2026-07-09 vision audit):
            // the observation fields above are verbatim relay; the watch rows
            // are NOT — they are derived classifications. One caption claiming
            // "no derivation" under both was a false claim on the safety
            // surface.
            Text(
              AppL10n.of(context).akitaObservationSource,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('jma-refetch-button'),
                onPressed: _refreshJma,
                child: Text(AppL10n.of(context).advisoryReFetch),
              ),
            ),
          ],
        );
      case JmaFailure():
        // N15 — the screen must match the speaker. This panel previously said
        // "Cached data is NOT shown" while the voice was WARNING FROM that
        // cache (the stale black-ice re-warn) — a flat contradiction on the
        // safety surface. The verdict below is computed by the SAME function
        // the voice path announces from ([feedLossVerdict]), so the two
        // channels cannot drift apart, and every feed-loss spoken line has a
        // visible counterpart a deaf/HoH or muted-media driver can read.
        final verdict = feedLossVerdict(
          cached: _lastGoodObservation,
          memory: _tripHazardMemory,
          now: _now(),
          spokenJa: _spokenJa,
        );
        final retained = _lastGoodObservation;
        final l = AppL10n.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.red.shade50,
              child: Text(
                key: const Key('jma-fetch-failed'),
                l.jmaObservationFetchFailed,
                style: TextStyle(color: Colors.red.shade900),
              ),
            ),
            const SizedBox(height: 4),
            ...switch (verdict) {
              // Retained + hazard: the fields she may be HEARING about, with
              // the staleness label FIRST, then the visible counterpart of the
              // exact stamped line the voice re-warns with.
              FeedLossStaleIce(:final hourJst, :final ageMinutes) => [
                  _jmaStaleBanner(l, ageMinutes),
                  if (retained != null) ..._observationFieldRows(retained),
                  const SizedBox(height: 4),
                  _staleIceVisibleCard(hourJst),
                ],
              // Retained, no slow hazard: the fields, staleness labelled.
              // Deliberately NO watch-verdict row re-rendered from the stale
              // reading — a stale 「該当なし」 shown here would read as current
              // calm, and absence must never render as calm.
              FeedLossRetainedQuiet(:final ageMinutes) => [
                  _jmaStaleBanner(l, ageMinutes),
                  if (retained != null) ..._observationFieldRows(retained),
                ],
              // No valid observation, but the plan-time forecast memory holds
              // a publisher-declared hazard valid NOW: the observation lane is
              // honestly empty AND the forecast card shows what the voice says.
              FeedLossForecastMemory(
                :final line,
                :final capturedAt
              ) =>
                [
                  _noValidObservationRow(l),
                  const SizedBox(height: 4),
                  _forecastMemoryVisibleCard(l, line, capturedAt),
                ],
              // Nothing valid to show: the visible counterpart of the spoken
              // absence line — never a bare "not shown" that contradicts or
              // undersells what the speaker said.
              FeedLossAbsence() => [
                  _conditionsUnknownVisibleRow(),
                ],
            },
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('jma-retry-button'),
                onPressed: _refreshJma,
                child: Text(l.retry),
              ),
            ),
          ],
        );
    }
  }

  /// The verbatim JMA observation fields — shared between the success panel
  /// and the feed-loss retained display, so a retained reading renders with
  /// IDENTICAL formatting to a live one (only the labels around it differ:
  /// success adds Fetched + the live watch rows; feed-loss adds the staleness
  /// banner and never re-renders a watch verdict from stale data).
  List<Widget> _observationFieldRows(JmaObservation observation) {
    final temp = observation.temperatureCelsius;
    final hum = observation.humidityPercent;
    final wind = observation.windMetersPerSecond;
    final snow = observation.snowDepthCm;
    final ts = observation.observedAtJstKey;
    // Format observed-at: yyyymmddHHMMSS → yyyy-mm-dd HH:MM JST
    String obsDisplay = ts;
    if (ts.length == 14) {
      obsDisplay =
          '${ts.substring(0, 4)}-${ts.substring(4, 6)}-${ts.substring(6, 8)} '
          '${ts.substring(8, 10)}:${ts.substring(10, 12)} JST';
    }
    return [
      _kv(AppL10n.of(context).observationStationLabel, '${observation.stationName} (${observation.stationId})'),
      _kv(AppL10n.of(context).observationObservedAtLabel, obsDisplay),
      _kv(AppL10n.of(context).observationTemperatureLabel, temp == null ? '—' : '${temp.toStringAsFixed(1)} °C'),
      _kv(AppL10n.of(context).observationHumidityLabel, hum == null ? '—' : '$hum %'),
      _kv(AppL10n.of(context).observationWindLabel, wind == null ? '—' : '${wind.toStringAsFixed(1)} m/s'),
      // W3 — the measured rain-rate the turmoil watch judges on,
      // shown verbatim beside the inference (same discipline as the
      // fields above; '—' = the station did not report the field).
      _kv(
        '降水量（10分間）',
        observation.precipitation10mMm == null
            ? '—'
            : '${observation.precipitation10mMm!.toStringAsFixed(1)} mm',
      ),
      _kv(AppL10n.of(context).observationSnowDepthLabel, snow == null ? '—' : '${snow.toStringAsFixed(0)} cm'),
    ];
  }

  /// N15 — prominent staleness label over RETAINED observation fields after a
  /// failed fetch. The retained fields ARE shown (the voice may be warning
  /// from them); this banner is the on-screen guarantee she is not reading
  /// them as live (the visual sibling of the spoken 「最新の情報は取得できて
  /// いません」 clause).
  Widget _jmaStaleBanner(AppL10n l, int ageMinutes) {
    return Container(
      key: const Key('jma-stale-banner'),
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      // liveRegion — live→stale is a safety-relevant transition; assistive
      // tech must announce it (OPS-059 floor). Contrast: orange.shade900 on
      // orange.shade50 was ~3.5:1, below the AA 4.5:1 floor at this size —
      // kCautionTextOnOrange measures ~7.1:1. 13 px, up from 12, for the
      // ageing-rural cohort this label protects.
      child: Semantics(
        liveRegion: true,
        child: Text(
          l.jmaRetainedStale(ageMinutes),
          style: const TextStyle(
            color: kCautionTextOnOrange,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// N15 — the observation lane is honestly EMPTY (no reading within the
  /// retain bound); shown above the forecast-memory card so the card is never
  /// mistaken for an observation.
  Widget _noValidObservationRow(AppL10n l) {
    return Text(
      l.jmaNoValidObservation,
      key: const Key('jma-no-valid-observation'),
      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
    );
  }

  /// N15 — visible counterpart of the stale black-ice re-warn: the EXACT text
  /// the voice speaks ([staleInvisibleBlackIceSpokenText], same hour stamp,
  /// same locale source [_spokenJa] — AAA F1: the eyes-on channel renders the
  /// identical content the eyes-off channel speaks). liveRegion so assistive
  /// tech announces it (OPS-059 floor).
  Widget _staleIceVisibleCard(int hourJst) {
    return Container(
      key: const Key('stale-ice-visible'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // kCautionTextOnAmber + 13 px — the amber.shade900-on-amber.shade50
          // pair was ~2.6:1, functionally invisible to a reduced-contrast
          // elderly reader (OPS-059 AA floor 4.5:1; this measures ~7.9:1).
          const Icon(Icons.warning_amber, size: 16, color: kCautionTextOnAmber),
          const SizedBox(width: 6),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                staleInvisibleBlackIceSpokenText(
                  hourJst: hourJst,
                  ja: _spokenJa,
                ),
                style: const TextStyle(
                  color: kCautionTextOnAmber,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// N15 — visible counterpart of the forecast-memory line (C2 RED-1): the
  /// EXACT line the voice speaks when it speaks (ja + covered mouth), or the
  /// visible-only counterpart when the voice keeps the absence line (en
  /// surface / uncovered mouth — see [FeedLossForecastMemory.spokenAloud]).
  /// Plus the capture timestamp so she knows this is plan-time knowledge,
  /// not a reading we just took. liveRegion for assistive tech (OPS-059
  /// floor).
  Widget _forecastMemoryVisibleCard(
    AppL10n l,
    String spokenJaLine,
    DateTime capturedAt,
  ) {
    final time = DateFormat('HH:mm').format(capturedAt.toLocal());
    return Container(
      key: const Key('forecast-memory-visible'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Contrast floor — see _staleIceVisibleCard.
              const Icon(Icons.ac_unit, size: 16, color: kCautionTextOnAmber),
              const SizedBox(width: 6),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    spokenJaLine,
                    style: const TextStyle(
                      color: kCautionTextOnAmber,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l.forecastMemoryCaption(time),
            style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
          ),
        ],
      ),
    );
  }

  /// N15 — visible counterpart of the spoken absence line: the EXACT text the
  /// voice speaks (same locale source [_spokenJa]). Amber, not grey body
  /// text: "we do not know the road state" is caution-class information, and
  /// absence must never render as calm. liveRegion for assistive tech.
  Widget _conditionsUnknownVisibleRow() {
    return Container(
      key: const Key('conditions-unknown-visible'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      // A node of its own: without `container` the flag merged into the
      // weather card, and the whole card was announced (measured 2026-09-14).
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Text(
          _spokenJa
              ? kConditionsUnknownJaSpokenText
              : kConditionsUnknownEnSpokenText,
          // Contrast floor — see _staleIceVisibleCard.
          style: const TextStyle(
            color: kCautionTextOnAmber,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// A1 pre-drive voice-lane caution row (compact, amber — caution-class,
  /// not error-class: the app still runs; the AUDIO lane may go silent where
  /// there is no signal). liveRegion so assistive tech announces it
  /// (OPS-059 floor, parity with the consent/status lines).
  Widget _voiceLaneCautionRow() {
    final l = AppL10n.of(context);
    return Container(
      key: const Key('voice-lane-caution'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      // amber.shade900 on this amber.shade50 measured 2.63:1 (2026-09-15);
      // kCautionTextOnAmber is 7.90:1.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.volume_off_outlined,
              size: 16, color: kCautionTextOnAmber),
          const SizedBox(width: 6),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                l.voiceOfflineCaution,
                style: const TextStyle(
                  color: kCautionTextOnAmber,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tier-2 media-muted caution row — STRONGER than the amber A1 row
  /// (red-tinted): the media stream is PROVEN at zero, so every spoken
  /// safety alert is silent right now. Carries the acknowledge action
  /// (informed haptics-only consent). NO behavior gating — the driver always
  /// drives, haptic is already unconditional, and we NEVER touch her volume:
  /// that is the Tier-3 dignity boundary the Chair holds (we inform; a
  /// volume-overriding actuator is a Chair-level dignity question, never an
  /// engineering default). liveRegion so assistive tech announces it
  /// (OPS-059 floor).
  Widget _mediaMutedCautionRow() {
    final l = AppL10n.of(context);
    return Container(
      key: const Key('media-muted-caution'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.volume_off, size: 16, color: Colors.red.shade900),
              const SizedBox(width: 6),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    l.mediaMutedCaution,
                    style: TextStyle(
                      color: Colors.red.shade900,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              key: const Key('media-muted-ack-button'),
              onPressed: () => setState(() => _mediaMutedAcked = true),
              child: Text(l.mediaMutedAckButton),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact acknowledged line after HER tap collapses the muted caution.
  Widget _mediaMutedAckedLine() {
    final l = AppL10n.of(context);
    return Row(
      key: const Key('media-muted-acked'),
      children: [
        Icon(Icons.vibration, size: 14, color: Colors.grey.shade700),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            l.mediaMutedAckedLine,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }

  /// Pre-drive caution: the platform reports NO vibrator.
  ///
  /// The stronger, MEASURED statement — *this device has none* — said before
  /// she commits to the drive, rather than *we could not verify* said after a
  /// warning was already lost. Red-tinted like the media-muted row rather than
  /// amber like the A1 voice row: for the driver whose ears are out, this is
  /// not a degradation of one channel among two, it is the loss of the last
  /// non-visual one. liveRegion so assistive tech announces it (OPS-059).
  Widget _hapticUnavailableCautionRow() {
    final l = AppL10n.of(context);
    return Container(
      key: const Key('haptic-unavailable-caution'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.vibration, size: 16, color: Colors.red.shade900),
          const SizedBox(width: 6),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                l.hapticUnavailableCaution,
                style: TextStyle(
                  color: Colors.red.shade900,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Says, inside the media-muted region, that the tactile channel did not
  /// land either.
  ///
  /// Rendered ONLY when the tactile channel has actually reported an owed cue
  /// lost — never pre-emptively, because a device that vibrates fine must not
  /// be told it might not (the same cry-wolf discipline that keeps the
  /// info-class cue silent). liveRegion so assistive tech announces it: the
  /// driver this line is for may be reading the screen through a
  /// screen-reader, and it is the only channel left.
  Widget _hapticUnverifiedInMutedNote() {
    final l = AppL10n.of(context);
    return Row(
      key: const Key('haptic-unverified-note'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.vibration, size: 14, color: Colors.red.shade900),
        const SizedBox(width: 6),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(
              l.hapticUnverifiedInMutedNote,
              style: TextStyle(
                fontSize: 12,
                color: Colors.red.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The honest position has degraded to dead-reckoning/lost on a REAL-GPS
  /// drought (never in deliberate mock mode). The map dot + status line couple
  /// to this so they cannot outlive the HUD's honest degrade — the silent-
  /// blackout bug where `_herFix` keeps a confident last point on the surface
  /// HER eyes snap to.
  bool get _herPositionDegraded =>
      !_isMockPosition && _driveHud.positionUnlocatable;

  /// The last event on her map is one the drive brain was not given
  /// ([_herHeldEvent]): no surface draws or states a position from it.
  bool get _herFixNotGivenToDriveBrain =>
      _herHeldEvent != null && identical(_herFix, _herHeldEvent);

  Widget _herStatusLine() {
    final l = AppL10n.of(context);
    // Initial state: no mode active. Deny-by-default — nothing touches GPS
    // until HER deliberate tap. The localized disclosure sits here so she can
    // read WHERE her coordinates go BEFORE she grants (task 3).
    if (_herSub == null && !_isMockPosition) {
      // W2 ladder fix (a) — ladder_out/api30/02b_location_consent.png showed
      // the status line ("Location not yet shared.") crammed into a
      // one-syllable-wide column beside the two consent buttons. The most
      // trust-carrying line on the card must read as a sentence: it now gets
      // the FULL card width, and the actions sit on their own row below,
      // Wrap-ping instead of squeezing when the screen is narrow.
      // liveRegion: assistive tech announces the consent-state line when it
      // changes (OPS-059 floor — the state change must reach eyes-off users).
      // A node of its own, labelled only this line (ruled 2026-09-14): it
      // merged into the map card, whose announced label was 736 characters.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              l.locationNotShared,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  key: const Key('share-location-button'),
                  onPressed: _shareLocation,
                  child: Text(l.shareMyLocation),
                ),
                // The Akita mock position is on the development page
                // (2026-09-15); a release build never offers it.
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            key: const Key('location-disclosure'),
            l.locationDisclosure,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 4),
          // B27+B30 — the REST of the real wire, on the same card: the OSRM
          // route egress (consent-gated pre-send), the online tile fallback
          // (tile.openstreetmap.org sees viewport tiles + IP), and the
          // network-TTS possibility. The coordinates-story she decides with
          // must not omit an egress that exists.
          Text(
            key: const Key('egress-disclosure'),
            l.egressDisclosure,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      );
    }
    // Mock-mode active.
    if (_isMockPosition) {
      final acc = switch (_herFix) {
        PositionAvailable(accuracyMeters: final double accuracyMeters) =>
          accuracyMeters.toStringAsFixed(0),
        _ => '35',
      };
      return Row(
        children: [
          Expanded(
            // amber.shade900 measured 2.52:1 on the card (2026-09-15);
            // kCautionTextOnAmber is 7.60:1 and still reads as amber.
            child: Text(
              l.mockPositionStatus(acc),
              style: const TextStyle(
                fontSize: 12,
                color: kCautionTextOnAmber,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: _clearPosition,
            child: Text(l.clear),
          ),
        ],
      );
    }
    // Real-GPS mode active.
    final fix = _herFix;
    final estimate = _driveHud.estimate;
    // On a silent GPS drought the raw fix stream stops emitting, so `_herFix`
    // still holds the last confident point — but the honest estimate has
    // degraded. In dead-reckoning, reuse the SAME label the HUD text shows
    // (「GPS 途絶（推測航法）」) + the last-known radius, so the status line under
    // the map can never assert 「現在地 ±Xm」 while the position is untrustworthy.
    //
    // In `lost` the line says how old the last trusted position is, never a
    // radius (2026-09-13): the controller no longer vouches for one, and with
    // no trusted fix ever the radius is infinite — this line used to read
    // 「現在地 不明 · 最後の位置 ±Infinitym」. Localized through AppL10n.
    //
    // Degraded from an anchor no event of this session set, the line claims
    // no last position: the same rule the map follows (her_map_inputs.dart).
    final degradedText = estimate == null
        ? null
        : !_herAnchoredThisSession
            ? l.positionLostStatus(double.infinity)
            : estimate.mode == LocalizationMode.lost
            ? l.positionLostStatus(estimate.secondsSinceTrustedFix)
            // Dead reckoning, in the app's resolved locale (was 'ja' and a
            // Japanese literal): an English device read Japanese here.
            : l.positionDeadReckoningStatus(
                _driveHudText.modeLabel(estimate.mode, l.locale.languageCode),
                estimate.confidenceRadiusMeters.toStringAsFixed(0),
              );
    final (text, color) = switch (fix) {
      // 60 s after the position stream subscribed, with nothing arrived:
      // "locating" is a promise the app has no evidence for (ruled
      // 2026-09-14). The app's existing line for a position unknown with no
      // trusted fix ever, the state the map now names, in that line's colour.
      null when _herFirstEventOverdue => (
        l.positionLostStatus(double.infinity),
        Colors.blueGrey.shade700,
      ),
      // shade600 measured 4.17:1 on the card (2026-09-15); shade700 is 5.60:1.
      null => (
        l.locatingYou,
        Colors.grey.shade700,
      ),
      // A position the drive brain was not given (ruled 2026-09-14): it would
      // not have been a trusted fix, so the line claims no position and no
      // radius, the words the same event gets when the brain refuses it.
      PositionAvailable() when _herFixNotGivenToDriveBrain => (
        l.positionLostStatus(double.infinity),
        Colors.blueGrey.shade700,
      ),
      // shade700, not shade400 (2026-09-13): in dead reckoning and lost this
      // line was the palest text on the surface, 3.03:1, while it is the only
      // place the age of her last position appears. Rendered at 6.55:1.
      PositionAvailable()
          when _herPositionDegraded && degradedText != null => (
        degradedText,
        Colors.blueGrey.shade700,
      ),
      PositionAvailable(accuracyMeters: final double accuracyMeters) => (
        l.youAreHere(accuracyMeters.toStringAsFixed(0)),
        Colors.blueGrey.shade700,
      ),
      // No measured accuracy (ruled 2026-09-14): the line states no radius.
      PositionAvailable() => (
        l.positionLostStatus(double.infinity),
        Colors.blueGrey.shade700,
      ),
      // Location is off for this app: the ruled line (2026-09-13), headed by
      // the same words as the map. Read from the typed cause, never from the
      // reason text.
      PositionUnavailable() when isLocationRefusal(fix) => (
        l.locationOffStatus(
          permanently: isPermanentLocationRefusal(fix),
          routeSettingOpen: _routeSettingOpen,
        ),
        Colors.grey.shade700,
      ),
      // This app has no location on this device, known from the exception's
      // type (ruled 2026-09-14). Only the words change: the event still
      // reaches the drive brain as before.
      PositionUnavailable() when isNoLocationOnThisDevice(fix) => (
        l.noLocationOnThisDeviceStatus,
        Colors.grey.shade700,
      ),
      PositionUnavailable(:final reason) => (
        l.gpsUnavailable(reason, routeSettingOpen: _routeSettingOpen),
        Colors.grey.shade700,
      ),
    };
    return Row(
      children: [
        Expanded(
          child: Text(
            key: const Key('her-status-line'),
            text,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ),
        TextButton(
          onPressed: _clearPosition,
          // After a denial nothing was started, so the same action is
          // offered as 閉じる / "Close", not 停止 / "Stop".
          child: Text(isLocationRefusal(fix) ? l.close : l.stop),
        ),
      ],
    );
  }

  /// The route section. A route is set only through the route act, opened
  /// from the control here, beside the ruled words; where route setting is
  /// closed the words stand alone (ruled 2026-09-14). Nothing on her map
  /// reaches this panel's state.
  Widget _routePanel() {
    final l = AppL10n.of(context);
    // One line per host, never both (ruled 2026-09-14). On a host that reads no
    // vehicle signal no state of the car opens route setting, so its line names
    // no stop; the phone keeps the line that names the stop that opens it.
    final whenStopped = routeSettingHost() == RouteSettingHost.phone
        ? Text(
            l.routeSettingWhenStopped,
            key: const Key('route-setting-when-stopped'),
            style: TextStyle(color: Colors.grey.shade800, fontSize: 12),
          )
        : Text(
            l.routeSettingClosedOnThisDevice,
            key: const Key('route-setting-closed-on-this-device'),
            style: TextStyle(color: Colors.grey.shade800, fontSize: 12),
          );
    // Closed (the IVI with no vehicle signal, or a phone measured moving): the
    // words, and a route she already set shown as it is, with no control that
    // sets, re-asks or clears one. Until 2026-09-14 closed meant the IVI only,
    // where no route can exist, and this branch drew the words alone; on a
    // phone that would hide a set route's distance, time and its "not
    // snow-aware" line the moment she moves, while its line stays on her map.
    final open = _routeSettingOpen;
    _routeSettingOpenBuilt = open;
    return Column(
      key: const Key('route-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        whenStopped,
        if (open)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              key: const Key('route-act-open'),
              onPressed: _openRouteAct,
              icon: const Icon(Icons.alt_route),
              label: Text(l.routeActOpen),
            ),
          ),
        if (open || _routeLoading || _routeResult != null)
          const SizedBox(height: 8),
        if (_routeLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          switch (_routeResult) {
            null => const SizedBox.shrink(),
            RouteSuccess(:final distanceMeters, :final durationSeconds) => Column(
                key: const Key('route-summary'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _kv(l.routeDistanceLabel,
                      '${(distanceMeters / 1000).toStringAsFixed(1)} km'),
                  _kv(l.routeDurationLabel, l.routeDuration(durationSeconds)),
                  const SizedBox(height: 4),
                  Text(
                    l.routeSourceOsrmDemo,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ],
              ),
            // The app's own words only (ruled 2026-09-14). The reason stays in
            // the result and reaches no widget: it can hold the request's
            // address with both chosen points, or a server's whole reply. It
            // is not written to the error log either, which keeps no location.
            RouteFailure() => Container(
                key: const Key('route-fetch-failed'),
                padding: const EdgeInsets.all(8),
                color: Colors.red.shade50,
                child: Text(
                  l.routeFetchFailed,
                  style: TextStyle(color: Colors.red.shade900),
                ),
              ),
            // B27 — decline is an honest NEUTRAL state, never error-styled:
            // the router did not fail, it was never asked. The change-choice
            // action keeps a remembered "no" from becoming a locked door.
            RouteConsentDeclined() => Container(
                key: const Key('route-consent-declined'),
                padding: const EdgeInsets.all(8),
                color: Colors.blueGrey.shade50,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      AppL10n.of(context).routeConsentDeclinedMessage,
                      style: TextStyle(
                        color: Colors.blueGrey.shade900,
                        fontSize: 12,
                      ),
                    ),
                    if (open)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          key: const Key('route-consent-change'),
                          onPressed: () {
                            // Re-open the question; the new answer (if any)
                            // is persisted over the old one.
                            _osrmConsent = null;
                            _fetchRoute();
                          },
                          child: Text(
                            AppL10n.of(context).routeConsentChangeChoice,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          },
        // A remembered yes is not a locked door either: after she agreed to
        // send, the same control that re-asks after a no is offered here.
        if (open && !_routeLoading && _osrmConsent == true)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              key: const Key('route-consent-change'),
              onPressed: _changeRouteConsentAfterYes,
              child: Text(l.routeConsentChangeChoice),
            ),
          ),
        if (open)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _origin == null ? null : _resetRoute,
              child: Text(l.routeReset),
            ),
          ),
      ],
    );
  }

  /// (e) The next maneuver, narrated ONLY when the honest position allows it.
  ///
  /// The panel reflects the SAME gate the announcer uses, so what is shown
  /// on-screen matches what would be spoken — including SUPPRESSION, because a
  /// wrong "turn right" is confidently-wrong whether heard OR seen.
  Widget _maneuverNarrationPanel() {
    final next = _nextManeuver;
    if (next == null) {
      return Text(
        key: const Key('maneuver-placeholder'),
        _routeResult is RouteSuccess
            ? AppL10n.of(context).routeNoManeuvers
            : AppL10n.of(context)
                .maneuverNoRouteYet(routeSettingOpen: _routeSettingOpen),
        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
      );
    }

    // Scoped as the caution panel is: an earlier session's estimate says
    // nothing about where she is in this one, and neither does a share she
    // ended or refused (2026-09-15).
    final mode =
        _driveHudPositionIsThisDrives ? _driveHud.estimate?.mode : null;
    final icy = _maneuverCoincidesWithHazard();
    final preview = _driveHud.previewNextManeuver(next,
        icyTurn: icy, positionIsThisShares: _driveHudPositionIsThisDrives);

    // The banner's state in the app's language (2026-09-15). Until then it was
    // the gate's internal name and an English reason in every language; the
    // reason is carried by the position row above and by her line.
    final l = AppL10n.of(context);
    final (Color bg, Color fg, String tier) = switch (preview.confidence) {
      NarrationConfidence.speak => (
          Colors.green.shade100,
          Colors.green.shade900,
          l.maneuverTierSpeak,
        ),
      // amber.shade900 here was 2.38:1 (2026-09-15). No position the app
      // gives the drive brain reaches this state today, so no rendered test
      // reaches it; kCautionTextOnAmber on amber.shade100 is 7.16:1.
      NarrationConfidence.hedge => (
          Colors.amber.shade100,
          kCautionTextOnAmber,
          l.maneuverTierHedge,
        ),
      NarrationConfidence.suppressed => (
          Colors.blueGrey.shade100,
          Colors.blueGrey.shade900,
          l.maneuverTierSuppressed,
        ),
    };

    // When suppressed there is NO maneuver phrase to show (the decision carries
    // empty text by construction) — show the honest "guidance paused" line, not
    // a turn.
    // In the app's resolved locale (2026-09-14; was a Japanese literal on every
    // device), like the narration text it stands in for.
    final herLine = preview.confidence == NarrationConfidence.suppressed
        ? l.maneuverGuidancePaused
        : preview.text;

    // Not drawn since 2026-09-15, because they are for the people who build
    // the app and not for her: a paragraph naming the routing class, its
    // request flag and the gate's state names; a count of parsed maneuvers;
    // and a note that turn timing and hearing are unverified in this
    // environment. That bound is recorded in KNOWN_LIMITATIONS.md.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mode != null)
          _kv(l.driveHudPositionTrustLabel,
              _driveHudText.modeLabel(mode, l.locale.languageCode)),
        // NOTE: the raw ENGLISH engine instruction is deliberately NOT rendered
        // to HER — it would both leak English to a JA driver (D4) and show a
        // confident "turn" string even when the position gate suppresses it.
        // HER sees only the gated, JA-localized narration banner below.
        const SizedBox(height: 8),
        Container(
          key: const Key('maneuver-narration-banner'),
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                key: const Key('maneuver-narration-tier'),
                tier,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(herLine, style: TextStyle(color: fg, fontSize: 15)),
              if (preview.icyCoupled &&
                  preview.confidence != NarrationConfidence.suppressed) ...[
                const SizedBox(height: 4),
                Text(
                  l.maneuverIcyMark,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // Nothing measured reaches this mark: the only input is the
                // simulated road condition (2026-09-16). Words to be ruled.
                Text(
                  key: const Key('maneuver-test-road-condition'),
                  l.maneuverTestRoadConditionInForce,
                  style: TextStyle(color: fg, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              key: const Key('maneuver-narrate-button'),
              onPressed: _narrateNextManeuver,
              icon: const Icon(Icons.record_voice_over),
              label: Text(l.maneuverNarrateButton),
            ),
            const SizedBox(width: 8),
            if (_lastManeuverNarration != null)
              Expanded(
                child: Text(
                  key: const Key('maneuver-narration-result'),
                  _lastManeuverNarration!.shouldAnnounce
                      ? l.maneuverNarrationAnnounced
                      : l.maneuverNarrationNotSpoken,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _corridorPanel() {
    if (_corridorLoading && _corridorResults == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final results = _corridorResults;
    if (results == null) {
      final l = AppL10n.of(context);
      return Row(children: [
        Text(l.advisoryNoFetchYet),
        const Spacer(),
        TextButton(onPressed: _refreshCorridor, child: Text(l.advisoryFetch)),
      ]);
    }
    // Compute temperature min/max across resolved stations for gradient shading.
    final temps = <double>[];
    for (final r in results) {
      if (r is JmaSuccess && r.observation.temperatureCelsius != null) {
        temps.add(r.observation.temperatureCelsius!);
      }
    }
    final tempMin = temps.isEmpty ? null : temps.reduce((a, b) => a < b ? a : b);
    final tempMax = temps.isEmpty ? null : temps.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header row
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              SizedBox(
                width: corridorStationColumnWidth,
                child: Text(AppL10n.of(context).prefectureHeadStation,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: Text(AppL10n.of(context).prefectureHeadSnow,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: Text(AppL10n.of(context).prefectureHeadTemp,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: Text(AppL10n.of(context).prefectureHeadWind,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              SizedBox(
                width: corridorObservedColumnWidth,
                child: Text(AppL10n.of(context).prefectureHeadObserved,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const Divider(height: 4),
        for (var i = 0; i < results.length; i++)
          CorridorRow(
            result: results[i],
            descriptor: corridorStations[i].descriptor,
            tempMin: tempMin,
            tempMax: tempMax,
          ),
        const SizedBox(height: 4),
        Text(
          key: const Key('prefecture-observations-source'),
          AppL10n.of(context).prefectureObservationsSource,
          style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _refreshCorridor,
            child: Text(AppL10n.of(context).prefectureRefetchAll),
          ),
        ),
      ],
    );
  }

  String _formatFetched(DateTime fetchedAt, int minutesStale) {
    final fmt = DateFormat('HH:mm');
    return AppL10n.of(context)
        .observationFetchedAt(fmt.format(fetchedAt), minutesStale);
  }

  // ===== Sub-bundle 2 — Driver state inputs panel =====

  Widget _driverStateInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // CircadianPhase dropdown.
        const Text('Circadian phase (#28; multiplier 1.0–1.5×)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        DropdownButton<CircadianPhase?>(
          value: _circadianPhase,
          isExpanded: true,
          onChanged: (v) => setState(() => _circadianPhase = v),
          items: <DropdownMenuItem<CircadianPhase?>>[
            const DropdownMenuItem(
              value: null,
              child: Text('(no signal — baseline)'),
            ),
            for (final p in CircadianPhase.values)
              DropdownMenuItem(
                value: p,
                child: Text('${p.name} (×${p.multiplier.toStringAsFixed(2)})'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // SessionState compose-fields (consecutive days + fatigue class).
        const Text('Session state (#29; consecutive days + fatigue class)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        Row(
          children: [
            const Text('Days:'),
            Expanded(
              child: Slider(
                value: _consecutiveDrivingDays.toDouble(),
                min: 0,
                max: 14,
                divisions: 14,
                label: '$_consecutiveDrivingDays',
                onChanged: (v) => _updateSessionState(days: v.round()),
              ),
            ),
            Text('$_consecutiveDrivingDays'),
          ],
        ),
        DropdownButton<CumulativeFatigueClass>(
          value: _cumulativeFatigue,
          isExpanded: true,
          onChanged: (v) {
            if (v != null) _updateSessionState(fatigue: v);
          },
          items: CumulativeFatigueClass.values
              .map((f) => DropdownMenuItem(
                    value: f,
                    child: Text(f.name),
                  ))
              .toList(),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                _sessionState == null
                    ? 'Session state: (no signal)'
                    : 'Session state: ${_sessionState!.consecutiveDrivingDays}d '
                        '· ${_sessionState!.cumulativeFatigue.name}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
            ),
            TextButton(
              onPressed: _sessionState == null
                  ? null
                  : () => setState(() => _sessionState = null),
              child: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Confidence dropdown + confirmation toggle.
        const Text(
            'Confidence (#30; cap-override-with-confirmation pattern)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        DropdownButton<Confidence?>(
          value: _confidence,
          isExpanded: true,
          onChanged: (v) {
            setState(() {
              _confidence = v;
              // Driver-always-drives: clear confirmation when confidence
              // changes away from .high so a stale confirm cannot
              // silently re-attach to a future .high state.
              if (v != Confidence.high) {
                _isHighConfidenceConfirmed = false;
              }
            });
          },
          items: const <DropdownMenuItem<Confidence?>>[
            DropdownMenuItem(
              value: null,
              child: Text('(no signal — no cap modification)'),
            ),
            DropdownMenuItem(
              value: Confidence.low,
              child: Text('low (auto-tighten cap)'),
            ),
            DropdownMenuItem(
              value: Confidence.medium,
              child: Text('medium (no cap modification)'),
            ),
            DropdownMenuItem(
              value: Confidence.high,
              child: Text('high (requires confirmation to loosen)'),
            ),
          ],
        ),
        if (_confidence == Confidence.high)
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'High-confidence confirmation',
              style: TextStyle(fontSize: 12),
            ),
            subtitle: Text(
              _isHighConfidenceConfirmed
                  ? 'Driver has confirmed high-confidence; cap MAY loosen.'
                  : 'Driver has NOT confirmed; treated as medium (no-op).',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
            value: _isHighConfidenceConfirmed,
            onChanged: (v) =>
                setState(() => _isHighConfidenceConfirmed = v),
          ),
        const SizedBox(height: 4),
        Text(
          'All inputs are advisory; the package never auto-actuates the '
          'vehicle (driver-always-drives invariant). Magnitudes are '
          'design-default-hypotheses pending field validation '
          '(KNOWN_LIMITATIONS.md DriverState-scaffolding section, 0.10.0).',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
        ),
      ],
    );
  }

  void _updateSessionState({
    int? days,
    CumulativeFatigueClass? fatigue,
  }) {
    setState(() {
      if (days != null) _consecutiveDrivingDays = days;
      if (fatigue != null) _cumulativeFatigue = fatigue;
      _sessionState = SessionState(
        consecutiveDrivingDays: _consecutiveDrivingDays,
        cumulativeFatigue: _cumulativeFatigue,
      );
    });
  }

  // ===== Sub-bundle 3 — Glance budget + voice pace + alert expandable =====

  Widget _glanceBudgetPanel() {
    final consumed = _glanceBudget.consumed;
    final remaining = _glanceBudget.remainingBudget;
    final total = _glanceBudget.totalBudget;
    final remainingRatio = total.inMicroseconds == 0
        ? 0.0
        : remaining.inMicroseconds / total.inMicroseconds;
    // Compute effective voice pace at the current ratio per the
    // budgetAwarePace profile (caution-add-only; pace ≤ 1.0×).
    final pace = _voiceConfig.budgetAwarePace
            ?.paceForRemainingRatio(remainingRatio) ??
        1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'NHTSA Phase 2 — 12-second total off-road glance budget per task. '
          'Tap "Simulate glance" to record an 800ms visual glance event '
          'against the budget; budget warning fires at 75% consumed; '
          'exhausted fires at 100%. Voice-pace is dynamically interpolated '
          'between minPace=0.7× and maxPace=1.0× based on remaining ratio.',
          style: TextStyle(fontSize: 11),
        ),
        const SizedBox(height: 6),
        _kv('Total budget',
            '${(total.inMilliseconds / 1000).toStringAsFixed(1)} s'),
        _kv('Consumed',
            '${(consumed.inMilliseconds / 1000).toStringAsFixed(1)} s '
                '($_glanceEventsRecorded events)'),
        _kv('Remaining',
            '${(remaining.inMilliseconds / 1000).toStringAsFixed(1)} s '
                '(${(remainingRatio * 100).toStringAsFixed(0)}%)'),
        _kv('Last event', _formatGlanceEvent(_lastGlanceEvent)),
        _kv('Effective voice pace', '${pace.toStringAsFixed(2)}× baseline'),
        const SizedBox(height: 8),
        // Wrap, not Row: same phone-width overflow class as the blackout
        // button (probe-caught) — two natural-size buttons cannot both be
        // honored at 393 logical under wide font metrics.
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ElevatedButton(
              onPressed: _simulateGlanceEvent,
              child: const Text('Simulate glance (800 ms)'),
            ),
            TextButton(
              onPressed: _resetGlanceBudget,
              child: const Text('Reset trip'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // AlertExplainerExpandableSheet — per-cohort default expansion.
        AlertExplainerExpandableSheet(
          condition: _condition,
          profile: _profile,
        ),
        const SizedBox(height: 4),
        Text(
          'Source: navigation_safety GlanceBudgetTracker + '
          'AlertExplainerExpandableSheet; voice_guidance '
          'BudgetAwarePaceProfile. All advisory; driver-always-drives.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
        ),
      ],
    );
  }

  String _formatGlanceEvent(GlanceBudgetEvent? event) {
    if (event == null) return '(no event yet)';
    return switch (event) {
      BudgetWarning(:final consumed, :final remaining) =>
        'BudgetWarning · consumed=${consumed.inMilliseconds}ms · '
            'remaining=${remaining.inMilliseconds}ms',
      BudgetExhausted(:final consumed, :final overshoot) =>
        'BudgetExhausted · consumed=${consumed.inMilliseconds}ms · '
            'overshoot=${overshoot.inMilliseconds}ms',
    };
  }

  void _simulateGlanceEvent() {
    _glanceBudget.record(GlanceEvent(
      timestamp: DateTime.now(),
      duration: const Duration(milliseconds: 800),
      modalClass: GlanceModalClass.visual,
    ));
    setState(() => _glanceEventsRecorded += 1);
  }

  void _resetGlanceBudget() {
    _glanceBudget.reset(BudgetResetReason.tripStart);
    setState(() {
      _glanceEventsRecorded = 0;
      _lastGlanceEvent = null;
    });
  }

  // ===== Sub-bundle 4 — Render budget viewport panel =====

  Widget _renderBudgetPanel() {
    final perf = _perfBudget;
    final data = _dataBudget;
    final bloc = _viewportBloc;
    if (perf == null || data == null || bloc == null) {
      return const Text('(initializing render-budget trio…)');
    }
    final perfSnap = perf.budgetSnapshot;
    final dataSnap = data.budgetSnapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'PerformanceBudget per-frame budget = '
          '${perf.config.frameBudget.inMicroseconds / 1000} ms '
          '(per-cohort lenient-direction default). '
          'DataBudget per-cycle budget = '
          '${(data.config.budgetBytes / (1024 * 1024)).toStringAsFixed(1)} '
          'MB (per-cohort tighter-direction default). '
          'ViewportRenderBudgetBloc composes both into a RenderFidelity '
          'recommendation; per-cohort floor prevents drop below cohort '
          'minimum.',
          style: const TextStyle(fontSize: 11),
        ),
        const SizedBox(height: 6),
        _kv('Last frame total',
            '${perfSnap.consumed.inMicroseconds} µs '
                '($_framesRecorded recorded)'),
        _kv('Frame remaining',
            '${perfSnap.remaining.inMicroseconds} µs'),
        _kv('Data consumed',
            '${dataSnap.consumedBytes} B '
                '($_fetchesRecorded fetches)'),
        _kv('Data remaining', '${dataSnap.remainingBytes} B'),
        _kv('Floor (per-cohort)', bloc.config.floor.name),
        const SizedBox(height: 6),
        BlocBuilder<ViewportRenderBudgetBloc, ViewportRenderState>(
          bloc: bloc,
          builder: (context, state) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _kv('RenderFidelity',
                    _renderFidelityLabel(state.fidelity)),
                _kv('Perf warning seen',
                    state.performanceWarningSeen.toString()),
                _kv('Perf exhausted seen',
                    state.performanceExhaustedSeen.toString()),
                _kv('Data warning seen',
                    state.dataWarningSeen.toString()),
                _kv('Data exhausted seen',
                    state.dataExhaustedSeen.toString()),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ElevatedButton(
              onPressed: () => _simulateFrame(overBudget: false),
              child: const Text('Frame (in budget)'),
            ),
            ElevatedButton(
              onPressed: () => _simulateFrame(overBudget: true),
              child: const Text('Frame (over budget)'),
            ),
            ElevatedButton(
              onPressed: () => _simulateDataFetch(bytes: 524288),
              child: const Text('Fetch 512 KB'),
            ),
            ElevatedButton(
              onPressed: () => _simulateDataFetch(bytes: 4 * 1024 * 1024),
              child: const Text('Fetch 4 MB (exhaust)'),
            ),
            TextButton(
              onPressed: _resetViewportCycle,
              child: const Text('Reset cycle'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Caution-add-direction-wins: any Exhausted → fidelity drops to '
          'low (clamped by per-cohort floor); any Warning → medium; both '
          'normal → high. Bloc never auto-raises fidelity post-drop — '
          'caution-add-only invariant. Source: offline_tiles / '
          'snow_rendering / map_viewport_bloc (resolved versions: pubspec.lock).',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
        ),
      ],
    );
  }

  String _renderFidelityLabel(RenderFidelity f) {
    switch (f) {
      case RenderFidelity.high:
        return 'high (all layers full quality)';
      case RenderFidelity.medium:
        return 'medium (drop non-essential / soften)';
      case RenderFidelity.low:
        return 'low (safety-critical only)';
    }
  }

  void _simulateFrame({required bool overBudget}) {
    final perf = _perfBudget;
    if (perf == null) return;
    // Synthesize a FrameTiming with totalSpan-equivalent shape.
    // FrameTiming exposes only build/raster timestamps; we use the
    // tracker's record(timing) entry which reads timing.totalSpan.
    // Build a synthetic FrameTiming that covers a target duration via
    // timestamp deltas.
    final budget = perf.config.frameBudget.inMicroseconds;
    final totalMicros = overBudget ? budget * 2 : budget ~/ 2;
    final timing = _syntheticFrameTiming(totalMicros);
    perf.record(timing);
    setState(() => _framesRecorded += 1);
  }

  void _simulateDataFetch({required int bytes}) {
    final data = _dataBudget;
    if (data == null) return;
    data.record(snow_rendering.DataFetchEvent(
      timestamp: DateTime.now(),
      bytesFetched: bytes,
    ));
    setState(() => _fetchesRecorded += 1);
  }

  void _resetViewportCycle() {
    final perf = _perfBudget;
    final data = _dataBudget;
    final bloc = _viewportBloc;
    if (perf == null || data == null || bloc == null) return;
    perf.reset(offline_tiles.BudgetResetReason.renderCycleStart);
    data.reset(snow_rendering.BudgetResetReason.renderCycleStart);
    bloc.add(const ViewportBudgetReset());
    setState(() {
      _framesRecorded = 0;
      _fetchesRecorded = 0;
    });
  }
}

/// Build a synthetic FrameTiming covering a target totalSpan in
/// microseconds. Used by sub-bundle 4 simulation buttons; the
/// PerformanceBudget tracker reads `timing.totalSpan` per its public
/// API contract. We construct a FrameTiming whose timestamps span the
/// target duration so totalSpan equals the target.
FrameTiming _syntheticFrameTiming(int totalMicros) {
  // FrameTiming.totalSpan = rasterFinish - vsyncStart (per dart:ui).
  // Equal-spacing midpoints satisfy the inner ordering invariants.
  return FrameTiming(
    vsyncStart: 0,
    buildStart: 0,
    buildFinish: totalMicros ~/ 2,
    rasterStart: totalMicros ~/ 2,
    rasterFinish: totalMicros,
    rasterFinishWallTime: totalMicros,
    frameNumber: 1,
  );
}

class _FireAttempt {
  final int index;
  final int relativeSeconds;
  final bool fired;
  const _FireAttempt({
    required this.index,
    required this.relativeSeconds,
    required this.fired,
  });
}

class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.amber.shade100,
      child: Text(
        AppL10n.of(context).responsibilityBanner,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

/// Post-drive diary entry form (Ring-2, three-month plan §2): two chip
/// questions + two optional text fields. Chip labels come from the enums'
/// own ja/token pairs (services/drive_diary.dart) so the persisted file and
/// the screen can never diverge; en locale shows the stable token.
///
/// Pops with `true` (persisted), `false` (write failed — honest line), or
/// null (cancelled; nothing recorded).
class _DiaryEntryDialog extends StatefulWidget {
  const _DiaryEntryDialog({required this.diary});

  final DriveDiary diary;

  @override
  State<_DiaryEntryDialog> createState() => _DiaryEntryDialogState();
}

class _DiaryEntryDialogState extends State<_DiaryEntryDialog> {
  DiaryRoadCondition _road = DiaryRoadCondition.unknown;
  DiaryAdvisoryExperience _advisory = DiaryAdvisoryExperience.notSure;
  final _areaController = TextEditingController();
  final _noteController = TextEditingController();

  // Re-entry guard: two near-simultaneous taps (save+save or save+cancel)
  // must not record twice nor pop twice (a double pop removes the HomePage
  // route under the dialog — a black screen).
  bool _popped = false;

  @override
  void dispose() {
    _areaController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final ja = l.locale.languageCode == 'ja';
    return AlertDialog(
      title: Text(l.diaryWriteButton),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.diaryRoadQuestion,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final c in DiaryRoadCondition.values)
                  ChoiceChip(
                    key: Key('diary-road-${c.token}'),
                    label: Text(ja ? c.ja : c.token),
                    selected: _road == c,
                    onSelected: (_) => setState(() => _road = c),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(l.diaryAdvisoryQuestion,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final a in DiaryAdvisoryExperience.values)
                  ChoiceChip(
                    key: Key('diary-advisory-${a.token}'),
                    label: Text(ja ? a.ja : a.token),
                    selected: _advisory == a,
                    onSelected: (_) => setState(() => _advisory = a),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('diary-area-field'),
              controller: _areaController,
              decoration: InputDecoration(
                labelText: l.diaryAreaLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('diary-note-field'),
              controller: _noteController,
              decoration: InputDecoration(
                labelText: l.diaryNoteLabel,
                hintText: l.diaryNoteHint,
                hintMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 4,
              // Bounds one entry well under the diary's rotation half-cap so
              // a single save can never dominate the ring buffer.
              maxLength: 500,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('diary-cancel-button'),
          onPressed: () {
            if (_popped) return;
            _popped = true;
            Navigator.of(context).pop();
          },
          child: Text(l.diaryCancelButton),
        ),
        TextButton(
          key: const Key('diary-save-button'),
          onPressed: () {
            if (_popped) return;
            _popped = true;
            final ok = widget.diary.record(
              road: _road,
              advisory: _advisory,
              area: _areaController.text,
              note: _noteController.text,
            );
            Navigator.of(context).pop(ok);
          },
          child: Text(l.diarySaveButton),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        key: const Key('page-foot'),
        // In her language since 2026-09-15, keeping what she needs: routes do
        // not consider snow, and where routes and weather observations come
        // from. The package names are on the development page.
        AppL10n.of(context).pageFoot(appVersion),
        // shade600 measured 4.39:1 on the page ground (2026-09-15); 5.90:1 now.
        style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Side-by-side threshold preview surfacing baseline vs with-vehicle
/// configs from `NavigationSafetyConfig.forProfileWithContext`.
///
/// Renders the warning visibility floor and warning temperature floor
/// with delta annotations when the selected vehicle-class token has a
/// registered override (e.g. `'kei-car'` → +50m / +1°C). Tokens with no
/// registered override produce identical with-vehicle and baseline
/// rows, demonstrating the no-op fallback semantics of
/// `applyOverrideForToken`.
///
/// AAA Article 17 (β) discipline: kei-car deltas are reported verbatim
/// from NSC 0.9.0 CHANGELOG; the design-default-hypothesis flag is
/// preserved verbatim in the provenance footer.
class _ThresholdPreview extends StatelessWidget {
  final DriverProfile profile;
  final String? vehicleClassToken;
  final VehicleThresholdOverrides vehicleOverrides;
  // Sub-bundle 2 — DriverState-axis scaffolding inputs (NSC 0.10.0).
  // All four are advisory; null falls back to baseline+vehicle layer.
  final CircadianPhase? circadianPhase;
  final SessionState? sessionState;
  final Confidence? confidence;
  final bool isHighConfidenceConfirmed;
  final Widget Function(String, String) kvBuilder;

  const _ThresholdPreview({
    required this.profile,
    required this.vehicleClassToken,
    required this.vehicleOverrides,
    required this.circadianPhase,
    required this.sessionState,
    required this.confidence,
    required this.isHighConfidenceConfirmed,
    required this.kvBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final baseline = NavigationSafetyConfig.forProfileWithContext(profile);
    final withVehicle = NavigationSafetyConfig.forProfileWithContext(
      profile,
      context: DrivingContext(vehicleClassToken: vehicleClassToken),
      vehicleOverrides: vehicleOverrides,
    );
    // Sub-bundle 2: compose baseline + vehicle + driver-state via
    // forDriverContext. DriverState.alert is the conservative default
    // (no state-axis adjustment) when the integrator has no live-state
    // signal; the per-input null-safety handling lives in the factory.
    final withDriverState = NavigationSafetyConfig.forDriverContext(
      DriverContext(profile: profile, state: DriverState.alert),
      environmentalContext: DrivingContext(vehicleClassToken: vehicleClassToken),
      vehicleOverrides: vehicleOverrides,
      circadianPhase: circadianPhase,
      sessionState: sessionState,
      confidence: confidence,
      isHighConfidenceConfirmed: isHighConfidenceConfirmed,
    );

    final visibilityDelta =
        withVehicle.warningVisibilityMeters - baseline.warningVisibilityMeters;
    final temperatureDelta = withVehicle.warningTemperatureCelsius -
        baseline.warningTemperatureCelsius;
    // Sub-bundle 2 driver-state row: delta vs baseline+vehicle.
    final driverStateVisibilityDelta = withDriverState.warningVisibilityMeters -
        withVehicle.warningVisibilityMeters;
    final driverStateCapDelta =
        (withDriverState.alertsPerMinuteCapOverride ?? 0) -
            (withVehicle.alertsPerMinuteCapOverride ?? 0);

    String formatVisibility(int meters, int delta) {
      if (delta == 0) return '$meters m';
      final sign = delta > 0 ? '+' : '';
      return '$meters m ($sign$delta)';
    }

    String formatTemperature(int celsius, int delta) {
      if (delta == 0) return '$celsius °C';
      final sign = delta > 0 ? '+' : '';
      return '$celsius °C ($sign$delta)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        kvBuilder(
          'Baseline warning visibility',
          '${baseline.warningVisibilityMeters} m',
        ),
        kvBuilder(
          'With-vehicle warning visibility',
          formatVisibility(
            withVehicle.warningVisibilityMeters,
            visibilityDelta,
          ),
        ),
        kvBuilder(
          '+ driver-state warning visibility',
          formatVisibility(
            withDriverState.warningVisibilityMeters,
            driverStateVisibilityDelta,
          ),
        ),
        kvBuilder(
          'Baseline warning temperature',
          '${baseline.warningTemperatureCelsius} °C',
        ),
        kvBuilder(
          'With-vehicle warning temperature',
          formatTemperature(
            withVehicle.warningTemperatureCelsius,
            temperatureDelta,
          ),
        ),
        kvBuilder(
          '+ driver-state alerts/min cap',
          withDriverState.alertsPerMinuteCapOverride == null
              ? '(no override)'
              : '${withDriverState.alertsPerMinuteCapOverride!.toStringAsFixed(1)} '
                  '${driverStateCapDelta == 0 ? "" : "(${driverStateCapDelta > 0 ? "+" : ""}${driverStateCapDelta.toStringAsFixed(1)})"}',
        ),
        const SizedBox(height: 4),
        Text(
          'Source: navigation_safety_core — '
          'forDriverContext composes baseline + vehicle + circadian-phase '
          '+ session-state + confidence (cap-override-with-confirmation '
          'pattern). All deltas are caution-add-only per package '
          'invariants. Magnitudes are design-default-hypotheses pending '
          'field validation per KNOWN_LIMITATIONS.md.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
        ),
      ],
    );
  }
}
