/// WS7 — app-level localization for the dignity-load-bearing surfaces:
/// the location-consent affordance, the live position/status line, and the
/// data-flow disclosure.
///
/// **Why a hand-written lookup map, not gen-l10n/ARB.** Per the BOD-17 fence
/// ("an ARB/gen or a simple lookup map is fine; keep it honest + minimal"),
/// this is a small, dependency-free lookup keyed on the resolved locale's
/// language code. It carries ONLY the strings the driver must read to grant location
/// and to understand where her coordinates go — not the whole dev-facing
/// chrome. The catalog's own driver-facing prose (AlertExplainer, glossary,
/// DriveHudLocalizer) already localizes itself verbatim; this fills the gap
/// the app owns.
///
/// **Dignity (load-bearing).** An English-only consent gate for a Japanese-reading
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

import '../services/invisible_ice_watch.dart' show InvisibleIceWatchResult;
import '../services/turmoil_watch.dart' show TurmoilWatchState, turmoilRowText;

/// Minimal app-level localizations for sngnav-app's consent + status surface.
///
/// Resolution is by [Locale.languageCode]: `ja` -> Japanese, anything else
/// -> English (the honest default; en is the fallback tongue, ja is the
/// driver's tongue and the first supported locale).
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

  /// The row's end-sharing control after location is off for this app. Same
  /// action as [stop]; "Stop" would be offered for a session that never
  /// started, beside words saying the app has no access (decided 2026-09-13).
  String get close => _ja ? '閉じる' : 'Close';

  // ===== Live position / mid-drive status =====

  String get locatingYou => _ja ? '現在地を取得しています…' : 'Locating you…';

  /// Amber DEV mock-position line (kept visually distinct from real GPS).
  String mockPositionStatus(String accuracyMeters) => _ja
      ? 'モック位置 · 秋田地点 ±$accuracyMeters m（開発用 — 実際のGPSではありません）'
      : 'Mock position · Akita station ±$accuracyMeters m (DEV — not real GPS)';

  /// The words on the map when her position is lost.
  String get positionUnknownLabel => _ja ? '現在地不明' : 'Position unknown';

  /// The words on the map when her position is known but the map edge cuts
  /// its mark, in part or whole.
  String get positionOffMapLabel =>
      _ja ? '現在地は地図の外' : 'Position off this map';

  /// The control under the map that brings the camera back to her and
  /// resumes follow, shown only while a hand has paused it.
  String get returnToMyPosition => _ja ? '現在地に戻る' : 'Back to my position';

  String youAreHere(String accuracyMeters) =>
      _ja ? '現在地 · ±$accuracyMeters m' : 'You are here · ±$accuracyMeters m';

  /// Status line under the map when the driver's position is LOST — past the position
  /// controller's honesty horizon. It says how old the last trusted position
  /// is, never a radius: in `lost` the controller no longer vouches for one,
  /// and with no trusted fix ever the radius is infinite. This line used to
  /// read 「現在地 不明 · 最後の位置 ±Infinitym」.
  ///
  /// Same shape as the dead-reckoning line (「GPS 途絶（推測航法） · 最後の位置
  /// ±135m」), with the age where the radius was. The prefix is
  /// `DriveHudLocalizer.modeLabel(LocalizationMode.lost)`, verbatim, so the
  /// map's status line and the drive HUD name the state with one vocabulary.
  ///
  /// [secondsSinceTrustedFix] is `LocalizationEstimate.secondsSinceTrustedFix`
  /// as of the controller's last update. Not finite, or negative, means no
  /// trusted fix has ever been seen, and no age is claimed. The age is a lower
  /// bound: whole minutes, rounded down, from an estimate the position
  /// watchdog refreshes on its own cadence. Past 24 hours it still reads true
  /// (「25時間0分前」).
  String positionLostStatus(double secondsSinceTrustedFix) {
    final prefix = _ja ? '現在地 不明' : 'Position unknown';
    if (!secondsSinceTrustedFix.isFinite || secondsSinceTrustedFix < 0) {
      return _ja ? '$prefix · 最後の位置 なし' : '$prefix · no last position';
    }
    final minutes = secondsSinceTrustedFix ~/ 60;
    if (minutes < 1) {
      return _ja
          ? '$prefix · 最後の位置 1分以内'
          : '$prefix · last position within 1 min';
    }
    final age = _formatMinutes(minutes);
    return _ja ? '$prefix · 最後の位置 $age前' : '$prefix · last position $age ago';
  }

  /// Status line under the map in DEAD RECKONING: the mode, and the radius
  /// around her last trusted position. [modeLabel] is
  /// `DriveHudLocalizer.modeLabel` for the same locale, so the line and the
  /// drive panel name the state with one vocabulary; [radiusMeters] is already
  /// formatted. The Japanese is byte-identical to the line it replaces, which
  /// joined a Japanese literal to a mode label hardcoded to `'ja'`, so an
  /// English device read 「GPS 途絶（推測航法） · 最後の位置 ±135m」 (2026-09-13).
  String positionDeadReckoningStatus(String modeLabel, String radiusMeters) =>
      _ja
          ? '$modeLabel · 最後の位置 ±${radiusMeters}m'
          : '$modeLabel · last position ±$radiusMeters m';

  /// The words on the map when location is off for this app: permission
  /// denied, now or for good (`isLocationRefusal`). They describe the setting
  /// and never say that she refused: a denial can happen without her taking
  /// any action. Decided 2026-09-13; 位置情報 is the word in the dialog she saw.
  /// English: "No location access", decided on the render the same day.
  /// "Location off" shared its first-word shape and the word "off" with
  /// "Position off this map", and blurred the two differed by 9.0/255.
  String get locationOffLabel =>
      _ja ? '位置情報オフ' : 'No location access';

  /// The line under the map when location is off for this app. Its head is
  /// [locationOffLabel], the same bytes as the words on the map. Only a denial
  /// for good gets the device-settings hint: the platform no longer shows the
  /// dialog then, and without the hint she has no way back. Ruled 2026-09-13,
  /// byte-exact. The English sentence after the dash re-decided 2026-09-14: it
  /// said "this app is not allowed to access location" under a head that
  /// already said so, and now adds only that it is a permission, and this
  /// app's. Japanese unchanged.
  ///
  /// [routeSettingOpen]: where route setting is closed (the IVI with no
  /// vehicle signal, decided 2026-09-14), the line must not say the route panel
  /// works, so its last sentence is left out. It has no default: a line that
  /// forgot to ask would say it.
  String locationOffStatus({
    required bool permanently,
    required bool routeSettingOpen,
  }) {
    final head = locationOffLabel;
    if (_ja) {
      final route = routeSettingOpen ? _routePanelWorksJa : '';
      return permanently
          ? '$head'
              ' — このアプリには位置情報へのアクセスが許可されていません。変更する場合は端末の設定から行えます。地図は表示されたままです。$route'
          : '$head'
              ' — このアプリには位置情報へのアクセスが許可されていません。地図は表示されたままです。$route';
    }
    final remains = routeSettingOpen
        ? 'The map remains; the route panel still works by tap.'
        : 'The map remains.';
    return permanently
        ? '$head'
            ' — location permission is off for this app. If you want to change this, you can do so in the device settings. $remains'
        : '$head'
            ' — location permission is off for this app. $remains';
  }

  static const String _routePanelWorksJa = 'ルート欄はタップで引き続き使えます。';

  // ===== Setting a route (decided 2026-09-14) =====
  //
  // A touch on her map sets no route point and clears none. On a phone with
  // no motion signal a route is set only through the route act, started from
  // a control; on the IVI with no vehicle signal route setting is closed.

  /// Shown on a phone where route setting is closed, and beside the route act.
  /// Ruled 2026-09-14, byte-exact. It states the condition; it does not tell
  /// her to stop the car. Never shown on a host where no state of the car
  /// opens route setting: there [routeSettingClosedOnThisDevice] is.
  String get routeSettingWhenStopped =>
      _ja ? 'ルートは停車中に設定できます。' : 'Routes can be set when the car is stopped.';

  /// The route panel's line on a host that reads no vehicle signal, where
  /// route setting is closed and nothing opens it. Ruled 2026-09-14,
  /// byte-exact: it states the state, with no cause, no instruction and no
  /// stop. "In this app" is load-bearing: the car's own navigation on the same
  /// screen may set routes.
  String get routeSettingClosedOnThisDevice => _ja
      ? 'この端末では、このアプリでルートを設定できません。'
      : 'Routes cannot be set in this app on this device.';

  /// The route section's title. Ruled 2026-09-14, byte-exact: no driving, no
  /// gesture, no promise, and the snow condition once. Was 'Route — tap A then
  /// B (driving, no snow-aware yet)' in both locales.
  String get routeSectionTitle =>
      _ja ? 'ルート（雪を考慮しません）' : 'Route (does not consider snow)';

  /// The control that opens the route act, and the act's own title. Added
  /// 2026-09-14, not yet reviewed on a render.
  String get routeActOpen => _ja ? 'ルートを設定' : 'Set a route';

  /// The route act's line before start A is chosen. Added 2026-09-14, not yet
  /// reviewed on a render. "The map" is the act's own map, not hers.
  String get routeActChooseStart => _ja
      ? '地図をタップして出発地 A を選んでください。'
      : 'Tap the map to choose start A.';

  /// The route act's line before destination B is chosen. Added 2026-09-14,
  /// not yet reviewed on a render.
  String get routeActChooseDestination => _ja
      ? '地図をタップして目的地 B を選んでください。'
      : 'Tap the map to choose destination B.';

  /// The route act's line with both points chosen. Added 2026-09-14, not yet
  /// reviewed on a render.
  String get routeActBothChosen =>
      _ja ? 'A と B を選びました。' : 'A and B are chosen.';

  /// The route act's control that clears both points. Added 2026-09-14, not
  /// yet reviewed on a render.
  String get routeActChooseAgain => _ja ? '選び直す' : 'Choose again';

  /// The route act's control that asks for the route. Added 2026-09-14, not yet
  /// reviewed on a render.
  String get routeActGetRoute => _ja ? 'ルートを取得' : 'Get route';

  // The route panel's other words. Found at bb02b98: English literals in
  // Japanese mode. English keeps its bytes; the Japanese was added 2026-09-14
  // and is not yet reviewed on a render.

  /// Row label for a fetched route's length.
  String get routeDistanceLabel => _ja ? '距離' : 'Distance';

  /// Row label for a fetched route's time.
  String get routeDurationLabel => _ja ? '所要時間' : 'Duration';

  /// A route's time, rounded to whole minutes: 「25分」 / "25 min",
  /// 「1時間5分」 / "1h 5m".
  String routeDuration(double seconds) =>
      _formatMinutes((seconds / 60).round());

  /// Where a fetched route came from, and what it is not.
  String get routeSourceOsrmDemo => _ja
      ? '出典: OSRM 公開デモ（router.project-osrm.org）。雪を考慮しません。本番のナビゲーション用ではありません。'
      : 'Source: OSRM public demo (router.project-osrm.org). NOT snow-aware. '
          'NOT for production navigation.';

  /// A route request that failed. Ruled 2026-09-14, byte-exact: the app's own
  /// words and nothing after them. The router's reason is not shown: on a dead
  /// network it carries the request's address with both chosen points, and on
  /// a refusal the server's whole reply. It names no cause, because the router
  /// throws one exception type for both and its text is not read.
  String get routeFetchFailed =>
      _ja ? 'ルートを取得できませんでした。' : 'Route fetch failed.';

  /// The control that clears A, B and the route.
  String get routeReset => _ja ? 'リセット' : 'Reset';

  /// A fetched route with no turn to announce.
  String get routeNoManeuvers => _ja
      ? 'このルートには曲がり角の案内がありません。'
      : 'No turn-by-turn maneuvers in this route.';

  /// The maneuver panel's line before any route. Its English said "Tap A then
  /// B above to fetch a route", a gesture that sets nothing since 2026-09-14.
  /// Where route setting is closed it offers nothing. Added 2026-09-14, not yet
  /// reviewed on a render.
  String maneuverNoRouteYet({required bool routeSettingOpen}) {
    if (!routeSettingOpen) return _ja ? 'ルートはありません。' : 'No route.';
    return _ja
        ? '上の「ルートを設定」でルートを取得すると、次の案内がここに表示されます。読み上げは現在地が信頼できるときだけです。'
        : 'Set a route above; the next maneuver appears here, narrated only '
            'when the position is trustworthy.';
  }

  // ===== Live drive panel: its row labels and the compounding note =====
  //
  // The panel's values come from DriveHudLocalizer in the same resolved locale;
  // these are the words around them. Until 2026-09-13 all of them were
  // Japanese literals, so an English reader got English values under Japanese
  // labels, or Japanese throughout where the locale was hardcoded.

  /// Row label for how much to believe the position (the mode).
  String get driveHudPositionTrustLabel => _ja ? '現在地の信頼度' : 'Position trust';

  /// Row label for the uncertainty radius.
  String get driveHudUncertaintyLabel => _ja ? '誤差' : 'Uncertainty';

  /// Row label for the reasons the caution was raised.
  String get driveHudReasonsLabel => _ja ? '理由' : 'Why';

  /// Row label for the first-class unknowns.
  String get driveHudUnknownsLabel => _ja ? '不明な点' : 'Unknowns';

  /// Row label for the sight-stopping speed hint, shown only under a grounded
  /// low or whiteout visibility reading. English decided 2026-09-14 (was
  /// "Guide speed"): a hint, not a speed the app guides her to. Japanese
  /// unchanged.
  String get driveHudGuideSpeedLabel => _ja ? '目安速度' : 'Speed hint';

  /// The live-drive card's instruction to share, shown only while she is not
  /// sharing. Names the share button by its own label ([shareMyLocation]); the
  /// card already cautions before she shares, so sharing adds her position
  /// rather than starting the caution.
  String get driveHudShareHint => _ja
      ? '上の「現在地を共有」を押すと、現在地も使って注意を判断します。'
      : 'Tap "Share my location" above and the caution also uses your position.';

  /// The live-drive card's line while no position has arrived.
  String get driveHudNoPositionFed =>
      _ja ? '（まだ現在地が届いていません）' : '(no position received yet)';

  /// The maneuver panel's line when turn guidance is withheld because her
  /// position is not trusted. Japanese byte-identical to the literal it
  /// replaces; English added 2026-09-14, not yet reviewed on a render.
  String get maneuverGuidancePaused => _ja
      ? 'この曲がり角の案内は保留しています（現在地が信頼できません）。'
      : 'Guidance for this turn is on hold (your position is not trusted).';

  /// The title of the section that shows the next turn. Until 2026-09-14 it
  /// was English in Japanese mode and called the narration "honest". The
  /// Japanese names what the section shows with the words its own line uses
  /// (次の案内がここに表示されます); not yet reviewed on a render.
  ///
  /// English without the implementation term (2026-09-15): it read "Next
  /// maneuver — confidence-gated narration".
  String get maneuverSectionTitle => _ja ? '次の案内' : 'Next maneuver';

  // The next-turn banner's state, its control and what her press did. Until
  // 2026-09-15 these were English in every language, and the state was named
  // by the gate's internal names (SPEAK, HEDGE, SUPPRESSED). The words for
  // her position are not repeated here: the section's own row and her line
  // already carry them. No state's words contain another's, so a reader that
  // finds a state by its words cannot find another. Not yet reviewed on a
  // render.

  /// Banner state: her position is trusted, and the turn is read as given.
  String get maneuverTierSpeak => _ja ? 'そのまま読み上げます' : 'Read aloud as given';

  /// Banner state: her position is only suspect, and the turn is read as a
  /// possibility she is asked to confirm. No position the app gives the drive
  /// brain reaches this state today.
  String get maneuverTierHedge =>
      _ja ? '確認をお願いして読み上げます' : 'Read aloud with a check';

  /// Banner state: her position is not trusted, and the turn is not read.
  String get maneuverTierSuppressed => _ja ? '読み上げません' : 'Not read aloud';

  /// Beside a line that also says the turn may be icy.
  String get maneuverIcyMark => _ja ? '❄ 凍結のおそれ' : '❄ May be icy';

  /// The control that reads the next maneuver aloud, through the same gate.
  String get maneuverNarrateButton =>
      _ja ? '次の案内を読み上げる' : 'Read the next maneuver aloud';

  /// After her press, when the announcement was DISPATCHED on both channels.
  ///
  /// It says SENT, not told, and the distinction is the whole point. The value
  /// behind it is `ManeuverNarration.shouldAnnounce`, which
  /// `ManeuverNarration._announce` sets to `true` AT CONSTRUCTION
  /// (services/maneuver_narration.dart), and
  /// `DriveHudController.narrateNextManeuver` dispatches `unawaited(...)` and
  /// returns the decision immediately — its own doc says "Announcing is
  /// fire-and-forget". So the decision exists before either channel has
  /// reported anything, and nothing about arrival is known when this renders.
  ///
  /// Until 2026-09-23 this line read 「音声＋振動で知らせました。」 /
  /// "Announced on audio + haptic." — a PAST-TENSE claim of delivery on TWO
  /// channels, produced from a pre-dispatch gate boolean. This app had already
  /// convicted itself of exactly that chain on the drive-HUD chips (the
  /// 2026-08-22 note in main.dart: a critical announce dispatched speech and
  /// produced ZERO vibrations on a real device, with nothing saying so). That
  /// correction landed on the chips; this card was not swept with it.
  /// [maneuverNarrationDeliveryUnverified] is the other half.
  String get maneuverNarrationSent =>
      _ja ? '音声と振動に送りました。' : 'Sent to audio + haptic.';

  /// Rendered directly beneath [maneuverNarrationSent] when a channel did not
  /// report delivery.
  ///
  /// The drive-HUD chips carry these same two facts, but they render two Cards
  /// above (Drive HUD -> Route -> Maneuver). A driver who taps the button here,
  /// hears nothing, and reads a line on THIS card has to be told on THIS card:
  /// two cards away is not the same glance. For a deaf or hard-of-hearing
  /// driver the tactile row is not the second channel, it is the only one.
  String maneuverNarrationDeliveryUnverified({
    required bool speech,
    required bool haptic,
  }) {
    if (speech && haptic) {
      return _ja
          ? '音声も振動も、届いたか確認できていません。'
          : 'Neither the voice nor the vibration could be verified as delivered.';
    }
    if (haptic) {
      return _ja
          ? '振動が届いたか確認できていません。'
          : 'The vibration could not be verified as delivered.';
    }
    return _ja
        ? '音声が届いたか確認できていません。'
        : 'The voice could not be verified as delivered.';
  }

  /// After her press, when nothing was read.
  String get maneuverNarrationNotSpoken =>
      _ja ? '何も読み上げていません。' : 'Nothing was read aloud.';

  // The live-drive card's title, description, demo controls, announce line and
  // footer. Until 2026-09-14 the description, the blackout button and counter,
  // and the announce line were English in Japanese mode, and the visibility
  // demo label and bands Japanese in English mode; the title and footer were
  // English in both, and several of these lines carried words that only the
  // team that built the app can read (work-package tags, its name for the
  // driver, a self-description as honest, the names of its own speech
  // routing). Those words are gone from both languages, each line keeping what
  // it tells her. Public names stay: package names, pub.dev, pubspec.lock,
  // NWS and JMA. New or changed sentences are not yet reviewed on a render.

  /// The card's title.
  String get driveHudTitle =>
      _ja ? '走行中の注意（自動）' : 'Live drive — compound-failure caution (auto)';

  /// What the card does, above its demo controls. The two package names it
  /// carried until 2026-09-15 are on the development page
  /// ([developerPackagesBody]).
  String get driveHudDescription => _ja
      ? '現在地（GPS → 推測航法 → 現在地 不明。自信のある誤った点は出しません）を、視界と実際の地域の警報・注意報と組み合わせます。注意の段階が上がった瞬間に、音声＋振動で自動的に知らせます（手動のボタンは不要です）。'
      : 'Combines your position (GPS → dead reckoning → position unknown; never '
          'a confident wrong dot) with visibility and the area\'s actual warnings '
          'and advisories. The moment the caution level rises, it tells you by '
          'voice and vibration automatically; no button is needed.';

  /// The card's footer: where each thing the card shows comes from, as the app
  /// reads it. Until 2026-09-14 it said the position is real, while the Akita
  /// mock position feeds this card; that visibility is unknown by default,
  /// while the JMA Akita station's reading feeds it whenever the station
  /// reports one (whatever her own location); and, in English, that absence
  /// reads as 未計測, while the English card reads "No visibility reading".
  ///
  /// It names no state the card shows (2026-09-15). The footer is drawn under
  /// every state, so a state's own words here put that state on her card
  /// while the card is in another: the first draft quoted 停車の検討 and
  /// 視界の測定値がありません under 特段の注意なし. It keeps the facts: with no
  /// reading the card says so, and it never tells her to turn back.
  ///
  /// Its last sentence named the two packages and where their versions are
  /// kept until 2026-09-15; that sentence is on the development page now.
  String get driveHudFooter => _ja
      ? '位置は端末の GPS です。GPS が弱まると、そのことを表示します。地域の警報・注意報は、気象庁と米国の NWS が実際に出したものです。視界は、気象庁の秋田の観測点（アメダス）が視程を出しているときはその値です。この道路に視界のセンサーはありません。値がないときはそう表示し、クリアとは扱いません。この注意では、速度は不明として扱います。助言だけで、運転するのはいつもドライバーです。引き返すようには伝えません。'
      : 'Position is this device\'s GPS; when GPS weakens, the card says so. The '
          'area advisory is what JMA and the US NWS actually issued. Visibility is '
          'the JMA Akita station\'s (AMeDAS) reading when the station reports one; '
          'there is no visibility sensor on this road. With no reading the card '
          'says so and never treats it as clear. This caution treats speed as '
          'unknown. Advisory only: the driver always drives, and the card never '
          'says to turn back.';

  /// The card's rung was computed from a test value, not a measurement
  /// (2026-09-16; words decided in safety review).
  String get driveHudTestValueInForce => _ja
      ? 'テスト値を使った表示です（測定ではありません）'
      : 'This card uses a test value, not a measurement.';

  /// The icy mark comes from a simulated road condition (2026-09-16; words
  /// decided in safety review).
  String get maneuverTestRoadConditionInForce => _ja
      ? '凍結の表示はテスト値です（路面は測定していません）'
      : 'The ice mark is a test value; the road was not measured.';

  /// The twin of [maneuverTestRoadConditionInForce]: the icy mark rests on a
  /// MEASURED radiative-frost watch. Exactly one of the two renders.
  ///
  /// IT STILL SAYS THE ROAD WAS NOT MEASURED, and that is the point of the
  /// wording rather than an oversight. The watch is an INFERENCE from JMA's
  /// measured air temperature and humidity through the catalog's shared
  /// radiative-frost classifier; no instrument touched the road surface, and
  /// JMA never stated the road is frozen. README.md holds the app to
  /// "a derived inference, labeled as such — never presented as a JMA
  /// statement", so this line names what WAS measured and what was not, in one
  /// sentence, instead of trading one overstatement for another.
  String get maneuverMeasuredRoadIceInForce => _ja
      ? '凍結の表示は気象庁の気温・湿度からの推定です（路面は測定していません）'
      : 'The ice mark is inferred from measured JMA air temperature and '
          'humidity; the road surface itself was not measured.';

  /// The label over the visibility demo override.
  String get driveHudVisibilityOverrideLabel => _ja
      ? '視程デモ上書き（既定：ライブ／未計測 — 合成クリアなし）'
      : 'Visibility demo override (default: live / not measured — no synthetic clear)';

  /// One band of the visibility demo override, by its metres; null is no
  /// override.
  String driveHudVisibilityBand(double? meters) => switch (meters) {
        // Japanese without the framing dashes (2026-09-14): at phone width
        // the closing dash fell alone onto a second line, and beside Japanese
        // a long dash reads like 一. English keeps its bytes.
        null => _ja
            ? '上書きなし：ライブ／未計測（既定）'
            : '— No override: live / not measured (default) —',
        1500.0 => _ja ? 'クリア ~1.5 km' : 'Clear ~1.5 km',
        700.0 => _ja ? '視界低下 ~700 m' : 'Reduced visibility ~700 m',
        300.0 => _ja ? '視界不良 ~300 m' : 'Poor visibility ~300 m',
        80.0 => _ja ? 'ホワイトアウト ~80 m' : 'Whiteout ~80 m',
        final double m => '~${m.toStringAsFixed(0)} m',
      };

  /// The demo button that advances a GPS blackout by 60 s.
  String get driveHudSimulateBlackout =>
      _ja ? 'GPS 途絶を再現（+60 秒）' : 'Simulate GPS blackout (+60 s)';

  /// How far the demo blackout has been advanced.
  String driveHudBlackoutSeconds(int seconds) =>
      _ja ? 'GPS 途絶: $seconds 秒' : 'blackout: ${seconds}s';

  /// Announce line: the top rung is spoken and felt when it rises.
  String get driveHudAnnounceCritical => _ja
      ? '段階が上がると、音声＋振動で知らせます。'
      : 'When the caution level rises, the app tells you by voice and vibration.';

  /// Announce line: the middle rung is spoken and felt when it rises. Same
  /// words as the top rung; a test that tells them apart reads the key.
  String get driveHudAnnounceWarning => _ja
      ? '段階が上がると、音声＋振動で知らせます。'
      : 'When the caution level rises, the app tells you by voice and vibration.';

  /// Announce line: raised and shown, and not spoken by this rung.
  ///
  /// Until 2026-09-14 it also said the specific hazard is read aloud through
  /// the app's own measured-weather route. That holds when caution rose only
  /// from a measured weather watch, which has spoken. The same line is shown
  /// when caution rose only because visibility was not measured: measured in
  /// the real app with a fresh Akita reading that carries no visibility and a
  /// shared position, nothing was spoken. The line now says only what holds in
  /// both.
  String get driveHudAnnounceRaisedNotSpoken => _ja
      ? '注意に上げました（表示と色のみ）。この段階では読み上げません。'
      : 'Raised to caution (shown in colour). This level is not read aloud.';

  /// Announce line: nothing is announced.
  String get driveHudAnnounceContinue =>
      _ja
      ? 'この段階では、音声や振動では知らせません。'
      : 'At this level, nothing is announced by voice or vibration.';

  /// Note in the caution banner when hazards compound.
  String get driveHudCompoundingNote => _ja
      ? '⚠ 危険が重なっています（現在地不確か＋視界不良）'
      : '⚠ Hazards are compounding (position uncertain + low visibility)';

  /// GPS-unavailable line. The [reason] is produced by the geolocator layer
  /// (her_position.dart) as English.
  ///
  /// [routeSettingOpen]: as for [locationOffStatus], the route panel's sentence
  /// is left out where route setting is closed.
  ///
  /// Ruled 2026-09-14: no refusal is read from a reason's text, and text the
  /// app did not write never reaches this line, in either locale. A reason
  /// the app writes on a path it measured keeps its words
  /// ([_measuredReasonWords]); for any other reason, including a refusal's
  /// words with no typed cause, the line is [positionNotObtainedStatus].
  String gpsUnavailable(String reason, {required bool routeSettingOpen}) {
    final r = _measuredReasonWords(reason);
    if (r == null) return positionNotObtainedStatus;
    if (_ja) {
      return 'GPS を取得できません — $r。地図は表示されたままです。'
          '${routeSettingOpen ? _routePanelWorksJa : ''}';
    }
    return routeSettingOpen
        ? 'GPS unavailable — $r. The map remains; the route panel still works by tap.'
        : 'GPS unavailable — $r. The map remains.';
  }

  /// The line under the map when no position was obtained and the app holds
  /// no typed cause, or the reason is not one the app wrote on a measured
  /// path. Ruled 2026-09-14, byte-exact. It starts with the map's own words
  /// and names no cause. It has no route-panel sentence: a line about position
  /// cannot know whether route setting is open.
  String get positionNotObtainedStatus => _ja
      ? '現在地不明 — 位置を取得できませんでした。地図は表示されたままです。'
      : 'Position unknown — this app could not get a position. The map remains.';

  /// The line under the map when the app knows from the exception's type that
  /// it has no location implementation on this device
  /// (`isNoLocationOnThisDevice`). Ruled 2026-09-14, byte-exact: no GPS, no
  /// error, no plugin, and no route-panel sentence.
  String get noLocationOnThisDeviceStatus => _ja
      ? '現在地不明 — この端末では、このアプリは位置を取得できません。地図は表示されたままです。'
      : 'Position unknown — this app cannot get a position on this device. The map remains.';

  /// The words for a reason her_position.dart writes on a path it measured,
  /// in this locale; null for anything else.
  ///
  /// Matched whole, except where the app's own reason carries values
  /// (the non-finite fix) or wraps a platform's text (a stream error). For a
  /// stream error only the app's wrapper is said: the exception text after it
  /// is the platform's, and never reaches her line. An exception while
  /// starting ('GPS init error: …') is not here: without a typed cause it
  /// measured only that no position was obtained. Nothing here looks for a
  /// refusal: a refusal is shown only from its typed cause.
  String? _measuredReasonWords(String reason) {
    if (reason.startsWith('GPS stream error')) {
      return _ja ? 'GPSストリームのエラー' : 'GPS stream error';
    }
    if (reason.startsWith('Degraded GPS fix — non-finite coordinate')) {
      return _ja ? 'GPS信号が乱れています（座標が不正です）' : reason;
    }
    return switch (reason) {
      'Location services disabled' => _ja ? '位置情報サービスが無効です' : reason,
      'Location service check timed out — platform did not answer' => _ja
          ? '位置情報サービスの確認に時間がかかりすぎました（端末が応答しません）'
          : reason,
      'Location permission check timed out — platform did not answer' => _ja
          ? '位置情報の許可状態の確認に時間がかかりすぎました（端末が応答しません）'
          : reason,
      'Location permission request timed out — no answer from the platform dialog' =>
        _ja ? '位置情報の許可の応答がありませんでした（確認画面が閉じられていません）' : reason,
      'GPS stream ended by the platform' =>
        _ja ? 'GPSの受信が端末側で終了しました' : reason,
      _ => null,
    };
  }

  // ===== Data-flow disclosure (task 3, corrected B28) — WIRE-ACCURATE =====
  //
  // Honesty-traced to the real wire, read at the resolved package sources
  // (pubspec.lock), not at the docs:
  //
  // - JAPAN: condition_aggregator_jma 0.7.1 maps the point to prefecture
  //   code(s) ON-DEVICE (`prefectureCodesForPoint`, jma_advisory_provider.dart
  //   :262) and requests only
  //   `https://www.jma.go.jp/bosai/warning/data/r8/{prefectureCode}.json`
  //   (base constant :70, the one construction site :527). The driver's
  //   coordinates NEVER leave the device for Japan — the previous copy claimed
  //   they were "sent to the JMA", which was FALSE.
  //   ⚑ Re-measured 2026-09-20 and the EVIDENCE under this claim had gone
  //   stale while the claim stayed true. This bullet said 0.3.0 — four minors
  //   behind the lock — with that version's line numbers, and named the
  //   `data/warning/` path, which JMA's 2026-05-29 restructure RETIRED and
  //   which the adapter stopped reading at 0.7.0 (it is kept in the package
  //   only as `kJmaRetiredWarningJsonBaseUrl`, marked "Do not fetch it").
  //   A block headed WIRE-ACCURATE was citing a wire we no longer use.
  //   The claim is now checked the strongest available way rather than by
  //   line number: `Uri.parse` appears EXACTLY ONCE in the package's whole
  //   `lib/src/` tree, at :527, and what it interpolates is a prefecture
  //   code. There is no second request that could carry a coordinate.
  // - UNITED STATES: noaa_nws_adapter 0.0.9 sends the actual point —
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
      ? '出発地と目的地の座標が、経路計算のため公開OSRMデモサーバー（router.project-osrm.org）に送信されます。よろしいですか。この選択は記憶され、ルート欄の「選択を変更」から変更できます。'
      : 'The origin and destination coordinates you tapped will be sent to the '
          'public OSRM demo server (router.project-osrm.org) to calculate the '
          'route. Is that OK? Your choice is remembered and can be changed with '
          '"Change choice" in the route panel.';

  String get routeConsentAccept => _ja ? '送信して経路を取得' : 'Send and fetch route';

  String get routeConsentDecline => _ja ? '送信しない' : 'Do not send';

  /// Honest neutral state after a decline/dismiss: no request was made,
  /// coordinates did not leave the device. Not an error — the router was
  /// never asked.
  String get routeConsentDeclinedMessage => _ja
      ? '経路は取得していません — 座標は送信されていません。'
      : 'No route was fetched — your coordinates were not sent.';

  /// Path back after a remembered answer, a no or a yes (dignity: neither
  /// may be a locked door).
  String get routeConsentChangeChoice => _ja ? '選択を変更' : 'Change choice';

  // ===== Advisory ordering / NWS de-emphasis for the ja surface (task 4) =====

  /// Caption shown on the (English) NWS card when the surface is Japanese —
  /// the card stays present (hiding safety data would be dishonest) but is
  /// de-emphasized and marked as English reference material.
  String get englishReferenceNote => _ja ? '英語の情報（参考）' : 'English (reference)';

  // ===== Announce affordance (driver-facing, was English-only) =====

  /// Label for the button that speaks + buzzes the current hazard.
  String get announceToDriver =>
      _ja ? '運転者へ知らせる（音声＋振動）' : 'Announce to driver (audio + haptic)';

  /// Helper under the announce button when the current condition IS announced
  /// (>= warning). [severityName] is the technical severity token (warning /
  /// critical), kept verbatim. The on-device HEAR/FEEL bound is stated
  /// honestly (not verified without a device).
  String announceFiresHelper(String severityName) => _ja
      ? '音声＋振動で発報します（重要度: $severityName）。'
          '端末での聴取・体感は本環境では未検証です。'
      : 'Fires audio + haptic (severity: $severityName). '
          'On-device HEAR/FEEL not verified in this env.';

  /// Helper under the announce button when the chosen condition is below
  /// warning: the announcer returns without voice or vibration
  /// (alert_announcer.dart, severity below warning). Until 2026-09-15 it said
  /// this with the severity token and the app's name for its speech gate.
  String get announceInfoHelper => _ja
      ? 'この路面状態は情報だけのため、押しても音声と振動では知らせません。'
      : 'This road condition is information only, so pressing this does not '
          'announce it by voice or vibration.';

  // ===== Advisory card states (driver-facing, was English-only) =====

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
  /// outage is an unknown, not a warning, and crying wolf would teach the driver to
  /// ignore the instrument.
  String get advisoryLookupIncomplete => _ja
      ? '警報・注意報の照会が完了したか確認できません — '
          '有効な警報・注意報の有無は不明です。'
      : 'Cannot confirm the advisory lookup was complete — whether any '
          'warning or advisory is in force is unknown.';

  /// Measured-weather feed NOT YET READ this session — the cold-start state.
  /// The invisible-ice and turmoil watches are non-firing because nobody has
  /// been asked yet, which looks EXACTLY like a measured all-clear on the
  /// drive brain's floor. Says so plainly instead. Deliberately not a hazard
  /// claim: an unread feed is an unknown, not a warning.
  String get measuredWatchNotYetRead => _ja
      ? '気象観測をまだ取得していません — 路面凍結・荒天の測定状況は不明です。'
      : 'The weather observation has not been read yet — the measured '
          'road-ice and turmoil watches are unknown.';

  /// Measured-weather feed READ AND FAILED. Distinct from the cold start
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

  // ===== Words decided for the driver's screen, 2026-09-15 (prefecture table, Akita card, banner) =====

  /// Prefecture table column heads. English unchanged.
  String get prefectureHeadStation => _ja ? '観測点' : 'Station';
  String get prefectureHeadSnow => _ja ? '積雪深' : 'Snow';
  String get prefectureHeadTemp => _ja ? '気温' : 'Temp';
  String get prefectureHeadWind => _ja ? '風速' : 'Wind';
  String get prefectureHeadObserved => _ja ? '観測時刻' : 'Observed';
  String get prefectureRefetchAll => _ja ? 'すべて再取得' : 'Re-fetch all';

  /// Akita observation card labels. The row appends its own colon.
  String get observationStationLabel => _ja ? '観測点' : 'Station';
  String get observationObservedAtLabel => _ja ? '観測時刻' : 'Observed at';
  String get observationTemperatureLabel => _ja ? '気温' : 'Temperature';
  String get observationHumidityLabel => _ja ? '湿度' : 'Humidity';
  String get observationWindLabel => _ja ? '風速' : 'Wind';
  String get observationSnowDepthLabel => _ja ? '積雪深' : 'Snow depth';
  String get observationFetchedLabel => _ja ? '取得時刻' : 'Fetched';

  /// The measured 10-minute precipitation row on the Akita card.
  String get observationPrecipitation10mLabel =>
      _ja ? '降水量（10分間）' : 'Precipitation (10 min)';

  // ===== The two watch rows on the Akita card =====
  //
  // Until 2026-09-19 these rows were drawn in Japanese on every page, so a
  // driver reading English saw 該当なし and 判定不能 side by side and could not
  // tell "none" from "cannot judge" — the one distinction these rows exist to
  // make. The English says "cannot judge" wherever the Japanese says 判定不能,
  // and "None" only where the Japanese says 該当なし — on the turmoil row. On the
  // black-ice row 該当なし reads "No radiative cooling window" (2026-09-20): a
  // bare "None" under "Road-ice watch" can be read as a road with no ice, and
  // this watch only ever says whether it found the window it looks for. The
  // Japanese is unchanged.
  // "Road-ice" and "turmoil" are the words the card's own feed lines already
  // use for these watches (measuredWatchNotYetRead, measuredWatchFeedLost).

  /// The black-ice watch row's label.
  String get roadIceWatchLabel => _ja ? '路面凍結ウォッチ' : 'Road-ice watch';

  /// The black-ice watch verdict as drawn. [r] null is the same as unknown:
  /// no verdict has been computed, and that is never shown as none.
  String roadIceWatchVerdict(InvisibleIceWatchResult? r) => switch (r) {
        InvisibleIceWatchResult.watch => _ja
            ? '⚠ ブラックアイスバーンのおそれ（放射冷却の窓）'
            : '⚠ Black ice possible (radiative cooling window)',
        // The window this watch looks for is not in the station's readings.
        // Not "None": that can read as a road with no ice, which the watch
        // never measures. The same words as the warning's parenthetical.
        InvisibleIceWatchResult.clear =>
          _ja ? '該当なし' : 'No radiative cooling window',
        // The classifier DECLINED to judge this reading — every field was
        // measured and in range, and it still produced no verdict.
        // Deliberately distinguishable from `outOfScope`'s wording: that one
        // says another watch owns these conditions, which is false here — no
        // watch covers it (the app has no fog concept at all). Not spoken: it
        // is the absence of a judgement, not a hazard (see the enum's
        // dartdoc).
        InvisibleIceWatchResult.outsideModelEnvelope => _ja
            ? '判定範囲外（この気象条件は判定していません）'
            : 'Outside its range (these weather conditions are not judged)',
        // Sub-zero ambient, no precip: expected-frozen regime. Distinct,
        // possibility-graded, NOT the surprise wording. English as the
        // sub-zero chip's own words, "Road may be frozen".
        InvisibleIceWatchResult.subZeroFrozen => _ja
            ? '⚠ 路面凍結のおそれ（気温0°C以下）'
            : '⚠ Road may be frozen (air temperature 0 °C or below)',
        // A scope exclusion is NOT an all-clear. Say plainly that this watch
        // does not cover these conditions, and never imply the surface is
        // safe.
        InvisibleIceWatchResult.outOfScope => _ja
            ? '本ウォッチの対象外（この条件は判定していません）'
            : 'Not covered by this watch (this condition is not judged)',
        InvisibleIceWatchResult.unknown || null => _ja
            ? '判定不能（気温・湿度・降水の観測値が不足）'
            : 'Cannot judge (temperature, humidity or precipitation not '
                'reported)',
      };

  /// The measured-turmoil watch row's label.
  String get turmoilWatchLabel => _ja ? '荒天ウォッチ' : 'Turmoil watch';

  /// The measured-turmoil verdict as drawn; [s] null means nothing was judged.
  String turmoilWatchVerdict(TurmoilWatchState? s) => s == null
      ? (_ja
          ? '判定不能（降水・風の観測値が不足）'
          : 'Cannot judge (precipitation and wind not reported)')
      : turmoilRowText(s, ja: _ja);

  // ===== Station names on an English page =====
  //
  // The station table (jma_fetch.dart) carries each station's kanji name and a
  // short Japanese place description, chosen so a driver who reads Japanese
  // has no translation step. A driver reading English had the same kanji and
  // could not read them. The names below are JMA's own English names for these
  // stations, from JMA's AMeDAS station table (enName); the descriptions are
  // this app's. Both are held to JMA's table by
  // test/corridor_stations_match_jma_table_test.dart.

  static const _stationNamesEn = <String, String>{
    '32286': 'Oga',
    '32402': 'Akita',
    '32551': 'Omagari',
    '32596': 'Yokote',
    '32691': 'Yuzawa',
  };

  static const _stationDescriptorsEn = <String, String>{
    '32286': 'North coast',
    '32402': 'City',
    '32551': 'Central inland',
    '32596': 'South inland',
    '32691': 'South mountains',
  };

  /// A station's name as drawn. In Japanese, [name] as the station table gives
  /// it. In English, JMA's English name for [stationId]; a station this app
  /// has no English name for keeps [name], so a new station shows its kanji
  /// rather than nothing.
  String stationName(String stationId, String name) =>
      _ja ? name : (_stationNamesEn[stationId] ?? name);

  /// A prefecture-table row's place description; same rule as [stationName].
  String stationDescriptor(String stationId, String descriptor) =>
      _ja ? descriptor : (_stationDescriptorsEn[stationId] ?? descriptor);

  /// The label on the map's Akita station marker.
  String get akitaStationMapLabel => _ja ? '秋田' : 'Akita';

  /// When the Akita observation was fetched, and how long ago. [minutes] is
  /// minutes since the fetch. Under a minute reads 1分以内 / within 1 min;
  /// an hour or more reads hours and minutes, as the app's other ages.
  String observationFetchedAt(String time, int minutes) {
    if (minutes < 1) return _ja ? '$time（1分以内）' : '$time (within 1 min)';
    final age = _formatMinutes(minutes);
    return _ja ? '$time（$age前）' : '$time ($age ago)';
  }

  /// The Akita card's source caption: which rows JMA published and which are
  /// this app's judgement. Two lines.
  String get akitaObservationSource => _ja
      ? '観測の各行は、気象庁アメダスの発表値です。\nウォッチ2行は気象庁ではなく、このアプリの判断です。'
      : 'The observation rows are the values JMA AMeDAS published.\nThe two watch rows are this app\'s judgement, not JMA\'s.';

  /// The responsibility banner at the top of her page. English unchanged.
  String get responsibilityBanner => _ja
      ? '開発中のアルファ版です。本番のナビゲーション用ではありません。運転の判断はすべて、ドライバーの責任です。このアプリは情報を表示するだけで、車を操作しません。'
      : 'Alpha software. Not for production navigation. The driver remains '
          'responsible for all driving decisions. This app surfaces information; '
          'it does not control the vehicle.';

  // ===== JMA feed-loss panel (the screen must match the speaker) =====

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
  /// past the 60-min retain bound): the observation feed is honestly empty.
  String get jmaNoValidObservation => _ja
      ? '60分以内の有効な観測を保持していません。'
      : 'No observation within the 60-minute retain window is held.';

  /// Caption under the visible forecast-memory card (the visible counterpart
  /// of the offline-survival fix).
  /// [time] is the local clock time the memory was captured — before
  /// departure, while the network was still alive.
  String forecastMemoryCaption(String time) => _ja
      ? '出発前 $time に取得した気象庁の予報 — 観測ではありません。'
      : 'JMA forecast fetched at $time, before departure — a forecast, not '
          'an observation.';

  /// A failed advisory fetch: the app's own words and nothing after them, as
  /// the route line ([routeFetchFailed]). Until 2026-09-15 this line ended with the
  /// exception text, which put an exception class, a status code and the
  /// request's URL on her screen.
  String get advisoryFetchFailed =>
      _ja ? '警報・注意報を取得できませんでした。' : 'Advisory fetch failed.';

  /// Before any advisory fetch has run.
  String get advisoryNoFetchYet => _ja ? '（まだ取得していません）' : '(no fetch yet)';

  /// The initial "Fetch" action.
  String get advisoryFetch => _ja ? '取得' : 'Fetch';

  /// The "Re-fetch" action (a result is already shown).
  String get advisoryReFetch => _ja ? '再取得' : 'Re-fetch';

  /// The "Retry" action after an error.
  String get retry => _ja ? '再試行' : 'Retry';

  /// Per-publisher soft-error line. [publisher] is the source label
  /// (verbatim). The exception text that followed it until 2026-09-15 is not
  /// shown, as for [routeFetchFailed].
  /// The name shown for an advisory source that has no name of its own: the
  /// card head, and the publisher in [advisoryPublisherErrored]. A fetch that
  /// threw before any publisher answered is reported under it. English
  /// unchanged; until 2026-09-16 the Japanese page read the English word too.
  String get advisoryOtherSource => _ja ? 'その他' : 'Source';

  /// The Japan Meteorological Agency's name, in the page's language. It is the
  /// publisher of every warning the app shows in Akita,
  /// and it appears twice on one page: the advisory card head, and the
  /// publisher inside [advisoryPublisherErrored].
  ///
  /// Until 2026-09-18 both were the literal 気象庁 in EVERY locale, while the
  /// nine other English strings that name the same body all say "JMA"
  /// (:424, :425, :631, :865 twice, :900, :1253, :1258, :1308, :1314). So the
  /// English page named one publisher two ways, worst on the error line, which
  /// read verbatim "Could not fetch from 気象庁." — an English sentence whose
  /// only subject was in another script. On a font stack with no CJK face that
  /// sentence names three empty boxes, and a source name that renders as
  /// nothing reads as no source at all.
  ///
  /// This is the publisher's NAME, not its safety wording. The verbatim-relay
  /// discipline in `advisory_cards.dart` covers event class, headline, area and
  /// description — the publisher's own words about the hazard — and those stay
  /// verbatim and untranslated in every locale. NWS and MET Norway are already
  /// one Latin string each and are unchanged.
  String get advisoryJmaPublisher => _ja ? '気象庁' : 'JMA';

  String advisoryPublisherErrored(String publisher) => _ja
      ? '配信元 $publisher から取得できませんでした。'
      : 'Could not fetch from $publisher.';

  // ===== The advisory card's OWN labels (2026-09-19) =====
  //
  // Found but not fixed in the 2026-09-18 change, seen in a rendered frame of
  // the Japanese card head: the Japanese card drew the English word
  // `severe` in the severity pill, because the pill rendered
  // `advisory.severity.name` — the raw Dart enum token — in every locale.
  // Beside it on the same Row the card drew `eff.`, and lower down `expires`:
  // three English tokens on a Japanese page, the same defect class as the 2026-09-18
  // error line that read "Could not fetch from ▯▯▯."
  //
  // The rule these follow is that change's, unchanged and applied one level out: the
  // card's OWN labels read the page's language; the publisher's verbatim
  // wording does not move. eventClass, areaDescription, headline and
  // description stay untranslated in every locale, and so does
  // `AdvisorySource.attributionString`, which belongs to the package and
  // carries the publisher's attribution terms — that one is named, not touched.
  //
  // ⚑ THE SEVERITY WORDS DELIBERATELY AVOID JMA'S REGULATED VOCABULARY.
  // Measured in condition_aggregator_jma 0.7.1 `jma_advisory_mapper.dart:724-734`:
  // 特別警報/危険警報 → extreme, 警報 → severe, 注意報 → moderate. So for a JMA
  // card 「警報」 would be exactly right — and this same pill also renders NWS
  // and MET Norway advisories, whose severity comes from CAP, not from JMA.
  // Printing 「警報」 on an NWS card would attribute a Japanese regulatory
  // classification to a publisher that never issued one. These are OUR scale,
  // so they are said in our own plain words.
  //
  // English is UNCHANGED on purpose — it is byte-for-byte the enum token it
  // already drew — so the English page is provably unmoved and the only
  // difference is the one that was defective.

  /// Severity `extreme`, as the pill says it in the page's language.
  String get advisorySeverityExtreme => _ja ? '甚大' : 'extreme';

  /// Severity `severe`.
  String get advisorySeveritySevere => _ja ? '重大' : 'severe';

  /// Severity `moderate`.
  String get advisorySeverityModerate => _ja ? '中程度' : 'moderate';

  /// Severity `minor`.
  String get advisorySeverityMinor => _ja ? '軽微' : 'minor';

  /// Severity `unknown` — said in full rather than as a bare 「不明」.
  ///
  /// The pill sits immediately after the publisher's name, so 「気象庁 不明」
  /// can be read as an unknown PUBLISHER rather than an unknown severity. The
  /// three extra characters remove that reading. An unknown severity must
  /// reach her as unknown, and must never be mistakable for anything else.
  String get advisorySeverityUnknown => _ja ? '重要度不明' : 'unknown';

  /// The time an advisory takes effect. Was the English literal `eff.` in
  /// every locale.
  String advisoryEffectiveAt(String time) => _ja ? '開始 $time' : 'eff. $time';

  /// The time an advisory stops applying. Was the English literal `expires`
  /// in every locale.
  String advisoryExpiresAt(String time) =>
      _ja ? '終了 $time' : 'expires $time';

  /// A warnings fetch that failed with no publisher named (decided
  /// 2026-09-16). The only app writer is a fetch that threw before any
  /// provider answered, so the line names nobody; 配信元 その他 named no one
  /// while reading like a publisher's name.
  String get advisoryFetchFailedBeforeAnyPublisher => _ja
      ? 'どの配信元からも応答がないまま、取得が失敗しました。'
      : 'The fetch failed before any publisher answered.';

  /// The Akita observation card after a failed fetch. The words are the first
  /// clause of [measuredWatchFeedLost]; the fetch's reason (an endpoint name
  /// and a status code) shown after them until 2026-09-15 is not.
  String get jmaObservationFetchFailed => _ja
      ? '気象観測を取得できませんでした。'
      : 'The weather observation could not be read.';

  /// One station's row in the prefecture weather card after a failed fetch.
  /// The reason shown after it until 2026-09-15 is not.
  String get corridorStationFetchFailed =>
      _ja ? '取得できませんでした。' : 'Fetch failed.';

  // ===== Voice-channel readiness + speech-unverified chip (Tier-1) =====

  /// Pre-drive caution shown ONLY when the voice-channel readiness read proved
  /// the ja voice is network-bound (jaNetworkOnly) or absent (noJaVoice).
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
  /// The stronger, measured statement a safety-review finding makes possible: not *"we could
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
  // boundary the project holds).

  /// Strong pre-drive caution when no spoken safety alert can be heard.
  ///
  /// ⚑ REWRITTEN 2026-08-22 after a safety review pushed back, finding two defects
  /// in the one sentence this used to be — *"メディア音量がゼロです。音声警告が
  /// 聞こえません。振動でお知らせします。"*:
  ///
  /// (a) **the stated cause was false.** Since `isStreamMute` reached the
  ///     probe the same day, this row also fires at a NON-ZERO index on a
  ///     muted stream — measured on AVD `sngnav_api30` at index 5 of 15.
  ///     "Silent" is true of both; "volume is zero" was true of one.
  /// (b) **the second clause promised a delivery the app only ATTEMPTS.**
  ///     Future tense, unconditional, about the one channel that had no
  ///     prospective probe. The review: *claimed delivery, earned attempt.*
  ///
  /// The wording below is the review's, verbatim from its verdict, and carries three
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
  /// ⚑ RENAMED 2026-08-22 after the same review pushed back. This used to read
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

  // ===== ログを共有 (share log) — beta feedback share-log surface (BETA_PLAN fix #8) =====
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
  // ---- WARNING-CHANNEL CHECK (2026-09-19) -----------------------------
  // Why these are driver-facing strings and not developer chrome: for a deaf or
  // hard-of-hearing driver the tactile cue is the ONLY warning channel
  // (the accessibility rule). Confirming it works BEFORE the pass shuts is a safety
  // affordance she is owed, not a debug button — which is also why this
  // surface must survive in a release build, unlike the development page.

  /// What the test warning SAYS. It states that it is a test, in her own
  /// tongue, so a cue heard from the next room is never mistaken for a real
  /// hazard — and it names both channels, so she knows what to listen and
  /// feel for.
  String get channelCheckSpokenLine => _ja
      ? 'これはテストです。警報の音と振動を確認しています。'
      : 'This is a test. Checking the warning sound and vibration.';

  String get channelCheckSectionTitle => _ja
      ? '警報チャンネルの確認 — 音と振動'
      : 'Warning channel check — sound and vibration';

  String get channelCheckIntro => _ja
      ? '本番と同じ警報を一度だけ出します。停車中に行ってください。'
      : 'Plays the real warning once. Do this while parked.';

  String get channelCheckFireButton =>
      _ja ? 'テスト警報を出す' : 'Play the test warning';

  String get channelCheckFiring => _ja ? '再生中…' : 'Playing…';

  String get channelCheckHeardQuestion =>
      _ja ? '音は聞こえましたか？' : 'Did you HEAR it?';

  String get channelCheckFeltQuestion =>
      _ja ? '振動は感じましたか？' : 'Did you FEEL it?';

  String get channelCheckYes => _ja ? 'はい' : 'Yes';
  String get channelCheckNo => _ja ? 'いいえ' : 'No';
  String get channelCheckUnsure => _ja ? 'わからない' : 'Not sure';

  String get channelCheckSaveButton =>
      _ja ? 'この結果を日記に残す' : 'Save this result to the diary';

  String get channelCheckSaved => _ja
      ? '保存しました。「日記を共有」で送れます。'
      : 'Saved. You can send it with "Share the diary".';

  String get channelCheckSaveFailed =>
      _ja ? '保存できませんでした。' : 'Could not save.';

  String get channelCheckUnavailable => _ja
      ? '日記が使えないため、結果を残せません。'
      : 'The diary is unavailable, so the result cannot be saved.';

  /// The honest bound, shown BESIDE the buttons — never after the fact.
  /// The app cannot detect the vibrator motor: `hasVibrator()` reports
  /// whether this is a physical device, and the native vibrate call answers
  /// success unconditionally. Only a person can close this.
  String get channelCheckHonestBound => _ja
      ? '端末は「出した」としか答えられません。実際に届いたかは、あなたの答えだけが決められます。'
      : 'The phone can only report that it sent the cue. Whether it actually '
          'arrived is something only your answer can decide.';

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

  // ===== Home page card titles (2026-09-15) =====
  //
  // Until 2026-09-15 fifteen of these were English literals in every language,
  // and some carried the project's internal words: its name for the driver's cohort,
  // a package version with issue numbers, a tool's name, package names, and a
  // default ("kei-car-at-65") the vehicle dropdown does not have. Each title
  // now says what its card is. A card that exists for development says so, so
  // it is not read as advice; the tuning record keeps its "not driving advice"
  // boundary in words.

  /// Her map.
  String get mapSectionTitle => _ja ? '地図' : 'Map';

  /// The driver-type selector.
  String get driverTypeSectionTitle => _ja ? '運転者のタイプ' : 'Driver type';

  /// The road-condition selector: a chosen value, not a measured one.
  String get simulatedRoadConditionSectionTitle => _ja
      ? '模擬の路面状態（開発用）'
      : 'Simulated road condition (for development)';

  /// The vehicle-type selector. Its value starts as unknown.
  String get vehicleTypeSectionTitle => _ja ? '車両の種類' : 'Vehicle type';

  /// Manual driver-state inputs: time of day, days driven, confidence.
  String get driverStateInputsSectionTitle => _ja
      ? '運転者の状態の入力（開発用）'
      : 'Driver state inputs (for development)';

  /// The warning thresholds the chosen driver type, vehicle and state give.
  String get warningThresholdsSectionTitle => _ja
      ? '警告の基準値（運転者のタイプ・車両・状態別）'
      : 'Warning thresholds (by driver type, vehicle and state)';

  /// The names and spoken words for the chosen road condition.
  String get roadConditionNamesSectionTitle => _ja
      ? '選んだ路面状態の呼び方'
      : 'Names for the chosen road condition';

  /// The guidance for the chosen road condition, and the announce button.
  String get roadConditionGuidanceSectionTitle => _ja
      ? '選んだ路面状態の案内'
      : 'Guidance for the chosen road condition';

  /// A simulated burst of warnings against the rate limit.
  String get alertRateLimitSectionTitle => _ja
      ? '警告の回数制限の試験（開発用）'
      : 'Alert rate limit test (for development)';

  /// The record the rate-limit test writes, for tuning.
  String get tuningRecordSectionTitle => _ja
      ? '開発・調整用の記録（運転の助言ではありません）'
      : 'Development and tuning record (not driving advice)';

  /// Simulated glances at the screen against a time budget, and voice pacing.
  String get glanceAndVoicePacingSectionTitle => _ja
      ? '画面を見る時間と音声の間隔の試験（開発用）'
      : 'Screen glance time and voice pacing test (for development)';

  /// Simulated map frames and tile downloads against their budgets.
  String get mapDrawingAndDataSectionTitle => _ja
      ? '地図の描画と通信量の試験（開発用）'
      : 'Map drawing and data use test (for development)';

  /// The Akita station's latest observation, from the publisher.
  String get akitaObservationSectionTitle => _ja
      ? '秋田の気象観測（気象庁アメダス）'
      : 'Akita weather observations (JMA AMeDAS)';

  /// Observations at stations across the prefecture, from the publisher.
  String get prefectureObservationsSectionTitle => _ja
      ? '秋田県内各地の気象観測（気象庁アメダス）'
      : 'Weather observations across Akita Prefecture (JMA AMeDAS)';

  /// Warnings and advisories the publishers have issued.
  String get advisoriesSectionTitle =>
      _ja ? '発表中の警報・注意報' : 'Warnings and advisories in force';

  // ===== The development page (2026-09-15) =====
  //
  // The eleven cards above from 運転者のタイプ to 地図の描画と通信量の試験 are not on
  // her home page. They are on this page, which only a build that asks for it
  // offers.

  /// The development page's title, and the tooltip of its entry.
  String get developerPageTitle => _ja ? '開発用の画面' : 'Development page';

  /// The development page's card holding the live-drive demos: the Akita mock
  /// position, the visibility band and the GPS blackout simulator, on her
  /// live-drive card until 2026-09-15.
  String get developerLiveDriveDemosSectionTitle => _ja
      ? '走行中の注意のデモ（開発用）'
      : 'Live-drive demos (for development)';

  /// The development page's last card: the packages the app is built on.
  String get developerPackagesSectionTitle => _ja
      ? 'このアプリのパッケージ（開発用）'
      : 'Packages in this app (for development)';

  /// The package names that were on her page foot and on the live-drive card
  /// until 2026-09-15, moved here as they were.
  String get developerPackagesBody => _ja
      ? 'pub.dev の SNGNav パッケージ（navigation_safety_core、navigation_safety、voice_guidance、driving_conditions、offline_tiles、snow_rendering、map_viewport_bloc）で作られています。走行中の注意の出典: localization_fallback ＋ compound_failure_advisor。バージョンは pubspec.lock にあります。'
      : 'Built on the SNGNav packages from pub.dev (navigation_safety_core, '
          'navigation_safety, voice_guidance, driving_conditions, offline_tiles, '
          'snow_rendering, map_viewport_bloc). The live-drive caution\'s '
          'source: localization_fallback + compound_failure_advisor. Resolved '
          'versions are in pubspec.lock.';

  // ===== The foot of her page and the prefecture card's source (2026-09-15) =====
  //
  // Until 2026-09-15 both were English literals in every language. The foot
  // named the reason the Akita station was chosen in the project's internal words, a
  // self-description of the position as honest, the dev mock's colour and seven
  // package names; the source line cited one of the project's internal decisions. Each keeps
  // what she needs from it.

  /// The foot of her home page: the app and its version, that routes do not
  /// consider snow, and where routes and weather observations come from.
  String pageFoot(String version) => _ja
      ? 'sngnav-app $version。ルートは公開OSRMデモサーバーで計算し、雪を考慮しません。気象の観測は気象庁（アメダス）のものです。'
      : 'sngnav-app $version. Routes are calculated by the public OSRM demo '
          'server and do not consider snow. Weather observations are from JMA '
          '(AMeDAS).';

  /// The prefecture weather card's source line.
  String get prefectureObservationsSource => _ja
      ? '出典: 気象庁アメダス。各観測点の値を、発表されたとおりに表示しています。'
      : 'Source: JMA AMeDAS. Each station\'s values are shown as published.';
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
