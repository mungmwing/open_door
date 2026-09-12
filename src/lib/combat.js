export const ROOM_STATUS = { waiting: '참가 대기', active: '전투 중', victory: '승리', defeat: '패배', closed: '종료' };
export const EFFECTS = { damage: '피해', block: '방어도', heal: 'HP 회복', draw: '드로우', energy: '에너지', strength: '힘', weak: '약화', vulnerable: '취약', poison: '중독', personal_energy: '전용 에너지 획득', generate_consumable: '무작위 소비 아이템 생성', thorns:'가시', dexterity:'민첩', frail:'손상', regeneration:'재생', metallicize:'금속화', barricade:'바리케이드', intangible:'무형', artifact:'인공물', lose_hp:'HP 손실', add_card:'전투 덱에 카드 삽입', summon:'아군 소환' };
export const POWER_KINDS = ['strength','thorns','dexterity','regeneration','metallicize','barricade','intangible','artifact'];
export const STATUS_KINDS = [...POWER_KINDS,'weak','vulnerable','poison','frail'];
export const effectMax = kind => ['generate_consumable','summon'].includes(kind) ? 3 : ['draw','energy','add_card'].includes(kind) ? 10 : 999;
export const TARGETS = { self: '자신', enemy: '선택한 적', enemies: '모든 적', random_enemy: '무작위 적', ally: '선택한 아군', allies: '모든 아군' };
export const effectText = (effect) => `${TARGETS[effect.target] || effect.target} · ${EFFECTS[effect.kind] || effect.kind} ${effect.amount}${effect.kind === 'generate_consumable' ? `개 (후보 ${effect.item_ids?.length || 0}종)` : effect.kind === 'add_card' ? `장 · ${effect.card?.card_name || '카드 미설정'} → ${{hand:'손패',draw:'뽑기 더미',discard:'버림 더미'}[effect.pile] || '더미 미설정'}` : effect.kind === 'summon' ? `기 · ${effect.monster_name || '지정 몬스터'}` : ''}`;
export const personalCost = (rule) => Math.max(0, Number(rule?.personal_cost) || 0);
export const resourceName = (player) => player?.personal_config?.name || '전용 에너지';
export const canPayCard = (player, card, rule) => (player?.energy || 0) >= cardCost(card) && (player?.personal_energy || 0) >= personalCost(rule);
export const cardCost = (card) => Math.max(0, Number(card.energy) || 0);
export const extraCardDraw = (card) => Math.max(0, Math.min(999, Math.trunc(Number(card?.card_drop_count) || 0)));
export const cardDestination = (card, rule) => rule?.exhaust ? '사용 후 소멸' : card?.card_type === '파워' ? '사용 후 파워 영역으로 이동' : '사용 후 버림';
export function representativeCardTarget(rule) {
  const effects = rule?.effects || [];
  const target = effects.find((e) => ['enemy', 'ally'].includes(e.target))?.target || effects[0]?.target;
  return { self:'자신', enemy:'적 1명', enemies:'전체 적', random_enemy:'무작위 적', ally:'아군 1명', allies:'전체 아군' }[target] || '';
}
export const targetSide = (rule) => rule?.effects?.some((e) => e.target === 'enemy') ? 'enemies' : rule?.effects?.some((e) => e.target === 'ally') ? 'players' : null;
export const emptyCombatRule = () => ({ playable: true, exhaust: false, effects: [], on_exhaust: [] });
export function playersForViewer(players=[],userId) {
  const self=players.find(p=>p.owner_id===userId);
  return self ? [self,...players.filter(p=>p!==self)] : [...players];
}
export function validateCombatRule(rule, nested = false) {
  if (rule == null) return '';
  if (typeof rule !== 'object' || typeof rule.playable !== 'boolean' || typeof rule.exhaust !== 'boolean') return '사용 가능·소멸 설정을 확인해 주세요.';
  if (rule.personal_cost !== undefined && (!Number.isInteger(rule.personal_cost) || rule.personal_cost < 0 || rule.personal_cost > 999)) return '전용 에너지 비용은 0~999 사이의 정수로 입력해 주세요.';
  for (const field of ['effects', 'on_exhaust', 'on_turn_end']) {
    const list = field === 'on_turn_end' && rule[field] === undefined ? [] : rule[field];
    if (!Array.isArray(list) || list.length > 8) return '효과는 종류별로 최대 8개까지 설정할 수 있습니다.';
    for (const effect of list) {
      if (!effect || !Object.hasOwn(EFFECTS, effect.kind) || !Object.hasOwn(TARGETS, effect.target)) return '효과 종류와 대상을 확인해 주세요.';
      const allyOnly = ['draw', 'energy', 'personal_energy'].includes(effect.kind);
      const max = effectMax(effect.kind);
      if (!Number.isInteger(effect.amount) || effect.amount < 1 || effect.amount > max) return `효과 수치는 1~${max} 사이의 정수로 입력해 주세요.`;
      if (allyOnly && !['self', 'ally', 'allies'].includes(effect.target)) return '드로우·에너지는 아군에게만 적용할 수 있습니다.';
      if (field !== 'effects' && ['enemy', 'ally'].includes(effect.target)) return '소멸 효과·턴 종료 효과는 자신·전체·무작위 대상을 사용해 주세요.';
      if (nested && ['add_card','summon','generate_consumable'].includes(effect.kind)) return '삽입 카드 안에는 카드·아이템 생성이나 소환을 넣을 수 없습니다.';
      if (effect.kind === 'summon' && (effect.target !== 'self' || !isUuid(effect.monster_id))) return '소환할 몬스터를 선택해 주세요. 소환 대상은 자신입니다.';
      if (effect.kind === 'add_card') {
        if (!['hand','draw','discard'].includes(effect.pile)) return '카드를 넣을 더미를 선택해 주세요.';
        const c = effect.card;
        if (!c?.card_name?.trim() || c.card_name.trim().length > 100 || !Number.isInteger(c.energy) || c.energy < 0 || c.energy > 10 || !['공격','스킬','파워','상태','저주'].includes(c.card_type) || ['card_retain','card_innate','card_ethereal'].some(k=>typeof c[k] !== 'boolean')) return '삽입 카드의 이름·비용·타입·키워드를 확인해 주세요.';
        if (!c.combat_rule) return '삽입 카드의 효과를 설정해 주세요.';
        if (c.card_drop_count !== undefined && (!Number.isInteger(c.card_drop_count) || c.card_drop_count < 0 || c.card_drop_count > 999)) return '삽입 카드의 추가 드로우는 0~999 사이의 정수입니다.';
        const error = validateCombatRule(c.combat_rule, true); if (error) return error;
      }
      if (effect.kind === 'generate_consumable' && (effect.target !== 'self' || !Array.isArray(effect.item_ids) || effect.item_ids.length < 1 || effect.item_ids.length > 30 || new Set(effect.item_ids).size !== effect.item_ids.length || effect.item_ids.some(id => !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)))) return '생성할 소비 아이템을 1~30종 선택해 주세요. 생성 대상은 자신입니다.';
    }
  }
  if (rule.effects.some((e) => e.target === 'enemy') && rule.effects.some((e) => e.target === 'ally')) return '한 카드의 선택 대상은 적 또는 아군 중 한 종류만 지정할 수 있습니다.';
  return '';
}
export const isUuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
export function uniqueCards(players = []) {
  const cards = new Map();
  for (const player of players) for (const card of player.cards || []) {
    if (!cards.has(card.id)) cards.set(card.id, { ...card, ownerName: player.name });
  }
  return [...cards.values()];
}
export function enemyIntent(enemy, index, round, players) {
  if (enemy.actions?.length) {
    const action = enemy.actions[((round - (enemy.summoned_round || 1)) % enemy.actions.length + enemy.actions.length) % enemy.actions.length];
    const living = players.filter(p=>p.hp>0);
    const target = living[(round-1+index)%living.length];
    return { label:action.name, amount:null, target: action.effects.some(e=>e.target==='enemy') ? target?.name : null, description:action.effects.map(effectText).join(' / ') };
  }
  const step = (round - (enemy.summoned_round || 1) + index) % 3;
  if (step === 1) return { label: '방어', amount: Math.floor((enemy.guard + (enemy.dexterity || 0)) * (enemy.frail > 0 ? .75 : 1)), target: null };
  const living = players.filter((p) => p.hp > 0);
  const target = living[(round - 1 + index) % living.length];
  let amount = Math.max(0, enemy.attack * (step === 2 ? 2 : 1) + (enemy.strength || 0));
  if (enemy.weak > 0) amount = Math.floor(amount * .75);
  // 아직 종료하지 않은 플레이어의 취약은 적 행동 전에 한 번 감소합니다.
  if ((target?.vulnerable || 0) - (target?.ended ? 0 : 1) > 0) amount = Math.floor(amount * 1.5);
  if ((target?.intangible || 0) - (target?.ended ? 0 : 1) > 0) amount = Math.min(1,amount);
  return { label: step === 2 ? '강타' : '공격', amount, target: target?.name };
}
export function combatError(error) {
  const message = error?.message || '연결에 문제가 생겼습니다. 다시 시도해 주세요.';
  if (/COMBAT_STALE/.test(message)) return '다른 행동이 먼저 반영되었습니다. 최신 상태를 확인하고 다시 눌러 주세요.';
  if (['PGRST202', 'PGRST205', '42P01', '42883'].includes(error?.code) || /schema cache|Could not find the function/.test(message)) {
    return '전투 기능의 데이터베이스 설정이 필요합니다. 관리자가 제공된 create_realtime_combat.sql 쿼리를 적용한 뒤 새로고침해 주세요.';
  }
  return message;
}
