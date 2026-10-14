/// The stop-spot guard's instrument: after 停止 nothing takes its place under
/// his finger, and after 現在地を共有 nothing takes that place either (code 16,
/// 2026-10-14).
///
/// WHY, written before the act. On code 15 the control drawn under 停止's
/// centre in the very next frame is 共有の同意を取り消す: 64.4% of 停止's
/// target, measured from the API 29 emulator's layout dumps (2026-10-13). A
/// second press takes back his consent and nothing tells him. Sakichi Vision
/// 15: "best is *cannot be done wrong*; next is *detected instantly*; worst is
/// *found downstream*". Vision 9: "The operator must not be the last line of
/// defense against defects — the machine itself must catch them."
///
/// WHAT IT MEASURES, as the screen review set the number (2026-10-14):
/// - FROM the tapped control's padded hit rectangle, read from the WIDGET tree
///   in the frame before the tap. Never from the semantics tree: there the map
///   card's own node covers all of 停止's target, so a guard reading it is red
///   forever or must exclude containers, and an exclusion is how a guard goes
///   blind (the consent review, 2026-10-13);
/// - TO every interactive control's hit rectangle in the next frame, and again
///   once the frames after the tap have settled;
/// - edge to edge, at least [kD8ClearanceDp] = 24 dp: half the platform's
///   48 dp minimum target, as one press's reach beyond a target it credited.
///
/// THE TRANSITIONS, named so a result says which one:
/// - T1: 停止 with a share running -> not sharing.
/// - T1c: 閉じる (停止's key and handler after a refusal) -> not sharing.
/// - T1r: 停止 while the map-return control is drawn above it -> not sharing.
/// - T2: 現在地を共有 with a yes held -> sharing.
/// - T2r: the same with follow paused, so the return control appears in that
///   frame over the share control's former place. Allowed for that one
///   control only, and earned: the effect grid runs there, and a mutant that
///   gives it a consequential handler must turn the guard red.
/// - T3: 共有の同意を取り消す -> its note.
///
/// WHAT COUNTS AS A CONTROL, stated so no exclusion is silent: a widget a tap
/// acts on. [ButtonStyleButton] (TextButton, OutlinedButton and their kin),
/// [IconButton], [InkResponse] (InkWell), a [GestureDetector] with a tap
/// callback, [Checkbox], [Switch], [Slider] and editable text, when enabled.
/// NOT counted: [RawGestureDetector] and [Listener], the gesture SURFACES the
/// map and the page's scroll are built from. The map sits 8 dp above the
/// status row on every build and a touch on it only pauses follow. A surface
/// is not a control; the effect grid ([d8EffectGrid]) is what finds a handler
/// a rectangle cannot, by tapping the real tree and reading what changed.
///
/// BOUNDS, riding every result: a test binding, not a phone; the faces are the
/// host's (render_see_env.dart); taps are injected at exact points, not a
/// gloved finger; 24 dp is an inference from the SDK's 48 dp, not a
/// measurement of a hand.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/akita_map.dart' show AkitaMap;
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/code15_fix_interval_record.dart';
import 'package:sngnav_app/services/location_consent.dart';
import 'package:sngnav_app/services/notification_permission.dart';

import '../render_see/render_see_env.dart';
import 'fake_alert_actuators.dart';
import 'test_record_writer.dart';

/// The clearance, edge to edge (the screen review, 2026-10-14).
const double kD8ClearanceDp = 24.0;

/// A window: its size in physical pixels and the insets the app is told of.
class D8Frame {
  const D8Frame(this.name, this.physical, this.insetTop, this.insetBottom);
  final String name;
  final Size physical;
  final double insetTop;
  final double insetBottom;
}

/// The frame the screen review ruled the sweep in, and the one the app's
/// first-screen tests use: 1080 x 2340 px, the status bar and the navigation
/// bar reported as 73 and 130 px of padding.
const D8Frame kD8Edge = D8Frame('2340/73/130', Size(1080, 2340), 73, 130);

/// The API 29 emulator's window as its layout dump shows it: 1080 x 2208 px,
/// ending above the navigation bar, with a 66 px status bar (app bar 0 to 80
/// dp). The consent dialog sits lower in this window than in [kD8Edge], so the
/// dialog check runs in both and the worse one governs.
const D8Frame kD8Api29Window = D8Frame('2208/66/0', Size(1080, 2208), 66, 0);

/// The three widths: 360, 392.7 and 411.4 dp, each 1080 px wide at its own
/// density.
const List<double> kD8Dprs = [3.0, 2.75, 2.625];

/// Text scale 1.00 to 2.00 in 0.05 steps: a four-scale sample hides the worst
/// cases between its samples (measured by the screen review at 0.01 steps).
final List<double> kD8Scales = [
  for (var i = 0; i <= 20; i++) (100 + 5 * i) / 100,
];

/// The control the guard allows inside the clearance in T2r, and only there.
const String kD8ReturnControlKey = 'her-map-return-to-position';

/// One geometry of the sweep.
class D8Geometry {
  const D8Geometry(this.lang, this.dpr, this.scale, {this.frame = kD8Edge});
  final String lang;
  final double dpr;
  final double scale;
  final D8Frame frame;
  Size get physical => frame.physical;
  double get widthDp => physical.width / dpr;
  double get heightDp => physical.height / dpr;
  D8Geometry inFrame(D8Frame f) => D8Geometry(lang, dpr, scale, frame: f);
  String get label =>
      '$lang ${widthDp.toStringAsFixed(1)}x'
      '${heightDp.toStringAsFixed(1)}dp x${scale.toStringAsFixed(2)} [${frame.name}]';
}

/// Sets the view to [g] and loads a real face: a Japanese face for ja,
/// Roboto for en. Returns whether the face loaded.
Future<bool> d8SetGeometry(WidgetTester tester, D8Geometry g) async {
  final faceLoaded =
      await tester.runAsync(
        () => loadDiscoveredFace(
          'Roboto',
          g.lang == 'ja' ? FaceSearch.japanese : FaceSearch.roboto,
        ),
      ) ??
      false;
  tester.view.devicePixelRatio = g.dpr;
  tester.view.physicalSize = g.physical;
  tester.view.padding = FakeViewPadding(
    top: g.frame.insetTop,
    bottom: g.frame.insetBottom,
  );
  tester.view.viewPadding = FakeViewPadding(
    top: g.frame.insetTop,
    bottom: g.frame.insetBottom,
  );
  tester.platformDispatcher.textScaleFactorTestValue = g.scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  return faceLoaded;
}

/// One control found in the frame.
class D8Control {
  D8Control(this.name, this.rect);
  final String name;
  final Rect rect;
  @override
  String toString() => '$name ${d8Rect(rect)}';
}

String d8Rect(Rect r) =>
    '[${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)}]'
    '[${r.right.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)}]';

/// Whether a tap acts on [w]. See the library comment for what is not counted.
bool d8IsControl(Widget w) {
  if (w is ButtonStyleButton) return w.enabled;
  if (w is IconButton) return w.onPressed != null || w.onLongPress != null;
  if (w is InkResponse) {
    return w.onTap != null ||
        w.onTapDown != null ||
        w.onTapUp != null ||
        w.onLongPress != null ||
        w.onDoubleTap != null ||
        w.onSecondaryTap != null;
  }
  if (w is GestureDetector) {
    return w.onTap != null ||
        w.onTapDown != null ||
        w.onTapUp != null ||
        w.onLongPress != null ||
        w.onDoubleTap != null ||
        w.onSecondaryTap != null;
  }
  if (w is Checkbox) return w.onChanged != null;
  if (w is Switch) return w.onChanged != null;
  if (w is Slider) return w.onChanged != null;
  if (w is EditableText) return !w.readOnly;
  return false;
}

/// The key a control is known by: its own, else the nearest keyed ancestor,
/// so a button's inner InkWell and GestureDetector are named for the button
/// (measured: an OutlinedButton.icon holds them more than 32 levels down).
String _ownerKey(Element e) {
  // The framework keys its own InkWell internals ("ink renderer"): never a
  // name a control is known by.
  String? describe(Key? k) => switch (k) {
    ValueKey<String>(:final value) => value,
    LabeledGlobalKey() when !'$k'.contains('ink renderer') => '$k',
    _ => null,
  };
  var found = describe(e.widget.key);
  if (found != null) return found;
  var depth = 0;
  e.visitAncestorElements((a) {
    found = describe(a.widget.key);
    return found == null && ++depth < 64;
  });
  return found ?? '';
}

String _nameOf(Element e) {
  final w = e.widget;
  String? label;
  void visit(Element c) {
    if (label != null) return;
    final cw = c.widget;
    if (cw is Text && cw.data != null) {
      label = cw.data;
    } else if (cw is RichText) {
      // An Icon is a RichText of one private-use glyph: not a label.
      final t = cw.text.toPlainText().replaceAll(RegExp('[\uE000-\uF8FF]'), '');
      if (t.isNotEmpty) label = t;
    } else {
      c.visitChildElements(visit);
    }
  }

  e.visitChildElements(visit);
  final k = _ownerKey(e);
  final shown = label?.replaceAll(' ', ' ').replaceAll('⁠', '');
  return '${w.runtimeType}${k.isEmpty ? '' : '($k)'}'
      '${shown == null ? '' : ' "$shown"'}';
}

/// Her screen in logical pixels: the window above the navigation bar.
Rect d8Screen(WidgetTester tester) {
  final view = tester.view;
  return Rect.fromLTRB(
    0,
    0,
    view.physicalSize.width / view.devicePixelRatio,
    (view.physicalSize.height - view.padding.bottom) / view.devicePixelRatio,
  );
}

/// Every interactive control on her screen in this frame, read from the
/// widget tree, with its padded hit rectangle.
List<D8Control> d8ControlsOnScreen(WidgetTester tester) {
  final screen = d8Screen(tester);
  final out = <D8Control>[];
  for (final e in find.byWidgetPredicate(d8IsControl).evaluate()) {
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
    final rect = ro.localToGlobal(Offset.zero) & ro.size;
    if (!rect.overlaps(screen)) continue;
    out.add(D8Control(_nameOf(e), rect));
  }
  return out;
}

/// Edge-to-edge distance between two rectangles, as the screen review's model
/// computes it: the separation on the separating axis, the corner distance
/// when separated on both, negative when they intersect.
double d8EdgeGap(Rect a, Rect b) {
  final dx = math.max(b.left - a.right, a.left - b.right);
  final dy = math.max(b.top - a.bottom, a.top - b.bottom);
  if (dx < 0 && dy < 0) return math.max(dx, dy);
  if (dx >= 0 && dy >= 0) return math.sqrt(dx * dx + dy * dy);
  return math.max(dx, dy);
}

/// One transition's measurement.
class D8Transition {
  D8Transition(this.name, this.geometry, this.from, this.after);
  final String name;
  final D8Geometry geometry;
  final Rect from;
  final List<D8Control> after;

  /// The nearest control after the tap, and its gap.
  (D8Control?, double) get nearest {
    D8Control? best;
    var gap = double.infinity;
    for (final c in after) {
      final g = d8EdgeGap(from, c.rect);
      if (g < gap) {
        gap = g;
        best = c;
      }
    }
    return (best, gap);
  }

  /// The nearest control whose key is not in [allowed].
  (D8Control?, double) nearestExcept(Set<String> allowed) {
    D8Control? best;
    var gap = double.infinity;
    for (final c in after) {
      if (allowed.any((k) => c.name.contains('($k)'))) continue;
      final g = d8EdgeGap(from, c.rect);
      if (g < gap) {
        gap = g;
        best = c;
      }
    }
    return (best, gap);
  }

  /// Every control closer than [kD8ClearanceDp], except those whose key is
  /// in [allowed].
  List<String> violations({Set<String> allowed = const {}}) => [
    for (final c in after)
      if (d8EdgeGap(from, c.rect) < kD8ClearanceDp &&
          !allowed.any((k) => c.name.contains('($k)')))
        '$name ${geometry.label}: ${c.name} at '
            '${d8EdgeGap(from, c.rect).toStringAsFixed(1)} dp from the '
            'former target ${d8Rect(from)}',
  ];

  String line({Set<String> allowed = const {}}) {
    final (c, g) = allowed.isEmpty ? nearest : nearestExcept(allowed);
    final over = c == null ? null : from.intersect(c.rect);
    final share = over == null || over.width <= 0 || over.height <= 0
        ? ''
        : ', overlapping ${(100 * over.width * over.height / (from.width * from.height)).toStringAsFixed(1)}% '
              'of the former target, its centre ${c!.rect.contains(from.center) ? 'INSIDE' : 'outside'}';
    return 'D8 $name ${geometry.label}: from ${d8Rect(from)} nearest '
        '${g.toStringAsFixed(1)} dp ${c?.name ?? '(no control on screen)'}$share';
  }
}

/// Counts every share the app starts: the thing consent gates.
class D8ShareSource {
  int starts = 0;
  final List<StreamController<PositionFix>> _streams = [];
  StreamController<PositionFix>? get current =>
      _streams.isEmpty ? null : _streams.last;
  Stream<PositionFix> call() {
    starts++;
    final c = StreamController<PositionFix>.broadcast();
    _streams.add(c);
    return c.stream;
  }

  Future<void> closeAll() async {
    for (final c in _streams) {
      await c.close();
    }
  }
}

final DateTime kD8Clock = DateTime.utc(2026, 1, 14, 21);

/// A trusted fix at Akita, 12 m.
PositionAvailable d8Fix() => PositionAvailable(
  latitude: 39.7186,
  longitude: 140.1024,
  accuracyMeters: 12,
  timestamp: kD8Clock,
);

/// The platform's typed refusal: the share row then offers 閉じる.
const PositionUnavailable kD8Refusal = PositionUnavailable(
  'Location permission denied',
  cause: PositionUnavailableCause.permissionDenied,
);

/// The harness's temp directory, and the path_provider and notification
/// mocks. The phone CAN post her a notification, as his does on code 15, so
/// the drive sentences are the true promise and a share runs with its service.
class D8Env {
  late Directory tmp;

  void setUp() {
    tmp = Directory.systemTemp.createTempSync('sngnav_stop_spot_guard');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
    m.setMockMethodCallHandler(
      NotificationPermission.channel,
      (MethodCall call) async => call.method == 'read'
          ? <String, Object>{
              'granted': true,
              'enabled': true,
              'needsRuntimeRequest': false,
            }
          : true,
    );
  }

  void tearDown() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    m.setMockMethodCallHandler(NotificationPermission.channel, null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  }

  File get consentFile => File('${tmp.path}/${LocationConsentStore.fileName}');
}

/// One launch of the real app.
class D8App {
  D8App(this.env, this.geometry);
  final D8Env env;
  final D8Geometry geometry;
  final shares = D8ShareSource();
  int settingsOpened = 0;
  late Code15FixIntervalRecord record;

  AppL10n get l => AppL10n(Locale(geometry.lang));

  /// [heldYes] seeds "she already agreed" through the app's own seam
  /// (HomePage.locationConsent); null asks her, as production does.
  Future<void> launch(WidgetTester tester, {bool? heldYes = true}) async {
    // The last launch's fire-and-forget consent write lands here, not inside
    // this launch's measurement.
    await tester.pumpWidget(const SizedBox.shrink());
    await settleIO(tester, rounds: 10);
    if (env.consentFile.existsSync()) env.consentFile.deleteSync();
    final dir = Directory('${env.tmp.path}/support')
      ..createSync(recursive: true);
    for (final f in dir.listSync()) {
      f.deleteSync(recursive: true);
    }
    record = Code15FixIntervalRecord(writer: kTestRecordWriter, directory: dir);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      SngnavApp(
        locale: Locale(geometry.lang),
        actuators: FakeAlertActuators(),
        clock: () => kD8Clock,
        jmaFetch: () async => const JmaFailure('test: no observation'),
        positionSource: shares.call,
        code15Record: record,
        locationConsent: heldYes,
        openPlatformSettings: () async {
          settingsOpened++;
          return true;
        },
      ),
    );
    await settle(tester, frames: 8);
  }

  Finder get shareButton => find.byKey(const Key('share-location-button'));
  Finder get withdraw => find.byKey(const Key('location-consent-withdraw'));
  Finder get withdrawnNote =>
      find.byKey(const Key('location-consent-withdrawn-note'));
  Finder get returnControl => find.byKey(const Key(kD8ReturnControlKey));
  Finder get stop =>
      find.ancestor(of: find.text(l.stop), matching: find.byType(TextButton));
  Finder get close =>
      find.ancestor(of: find.text(l.close), matching: find.byType(TextButton));

  /// Brings [f] onto her screen as she would scroll to it: no scroll when it
  /// is already whole on screen, else the least scroll that shows it, 8 dp
  /// clear of the navigation bar (the rule the app's own
  /// _bringDriveStopIntoView uses for 停止).
  Future<void> reveal(WidgetTester tester, Finder f) async {
    final rect = tester.getRect(f);
    final scrollable = find
        .ancestor(of: f, matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    final viewTop = tester.getRect(scrollable).top;
    final screenBottom = d8Screen(tester).bottom;
    if (rect.top >= viewTop && rect.bottom <= screenBottom) return;
    final target = rect.bottom > screenBottom
        ? position.pixels + rect.bottom - screenBottom + 8
        : position.pixels - (viewTop - rect.top);
    position.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    await tester.pump();
  }

  /// Taps the centre of [f], as a press on it lands, and pumps the next frame
  /// only. Returns [f]'s rectangle in the frame before the tap.
  Future<Rect> tapAndNextFrame(WidgetTester tester, Finder f) async {
    final rect = tester.getRect(f);
    await tester.tapAt(rect.center);
    await tester.pump();
    return rect;
  }

  /// Lets the frames after a tap settle, never past a 2 s bound.
  Future<void> settle(WidgetTester tester, {int frames = 6}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Lets real file IO land (the consent store's reads and writes), without
  /// advancing the fake clock.
  Future<void> settleIO(WidgetTester tester, {int rounds = 25}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  /// A finger on her map: follow pauses (main.dart _onHerMapTouched).
  Future<void> pauseFollow(WidgetTester tester) async {
    final map = find.byType(AkitaMap);
    final g = await tester.startGesture(tester.getRect(map).center);
    await tester.pump(const Duration(milliseconds: 40));
    await g.up();
    await tester.pump(const Duration(milliseconds: 400));
  }

  bool navigatorCanPop(WidgetTester tester) {
    final nav = find.byType(Navigator);
    if (nav.evaluate().isEmpty) return false;
    return tester.state<NavigatorState>(nav.first).canPop();
  }

  /// The record's `end` lines for [share].
  int endLines(int share) => record
      .readAll()
      .split('\n')
      .where((l) => RegExp('^s=$share t=\\d+ k=end\$').hasMatch(l))
      .length;
}

/// What a stray tap must not change: her consent (field and store), her share,
/// the route stack (no route, no dialog), the system settings, and the record.
class D8Snapshot {
  D8Snapshot(this.app, WidgetTester tester)
    : shares = app.shares.starts,
      canPop = app.navigatorCanPop(tester),
      dialogs = find.byType(Dialog).evaluate().length,
      withdrawDrawn = app.withdraw.evaluate().isNotEmpty,
      noteDrawn = app.withdrawnNote.evaluate().isNotEmpty,
      stopDrawn =
          app.stop.evaluate().isNotEmpty || app.close.evaluate().isNotEmpty,
      settingsOpened = app.settingsOpened,
      recordLines = _withoutAlive(app.record.readAll()),
      consentExists = app.env.consentFile.existsSync();
  final D8App app;
  final int shares;
  final bool canPop;
  final int dialogs;
  final bool withdrawDrawn;
  final bool noteDrawn;
  final bool stopDrawn;
  final int settingsOpened;
  final String recordLines;
  final bool consentExists;

  /// The alive timer writes `alive` while a share is quiet; that is the
  /// share running, not a tap's effect.
  static String _withoutAlive(String text) =>
      text.split('\n').where((l) => !l.contains(' k=alive')).join('\n');

  /// Every difference from [before], named.
  List<String> differences(D8Snapshot before) => [
    if (shares != before.shares)
      'a share started (${before.shares} -> $shares)',
    if (canPop != before.canPop)
      'a route was pushed (canPop ${before.canPop} -> $canPop)',
    if (dialogs != before.dialogs)
      'a dialog appeared (${before.dialogs} -> $dialogs)',
    if (withdrawDrawn != before.withdrawDrawn)
      'consent changed (withdrawal drawn ${before.withdrawDrawn} -> $withdrawDrawn)',
    if (noteDrawn != before.noteDrawn)
      'consent changed (withdrawn note ${before.noteDrawn} -> $noteDrawn)',
    if (stopDrawn != before.stopDrawn)
      'the share changed (停止 drawn ${before.stopDrawn} -> $stopDrawn)',
    if (settingsOpened != before.settingsOpened)
      'the system settings were opened',
    if (recordLines != before.recordLines) 'a record line was written',
    if (consentExists != before.consentExists) 'the consent store was written',
  ];
}

/// The effect grid: taps a 9 x 7 grid over [target] (1 dp inside its edges),
/// one point at a time, pumping the next frame after each, and returns what
/// the first tap that changed anything changed. Empty when nothing changed.
/// Rectangles find controls; this finds any handler.
Future<List<String>> d8EffectGrid(
  WidgetTester tester,
  D8App app,
  Rect target,
  String what,
) async {
  final before = D8Snapshot(app, tester);
  final inner = target.deflate(1);
  for (var j = 0; j < 7; j++) {
    for (var i = 0; i < 9; i++) {
      final p = Offset(
        inner.left + inner.width * i / 8,
        inner.top + inner.height * j / 6,
      );
      await tester.tapAt(p);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final diff = D8Snapshot(app, tester).differences(before);
      if (diff.isNotEmpty) {
        return [
          '$what ${app.geometry.label}: a tap at (${p.dx.toStringAsFixed(1)},'
              '${p.dy.toStringAsFixed(1)}) inside the former target '
              '${d8Rect(target)}: ${diff.join('; ')}',
        ];
      }
    }
  }
  // The consent store is written fire-and-forget: let real IO land, then read.
  await app.settleIO(tester, rounds: 10);
  final diff = D8Snapshot(app, tester).differences(before);
  return diff.isEmpty
      ? const []
      : ['$what ${app.geometry.label}: after the grid: ${diff.join('; ')}'];
}

/// Everything one geometry measured: every line, and every failure.
class D8Result {
  final List<String> lines = [];

  /// The row checks: every transition, effect grid, `end` pin and positive
  /// control. These are D-8's own and bind code 16.
  final List<String> failures = [];

  /// S-3 WHOLE: an answer of the consent dialog lies under 現在地を共有's
  /// place, in either window. Carried as its own requirement (the Chair,
  /// 2026-10-14); its red lines are kept here, never dropped.
  final List<String> dialogFailures = [];

  /// The consent dialog's yes, as a share of 現在地を共有's place: the larger
  /// of the two windows. Null when the dialog was not measured, which is never
  /// a pass. S-3 NARROW compares it with code 15's.
  double? yesFraction;

  /// True only once the dialog was measured in both windows. S-3 WHOLE with
  /// nothing measured is never a pass (an aborted sequence D leaves it false).
  bool dialogMeasured = false;

  void fail(String s) => failures.add(s);
}

void _check(D8Result r, D8Transition t, {Set<String> allowed = const {}}) {
  r.lines.add(t.line(allowed: allowed));
  r.failures.addAll(t.violations(allowed: allowed));
}

/// Runs one sequence of the guard. An exception inside it is recorded as that
/// sequence's failure, never swallowed, and the next sequence still runs: on
/// a red tree a stray tap can end the share a later step expects, and one
/// abort must not leave the dialog check unmeasured.
Future<void> _sequence(
  D8Result r,
  String name,
  D8Geometry g,
  Future<void> Function() body,
) async {
  try {
    await body();
  } catch (e) {
    r.fail(
      'sequence $name ${g.label}: aborted: '
      '${e.toString().split('\n').first}',
    );
  }
}

/// The whole guard at one geometry, through the real HomePage: T2, T1 and T3
/// on one launch; T2r and T1r with follow paused; T1c after a refusal; the
/// effect grid after each; the `end` pin; and the consent dialog's answers
/// against 現在地を共有's place. Returns every line and every failure.
Future<D8Result> d8RunGeometry(
  WidgetTester tester,
  D8Env env,
  D8Geometry g,
) async {
  final r = D8Result();
  if (!await d8SetGeometry(tester, g)) {
    r.fail(
      '${g.label}: no real face loaded, so this measures the test font: '
      'no verdict',
    );
    return r;
  }

  await _sequence(r, 'A', g, () async {
    // ---- A: a yes held, follow on: T2, T1, T3 -------------------------------
    var app = D8App(env, g);
    await app.launch(tester);
    await app.reveal(tester, app.shareButton);
    var from = await app.tapAndNextFrame(tester, app.shareButton);
    if (app.shares.starts != 1 || app.stop.evaluate().isEmpty) {
      r.fail(
        'T2 ${g.label}: control: the share did not start at the tap '
        '(starts ${app.shares.starts})',
      );
      return;
    }
    _check(r, D8Transition('T2', g, from, d8ControlsOnScreen(tester)));
    app.shares.current!.add(d8Fix());
    await app.settle(tester);
    _check(r, D8Transition('T2-settled', g, from, d8ControlsOnScreen(tester)));
    r.failures.addAll(await d8EffectGrid(tester, app, from, 'T2-grid'));

    await app.reveal(tester, app.stop);
    final share = 1;
    from = await app.tapAndNextFrame(tester, app.stop);
    _check(r, D8Transition('T1', g, from, d8ControlsOnScreen(tester)));
    // The `end` pin: his tap's `end`, written once, before the share is cleared.
    final ends = app.endLines(share);
    r.lines.add('D8 end-pin ${g.label}: $ends end line(s) for share $share');
    if (ends != 1) {
      r.fail(
        'end-pin ${g.label}: $ends `end` line(s) for share $share after 停止, '
        'expected exactly 1',
      );
    }
    r.failures.addAll(await d8EffectGrid(tester, app, from, 'T1-grid'));
    await app.settle(tester);
    _check(r, D8Transition('T1-settled', g, from, d8ControlsOnScreen(tester)));

    if (app.withdraw.evaluate().isEmpty) {
      // A tree where the grid already withdrew: measure T3 on a fresh launch.
      app = D8App(env, g);
      await app.launch(tester);
      await app.reveal(tester, app.shareButton);
      await app.tapAndNextFrame(tester, app.shareButton);
      app.shares.current!.add(d8Fix());
      await app.settle(tester);
      await app.reveal(tester, app.stop);
      await app.tapAndNextFrame(tester, app.stop);
      await app.settle(tester);
    }
    if (app.withdraw.evaluate().isEmpty) {
      r.fail(
        'T3 ${g.label}: the withdrawal is not drawn after 停止 with a yes held',
      );
    } else {
      await app.reveal(tester, app.withdraw);
      from = await app.tapAndNextFrame(tester, app.withdraw);
      if (app.withdrawnNote.evaluate().isEmpty) {
        r.fail(
          'T3 ${g.label}: control: no withdrawn note after the withdrawal',
        );
      }
      _check(r, D8Transition('T3', g, from, d8ControlsOnScreen(tester)));
      await app.settle(tester);
      _check(
        r,
        D8Transition('T3-settled', g, from, d8ControlsOnScreen(tester)),
      );
    }
    await app.shares.closeAll();
  });
  await _sequence(r, 'B', g, () async {
    // ---- B: follow paused: T2r, then T1r ------------------------------------
    var app = D8App(env, g);
    await app.launch(tester);
    await app.pauseFollow(tester);
    await app.reveal(tester, app.shareButton);
    var from = await app.tapAndNextFrame(tester, app.shareButton);
    final t2r = D8Transition('T2r', g, from, d8ControlsOnScreen(tester));
    _check(r, t2r, allowed: {kD8ReturnControlKey});
    // Positive control: the instrument finds a real intersection here, the
    // return control over the share control's former place, as code 15 has it.
    final ret = t2r.after.where(
      (c) => c.name.contains('($kD8ReturnControlKey)'),
    );
    if (ret.isEmpty) {
      r.fail(
        'T2r ${g.label}: positive control: the return control is not drawn '
        'after a share with follow paused, so T2r and T1r measured nothing',
      );
    } else {
      final gap = d8EdgeGap(from, ret.first.rect);
      r.lines.add(
        'D8 T2r-positive-control ${g.label}: the return control at '
        '${gap.toStringAsFixed(1)} dp from the share control\'s former place',
      );
      if (gap >= kD8ClearanceDp) {
        r.fail(
          'T2r ${g.label}: positive control: the return control is '
          '${gap.toStringAsFixed(1)} dp away; the instrument must find it '
          'inside $kD8ClearanceDp dp, or it may be blind',
        );
      }
    }
    app.shares.current!.add(d8Fix());
    await app.settle(tester);
    // The exception is earned: no consent, share, record, route or dialog
    // change from any tap over the share control's former place.
    r.failures.addAll(await d8EffectGrid(tester, app, from, 'T2r-grid'));
    // Positive control for the grid, where the return control lies inside the
    // grid: its taps reached the control's handler, so follow resumed and the
    // control is gone. Where it lies outside, no tap could reach it.
    final reachable =
        ret.isNotEmpty && ret.first.rect.overlaps(from.deflate(1));
    r.lines.add(
      'D8 T2r-grid-positive-control ${g.label}: the return control '
      '${reachable ? 'lies inside the grid' : 'lies outside the grid: not applicable'}',
    );
    if (reachable && app.returnControl.evaluate().isNotEmpty) {
      r.fail(
        'T2r-grid ${g.label}: positive control: no grid tap reached the '
        'return control, so the grid may not reach handlers',
      );
    }
    await app.pauseFollow(tester);
    if (app.returnControl.evaluate().isEmpty) {
      r.fail(
        'T1r ${g.label}: control: the return control is not drawn with '
        'follow paused during a share',
      );
    } else {
      await app.reveal(tester, app.stop);
      from = await app.tapAndNextFrame(tester, app.stop);
      _check(r, D8Transition('T1r', g, from, d8ControlsOnScreen(tester)));
      r.failures.addAll(await d8EffectGrid(tester, app, from, 'T1r-grid'));
      await app.settle(tester);
      _check(
        r,
        D8Transition('T1r-settled', g, from, d8ControlsOnScreen(tester)),
      );
    }
    await app.shares.closeAll();
  });
  await _sequence(r, 'C', g, () async {
    // ---- C: a refusal: T1c -------------------------------------------------
    var app = D8App(env, g);
    await app.launch(tester);
    await app.reveal(tester, app.shareButton);
    await app.tapAndNextFrame(tester, app.shareButton);
    app.shares.current!.add(kD8Refusal);
    await app.settle(tester);
    if (app.close.evaluate().isEmpty) {
      r.fail('T1c ${g.label}: control: 閉じる is not drawn after a refusal');
    } else {
      await app.reveal(tester, app.close);
      final from = await app.tapAndNextFrame(tester, app.close);
      _check(r, D8Transition('T1c', g, from, d8ControlsOnScreen(tester)));
      r.failures.addAll(await d8EffectGrid(tester, app, from, 'T1c-grid'));
      await app.settle(tester);
      _check(
        r,
        D8Transition('T1c-settled', g, from, d8ControlsOnScreen(tester)),
      );
    }
    await app.shares.closeAll();
  });
  await _sequence(r, 'D', g, () async {
    // ---- D: no yes held: the consent dialog's answers ----------------------
    // A second press on 現在地を共有 must not land on either answer: a yes
    // reached by a double press is not her affirmative act. The answers are
    // pinned to the dialog's foot, so where they sit depends on the window:
    // measured in both frames, and the worse one governs.
    var measured = true;
    for (final f in const [kD8Edge, kD8Api29Window]) {
      final gd = g.inFrame(f);
      await d8SetGeometry(tester, gd);
      final app = D8App(env, gd);
      await app.launch(tester, heldYes: null);
      await app.settleIO(tester);
      await app.reveal(tester, app.shareButton);
      final from = await app.tapAndNextFrame(tester, app.shareButton);
      await app.settleIO(tester);
      await app.settle(tester);
      final answers = [
        for (final k in const [
          'location-consent-accept',
          'location-consent-decline',
        ])
          if (find.byKey(Key(k)).evaluate().isNotEmpty)
            D8Control(k, tester.getRect(find.byKey(Key(k)))),
      ];
      if (answers.length != 2) {
        r.dialogFailures.add(
          'dialog ${gd.label}: control: the consent dialog\'s two answers '
          'are not both drawn (${answers.length})',
        );
        r.yesFraction = null;
        measured = false;
      } else {
        for (final a in answers) {
          final gap = d8EdgeGap(from, a.rect);
          r.lines.add(
            'D8 dialog ${gd.label}: ${a.name} ${d8Rect(a.rect)} at '
            '${gap.toStringAsFixed(1)} dp from 現在地を共有\'s place ${d8Rect(from)}',
          );
          if (gap < 0) {
            r.dialogFailures.add(
              'dialog ${gd.label}: ${a.name} ${d8Rect(a.rect)} intersects '
              '現在地を共有\'s place ${d8Rect(from)} (${gap.toStringAsFixed(1)} dp)',
            );
          }
          if (a.name == 'location-consent-accept' && measured) {
            final o = from.intersect(a.rect);
            final share = o.width > 0 && o.height > 0
                ? o.width * o.height / (from.width * from.height)
                : 0.0;
            r.yesFraction = math.max(r.yesFraction ?? 0.0, share);
          }
        }
      }
      await app.shares.closeAll();
    }
    r.dialogMeasured = measured;
    if (r.yesFraction != null) {
      r.lines.add(
        'D8 s3-yes ${g.label}: the yes covers '
        '${(100 * r.yesFraction!).toStringAsFixed(1)}% of 現在地を共有\'s place '
        '(larger window)',
      );
    }
  });
  await tester.pumpWidget(const SizedBox.shrink());
  return r;
}

/// One row of test/fixtures/stop_spot_guard/s3_baseline.tsv.
class D8S3Baseline {
  D8S3Baseline(this.code15Yes, this.headYes, this.narrowRed, this.wholeRed);

  /// The yes's share of 現在地を共有's place on code 15's tree.
  final double code15Yes;

  /// The same on the head the carry was recorded on: the CEILING for a
  /// carried geometry. A carried red that grows past it is not the carried
  /// red any more (2026-10-14, the consent review's fix: without it a yes
  /// twice as deep still read as "carried" and the census stayed green).
  final double headYes;

  /// Recorded red on the head carried under the Chair's answer A of
  /// 2026-10-14, as the project's board record (7108b257) writes it down.
  final bool narrowRed;
  final bool wholeRed;
}

/// The key a geometry has in the S-3 fixture.
String d8Key(String lang, double widthDp, double scale) =>
    '$lang ${widthDp.toStringAsFixed(1)} ${scale.toStringAsFixed(2)}';

/// The S-3 fixture, read once. Generated from two guard runs, never edited by
/// hand (its header names them).
Map<String, D8S3Baseline> d8S3Baseline() {
  final out = <String, D8S3Baseline>{};
  for (final line in File(
    'test/fixtures/stop_spot_guard/s3_baseline.tsv',
  ).readAsLinesSync()) {
    if (line.startsWith('#') || line.startsWith('lang\t') || line.isEmpty) {
      continue;
    }
    final f = line.split('\t');
    out[d8Key(f[0], double.parse(f[1]), double.parse(f[2]))] = D8S3Baseline(
      double.parse(f[3]),
      double.parse(f[4]),
      f[5] == '1',
      f[6] == '1',
    );
  }
  return out;
}

/// S-3 NARROW's tolerance: the consent review's (2026-10-14).
const double kD8YesTolerance = 0.005;

/// Where the two carried skips rest, on disk.
const String _kD8CarryRecord =
    'Carried under the Chair\'s answer A of 2026-10-14 (its board record, '
    '7108b257); skipped on his answer of the same day, "Acknowledge now; mark '
    'them skipped next", as the CI gate\'s entry 7 (89b89c47) records it.';

/// The reason a carried S-3 NARROW geometry is skipped. Its carry is named in
/// figures, so the skip says what it is skipping.
String d8CarriedNarrowSkip(D8S3Baseline b) =>
    'KNOWN RED, carried: at this geometry the yes was recorded covering '
    '${(100 * b.headYes).toStringAsFixed(1)}% of 現在地を共有\'s place, against '
    '${(100 * b.code15Yes).toStringAsFixed(1)}% on code 15. $_kD8CarryRecord '
    'Still measured: this file\'s S-3 census fails if it goes deeper, turns '
    'green, or is not measured.';

/// The reason a carried S-3 WHOLE geometry is skipped.
const String kD8CarriedWholeSkip =
    'KNOWN RED, carried: at this geometry an answer of the consent dialog was '
    'recorded under 現在地を共有\'s place, as on code 15\'s tree. '
    '$_kD8CarryRecord Still measured: this file\'s S-3 census fails if it '
    'turns green, if any other geometry turns red, or if the dialog is not '
    'measured.';

/// The sweep for one language and width: every scale in [kD8Scales].
/// `D8_SCALES=1.0,1.5` in the environment narrows it for a probe or a mutant
/// run; the suite runs the whole sweep.
///
/// THREE TESTS PER GEOMETRY, and why they are apart. A test that holds
/// several checks reports one result, so a red dialog check would hide a new
/// red row check behind it. Apart, each says its own truth:
/// - ROWS: every transition, effect grid, `end` pin and positive control.
///   D-8's own; binds code 16. Green everywhere on this layout.
/// - S-3 NARROW: the consent dialog's yes covers no more of 現在地を共有's place
///   than on code 15's tree (+0.005), per geometry. D-8's own: its move must
///   not make the yes easier to reach. RED at 16 large-text geometries where
///   the capped label grows the target into the yes. The Chair answered A on
///   2026-10-14 ("ship the fix, carry the dialog"); the board record of that
///   answer (7108b257) writes down that these 16 stay red and are fixed before
///   this layout reaches code 17 or main. The words here rest on that record,
///   not on more.
/// - S-3 WHOLE: no answer of the consent dialog lies under 現在地を共有's place.
///   Shared with code 15's tree (red there at 100 of 126) and carried as its
///   own requirement; red at 90 here.
/// SKIPPED AT THE RECORDED SETS, NEVER UNMEASURED (2026-10-14). The Chair's
/// answer to the CI question, "Acknowledge now; mark them skipped next", as
/// the CI gate's entry 7 (89b89c47) records it: the 16 narrow and the 90 whole
/// carried geometries are skipped with a KNOWN RED reason, so a later head can
/// go green. A skip stops a verdict, not the measurement: ROWS measures the
/// dialog at every geometry whatever is skipped, and the CENSUS below is the
/// verdict on every carried geometry. Everywhere else the two S-3 tests run.
/// A geometry with no baseline row is never skipped (no verdict is a fail).
/// ONE CENSUS per file: the sets of geometries red on S-3 NARROW and S-3 WHOLE
/// equal the recorded sets exactly, no carried geometry is deeper than its
/// carry, and every geometry's dialog was measured in both windows. A new red,
/// a deeper red, a recorded red that turned green unannounced, or a dialog not
/// measured turns the census red; so the suite's red set can be read by name,
/// and a change in it cannot pass in silence. It prints every carried
/// geometry's measured value, so a skipped number is still read.
void d8Sweep(String lang, double dpr) {
  final env = D8Env();
  setUp(env.setUp);
  tearDown(env.tearDown);
  final only = Platform.environment['D8_SCALES'];
  final scales = only == null || only.isEmpty
      ? kD8Scales
      : [for (final s in only.split(',')) double.parse(s)];
  final baseline = d8S3Baseline();
  final results = <String, D8Result>{};
  final widthDp = kD8Edge.physical.width / dpr;
  for (final s in scales) {
    final g = D8Geometry(lang, dpr, s);
    final key = d8Key(lang, g.widthDp, s);
    final carry = baseline[key];
    testWidgets('stop-spot guard, rows, ${g.label}', (tester) async {
      final r = await d8RunGeometry(tester, env, g);
      results[key] = r;
      for (final l in r.lines) {
        // ignore: avoid_print
        print(l);
      }
      expect(r.failures, isEmpty, reason: '\n${r.failures.join('\n')}');
    });
    test(
      'stop-spot guard, S-3 narrow: the yes covers no more of '
      '現在地を共有\'s place than on code 15, ${g.label}',
      () {
        final r = results[key];
        final b = baseline[key];
        expect(
          r,
          isNotNull,
          reason: 'the geometry was not measured: no verdict',
        );
        expect(
          b,
          isNotNull,
          reason: 'no code 15 baseline for $key: no verdict',
        );
        // Both windows, or no verdict (2026-10-14, the consent review's X2: one
        // window's measurement passed this test while the other had aborted).
        expect(
          r!.dialogMeasured,
          isTrue,
          reason:
              'the consent dialog was not measured in both windows: no '
              'verdict',
        );
        expect(
          r.yesFraction,
          isNotNull,
          reason: 'the consent dialog was not measured: no verdict',
        );
        final yes = r.yesFraction!;
        // A carried geometry is skipped above and judged by the census, so a
        // red here is always outside the recorded 16.
        expect(
          yes <= b!.code15Yes + kD8YesTolerance,
          isTrue,
          reason:
              '$key: the yes covers ${(100 * yes).toStringAsFixed(1)}% of '
              '現在地を共有\'s place, against ${(100 * b.code15Yes).toStringAsFixed(1)}% '
              'on code 15. NEW: not among the 16 recorded geometries.',
        );
      },
      skip: carry != null && carry.narrowRed
          ? d8CarriedNarrowSkip(carry)
          : false,
    );
    test('stop-spot guard, S-3 whole: no answer of the consent dialog under '
        '現在地を共有\'s place, ${g.label}', () {
      final r = results[key];
      expect(r, isNotNull, reason: 'the geometry was not measured: no verdict');
      expect(
        r!.dialogMeasured,
        isTrue,
        reason:
            'the consent dialog was not measured in both windows: no '
            'verdict\n${r.dialogFailures.join('\n')}',
      );
      expect(
        r.dialogFailures,
        isEmpty,
        reason:
            'NEW: not among the 90 recorded geometries (a carried geometry '
            'is skipped above and judged by the census).\n'
            '${r.dialogFailures.join('\n')}',
      );
    }, skip: carry != null && carry.wholeRed ? kD8CarriedWholeSkip : false);
  }
  test('stop-spot guard, S-3 census, $lang ${widthDp.toStringAsFixed(1)} dp: '
      'the red sets are exactly as recorded', () {
    final narrow = <String>{}, whole = <String>{}, deeper = <String>{};
    final wantNarrow = <String>{}, wantWhole = <String>{};
    for (final s in scales) {
      final key = d8Key(lang, widthDp, s);
      final r = results[key];
      final b = baseline[key];
      expect(r, isNotNull, reason: '$key was not measured: no census');
      expect(b, isNotNull, reason: 'no baseline for $key: no census');
      expect(
        r!.dialogMeasured && r.yesFraction != null,
        isTrue,
        reason: '$key: the dialog was not measured: no census',
      );
      if (r.yesFraction! > b!.code15Yes + kD8YesTolerance) narrow.add(key);
      // The ceiling: a carried geometry may not get deeper than it was
      // recorded while carried.
      if (b.narrowRed && r.yesFraction! > b.headYes + kD8YesTolerance) {
        deeper.add(key);
      }
      if (r.dialogFailures.isNotEmpty) whole.add(key);
      if (b.narrowRed) wantNarrow.add(key);
      if (b.wholeRed) wantWhole.add(key);
      // A skipped verdict's number is still read: every carried geometry's
      // measured value goes into the log.
      if (b.narrowRed || b.wholeRed) {
        // ignore: avoid_print
        print(
          'D8 S-3 carried $key: the yes covers '
          '${(100 * r.yesFraction!).toStringAsFixed(1)}% of 現在地を共有\'s place '
          '(carry ${(100 * b.headYes).toStringAsFixed(1)}%, code 15 '
          '${(100 * b.code15Yes).toStringAsFixed(1)}%); S-3 whole '
          '${r.dialogFailures.isEmpty ? 'green' : 'red'} '
          '(carried ${b.wholeRed ? 'red' : 'green'})',
        );
      }
    }
    expect(
      narrow.difference(wantNarrow),
      isEmpty,
      reason: 'S-3 narrow: NEW red geometries',
    );
    expect(
      deeper,
      isEmpty,
      reason: 'S-3 narrow: NEW: deeper than carried at a carried geometry',
    );
    expect(
      wantNarrow.difference(narrow),
      isEmpty,
      reason:
          'S-3 narrow: recorded red geometries now green; regenerate '
          'the fixture and say so',
    );
    expect(
      whole.difference(wantWhole),
      isEmpty,
      reason: 'S-3 whole: NEW red geometries',
    );
    expect(
      wantWhole.difference(whole),
      isEmpty,
      reason:
          'S-3 whole: recorded red geometries now green; regenerate the '
          'fixture and say so',
    );
  });
}
