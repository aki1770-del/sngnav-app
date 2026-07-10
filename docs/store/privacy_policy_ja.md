# プライバシーポリシー — sngnav-app

最終更新: 2026-07-10

<!-- Play Console は位置情報を要求するアプリに公開されたプライバシーポリシー URL を
     求める。本ファイルはその原文（ja 主・en 全訳付き）。ホスティング先が決まったら
     そのページにこの内容を掲載する。
     OPS-062: 権限は scout_full_3 §(2)、送信先は §(3) と正確に一致させている。
     FOREGROUND_SERVICE / FOREGROUND_SERVICE_LOCATION は本チェンジセットで
     マニフェストから削除されるため記載しない（宣言のみ・未使用だったもの。
     scout 062-6）。万一削除が着地しないまま公開する場合は、本ページの権限一覧を
     マニフェストの実態に合わせて更新すること。 -->

本アプリ（sngnav-app）は、雪道の運転を支えるための情報アプリです。私たちは、あなたのデータをできる限り端末の外に出さない設計を選んでいます。このページは、アプリが何を使い、何を送り、何を送らないかを、実際のコードのとおりに説明するものです。

## 収集しないもの

- **テレメトリはありません。** 利用状況・操作履歴などが自動送信されることはありません。
- **アカウントはありません。** 登録・ログインは不要で、個人情報の入力欄もありません。
- **広告 SDK・解析（アナリティクス）SDK は入っていません。**
- **本アプリ独自のサーバーはありません。** あなたのデータが「私たちのサーバー」に送られることはありません — 存在しないためです。
- **バックグラウンドでの位置情報取得は設計上行いません。** Android の ACCESS_BACKGROUND_LOCATION 権限は要求していません。位置情報を使うのはアプリが画面に表示されている間だけです。
  <!-- AndroidManifest.xml:6-8 -->

## アプリが要求する権限（Android）

| 権限 | 用途 |
|---|---|
| INTERNET | 気象データ・経路・地図タイルの取得（下記「端末の外に出るデータ」の4つのみ） |
| ACCESS_FINE_LOCATION | 地図上の現在地表示。**同意した場合のみ**・アプリの使用中のみ |
| ACCESS_COARSE_LOCATION | 同上（端末が精密な位置を返せない場合の粗い位置） |
| WAKE_LOCK | 走行中に画面を消灯させないため（走行画面の表示中のみ） |

<!-- AndroidManifest.xml:5,9,10,13; 用途の根拠は scout_full_3 §(2) の code evidence -->

これ以外の権限（ストレージ・カメラ・連絡先・バックグラウンド位置情報など）は要求しません。

## 端末の外に出るデータ（この4つがすべてです）

1. **気象庁アメダス観測値の取得** — アプリの起動時と再取得時に、あらかじめ決められた観測所 ID（秋田周辺の固定5地点）のデータを気象庁のサーバー（www.jma.go.jp）から取得します。**あなたの座標は送信されません。** 通信には連絡先として本アプリの公開リポジトリ URL を含む User-Agent が付きます（気象庁側の流量管理・セキュリティ連絡のためのもので、あなたを識別するものではありません）。
   <!-- jma_fetch.dart:24,48,134-154; main.dart:79-84 -->

2. **警報・注意報の取得（同意した場合のみ）** — 現在地の共有に同意すると、走行約1kmごとに現在の座標が、**その地域を管轄する公的な気象機関のみ**に送信されます（日本国内の地点は気象庁のみ、米国内の地点は NWS のみ。管轄外の機関に座標が送信されることはありません）。座標はメモリ上でのみ扱われ、端末に保存されません。
   <!-- main.dart:753-770; services/advisory_service.dart:12-17; provider_coverage.dart;
        app_localizations.dart:136-148 のアプリ内開示と同内容 -->

3. **経路検索** — 地図上であなたが**タップして指定した**出発地・目的地の座標が、経路計算のために OSRM 公開デモサーバー（router.project-osrm.org）へ送信されます。GPS の現在地が経路検索へ自動送信されることはありません。OSRM デモサーバーは第三者が運営する公開サービスです。
   <!-- main.dart:868-885（タップ由来）, 921-926, 956（送信）。GPS 自動供給なし -->

4. **地図タイルの補完取得** — 同梱のオフライン地図がカバーしない範囲を表示したとき、その部分のタイル座標（おおまかな表示領域に相当する情報）が OpenStreetMap のタイルサーバー（tile.openstreetmap.org）へ送信されます。同梱範囲内はオフラインで表示され、通信は発生しません。
   <!-- akita_map.dart:90; services/offline_basemap.dart:53-56 offline-first -->

上記のほかに、端末の外に出るデータはありません。

## 不具合ログについて

アプリ内部のエラーは、端末内のログファイルにのみ記録されます（上限約200KB。超えた分は古いものから消えます）。このログが端末の外に出るのは、**あなたが「ログを共有」を押して端末の共有機能で送ったときだけ**です。自動送信はありません。
<!-- lib/services/error_log.dart:9-15,32 -->

## お問い合わせ

- メール: aki1770@gmail.com
- 開発リポジトリ: https://github.com/aki1770-del/sngnav-app

このポリシーに変更があった場合は、このページの日付を更新してお知らせします。

---

# Privacy Policy — sngnav-app (English)

Last updated: 2026-07-10

sngnav-app is an advisory app that supports driving on snowy roads. We deliberately keep your data on your device wherever possible. This page explains — matching the actual code — what the app uses, what it sends, and what it does not send.

## What we do NOT collect

- **No telemetry.** Usage data and interaction history are never sent automatically.
- **No accounts.** No registration, no login, no personal-information fields.
- **No advertising or analytics SDKs.**
- **No app-owned servers.** Your data is never sent to "our servers" — none exist.
- **No background location by design.** The app does not request Android's ACCESS_BACKGROUND_LOCATION permission. Location is used only while the app is on screen.

## Permissions the app requests (Android)

| Permission | Purpose |
|---|---|
| INTERNET | Fetching weather data, routes, and map tiles (only the four flows listed below) |
| ACCESS_FINE_LOCATION | Showing your position on the map. **Only after you consent**, and only while the app is in use |
| ACCESS_COARSE_LOCATION | Same flow (a coarse position when a precise one is unavailable) |
| WAKE_LOCK | Keeping the screen on while the driving surface is shown |

No other permissions (storage, camera, contacts, background location, etc.) are requested.

## Data that leaves your device (these four flows are all of it)

1. **JMA AMeDAS observation fetch** — on app start and re-fetch, the app requests data for fixed, pre-configured weather-station IDs (a five-station corridor around Akita) from the Japan Meteorological Agency servers (www.jma.go.jp). **Your coordinates are not sent.** Requests carry a User-Agent containing this app's public repository URL, so the publisher can do rate-limit accounting and reach a security contact — it does not identify you.

2. **Advisory fetch (only after consent)** — if you consent to sharing your location, your current coordinates are sent about once per kilometre of travel **only to the public weather agency with jurisdiction over your area** (a point in Japan goes to the JMA only; a point in the United States goes to the NWS only; an agency that does not cover your location is never contacted). Coordinates are held in memory only and are never persisted on the device.

3. **Route lookup** — the origin and destination coordinates **you tap on the map** are sent to the public OSRM demo router (router.project-osrm.org) to compute a route. Your GPS position is never fed to the router automatically. The OSRM demo server is a third-party public service.

4. **Map-tile fallback** — when you view an area the bundled offline basemap does not cover, the tile coordinates for that area (roughly equivalent to a coarse viewport location) are sent to the OpenStreetMap tile server (tile.openstreetmap.org). Areas within the bundled coverage render offline with no network traffic.

Nothing else leaves the device.

## Crash / error log

Internal errors are recorded only in a local log file on your device (capped at roughly 200 KB; oldest entries are dropped first). The log leaves your device **only when you press "ログを共有" (Share log) and send it through your device's share sheet**. There is no automatic upload.

## Contact

- Email: aki1770@gmail.com
- Repository: https://github.com/aki1770-del/sngnav-app

If this policy changes, we will update the date on this page.
