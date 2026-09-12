-- 장비/유물 장착 상태 저장을 위한 SQL입니다.
-- Supabase SQL Editor에서 한 번 실행해 주세요.

alter table public.inventory_items
  add column if not exists is_equipped boolean not null default false;

create index if not exists inventory_items_equipped_character_idx
  on public.inventory_items (character_id)
  where is_equipped = true;

-- 플레이어는 자신의 캐릭터 인벤토리에서 is_equipped만 변경할 수 있고,
-- 관리자는 기존처럼 인벤토리 전체를 관리할 수 있도록 합니다.
drop policy if exists "owners can toggle inventory equipment" on public.inventory_items;
create policy "owners can toggle inventory equipment"
on public.inventory_items for update to authenticated
using (
  public.is_admin()
  or exists (
    select 1
    from public.characters c
    where c.id = character_id and c.owner_id = auth.uid()
  )
)
with check (
  public.is_admin()
  or exists (
    select 1
    from public.characters c
    where c.id = character_id and c.owner_id = auth.uid()
  )
);

create or replace function public.prevent_player_inventory_edits()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() and (
    new.character_id is distinct from old.character_id
    or new.item_id is distinct from old.item_id
    or new.item_name is distinct from old.item_name
    or new.item_effect is distinct from old.item_effect
    or new.item_description is distinct from old.item_description
    or new.quantity is distinct from old.quantity
    or new.grade is distinct from old.grade
    or new.item_type is distinct from old.item_type
    or new.icon_url is distinct from old.icon_url
    or new.created_at is distinct from old.created_at
  ) then
    raise exception '플레이어는 장착 상태만 변경할 수 있습니다.';
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_player_inventory_edits on public.inventory_items;
create trigger prevent_player_inventory_edits
before update on public.inventory_items
for each row execute function public.prevent_player_inventory_edits();
