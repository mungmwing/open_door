<script>
  import CardEffectEditor from './CardEffectEditor.svelte';
  import EffectHelp from './EffectHelp.svelte';
  import { emptyCombatRule } from '../lib/combat';
  import { RELIC_EVENTS, EVENT_HELP, validateRelics } from '../lib/combatExpansion';
  export let value = null;
  export let disabled = false;
  export let onChange = () => {};
  $: problem=validateRelics(value);
  function update(i,key,next) { onChange(value.map((entry,n)=>n===i?{...entry,[key]:next}:entry)); }
</script>
<fieldset {disabled} class="relic-editor"><legend>유물 자동 전투 효과</legend>
  <div class="relic-help">발동 방식 <EffectHelp label="유물 발동 방식" text={EVENT_HELP} /></div>
  {#each value || [] as entry,i}<section>
    <label>발동 시점<select value={entry.event} on:change={e=>update(i,'event',e.currentTarget.value)}>{#each Object.entries(RELIC_EVENTS) as [key,label]}<option value={key}>{label}</option>{/each}</select></label>
    <CardEffectEditor itemMode automatic {disabled} value={{...emptyCombatRule(),effects:entry.effects}} onChange={rule=>update(i,'effects',rule.effects)} />
    <button type="button" class="subtle-btn" on:click={()=>onChange(value.filter((_,n)=>n!==i))}>이 발동 조건 삭제</button>
  </section>{/each}
  <button type="button" class="subtle-btn" disabled={disabled || value?.length>=8} on:click={()=>onChange([...(value||[]),{event:'battle_start',effects:[]}])}>발동 조건 추가</button>
  {#if value != null}<button type="button" class="subtle-btn" on:click={()=>onChange(null)}>전투 효과 설정 해제</button>{/if}
  {#if problem}<p role="alert">{problem}</p>{/if}
</fieldset>
<style>.relic-editor{min-width:0;border:1px solid #526075;border-radius:10px;padding:14px;color:#ddd5bf}.relic-help{display:flex;gap:8px;align-items:center;flex-wrap:wrap}section{padding:14px 0;border-bottom:1px solid #46526a;margin-bottom:14px}label{display:grid;gap:8px}select{min-height:42px;background:#101b29;color:#eee;border:1px solid #526075;border-radius:6px;padding:8px;width:100%}button{margin:8px 6px 0 0}p{color:#efb0a4}</style>
