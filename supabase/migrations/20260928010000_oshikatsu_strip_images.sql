-- 推し活手帳: 画像データを Supabase に残さない
-- 写真・推しの写真・ヘッダーロゴは、すべて本人の Google ドライブに保存し、記録には置き場所（gdrive:<ファイルID>）だけを入れる。
-- ここでは、Supabase 側に残っている画像データ（data:image/... の文字列）を消す。
--   1) 変更履歴（oshikatsu_records_history）に残る画像データを消す
--   2) 削除済みの記録（deleted = true）に残る画像データを消す
--   3) これからは、変更履歴に残すときも画像データを消してから残す
-- 画像データの部分は null（写真なし）に置き換える。記録のほかの内容はそのまま残る。
-- 表示中の記録（deleted = false）の画像データは、アプリが Google ドライブへ移してから置き場所に書き換えるので、ここでは触らない。

-- 画像データ（"data:image/..." の JSON 文字列）を null に置き換える
create or replace function public.oshikatsu_strip_images(d jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case
    when d is null then null
    when position('"data:image/' in d::text) = 0 then d
    else regexp_replace(d::text, '"data:image/(?:[^"\\]|\\.)*"', 'null', 'g')::jsonb
  end
$$;
revoke all on function public.oshikatsu_strip_images(jsonb) from public, anon, authenticated;

-- 3) 変更履歴に残すときに画像データを消す（それ以外は 20260927000000 と同じ）
create or replace function public.oshikatsu_records_archive()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    -- 削除の印だけで中身が空のときは、直前の中身を残す（画像データは消す）
    if new.deleted and (new.data is null or new.data = '{}'::jsonb) then
      new.data := public.oshikatsu_strip_images(old.data);
    end if;
    if old.data is distinct from new.data or old.deleted is distinct from new.deleted then
      insert into public.oshikatsu_records_history (user_id, kind, id, data, deleted, updated_at, op)
      values (old.user_id, old.kind, old.id, public.oshikatsu_strip_images(old.data), old.deleted, old.updated_at, 'update');
    end if;
    delete from public.oshikatsu_records_history
      where user_id = old.user_id and archived_at < now() - interval '30 days';
    return new;
  else
    insert into public.oshikatsu_records_history (user_id, kind, id, data, deleted, updated_at, op)
    values (old.user_id, old.kind, old.id, public.oshikatsu_strip_images(old.data), old.deleted, old.updated_at, 'delete');
    return old;
  end if;
end;
$$;
revoke all on function public.oshikatsu_records_archive() from public, anon, authenticated;

-- 1) 変更履歴に残る画像データを消す
update public.oshikatsu_records_history
   set data = public.oshikatsu_strip_images(data)
 where position('"data:image/' in data::text) > 0;

-- 2) 削除済みの記録に残る画像データを消す
--    （この更新でも変更履歴は残るが、3) により画像データは消えた形で残る）
update public.oshikatsu_records
   set data = public.oshikatsu_strip_images(data)
 where deleted = true
   and position('"data:image/' in data::text) > 0;

-- 確認用：表示中の記録で、まだ画像データのままのもの（アプリが Google ドライブへ移すと 0 件になる）
-- select kind, count(*) from public.oshikatsu_records
--  where deleted = false and position('"data:image/' in data::text) > 0
--  group by kind;
