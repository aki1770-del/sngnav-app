/// The GPS trust verdict: whether a fix can be believed before it is shown to
/// her as 「GPS 良好」, followed by her map, or read aloud as given.
///
/// **Why this exists (decided 2026-10-05; the gap was first written down on
/// 2026-07-14).** The drive brain fed every finite fix to
/// `LocalizationController.onFix` with no verdict, and localization_fallback
/// 0.1.4 defaults the verdict to `trusted`. A jump no car made, a fix the
/// receiver itself put at ±400 m, or a replayed timestamp all read 「GPS 良好」,
/// the map followed them with a small ring, the caution rung stayed at its
/// lowest, and a turn read on her press was read as given. That is a
/// success-shaped answer from a check that never ran, and it settled every
/// doubtful fix toward "good".
///
/// **What changes what she is shown, and what does not.**
///  - ACTS: a fix no newer than the last fix assessed is `failed`; a reported
///    accuracy over [kGpsCoarseAccuracyMeters] is `suspect`; an implied speed
///    over [kGpsMaxPlausibleSpeedMps] is `failed`, measured from the previous
///    fix (position_integrity's hard gates, read from `gateResults`) and from
///    the last fix the drive brain took as trusted (this file, with both
///    reported accuracies taken off the distance). The speed gate acts only
///    under two conditions found by a tunnel-exit test: fixes less than
///    [kGpsTeleportRegimeBelow] apart go to the package's teleport check, and
///    this file's own speed gate subtracts both accuracies.
///  - SHADOW: the package's acceleration and stationary-jitter gates, and a
///    frozen-position rule. They are computed for every fix and kept in
///    [GpsTrustVerdict.shadow], and they change nothing she sees or hears
///    until their false alarms have been counted on honest fixes from a real
///    phone. A warning she learns to ignore protects nobody.
///  - The first fix of a history is NOT ASSESSED: there is nothing to compare
///    it with. It is `suspect`, never `trusted`, and it is the comparison base
///    for the next fix, so the next fix is not "first" again.
///  - A coarse fix is never a comparison base. position_integrity compares
///    each fix with the one before it, whatever that one was; a network-grade
///    fix 300 m from her would make her next satellite fix read as an
///    impossible speed. Where satellite and network fixes alternate, no fix
///    would ever be trusted. So a fix over [kGpsCoarseAccuracyMeters] is not
///    given to the package at all.
///  - After a fix the hard gates reject, position_integrity compares the next
///    fix with the rejected one (its own KNOWN_LIMITATIONS §7, "Recovery has a
///    one-fix transient"). Kept as the package does it: a one-off jump costs
///    the jump and the fix that returns, and the fix after that is trusted.
///
/// **What `trusted` means here, and what it does not.** No check in this file
/// found a fault with the fix. It does not mean the position is right: a
/// displaced track that stays self-consistent after its first two fixes, an
/// offset that builds up slowly, and a bias present from the first fix of a
/// share all pass. See KNOWN_LIMITATIONS.md, "The GPS trust verdict".
///
/// Every threshold here is an advisory value. Nothing here is safety-rated or
/// certified. Pure Dart: no Flutter, no timers, no IO.
library;

import 'dart:math' as math;

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show kRadiusNeighbourhoodM;
import 'package:localization_fallback/localization_fallback.dart'
    show TrustSignal;
import 'package:position_integrity/position_integrity.dart' as pi;

import '../her_position.dart';

/// A fix whose own reported accuracy is over this, in metres, is `suspect`:
/// the receiver itself puts her somewhere in a neighbourhood. It is the
/// caution advisor's own "neighbourhood scale" line
/// (compound_failure_advisor `kRadiusNeighbourhoodM`), so trust and caution
/// share one number. Routed to `suspect`, never `lost`: lowering the
/// controller's `maxTrustworthyRadiusMeters` instead would make every coarse
/// fix lost at once and, with no anchor yet, give the top caution rung on a
/// clear day.
const double kGpsCoarseAccuracyMeters = kRadiusNeighbourhoodM;

/// An implied speed over this, in m/s, is no road vehicle: `failed`. It is
/// position_integrity's own default, 17 m/s above Japan's highest legal speed
/// (120 km/h, 33 m/s, held by a test at that speed).
const double kGpsMaxPlausibleSpeedMps = 50.0;

/// Two fixes closer together than this are judged by position_integrity's
/// teleport check (a jump of more than its 30 m fails) instead of its speed
/// gate. Raised from the package's 100 ms so that a reacquisition burst at a
/// tunnel exit (honest fixes 0.3 s apart, each ±20 m) is not read as an
/// impossible speed. Ordinary fixes a second or more apart stay in the speed
/// regime. PROVISIONAL: how far apart real bursts arrive on her phone has not
/// been measured.
const Duration kGpsTeleportRegimeBelow = Duration(milliseconds: 500);

/// The frozen-position rule (shadow only) looks back at least this far.
const Duration kGpsFrozenWindow = Duration(seconds: 3);

/// The worse of two verdicts: trusted < suspect < failed.
TrustSignal worseTrust(TrustSignal a, TrustSignal b) =>
    a.index >= b.index ? a : b;

/// The verdict on one fix.
class GpsTrustVerdict {
  const GpsTrustVerdict({
    required this.acting,
    required this.shadow,
    required this.assessed,
    required this.reasons,
    this.shadowReasons = const [],
    this.awaitingComparison = false,
  });

  /// What the drive brain is given for this fix, and so what she is shown.
  final TrustSignal acting;

  /// What the gates kept in shadow say about this fix. Never acted on. When
  /// they could not run (the first fix, a replay, an assessor fault) it is
  /// `suspect`, never `trusted`: a gate that did not run has found nothing,
  /// and nothing found must not read as a pass.
  final TrustSignal shadow;

  /// False when there was nothing to judge the fix against (the first fix of
  /// a history), or the assessor itself could not run.
  final bool assessed;

  /// True only for a first fix that nothing found wrong: not coarse, and the
  /// assessor running. It is not trusted, because nothing could judge it yet;
  /// it is not a failure either. The app treats it as a share starting
  /// normally, not as a share that failed to start (decided 2026-10-05).
  final bool awaitingComparison;

  /// Why [acting] is what it is: the acting gates that fired, or why the fix
  /// was not assessed. Empty on a clean fix.
  final List<String> reasons;

  /// The shadow gates that fired, or why they could not run. Empty when they
  /// ran and none fired.
  final List<String> shadowReasons;

  @override
  String toString() => 'GpsTrustVerdict(acting: ${acting.name}, '
      'shadow: ${shadow.name}, assessed: $assessed, $reasons, $shadowReasons)';
}

/// One fix as the assessor remembers it.
class _Seen {
  const _Seen(this.lat, this.lon, this.accuracy, this.t, this.lowerBound);
  final double lat;
  final double lon;
  final double accuracy;
  final DateTime t;
  final double? lowerBound;
}

/// Judges each fix against the fixes before it. One per drive brain.
///
/// It advances once per fix it is given, through [assess]. Asking about the
/// same fix twice is the caller's to avoid: `DriveLocalizer` keeps the verdict
/// for the fix it was last asked about, so asking and then feeding the same
/// fix advances this once.
class GpsTrustAssessor {
  /// [monitor] builds position_integrity's monitor. It is injectable only so a
  /// test can make construction throw.
  GpsTrustAssessor({pi.PositionIntegrityMonitor Function()? monitor})
      : _makeMonitor = monitor ?? _defaultMonitor {
    try {
      _monitor = _makeMonitor();
    } catch (e) {
      _recordFault('could not be constructed: $e');
    }
  }

  /// The package's defaults everywhere except the speed limit (its default,
  /// stated) and the teleport regime. The acceleration limit stays at the
  /// package's 8 m/s²: it acts on nothing here, it only fills the shadow
  /// record, and no limit for it has been measured on a phone.
  static pi.PositionIntegrityMonitor _defaultMonitor() =>
      pi.PositionIntegrityMonitor(
        maxPlausibleSpeed: kGpsMaxPlausibleSpeedMps,
        minSpeedDelta: kGpsTeleportRegimeBelow,
      );

  final pi.PositionIntegrityMonitor Function() _makeMonitor;
  pi.PositionIntegrityMonitor? _monitor;

  /// How many times the assessor could not be built or threw, and the last
  /// reason. Each fix it could not judge was given as `suspect`, never as
  /// `trusted`, and the position feed was never stopped.
  int faultCount = 0;
  String? lastFault;

  _Seen? _last;
  _Seen? _anchor;
  final List<_Seen> _window = [];

  /// Whether position_integrity has been given a fix since the last reset,
  /// that is, whether it has anything to compare the next fix with.
  bool _monitorHasBase = false;

  void _recordFault(String why) {
    faultCount++;
    lastFault = why;
  }

  /// Forget every fix: the next one is a first fix again. Called where a
  /// share begins. A fault recorded stays recorded.
  void reset() {
    _monitor?.reset();
    _monitorHasBase = false;
    _last = null;
    _anchor = null;
    _window.clear();
  }

  /// The drive brain took [fix], whose measured accuracy is [accuracy], as
  /// trusted. The next fixes' speed is measured from it as well as from the
  /// previous fix, so a jump that stays where it jumped is not trusted on its
  /// second fix. A displaced track becomes plausible again after about
  /// distance / 50 s.
  void anchorOn(PositionAvailable fix, double accuracy) {
    _anchor = _Seen(fix.latitude, fix.longitude, accuracy, fix.timestamp,
        fix.speedLowerBoundMps);
  }

  /// The verdict on [fix], whose measured horizontal accuracy is [accuracy]
  /// and whose geometry the caller has already found finite. Advances the
  /// assessor, except on a fix no newer than the last one and on a fault.
  GpsTrustVerdict assess(PositionAvailable fix, double accuracy) {
    final monitor = _monitor;
    if (monitor == null) {
      return _notAssessed('assessor unavailable: $lastFault');
    }
    final last = _last;
    // A fix that carries no new time carries no new position: `failed`.
    // Never the package's "skipped" `suspect`, which would show a replay as a
    // present, doubtful fix and read a hedged turn from it.
    if (last != null && !fix.timestamp.isAfter(last.t)) {
      return const GpsTrustVerdict(
        acting: TrustSignal.failed,
        shadow: TrustSignal.suspect,
        assessed: true,
        reasons: ['not newer than the last fix assessed'],
        shadowReasons: ['not evaluated: a replayed or older fix'],
      );
    }

    final seen = _Seen(fix.latitude, fix.longitude, accuracy, fix.timestamp,
        fix.speedLowerBoundMps);
    final coarse = accuracy > kGpsCoarseAccuracyMeters;
    if (coarse) {
      // Never a comparison base: not given to position_integrity, not in the
      // frozen-position window. It still counts as the last fix in time.
      _last = seen;
      final anchorWhy = _anchorSpeedFault(fix, accuracy);
      return GpsTrustVerdict(
        acting: anchorWhy == null ? TrustSignal.suspect : TrustSignal.failed,
        shadow: TrustSignal.suspect,
        assessed: true,
        reasons: [_coarseReason(accuracy), ?anchorWhy],
        shadowReasons: const ['not evaluated: a coarse fix'],
      );
    }

    final hadBase = _monitorHasBase;
    final pi.IntegrityVerdict verdict;
    try {
      verdict = monitor.update(pi.PositionFix(
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracyMetres: accuracy,
        timestamp: fix.timestamp,
      ));
    } catch (e) {
      _recordFault('threw on a fix: $e');
      return _notAssessed('assessor threw: $e');
    }
    _monitorHasBase = true;
    _last = seen;
    _window.add(seen);

    if (!hadBase) {
      // Nothing to compare it with. The app holds it before a share has
      // anchored, and it is never trusted if it is fed. The package has taken
      // it as its comparison base, so the next fix is judged against it.
      final anchorWhy = _anchorSpeedFault(fix, accuracy);
      return GpsTrustVerdict(
        acting: anchorWhy == null ? TrustSignal.suspect : TrustSignal.failed,
        shadow: TrustSignal.suspect,
        assessed: false,
        reasons: [
          'first fix: nothing to compare it with',
          ?anchorWhy,
        ],
        shadowReasons: const ['not evaluated: a first fix'],
        awaitingComparison: anchorWhy == null,
      );
    }

    var acting = TrustSignal.trusted;
    final reasons = <String>[];
    // Only the package's HARD gates act. Its overall status would let its
    // soft gates act too.
    final gates = verdict.gateResults;
    final hardGateFired = gates[pi.GateId.teleport] == false ||
        gates[pi.GateId.impossibleSpeed] == false;
    if (hardGateFired) {
      acting = TrustSignal.failed;
      reasons.add(verdict.reason);
    }
    final anchorWhy = _anchorSpeedFault(fix, accuracy);
    if (anchorWhy != null) {
      acting = TrustSignal.failed;
      reasons.add(anchorWhy);
    }

    var shadow = TrustSignal.trusted;
    final shadowReasons = <String>[];
    if (gates[pi.GateId.impossibleAccel] == false ||
        gates[pi.GateId.stationaryJitter] == false) {
      // A sustained acceleration fault escalates to `failed` inside the
      // package; that escalation belongs to the shadow record.
      shadow = verdict.status == pi.IntegrityStatus.failed && !hardGateFired
          ? TrustSignal.failed
          : TrustSignal.suspect;
      shadowReasons.add(verdict.reason);
    }
    final frozen = _frozenWhileSurelyMoving(seen);
    if (frozen != null) {
      shadow = worseTrust(shadow, TrustSignal.suspect);
      shadowReasons.add(frozen);
    }

    return GpsTrustVerdict(
      acting: acting,
      shadow: shadow,
      assessed: true,
      reasons: reasons,
      shadowReasons: shadowReasons,
    );
  }

  /// The implied speed from the last fix the drive brain trusted, with both
  /// reported accuracies taken off the distance; why it is over
  /// [kGpsMaxPlausibleSpeedMps], or `null`.
  String? _anchorSpeedFault(PositionAvailable fix, double accuracy) {
    final anchor = _anchor;
    if (anchor == null || !fix.timestamp.isAfter(anchor.t)) return null;
    final dt = fix.timestamp.difference(anchor.t).inMicroseconds / 1e6;
    final apart =
        _metres(anchor.lat, anchor.lon, fix.latitude, fix.longitude) -
            anchor.accuracy -
            accuracy;
    final speed = apart / dt;
    if (speed <= kGpsMaxPlausibleSpeedMps) return null;
    return 'implied speed from the last trusted fix: '
        '${speed.toStringAsFixed(0)} m/s beyond both accuracies';
  }

  GpsTrustVerdict _notAssessed(String why) => GpsTrustVerdict(
        acting: TrustSignal.suspect,
        shadow: TrustSignal.suspect,
        assessed: false,
        reasons: [why],
        shadowReasons: const ['not evaluated: assessor fault'],
      );

  static String _coarseReason(double accuracy) =>
      'reported accuracy ${accuracy.toStringAsFixed(0)} m is over '
      '${kGpsCoarseAccuracyMeters.toStringAsFixed(0)} m';

  /// The frozen-position rule (shadow only). Over a window of at least
  /// [kGpsFrozenWindow], the slowest speed she was SURELY moving at
  /// ([PositionAvailable.speedLowerBoundMps]), times the time, less the
  /// reported accuracy at both ends, is more than the fix moved. Every fix
  /// after the window's start must carry a lower bound; one with none (a stop,
  /// a crawl as uncertain as its speed, no speed reported) means no check.
  /// Returns why it fired, or `null`.
  String? _frozenWhileSurelyMoving(_Seen current) {
    // Keep the newest fix at least [kGpsFrozenWindow] old, and every fix since.
    while (_window.length >= 2 &&
        current.t.difference(_window[1].t) >= kGpsFrozenWindow) {
      _window.removeAt(0);
    }
    if (_window.length < 2) return null;
    final ref = _window.first;
    final span = current.t.difference(ref.t);
    if (span < kGpsFrozenWindow) return null;
    var slowest = double.infinity;
    for (final f in _window.skip(1)) {
      final lower = f.lowerBound;
      if (lower == null) return null;
      slowest = math.min(slowest, lower);
    }
    final seconds = span.inMicroseconds / 1e6;
    final need = slowest * seconds - (ref.accuracy + current.accuracy);
    if (need <= 0) return null;
    final moved = _metres(ref.lat, ref.lon, current.lat, current.lon);
    if (moved >= need) return null;
    return 'frozen: moved ${moved.toStringAsFixed(0)} m in '
        '${seconds.toStringAsFixed(1)} s while surely moving at '
        '${slowest.toStringAsFixed(1)} m/s (needs over '
        '${need.toStringAsFixed(0)} m)';
  }

  /// Great-circle distance on the sphere both packages use (R = 6371 km).
  static double _metres(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
    final dp = p2 - p1, dl = (lon2 - lon1) * math.pi / 180;
    final h = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
  }
}
