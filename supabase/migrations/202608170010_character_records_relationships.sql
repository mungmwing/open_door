-- Character-specific records and NPC relationships.
create table if not exists public.character_extra_records (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.characters(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 120),
  content text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.character_relationships (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.characters(id) on delete cascade,
  npc_post_id uuid references public.posts(id) on delete set null,
  relationship_name text not null default '',
  memo text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.character_extra_records enable row level security;
alter table public.character_relationships enable row level security;

drop policy if exists "character records are visible to owner and admins" on public.character_extra_records;
create policy "character records are visible to owner and admins"
on public.character_extra_records for select to authenticated
using (exists (select 1 from public.characters c where c.id = character_id and (c.owner_id = auth.uid() or public.is_admin())));
drop policy if exists "owners and admins can create character records" on public.character_extra_records;
create policy "owners and admins can create character records"
on public.character_extra_records for insert to authenticated
with check (author_id = auth.uid() and exists (select 1 from public.characters c where c.id = character_id and (c.owner_id = auth.uid() or public.is_admin())));
drop policy if exists "authors and admins can update character records" on public.character_extra_records;
create policy "authors and admins can update character records"
on public.character_extra_records for update to authenticated
using (author_id = auth.uid() or public.is_admin())
with check (
  (author_id = auth.uid() or public.is_admin())
  and exists (select 1 from public.characters c where c.id = character_id and (c.owner_id = auth.uid() or public.is_admin()))
);
drop policy if exists "authors and admins can delete character records" on public.character_extra_records;
create policy "authors and admins can delete character records"
on public.character_extra_records for delete to authenticated
using (author_id = auth.uid() or public.is_admin());

drop policy if exists "character relationships are visible to owner and admins" on public.character_relationships;
create policy "character relationships are visible to owner and admins"
on public.character_relationships for select to authenticated
using (exists (select 1 from public.characters c where c.id = character_id and (c.owner_id = auth.uid() or public.is_admin())));
drop policy if exists "owners and admins can manage character relationships" on public.character_relationships;
create policy "owners and admins can manage character relationships"
on public.character_relationships for all to authenticated
using (exists (select 1 from public.characters c where c.id = character_id and (c.owner_id = auth.uid() or public.is_admin())))
with check (exists (select 1 from public.characters c where c.id = character_id and (c.owner_id = auth.uid() or public.is_admin())));

drop trigger if exists character_extra_records_set_updated_at on public.character_extra_records;
create trigger character_extra_records_set_updated_at
before update on public.character_extra_records
for each row execute function public.set_updated_at();
drop trigger if exists character_relationships_set_updated_at on public.character_relationships;
create trigger character_relationships_set_updated_at
before update on public.character_relationships
for each row execute function public.set_updated_at();
