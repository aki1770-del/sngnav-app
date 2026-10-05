import 'package:flutter/material.dart';

/// One label and its value on one row, as the app draws every key-value line.
///
/// Moved here from `lib/main.dart` (2026-10-04), where it was the app
/// state's `_kv`, so that the next-turn panel, now its own widget, draws its
/// position row with this same code. `_kv` in `lib/main.dart` calls this.
///
/// Ladder fix (a) — the old fixed 110-px label column mangled long
/// labels: 路面凍結ウォッチ wrapped MID-WORD (ladder_out/api30/03_jma_card.png)
/// and the threshold-preview labels stacked one word per line
/// (05b_airplane_top.png). The label is now measured at the live text
/// scale: short labels keep the exact 110-px column (no visual change),
/// longer ones take their natural single-line width, capped at 60% of the
/// row so the value column always keeps room (word-boundary wrap beyond
/// the cap — never a forced mid-word break at 110).
Widget kvRow(String k, String v) {
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
