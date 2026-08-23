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
    if (reason.contains('service check timed out')) {
      return '位置情報サービスの確認に時間がかかりすぎました（端末が応答しません）';
    }
    if (reason.contains('permission check timed out')) {
      return '位置情報の許可状態の確認に時間がかかりすぎました（端末が応答しません）';
    }
    if (reason.contains('permission request timed out')) {
      return '位置情報の許可の応答がありませんでした（確認画面が閉じられていません）';
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
    if (reason.contains('stream ended by the platform')) {
      return 'GPSの受信が端末側で終了しました';
    }
    if (reason.startsWith('GPS stream error')) {
      return 'GPSストリームのエラー';
    }
    if (reason.startsWith('GPS init error')) {
      return 'GPS初期化のエラー';
    }
    return reason;
  }

  // ===== Data-flow disclosure (task 3, corrected B28) — WIRE-ACCURATE =====
  //
  // Honesty-traced to the real wire, read at the resolved package sources
  // (pubspec.lock), not at the docs:
  //
  // - JAPAN: condition_aggregator_jma 0.3.0 maps the point to prefecture
  //   code(s) ON-DEVICE (`prefectureCodesForPoint`, jma_advisory_provider.dart
  //   :163) and requests only
  //   `https://www.jma.go.jp/bosai/warning/data/warning/{prefectureCode}.json`
  //   (:53, :342). HER coordinates NEVER leave the device for Japan — the
  //   previous copy claimed they were "sent to the JMA", which was FALSE.
  // - UNITED STATES: noaa_nws_adapter 0.0.8 sends the actual point —
  //   `GET https://api.weather.gov/alerts/active?point={lat},{lon}`
  //   (noaa_nws_client.dart:307) — and short-circuits out-of-coverage points
  //   BEFORE any URI is constructed (:305), so a non-US coordinate never
  //   reaches the NWS either.
  // - JMA wire (Japan), all region/prefecture-keyed public data — precise
  //   coordinates are NOT sent: (1) the prefecture warning file
  //   warning/{prefectureCode}.json (condition_aggregator_jma provider,
  //   prefectureCodesForPoint on-device); (2) the regional AMeDAS observation
  //   (jma_fetch.dart, Akita station 32402); (3) the prefecture forecast
  //   forecast/{areaCode}.json (jma_forecast_fetch.dart, Akita 050000).
  // - Cadence: the warning refresh fires about once per ~1 km of travel
  //   (_maybeRefreshAdvisoriesForFix in main.dart, 0.01° gate); the whole JMA
  //   set (AMeDAS + forecast via _refreshJma, warning via the advisory refresh)
  //   also fires on a 10-minute foreground ticker (_jmaTicker, main.dart) even
  //   while stopped. Coordinates are held only in memory, never persisted,
  //   never sent to any server this app runs (there is none). Foreground-only
  //   per AndroidManifest.xml.
  //
  // BOTH locales state both regional facts: locale is NOT location — a
  // Japanese-reading driver in the US would hit the NWS point path, so the ja
  // copy claiming "coordinates never leave the device" unconditionally would
  // itself be false. Each claim is scoped to its region.

  String get locationDisclosure => _ja
      ? '現在地を共有すると、周辺の警報・注意報の取得に使われます。'
          '日本国内では座標が端末の外へ送信されることはありません — '
          '端末内で現在地から都道府県・地域を判定し、気象庁の公開データに対して、'
          '都道府県コードによる警報・注意報、地域のアメダス観測、'
          '都道府県の予報を要求します。いずれも都道府県・地域単位の公開データで、'
          '正確な座標は送信しません。警報・注意報は走行約1kmごとに更新され、'
          'これらの取得は使用中であれば停車していても約10分ごとに行われます。'
          'アメリカ合衆国内では、地点の警報を取得するため座標が'
          '米国国立気象局（NWS）へ送信されます。'
          '現在地を管轄しない気象機関へ問い合わせることはありません。'
          '共有は任意で、アプリの使用中のみ行われ、位置情報は端末に保存されず、'
          '本アプリ独自のサーバーへ送信されることもありません。'
      : 'When you share your location, it is used to fetch nearby weather '
          'advisories. In Japan your coordinates never leave the device: the '
          'app determines your prefecture and region on the device and '
          'requests, from the JMA public data, the warning file for your '
          'prefecture code, the regional AMeDAS observations, and the '
          'forecast for your prefecture — all prefecture- or region-keyed '
          'public data, so your exact coordinates are not sent. The warning '
          'file is refreshed about once per kilometre of travel; all three '
          'are re-requested about every 10 minutes while the app is open, '
          'even when stopped. In the United States your coordinates '
          'are sent to the NWS to fetch alerts for your exact point. A '
          'service that does not cover your location is never contacted. '
          'Sharing is opt-in, happens only while the app is open, and your '
          "location is never stored on the device or sent to this app's own "
          'servers.';

  // ===== Other-egress disclosure (B27 + B30) — the rest of the wire =====
  //
  // The coordinates-story above covers the advisory fetch. These are the
  // OTHER network egresses the app actually has, stated on the same card so
  // the disclosure she decides with matches the whole real wire:
  //
  // - OSRM (B27): tap-route sends full-precision origin+destination to
  //   router.project-osrm.org (route_fetch.dart / main.dart _fetchRoute) —
  //   consent-gated pre-send since B27; nothing is sent until she agrees.
  // - OSM tiles (B30): akita_map.dart TileLayer urlTemplate
  //   'https://tile.openstreetmap.org/{z}/{x}/{y}.png' — the bundled offline
  //   archive serves first; the network fallback (uncovered tiles / online)
  //   sends viewport tile requests + her IP to tile.openstreetmap.org.
  // - Network TTS (B30): spoken alerts prefer the bundled on-device audio
  //   (voice/bundled_audio_engine.dart); when the OS speech engine falls back
  //   and its selected voice is network-bound (voice_lane_readiness.dart
  //   reads exactly this), the spoken text may route via the OS voice vendor.

  String get egressDisclosure => _ja
      ? 'このほかに端末の外と通信するのは次の場合のみです。'
          '【経路計算】地図で選んだ出発地と目的地の座標は、確認画面で同意した'
          '場合にのみ、公開OSRMデモサーバー（router.project-osrm.org）へ'
          '送信されます。同意するまで送信されません。'
          '【地図タイル】オフライン収録範囲外の地図を表示するとき、'
          'tile.openstreetmap.org が表示範囲のタイル要求とIPアドレスを'
          '受け取ります。'
          '【音声】音声警告は端末に同梱した音声を優先します。端末の音声エンジンが'
          'ネットワーク音声を使う場合、読み上げる文がOSの音声提供元を'
          '経由することがあります。'
      : 'The only other times this app talks to the outside: '
          'Route calculation — the origin and destination you tap are sent to '
          'the public OSRM demo server (router.project-osrm.org) only after '
          'you agree on the confirmation dialog; nothing is sent until you '
          'agree. Map tiles — when the map shows areas outside the bundled '
          'offline archive, tile.openstreetmap.org receives tile requests for '
          'the visible area and your IP address. Voice — spoken alerts prefer '
          'the bundled on-device audio; if the device speech engine uses a '
          'network voice, the spoken text may pass through the OS voice '
          'vendor.';

  // ===== OSRM pre-send route consent (B27) — ja-primary, asked ONCE =====

  String get routeConsentTitle =>
      _ja ? '経路計算のための送信の確認' : 'Send coordinates for route calculation?';

  /// The pre-send disclosure she decides with. States exactly what leaves
  /// the device (the two tapped coordinates), where it goes (the public
  /// OSRM demo server), and why — BEFORE anything is sent.
  String get routeConsentBody => _ja
      ? '出発地と目的地の座標が、経路計算のため公開OSRMデモサーバー'
          '（router.project-osrm.org）に送信されます。よろしいですか。'
          'この選択は記憶され、あとから変更できます。'
      : 'The origin and destination coordinates you tapped will be sent to '
          'the public OSRM demo server (router.project-osrm.org) to '
          'calculate the route. Is that OK? Your choice is remembered and '
          'can be changed later.';

  String get routeConsentAccept => _ja ? '送信して経路を取得' : 'Send and fetch route';

  String get routeConsentDecline => _ja ? '送信しない' : 'Do not send';

  /// Honest neutral state after a decline/dismiss: no request was made,
  /// coordinates did not leave the device. Not an error — the router was
  /// never asked.
  String get routeConsentDeclinedMessage => _ja
      ? '経路は取得していません — 座標は送信されていません。'
      : 'No route was fetched — your coordinates were not sent.';

  /// Path back after a persisted decline (dignity: a remembered "no" must
  /// never be a locked door).
  String get routeConsentChangeChoice => _ja ? '選択を変更' : 'Change choice';

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

  /// Degraded empty-state: the fetch produced NO advisories AND at least one
  /// covering publisher errored — whether a warning is in force is UNKNOWN.
  /// Rendering the positive all-clear here would be a fabricated clear: the
  /// absence is a fetch failure, not a publisher statement. Absence must
  /// never render as calm.
  String get advisoryFetchUnknown => _ja
      ? '警報・注意報を取得できませんでした — 有効な警報・注意報の有無は不明です。'
      : 'Advisory fetch failed — whether any warning or advisory is in '
          'force is unknown.';

  /// Incomplete-lookup state: the result carries no proof that every source
  /// answered (`canAssertNoAdvisory` false) and yet no covering publisher
  /// reported an error and the point IS covered — so neither of the two
  /// named causes above applies. We cannot say what happened, and therefore
  /// cannot say the sky is clear. The fail-safe backstop: any advisory
  /// result that cannot account for its own completeness renders here rather
  /// than as the positive all-clear. Deliberately NOT a hazard claim — an
  /// outage is an unknown, not a warning, and crying wolf would teach HER to
  /// ignore the instrument.
  String get advisoryLookupIncomplete => _ja
      ? '警報・注意報の照会が完了したか確認できません — '
          '有効な警報・注意報の有無は不明です。'
      : 'Cannot confirm the advisory lookup was complete — whether any '
          'warning or advisory is in force is unknown.';

  /// Measured-weather lane NOT YET READ this session — the cold-start state.
  /// The invisible-ice and turmoil watches are non-firing because nobody has
  /// been asked yet, which looks EXACTLY like a measured all-clear on the
  /// drive brain's floor. Says so plainly instead. Deliberately not a hazard
  /// claim: an unread feed is an unknown, not a warning.
  String get measuredWatchNotYetRead => _ja
      ? '気象観測をまだ取得していません — 路面凍結・荒天の測定状況は不明です。'
      : 'The weather observation has not been read yet — the measured '
          'road-ice and turmoil watches are unknown.';

  /// Measured-weather lane READ AND FAILED. Distinct from the cold start
  /// above: something went wrong, and the resulting non-firing watches say
  /// nothing about the road. Same anti-cry-wolf discipline — we report the
  /// outage, we do not invent a hazard out of it.
  String get measuredWatchFeedLost => _ja
      ? '気象観測を取得できませんでした — 路面凍結・荒天の測定状況は不明です。'
      : 'The weather observation could not be read — the measured road-ice '
          'and turmoil watches are unknown.';

  /// Uncovered-point state: NO supported publisher covers this point, so
  /// nobody was queried (no request left the device) and NOBODY made a
  /// statement. The positive all-clear line would be a publisher claim
  /// nobody made; this line says honestly that it cannot be checked here.
  String get advisoryNoCoveringPublisher => _ja
      ? 'この地点を管轄する対応データ提供元がありません — '
          '警報・注意報の有無はこのアプリでは確認できません。'
      : 'No supported weather publisher covers this location — whether any '
          'warning is in force cannot be checked by this app.';

  /// Stale-retention banner over advisories kept from a PRIOR successful
  /// fetch after the latest fetch failed. Retention is bounded: an
  /// expires-bearing advisory is kept only within the publisher's declared
  /// validity; a null-expires advisory (JMA warnings) is kept only within a
  /// bounded synthetic window anchored to the last successful fetch. Either
  /// way it is DROPPED once its bound passes, and the clear is never retained.
  /// [minutes] is the age of the retained data.
  String advisoryRetainedStale(int minutes) {
    final age = _formatMinutes(minutes);
    return _ja
        ? '未更新 — $age前に取得した警報を表示しています（最新の取得に失敗）。'
            '有効期限または保持期限を過ぎたものは表示しません。'
        : 'Stale — showing advisories fetched $age ago (latest fetch '
            'failed). Advisories past their validity or retention window '
            'are dropped.';
  }

  /// Minutes below an hour, hours+minutes above (retention is bounded by
  /// the publisher's declared expiry, so days-scale ages cannot occur).
  String _formatMinutes(int minutes) {
    if (minutes < 60) return _ja ? '$minutes分' : '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return _ja ? '$h時間$m分' : '${h}h ${m}m';
  }

  // ===== JMA feed-loss panel (N15 — the screen must match the speaker) =====

  /// Prominent staleness label over the RETAINED observation shown after a
  /// failed JMA fetch. The retained fields ARE shown (the voice may be
  /// warning from them — the stale black-ice re-warn); this label is the
  /// on-screen guarantee she is not reading them as live. [minutes] is the
  /// age of the retained observation.
  String jmaRetainedStale(int minutes) {
    final age = _formatMinutes(minutes);
    return _ja
        ? '未更新 — $age前の観測を表示しています（最新の取得に失敗）。'
        : 'Stale — showing the observation from $age ago (latest fetch '
            'failed).';
  }

  /// Feed-loss with NO valid observation held (none, unparseable stamp, or
  /// past the 60-min retain bound): the observation lane is honestly empty.
  String get jmaNoValidObservation => _ja
      ? '60分以内の有効な観測を保持していません。'
      : 'No observation within the 60-minute retain window is held.';

  /// Caption under the visible forecast-memory card (C2 RED-1 counterpart).
  /// [time] is the local clock time the memory was captured — before
  /// departure, while the network was still alive.
  String forecastMemoryCaption(String time) => _ja
      ? '出発前 $time に取得した気象庁の予報 — 観測ではありません。'
      : 'JMA forecast fetched at $time, before departure — a forecast, not '
          'an observation.';

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

  // ===== Voice-lane readiness (A1) + speech-unverified chip (Tier-1) =====

  /// Pre-drive caution shown ONLY when the voice-lane readiness read proved
  /// the ja lane is network-bound (jaNetworkOnly) or absent (noJaVoice).
  /// unknown shows NOTHING — never a false warning off-device.
  String get voiceOfflineCaution => _ja
      ? 'オフライン音声が未インストールです。'
          '電波のない場所では音声警告が出ない可能性があります。'
      : 'Offline Japanese voice not installed — voice alerts may not sound '
          'where there is no signal.';

  /// In-drive HUD chip while the LAST announce could not be verified as
  /// delivered (platform completion report missing / failure). Cleared on
  /// the next verified speak.
  String get speechUnverifiedChip =>
      _ja ? '音声警告を確認できませんでした' : 'Voice alert could not be verified';

  /// In-drive HUD chip while the LAST tactile cue that was OWED did not land
  /// (no vibrator / platform fault / platform never answered). Cleared on the
  /// next cue the platform accepts.
  ///
  /// The tactile twin of [speechUnverifiedChip], and it did not exist until
  /// 2026-08-22. Measured on a device the day before: an announce at severity
  /// `critical` dispatched Japanese speech and produced ZERO vibrations, and
  /// nothing anywhere said so. For a deaf or hard-of-hearing driver — and for
  /// any driver whose ears are useless inside a roaring whiteout — this is not
  /// the second channel. It is the only one.
  String get hapticUnverifiedChip =>
      _ja ? '振動警告を確認できませんでした' : 'Vibration alert could not be verified';

  /// Shown INSIDE the media-muted caution when the tactile channel has also
  /// reported an owed cue lost.
  ///
  /// [mediaMutedCaution] promises her 「振動でお知らせします」 and offers a button
  /// that says 「承知しました（振動のみで続行）」. If the vibration channel is not
  /// landing either, that promise is false and she is being asked to consent
  /// to it. This line withdraws it in the same glance, and names what is
  /// actually left: the screen.
  /// PRE-DRIVE caution when the platform reports NO vibrator at all.
  ///
  /// The stronger, measured statement AAA's G-3 makes possible: not *"we could
  /// not verify"* after a warning was already lost, but *"this device has
  /// none"* before she commits to the drive. Rendered ONLY on a `false`
  /// answer — `null` (unreadable / off-mobile / test binding) renders nothing,
  /// because a caution about a device that may vibrate perfectly well is a
  /// false alarm on the channel that can least afford one.
  String get hapticUnavailableCaution => _ja
      ? 'この端末は振動に対応していません。'
          '音が聞こえない場合、警告は画面表示のみになります。'
      : 'This device reports no vibration. If you cannot hear the sound, '
          'warnings will be on screen only.';

  String get hapticUnverifiedInMutedNote => _ja
      ? '振動も確認できませんでした。警告は画面表示のみです。'
      : 'Vibration could not be verified either — warnings are on-screen only.';

  // ===== Tier-2 audio readiness — media-volume-zero probe =====
  //
  // Shown ONLY when the read-only platform probe PROVED the media stream is
  // at zero (null = probe unavailable = NOTHING). Informed acknowledgment,
  // never a block: haptic alerts are already unconditional, the driver
  // always drives, and we NEVER touch her volume (the Tier-3 dignity
  // boundary the Chair holds).

  /// Strong pre-drive caution when no spoken safety alert can be heard.
  ///
  /// ⚑ REWRITTEN 2026-08-22 on AAA's PUSHBACK (G-1), which found two defects
  /// in the one sentence this used to be — *"メディア音量がゼロです。音声警告が
  /// 聞こえません。振動でお知らせします。"*:
  ///
  /// (a) **the stated cause was false.** Since `isStreamMute` reached the
  ///     probe the same day, this row also fires at a NON-ZERO index on a
  ///     muted stream — measured on AVD `sngnav_api30` at index 5 of 15.
  ///     "Silent" is true of both; "volume is zero" was true of one.
  /// (b) **the second clause promised a delivery the app only ATTEMPTS.**
  ///     Future tense, unconditional, about the one channel that had no
  ///     prospective probe. AAA: *claimed delivery, earned attempt.*
  ///
  /// The wording below is AAA's, verbatim from its verdict, and carries three
  /// checkable properties: the cause is stated as silent; the tactile channel
  /// is attempted, not promised; and what REMAINS — the screen — is named,
  /// because a caution that removes a channel without naming what is left is
  /// not actionable.
  String get mediaMutedCaution => _ja
      ? '音声警告は聞こえません（メディア音声が無音です）。'
          '警告は画面に表示され、振動も試みますが、この端末では未確認です。'
      : 'Spoken alerts cannot be heard — the media stream is silent. '
          'Warnings still appear on screen; vibration is attempted but is '
          'not verified on this device.';

  /// Acknowledge action on the media-muted caution.
  ///
  /// ⚑ RENAMED 2026-08-22 on AAA's PUSHBACK (G-2). This used to read
  /// 「承知しました（振動のみで続行）」 — asking her to consent to, and then
  /// labelling her whole drive by, a channel the app had never verified. The
  /// measured fact is the AUDIO loss, not the haptic presence, so the mode is
  /// named after what was measured.
  String get mediaMutedAckButton => _ja
      ? '承知しました（音声なしで続行）'
      : 'Understood — continue without spoken alerts';

  /// Compact line after acknowledgment collapses the caution.
  String get mediaMutedAckedLine =>
      _ja ? '音声なしモード承知済み' : 'No-spoken-alerts mode acknowledged';

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

  // ===== Ring-2 運転日記 — post-drive diary surface (three-month plan §2) =====
  //
  // Honesty-traced to real code: entries persist ONLY to a local file
  // (services/drive_diary.dart — zero telemetry), record no coordinates
  // (the only place is the one SHE TYPES), and leave the device only via
  // the explicit share tap.

  /// Section title for the drive-diary card.
  String get diarySectionTitle =>
      _ja ? '運転日記 — 走った後にひとこと' : 'Drive diary — a note after the drive';

  /// Opens the post-drive entry form.
  String get diaryWriteButton => _ja ? '日記を書く' : 'Write an entry';

  /// One-tap share of the whole diary (log-share idiom).
  String get diaryShareButton => _ja ? '日記を共有' : 'Share diary';

  /// Status line when the documents directory could not be resolved —
  /// actions are honestly disabled.
  String get diaryUnavailable => _ja
      ? '運転日記はこの環境では利用できません。'
      : 'The drive diary is unavailable in this environment.';

  /// Status line when no entries exist yet.
  String get diaryEmpty => _ja
      ? '日記はまだありません。走った後に、路面のようすをひとこと残せます。'
      : 'No entries yet. After a drive, you can leave a note about the road.';

  /// Status line when entries are present.
  String get diaryHasEntries => _ja
      ? '日記の記録があります。共有ボタンで送れます。'
      : 'Diary entries are present. Use the share button to send them.';

  /// Form: road-condition question.
  String get diaryRoadQuestion => _ja ? '路面はどうでしたか？' : 'How was the road?';

  /// Form: advisory-experience question.
  String get diaryAdvisoryQuestion =>
      _ja ? 'このアプリの警告はどうでしたか？' : "How were this app's warnings?";

  /// Form: optional area field label (her words, never a sensor read).
  String get diaryAreaLabel =>
      _ja ? '地域（任意・例：横手市郊外）' : 'Area (optional, e.g. rural Yokote)';

  /// Form: optional free-text field label.
  String get diaryNoteLabel => _ja ? 'メモ（任意）' : 'Note (optional)';

  /// Form: note-field hint — carries the too-late vs false-alarm
  /// disambiguation the chip label cannot (it clips at dialog width).
  String get diaryNoteHint => _ja
      ? '例：橋の上で警告が遅かった、誤警告だった など'
      : 'e.g. the warning came late on the bridge, or was a false alarm';

  /// Form: save action.
  String get diarySaveButton => _ja ? '保存' : 'Save';

  /// Form: cancel action.
  String get diaryCancelButton => _ja ? 'キャンセル' : 'Cancel';

  /// Post-save confirmation (SnackBar) — names where the entry went.
  String get diarySavedLine => _ja
      ? '保存しました（この端末の中だけに記録されます）'
      : 'Saved (recorded only on this device).';

  /// Honest failure line when the entry could not be persisted.
  String get diarySaveFailedLine => _ja
      ? '保存できませんでした。もう一度お試しください。'
      : 'Could not save. Please try again.';

  /// Consent-framing disclosure under the diary actions (location-disclosure
  /// discipline: state WHERE the data goes BEFORE the tap).
  String get diaryDisclosure => _ja
      ? '日記はこの端末の中だけに保存されます。自動送信は一切なく、'
          '位置情報は記録されません（地域欄はあなたが書いた言葉だけです）。'
          '共有ボタンを押したときだけ、端末の共有画面で選んだ相手に送られます。'
      : 'The diary is stored only on this device. Nothing is sent '
          'automatically, and no location is recorded (the area '
          'field is only your own words). It leaves the device only when '
          'you tap share and choose a destination yourself.';
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
