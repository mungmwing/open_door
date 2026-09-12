-- 장비 부위(모자/상의/하의/무기)와 동일 부위 자동 교체 기능을 추가합니다.
-- 이 파일은 자동 실행되지 않습니다. Supabase SQL Editor에서 직접 실행해 주세요.

alter table public.items
  add column if not exists equipment_slot text;

update public.items
set equipment_slot = null
where item_type <> '장비' and equipment_slot is not null;

alter table public.items
  drop constraint if exists items_equipment_slot_check;

alter table public.items
  add constraint items_equipment_slot_check
  check (
    (item_type = '장비' and (equipment_slot is null or equipment_slot in ('모자', '상의', '하의', '무기')))
    or (item_type <> '장비' and equipment_slot is null)
  );

alter table public.inventory_items
  add column if not exists is_equipped boolean not null default false;

create index if not exists inventory_items_equipped_character_idx
  on public.inventory_items (character_id)
  where is_equipped = true;

-- 어느 경로에서 장착 상태가 변경되더라도 같은 캐릭터의 같은 부위는 하나만 남깁니다.
create or replace function public.enforce_equipment_slot_exclusivity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item_type text;
  v_equipment_slot text;
begin
  if not coalesce(new.is_equipped, false) then
    return new;
  end if;

  select coalesce(catalog.item_type, new.item_type), catalog.equipment_slot
    into v_item_type, v_equipment_slot
  from public.items catalog
  where catalog.id = new.item_id;

  if not found then
    v_item_type := new.item_type;
    v_equipment_slot := null;
  end if;

  if v_item_type = '장비' then
    if v_equipment_slot is null then
      raise exception '장비 부위가 지정되지 않은 아이템은 장착할 수 없습니다.';
    end if;

    update public.inventory_items other_inventory
       set is_equipped = false
      from public.items other_item
     where other_inventory.item_id = other_item.id
       and other_inventory.character_id = new.character_id
       and other_inventory.id <> new.id
       and other_inventory.is_equipped = true
       and other_item.item_type = '장비'
       and other_item.equipment_slot = v_equipment_slot;
  elsif v_item_type <> '유물' then
    raise exception '장비 또는 유물만 장착할 수 있습니다.';
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_equipment_slot_exclusivity on public.inventory_items;
create trigger enforce_equipment_slot_exclusivity
before insert or update of is_equipped, item_id, character_id
on public.inventory_items
for each row
execute function public.enforce_equipment_slot_exclusivity();

-- 기존에 장착된 아이템의 부위를 관리자가 나중에 지정하거나 변경해도 즉시 정리합니다.
create or replace function public.reconcile_equipment_after_catalog_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.item_type = '장비' and new.equipment_slot is not null then
    with ranked_equipment as (
      select inventory.id,
             row_number() over (
               partition by inventory.character_id
               order by inventory.created_at desc, inventory.id desc
             ) as slot_order
      from public.inventory_items inventory
      join public.items catalog on catalog.id = inventory.item_id
      where inventory.is_equipped = true
        and catalog.item_type = '장비'
        and catalog.equipment_slot = new.equipment_slot
    )
    update public.inventory_items inventory
       set is_equipped = false
      from ranked_equipment ranked
     where inventory.id = ranked.id
       and ranked.slot_order > 1;
  elsif new.item_type not in ('장비', '유물')
     or (new.item_type = '장비' and new.equipment_slot is null) then
    update public.inventory_items
       set is_equipped = false
     where item_id = new.id
       and is_equipped = true;
  end if;

  return new;
end;
$$;

drop trigger if exists reconcile_equipment_after_catalog_change on public.items;
create trigger reconcile_equipment_after_catalog_change
after update of item_type, equipment_slot
on public.items
for each row
execute function public.reconcile_equipment_after_catalog_change();

-- 플레이어와 관리자가 사용하는 원자적 장착/해제 함수입니다.
create or replace function public.set_inventory_item_equipped(
  p_inventory_item_id uuid,
  p_equipped boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_character_id uuid;
  v_item_type text;
  v_equipment_slot text;
begin
  select inventory.character_id,
         coalesce(catalog.item_type, inventory.item_type),
         catalog.equipment_slot
    into v_character_id, v_item_type, v_equipment_slot
  from public.inventory_items inventory
  left join public.items catalog on catalog.id = inventory.item_id
  where inventory.id = p_inventory_item_id;

  if not found then
    raise exception '인벤토리 아이템을 찾을 수 없습니다.';
  end if;

  if not (
    coalesce(public.is_admin(), false)
    or exists (
      select 1
      from public.characters character
      where character.id = v_character_id
        and character.owner_id = auth.uid()
    )
  ) then
    raise exception '이 캐릭터의 장착 상태를 변경할 권한이 없습니다.';
  end if;

  if v_item_type not in ('장비', '유물') then
    raise exception '장비 또는 유물만 장착할 수 있습니다.';
  end if;

  if p_equipped and v_item_type = '장비' and v_equipment_slot is null then
    raise exception '장비 부위가 지정되지 않은 아이템은 장착할 수 없습니다.';
  end if;

  -- 캐릭터 행을 잠가 같은 캐릭터의 동시 장착 요청을 순서대로 처리합니다.
  perform 1
  from public.characters character
  where character.id = v_character_id
  for update;

  update public.inventory_items
  set is_equipped = p_equipped
  where id = p_inventory_item_id;
end;
$$;

revoke all on function public.set_inventory_item_equipped(uuid, boolean) from public;
grant execute on function public.set_inventory_item_equipped(uuid, boolean) to authenticated;
