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
