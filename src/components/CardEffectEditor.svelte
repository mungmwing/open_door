<script>
  import { onMount } from 'svelte';
  import { supabase } from '../supabaseClient';
  import { generatedCard } from '../lib/combatExpansion';
  import { EFFECTS, TARGETS, emptyCombatRule, effectText, validateCombatRule, cardDestination, extraCardDraw, effectMax } from '../lib/combat';
  import { EFFECT_HELP, KEYWORD_HELP } from '../lib/cardHelp';
  import EffectHelp from './EffectHelp.svelte';

  export let value = null;
  export let optional = false;
  export let disabled = false;
  export let onChange = () => {};
  export let card = null;
  export let editCard = false;
  export let onCardChange = () => {};
  export let catalogItems = [];
  export let personalEnergyName = '';
  export let itemMode = false;
  export let allowedKinds = null;
  export let allowedTargets = null;
  export let automatic = false;
  export let nested = false;
  let monsterCatalog = [];
  let monsterError = '';
  onMount(async()=>{ if(!supabase || nested) return; const {data,error}=await supabase.from('combat_monsters').select('id,name').order('name'); monsterCatalog=data||[]; monsterError=error ? (['42P01','PGRST205'].includes(error.code) ? 'add_combat_monsters_relics.sql을 먼저 적용해 주세요.' : error.message) : ''; });
  $: draft = { ...(value || emptyCombatRule()), on_turn_end:value?.on_turn_end || [] };
  $: extraDraw = extraCardDraw(card);
  $: explicitDraw = draft.effects.filter((e) => e.kind === 'draw' && ['self', 'allies'].includes(e.target)).reduce((sum, e) => sum + (Number(e.amount) || 0), 0);
  $: problem = validateCombatRule(value);

  function targets(field, kind) {
    return Object.entries(TARGETS).filter(([key]) =>
      (!automatic && field === 'effects' || !['enemy', 'ally'].includes(key)) &&
      (!allowedTargets || allowedTargets.includes(key)) &&
      (!['draw', 'energy', 'personal_energy'].includes(kind) || ['self', 'ally', 'allies'].includes(key)) && (!['generate_consumable','summon'].includes(kind) || key === 'self'));
  }
  function setEffect(field, index, key, next) {
    const effects = draft[field].map((effect, i) => {
      if (i !== index) return effect;
      const updated = { ...effect, [key]: next };
      if (key === 'kind') {
        updated.amount = Math.min(updated.amount || 1, effectMax(next));
        if (next === 'generate_consumable') updated.item_ids = updated.item_ids || [];
        else delete updated.item_ids;
        if(next==='add_card') { updated.card=updated.card || generatedCard(); updated.pile=updated.pile || 'discard'; }
        else { delete updated.card; delete updated.pile; }
        if(next!=='summon') { delete updated.monster_id; delete updated.monster_name; }
      }
      if (!targets(field, updated.kind).some(([target]) => target === updated.target)) updated.target = 'self';
      return updated;
    });
    onChange({ ...draft, [field]: effects });
  }
  function addEffect(field) {
    if (draft[field].length >= 8) return;
    const kind=allowedKinds?.[0] || (automatic ? 'block' : 'damage');
    const choices=targets(field,kind).map(([key])=>key);
    onChange({ ...draft, [field]: [...draft[field], { kind, amount: kind==='damage'?6:1, target:automatic ? 'self' : choices.includes('enemy') ? 'enemy' : choices.includes('random_enemy') ? 'random_enemy' : choices[0], ...(kind==='add_card'?{card:generatedCard(),pile:'discard'}:{}) }] });
  }
</script>

<fieldset class="card-rule-editor" {disabled}>
    {#if !itemMode}<div class="rule-options">
      {#each [['playable', '사용 가능'], ['exhaust', '사용 후 소멸']] as [key, label]}
        <div class="rule-option"><label class="rule-toggle"><input type="checkbox" checked={draft[key]} on:change={(event) => onChange({ ...draft, [key]: event.currentTarget.checked })} />{label}</label><EffectHelp {label} text={KEYWORD_HELP[key]} /></div>
      {/each}
      {#if editCard}
        {#each [['card_retain', '유지'], ['card_innate', '선천'], ['card_ethereal', '에테리얼']] as [key, label]}
          <div class="rule-option"><label class="rule-toggle"><input type="checkbox" checked={card[key]} on:change={(event) => onCardChange(key, event.currentTarget.checked)} />{label}</label><EffectHelp {label} text={KEYWORD_HELP[key]} /></div>
        {/each}
      {/if}
    </div>
    <div class="rule-description"><label>{personalEnergyName || '전용 에너지'} 사용 비용<input aria-label="전용 에너지 사용 비용" type="number" min="0" max="999" step="1" value={draft.personal_cost ?? 0} on:input={(event) => onChange({...draft,personal_cost:event.currentTarget.value === '' ? null : Number(event.currentTarget.value)})} /></label><p class="rule-help">기본 에너지와 별도로 사용 전에 차감합니다. 0이면 소모하지 않습니다.</p></div>{/if}
    {#if card?.card_retain && card?.card_ethereal}<p class="rule-help">유지와 에테리얼이 함께 켜져 있어 턴 종료에는 소멸합니다.</p>{/if}
    {#if card?.card_type === '파워'}<div class="help-heading">파워 카드 <EffectHelp label="파워 카드" text={KEYWORD_HELP.type} /></div>{/if}
    {#each (itemMode ? [['effects', '적용 효과']] : [['effects', '사용 효과'], ['on_exhaust', '소멸 시 발동 효과'], ['on_turn_end','손에 남았을 때 턴 종료 효과']]) as [field, title]}
      <section class="rule-effects">
        <div class="help-heading"><h4>{title} <span>{draft[field].length}/8</span></h4><EffectHelp label={title} text={KEYWORD_HELP[field]} /></div>
        {#if editCard && field !== 'on_turn_end'}
          {@const descriptionKey = field === 'effects' ? 'card_effect' : 'card_exhaust_effect'}
          <label class="rule-description">{field === 'effects' ? '카드 효과 설명 (참고)' : '소멸 시 설명 (참고)'}<textarea rows="2" value={card[descriptionKey] || ''} placeholder="설명은 참고용입니다. 실제 효과는 아래에서 설정하세요." on:input={(event) => onCardChange(descriptionKey, event.currentTarget.value)}></textarea></label>
        {/if}
        {#each draft[field] as effect, i}
          <div class="rule-effect-row">
            <div><label>효과 종류<select aria-label={`${title} ${i + 1} 종류`} value={effect.kind} on:change={(event) => setEffect(field, i, 'kind', event.currentTarget.value)}>
              {#each Object.entries(EFFECTS).filter(([key])=>(!allowedKinds || allowedKinds.includes(key)) && (!nested || !['add_card','summon','generate_consumable'].includes(key)) && (!itemMode || key !== 'generate_consumable')) as [key, text]}<option value={key}>{text}</option>{/each}
            </select></label><div class="help-heading">{EFFECTS[effect.kind]}<EffectHelp label={`${title} ${i + 1} ${EFFECTS[effect.kind]}`} text={EFFECT_HELP[effect.kind]} /></div></div>
            <label>수치<input aria-label={`${title} ${i + 1} 수치`} type="number" value={effect.amount} min="1" max={effectMax(effect.kind)} step="1" required on:input={(event) => setEffect(field, i, 'amount', event.currentTarget.value === '' ? null : Number(event.currentTarget.value))} /></label>
            <div><label>대상<select aria-label={`${title} ${i + 1} 대상`} value={effect.target} on:change={(event) => setEffect(field, i, 'target', event.currentTarget.value)}>
              {#each targets(field, effect.kind) as [key, text]}<option value={key}>{text}</option>{/each}
            </select></label><div class="help-heading">대상 안내<EffectHelp label={`${title} ${i + 1} 대상`} text={KEYWORD_HELP.effectTarget} /></div></div>
            <button class="rule-remove" type="button" aria-label={`${title} ${i + 1} 삭제`} on:click={() => onChange({ ...draft, [field]: draft[field].filter((_, n) => n !== i) })}>×</button>
          </div>
          {#if effect.kind === 'summon'}
            <label>소환할 몬스터<select value={effect.monster_id || ''} on:change={event=>{const id=event.currentTarget.value; const effects=draft[field].map((e,n)=>n===i?{...e,monster_id:id,monster_name:monsterCatalog.find(m=>m.id===id)?.name || ''}:e);onChange({...draft,[field]:effects});}}><option value="">몬스터 선택</option>{#each monsterCatalog as monster}<option value={monster.id}>{monster.name}</option>{/each}</select></label>
            {#if monsterError}<p class="rule-error">{monsterError}</p>{/if}
            {#if effect.monster_id && !monsterCatalog.some(m=>m.id===effect.monster_id)}<p class="rule-warning">기존 소환 대상이 목록에 없습니다. 몬스터를 다시 선택해 주세요.</p>{/if}
            <p class="rule-help"><a href="#admin/monsters" target="_blank" rel="noopener">몬스터 관리 열기</a> · 저장된 몬스터를 새 전투 시작 시 복사합니다.</p>
          {/if}
          {#if effect.kind === 'add_card' && !nested}
            <fieldset class="generation-pool"><legend>삽입할 카드 사전 설정</legend>
              <div class="rule-options">{#each [['wound','상처'],['dazed','어지러움'],['burn','화상'],['slimed','점액']] as [key,label]}<button type="button" class="subtle-btn" on:click={()=>setEffect(field,i,'card',generatedCard(key))}>{label} 불러오기</button>{/each}</div>
              <label>삽입 위치<select value={effect.pile || 'discard'} on:change={e=>setEffect(field,i,'pile',e.currentTarget.value)}><option value="discard">버림 더미</option><option value="draw">뽑기 더미 (무작위 위치)</option><option value="hand">손패 (초과 시 버림)</option></select></label>
              {#if effect.card}
                <label>카드 이름<input value={effect.card.card_name} maxlength="100" on:input={e=>setEffect(field,i,'card',{...effect.card,card_name:e.currentTarget.value})} /></label>
                <label>기본 에너지 비용<input type="number" min="0" max="10" value={effect.card.energy} on:input={e=>setEffect(field,i,'card',{...effect.card,energy:e.currentTarget.value===''?null:Number(e.currentTarget.value)})} /></label>
                <label>카드 타입<select value={effect.card.card_type} on:change={e=>setEffect(field,i,'card',{...effect.card,card_type:e.currentTarget.value})}>{#each ['공격','스킬','파워','상태','저주'] as type}<option>{type}</option>{/each}</select></label>
                <svelte:self nested editCard card={effect.card} value={effect.card.combat_rule} {disabled} onChange={rule=>setEffect(field,i,'card',{...effect.card,combat_rule:rule})} onCardChange={(key,value)=>setEffect(field,i,'card',{...effect.card,[key]:value})} />
              {/if}
            </fieldset>
          {/if}
          {#if effect.kind === 'generate_consumable'}
            <fieldset class="generation-pool"><legend>생성할 소비 아이템 후보 ({effect.item_ids?.length || 0}/30)</legend>
              {#each catalogItems.filter(item=>item.item_type === '소비') as item}
                <label class="rule-toggle"><input type="checkbox" checked={effect.item_ids?.includes(item.id)} disabled={disabled || (item.combat_effects == null && !effect.item_ids?.includes(item.id))} on:change={(event)=>setEffect(field,i,'item_ids',event.currentTarget.checked ? [...(effect.item_ids||[]),item.id] : (effect.item_ids||[]).filter(id=>id!==item.id))} />{item.name}{item.combat_effects == null ? ' · 전투 효과 미설정' : ''}</label>
              {:else}<p class="rule-help">아이템 관리에서 소비 아이템과 전투 효과를 먼저 등록해 주세요.</p>{/each}
              {#each (effect.item_ids||[]).filter(id=>!catalogItems.some(item=>item.id===id)) as missing}<p class="rule-warning">목록에 없는 후보: {missing} <button type="button" on:click={()=>setEffect(field,i,'item_ids',effect.item_ids.filter(id=>id!==missing))}>제외</button></p>{/each}
            </fieldset>
          {/if}
        {/each}
        <button class="subtle-btn" type="button" disabled={disabled || draft[field].length >= 8} on:click={() => addEffect(field)}>{title} 추가</button>
        {#if field === 'effects' && editCard}
          <div class="rule-draw">
            <div class="help-heading"><strong>추가 드로우</strong><EffectHelp label="추가 드로우" text={KEYWORD_HELP.drop} /></div>
            <label>사용 후 추가로 뽑을 카드 수<input aria-label="추가 드로우 개수" type="number" min="0" max="999" step="1" required value={card.card_drop_count === undefined ? 0 : card.card_drop_count ?? ''} on:input={(event) => onCardChange('card_drop_count', event.currentTarget.value === '' ? null : Number(event.currentTarget.value))} /></label>
            <label class="rule-description">추가 드로우 설명 (참고)<textarea rows="2" value={card.card_drop_effect || ''} on:input={(event) => onCardChange('card_drop_effect', event.currentTarget.value)}></textarea></label>
            <p class="rule-help">기존 추가 드롭 개수입니다. 카드 사용 시 자동으로 뽑습니다. 손패는 최대 10장입니다.</p>
          </div>
        {/if}
      </section>
    {/each}
    {#if draft.on_exhaust.length && !draft.exhaust && !card?.card_ethereal}<p class="rule-warning">소멸 시 발동 효과가 있지만 소멸 조건이 꺼져 있습니다. 사용 후 소멸 또는 에테리얼을 켜야 발동합니다.</p>{/if}
    {#if extraDraw && explicitDraw}<p class="rule-warning">사용 효과 드로우 {explicitDraw}장과 추가 드로우 {extraDraw}장은 합산됩니다. 같은 효과를 두 번 입력하지 않았는지 확인하세요.</p>{/if}
    {#if problem}<p class="rule-error" role="alert">{problem}</p>{:else}
      <div class="rule-preview" aria-label="전투 효과 미리보기">
        <strong>실제 전투 적용</strong>
        {#if optional && value == null}<p>{itemMode ? '사용 효과' : '사용·소멸 효과'} 미설정 · 아래에서 설정 완료하거나 효과를 추가하세요.</p>{/if}
        {#if !itemMode}<p>{draft.playable ? '사용 가능' : '사용 불가'} · {cardDestination(card, draft)}{draft.personal_cost ? ` · ${personalEnergyName || '전용 에너지'} ${draft.personal_cost} 소모` : ''}</p>{/if}
        {#each [['card_retain','유지'],['card_innate','선천'],['card_ethereal','에테리얼']] as [key,label]}{#if card?.[key]}<p>{label}: {KEYWORD_HELP[key]}</p>{/if}{/each}
        {#each draft.effects as effect}<p>{effectText(effect)}</p>{:else}<p>사용 효과 없음</p>{/each}
        {#if extraDraw > 0}<p>사용 효과 처리 후: 자신 · 추가 드로우 {extraDraw}장 (손패 최대 10장)</p>{/if}
        {#each draft.on_exhaust as effect}<p>소멸 시 발동: {effectText(effect)}</p>{/each}
        {#each draft.on_turn_end as effect}<p>손에 남으면 턴 종료: {effectText(effect)}</p>{/each}
      </div>
    {/if}
    {#if optional}
      <div class="rule-setting-state">{#if value == null}<button class="subtle-btn" type="button" on:click={() => onChange(draft)}>현재 효과 설정 완료</button>{:else}<span>효과 설정됨</span><button class="subtle-btn" type="button" on:click={() => onChange(null)}>{itemMode ? '사용 효과' : '사용·소멸 효과'} 설정 해제</button>{/if}</div>
      <p class="rule-help">{itemMode ? '아이템 저장 후 새 전투에 적용됩니다.' : '전체 변경사항 저장 후 새로 참가하는 방에 적용됩니다.'} 설명을 적는 것만으로 수치 효과가 추가되지는 않습니다.</p>
    {/if}
</fieldset>

<style>
  .card-rule-editor { min-width:0; margin:0; padding:0; border:0; font-size:14px; }
  .rule-toggle { display:flex!important; flex-direction:row!important; align-items:center; gap:8px!important; color:#e4e8ef; font-size:14px; }
  .rule-toggle input { width:18px!important; height:18px; margin:0; accent-color:#d8bd75; }
  .rule-help { margin:12px 0 0; color:#aebbcf; font-size:14px; line-height:1.7; }
  .rule-options { display:flex; gap:18px; flex-wrap:wrap; margin:18px 0; }
  .rule-effects { margin-top:20px; }
  .rule-effects h4 { margin:0; color:#e3e8f0; font-size:15px; }
  .rule-effects h4 span { color:#aebbcf; font-weight:400; margin-left:8px; }
  .rule-effect-row { display:grid; grid-template-columns:minmax(0,1.1fr) minmax(68px,.55fr) minmax(0,1fr) 32px; align-items:start; gap:8px; max-width:100%; margin:14px 0; padding:10px; overflow:hidden; border-radius:8px; background:#152031; }
  .rule-effect-row > * { min-width:0; }
  .card-rule-editor label { display:grid; gap:5px; color:#bfcadd; font-size:13px; min-width:0; }
  .card-rule-editor input,.card-rule-editor select,.card-rule-editor textarea { box-sizing:border-box; width:100%; min-width:0; min-height:42px; padding:8px; border:1px solid #47536a; border-radius:7px; background:#0e1724; color:#f3f4f7; font:inherit; font-size:14px; }
  .card-rule-editor textarea { resize:vertical; line-height:1.6; }
  .rule-toggle input { min-height:0; }
  .help-heading, .rule-option { display:flex; align-items:center; flex-wrap:wrap; gap:8px; color:#bccadd; font-size:13px; margin:8px 0; }
  .rule-option { padding:8px 10px; border:1px solid #425066; border-radius:8px; margin:0; }
  .rule-description { margin:10px 0; }
  .rule-draw { margin-top:18px; padding:12px; border:1px solid #435345; border-radius:8px; }
  .rule-draw input { max-width:120px; }
  .rule-warning { color:#ecd494; font-size:13px; line-height:1.6; }
  .rule-setting-state { display:flex; flex-wrap:wrap; align-items:center; gap:12px; margin-top:14px; color:#c4d3b9; }
  .generation-pool { min-width:0; margin:8px 0 16px; border:1px solid #47536a; border-radius:8px; padding:12px; }
  .generation-pool .rule-toggle { margin:8px 0; }
  .rule-remove { min-height:42px; padding:0; border:0; background:transparent; color:#efaaaa; font-size:24px; }
  .rule-preview { margin-top:18px; padding:14px; border:1px solid #586047; border-radius:8px; color:#e5d8b4; background:#222a25; }
  .rule-preview strong { font-size:14px; }
  .rule-preview p { margin:7px 0 0; font-size:14px; }
  .rule-error { margin-top:12px; color:#ffc1b7; font-size:14px; }
  .card-rule-editor :focus-visible { outline:2px solid #d8bd75; outline-offset:2px; }
  .card-rule-editor button:disabled { opacity:.5; cursor:default; }
  @media(max-width:640px) {
    .rule-effect-row { grid-template-columns:minmax(0,1fr) 76px 32px; }
    .rule-effect-row > :first-child { grid-column:1/3; }
    .rule-effect-row > :nth-child(2) { grid-row:2; grid-column:1/3; }
    .rule-effect-row > :nth-child(3) { grid-row:3; grid-column:1/3; }
    .rule-remove { grid-column:3; grid-row:1/4; }
  }
</style>
