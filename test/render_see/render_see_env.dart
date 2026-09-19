/// Shared environment honesty for the render_see suites.
///
/// The render_see tests serve render-and-look verification: they produce ja-rendered PNGs a
/// human LOOKS at on the dev host, with golden files as the local
/// regression anchor. Two facts make the golden comparison meaningless
/// off that host:
///
/// 1. The CJK system fonts (IPAGothic / DroidSansFallback) may be
///    absent — glyphs render as tofu, pixels diff wildly.
/// 2. Golden pixels are engine-version-specific — CI pins a different
///    Flutter than the dev host, so text shaping/AA differ even with
///    identical fonts.
///
/// So: when the fonts fail to load, [installNoopGoldenComparator]
/// swaps in a comparator that records an honest per-golden SKIP note
/// instead of failing. The test still builds, pumps, and renders the
/// REAL widgets (a broken pipeline still fails loudly); only the
/// pixel claim is withdrawn. Nobody affirms CI PNGs as look-verified
/// evidence — that affirmation only ever happens from a human-viewed
/// desktop run.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

Future<ByteData> _fontBytes(String path) async {
  final bytes = await File(path).readAsBytes();
  return ByteData.view(Uint8List.fromList(bytes).buffer);
}

/// Load whichever of [paths] exist on this host under [family].
/// Returns `true` when at least one font loaded (glyph fidelity is
/// verifiable), `false` when none did (env-honest degradation).
///
/// [searched] names the search that produced [paths], for the failure line.
/// Without it an empty [paths] prints `fonts sought: []`, which tells the
/// next reader nothing about where we looked — the CI log of run
/// 35300438549 was readable precisely because it printed the paths.
Future<bool> loadCjkFamily(
  String family,
  List<String> paths, {
  String? searched,
}) async {
  final present = paths.where((p) => File(p).existsSync()).toList();
  if (present.isEmpty) {
    // ignore: avoid_print
    print('render_see: no CJK system font on this host — ja glyph '
        'fidelity NOT verified in this environment (fonts sought: $paths)'
        '${searched == null ? '' : '\nrender_see: searched $searched'}');
    return false;
  }
  final loader = FontLoader(family);
  for (final p in present) {
    loader.addFont(_fontBytes(p));
  }
  // ignore: avoid_print
  print('render_see: family "$family" loaded from ${present.join(', ')}');
  await loader.load();
  return true;
}

/// The three searches a suite can ask for by name.
enum FaceSearch {
  /// Any face that really covers Japanese.
  japanese,

  /// IPAGothic and nothing else — for a suite whose finding is face-named.
  ipaGothic,

  /// Roboto, Android's face, from the SDK running this test.
  roboto,
}

List<String> _orderFor(FaceSearch s) => switch (s) {
  FaceSearch.japanese => japaneseFontSearchOrder(),
  FaceSearch.ipaGothic => ipaGothicSearchOrder(),
  FaceSearch.roboto => robotoSearchOrder(),
};

/// What the search looked at, written out so a red log says where to fix the
/// HOST rather than sending the reader into the widget code. Printed only on
/// failure, where it is the whole of what the next reader has.
String describeFaceSearch(FaceSearch s) {
  final roots = _systemRoots();
  final walked = _walkFontRoots(_japaneseFaceName);
  final lines = <String>[
    'search=${s.name}',
    if (roots != null) 'SNGNAV_TEST_FONT_ROOTS restricts to ${roots.join(':')}',
    'flutter SDK material_fonts: ${_sdkMaterialFonts()?.path ?? 'not found'}',
    'known paths tried: ${_orderFor(s).isEmpty ? 'none matched' : _orderFor(s).join(', ')}',
    'font-root walk found: '
        '${walked.isEmpty ? '(no Japanese face under ${_systemFontRoots.join(', ')})' : walked.join(', ')}',
    // fc-match is deliberately absent — see the banner below; inside
    // `flutter test` it answers a Japanese query with a Latin font.
    'tiers yielded nothing; install a face and re-run:',
    if (s == FaceSearch.japanese || s == FaceSearch.ipaGothic)
      '  Debian/Ubuntu: sudo apt-get install -y fonts-ipafont-gothic fonts-droid-fallback',
    if (s == FaceSearch.japanese)
      '  or set SNGNAV_TEST_CJK_FONT=/path/to/a/japanese.ttf',
    if (s == FaceSearch.ipaGothic)
      '  or set SNGNAV_TEST_IPAGOTHIC_FONT=/path/to/ipag.ttf',
    if (s == FaceSearch.roboto)
      '  Roboto ships inside the Flutter SDK; a missing one means the SDK '
          'cache is incomplete — run `flutter precache`',
  ];
  return lines.join('\n  ');
}

/// Discover a face on THIS host and load it under [family].
///
/// The family name is deliberately separate from the search: the app's default
/// family is Roboto, so a suite that wants the app's own text drawn with real
/// Japanese glyphs loads a Japanese face UNDER the name `Roboto`. That
/// substitution predates this function and is preserved by it.
Future<bool> loadDiscoveredFace(String family, FaceSearch search) =>
    loadCjkFamily(family, _orderFor(search),
        searched: describeFaceSearch(search));

// ── Font discovery ────────────────────────────────────────────────────────
//
// WHY this exists. Until 2026-09-18 every caller of [loadCjkFamily] passed a
// fixed absolute path, and two of the three named ONE DEVELOPER'S MACHINE:
// `$FLUTTER_ROOT/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf` (under a home directory)
// and `/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf`. The first CI run
// this app ever had (run 35300438549, head da281ce) failed 7 tests on exactly
// that, logging `no CJK system font on this host` 31 times. The tests were
// RIGHT to fail — without real glyph metrics they cannot see the defect they
// exist for, and a guard that passes without glyphs is worse than one that
// fails. What was wrong was the LOOKING. These functions do the looking.
//
// ⚑ MEASURED 2026-09-18, and the reason every fc-match result below is
// VALIDATED rather than trusted: **fc-match never says "not found".**
//   $ fc-match -f '%{family}|%{file}\n' 'ZZZNotARealFamily12345'
//   Noto Sans|/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf
//   $ fc-match -f '%{family}|%{file}\n' 'Roboto'
//   Noto Sans|/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf
// An unvalidated fc-match therefore hands a Japanese legibility guard a
// LATIN-ONLY face, the load succeeds, and the guard reports a clearance it
// never measured. That is the absent-verdict-reads-as-a-pass defect, arriving
// through the very fix meant to end it. So: a family match is confirmed
// against `%{family}`, and a Japanese match against `fc-list :lang=ja`.
//
// TIER-STOP, and why the order is what it is. Each search returns the FIRST
// TIER that yields any file, never a concatenation of all tiers. Tier 1 is
// the two Debian faces the dev host already had and CI now installs, so on
// both of those hosts discovery returns exactly the list the hard-coded
// callers used to pass — the metrics do not move, and CI and the dev host
// read the same glyphs. Later tiers only ever fire where tier 1 is absent, on
// a machine that had nothing before.

/// Directory a test-run Flutter SDK keeps its bundled fonts in, found from the
/// `flutter_tester` binary this test process IS
/// (`<sdk>/bin/cache/artifacts/engine/<host>/flutter_tester`), so it is the
/// SDK actually running, not one named in an environment variable. Measured
/// 2026-09-18 on this host: resolvedExecutable
/// `$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-x64/flutter_tester`
/// → artifacts `$FLUTTER_ROOT/bin/cache/artifacts`, which holds both
/// `material_fonts/MaterialIcons-Regular.otf` and `Roboto-Regular.ttf`.
///
/// [loadMaterialIconsFont] has resolved its font this way since before the CI
/// finding; this names the step so Roboto can use it too rather than growing
/// a second mechanism beside it.
Directory? _sdkMaterialFonts() {
  for (final root in <String?>[
    File(Platform.resolvedExecutable).parent.parent.parent.path,
    if (Platform.environment['FLUTTER_ROOT'] case final r?)
      '$r/bin/cache/artifacts', // ignore: use_null_aware_elements
  ]) {
    if (root == null) continue;
    final d = Directory('$root/material_fonts');
    if (d.existsSync()) return d;
  }
  return null;
}

/// Restrict the SYSTEM font search to these directory prefixes, `:`-separated.
///
/// A TEST CONTROL, and it can only ever NARROW: pointing it at an empty
/// directory makes a host with fonts behave like a host without any, which is
/// how the fail-closed half of these guards is proven without uninstalling a
/// font. It cannot turn a red green — it removes candidates, never adds one.
/// It restricts EVERY candidate including the SDK-bundled Roboto, because a
/// control that leaves one tier reachable does not prove the fail-closed path
/// for the suite that uses that tier. (This comment said the opposite for as
/// long as it took to run the control: the code filtered the SDK path all
/// along, and the sentence was written from intent rather than from the code.)
/// It is also the honest knob for a developer whose faces live somewhere this
/// file does not list (`~/.local/share/fonts`, a Nix store, a container mount)
/// — in that use it is set to the directory that HAS the fonts, not an empty
/// one.
List<String>? _systemRoots() {
  final v = Platform.environment['SNGNAV_TEST_FONT_ROOTS'];
  if (v == null) return null;
  return v.split(':').where((s) => s.isNotEmpty).toList();
}

bool _underRoots(String path) {
  final roots = _systemRoots();
  if (roots == null) return true;
  return roots.any((r) => path.startsWith(r));
}

List<String> _existing(Iterable<String> paths) => paths
    .where((p) => _underRoots(p) && File(p).existsSync())
    .toList(growable: false);

/// ⚑ WHY THERE IS NO fc-match HERE, measured 2026-09-18 from inside a running
/// `flutter test` — recorded so the next reader does not add one back.
///
/// `flutter test` REPLACES fontconfig's configuration for the test process:
///   FONTCONFIG_FILE=/tmp/flutter_tools.XXXX/flutter_test_fonts.YYYY/fonts.conf
/// That config knows only the harness's own font directory, so inside a test
/// fontconfig is blind to the system — on THIS host, which carries 13 faces
/// declaring Japanese coverage:
///   fc-list :lang=ja file            -> exit 0, ZERO lines
///   fc-match 'sans-serif:lang=ja'    -> Roboto, from the SDK's material_fonts
/// The second is the dangerous one. Asked for a JAPANESE face, fontconfig
/// answers with a LATIN-ONLY one and exits 0. A discovery that trusted it
/// would load Roboto, the load would succeed, the guard would pass, and the
/// Japanese legibility of the driver's screen would have been certified by a font with
/// no kanji in it. This is not a host quirk and no environment variable fixes
/// it — it is what the harness does for hermeticity, on every host.
///
/// So discovery walks the font directories itself. 1060 files under
/// /usr/share/fonts in 47 ms, measured, which is cheaper than the subprocess
/// it replaces.

const _systemFontRoots = <String>[
  '/usr/share/fonts',
  '/usr/local/share/fonts',
  '/System/Library/Fonts',
  '/Library/Fonts',
];

/// Faces verified to load with real Japanese metrics, matched on file name.
///
/// The bound, stated because it is a heuristic and not a coverage test: this
/// matches NAMES, so it can only find faces someone listed here. A face under
/// another name is missed and the suite fails closed — the right failure. It
/// cannot match Roboto, Noto Sans, DejaVu or any other Latin face, which is
/// the failure that would matter.
final _japaneseFaceName = RegExp(
  r'ipag|notosanscjk|notoserifcjk|sourcehansans|sourcehanserif|'
  r'droidsansfallback|fonts-japanese|hiragino|ヒラギノ|osaka|'
  r'takaogothic|takaopgothic|yugoth|meiryo|msgothic|ipamjm',
  caseSensitive: false,
);

/// A weight/slant token in a file name, used to rank a walk's hits.
///
/// Measured 2026-09-18: a plain alphabetical sort handed the suite
/// `NotoSerifCJK-Bold.ttc` because `B` sorts before `R`, so the first host to
/// fall through to the walk would have had its layout measured in BOLD. Rank
/// `Regular` first, anything unmarked second, a weighted face last.
final _weightToken = RegExp(
  r'bold|italic|oblique|light|thin|black|heavy|medium|semi|extra|demi',
  caseSensitive: false,
);
final _regularToken = RegExp(r'regular|-r\b', caseSensitive: false);

int _faceRank(String path) {
  final base = path.split('/').last;
  if (_regularToken.hasMatch(base)) return 0;
  if (_weightToken.hasMatch(base)) return 2;
  return 1;
}

/// Every font file under the system roots whose name matches [name], ranked so
/// a regular weight wins, then alphabetical — so two hosts carrying the same
/// faces resolve to the same file and measure the same metrics.
List<String> _walkFontRoots(RegExp name) {
  final out = <String>[];
  for (final root in [
    ..._systemFontRoots,
    if (Platform.environment['HOME'] case final h?) ...[
      '$h/.local/share/fonts',
      '$h/.fonts',
    ],
  ]) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    try {
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        // `followLinks: false` keeps a pathological font tree from looping,
        // but it also hands back a symlinked font as a Link rather than a
        // File — and a Debian alternatives slot
        // (`fonts-japanese-gothic.ttf`) is exactly that. Accept both; the
        // caller's `File(p).existsSync()` resolves the link and drops a
        // dangling one.
        if (e is! File && e is! Link) continue;
        final base = e.uri.pathSegments.last;
        if (!name.hasMatch(base)) continue;
        if (!RegExp(r'\.(ttf|otf|ttc|otc)$', caseSensitive: false)
            .hasMatch(base)) {
          continue;
        }
        out.add(e.path);
      }
    } on FileSystemException {
      continue; // an unreadable font directory is not a reason to stop
    }
  }
  out.sort((a, b) {
    final r = _faceRank(a).compareTo(_faceRank(b));
    return r != 0 ? r : a.compareTo(b);
  });
  return out;
}

List<String> _firstNonEmpty(List<List<String>> tiers) {
  for (final t in tiers) {
    if (t.isNotEmpty) return t;
  }
  return const [];
}

/// Where a Japanese-capable face is looked for, in order. Tier-stop.
///
/// 1. `SNGNAV_TEST_CJK_FONT` — an explicit file, for a host this list misses.
/// 2. `fonts-ipafont-gothic` + `fonts-droid-fallback` at their Debian paths —
///    the pair the dev host carries and CI installs, so both read one face.
/// 3. `fonts-japanese-gothic.ttf` (the Debian alternatives symlink; resolves
///    to ipag.ttf on this host) and `fonts-noto-cjk`'s collection. A `.ttc`
///    loads: measured 2026-09-18, NotoSansCJK-Regular.ttc moved a 7-char
///    Latin string from the test font's 280.0 to 101.84, so real metrics.
/// 4. macOS system Hiragino, for an edge developer not on Debian.
/// 5. fc-match, validated against `fc-list :lang=ja`.
/// 6. anything `fc-list :lang=ja` names, first that exists.
List<String> japaneseFontSearchOrder() => _firstNonEmpty([
  _existing([?Platform.environment['SNGNAV_TEST_CJK_FONT']]),
  _existing(const [
    '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf',
    '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf',
  ]),
  _existing(const [
    '/usr/share/fonts/truetype/fonts-japanese-gothic.ttf',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/truetype/fonts-japanese-mincho.ttf',
  ]),
  _existing(const [
    '/System/Library/Fonts/Hiragino Sans GB.ttc',
    '/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc',
    '/Library/Fonts/Osaka.ttf',
  ]),
  _existing(_walkFontRoots(_japaneseFaceName)).take(1).toList(),
]);

/// Where IPAGothic SPECIFICALLY is looked for, in order. Tier-stop.
///
/// Separate from [japaneseFontSearchOrder] because two suites name this face
/// in their own titles and docstrings — the card is read "ja, IPAGothic,
/// 393 px", and the dash-alone band was found at "393 logical px, IPAGothic".
/// Handing those a different Japanese face would silently re-point a measured
/// finding at metrics it was never made against. Where IPAGothic is absent
/// they fail closed, which is the correct answer for a face-named test.
List<String> ipaGothicSearchOrder() => _firstNonEmpty([
  _existing([?Platform.environment['SNGNAV_TEST_IPAGOTHIC_FONT']]),
  _existing(const ['/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf']),
  // The Debian alternatives symlink, but only when it really resolves to
  // IPAGothic — it is an alternatives slot and another face can own it.
  _existing([
    for (final l in const ['/usr/share/fonts/truetype/fonts-japanese-gothic.ttf'])
      if (File(l).existsSync() &&
          File(l).resolveSymbolicLinksSync().contains('ipafont'))
        l,
  ]),
  _existing(_walkFontRoots(RegExp(r'ipag', caseSensitive: false)))
      .take(1)
      .toList(),
]);

/// Where Roboto is looked for, in order. Tier-stop.
///
/// The SDK's own copy comes first and is the one that matters: Roboto is
/// Android's face, `flutter test` is already running out of a Flutter SDK, and
/// that SDK ships `material_fonts/Roboto-Regular.ttf`. So this resolves on any
/// host that can run the suite at all, with no font package installed.
///
/// ⚑ The bound that rides it: CI pins Flutter 3.41.4 while this dev host runs
/// 3.45.0-1.0.pre-48, so the two read Roboto from different SDK checkouts.
/// Same file name, not proven the same bytes. The workflow already names that
/// SDK skew for the APK build; it reaches the glyphs too.
List<String> robotoSearchOrder() => _firstNonEmpty([
  _existing([?Platform.environment['SNGNAV_TEST_ROBOTO_FONT']]),
  _existing([?_sdkMaterialFonts()?.path].map((d) => '$d/Roboto-Regular.ttf')),
  _existing(const [
    '/usr/share/fonts/truetype/roboto/unhinted/RobotoTTF/Roboto-Regular.ttf',
    '/usr/share/fonts/truetype/roboto/Roboto-Regular.ttf',
  ]),
  _existing(_walkFontRoots(RegExp(r'^Roboto-Regular\.ttf$', caseSensitive: false)))
      .take(1)
      .toList(),
]);

/// Load the app's own bundled symbols-subset font (the APK-shipped bytes at
/// `assets/fonts/SnGNavSymbols.ttf`) under its REAL family name — the one
/// `ThemeData.fontFamilyFallback` in main.dart names — so a capture renders
/// the ⚠/❄-class glyphs from the same bytes the phone ships instead of
/// tofu. Opt-in per capture suite: existing goldens were cut without it and
/// stay pixel-stable unless a suite loads it deliberately.
Future<bool> loadBundledSymbolsFont() =>
    loadCjkFamily('SnGNavSymbols', ['assets/fonts/SnGNavSymbols.ttf']);

/// Load the Flutter SDK's own MaterialIcons font, found beside the
/// `flutter_tester` binary (`<sdk>/bin/cache/artifacts/engine/<host>/`).
/// `flutter test` does not load it by itself, so an `Icons.*` glyph renders
/// as a hollow box — and on a map, a hollow box next to a marker reads as a
/// shape of its own. Returns `false` when the font is not where a standard
/// SDK keeps it. Opt-in per capture suite, like [loadBundledSymbolsFont].
Future<bool> loadMaterialIconsFont() async {
  // Resolved through [_sdkMaterialFonts] since 2026-09-18, so this and Roboto
  // find the SDK by ONE mechanism. It tries the same resolvedExecutable path
  // first and then FLUTTER_ROOT, so it can only find more, never less.
  final dir = _sdkMaterialFonts();
  final font = File('${dir?.path}/MaterialIcons-Regular.otf');
  if (dir == null || !font.existsSync()) {
    // ignore: avoid_print
    print('render_see: MaterialIcons not found at ${font.path} — Icons.* '
        'glyphs render as boxes in this environment');
    return false;
  }
  final loader = FontLoader('MaterialIcons')..addFont(_fontBytes(font.path));
  await loader.load();
  return true;
}

/// Whether comparing a golden's PIXELS means anything on this host.
///
/// ⚑ Read this before changing the CI font step. Reason 2 in this file's
/// header — golden pixels are engine-version-specific, and CI pins Flutter
/// 3.41.4 while the dev host runs 3.45.0-1.0.pre-48, so shaping and AA differ
/// even with identical fonts — was never enforced by anything. It did not
/// need to be: CI had no CJK font, so every capture suite took the fontless
/// branch and installed the no-op comparator. **The goldens were skipped on CI
/// by accident, and the accident was load-bearing.**
///
/// On 2026-09-18 CI began installing `fonts-ipafont-gothic` and
/// `fonts-droid-fallback`, because seven legibility guards cannot see the
/// Japanese screen without real glyphs. That removes the accident: the fonts
/// now load on CI, the fontless branch stops firing, and 18 capture suites
/// would start comparing dev-host pixels against a different engine's.
///
/// So the reason is stated on its own here rather than left riding on a
/// missing font. This changes no behaviour that anyone has seen: CI skipped
/// these goldens before and skips them now. What changes is that it skips them
/// for the true reason, and keeps skipping them when the font situation moves
/// again.
///
/// `SNGNAV_TEST_COMPARE_GOLDENS=1` forces the real comparator anywhere, for
/// whoever eventually cuts goldens on a runner's own engine.
bool goldenPixelsComparableHere() {
  final env = Platform.environment;
  if (env['SNGNAV_TEST_COMPARE_GOLDENS'] == '1') return true;
  return env['CI'] != 'true' && env['GITHUB_ACTIONS'] != 'true';
}

/// Replace the golden comparator with one that SKIPS (pass + honest
/// note) every comparison. Called when no real glyphs loaded, and when
/// [goldenPixelsComparableHere] says this host did not cut these goldens.
// ⚑ THE SKIP NOTE USED TO STATE THE WRONG REASON. Corrected 2026-09-18 (0.0.2
// release), found while counting skips for one of that release's criteria.
//
// This comparator is installed from TWO different conditions (see the call
// pattern in every capture suite: `if (!cjkLoaded || !goldenPixelsComparableHere())`)
// and it printed ONE of them unconditionally: "no CJK fonts on this host".
//
// On CI that sentence is now FALSE. Since 2026-09-18 the workflow installs
// fonts-ipafont-gothic and fonts-droid-fallback and asserts both faces exist
// before the suite runs, so the fonts ARE there; the goldens skip for the OTHER
// reason — CI pins Flutter 3.41.4 and these goldens were cut on a dev host
// running 3.45.0-1.0.pre-48, so shaping and anti-aliasing differ and the pixels
// are not comparable whatever fonts are present.
//
// Why a wrong reason in a skip note is not cosmetic: 43 skip lines in the
// 2026-09-18 CI run each told their reader to go install fonts. Someone acting
// on that would have installed fonts, seen the skips continue, and had no way
// to tell a working guard from a broken one. A skip is not a pass, and a skip
// that misnames its cause cannot even be audited.
//
// The reason is resolved at install time from the same predicate the caller
// used, so the note can no longer drift from the condition. Engine-mismatch is
// reported first when both hold, because it is the load-bearing one: it would
// skip these goldens even with every font present.
void installNoopGoldenComparator() {
  goldenFileComparator = _SkipNoteComparator(
    reason: goldenPixelsComparableHere()
        ? 'no CJK fonts on this host'
        : 'this host did not cut these goldens — CI pins a different Flutter '
            'engine than the dev host that cut them, so pixels are not '
            'comparable even with identical fonts',
  );
}

class _SkipNoteComparator extends GoldenFileComparator {
  _SkipNoteComparator({required this.reason});

  /// Why this host cannot compare these pixels. Resolved at install time.
  final String reason;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    // ignore: avoid_print
    print('render_see: golden comparison SKIPPED for $golden — $reason; '
        'pixel claims are withdrawn (render pipeline was still exercised).');
    return true;
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {
    // Never update goldens from a fontless environment.
  }
}
