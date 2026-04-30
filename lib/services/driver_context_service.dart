/// Slice 4 — driver context service.
///
/// Holds the active DriverProfile (trait), the active DriverState (live),
/// the latest DrivingContext (environmental), and the last resolved
/// NavigationSafetyConfig. Recomputes the config on each input change
/// with a small debounce so a burst of updates produces one recompute
/// rather than several.
///
/// The state-axis follows a passive-propose / active-affirm pattern.
/// External signals (a fatigue heuristic, a long-drive timer, a cohort
/// study trigger) suggest a state via proposeState; the service stores
/// the suggestion separately from the active state. The active state
/// only changes when the UI calls affirmState. This pattern is the
/// load-bearing piece of Slice 4: a transient state attribution must
/// be a deliberate driver act, not a silent inference, because a wrong
/// silent classification of a driver as "fatigued" or "distracted"
/// would degrade their experience without their consent.
///
/// The default profile is ageingRural — the named first customer
/// is an older driver in rural Akita, and the most-vulnerable cohort
/// member shapes the default. The default state is alert.
///
/// This service does NOT branch on profile or state. It only stores
/// inputs and recomputes the config. The widget tree is forbidden
/// from branching on profile or state. The architectural test in
/// test/architectural/severity_not_profile_test.dart enforces the ban.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

/// The minimum gap between input changes and the next recompute. Keeps
/// a burst of updates (e.g. profile picker tap then immediate state
/// affirmation) from producing two recomputes back-to-back.
const Duration kDriverContextRecomputeDebounce = Duration(seconds: 2);

/// Active driver profile + state + environmental context, plus the
/// last resolved NavigationSafetyConfig. Listeners are notified when
/// any of these changes; the resolved config is recomputed with a
/// debounce so bursts collapse to one recompute.
class DriverContextService extends ChangeNotifier {
  DriverProfile _profile;
  DriverState _activeState;
  DriverState? _proposedState;
  DrivingContext _drivingContext;
  NavigationSafetyConfig _resolvedConfig;
  Timer? _debounce;
  final Duration _debounceDuration;

  /// Construct with a starting profile + state. Defaults follow the
  /// named-first-customer substance: ageingRural is the first cohort.
  DriverContextService({
    DriverProfile initialProfile = DriverProfile.ageingRural,
    DriverState initialState = DriverState.alert,
    DrivingContext initialDrivingContext = const DrivingContext(),
    Duration debounceDuration = kDriverContextRecomputeDebounce,
  })  : _profile = initialProfile,
        _activeState = initialState,
        _drivingContext = initialDrivingContext,
        _debounceDuration = debounceDuration,
        _resolvedConfig = NavigationSafetyConfig.forDriverContext(
          DriverContext(profile: initialProfile, state: initialState),
          environmentalContext: initialDrivingContext,
        );

  /// The active driver profile (trait axis).
  DriverProfile get profile => _profile;

  /// The active driver state (live axis). Changes only via affirmState.
  DriverState get activeState => _activeState;

  /// A state the service is suggesting the driver might be in. Null
  /// when no suggestion is pending. The active state never silently
  /// follows the proposal; the UI must call affirmState to commit.
  DriverState? get proposedState => _proposedState;

  /// The latest environmental context (speed, humidity, temperature,
  /// time-since-precipitation).
  DrivingContext get drivingContext => _drivingContext;

  /// The most recently resolved NavigationSafetyConfig. The widget tree
  /// reads this and nothing else; it is the only output the rest of
  /// the app sees from this service.
  NavigationSafetyConfig get resolvedConfig => _resolvedConfig;

  /// Replace the active profile. Triggers a debounced recompute.
  void setProfile(DriverProfile profile) {
    if (_profile == profile) return;
    _profile = profile;
    _scheduleRecompute();
    notifyListeners();
  }

  /// Replace the environmental context. Triggers a debounced recompute.
  void setDrivingContext(DrivingContext context) {
    if (_drivingContext == context) return;
    _drivingContext = context;
    _scheduleRecompute();
    notifyListeners();
  }

  /// Suggest a state without committing. The proposal sits beside the
  /// active state until the UI calls affirmState. Pass null to clear
  /// any pending proposal without a state change.
  void proposeState(DriverState? state) {
    if (_proposedState == state) return;
    _proposedState = state;
    notifyListeners();
  }

  /// Commit a state change. This is the only path that mutates the
  /// active state; passive-propose semantics mean the service never
  /// silently follows a proposal. Clearing the proposal happens here
  /// so the rail does not show a stale suggestion after affirmation.
  void affirmState(DriverState state) {
    final stateChanged = _activeState != state;
    final hadProposal = _proposedState != null;
    if (!stateChanged && !hadProposal) return;
    _activeState = state;
    _proposedState = null;
    if (stateChanged) {
      _scheduleRecompute();
    }
    notifyListeners();
  }

  void _scheduleRecompute() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, _recomputeNow);
  }

  /// Force the recompute immediately. Tests use this to skip the
  /// debounce wait.
  @visibleForTesting
  void recomputeNowForTesting() {
    _debounce?.cancel();
    _recomputeNow();
  }

  void _recomputeNow() {
    final next = NavigationSafetyConfig.forDriverContext(
      DriverContext(profile: _profile, state: _activeState),
      environmentalContext: _drivingContext,
    );
    if (next == _resolvedConfig) return;
    _resolvedConfig = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
