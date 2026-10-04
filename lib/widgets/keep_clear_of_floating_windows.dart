/// Keeps the rect of its child in Android's keep-clear request while it is
/// on the page, and takes it back out when it leaves.
///
/// WHY: 停止 sat under Google Maps' picture-in-picture window and her tap
/// went to Maps (lib/services/keep_clear.dart says what was measured, and
/// what Android does and does not do with the request).
///
/// The rect follows the child. It is measured after a frame whenever this
/// widget builds or its page scrolls, and sent only when it changed, so a
/// still page sends nothing. Every instance on screen is sent together,
/// because the platform call replaces the whole set.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/keep_clear.dart';

class KeepClearOfFloatingWindows extends StatefulWidget {
  const KeepClearOfFloatingWindows({super.key, required this.child});

  final Widget child;

  static final Map<_KeepClearState, Rect> _live = {};
  static List<Rect> _lastSent = const [];

  static void _send() {
    final rects = _live.values.toList(growable: false);
    if (_sameRects(rects, _lastSent)) return;
    _lastSent = rects;
    // Not awaited: the answer only says whether Android was asked, and no
    // frame waits on it.
    unawaited(KeepClear.setRects(rects));
  }

  static bool _sameRects(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  State<KeepClearOfFloatingWindows> createState() => _KeepClearState();
}

class _KeepClearState extends State<KeepClearOfFloatingWindows> {
  ScrollPosition? _position;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_schedule);
      _position = position;
      _position?.addListener(_schedule);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_schedule);
    _position = null;
    if (KeepClearOfFloatingWindows._live.remove(this) != null) {
      KeepClearOfFloatingWindows._send();
    }
    super.dispose();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _measure();
    });
  }

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject();
    final view = View.maybeOf(context);
    if (box is! RenderBox || !box.attached || !box.hasSize || view == null) {
      return;
    }
    final logical = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    final dpr = view.devicePixelRatio;
    // Outward to whole pixels, so the request never falls short of the
    // control's edge.
    final physical = Rect.fromLTRB(
      (logical.left * dpr).floorToDouble(),
      (logical.top * dpr).floorToDouble(),
      (logical.right * dpr).ceilToDouble(),
      (logical.bottom * dpr).ceilToDouble(),
    );
    if (KeepClearOfFloatingWindows._live[this] == physical) return;
    KeepClearOfFloatingWindows._live[this] = physical;
    KeepClearOfFloatingWindows._send();
  }

  @override
  Widget build(BuildContext context) {
    _schedule();
    return widget.child;
  }
}
