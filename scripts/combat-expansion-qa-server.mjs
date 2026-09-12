// UI QA 전용 서버. 외부 Supabase 연결 없이 인메모리 PostgreSQL만 사용합니다.
// node scripts/combat-qa-server.mjs (http://localhost:5182/output/combat-qa/expansion-ui/index.html)
import { PGlite } from '../output/combat-qa/node_modules/@electric-sql/pglite/dist/index.js';
import { createServer } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
const db = new PGlite();
const ids = { admin:'00000000-0000-0000-0000-000000000001', alice:'00000000-0000-0000-0000-000000000002', bob:'00000000-0000-0000-0000-000000000003', viewer:'00000000-0000-0000-0000-000000000004' };
await db.exec(`create role anon; create role authenticated; create schema auth;
  create table auth.users(id uuid primary key);
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  grant usage on schema auth to anon,authenticated; grant execute on function auth.uid() to anon,authenticated;
  create table profiles(id uuid primary key,role text);
  create function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.profiles where id=auth.uid() and role='admin')$$;
  create table characters(id uuid primary key,owner_id uuid,name text,hp integer,max_hp integer,avatar_url text);
  create table character_cards(id uuid primary key,character_id uuid,card_name text,card_effect text,quantity integer,energy integer,card_type text,card_retain boolean,card_innate boolean,card_ethereal boolean,created_at timestamptz default now());`);
for (const [name,id] of Object.entries(ids)) {
  await db.query('insert into auth.users values($1)',[id]);await db.query('insert into profiles values($1,$2)',[id,name==='admin'?'admin':'player']);
  if(['alice','bob'].includes(name)) {
    await db.query('insert into characters values($1,$1,$2,50,50,null)',[id,name==='alice'?'앨리스':'보브']);
    await db.query("insert into character_cards values(gen_random_uuid(),$1,'타격','적 하나에게 6의 피해를 줍니다.',5,1,'공격',false,false,false,now())",[id]);
  }
}
await db.exec(await readFile('supabase/queries/create_realtime_combat.sql','utf8'));
await db.exec("alter table character_cards add column grade text not null default '기본'; grant select on character_cards to authenticated;");
await db.exec(await readFile('supabase/queries/add_card_combat_presets.sql','utf8'));
await db.exec(`create table items(id uuid primary key default gen_random_uuid(),name text,item_type text,icon_url text,grade text default '일반',item_effect text default '',item_description text default '');
create table inventory_items(id uuid primary key default gen_random_uuid(),character_id uuid,item_id uuid references items(id),item_name text,item_effect text,item_description text,quantity integer check(quantity>0),grade text,item_type text,icon_url text,is_equipped boolean default false,created_at timestamptz default now());
create unique index inventory_catalog_unique on inventory_items(character_id,item_id) where item_id is not null;
grant select,update on characters,items,inventory_items to authenticated;`);
await db.exec(await readFile('supabase/queries/add_combat_consumables_energy.sql','utf8'));
await db.exec(await readFile('supabase/queries/add_combat_monsters_relics.sql','utf8'));
await db.exec(await readFile('supabase/queries/add_combat_spectators.sql','utf8'));
await db.exec('grant insert,delete on items to authenticated');
await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);
await db.exec(`insert into items(id,name,item_type,combat_effects) values('00000000-0000-0000-0000-000000000020','회복약','소비','[{"kind":"heal","amount":10,"target":"self"}]'),('00000000-0000-0000-0000-000000000021','폭탄','소비','[{"kind":"damage","amount":9,"target":"enemy"}]');
insert into inventory_items(id,character_id,item_id,item_name,quantity,grade,item_type) values('00000000-0000-0000-0000-000000000030','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000020','회복약',3,'일반','소비'),('00000000-0000-0000-0000-000000000031','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000021','폭탄',2,'일반','소비');
update characters set hp=30 where id='00000000-0000-0000-0000-000000000002';
update character_cards set combat_rule='{"playable":true,"exhaust":false,"effects":[],"on_exhaust":[]}';`);
await db.exec(`insert into combat_monsters(id,name,hp,attack,guard,powers,actions) values('00000000-0000-0000-0000-000000000080','수호 늑대',30,5,3,'[{"kind":"thorns","amount":2,"target":"self"}]','[{"name":"물기","effects":[{"kind":"damage","amount":5,"target":"enemy"}]}]');
insert into items(id,name,item_type) values('00000000-0000-0000-0000-000000000081','전투 유물','유물');
insert into inventory_items(character_id,item_id,item_name,quantity,item_type,is_equipped) values('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000081','전투 유물',1,'유물',true);`);
const dir = resolve('output/combat-qa/expansion-ui'); await mkdir(dir,{recursive:true});
await writeFile(resolve(dir,'index.html'), '<!doctype html><html lang="ko"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>전투 UI QA · 임시 데이터</title></head><body><div id="app"></div><script type="module" src="/output/combat-qa/expansion-ui/main.js"></script></body></html>');
await writeFile(resolve(dir,'main.js'), `import { mount } from 'svelte'; import App from './QaApp.svelte'; mount(App,{target:document.getElementById('app')});`);
await writeFile(resolve(dir,'QaApp.svelte'), `<script>
  import { onMount } from 'svelte'; import AdminMonstersPage from '/src/pages/AdminMonstersPage.svelte'; import CombatPage from '/src/pages/CombatPage.svelte'; import AdminCharacterWorkspace from '/src/pages/AdminCharacterWorkspace.svelte'; import AdminItemsPage from '/src/pages/AdminItemsPage.svelte'; import { defaultPersonalEnergy,prepareResourceSave } from '/src/lib/combatResources.js'; import '/src/app.css';
  import { buildAdminCardRows, normalizeOwnedCard, prepareCardSave } from '/src/lib/cardPersistence.js'; import { supabase } from './adapter.js';
  const name=new URLSearchParams(location.search).get('user')||'admin'; const ids=${JSON.stringify(ids)};
  const user={id:ids[name]||ids.admin}; let route=location.hash.slice(1)||'combat';
  let catalogItems=[];let stock=[];let itemForm={id:'',name:'',grade:'일반',item_type:'소비',item_effect:'',item_description:'',combat_effects:null};let adminCards=[];let saving=false;let saveNotice='';let cardsLoading=true;
  let adminCharacterForm={name:'앨리스',roleName:'전사',roleTraits:'QA 전사',level:1,hp:50,maxHp:50,money:0};
  async function loadCatalog(){const result=await supabase.rpc('qa_catalog');catalogItems=result.data||[];const inv=await supabase.rpc('qa_inventory');stock=inv.data||[];}
  async function saveItem(){saving=true;const result=await supabase.rpc('qa_save_item',{item:itemForm});saveNotice=result.error?.message||'아이템 저장 완료';saving=false;await loadCatalog();}
  async function loadCards(){const energy=await supabase.rpc('qa_energy');adminCharacterForm.personalEnergy={...defaultPersonalEnergy(),...(energy.data||{})};await loadCatalog();const result=await supabase.rpc('qa_cards_list');adminCards=(result.data||[]).map(normalizeOwnedCard);cardsLoading=false;}
  async function saveCards(){saving=true;saveNotice='';try{const rows=buildAdminCardRows(adminCards,ids.alice);await prepareCardSave(supabase,rows);await prepareResourceSave(supabase,adminCharacterForm.personalEnergy,rows);const energy=await supabase.rpc('qa_save_energy',{config:adminCharacterForm.personalEnergy});if(energy.error)throw energy.error;const result=await supabase.rpc('combat_save_character_cards',{p_character_id:ids.alice,p_cards:rows});if(result.error)throw result.error;adminCards=result.data.map(normalizeOwnedCard);saveNotice='사전 설정 저장 완료';}catch(e){saveNotice=e.message;}finally{saving=false;}}
  onMount(()=>{if(name==='admin')loadCards();const change=()=>route=location.hash.slice(1)||'combat';window.addEventListener('hashchange',change);return()=>window.removeEventListener('hashchange',change)});
  </script><div style="max-width:1280px;margin:24px auto;padding:0 16px"><p style="color:#d8bd75">로컬 UI QA · {name} · 임시 데이터만 사용</p>{#if name==='admin'}<nav><a href="#admin/monsters">몬스터 관리 QA</a> · <a href="#cards">카드 설정 QA</a> · <a href="#items">아이템 설정 QA</a> · <a href="#combat">전투방 QA</a></nav>{/if}
  <p role="status">{saveNotice}</p>{#if name==='admin'}<button on:click={loadCatalog}>원본 재조회</button>{#each stock as item}<p>원본 {item.item_name}: {item.quantity}개</p>{/each}{/if}
  {#if route==='admin/monsters' && name==='admin'}<AdminMonstersPage authReady={true} isAdmin={true} />{:else if route==='items' && name==='admin'}<AdminItemsPage authReady={true} isAdmin={true} bind:itemForm {catalogItems} filteredCatalogItems={catalogItems} itemSaving={saving} saveCatalogItem={saveItem} editCatalogItem={(item)=>itemForm=structuredClone(item)} />{:else if route==='cards' && name==='admin'}<AdminCharacterWorkspace {adminCards} bind:adminCharacterForm {catalogItems} authReady={true} isAdmin={true} adminDetailLoading={cardsLoading} adminCharacterSaving={saving} adminSelectedCharacter={{id:ids.alice,name:'앨리스',role_name:'전사',hp:50,max_hp:50}} cardGrades={['기본','일반','고급','희귀','특수']} saveAdminCharacter={saveCards} newAdminCard={()=>adminCards=[...adminCards,normalizeOwnedCard({card_name:'새 카드',quantity:1,grade:'기본'})]} removeAdminCard={(index)=>adminCards=adminCards.filter((_,i)=>i!==index)}/>{:else}<CombatPage {user} authReady={true} isAdmin={name==='admin'} currentRoute={route}/>{/if}</div>`);
await writeFile(resolve(dir,'adapter.js'), `const user=new URLSearchParams(location.search).get('user')||'admin';
async function api(body){try{return await (await fetch('/__combat_qa',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({...body,user})})).json()}catch(e){return {data:null,error:{message:e.message}}}}
function from(table){const args={table,operation:'select',filters:[]};const builder={select(columns='*'){args.columns=columns;return this},eq(key,value){args.filters.push([key,value]);return this},order(key){args.order=key;return this},limit(n){args.limit=n;return this},single(){args.single=true;return this},maybeSingle(){args.single=true;return this},insert(data){args.operation='insert';args.data=data;return this},update(data){args.operation='update';args.data=data;return this},delete(){args.operation='delete';return this},then(ok,bad){return api({name:'qa_table',args}).then(ok,bad)}};return builder;}
export const supabase={rpc:(name,args)=>api({name,args}),from,channel:()=>({on(){return this},subscribe(cb){cb('CHANNEL_ERROR');return this}}),removeChannel:async()=>{}};`);
let queue=Promise.resolve();
let demo=(await db.query("select to_jsonb(combat_create_room('관전·본인 순서 검증')) as value")).rows[0].value;
for(const name of ['alice','bob']) {await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[name]]);demo=(await db.query("select to_jsonb(combat_room_action($1,$2,'join','{}')) as value",[demo.id,demo.version])).rows[0].value;}
await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);demo=(await db.query("select to_jsonb(combat_room_action($1,$2,'configure',$3)) as value",[demo.id,demo.version,JSON.stringify({enemies:[{name:'시험 기사',hp:500,attack:2,guard:3}]})])).rows[0].value;
for(const name of ['alice','bob']) {await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[name]]);demo=(await db.query("select to_jsonb(combat_room_action($1,$2,'ready','{}')) as value",[demo.id,demo.version])).rows[0].value;}
await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);demo=(await db.query("select to_jsonb(combat_room_action($1,$2,'start','{}')) as value",[demo.id,demo.version])).rows[0].value;
const server=await createServer({configFile:false,root:process.cwd(),plugins:[{
  name:'combat-local-qa-adapter',enforce:'pre',resolveId(source,importer){if(source==='../supabaseClient')return resolve(dir,'adapter.js')},
  configureServer(vite){vite.middlewares.use('/__combat_qa',(req,res)=>{
    if(req.method!=='POST'){res.statusCode=405;res.end();return}
    let raw='';req.on('data',chunk=>{raw+=chunk});req.on('end',()=>{
      const job=async()=>{try{
        const {name,args={},user}=JSON.parse(raw);if(!ids[user])throw new Error('Unknown QA user');
        await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[user]]);await db.exec('set role authenticated');
        let data;
        if(name==='qa_table') {
          if(!['combat_rooms','combat_monsters','items','characters','character_cards'].includes(args.table))throw new Error('Unknown QA table');
          const params=[];const quote=key=>{if(!/^[a-z_]+$/.test(key))throw new Error('Invalid column');return '"'+key+'"'};
          const filter=()=>args.filters.length?' where '+args.filters.map(([key,value])=>{params.push(value);return quote(key)+'=$'+params.length}).join(' and '):'';
          let query;
          if(args.operation==='select')query='select * from '+args.table+filter()+(args.order?' order by '+quote(args.order):'')+(args.limit===0?' limit 0':'');
          else if(!['items','combat_monsters'].includes(args.table)||user!=='admin')throw new Error('Admin QA catalog only');
          else if(args.operation==='delete')query='delete from '+args.table+filter()+' returning *';
          else {
            const entries=Object.entries(args.data);const keys=entries.map(([key])=>quote(key));for(const [key,value] of entries)params.push(['powers','actions','combat_effects','relic_effects'].includes(key)&&value!=null?JSON.stringify(value):value);
            if(args.operation==='insert')query='insert into '+args.table+'('+keys.join(',')+') values('+params.map((_,i)=>'$'+(i+1)).join(',')+') returning *';
            else query='update '+args.table+' set '+keys.map((key,i)=>key+'=$'+(i+1)).join(',')+filter()+' returning *';
          }
          const rows=(await db.query(query,params)).rows;data=args.single?rows[0]||null:rows;
        }
        else if(name==='room')data=(await db.query('select to_jsonb(r) as value from combat_rooms r where id=$1',[args.id])).rows[0]?.value||null;
        else if(name==='combat_list_rooms')data=(await db.query('select * from combat_list_rooms()')).rows;
        else if(name==='combat_create_room')data=(await db.query('select to_jsonb(combat_create_room($1)) as value',[args.p_name])).rows[0].value;
        else if(name==='combat_room_action')data=(await db.query('select to_jsonb(combat_room_action($1,$2,$3,$4)) as value',[args.p_room_id,args.p_version,args.p_action,JSON.stringify(args.p_payload)])).rows[0].value;
        else if(name==='combat_watch_room')data=(await db.query('select to_jsonb(combat_watch_room($1,$2)) as value',[args.p_room_id,args.p_watch])).rows[0].value;
        else if(name==='combat_save_character_cards')data=(await db.query('select combat_save_character_cards($1,$2) as value',[args.p_character_id,JSON.stringify(args.p_cards)])).rows[0].value;
        else if(name==='combat_available_consumables')data=(await db.query('select combat_available_consumables() as value')).rows[0].value;
        else if(name==='qa_resource_schema')data=(await db.query('select personal_energy,inventory_version from characters limit 0')).rows;
        else if(name==='qa_catalog')data=(await db.query('select * from items order by name')).rows;
        else if(name==='qa_inventory' && user==='admin')data=(await db.query('select * from inventory_items order by item_name')).rows;
        else if(name==='qa_energy' && user==='admin')data=(await db.query('select personal_energy from characters where id=$1',[ids.alice])).rows[0].personal_energy;
        else if(name==='qa_save_energy' && user==='admin')data=(await db.query('update characters set personal_energy=$2 where id=$1 returning personal_energy',[ids.alice,JSON.stringify(args.config)])).rows;
        else if(name==='qa_save_item' && user==='admin')data=(await db.query('update items set name=$2,combat_effects=$3,relic_effects=$4,item_type=$5 where id=$1 returning *',[args.item.id,args.item.name,JSON.stringify(args.item.combat_effects ?? null),JSON.stringify(args.item.relic_effects ?? null),args.item.item_type])).rows;
        else if(name==='qa_preset_schema')data=(await db.query('select combat_rule from character_cards limit 0')).rows;
        else if(name==='qa_cards_list' && user==='admin')data=(await db.query('select * from character_cards where character_id=$1 order by created_at,id',[ids.alice])).rows;
        else throw new Error('Unknown QA operation');
        res.setHeader('Content-Type','application/json');res.end(JSON.stringify({data,error:null}));
      }catch(error){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({data:null,error:{message:error.message,code:error.code}}))}
      finally{await db.exec('reset role')}};
      queue=queue.then(job,job);
    });
  })}
},svelte()],server:{host:'localhost',port:5182,strictPort:true}});
await server.listen();
console.log('Local UI QA: http://localhost:5182/output/combat-qa/expansion-ui/index.html?user=admin#combat');
console.log('Users: admin, alice, bob. No production database connection. Polling fallback is intentionally tested.');
