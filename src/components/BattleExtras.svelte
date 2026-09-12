<script>
  import EffectHelp from './EffectHelp.svelte';
  import CardEffectEditor from './CardEffectEditor.svelte';
  import { EFFECTS, STATUS_KINDS, emptyCombatRule, effectText, validateCombatRule, enemyIntent } from '../lib/combat';
  import { EFFECT_HELP } from '../lib/cardHelp';
  import { generatedCard, RELIC_EVENTS, EVENT_HELP } from '../lib/combatExpansion';
  export let state;
  export let host=false;
  export let active=false;
  export let busy=false;
  export let canAct=false;
  export let selectedSide=null;
  export let selectedTarget='';
  export let onTarget=()=>{};
  export let onAct=()=>{};
  let playerId='';
  let injection={...emptyCombatRule(),effects:[{kind:'add_card',target:'self',amount:1,pile:'discard',card:generatedCard()}]};
  $: living=state.players.filter(p=>p.hp>0);
  $: if(!living.some(p=>p.id===playerId)) playerId=living[0]?.id || '';
</script>
<div class="battle-extras">
  {#if state.summons?.length}<section><h3>소환 아군 ({state.summons.filter(u=>u.hp>0).length}/6)</h3><div class="summon-list">
    {#each state.summons as unit,i}<article class:fallen={unit.hp<=0}>
      <button type="button" class:selected={selectedTarget===unit.id} disabled={busy||!canAct||selectedSide!=='players'||unit.hp<=0} on:click={()=>onTarget(unit.id)}><strong>{unit.name}</strong><span>HP {unit.hp}/{unit.max_hp} · 방어 {unit.block}</span><small>{unit.summoner_name}의 소환물 · {unit.hp>0?enemyIntent(unit,i,state.round,state.enemies).label:'쓰러짐'}</small></button>
      {#each STATUS_KINDS.filter(k=>unit[k]) as key}<div class="help-row">{EFFECTS[key]} {unit[key]} <EffectHelp label={`${unit.name} ${EFFECTS[key]}`} text={EFFECT_HELP[key]} /></div>{/each}
    </article>{/each}
  </div></section>{/if}
  <details><summary>유물과 전투 효과 도움말</summary>
    <div class="help-row">유물 적용 <EffectHelp label="유물 적용" text={EVENT_HELP} /></div>
    {#each state.players as player}<div class="relic-player"><strong>{player.name} · 적용 유물 {player.relics?.length || 0}종</strong>
      {#each player.relics || [] as relic}<p>◇ {relic.name}</p>{#each relic.events as event}<small>{RELIC_EVENTS[event.event]}: {event.effects.map(effectText).join(' / ') || '효과 없음'}</small>{/each}{/each}
    </div>{/each}
    {#each STATUS_KINDS as key}<div class="help-row">{EFFECTS[key]} <EffectHelp label={`전투 ${EFFECTS[key]}`} text={EFFECT_HELP[key]} /></div>{/each}
    {#each [...state.enemies,...(state.summons||[])].filter(u=>u.actions?.length) as unit}<details><summary>{unit.name}의 반복 행동</summary>{#each unit.actions as action}<p>{action.name}</p>{#each action.effects as effect}<small>{effectText(effect)}</small>{/each}{/each}</details>{/each}
  </details>
  {#if host && active}<details><summary>관리자: 플레이어 전투 덱에 카드 삽입</summary><form on:submit|preventDefault={()=>onAct('inject_card',{player_id:playerId,effect:injection.effects[0]})}>
    <label>받을 플레이어<select bind:value={playerId} disabled={busy}>{#each living as p}<option value={p.id}>{p.name}</option>{/each}</select></label>
    <CardEffectEditor itemMode allowedKinds={['add_card']} allowedTargets={['self']} value={injection} disabled={busy} onChange={next=>injection={...next,effects:next.effects.slice(-1)}} />
    <button class="primary-btn" disabled={busy||!playerId||injection.effects.length!==1||!!validateCombatRule(injection)}>전투 덱에 삽입</button>
  </form></details>{/if}
</div>
<style>.battle-extras{margin:14px 0;color:#d2c8b4;font-size:13px}h3{font-size:15px;margin:8px 0}.summon-list{display:flex;gap:10px;overflow-x:auto;padding:4px}.summon-list article{flex:0 0 190px;border:1px solid #607b73;border-radius:8px;background:#172824;padding:10px}.summon-list button{display:grid;gap:6px;width:100%;padding:8px;background:transparent;border:1px solid transparent;color:#e2e3cf;text-align:left;border-radius:6px}.summon-list button:disabled{opacity:1}.summon-list button.selected{border-color:#d8bd75}.fallen{opacity:.5}.summon-list small{color:#b8cabb}details{border:1px solid #4b544b;border-radius:8px;padding:12px;margin:10px 0;background:#172021}summary{cursor:pointer}.help-row{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin:10px 0}.relic-player{padding:12px 0;border-bottom:1px solid #465249}.relic-player small,details>small{display:block;line-height:1.8;overflow-wrap:anywhere}p{margin:10px 0 4px}form{padding-top:14px}label{display:grid;gap:6px}select{min-height:42px;background:#0e1724;color:#eee;width:100%;border:1px solid #47536a;border-radius:6px}form>button{margin-top:14px}</style>
