import { POWER_KINDS, validateCombatRule, emptyCombatRule } from './combat.js';
export const EXPANSION_SQL = 'add_combat_monsters_relics.sql';
export const RELIC_EVENTS = { battle_start:'전투 시작', turn_start:'내 턴 시작', turn_end:'내 턴 종료', card_play:'카드 사용 후', attack_play:'공격 카드 사용 후' };
export const EVENT_HELP = '인벤토리에서 장착한 유물을 종류별 1회 자동 적용합니다. 동일 유물의 수량은 중첩되지 않습니다. 전투 시작 시 장착 상태와 효과를 확정하며 진행 중에는 바뀌지 않습니다. 위에서부터 발동하며 카드 사용 후→공격 카드 사용 후 순서입니다. 자동 효과는 추가 카드 사용 이벤트를 발생시키지 않습니다. 전투 시작에는 시작 효과 다음 첫 턴 시작 효과를 적용합니다.';
export const defaultMonster = () => ({name:'',description:'',hp:40,attack:6,guard:5,powers:[],actions:[]});
export async function prepareExpansionRules(client,rules) {
  const oldKinds=['damage','block','heal','draw','energy','strength','weak','vulnerable','poison','personal_energy','generate_consumable'];
  if(!rules.some(rule=>rule && (rule.on_turn_end?.length || [...(rule.effects||[]),...(rule.on_exhaust||[])].some(e=>!oldKinds.includes(e.kind))))) return;
  const {error}=await client.from('items').select('relic_effects').limit(0);
  if(!error) return;
  if(['42703','PGRST204'].includes(error.code) && /relic_effects/.test(error.message||'')) throw new Error(`${EXPANSION_SQL}을 먼저 적용해 주세요. 변경사항은 저장하지 않았습니다.`);
  throw error;
}
export function generatedCard(preset='wound') {
  return {card_name:({wound:'상처',dazed:'어지러움',burn:'화상',slimed:'점액'})[preset] || '새 카드',energy:preset==='slimed'?1:0,card_type:'상태',card_retain:false,card_innate:false,card_ethereal:preset==='dazed',combat_rule:{...emptyCombatRule(),playable:preset==='slimed',exhaust:preset==='slimed',on_turn_end:preset==='burn'?[{kind:'lose_hp',amount:2,target:'self'}]:[]}};
}
export function validateRelics(events) {
  if (events == null) return '';
  if (!Array.isArray(events) || events.length > 8) return '유물 발동 조건은 최대 8개입니다.';
  for (const event of events) {
    if (!Object.hasOwn(RELIC_EVENTS,event.event)) return '유물 발동 시점을 확인해 주세요.';
    const error=validateCombatRule({...emptyCombatRule(),effects:event.effects}); if(error) return error;
    if(event.effects.some(e=>['enemy','ally'].includes(e.target))) return '유물은 자신·전체·무작위 대상으로 설정해 주세요.';
  }
  return '';
}
export function validateMonster(monster) {
  if (!monster.name?.trim() || monster.name.trim().length>60) return '몬스터 이름은 1~60자입니다.';
  if (typeof monster.description !== 'string' || monster.description.length>2000) return '설명은 2000자까지입니다.';
  for(const [key,min,max] of [['hp',1,99999],['attack',0,999],['guard',0,999]]) if(!Number.isInteger(monster[key]) || monster[key]<min || monster[key]>max) return `${key} 수치는 ${min}~${max} 정수입니다.`;
  const powerError=validateCombatRule({...emptyCombatRule(),effects:monster.powers}); if(powerError) return powerError;
  if(monster.powers.some(e=>!POWER_KINDS.includes(e.kind) || e.target!=='self')) return '시작 파워는 자신에게 적용하는 강화 효과입니다.';
  if(!Array.isArray(monster.actions) || monster.actions.length>8) return '반복 행동은 최대 8개입니다.';
  for (const action of monster.actions) {
    if(!action.name?.trim() || action.name.trim().length>60) return '행동 이름은 1~60자입니다.';
    const error=validateCombatRule({...emptyCombatRule(),effects:action.effects}); if(error) return error;
    if(action.effects.some(e=>['draw','energy','personal_energy','generate_consumable','summon'].includes(e.kind) || e.target==='ally' || (e.kind==='add_card' && !['enemy','enemies','random_enemy'].includes(e.target)))) return '몬스터는 자원·소환 효과를 쓸 수 없으며 카드 삽입은 상대 진영에 설정해 주세요. 선택 아군 대신 자신·모든 아군을 사용하세요.';
  }
  return '';
}
export async function prepareRelicSave(client, events) {
  const error=validateRelics(events); if(error) throw new Error(error);
  const result=await client.from('items').select('relic_effects').limit(0);
  if(!result.error) return true;
  if(!['42703','PGRST204'].includes(result.error.code) || !/relic_effects/.test(result.error.message||'')) throw result.error;
  if(events != null) throw new Error(`${EXPANSION_SQL}을 먼저 적용해 주세요. 변경사항은 저장하지 않았습니다.`);
  return false;
}
