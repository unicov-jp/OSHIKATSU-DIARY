-- 推し活手帳: アーティスト・曲の登録を記録の表に入れられるようにする
-- oshikatsu_records の kind に 'artist'（アーティスト）と 'song'（曲）を追加する。
-- 実行するまでは、アーティスト・曲の登録はその端末の中にだけ残り、ほかの記録の同期はこれまでどおり動く。

alter table public.oshikatsu_records drop constraint if exists oshikatsu_records_kind_check;
alter table public.oshikatsu_records
  add constraint oshikatsu_records_kind_check
  check (kind in ('oshi', 'live', 'cheki', 'goods', 'settings', 'artist', 'song'));
