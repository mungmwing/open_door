export function plainNpcName(npc = {}) {
  const direct = String(npc.npcName || npc.npc_name || '').trim();
  if (direct) return direct;
  return String(npc.title || '').replace(/^\[[^\]]+\]\s*/, '').trim();
}

export function mergeSessionReferences(post, characters = [], npcs = [], ownerColors = new Map()) {
  const characterMap = new Map(characters.map(character => [character.id, character]));
  const npcMap = new Map(npcs.map(npc => [npc.id, npc]));
  const reference = (type, id) => type === 'character' ? characterMap.get(id) : type === 'npc' ? npcMap.get(id) : null;
  const name = (type, item, fallback = '') => type === 'npc' ? plainNpcName(item) || fallback : String(item?.name || fallback);
  const avatar = (type, item, fallback = '') => type === 'npc' ? item?.image_url || item?.imageUrl || fallback : item?.avatar_url || fallback;
  const color = item => ownerColors.get(item?.owner_id) || '';

  const sessionEntries = (post.sessionEntries || []).map(entry => {
    const type = entry.type === 'dialogue' ? entry.speakerType : entry.actorType;
    const id = entry.type === 'dialogue' ? entry.speakerId : entry.actorId;
    const item = reference(type, id);
    if (!item) return entry;
    return entry.type === 'dialogue'
      ? { ...entry, speakerName: name(type, item, entry.speakerName), speakerImageUrl: avatar(type, item, entry.speakerImageUrl), accentColor: entry.accentColor || color(item) }
      : { ...entry, actorName: name(type, item, entry.actorName), accentColor: entry.accentColor || color(item) };
  });
  const sessionParticipants = (post.sessionParticipants || []).map(participant => {
    const item = reference(participant.participantType, participant.participantId);
    return item ? { ...participant, name: name(participant.participantType, item, participant.name), accentColor: participant.accentColor || color(item) } : participant;
  });
  return { ...post, sessionEntries, sessionParticipants };
}
