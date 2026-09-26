/// The manifest address, the reader's state and the stored address reach
/// no pixel, and are read outside their own two files only by the debug line,
/// only in a debug build.
///
/// WHY, written before this file. WDA, the reviewer who rules on what this
/// update channel may carry, allowed its one control fact, the manifest's
/// own address, on condition W-3: it reaches no pixel, proven by a test and
/// not only by a search someone once ran. The value is a URL string, and on
/// a screen it would be a second place for a sentence from the network to
/// reach the holder.
///
/// WDA's ruling is recorded in the unit's masterplan at
/// `outputs/weaver-dignity-auditor/r122_4a_reader_nsc_snow_d4_2026_09_25/VERDICT.md`.
///
/// TWO HALVES.
///  1. SOURCE. Every file under lib/ except the two that own the address
///     (update_check.dart, update_manifest.dart) is read. A mention of the
///     address, the reader's state or the stored address inside
///     lib/widgets/ fails; anywhere else it must be in lib/main.dart AND
///     inside `if (kDebugMode) {…}` or on the chosen side of a
///     `kDebugMode ? … :` expression.
///  2. PIXELS. The one widget that receives a check result, UpdateNotice, is
///     drawn once for every state the address reader can report. Its text
///     and its raster must be identical across all of them, and a control
///     proves the capture does see a change when something drawn changes.
///
/// HONEST BOUND. Half 1 reads source through dart_views.dart and names the
/// symbols it looks for; a value reached another way (a tear-off stored in a
/// variable, reflection, a new symbol) is outside it. Half 2 draws the one
/// widget that takes a result today.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/build_identity.dart';
import 'package:sngnav_app/services/update_check.dart';
import 'package:sngnav_app/services/update_manifest.dart';
import 'package:sngnav_app/widgets/update_notice.dart';

import 'dart_views.dart';

const _owners = {
  'lib/services/update_check.dart',
  'lib/services/update_manifest.dart',
};

/// The address, the reader's state and the stored address, by every name
/// they have outside their own files.
final _named = RegExp(r'\bmanifestUrl\w*|\bManifestAddress\b|'
    r'\bresolveManifestUrl\b|\bpersistManifestUrl\b|\bdefaultManifestUrl\b|'
    r'\bSNGNAV_UPDATE_MANIFEST_URL\b|update_manifest_url\.txt');

/// `UpdateCheckResult.address`. Only looked for in files that import the
/// checker, the only way to hold a result.
final _addressField = RegExp(r'\.address\b');

const _wda = 'WDA ruled (2026-09-25, condition W-3) that the manifest address '
    'reaches no pixel. Outside update_check.dart and update_manifest.dart it '
    'may be read only by the debug line in lib/main.dart, inside kDebugMode.';

/// Every place in [files] (path -> source) that reads the address where it
/// may not. Empty when each read is the guarded debug line.
List<String> addressLeaks(Map<String, String> files) {
  final leaks = <String>[];
  for (final MapEntry(key: path, value: source) in files.entries) {
    if (_owners.contains(path)) continue;
    final v = DartViews(source);
    // The import path is a string, so it is matched in the code view.
    final holdsResults = RegExp(r'''import\s+['"][^'"]*update_check\.dart['"]''')
        .hasMatch(v.code);
    final hits = [
      ..._named.allMatches(v.code),
      if (holdsResults) ..._addressField.allMatches(v.code),
    ];
    for (final h in hits) {
      final where = '$path:${v.lineOf(h.start)} `${h.group(0)}`';
      if (path.startsWith('lib/widgets/')) {
        leaks.add('$where is read by a widget');
      } else if (path != 'lib/main.dart') {
        leaks.add('$where is outside the one debug line');
      } else if (!_insideDebugGuard(v, h.start)) {
        leaks.add('$where escapes the kDebugMode guard');
      }
    }
  }
  return leaks;
}

/// True when [at] is inside `if (kDebugMode) {…}`, or after the `?` and
/// before the `:` of a `kDebugMode ? … : …` on its own line. Braces are
/// counted in the shape view, where no brace in a string or comment is left.
bool _insideDebugGuard(DartViews v, int at) {
  for (final m in RegExp(r'\bif\s*\(\s*kDebugMode\s*\)\s*\{').allMatches(v.shape)) {
    final open = m.end - 1;
    if (open < at && at < v.closingBrace(open)) return true;
  }
  final lineStart = v.shape.lastIndexOf('\n', at) + 1;
  final head = v.shape.substring(lineStart, at);
  final q = RegExp(r'(?<![!\w])kDebugMode\s*\?').allMatches(head).lastOrNull;
  if (q == null || head.substring(q.end).contains(':')) return false;
  // THE CONDITION MUST BE kDebugMode ALONE (2026-09-25, round 5b, on the
  // voice-census author's finding, TRAP-20). `?:` binds more loosely than
  // every other operator, so `_verbose || kDebugMode ? read : null` is
  // `(_verbose || kDebugMode) ? read : null` and reads in release whenever
  // _verbose holds; so do `|`, `??`, `==`, `^` and `a || b && kDebugMode`.
  // Until this line, any condition whose LAST token was kDebugMode was
  // exempt. Now what stands before kDebugMode must begin an expression: an
  // assignment, `=>`, an opening bracket, a comma, a `;`, `return`, or the
  // `?` or `:` of an enclosing conditional. Anything else is not exempt, a
  // conjunction included: this reports a read that is in fact debug-only
  // rather than exempt one that is not.
  //
  // W-3a (2026-09-25, round 5c, WDA REL1/2/3/5/6): read what stands before
  // kDebugMode ACROSS THE LINE BREAK, not only on the read's own line. `head`
  // starts at lineStart, so when `kDebugMode ?` begins its line `before` was
  // empty and empty counted as the start of an expression — a wrapped
  // `_verbose ||`, `_force ??`, `!`, `|` or `false ==` on the line above was
  // never seen, and five release-reachable reads passed as debug-only. Taking
  // the shape from 0 up to the match reads the last code token above; it can
  // only turn a false exemption into a report, never the reverse (it differs
  // from the one-line form solely when nothing but whitespace precedes
  // kDebugMode on its line).
  final before = v.shape.substring(0, lineStart + q.start).trimRight();
  return before.isEmpty ||
      RegExp(r'(?:(?<![=!<>?])=|=>|[(\[{,;:]|(?<!\?)\?|\breturn)$')
          .hasMatch(before);
}

Map<String, String> _libTree() => {
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart'))
          f.path.replaceAll(r'\', '/'): f.readAsStringSync(),
    };

const _kPkg = 'dev.aki1770del.sngnav_app';

UpdateCheckResult _result(ManifestAddress address, {int code = 11}) =>
    UpdateCheckResult(
      status: UpdateCheckStatus.updateAvailable,
      running: const BuildIdentity(
        versionName: '0.0.2',
        versionCode: 10,
        packageName: _kPkg,
        selfSha256:
            '7129d4a4bb1b03e3badcb20b37a26f22c1b4e1e86946d5b4df4598898a90b845',
        gitSha: '5794d0c',
      ),
      available: UpdateManifestEntry(
        versionCode: code,
        versionName: '0.0.2',
        artifactUrl: Uri.parse('https://example.test/app.apk'),
        package: _kPkg,
        sha256:
            'fd2cdf4b615b275bdfbe1902ee8249473e603f83b8325def2552020f85038937',
        sizeBytes: 94671699,
        signerSha256:
            '6a4906edb4ebdc5f54ad24ab1818054618adba480df98b4f4f1dac45600d0f14',
      ),
      runningIsPublished: false,
      address: address,
    );

const Key _shot = Key('update-address-shot');

Widget _host(UpdateCheckResult result) => MaterialApp(
      locale: const Locale('ja'),
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(
        backgroundColor: const Color(0xFFFFFFFF),
        body: RepaintBoundary(
          key: _shot,
          child: SizedBox(
            width: 400,
            height: 600,
            child: SingleChildScrollView(
              child: UpdateNotice(
                result: result,
                driving: false,
                dismissedVersionCode: null,
                onDismiss: () {},
              ),
            ),
          ),
        ),
      ),
    );

/// Everything the notice says in words, in tree order.
List<String> _words(WidgetTester tester) => [
      for (final w in tester.widgetList(find.byWidgetPredicate(
          (w) => w is Text || w is SelectableText)))
        if (w is Text)
          w.data ?? w.textSpan?.toPlainText() ?? ''
        else if (w is SelectableText)
          w.data ?? w.textSpan?.toPlainText() ?? '',
    ];

/// The raster, read back, as bytes. Carried OUT of runAsync, because toImage
/// awaited inside the fake-async zone never completes (the house pattern of
/// update_notice_pixel_guard_test.dart).
Future<List<int>> _raster(WidgetTester tester) async {
  final bytes = await tester.runAsync(() async {
    final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
    final img = await b.toImage(pixelRatio: 1.0);
    final d = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    return d!.buffer.asUint8List().toList();
  });
  return bytes!;
}

void main() {
  group('1. SOURCE: the address is read only by the guarded debug line', () {
    test('nothing in lib/ reads it where it may not', () {
      final leaks = addressLeaks(_libTree());
      expect(leaks, isEmpty, reason: '$_wda\n${leaks.join('\n')}');
    });

    test('the debug line itself is still there, so the rule above is not '
        'passing on an empty tree', () {
      final main = DartViews.read('lib/main.dart').code;
      expect(RegExp(r'address=\$\{result\.address\.name\}').hasMatch(main),
          isTrue,
          reason: 'the debug line moved or changed; re-point this control');
    });

    // STANDING NEGATIVE CONTROLS on the REAL tree, one edit each, in memory.
    group('it can fail', () {
      final tree = _libTree();
      const guarded =
          'kDebugMode ? await UpdateChecker.resolveManifestUrl() : null';

      Map<String, String> edit(String path, String from, String to) {
        final src = tree[path]!;
        expect(src.split(from).length, 2,
            reason: 'control anchor `$from` not found exactly once in $path');
        return {...tree, path: src.replaceFirst(from, to)};
      }

      final cases = <(String, String, String, String)>[
        ('the stored address read before the guard, as it was until '
            '2026-09-25', 'lib/main.dart', guarded,
            'await UpdateChecker.resolveManifestUrl()'),
        ('the guard turned the wrong way round', 'lib/main.dart', guarded,
            '!kDebugMode ? null : await UpdateChecker.resolveManifestUrl()'),
        // A condition that ENDS in kDebugMode but is not kDebugMode alone
        // reads in release. Each passed as debug-only until round 5b.
        for (final condition in [
          '_verbose || kDebugMode',
          '_verbose | kDebugMode',
          '_force ?? kDebugMode',
          'false == kDebugMode',
          '_verbose ^ kDebugMode',
          '_a || _b && kDebugMode',
        ])
          ('the read under `$condition ?`, which runs in release',
              'lib/main.dart', guarded,
              '$condition ? await UpdateChecker.resolveManifestUrl() : null'),
        // CROSS-LINE (W-3a, WDA round 5c REL1/2/3/5/6): the other operand sits
        // on the line ABOVE kDebugMode, so the read runs in release, and the
        // round-5b rule — which judged only the read's own line — missed it.
        // These fail on `aee13cc`'s rule and are caught by W-3a.
        for (final (label, wrapped) in const [
          ('||', '_verbose ||'),
          ('??', '_force ??'),
          ('!', '!'),
          ('|', '_verbose |'),
          ('false ==', 'false =='),
        ])
          ('caught cross-line: `$label` wrapped onto the line above kDebugMode, '
              'which runs in release', 'lib/main.dart', guarded,
              '$wrapped\n          kDebugMode ? '
                  'await UpdateChecker.resolveManifestUrl() : null'),
        ('the reader\'s state printed after the guard closes', 'lib/main.dart',
            "      if (!mounted) return;\n      setState(() => _updateResult = result);",
            "      debugPrint('\${result.address}');\n"
                "      if (!mounted) return;\n      setState(() => _updateResult = result);"),
        ('a widget that shows the reader\'s state',
            'lib/widgets/update_notice.dart',
            'Text(l10n.updateAvailableLine(entry.display)),',
            "Text('\${result!.address.name}'),"),
      ];
      for (final (why, path, from, to) in cases) {
        test('caught: $why', () {
          expect(addressLeaks(edit(path, from, to)), isNotEmpty);
        });
      }

      test('still exempt: kDebugMode alone, inside an enclosing bracket', () {
        expect(
            addressLeaks(edit('lib/main.dart', guarded, '($guarded)')),
            isEmpty,
            reason: 'the round-5b rule must refuse conditions that are not '
                'kDebugMode alone, not every spelling but one');
      });

      test('still exempt: kDebugMode alone, wrapped after `=` onto its own '
          'line (W-3a reads the token above only to reject non-kDebugMode '
          'operands, not to over-report)', () {
        expect(
            addressLeaks(edit('lib/main.dart', guarded,
                '\n          kDebugMode ? '
                    'await UpdateChecker.resolveManifestUrl() : null')),
            isEmpty,
            reason: 'the assignment `final url =` above kDebugMode begins an '
                'expression, so a bare kDebugMode wrapped onto the next line '
                'stays exempt');
      });
    });
  });

  group('2. PIXELS: the notice draws the same whatever the reader did', () {
    testWidgets('identical words and identical raster for every '
        'ManifestAddress state', (tester) async {
      String? firstWords;
      List<int>? firstRaster;
      for (final a in ManifestAddress.values) {
        await tester.pumpWidget(_host(_result(a)));
        await tester.pumpAndSettle();
        final words = _words(tester).join('\n');
        final raster = await _raster(tester);
        expect(words, contains('0.0.2+11'),
            reason: 'the notice must be showing, or this compares nothing');
        firstWords ??= words;
        firstRaster ??= raster;
        expect(words, firstWords,
            reason: '$_wda\nThe words changed with the reader state ${a.name}');
        expect(raster, firstRaster,
            reason: '$_wda\nThe pixels changed with the reader state ${a.name}');
      }
    });

    testWidgets('control: the capture DOES see a change in what is drawn',
        (tester) async {
      await tester.pumpWidget(_host(_result(ManifestAddress.notAsked)));
      await tester.pumpAndSettle();
      final words = _words(tester).join('\n');
      final raster = await _raster(tester);
      await tester.pumpWidget(
          _host(_result(ManifestAddress.notAsked, code: 1100)));
      await tester.pumpAndSettle();
      expect(_words(tester).join('\n'), isNot(words));
      expect(await _raster(tester), isNot(raster),
          reason: 'a longer version string must move pixels, or the raster '
              'check above proves nothing');
    });
  });
}
