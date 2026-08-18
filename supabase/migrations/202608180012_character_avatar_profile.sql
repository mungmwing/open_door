-- Keep normal users' public profile avatar in sync with their character photo.
-- Admin profile photos continue to use profiles.avatar_url directly.
alter table public.profiles enable row level security;

drop policy if exists "users can update their own profile avatar" on public.profiles;
create policy "users can update their own profile avatar"
on public.profiles for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());
