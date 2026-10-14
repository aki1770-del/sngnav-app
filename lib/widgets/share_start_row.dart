/// Where 現在地を共有 sits in the not-sharing row, so that no press aimed at
/// 停止 or 閉じる can land on it, and no press aimed at it can land on 停止
/// (code 16, 2026-10-14).
///
/// WHY. On code 15 the not-sharing row was end-aligned: 現在地を共有 and
/// 共有の同意を取り消す sat at the right end, and the right end is where 停止
/// is drawn while a share runs. The swap happens in the frame after his tap,
/// so a second press on 停止 took back his consent, and with no yes held it
/// would have restarted the share he had just ended (measured from the API 29
/// emulator's layout dumps, 2026-10-13). The withdrawal now has its own line
/// lower on the card; this widget places the share control.
///
/// THE RULE, as the screen review ruled it (2026-10-14):
/// - PIN, where code 15's row with a yes held would have fitted on one line:
///   the control stays exactly where he has been tapping it, its right edge
///   one withdrawal-width plus [ShareStartRow.spacing] left of the row's end,
///   in every consent state. His thumb keeps its place.
/// - RESERVED END, everywhere else, and wherever PIN would come within
///   [ShareStartRow.clearance] of the end column: start-aligned, its width
///   capped so its right edge stays that far left of the widest of 停止 and
///   閉じる at this text size. Its label wraps if it must.
///
/// HOW THE WIDTHS ARE KNOWN, and what the first version got wrong. They are
/// computed, never drawn: [textButtonNaturalWidth] resolves a TextButton's
/// style the way the framework resolves it (its own defaultStyleOf and
/// themeStyleOf, the visual density, the padded tap target) and measures the
/// label with the text painter the label's own Text would use. Nothing stands
/// in the element tree but the share control itself.
/// ⚑ The first version (5e73c4f7) laid out real, hidden TextButtons labelled
/// 停止 and 閉じる to measure them, and its comment said they were invisible to
/// the test finders. That was true only for finders that skip offstage
/// widgets. A finder that does not (`skipOffstage: false`) found the hidden
/// 停止 in the not-sharing row and read a share as running when none was: four
/// tests failed. Corrected here; the measuring is off the tree.
///
/// The computed widths are pinned against real TextButtons laid out in the
/// app's own theme, at both languages and every text size the stop-spot guard
/// covers (test/widgets/stop_spot_guard/text_button_width_test.dart), and the
/// guard measures the real 停止 against the real share control, so a
/// divergence between the computation and the real button turns one of them
/// red.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The clearance, edge to edge, between a tapped control's target and any
/// control drawn in its place in the next frame (the screen review,
/// 2026-10-14): half the platform's 48 dp minimum target.
const double kStopSpotClearance = 24.0;

/// Which rule placed the share control in the last layout.
enum ShareStartRule { pin, reservedEnd }

/// The width a `TextButton(onPressed: …, child: Text(label))` takes in
/// [context] when nothing narrows it: its padded tap target, label on one
/// line. Computed from the framework's own style resolution; no button is
/// built.
double textButtonNaturalWidth(BuildContext context, String label) {
  const probe = TextButton(onPressed: null, child: SizedBox.shrink());
  final defaults = probe.defaultStyleOf(context);
  final themed = probe.themeStyleOf(context);
  // An enabled button at rest: the state 停止 and 閉じる are drawn in.
  const states = <WidgetState>{};
  T? pick<T>(T? Function(ButtonStyle? s) of) => of(themed) ?? of(defaults);

  final textStyle = pick((s) => s?.textStyle?.resolve(states));
  final padding = pick((s) => s?.padding?.resolve(states))!
      .resolve(Directionality.of(context));
  final minimumSize = pick((s) => s?.minimumSize?.resolve(states))!;
  final maximumSize = pick((s) => s?.maximumSize?.resolve(states))!;
  final density = pick((s) => s?.visualDensity)!;
  final tapTarget = pick((s) => s?.tapTargetSize)!;
  final adjust = density.baseSizeAdjustment;

  // Material draws the label under DefaultTextStyle(textStyle), not merged
  // with the ambient one; Text then applies bold-text if the platform asks.
  var style = textStyle ?? Theme.of(context).textTheme.bodyMedium!;
  if (MediaQuery.boldTextOf(context)) {
    style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
  }
  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    textHeightBehavior: DefaultTextHeightBehavior.maybeOf(context),
  )..layout();
  final textWidth = painter.width;
  painter.dispose();

  // ButtonStyleButton: density never narrows the horizontal padding.
  final dx = math.max(0.0, adjust.dx);
  final constraints = density.effectiveConstraints(BoxConstraints(
    minWidth: minimumSize.width,
    minHeight: minimumSize.height,
    maxWidth: maximumSize.width,
    maxHeight: maximumSize.height,
  ));
  var width = (textWidth + padding.horizontal + 2 * dx)
      .clamp(constraints.minWidth, constraints.maxWidth)
      .toDouble();
  if (tapTarget == MaterialTapTargetSize.padded) {
    width = math.max(width, kMinInteractiveDimension + adjust.dx);
  }
  return width;
}

/// The not-sharing row: [share] placed by PIN or RESERVED END, against the
/// widths [withdrawLabel], [stopLabel] and [closeLabel] would take as
/// TextButtons at this text size.
class ShareStartRow extends StatelessWidget {
  const ShareStartRow({
    super.key,
    required this.share,
    required this.withdrawLabel,
    required this.stopLabel,
    required this.closeLabel,
    this.clearance = kStopSpotClearance,
    this.spacing = 8,
  });

  /// The share control, the only widget this row draws.
  final Widget share;

  /// The withdrawal's label, as code 15's row drew it beside [share].
  final String withdrawLabel;

  /// 停止 and 閉じる, drawn at the row's end while a share runs.
  final String stopLabel;
  final String closeLabel;

  /// The edge-to-edge clearance from the end column.
  final double clearance;

  /// The spacing code 15's row had between its two buttons.
  final double spacing;

  @override
  Widget build(BuildContext context) => _ShareStartRowLayout(
        withdrawWidth: textButtonNaturalWidth(context, withdrawLabel),
        endColumn: math.max(textButtonNaturalWidth(context, stopLabel),
            textButtonNaturalWidth(context, closeLabel)),
        clearance: clearance,
        spacing: spacing,
        child: share,
      );
}

class _ShareStartRowLayout extends SingleChildRenderObjectWidget {
  const _ShareStartRowLayout({
    required this.withdrawWidth,
    required this.endColumn,
    required this.clearance,
    required this.spacing,
    required Widget super.child,
  });

  final double withdrawWidth;
  final double endColumn;
  final double clearance;
  final double spacing;

  @override
  RenderShareStartRow createRenderObject(BuildContext context) =>
      RenderShareStartRow(
        withdrawWidth: withdrawWidth,
        endColumn: endColumn,
        clearance: clearance,
        spacing: spacing,
        textDirection: Directionality.of(context),
      );

  @override
  void updateRenderObject(
      BuildContext context, RenderShareStartRow renderObject) {
    renderObject
      ..withdrawWidth = withdrawWidth
      ..endColumn = endColumn
      ..clearance = clearance
      ..spacing = spacing
      ..textDirection = Directionality.of(context);
  }
}

/// Places its one child, the share control, by PIN or RESERVED END.
class RenderShareStartRow extends RenderShiftedBox {
  RenderShareStartRow({
    required double withdrawWidth,
    required double endColumn,
    required double clearance,
    required double spacing,
    required TextDirection textDirection,
  })  : _withdrawWidth = withdrawWidth,
        _endColumn = endColumn,
        _clearance = clearance,
        _spacing = spacing,
        _textDirection = textDirection,
        super(null);

  double _withdrawWidth;
  set withdrawWidth(double v) {
    if (v == _withdrawWidth) return;
    _withdrawWidth = v;
    markNeedsLayout();
  }

  double _endColumn;
  set endColumn(double v) {
    if (v == _endColumn) return;
    _endColumn = v;
    markNeedsLayout();
  }

  double _clearance;
  set clearance(double v) {
    if (v == _clearance) return;
    _clearance = v;
    markNeedsLayout();
  }

  double _spacing;
  set spacing(double v) {
    if (v == _spacing) return;
    _spacing = v;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection v) {
    if (v == _textDirection) return;
    _textDirection = v;
    markNeedsLayout();
  }

  /// The rule the last layout used.
  ShareStartRule get rule => _rule;
  ShareStartRule _rule = ShareStartRule.reservedEnd;

  /// The share control's constraints and start x (left to right), and the
  /// rule, for [constraints]. [natural] gives the control's width laid out
  /// loosely in the row.
  (BoxConstraints, double, ShareStartRule) _place(
      BoxConstraints constraints, double Function(BoxConstraints) natural) {
    final w = constraints.maxWidth;
    final loose = constraints.loosen();
    if (!w.isFinite) return (loose, 0, ShareStartRule.reservedEnd);
    // A button never draws wider than the row it sits in.
    final withdrawW = math.min(_withdrawWidth, w);
    final endColumn = math.min(_endColumn, w);
    final shareW = natural(loose);
    final pinnedRight = w - withdrawW - _spacing;
    final fitsOneLine = shareW + _spacing + withdrawW <= w;
    if (fitsOneLine && pinnedRight <= w - _clearance - endColumn) {
      return (loose, pinnedRight - shareW, ShareStartRule.pin);
    }
    final cap = math.max(0.0, w - _clearance - endColumn);
    return (BoxConstraints(maxWidth: cap), 0, ShareStartRule.reservedEnd);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final c = child;
    if (c == null) return constraints.smallest;
    final (cc, _, _) = _place(constraints, (l) => c.getDryLayout(l).width);
    final s = c.getDryLayout(cc);
    return constraints.constrain(Size(
        constraints.maxWidth.isFinite ? constraints.maxWidth : s.width,
        s.height));
  }

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    final (cc, x, rule) = _place(constraints, (l) {
      c.layout(l, parentUsesSize: true);
      return c.size.width;
    });
    _rule = rule;
    c.layout(cc, parentUsesSize: true);
    final s = c.size;
    final w = constraints.maxWidth.isFinite ? constraints.maxWidth : s.width;
    final start = _textDirection == TextDirection.ltr ? x : w - x - s.width;
    (c.parentData! as BoxParentData).offset = Offset(start, 0);
    size = constraints.constrain(Size(w, s.height));
  }
}
