<script>
  import RelicEffectEditor from '../components/RelicEffectEditor.svelte';
  import CardEffectEditor from '../components/CardEffectEditor.svelte';
  export let authReady = false;
  export let profileLoading = false;
  export let isAdmin = false;
  export let currentRoute = 'admin/items';
  export let itemForm = { id: '', name: '', item_effect: '', item_description: '', grade: '일반', item_type: '기타', equipment_slot: '', chest_reward_item_ids: [], chest_reward_count: 1 };
  export let itemFormImagePreview = '';
  export let itemSaving = false;
  export let catalogItems = [];
  export let filteredCatalogItems = [];
  export let catalogLoading = false;
  export let catalogSearchTerm = '';
  export let resetItemForm = () => {};
  export let saveCatalogItem = () => {};
  export let editCatalogItem = () => {};
  export let deleteCatalogItem = () => {};
  export let handleItemFormImageChange = () => {};
  export let getInventoryIcon = () => '◆';
  export let isImageIcon = () => false;

  let selectedCatalogItem = null;

  function openCatalogItem(item) {
    selectedCatalogItem = item;
  }

  function closeCatalogItem() {
    selectedCatalogItem = null;
  }
</script>

{#if !authReady || profileLoading}
  <section class="admin-page panel"><div class="empty-state"><span>◌</span><strong>관리자 권한을 확인하는 중이에요</strong><p>잠시만 기다려 주세요.</p></div></section>
{:else if !isAdmin}
  <section class="about-page panel"><p class="eyebrow">ACCESS RESTRICTED</p><h1>관리자 권한이<br /><em>필요합니다</em></h1><p class="about-lead">이 페이지는 관리자 계정만 이용할 수 있습니다.</p><a class="primary-btn about-button" href="#home">홈으로 돌아가기 <span>→</span></a></section>
{:else}
  <section class="admin-page panel">
    <div class="admin-shell">
      <nav class="admin-sidebar" aria-label="관리자 메뉴"><div class="admin-sidebar-brand"><span class="eyebrow">CONTROL ROOM</span><strong>관리자 메뉴</strong></div><a class:active={currentRoute === 'admin'} href="#admin"><span>◌</span><span><strong>플레이어 계정 생성</strong><small>ACCOUNTS &amp; CHARACTERS</small></span></a><a href="#admin/monsters"><span>♟</span><span><strong>몬스터 관리</strong><small>MONSTER CATALOG</small></span></a><a class:active={currentRoute === 'admin/items'} href="#admin/items"><span>◇</span><span><strong>아이템 관리</strong><small>ITEM CATALOG</small></span></a><a class:active={currentRoute === 'admin/shop'} href="#admin/shop"><span>G</span><span><strong>상점 상품 관리</strong><small>SHOP INVENTORY</small></span></a><a class:active={currentRoute === 'admin/combat-test'} href="#admin/combat-test"><span>⚔</span><span><strong>전투 테스트</strong><small>CARD DRAW LAB</small></span></a><a href="#combat"><span>⚔</span><span><strong>실시간 전투방</strong><small>CO-OP CARD BATTLE</small></span></a><div class="admin-sidebar-foot">운영 도구<br /><span>CAMPAIGN ADMIN</span></div></nav>
      <div class="admin-shell-main">
        <div class="page-heading"><div><p class="eyebrow">ITEM CATALOG</p><h1>아이템 관리</h1><p>TRPG에서 사용할 아이템을 등록하고 관리합니다. 등록된 아이템은 플레이어 인벤토리에서 사용할 수 있습니다.</p></div><a class="subtle-btn" href="#admin">← 관리자 페이지</a></div>
        <div class="admin-items-layout">
          <section class="admin-card admin-item-editor">
            <div class="form-section-head"><div><p class="eyebrow">{itemForm.id ? 'EDIT ITEM' : 'NEW ITEM'}</p><h2>{itemForm.id ? '아이템 수정' : '새 아이템 등록'}</h2></div>{#if itemForm.id}<button class="subtle-btn" type="button" on:click={resetItemForm}>새 아이템</button>{/if}</div>
            <form class="editor-form" on:submit|preventDefault={saveCatalogItem}>
              <div class="item-image-editor"><label class="item-image-upload"><span class="field-label">아이템 아이콘</span><span class="item-image-preview">{#if itemFormImagePreview}<img decoding="async" src={itemFormImagePreview} alt="아이템 아이콘 미리보기" />{:else}<span class="item-image-placeholder">◆</span>{/if}</span><span class="item-image-button">이미지 선택</span><input type="file" accept="image/png,image/jpeg,image/webp" on:change={handleItemFormImageChange} /></label><div class="item-image-help"><strong>아이콘 이미지</strong><p>PNG, JPG, WEBP<br />최대 5MB</p></div></div>
              <div class="field-grid"><label class="field-wide">아이템 이름<input bind:value={itemForm.name} maxlength="100" placeholder="예: 낡은 철검" required /></label><label>등급<select bind:value={itemForm.grade}><option>일반</option><option>고급</option><option>희귀</option><option>영웅</option><option>전설</option><option>신화</option></select></label><label>아이템 타입<select bind:value={itemForm.item_type}><option>장비</option><option>소비</option><option>유물</option><option>상자</option><option>기타</option></select></label>
                {#if itemForm.item_type === '장비'}<label>장비 부위<select bind:value={itemForm.equipment_slot} required><option value="">부위 선택</option><option>모자</option><option>상의</option><option>하의</option><option>무기</option></select></label>{/if}
                {#if itemForm.item_type === '상자'}<div class="chest-config field-wide"><div class="chest-config-head"><strong>상자 보상 설정</strong><span>선택한 목록에서 무작위로 지급합니다</span></div><label>한 번 열 때 지급할 개수<input bind:value={itemForm.chest_reward_count} type="number" min="1" max="50" /></label><label>보상 아이템 목록<select bind:value={itemForm.chest_reward_item_ids} multiple size="5" aria-label="상자 보상 아이템 목록">{#each catalogItems.filter((catalogItem) => catalogItem.id !== itemForm.id) as catalogItem}<option value={catalogItem.id}>{catalogItem.name} · {catalogItem.grade}</option>{/each}</select></label><p>Ctrl 또는 Shift를 누르면 여러 아이템을 선택할 수 있습니다.</p></div>{/if}
                <label class="field-wide">[효과]<textarea bind:value={itemForm.item_effect} rows="4" maxlength="1000" placeholder="게임에서 적용되는 효과를 작성해 주세요."></textarea></label><label class="field-wide">[설명]<textarea bind:value={itemForm.item_description} rows="5" maxlength="2000" placeholder="아이템의 일반 설명이나 설정을 작성해 주세요."></textarea></label>
              </div>
              {#if itemForm.item_type === '소비'}<h3>전투에서 사용할 때</h3><CardEffectEditor itemMode optional disabled={itemSaving} value={itemForm.combat_effects == null ? null : {playable:true,exhaust:false,effects:itemForm.combat_effects,on_exhaust:[]}} onChange={rule=>itemForm.combat_effects=rule?.effects ?? null} />{/if}
              {#if itemForm.item_type === '유물'}<RelicEffectEditor disabled={itemSaving} value={itemForm.relic_effects} onChange={effects=>itemForm.relic_effects=effects} />{/if}
              <div class="form-actions">{#if itemForm.id}<button class="subtle-btn" type="button" on:click={resetItemForm}>취소</button>{/if}<button class="primary-btn" type="submit" disabled={itemSaving}>{itemSaving ? '저장 중…' : itemForm.id ? '아이템 수정' : '아이템 등록'} <span>↗</span></button></div>
            </form>
          </section>
          <section class="admin-card admin-item-list"><div class="form-section-head"><div><p class="eyebrow">ITEM CATALOG</p><h2>등록된 아이템 <span class="item-count">{catalogItems.length}</span></h2></div></div><div class="admin-item-toolbar"><label class="inventory-search"><span aria-hidden="true">⌕</span><input bind:value={catalogSearchTerm} type="search" placeholder="아이템 이름, 효과, 등급, 타입 검색" aria-label="아이템 검색" /></label>{#if catalogSearchTerm}<button class="subtle-btn" type="button" on:click={() => (catalogSearchTerm = '')}>검색 초기화</button>{/if}</div>
            {#if catalogLoading}<div class="empty-state admin-item-empty"><span>◌</span><strong>아이템을 불러오는 중이에요</strong></div>{:else if !filteredCatalogItems.length}<div class="empty-state admin-item-empty"><span>◇</span><strong>{catalogSearchTerm ? '검색 결과가 없습니다' : '등록된 아이템이 없습니다'}</strong></div>{:else}<div class="admin-items-grid">{#each filteredCatalogItems as item}<article class="admin-item-card"><button class="admin-item-card-open" type="button" aria-label={`${item.name} 상세 보기`} on:click={() => openCatalogItem(item)}><div class="admin-item-icon">{#if isImageIcon(getInventoryIcon(item))}<img loading="lazy" decoding="async" src={getInventoryIcon(item)} alt="" />{:else}{getInventoryIcon(item)}{/if}</div><div class="admin-item-info"><div class="admin-item-title-row"><strong>{item.name}</strong>{#if item.id === itemForm.id}<span class="tag">편집 중</span>{/if}</div><small class="admin-item-detail-hint">아이템을 눌러 효과·설명 확인</small></div></button><div class="admin-item-actions"><button class="subtle-btn" type="button" on:click={() => editCatalogItem(item)}>수정</button><button class="danger-btn" type="button" on:click={() => deleteCatalogItem(item)}>삭제</button></div></article>{/each}</div>{/if}
          </section>
        </div>
      </div>
    </div>
  </section>
{/if}

{#if selectedCatalogItem}
  <div class="item-detail-overlay">
    <div class="item-detail-modal" role="dialog" aria-modal="true" aria-labelledby="catalog-item-detail-title">
      <button class="item-detail-close" type="button" aria-label="아이템 상세 닫기" on:click={closeCatalogItem}>×</button>
      <div class="item-detail-icon">{#if isImageIcon(getInventoryIcon(selectedCatalogItem))}<img decoding="async" src={getInventoryIcon(selectedCatalogItem)} alt="" />{:else}<span>{getInventoryIcon(selectedCatalogItem)}</span>{/if}</div>
      <div class="item-detail-copy"><p class="eyebrow">ITEM DETAIL</p><h2 id="catalog-item-detail-title">{selectedCatalogItem.name}</h2><div><span class="tag">{selectedCatalogItem.grade}</span><span class="tag">{selectedCatalogItem.item_type}</span>{#if selectedCatalogItem.item_type === '장비'}<span class="tag">{selectedCatalogItem.equipment_slot || '부위 미지정'}</span>{/if}</div><div class="item-copy-block"><strong>[효과]</strong><p>{selectedCatalogItem.item_effect || '등록된 효과가 없습니다.'}</p></div><div class="item-copy-block"><strong>[설명]</strong><p>{selectedCatalogItem.item_description || '등록된 설명이 없습니다.'}</p></div></div>
    </div>
  </div>
{/if}
