-- 직접 실행하지 않은 수동 적용 쿼리입니다. Supabase SQL Editor에서 전체 실행하세요.
-- 전제: profiles, characters, character_cards, public.is_admin() (기존 TRPG 스키마).
-- 원본 캐릭터/카드 테이블은 변경하지 않습니다. 모든 전투는 별도 스냅샷에서 처리합니다.
begin;

create schema if not exists combat_private;
revoke all on schema combat_private from public, anon, authenticated;

create table if not exists public.combat_rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(name) between 1 and 80),
  created_by uuid not null references auth.users(id),
  member_ids uuid[] not null default '{}',
  status text not null default 'waiting' check (status in ('waiting','active','victory','defeat','closed')),
  version integer not null default 0,
  state jsonb not null default '{"players":[],"enemies":[],"rules":{},"log":[],"round":0}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists combat_rooms_updated_idx on public.combat_rooms(updated_at desc);
alter table public.combat_rooms enable row level security;
revoke all on public.combat_rooms from anon, authenticated;
grant select on public.combat_rooms to authenticated;
drop policy if exists combat_room_read on public.combat_rooms;
create policy combat_room_read on public.combat_rooms for select to authenticated
using (created_by = (select auth.uid()) or (select auth.uid()) = any(member_ids));

-- 아래 도우미는 API에 노출하지 않으며 공개 RPC에서만 호출합니다.
create or replace function combat_private.num(v jsonb, lo integer, hi integer)
returns integer language plpgsql immutable set search_path = '' as $$
declare n numeric;
begin
  if v is null or jsonb_typeof(v) <> 'number' then raise exception '숫자 설정을 확인해 주세요.'; end if;
  n := v::text::numeric;
  if n <> trunc(n) or n < lo or n > hi then raise exception '숫자 설정 범위를 확인해 주세요. (%~%)', lo, hi; end if;
  return n::integer;
end; $$;

create or replace function combat_private.note(s jsonb, message text)
returns jsonb language sql set search_path = '' as $$
  select jsonb_set(s, '{log}', coalesce((select jsonb_agg(value order by ord)
    from jsonb_array_elements(coalesce(s->'log','[]') || jsonb_build_array(message)) with ordinality a(value,ord)
    where ord > greatest(0,jsonb_array_length(coalesce(s->'log','[]')) + 1 - 100)), '[]'));
$$;

create or replace function combat_private.shuffle(pile jsonb)
returns jsonb language sql volatile set search_path = '' as $$
  select coalesce(jsonb_agg(value order by random()),'[]') from jsonb_array_elements(pile);
$$;

create or replace function combat_private.draw(p jsonb, n integer)
returns jsonb language plpgsql volatile set search_path = '' as $$
declare hand jsonb := p->'hand'; pile jsonb := p->'draw'; disc jsonb := p->'discard'; i integer;
begin
  for i in 1..least(n,10) loop
    exit when jsonb_array_length(hand) >= 10;
    if jsonb_array_length(pile) = 0 then pile := combat_private.shuffle(disc); disc := '[]'; end if;
    exit when jsonb_array_length(pile) = 0;
    hand := hand || jsonb_build_array(pile->0); pile := pile - 0;
  end loop;
  return p || jsonb_build_object('hand',hand,'draw',pile,'discard',disc);
end; $$;

create or replace function combat_private.hit(target jsonb, amount integer, source jsonb default '{}', direct boolean default false)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare damage integer := amount; shield integer := coalesce((target->>'block')::integer,0);
begin
  if not direct then
    damage := greatest(0,damage + coalesce((source->>'strength')::integer,0));
    if coalesce((source->>'weak')::integer,0)>0 then damage := floor(damage * 0.75); end if;
    if coalesce((target->>'vulnerable')::integer,0)>0 then damage := floor(damage * 1.5); end if;
    target := jsonb_set(target,'{block}',to_jsonb(greatest(0,shield-damage)));
    damage := greatest(0,damage-shield);
  end if;
  return jsonb_set(target,'{hp}',to_jsonb(greatest(0,(target->>'hp')::integer-damage)));
end; $$;

create or replace function combat_private.validate_effects(effects jsonb)
returns void language plpgsql immutable set search_path = '' as $$
declare e jsonb; k text; t text;
begin
  if jsonb_typeof(effects) is distinct from 'array' then raise exception '카드 효과 목록이 올바르지 않습니다.'; end if;
  if jsonb_array_length(effects)>8 then raise exception '효과는 최대 8개입니다.'; end if;
  for e in select value from jsonb_array_elements(effects) loop
    k := e->>'kind'; t := e->>'target';
    if k is null or k not in ('damage','block','heal','draw','energy','strength','weak','vulnerable','poison')
      or t is null or t not in ('self','enemy','enemies','random_enemy','ally','allies') then
      raise exception '지원하지 않는 카드 효과 또는 대상입니다.';
    end if;
    perform combat_private.num(e->'amount',1,case when k in ('draw','energy') then 10 else 999 end);
    if k in ('draw','energy') and t not in ('self','ally','allies') then raise exception '드로우·에너지는 아군에게만 적용할 수 있습니다.'; end if;
  end loop;
end; $$;

create or replace function combat_private.effects(s jsonb, actor integer, effects jsonb, selected_target text default null)
returns jsonb language plpgsql volatile set search_path = '' as $$
declare e jsonb; side text; indices integer[]; idx integer; unit jsonb; source jsonb; amount integer; k text; t text;
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
      else unit := jsonb_set(unit,array[k],to_jsonb(least(9999,coalesce((unit->>k)::integer,0)+amount)));
      end if;
      s := jsonb_set(s,array[side,idx::text],unit);
    end loop;
  end loop;
  return s;
end; $$;

create or replace function combat_private.outcome(s jsonb)
returns text language sql immutable set search_path = '' as $$
  select case
    when not exists(select 1 from jsonb_array_elements(s->'enemies') e where (e->>'hp')::integer>0) then 'victory'
    when not exists(select 1 from jsonb_array_elements(s->'players') p where (p->>'hp')::integer>0) then 'defeat'
    else 'active' end;
$$;

create or replace function combat_private.end_hand(s jsonb, actor integer)
returns jsonb language plpgsql volatile set search_path = '' as $$
declare p jsonb := s->'players'->actor; c jsonb; r jsonb; kept jsonb := '[]'; disc jsonb := p->'discard'; gone jsonb := p->'exhaust'; triggers jsonb := '[]';
begin
  for c in select value from jsonb_array_elements(p->'hand') loop
    r := s->'rules'->(c->>'id');
    if coalesce((c->>'card_ethereal')::boolean,false) then
      gone := gone || jsonb_build_array(c); triggers := triggers || coalesce(r->'on_exhaust','[]');
    elsif coalesce((c->>'card_retain')::boolean,false) then kept := kept || jsonb_build_array(c);
    else disc := disc || jsonb_build_array(c); end if;
  end loop;
  p := p || jsonb_build_object('hand',kept,'discard',disc,'exhaust',gone,'ended',true);
  s := jsonb_set(s,array['players',actor::text],p);
  s := combat_private.effects(s,actor,triggers);
  p := s->'players'->actor;
  -- 종료 시 소멸 효과로 뽑은 카드는 다시 종료 처리하지 않으며 다음 턴까지 남습니다.
  p := p || jsonb_build_object('weak',greatest(0,(p->>'weak')::integer-1),'vulnerable',greatest(0,(p->>'vulnerable')::integer-1));
  return jsonb_set(s,array['players',actor::text],p);
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
    p := combat_private.hit(p,(p->>'poison')::integer,'{}',true);
    p := jsonb_set(p,'{poison}',to_jsonb(greatest(0,(p->>'poison')::integer-1)));
    if (p->>'hp')::integer>0 then p := combat_private.draw(p,5); end if;
    s := jsonb_set(s,array['players',i::text],p);
  end loop;
  return combat_private.note(s,format('라운드 %s · 플레이어 턴',round_no+1));
end; $$;

create or replace function public.combat_list_rooms()
returns table(id uuid,name text,status text,player_count integer,created_by uuid,is_member boolean,updated_at timestamptz,version integer)
language sql stable security definer set search_path = '' as $$
  select r.id,r.name,r.status,cardinality(r.member_ids),r.created_by,
    auth.uid()=any(r.member_ids),r.updated_at,r.version
  from public.combat_rooms r
  where auth.uid() is not null and (r.status in ('waiting','active') or r.created_by=auth.uid() or auth.uid()=any(r.member_ids))
  order by r.updated_at desc limit 100;
$$;

create or replace function public.combat_create_room(p_name text)
returns public.combat_rooms language plpgsql security definer set search_path = '' as $$
declare r public.combat_rooms;
begin
  if auth.uid() is null or not public.is_admin() then raise exception '관리자만 방을 만들 수 있습니다.'; end if;
  if p_name is null or length(trim(p_name)) not between 1 and 80 then raise exception '방 이름은 1~80자로 입력해 주세요.'; end if;
  insert into public.combat_rooms(name,created_by) values(trim(p_name),auth.uid()) returning * into r;
  return r;
end; $$;

create or replace function public.combat_delete_room(p_room_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_status text;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  if not public.is_admin() then raise exception '관리자만 전투 기록을 삭제할 수 있습니다.'; end if;

  select r.status into v_status
  from public.combat_rooms r
  where r.id = p_room_id and r.created_by = auth.uid()
  for update;

  if not found then raise exception '전투 기록을 삭제할 권한이 없습니다.'; end if;
  if v_status in ('waiting','active') then raise exception '진행 중인 전투는 종료한 뒤 삭제해 주세요.'; end if;

  delete from public.combat_rooms where id = p_room_id;
end; $$;

create or replace function public.combat_room_action(p_room_id uuid,p_version integer,p_action text,p_payload jsonb default '{}')
returns public.combat_rooms language plpgsql security definer set search_path = '' as $$
declare
  r public.combat_rooms; s jsonb; uid uuid := auth.uid(); host boolean; actor integer; i integer; j integer;
  p jsonb; c jsonb; card jsonb; rule jsonb; enemy jsonb; effects jsonb; deck jsonb; pile jsonb;
  players jsonb; enemies jsonb; char_id uuid; rule_id text; target text; side text; cost integer;
begin
  if uid is null then raise exception '로그인이 필요합니다.'; end if;
  select * into r from public.combat_rooms where id=p_room_id for update;
  if not found then raise exception '방을 찾을 수 없습니다.'; end if;
  host := r.created_by=uid and public.is_admin(); s := r.state;
  if not host and not uid=any(r.member_ids) and p_action<>'join' then raise exception '이 방에 참가할 권한이 없습니다.'; end if;
  if p_version is null or r.version<>p_version then raise exception 'COMBAT_STALE: 다른 행동이 먼저 반영되었습니다. 최신 상태에서 다시 시도해 주세요.'; end if;
  if p_action in ('configure','rule','start','close','force_end') and not host then raise exception '방장만 사용할 수 있는 기능입니다.'; end if;
  if p_action in ('join','leave','configure','rule','ready','start') and r.status<>'waiting' then raise exception '대기 중인 방에서만 가능합니다.'; end if;
  if p_action in ('play','end','force_end') and r.status<>'active' then raise exception '진행 중인 전투가 아닙니다.'; end if;
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
    p := jsonb_build_object('id',char_id,'owner_id',uid,'name',c->>'name','avatar_url',c->>'avatar_url',
      'max_hp',(c->>'max_hp')::integer,'hp',least((c->>'hp')::integer,(c->>'max_hp')::integer),
      'block',0,'energy',3,'strength',0,'weak',0,'vulnerable',0,'poison',0,'ready',false,'ended',false,
      'cards',deck,'hand','[]'::jsonb,'draw','[]'::jsonb,'discard','[]'::jsonb,'exhaust','[]'::jsonb,'powers','[]'::jsonb);
    s := jsonb_set(s,'{players}',(s->'players') || jsonb_build_array(p));
    r.member_ids := array_append(r.member_ids,uid);
    s := combat_private.note(s,format('%s 참가 · 보유 카드 %s장',p->>'name',jsonb_array_length(deck)));
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
    for i in 0..jsonb_array_length(s->'players')-1 loop
      p := s->'players'->i;
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

  if p_action in ('configure','rule','join','leave') then
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
revoke all on function public.combat_list_rooms() from public,anon;
revoke all on function public.combat_create_room(text) from public,anon;
revoke all on function public.combat_delete_room(uuid) from public,anon;
revoke all on function public.combat_room_action(uuid,integer,text,jsonb) from public,anon;
grant execute on function public.combat_list_rooms() to authenticated;
grant execute on function public.combat_create_room(text) to authenticated;
grant execute on function public.combat_delete_room(uuid) to authenticated;
grant execute on function public.combat_room_action(uuid,integer,text,jsonb) to authenticated;

do $$ begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(
    select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='combat_rooms'
  ) then alter publication supabase_realtime add table public.combat_rooms; end if;
end $$;
notify pgrst, 'reload schema';
commit;
