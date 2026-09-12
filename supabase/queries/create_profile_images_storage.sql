-- 프로필 이미지를 DB의 Base64 문자열 대신 Supabase Storage URL로 저장합니다.
-- Supabase SQL Editor에서 한 번 실행하세요.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'profile-images',
  'profile-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "public can view profile images" on storage.objects;
create policy "public can view profile images"
on storage.objects for select
to anon, authenticated
using (bucket_id = 'profile-images');

drop policy if exists "users can upload own profile images" on storage.objects;
create policy "users can upload own profile images"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "users can update own profile images" on storage.objects;
create policy "users can update own profile images"
on storage.objects for update
to authenticated
using (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "users can delete own profile images" on storage.objects;
create policy "users can delete own profile images"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- 기존 Base64 프로필 이미지는 사용자가 새 사진을 저장할 때 Storage URL로 교체됩니다.
