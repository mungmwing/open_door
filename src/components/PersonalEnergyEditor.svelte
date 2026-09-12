<script>
  import { defaultPersonalEnergy, validatePersonalEnergy } from '../lib/combatResources';
  export let value = {};
  export let disabled = false;
  export let onChange = () => {};
  $: config = {...defaultPersonalEnergy(),...value};
  $: problem = validatePersonalEnergy(config);
  const set = (key, next) => onChange({...config,[key]:next});
</script>
<fieldset {disabled} class="personal-energy-editor">
  <legend>전용 개인 에너지</legend>
  <label>에너지 명칭<input value={config.name} maxlength="30" placeholder="예: 분노, 마력, 집중" on:input={e=>set('name',e.currentTarget.value)} /></label>
  <p>명칭을 비우면 사용하지 않습니다. 기본 에너지와 별도로 관리하며 매 전투 시작량부터 시작합니다.</p>
  {#if config.name.trim()}
    <div class="energy-fields">{#each [['initial','전투 시작량'],['max','최대 보유량'],['per_turn','매 턴 회복량']] as [key,label]}<label>{label}<input type="number" min={key === 'max' ? 1 : 0} max={key === 'max' ? 999 : config.max} step="1" required value={config[key]} on:input={e=>set(key,e.currentTarget.value === '' ? null : Number(e.currentTarget.value))} /></label>{/each}</div>
    <label class="energy-reset"><input type="checkbox" checked={config.reset_each_turn} on:change={e=>set('reset_each_turn',e.currentTarget.checked)} />매 턴 0으로 초기화한 뒤 회복</label>
    <p>{config.reset_each_turn ? '남은 에너지는 다음 턴에 사라집니다.' : '남은 에너지는 다음 턴에도 유지됩니다.'} 카드의 획득 효과와 사용 비용에서 이 에너지를 사용할 수 있습니다.</p>
  {/if}
  {#if problem}<p class="energy-error" role="alert">{problem}</p>{/if}
</fieldset>
<style>
  .personal-energy-editor { min-width:0; margin:18px 0; padding:16px; border:1px solid #685b85; border-radius:10px; }
  legend { color:#d6c3ed; padding:0 8px; font-weight:600; }
  label { display:grid; gap:6px; color:#c2c9d6; font-size:13px; }
  input { width:100%; box-sizing:border-box; padding:10px; color:#edf0f6; background:#101927; border:1px solid #48546a; border-radius:7px; font:inherit; }
  p { color:#b2bfd2; font-size:13px; line-height:1.7; }
  .energy-fields { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:10px; }
  .energy-reset { display:flex; align-items:center; gap:8px; margin-top:14px; }
  .energy-reset input { width:18px; height:18px; }
  .energy-error { color:#ffc1b7; }
  @media(max-width:640px) { .energy-fields { grid-template-columns:1fr; } }
</style>
