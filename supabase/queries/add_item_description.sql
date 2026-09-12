-- 아이템 효과와 설명을 분리하기 위한 컬럼 추가 쿼리입니다.
-- 기존 item_effect 값은 그대로 효과로 유지됩니다.

alter table public.items
  add column if not exists item_description text not null default '';

alter table public.inventory_items
  add column if not exists item_description text not null default '';

comment on column public.items.item_effect is '아이템의 게임 효과';
comment on column public.items.item_description is '아이템의 일반 설명 및 설정';
comment on column public.inventory_items.item_effect is '인벤토리에 저장된 아이템 효과 스냅샷';
comment on column public.inventory_items.item_description is '인벤토리에 저장된 아이템 설명 스냅샷';
