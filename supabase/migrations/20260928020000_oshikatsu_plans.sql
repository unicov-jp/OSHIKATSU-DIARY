-- 推し活手帳: アカウントの種類（マスター・有料・無料）と、種類ごとの機能のON/OFF
--
-- oshikatsu_profiles       … 1人1行。plan は 'master'（マスター）/ 'paid'（有料）/ 'free'（無料）
-- oshikatsu_plan_features  … 種類ごとの機能のON/OFF（行が無い機能はON）
-- oshikatsu_news           … マイページの NEWS（お知らせ）。書けるのはマスターだけ
--
-- ・新しく登録した人は自動で「無料」になる。今いる人も「無料」として行を作る。
-- ・本人は自分の行を読めるだけで、種類を書き換えることはできない（有料・マスターへの自己昇格を防ぐ）。
-- ・マスターは全員の行を読み、種類を変更でき、機能のON/OFFを設定できる。
-- ・最初のマスターは、このファイルの最後の1行（メールアドレスを入れて実行）で決める。

create table if not exists public.oshikatsu_profiles (
  user_id    uuid        primary key references auth.users (id) on delete cascade,
  email      text,
  plan       text        not null default 'free' check (plan in ('master', 'paid', 'free')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.oshikatsu_plan_features (
  plan       text        not null check (plan in ('paid', 'free')),
  feature    text        not null,
  enabled    boolean     not null default true,
  updated_at timestamptz not null default now(),
  primary key (plan, feature)
);

-- マスターかどうか（行レベルセキュリティの中で使う。自分の行を読むだけなので再帰しない）
create or replace function public.oshikatsu_is_master()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.oshikatsu_profiles
     where user_id = (select auth.uid()) and plan = 'master'
  );
$$;
revoke all on function public.oshikatsu_is_master() from public, anon;
grant execute on function public.oshikatsu_is_master() to authenticated;

-- 新しく登録した人の行を「無料」で作る
create or replace function public.oshikatsu_new_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.oshikatsu_profiles (user_id, email, plan)
  values (new.id, new.email, 'free')
  on conflict (user_id) do nothing;
  return new;
end;
$$;
revoke all on function public.oshikatsu_new_profile() from public, anon, authenticated;

drop trigger if exists oshikatsu_new_profile on auth.users;
create trigger oshikatsu_new_profile
  after insert on auth.users
  for each row execute function public.oshikatsu_new_profile();

-- 今いる人の行を「無料」で作る
insert into public.oshikatsu_profiles (user_id, email, plan)
select id, email, 'free' from auth.users
on conflict (user_id) do nothing;

-- 行レベルセキュリティ
alter table public.oshikatsu_profiles enable row level security;
alter table public.oshikatsu_plan_features enable row level security;

drop policy if exists "oshikatsu_profiles_select" on public.oshikatsu_profiles;
create policy "oshikatsu_profiles_select" on public.oshikatsu_profiles
  for select to authenticated
  using ((select auth.uid()) = user_id or (select public.oshikatsu_is_master()));

drop policy if exists "oshikatsu_profiles_update_master" on public.oshikatsu_profiles;
create policy "oshikatsu_profiles_update_master" on public.oshikatsu_profiles
  for update to authenticated
  using ((select public.oshikatsu_is_master()))
  with check ((select public.oshikatsu_is_master()));

drop policy if exists "oshikatsu_plan_features_select" on public.oshikatsu_plan_features;
create policy "oshikatsu_plan_features_select" on public.oshikatsu_plan_features
  for select to authenticated using (true);

drop policy if exists "oshikatsu_plan_features_write_master" on public.oshikatsu_plan_features;
create policy "oshikatsu_plan_features_write_master" on public.oshikatsu_plan_features
  for all to authenticated
  using ((select public.oshikatsu_is_master()))
  with check ((select public.oshikatsu_is_master()));

revoke all on public.oshikatsu_profiles from anon;
revoke all on public.oshikatsu_plan_features from anon;
grant select, update (plan, updated_at) on public.oshikatsu_profiles to authenticated;
grant select, insert, update, delete on public.oshikatsu_plan_features to authenticated;

-- お知らせ（マイページの NEWS）：だれでも読める。書けるのはマスターだけ
create table if not exists public.oshikatsu_news (
  id           uuid        primary key default gen_random_uuid(),
  title        text        not null,
  body         text        not null default '',
  published_at timestamptz not null default now(),
  created_by   uuid        references auth.users (id) on delete set null,
  updated_at   timestamptz not null default now()
);
create index if not exists oshikatsu_news_published_idx on public.oshikatsu_news (published_at desc);
alter table public.oshikatsu_news enable row level security;

drop policy if exists "oshikatsu_news_select" on public.oshikatsu_news;
create policy "oshikatsu_news_select" on public.oshikatsu_news
  for select to authenticated using (true);

drop policy if exists "oshikatsu_news_write_master" on public.oshikatsu_news;
create policy "oshikatsu_news_write_master" on public.oshikatsu_news
  for all to authenticated
  using ((select public.oshikatsu_is_master()))
  with check ((select public.oshikatsu_is_master()));

revoke all on public.oshikatsu_news from anon;
grant select, insert, update, delete on public.oshikatsu_news to authenticated;

-- 最初のマスターを決める（メールアドレスを自分のものに書き換えて、この1行を実行する）
-- update public.oshikatsu_profiles set plan = 'master', updated_at = now() where email = 'ここにマスターにするメールアドレス';
