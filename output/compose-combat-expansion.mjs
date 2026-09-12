import {readFile,writeFile} from 'node:fs/promises';
const path='supabase/queries/add_combat_monsters_relics.sql';
let base=await readFile('supabase/queries/add_combat_consumables_energy.sql','utf8');
let rpc=base.slice(base.indexOf('create or replace function public.combat_room_action('),base.indexOf('revoke all on all functions in schema combat_private'));
function replace(old,next){if(!rpc.includes(old))throw new Error('Missing RPC anchor: '+old.slice(0,100));rpc=rpc.replace(old,next);}
replace("if p_action in ('configure','rule','start','close','force_end')", "if p_action in ('configure','rule','start','close','force_end','inject_card')");
replace("('play','end','force_end','use_item','discard_item')", "('play','end','force_end','use_item','discard_item','inject_card')");
replace("'cards',deck,'hand'", "'relics',combat_private.relics_for(char_id),'cards',deck,'hand'");
const oldConfigure=rpc.slice(rpc.indexOf("    for enemy in select value from jsonb_array_elements(p_payload->'enemies') loop"),rpc.indexOf("    s := jsonb_set(s,'{enemies}',enemies);"));
replace(oldConfigure,`    for enemy in select value from jsonb_array_elements(p_payload->'enemies') loop
      if coalesce(enemy->>'catalog_id','')<>'' then
        select to_jsonb(m) into c from public.combat_monsters m where m.id=(enemy->>'catalog_id')::uuid;
        if c is null then raise exception '등록된 몬스터를 찾을 수 없습니다. 목록을 새로고침해 주세요.';end if;
      else
        c:=enemy || jsonb_build_object('powers',coalesce(enemy->'initial_powers',enemy->'powers','[]'));
      end if;
      enemies:=enemies || jsonb_build_array(combat_private.monster_unit(c));
    end loop;
`);
replace("    for i in 0..jsonb_array_length(s->'players')-1 loop", "    s:=combat_private.prepare_expansion(s);\n    for i in 0..jsonb_array_length(s->'players')-1 loop");
replace("s := combat_private.note(s,'전투 시작 · 라운드 1');", `s := combat_private.note(s,'전투 시작 · 라운드 1');
    for i in 0..jsonb_array_length(s->'players')-1 loop s:=combat_private.fire_relics(s,i,'battle_start');end loop;
    for i in 0..jsonb_array_length(s->'players')-1 loop s:=combat_private.fire_relics(s,i,'turn_start');end loop;`);
// The old consumable catalog loop overwrites the complete snapshot. Keep its
// inventory validation but merge generated pools discovered from relics too.
replace("s:=jsonb_set(s,'{consumable_catalog}',catalog);", "s:=jsonb_set(s,'{consumable_catalog}',coalesce(s->'consumable_catalog','{}') || catalog);");
rpc=rpc.replaceAll("jsonb_array_elements(s->side) t", "jsonb_array_elements(case when side='players' then (s->'players') || coalesce(s->'summons','[]') else s->side end) t");
replace("    s := combat_private.note(s,format('%s: %s 사용 (-%s 에너지)',p->>'name',card->>'card_name',cost));",`    s := combat_private.note(s,format('%s: %s 사용 (-%s 에너지)',p->>'name',card->>'card_name',cost));
    s:=combat_private.fire_relics(s,actor,'card_play');
    if card->>'card_type'='공격' then s:=combat_private.fire_relics(s,actor,'attack_play');end if;`);
replace("  elsif p_action in ('use_item','discard_item') then",`  elsif p_action='inject_card' then
    effects:=p_payload->'effect';
    if effects->>'kind' is distinct from 'add_card' or effects->>'target' is distinct from 'self' then raise exception '카드 삽입 설정을 확인해 주세요.';end if;
    perform combat_private.validate_effects(jsonb_build_array(effects));
    select (ord-1)::integer into actor from jsonb_array_elements(s->'players') with ordinality a(value,ord) where value->>'id'=p_payload->>'player_id' and (value->>'hp')::integer>0;
    if actor is null then raise exception '살아 있는 플레이어를 선택해 주세요.';end if;
    s:=combat_private.effects(s,actor,jsonb_build_array(effects));
    s:=combat_private.note(s,'방장이 전투 덱에 카드를 삽입했습니다.');
  elsif p_action in ('use_item','discard_item') then`);
const sql=await readFile(path,'utf8');
await writeFile(path,sql+'\n'+rpc+`\nrevoke all on all functions in schema combat_private from public,anon,authenticated;
revoke all on function public.combat_room_action(uuid,integer,text,jsonb) from public,anon;
grant execute on function public.combat_room_action(uuid,integer,text,jsonb) to authenticated;
notify pgrst, 'reload schema';
commit;
`);
