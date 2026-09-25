-- 推し活手帳: クラウド同期用テーブル
-- 推し・LIVE・チェキ・物販・アプリ設定を、1件ずつ JSON (data) として保存する。
-- 行はログインユーザーごとに分離され、RLS により本人の行しか読み書きできない。

create table if not exists public.oshikatsu_records (
  user_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  kind       text        not null check (kind in ('oshi', 'live', 'cheki', 'goods', 'settings')),
  id         text        not null check (char_length(id) between 1 and 100),
  data       jsonb       not null default '{}'::jsonb,
  deleted    boolean     not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, kind, id)
);

-- 差分取得（updated_at 以降の行だけを読む）用
create index if not exists oshikatsu_records_user_updated_idx
  on public.oshikatsu_records (user_id, updated_at);

-- updated_at はクライアントの時計ではなくサーバー側で必ず更新する
create or replace function public.oshikatsu_records_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

drop trigger if exists oshikatsu_records_touch on public.oshikatsu_records;
create trigger oshikatsu_records_touch
  before insert or update on public.oshikatsu_records
  for each row execute function public.oshikatsu_records_touch();

-- Row Level Security: 本人の行のみ
alter table public.oshikatsu_records enable row level security;

drop policy if exists "oshikatsu_records_select_own" on public.oshikatsu_records;
create policy "oshikatsu_records_select_own" on public.oshikatsu_records
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "oshikatsu_records_insert_own" on public.oshikatsu_records;
create policy "oshikatsu_records_insert_own" on public.oshikatsu_records
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "oshikatsu_records_update_own" on public.oshikatsu_records;
create policy "oshikatsu_records_update_own" on public.oshikatsu_records
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "oshikatsu_records_delete_own" on public.oshikatsu_records;
create policy "oshikatsu_records_delete_own" on public.oshikatsu_records
  for delete to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.oshikatsu_records from anon;
grant select, insert, update, delete on public.oshikatsu_records to authenticated;
