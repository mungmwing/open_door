-- 카드 전투 테스트용 키워드·카드 타입·대상 정보를 추가합니다.
-- Supabase SQL Editor에서 1회 실행해 주세요.

alter table public.character_cards
  add column if not exists card_retain boolean not null default false,
  add column if not exists card_innate boolean not null default false,
  add column if not exists card_ethereal boolean not null default false,
  add column if not exists card_type text not null default '스킬',
  add column if not exists card_target text not null default '자신';

alter table public.character_cards
  drop constraint if exists character_cards_card_type_check;

alter table public.character_cards
  add constraint character_cards_card_type_check
  check (card_type in ('공격', '스킬', '파워', '상태', '저주'));

alter table public.character_cards
  drop constraint if exists character_cards_card_target_check;

alter table public.character_cards
  add constraint character_cards_card_target_check
  check (card_target in ('자신', '적 1명', '전체 적', '무작위 적', '아군 1명', '전체 아군'));

comment on column public.character_cards.card_retain is '턴 종료 후 손패에 유지되는 카드';
comment on column public.character_cards.card_innate is '전투 시작 손패에 우선 배치되는 카드';
comment on column public.character_cards.card_ethereal is '턴 종료 시 손패에 남아 있으면 소멸되는 카드';
comment on column public.character_cards.card_type is '공격·스킬·파워·상태·저주 카드 타입';
comment on column public.character_cards.card_target is '카드 효과의 기본 대상';
