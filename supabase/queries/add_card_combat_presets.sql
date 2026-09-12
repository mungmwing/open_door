-- 수동 적용 쿼리: create_realtime_combat.sql 적용 후 전체 실행하세요.
-- 앱/에이전트는 운영 DB에 이 쿼리를 자동 실행하지 않습니다.
-- 카드 사전 설정 저장, 원자적 카드 저장, 새 참가자의 전투방 자동 적용.
begin;

-- 기존 카드 편집기의 선택 컬럼도 이전 스키마에서 누락되지 않도록 보완합니다.
alter table public.character_cards
  add column if not exists combat_rule jsonb default null,
  add column if not exists energy integer not null default 0,
  add column if not exists card_exhaust_effect text not null default '',
  add column if not exists card_drop_effect text not null default '',
  add column if not exists card_drop_count integer not null default 0,
  add column if not exists card_retain boolean not null default false,
  add column if not exists card_innate boolean not null default false,
  add column if not exists card_ethereal boolean not null default false,
  add column if not exists card_type text not null default '스킬',
  add column if not exists card_target text not null default '자신';
comment on column public.character_cards.combat_rule is '관리자가 미리 저장한 실시간 전투 효과. NULL은 미설정. 참가 시 방에 복사하며 기존 전투는 변경하지 않음.';

create or replace function combat_private.validate_card_rule(rule jsonb)
returns void language plpgsql immutable set search_path = '' as $$
begin
  if rule is null then return; end if;
  if jsonb_typeof(rule) is distinct from 'object'
    or jsonb_typeof(rule->'playable') is distinct from 'boolean'
    or jsonb_typeof(rule->'exhaust') is distinct from 'boolean' then
    raise exception '사용 가능·소멸 설정을 확인해 주세요.';
  end if;
  perform combat_private.validate_effects(rule->'effects');
  perform combat_private.validate_effects(rule->'on_exhaust');
  if exists(select 1 from jsonb_array_elements(rule->'on_exhaust') e where e->>'target' in ('enemy','ally')) then
    raise exception '소멸 효과는 자신·전체·무작위 대상을 사용해 주세요.';
  end if;
  if exists(select 1 from jsonb_array_elements(rule->'effects') e where e->>'target'='enemy')
    and exists(select 1 from jsonb_array_elements(rule->'effects') e where e->>'target'='ally') then
    raise exception '한 카드의 선택 대상은 적 또는 아군 중 한 종류만 지정할 수 있습니다.';
  end if;
end; $$;

create or replace function combat_private.guard_card_preset()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.combat_rule = 'null'::jsonb then new.combat_rule := null; end if;
  if (tg_op='INSERT' and new.combat_rule is not null)
    or (tg_op='UPDATE' and new.combat_rule is distinct from old.combat_rule) then
    if auth.uid() is null or not public.is_admin() then raise exception '전투 사전 설정은 관리자만 변경할 수 있습니다.'; end if;
    perform combat_private.validate_card_rule(new.combat_rule);
  end if;
  return new;
end; $$;
drop trigger if exists character_cards_guard_combat_preset on public.character_cards;
create trigger character_cards_guard_combat_preset before insert or update of combat_rule on public.character_cards
for each row execute function combat_private.guard_card_preset();

-- 기존 방 액션 RPC가 복사한 서버 덱에서만 사전 설정을 가져옵니다.
-- 멤버 변화가 없는 설정/카드 사용은 건드리지 않습니다.
create or replace function combat_private.import_card_presets()
returns trigger language plpgsql security definer set search_path = '' as $$
declare c jsonb; merged jsonb;
begin
  if new.status<>'waiting' or new.member_ids is not distinct from old.member_ids then return new; end if;
  -- 퇴장한 덱의 설정은 제거하여 재참가 시 최신 사전 설정을 사용합니다.
  select coalesce(jsonb_object_agg(key,value),'{}') into merged from jsonb_each(new.state->'rules') r
  where exists(select 1 from jsonb_array_elements(new.state->'players') p cross join lateral jsonb_array_elements(p->'cards') card where card->>'id'=r.key);
  for c in
    select distinct card from jsonb_array_elements(new.state->'players') p cross join lateral jsonb_array_elements(p->'cards') card
    where not exists(select 1 from jsonb_array_elements(old.state->'players') op where op->>'owner_id'=p->>'owner_id')
  loop
    if c->'combat_rule' is not null and c->'combat_rule'<>'null'::jsonb then
      perform combat_private.validate_card_rule(c->'combat_rule');
      merged := jsonb_set(merged,array[c->>'id'],c->'combat_rule');
    end if;
  end loop;
  new.state := jsonb_set(new.state,'{rules}',merged);
  return new;
end; $$;
drop trigger if exists combat_rooms_import_card_presets on public.combat_rooms;
create trigger combat_rooms_import_card_presets before update of member_ids on public.combat_rooms
for each row execute function combat_private.import_card_presets();

-- 하나의 트랜잭션으로 저장하므로 검증/INSERT 실패 시 기존 카드가 보존됩니다.
-- 기존 카드 ID와 created_at은 유지하며, 이번 목록에서 제거한 카드만 삭제합니다.
create or replace function public.combat_save_character_cards(p_character_id uuid,p_cards jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c jsonb; card_id uuid; kept uuid[] := '{}'; saved jsonb;
begin
  if auth.uid() is null or not public.is_admin() then raise exception '카드는 관리자만 저장할 수 있습니다.'; end if;
  perform 1 from public.characters where id=p_character_id for update;
  if not found then raise exception '캐릭터를 찾을 수 없습니다.'; end if;
  if jsonb_typeof(p_cards) is distinct from 'array' then raise exception '카드 목록이 올바르지 않습니다.'; end if;
  if jsonb_array_length(p_cards)>500 then raise exception '카드 종류는 최대 500개까지 저장할 수 있습니다.'; end if;
  for c in select value from jsonb_array_elements(p_cards) loop
    if length(trim(coalesce(c->>'card_name',''))) not between 1 and 200 then raise exception '카드 이름은 1~200자로 입력해 주세요.'; end if;
    perform combat_private.validate_card_rule(nullif(c->'combat_rule','null'::jsonb));
    if c->>'card_type' is null or c->>'card_type' not in ('공격','스킬','파워','상태','저주')
      or c->>'card_target' is null or c->>'card_target' not in ('자신','적 1명','전체 적','무작위 적','아군 1명','전체 아군') then raise exception '카드 타입과 대상을 확인해 주세요.'; end if;
    card_id := coalesce(nullif(c->>'id','')::uuid,gen_random_uuid());
    if card_id=any(kept) then raise exception '중복된 카드 ID입니다.'; end if;
    if exists(select 1 from public.character_cards where id=card_id and character_id<>p_character_id) then raise exception '다른 캐릭터의 카드 ID는 사용할 수 없습니다.'; end if;
    kept := array_append(kept,card_id);
    insert into public.character_cards(id,character_id,card_name,card_effect,card_exhaust_effect,card_drop_effect,card_drop_count,card_retain,card_innate,card_ethereal,card_type,card_target,quantity,energy,grade,combat_rule)
    values(card_id,p_character_id,trim(c->>'card_name'),coalesce(c->>'card_effect',''),coalesce(c->>'card_exhaust_effect',''),coalesce(c->>'card_drop_effect',''),
      combat_private.num(c->'card_drop_count',0,999),coalesce((c->>'card_retain')::boolean,false),coalesce((c->>'card_innate')::boolean,false),coalesce((c->>'card_ethereal')::boolean,false),
      c->>'card_type',c->>'card_target',combat_private.num(c->'quantity',1,9999),combat_private.num(c->'energy',0,999),coalesce(c->>'grade','기본'),nullif(c->'combat_rule','null'::jsonb))
    on conflict(id) do update set
      card_name=excluded.card_name,card_effect=excluded.card_effect,card_exhaust_effect=excluded.card_exhaust_effect,
      card_drop_effect=excluded.card_drop_effect,card_drop_count=excluded.card_drop_count,card_retain=excluded.card_retain,
      card_innate=excluded.card_innate,card_ethereal=excluded.card_ethereal,card_type=excluded.card_type,card_target=excluded.card_target,
      quantity=excluded.quantity,energy=excluded.energy,grade=excluded.grade,combat_rule=excluded.combat_rule;
  end loop;
  delete from public.character_cards where character_id=p_character_id and not(id=any(kept));
  select coalesce(jsonb_agg(to_jsonb(cc) order by cc.created_at,cc.id),'[]') into saved from public.character_cards cc where cc.character_id=p_character_id;
  return saved;
end; $$;

revoke all on function combat_private.validate_card_rule(jsonb) from public,anon,authenticated;
revoke all on function combat_private.guard_card_preset() from public,anon,authenticated;
revoke all on function combat_private.import_card_presets() from public,anon,authenticated;
revoke all on function public.combat_save_character_cards(uuid,jsonb) from public,anon;
grant execute on function public.combat_save_character_cards(uuid,jsonb) to authenticated;
notify pgrst, 'reload schema';
commit;
