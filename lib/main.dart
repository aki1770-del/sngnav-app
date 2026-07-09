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
    show AdvisoryLevel, DriveAction;
import 'package:condition_aggregator/condition_aggregator.dart'
    show AdvisoryAggregateResult, AdvisorySeverity;
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
    show OsrmRoutingEngine, RouteManeuver, RouteRequest, RoutingException;
import 'package:offline_tiles/offline_tiles.dart' as offline_tiles;
import 'package:snow_rendering/snow_rendering.dart' as snow_rendering;
import 'package:voice_guidance/voice_guidance.dart'
    show BudgetAwarePaceProfile, VoiceGuidanceConfig;

import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:latlong2/latlong.dart';

import 'actuators/alert_actuators.dart';
import 'actuators/alert_announcer.dart';
import 'actuators/mobile_alert_actuators.dart';
import 'akita_map.dart';
import 'services/offline_basemap.dart';
import 'l10n/app_localizations.dart';
import 'corridor_row.dart';
import 'her_position.dart';
import 'jma_fetch.dart';
import 'route_fetch.dart';
import 'services/advisory_service.dart';
import 'services/drive_hud_controller.dart';
import 'services/error_log.dart';
import 'services/drive_hud_localizer.dart';
import 'services/maneuver_narration.dart';
import 'services/invisible_ice_watch.dart';
import 'services/jma_advisory_provider_factory.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // W2 — crash boundary + local error log (services/error_log.dart): every
  // uncaught error is appended to a size-capped on-device file. NO network,
  // NO telemetry — the log leaves the device only via the future
  // user-initiated ログを共有 action. Never blocks boot (best-effort install).
  await installCrashBoundary();
  runApp(const SngnavApp());
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

class SngnavApp extends StatelessWidget {
  /// [actuators] is injectable so tests (and future device harnesses) can
  /// supply a fake/real actuator layer; production leaves it null and the app
  /// picks [defaultAlertActuators] (mobile -> real, everywhere else -> no-op).
  ///
  /// [locale] overrides the device locale (null = follow the device). It is a
  /// testability + future device-harness hook: the WS7 tests pump the consent
  /// gate under `Locale('ja')` to prove HER surface renders in Japanese.
  const SngnavApp({super.key, this.actuators, this.locale});

  final AlertActuators? actuators;
  final Locale? locale;

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
      home: HomePage(actuators: actuators),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.actuators});

  /// Injectable actuator layer (null -> [defaultAlertActuators]).
  final AlertActuators? actuators;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // V21: ageingRural is the default — HER's mother is the named first customer.
  DriverProfile _profile = DriverProfile.ageingRural;

  // Mocked road-surface condition for Slice 0.
  RoadSurfaceCondition _condition = RoadSurfaceCondition.ice;

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
  // Mocked visibility band for the in-drive demo. Metres, or null = "no
  // reading" (a first-class unknown the advisor honours). Defaults to a clear
  // demo value so merely sharing location does not auto-announce; HER real
  // whiteout is what the degraded bands model.
  double? _mockVisibilityMeters = 1500;
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

  // BETA_PLAN W1 — invisible-ice (radiative-frost) watch state over the
  // live JMA observation. _invisibleIceAnnounced is the transition gate.
  InvisibleIceWatchResult? _invisibleIceResult;
  bool _invisibleIceAnnounced = false;

  // Slice 3 — corridor stations along Akita prefecture's inhabited spine.
  List<JmaResult>? _corridorResults;
  bool _corridorLoading = false;

  // Routing state — Slice 2b. Tap A → tap B → fetch → polyline.
  LatLng? _origin;
  LatLng? _destination;
  RouteResult? _routeResult;
  bool _routeLoading = false;

  // (e) honest maneuver narration — the real step list parsed by the
  // ALREADY-BUILT OsrmRoutingEngine pipeline (steps=true), plus the NEXT
  // actionable maneuver surfaced in the drive flow. `_lastManeuverNarration`
  // holds the most recent gated decision (spoken / hedged / suppressed) so the
  // panel can show, honestly, what the announcer did.
  List<RouteManeuver> _routeManeuvers = const [];
  RouteManeuver? _nextManeuver;
  ManeuverNarration? _lastManeuverNarration;

  // HER position — Slice 2c. The passenger sits down quietly.
  PositionFix? _herFix;
  StreamSubscription<PositionFix>? _herSub;

  // Offline-basemap PoC (Chair Option A, 2026-07-01). Loaded once at init from
  // the bundled PLACEHOLDER MBTiles asset, then handed to AkitaMap so the Akita
  // corridor renders OFFLINE-FIRST (network only for uncovered tiles) — the
  // basemap no longer goes fully blank when the network is gone. Null until
  // loaded / on any failure ⇒ plain network basemap (honest degradation). The
  // bundled tiles are HONEST PLACEHOLDERS, not real cartography; real Akita
  // raster coverage is EIE's production.
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
    // a true multi-hour screen-off drive would need a foreground service, and
    // FOREGROUND_SERVICE_LOCATION is declared for a user-visible ongoing-drive
    // notification — never silent background location tracking, which we
    // refuse for dignity, hence NO ACCESS_BACKGROUND_LOCATION.)
    _actuators = widget.actuators ?? defaultAlertActuators();
    _announcer = AlertAnnouncer(actuators: _actuators);
    unawaited(_actuators.keepAwake(true));
    // Offline-basemap PoC — load the bundled placeholder MBTiles archive and
    // hand the resulting OfflineTileProvider to AkitaMap. Async + fail-soft:
    // a null result leaves the basemap on the plain network layer.
    unawaited(_loadOfflineBasemap());
    // WS6 — inject the app's SINGLE actuator + announcer into the drive brain
    // (it never resolves its own — one actuator, one wakelock owner). A rising
    // caution rung fires _announcer.announce (audio + haptic). Listen so the
    // on-screen WS6 panel repaints when the estimate / caution changes.
    _driveHud = DriveHudController(
      actuators: _actuators,
      announcer: _announcer,
      text: _driveHudText,
      localeTag: 'ja',
    );
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
    _advisoryService = AdvisoryService(providers: [
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
    // Close the offline MBTiles archive (sqlite3) + its network provider.
    unawaited(_offlineBaseProvider?.dispose());
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
    super.dispose();
  }

  void _shareLocation() {
    if (_herSub != null) return;
    setState(() {
      _herFix = null;
      _isMockPosition = false;
    });
    _herSub = herPositionStream().listen((fix) {
      if (!mounted) return;
      setState(() => _herFix = fix);
      _maybeRefreshAdvisoriesForFix(fix);
      _feedDriveHud(fix);
    });
  }

  void _useMockPosition() {
    _herSub?.cancel();
    _herSub = null;
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
    _feedDriveHud(mockFix);
  }

  // ===== WS6 — feed the live drive brain + the on-screen caution panel =====

  void _onDriveHudChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// Map the app's real aggregated advisory result to the advisor's mirror
  /// [AdvisoryLevel] — the single MOST-severe active advisory in force, or
  /// `null` when there is none (or only an `unknown`-severity one). The advisor
  /// does NOT aggregate; it consumes the one severity the integrator selects.
  AdvisoryLevel? _topAdvisoryLevel(AdvisoryAggregateResult? result) {
    if (result == null || result.advisories.isEmpty) return null;
    var top = AdvisorySeverity.unknown;
    for (final a in result.advisories) {
      if (a.severity.index > top.index) top = a.severity;
    }
    return switch (top) {
      AdvisorySeverity.unknown => null,
      AdvisorySeverity.minor => AdvisoryLevel.minor,
      AdvisorySeverity.moderate => AdvisoryLevel.moderate,
      AdvisorySeverity.severe => AdvisoryLevel.severe,
      AdvisorySeverity.extreme => AdvisoryLevel.extreme,
    };
  }

  /// Push the app's live environment (real advisory + mocked visibility; speed
  /// is unknown — the fix carries none) onto the drive brain, then feed the
  /// position sample. [DriveHudController.onPositionFix] recomputes the caution
  /// and, if the rung RISES, auto-announces on the single _announcer.
  void _feedDriveHud(PositionFix fix) {
    // Set the environment fields directly (no recompute yet), so onPositionFix
    // does the single recompute+announce with the current environment.
    _driveHud.visibilityMeters = _mockVisibilityMeters;
    _driveHud.visibilityAgeSeconds = _mockVisibilityMeters == null ? null : 0;
    _driveHud.advisorySeverity = _topAdvisoryLevel(_advisoryResult);
    _driveHud.speedMetersPerSecond = null;
    // A fresh trusted fix resets the blackout clock; a PositionUnavailable
    // (denied / revoked / error / non-finite) degrades honestly toward lost.
    if (fix is PositionAvailable) {
      _driveHudBaseTime = fix.timestamp;
      _blackoutSeconds = 0;
    }
    _driveHud.onPositionFix(fix);
  }

  /// Recompute the caution when the mocked visibility band changes (no new
  /// position). [DriveHudController.updateEnvironment] recomputes + re-announces
  /// on a rung rise if an estimate already exists.
  void _onVisibilityChanged(double? meters) {
    setState(() => _mockVisibilityMeters = meters);
    _driveHud.updateEnvironment(
      visibilityMeters: _mockVisibilityMeters,
      visibilityAgeSeconds: _mockVisibilityMeters == null ? null : 0,
      advisorySeverity: _topAdvisoryLevel(_advisoryResult),
      speedMetersPerSecond: null,
    );
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
    _driveHud.poll(now: base.add(Duration(seconds: _blackoutSeconds)));
  }

  // Visibility bands for the mocked in-drive control. metres, or null =
  // "no reading" (a first-class unknown).
  static const List<(String, double?)> _visibilityBands = [
    ('クリア ~1.5 km（demo default）', 1500),
    ('視界低下 ~700 m', 700),
    ('視界不良 ~300 m', 300),
    ('ホワイトアウト ~80 m', 80),
    ('測定なし（不明）', null),
  ];

  Widget _driveHudPanel() {
    final estimate = _driveHud.estimate;
    final advice = _driveHud.advice;
    final hasBaseline = _herFix is PositionAvailable;

    final (Color bannerColor, Color textColor) = switch (advice?.action) {
      DriveAction.considerStopping => (Colors.red.shade100, Colors.red.shade900),
      DriveAction.heightenedCaution => (
          Colors.amber.shade100,
          Colors.amber.shade900
        ),
      _ => (Colors.grey.shade200, Colors.grey.shade800),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Fuses HER honest position (localization_fallback: GPS → dead '
          'reckoning → lost, never a confident wrong dot) with visibility + the '
          'real area advisory (compound_failure_advisor). The MOMENT the caution '
          'rung RISES it auto-announces on the SAME audio + haptic channel as '
          'WS5 — no manual button. Share a location above, then lower the '
          'visibility band and/or simulate a GPS blackout to see it rise.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        ),
        const SizedBox(height: 10),
        // Mocked visibility band (no real sensor yet — honest).
        const Text('Mocked visibility band (no visibility sensor yet)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        DropdownButton<double?>(
          key: const Key('drive-hud-visibility'),
          value: _mockVisibilityMeters,
          isExpanded: true,
          onChanged: _onVisibilityChanged,
          items: [
            for (final (label, meters) in _visibilityBands)
              DropdownMenuItem<double?>(value: meters, child: Text(label)),
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
              label: const Text('Simulate GPS blackout (+60 s)'),
            ),
            if (_blackoutSeconds > 0)
              Text('blackout: ${_blackoutSeconds}s',
                  style: TextStyle(
                      fontSize: 12, color: Colors.orange.shade900)),
          ],
        ),
        if (!hasBaseline)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Share a location (Akita mock or GPS) above to start the drive '
              'brain.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
            ),
          ),
        const SizedBox(height: 12),
        if (estimate == null || advice == null)
          Text('(no position fed yet)',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12))
        else ...[
          // The honest position line.
          _kv('現在地の信頼度',
              _driveHudText.modeLabel(estimate.mode, 'ja')),
          _kv('誤差',
              _driveHudText.radiusLabel(estimate.confidenceRadiusMeters, 'ja')),
          const SizedBox(height: 8),
          // The caution headline banner (JA), coloured by rung.
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
                  _driveHudText.actionHeadline(advice.action, 'ja'),
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (advice.action != DriveAction.continueDriving) ...[
                  const SizedBox(height: 4),
                  Text(
                    _driveHudText.spokenGuidance(advice.action, 'ja'),
                    style: TextStyle(color: textColor, fontSize: 14),
                  ),
                ],
                if (advice.compounding) ...[
                  const SizedBox(height: 6),
                  Text(
                    '⚠ 危険が重なっています（現在地不確か＋視界不良）',
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
              '理由',
              [for (final r in advice.reasons) _driveHudText.reasonLabel(r, 'ja')]
                  .join(' · '),
            ),
          if (advice.unknowns.isNotEmpty)
            _kv(
              '不明な点',
              [
                for (final u in advice.unknowns)
                  _driveHudText.unknownLabel(u, 'ja')
              ].join(' · '),
            ),
          if (advice.sightStoppingSpeedHintMps != null)
            _kv(
              '目安速度',
              _driveHudText.sightHintLabel(
                  advice.sightStoppingSpeedHintMps!, 'ja'),
            ),
          const SizedBox(height: 8),
          // Announce status — honest reach bounds.
          Text(
            switch (advice.action) {
              DriveAction.considerStopping =>
                'Auto-fires audio + haptic (critical) on rung rise. '
                    'On-device HEAR/FEEL not verified in this env.',
              DriveAction.heightenedCaution =>
                'Auto-fires audio + haptic (warning) on rung rise. '
                    'On-device HEAR/FEEL not verified in this env.',
              DriveAction.continueDriving =>
                'Continue — nothing announced (parity with the voice gate).',
            },
            style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          'Position is REAL (HER GPS, honestly degraded); area advisory is REAL '
          '(NWS + JMA); visibility is MOCKED (no sensor yet); speed is unknown. '
          'Advisory-only, driver-always-drives; the ceiling is "consider '
          'stopping", never "turn back". Source: localization_fallback 0.1.1 + '
          'compound_failure_advisor 0.1.1 (pub.dev).',
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
      final result = await _advisoryService.fetchAtPoint(
        latitude: latitude,
        longitude: longitude,
      );
      if (!mounted) return;
      setState(() {
        _advisoryResult = result;
        _advisoryLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _advisoryErrorMessage = e.toString();
        _advisoryLoading = false;
      });
    }
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
    _herSub?.cancel();
    _herSub = null;
    setState(() {
      _herFix = null;
      _isMockPosition = false;
    });
  }

  Future<void> _refreshJma() async {
    setState(() => _jmaLoading = true);
    final result = await fetchLatestObservation();
    if (!mounted) return;
    setState(() {
      _jmaResult = result;
      _jmaLoading = false;
      if (result is JmaSuccess) {
        _invisibleIceResult = evaluateInvisibleIceWatch(result.observation);
      } else {
        _invisibleIceResult = InvisibleIceWatchResult.unknown;
      }
    });
    _announceInvisibleIceTransition();
  }

  /// BETA_PLAN W1 — the invisible-ice (radiative-frost) watch over the
  /// live JMA observation. Transition-gated: announces ONCE when the
  /// measured window turns on (clear/unknown → watch), never repeats on
  /// every fetch while the window persists (the cry-wolf discipline the
  /// SNGNav status bar uses). Spoken text is the catalog's
  /// possibility-graded looks-wet line, VERBATIM (AAA Article 17 β —
  /// the app does not paraphrase catalog strings); warning tier, not
  /// critical, because the detection is a dew-point inference, not a
  /// surface measurement.
  void _announceInvisibleIceTransition() {
    final fired = _invisibleIceResult == InvisibleIceWatchResult.watch;
    if (fired && !_invisibleIceAnnounced) {
      unawaited(
        _announcer.announce(
          severity: AlertSeverity.warning,
          text: invisibleBlackIceAnnouncement.jaSpokenText,
          localeTag: 'ja-JP',
        ),
      );
    }
    _invisibleIceAnnounced = fired;
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

  void _handleMapTap(LatLng point) {
    if (_origin == null) {
      setState(() {
        _origin = point;
        _destination = null;
        _routeResult = null;
        _clearManeuverState();
      });
      return;
    }
    if (_destination == null) {
      setState(() => _destination = point);
      _fetchRoute();
      return;
    }
    // Both set — start over with this tap as new origin.
    setState(() {
      _origin = point;
      _destination = null;
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

  /// Clear the parsed maneuver list + next maneuver + last narration decision.
  /// Called inside a `setState` when the route is reset/replaced.
  void _clearManeuverState() {
    _routeManeuvers = const [];
    _nextManeuver = null;
    _lastManeuverNarration = null;
  }

  Future<void> _fetchRoute() async {
    final o = _origin;
    final d = _destination;
    if (o == null || d == null) return;
    setState(() => _routeLoading = true);

    // Route via the ALREADY-BUILT OsrmRoutingEngine maneuver pipeline: it
    // requests `steps=true` and parses the real maneuver list. ONE fetch yields
    // BOTH the polyline (for the map, via `result.shape`) and the honest
    // maneuver list (for (e) narration). We keep the app's own `RouteSuccess`
    // shape so the existing map + forecast wiring is untouched. No new feature
    // is added to routing_engine — it stays in maintenance-mode; this is pure
    // app-layer wiring to its existing surface.
    final engine = OsrmRoutingEngine(baseUrl: _osrmDemoBaseUrl);
    RouteResult result;
    var maneuvers = const <RouteManeuver>[];
    try {
      final r = await engine.calculateRoute(
        RouteRequest(origin: o, destination: d, language: 'ja-JP'),
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
      _routeManeuvers = maneuvers;
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
    final cap = AlertDensityThrottle.defaultCapFor(_profile);
    final glossary = RoadSurfaceConditionGlossary.forConditionAndProfile(
      _condition,
      _profile,
    );
    // Action-coupled explainer for current (condition, profile) tuple.
    // Action string is rendered VERBATIM per AAA Article 17 (β) — the
    // package owns the wording (advisory mood, JAF/MLIT vocabulary,
    // per-profile verbosity). The app must not paraphrase or restyle.
    final explainer = AlertExplainer.forConditionAndProfile(
      _condition,
      _profile,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('sngnav-app (alpha)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Banner(),
            const SizedBox(height: 16),
            _section(
              title: 'Driver profile',
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
              title: 'Mocked road condition',
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
              title: 'Vehicle class (HER cohort: kei-car-at-65 default)',
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
              title: 'Driver state inputs (NSC 0.10.0 — #28 / #29 / #30)',
              child: _driverStateInputs(),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Threshold preview '
                  '(profile × vehicle × driver-state)',
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
              title: 'Glossary (per profile)',
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
              title: 'Action-coupled explainer (current condition × profile)',
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
                    'Source: navigation_safety_core AlertExplainer — verbatim '
                    'relay from JAF / MLIT / NEXCO public driver-guidance.',
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
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Live drive — compound-failure caution (WS6, auto)',
              child: _driveHudPanel(),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Alert density throttle',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _kv('Per-profile cap', '${cap.toStringAsFixed(1)} alerts/min'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _fireAlertSequence,
                    child: const Text('Fire 8 sequential warning alerts'),
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
                                '${a.fired ? "FIRED" : "throttled"}',
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
              title: 'LoomFit telemetry — developer / calibration trace',
              child: _loomFitTelemetryPanel(),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Glance budget + voice pace + alert expandable '
                  '(navigation_safety / voice_guidance)',
              child: _glanceBudgetPanel(),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Render budget viewport '
                  '(offline_tiles / snow_rendering / map_viewport_bloc)',
              child: _renderBudgetPanel(),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Map — Akita-shi (station 32402)',
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
                    onTap: _handleMapTap,
                    herPosition: switch (_herFix) {
                      PositionAvailable(:final latitude, :final longitude) =>
                        LatLng(latitude, longitude),
                      _ => null,
                    },
                    herAccuracyMeters: switch (_herFix) {
                      PositionAvailable(:final accuracyMeters) => accuracyMeters,
                      _ => null,
                    },
                    isHerPositionMock: _isMockPosition,
                  ),
                  const SizedBox(height: 8),
                  _herStatusLine(),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Route — tap A then B (driving, no snow-aware yet)',
              child: _routePanel(),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Next maneuver — honest confidence-gated narration',
              child: _maneuverNarrationPanel(),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'JMA AMeDAS — Akita-shi (station 32402)',
              child: _jmaPanel(),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Corridor weather — Akita prefecture spine',
              child: _corridorPanel(),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Active advisories — NWS + JMA (publisher verbatim)',
              child: AdvisoryCards(
                loading: _advisoryLoading,
                result: _advisoryResult,
                errorMessage: _advisoryErrorMessage,
                onRefresh: _onAdvisoryRefreshTapped,
              ),
            ),
            const SizedBox(height: 16),
            const _Footer(),
          ],
        ),
      ),
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
      return Row(children: [
        const Text('(no fetch yet)'),
        const Spacer(),
        TextButton(onPressed: _refreshJma, child: const Text('Fetch')),
      ]);
    }
    switch (result) {
      case JmaSuccess(:final observation):
        final stale = observation.minutesStale(DateTime.now());
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _kv('Station', '${observation.stationName} (${observation.stationId})'),
            _kv('Observed at', obsDisplay),
            _kv('Temperature', temp == null ? '—' : '${temp.toStringAsFixed(1)} °C'),
            _kv('Humidity', hum == null ? '—' : '$hum %'),
            _kv('Wind', wind == null ? '—' : '${wind.toStringAsFixed(1)} m/s'),
            _kv('Snow depth', snow == null ? '—' : '${snow.toStringAsFixed(0)} cm'),
            _kv('Fetched', _formatFetched(observation.fetchedAt, stale)),
            // BETA_PLAN W1 — the invisible-ice watch verdict, rendered with
            // the same honest-unknown discipline as the fields above.
            _kv(
              '路面凍結ウォッチ',
              switch (_invisibleIceResult) {
                InvisibleIceWatchResult.watch =>
                  '⚠ ブラックアイスバーンのおそれ（放射冷却の窓）',
                InvisibleIceWatchResult.clear => '該当なし',
                InvisibleIceWatchResult.unknown || null =>
                  '判定不能（気温・湿度・降水の観測値が不足）',
              },
            ),
            const SizedBox(height: 8),
            // Honesty split (CT Joel-Test catch, 2026-07-09 vision audit):
            // the observation fields above are verbatim relay; the watch row
            // is NOT — it is a derived classification. One caption claiming
            // "no derivation" under both was a false claim on the safety
            // surface.
            Text(
              'Source: JMA AMeDAS — observation fields are verbatim relay. '
              '路面凍結ウォッチ is DERIVED from them (shared radiative-frost '
              'classifier) — an inference, not a JMA statement.',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _refreshJma,
                child: const Text('Re-fetch'),
              ),
            ),
          ],
        );
      case JmaFailure(:final reason):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.red.shade50,
              child: Text(
                'JMA fetch failed: $reason',
                style: TextStyle(color: Colors.red.shade900),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Cached data is NOT shown — staleness must be visible. Try again or '
              'check connectivity.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _refreshJma,
                child: const Text('Retry'),
              ),
            ),
          ],
        );
    }
  }

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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
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
                TextButton(
                  key: const Key('use-mock-button'),
                  onPressed: _useMockPosition,
                  child: Text(l.useAkitaMock),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            key: const Key('location-disclosure'),
            l.locationDisclosure,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      );
    }
    // Mock-mode active.
    if (_isMockPosition) {
      final acc = switch (_herFix) {
        PositionAvailable(:final accuracyMeters) =>
          accuracyMeters.toStringAsFixed(0),
        _ => '35',
      };
      return Row(
        children: [
          Expanded(
            child: Text(
              l.mockPositionStatus(acc),
              style: TextStyle(
                fontSize: 12,
                color: Colors.amber.shade900,
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
    final (text, color) = switch (fix) {
      null => (
        l.locatingYou,
        Colors.grey.shade600,
      ),
      PositionAvailable(:final accuracyMeters) => (
        l.youAreHere(accuracyMeters.toStringAsFixed(0)),
        Colors.blueGrey.shade700,
      ),
      PositionUnavailable(:final reason) => (
        l.gpsUnavailable(reason),
        Colors.grey.shade700,
      ),
    };
    return Row(
      children: [
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12, color: color)),
        ),
        TextButton(
          onPressed: _clearPosition,
          child: Text(l.stop),
        ),
      ],
    );
  }

  Widget _routePanel() {
    final hint = switch ((_origin, _destination)) {
      (null, _) => 'Tap the map to set point A (origin).',
      (_, null) => 'Tap again to set point B (destination).',
      _ => 'A and B set. Tap anywhere to start over.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(hint, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _kv('Distance', '${(distanceMeters / 1000).toStringAsFixed(1)} km'),
                  _kv('Duration', _formatDuration(durationSeconds)),
                  const SizedBox(height: 4),
                  Text(
                    'Source: OSRM public demo (router.project-osrm.org). '
                    'NOT snow-aware. NOT for production navigation.',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ],
              ),
            RouteFailure(:final reason) => Container(
                padding: const EdgeInsets.all(8),
                color: Colors.red.shade50,
                child: Text(
                  'Route fetch failed: $reason',
                  style: TextStyle(color: Colors.red.shade900),
                ),
              ),
          },
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _origin == null ? null : _resetRoute,
            child: const Text('Reset'),
          ),
        ),
      ],
    );
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).round();
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return '${h}h ${m}m';
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
        _routeResult is RouteSuccess
            ? 'No turn-by-turn maneuvers in this route.'
            : 'Tap A then B above to fetch a route; the next maneuver appears '
                'here, narrated only when the position is trustworthy.',
        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
      );
    }

    final mode = _driveHud.estimate?.mode;
    final icy = _maneuverCoincidesWithHazard();
    final preview = _driveHud.previewNextManeuver(next, icyTurn: icy);

    final (Color bg, Color fg, String tier) = switch (preview.confidence) {
      NarrationConfidence.speak => (
          Colors.green.shade100,
          Colors.green.shade900,
          'SPEAK — GPS trusted',
        ),
      NarrationConfidence.hedge => (
          Colors.amber.shade100,
          Colors.amber.shade900,
          'HEDGE — GPS suspect',
        ),
      NarrationConfidence.suppressed => (
          Colors.blueGrey.shade100,
          Colors.blueGrey.shade900,
          'SUPPRESSED — position not trusted',
        ),
    };

    // When suppressed there is NO maneuver phrase to show (the decision carries
    // empty text by construction) — show the honest "guidance paused" line, not
    // a turn.
    final herLine = preview.confidence == NarrationConfidence.suppressed
        ? 'この曲がり角の案内は保留しています（現在地が信頼できません）。'
        : preview.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'The NEXT maneuver (parsed by OsrmRoutingEngine, steps=true), narrated '
          'ONLY when the honest position allows it. A turn is never spoken '
          'against a drifting or lost dot — the confidently-wrong instruction '
          'this gate refuses. Simulate a GPS blackout in the drive panel above '
          'to watch SPEAK → SUPPRESS.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        ),
        const SizedBox(height: 8),
        if (mode != null)
          _kv('現在地の信頼度', _driveHudText.modeLabel(mode, 'ja')),
        _kv('Maneuvers parsed', '${_routeManeuvers.length} '
            '(next: ${next.index + 1})'),
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
                  '❄ icy-turn advisory coupled',
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
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
              label: const Text('Narrate next maneuver (gated)'),
            ),
            const SizedBox(width: 8),
            if (_lastManeuverNarration != null)
              Expanded(
                child: Text(
                  _lastManeuverNarration!.shouldAnnounce
                      ? 'Announced (${_lastManeuverNarration!.confidence.name}) '
                          '— audio + haptic.'
                      : 'Suppressed — nothing announced (honest silence).',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Turn-trigger TIMING and whether HER HEARS the line are device-'
          'observable and NOT verified in this env (no device). Not a '
          '"guidance works" claim.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
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
      return Row(children: [
        const Text('(no fetch yet)'),
        const Spacer(),
        TextButton(onPressed: _refreshCorridor, child: const Text('Fetch')),
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
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              SizedBox(
                width: corridorStationColumnWidth,
                child: Text('Station',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: Text('Snow',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: Text('Temp',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: Text('Wind',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              SizedBox(
                width: corridorObservedColumnWidth,
                child: Text('Observed',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
          'Source: JMA AMeDAS — verbatim relay per station, no derivation. '
          'Geographic aggregation only (op-(e) per AAA Article 17 (β)).',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _refreshCorridor,
            child: const Text('Re-fetch all'),
          ),
        ),
      ],
    );
  }

  String _formatFetched(DateTime fetchedAt, int minutesStale) {
    final fmt = DateFormat('HH:mm');
    return '${fmt.format(fetchedAt)} ($minutesStale min ago)';
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
        Row(
          children: [
            ElevatedButton(
              onPressed: _simulateGlanceEvent,
              child: const Text('Simulate glance (800 ms)'),
            ),
            const SizedBox(width: 8),
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
      child: const Text(
        'Alpha software. Not for production navigation. The driver remains '
        'responsible for all driving decisions. This app surfaces information; '
        'it does not control the vehicle.',
        style: TextStyle(fontSize: 12),
      ),
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
        'sngnav-app $appVersion. '
        'Built on the SNGNav package family from pub.dev '
        '(navigation_safety_core, navigation_safety, voice_guidance, '
        'driving_conditions, offline_tiles, snow_rendering, '
        'map_viewport_bloc — resolved versions in pubspec.lock). '
        'Akita station chosen because HER\'s mother lives there (V21). '
        'GPS shows position with honest accuracy; mock dot is amber (dev). '
        'Routing via OSRM public demo (NOT snow-aware yet). '
        'Corridor weather = 5-station JMA verbatim (op-(e) aggregation only).',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
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
