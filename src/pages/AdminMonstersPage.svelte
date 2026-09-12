<script>
  import { onMount } from 'svelte';
  import { supabase } from '../supabaseClient';
  import CardEffectEditor from '../components/CardEffectEditor.svelte';
  import EffectHelp from '../components/EffectHelp.svelte';
  import { EFFECTS, POWER_KINDS, emptyCombatRule, effectText } from '../lib/combat';
  import { defaultMonster, validateMonster, EXPANSION_SQL } from '../lib/combatExpansion';
  export let authReady=false;
  export let profileLoading=false;
  export let isAdmin=false;
  let monsters=[], draft=defaultMonster(), loading=false, busy=false, error='', notice='', search='';
  let mounted=false, wasAdmin=false;
  const actionKinds=Object.keys(EFFECTS).filter(k=>!['draw','energy','personal_energy','generate_consumable','summon'].includes(k));
  $: visible=monsters.filter(m=>`${m.name} ${m.description}`.includes(search.trim()));
  $: if(mounted && authReady && !profileLoading && isAdmin && !wasAdmin){wasAdmin=true;load();}
  $: if(!isAdmin){wasAdmin=false;monsters=[];draft=defaultMonster();}
  onMount(()=>{mounted=true;});
  async function load(){loading=true;error='';try{const r=await supabase.from('combat_monsters').select('*').order('name');if(r.error)throw r.error;monsters=r.data||[];}catch(e){error=['42P01','PGRST205'].includes(e.code)?`${EXPANSION_SQL}을 먼저 적용해 주세요.`:e.message;}finally{loading=false;}}
  async function save(){error=validateMonster(draft);notice='';if(error||busy)return;busy=true;try{const {id,...fields}=draft;const payload={name:fields.name.trim(),description:fields.description,hp:fields.hp,attack:fields.attack,guard:fields.guard,powers:fields.powers,actions:fields.actions};const r=id?await supabase.from('combat_monsters').update(payload).eq('id',id).select().single():await supabase.from('combat_monsters').insert(payload).select().single();if(r.error)throw r.error;draft=structuredClone(r.data);await load();notice='몬스터를 저장했습니다. 새 방 편성과 새 전투의 소환에 적용됩니다.';}catch(e){error=e.message;}finally{busy=false;}}
  async function remove(monster){if(!confirm(`“${monster.name}”을 삭제할까요? 이 몬스터를 소환하는 카드는 새 전투 시작 전에 다시 설정해야 합니다.`))return;busy=true;error='';try{const r=await supabase.from('combat_monsters').delete().eq('id',monster.id);if(r.error)throw r.error;if(draft.id===monster.id)draft=defaultMonster();await load();}catch(e){error=e.message;}finally{busy=false;}}
  function setAction(i,key,value){draft={...draft,actions:draft.actions.map((a,n)=>i===n?{...a,[key]:value}:a)};}
</script>
<section class="admin-page panel monster-page">
  {#if !authReady || profileLoading}<p>관리자 권한을 확인하는 중입니다.</p>{:else if !isAdmin}<h1>관리자 권한이 필요합니다</h1><a href="#home">홈으로</a>{:else}
  <div class="page-heading"><div><p class="eyebrow">MONSTER CATALOG</p><h1>몬스터 관리</h1><p>적 편성과 아군 소환에 사용할 몬스터를 미리 설정합니다.</p></div><a class="subtle-btn" href="#admin">← 관리자 페이지</a><a class="subtle-btn" href="#combat">전투방</a></div>
  {#if error}<p class="error" role="alert">{error}</p>{/if}{#if notice}<p role="status">{notice}</p>{/if}
  <div class="monster-layout"><form class="admin-card editor-form" on:submit|preventDefault={save}>
    <div class="form-section-head"><h2>{draft.id?'몬스터 수정':'새 몬스터 추가'}</h2><button type="button" class="subtle-btn" disabled={busy} on:click={()=>{draft=defaultMonster();notice='';error='';}}>새 몬스터</button></div>
    <fieldset disabled={busy}><div class="field-grid"><label class="field-wide">이름<input bind:value={draft.name} maxlength="60" required /></label><label>HP<input type="number" bind:value={draft.hp} min="1" max="99999" step="1" required /></label><label>기본 공격<input type="number" bind:value={draft.attack} min="0" max="999" step="1" required /></label><label>기본 방어<input type="number" bind:value={draft.guard} min="0" max="999" step="1" required /></label><label class="field-wide">설명<textarea bind:value={draft.description} maxlength="2000" rows="2"></textarea></label></div>
    <div class="help-row"><h3>시작 파워</h3><EffectHelp label="시작 파워" text="전투 시작 또는 소환 직후 자신에게 한 번 부여합니다. 힘·가시·민첩·재생·금속화·바리케이드·무형·인공물을 설정할 수 있습니다." /></div>
    <CardEffectEditor itemMode allowedKinds={POWER_KINDS} allowedTargets={['self']} value={{...emptyCombatRule(),effects:draft.powers}} onChange={rule=>draft={...draft,powers:rule.effects}} />
    <div class="help-row"><h3>반복 행동 ({draft.actions.length}/8)</h3><EffectHelp label="반복 행동" text="비워 두면 기본 공격→방어→2배 강타 순환을 사용합니다. 행동을 추가하면 아래 목록을 첫 행동부터 반복합니다. 각 행동에 입력한 수치가 실제 판정에 쓰이며 기본 공격·방어와 자동 합산되지 않습니다. 대상의 적/아군은 행동하는 몬스터의 진영 기준입니다. 소환 후에는 플레이어가 아군이 됩니다. 카드 삽입은 덱을 가진 상대만 적용합니다." /></div>
    {#each draft.actions as action,i}<section class="monster-action"><label>행동 {i+1} 이름<input value={action.name} maxlength="60" required on:input={e=>setAction(i,'name',e.currentTarget.value)} /></label>
      <CardEffectEditor itemMode allowedKinds={actionKinds} allowedTargets={['self','enemy','enemies','random_enemy','allies']} value={{...emptyCombatRule(),effects:action.effects}} onChange={rule=>setAction(i,'effects',rule.effects)} />
      <button type="button" class="subtle-btn" on:click={()=>draft={...draft,actions:draft.actions.filter((_,n)=>n!==i)}}>행동 삭제</button>
    </section>{/each}
    <div class="form-actions"><button type="button" class="subtle-btn" disabled={draft.actions.length>=8} on:click={()=>draft={...draft,actions:[...draft.actions,{name:'공격',effects:[{kind:'damage',amount:Math.max(1,draft.attack||1),target:'enemy'}]}]}}>행동 추가</button><button class="primary-btn" type="submit">{busy?'저장 중…':'몬스터 저장'}</button></div></fieldset>
  </form><section class="admin-card"><h2>등록된 몬스터 ({monsters.length})</h2><label class="monster-search"><span>몬스터 검색</span><span class="monster-search-control"><b aria-hidden="true">⌕</b><input type="search" bind:value={search} placeholder="이름, 설명 검색" /></span></label><button type="button" class="subtle-btn" disabled={loading||busy} on:click={load}>목록 새로고침</button>
    {#if loading}<p>불러오는 중…</p>{:else}{#each visible as monster}<article class="monster-entry"><h3>{monster.name}</h3><p>HP {monster.hp} · 공격 {monster.attack} · 방어 {monster.guard}</p><p>{monster.description}</p>{#each monster.powers as effect}<small>{effectText(effect)}</small>{/each}<p>행동: {monster.actions.length?monster.actions.map(a=>a.name).join(' → '):'공격 → 방어 → 강타'}</p><button class="subtle-btn" type="button" disabled={busy} on:click={()=>{draft=structuredClone(monster);error='';notice='';}}>수정</button><button class="danger-btn" type="button" disabled={busy} on:click={()=>remove(monster)}>삭제</button></article>{:else}<p>등록된 몬스터가 없습니다.</p>{/each}{/if}
  </section></div>{/if}
</section>
<style>.monster-layout{display:grid;grid-template-columns:minmax(0,1.4fr) minmax(0,1fr);gap:20px}.monster-layout>*{min-width:0}.monster-page fieldset{border:0;padding:0;min-width:0}.help-row{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:18px}.monster-action,.monster-entry{padding:16px 0;border-bottom:1px solid #46526a}.monster-entry p{margin:8px 0;overflow-wrap:anywhere}.monster-entry small{display:block}.monster-entry button{margin:8px 8px 0 0}.error{color:#ffb7a7}.monster-page input,.monster-page textarea{width:100%;min-width:0;box-sizing:border-box}.monster-page h3{overflow-wrap:anywhere}.monster-search{display:grid;gap:7px;margin:14px 0;color:#aab4c1;font-size:12px}.monster-search-control{display:flex;align-items:center;gap:9px;padding:0 12px;border:1px solid #47536a;border-radius:9px;background:#0e1724}.monster-search-control:focus-within{border-color:#d8bd75;box-shadow:0 0 0 3px rgba(216,189,117,.1)}.monster-search-control b{color:#d8bd75;font-size:19px}.monster-search-control input{height:44px;border:0!important;outline:0;background:transparent;color:#f3f4f7}.monster-search-control input::placeholder{color:#718094}@media(max-width:850px){.monster-layout{grid-template-columns:1fr}}</style>
