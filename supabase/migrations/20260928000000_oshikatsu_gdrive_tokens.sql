-- 推し活手帳: Google ドライブへの接続を続けるためのリフレッシュトークン
-- 一度 Google ドライブに接続すると、サーバー（/api/gdrive-token）がここに本人のリフレッシュトークンを保存し、
-- PC・スマホなど同じアカウントでログインしたどの端末からでも、つなぎ直さずに写真とバックアップを使えるようにする。
-- リフレッシュトークンは OAuth クライアントシークレット（サーバーだけが持つ）が無いと使えない。
-- 読み書きは本人の行だけ（行レベルセキュリティ）。

create table if not exists public.oshikatsu_gdrive_tokens (
  user_id       uuid        primary key references auth.users (id) on delete cascade,
  refresh_token text        not null,
  updated_at    timestamptz not null default now()
);

alter table public.oshikatsu_gdrive_tokens enable row level security;

drop policy if exists "oshikatsu_gdrive_tokens_select_own" on public.oshikatsu_gdrive_tokens;
create policy "oshikatsu_gdrive_tokens_select_own" on public.oshikatsu_gdrive_tokens
  for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "oshikatsu_gdrive_tokens_insert_own" on public.oshikatsu_gdrive_tokens;
create policy "oshikatsu_gdrive_tokens_insert_own" on public.oshikatsu_gdrive_tokens
  for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists "oshikatsu_gdrive_tokens_update_own" on public.oshikatsu_gdrive_tokens;
create policy "oshikatsu_gdrive_tokens_update_own" on public.oshikatsu_gdrive_tokens
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists "oshikatsu_gdrive_tokens_delete_own" on public.oshikatsu_gdrive_tokens;
create policy "oshikatsu_gdrive_tokens_delete_own" on public.oshikatsu_gdrive_tokens
  for delete to authenticated using ((select auth.uid()) = user_id);

revoke all on public.oshikatsu_gdrive_tokens from anon;
grant select, insert, update, delete on public.oshikatsu_gdrive_tokens to authenticated;
