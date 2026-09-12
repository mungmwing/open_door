-- 수동 실행 전용. 운영 DB에 자동 적용하지 않습니다.
-- 순서: create_realtime_combat.sql → add_card_combat_presets.sql
--       → add_combat_consumables_energy.sql → 이 파일 전체 (항상 마지막).
-- 기존 데이터 일괄 변경 없음. 새 카탈로그와 컬럼, 검증·판정 함수를 추가/교체합니다.
begin;

create table if not exists public.combat_monsters (
  id uuid primary key default gen_random_uuid(),
  name text not null check(length(trim(name)) between 1 and 60),
  description text not null default '' check(length(description)<=2000),
  hp integer not null default 40 check(hp between 1 and 99999),
  attack integer not null default 6 check(attack between 0 and 999),
  guard integer not null default 5 check(guard between 0 and 999),
  powers jsonb not null default '[]', actions jsonb not null default '[]',
  created_at timestamptz not null default now()
);
alter table public.combat_monsters enable row level security;
drop policy if exists combat_monsters_read on public.combat_monsters;
create policy combat_monsters_read on public.combat_monsters for select to authenticated using(true);
drop policy if exists combat_monsters_admin on public.combat_monsters;
create policy combat_monsters_admin on public.combat_monsters for all to authenticated using(public.is_admin()) with check(public.is_admin());
revoke all on public.combat_monsters from public,anon,authenticated;
grant select,insert,update,delete on public.combat_monsters to authenticated;
alter table public.items add column if not exists relic_effects jsonb default null;
comment on column public.items.relic_effects is '보유 유물의 자동 전투 효과 [{event,effects}]. 종류별 1회 적용, 전투 시작 시 스냅샷.';

create or replace function combat_private.validate_effects(effects jsonb)
returns void language plpgsql immutable set search_path='' as $$
declare e jsonb; k text; t text; c jsonb;
begin
  if jsonb_typeof(effects) is distinct from 'array' then raise exception '카드 효과 목록이 올바르지 않습니다.'; end if;
  if jsonb_array_length(effects)>8 then raise exception '효과는 최대 8개입니다.'; end if;
  for e in select value from jsonb_array_elements(effects) loop
    k:=e->>'kind';t:=e->>'target';
    if k is null or k not in ('damage','block','heal','draw','energy','strength','weak','vulnerable','poison','personal_energy','generate_consumable','thorns','dexterity','frail','regeneration','metallicize','barricade','intangible','artifact','lose_hp','add_card','summon')
      or t is null or t not in ('self','enemy','enemies','random_enemy','ally','allies') then raise exception '지원하지 않는 카드 효과 또는 대상입니다.'; end if;
    perform combat_private.num(e->'amount',1,case when k in ('summon','generate_consumable') then 3 when k in ('draw','energy','add_card') then 10 else 999 end);
    if k in ('draw','energy','personal_energy') and t not in ('self','ally','allies') then raise exception '드로우·에너지는 아군에게만 적용할 수 있습니다.'; end if;
    if k='generate_consumable' then
      if t<>'self' or jsonb_typeof(e->'item_ids') is distinct from 'array' then raise exception '아이템 생성은 자신에게 적용하며 후보 목록이 필요합니다.'; end if;
      if jsonb_array_length(e->'item_ids') not between 1 and 30 then raise exception '생성 후보는 1~30개를 선택해 주세요.'; end if;
      if exists(select 1 from jsonb_array_elements_text(e->'item_ids') x where x is null or x !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then raise exception '생성 후보 ID를 확인해 주세요.'; end if;
      if (select count(distinct x) from jsonb_array_elements_text(e->'item_ids') x)<>jsonb_array_length(e->'item_ids') then raise exception '생성 후보는 중복할 수 없습니다.'; end if;
    elsif k='summon' then
      if t<>'self' or coalesce(e->>'monster_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception '소환할 몬스터를 선택해 주세요. 소환 대상은 자신입니다.'; end if;
    elsif k='add_card' then
      if coalesce(e->>'pile','') not in ('hand','draw','discard') then raise exception '카드를 넣을 더미를 선택해 주세요.'; end if;
      c:=e->'card';
      if jsonb_typeof(c) is distinct from 'object' or length(trim(coalesce(c->>'card_name',''))) not between 1 and 100 then raise exception '삽입 카드 이름을 확인해 주세요.'; end if;
      perform combat_private.num(c->'energy',0,10);
      perform combat_private.num(coalesce(c->'card_drop_count','0'),0,999);
      if coalesce(c->>'card_type','') not in ('공격','스킬','파워','상태','저주') or jsonb_typeof(c->'card_retain') is distinct from 'boolean' or jsonb_typeof(c->'card_innate') is distinct from 'boolean' or jsonb_typeof(c->'card_ethereal') is distinct from 'boolean' then raise exception '삽입 카드 타입·키워드를 확인해 주세요.'; end if;
      if jsonb_typeof(c->'combat_rule') is distinct from 'object' then raise exception '삽입 카드 효과를 설정해 주세요.'; end if;
      -- 재귀 생성은 한 단계에서 차단합니다. 임의 깊이의 중첩 규칙을 실행하지 않습니다.
      if exists(select 1 from jsonb_array_elements(coalesce(c->'combat_rule'->'effects','[]') || coalesce(c->'combat_rule'->'on_exhaust','[]') || coalesce(c->'combat_rule'->'on_turn_end','[]')) x where x->>'kind' in ('add_card','summon','generate_consumable')) then raise exception '삽입 카드 안에는 카드·아이템 생성이나 소환을 넣을 수 없습니다.'; end if;
      perform combat_private.validate_card_rule(c->'combat_rule');
    end if;
  end loop;
end; $$;

create or replace function combat_private.validate_card_rule(rule jsonb)
returns void language plpgsql immutable set search_path='' as $$
begin
  if rule is null then return; end if;
  if jsonb_typeof(rule) is distinct from 'object' or jsonb_typeof(rule->'playable') is distinct from 'boolean' or jsonb_typeof(rule->'exhaust') is distinct from 'boolean' then raise exception '사용 가능·소멸 설정을 확인해 주세요.'; end if;
  perform combat_private.num(coalesce(rule->'personal_cost','0'),0,999);
  perform combat_private.validate_effects(rule->'effects');
  perform combat_private.validate_effects(rule->'on_exhaust');
  perform combat_private.validate_effects(coalesce(rule->'on_turn_end','[]'));
  if exists(select 1 from jsonb_array_elements(rule->'on_exhaust' || coalesce(rule->'on_turn_end','[]')) e where e->>'target' in ('enemy','ally')) then raise exception '소멸 효과·턴 종료 효과는 자신·전체·무작위 대상을 사용해 주세요.'; end if;
  if exists(select 1 from jsonb_array_elements(rule->'effects') e where e->>'target'='enemy') and exists(select 1 from jsonb_array_elements(rule->'effects') e where e->>'target'='ally') then raise exception '한 카드의 선택 대상은 적 또는 아군 중 한 종류만 지정할 수 있습니다.'; end if;
end; $$;

create or replace function combat_private.validate_monster(m jsonb)
returns void language plpgsql immutable set search_path='' as $$
declare a jsonb;
begin
  if length(trim(coalesce(m->>'name',''))) not between 1 and 60 then raise exception '몬스터 이름은 1~60자입니다.'; end if;
  perform combat_private.num(m->'hp',1,99999);perform combat_private.num(m->'attack',0,999);perform combat_private.num(m->'guard',0,999);
  perform combat_private.validate_effects(coalesce(m->'powers','[]'));
  if exists(select 1 from jsonb_array_elements(coalesce(m->'powers','[]')) e where e->>'kind' not in ('strength','thorns','dexterity','regeneration','metallicize','barricade','intangible','artifact') or e->>'target'<>'self') then raise exception '시작 파워는 자신에게 적용하는 강화 효과입니다.'; end if;
  if jsonb_typeof(coalesce(m->'actions','[]')) is distinct from 'array' or jsonb_array_length(coalesce(m->'actions','[]'))>8 then raise exception '반복 행동은 최대 8개입니다.'; end if;
  for a in select value from jsonb_array_elements(coalesce(m->'actions','[]')) loop
    if length(trim(coalesce(a->>'name',''))) not between 1 and 60 then raise exception '행동 이름은 1~60자입니다.'; end if;
    perform combat_private.validate_effects(a->'effects');
    if exists(select 1 from jsonb_array_elements(a->'effects') e where e->>'kind' in ('draw','energy','personal_energy','generate_consumable','summon') or e->>'target'='ally' or (e->>'kind'='add_card' and e->>'target' not in ('enemy','enemies','random_enemy'))) then raise exception '몬스터 행동의 자원·소환·카드 삽입 대상을 확인해 주세요.'; end if;
  end loop;
end; $$;
create or replace function combat_private.guard_monster()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not public.is_admin() then raise exception '몬스터는 관리자만 저장할 수 있습니다.'; end if;
  perform combat_private.validate_monster(to_jsonb(new));return new;
end; $$;
drop trigger if exists combat_monster_guard on public.combat_monsters;
create trigger combat_monster_guard before insert or update on public.combat_monsters for each row execute function combat_private.guard_monster();

create or replace function combat_private.validate_relic(events jsonb)
returns void language plpgsql immutable set search_path='' as $$
declare e jsonb;
begin
  if events is null then return; end if;
  if jsonb_typeof(events) is distinct from 'array' or jsonb_array_length(events)>8 then raise exception '유물 발동 조건은 최대 8개입니다.'; end if;
  for e in select value from jsonb_array_elements(events) loop
    if coalesce(e->>'event','') not in ('battle_start','turn_start','turn_end','card_play','attack_play') then raise exception '유물 발동 시점을 확인해 주세요.'; end if;
    perform combat_private.validate_effects(e->'effects');
    if exists(select 1 from jsonb_array_elements(e->'effects') x where x->>'target' in ('enemy','ally')) then raise exception '유물은 자신·전체·무작위 대상으로 설정해 주세요.'; end if;
  end loop;
end; $$;
create or replace function combat_private.guard_relic()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.relic_effects='null'::jsonb then new.relic_effects:=null; end if;
  if new.relic_effects is not null then
    if new.item_type<>'유물' then raise exception '유물 타입에만 유물 효과를 저장할 수 있습니다.'; end if;
    if auth.uid() is null or not public.is_admin() then raise exception '유물 효과는 관리자만 저장할 수 있습니다.'; end if;
    perform combat_private.validate_relic(new.relic_effects);
  elsif tg_op='UPDATE' and old.relic_effects is not null and (auth.uid() is null or not public.is_admin()) then raise exception '유물 효과는 관리자만 변경할 수 있습니다.';
  end if;
  return new;
end; $$;
drop trigger if exists combat_relic_guard on public.items;
create trigger combat_relic_guard before insert or update on public.items for each row execute function combat_private.guard_relic();

create or replace function combat_private.monster_unit(m jsonb)
returns jsonb language plpgsql volatile set search_path='' as $$
declare u jsonb; e jsonb;
begin
  perform combat_private.validate_monster(m);
  u:=jsonb_build_object('id',gen_random_uuid(),'monster_id',m->'id','name',trim(m->>'name'),'hp',m->'hp','max_hp',m->'hp','attack',m->'attack','guard',m->'guard','actions',coalesce(m->'actions','[]'),'initial_powers',coalesce(m->'powers','[]'),'block',0,'strength',0,'weak',0,'vulnerable',0,'poison',0);
  for e in select value from jsonb_array_elements(coalesce(m->'powers','[]')) loop
    u:=jsonb_set(u,array[e->>'kind'],to_jsonb(least(9999,coalesce((u->>(e->>'kind'))::integer,0)+(e->>'amount')::integer)));
  end loop;
  return u;
end; $$;

-- 全 진영의 대상 주소를 분리하여 소환물에 손패/에너지가 생기지 않도록 합니다.
create or replace function combat_private.team_refs(s jsonb, enemy_team boolean)
returns jsonb language sql immutable set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object('side',side,'idx',ord-1,'id',u->>'id') order by rank,ord),'[]')
  from (select 'enemies' side,0 rank,value u,ordinality ord from jsonb_array_elements(coalesce(s->'enemies','[]')) with ordinality where enemy_team
    union all select 'players',0,value,ordinality from jsonb_array_elements(coalesce(s->'players','[]')) with ordinality where not enemy_team
    union all select 'summons',1,value,ordinality from jsonb_array_elements(coalesce(s->'summons','[]')) with ordinality where not enemy_team) q
  where (u->>'hp')::integer>0;
$$;

create or replace function combat_private.hit(target jsonb,amount integer,source jsonb default '{}',direct boolean default false)
returns jsonb language plpgsql immutable set search_path='' as $$
declare dealt integer:=greatest(0,amount); absorbed integer:=0; unit jsonb:=target;
begin
  if not direct then
    dealt:=greatest(0,dealt+coalesce((source->>'strength')::integer,0));
    if coalesce((source->>'weak')::integer,0)>0 then dealt:=floor(dealt*.75); end if;
    if coalesce((unit->>'vulnerable')::integer,0)>0 then dealt:=floor(dealt*1.5); end if;
  end if;
  if coalesce((unit->>'intangible')::integer,0)>0 then dealt:=least(1,dealt); end if;
  if not direct then absorbed:=least(coalesce((unit->>'block')::integer,0),dealt); end if;
  return unit || jsonb_build_object('hp',greatest(0,(unit->>'hp')::integer-dealt+absorbed),'block',coalesce((unit->>'block')::integer,0)-absorbed);
end; $$;

create or replace function combat_private.unit_start(u jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
begin
  if coalesce((u->>'barricade')::integer,0)=0 then u:=jsonb_set(u,'{block}','0'); end if;
  u:=combat_private.hit(u,coalesce((u->>'poison')::integer,0),'{}',true);
  return jsonb_set(u,'{poison}',to_jsonb(greatest(0,coalesce((u->>'poison')::integer,0)-1)));
end; $$;
create or replace function combat_private.unit_end(u jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
declare k text;
begin
  if (u->>'hp')::integer<=0 then return u; end if;
  u:=u || jsonb_build_object('hp',least((u->>'max_hp')::integer,(u->>'hp')::integer+coalesce((u->>'regeneration')::integer,0)),
    'block',least(9999,coalesce((u->>'block')::integer,0)+coalesce((u->>'metallicize')::integer,0)));
  foreach k in array array['weak','vulnerable','frail','intangible','regeneration'] loop u:=jsonb_set(u,array[k],to_jsonb(greatest(0,coalesce((u->>k)::integer,0)-1))); end loop;
  return u;
end; $$;

create or replace function combat_private.effects_from(s jsonb,source_side text,actor integer,effects jsonb,selected_target text default null)
returns jsonb language plpgsql volatile set search_path='' as $$
declare e jsonb; source jsonb; refs jsonb; ref jsonb; unit jsonb; side text; idx integer; k text; t text; amount integer; dealt integer; n integer; slot integer; item_key text; card_key text; template jsonb; card jsonb; pile text; slots jsonb; generated jsonb; summons jsonb;
begin
  for e in select value from jsonb_array_elements(effects) loop
    source:=s->source_side->actor;
    exit when coalesce((source->>'hp')::integer,0)<=0;
    k:=e->>'kind';t:=e->>'target';amount:=(e->>'amount')::integer;
    if k='summon' then
      if source_side<>'players' then continue; end if;
      template:=s->'summon_catalog'->(e->>'monster_id');
      if template is null then raise exception '소환할 몬스터 설정이 없습니다. 새 전투방에서 확인해 주세요.'; end if;
      select coalesce(jsonb_agg(value),'[]') into summons from jsonb_array_elements(coalesce(s->'summons','[]')) where (value->>'hp')::integer>0;
      for n in 1..amount loop
        if jsonb_array_length(summons)>=6 then s:=combat_private.note(s,'아군 소환 한도 6기: 초과 소환을 건너뜁니다.');exit;end if;
        unit:=combat_private.monster_unit(template) || jsonb_build_object('summoner_id',source->>'id','summoner_name',source->>'name','summoned_round',s->'round');
        summons:=summons || jsonb_build_array(unit);
        s:=combat_private.note(s,format('%s: 아군 %s 소환',source->>'name',unit->>'name'));
      end loop;
      s:=jsonb_set(s,'{summons}',summons);continue;
    end if;
    if t='self' then refs:=jsonb_build_array(jsonb_build_object('side',source_side,'idx',actor));
    else
      refs:=combat_private.team_refs(s,case when t in ('enemy','enemies','random_enemy') then source_side<>'enemies' else source_side='enemies' end);
      if t='random_enemy' then select coalesce(jsonb_build_array(value),'[]') into refs from jsonb_array_elements(refs) order by random() limit 1;
      elsif t in ('enemy','ally') then select coalesce(jsonb_agg(value),'[]') into refs from jsonb_array_elements(refs) where value->>'id'=selected_target; end if;
    end if;
    for ref in select value from jsonb_array_elements(coalesce(refs,'[]')) loop
      source:=s->source_side->actor;
      exit when (source->>'hp')::integer<=0;
      side:=ref->>'side';idx:=(ref->>'idx')::integer;unit:=s->side->idx;
      if (unit->>'hp')::integer<=0 then continue; end if;
      if k in ('draw','energy','personal_energy','generate_consumable','add_card') and side<>'players' then continue; end if;
      if k='damage' then
        dealt:=coalesce((unit->>'thorns')::integer,0);
        unit:=combat_private.hit(unit,amount,source);
        s:=jsonb_set(s,array[side,idx::text],unit);
        s:=combat_private.note(s,format('%s → %s: HP %s',source->>'name',unit->>'name',unit->>'hp'));
        if dealt>0 and (side<>source_side or idx<>actor) then
          source:=combat_private.hit(s->source_side->actor,dealt,'{}',true);
          s:=jsonb_set(s,array[source_side,actor::text],source);
          s:=combat_private.note(s,format('%s: 가시 반격 %s → %s',unit->>'name',dealt,source->>'name'));
        end if;
        continue;
      elsif k='lose_hp' then unit:=jsonb_set(unit,'{hp}',to_jsonb(greatest(0,(unit->>'hp')::integer-amount)));
      elsif k='heal' then unit:=jsonb_set(unit,'{hp}',to_jsonb(least((unit->>'max_hp')::integer,(unit->>'hp')::integer+amount)));
      elsif k='block' then
        dealt:=greatest(0,amount+coalesce((unit->>'dexterity')::integer,0));
        if coalesce((unit->>'frail')::integer,0)>0 then dealt:=floor(dealt*.75);end if;
        unit:=jsonb_set(unit,'{block}',to_jsonb(least(9999,coalesce((unit->>'block')::integer,0)+dealt)));
      elsif k='draw' then unit:=combat_private.draw(unit,amount);
      elsif k='personal_energy' then
        if coalesce(unit->'personal_config'->>'name','')<>'' then unit:=jsonb_set(unit,'{personal_energy}',to_jsonb(least((unit->'personal_config'->>'max')::integer,coalesce((unit->>'personal_energy')::integer,0)+amount))); end if;
      elsif k='add_card' then
        template:=e->'card';card_key:='generated:' || md5(template::text);
        s:=jsonb_set(s,array['rules',card_key],template->'combat_rule');
        for n in 1..amount loop
          if jsonb_array_length(unit->'cards')>=200 then s:=combat_private.note(s,format('%s: 전투 덱 200장 한도로 삽입을 건너뜁니다.',unit->>'name'));exit;end if;
          card:=jsonb_build_object('id',card_key,'instance_id',gen_random_uuid(),'card_name',template->'card_name','card_type',template->'card_type','energy',template->'energy','card_retain',template->'card_retain','card_innate',template->'card_innate','card_ethereal',template->'card_ethereal','card_drop_count',coalesce(template->'card_drop_count','0'),'card_effect',coalesce(template->'card_effect','""'),'generated',true);
          pile:=e->>'pile';if pile='hand' and jsonb_array_length(unit->'hand')>=10 then pile:='discard';end if;
          unit:=jsonb_set(unit,'{cards}',unit->'cards' || jsonb_build_array(card));
          unit:=jsonb_set(unit,array[pile],unit->pile || jsonb_build_array(card));
          if pile='draw' then select jsonb_agg(value order by random()) into slots from jsonb_array_elements(unit->'draw');unit:=jsonb_set(unit,'{draw}',slots);end if;
          s:=combat_private.note(s,format('%s: %s 삽입 (%s)',unit->>'name',card->>'card_name',pile));
        end loop;
      elsif k='generate_consumable' then
        slots:=coalesce(unit->'consumables','[null,null,null]');
        for n in 1..amount loop
          select (ord-1)::integer into slot from jsonb_array_elements(slots) with ordinality a(value,ord) where value='null'::jsonb order by ord limit 1;
          if slot is null then s:=combat_private.note(s,format('%s: 소비 아이템 슬롯이 가득 차 생성을 건너뜁니다.',unit->>'name'));exit;end if;
          select value into item_key from jsonb_array_elements_text(e->'item_ids') order by random() limit 1;
          generated:=s->'consumable_catalog'->item_key;
          if generated is null then raise exception '생성할 소비 아이템 설정이 없습니다. 새 전투방에서 확인해 주세요.';end if;
          slots:=jsonb_set(slots,array[slot::text],generated || jsonb_build_object('source','generated','instance_id',gen_random_uuid()));
          s:=combat_private.note(s,format('%s: 전투 전용 %s 생성',unit->>'name',generated->>'name'));
        end loop;
        unit:=jsonb_set(unit,'{consumables}',slots);
      elsif k in ('weak','vulnerable','poison','frail') and coalesce((unit->>'artifact')::integer,0)>0 then
        unit:=jsonb_set(unit,'{artifact}',to_jsonb((unit->>'artifact')::integer-1));
        s:=combat_private.note(s,format('%s: 인공물로 %s 차단',unit->>'name',k));
      else unit:=jsonb_set(unit,array[k],to_jsonb(least(9999,coalesce((unit->>k)::integer,0)+amount)));
      end if;
      s:=jsonb_set(s,array[side,idx::text],unit);
    end loop;
  end loop;
  return s;
end; $$;
create or replace function combat_private.effects(s jsonb,actor integer,effects jsonb,selected_target text default null)
returns jsonb language sql volatile set search_path='' as $$ select combat_private.effects_from(s,'players',actor,effects,selected_target); $$;

create or replace function combat_private.relics_for(character_id uuid)
returns jsonb language sql stable set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object('item_id',i.id,'name',i.name,'events',i.relic_effects) order by i.id),'[]')
  from public.items i where i.item_type='유물' and i.relic_effects is not null
    and exists(select 1 from public.inventory_items iv where iv.character_id=relics_for.character_id and iv.item_id=i.id and iv.quantity>0 and iv.is_equipped);
$$;
create or replace function combat_private.fire_relics(s jsonb,actor integer,event_name text)
returns jsonb language plpgsql volatile set search_path='' as $$
declare relic jsonb; e jsonb;
begin
  for relic in select value from jsonb_array_elements(coalesce(s->'players'->actor->'relics','[]')) loop
    for e in select value from jsonb_array_elements(relic->'events') where value->>'event'=event_name loop
      if (s->'players'->actor->>'hp')::integer<=0 then return s;end if;
      s:=combat_private.note(s,format('%s: 유물 %s 발동 (%s)',s->'players'->actor->>'name',relic->>'name',event_name));
      s:=combat_private.effects(s,actor,e->'effects');
    end loop;
  end loop;return s;
end; $$;

create or replace function combat_private.prepare_expansion(s jsonb)
returns jsonb language plpgsql stable set search_path='' as $$
declare i integer; relics jsonb; r jsonb; effects jsonb:='[]'; e jsonb; m jsonb; key text; monster_catalog jsonb:='{}'; consumable_catalog jsonb:=coalesce(s->'consumable_catalog','{}');
begin
  for i in 0..jsonb_array_length(s->'players')-1 loop
    relics:=combat_private.relics_for((s->'players'->i->>'id')::uuid);
    if jsonb_array_length(relics)>100 then raise exception '유물은 최대 100종까지 전투에 적용할 수 있습니다.';end if;
    s:=jsonb_set(s,array['players',i::text,'relics'],relics);
    for r in select value from jsonb_array_elements(relics) loop
      perform combat_private.validate_relic(r->'events');
      for e in select value from jsonb_array_elements(r->'events') loop effects:=effects || (e->'effects');end loop;
    end loop;
    for r in select value from jsonb_array_elements(coalesce(s->'players'->i->'consumables','[]')) where value<>'null'::jsonb loop effects:=effects || (r->'effects');end loop;
  end loop;
  for r in select value from jsonb_each(s->'rules') loop
    perform combat_private.validate_card_rule(r);
    effects:=effects || (r->'effects') || (r->'on_exhaust') || coalesce(r->'on_turn_end','[]');
  end loop;
  for key in select distinct x from jsonb_array_elements(effects) entry cross join lateral jsonb_array_elements_text(entry->'item_ids') x where entry->>'kind'='generate_consumable' loop
    r:=combat_private.item_snapshot(key);
    consumable_catalog:=jsonb_set(consumable_catalog,array[key],r);
    effects:=effects || (r->'effects');
  end loop;
  for e in select value from jsonb_array_elements(effects) where value->>'kind'='summon' loop
    select to_jsonb(monster) into m from public.combat_monsters monster where id=(e->>'monster_id')::uuid;
    if m is null then raise exception '소환할 몬스터가 삭제되었습니다. 카드·유물·아이템 설정을 확인해 주세요.';end if;
    perform combat_private.validate_monster(m);
    monster_catalog:=jsonb_set(monster_catalog,array[e->>'monster_id'],m);
  end loop;
  return s || jsonb_build_object('summon_catalog',monster_catalog,'summons','[]'::jsonb,'consumable_catalog',consumable_catalog);
end; $$;

create or replace function combat_private.end_hand(s jsonb,actor integer)
returns jsonb language plpgsql volatile set search_path='' as $$
declare p jsonb; c jsonb; rule jsonb; initial_hand jsonb; kept jsonb:='[]'; disc jsonb; gone jsonb; triggers jsonb:='[]';
begin
  initial_hand:=s->'players'->actor->'hand';
  for c in select value from jsonb_array_elements(initial_hand) loop
    s:=combat_private.effects(s,actor,coalesce(s->'rules'->(c->>'id')->'on_turn_end','[]'));
  end loop;
  p:=s->'players'->actor;disc:=p->'discard';gone:=p->'exhaust';
  -- 종료 효과로 새로 뽑거나 삽입한 카드는 다음 턴까지 보존하며 다시 종료하지 않습니다.
  for c in select value from jsonb_array_elements(p->'hand') loop
    rule:=s->'rules'->(c->>'id');
    if not exists(select 1 from jsonb_array_elements(initial_hand) x where x->>'instance_id'=c->>'instance_id') then kept:=kept || jsonb_build_array(c);
    elsif coalesce((c->>'card_ethereal')::boolean,false) then gone:=gone || jsonb_build_array(c);triggers:=triggers || coalesce(rule->'on_exhaust','[]');
    elsif coalesce((c->>'card_retain')::boolean,false) then kept:=kept || jsonb_build_array(c);
    else disc:=disc || jsonb_build_array(c);end if;
  end loop;
  p:=p || jsonb_build_object('hand',kept,'discard',disc,'exhaust',gone,'ended',true);
  s:=jsonb_set(s,array['players',actor::text],p);
  s:=combat_private.effects(s,actor,triggers);
  s:=combat_private.fire_relics(s,actor,'turn_end');
  return jsonb_set(s,array['players',actor::text],combat_private.unit_end(s->'players'->actor));
end; $$;

create or replace function combat_private.monster_act(s jsonb,side text,actor integer)
returns jsonb language plpgsql volatile set search_path='' as $$
declare u jsonb:=s->side->actor; r integer:=(s->>'round')::integer; step integer; a jsonb; refs jsonb; target text;
begin
  if (u->>'hp')::integer<=0 then return s;end if;
  refs:=combat_private.team_refs(s,side<>'enemies');
  if jsonb_array_length(refs)=0 then return s;end if;
  target:=refs->((r-1+actor)%jsonb_array_length(refs))->>'id';
  if jsonb_array_length(coalesce(u->'actions','[]'))>0 then
    step:=(r-coalesce((u->>'summoned_round')::integer,1))%jsonb_array_length(u->'actions');a:=u->'actions'->step;
  else
    step:=(r-coalesce((u->>'summoned_round')::integer,1)+actor)%3;
    a:=jsonb_build_object('name',case when step=1 then '방어' when step=2 then '강타' else '공격' end,'effects',
      jsonb_build_array(jsonb_build_object('kind',case when step=1 then 'block' else 'damage' end,'target',case when step=1 then 'self' else 'enemy' end,'amount',case when step=1 then (u->>'guard')::integer else (u->>'attack')::integer * case when step=2 then 2 else 1 end end)));
  end if;
  s:=combat_private.note(s,format('%s: %s',u->>'name',a->>'name'));
  s:=combat_private.effects_from(s,side,actor,a->'effects',target);
  return jsonb_set(s,array[side,actor::text],combat_private.unit_end(s->side->actor));
end; $$;

create or replace function combat_private.next_round(s jsonb)
returns jsonb language plpgsql volatile set search_path='' as $$
declare i integer; p jsonb; side text; round_no integer:=(s->>'round')::integer;
begin
  foreach side in array array['summons','enemies'] loop
    -- 진영 시작 효과를 먼저 전체 처리한 뒤 생존자가 순서대로 행동합니다.
    for i in 0..jsonb_array_length(coalesce(s->side,'[]'))-1 loop
      if (s->side->i->>'hp')::integer>0 then s:=jsonb_set(s,array[side,i::text],combat_private.unit_start(s->side->i));end if;
    end loop;
    if combat_private.outcome(s)<>'active' then return s;end if;
    for i in 0..jsonb_array_length(coalesce(s->side,'[]'))-1 loop
      s:=combat_private.monster_act(s,side,i);
      if combat_private.outcome(s)<>'active' then return s;end if;
    end loop;
  end loop;
  s:=jsonb_set(s,'{round}',to_jsonb(round_no+1));
  for i in 0..jsonb_array_length(s->'players')-1 loop
    p:=s->'players'->i;
    if (p->>'hp')::integer<=0 then continue;end if;
    p:=combat_private.unit_start(p) || jsonb_build_object('energy',3,'ended',false);
    if coalesce(p->'personal_config'->>'name','')<>'' then
      p:=jsonb_set(p,'{personal_energy}',to_jsonb(least((p->'personal_config'->>'max')::integer,case when (p->'personal_config'->>'reset_each_turn')::boolean then 0 else coalesce((p->>'personal_energy')::integer,0) end+(p->'personal_config'->>'per_turn')::integer)));
    end if;
    if (p->>'hp')::integer>0 then p:=combat_private.draw(p,5);end if;
    s:=jsonb_set(s,array['players',i::text],p);
  end loop;
  for i in 0..jsonb_array_length(s->'players')-1 loop s:=combat_private.fire_relics(s,i,'turn_start');end loop;
  return combat_private.note(s,format('라운드 %s · 플레이어 턴',round_no+1));
end; $$;

create or replace function public.combat_room_action(p_room_id uuid,p_version integer,p_action text,p_payload jsonb default '{}')
returns public.combat_rooms language plpgsql security definer set search_path = '' as $$
declare
  r public.combat_rooms; s jsonb; uid uuid := auth.uid(); host boolean; actor integer; i integer; j integer;
  p jsonb; c jsonb; card jsonb; rule jsonb; enemy jsonb; effects jsonb; deck jsonb; pile jsonb;
  players jsonb; enemies jsonb; char_id uuid; rule_id text; target text; side text; cost integer; resource_cost integer; slots jsonb; slot_item jsonb; slot_no integer; inv public.inventory_items; conf jsonb; item_key text; catalog jsonb;
begin
  if uid is null then raise exception '로그인이 필요합니다.'; end if;
  select * into r from public.combat_rooms where id=p_room_id for update;
  if not found then raise exception '방을 찾을 수 없습니다.'; end if;
  host := r.created_by=uid and public.is_admin(); s := r.state;
  if not host and not uid=any(r.member_ids) and p_action<>'join' then raise exception '이 방에 참가할 권한이 없습니다.'; end if;
  if p_version is null or r.version<>p_version then raise exception 'COMBAT_STALE: 다른 행동이 먼저 반영되었습니다. 최신 상태에서 다시 시도해 주세요.'; end if;
  if p_action in ('configure','rule','start','close','force_end','inject_card') and not host then raise exception '방장만 사용할 수 있는 기능입니다.'; end if;
  if p_action in ('join','leave','configure','rule','ready','start','loadout') and r.status<>'waiting' then raise exception '대기 중인 방에서만 가능합니다.'; end if;
  if p_action in ('play','end','force_end','use_item','discard_item','inject_card') and r.status<>'active' then raise exception '진행 중인 전투가 아닙니다.'; end if;
  select (ord-1)::integer into actor from jsonb_array_elements(s->'players') with ordinality a(value,ord) where value->>'owner_id'=uid::text;

  if p_action='join' then
    if uid=any(r.member_ids) then raise exception '이미 참가한 방입니다.'; end if;
    if cardinality(r.member_ids)>=6 then raise exception '최대 6명까지 참가할 수 있습니다.'; end if;
    select to_jsonb(ch) into c from public.characters ch where ch.owner_id=uid limit 1;
    if c is null then raise exception '참가할 캐릭터가 없습니다.'; end if;
    if coalesce((c->>'max_hp')::integer,0)<=0 or coalesce((c->>'hp')::integer,0)<=0 then raise exception '현재 HP와 최대 HP가 1 이상이어야 참가할 수 있습니다.'; end if;
    char_id := (c->>'id')::uuid;
    select coalesce(jsonb_agg(to_jsonb(cc) || jsonb_build_object('instance_id',cc.id::text || ':' || n) order by cc.created_at,cc.id,n),'[]') into deck
    from public.character_cards cc cross join lateral generate_series(1,least(cc.quantity,101)) n where cc.character_id=char_id;
    if jsonb_array_length(deck) not between 1 and 100 then raise exception '보유 덱은 1~100장이어야 합니다.'; end if;
    conf:=coalesce(c->'personal_energy','{}'); perform combat_private.validate_personal_energy(conf);
    p := jsonb_build_object('personal_config',conf,'personal_energy',coalesce((conf->>'initial')::integer,0),'consumables','[null,null,null]'::jsonb,'id',char_id,'owner_id',uid,'name',c->>'name','avatar_url',c->>'avatar_url',
      'max_hp',(c->>'max_hp')::integer,'hp',least((c->>'hp')::integer,(c->>'max_hp')::integer),
      'block',0,'energy',3,'strength',0,'weak',0,'vulnerable',0,'poison',0,'ready',false,'ended',false,
      'relics',combat_private.relics_for(char_id),'cards',deck,'hand','[]'::jsonb,'draw','[]'::jsonb,'discard','[]'::jsonb,'exhaust','[]'::jsonb,'powers','[]'::jsonb);
    s := jsonb_set(s,'{players}',(s->'players') || jsonb_build_array(p));
    r.member_ids := array_append(r.member_ids,uid);
    s := combat_private.note(s,format('%s 참가 · 보유 카드 %s장',p->>'name',jsonb_array_length(deck)));
  elsif p_action='loadout' then
    if actor is null then raise exception '자신의 캐릭터로 참가해 주세요.'; end if;
    if jsonb_typeof(p_payload->'inventory_ids') is distinct from 'array' or jsonb_array_length(p_payload->'inventory_ids')<>3 then raise exception '소비 아이템은 3칸입니다.'; end if;
    p:=s->'players'->actor;slots:='[]';
    for item_key in select value from jsonb_array_elements_text(p_payload->'inventory_ids') loop
      if item_key is null then slots:=slots || '[null]'::jsonb; continue; end if;
      select iv.* into inv from public.inventory_items iv where iv.id::text=item_key and iv.character_id=(p->>'id')::uuid;
      if not found or inv.quantity<(select count(*) from jsonb_array_elements_text(p_payload->'inventory_ids') x where x=item_key) then raise exception '본인이 보유한 수량 안에서 소비 아이템을 장착해 주세요.'; end if;
      slots:=slots || jsonb_build_array(combat_private.item_snapshot(inv.item_id::text) || jsonb_build_object('inventory_id',inv.id,'source','real','instance_id',gen_random_uuid()));
    end loop;
    s:=jsonb_set(s,array['players',actor::text,'consumables'],slots);
  elsif p_action='leave' then
    if actor is null then raise exception '참가 중인 캐릭터가 없습니다.'; end if;
    s := combat_private.note(s,format('%s 대기실 퇴장',s->'players'->actor->>'name'));
    s := jsonb_set(s,'{players}',(s->'players')-actor); r.member_ids := array_remove(r.member_ids,uid);
  elsif p_action='configure' then
    if jsonb_typeof(p_payload->'enemies') is distinct from 'array' then raise exception '적 설정이 올바르지 않습니다.'; end if;
    if jsonb_array_length(p_payload->'enemies') not between 1 and 6 then raise exception '적은 1~6명으로 설정해 주세요.'; end if;
    enemies := '[]';
    for enemy in select value from jsonb_array_elements(p_payload->'enemies') loop
      if coalesce(enemy->>'catalog_id','')<>'' then
        select to_jsonb(m) into c from public.combat_monsters m where m.id=(enemy->>'catalog_id')::uuid;
        if c is null then raise exception '등록된 몬스터를 찾을 수 없습니다. 목록을 새로고침해 주세요.';end if;
      else
        c:=enemy || jsonb_build_object('powers',coalesce(enemy->'initial_powers',enemy->'powers','[]'));
      end if;
      enemies:=enemies || jsonb_build_array(combat_private.monster_unit(c));
    end loop;
    s := jsonb_set(s,'{enemies}',enemies);
  elsif p_action='rule' then
    rule_id := p_payload->>'card_id'; rule := p_payload->'rule';
    if rule is null or jsonb_typeof(rule)<>'object' or not exists(select 1 from jsonb_array_elements(s->'players') pl cross join lateral jsonb_array_elements(pl->'cards') ca where ca->>'id'=rule_id) then raise exception '참가자가 보유한 카드를 선택해 주세요.'; end if;
    perform combat_private.validate_card_rule(rule);
    perform combat_private.validate_effects(rule->'effects'); perform combat_private.validate_effects(rule->'on_exhaust');
    if jsonb_typeof(rule->'playable') is distinct from 'boolean' or jsonb_typeof(rule->'exhaust') is distinct from 'boolean' then raise exception '사용·소멸 설정이 올바르지 않습니다.'; end if;
    -- 종료 소멸에는 클릭 대상이 없으므로 선택형 대상을 금지합니다.
    if exists(select 1 from jsonb_array_elements(rule->'on_exhaust') e where e->>'target' in ('enemy','ally')) then raise exception '소멸 효과는 선택 대상 대신 전체·무작위·자신 대상을 사용해 주세요.'; end if;
    if exists(select 1 from jsonb_array_elements(rule->'effects') e where e->>'target'='enemy') and exists(select 1 from jsonb_array_elements(rule->'effects') e where e->>'target'='ally') then raise exception '한 카드의 선택 대상은 적 또는 아군 한 종류만 지정할 수 있습니다.'; end if;
    s := jsonb_set(s,array['rules',rule_id],rule);
  elsif p_action='ready' then
    if actor is null then raise exception '캐릭터로 먼저 참가해 주세요.'; end if;
    s := jsonb_set(s,array['players',actor::text,'ready'],to_jsonb(not (s->'players'->actor->>'ready')::boolean));
  elsif p_action='start' then
    if jsonb_array_length(s->'players')=0 or jsonb_array_length(s->'enemies')=0 then raise exception '참가자와 적을 준비해 주세요.'; end if;
    if exists(select 1 from jsonb_array_elements(s->'players') pl where not (pl->>'ready')::boolean) then raise exception '모든 참가자가 준비 완료해야 합니다.'; end if;
    if exists(select 1 from jsonb_array_elements(s->'players') pl cross join lateral jsonb_array_elements(pl->'cards') ca where not (s->'rules') ? (ca->>'id')) then raise exception '모든 보유 카드의 전투 효과를 설정해 주세요.'; end if;
    catalog:='{}';
    for item_key in select distinct id from jsonb_each(s->'rules') rule_entry cross join lateral jsonb_array_elements((rule_entry.value->'effects') || (rule_entry.value->'on_exhaust')) ef cross join lateral jsonb_array_elements_text(coalesce(ef->'item_ids','[]')) id where ef->>'kind'='generate_consumable' loop
      catalog:=jsonb_set(catalog,array[item_key],combat_private.item_snapshot(item_key));
    end loop;
    s:=jsonb_set(s,'{consumable_catalog}',coalesce(s->'consumable_catalog','{}') || catalog);
    for i in 0..jsonb_array_length(s->'players')-1 loop
      p := s->'players'->i;
      if coalesce(p->'personal_config'->>'name','')='' and exists(select 1 from jsonb_array_elements(p->'cards') ca where coalesce((s->'rules'->(ca->>'id')->>'personal_cost')::integer,0)>0) then raise exception '전용 에너지 비용이 있는 캐릭터의 에너지 명칭을 먼저 설정해 주세요.'; end if;
      slots:=coalesce(p->'consumables','[null,null,null]');
      for slot_no in 0..2 loop
        slot_item:=slots->slot_no;if slot_item='null'::jsonb then continue; end if;
        select iv.* into inv from public.inventory_items iv where iv.id::text=slot_item->>'inventory_id' and iv.character_id=(p->>'id')::uuid and iv.item_id::text=slot_item->>'item_id';
        if not found or inv.quantity<(select count(*) from jsonb_array_elements(slots) x where x->>'inventory_id'=slot_item->>'inventory_id') then raise exception '장착한 소비 아이템 수량이 변경되었습니다. 로비에서 다시 장착해 주세요.'; end if;
        slots:=jsonb_set(slots,array[slot_no::text],slot_item || combat_private.item_snapshot(inv.item_id::text));
      end loop;
      p:=jsonb_set(p,'{consumables}',slots);
      select jsonb_agg(value order by coalesce((value->>'card_innate')::boolean,false) desc, random()) into pile from jsonb_array_elements(p->'cards');
      -- 선천이 5장보다 많으면 첫 손패를 늘리되 손패 상한 10장을 지킵니다.
      select greatest(5,count(*)::integer) into cost from jsonb_array_elements(p->'cards') ca where coalesce((ca->>'card_innate')::boolean,false);
      p := combat_private.draw(jsonb_set(p,'{draw}',pile),cost);
      s := jsonb_set(s,array['players',i::text],p);
    end loop;
    s:=combat_private.prepare_expansion(s);
    s := jsonb_set(s,'{round}','1'); r.status := 'active'; s := combat_private.note(s,'전투 시작 · 라운드 1');
    for i in 0..jsonb_array_length(s->'players')-1 loop s:=combat_private.fire_relics(s,i,'battle_start');end loop;
    for i in 0..jsonb_array_length(s->'players')-1 loop s:=combat_private.fire_relics(s,i,'turn_start');end loop;
  elsif p_action='play' then
    if actor is null then raise exception '자신의 캐릭터로만 행동할 수 있습니다.'; end if;
    p := s->'players'->actor;
    if (p->>'hp')::integer<=0 or (p->>'ended')::boolean then raise exception '현재 행동할 수 없습니다.'; end if;
    select value,(ord-1)::integer into card,j from jsonb_array_elements(p->'hand') with ordinality a(value,ord) where value->>'instance_id'=p_payload->>'instance_id';
    if card is null then raise exception '손패에 없는 카드입니다.'; end if;
    rule := s->'rules'->(card->>'id');
    if not coalesce((rule->>'playable')::boolean,false) then raise exception '사용할 수 없는 카드입니다.'; end if;
    cost := greatest(0,coalesce((card->>'energy')::integer,0));
    if cost>(p->>'energy')::integer then raise exception '에너지가 부족합니다.'; end if;
    resource_cost:=coalesce((rule->>'personal_cost')::integer,0);
    if resource_cost>coalesce((p->>'personal_energy')::integer,0) then raise exception '%이(가) 부족합니다.',coalesce(nullif(p->'personal_config'->>'name',''),'전용 에너지'); end if;
    p:=jsonb_set(p,'{personal_energy}',to_jsonb(coalesce((p->>'personal_energy')::integer,0)-resource_cost));
    effects := rule->'effects'; target := p_payload->>'target_id';
    for side in select distinct case when e->>'target'='enemy' then 'enemies' else 'players' end from jsonb_array_elements(effects) e where e->>'target' in ('enemy','ally') loop
      if not exists(select 1 from jsonb_array_elements(case when side='players' then (s->'players') || coalesce(s->'summons','[]') else s->side end) t where t->>'id'=target and (t->>'hp')::integer>0) then raise exception '살아 있는 올바른 대상을 선택해 주세요.'; end if;
    end loop;
    p := p || jsonb_build_object('energy',(p->>'energy')::integer-cost,'hand',(p->'hand')-j);
    -- 드로우 효과가 사용 중인 카드를 다시 뽑지 않도록 효과 처리 후 더미로 보냅니다.
    s := jsonb_set(s,array['players',actor::text],p);
    s := combat_private.effects(s,actor,effects,target);
    p := s->'players'->actor;
    -- 추가 드롭 개수는 사용 효과 뒤에 실행하는 추가 드로우입니다.
    -- 사용 중인 카드는 아직 어느 더미에도 없으므로 자신을 다시 뽑지 않습니다.
    if (p->>'hp')::integer>0 then
      p := combat_private.draw(p,greatest(0,least(10,coalesce((card->>'card_drop_count')::integer,0))));
      s := jsonb_set(s,array['players',actor::text],p);
    end if;
    if (rule->>'exhaust')::boolean then
      p := jsonb_set(p,'{exhaust}',(p->'exhaust') || jsonb_build_array(card)); s := jsonb_set(s,array['players',actor::text],p);
      s := combat_private.effects(s,actor,rule->'on_exhaust');
    elsif card->>'card_type'='파워' then
      -- 파워는 덱에서 제외하지만 소멸은 아니므로 on_exhaust를 발동하지 않습니다.
      p := jsonb_set(p,'{powers}',coalesce(p->'powers','[]') || jsonb_build_array(card)); s := jsonb_set(s,array['players',actor::text],p);
    else p := jsonb_set(p,'{discard}',(p->'discard') || jsonb_build_array(card)); s := jsonb_set(s,array['players',actor::text],p); end if;
    s := combat_private.note(s,format('%s: %s 사용 (-%s 에너지)',p->>'name',card->>'card_name',cost));
    s:=combat_private.fire_relics(s,actor,'card_play');
    if card->>'card_type'='공격' then s:=combat_private.fire_relics(s,actor,'attack_play');end if;
  elsif p_action='inject_card' then
    effects:=p_payload->'effect';
    if effects->>'kind' is distinct from 'add_card' or effects->>'target' is distinct from 'self' then raise exception '카드 삽입 설정을 확인해 주세요.';end if;
    perform combat_private.validate_effects(jsonb_build_array(effects));
    select (ord-1)::integer into actor from jsonb_array_elements(s->'players') with ordinality a(value,ord) where value->>'id'=p_payload->>'player_id' and (value->>'hp')::integer>0;
    if actor is null then raise exception '살아 있는 플레이어를 선택해 주세요.';end if;
    s:=combat_private.effects(s,actor,jsonb_build_array(effects));
    s:=combat_private.note(s,'방장이 전투 덱에 카드를 삽입했습니다.');
  elsif p_action in ('use_item','discard_item') then
    if actor is null then raise exception '자신의 아이템만 사용할 수 있습니다.'; end if;
    p:=s->'players'->actor;
    if (p->>'hp')::integer<=0 or (p->>'ended')::boolean then raise exception '현재 행동할 수 없습니다.'; end if;
    slot_no:=combat_private.num(p_payload->'slot',0,2);slot_item:=p->'consumables'->slot_no;
    if slot_item is null or slot_item='null'::jsonb or slot_item->>'instance_id' is distinct from p_payload->>'instance_id' then raise exception '해당 슬롯의 아이템이 변경되었습니다.'; end if;
    if p_action='discard_item' then
      if slot_item->>'source'<>'generated' then raise exception '원본 아이템은 전투 중 버릴 수 없습니다.'; end if;
    else
      effects:=slot_item->'effects'; target:=p_payload->>'target_id';perform combat_private.validate_consumable(effects);
      for side in select distinct case when e->>'target'='enemy' then 'enemies' else 'players' end from jsonb_array_elements(effects) e where e->>'target' in ('enemy','ally') loop
        if not exists(select 1 from jsonb_array_elements(case when side='players' then (s->'players') || coalesce(s->'summons','[]') else s->side end) t where t->>'id'=target and (t->>'hp')::integer>0) then raise exception '살아 있는 올바른 대상을 선택해 주세요.'; end if;
      end loop;
      if slot_item->>'source'='real' then
        if not exists(select 1 from public.inventory_items iv where iv.id::text=slot_item->>'inventory_id' and iv.character_id=(p->>'id')::uuid and iv.item_id::text=slot_item->>'item_id') then raise exception '원본 아이템이 변경되었습니다.'; end if;
        perform combat_private.consume_inventory((slot_item->>'inventory_id')::uuid,(p->>'id')::uuid,(slot_item->>'item_id')::uuid);
      elsif slot_item->>'source'<>'generated' then raise exception '잘못된 아이템 출처입니다.'; end if;
    end if;
    s:=jsonb_set(s,array['players',actor::text,'consumables',slot_no::text],'null');
    if p_action='use_item' then s:=combat_private.effects(s,actor,effects,target); end if;
    s:=combat_private.note(s,format('%s: %s %s (%s)',p->>'name',slot_item->>'name',case when p_action='use_item' then '사용' else '버림' end,case when slot_item->>'source'='real' then '원본 1개 소모' else '전투 전용' end));
  elsif p_action in ('end','force_end') then
    if p_action='force_end' then select (ord-1)::integer into actor from jsonb_array_elements(s->'players') with ordinality a(value,ord) where value->>'id'=p_payload->>'player_id'; end if;
    if actor is null then raise exception '턴을 종료할 참가자가 없습니다.'; end if;
    p := s->'players'->actor;
    if (p->>'hp')::integer<=0 or (p->>'ended')::boolean then raise exception '이미 종료했거나 쓰러진 참가자입니다.'; end if;
    s := combat_private.end_hand(s,actor);
    s := combat_private.note(s,format('%s 턴 종료%s',p->>'name',case when p_action='force_end' then ' (방장)' else '' end));
  elsif p_action='close' then
    if r.status not in ('waiting','active') then raise exception '이미 종료된 방입니다.'; end if;
    r.status := 'closed'; s := combat_private.note(s,'방장이 전투를 종료했습니다.');
  else raise exception '지원하지 않는 전투 명령입니다.';
  end if;

  if p_action in ('configure','rule','join','leave','loadout') then
    select coalesce(jsonb_agg(value || '{"ready":false}'::jsonb order by ord),'[]') into players from jsonb_array_elements(s->'players') with ordinality a(value,ord);
    s := jsonb_set(s,'{players}',players);
  end if;
  if r.status='active' then
    r.status := combat_private.outcome(s);
    if r.status='active' and not exists(select 1 from jsonb_array_elements(s->'players') pl where (pl->>'hp')::integer>0 and not (pl->>'ended')::boolean) then
      s := combat_private.next_round(s); r.status := combat_private.outcome(s);
    end if;
    if r.status in ('victory','defeat') then s := combat_private.note(s,case when r.status='victory' then '승리 · 모든 적을 쓰러뜨렸습니다.' else '패배 · 파티가 모두 쓰러졌습니다.' end); end if;
  end if;
  update public.combat_rooms set state=s,status=r.status,member_ids=r.member_ids,version=version+1,updated_at=clock_timestamp() where id=r.id returning * into r;
  return r;
end; $$;


revoke all on all functions in schema combat_private from public,anon,authenticated;
revoke all on function public.combat_room_action(uuid,integer,text,jsonb) from public,anon;
grant execute on function public.combat_room_action(uuid,integer,text,jsonb) to authenticated;
notify pgrst, 'reload schema';
commit;
