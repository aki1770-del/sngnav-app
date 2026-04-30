/// Slice 4 — bridge JMA AMeDAS observations + GPS speed into a
/// DrivingContext value the navigation_safety_core threshold factory
/// understands.
///
/// Pure Dart. No Flutter, no platform channels, no I/O. Takes inputs
/// the app already has and produces a single immutable value object.
/// This is the only place the app converts external observation units
/// into the core package's input units; every other call site receives
/// a ready-made DrivingContext.
///
/// Article 17 boundary: this module is operation-class (b) — present-
/// tense single-point arithmetic on already-relayed JMA values
/// (humidity percent to fraction; nothing more). It does not derive,
/// fuse, or predict. Time-since-precipitation is read from a separate
/// caller-supplied input because the JMA verbatim fetch does not carry
/// a precipitation-event timestamp.
///
/// The bridge is mockable: every input is a plain Dart value, so unit
/// tests pass synthetic observations without HTTP or geolocator.
library;

import 'package:navigation_safety_core/navigation_safety_core.dart';

/// Convert a JMA observation snapshot plus a GPS speed sample plus an
/// optional time-since-precipitation duration into a DrivingContext.
///
/// Each input may be null when not available; the returned DrivingContext
/// carries nulls for the corresponding fields and the threshold factory
/// falls back to per-profile baselines for those dimensions.
///
/// The conversion rules:
///
/// - speedMps is passed through unchanged (the geolocator stream already
///   reports metres per second on every supported platform).
/// - humidityPercent (0..100 integer) becomes humidityRH (0.0..1.0
///   fraction); null in stays null out.
/// - ambientTempCelsius is passed through unchanged.
/// - timeSincePrecipitation is passed through unchanged; the caller is
///   responsible for tracking the most recent precipitation event from
///   whatever source it has (JMA precipitation-history endpoint, manual
///   user input, or a separate observation stream).
DrivingContext bridgeJmaToDrivingContext({
  double? speedMps,
  int? humidityPercent,
  double? ambientTempCelsius,
  Duration? timeSincePrecipitation,
}) {
  return DrivingContext(
    speedMps: speedMps,
    humidityRH:
        humidityPercent == null ? null : humidityPercent.clamp(0, 100) / 100.0,
    ambientTempCelsius: ambientTempCelsius,
    timeSincePrecipitation: timeSincePrecipitation,
  );
}
