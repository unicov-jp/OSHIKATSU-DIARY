# 推し活手帳（OSHIKATSU DIARY）

推し活（アイドル・アーティストのファン活動）を記録するための個人用Webアプリです。
LIVE参戦・チェキ・物販の記録、複数推し・複数グループ（兼任）の管理、統計表示などができます。

## 実行方法

ビルド不要の単一HTMLファイルです。

```bash
open index.html   # または任意のブラウザで直接開く
```

ローカルサーバーも不要ですが、使う場合は例えば：

```bash
npx serve .
# または
python3 -m http.server 8000
```

## クラウド同期（Supabase）とログイン

**ログイン必須**です。未ログイン時はログイン画面だけを表示し、タブ・＋ボタン・ヘッダーの操作は隠します（`render()` の先頭で `renderAuthGate()` に切り替え、`#app.auth-gate` のCSSで非表示）。ログインすると記録が Supabase に保存され、複数の端末で同期されます。接続情報を取得できない場合（`index.html` をファイルとして直接開いた場合を含む）は、接続できない旨と再読み込みボタンを表示します。

- **ログイン方法**：メールアドレス＋パスワード（新規登録・パスワード再設定あり）、Googleアカウント
- **接続情報**：`api/config.js`（Vercel Serverless Function）が、Vercel の環境変数 `NEXT_PUBLIC_SUPABASE_URL` と `NEXT_PUBLIC_SUPABASE_ANON_KEY`（または `..._PUBLISHABLE_KEY`）を `/api/config` で返します。service_role / secret キーは返さないようにしています。
- **ライブラリ**：`vendor/supabase-js-2.117.2.js`（@supabase/supabase-js の UMD 版を同梱。CDN には依存しません）
- **テーブル**：`supabase/migrations/20260925000000_create_oshikatsu_records.sql`
  - `oshikatsu_records(user_id, kind, id, data jsonb, deleted, created_at, updated_at)`
  - `kind` は `oshi` / `live` / `cheki` / `goods` / `settings`。1件の推し・記録・設定が1行です。
  - RLS により、本人の行しか読み書きできません。削除は `deleted=true` の論理削除で、ほかの端末にも反映されます。

### 同期の仕組み

- 端末側は、ユーザーごとのキャッシュ（`oshikatsu_diary_v1:u:<userId>`）と同期メタ情報（`oshikatsu_sync_v1:<userId>`）を `localStorage` に持ちます。
- `saveLocal()` が呼ばれると、「最後にクラウドと一致していた内容のハッシュ」と比べて、変更・追加・削除された行だけを送信します（0.8秒のデバウンス）。
- 受信は `updated_at` による差分取得です。画面に戻ったとき、オンラインに復帰したとき、1分ごとに自動で行います（同期状態は画面に表示しません）。
- 同じ行を複数の端末で編集した場合は、後から保存した方が残ります。
- ログイン必須化より前にその端末で付けていた記録（`oshikatsu_diary_v1`）は、ログイン時に確認のうえアカウントへ取り込めます。
- ログアウトすると、その端末のユーザー別キャッシュは削除されます。

### マイページの「アカウント」

「登録した推し」とプライバシーポリシーのリンクの間に表示します。

- メールアドレス：ログイン中のアカウント
- パスワード：設定済み／未設定と「変更」「設定」ボタン。Googleだけで登録した人も、ここでパスワードを設定するとメールアドレスでログインできます（`sb.auth.updateUser`）。
  - Google で登録した人がパスワードを追加しても Supabase のユーザー情報には現れないため、設定・変更時に `user_metadata.has_password = true` を保存して「設定済み」の判定に使います。すでに同じパスワードがある（Supabase が「前と同じ」と返す）場合も目印だけ付けます。
- Google認証：連携済み／未連携と「連携する」「解除」ボタン（`sb.auth.linkIdentity` / `unlinkIdentity`）。ログイン方法が1つしかない場合は解除できません。
  - 「連携する」を使うには、Supabase の Authentication → Sign In / Providers で **Allow manual linking** を有効にする必要があります。
- ログアウト

### Supabase / Google 側の設定

1. SQL Editor で上記マイグレーションの SQL を実行する（または Supabase の GitHub 連携で適用する）。
2. Authentication → URL Configuration
   - Site URL：`https://oshikatsu-diary.vercel.app`
   - Redirect URLs：`https://oshikatsu-diary.vercel.app/**`（プレビュー環境も使う場合は `https://*-minatani-01s-projects.vercel.app/**` も追加）
3. Authentication → Sign In / Providers → Google を有効にし、Google Cloud Console で発行した OAuth クライアントID・シークレットを登録する。
   - Google 側の「承認済みのリダイレクト URI」には、Supabase の Google 設定画面に表示される Callback URL（`https://<project-ref>.supabase.co/auth/v1/callback`）を登録します。

## 技術構成

- **1ファイル完結**：`index.html` の中にCSS（`<style>`）とJS（`<script>`）がすべて内包されています。ビルドツールは使用していません（vanilla JS / vanilla CSS）。外部ライブラリは同梱の supabase-js のみです。
- **データ保存**：Supabase が正本で、ブラウザの `localStorage` にユーザー別のキャッシュを持ちます（上記参照）。
  - キー: `oshikatsu_diary_v1:u:<userId>`（ログイン中のキャッシュ）、`oshikatsu_diary_v1`（ログイン必須化以前のデータ。初回ログイン時に取り込み可）
  - 中身: `{ oshis, live, cheki, goods, activeOshiId, headerLogo }`
- **画像**：アップロードされた写真はすべて `dataURL`（base64）としてlocalStorageに直接保存されます。ファイルアップロードは `resizeImageFile`（JPEG化・不透明画像用）と `resizeImageFilePreserveAlpha`（PNG化・透過を保持したい画像用、ヘッダーロゴなど）の2種類のリサイズ関数を使い分けています。

## データモデル（概要）

### 推し（oshi）
```
{
  id, name, agency, photo, color, birthYear, birthMonth, birthDay,
  groups: [
    { id, name, color, sns_web, sns_instagram, sns_x, sns_tiktok, sns_youtube }
  ],
  sns_person_instagram, sns_person_x, sns_person_tiktok, sns_person_youtube, sns_person_web,
  photoOriginal, mode: "pale", order, hidden, createdAt
}
```
- プロフィール写真は `AvatarCropper` で丸枠に合わせて切り抜いた 480x480 のJPEGを `photo` に、切り抜く前の画像（長辺1000pxに縮小）を `photoOriginal` に保存する。写真メニューの「位置を調整」で、`photoOriginal` から何度でも調整し直せる（以前に登録した写真は `photo` から調整）。
- `hidden: true` の推しは非表示。推しの切り替え・記録一覧の絞り込み・記録フォームの推し選択に出さない（`visibleOshis()`）。記録や集計には残り、マイページの「非表示の推し」から戻せる。お気に入りの推しを非表示にすると、表示中のほかの推しがお気に入りになる。
- `groups` は配列の**並び順がそのまま「メイン所属／サブ所属」を表す**（先頭＝メイン）。専用のフラグは持たない。
- 推しの登録・編集で、所属（`#agencyOptions`）とグループ名（`#groupNameOptions`）の入力欄には、登録済みの値を `datalist` で候補表示する。グループ名を候補から選んだときも、下のSNS自動入力がその場で働く。
- 推しの登録・編集でグループ名を入力し終えたとき、ほかの推しに**完全一致**する名前のグループがあれば、そのSNS（公式HP含む）を空欄にだけ自動で入れる（同じグループの別メンバーを登録するとき用。入力済みのSNSは上書きしない）。
- 個人の `sns_person_web` とグループの `sns_web` は公式HPのURL（IDではなくURLを保存）。`safeWebUrl()` で http(s) のみに正規化し、スキーム省略時は `https://` を補う。そのほかの `sns_*` はIDを保存する。
- 推し全体のテーマカラー（`oshi.color`）は、保存時に「メイングループの色」から自動的に決定される（`effectiveColor()` 参照）。グループが1つもない推しは自動割り当てのプリセット色になる。
- 過去バージョンの単一グループ形式（`oshi.group` 文字列 + `sns_group_*`）のデータも `oshiGroupsList()` が後方互換で読み込む。

### 記録（live / cheki / goods）
各配列は `state.live` / `state.cheki` / `state.goods` に格納。共通フィールド：
`{ id, oshiId, groupId, date, memo, tag, favorite, hidden, ... }`
（`groupId` はその記録がどのグループ活動かを表す任意フィールド。フォームでは推しを選ぶとメイングループがデフォルト選択される）

- live固有: `title, venue, streamUrl, ticketType, seat, price, photo, extraOshis, openTime, startTime, endTime`
  - `openTime` / `startTime` / `endTime`：開場・開始・終了の時刻（`HH:MM`、任意）。
  - 一覧のLIVEは、推しの行にグループ名だけを出し（同じグループは1回、グループのない推しは人物名）、次の行は会場と「カレンダーに追加」ボタン。チケット種別・座席は一覧に出さない。
  - 「カレンダーに追加」は `googleCalendarUrl()` で Google カレンダーの予定作成URL（APIキー不要）を開く。開始＝開始時刻→開場時刻、終了＝終了時刻→開始の2時間後、時刻が無ければ終日。メモに開場・開始・終了と出演グループ、場所に会場（住所）を入れる。
  - `viewing`：観戦方法。`"venue"`（現地）/ `"stream"`（配信）。フォームは日付の下のボタンで選び、一覧のチケットには「LIVE」の横に現地（塗り）／配信（枠線）の印を出す。未設定の以前の記録は、配信URLがあって会場が空なら配信、それ以外は現地とみなす（`recViewing()`）。ホームの「参戦」「参戦回数」や集計の「参戦」は現地観戦だけを数える（配信で観たLIVEは数えない）。
  - `ticketUrl`：オンラインチケットのURL（`safeWebUrl()` で http(s) のみ）。フォームでは「チケット代」の上に入力欄があり、一覧に「チケットを見る」リンクを出す。
  - `streamUrls`：配信URLの配列（http(s) のみ）。互換のため1件目は `streamUrl` にも入れる。以前の記録は `streamUrl` だけでも表示できる（`recStreamUrls()`）。一覧のリンク表記は件数に関係なく「配信を見る」。複数あるときは押すとメニュー（`#streamMenu`）が開き、「配信1（ドメイン）」「配信2（ドメイン）」…から選ぶ。
  - `venuePlace`：会場を Google マップの候補から選んだときの場所 `{ placeId, name, address, lat, lng }`。手入力のままなら `null`（遠征マップ用）。
  - `extraOshis`：対バンなどで一緒に記録する2人目以降の推し `[{ oshiId, groupId }]`。1人目は従来どおり `oshiId` / `groupId`。
  - 推し別の集計（参戦回数・金額）では、`recHasOshi()` で `oshiId` と `extraOshis` の両方を対象にし、金額は `recAmountForOshi()` で人数に均等に割ります（合計の二重計上を防ぐため）。
  - フォームでは推しとグループを横並びで選び、LIVEのみ「＋ 推しを追加」で行を増やせます。LIVEの行は「人物名・グループ名・チェキボタン・✕ボタン」の4列（1行目は✕の位置を空けて列をそろえる）。
  - チェキボタンを押すと、その行の推し・グループと、LIVEの日付・公演・ツアー名で、チェキの記録（1枚・金額0）をすぐに追加します。
- cheki固有: `title, count, price, content, photo`
- goods固有: `title, item, price, qty, photo, shopUrl`（`shopUrl` はONLINE物販のURL。`safeWebUrl()` で http(s) のみ保存し、一覧に「購入ページを見る」リンクを表示）（写真はLIVEと同じくチケット右側の背景に表示）

## 実装上の注意点（引き継ぎ時に踏みやすい罠）

1. **CSS詳細度の罠**：`.field input[type=text], .field select, ...` という汎用ルール（`width:100%` 等を強制）が、コンポーネント個別のスタイル（例：グループカード内の小さな名前入力欄）より詳細度で勝ってしまうことが何度か発生しました。フォーム内に新しい `input`/`select` を独自スタイルで追加する場合は、汎用ルールの詳細度（`.field input[type=xxx]` は2クラス+属性セレクタ）を上回るように `!important` を使うか、汎用ルールに含まれない要素構造にすることを推奨します。
2. **ポップオーバーの位置**：SNSアイコン編集・カラーピッカー・トップバーのドロップダウンなど、すべて `position:fixed` ＋ `openPopoverNear(anchorEl, popEl)` で位置計算しています。横スクロールするコンテナの中に絶対配置のポップオーバーを置くと親のスクロールで表示がズレる問題が過去にあったため、この方式に統一しています。
3. **画像形式**：ロゴなど透過を保持したい画像は必ず `resizeImageFilePreserveAlpha`（PNG出力）を使うこと。既存の `resizeImageFile` はJPEG出力のため透過が失われます。
4. **`/mnt/user-data/outputs/` との同期ズレ**：作業用ファイルと公開用ファイルを手動 `cp` で同期する運用だったため、一度だけ同期漏れによる巻き戻りバグが発生したことがあります。Claude Codeでの開発では、Gitなど単一の真実源で管理することを推奨します。
5. **推しリスト・グループリストの並び順**：`state.oshis` 配列そのものの並びが表示順＝優先順位（先頭が「メイン」）です。別途ソート用フィールドはありません。ドラッグ＆ドロップ・矢印ボタンでの並べ替えはどちらも配列を直接 `splice` して並べ替えています。

## 主な機能一覧

- 複数推し・推しごとの複数グループ（兼任）管理、グループごとのSNS・担当カラー
- LIVE／チェキ／物販の記録（写真、配信URL、チケット情報など）
- 統計（推し別／イベント別／期間別／カレンダー）
- 個人・グループごとの公式HPのURL登録（SNSアイコンの末尾）
- ヘッダーへの推しグループロゴのアップロード（透過PNG対応）
- お気に入り推しの切り替え（トップバーのドロップダウン）
- メールアドレス / Googleアカウントでのログイン（ログイン必須）と、複数端末でのクラウド同期（マイページ →「アカウント」で、メールアドレスの確認、パスワードの設定・変更、Google認証の連携・解除、ログアウト）

## 会場と Google マップ（遠征マップの準備）

LIVE の「会場」欄で2文字以上入力すると、Google Places API (New) の候補（`AutocompleteSuggestion.fetchAutocompleteSuggestions`）を表示します。候補を選ぶと `place.fetchFields()` で正式名称・住所・緯度経度・Place ID を取得し、`venuePlace` に保存します。会場名を手で書き換えると `venuePlace` は外れます。

- 会場名は、記録一覧で Google マップへのリンクになります（APIキー不要の検索URL）。
- APIキーは Vercel の環境変数 `GOOGLE_MAPS_API_KEY` に設定し、`/api/config` の `googleMapsApiKey` でブラウザに渡します。キーが無いときは手入力のみで動きます。
- Google Cloud で有効にする API：**Maps JavaScript API**、**Places API (New)**。キーは「HTTPリファラー」を `https://oshikatsu-diary.vercel.app/*` に制限し、API の制限もこの2つにしてください。
- 今後「遠征マップ」を作るときは、`state.live` の `venuePlace.lat / lng` を使います。

## アプリとしてインストール（PWA）

- `manifest.webmanifest`：アプリ名・アイコン・`display: standalone` など。`icons/` にアイコン（192/512、maskable 512、apple-touch-icon 180、favicon 32）。
- `sw.js`：Service Worker。画面（HTML）はネットワーク優先で、つながらないときだけ保存済みを表示。静的ファイルはキャッシュ優先で裏で更新。`/api/` と外部サービス（Supabase・Google など）はキャッシュしない。内容を大きく変えたときは `CACHE` の名前（`oshikatsu-v1`）を上げると古いキャッシュが消える。
- `index.html` で https（と開発用の localhost）のときだけ Service Worker を登録する。ブラウザのステータスバー色（`theme-color`）はテーマに合わせて変わる。
- Android の Chrome：メニュー →「ホーム画面に追加」→「インストール」。iPhone の Safari：共有 →「ホーム画面に追加」。

## プライバシーポリシー

`privacy.html`（公開URL：`https://oshikatsu-diary.vercel.app/privacy.html`）。ログイン画面とマイページの最下部からリンクしています。Google OAuth 同意画面の「プライバシーポリシーのリンク」にもこのURLを設定します。取得する情報や外部サービスを追加・変更したときは、このページも更新してください。

## Claude Codeでの作業にあたって

- `index.html` 内はセクションコメント（`/* ============ ... ============ */`）で大まかに区切られています（データ層／描画関数／フォーム／イベント配線など）。
- 新機能を追加する際は、まず該当セクションを `grep` などで探してから編集することを推奨します（ファイルが大きいため）。
