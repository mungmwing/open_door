-- Master item catalog linked to character inventory rows.
create table if not exists public.items (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 120),
  item_effect text not null default '',
  grade text not null default '일반' check (grade in ('일반', '고급', '희귀', '영웅', '전설', '신화')),
  item_type text not null default '기타' check (item_type in ('유물', '장비', '소비', '기타')),
  icon_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists items_name_lower_unique on public.items (lower(trim(name)));

alter table public.inventory_items add column if not exists item_id uuid references public.items(id) on delete restrict;

create unique index if not exists inventory_items_character_item_unique
on public.inventory_items (character_id, item_id)
where item_id is not null;

-- Seed catalog entries from existing inventory rows and link them.
insert into public.items (name, item_effect, grade, item_type, icon_url)
select distinct on (lower(trim(source.item_name)))
  trim(source.item_name),
  coalesce(source.item_effect, ''),
  source.grade,
  source.item_type,
  source.icon_url
from public.inventory_items source
where trim(source.item_name) <> ''
  and not exists (
    select 1
    from public.items existing
    where lower(trim(existing.name)) = lower(trim(source.item_name))
  )
order by lower(trim(source.item_name)), source.created_at;

update public.inventory_items inv
set item_id = cat.id
from public.items cat
where inv.item_id is null
  and trim(inv.item_name) <> ''
  and lower(trim(cat.name)) = lower(trim(inv.item_name));

drop trigger if exists items_set_updated_at on public.items;
create trigger items_set_updated_at
before update on public.items
for each row execute function public.set_updated_at();

alter table public.items enable row level security;

drop policy if exists "items are readable by authenticated users" on public.items;
create policy "items are readable by authenticated users"
on public.items for select to authenticated
using (true);

drop policy if exists "admins can insert items" on public.items;
create policy "admins can insert items"
on public.items for insert to authenticated
with check (public.is_admin());

drop policy if exists "admins can update items" on public.items;
create policy "admins can update items"
on public.items for update to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "admins can delete items" on public.items;
create policy "admins can delete items"
on public.items for delete to authenticated
using (public.is_admin());

insert into storage.buckets (id, name, public)
values ('item-icons', 'item-icons', true)
on conflict (id) do update set public = true;

drop policy if exists "public can view item icons" on storage.objects;
create policy "public can view item icons"
on storage.objects for select to anon, authenticated
using (bucket_id = 'item-icons');

drop policy if exists "admins can upload item icons" on storage.objects;
create policy "admins can upload item icons"
on storage.objects for insert to authenticated
with check (bucket_id = 'item-icons' and public.is_admin());

drop policy if exists "admins can delete item icons" on storage.objects;
create policy "admins can delete item icons"
on storage.objects for delete to authenticated
using (bucket_id = 'item-icons' and public.is_admin());
