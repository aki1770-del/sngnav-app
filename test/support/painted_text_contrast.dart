/// The contrast of what is actually painted: every paragraph in the tree, in
/// its own colour, against the fill behind it.
///
/// WHY (2026-09-15). Two chips drew their words at 2.38:1 against the app's
/// own 4.5:1 floor. The count that named them came from one colour pair, and
/// it missed the same amber on two more surfaces she can reach. A floor held
/// constant by constant only covers the constants someone thought of. This
/// reads the render tree instead: each [RenderParagraph]'s span colours,
/// composited over the nearest filled ancestor (a box decoration, a Material
/// or Card surface, a [ColoredBox]).
///
/// Bounds, so no reader takes this for more than it is:
/// * Text inside the map is not measured. Its ground is tiles, not a fill.
/// * The text of an inactive control is returned with [PaintedText.inactive]
///   set and is not held to the floor: WCAG 2.x 1.4.3 exempts inactive user
///   interface components.
/// * A paragraph whose ground cannot be found is returned with a null
///   [PaintedText.ground]. A floor check must fail on it rather than assume a
///   ground.
/// * Colours are the framework's, as handed to the painter. A phone panel's
///   brightness, glare and antialiasing are not in this number.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart' show FlutterMap;
import 'package:flutter_test/flutter_test.dart';

/// The app's accessibility floor for text (WCAG 2.x AA).
const double kTextContrastFloor = 4.5;

/// The floor for an icon glyph (WCAG 2.x 1.4.11, non-text contrast).
const double kIconContrastFloor = 3.0;

double _linear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b);

/// WCAG 2.x contrast ratio of two opaque colours.
double contrastRatio(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// One run of painted text and what it was painted on.
class PaintedText {
  const PaintedText({
    required this.text,
    required this.isIcon,
    required this.foreground,
    required this.ground,
    required this.fontSize,
    required this.key,
    required this.inactive,
  });

  final String text;

  /// A single glyph from the icon font's private-use range.
  final bool isIcon;
  final Color foreground;

  /// The opaque fill behind the text, or null when none was found.
  final Color? ground;
  final double? fontSize;

  /// The nearest ancestor `Key('...')`, or `-`.
  final String key;

  /// Inside a control that cannot be used right now.
  final bool inactive;

  double get floor => isIcon ? kIconContrastFloor : kTextContrastFloor;

  /// Null when the ground is unknown.
  double? get ratio => ground == null
      ? null
      : contrastRatio(Color.alphaBlend(foreground, ground!), ground!);

  bool get belowFloor => ratio != null && ratio! < floor;

  String describe() {
    final shown = isIcon
        ? 'icon U+${text.runes.first.toRadixString(16)}'
        : '「${text.replaceAll('\n', '⏎')}」';
    return '${ratio == null ? 'ground unknown' : '${ratio!.toStringAsFixed(2)}:1'}'
        ' (floor ${floor.toStringAsFixed(1)}) ${_hex(foreground)} on '
        '${ground == null ? '?' : _hex(ground!)}, ${fontSize ?? '?'} px, '
        'key $key: $shown';
  }
}

Color? _fillOf(RenderObject ro) {
  if (ro is RenderDecoratedBox &&
      ro.position == DecorationPosition.background) {
    final d = ro.decoration;
    if (d is BoxDecoration && d.color != null) return d.color;
    if (d is ShapeDecoration && d.color != null) return d.color;
  }
  if (ro is RenderPhysicalModel) return ro.color;
  if (ro is RenderPhysicalShape) return ro.color;
  if (ro.runtimeType.toString() == '_RenderColoredBox') {
    return (ro as dynamic).color as Color;
  }
  return null;
}

Color? _groundOf(RenderObject ro) {
  final fills = <Color>[];
  RenderObject? p = ro.parent;
  while (p != null) {
    final f = _fillOf(p);
    if (f != null && f.a > 0) {
      fills.add(f);
      if (f.a >= 1.0) break;
    }
    p = p.parent;
  }
  if (fills.isEmpty || fills.last.a < 1.0) return null;
  var ground = fills.removeLast();
  for (final f in fills.reversed) {
    ground = Color.alphaBlend(f, ground);
  }
  return ground;
}

Element? _elementOf(RenderObject ro) {
  final creator = ro.debugCreator;
  return creator is DebugCreator ? creator.element : null;
}

String _nearestKey(Element? e) {
  var found = '-';
  e?.visitAncestorElements((a) {
    final k = a.widget.key;
    if (k is ValueKey<String>) {
      found = k.value;
      return false;
    }
    return true;
  });
  return found;
}

bool _insideInactiveControl(Element? e) {
  var inactive = false;
  e?.visitAncestorElements((a) {
    final w = a.widget;
    // A DropdownButton<T> is read through dynamic: its onChanged is typed on T,
    // and reading it as DropdownButton<dynamic> fails Dart's covariance check.
    if ((w is ButtonStyleButton && !w.enabled) ||
        (w is IconButton && w.onPressed == null) ||
        (w is DropdownButton && (w as dynamic).onChanged == null)) {
      inactive = true;
      return false;
    }
    return true;
  });
  return inactive;
}

void _spans(InlineSpan span, TextStyle? inherited,
    void Function(String text, TextStyle? style) out) {
  if (span is! TextSpan) return;
  final style = inherited == null ? span.style : inherited.merge(span.style);
  if ((span.text ?? '').isNotEmpty) out(span.text!, style);
  for (final child in span.children ?? const <InlineSpan>[]) {
    _spans(child, style, out);
  }
}

/// Every run of text painted on the current screen outside the map.
List<PaintedText> paintedTextOutsideMap(WidgetTester tester) {
  final inMap = <RenderObject>{
    for (final e in find
        .descendant(of: find.byType(FlutterMap), matching: find.byType(RichText))
        .evaluate())
      e.renderObject!,
  };
  final out = <PaintedText>[];
  for (final ro in tester.allRenderObjects.whereType<RenderParagraph>().toSet()) {
    if (inMap.contains(ro)) continue;
    final element = _elementOf(ro);
    final ground = _groundOf(ro);
    final key = _nearestKey(element);
    final inactive = _insideInactiveControl(element);
    _spans(ro.text, null, (text, style) {
      final fg = style?.foreground?.color ?? style?.color;
      if (fg == null || text.trim().isEmpty) return;
      final runes = text.runes;
      out.add(PaintedText(
        text: text,
        isIcon: runes.length == 1 && runes.first >= 0xE000 && runes.first <= 0xF8FF,
        foreground: fg,
        ground: ground,
        fontSize: style?.fontSize,
        key: key,
        inactive: inactive,
      ));
    });
  }
  return out;
}
