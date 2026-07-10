/// WS7 — app-level localization for the dignity-load-bearing surfaces:
/// the location-consent affordance, the live position/status line, and the
/// data-flow disclosure.
///
/// **Why a hand-written lookup map, not gen-l10n/ARB.** Per the BOD-17 fence
/// ("an ARB/gen or a simple lookup map is fine; keep it honest + minimal"),
/// this is a small, dependency-free lookup keyed on the resolved locale's
/// language code. It carries ONLY the strings HER must read to grant location
/// and to understand where her coordinates go — not the whole dev-facing
/// chrome. The catalog's own driver-facing prose (AlertExplainer, glossary,
/// DriveHudLocalizer) already localizes itself verbatim; this fills the gap
/// the app owns.
///
/// **D4 (load-bearing).** An English-only consent gate for a Japanese-reading
/// driver both breaches dignity AND functionally kills the position dot: she
/// cannot read the gate, so she cannot grant, so there is no dot. Localizing
/// this surface is the reach fix, not a nicety.
///
/// The Global*Localizations delegates (wired in main.dart) localize the
/// Material/Cupertino/Widgets chrome; this delegate localizes the app's own
/// consent/status/disclosure strings.
library;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/widgets.dart';

/// Minimal app-level localizations for sngnav-app's consent + status surface.
///
/// Resolution is by [Locale.languageCode]: `ja` -> Japanese, anything else
/// -> English (the honest default; en is the fallback tongue, ja is HER
/// tongue and the first supported locale).
class AppL10n {
  const AppL10n(this.locale);

  final Locale locale;

  bool get _ja => locale.languageCode == 'ja';

  /// The nearest [AppL10n] in the widget tree. Falls back to an English
  /// instance if the delegate is somehow not installed (defensive; the
  /// delegate loads synchronously so this should not happen in practice).
  static AppL10n of(BuildContext context) =>
      Localizations.of<AppL10n>(context, AppL10n) ??
      const AppL10n(Locale('en'));

  /// The delegate to add to `MaterialApp.localizationsDelegates`.
  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// Language codes this app localizes its own strings for.
  static const List<Locale> supportedLocales = [Locale('ja'), Locale('en')];

  // ===== Consent affordance (deny-by-default; nothing runs until she taps) =====

  String get locationNotShared =>
      _ja ? '位置情報はまだ共有されていません。' : 'Location not yet shared.';

  String get shareMyLocation => _ja ? '現在地を共有' : 'Share my location';

  String get useAkitaMock =>
      _ja ? '秋田のモック位置（開発用）' : 'Use Akita mock (dev)';

  String get clear => _ja ? 'クリア' : 'Clear';

  String get stop => _ja ? '停止' : 'Stop';

  // ===== Live position / mid-drive status =====

  String get locatingYou => _ja ? '現在地を取得しています…' : 'Locating you…';

  /// Amber DEV mock-position line (kept visually distinct from real GPS).
  String mockPositionStatus(String accuracyMeters) => _ja
      ? 'モック位置 · 秋田地点 ±$accuracyMeters m（開発用 — 実際のGPSではありません）'
      : 'Mock position · Akita station ±$accuracyMeters m (DEV — not real GPS)';

  String youAreHere(String accuracyMeters) =>
      _ja ? '現在地 · ±$accuracyMeters m' : 'You are here · ±$accuracyMeters m';

  /// GPS-unavailable line. The [reason] is produced by the geolocator layer
  /// (her_position.dart) as English; [_localizeReason] maps the known cases
  /// into HER language and passes anything unrecognized through honestly.
  String gpsUnavailable(String reason) {
    final r = _localizeReason(reason);
    return _ja
        ? 'GPS を取得できません — $r。地図は表示されたままです。ルート欄はタップで引き続き使えます。'
        : 'GPS unavailable — $r. The map remains; the route panel still works by tap.';
  }

  /// Maps the known [PositionUnavailable] reasons (defined verbatim in
  /// her_position.dart, same repo) to HER language. Unknown reasons pass
  /// through unchanged — an honest degrade, never a fabricated translation.
  ///
  /// NOTE (coupling flagged for AAA/follow-up): this matches on English
  /// substrings that live in her_position.dart. A cleaner design would have
  /// that layer emit a typed reason; kept string-matched here to avoid a
  /// wider refactor + retest of the finite-guard chokepoint this arc.
  String _localizeReason(String reason) {
    if (!_ja) return reason;
    if (reason.contains('services disabled')) {
      return '位置情報サービスが無効です';
    }
    if (reason.contains('permanently denied')) {
      return '位置情報の許可が恒久的に拒否されています（OSの設定で変更してください）';
    }
    if (reason.contains('permission denied')) {
      return '位置情報の許可が拒否されました';
    }
    if (reason.contains('non-finite')) {
      return 'GPS信号が乱れています（座標が不正です）';
    }
    if (reason.startsWith('GPS stream error')) {
      return 'GPSストリームのエラー';
    }
    if (reason.startsWith('GPS init error')) {
      return 'GPS初期化のエラー';
    }
    return reason;
  }

  // ===== Data-flow disclosure (task 3) — REGION-ACCURATE =====
  //
  // Honesty-traced to real code: coordinates are sent only when the caller's
  // position moves >= ~0.01 deg (~1 km) (see _maybeRefreshAdvisoriesForFix in
  // main.dart), and are REGION-GATED — a coordinate goes ONLY to the publisher
  // whose coverage includes it (AdvisoryService.fetchAtPoint +
  // services/provider_coverage.dart: a Japan point → 気象庁/JMA only, NWS is
  // never contacted; a US point → NWS only). They are held only in memory
  // (never persisted) and never sent to any server this app runs (there is
  // none). Foreground-only per AndroidManifest.xml (no ACCESS_BACKGROUND_LOCATION).
  //
  // The JA copy names 気象庁/JMA (the only service a Japanese-point driver's
  // coordinate reaches) and states that out-of-region services are not
  // contacted — it does NOT claim her coordinate goes to the NWS, because the
  // code will not call it. The EN copy is truthful for both regions (JMA in
  // Japan; NWS in the US) and states the same not-contacted-out-of-region fact.

  String get locationDisclosure => _ja
      ? '現在地を共有すると、周辺の気象情報を取得するため、走行約1kmごとに現在の座標が、'
          'その地域を管轄する公的な気象機関へ送信されます（日本国内では気象庁）。'
          '管轄外の気象機関へ座標が送信されることはありません。共有は任意で、'
          'アプリの使用中のみ行われ、端末に保存されず、'
          '本アプリ独自のサーバーへ送信されることはありません。'
      : 'When you share your location, your coordinates are sent — about once '
          'per kilometre of travel — only to the public weather service that '
          'covers your area (the JMA in Japan; the NWS in the United States), '
          'to fetch nearby advisories. A service that does not cover your '
          'location is never contacted. It is opt-in, used only while the app '
          'is open, is not stored on your device, and is never sent to this '
          "app's own servers.";

  // ===== Advisory ordering / NWS de-emphasis for the ja surface (task 4) =====

  /// Caption shown on the (English) NWS card when the surface is Japanese —
  /// the card stays present (hiding safety data would be dishonest) but is
  /// de-emphasized and marked as English reference material.
  String get englishReferenceNote => _ja ? '英語の情報（参考）' : 'English (reference)';

  // ===== WS5 announce affordance (D4 — HER-surface, was English-only) =====

  /// Label for the button that speaks + buzzes the current hazard.
  String get announceToDriver =>
      _ja ? '運転者へ知らせる（音声＋振動）' : 'Announce to driver (audio + haptic)';

  /// Helper under the announce button when the current condition IS announced
  /// (>= warning). [severityName] is the technical severity token (warning /
  /// critical), kept verbatim. The on-device HEAR/FEEL bound is stated
  /// honestly (OPS-066 — not verified without a device).
  String announceFiresHelper(String severityName) => _ja
      ? '音声＋振動で発報します（重要度: $severityName）。'
          '端末での聴取・体感は本環境では未検証です。'
      : 'Fires audio + haptic (severity: $severityName). '
          'On-device HEAR/FEEL not verified in this env.';

  /// Helper under the announce button when the current condition is info-class
  /// (announced on neither channel — parity with the voice gate).
  String get announceInfoHelper => _ja
      ? '情報クラス — どちらのチャンネルでも発報しません（音声ゲートと同じ扱い）。'
      : 'info-class — not announced on either channel '
          '(parity with the voice gate).';

  // ===== Advisory card states (D4 — HER-surface, was English-only) =====

  /// Empty-state: honest no-data render (never a stale snapshot fallback).
  String get advisoryNoneActive => _ja
      ? 'この地点に有効な警報・注意報はありません。'
      : 'No active advisories at this location.';

  /// Error-state prefix for a failed advisory fetch. [message] is the
  /// exception text, passed through verbatim (an honest degrade).
  String advisoryFetchFailed(String message) => _ja
      ? '警報・注意報の取得に失敗しました: $message'
      : 'Advisory fetch failed: $message';

  /// Before any advisory fetch has run.
  String get advisoryNoFetchYet => _ja ? '（まだ取得していません）' : '(no fetch yet)';

  /// The initial "Fetch" action.
  String get advisoryFetch => _ja ? '取得' : 'Fetch';

  /// The "Re-fetch" action (a result is already shown).
  String get advisoryReFetch => _ja ? '再取得' : 'Re-fetch';

  /// The "Retry" action after an error.
  String get retry => _ja ? '再試行' : 'Retry';

  /// Per-publisher soft-error line. [publisher] is the source label
  /// (verbatim); [message] is the exception text (verbatim).
  String advisoryPublisherErrored(String publisher, String message) => _ja
      ? '配信元 $publisher でエラー: $message'
      : 'Publisher $publisher errored: $message';

  // ===== C6 ログを共有 — beta feedback share-log surface (BETA_PLAN fix #8) =====
  //
  // Honesty-traced to real code: the share fires ONLY from the button tap
  // (services/log_share.dart — no auto-telemetry, no background path, no
  // accounts), and the payload is strictly build-header + the local error
  // log (services/error_log.dart records only timestamp + source + error +
  // stack; no location history is stored, and the action adds none).

  /// Section title for the feedback / share-log card.
  String get logShareSectionTitle =>
      _ja ? 'フィードバック — ログを共有' : 'Feedback — share log';

  /// Label for the one-tap share-log action (BETA_PLAN's ログを共有).
  String get shareLog => _ja ? 'ログを共有' : 'Share log';

  /// Status line when the crash boundary could not resolve a log file
  /// (path_provider unavailable) — the action is honestly disabled.
  String get logShareUnavailable => _ja
      ? 'エラーログはこの環境では利用できません。'
      : 'The error log is unavailable in this environment.';

  /// Status line when the log exists but holds no records. Sharing stays
  /// possible and sends an honest "log is empty" payload (never fabricated
  /// content).
  String get logShareEmpty => _ja
      ? 'ログは空です（クラッシュ・エラーの記録はありません）。'
      : 'The log is empty (no crash or error records).';

  /// Status line when error records are present to share.
  String get logShareHasRecords => _ja
      ? 'エラー記録があります。共有ボタンでベータ・フィードバックとして送れます。'
      : 'Error records are present. Use the share button to send them as '
          'beta feedback.';

  /// Consent-framing disclosure under the share button (mirrors the
  /// location-disclosure discipline: state WHERE the data goes BEFORE the
  /// tap).
  String get logShareDisclosure => _ja
      ? '共有はこのボタンを押したときだけ行われます。自動送信・テレメトリはなく、'
          'アカウントも不要です。ログに含まれるのはエラーの記録のみで、'
          '位置情報の履歴は含まれません。送信先は端末の共有画面で自分で選べます。'
      : 'Sharing happens only when you tap this button — no automatic '
          'upload, no telemetry, and no account. The log contains only '
          'error records; it holds no location history. You choose the '
          "destination in your device's share sheet.";
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'ja';

  @override
  Future<AppL10n> load(Locale locale) =>
      SynchronousFuture<AppL10n>(AppL10n(locale));

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}
