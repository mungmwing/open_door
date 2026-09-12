// 임시 인메모리 PostgreSQL에만 실행합니다. 운영 DB 연결은 사용하지 않습니다.
// npm install --prefix output/combat-qa --no-audit --no-fund @electric-sql/pglite
// node scripts/combat-qa.mjs
import { PGlite } from '../output/combat-qa/node_modules/@electric-sql/pglite/dist/index.js';
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { EFFECTS, cardCost, uniqueCards, targetSide, enemyIntent, combatError, validateCombatRule, cardDestination, extraCardDraw, representativeCardTarget } from '../src/lib/combat.js';
import { EFFECT_HELP, KEYWORD_HELP } from '../src/lib/cardHelp.js';
import { buildAdminCardRows, normalizeOwnedCard, prepareCardSave } from '../src/lib/cardPersistence.js';
import { formatCombatTestCards, groupCombatTestCards } from '../src/lib/combatTest.js';

const db = new PGlite();
const admin = '00000000-0000-0000-0000-000000000001';
const alice = '00000000-0000-0000-0000-000000000002';
const bob = '00000000-0000-0000-0000-000000000003';
const outsider = '00000000-0000-0000-0000-000000000004';
const cid = (n) => `10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const cardId = (n) => `20000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const scalar = async (sql, params = []) => (await db.query(sql, params)).rows[0]?.value;
let passed = 0;
async function test(name, fn) { await fn(); passed++; console.log(`PASS ${name}`); }
async function as(uid, fn) {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [uid || '']);
  await db.exec(uid ? 'set role authenticated' : 'set role anon');
  try { return await fn(); } finally { await db.exec('reset role'); }
}
const invoke = (room, action, payload = {}) => scalar('select to_jsonb(public.combat_room_action($1,$2,$3,$4::jsonb)) as value', [room.id,room.version,action,JSON.stringify(payload)]);
const fail = (fn, expression) => assert.rejects(fn, expression);
const effect = (kind, amount, target='self') => ({kind,amount,target});
const rule = (effects, extra={}) => ({playable:true,exhaust:false,effects,on_exhaust:[],...extra});
const fresh = (id) => scalar('select to_jsonb(r) as value from public.combat_rooms r where id=$1',[id]);

try {
  await db.exec(`create role anon; create role authenticated; create schema auth;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to anon,authenticated; grant execute on function auth.uid() to anon,authenticated;
    create table public.profiles(id uuid primary key, role text);
    create function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.profiles where id=auth.uid() and role='admin')$$;
    create table public.characters(id uuid primary key,owner_id uuid,name text,hp integer,max_hp integer,avatar_url text);
    create table public.character_cards(id uuid primary key,character_id uuid,card_name text,card_effect text,quantity integer,energy integer,card_type text,card_retain boolean,card_innate boolean,card_ethereal boolean,created_at timestamptz default now());`);
  for (const uid of [admin,alice,bob,outsider]) {
    await db.query('insert into auth.users values($1)',[uid]);
    await db.query('insert into profiles values($1,$2)',[uid,uid===admin?'admin':'player']);
  }
  await db.query("insert into characters values($1,$2,'앨리스',50,50,null),($3,$4,'보브',40,40,null)",[cid(1),alice,cid(2),bob]);
  await db.query("insert into character_cards values($1,$2,'타격','6 피해',6,1,'공격',false,false,false,now()),($3,$2,'수비','방어 5',2,1,'스킬',true,true,false,now()),($4,$2,'유령','중독',1,0,'스킬',true,true,true,now()),($5,$6,'협력','아군 회복',6,1,'스킬',false,false,false,now())",[cardId(1),cid(1),cardId(2),cardId(3),cardId(4),cid(2)]);
  const sql = await readFile(new URL('../supabase/queries/create_realtime_combat.sql',import.meta.url),'utf8');
  await test('수동 적용 SQL 전체 컴파일',()=>db.exec(sql));
  await test('SQL 재실행 가능',()=>db.exec(sql));
  const deleteSql = await readFile(new URL('../supabase/queries/add_combat_room_delete.sql',import.meta.url),'utf8');
  await test('전투 기록 삭제 추가 SQL 컴파일 및 재적용',async()=>{await db.exec(deleteSql);await db.exec(deleteSql)});
  await test('비로그인 RPC 차단',()=>as(null,()=>fail(()=>scalar('select public.combat_list_rooms() as value'),/permission denied/)));
  await test('비로그인 전투 기록 삭제 차단',()=>as(null,()=>fail(()=>scalar("select public.combat_delete_room('00000000-0000-0000-0000-000000000000') as value"),/permission denied/)));
  await test('일반 플레이어 방 생성 차단',()=>as(alice,()=>fail(()=>scalar("select public.combat_create_room('권한 없음') as value"),/관리자/)));
  let room = await as(admin,()=>scalar("select to_jsonb(public.combat_create_room('QA 협동 전투')) as value"));
  await test('비참가자 상세 RLS 차단',()=>as(outsider,async()=>assert.equal(await fresh(room.id),undefined)));
  await test('클라이언트 직접 상태 변경 차단',()=>as(alice,()=>fail(()=>db.query("update combat_rooms set status='victory' where id=$1",[room.id]),/permission denied/)));
  await test('내부 판정 함수 호출 차단',()=>as(alice,()=>fail(()=>scalar("select combat_private.draw('{}',5) as value"),/permission denied/)));
  await test('잘못된 캐릭터 참가 차단',()=>as(outsider,()=>fail(()=>invoke(room,'join'),/캐릭터/)));
  room = await as(alice,()=>invoke(room,'join'));
  await test('보유 수량대로 복사 / 원본 변경 없음',async()=>{ assert.equal(room.state.players[0].cards.length,9); assert.equal(await scalar('select hp as value from characters where id=$1',[cid(1)]),50); });
  await test('중복 참가 차단',()=>as(alice,()=>fail(()=>invoke(room,'join'),/이미 참가/)));
  const stale = room;
  room = await as(bob,()=>invoke(room,'join'));
  await test('동일 버전의 후속 변경 거부',()=>as(alice,()=>fail(()=>invoke(stale,'ready'),/COMBAT_STALE/)));
  await test('타인이 방 설정 변경 불가',()=>as(alice,()=>fail(()=>invoke(room,'configure',{enemies:[]}),/방장/)));
  await test('숫자/효과 설정 검증',()=>as(admin,()=>fail(()=>invoke(room,'configure',{enemies:[{name:'적',hp:-1,attack:1,guard:1}]}),/범위/)));
  room = await as(admin,()=>invoke(room,'configure',{enemies:[{name:'문지기',hp:100,attack:6,guard:8}]}));
  await test('미설정 카드 시작 차단',async()=>{
    room=await as(alice,()=>invoke(room,'ready')); room=await as(bob,()=>invoke(room,'ready'));
    await as(admin,()=>fail(()=>invoke(room,'start'),/모든 보유 카드/));
  });
  await test('소유하지 않은 카드 규칙 등록 차단',()=>as(admin,()=>fail(()=>invoke(room,'rule',{card_id:cardId(99),rule:rule([])}),/보유한 카드/)));
  await test('효과 타입과 종료 소멸 대상 검증',async()=>{
    await as(admin,()=>fail(()=>invoke(room,'rule',{card_id:cardId(1),rule:rule([effect('hack',1)])}),/지원하지 않는/));
    await as(admin,()=>fail(()=>invoke(room,'rule',{card_id:cardId(1),rule:rule([],{on_exhaust:[effect('damage',1,'enemy')]})}),/소멸 효과/));
  });
  for (const [id,value] of [[cardId(1),rule([effect('damage',6,'enemy')])],[cardId(2),rule([effect('block',5)])],[cardId(3),rule([effect('poison',3,'enemies')],{on_exhaust:[effect('block',2)]})],[cardId(4),rule([effect('heal',4,'ally')])]]) room=await as(admin,()=>invoke(room,'rule',{card_id:id,rule:value}));
  await test('설정 변경 시 준비 해제',async()=>assert.ok(room.state.players.every(p=>!p.ready)));
  room=await as(alice,()=>invoke(room,'ready')); room=await as(bob,()=>invoke(room,'ready')); room=await as(admin,()=>invoke(room,'start'));
  await test('시작 손패 / 선천 우선 / 인스턴스 유일',async()=>{
    assert.equal(room.status,'active'); assert.equal(room.state.players[0].hand.length,5);
    assert.equal(room.state.players[0].hand.filter(c=>c.card_innate).length,3);
    assert.equal(new Set(room.state.players[0].cards.map(c=>c.instance_id)).size,9);
  });
  await test('전투 시작 후 참가와 설정 변경 차단',async()=>{
    await as(outsider,()=>fail(()=>invoke(room,'join'),/대기 중/));
    await as(admin,()=>fail(()=>invoke(room,'configure',{enemies:[]}),/대기 중/));
  });
  const attackCard = room.state.players[0].hand.find(c=>c.id===cardId(1));
  await test('남의 손패 사용 차단',()=>as(bob,()=>fail(()=>invoke(room,'play',{instance_id:attackCard.instance_id,target_id:room.state.enemies[0].id}),/손패에 없는/)));
  await test('올바르지 않은 대상 및 미선택 차단',()=>as(alice,()=>fail(()=>invoke(room,'play',{instance_id:attackCard.instance_id,target_id:cid(2)}),/대상/)));
  room=await as(alice,()=>invoke(room,'play',{instance_id:attackCard.instance_id,target_id:room.state.enemies[0].id}));
  await test('피해와 에너지, 버림 더미 반영',async()=>{assert.equal(room.state.enemies[0].hp,94);assert.equal(room.state.players[0].energy,2);assert.equal(room.state.players[0].discard.length,1);});
  await test('사용한 카드 재사용 차단',()=>as(alice,()=>fail(()=>invoke(room,'play',{instance_id:attackCard.instance_id,target_id:room.state.enemies[0].id}),/손패에 없는/)));
  room=await as(alice,()=>invoke(room,'end'));
  await test('에테리얼이 유지보다 우선 / 소멸 효과',async()=>{
    assert.equal(room.state.players[0].exhaust.length,1);assert.equal(room.state.players[0].block,2);
    assert.equal(room.state.players[0].hand.length,2);assert.equal(room.state.round,1);
  });
  await test('종료 후 행동 차단',()=>as(alice,()=>fail(()=>invoke(room,'play',{instance_id:room.state.players[0].hand[0].instance_id}),/행동할 수/)));
  room=await as(bob,()=>invoke(room,'end'));
  await test('전원 종료 시 적 공격과 새 턴',async()=>{
    assert.equal(room.state.round,2);assert.equal(room.state.players[0].hp,46);assert.equal(room.state.players[0].block,0);
    assert.equal(room.state.players[0].energy,3);assert.equal(room.state.players[0].hand.length,7);assert.equal(room.state.players[0].ended,false);
    const p=room.state.players[0];assert.equal(p.hand.length+p.draw.length+p.discard.length+p.exhaust.length,p.cards.length);
  });
  await test('방장 강제 턴 종료 / 적 방어 행동',async()=>{
    room=await as(admin,()=>invoke(room,'force_end',{player_id:cid(1)}));room=await as(admin,()=>invoke(room,'force_end',{player_id:cid(2)}));
    assert.equal(room.state.round,3);assert.equal(room.state.enemies[0].block,8);
  });
  await test('방어·힘·약화·취약의 계산',async()=>{
    const value=await scalar("select combat_private.hit($1,10,$2) as value",[JSON.stringify({hp:50,block:4,vulnerable:1}),JSON.stringify({strength:2,weak:1})]);
    assert.equal(value.hp,41);assert.equal(value.block,0);
  });
  await test('드로우 상한 / 소멸 카드 재유입 없음',async()=>{
    const p={hand:Array.from({length:9},(_,i)=>i),draw:['a','b','c'],discard:['d'],exhaust:['z']};
    const value=await scalar('select combat_private.draw($1,5) as value',[JSON.stringify(p)]);
    assert.equal(value.hand.length,10);assert.equal(value.draw.length,2);assert.deepEqual(value.exhaust,['z']);
  });
  await test('회복 상한, 중독 누적, 에너지/드로우 효과',async()=>{
    const s={players:[{hp:10,max_hp:20,energy:1,hand:[],draw:[1,2],discard:[],poison:0}],enemies:[]};
    const value=await scalar('select combat_private.effects($1,0,$2) as value',[JSON.stringify(s),JSON.stringify([effect('heal',50),effect('energy',2),effect('draw',2),effect('poison',3)])]);
    assert.equal(value.players[0].hp,20);assert.equal(value.players[0].energy,3);assert.equal(value.players[0].hand.length,2);assert.equal(value.players[0].poison,3);
  });
  await test('승패 판정',async()=>{
    assert.equal(await scalar('select combat_private.outcome($1) as value',[JSON.stringify({players:[{hp:10}],enemies:[{hp:0}]})]),'victory');
    assert.equal(await scalar('select combat_private.outcome($1) as value',[JSON.stringify({players:[{hp:0}],enemies:[{hp:10}]})]),'defeat');
  });
  await test('에너지 부족 거부와 실패 요청 원자성',async()=>{
    const original = structuredClone(room.state);
    const noEnergy = structuredClone(original); noEnergy.players[0].energy=0;
    await db.query('update combat_rooms set state=$2 where id=$1',[room.id,JSON.stringify(noEnergy)]);
    const card=noEnergy.players[0].hand.find(c=>c.id===cardId(1));
    await as(alice,()=>fail(()=>invoke(room,'play',{instance_id:card.instance_id,target_id:noEnergy.enemies[0].id}),/에너지가 부족/));
    const after=await fresh(room.id);assert.equal(after.version,room.version);assert.deepEqual(after.state,noEnergy);
    await db.query('update combat_rooms set state=$2 where id=$1',[room.id,JSON.stringify(original)]);
  });
  await test('파워 분리, 소멸 시 발동 방지, 승리 저장, 종료 후 사용 차단',async()=>{
    const original = structuredClone(room);
    const state=structuredClone(room.state);const card=state.players[0].hand.find(c=>c.id===cardId(1));
    card.card_type='파워';state.rules[card.id].on_exhaust=[effect('block',3)];state.enemies[0].hp=1;state.enemies[0].block=0;
    await db.query('update combat_rooms set state=$2 where id=$1',[room.id,JSON.stringify(state)]);
    room=await as(alice,()=>invoke(room,'play',{instance_id:card.instance_id,target_id:state.enemies[0].id}));
    assert.equal(room.status,'victory');assert.ok(room.state.players[0].powers.some(c=>c.instance_id===card.instance_id));assert.equal(room.state.players[0].block,state.players[0].block);
    await as(alice,()=>fail(()=>invoke(room,'end'),/진행 중/));
    await db.query('update combat_rooms set state=$2,status=$3,version=$4 where id=$1',[original.id,JSON.stringify(original.state),original.status,original.version]);room=original;
  });
  await test('중독 처치 즉시 승리 / 쓰러진 적은 행동하지 않음',async()=>{
    const state=structuredClone(room.state);state.enemies[0].hp=2;state.enemies[0].poison=3;
    const value=await scalar('select combat_private.next_round($1) as value',[JSON.stringify(state)]);
    assert.equal(value.enemies[0].hp,0);assert.equal(value.enemies[0].poison,2);assert.equal(value.players[0].hp,state.players[0].hp);
  });
  await test('적 전멸 공격으로 패배 저장',async()=>{
    const original=structuredClone(room);const state=structuredClone(room.state);
    state.players.forEach(p=>{p.hp=1;p.ended=true;p.block=0});state.players[0].ended=false;
    state.enemies=[{...state.enemies[0],attack:999},{...state.enemies[0],id:'other-enemy',attack:999}];state.round=3;
    await db.query('update combat_rooms set state=$2 where id=$1',[room.id,JSON.stringify(state)]);
    room=await as(alice,()=>invoke(room,'end'));assert.equal(room.status,'defeat');assert.ok(room.state.players.every(p=>p.hp===0));
    await db.query('update combat_rooms set state=$2,status=$3,version=$4 where id=$1',[original.id,JSON.stringify(original.state),original.status,original.version]);room=original;
  });
  await test('대기실 퇴장 / 재참가 / 최신 카드 스냅샷',async()=>{
    let waiting=await as(admin,()=>scalar("select to_jsonb(public.combat_create_room('재참가 QA')) as value"));
    waiting=await as(alice,()=>invoke(waiting,'join'));waiting=await as(alice,()=>invoke(waiting,'leave'));
    assert.equal(waiting.state.players.length,0);await as(alice,async()=>assert.equal(await fresh(waiting.id),undefined));
    waiting=await as(alice,()=>invoke(waiting,'join'));assert.equal(waiting.state.players[0].cards.length,9);
  });
  await test('HP 0 / 빈 덱 / 100장 초과 참가 차단',async()=>{
    const waiting=await as(admin,()=>scalar("select to_jsonb(public.combat_create_room('덱 검증 QA')) as value"));
    await db.query('update characters set hp=0 where id=$1',[cid(1)]);
    await as(alice,()=>fail(()=>invoke(waiting,'join'),/HP/));await db.query('update characters set hp=50 where id=$1',[cid(1)]);
    await db.query('update character_cards set quantity=101 where id=$1',[cardId(1)]);
    await as(alice,()=>fail(()=>invoke(waiting,'join'),/1~100/));await db.query('update character_cards set quantity=6 where id=$1',[cardId(1)]);
    await db.query("insert into characters values($1,$2,'빈 덱',10,10,null)",[cid(9),outsider]);
    await as(outsider,()=>fail(()=>invoke(waiting,'join'),/1~100/));
  });
  await test('방 종료 후 행동 거부 / 결과 보존',async()=>{
    room=await as(admin,()=>invoke(room,'close'));assert.equal(room.status,'closed');
    await as(alice,()=>fail(()=>invoke(room,'end'),/진행 중/));assert.equal((await fresh(room.id)).status,'closed');
  });
  await test('프런트 카드/대상/의도/오류 도우미',async()=>{
    assert.equal(cardCost({energy:null}),0);assert.equal(targetSide(rule([effect('damage',2,'enemy')])),'enemies');
    assert.equal(uniqueCards(room.state.players).length,4);
    assert.deepEqual(enemyIntent({attack:6,guard:8,strength:2,weak:1},0,3,[{hp:10,name:'앨리스',vulnerable:1,ended:true}]),{label:'강타',amount:15,target:'앨리스'});
    assert.equal(enemyIntent({attack:6,guard:8,strength:2,weak:1},0,3,[{hp:10,name:'앨리스',vulnerable:1,ended:false}]).amount,10);
    assert.match(combatError({code:'PGRST202'}),/데이터베이스 설정/);
  });
  await test('종료 전 삭제와 일반 사용자 삭제 차단 / 생성 관리자 기록 삭제',async()=>{
    let deletable=await as(admin,()=>scalar("select to_jsonb(public.combat_create_room('삭제 QA')) as value"));
    await as(admin,()=>fail(()=>scalar('select public.combat_delete_room($1) as value',[deletable.id]),/종료한 뒤/));
    deletable=await as(admin,()=>invoke(deletable,'close'));
    await as(alice,()=>fail(()=>scalar('select public.combat_delete_room($1) as value',[deletable.id]),/관리자/));
    await as(admin,()=>scalar('select public.combat_delete_room($1) as value',[deletable.id]));
    assert.equal(await fresh(deletable.id),undefined);
  });
  await test('전투 테스트 복사 시 동일 카드 수량 병합',async()=>{
    const strike={id:cardId(1),card_name:'타격',grade:'기본',energy:1,card_effect:'6 피해'};
    const guard={id:cardId(2),card_name:'수비',grade:'일반',energy:1,card_effect:'방어 5'};
    const hand=[{...strike,drawId:'a'},{...guard,drawId:'b'},{...strike,drawId:'c'}];
    assert.deepEqual(groupCombatTestCards(hand).map(({card,quantity})=>[card.card_name,quantity]),[['타격',2],['수비',1]]);
    const copied=formatCombatTestCards([{name:'앨리스',hp:40,maxHp:50,hand}],3,true);
    assert.match(copied,/전투 · TURN 3/);
    assert.match(copied,/- 타격 x2 \(기본 · 1 e\)/);
    assert.match(copied,/- 수비 \(일반 · 1 e\)/);
    assert.equal((copied.match(/효과: 6 피해/g)||[]).length,1);
  });
  // 실제 기본 카드 테이블의 grade 컬럼 및 카드 접근 정책을 QA fixture에 보완합니다.
  await db.exec(`alter table character_cards add column grade text not null default '기본';
    grant select on characters to authenticated;
    grant select,insert,update,delete on character_cards to authenticated;
    alter table character_cards enable row level security;
    create policy card_owner on character_cards for all to authenticated
    using (exists(select 1 from characters c where c.id=character_id and (c.owner_id=auth.uid() or public.is_admin())))
    with check (exists(select 1 from characters c where c.id=character_id and (c.owner_id=auth.uid() or public.is_admin())));`);
  const presetSql = await readFile(new URL('../supabase/queries/add_card_combat_presets.sql',import.meta.url),'utf8');
  await test('카드 사전 설정 SQL 적용과 재적용',async()=>{await db.exec(presetSql);await db.exec(presetSql)});
  const readCards=async(id)=>(await db.query('select * from character_cards where character_id=$1 order by created_at,id',[id])).rows.map(normalizeOwnedCard);
  const saveCards=(id,cards)=>scalar('select public.combat_save_character_cards($1,$2) as value',[id,JSON.stringify(buildAdminCardRows(cards,id))]);
  let presetCards=await readCards(cid(1));
  const initialIds=presetCards.map(c=>c.id);const initialTimes=presetCards.map(c=>new Date(c.created_at).getTime());
  presetCards=presetCards.map(c=>({...c,combat_rule:c.id===cardId(1)?rule([effect('damage',9,'enemy')]):rule([])}));
  await test('관리자 사전 설정 저장, ID·생성일 유지',async()=>{
    presetCards=await as(admin,()=>saveCards(cid(1),presetCards));
    assert.deepEqual(presetCards.map(c=>c.id),initialIds);assert.deepEqual(presetCards.map(c=>new Date(c.created_at).getTime()),initialTimes);
    assert.deepEqual((await readCards(cid(1)))[0].combat_rule,presetCards[0].combat_rule);
  });
  await test('플레이어의 저장 RPC 및 직접 사전 설정 변경 차단',async()=>{
    await as(alice,()=>fail(()=>saveCards(cid(1),presetCards),/관리자/));
    await as(alice,()=>fail(()=>db.query('update character_cards set combat_rule=$2 where id=$1',[cardId(1),JSON.stringify(rule([]))]),/관리자/));
    await as(bob,async()=>assert.equal((await db.query('select * from character_cards where character_id=$1',[cid(1)])).rows.length,0));
  });
  await test('잘못된 두 번째 카드 설정으로 전체 저장 롤백',async()=>{
    const before=await readCards(cid(1));const bad=structuredClone(before);bad[0].card_name='롤백되어야 함';bad[1].combat_rule=rule([effect('damage',-3,'enemy')]);
    await as(admin,()=>fail(()=>saveCards(cid(1),bad),/범위/));assert.deepEqual(await readCards(cid(1)),before);
  });
  await test('다른 캐릭터 ID와 중복 카드 저장 거부',async()=>{
    await as(admin,()=>fail(()=>saveCards(cid(1),[{...presetCards[0],id:cardId(4)}]),/다른 캐릭터/));
    await as(admin,()=>fail(()=>saveCards(cid(1),[presetCards[0],presetCards[0]]),/중복/));
    assert.equal((await readCards(cid(1))).length,3);
  });
  let presetRoom=await as(admin,()=>scalar("select to_jsonb(public.combat_create_room('사전 설정 전투')) as value"));
  presetRoom=await as(alice,()=>invoke(presetRoom,'join',{rules:{[cardId(1)]:rule([effect('damage',999,'enemies')])}}));
  await test('참가 시 서버 사전 설정 자동 적용 / 클라이언트 주입 무시',async()=>{
    assert.equal(presetRoom.state.rules[cardId(1)].effects[0].amount,9);
    assert.deepEqual(presetRoom.state.rules[cardId(2)],rule([]));
  });
  await test('방 수정과 새 사전 설정은 서로 분리',async()=>{
    presetRoom=await as(admin,()=>invoke(presetRoom,'rule',{card_id:cardId(1),rule:rule([effect('damage',12,'enemy')])}));
    assert.equal((await readCards(cid(1))).find(c=>c.id===cardId(1)).combat_rule.effects[0].amount,9);
    presetCards=presetCards.map(c=>({...c,combat_rule:c.id===cardId(1)?rule([effect('damage',15,'enemy')]):c.combat_rule}));
    presetCards=await as(admin,()=>saveCards(cid(1),presetCards));
    assert.equal((await fresh(presetRoom.id)).state.rules[cardId(1)].effects[0].amount,12);
    presetRoom=await as(bob,()=>invoke(presetRoom,'join'));
    assert.equal(presetRoom.state.rules[cardId(1)].effects[0].amount,12);
  });
  await test('퇴장 시 이전 방 규칙 정리 / 재참가 시 최신 사전 설정',async()=>{
    presetRoom=await as(alice,()=>invoke(presetRoom,'leave'));assert.equal(presetRoom.state.rules[cardId(1)],undefined);
    presetRoom=await as(alice,()=>invoke(presetRoom,'join'));assert.equal(presetRoom.state.rules[cardId(1)].effects[0].amount,15);
  });
  await test('사전 설정 그대로 전투 시작과 실제 피해 판정',async()=>{
    presetRoom=await as(admin,()=>invoke(presetRoom,'rule',{card_id:cardId(4),rule:rule([])}));
    presetRoom=await as(admin,()=>invoke(presetRoom,'configure',{enemies:[{name:'적',hp:50,attack:1,guard:1}]}));
    presetRoom=await as(alice,()=>invoke(presetRoom,'ready'));presetRoom=await as(bob,()=>invoke(presetRoom,'ready'));presetRoom=await as(admin,()=>invoke(presetRoom,'start'));
    const card=presetRoom.state.players.find(p=>p.owner_id===alice).hand.find(c=>c.id===cardId(1));
    presetRoom=await as(alice,()=>invoke(presetRoom,'play',{instance_id:card.instance_id,target_id:presetRoom.state.enemies[0].id}));
    assert.equal(presetRoom.state.enemies[0].hp,35);
  });
  await test('사전 설정 해제 저장 / 진행 중 전투 보호',async()=>{
    presetCards=presetCards.map(c=>({...c,combat_rule:null}));await as(admin,()=>saveCards(cid(1),presetCards));
    assert.ok((await readCards(cid(1))).every(c=>c.combat_rule===null));
    assert.equal((await fresh(presetRoom.id)).state.rules[cardId(1)].effects[0].amount,15);
  });
  await test('효과 프런트 검증 / 저장 payload / 구형 스키마 기본값',async()=>{
    assert.match(validateCombatRule(rule([effect('draw',2,'enemy')])),/아군/);
    assert.match(validateCombatRule(rule([],{on_exhaust:[effect('heal',2,'ally')]})),/소멸/);
    assert.equal(validateCombatRule(null),'');assert.equal(validateCombatRule(rule([])),'');
    assert.equal(normalizeOwnedCard({card_name:'구형 카드'}).combat_rule,null);
    const row=buildAdminCardRows([{...presetCards[0],combat_rule:rule([effect('block',5)])}],cid(1))[0];
    assert.equal(row.id,presetCards[0].id);assert.equal(row.combat_rule.effects[0].amount,5);
  });
  await test('SQL 미적용·잘못된 효과는 저장 전 차단 / 통신 오류 유지',async()=>{
    const mock=(error)=>({from:()=>({select:()=>({limit:async()=>({error})})})});
    const missing={code:'42703',message:'column character_cards.combat_rule does not exist'};
    const cards=[{card_name:'타격',combat_rule:rule([effect('damage',6,'enemy')])}];
    await fail(()=>prepareCardSave(mock(missing),cards),/add_card_combat_presets.sql/);
    assert.equal(await prepareCardSave(mock(missing),[{card_name:'기본 카드',combat_rule:null}]),false);
    assert.equal(await prepareCardSave(mock(null),cards),true);
    await fail(()=>prepareCardSave(mock(new Error('network error')),cards),/network error/);
    await fail(()=>prepareCardSave(mock(null),[{card_name:'잘못된 카드',combat_rule:rule([effect('damage',null)])}]),/수치/);
  });
  const keywordSql = await readFile(new URL('../supabase/queries/fix_combat_card_keywords.sql',import.meta.url),'utf8');
  await test('키워드 수정 SQL 적용·재적용 / 신규 설치와 동일 RPC',async()=>{
    const extract=s=>s.match(/create or replace function public\.combat_room_action\([\s\S]*?\nend; \$\$;/)[0];
    assert.equal(extract(keywordSql),extract(sql));await db.exec(keywordSql);await db.exec(keywordSql);
  });
  // 통제된 로컬 방 스냅샷을 실제 인증 RPC로 처리합니다. 운영 DB 접근 없음.
  const unit=(id,owner)=>({id,owner_id:owner,name:owner===alice?'앨리스':'보브',hp:50,max_hp:50,energy:3,block:0,strength:0,weak:0,vulnerable:0,poison:0,ended:false,ready:true,cards:[],hand:[],draw:[],discard:[],exhaust:[],powers:[]});
  async function keywordFixture(cardExtra={},customRule=rule([]),options={}) {
    const card={id:cardId(80),instance_id:'keyword-card',card_name:'키워드 검증',energy:0,card_type:'스킬',card_drop_count:0,...cardExtra};
    const p=unit(cid(1),alice);p.hand=[card,...Array.from({length:4},(_,i)=>({id:cardId(81),instance_id:`hand-${i}`,card_name:'손패',card_type:'스킬'}))];
    p.draw=Array.from({length:12},(_,i)=>({id:cardId(81),instance_id:`draw-${i}`,card_name:'뽑기',card_type:'스킬'}));p.cards=[...p.hand,...p.draw];
    const state={players:[p,unit(cid(2),bob)],enemies:[{id:'enemy',name:'적',hp:100,max_hp:100,attack:0,guard:0,block:0,strength:0,weak:0,vulnerable:0,poison:0}],rules:{[cardId(80)]:customRule,[cardId(81)]:rule([])},round:1,log:[]};
    if(options.modify)options.modify(state);
    await db.query("update combat_rooms set status='active',state=$2 where id=$1",[presetRoom.id,JSON.stringify(state)]);
    return {room:await fresh(presetRoom.id),card};
  }
  const playFixture=async(f)=>as(alice,()=>invoke(f.room,'play',{instance_id:f.card.instance_id,target_id:'enemy'}));
  await test('추가 드로우는 사용 효과 뒤 1회 실행 / 현재 사용 카드 재드로우 방지',async()=>{
    const f=await keywordFixture({card_drop_count:2},rule([effect('draw',1)]));const r=await playFixture(f);const p=r.state.players[0];
    assert.equal(p.hand.length,7);assert.equal(p.draw.length,9);assert.equal(p.discard.length,1);assert.equal(p.discard[0].instance_id,f.card.instance_id);
    assert.ok(!p.hand.some(c=>c.instance_id===f.card.instance_id));assert.equal(r.state.players[1].hand.length,0);
    assert.equal(p.hand.length+p.draw.length+p.discard.length+p.exhaust.length+p.powers.length,p.cards.length);
  });
  await test('추가 드로우 999도 손패 10장 상한 / 소멸 더미 보존',async()=>{
    const f=await keywordFixture({card_drop_count:999});const r=await playFixture(f);
    assert.equal(r.state.players[0].hand.length,10);assert.equal(r.state.players[0].draw.length,6);
  });
  await test('에테리얼을 턴 안에 사용하면 버림 / 소멸 효과는 미발동',async()=>{
    const f=await keywordFixture({card_ethereal:true,card_drop_count:2},rule([],{on_exhaust:[effect('block',7)]}));const p=(await playFixture(f)).state.players[0];
    assert.equal(p.discard.length,1);assert.equal(p.exhaust.length,0);assert.equal(p.block,0);assert.equal(p.hand.length,6);
  });
  await test('사용 후 소멸은 사용 효과 → 추가 드로우 → 소멸 시 발동 순서',async()=>{
    const f=await keywordFixture({card_ethereal:true,card_drop_count:2},rule([effect('block',3)],{exhaust:true,on_exhaust:[effect('block',7),effect('draw',1)]}));const p=(await playFixture(f)).state.players[0];
    assert.equal(p.block,10);assert.equal(p.hand.length,7);assert.equal(p.exhaust.length,1);assert.equal(p.discard.length,0);
  });
  await test('턴 종료 에테리얼은 유지보다 우선 / 추가 드로우는 미발동',async()=>{
    const f=await keywordFixture({card_ethereal:true,card_retain:true,card_drop_count:9},rule([],{on_exhaust:[effect('block',7),effect('draw',1)]}));
    const r=await as(alice,()=>invoke(f.room,'end'));const p=r.state.players[0];
    assert.equal(p.exhaust.length,1);assert.equal(p.discard.length,4);assert.equal(p.hand.length,1);assert.equal(p.block,7);
    assert.equal(p.hand[0].instance_id,'draw-0');assert.equal(p.draw.length,11);
  });
  await test('일반 버림과 설명문만으로 소멸 시 효과가 발동하지 않음',async()=>{
    const f=await keywordFixture({card_exhaust_effect:'소멸 효과 설명',card_drop_effect:'카드 9장 뽑기'},rule([],{on_exhaust:[effect('block',7)]}));
    const p=(await playFixture(f)).state.players[0];assert.equal(p.block,0);assert.equal(p.hand.length,4);assert.equal(p.exhaust.length,0);assert.equal(p.discard.length,1);
  });
  await test('파워 영역 이동 / 재드로우와 소멸 시 발동 방지',async()=>{
    const f=await keywordFixture({card_type:'파워',card_drop_count:2},rule([effect('strength',3)],{on_exhaust:[effect('block',7)]}));
    const p=(await playFixture(f)).state.players[0];assert.equal(p.strength,3);assert.equal(p.block,0);assert.equal(p.powers.length,1);assert.equal(p.exhaust.length,0);
    const drawn=await scalar('select combat_private.draw($1,10) as value',[JSON.stringify({...p,hand:[],draw:[]})]);assert.equal(drawn.hand.length,0);assert.equal(drawn.powers.length,1);
  });
  await test('파워에도 명시한 사용 후 소멸은 우선 적용',async()=>{
    const f=await keywordFixture({card_type:'파워'},rule([],{exhaust:true,on_exhaust:[effect('block',7)]}));const p=(await playFixture(f)).state.players[0];
    assert.equal(p.block,7);assert.equal(p.exhaust.length,1);assert.equal(p.powers.length,0);
  });
  await test('유지 카드는 다음 턴까지 보존되고 기본 5장을 추가로 뽑음',async()=>{
    const f=await keywordFixture({card_retain:true});let r=await as(alice,()=>invoke(f.room,'end'));
    assert.equal(r.state.players[0].hand.length,1);r=await as(bob,()=>invoke(r,'end'));
    assert.equal(r.state.players[0].hand.length,6);assert.equal(r.state.players[0].hand[0].instance_id,f.card.instance_id);
  });
  for(const innateCount of [6,12]) await test(`선천 ${innateCount}장 실제 보유 덱 참가·첫 손패 상한`,async()=>{
    const own=[{...presetCards[0],quantity:innateCount,card_innate:true,card_retain:false,card_ethereal:false,combat_rule:rule([]),card_drop_count:0},{...presetCards[1],quantity:2,card_innate:false,combat_rule:rule([])}];
    await as(admin,()=>saveCards(cid(1),own));
    let r=await as(admin,()=>scalar("select to_jsonb(public.combat_create_room('선천 검증')) as value"));r=await as(alice,()=>invoke(r,'join'));
    r=await as(admin,()=>invoke(r,'configure',{enemies:[{name:'적',hp:100,attack:0,guard:0}]}));r=await as(alice,()=>invoke(r,'ready'));r=await as(admin,()=>invoke(r,'start'));
    const p=r.state.players[0];assert.equal(p.hand.length,Math.min(10,innateCount));assert.ok(p.hand.every(c=>c.card_innate));
    assert.equal(p.draw.filter(c=>c.card_innate).length,Math.max(0,innateCount-10));
  });
  await test('추가 드로우 잘못된 입력은 저장 전 거부 / 원본 카드 보존',async()=>{
    const mock={from:()=>({select:()=>({limit:async()=>({error:null})})})};
    for(const count of [null,-1,1.5,1000]) await fail(()=>prepareCardSave(mock,buildAdminCardRows([{card_name:'드로우',card_drop_count:count}],cid(1))),/추가 드로우/);
    const before=await readCards(cid(1));await as(admin,()=>fail(()=>saveCards(cid(1),[{...before[0],card_drop_count:1.5}]),/범위/));assert.deepEqual(await readCards(cid(1)),before);
  });
  await test('프런트 설명과 카드 이동·추가 드로우 표시 일치',async()=>{
    assert.equal(extraCardDraw({card_drop_count:2}),2);assert.equal(extraCardDraw({}),0);
    assert.match(cardDestination({card_type:'파워'},rule([])),/파워/);assert.match(cardDestination({card_type:'파워'},rule([],{exhaust:true})),/소멸/);
    assert.deepEqual(Object.keys(EFFECT_HELP).sort(),Object.keys(EFFECTS).sort());assert.match(KEYWORD_HELP.card_ethereal,/턴 종료/);assert.match(KEYWORD_HELP.drop,/합산/);
  });
  await test('대표 대상은 실제 효과에서 파생되어 저장되고 구형 설명은 보존',async()=>{
    const r=rule([effect('block',3),effect('damage',6,'enemy')]);assert.equal(representativeCardTarget(r),'적 1명');
    const row=buildAdminCardRows([{card_name:'복합 카드',card_target:'자신',card_drop_count:2,combat_rule:r,card_exhaust_effect:'기존 설명'}],cid(1))[0];
    assert.equal(row.card_target,'적 1명');assert.equal(row.card_exhaust_effect,'기존 설명');assert.equal(row.combat_rule.exhaust,false);
    assert.equal(representativeCardTarget(rule([])),'');
  });
  console.log(`\n${passed} checks passed. Production database was not accessed.`);
} finally { await db.close(); }
