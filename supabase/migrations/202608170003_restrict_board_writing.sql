-- Only the users board is writable by regular authenticated users.
drop policy if exists "authenticated users can create posts" on public.posts;
create policy "users can create user-board posts and admins can create all posts"
on public.posts for insert to authenticated
with check (author_id = auth.uid() and (board_slug = 'users' or public.is_admin()));
