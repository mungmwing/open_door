-- Shared item catalog. Administrators register items once and reuse them when
-- filling a character inventory instead of retyping the same values.
create table if not exists public.items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  effect text not null default '',
  grade text not null default '일반' check (grade in ('일반', '고급', '희귀', '영웅', '전설', '신화')),
  item_type text not null default '기타' check (item_type in ('유물', '장비', '소비', '기타')),
  icon_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists items_name_unique on public.items(lower(name));

drop trigger if exists items_set_updated_at on public.items;
create trigger items_set_updated_at
before update on public.items
for each row execute function public.set_updated_at();

alter table public.inventory_items add column if not exists item_id uuid references public.items(id) on delete set null;
create index if not exists inventory_items_item_id_idx on public.inventory_items(item_id);

-- Move items that were typed directly into a character inventory into the catalog.
insert into public.items (name, effect, grade, item_type, icon_url)
select distinct on (lower(item_name)) trim(item_name), coalesce(item_effect, ''), grade, item_type, icon_url
from public.inventory_items
where trim(coalesce(item_name, '')) <> ''
order by lower(item_name), created_at
on conflict do nothing;

update public.inventory_items as inventory
set item_id = catalog.id
from public.items as catalog
where inventory.item_id is null and lower(trim(inventory.item_name)) = lower(catalog.name);

alter table public.items enable row level security;

drop policy if exists "items are readable by authenticated users" on public.items;
create policy "items are readable by authenticated users"
on public.items for select to authenticated
using (true);

drop policy if exists "admins manage items" on public.items;
create policy "admins manage items"
on public.items for all to authenticated
using (public.is_admin())
with check (public.is_admin());
