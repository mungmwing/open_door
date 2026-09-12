// 실제 운영 DB에 접속하지 않는 인메모리 PostgreSQL 통합 검증.
import {PGlite} from '../output/combat-qa/node_modules/@electric-sql/pglite/dist/index.js';
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {validateCombatRule,emptyCombatRule,EFFECTS,enemyIntent,playersForViewer} from '../src/lib/combat.js';
import {generatedCard,defaultMonster,validateMonster,validateRelics,prepareRelicSave} from '../src/lib/combatExpansion.js';
import {EFFECT_HELP} from '../src/lib/cardHelp.js';
const db=new PGlite(); const uid=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const admin=uid(1),alice=uid(2),bob=uid(3),char=uid(12),other=uid(13),monsterId=uid(20),summonId=uid(21),relicId=uid(30),cardId=uid(40),bobCardId=uid(41);
const scalar=async(q,p=[])=>(await db.query(q,p)).rows[0]?.value;
const as=async(u,fn)=>{await db.query("select set_config('request.jwt.claim.sub',$1,false)",[u||'']);await db.exec(u?'set role authenticated':'set role anon');try{return await fn()}finally{await db.exec('reset role')}};
let passed=0;const test=async(name,fn)=>{await fn();passed++;console.log('PASS '+name)};
const ef=(kind,amount,target='self',extra={})=>({kind,amount,target,...extra});
const rule=(effects=[],extra={})=>({...emptyCombatRule(),effects,...extra});
const invoke=(r,a,p={})=>scalar('select to_jsonb(combat_room_action($1,$2,$3,$4)) as value',[r.id,r.version,a,JSON.stringify(p)]);
const fresh=r=>scalar('select to_jsonb(r) as value from combat_rooms r where id=$1',[r.id]);
const setState=async(r,state)=>{await db.query('update combat_rooms set state=$2,status=$3 where id=$1',[r.id,JSON.stringify(state),'active']);return fresh(r)};
const spawn=ef('summon',1,'self',{monster_id:summonId,monster_name:'수호 늑대'});
const injection=ef('add_card',2,'enemies',{pile:'discard',card:generatedCard('burn')});
async function setRule(id,value){await as(admin,()=>db.query('update character_cards set combat_rule=$2 where id=$1',[id,JSON.stringify(value)]));}
async function room({two=false,enemy={name:'표적',hp:500,attack:0,guard:0},start=true}={}){
  let r=await as(admin,()=>scalar("select to_jsonb(combat_create_room('확장 QA')) as value"));
  r=await as(alice,()=>invoke(r,'join'));if(two)r=await as(bob,()=>invoke(r,'join'));
  r=await as(admin,()=>invoke(r,'configure',{enemies:[enemy]}));
  r=await as(alice,()=>invoke(r,'ready'));if(two)r=await as(bob,()=>invoke(r,'ready'));
  if(start)r=await as(admin,()=>invoke(r,'start'));return r;
}
try{
// Reuse only the inert bootstrap schema from the resource QA file.
const resourceTest=await readFile('scripts/combat-resources-qa.mjs','utf8');
const bootstrap=resourceTest.slice(resourceTest.indexOf('await db.exec(`')+'await db.exec(`'.length,resourceTest.indexOf('`);',resourceTest.indexOf('await db.exec(`')));
await db.exec(bootstrap);
for(const [id,roleName] of [[admin,'admin'],[alice,'player'],[bob,'player']]){await db.query('insert into auth.users values($1)',[id]);await db.query('insert into profiles values($1,$2)',[id,roleName]);}
await db.query("insert into characters values($1,$2,'앨리스',40,50,null),($3,$4,'보브',40,40,null)",[char,alice,other,bob]);
await db.query("insert into character_cards(id,character_id,card_name,quantity) values($1,$2,'타격',5),($3,$4,'보브 카드',5)",[cardId,char,bobCardId,other]);
for(const file of ['create_realtime_combat.sql','add_card_combat_presets.sql','add_combat_consumables_energy.sql'])await db.exec(await readFile('supabase/queries/'+file,'utf8'));
const sql=await readFile('supabase/queries/add_combat_monsters_relics.sql','utf8');
await test('확장 SQL 전체 컴파일·재적용',async()=>{await db.exec(sql);await db.exec(sql)});
await test('관전 SQL 전체 컴파일·재적용',async()=>{const sql=await readFile('supabase/queries/add_combat_spectators.sql','utf8');await db.exec(sql);await db.exec(sql);});
await as(admin,async()=>{
  await db.query('insert into combat_monsters(id,name,hp,attack,guard,powers,actions) values($1,$2,80,6,5,$3,$4),($5,$6,25,4,2,$7,$8)',[monsterId,'저주술사',JSON.stringify([ef('thorns',2)]),JSON.stringify([{name:'저주',effects:[injection,ef('weak',2,'enemies')]},{name:'연타',effects:[ef('damage',3,'enemy'),ef('damage',3,'enemy')]}]),summonId,'수호 늑대',JSON.stringify([ef('strength',2),ef('thorns',1)]),JSON.stringify([{name:'물기',effects:[ef('damage',4,'enemy')]}])]);
  await db.query("update character_cards set card_type='공격' where id=$1",[cardId]);
});
await setRule(cardId,rule([ef('damage',6,'enemy')]));await setRule(bobCardId,rule());
await test('일반 관전자 출입·RLS·전투 권한 차단·버전 보존',async()=>{
  let r=await room();assert.equal(await as(bob,()=>fresh(r)),undefined);
  const before=structuredClone(r);r=await as(bob,()=>scalar('select to_jsonb(combat_watch_room($1,true)) as value',[r.id]));
  assert.deepEqual(r.state,before.state);assert.equal(r.version,before.version);assert.equal(r.updated_at,before.updated_at);assert.equal((await as(bob,()=>fresh(r))).id,r.id);
  for(const action of ['play','end','force_end','rule','configure','use_item','inject_card','close'])await assert.rejects(as(bob,()=>invoke(r,action)),/권한/);
  await assert.rejects(as(bob,()=>db.query("update combat_rooms set status='victory' where id=$1",[r.id])),/permission denied/);
  await assert.rejects(as(null,()=>scalar('select combat_watch_room($1,true) as value',[r.id])),/permission denied/);
  r=await as(bob,()=>scalar('select to_jsonb(combat_watch_room($1,true)) as value',[r.id]));assert.equal(r.spectator_ids.length,1);
  await as(bob,()=>scalar('select combat_watch_room($1,false) as value',[r.id]));assert.equal(await as(bob,()=>fresh(r)),undefined);
  r=await as(admin,()=>invoke(r,'close'));await assert.rejects(as(bob,()=>scalar('select combat_watch_room($1,true) as value',[r.id])),/대기 중/);
});
await test('관전 중 캐릭터 참가 전환·종료 기록 재접속',async()=>{
  let r=await room({start:false});r=await as(bob,()=>scalar('select to_jsonb(combat_watch_room($1,true)) as value',[r.id]));r=await as(bob,()=>invoke(r,'join'));assert.equal(r.state.players.length,2);
  const otherRoom=await room();await as(bob,()=>scalar('select combat_watch_room($1,true) as value',[otherRoom.id]));await as(admin,()=>invoke(otherRoom,'close'));assert.equal((await as(bob,()=>fresh(otherRoom))).status,'closed');
});
await test('각 이용자의 플레이어 1번 표시·서버/의도 순서는 보존',async()=>{
  const original=[{id:'a',owner_id:alice},{id:'b',owner_id:bob}];assert.deepEqual(playersForViewer(original,bob).map(p=>p.id),['b','a']);assert.deepEqual(playersForViewer(original,alice).map(p=>p.id),['a','b']);assert.deepEqual(original.map(p=>p.id),['a','b']);assert.deepEqual(playersForViewer(original,admin),original);
});
await test('카탈로그 읽기·관리자 저장 권한 및 비공개 함수 차단',async()=>{
  assert.equal((await as(alice,()=>db.query('select * from combat_monsters'))).rows.length,2);
  await assert.rejects(as(alice,()=>db.query("insert into combat_monsters(name) values('위조')")),/관리자|row-level/);
  const changed=await as(alice,()=>db.query("update combat_monsters set hp=999 where id=$1 returning id",[monsterId]));assert.equal(changed.rows.length,0);
  await assert.rejects(as(null,()=>db.query('select * from combat_monsters')),/permission denied/);
  await assert.rejects(as(alice,()=>db.query("select combat_private.effects_from('{}','players',0,'[]')")),/permission denied/);
});
await test('몬스터 잘못된 파워·행동·생성 중첩 거부',async()=>{
  await assert.rejects(as(admin,()=>db.query('update combat_monsters set powers=$2 where id=$1',[monsterId,JSON.stringify([ef('damage',2)])])),/시작 파워/);
  await assert.rejects(as(admin,()=>db.query('update combat_monsters set actions=$2 where id=$1',[monsterId,JSON.stringify([{name:'잘못된 소환',effects:[spawn]}])])),/몬스터 행동/);
  const c=generatedCard();c.combat_rule.effects=[spawn];await assert.rejects(setRule(cardId,rule([ef('add_card',1,'self',{card:c,pile:'hand'})])),/삽입 카드 안/);
  await assert.rejects(setRule(cardId,rule([],{on_turn_end:[ef('damage',2,'enemy')]})),/턴 종료/);
});
await test('몬스터 카탈로그 스냅샷·시작 파워·반복 행동·강제 카드 삽입',async()=>{
  let r=await room({enemy:{catalog_id:monsterId},two:true});assert.equal(r.state.enemies[0].thorns,2);
  await as(admin,()=>db.query("update combat_monsters set name='변경된 이름' where id=$1",[monsterId]));assert.equal(r.state.enemies[0].name,'저주술사');
  r=await as(alice,()=>invoke(r,'end'));r=await as(bob,()=>invoke(r,'end'));
  assert.equal(r.state.round,2);for(const p of r.state.players){assert.equal(p.cards.filter(c=>c.generated).length,2);assert.equal(p.weak,2);}
  const before=r.state.players.reduce((n,p)=>n+p.hp,0);r=await as(alice,()=>invoke(r,'end'));r=await as(bob,()=>invoke(r,'end'));
  assert.ok(r.state.players.reduce((n,p)=>n+p.hp,0)<=before-6);assert.ok(r.state.log.some(l=>l.includes('연타')));
  assert.equal(await scalar('select quantity as value from character_cards where id=$1',[cardId]),5);
});
await test('방장 직접 삽입·일반 플레이어/관전자 차단·버전 충돌',async()=>{
  let r=await room();const payload={player_id:char,effect:{...injection,target:'self',amount:1,pile:'hand'}};
  await assert.rejects(as(alice,()=>invoke(r,'inject_card',payload)),/방장/);
  await assert.rejects(as(bob,()=>invoke(r,'inject_card',payload)),/권한/);
  const stale=r;r=await as(admin,()=>invoke(r,'inject_card',payload));assert.equal(r.state.players[0].hand.at(-1).card_name,'화상');
  await assert.rejects(as(admin,()=>invoke(stale,'inject_card',payload)),/COMBAT_STALE/);
  const before=await fresh(r);await assert.rejects(as(admin,()=>invoke(r,'inject_card',{...payload,effect:{...payload.effect,pile:'hack'}})),/더미/);assert.deepEqual(await fresh(r),before);
});
await test('카드 삽입 손패 상한·전투 덱 한도·고유 인스턴스',async()=>{
  let r=await room();r=await as(admin,()=>invoke(r,'inject_card',{player_id:char,effect:{...injection,target:'self',amount:10,pile:'hand'}}));
  const p=r.state.players[0];assert.equal(p.hand.length,10);assert.equal(p.discard.length,5);assert.equal(new Set(p.cards.map(c=>c.instance_id)).size,15);
  const s=structuredClone(r.state);while(s.players[0].cards.length<199)s.players[0].cards.push({...p.cards[0],instance_id:uid(s.players[0].cards.length+1000)});
  r=await setState(r,s);r=await as(admin,()=>invoke(r,'inject_card',{player_id:char,effect:{...injection,target:'self',amount:10}}));assert.equal(r.state.players[0].cards.length,200);
});
await test('화상 HP 손실·어지러움 소멸·점액 사용·재드로우 보존',async()=>{
  let r=await room();
  for(const preset of ['burn','dazed','slimed'])r=await as(admin,()=>invoke(r,'inject_card',{player_id:char,effect:ef('add_card',1,'self',{pile:'hand',card:generatedCard(preset)})}));
  const slime=r.state.players[0].hand.find(c=>c.card_name==='점액');r=await as(alice,()=>invoke(r,'play',{instance_id:slime.instance_id}));assert.equal(r.state.players[0].energy,2);
  const hp=r.state.players[0].hp;r=await as(alice,()=>invoke(r,'end'));assert.equal(r.state.players[0].hp,hp-2);assert.equal(r.state.players[0].exhaust.length,2);assert.ok(r.state.players[0].cards.some(c=>c.card_name==='화상'));
});
await test('가시 반격·민첩/손상·인공물·무형·직접 HP 손실',async()=>{
  const u={hp:40,max_hp:50,block:0,thorns:3},p={...u,thorns:2,energy:3,cards:[],draw:[],hand:[],discard:[],exhaust:[]};
  let s={players:[p],enemies:[{...u,id:'enemy',block:100,thorns:4}],rules:{}};
  s=await scalar('select combat_private.effects($1,0,$2,$3) as value',[JSON.stringify(s),JSON.stringify([ef('damage',6,'enemy')]),'enemy']);assert.equal(s.enemies[0].hp,40);assert.equal(s.players[0].hp,36);
  s.players[0]={...p,dexterity:3,frail:2,artifact:1,intangible:2};
  s=await scalar('select combat_private.effects($1,0,$2) as value',[JSON.stringify(s),JSON.stringify([ef('block',5),ef('poison',4),ef('weak',2),ef('lose_hp',3)])]);
  assert.equal(s.players[0].block,6);assert.equal(s.players[0].poison,undefined);assert.equal(s.players[0].artifact,0);assert.equal(s.players[0].weak,2);assert.equal(s.players[0].hp,37);
  const hit=await scalar('select combat_private.hit($1,20,$2,true) as value',[JSON.stringify({...u,intangible:1}),JSON.stringify({})]);assert.equal(hit.hp,39);
});
await test('금속화·재생·바리케이드와 턴 감소 판정',async()=>{
  let r=await room();const s=structuredClone(r.state);s.players[0]={...s.players[0],block:5,barricade:1,metallicize:3,regeneration:4,frail:2,intangible:2};
  r=await setState(r,s);r=await as(alice,()=>invoke(r,'end'));const p=r.state.players[0];assert.equal(p.block,8);assert.equal(p.hp,44);assert.equal(p.regeneration,3);assert.equal(p.frail,1);assert.equal(p.intangible,1);
});
await test('유물 종류별 중복 방지 및 5가지 발동 시점',async()=>{
  await as(admin,async()=>{
    await db.query('insert into items(id,name,item_type,relic_effects) values($1,$2,$3,$4)',[relicId,'시험 유물','유물',JSON.stringify([{event:'battle_start',effects:[ef('strength',2)]},{event:'turn_start',effects:[ef('energy',1)]},{event:'turn_end',effects:[ef('heal',3)]},{event:'card_play',effects:[ef('block',1)]},{event:'attack_play',effects:[ef('block',2)]}])]);
    await db.query("insert into inventory_items(character_id,item_id,item_name,quantity,item_type,is_equipped) values($1,$2,'시험 유물',3,'유물',true)",[char,relicId]);
  });
  let r=await room();assert.equal(r.state.players[0].relics.length,1);assert.equal(r.state.players[0].strength,2);assert.equal(r.state.players[0].energy,4);
  r=await as(alice,()=>invoke(r,'play',{instance_id:r.state.players[0].hand[0].instance_id,target_id:r.state.enemies[0].id}));assert.equal(r.state.players[0].block,3);assert.equal(r.state.enemies[0].hp,492);
  r=await as(alice,()=>invoke(r,'end'));assert.equal(r.state.players[0].hp,43);assert.equal(r.state.players[0].energy,4);assert.equal(r.state.players[0].strength,2);
  await as(admin,()=>db.query('update items set relic_effects=$2 where id=$1',[relicId,JSON.stringify([{event:'battle_start',effects:[ef('strength',99)]}])]));assert.equal((await fresh(r)).state.players[0].relics[0].events[0].effects[0].amount,2);
  assert.equal(await scalar('select quantity as value from inventory_items where item_id=$1',[relicId]),3);
});
await test('유물 잘못된 대상·타입·플레이어 편집 거부 및 시작 때 보유 재확인',async()=>{
  await assert.rejects(as(admin,()=>db.query('update items set relic_effects=$2 where id=$1',[relicId,JSON.stringify([{event:'battle_start',effects:[ef('damage',9,'enemy')]}])])),/유물은/);
  await assert.rejects(as(admin,()=>db.query("update items set item_type='기타' where id=$1",[relicId])),/유물 타입/);
  await assert.rejects(as(alice,()=>db.query('update items set relic_effects=null where id=$1',[relicId])),/관리자/);
  let r=await room({start:false});await as(admin,()=>db.query('delete from inventory_items where item_id=$1',[relicId]));r=await as(admin,()=>invoke(r,'start'));assert.equal(r.state.players[0].relics.length,0);assert.equal(r.state.players[0].strength,0);
});
await test('소환 지정 몬스터 스냅샷·시작 파워·자동 공격·적의 소환물 피격',async()=>{
  await setRule(cardId,rule([spawn]));let r=await room({enemy:{name:'적',hp:500,attack:5,guard:0}});
  r=await as(alice,()=>invoke(r,'play',{instance_id:r.state.players[0].hand[0].instance_id}));assert.equal(r.state.summons.length,1);assert.equal(r.state.summons[0].strength,2);assert.equal(r.state.summons[0].name,'수호 늑대');
  await as(admin,()=>db.query("update combat_monsters set attack=90 where id=$1",[summonId]));assert.equal(r.state.summon_catalog[summonId].attack,4);
  r=await as(alice,()=>invoke(r,'end'));assert.equal(r.state.enemies[0].hp,494);assert.equal(r.state.players[0].hp,35);
  const s=structuredClone(r.state);s.enemies[0].actions=[{name:'공격',effects:[ef('damage',5,'enemy')]}];r=await setState(r,s);
  r=await as(alice,()=>invoke(r,'end'));assert.equal(r.state.summons[0].hp,20);assert.equal(r.state.enemies[0].hp,487);assert.equal(r.state.players[0].hp,35);
});
await test('소환물 선택 회복/전체 아군 효과·덱 자원 제외·6기 상한',async()=>{
  let r=await room();const s=structuredClone(r.state);s.rules[cardId]=rule([spawn,ef('heal',3,'ally'),ef('block',2,'allies'),ef('draw',2,'allies')]);
  // Spawn a first unit through the authoritative card action before selecting it.
  r=await as(alice,()=>invoke(r,'play',{instance_id:r.state.players[0].hand[0].instance_id}));
  let next=structuredClone(r.state);next.rules[cardId]=s.rules[cardId];next.summons[0].hp=10;r=await setState(r,next);
  r=await as(alice,()=>invoke(r,'play',{instance_id:r.state.players[0].hand[0].instance_id,target_id:r.state.summons[0].id}));assert.equal(r.state.summons[0].hp,13);assert.equal(r.state.summons[0].block,2);assert.equal(r.state.summons[0].hand,undefined);
  next=structuredClone(r.state);next.rules[cardId]=rule([{...spawn,amount:3}]);r=await setState(r,next);
  for(let i=0;i<2;i++)r=await as(alice,()=>invoke(r,'play',{instance_id:r.state.players[0].hand[0].instance_id}));assert.equal(r.state.summons.length,6);
});
await test('사망 소환물 정리·플레이어 전멸 패배·삭제된 후보 시작 차단',async()=>{
  let r=await room();r=await as(alice,()=>invoke(r,'play',{instance_id:r.state.players[0].hand[0].instance_id}));let s=structuredClone(r.state);s.summons[0].hp=0;r=await setState(r,s);
  r=await as(alice,()=>invoke(r,'play',{instance_id:r.state.players[0].hand[0].instance_id}));assert.equal(r.state.summons.length,1);assert.equal(r.state.summons[0].hp,25);
  s=structuredClone(r.state);s.rules[cardId]=rule([ef('lose_hp',999)]);r=await setState(r,s);r=await as(alice,()=>invoke(r,'play',{instance_id:r.state.players[0].hand[0].instance_id}));assert.equal(r.status,'defeat');
  const waiting=await room({start:false});await as(admin,()=>db.query('delete from combat_monsters where id=$1',[summonId]));await assert.rejects(as(admin,()=>invoke(waiting,'start')),/소환할 몬스터가 삭제/);
});
await test('프런트/서버 규칙과 모든 효과 도움말·SQL 미적용 저장 방어',async()=>{
  for(const key of Object.keys(EFFECTS))assert.ok(EFFECT_HELP[key],key);
  assert.equal(validateCombatRule(rule([spawn,injection])), '');assert.equal(validateMonster({...defaultMonster(),name:'몬스터'}),'');assert.match(validateRelics([{event:'turn_end',effects:[ef('heal',2,'ally')]}]),/유물은/);
  const missing={from:()=>({select:()=>({limit:async()=>({error:{code:'42703',message:'column relic_effects does not exist'}})})})};assert.equal(await prepareRelicSave(missing,null),false);await assert.rejects(prepareRelicSave(missing,[]),/add_combat_monsters_relics/);
  assert.equal(enemyIntent({actions:[{name:'저주',effects:[injection]}]},0,1,[]).label,'저주');
  assert.equal(enemyIntent({attack:4,guard:3,summoned_round:2},0,2,[]).label,'공격');
});
console.log(`\n${passed} expansion checks passed. Production database was not accessed.`);
}catch(error){console.error({message:error.message,code:error.code,where:error.where,stack:error.stack?.split('\n').slice(0,5).join('\n')});process.exitCode=1;}finally{await db.close();}
