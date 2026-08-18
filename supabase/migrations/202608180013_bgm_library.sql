-- BGM library for map, character, and scene music used by session logs.
insert into public.boards (slug, name, description, sort_order, is_public)
values ('bgm', 'BGM 게시판', '맵 · 캐릭터 · 장면별 배경음악', 65, true)
on conflict (slug) do update set name = excluded.name, description = excluded.description, is_public = true;

alter table public.posts add column if not exists bgm_url text;
alter table public.posts add column if not exists bgm_category text;

insert into storage.buckets (id, name, public)
values ('bgm-audio', 'bgm-audio', true)
on conflict (id) do update set public = true;

drop policy if exists "public can view bgm audio" on storage.objects;
create policy "public can view bgm audio"
on storage.objects for select to anon, authenticated
using (bucket_id = 'bgm-audio');

drop policy if exists "admins can upload bgm audio" on storage.objects;
create policy "admins can upload bgm audio"
on storage.objects for insert to authenticated
with check (bucket_id = 'bgm-audio' and public.is_admin());

drop policy if exists "admins can delete bgm audio" on storage.objects;
create policy "admins can delete bgm audio"
on storage.objects for delete to authenticated
using (bucket_id = 'bgm-audio' and public.is_admin());
