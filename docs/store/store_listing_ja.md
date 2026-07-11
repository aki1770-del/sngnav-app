# Play ストア掲載文（草稿・ja主） — sngnav-app

<!-- W3 エントリーゲート成果物（BETA_PLAN.md:226）。作成 2026-07-10。
     OPS-062: 本文のすべての事実主張は 2026-07-10 時点のディスク上の実態に照合済み。
     公開前に W4 の再読（BETA_PLAN.md:233）で検証済み事実と再照合すること。
     TFA claim boundary（BETA_PLAN.md:52-55）: 検証済みの電話機マトリクスの範囲のみを
     主張する。IVI／車載ハードウェア到達は一切主張しない。 -->

**状態**: 草稿（ストア未公開）。掲載時に最新の検証状態と再照合してから使用する。

**表示名**: SNGNav。<!-- AndroidManifest.xml の android:label は "SNGNav" 済み
（AAA 実測 2026-07-11）。旧「未確定 / sngnav_app」注記は解消。 -->

---

## 簡単な説明（80字以内・案）

雪道の運転を支える情報アプリ（アルファ版）。気象庁の観測値と、路面凍結の可能性の推定を表示し、音声と振動で知らせます。

## 詳しい説明（ja）

雪国の毎日の運転を支えるための情報アプリです。秋田を最初の対象地域として開発しています。現在はアルファ段階で、少人数のテスト参加者と一緒に確かめながら育てています。

**このアプリは情報を提示するだけで、運転の責任は常に運転者にあります。車両を制御することはありません。**
<!-- README.md:21 の register に一致 -->

### できること（2026年7月時点）

- **気象庁アメダスの観測値の表示** — 気温・湿度・風・積雪・10分間降水量・観測時刻。観測値は気象庁の発表値をそのまま表示します（改変・加工しません）。
  <!-- main.dart:1527 verbatim relay; README.md:14 -->
- **路面凍結ウォッチ** — 観測値から推定した「見えない凍結（ブラックアイスバーン）」の可能性を、**気象庁の発表ではなく本アプリの推定であると明記した上で**表示・読み上げます。判断に必要な観測値が足りないときは「判定不能」と表示し、勝手に「問題なし」とは言いません。
  <!-- README.md:15; main.dart:1510-1529 — 観測値は気象庁の値をそのまま表示、ウォッチ行はそこからの推定と明記 -->
- **オフライン地図** — 秋田県の実際の OpenStreetMap 地図データを端末に同梱。電波がない場所でも地図が表示されます（同梱範囲外は通信で補完）。
  地図データ: © OpenStreetMap contributors（ODbL ライセンス）
  <!-- README.md:25; Geofabrik cut tohoku-260709 -->
- **GPS 現在地表示** — 同意した場合のみ。アプリを開いている間だけ使い、バックグラウンドでの位置追跡は設計上行いません。
- **走行中の注意は音声と振動で知らせます。走行中は画面を注視しないでください。** 画面での確認は、出発前または安全な場所に停車してから行ってください。
  <!-- AAA 掲載ガードレール 2026-07-11（道交法71条5号の5 との整合; D4）。
       eyes-off 設計（HEAR/FEEL チャンネル + wakelock）は README.md:21-23 -->

  <!-- AndroidManifest.xml:6-8; app_localizations.dart:136-141 -->
- **走行中の注意表示（HUD）と音声・振動の通知** — 注意の上限は「停車の検討」です。「引き返せ」のような指示はしません。
  <!-- main.dart:743-745 -->
- **警報・注意報カード** — 現在地周辺の気象庁の警報・注意報を表示します。

### 正直な現状（アルファ段階の限界）

- **動作検証の範囲は限られています。** 検証は実機1台とエミュレータ（Android API 30/34/36 系）の範囲で行っており、「どの端末でも動く」とは言えません。
  <!-- BETA_PLAN.md:30-32 N=1 device matrix。2026-07-10 時点の実態: エミュレータ API 30 は
       フルウォーク済み（ladder_out/FINDINGS.md）、API 34/36 は未実施（正直スキップ）、
       実機時間（A2/A5）はこれから。掲載前に必ず実態と再照合すること。 -->
- **オフライン地図はエミュレータでの検証済みです**（2026-07-10 機内モード通し確認）。実機での確認はこれからです。
  <!-- BETA_PLAN.md:177-190 -->
- **音声・振動を実機で「聞こえる・感じられる」ことの確認はまだです。** 読み上げの仕組み自体はエミュレータで確認済みですが、実機での聴取・体感は未検証です。
  <!-- README.md:23; docs/DEVICE_VERIFICATION.md:96-99; app_localizations.dart:167-171 の register -->
- **凍結検知の実地検証は初雪（2026年11月頃）に予定しています。** 道路が実際に凍るまで、このアプリの中心の約束は本番の条件では確認できません。走行機能の検証と凍結検知の実地検証は、別のものとして扱い、混同しません。
  <!-- BETA_PLAN.md:34-38; README.md:27 — drive-loop と mission-loop の非混同 -->
- **読み上げの言語について。** 走行中 HUD と路面凍結ウォッチの読み上げは端末の言語設定に従います（日本語／英語）。ただし「路面状態の説明」の読み上げは運転者プロファイルに紐づいており、外国人観光客プロファイルを選んだ場合は英語で読み上げます。
  <!-- W3 修正は着地済み（main.dart:453/974-984 が ttsTag で ja/en 選択 —
       AAA 実測 2026-07-11。「着地を前提」注記は解消）。
       説明読み上げのプロファイル紐づけ: main.dart:999 explainer.localeTag。
       「日本語のみ」という一括表現はしない — 正確なスコープで述べる。 -->
- **オフラインでも音声が出るよう、端末に日本語のオフライン音声データ（テキスト読み上げ）のインストールを推奨します。** 音声データがない端末では、電波のない場所で読み上げが無音になることがあります。
  <!-- BETA_PLAN.md:160-165 local-ja-TTS-voice 依存 -->
- **画面表示は日本語化を進めています。** 同意・警報・ウォッチの各表示は日本語ですが、一部にまだ英語表示が残ります。
  <!-- README.md:25; BETA_PLAN.md:218 C5 未クローズ — full-ja UI を示唆しない -->
- **経路表示は雪を考慮しません。** 経路は道路のつながりだけを反映し、峠の冬季閉鎖・除雪状況・チェーン規制は分かりません。経路をたどる前の判断は運転者のものです。
  <!-- KNOWN_LIMITATIONS.md 気象業務法境界 + OSRM 節 -->

### プライバシー

- テレメトリ（利用状況の自動送信）はありません。アカウント登録は不要です。広告・解析 SDK は入っていません。
- 位置情報の共有は任意（オプトイン）で、アプリの使用中のみです。座標は端末に保存されず、本アプリ独自のサーバーへ送信されることはありません（そもそもサーバーがありません）。
  <!-- app_localizations.dart:136-141 の register に一致 -->
- 不具合ログは端末内だけに保存されます（約200KB上限）。「ログを共有」を押したときだけ、端末の共有機能を通じて送られます。
  <!-- lib/services/error_log.dart:9-15 -->
- 詳細は プライバシーポリシー（docs/store/privacy_policy_ja.md を掲載したページ）をご覧ください。

### 開発について

オープンソースで開発しています: https://github.com/aki1770-del/sngnav-app
おかしいと思ったこと（計算が合わない、観測値が窓の外と違う、鳴るべきでない警告が鳴った など）があれば、ぜひ教えてください。黙った欠陥は、認めた欠陥より悪い失敗です。
<!-- README.md:52-54 honest-disclosure invite の register -->

---

## English summary (short)

Alpha-stage advisory app for snow-country driving in Japan (Akita-first). Shows verbatim JMA weather observations and a clearly-labeled **derived** invisible-ice (black ice) watch — an inference, never a JMA statement; missing data reads "cannot judge", never "clear". Bundled offline OpenStreetMap basemap for Akita (© OpenStreetMap contributors, ODbL), opt-in foreground-only GPS, drive-caution HUD whose ceiling is "consider stopping" — never "turn back".

**Honest bounds:** the app surfaces information only; the driver remains responsible for all driving decisions; it does not control the vehicle. Verified on a small device matrix (one physical device + emulators) — not claimable for all phones. Offline map is emulator-verified (2026-07-10 airplane-mode pass); on-device audio/haptic HEAR/FEEL still unverified. Ice-mission field verification is scheduled for first snow, ~November 2026 — the drive-loop claim and the ice-mission claim are never conflated. Spoken drive-HUD and ice-watch lines follow the device locale (ja/en); the condition-explainer announcement is driver-profile-bound (English on the foreign-tourist profile). Installing an offline Japanese TTS voice is recommended so speech works without a network. No telemetry, no accounts, no ads/analytics SDKs; crash log stays on-device (~200 KB cap) and leaves only via the user-initiated share action.
