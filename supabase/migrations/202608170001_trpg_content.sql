-- open door TRPG content schema
-- Run this file in Supabase SQL Editor before using the writing and character pages.

create extension if not exists pgcrypto;

-- This project already has a legacy characters table. Extend it without removing
-- owner_id, class_name, content, or status so existing records remain compatible.
update public.boards set is_public = false where slug = 'characters';

alter table public.characters add column if not exists role_name text not null default '';
alter table public.characters add column if not exists role_traits text not null default '';
alter table public.characters add column if not exists age integer;
alter table public.characters add column if not exists height numeric(6,2);
alter table public.characters add column if not exists weight numeric(6,2);

update public.characters
set role_name = coalesce(nullif(role_name, ''), coalesce(class_name, '')),
    role_traits = coalesce(nullif(role_traits, ''), coalesce(content, ''))
where role_name = '' or role_traits = '';

create unique index if not exists characters_owner_id_unique on public.characters(owner_id);

create table if not exists public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.characters(id) on delete cascade,
  item_name text not null,
  item_effect text not null default '',
  quantity integer not null default 1 check (quantity > 0),
  grade text not null default '일반' check (grade in ('일반', '고급', '희귀', '영웅', '전설', '신화')),
  item_type text not null default '기타' check (item_type in ('유물', '장비', '소비', '기타')),
  created_at timestamptz not null default now()
);

create table if not exists public.character_cards (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.characters(id) on delete cascade,
  card_name text not null,
  card_effect text not null default '',
  quantity integer not null default 1 check (quantity > 0),
  grade text not null default '기본' check (grade in ('기본', '일반', '고급', '희귀', '특수')),
  created_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists characters_set_updated_at on public.characters;
create trigger characters_set_updated_at
before update on public.characters
for each row execute function public.set_updated_at();

alter table public.characters enable row level security;
alter table public.inventory_items enable row level security;
alter table public.character_cards enable row level security;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

grant execute on function public.is_admin() to anon, authenticated;

drop policy if exists "characters are visible to their owner and admins" on public.characters;
create policy "characters are visible to their owner and admins"
on public.characters for select to authenticated
using (owner_id = auth.uid() or public.is_admin());

drop policy if exists "players can create their own character" on public.characters;
create policy "players can create their own character"
on public.characters for insert to authenticated
with check (owner_id = auth.uid() or public.is_admin());

drop policy if exists "players and admins can update characters" on public.characters;
create policy "players and admins can update characters"
on public.characters for update to authenticated
using (owner_id = auth.uid() or public.is_admin())
with check (owner_id = auth.uid() or public.is_admin());

drop policy if exists "players and admins can delete characters" on public.characters;
create policy "players and admins can delete characters"
on public.characters for delete to authenticated
using (owner_id = auth.uid() or public.is_admin());

drop policy if exists "inventory follows character access" on public.inventory_items;
create policy "inventory follows character access"
on public.inventory_items for all to authenticated
using (exists (select 1 from public.characters c where c.id = character_id and (c.owner_id = auth.uid() or public.is_admin())))
with check (exists (select 1 from public.characters c where c.id = character_id and (c.owner_id = auth.uid() or public.is_admin())));

drop policy if exists "cards follow character access" on public.character_cards;
create policy "cards follow character access"
on public.character_cards for all to authenticated
using (exists (select 1 from public.characters c where c.id = character_id and (c.owner_id = auth.uid() or public.is_admin())))
with check (exists (select 1 from public.characters c where c.id = character_id and (c.owner_id = auth.uid() or public.is_admin())));

alter table public.posts add column if not exists author_id uuid references auth.users(id) on delete set null;

alter table public.posts enable row level security;
drop policy if exists "published posts are publicly readable" on public.posts;
create policy "published posts are publicly readable"
on public.posts for select to anon, authenticated
using (status = 'published' or author_id = auth.uid() or public.is_admin());

drop policy if exists "authenticated users can create posts" on public.posts;
create policy "authenticated users can create posts"
on public.posts for insert to authenticated
with check (author_id = auth.uid());

drop policy if exists "authors and admins can update posts" on public.posts;
create policy "authors and admins can update posts"
on public.posts for update to authenticated
using (author_id = auth.uid() or public.is_admin())
with check (author_id = auth.uid() or public.is_admin());

drop policy if exists "authors and admins can delete posts" on public.posts;
create policy "authors and admins can delete posts"
on public.posts for delete to authenticated
using (author_id = auth.uid() or public.is_admin());

create or replace function public.increment_post_views(post_id_input uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.posts set views = coalesce(views, 0) + 1 where id = post_id_input;
$$;

grant execute on function public.increment_post_views(uuid) to anon, authenticated;

-- Discussion and reaction data for published post detail pages.
create table if not exists public.post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  content text not null check (char_length(trim(content)) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists post_comments_post_id_created_at_idx
on public.post_comments(post_id, created_at);

create table if not exists public.post_likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index if not exists post_likes_post_id_idx
on public.post_likes(post_id);

alter table public.post_comments enable row level security;
alter table public.post_likes enable row level security;

drop policy if exists "published post comments are publicly readable" on public.post_comments;
create policy "published post comments are publicly readable"
on public.post_comments for select to anon, authenticated
using (exists (select 1 from public.posts p where p.id = post_id and (p.status = 'published' or p.author_id = auth.uid() or public.is_admin())));

drop policy if exists "authenticated users can create post comments" on public.post_comments;
create policy "authenticated users can create post comments"
on public.post_comments for insert to authenticated
with check (author_id = auth.uid() and exists (select 1 from public.posts p where p.id = post_id and p.status = 'published'));

drop policy if exists "authors and admins can update post comments" on public.post_comments;
create policy "authors and admins can update post comments"
on public.post_comments for update to authenticated
using (author_id = auth.uid() or public.is_admin())
with check (author_id = auth.uid() or public.is_admin());

drop policy if exists "authors and admins can delete post comments" on public.post_comments;
create policy "authors and admins can delete post comments"
on public.post_comments for delete to authenticated
using (author_id = auth.uid() or public.is_admin());

drop policy if exists "post like counts are publicly readable" on public.post_likes;
create policy "post like counts are publicly readable"
on public.post_likes for select to anon, authenticated
using (exists (select 1 from public.posts p where p.id = post_id and p.status = 'published'));

drop policy if exists "authenticated users can like published posts" on public.post_likes;
create policy "authenticated users can like published posts"
on public.post_likes for insert to authenticated
with check (user_id = auth.uid() and exists (select 1 from public.posts p where p.id = post_id and p.status = 'published'));

drop policy if exists "users can remove their own post likes" on public.post_likes;
create policy "users can remove their own post likes"
on public.post_likes for delete to authenticated
using (user_id = auth.uid());
