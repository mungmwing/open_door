-- open door 상점 기능용 쿼리입니다.
-- characters.money를 회원의 G 잔액으로 사용합니다.
-- 이 파일은 자동 실행되지 않으며 Supabase SQL Editor에서 직접 실행해 주세요.

-- 상점 RPC가 아이템 설명과 구매 후 인벤토리 스냅샷을 저장할 수 있도록 보장합니다.
alter table public.characters
  add column if not exists money integer not null default 0;

alter table public.items
  add column if not exists item_description text not null default '';

alter table public.inventory_items
  add column if not exists item_description text not null default '';

create table if not exists public.shop_listings (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null unique references public.items(id) on delete restrict,
  price_g integer not null default 0 check (price_g >= 0),
  personal_limit integer check (personal_limit is null or personal_limit > 0),
  total_limit integer check (total_limit is null or total_limit > 0),
  sold_count integer not null default 0 check (sold_count >= 0),
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.shop_purchases (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.shop_listings(id) on delete cascade,
  character_id uuid not null references public.characters(id) on delete cascade,
  quantity integer not null default 0 check (quantity >= 0),
  unit_price_g integer not null default 0 check (unit_price_g >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (listing_id, character_id)
);

create or replace function public.set_shop_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists shop_listings_set_updated_at on public.shop_listings;
create trigger shop_listings_set_updated_at
before update on public.shop_listings
for each row execute function public.set_shop_updated_at();

drop trigger if exists shop_purchases_set_updated_at on public.shop_purchases;
create trigger shop_purchases_set_updated_at
before update on public.shop_purchases
for each row execute function public.set_shop_updated_at();

alter table public.shop_listings enable row level security;
alter table public.shop_purchases enable row level security;

drop policy if exists "shop listings are readable by authenticated users" on public.shop_listings;
create policy "shop listings are readable by authenticated users"
on public.shop_listings for select to authenticated
using (true);

drop policy if exists "admins manage shop listings" on public.shop_listings;
create policy "admins manage shop listings"
on public.shop_listings for all to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "members view their shop purchases" on public.shop_purchases;
create policy "members view their shop purchases"
on public.shop_purchases for select to authenticated
using (exists (
  select 1 from public.characters c
  where c.id = character_id
    and (c.owner_id = auth.uid() or public.is_admin())
));

create or replace function public.purchase_shop_item(
  p_listing_id uuid,
  p_quantity integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_character public.characters%rowtype;
  v_listing record;
  v_previous_quantity integer := 0;
  v_total_cost integer;
  v_stock_remaining integer;
begin
  if auth.uid() is null then
    raise exception '로그인 후 구매할 수 있습니다.';
  end if;

  if p_quantity is null or p_quantity < 1 then
    raise exception '구매 수량은 1개 이상이어야 합니다.';
  end if;

  select * into v_character
  from public.characters
  where owner_id = auth.uid()
  order by created_at
  limit 1
  for update;

  if not found then
    raise exception '구매할 캐릭터가 없습니다.';
  end if;

  select sl.*, i.name, i.item_effect, i.item_description, i.grade, i.item_type, i.icon_url
  into v_listing
  from public.shop_listings sl
  join public.items i on i.id = sl.item_id
  where sl.id = p_listing_id
  for update of sl;

  if not found then
    raise exception '판매 상품을 찾을 수 없습니다.';
  end if;

  if not v_listing.is_active then
    raise exception '현재 판매 중인 상품이 아닙니다.';
  end if;

  if v_listing.total_limit is not null and v_listing.sold_count + p_quantity > v_listing.total_limit then
    raise exception '전체 판매 수량을 초과했습니다.';
  end if;

  select coalesce(quantity, 0) into v_previous_quantity
  from public.shop_purchases
  where listing_id = p_listing_id
    and character_id = v_character.id
  for update;

  if v_listing.personal_limit is not null and v_previous_quantity + p_quantity > v_listing.personal_limit then
    raise exception '개인 구매 제한 수량을 초과했습니다.';
  end if;

  v_total_cost := v_listing.price_g * p_quantity;
  if v_character.money < v_total_cost then
    raise exception 'G가 부족합니다.';
  end if;

  update public.characters
  set money = money - v_total_cost
  where id = v_character.id;

  insert into public.inventory_items (
    character_id, item_id, item_name, item_effect, item_description,
    quantity, grade, item_type, icon_url
  ) values (
    v_character.id, v_listing.item_id, v_listing.name, v_listing.item_effect,
    coalesce(v_listing.item_description, ''), p_quantity, v_listing.grade,
    v_listing.item_type, v_listing.icon_url
  )
  on conflict (character_id, item_id) where item_id is not null
  do update set
    quantity = public.inventory_items.quantity + excluded.quantity,
    item_name = excluded.item_name,
    item_effect = excluded.item_effect,
    item_description = excluded.item_description,
    grade = excluded.grade,
    item_type = excluded.item_type,
    icon_url = excluded.icon_url;

  insert into public.shop_purchases (listing_id, character_id, quantity, unit_price_g)
  values (p_listing_id, v_character.id, p_quantity, v_listing.price_g)
  on conflict (listing_id, character_id)
  do update set
    quantity = public.shop_purchases.quantity + excluded.quantity,
    unit_price_g = excluded.unit_price_g;

  update public.shop_listings
  set sold_count = sold_count + p_quantity
  where id = p_listing_id;

  v_stock_remaining := case
    when v_listing.total_limit is null then null
    else v_listing.total_limit - v_listing.sold_count - p_quantity
  end;

  return jsonb_build_object(
    'item_name', v_listing.name,
    'quantity', p_quantity,
    'spent_g', v_total_cost,
    'remaining_balance', v_character.money - v_total_cost,
    'stock_remaining', v_stock_remaining
  );
end;
$$;

revoke all on function public.purchase_shop_item(uuid, integer) from public;
grant execute on function public.purchase_shop_item(uuid, integer) to authenticated;
