-- 推し活手帳: 記録の変更履歴（復元用）
-- oshikatsu_records の行が上書き・削除される直前の内容を、自動で履歴テーブルに残す。
-- また、削除（deleted = true）で中身が空で送られてきても、クラウド側では直前の中身を残す。
-- 履歴は30日で自動的に消える。アプリからは本人の履歴を読むことだけができる（書き換え不可）。

create table if not exists public.oshikatsu_records_history (
  hid         bigint generated always as identity primary key,
  user_id     uuid        not null references auth.users (id) on delete cascade,
  kind        text        not null,
  id          text        not null,
  data        jsonb       not null default '{}'::jsonb,
  deleted     boolean     not null default false,
  updated_at  timestamptz not null,
  archived_at timestamptz not null default now(),
  op          text        not null check (op in ('update', 'delete'))
);

create index if not exists oshikatsu_records_history_user_idx
  on public.oshikatsu_records_history (user_id, archived_at desc);

-- 上書き・削除の直前の行を履歴に残す（中身が変わらない更新は残さない）
create or replace function public.oshikatsu_records_archive()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    -- 削除の印だけで中身が空のときは、直前の中身を残す（あとで戻せるように）
    if new.deleted and (new.data is null or new.data = '{}'::jsonb) then
      new.data := old.data;
    end if;
    if old.data is distinct from new.data or old.deleted is distinct from new.deleted then
      insert into public.oshikatsu_records_history (user_id, kind, id, data, deleted, updated_at, op)
      values (old.user_id, old.kind, old.id, old.data, old.deleted, old.updated_at, 'update');
    end if;
    -- 30日より前の履歴は消す（この人の分だけ）
    delete from public.oshikatsu_records_history
      where user_id = old.user_id and archived_at < now() - interval '30 days';
    return new;
  else
    insert into public.oshikatsu_records_history (user_id, kind, id, data, deleted, updated_at, op)
    values (old.user_id, old.kind, old.id, old.data, old.deleted, old.updated_at, 'delete');
    return old;
  end if;
end;
$$;

drop trigger if exists oshikatsu_records_archive on public.oshikatsu_records;
create trigger oshikatsu_records_archive
  before update or delete on public.oshikatsu_records
  for each row execute function public.oshikatsu_records_archive();

-- Row Level Security: 本人の履歴を読むことだけできる
alter table public.oshikatsu_records_history enable row level security;

drop policy if exists "oshikatsu_records_history_select_own" on public.oshikatsu_records_history;
create policy "oshikatsu_records_history_select_own" on public.oshikatsu_records_history
  for select to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.oshikatsu_records_history from anon;
revoke all on public.oshikatsu_records_history from authenticated;
grant select on public.oshikatsu_records_history to authenticated;
revoke all on function public.oshikatsu_records_archive() from public, anon, authenticated;
