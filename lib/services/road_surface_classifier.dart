/// Slice 5a — road surface classification from current weather.
///
/// Wraps `RoadSurfaceState.fromCondition` (re-exported by
/// `driving_conditions` from `snow_rendering`) plus a
/// `HysteresisFilter<RoadSurfaceState>` so the surface state does not
/// oscillate at temperature / intensity boundaries.
///
/// Driver-facing loom: "the driver does not see the surface state flip
/// twice per second when the temperature crosses 0 °C — the hysteresis
/// filter holds the state for a debounce window before flipping."
///
/// Severity-not-profile invariant (Slice 4 anchor): the classifier
/// produces severity-class output (RoadSurfaceState + grip factor); the
/// downstream `AlertSurfaceController` decides per-profile rendering.
///
/// ## Absence is not a determination (snow_rendering 0.3.0 safety recall)
///
/// `snow_rendering` 0.3.0 is a SAFETY RECALL. In the package's own words:
///
/// > Up to and including 0.2.7, this package told drivers "Conditions normal"
/// > about roads it had no data for.
///
/// The chain was `no data -> RoadSurfaceState.dry -> gripFactor 1.0 (MAXIMUM
/// GRIP) -> RecommendedResponse.proceed -> "Conditions normal"`. 0.3.0 fixes it
/// in the type system: `fromCondition` returns `RoadSurfaceState?`, and `null`
/// means "cannot classify" — never `dry`.
///
/// **This app cannot take that fix today.** Measured 2026-08-06 against the
/// live pub.dev API, three PUBLISHED siblings cap us below the recall
/// (`driving_conditions` 0.5.5 -> `snow_rendering ^0.2.1`; that package plus
/// `adaptive_reroute` 0.1.6 and `route_condition_forecast` 0.1.5 all -> the
/// `driving_weather ^0.4.0` that `snow_rendering` 0.3.0 leaves behind). The
/// exact caps and the catalog-side republish they need are recorded in
/// `pubspec.yaml`. Forcing the constraint past the resolver is forbidden
/// (AAE-3); so the guarantee is enforced HERE instead — which is exactly what
/// `snow_rendering` 0.2.9's own dartdoc instructs, verbatim:
///
/// > Never call this with fields you did not measure; gate absence at your call
/// > site and tell your user "unknown".
///
/// So [classify] returns a NULLABLE state. `null` is "cannot judge" — it is
/// **not** an alarm, and it is never `dry`. This shape is deliberately the same
/// one 0.3.0 exposes, so the migration is a constraint change and a re-verify,
/// not a rewrite.
///
/// Two directions of honesty, both load-bearing:
/// - an ABSENCE must never be rendered as a benign determination; and
/// - an absence must never SUPPRESS a hazard a measured field already
///   justifies (caution-add-only). Positive determinations are passed through
///   untouched, and an abstention is never fed to the filter, so it can neither
///   manufacture a state nor erase one.
///
/// A fully MEASURED warm dry road is still `dry`. Turning every warm road into
/// "unknown" would be the cry-wolf inverse and a defect of its own.
///
/// Pure Dart, no Flutter dependency in this file.
library;

import 'package:driving_conditions/driving_conditions.dart'
    show RoadSurfaceState, HysteresisFilter;
import 'package:driving_weather/driving_weather.dart'
    show PrecipitationType, WeatherCondition;

import 'radiative_frost_decline.dart' show radiativeFrostJudgementDeclined;

/// Classifies an incoming `WeatherCondition` into a debounced
/// `RoadSurfaceState`, or abstains when the reading cannot support a
/// determination.
///
/// Construction notes:
/// - The hysteresis filter defaults to window 3, threshold 2 — a new
///   state must be observed in 2 of the last 3 readings before it
///   replaces the current state. Tuning is configurable.
/// - The first reading always sets the state (the filter has no prior
///   to debounce against).
class RoadSurfaceClassifier {
  RoadSurfaceClassifier({
    HysteresisFilter<RoadSurfaceState>? filter,
  }) : _filter = filter ?? HysteresisFilter<RoadSurfaceState>();

  final HysteresisFilter<RoadSurfaceState> _filter;

  bool _lastReadingAbstained = false;

  /// The last debounced surface state the classifier actually DETERMINED.
  ///
  /// `null` until [classify] has produced at least one determination.
  ///
  /// Deliberately NOT cleared by an abstention: a dropped sensor reading must
  /// not erase a hazard that a measured reading already justified. Read it
  /// together with [lastReadingAbstained] — this getter answers "what did we
  /// last judge?", not "what is true right now".
  RoadSurfaceState? get current => _filter.current;

  /// Whether the most recent [classify] call ABSTAINED.
  ///
  /// When true, the newest reading could not support a determination and
  /// [current] is a carried-forward earlier judgement, not a fresh one. A
  /// driver-facing surface should render "判定不能" ("cannot judge") rather
  /// than presenting [current] as the present state.
  bool get lastReadingAbstained => _lastReadingAbstained;

  /// Classify [condition] and return the debounced state, or `null` when the
  /// reading cannot support a determination.
  ///
  /// `null` means "cannot judge". It never means `dry`, and it is never an
  /// alarm. An abstention is NOT fed to the hysteresis filter, so repeated
  /// abstentions can neither debounce toward a fabricated state nor displace a
  /// hazard already determined.
  RoadSurfaceState? classify(WeatherCondition condition) {
    // Typed nullable DELIBERATELY so this line compiles unchanged against BOTH
    // the 0.2.x non-nullable return and the 0.3.x nullable one. The analyzer is
    // right that the annotation is redundant *today* — it is redundant only
    // because we are still pinned below the recall, and it is what stops this
    // becoming a rewrite on the day the catalog cap lifts. The `raw == null`
    // branch below is likewise dead under 0.2.x and live under 0.3.x.
    // ignore: unnecessary_nullable_for_final_variable_declarations
    final RoadSurfaceState? raw = RoadSurfaceState.fromCondition(condition);

    if (raw == null || !_isTrustworthy(raw, condition)) {
      _lastReadingAbstained = true;
      return null;
    }

    _lastReadingAbstained = false;
    return _filter.add(raw);
  }

  /// Reset the filter — useful when leaving a region or restarting a
  /// session.
  void reset() {
    _filter.reset();
    _lastReadingAbstained = false;
  }

  /// Is [raw] a determination this app is willing to stand behind?
  ///
  /// Only ever narrows [RoadSurfaceState.dry] — the one benign state, and the
  /// only one the recall chain can reach from absent data. Every hazard-class
  /// state is positive evidence and passes through untouched, so this can
  /// never suppress a warning.
  static bool _isTrustworthy(RoadSurfaceState raw, WeatherCondition c) {
    if (raw != RoadSurfaceState.dry) return true;

    final temp = c.temperatureCelsius;

    // A non-finite temperature is a REJECTED input, never an all-clear.
    if (!temp.isFinite) return false;

    // At or below freezing, "maximum grip" is not a claim this app makes. Its
    // own invisible-ice watch treats temp <= 0 as frozen UNCONDITIONALLY
    // (`invisible_ice_watch.dart`, the `subZeroFrozen` branch); a `dry` verdict
    // here would have the two surfaces contradicting each other about the same
    // road. `null` says "cannot judge" without crying wolf.
    if (temp <= 0) return false;

    // Above zero with no precipitation, the radiative-frost check is the ONLY
    // hazard discriminator. Without humidity it is a rejected input and never
    // looks — so `dry` is the absence of a determination, not a finding. This
    // mirrors the ice watch's own above-zero guard, which abstains on absent
    // humidity rather than reporting a clear road.
    if (c.precipType == PrecipitationType.none) {
      final rh = c.humidityRH;
      if (rh == null || !rh.isFinite) return false;

      // The shared DECLINE predicate — the app's single source of truth for
      // "did the classifier decline, or judge and find no frost?". Called,
      // never re-derived.
      if (radiativeFrostJudgementDeclined(t: temp, rhPercent: rh)) return false;
    }

    return true;
  }
}
