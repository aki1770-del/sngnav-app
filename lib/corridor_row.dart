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
import 'l10n/app_localizations.dart';

/// Width of the station-name column (header + every row).
const double corridorStationColumnWidth = 130;

/// Width of the observed-time column (header + every row).
const double corridorObservedColumnWidth = 70;

/// The unit each data column is in. Drawn ONCE, in the column head, instead of
/// beside every value.
///
/// Why (measured 2026-09-18, at 393 px, device pixel ratio 2, both faces). At
/// phone width the three data columns are 43.0 px each. A value carrying its
/// own unit does not fit in 43 px, and the cell's `FittedBox` shrank it rather
/// than wrapping it: "-12.1 °C" drew at **9.21 px** with a Japanese face and
/// the wind at 10.32 px, against the 11 px floor this card holds its failure
/// line to — the temperature, the number that says ice, was the smallest text
/// on her page. The temperature pill also spans its whole cell, so the pill and
/// the wind value had **0.0 px** between them.
///
/// With the unit in the head every value draws at the full 12.00 px in both
/// faces, and the wind clears the observed time by 18 px.
///
/// These are SI symbols and are deliberately NOT localized: 「cm」「°C」「m/s」
/// are written the same on her Japanese page and on the English one, which is
/// why they are constants here beside the column widths rather than strings in
/// the localizations. They live in this file for the same reason the widths do
/// — the head in `main.dart` and the rows here must not drift apart.
///
/// ⚑ The unit leaving the cell must never mean the unit leaving the SCREEN
/// READER. Each data cell below carries `<value> <unit>` as its semantics
/// label, so a reader who cannot see the column head still hears the unit.
const String corridorSnowUnit = 'cm';
const String corridorTempUnit = '°C';
const String corridorWindUnit = 'm/s';

/// Gap held between the temperature pill's painted edge and the wind value.
///
/// The pill is the only data cell with a painted background, so it fills its
/// 43 px cell edge to edge and its colour ran straight into the next column's
/// number. 4 px is the gap this card holds between neighbouring columns.
const double corridorPillInset = 4;

/// One column head: the label, and under it the unit the column is in.
///
/// Two lines, because one will not fit. Measured at 393 px in both faces: the
/// unit set INLINE overflows a 43 px head in seven of nine label/unit pairs —
/// 「風速 (m/s)」 by 14.0 px, 「積雪深 (cm)」 by 19.5 px, "Wind (m/s)" by 14.4 px
/// — and an overflowing head either wraps where it likes or is clipped. On its
/// own line every unit fits in both faces and both languages, the widest being
/// 28.7 px in a 43.0 px column.
class CorridorColumnHead extends StatelessWidget {
  const CorridorColumnHead({
    super.key,
    required this.label,
    required this.unit,
  });

  final String label;

  /// The unit, or null for a column that has none (the station and the
  /// observed time). A null unit still reserves the second line, so the heads
  /// share one baseline and the table does not step.
  final String? unit;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
      Text(
        unit ?? '',
        // grey.shade700, as the card's other secondary lines: shade600 was
        // 4.17:1 on this card, under the 4.5:1 floor. Held at 11 px, the same
        // floor as the failure line — a unit that is the only place the reader
        // can learn what a number means is not a caption.
        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
      ),
    ],
  );
}

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
        JmaFailure() => _FailureRow(descriptor: descriptor),
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
              Text(
                  AppL10n.of(context).stationName(
                      observation.stationId, observation.stationName),
                  style: const TextStyle(fontSize: 12)),
              // grey.shade700, as the card's other secondary lines: shade600
              // was 4.17:1 on the card (2026-09-15), under the 4.5:1 floor.
              Text(descriptor,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
            ],
          ),
        ),
        Expanded(
          child: _ValueCell(
            value: snow?.toStringAsFixed(0),
            unit: corridorSnowUnit,
          ),
        ),
        Expanded(child: _TempCell(temp: temp, tempMin: tempMin, tempMax: tempMax)),
        Expanded(
          child: _ValueCell(
            value: wind?.toStringAsFixed(1),
            unit: corridorWindUnit,
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

/// One data value, drawn bare, with its unit in the column head.
///
/// History, because the shape of this widget is the record of two defects.
/// Until 2026-09-15 a value and its unit were one wrapping line, and the line
/// broke INSIDE the unit at 393 px. That was fixed by laying the pair out
/// unwrapped in a `FittedBox`, which moved the failure rather than removing it:
/// the pair still did not fit 43 px, so it was SHRUNK — to 9.21 px for the
/// temperature with a Japanese face, under this card's own 11 px floor. Neither
/// version was legible; the first was broken and the second was small.
///
/// The unit is now in the head ([CorridorColumnHead]) and every value draws at
/// its full 12 px. The `FittedBox` stays as the backstop for a value nobody has
/// seen yet — a four-digit snow depth, a system text scale — and where the
/// value fits it is not scaled at all.
///
/// [unit] is not drawn. It is carried into the semantics label so a screen
/// reader still hears "130 cm" and not "130": the column head is a visual
/// affordance, and taking the unit out of the cell must not take it away from a
/// reader who cannot see the head.
class _ValueCell extends StatelessWidget {
  const _ValueCell({required this.value, required this.unit});

  /// The formatted number, or null when the station gave none.
  final String? value;

  final String unit;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final box = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        v ?? '—',
        style: const TextStyle(fontSize: 12),
        softWrap: false,
        maxLines: 1,
      ),
    );
    // A missing value gets no unit: "— cm" would announce a measurement that
    // was never made.
    if (v == null) return box;
    return Semantics(
      label: '$v $unit',
      excludeSemantics: true,
      child: box,
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

    final value = temp?.toStringAsFixed(1);
    final spoken = value == null ? '—' : '$value $corridorTempUnit';
    final cell = Container(
      // 3 px each side (was 6): at 393 px the cell is 43 px, and "-2.1 °C" in
      // Roboto is 37 px (measured 2026-09-15), so 6 px left it drawn at 0.84.
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      // ⚑ The pill is the only data cell that paints a background, so without
      // this it fills its 43 px cell edge to edge and its colour runs straight
      // into the wind value: measured 0.0 px between the two painted extents
      // on 2026-09-16, where this card holds 4 px between neighbouring columns.
      // The inset is on the trailing side only — the leading edge is the
      // column's own alignment and must stay put, and the snow value ends
      // ~22 px before it in both faces, so nothing crowds it there.
      margin: const EdgeInsetsDirectional.only(end: corridorPillInset),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: _ValueCell(value: value, unit: corridorTempUnit),
    );

    if (semanticEndpoint == null) return cell;
    // The endpoint hint replaces the inner cell's own label, so the unit has to
    // be carried here too or it is lost for the coldest and warmest stations —
    // the two rows a reader most needs the unit on.
    return Semantics(
      label: '$spoken, $semanticEndpoint',
      excludeSemantics: true,
      child: cell,
    );
  }
}

class _FailureRow extends StatelessWidget {
  const _FailureRow({required this.descriptor});

  final String descriptor;
  @override
  Widget build(BuildContext context) {
    // Preserve column structure: data cells become em-dashes; the failure
    // line sits under the descriptor on the second name-column line. The
    // fetch's reason is not shown there (decided 2026-09-14 for the route line, applied here 2026-09-15). This
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
                key: const Key('corridor-station-fetch-failed'),
                AppL10n.of(context).corridorStationFetchFailed,
                // red.shade900 at 11 px (2026-09-15): red.shade700 at 10 px was
                // 4.51:1 on the card, at the floor; the source line beside the
                // table is 11 px.
                style: TextStyle(fontSize: 11, color: Colors.red.shade900),
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
