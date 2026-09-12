-- 카드 전투 테스트에서 기본/소멸/추가 드롭 효과와 추가 드롭 개수를 분리해 저장합니다.
-- Supabase SQL Editor에서 1회 실행해 주세요. 이 파일을 앱에서 자동 실행하지는 않습니다.

alter table public.character_cards
  add column if not exists card_exhaust_effect text not null default '',
  add column if not exists card_drop_effect text not null default '',
  add column if not exists card_drop_count integer not null default 0;

alter table public.character_cards
  drop constraint if exists character_cards_card_drop_count_check;

alter table public.character_cards
  add constraint character_cards_card_drop_count_check check (card_drop_count >= 0);

comment on column public.character_cards.card_exhaust_effect is '카드가 소멸될 때 적용되는 효과';
comment on column public.character_cards.card_drop_effect is '카드 효과로 추가 드롭할 카드 또는 처리 내용';
comment on column public.character_cards.card_drop_count is '카드 사용 시 추가로 드롭할 카드 수';
