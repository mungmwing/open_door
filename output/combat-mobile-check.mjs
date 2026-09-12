import { chromium } from 'C:/Users/jeongwon/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs';
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
const base = 'http://localhost:5181';
const api = async (user, name, args = {}) => {
  const result = await (await fetch(`${base}/__combat_qa`, {method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({user,name,args})})).json();
  if (result.error) throw new Error(result.error.message);
  return result.data;
};
let room = await api('admin','combat_create_room',{p_name:'잿빛 성문 · 전투 화면 확인'});
const act = async (user, action, payload = {}) => room = await api(user,'combat_room_action',{p_room_id:room.id,p_version:room.version,p_action:action,p_payload:payload});
await act('alice','join');
await act('bob','join');
await act('admin','configure',{enemies:Array.from({length:6},(_,i)=>({name:['성문 파수꾼','그림자 추종자','철갑 수호자','고대의 망령','독 안개 사냥꾼','심연의 감시자'][i],hp:80,attack:6,guard:8}))});
for (const player of room.state.players) {
  for (const card of [...new Map(player.cards.map(c=>[c.id,c])).values()]) await act('admin','rule',{card_id:card.id,rule:{playable:true,exhaust:false,effects:[{kind:'damage',amount:6,target:'enemy'}],on_exhaust:[]}});
}
await act('alice','ready'); await act('bob','ready'); await act('admin','start');
const browser = await chromium.launch({headless:true,channel:'msedge'});
const page = await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1,isMobile:true,hasTouch:true});
const errors=[];page.on('pageerror',error=>errors.push(error.message));
await page.goto(`${base}/output/combat-qa/ui/index.html?user=alice#combat/${room.id}`);
await page.locator('.battle-card').first().waitFor();
await mkdir('output/combat-ui-review',{recursive:true});
const checks=[];
for (const width of [320,390,600,768,1280]) {
  await page.setViewportSize({width,height:width===1280?900:844});
  const size = await page.evaluate(()=>{
    const box=s=>{const e=document.querySelector(s);const r=e.getBoundingClientRect();return {height:Math.round(r.height),top:Math.round(r.top),width:Math.round(r.width),scrollWidth:e.scrollWidth,clientWidth:e.clientWidth}};
    return {page:document.documentElement.scrollWidth,viewport:innerWidth,arena:box('.battle-arena'),enemies:box('.battle-enemies'),hand:box('.battle-hand'),card:box('.battle-card'),end:box('.battle-hand-section .primary-btn')};
  });
  assert.equal(size.page,width,'No page horizontal overflow');
  assert.ok(size.enemies.height<240,'Six enemies stay compact');
  assert.ok(size.hand.height<350,'Hand stays one row');
  checks.push({width,...size});
  await page.screenshot({path:`output/combat-ui-review/${width}.png`,fullPage:true});
}
await page.setViewportSize({width:390,height:844});
await page.locator('.battle-card').first().click();
await page.locator('.battle-quick-target select').selectOption(room.state.enemies[5].id);
assert.equal(await page.locator('.battle-enemy.targeted').count(),1);
await page.screenshot({path:'output/combat-ui-review/selected.png',fullPage:true});
await page.locator('.battle-play-bar .primary-btn').click();
await page.locator('.battle-play-bar').waitFor({state:'hidden'});
room = await api('alice','room',{id:room.id});
assert.equal(room.state.enemies[5].hp,74,'Quick target plays against offscreen sixth enemy');
assert.equal(room.state.players[0].energy,2);
await page.locator('.battle-hand-section .battle-section-head .primary-btn').click();
await page.getByRole('button',{name:'다른 플레이어를 기다리는 중'}).waitFor();
await page.locator('.battle-inventory > summary').click();
assert.ok(await page.locator('.consumable-panel').isVisible());
assert.equal(errors.length,0,errors.join('\n'));
await writeFile('output/combat-ui-review/checks.json',JSON.stringify({roomId:room.id,checks,errors,interaction:'Card selected, sixth enemy targeted, damage and energy checked, turn ended, inventory expanded'},null,2));
console.log(JSON.stringify({roomId:room.id,checks,errors}));
await browser.close();
