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
///   one withdrawal-width plus [spacing] left of the row's end, in every
///   consent state. His thumb keeps its place.
/// - RESERVED END, everywhere else, and wherever PIN would come within
///   [clearance] of the end column: start-aligned, its width capped so its
///   right edge stays [clearance] left of the widest of 停止 and 閉じる at this
///   text size. Its label wraps if it must.
/// The end column is read from real buttons laid out here with the same
/// labels, never from a number: the separation is horizontal by
/// construction, whatever the face, the status line's height, or whether the
/// map-return control moved the card. The stop-spot guard
/// (test/support/d8_stop_spot_guard.dart) measures the real 停止 against the
/// real share control at every covered size, so a divergence between those
/// buttons and the real 停止 turns it red.
///
/// The measuring buttons are laid out and nothing else: not painted, not hit
/// tested, not in the semantics tree, not focusable, and invisible to the
/// test finders, which treat them as offstage.
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

/// The not-sharing row: [share] placed by PIN or RESERVED END, measured
/// against [withdrawLabel], [stopLabel] and [closeLabel] drawn as the real
/// buttons draw them.
class ShareStartRow extends MultiChildRenderObjectWidget {
  ShareStartRow({
    super.key,
    required Widget share,
    required String withdrawLabel,
    required String stopLabel,
    required String closeLabel,
    this.clearance = kStopSpotClearance,
    this.spacing = 8,
  }) : super(children: [
          share,
          _measure(withdrawLabel),
          _measure(stopLabel),
          _measure(closeLabel),
        ]);

  /// The edge-to-edge clearance from the end column.
  final double clearance;

  /// The spacing code 15's row had between its two buttons.
  final double spacing;

  static Widget _measure(String label) => ExcludeFocus(
        child: TextButton(onPressed: null, child: Text(label)),
      );

  @override
  RenderShareStartRow createRenderObject(BuildContext context) =>
      RenderShareStartRow(
        clearance: clearance,
        spacing: spacing,
        textDirection: Directionality.of(context),
      );

  @override
  void updateRenderObject(
      BuildContext context, RenderShareStartRow renderObject) {
    renderObject
      ..clearance = clearance
      ..spacing = spacing
      ..textDirection = Directionality.of(context);
  }

  @override
  MultiChildRenderObjectElement createElement() => _ShareStartRowElement(this);
}

/// The measuring buttons are offstage to the test finders, as they are to
/// her: only the share control is "on stage".
class _ShareStartRowElement extends MultiChildRenderObjectElement {
  _ShareStartRowElement(super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    if (children.isNotEmpty) visitor(children.first);
  }
}

class _ShareStartRowParentData extends ContainerBoxParentData<RenderBox> {}

/// Lays out four children: the share control, then the withdrawal, 停止 and
/// 閉じる measuring buttons. Paints, hit tests and describes the first only.
class RenderShareStartRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ShareStartRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ShareStartRowParentData> {
  RenderShareStartRow({
    required double clearance,
    required double spacing,
    required TextDirection textDirection,
  })  : _clearance = clearance,
        _spacing = spacing,
        _textDirection = textDirection;

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

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ShareStartRowParentData) {
      child.parentData = _ShareStartRowParentData();
    }
  }

  RenderBox get _share => firstChild!;
  RenderBox get _withdraw => childAfter(_share)!;
  RenderBox get _stop => childAfter(_withdraw)!;
  RenderBox get _close => childAfter(_stop)!;

  /// The placement for [constraints]: the share control's constraints, its
  /// start x (left to right), and the rule.
  (BoxConstraints, double, ShareStartRule) _place(
    BoxConstraints constraints,
    Size Function(RenderBox, BoxConstraints) size,
  ) {
    final w = constraints.maxWidth;
    if (!w.isFinite) {
      // Unbounded: nothing to align against. Start-aligned, natural width.
      return (constraints.loosen(), 0, ShareStartRule.reservedEnd);
    }
    final loose = BoxConstraints(maxWidth: w);
    final withdrawW = size(_withdraw, loose).width;
    final endColumn =
        math.max(size(_stop, loose).width, size(_close, loose).width);
    final shareW = size(_share, loose).width;
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
    final (c, _, _) = _place(constraints, ChildLayoutHelper.dryLayoutChild);
    final s = _share.getDryLayout(c);
    return constraints.constrain(Size(
        constraints.maxWidth.isFinite ? constraints.maxWidth : s.width,
        s.height));
  }

  @override
  void performLayout() {
    Size layout(RenderBox child, BoxConstraints c) =>
        ChildLayoutHelper.layoutChild(child, c);
    final (c, x, rule) = _place(constraints, layout);
    _rule = rule;
    final s = layout(_share, c);
    final w = constraints.maxWidth.isFinite ? constraints.maxWidth : s.width;
    final start = _textDirection == TextDirection.ltr ? x : w - x - s.width;
    (_share.parentData! as _ShareStartRowParentData).offset = Offset(start, 0);
    for (final m in [_withdraw, _stop, _close]) {
      (m.parentData! as _ShareStartRowParentData).offset = Offset.zero;
    }
    size = constraints.constrain(Size(w, s.height));
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _share.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _share.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _share.getMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _share.getMaxIntrinsicHeight(width);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final d = _share.getDistanceToActualBaseline(baseline);
    if (d == null) return null;
    return d + (_share.parentData! as _ShareStartRowParentData).offset.dy;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final pd = _share.parentData! as _ShareStartRowParentData;
    context.paintChild(_share, offset + pd.offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final pd = _share.parentData! as _ShareStartRowParentData;
    return result.addWithPaintOffset(
      offset: pd.offset,
      position: position,
      hitTest: (result, transformed) =>
          _share.hitTest(result, position: transformed),
    );
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) =>
      visitor(_share);
}
