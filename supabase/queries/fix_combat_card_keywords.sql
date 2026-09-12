-- 수동 적용 전용: 운영 DB에는 직접 실행하지 않았습니다.
-- 기존 create_realtime_combat.sql 적용 후 이 파일 전체를 실행하세요.
-- 카드 사전 설정을 사용하려면 add_card_combat_presets.sql도 필요합니다.
-- 추가 드롭 자동 드로우, 선천 첫 손패 확장, 파워와 소멸 구분을 수정합니다.
-- 카드/방 데이터를 일괄 수정하지 않습니다. 검증은 새 방에서 진행하세요.
begin;

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

revoke all on function public.combat_room_action(uuid,integer,text,jsonb) from public,anon;
grant execute on function public.combat_room_action(uuid,integer,text,jsonb) to authenticated;
notify pgrst, 'reload schema';
commit;
