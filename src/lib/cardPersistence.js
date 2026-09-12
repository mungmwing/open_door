import { validateCombatRule, representativeCardTarget } from './combat.js';
import { prepareExpansionRules } from './combatExpansion.js';

export const CARD_PRESET_SQL_NOTICE = '전투 효과를 저장하려면 add_card_combat_presets.sql을 먼저 적용해 주세요. 기존 카드는 변경하지 않았습니다.';

export function normalizeOwnedCard(card) {
  return { energy: 0, card_exhaust_effect: '', card_drop_effect: '', card_drop_count: 0,
    card_retain: false, card_innate: false, card_ethereal: false, card_type: '스킬', card_target: '자신', combat_rule: null, ...card };
}

export function buildAdminCardRows(cards, characterId) {
  return cards.filter((card) => card.card_name?.trim()).map((card) => ({
    ...(card.id ? { id: card.id } : {}), character_id: characterId,
    card_name: card.card_name.trim(), card_effect: card.card_effect?.trim() || '',
    card_exhaust_effect: card.card_exhaust_effect?.trim() || '', card_drop_effect: card.card_drop_effect?.trim() || '',
    card_drop_count: card.card_drop_count === undefined ? 0 : card.card_drop_count === null ? null : Number(card.card_drop_count),
    card_retain: Boolean(card.card_retain), card_innate: Boolean(card.card_innate), card_ethereal: Boolean(card.card_ethereal),
    card_type: card.card_type || '스킬', card_target: representativeCardTarget(card.combat_rule) || card.card_target || '자신',
    quantity: Math.max(1, Number(card.quantity) || 1), energy: Math.max(0, Number(card.energy) || 0), grade: card.grade || '기본',
    combat_rule: card.combat_rule == null ? null : structuredClone(card.combat_rule)
  }));
}

// 저장/삭제 전에 호출합니다. 통신·권한 오류를 컬럼 미적용으로 오인하지 않습니다.
export async function prepareCardSave(client, cards) {
  for (const card of cards) {
    if (card.card_drop_count !== undefined && (!Number.isInteger(card.card_drop_count) || card.card_drop_count < 0 || card.card_drop_count > 999)) throw new Error(`${card.card_name}: 추가 드로우 개수는 0~999 사이의 정수로 입력해 주세요.`);
    const problem = validateCombatRule(card.combat_rule);
    if (problem) throw new Error(`${card.card_name}: ${problem}`);
  }
  await prepareExpansionRules(client,cards.map(c=>c.combat_rule));
  const { error } = await client.from('character_cards').select('combat_rule').limit(0);
  if (!error) return true;
  const missingColumn = ['42703', 'PGRST204'].includes(error.code) && /combat_rule/.test(error.message || '');
  if (!missingColumn) throw error;
  if (cards.some((card) => card.combat_rule != null)) throw new Error(CARD_PRESET_SQL_NOTICE);
  return false;
}
