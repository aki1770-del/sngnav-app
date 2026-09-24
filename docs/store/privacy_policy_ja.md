# プライバシーポリシー — sngnav-app

最終更新: 2026-09-24

<!-- Play Console は位置情報を要求するアプリに公開されたプライバシーポリシー URL を
     求める。本ファイルはその原文（ja 主・en 全訳付き）。ホスティング先が決まったら
     そのページにこの内容を掲載する。
     OPS-062: 権限は scout_full_3 §(2)、送信先は §(3) と正確に一致させている。
     2026-09-24 AAE 更新 — 上の 2026-07-10 版はここで「FOREGROUND_SERVICE /
     FOREGROUND_SERVICE_LOCATION は本チェンジセットでマニフェストから削除される
     ため記載しない」と書き、同時に「万一削除が着地しないまま公開する場合は、本
     ページの権限一覧をマニフェストの実態に合わせて更新すること」と指示していた。
     この 2 権限は 2026-09-24 に、削除時に置かれた条件（運転者自身が開始する、
     通知の見える常時サービスが実際に作られたとき）を満たして**戻った**。
     指示どおり、本ページの権限一覧をマニフェストの実態に合わせて更新した。
     出典は本日ビルドした release のマージ後マニフェスト
     build/app/intermediates/merged_manifests/release/
       processReleaseManifest/AndroidManifest.xml（uses-permission 7 件）。
     ⚑ 権限が増えたときは、権限表だけでなく「収集しないもの」の記述も読み直すこと —
     今回の 2 権限は『画面に表示されている間だけ』という文そのものを偽にした。

     2026-08-10 AAE 訂正（OPS-062(A) / AAE-7）— 出典を「ソースのマニフェスト」から
     「実際に配布されるマニフェスト」へ切り替えた。
     旧版の権限表は android/app/src/main/AndroidManifest.xml（＝我々が書いた行）だけを
     読んで作られていた。APK に実際に入るのはプラグインをマージした後のマニフェストで、
     そこには vibration プラグイン由来の VIBRATE が含まれる。旧版はそれを載せないまま
     「これ以外の権限は要求しません」と書いており、配布物と食い違っていた。
     本表の出典は、この日ビルドした release APK の
     build/app/intermediates/packaged_manifests/release/
       processReleaseManifestForPackage/AndroidManifest.xml:15,21,22,27,45
     （aapt2 dump badging でも同一を確認）。
     権限を足したのではない — 前から入っていたものを、初めて正直に書いた。
     以後この表を更新するときは、必ずマージ後のマニフェストを読むこと。

     2026-09-24 CT 追記（AAE 3ce5de6 の統合時）— AAE 版はこの 2026-08-10 の
     ブロックごと削除していた。削除すると『authored マニフェストを読むな、
     マージ後を読め』という指示そのものが消え、VIBRATE 行が再び落ちる。残す。
     AAE 版から持ち越した唯一の行: 権限表とマニフェストの一致は
     tool/assert_disclosure_parity.sh が機械的に検査する（ただし同スクリプトが
     読むのは authored マニフェストであり、マージ後ではない — VIBRATE のように
     プラグイン由来で増える権限は検査できない。honest bound）。 -->

本アプリ（sngnav-app）は、雪道の運転を支えるための情報アプリです。私たちは、あなたのデータをできる限り端末の外に出さない設計を選んでいます。このページは、アプリが何を使い、何を送り、何を送らないかを、実際のコードのとおりに説明するものです。

## 収集しないもの

- **テレメトリはありません。** 利用状況・操作履歴などが自動送信されることはありません。
- **アカウントはありません。** 登録・ログインは不要で、個人情報の入力欄もありません。
- **広告 SDK・解析（アナリティクス）SDK は入っていません。**
- **本アプリ独自のサーバーはありません。** あなたのデータが「私たちのサーバー」に送られることはありません — 存在しないためです。
- **通知の出ない、こっそりした位置情報取得は行いません。** Android の ACCESS_BACKGROUND_LOCATION 権限は要求していません。位置情報を使うのは次の 2 つの場合だけです — (1) アプリを画面に表示している間、(2) **あなた自身が「現在地を共有」を押して運転を開始したあと**、その運転が続いている間。(2) では画面を消しても、アプリを閉じても受信が続きます（雪道で画面を見ていられないときに警告を止めないためです）。ただし **その間はずっと通知が表示されます**。通知をタップして「停止」を押せば、運転と位置情報の受信が同時に終わります。**通知が出ていない状態で位置情報を取ることはありません。**
  <!-- AndroidManifest.xml の uses-permission 7 件。ACCESS_BACKGROUND_LOCATION は
       今も要求していない。(2) は前景サービス（geolocator の
       GeolocatorLocationService、foregroundServiceType="location"）による。 -->

## アプリが要求する権限（Android）

| 権限 | 用途 |
|---|---|
| INTERNET | 気象データ・経路・地図タイルの取得（下記「端末の外に出るデータ」の4つのみ） |
| ACCESS_FINE_LOCATION | 地図上の現在地表示と、走行中の路面警告。**同意した場合のみ**。アプリの表示中、または**あなたが開始した運転中**（その間は通知が出ています） |
| ACCESS_COARSE_LOCATION | 同上（端末が精密な位置を返せない場合の粗い位置） |
| WAKE_LOCK | 走行画面を表示している間、画面を消灯させないため。加えて、あなたが開始した運転中は、**画面を消していても警告が届くように**端末が眠り込むのを防ぎます |
| VIBRATE | 危険を知らせる**振動**（前を見たまま気づけるように）。音を聞き取りにくい方・吹雪で画面を見られない場面のための channel です |
| FOREGROUND_SERVICE | あなたが「現在地を共有」で開始した運転の間、**通知を表示したまま**位置情報の受信を続けるため。通知の出ない実行はありません |
| FOREGROUND_SERVICE_LOCATION | 上記サービスが扱うのが位置情報であることを OS に明示するため（Android 14 以降、これが無いと運転中の受信そのものが OS に拒否されます） |
| POST_NOTIFICATIONS | 運転中であることを示す**あの通知そのもの**を表示するため。Android 13 以降はこの許可が無いと通知が出ません。**許可しなかった場合、アプリは前景サービスを開始しません** — 見えない通知の裏で位置情報を使うことはしないので、その場合の運転は画面を表示している間だけになります |

<!-- 出典＝配布されるマニフェスト（マージ後）:
     build/app/intermediates/merged_manifests/release/
       processReleaseManifest/AndroidManifest.xml（uses-permission 7 件。
       行番号は書かない — ファイルが動くと引用先が壊れるため）。
     VIBRATE の実使用: lib/actuators/mobile_alert_actuators.dart:191-192
     （Vibration.hasVibrator / Vibration.vibrate）。宣言のみの権限ではない。
     ⚑ 上の『7 件』は 2026-09-24 16:49 のビルド成果物の実測値であり、
     そのビルドは POST_NOTIFICATIONS 追加より前の系統のものである。
     本チェンジセットの authored マニフェストは 8 件（CT 実測）。
     マージ後マニフェストの再ビルドと再計数は AAE に owed — 未計測のまま
     数字を書き換えることはしない。
     FOREGROUND_SERVICE* の実使用: lib/main.dart の _shareLocation が
     herPositionStream に driveNotification を渡し、geolocator の
     GeolocatorLocationService が前景で動く。宣言のみではない。 -->

これ以外の権限（ストレージ・カメラ・連絡先・**バックグラウンド位置情報**など）は要求しません。

なお、ビルドの都合で `dev.aki1770del.sngnav_app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`
という**アプリ自身にしか効かない権限**が1つ自動生成されます（AndroidX が付与するもので、
`protectionLevel="signature"`）。これはアプリ内部の受信機を外部に公開しないための鍵であり、
端末のデータへのアクセス権ではありません。あなたの情報には一切関係しません。
<!-- packaged_manifests/…/AndroidManifest.xml:56-57（permission 宣言）, :59（uses-permission） -->

*訂正のお知らせ（2026-09-24）: FOREGROUND_SERVICE と FOREGROUND_SERVICE_LOCATION の
2 行を追加し、「位置情報を使うのは画面に表示されている間だけ」という記述を訂正しました。
この 2 権限は 2026-07-10 に「宣言だけで実体が無い」として削除され、「運転者自身が開始する、
通知の見えるサービスを実際に作ったときに同じ変更で戻す」と約束されていました。2026-09-24 に
そのサービスが実際に動いたため、約束どおり戻っています。**機能が先に着地し、この説明が後から
追いつく形になりました** — 本来は同じ変更で直すべきものです。アプリが新しくできるように
なったことは、画面を消していても運転中の警告が届くことであり、**通知が出ていない状態での
位置情報取得は、以前と同じく一切ありません。** ACCESS_BACKGROUND_LOCATION も引き続き
要求していません。*

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

Last updated: 2026-09-24

sngnav-app is an advisory app that supports driving on snowy roads. We deliberately keep your data on your device wherever possible. This page explains — matching the actual code — what the app uses, what it sends, and what it does not send.

## What we do NOT collect

- **No telemetry.** Usage data and interaction history are never sent automatically.
- **No accounts.** No registration, no login, no personal-information fields.
- **No advertising or analytics SDKs.**
- **No app-owned servers.** Your data is never sent to "our servers" — none exist.
- **No silent background location.** The app does not request Android's ACCESS_BACKGROUND_LOCATION permission. Location is used in exactly two cases: (1) while the app is on screen, and (2) after **you yourself** start a drive with 現在地を共有 ("Share my location"), for as long as that drive lasts. In case (2) the feed continues with the screen off and the app closed — so a warning still reaches you on a snow road you cannot watch a screen on — but **an ongoing notification is shown the entire time**. Tapping it and pressing 停止 ("Stop") ends the drive and the location feed together. **There is no location collection without that notification.**

## Permissions the app requests (Android)

| Permission | Purpose |
|---|---|
| INTERNET | Fetching weather data, routes, and map tiles (only the four flows listed below) |
| ACCESS_FINE_LOCATION | Showing your position on the map, and road warnings while driving. **Only after you consent** — while the app is on screen, or during **a drive you started** (the notification is shown throughout) |
| ACCESS_COARSE_LOCATION | Same flow (a coarse position when a precise one is unavailable) |
| WAKE_LOCK | Keeping the screen on while the driving surface is shown; and, during a drive you started, keeping the device from sleeping so that **warnings still arrive with the screen off** |
| VIBRATE | The **haptic** hazard cue — so a warning can be noticed without looking. This is the channel for a driver who cannot hear well, or cannot look at the screen in a whiteout |
| FOREGROUND_SERVICE | Keeping the position feed alive, **behind a notification you can see**, during a drive you started. It never runs without that notification |
| FOREGROUND_SERVICE_LOCATION | Declaring to the OS that this service handles location. From Android 14 the OS refuses the drive-time feed without it |
| POST_NOTIFICATIONS | Showing **that notification itself**. From Android 13 nothing is shown without it. **If you decline, the app does not start the foreground service at all** — we will not hold your location behind a notification you cannot see, so the drive is then screen-on only |

No other permissions (storage, camera, contacts, **background location**, etc.) are requested.

One further permission is generated automatically by the build and is listed here for
completeness: `dev.aki1770del.sngnav_app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. AndroidX
defines it with `protectionLevel="signature"` so that the app's own dynamically registered
broadcast receivers are not exported to other apps. It grants no access to anything on your
device and touches none of your data.

*Correction note (2026-08-10): the VIBRATE row was missing from earlier versions of this page.
The permission was always present in the shipped app — the page had been written from the
manifest we author by hand, not from the merged manifest that is actually packaged. Nothing was
added to the app; a permission it already requested is now stated honestly. The source for this
table is the packaged release manifest of a build made on the date above.*

*Correction note (2026-09-24): the FOREGROUND_SERVICE and FOREGROUND_SERVICE_LOCATION rows were
added, and the sentence "location is used only while the app is on screen" was corrected. Those two
permissions were removed on 2026-07-10 as declared-but-unused, on a written promise that they would
return in the same change-set as a real, driver-started, notification-visible service. That service
landed on 2026-09-24 and they returned with it. **The capability landed first and this page caught
up afterwards** — it should have been one change. What the app can now do is keep warning you with
the screen off during a drive you started; what has NOT changed is that **there is no location
collection without a visible notification**, and ACCESS_BACKGROUND_LOCATION is still not requested.*

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
