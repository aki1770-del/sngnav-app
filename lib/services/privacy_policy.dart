/// The privacy policy, bundled INTO the app.
///
/// WHY (2026-09-23). Google Play's User Data policy, read at source by AAA this
/// day, is unconditional and is not gated by any reasonable-expectation test:
///
///   "All apps must post a privacy policy link in the designated field within
///    Play Console, and a privacy policy link or text within the app itself."
///   "Apps that do not access any personal and sensitive user data must still
///    submit a privacy policy."
///
/// Measured the same day: `grep -rniE "privacy.?policy|プライバシー" lib/ android/`
/// returned ONE hit in the whole app, and it was a COMMENT in AndroidManifest.xml.
/// No link, no text, no route, no surface.
///
/// THE DOCUMENT ALREADY EXISTED. `docs/store/privacy_policy_ja.md` (ja primary,
/// full English translation below it) has been in this repository since
/// 2026-08-10 and is served publicly. Nothing here drafts policy language: this
/// file bundles and renders the document that exists, and the ONE copy in the
/// repository is the one the app ships, so the shipped text cannot drift from
/// the published text. That is why the markdown file itself is the asset rather
/// than a transcription of it.
///
/// TEXT, NOT A LINK, DELIBERATELY. The policy permits either. A link is useless
/// to the driver this app is for: she is in a place where the network went
/// away, which is the whole premise. The bundled text needs no network. The
/// repository URL is shown as well, for anyone who wants the canonical page.
library;

import 'package:flutter/services.dart' show rootBundle;

/// The asset path. Declared in pubspec `flutter/assets`, and it points at the
/// SOURCE document rather than a copy.
const String kPrivacyPolicyAsset = 'docs/store/privacy_policy_ja.md';

/// Where the same document is published.
const String kPrivacyPolicyRepoUrl =
    'https://github.com/aki1770-del/sngnav-app/blob/main/docs/store/privacy_policy_ja.md';

/// HTML comment blocks in the source document are AUTHORING NOTES — provenance
/// for the permission table, OPS-rule citations, instructions to whoever hosts
/// the page. They are not the policy and they are not addressed to her.
final RegExp _htmlComment = RegExp(r'<!--.*?-->', dotAll: true);

/// The policy text as it should be shown to a person.
///
/// Strips only HTML comment blocks. Nothing else is rewritten, reflowed or
/// summarised: a policy that the app paraphrases is a different policy from the
/// one that was published, and the two would drift apart silently.
String renderPolicyForDisplay(String raw) =>
    raw.replaceAll(_htmlComment, '').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

/// Load the bundled policy. Returns null when the asset is missing or
/// unreadable — the caller renders an honest failure line rather than an empty
/// page that looks like a policy with no terms in it.
Future<String?> loadPrivacyPolicy() async {
  try {
    final raw = await rootBundle.loadString(kPrivacyPolicyAsset);
    final shown = renderPolicyForDisplay(raw);
    return shown.isEmpty ? null : shown;
  } catch (_) {
    return null;
  }
}


// ===========================================================================
// THE RENDERER, 2026-09-23.
//
// The page shipped the document through a single Text widget, so she read the
// MARKDOWN SOURCE: `#` before every heading, `**` around every emphasis, and —
// worst — the two Android permission tables as rows of `|` pipes. Measured at
// the page: `# ` present, `| 権限 |` present, `**` present.
//
// WHY THIS IS A RENDERER FIX AND NOT A DOCUMENT FIX, and the argument is
// better than "it looks untidy". The whole design rests on the app bundling
// the SOURCE file, so the shipped text cannot drift from the published text.
// Published as a page, markdown renders to headings and a table. Shipped
// through a Text widget it renders as syntax. So byte-identity of the file was
// guaranteeing byte-identity of nothing a reader sees, and the published and
// shipped views already differed — entirely in the renderer. Repairing the
// renderer is what makes that identity true. Any fix that reached for the
// WORDS would be the wrong fix.
//
// ⚑ THE SAFETY PROPERTY THIS PARSER OWES, because this is a legal surface and
// a renderer that silently drops a clause is worse than one that shows pipes:
// every word of the document must survive into a block. That is not a claim in
// a comment — test/services/privacy_policy_render_test.dart tokenises the
// source and the blocks and fails on any word that does not arrive.
// ===========================================================================

/// One rendered piece of the policy.
sealed class PolicyBlock {
  const PolicyBlock();
}

/// A `#`-prefixed heading, with the markers removed and the level kept.
final class PolicyHeading extends PolicyBlock {
  const PolicyHeading(this.level, this.text);
  final int level;
  final String text;
}

/// A run of ordinary lines, joined.
final class PolicyParagraph extends PolicyBlock {
  const PolicyParagraph(this.text);
  final String text;
}

/// A `-` or `*` list item, marker removed.
final class PolicyBullet extends PolicyBlock {
  const PolicyBullet(this.text);
  final String text;
}

/// A pipe table. [rows] excludes the `|---|---|` separator, which carries no
/// words — dropping it is the one thing this parser discards, and it is why
/// the word-preservation guard still holds.
final class PolicyTable extends PolicyBlock {
  const PolicyTable(this.rows, {required this.hasHeader});
  final List<List<String>> rows;
  final bool hasHeader;
}

bool _isTableSeparator(String line) {
  final cells = _cells(line);
  return cells.isNotEmpty &&
      cells.every((c) => c.isNotEmpty && RegExp(r'^[-: ]+$').hasMatch(c));
}

List<String> _cells(String line) {
  var t = line.trim();
  if (t.startsWith('|')) t = t.substring(1);
  if (t.endsWith('|')) t = t.substring(0, t.length - 1);
  return t.split('|').map((c) => c.trim()).toList();
}

/// Parse the policy into blocks. Total: any line that matches nothing becomes
/// a paragraph, so no input can fall through and vanish.
List<PolicyBlock> parsePolicyBlocks(String source) {
  final out = <PolicyBlock>[];
  final para = <String>[];
  void flush() {
    if (para.isEmpty) return;
    out.add(PolicyParagraph(para.join('\n')));
    para.clear();
  }

  final lines = source.split('\n');
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final t = line.trim();

    if (t.isEmpty) {
      flush();
      i++;
      continue;
    }

    final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(t);
    if (h != null) {
      flush();
      out.add(PolicyHeading(h.group(1)!.length, h.group(2)!.trim()));
      i++;
      continue;
    }

    if (t.startsWith('|')) {
      flush();
      final rows = <List<String>>[];
      var hasHeader = false;
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        final l = lines[i].trim();
        if (_isTableSeparator(l)) {
          hasHeader = rows.isNotEmpty;
        } else {
          rows.add(_cells(l));
        }
        i++;
      }
      out.add(PolicyTable(rows, hasHeader: hasHeader));
      continue;
    }

    final b = RegExp(r'^[-*]\s+(.*)$').firstMatch(t);
    if (b != null) {
      flush();
      out.add(PolicyBullet(b.group(1)!.trim()));
      i++;
      continue;
    }

    para.add(t);
    i++;
  }
  flush();
  return out;
}

/// Split a line into runs, marking the ones `**wrapped**` as bold. The markers
/// themselves are the only characters removed.
List<({String text, bool bold})> policyInlineRuns(String text) {
  final out = <({String text, bool bold})>[];
  final re = RegExp(r'\*\*(.+?)\*\*', dotAll: true);
  var last = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > last) {
      out.add((text: text.substring(last, m.start), bold: false));
    }
    out.add((text: m.group(1)!, bold: true));
    last = m.end;
  }
  if (last < text.length) out.add((text: text.substring(last), bold: false));
  return out.isEmpty ? [(text: text, bold: false)] : out;
}
