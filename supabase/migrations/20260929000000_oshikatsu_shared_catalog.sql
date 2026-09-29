-- 推し活手帳: アーティスト・曲を全ユーザーで共有する辞書にする
--
-- oshikatsu_artists         … アーティスト（名前は大文字小文字・前後の空白を区別せず1つだけ）と背景画像
-- oshikatsu_songs           … 曲（曲名＋アーティスト名の組み合わせで1つだけ）
-- oshikatsu_catalog_renames … マスターが名前を変えた記録。各ユーザーのアプリが、自分のLIVE記録のセトリに同じ変更を当てる
-- Storage の oshikatsu-artists … アーティストの背景画像（だれでも見られる公開の置き場）
--
-- ・ログインしている人はだれでも読める。
-- ・アーティスト・曲の追加はだれでもできる（背景画像は付けられない）。
-- ・名前の変更・削除、背景画像の設定・変更・削除はマスターだけ（oshikatsu_is_master() を使う。
--   20260928020000_oshikatsu_plans.sql を先に実行しておくこと）。
-- ・これまで各ユーザーの記録（oshikatsu_records の kind = 'artist' / 'song'）にあった登録は、
--   アプリを開いたときにアプリがこちらへ移す（画像はマスターの端末から移す）。

create table if not exists public.oshikatsu_artists (
  id         uuid        primary key default gen_random_uuid(),
  name       text        not null check (length(btrim(name)) between 1 and 100),
  name_key   text        generated always as (lower(btrim(name))) stored,
  image_path text,
  image_pos  text        check (image_pos is null or image_pos ~ '^[0-9]{1,3}(\.[0-9]+)?% [0-9]{1,3}(\.[0-9]+)?%$'),
  created_by uuid        default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists oshikatsu_artists_name_key on public.oshikatsu_artists (name_key);

create table if not exists public.oshikatsu_songs (
  id         uuid        primary key default gen_random_uuid(),
  title      text        not null check (length(btrim(title)) between 1 and 200),
  artist     text        not null default '' check (length(artist) <= 100),
  title_key  text        generated always as (lower(btrim(title))) stored,
  artist_key text        generated always as (lower(btrim(artist))) stored,
  created_by uuid        default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists oshikatsu_songs_key on public.oshikatsu_songs (title_key, artist_key);

create table if not exists public.oshikatsu_catalog_renames (
  id          bigint      generated always as identity primary key,
  kind        text        not null check (kind in ('artist', 'song')),
  from_title  text        not null default '',
  from_artist text        not null default '',
  to_title    text        not null default '',
  to_artist   text        not null default '',
  created_by  uuid        default auth.uid() references auth.users (id) on delete set null,
  created_at  timestamptz not null default now()
);

-- 行レベルセキュリティ
alter table public.oshikatsu_artists enable row level security;
alter table public.oshikatsu_songs enable row level security;
alter table public.oshikatsu_catalog_renames enable row level security;

drop policy if exists "oshikatsu_artists_select" on public.oshikatsu_artists;
create policy "oshikatsu_artists_select" on public.oshikatsu_artists
  for select to authenticated using (true);
drop policy if exists "oshikatsu_artists_insert" on public.oshikatsu_artists;
create policy "oshikatsu_artists_insert" on public.oshikatsu_artists
  for insert to authenticated
  with check (created_by = (select auth.uid()) and (image_path is null or (select public.oshikatsu_is_master())));
drop policy if exists "oshikatsu_artists_update_master" on public.oshikatsu_artists;
create policy "oshikatsu_artists_update_master" on public.oshikatsu_artists
  for update to authenticated
  using ((select public.oshikatsu_is_master()))
  with check ((select public.oshikatsu_is_master()));
drop policy if exists "oshikatsu_artists_delete_master" on public.oshikatsu_artists;
create policy "oshikatsu_artists_delete_master" on public.oshikatsu_artists
  for delete to authenticated using ((select public.oshikatsu_is_master()));

drop policy if exists "oshikatsu_songs_select" on public.oshikatsu_songs;
create policy "oshikatsu_songs_select" on public.oshikatsu_songs
  for select to authenticated using (true);
drop policy if exists "oshikatsu_songs_insert" on public.oshikatsu_songs;
create policy "oshikatsu_songs_insert" on public.oshikatsu_songs
  for insert to authenticated with check (created_by = (select auth.uid()));
drop policy if exists "oshikatsu_songs_update_master" on public.oshikatsu_songs;
create policy "oshikatsu_songs_update_master" on public.oshikatsu_songs
  for update to authenticated
  using ((select public.oshikatsu_is_master()))
  with check ((select public.oshikatsu_is_master()));
drop policy if exists "oshikatsu_songs_delete_master" on public.oshikatsu_songs;
create policy "oshikatsu_songs_delete_master" on public.oshikatsu_songs
  for delete to authenticated using ((select public.oshikatsu_is_master()));

drop policy if exists "oshikatsu_catalog_renames_select" on public.oshikatsu_catalog_renames;
create policy "oshikatsu_catalog_renames_select" on public.oshikatsu_catalog_renames
  for select to authenticated using (true);
drop policy if exists "oshikatsu_catalog_renames_insert_master" on public.oshikatsu_catalog_renames;
create policy "oshikatsu_catalog_renames_insert_master" on public.oshikatsu_catalog_renames
  for insert to authenticated with check ((select public.oshikatsu_is_master()));

revoke all on public.oshikatsu_artists from anon;
revoke all on public.oshikatsu_songs from anon;
revoke all on public.oshikatsu_catalog_renames from anon;
grant select, insert, update, delete on public.oshikatsu_artists to authenticated;
grant select, insert, update, delete on public.oshikatsu_songs to authenticated;
grant select, insert on public.oshikatsu_catalog_renames to authenticated;

-- 背景画像の置き場（公開。1枚2MBまで。書き込み・削除はマスターだけ）
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('oshikatsu-artists', 'oshikatsu-artists', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = 2097152, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

drop policy if exists "oshikatsu_artists_images_select" on storage.objects;
create policy "oshikatsu_artists_images_select" on storage.objects
  for select to authenticated using (bucket_id = 'oshikatsu-artists');
drop policy if exists "oshikatsu_artists_images_insert_master" on storage.objects;
create policy "oshikatsu_artists_images_insert_master" on storage.objects
  for insert to authenticated with check (bucket_id = 'oshikatsu-artists' and (select public.oshikatsu_is_master()));
drop policy if exists "oshikatsu_artists_images_update_master" on storage.objects;
create policy "oshikatsu_artists_images_update_master" on storage.objects
  for update to authenticated
  using (bucket_id = 'oshikatsu-artists' and (select public.oshikatsu_is_master()))
  with check (bucket_id = 'oshikatsu-artists' and (select public.oshikatsu_is_master()));
drop policy if exists "oshikatsu_artists_images_delete_master" on storage.objects;
create policy "oshikatsu_artists_images_delete_master" on storage.objects
  for delete to authenticated using (bucket_id = 'oshikatsu-artists' and (select public.oshikatsu_is_master()));
