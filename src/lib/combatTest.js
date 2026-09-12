function combatTestCardKey(card) {
  if (card?.id) return `id:${card.id}`;
  return JSON.stringify([
    card?.card_name || '',
    card?.grade || '',
    Number(card?.energy) || 0,
    card?.card_effect || '',
    card?.card_exhaust_effect || '',
    Number(card?.card_drop_count) || 0,
    card?.card_drop_effect || ''
  ]);
}

export function groupCombatTestCards(cards = []) {
  const grouped = [];
  const indexes = new Map();
  for (const card of cards) {
    const key = combatTestCardKey(card);
    const groupIndex = indexes.get(key);
    if (groupIndex !== undefined) {
      grouped[groupIndex].quantity += 1;
      continue;
    }
    indexes.set(key, grouped.length);
    grouped.push({ card, quantity: 1 });
  }
  return grouped;
}

export function formatCombatTestPlayerCards(player, includeEffects = false) {
  const lines = [`[${player.name}] (HP: ${player.hp} / ${player.maxHp})`, '', '드롭 카드:', ''];
  const groupedCards = groupCombatTestCards(player.hand || []);
  if (groupedCards.length) {
    groupedCards.forEach(({ card, quantity }) => {
      const quantityText = quantity > 1 ? ` x${quantity}` : '';
      lines.push(`- ${card.card_name || '이름 없는 카드'}${quantityText} (${card.grade || '기본'} · ${Number(card.energy) || 0} e)`);
      if (includeEffects) {
        if (card.card_effect) lines.push(`  효과: ${card.card_effect}`);
        if (card.card_exhaust_effect) lines.push(`  소멸: ${card.card_exhaust_effect}`);
        if (card.card_drop_count > 0 || card.card_drop_effect) lines.push(`  추가 드로우${card.card_drop_count > 0 ? ` ${card.card_drop_count}장` : ''}: ${card.card_drop_effect || '추가 드로우'}`);
      }
    });
  } else {
    lines.push('- 없음');
  }
  return lines.join('\n');
}

export function formatCombatTestCards(players, turn, includeEffects = false) {
  return [`전투 · TURN ${turn}`, '', players.map((player) => formatCombatTestPlayerCards(player, includeEffects)).join('\n\n')].join('\n').trim();
}
