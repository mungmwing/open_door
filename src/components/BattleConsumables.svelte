<script>
  import { effectText, targetSide } from '../lib/combat';
  export let player;
  export let players = [];
  export let enemies = [];
  export let waiting = false;
  export let busy = false;
  export let canAct = false;
  export let available = [];
  export let error = '';
  export let onAct = async () => false;
  export let onRefresh = () => {};
  let draft = ['', '', ''];
  let selectedTargets = ['', '', ''];
  let seeded = '';
  $: slots = player?.consumables || [null,null,null];
  $: savedKey = `${player?.id}:${JSON.stringify(slots.map(item=>item?.inventory_id || ''))}`;
  $: if(savedKey !== seeded) {seeded=savedKey;draft=slots.map(item=>item?.inventory_id || '');}
  function targets(item) {
    const side = targetSide({effects:item.effects});
    return side ? (side === 'enemies' ? enemies : players).filter(unit=>unit.hp>0) : [];
  }
  function targetValid(item,index) {return !targetSide({effects:item.effects}) || targets(item).some(unit=>unit.id===selectedTargets[index]);}
</script>
<section class="consumable-panel" aria-label="전투 소비 아이템">
  <div class="consumable-heading"><h2>전투 소비 아이템 <small>{slots.filter(Boolean).length}/3</small></h2>{#if waiting}<button type="button" class="subtle-btn" disabled={busy} on:click={onRefresh}>보유 아이템 새로고침</button>{/if}</div>
  {#if error}<p class="consumable-error" role="alert">{error}</p>{/if}
  <div class="consumable-slots">
    {#each [0,1,2] as index}
      {@const item=slots[index]}
      <article class:empty={!item}>
        <span class="slot-number">SLOT {index+1}</span>
        {#if waiting}
          <label>장착할 소비 아이템<select aria-label={`소비 아이템 ${index+1} 장착`} bind:value={draft[index]} disabled={busy || !!error}>
            <option value="">빈 슬롯</option>
            {#each available as own}<option value={own.inventory_id} disabled={own.effects == null || own.quantity <= draft.filter((id,i)=>i!==index && id===own.inventory_id).length}>{own.name} · 보유 {own.quantity}개{own.effects == null ? ' · 효과 미설정' : ''}</option>{/each}
            {#if draft[index] && !available.some(own=>own.inventory_id===draft[index])}<option value={draft[index]}>현재 장착품 · 보유 목록 확인 필요</option>{/if}
          </select></label>
          {@const preview=available.find(own=>own.inventory_id===draft[index])}
          {#each preview?.effects || [] as effect}<p>{effectText(effect)}</p>{/each}
        {:else if item}
          <div class="consumable-title">{#if item.icon_url}<img src={item.icon_url} alt="" />{:else}<span>⚗</span>{/if}<strong>{item.name}</strong></div>
          <small class="source">{item.source === 'real' ? '원본 보유 아이템 · 사용 시 1개 소모' : '전투 전용 · 원본 인벤토리와 별도'}</small>
          {#each item.effects as effect}<p>{effectText(effect)}</p>{/each}
          {#if targetSide({effects:item.effects})}<label>사용 대상<select aria-label={`소비 아이템 ${index+1} 대상`} bind:value={selectedTargets[index]} disabled={busy || !canAct}><option value="">대상 선택</option>{#each targets(item) as target}<option value={target.id}>{target.name} · HP {target.hp}</option>{/each}</select></label>{/if}
          <div class="item-actions"><button type="button" class="primary-btn" disabled={busy || !canAct || !targetValid(item,index)} on:click={()=>onAct('use_item',{slot:index,instance_id:item.instance_id,target_id:selectedTargets[index] || null})}>{item.name} 사용</button>{#if item.source === 'generated'}<button type="button" class="subtle-btn" disabled={busy || !canAct} on:click={()=>onAct('discard_item',{slot:index,instance_id:item.instance_id})}>버리기</button>{/if}</div>
        {:else}<p class="empty-copy">빈 슬롯<br />카드로 생성한 소비 아이템이 들어옵니다.</p>{/if}
      </article>
    {/each}
  </div>
  {#if waiting}<div class="consumable-heading"><p>장착할 때는 소모하지 않습니다. 실제 사용에 성공하면 원본 수량이 1개 줄어듭니다.</p><button type="button" class="primary-btn" disabled={busy || !!error} on:click={()=>onAct('loadout',{inventory_ids:draft.map(id=>id || null)})}>소비 아이템 장착 저장</button></div>{:else}<p class="consumable-note">사용에는 기본 에너지가 들지 않습니다. 생성품은 빈 3칸만 채우며 전투가 끝나면 사라집니다.</p>{/if}
</section>
<style>
  .consumable-panel { padding:20px; margin:20px 0; border:1px solid #52635e; border-radius:12px; background:#14201f; }
  .consumable-heading { display:flex; flex-wrap:wrap; gap:12px; align-items:center; justify-content:space-between; }
  h2 { margin:0; font-size:18px; color:#e8e5db; } h2 small { color:#abc1ac; }
  .consumable-slots { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:12px; margin-top:16px; }
  article { min-width:0; padding:14px; border:1px solid #536059; border-radius:9px; background:#102022; }
  article.empty { border-style:dashed; }
  .slot-number { display:block; color:#94ada9; font-size:11px; letter-spacing:1px; margin-bottom:12px; }
  label { display:grid; gap:7px; font-size:13px; color:#bbcbd1; }
  select { box-sizing:border-box; width:100%; min-width:0; padding:10px; border:1px solid #506369; border-radius:7px; color:#edf0eb; background:#0c171d; }
  p { color:#c8d7d3; font-size:13px; line-height:1.7; }
  .consumable-title { display:flex; align-items:center; gap:10px; margin-bottom:10px; color:#f0e8cf; }
  .consumable-title img { width:36px; height:36px; object-fit:contain; }
  .source { color:#acbea8; font-size:12px; }
  .item-actions { display:flex; flex-wrap:wrap; gap:8px; margin-top:14px; }
  .empty-copy { color:#839ba5; }
  .consumable-error { color:#ffc4b2; }
  .consumable-note { margin-bottom:0; }
  @media(max-width:760px) {.consumable-slots {grid-template-columns:1fr;} .consumable-panel {padding:14px;} }
</style>
