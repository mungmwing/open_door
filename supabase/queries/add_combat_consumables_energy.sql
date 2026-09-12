-- 수동 적용 전용. create_realtime_combat.sql, add_card_combat_presets.sql 이후 전체 실행.
-- 최신 키워드 수정도 포함합니다. 운영 DB에는 자동 실행하지 않습니다.
begin;

alter table public.characters add column if not exists personal_energy jsonb not null default '{}',
  add column if not exists inventory_version bigint not null default 0;
alter table public.items add column if not exists combat_effects jsonb default null;

create table if not exists combat_private.inventory_spend_permits (
  inventory_id uuid primary key, transaction_id bigint not null, previous_quantity integer not null
);
revoke all on combat_private.inventory_spend_permits from public,anon,authenticated;

create or replace function combat_private.validate_personal_energy(config jsonb)
returns void language plpgsql immutable set search_path='' as $$
declare cap integer;
begin
  if jsonb_typeof(config) is distinct from 'object' then raise exception '전용 에너지 설정을 확인해 주세요.'; end if;
  if coalesce(trim(config->>'name'),'')='' then return; end if;
  if jsonb_typeof(config->'name') is distinct from 'string' then raise exception '전용 에너지 명칭을 입력해 주세요.'; end if;
  if length(trim(config->>'name'))>30 then raise exception '전용 에너지 명칭은 30자까지입니다.'; end if;
  cap := combat_private.num(config->'max',1,999);
  perform combat_private.num(config->'initial',0,cap);
  perform combat_private.num(config->'per_turn',0,cap);
  if jsonb_typeof(config->'reset_each_turn') is distinct from 'boolean' then raise exception '전용 에너지 턴 설정을 확인해 주세요.'; end if;
end; $$;

create or replace function combat_private.guard_character_energy()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='UPDATE' and new.inventory_version is distinct from old.inventory_version and pg_trigger_depth()=1 and not public.is_admin() then
    raise exception '인벤토리 버전은 직접 변경할 수 없습니다.';
  end if;
  if (tg_op='INSERT' and new.personal_energy<>'{}') or (tg_op='UPDATE' and new.personal_energy is distinct from old.personal_energy) then
    if auth.uid() is null or not public.is_admin() then raise exception '전용 에너지 설정은 관리자만 변경할 수 있습니다.'; end if;
    perform combat_private.validate_personal_energy(new.personal_energy);
    if coalesce(trim(new.personal_energy->>'name'),'')='' then new.personal_energy:='{}'; end if;
  end if;
  return new;
end; $$;
drop trigger if exists combat_character_energy_guard on public.characters;
create trigger combat_character_energy_guard before insert or update of personal_energy,inventory_version on public.characters
for each row execute function combat_private.guard_character_energy();

create or replace function combat_private.inventory_version_changed()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='DELETE' then update public.characters set inventory_version=inventory_version+1 where id=old.character_id; return old; end if;
  update public.characters set inventory_version=inventory_version+1 where id=new.character_id;
  if tg_op='UPDATE' and new.character_id<>old.character_id then update public.characters set inventory_version=inventory_version+1 where id=old.character_id; end if;
  return new;
end; $$;
drop trigger if exists combat_inventory_version_changed on public.inventory_items;
create trigger combat_inventory_version_changed after insert or update or delete on public.inventory_items
for each row execute function combat_private.inventory_version_changed();

-- 일반 플레이어의 직접 수량 변경은 계속 거부합니다. 소비 RPC가 만든 현재 트랜잭션의
-- 비공개 허가가 있을 때만 정확히 1개 차감을 허용합니다. 클라이언트 GUC를 신뢰하지 않습니다.
create or replace function public.prevent_player_inventory_edits()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if not public.is_admin() and (to_jsonb(new)-'is_equipped') is distinct from (to_jsonb(old)-'is_equipped') then
    if new.quantity=old.quantity-1 and (to_jsonb(new)-'quantity')=(to_jsonb(old)-'quantity')
      and exists(select 1 from combat_private.inventory_spend_permits where inventory_id=old.id and transaction_id=txid_current() and previous_quantity=old.quantity) then return new; end if;
    raise exception '플레이어는 장착 상태만 변경할 수 있습니다.';
  end if;
  return new;
end; $$;
drop trigger if exists prevent_player_inventory_edits on public.inventory_items;
create trigger prevent_player_inventory_edits before update on public.inventory_items for each row execute function public.prevent_player_inventory_edits();

create or replace function combat_private.consume_inventory(inv_id uuid,character_id uuid,expected_item uuid)
returns void language plpgsql security definer set search_path='' as $$
declare inv public.inventory_items;
begin
  perform 1 from public.characters where id=character_id for update;
  select * into inv from public.inventory_items where id=inv_id and inventory_items.character_id=consume_inventory.character_id for update;
  if not found or inv.quantity<1 or inv.item_id is distinct from expected_item then raise exception '원본 아이템 수량이 부족합니다. 인벤토리를 확인해 주세요.'; end if;
  if inv.quantity=1 then delete from public.inventory_items where id=inv.id;
  else
    insert into combat_private.inventory_spend_permits values(inv.id,txid_current(),inv.quantity);
    update public.inventory_items set quantity=quantity-1 where id=inv.id;
    delete from combat_private.inventory_spend_permits where inventory_id=inv.id;
  end if;
end; $$;

create or replace function public.combat_available_consumables()
returns jsonb language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object('inventory_id',iv.id,'item_id',it.id,'name',it.name,'quantity',iv.quantity,'icon_url',it.icon_url,'effects',it.combat_effects) order by it.name,iv.id),'[]')
  from public.inventory_items iv join public.characters ch on ch.id=iv.character_id join public.items it on it.id=iv.item_id
  where ch.owner_id=auth.uid() and it.item_type='소비' and iv.quantity>0;
$$;

create or replace function public.combat_save_inventory(p_character_id uuid,p_expected_version bigint,p_items jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare v bigint; c jsonb; ident uuid; kept uuid[]:='{}';
begin
  if auth.uid() is null or not public.is_admin() then raise exception '관리자만 인벤토리를 저장할 수 있습니다.'; end if;
  select inventory_version into v from public.characters where id=p_character_id for update;
  if not found then raise exception '캐릭터가 없습니다.'; end if;
  if p_expected_version is null or v<>p_expected_version then raise exception '아이템이 사용되거나 인벤토리가 변경되었습니다. 새로 불러온 뒤 저장해 주세요.'; end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)>500 then raise exception '인벤토리 목록을 확인해 주세요.'; end if;
  for c in select value from jsonb_array_elements(p_items) loop
    ident:=coalesce(nullif(c->>'id','')::uuid,gen_random_uuid());
    if ident=any(kept) or exists(select 1 from public.inventory_items where id=ident and character_id<>p_character_id) then raise exception '올바르지 않은 인벤토리 ID입니다.'; end if;
    kept:=array_append(kept,ident);
    insert into public.inventory_items(id,character_id,item_id,item_name,item_effect,item_description,quantity,grade,item_type,icon_url,is_equipped)
    values(ident,p_character_id,nullif(c->>'item_id','')::uuid,c->>'item_name',coalesce(c->>'item_effect',''),coalesce(c->>'item_description',''),combat_private.num(c->'quantity',1,99999),c->>'grade',c->>'item_type',c->>'icon_url',coalesce((c->>'is_equipped')::boolean,false))
    on conflict(id) do update set item_id=excluded.item_id,item_name=excluded.item_name,item_effect=excluded.item_effect,item_description=excluded.item_description,quantity=excluded.quantity,grade=excluded.grade,item_type=excluded.item_type,icon_url=excluded.icon_url,is_equipped=excluded.is_equipped;
  end loop;
  delete from public.inventory_items where character_id=p_character_id and not(id=any(kept));
end; $$;

create or replace function combat_private.validate_consumable(effects jsonb)
returns void language plpgsql stable set search_path='' as $$
begin
  perform combat_private.validate_effects(effects);
  if exists(select 1 from jsonb_array_elements(effects) e where e->>'kind'='generate_consumable') then raise exception '소비 아이템은 다른 아이템을 생성할 수 없습니다.'; end if;
  if exists(select 1 from jsonb_array_elements(effects) e where e->>'target'='enemy') and exists(select 1 from jsonb_array_elements(effects) e where e->>'target'='ally') then raise exception '소비 아이템의 선택 대상은 적 또는 아군 한 종류만 가능합니다.'; end if;
end; $$;
create or replace function combat_private.guard_consumable_effects()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.combat_effects='null'::jsonb then new.combat_effects:=null; end if;
  if new.combat_effects is not null then
    if auth.uid() is null or not public.is_admin() then raise exception '소비 아이템 효과는 관리자만 설정할 수 있습니다.'; end if;
    if new.item_type<>'소비' then raise exception '소비 아이템에만 전투 효과를 설정할 수 있습니다.'; end if;
    perform combat_private.validate_consumable(new.combat_effects);
  end if;
  return new;
end; $$;
drop trigger if exists combat_item_effects_guard on public.items;
create trigger combat_item_effects_guard before insert or update on public.items for each row execute function combat_private.guard_consumable_effects();

-- 전투 참가/시작 시 서버의 캐릭터 설정·아이템 효과만 복사합니다.
create or replace function combat_private.item_snapshot(item_id text)
returns jsonb language plpgsql stable set search_path='' as $$
declare item public.items;
begin
  select * into item from public.items where id=item_id::uuid and item_type='소비';
  if not found or item.combat_effects is null then raise exception '소비 아이템의 전투 효과를 먼저 설정해 주세요.'; end if;
  perform combat_private.validate_consumable(item.combat_effects);
  return jsonb_build_object('item_id',item.id,'name',item.name,'icon_url',item.icon_url,'effects',item.combat_effects);
end; $$;

create or replace function combat_private.validate_effects(effects jsonb)
returns void language plpgsql immutable set search_path = '' as $$
declare e jsonb; k text; t text;
begin
  if jsonb_typeof(effects) is distinct from 'array' then raise exception '카드 효과 목록이 올바르지 않습니다.'; end if;
  if jsonb_array_length(effects)>8 then raise exception '효과는 최대 8개입니다.'; end if;
  for e in select value from jsonb_array_elements(effects) loop
    k := e->>'kind'; t := e->>'target';
    if k is null or k not in ('damage','block','heal','draw','energy','strength','weak','vulnerable','poison','personal_energy','generate_consumable')
      or t is null or t not in ('self','enemy','enemies','random_enemy','ally','allies') then
      raise exception '지원하지 않는 카드 효과 또는 대상입니다.';
    end if;
    perform combat_private.num(e->'amount',1,case when k='generate_consumable' then 3 when k in ('draw','energy') then 10 else 999 end);
    if k in ('draw','energy','personal_energy') and t not in ('self','ally','allies') then raise exception '드로우·에너지는 아군에게만 적용할 수 있습니다.'; end if;
    if k='generate_consumable' then
      if t<>'self' or jsonb_typeof(e->'item_ids') is distinct from 'array' then raise exception '아이템 생성은 자신에게 적용하며 후보 목록이 필요합니다.'; end if;
      if jsonb_array_length(e->'item_ids') not between 1 and 30 then raise exception '생성 후보는 1~30개를 선택해 주세요.'; end if;
      if exists(select 1 from jsonb_array_elements_text(e->'item_ids') x where x !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then raise exception '생성 후보 ID를 확인해 주세요.'; end if;
      if (select count(distinct x) from jsonb_array_elements_text(e->'item_ids') x)<>jsonb_array_length(e->'item_ids') then raise exception '생성 후보는 중복할 수 없습니다.'; end if;
    end if;
  end loop;
end; $$;

create or replace function combat_private.effects(s jsonb, actor integer, effects jsonb, selected_target text default null)
returns jsonb language plpgsql volatile set search_path = '' as $$
declare e jsonb; side text; indices integer[]; idx integer; unit jsonb; source jsonb; amount integer; k text; t text; slot integer; item_key text; generated jsonb; slots jsonb; n integer;
begin
  for e in select value from jsonb_array_elements(effects) loop
    source := s->'players'->actor; k := e->>'kind'; t := e->>'target'; amount := (e->>'amount')::integer;
    side := case when t in ('enemy','enemies','random_enemy') then 'enemies' else 'players' end;
    if t='self' then indices := array[actor];
    elsif t='random_enemy' then
      select array[(ord-1)::integer] into indices from jsonb_array_elements(s->side) with ordinality a(value,ord)
      where (value->>'hp')::integer>0 order by random() limit 1;
    else
      select array_agg((ord-1)::integer) into indices from jsonb_array_elements(s->side) with ordinality a(value,ord)
      where (value->>'hp')::integer>0 and (t in ('enemies','allies') or value->>'id'=selected_target);
    end if;
    if indices is null and t in ('enemy','ally') then
      -- 앞선 효과로 선택 대상이 죽었으면 후속 효과는 건너뜁니다. 최초 대상 검증은 RPC에서 수행합니다.
      continue;
    end if;
    foreach idx in array coalesce(indices,'{}'::integer[]) loop
      unit := s->side->idx;
      if (unit->>'hp')::integer<=0 then continue; end if;
      if k='damage' then unit := combat_private.hit(unit,amount,source);
      elsif k='heal' then unit := jsonb_set(unit,'{hp}',to_jsonb(least((unit->>'max_hp')::integer,(unit->>'hp')::integer+amount)));
      elsif k='draw' then unit := combat_private.draw(unit,amount);
      elsif k='personal_energy' then
        if coalesce(unit->'personal_config'->>'name','')<>'' then unit := jsonb_set(unit,'{personal_energy}',to_jsonb(least((unit->'personal_config'->>'max')::integer,coalesce((unit->>'personal_energy')::integer,0)+amount))); end if;
      elsif k='generate_consumable' then
        slots:=coalesce(unit->'consumables','[null,null,null]');
        for n in 1..amount loop
          select (ord-1)::integer into slot from jsonb_array_elements(slots) with ordinality a(value,ord) where value='null'::jsonb order by ord limit 1;
          if slot is null then s:=combat_private.note(s,format('%s: 소비 아이템 슬롯이 가득 차 생성을 건너뜁니다.',unit->>'name')); exit; end if;
          select value into item_key from jsonb_array_elements_text(e->'item_ids') order by random() limit 1;
          generated:=s->'consumable_catalog'->item_key;
          if generated is null then raise exception '생성할 소비 아이템 설정이 없습니다. 새 전투방에서 확인해 주세요.'; end if;
          slots:=jsonb_set(slots,array[slot::text],generated || jsonb_build_object('source','generated','instance_id',gen_random_uuid()));
          s:=combat_private.note(s,format('%s: 전투 전용 %s 생성',unit->>'name',generated->>'name'));
        end loop;
        unit:=jsonb_set(unit,'{consumables}',slots);
      else unit := jsonb_set(unit,array[k],to_jsonb(least(9999,coalesce((unit->>k)::integer,0)+amount)));
      end if;
      s := jsonb_set(s,array[side,idx::text],unit);
    end loop;
  end loop;
  return s;
end; $$;

create or replace function combat_private.next_round(s jsonb)
returns jsonb language plpgsql volatile set search_path = '' as $$
declare i integer; p jsonb; enemy jsonb; living integer[]; target integer; round_no integer := (s->>'round')::integer; attack integer; intent integer;
begin
  -- 적 진영 시작: 방어도 제거, 중독 피해.
  for i in 0..jsonb_array_length(s->'enemies')-1 loop
    enemy := s->'enemies'->i;
    if (enemy->>'hp')::integer<=0 then continue; end if;
    enemy := jsonb_set(enemy,'{block}','0');
    enemy := combat_private.hit(enemy,(enemy->>'poison')::integer,'{}',true);
    enemy := jsonb_set(enemy,'{poison}',to_jsonb(greatest(0,(enemy->>'poison')::integer-1)));
    s := jsonb_set(s,array['enemies',i::text],enemy);
  end loop;
  if combat_private.outcome(s)<>'active' then return s; end if;
  for i in 0..jsonb_array_length(s->'enemies')-1 loop
    enemy := s->'enemies'->i;
    if (enemy->>'hp')::integer<=0 then continue; end if;
    intent := (round_no-1+i)%3;
    if intent=1 then
      enemy := jsonb_set(enemy,'{block}',enemy->'guard');
      s := combat_private.note(s,format('%s: 방어도 %s',enemy->>'name',enemy->>'guard'));
    else
      select array_agg((ord-1)::integer order by ord) into living from jsonb_array_elements(s->'players') with ordinality a(value,ord) where (value->>'hp')::integer>0;
      exit when living is null;
      target := living[1+(round_no-1+i)%cardinality(living)];
      attack := (enemy->>'attack')::integer * case when intent=2 then 2 else 1 end;
      p := s->'players'->target;
      s := jsonb_set(s,array['players',target::text],combat_private.hit(p,attack,enemy));
      s := combat_private.note(s,format('%s → %s: HP %s → %s',enemy->>'name',p->>'name',p->>'hp',s->'players'->target->>'hp'));
    end if;
    enemy := enemy || jsonb_build_object('weak',greatest(0,(enemy->>'weak')::integer-1),'vulnerable',greatest(0,(enemy->>'vulnerable')::integer-1));
    s := jsonb_set(s,array['enemies',i::text],enemy);
  end loop;
  if combat_private.outcome(s)<>'active' then return s; end if;
  s := jsonb_set(s,'{round}',to_jsonb(round_no+1));
  for i in 0..jsonb_array_length(s->'players')-1 loop
    p := s->'players'->i;
    if (p->>'hp')::integer<=0 then continue; end if;
    p := p || jsonb_build_object('block',0,'energy',3,'ended',false);
    if coalesce(p->'personal_config'->>'name','')<>'' then
      p:=jsonb_set(p,'{personal_energy}',to_jsonb(least((p->'personal_config'->>'max')::integer,
        case when (p->'personal_config'->>'reset_each_turn')::boolean then 0 else coalesce((p->>'personal_energy')::integer,0) end + (p->'personal_config'->>'per_turn')::integer)));
    end if;
    p := combat_private.hit(p,(p->>'poison')::integer,'{}',true);
    p := jsonb_set(p,'{poison}',to_jsonb(greatest(0,(p->>'poison')::integer-1)));
    if (p->>'hp')::integer>0 then p := combat_private.draw(p,5); end if;
    s := jsonb_set(s,array['players',i::text],p);
  end loop;
  return combat_private.note(s,format('라운드 %s · 플레이어 턴',round_no+1));
end; $$;

create or replace function combat_private.validate_card_rule(rule jsonb)
returns void language plpgsql immutable set search_path = '' as $$
begin
  if rule is null then return; end if;
  if jsonb_typeof(rule) is distinct from 'object'
    or jsonb_typeof(rule->'playable') is distinct from 'boolean'
    or jsonb_typeof(rule->'exhaust') is distinct from 'boolean' then
    raise exception '사용 가능·소멸 설정을 확인해 주세요.';
  end if;
  perform combat_private.num(coalesce(rule->'personal_cost','0'),0,999);
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
  if p_action in ('configure','rule','start','close','force_end') and not host then raise exception '방장만 사용할 수 있는 기능입니다.'; end if;
  if p_action in ('join','leave','configure','rule','ready','start','loadout') and r.status<>'waiting' then raise exception '대기 중인 방에서만 가능합니다.'; end if;
  if p_action in ('play','end','force_end','use_item','discard_item') and r.status<>'active' then raise exception '진행 중인 전투가 아닙니다.'; end if;
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
      'cards',deck,'hand','[]'::jsonb,'draw','[]'::jsonb,'discard','[]'::jsonb,'exhaust','[]'::jsonb,'powers','[]'::jsonb);
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
      if enemy->>'name' is null or length(trim(enemy->>'name')) not between 1 and 60 then raise exception '적 이름은 1~60자로 입력해 주세요.'; end if;
      enemies := enemies || jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'name',trim(enemy->>'name'),
        'hp',combat_private.num(enemy->'hp',1,99999),'max_hp',combat_private.num(enemy->'hp',1,99999),
        'attack',combat_private.num(enemy->'attack',0,999),'guard',combat_private.num(enemy->'guard',0,999),
        'block',0,'strength',0,'weak',0,'vulnerable',0,'poison',0));
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
    s:=jsonb_set(s,'{consumable_catalog}',catalog);
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
    s := jsonb_set(s,'{round}','1'); r.status := 'active'; s := combat_private.note(s,'전투 시작 · 라운드 1');
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
      if not exists(select 1 from jsonb_array_elements(s->side) t where t->>'id'=target and (t->>'hp')::integer>0) then raise exception '살아 있는 올바른 대상을 선택해 주세요.'; end if;
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
        if not exists(select 1 from jsonb_array_elements(s->side) t where t->>'id'=target and (t->>'hp')::integer>0) then raise exception '살아 있는 올바른 대상을 선택해 주세요.'; end if;
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
revoke all on function public.combat_available_consumables() from public,anon;
grant execute on function public.combat_available_consumables() to authenticated;
revoke all on function public.combat_save_inventory(uuid,bigint,jsonb) from public,anon;
grant execute on function public.combat_save_inventory(uuid,bigint,jsonb) to authenticated;
revoke all on function public.combat_room_action(uuid,integer,text,jsonb) from public,anon;
grant execute on function public.combat_room_action(uuid,integer,text,jsonb) to authenticated;
notify pgrst, 'reload schema';
commit;
