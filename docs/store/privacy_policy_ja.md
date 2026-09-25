# プライバシーポリシー — sngnav-app

最終更新: 2026-09-25

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
     ⚑ 2026-09-25 注記: この『7 件』は POST_NOTIFICATIONS 追加より前のビルドの
     実測値。いまの authored マニフェストは 8 件で、本ページの権限表も 8 行。
     マージ後マニフェストの再ビルドと再計数はまだ行っていない（下の :71 付近の
     コメントと同じ owed）。未計測の数字には書き換えない。
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
- **あなたが始めていない位置情報の取得は行いません。** Android の ACCESS_BACKGROUND_LOCATION 権限は要求していません。位置情報を使うのは次の 2 つの場合だけです — (1) アプリを画面に表示している間、(2) **あなた自身が「現在地を共有」を押して運転を開始したあと**、その運転が続いている間。(2) では画面を消しても、ほかのアプリに切り替えても受信が続きます（雪道で画面を見ていられないときに警告を止めないためです）。最近使ったアプリの一覧からアプリを消した場合にどうなるかは、まだ確かめていません。運転を始めると、アプリは運転中であることを示す通知を出し、運転が終わるまで自分からは取り下げません。アプリを開いて（または通知をタップして）「停止」を押せば、運転と位置情報の受信が同時に終わります。**あなたが受信を終えるための操作は「停止」です。確実に終えるには「停止」を押してください。** 通知を消しても受信は終わりません。このほか、Android がアプリを終了させたときや、位置情報の提供を止めたときにも受信は終わります。（2026-09-25 訂正: 以前は「受信を終わらせるのは『停止』だけです」「アプリを閉じても受信が続きます」と書いていました。前者は言い過ぎで、後者のうち一覧から消す場合は確かめていませんでした。） ⚑ **ただし、この通知が見えない場合が 2 つあります（2026-09-25 訂正）。** (a) **画面をロックしている間は、ロック画面にこの通知が表示されないことがあります。** (b) **Android 14 以降では、この通知を横にスワイプして消すことができます。消しても位置情報の受信は止まりません。** どちらも、Android 14 の試験用エミュレーター（実機ではありません）で本アプリと同じ通知の設定を再現して確かめたことです — (a) ロック中の画面には表示されず、(b) スワイプで通知が消えたあとも、受信を担う前景サービスは動き続けました。Android 11 の試験用エミュレーターでは、同じスワイプで通知は消えませんでした。お使いの機種で同じになるかは、まだ確かめていません。このページは以前、「通知が出ていない状態で位置情報を取ることはありません」「この通知は消すこともできません」と書いていました。この 2 つの場合には、どちらも正しくありませんでした。
  <!-- AndroidManifest.xml の uses-permission 7 件（⚑ 2026-09-25: POST_NOTIFICATIONS
       追加前のビルドの数。authored マニフェストはいま 8 件。マージ後の再計数は owed）。
       ACCESS_BACKGROUND_LOCATION は
       今も要求していない。(2) は前景サービス（geolocator の
       GeolocatorLocationService、foregroundServiceType="location"）による。 -->

## アプリが要求する権限（Android）

| 権限 | 用途 |
|---|---|
| INTERNET | 気象データ・経路・地図タイルの取得と、新しいビルドがあるかの確認（下記「端末の外に出るデータ」の6つのみ） |
| ACCESS_FINE_LOCATION | 地図上の現在地表示と、走行中の路面警告。**同意した場合のみ**。アプリの表示中、または**あなたが開始した運転中**（運転中は通知を出しますが、見えない場合があります — 上の「収集しないもの」を参照） |
| ACCESS_COARSE_LOCATION | 同上（端末が精密な位置を返せない場合の粗い位置） |
| WAKE_LOCK | 走行画面を表示している間、画面を消灯させないため。加えて、あなたが開始した運転中は、**画面を消していても警告が届くように**端末が眠り込むのを防ぎます |
| VIBRATE | 危険を知らせる**振動**（前を見たまま気づけるように）。音を聞き取りにくい方・吹雪で画面を見られない場面のための channel です |
| FOREGROUND_SERVICE | あなたが「現在地を共有」で開始した運転の間、位置情報の受信を続けるため。開始と同時に通知を出します。ただし Android 14 以降はその通知をスワイプで消すことができ、消しても受信は続きます（アプリの「停止」で終わります）。ロック中の画面には表示されないことがあります |
| FOREGROUND_SERVICE_LOCATION | 上記サービスが扱うのが位置情報であることを OS に明示するため（Android 14 以降、これが無いと運転中の受信そのものが OS に拒否されます） |
| POST_NOTIFICATIONS | 運転中であることを示す**あの通知そのもの**を表示するため。Android 13 以降はこの許可が無いと通知が出ません。**許可しなかった場合、アプリは前景サービスを開始しません** — 通知を出せない状態で運転中の受信を始めることはしないので、その場合の運転は画面を表示している間だけになります |

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

*訂正のお知らせ（2026-08-10）: 以前のこのページには VIBRATE の行がありませんでした。
この権限は配布したアプリに最初から含まれていました — このページが、実際に配布される
（プラグインを合わせた後の）マニフェストではなく、手で書いたマニフェストから作られて
いたためです。アプリに何かを足したのではなく、すでに要求していた権限を正直に書いた
ものです。この表の出典は、上記の日付にビルドした release のマニフェストです。*
<!-- 2026-09-25: この訂正は英語の後半にだけ見える形で書かれ、日本語（主）の側では
     上の HTML コメントの中にしかなかった。コメントは画面に出ないため、日本語で読む人
     には 2 件、英語で読む人には 3 件の訂正が見えていた。英語側と同じ内容をここに置く。 -->

*訂正のお知らせ（2026-09-24）: FOREGROUND_SERVICE と FOREGROUND_SERVICE_LOCATION の
2 行を追加し、「位置情報を使うのは画面に表示されている間だけ」という記述を訂正しました。
この 2 権限は 2026-07-10 に「宣言だけで実体が無い」として削除され、「運転者自身が開始する、
通知の見えるサービスを実際に作ったときに同じ変更で戻す」と約束されていました。2026-09-24 に
そのサービスが実際に動いたため、約束どおり戻っています。**機能が先に着地し、この説明が後から
追いつく形になりました** — 本来は同じ変更で直すべきものです。アプリが新しくできるように
なったことは、画面を消していても運転中の警告が届くことです。ACCESS_BACKGROUND_LOCATION も
引き続き要求していません。*

*訂正のお知らせ（2026-09-25）: 上の 2026-09-24 のお知らせには、もう一文、
「通知が出ていない状態での位置情報取得は、以前と同じく一切ありません。」と書いていました。
この一文は正しくなかったため、そのお知らせから取り除き、ここに残しています。運転中の通知は、
ロック中の画面には表示されないことがあり、Android 14 以降ではスワイプで消せて、消しても
位置情報の受信は続きます（上の「収集しないもの」を参照）。どちらも Android 14 の試験用
エミュレーターで確かめたことで、実機ではまだ確かめていません。*
<!-- 2026-09-25: この一文は以前、取り消し線の記法で消した形で上のお知らせに残していた。
     アプリ内のポリシー表示は取り消し線を描かないため、アプリの中では取り消した一文が太字の
     まま、両側に記法の記号が付いて表示され、このお知らせは見えない「取り消し線」を指していた。
     取り消し線は読み上げ（スクリーンリーダー）でも伝わらない。取り消しは言葉で書く。
     test/services/privacy_policy_render_test.dart が、この文書に取り消し線の記法が無いことを確かめる。 -->

## 端末の外に出るデータ（この6つがすべてです）

1. **気象庁アメダス観測値の取得** — 秋田県内の決められた 5 か所の観測所（男鹿・秋田・大曲・横手・湯沢）の観測値を、気象庁のサーバー（www.jma.go.jp）から取得します。アプリの起動時に 5 か所すべてを取得し、その後は秋田の観測所を約10分ごとに取得します。観測所の一覧で再取得を押したときは、5 か所すべてを取り直します。現在地を共有するかどうかに関係なく行い、**あなたの座標は送信されません。** 通信には、本アプリの名前（sngnav-app）と、連絡先として開発プロジェクトの公開リポジトリ URL（https://github.com/aki1770-del/sngnav）を含む User-Agent が付きます（気象庁側の流量管理・セキュリティ連絡のためのもので、あなたを識別するものではありません）。
   <!-- flow: jma-amedas -->
   <!-- 出典（記号で引用）: jma_fetch.dart の fetchLatestObservation（既定の観測所 akitaStationId = 32402）と
        fetchCorridorObservations（corridorStations の 5 件）。main.dart の _refreshJma（initState と
        _jmaTicker の 10 分ごと）と _refreshCorridor（initState と再取得ボタン）。
        ⚑ 2026-09-25 訂正（コード側）: 沿線 5 か所の要求には User-Agent が付いておらず、本文の
        「通信には…User-Agent が付きます」は起動時の 6 要求のうち 5 つで偽だった。コードを直し、
        test/jma_corridor_user_agent_test.dart が lib/ の全呼び出しを固定している。 -->

2. **気象庁の予報の取得** — 秋田県の予報（予報区コード 050000。固定で、あなたの現在地では変わりません）を、気象庁のサーバー（www.jma.go.jp）から取得します。観測値の取得に成功したときに、手元の予報が 3 時間より古ければ取り直します（取れなかったときは、次に観測値が取れたときに再試行します）。現在地を共有するかどうかに関係なく行い、**あなたの座標は送信されません。** User-Agent は 1 と同じです。
   <!-- flow: jma-forecast -->
   <!-- 出典: services/jma_forecast_fetch.dart の fetchJmaForecast（既定 akitaForecastAreaCode = 050000）。
        main.dart の _captureTripHazardMemory（3 時間未満の記憶があれば早期 return）。
        ⚑ 2026-09-25 追加: この要求は以前どの項目にも書かれておらず、見出しは「この5つがすべてです」
        だった。予報は 1 の観測と同じホスト（www.jma.go.jp）なので、ホスト単位の照合では見えなかった。 -->

3. **警報・注意報の取得** — **現在地を共有しているあいだ**は、走行約1kmごとに（停車中や、運転中に画面を消しているときも約10分ごとに）、**その地域を管轄する公的な気象機関のみ**に警報・注意報を問い合わせます。**日本国内では、あなたの座標は端末の外に出ません** — 端末の中で現在地から都道府県を判定し、気象庁には都道府県コードだけを送ります（都道府県単位のおおまかな位置に相当します。県境の近くでは、該当しうる県それぞれのコードを送るため、県境付近にいることまでは分かります）。**米国内では、地点の警報を得るため座標が NWS（米国国立気象局）に送信されます。** 現在地を使う問い合わせを、現在地を管轄しない機関に送ることはありません。**現在地を共有していないとき、または位置がまだ分からないときは、秋田県の警報・注意報を約10分ごとに取得します**（あなたの位置は使いません）。座標はメモリ上でのみ扱われ、端末に保存されません。（2026-09-25 訂正: 以前は「日本国内でも座標が気象庁に送信される」と書いていましたが、これは正しくありませんでした。また、この項目には「同意した場合のみ」とありましたが、秋田県の警報・注意報の取得は、同意の前から行われていました。さらに「現在地を管轄しない機関に問い合わせることはありません」と書いていましたが、気象庁にはあなたがどこにいても起動時から秋田県のデータを問い合わせるため、言い切りとしては正しくありませんでした。現在地を使う問い合わせに限った書き方に直しています。）
   <!-- flow: warnings -->
   <!-- 出典（記号で引用）: condition_aggregator_jma 0.7.1（pubspec.lock が解決する版）の
        jma_advisory_provider.dart — 要求 URL は `$warningJsonBaseUrl$prefectureCode.json`
        （bosai/warning/data/r8/ = 都道府県コード）。座標→都道府県の判定は同パッケージの境界ボックスで、
        端末内。県境付近では prefectureCodesForPoint が複数のコードを返す（パッケージの過剰警告の方針）。
        米国は NWS に地点座標。範囲判定は lib/services/provider_coverage.dart / advisory_service.dart の
        coversPoint。約10分ごと: main.dart の _jmaTicker（Timer.periodic 10 分）→ _onAdvisoryRefreshTapped。
        位置が無いとき: _onAdvisoryRefreshTapped が akitaStation の座標で _refreshAdvisories を呼ぶ（同意の
        ゲートは無い）。⚑ 2026-09-25: 旧見出しの「（同意した場合のみ）」はこの経路について偽だった。 -->

4. **経路検索** — 地図上であなたが**タップして指定した**出発地・目的地の座標が、経路計算のために OSRM 公開デモサーバー（router.project-osrm.org）へ送信されます。GPS の現在地が経路検索へ自動送信されることはありません。OSRM デモサーバーは第三者が運営する公開サービスです。
   <!-- flow: route -->
   <!-- main.dart:868-885（タップ由来）, 921-926, 956（送信）。GPS 自動供給なし -->

5. **地図タイルの補完取得** — 同梱のオフライン地図がカバーしない範囲を表示したとき、その部分のタイル座標（おおまかな表示領域に相当する情報）が OpenStreetMap のタイルサーバー（tile.openstreetmap.org）へ送信されます。同梱範囲内はオフラインで表示され、通信は発生しません。
   <!-- flow: tiles -->
   <!-- akita_map.dart:90; services/offline_basemap.dart:53-56 offline-first -->

6. **新しいビルドがあるかの確認** — 最初の画面が出た直後に、公開バージョン一覧（JSON）を取得します。取得先は、アプリに組み込まれた GitHub の配信サーバー（raw.githubusercontent.com）か、以前の一覧が示した新しい置き場所です。**あなたの座標も、端末を識別する情報も送信しません**（リクエストに本文はありません）。本アプリはストア外配布で自動更新が無く、この確認が無いと修正を出してもお知らせする手段がありません。**確認は起動直後の 1 回だけで、繰り返しません。** **一覧の置き場所は変わることがあります。** 一覧が自分の新しい置き場所として別の https のアドレスを示したときは、新しいビルドがあるかどうかに関係なく、そのアドレスへ 1 回だけ要求を送ります（転送〈リダイレクト〉はたどりません）。そこにある一覧が自分の場所としてそのアドレスを示し、このアプリのものであるときにかぎり、そのアドレスを端末に保存し、次の起動からそこを使います。保存するのは一覧を置く場所のアドレスで、あなたの情報ではありません。このアドレスも一覧が指定するもので、アプリの中に固定されていません。 一覧があなたのものより新しいビルドを示したときにかぎり、**その一覧が指定した配布先 URL** へ「実際に入手できるか」の存在確認だけを送ります（ダウンロードはしません）。**この配布先のホストは一覧が指定するもので、アプリの中に固定されていません**（現在は GitHub）。アプリが何かをインストールすることはありません（REQUEST_INSTALL_PACKAGES は要求していません）。（2026-09-25 訂正: 以前は「運転中であればその 1 回も行いません」と書いていました。確認は、運転を始められるより前の起動直後に行われるため、この一文が防いでいることは何もなく、確認の途中で運転を始めても確認は止まりません。）
   <!-- flow: update-check -->
   <!-- describes: manifest-address-reader -->
   <!-- 置き場所の移動（2026-09-25 追記）の出典: services/update_check.dart の
        UpdateChecker.resolveManifestUrl（保存された https のアドレス、無ければ組み込みの既定）、
        check → _goAndSee（新しいアドレスへ 1 回 GET、followRedirects = false、そこで一覧が自分を
        名乗りこのアプリのものなら保存）、persistManifestUrl（保存）。update_manifest.dart の
        UpdateManifest.manifestUrl（`manifest_url`）。この文はそのコードと同じビルドでしか出荷しない:
        test/store/address_reader_disclosure_parity_test.dart。 -->
   <!-- services/update_check.dart: UpdateChecker.defaultManifestUrl（一覧の取得先）,
        UpdateChecker._run の _client.get（取得）, UpdateChecker._artifactReachable（配布先の存在確認）;
        main.dart: initState の addPostFrameCallback(_runUpdateCheck)（最初のフレーム後に実行）,
        _runUpdateCheck の _driveActive ガード（運転中は実行しない）。
        ⚑ 行番号ではなく記号で引用（2026-09-25）。この引用を書いている間に対象ファイルが
        2 度ずれ、行番号が別の文を指した — 動くファイルの行番号は引用ではない。
        ⚑「ダウンロードはしません」は 2026-09-25 まで条件付きで偽だった。HEAD を拒否する
        配布先への代替手段（1 バイトの Range 付き GET）が `_client.get` で本文を最後まで
        読んでいたため、Range を無視して 200 と全体を返すホストでは成果物（約 95 MB）を
        丸ごと取得していた。現在は _artifactReachable が状態行だけを読み、本文は読まずに
        閉じる。test/services/update_check_test.dart の「the existence check never downloads
        the artifact」が、そのホストから引き出された量を数えて固定している。 -->

**音声について（2026-09-25 追記）:** 音声警告は端末に同梱した音声を優先します。お使いの端末の音声読み上げエンジンがネットワーク音声を使う設定になっている場合、読み上げる文（路面の警告文など）が OS の音声提供元を経由することがあります。これはアプリ自身が行う通信ではありませんが、アプリ内の説明ではすでに明記しているため、このページにも書きます。
   <!-- アプリ内開示 AppL10n.egressDisclosure の【音声】と同じ内容（test/l10n/consent_localization_test.dart が『ネットワーク音声』を固定）。
        以前このページは、この経路を書かないまま「上記のほかに、端末の外に出るデータはありません」と言い切っていた。 -->

**位置の取得について（2026-09-25 追記）:** 本アプリは、Android の位置情報サービスから位置を受け取ります。Google Play 開発者サービスがある端末では、Google の位置情報サービス（Fused Location Provider）を使います。そのサービスが位置を求めるために何を使い、何を送るか（Wi-Fi や携帯電話網を使うかどうかなど）は、アプリではなく端末の位置情報の設定で決まります。これはアプリ自身が行う通信ではありません。
<!-- 出典: geolocator_android 4.6.2（pubspec.lock）の GeolocationManager.createLocationClient —
     forceLocationManager が false で Play 開発者サービスがあれば FusedLocationClient。lib/ に
     forceLocationManager の指定は無い。端末上での実測はしていない（コードの読み）。 -->

**IP アドレスについて（2026-09-25 追記）:** インターネットの通信である以上、上の 6 つのどの通信でも、あなたの端末の IP アドレスは通信先のサーバーに届きます。

上記のほかに端末の外に出るのは、下の不具合ログと運転日記を、あなたが自分で共有したときだけです。
<!-- 2026-09-25 訂正: 以前は「上記のほかに、端末の外に出るデータはありません。」と書き、運転日記に
     一度も触れていなかった。日記は、あなたが「日記を共有」を押したときに端末の共有機能で外に出る
     （lib/services/drive_diary.dart の shareDiaryViaShareSheet）。不具合ログはこの下で説明済みだった。
     見出しが数える件数は、アプリ自身が行う通信の数（egress_inventory_parity_test が固定）。 -->

## 不具合ログについて

アプリ内部のエラーは、端末内のログファイルにのみ記録されます（上限約200KB。超えた分は古いものから消えます）。エラーの文面は、起きたとおりに記録されます。位置を運ぶ通信（経路検索と米国の警報）は、自分のエラーをこのログに書かないことを確かめています。ただし、起こりうるすべてのエラーの文面までは確かめていません（たとえば地図タイルの読み込みエラーに、表示中の範囲を示すタイル座標が含まれるかどうか）。このログが端末の外に出るのは、**あなたが「ログを共有」を押して端末の共有機能で送ったときだけ**です。自動送信はありません。
<!-- lib/services/error_log.dart:9-15,32
     ⚑ 2026-09-25 追記の根拠: LocalErrorLog.record は error.toString() と stack をそのまま書く。
     経路検索（main.dart の _fetchRoute）は例外を RouteFailure にして画面に出し、ログには書かない。
     警報（_refreshAdvisories）は try/catch で受ける。意図してログに書く 2 か所
     （hardened_tts_engine.dart と hardened_haptic_channel.dart）は、文の長さとパターン名だけを書く。
     網羅していないのは、フレームワークが FlutterError.onError に報告するエラーの文面。 -->

## 運転日記について

運転日記に記録した内容（日時、あなたが選んだ答え、あなたが書いた地域やメモ。警告の確認を記録したときは、聞こえたか・感じたかの答えと、端末の申告、アプリのバージョン）は、端末内のファイルにだけ保存されます（上限約512KB。超えた分は古いものから消えます）。位置や経路は記録しません — 場所として残るのは、あなたが自分で書いた言葉だけです。日記が端末の外に出るのは、**あなたが「日記を共有」を押して端末の共有機能で送ったときだけ**です。送られるのは日記の本文と、アプリのバージョン・OS の種類・書き出した時刻です。自動送信はありません。
<!-- 2026-09-25 追加。出典（記号）: lib/services/drive_diary.dart の DriveDiary.record /
     recordChannelCheck（書く項目）、maxBytes = 512 * 1024（超えると半分まで古い順に削る）、
     composeDiarySharePayload（送る中身: 見出し 3 行 + 本文）、shareDiaryViaShareSheet（OS の共有シート）。 -->

## お問い合わせ

- メール: aki1770@gmail.com
- 開発リポジトリ: https://github.com/aki1770-del/sngnav-app

このポリシーに変更があった場合は、このページの日付を更新してお知らせします。

---

# Privacy Policy — sngnav-app (English)

Last updated: 2026-09-25

sngnav-app is an advisory app that supports driving on snowy roads. We deliberately keep your data on your device wherever possible. This page explains — matching the actual code — what the app uses, what it sends, and what it does not send.

## What we do NOT collect

- **No telemetry.** Usage data and interaction history are never sent automatically.
- **No accounts.** No registration, no login, no personal-information fields.
- **No advertising or analytics SDKs.**
- **No app-owned servers.** Your data is never sent to "our servers" — none exist.
- **No location collection you did not start.** The app does not request Android's ACCESS_BACKGROUND_LOCATION permission. Location is used in exactly two cases: (1) while the app is on screen, and (2) after **you yourself** start a drive with 現在地を共有 ("Share my location"), for as long as that drive lasts. In case (2) the feed continues with the screen off or while you use another app — so a warning still reaches you on a snow road you cannot watch a screen on. What happens if you remove the app from the recent-apps list has not been checked yet. When a drive starts, the app posts a notification saying a drive is running, and the app itself does not withdraw it until the drive ends. Opening the app (or tapping the notification) and pressing 停止 ("Stop") ends the drive and the location feed together. **The control the app gives you for ending the feed is 停止; to be sure it has ended, press 停止.** Dismissing the notification does not end it. The feed also ends if Android stops the app or stops supplying location. (Corrected 2026-09-25: this page said "停止 is the only thing that ends the feed" and that the feed continues "with the app closed". The first overstated it; the second was never checked for removing the app from the recent-apps list.) ⚑ **There are two cases in which you may not see that notification (corrected 2026-09-25).** (a) **While your screen is locked, the notification may not be shown on the lock screen.** (b) **On Android 14 and later you can swipe the notification away, and doing so does NOT stop the location feed.** Both were observed on an Android 14 test emulator — not a real phone — reproducing this app's notification settings: (a) it was not shown on the locked screen, and (b) after it was swiped away, the foreground service that carries the feed kept running. On an Android 11 test emulator the same swipe did not remove the notification. We have not yet confirmed any of this on a real phone. This page previously said "there is no location collection without that notification" and "you cannot dismiss it"; in these two cases neither was true.

## Permissions the app requests (Android)

| Permission | Purpose |
|---|---|
| INTERNET | Fetching weather data, routes and map tiles, and checking whether a newer build exists (only the six flows listed below) |
| ACCESS_FINE_LOCATION | Showing your position on the map, and road warnings while driving. **Only after you consent** — while the app is on screen, or during **a drive you started** (a notification is posted for the drive, but there are cases where you may not see it — see the first section above) |
| ACCESS_COARSE_LOCATION | Same flow (a coarse position when a precise one is unavailable) |
| WAKE_LOCK | Keeping the screen on while the driving surface is shown; and, during a drive you started, keeping the device from sleeping so that **warnings still arrive with the screen off** |
| VIBRATE | The **haptic** hazard cue — so a warning can be noticed without looking. This is the channel for a driver who cannot hear well, or cannot look at the screen in a whiteout |
| FOREGROUND_SERVICE | Keeping the position feed alive during a drive you started. A notification is posted when it starts; on Android 14 and later you can swipe that notification away and the feed continues (停止 in the app ends it), and it may not be shown on a locked screen |
| FOREGROUND_SERVICE_LOCATION | Declaring to the OS that this service handles location. From Android 14 the OS refuses the drive-time feed without it |
| POST_NOTIFICATIONS | Showing **that notification itself**. From Android 13 nothing is shown without it. **If you decline, the app does not start the foreground service at all** — it never starts drive-time collection when it cannot post that notification, so the drive is then screen-on only |

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
the screen off during a drive you started, and ACCESS_BACKGROUND_LOCATION is still not requested.*

*Correction note (2026-09-25): the 2026-09-24 note above also said "what has NOT changed is that there
is no location collection without a visible notification". That was not true, so it has been taken out
of that note and is kept here. The drive notification may not be shown on a locked screen, and on
Android 14 and later it can be swiped away while the location feed continues (see the first section
above). Both were observed on an Android 14 test emulator, not yet on a real phone.*

## Data that leaves your device (these six flows are all of it)

1. **JMA AMeDAS observation fetch** — the app requests observations for five fixed weather stations in Akita Prefecture (Oga, Akita, Omagari, Yokote, Yuzawa) from the Japan Meteorological Agency servers (www.jma.go.jp): all five when the app starts, then the Akita station about every 10 minutes, and all five again when you press re-fetch on the station list. This happens whether or not you share your location, and **your coordinates are not sent.** Requests carry a User-Agent naming this app (sngnav-app) and giving the project's public repository URL (https://github.com/aki1770-del/sngnav) as a contact, so the publisher can do rate-limit accounting and reach a security contact — it does not identify you.
   <!-- flow: jma-amedas -->

2. **JMA forecast fetch** — the app requests the forecast for Akita Prefecture (forecast area 050000; fixed, it does not change with your position) from www.jma.go.jp. When an observation fetch succeeds and the forecast it holds is more than 3 hours old, it fetches it again (if that fails, it retries at the next successful observation fetch). This happens whether or not you share your location, and **your coordinates are not sent.** The User-Agent is the same as in 1.
   <!-- flow: jma-forecast -->

3. **Advisory fetch** — **while you are sharing your location**, the app asks for warnings and advisories about once per kilometre of travel (and about every 10 minutes when stopped, or when driving with the screen off), **only from the public weather agency with jurisdiction over your area**. **In Japan your coordinates never leave the device**: the app works out your prefecture on the device and sends the JMA only prefecture codes (equivalent to a coarse, prefecture-level location; near a prefectural border it sends the code of each prefecture you may be in, which shows you are near that border). **In the United States your coordinates are sent to the NWS** to fetch alerts for your exact point. A request that uses your position is never sent to an agency that does not cover it. **When you are not sharing your location, or your position is not yet known, the app fetches the Akita Prefecture warnings about every 10 minutes** (your position is not used). Coordinates are held in memory only and are never persisted on the device. (Corrected 2026-09-25: this page previously said your coordinates were sent to the JMA in Japan too. That was not true. It also said this fetch happened "only after consent"; the Akita Prefecture warnings were fetched before any consent. And it said "an agency that does not cover your location is never contacted"; the app asks the JMA for Akita data from the moment it starts, wherever you are, so as an absolute that was not true. The sentence now covers only the requests that use your position.)
   <!-- flow: warnings -->

4. **Route lookup** — the origin and destination coordinates **you tap on the map** are sent to the public OSRM demo router (router.project-osrm.org) to compute a route. Your GPS position is never fed to the router automatically. The OSRM demo server is a third-party public service.
   <!-- flow: route -->

5. **Map-tile fallback** — when you view an area the bundled offline basemap does not cover, the tile coordinates for that area (roughly equivalent to a coarse viewport location) are sent to the OpenStreetMap tile server (tile.openstreetmap.org). Areas within the bundled coverage render offline with no network traffic.
   <!-- flow: tiles -->

6. **Update check** — just after the first screen appears, the app fetches a published version list (JSON), either from GitHub's raw content server (raw.githubusercontent.com), which is built into the app, or from a new home an earlier list named. **No coordinates and no device identifier are sent** — the request has no body. This app is distributed outside any store and has no auto-update, so without this check there is nothing to tell you a fix exists. **The check happens once, just after the app starts, and is not repeated.** **The list's own address can change.** When a list names a different https address as its new home, the app sends one request to that address, whether or not a newer build is listed (it does not follow redirects). Only if the list found there names that same address as its own and is for this app does the app store the address on the device and use it from the next launch. What is stored is where the list lives, not information about you. This address, too, comes from the list and is not fixed inside the app. Only when the list names a build newer than yours, the app sends an existence check — never a download — to **the download URL that list specifies**, so it never announces a build you cannot actually get. **That host comes from the list and is not fixed inside the app** (today it is GitHub). The app installs nothing (REQUEST_INSTALL_PACKAGES is not requested). (Corrected 2026-09-25: this page said "if a drive is in progress it is skipped entirely". The check runs just after start, before a drive can have begun, so that sentence guarded nothing, and starting a drive while the check is still running does not stop it.)
   <!-- flow: update-check -->
   <!-- describes: manifest-address-reader -->

**About voice (added 2026-09-25):** Spoken alerts prefer the audio bundled on the device. If your device's text-to-speech engine is set to use a network voice, the text being spoken (such as a road warning) may pass through the OS voice vendor. This is not a connection the app makes itself, but the in-app disclosure already says so, and this page now says it too.

**About location (added 2026-09-25):** The app receives your position from Android's location service. On a device with Google Play services, that is Google's fused location provider. What that service uses and sends to work out a position (for example whether it uses Wi-Fi or mobile networks) is set by your device's location settings, not by this app. It is not a connection the app makes itself.

**About your IP address (added 2026-09-25):** Like any internet request, each of the six flows above shows your device's IP address to the server that receives it.

Besides the above, data leaves the device only when you share the error log or the drive diary yourself (below).

## Crash / error log

Internal errors are recorded only in a local log file on your device (capped at roughly 200 KB; oldest entries are dropped first). The text of each error is recorded as it occurred. The requests that carry your position (route lookup, and US alerts) have been checked not to write their errors to this log, but not every possible error message has been checked (for example, whether a map-tile loading error could include the tile coordinates of the area on screen). The log leaves your device **only when you press "ログを共有" (Share log) and send it through your device's share sheet**. There is no automatic upload.

## Drive diary

What you record in the drive diary (the time, the answers you choose, the area and note you type, and, for a warning check, whether you heard and felt it, what the device reported and the app version) is saved only in a file on your device (capped at roughly 512 KB; the oldest entries are dropped first). No position or route is recorded; the only place in it is what you type yourself. The diary leaves your device **only when you press 日記を共有 (Share diary) and send it through your device's share sheet**. What is sent is the diary text, with the app version, the kind of operating system and the time it was exported. There is no automatic upload.

## Contact

- Email: aki1770@gmail.com
- Repository: https://github.com/aki1770-del/sngnav-app

If this policy changes, we will update the date on this page.
