import { validateCombatRule } from './combat.js';
import { prepareExpansionRules } from './combatExpansion.js';
export const RESOURCE_SQL = 'add_combat_consumables_energy.sql';
export const defaultPersonalEnergy = () => ({name:'',initial:0,max:10,per_turn:0,reset_each_turn:false});
export function validatePersonalEnergy(config) {
  if (typeof config?.name !== 'string') return '전용 에너지 명칭을 입력해 주세요.';
  if (!config.name.trim()) return '';
  if (config.name.trim().length > 30) return '전용 에너지 명칭은 30자까지입니다.';
  if (!Number.isInteger(config.max) || config.max < 1 || config.max > 999) return '전용 에너지 최대량은 1~999 사이의 정수입니다.';
  if (['initial','per_turn'].some(key=>!Number.isInteger(config[key]) || config[key]<0 || config[key]>config.max)) return '시작량과 턴 회복량은 0~최대량 사이의 정수입니다.';
  return '';
}
export async function prepareResourceSave(client, config, cards=[]) {
  const error = validatePersonalEnergy(config); if(error) throw new Error(error);
  const result = await client.from('characters').select('personal_energy,inventory_version').limit(0);
  if (!result.error) return true;
  const missing = ['42703','PGRST204'].includes(result.error.code) && /personal_energy|inventory_version/.test(result.error.message || '');
  if (!missing) throw result.error;
  if(config?.name?.trim() || cards.some(c=>c.combat_rule?.personal_cost || [...(c.combat_rule?.effects||[]),...(c.combat_rule?.on_exhaust||[])].some(e=>['personal_energy','generate_consumable'].includes(e.kind)))) throw new Error(`${RESOURCE_SQL}을 먼저 적용해 주세요. 변경사항은 저장하지 않았습니다.`);
  return false;
}

export async function prepareConsumableSave(client, effects) {
  if (effects != null) {
    const problem=validateCombatRule({playable:true,exhaust:false,effects,on_exhaust:[]});
    if(problem) throw new Error(problem);
    if(effects.some(e=>e.kind==='generate_consumable')) throw new Error('소비 아이템은 다른 아이템을 생성할 수 없습니다.');
  }
  if(effects) await prepareExpansionRules(client,[{effects}]);
  const result=await client.from('items').select('combat_effects').limit(0);
  if(!result.error) return true;
  const missing=['42703','PGRST204'].includes(result.error.code) && /combat_effects/.test(result.error.message||'');
  if(!missing) throw result.error;
  if(effects != null) throw new Error(RESOURCE_SQL+'을 먼저 적용해 주세요. 변경사항은 저장하지 않았습니다.');
  return false;
}
