/// Corridor table row widget — one JMA AMeDAS station per row.
///
/// Extracted from main.dart so the row is widget-testable in isolation
/// (without spinning up the full app or hitting the JMA network).
///
/// Layout discipline: column widths are constants shared with the header
/// row in main.dart so the two stay in lockstep. Failure rows preserve
/// the column structure (an em-dash in each data cell) so the visual
/// rhythm of the table does not collapse when one station fetches and
/// another fails.
///
/// Color discipline: the temperature-cell background gradient is
/// supplemental, not primary. The temperature value itself is the
/// authoritative signal (and is what a screen reader announces).
/// The blue↔orange palette is divergent and CB-safe; the coldest and
/// warmest stations carry an extra Semantics label so the relative
/// position is also reachable without sight.
library;

import 'package:flutter/material.dart';

import 'jma_fetch.dart';

/// Width of the station-name column (header + every row).
const double corridorStationColumnWidth = 130;

/// Width of the observed-time column (header + every row).
const double corridorObservedColumnWidth = 70;

/// One row of the corridor weather table.
///
/// Pass the resolved [JmaResult] for the station, its [descriptor], and
/// the corridor-wide [tempMin]/[tempMax] (null if no resolved temps).
class CorridorRow extends StatelessWidget {
  const CorridorRow({
    super.key,
    required this.result,
    required this.descriptor,
    required this.tempMin,
    required this.tempMax,
  });

  final JmaResult result;
  final String descriptor;
  final double? tempMin;
  final double? tempMax;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: switch (result) {
        JmaSuccess(:final observation) => _SuccessRow(
            observation: observation,
            descriptor: descriptor,
            tempMin: tempMin,
            tempMax: tempMax,
          ),
        JmaFailure(:final reason) => _FailureRow(
            descriptor: descriptor,
            reason: reason,
          ),
      },
    );
  }
}

class _SuccessRow extends StatelessWidget {
  const _SuccessRow({
    required this.observation,
    required this.descriptor,
    required this.tempMin,
    required this.tempMax,
  });

  final JmaObservation observation;
  final String descriptor;
  final double? tempMin;
  final double? tempMax;

  @override
  Widget build(BuildContext context) {
    final snow = observation.snowDepthCm;
    final temp = observation.temperatureCelsius;
    final wind = observation.windMetersPerSecond;
    final ts = observation.observedAtJstKey;
    final obsTime = (ts.length == 14)
        ? '${ts.substring(8, 10)}:${ts.substring(10, 12)}'
        : ts;

    return Row(
      children: [
        SizedBox(
          width: corridorStationColumnWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(observation.stationName,
                  style: const TextStyle(fontSize: 12)),
              Text(descriptor,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ],
          ),
        ),
        Expanded(
          child: Text(
            snow == null ? '—' : '${snow.toStringAsFixed(0)} cm',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(child: _TempCell(temp: temp, tempMin: tempMin, tempMax: tempMax)),
        Expanded(
          child: Text(
            wind == null ? '—' : '${wind.toStringAsFixed(1)} m/s',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        SizedBox(
          width: corridorObservedColumnWidth,
          child: Text(
            '$obsTime JST',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }
}

/// Temperature cell with corridor-relative gradient background.
///
/// Background lerps blue↔orange between the corridor's coldest and
/// warmest resolved temperatures. When fewer than two stations have
/// resolved (or all temps are equal) the gradient is skipped — no
/// false-positive color signal from a single data point.
class _TempCell extends StatelessWidget {
  const _TempCell({
    required this.temp,
    required this.tempMin,
    required this.tempMax,
  });

  final double? temp;
  final double? tempMin;
  final double? tempMax;

  @override
  Widget build(BuildContext context) {
    final hasGradient = temp != null &&
        tempMin != null &&
        tempMax != null &&
        tempMax! > tempMin!;

    Color bg = Colors.transparent;
    String? semanticEndpoint;
    if (hasGradient) {
      final t = (temp! - tempMin!) / (tempMax! - tempMin!);
      bg = Color.lerp(Colors.blue.shade100, Colors.orange.shade100, t) ??
          Colors.transparent;
      // Endpoint hint for screen readers — gradient itself is unreachable
      // without sight, but "coldest" / "warmest in corridor" is.
      if (temp == tempMin) semanticEndpoint = 'coldest in corridor';
      if (temp == tempMax) semanticEndpoint = 'warmest in corridor';
    }

    final text = temp == null ? '—' : '${temp!.toStringAsFixed(1)} °C';
    final cell = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );

    if (semanticEndpoint == null) return cell;
    return Semantics(
      label: '$text, $semanticEndpoint',
      excludeSemantics: true,
      child: cell,
    );
  }
}

class _FailureRow extends StatelessWidget {
  const _FailureRow({required this.descriptor, required this.reason});

  final String descriptor;
  final String reason;

  @override
  Widget build(BuildContext context) {
    // Preserve column structure: data cells become em-dashes; the reason
    // sits under the descriptor on the second name-column line. This
    // keeps the table's visual rhythm intact when one row fails.
    return Row(
      children: [
        SizedBox(
          width: corridorStationColumnWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('— ($descriptor)', style: const TextStyle(fontSize: 12)),
              Text(
                'fetch failed: $reason',
                style: TextStyle(fontSize: 10, color: Colors.red.shade700),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
        const Expanded(child: Text('—', style: TextStyle(fontSize: 12))),
        const Expanded(child: Text('—', style: TextStyle(fontSize: 12))),
        const Expanded(child: Text('—', style: TextStyle(fontSize: 12))),
        const SizedBox(
          width: corridorObservedColumnWidth,
          child: Text('—', style: TextStyle(fontSize: 11)),
        ),
      ],
    );
  }
}
