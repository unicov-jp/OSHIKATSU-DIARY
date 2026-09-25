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
- 受信は `updated_at` による差分取得です。画面に戻ったとき、オンラインに復帰したとき、1分ごと、「今すぐ同期」を押したときに行います。
- 同じ行を複数の端末で編集した場合は、後から保存した方が残ります。
- ログイン必須化より前にその端末で付けていた記録（`oshikatsu_diary_v1`）は、ログイン時に確認のうえアカウントへ取り込めます。
- ログアウトすると、その端末のユーザー別キャッシュは削除されます。

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
  sns_person_instagram, sns_person_x, sns_person_tiktok, sns_person_youtube,
  mode: "pale", order, createdAt
}
```
- `groups` は配列の**並び順がそのまま「メイン所属／サブ所属」を表す**（先頭＝メイン）。専用のフラグは持たない。
- グループの `sns_web` は公式HPのURL（IDではなくURLを保存）。`safeWebUrl()` で http(s) のみに正規化し、スキーム省略時は `https://` を補う。そのほかの `sns_*` はIDを保存する。
- 推し全体のテーマカラー（`oshi.color`）は、保存時に「メイングループの色」から自動的に決定される（`effectiveColor()` 参照）。グループが1つもない推しは自動割り当てのプリセット色になる。
- 過去バージョンの単一グループ形式（`oshi.group` 文字列 + `sns_group_*`）のデータも `oshiGroupsList()` が後方互換で読み込む。

### 記録（live / cheki / goods）
各配列は `state.live` / `state.cheki` / `state.goods` に格納。共通フィールド：
`{ id, oshiId, groupId, date, memo, tag, favorite, hidden, ... }`
（`groupId` はその記録がどのグループ活動かを表す任意フィールド。フォームでは推しを選ぶとメイングループがデフォルト選択される）

- live固有: `title, venue, streamUrl, ticketType, seat, price, photo`
- cheki固有: `title, count, price, content, photo`
- goods固有: `title, item, price, qty`

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
- グループごとの公式HPのURL登録（グループSNSの先頭）
- ヘッダーへの推しグループロゴのアップロード（透過PNG対応）
- お気に入り推しの切り替え（トップバーのドロップダウン）
- メールアドレス / Googleアカウントでのログイン（ログイン必須）と、複数端末でのクラウド同期（マイページ →「アカウント・同期」）

## プライバシーポリシー

`privacy.html`（公開URL：`https://oshikatsu-diary.vercel.app/privacy.html`）。ログイン画面とマイページの最下部からリンクしています。Google OAuth 同意画面の「プライバシーポリシーのリンク」にもこのURLを設定します。取得する情報や外部サービスを追加・変更したときは、このページも更新してください。

## Claude Codeでの作業にあたって

- `index.html` 内はセクションコメント（`/* ============ ... ============ */`）で大まかに区切られています（データ層／描画関数／フォーム／イベント配線など）。
- 新機能を追加する際は、まず該当セクションを `grep` などで探してから編集することを推奨します（ファイルが大きいため）。
