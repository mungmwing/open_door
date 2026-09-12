<script>
  import { tick } from 'svelte';
  import CardEffectEditor from '../components/CardEffectEditor.svelte';
  import EffectHelp from '../components/EffectHelp.svelte';
  import { KEYWORD_HELP } from '../lib/cardHelp';
  import { representativeCardTarget } from '../lib/combat';
  import PersonalEnergyEditor from '../components/PersonalEnergyEditor.svelte';

  export let authReady = false;
  export let profileLoading = false;
  export let adminDetailLoading = false;
  export let isAdmin = false;
  export let adminSelectedCharacter = null;
  export let adminCharacterForm = {};
  export let adminCharacterSaving = false;
  export let extraRecords = [];
  export let extraRecordForm = {};
  export let extraRecordSaving = false;
  export let adminInventory = [];
  export let equippedItems = [];
  export let equipmentSaving = false;
  export let adminCards = [];
  export let filteredInventoryCatalogItems = [];
  export let inventorySearchTerm = '';
  export let cardGrades = [];
  export let catalogItems = [];
  export let saveAdminCharacter = () => {};
  export let deleteAdminCharacter = () => {};
  export let saveExtraRecord = () => {};
  export let deleteExtraRecord = () => {};
  export let addCatalogItemToInventory = () => {};
  export let removeAdminInventory = () => {};
  export let isEquippableItem = () => false;
  export let toggleInventoryEquipment = () => {};
  export let newAdminCard = () => {};
  export let removeAdminCard = () => {};
  export let getInventoryIcon = () => '◆';
  export let isImageIcon = () => false;

  const cardTypes = ['공격', '스킬', '파워', '상태', '저주'];
  const itemTypes = ['전체', '유물', '장비', '소비', '상자', '기타'];
  const cardKeywordOptions = [
    { value: 'all', label: '전체' },
    { value: 'retain', label: '유지' },
    { value: 'innate', label: '선천' },
    { value: 'ethereal', label: '에테리얼' },
    { value: 'exhaust', label: '소멸' },
    { value: 'drop', label: '추가 드로우' }
  ];

  let activeSection = 'summary';
  let ownedItemSearch = '';
  let itemTypeFilter = '전체';
  let selectedInventoryIndex = -1;
  let cardSearch = '';
  let cardTypeFilter = '전체';
  let cardKeywordFilter = 'all';
  let selectedCardIndex = -1;

  $: inventoryEntries = adminInventory.map((item, index) => ({ item, index }));
  $: filteredInventoryEntries = inventoryEntries.filter(({ item }) => {
    const keyword = ownedItemSearch.toLowerCase().trim();
    const matchesSearch = !keyword || `${item.item_name} ${item.item_effect} ${item.item_description} ${item.grade}`.toLowerCase().includes(keyword);
    const matchesType = itemTypeFilter === '전체' || item.item_type === itemTypeFilter;
    return matchesSearch && matchesType;
  });
  $: selectedInventoryItem = selectedInventoryIndex >= 0 ? adminInventory[selectedInventoryIndex] : null;

  $: cardEntries = adminCards.map((card, index) => ({ card, index }));
  $: filteredCardEntries = cardEntries.filter(({ card }) => {
    const keyword = cardSearch.toLowerCase().trim();
    const matchesSearch = !keyword || `${card.card_name} ${card.card_effect} ${card.card_exhaust_effect} ${card.card_drop_effect} ${card.grade}`.toLowerCase().includes(keyword);
    const matchesType = cardTypeFilter === '전체' || (card.card_type || '스킬') === cardTypeFilter;
    const matchesKeyword = cardKeywordFilter === 'all'
      || (cardKeywordFilter === 'retain' && card.card_retain)
      || (cardKeywordFilter === 'innate' && card.card_innate)
      || (cardKeywordFilter === 'ethereal' && card.card_ethereal)
      || (cardKeywordFilter === 'exhaust' && card.combat_rule?.exhaust)
      || (cardKeywordFilter === 'drop' && Number(card.card_drop_count) > 0);
    return matchesSearch && matchesType && matchesKeyword;
  });
  $: selectedCard = selectedCardIndex >= 0 ? adminCards[selectedCardIndex] : null;

  function openSection(section) {
    activeSection = section;
    if (section === 'inventory' && selectedInventoryIndex < 0 && adminInventory.length) selectedInventoryIndex = 0;
    if (section === 'cards' && selectedCardIndex < 0 && adminCards.length) selectedCardIndex = 0;
  }

  function setCardCombatRule(rule) {
    selectedCard.combat_rule = rule;
    selectedCard.card_target = representativeCardTarget(rule) || selectedCard.card_target || '자신';
    adminCards = adminCards;
  }

  function setCardField(key, value) {
    selectedCard[key] = value;
    adminCards = adminCards;
  }

  async function addCardAndOpen() {
    newAdminCard();
    await tick();
    selectedCardIndex = Math.max(0, adminCards.length - 1);
  }

  function removeSelectedCard() {
    if (selectedCardIndex < 0) return;
    removeAdminCard(selectedCardIndex);
    selectedCardIndex = adminCards.length > 1 ? Math.min(selectedCardIndex, adminCards.length - 2) : -1;
  }

  function removeSelectedInventoryItem() {
    if (selectedInventoryIndex < 0) return;
    removeAdminInventory(selectedInventoryIndex);
    selectedInventoryIndex = adminInventory.length > 1 ? Math.min(selectedInventoryIndex, adminInventory.length - 2) : -1;
  }
</script>

{#if !authReady || profileLoading || adminDetailLoading}
  <section class="character-detail-page panel"><div class="empty-state"><span>◌</span><strong>캐릭터 상세 정보를 불러오는 중이에요</strong></div></section>
{:else if !isAdmin || !adminSelectedCharacter}
  <section class="about-page panel"><p class="eyebrow">ACCESS RESTRICTED</p><h1>관리자 권한이<br /><em>필요합니다</em></h1><p class="about-lead">이 페이지는 캠페인 관리자만 이용할 수 있습니다.</p><a class="primary-btn about-button" href="#admin">관리자 페이지로 돌아가기 <span>→</span></a></section>
{:else}
  <section class="admin-character-workspace panel">
    <a class="back-link" href="#admin">← 플레이어 목록으로 돌아가기</a>

    <header class="character-workspace-header">
      <div class="character-workspace-identity">
        {#if adminSelectedCharacter.avatar_url}<img decoding="async" src={adminSelectedCharacter.avatar_url} alt={`${adminSelectedCharacter.name} 프로필 사진`} />{:else}<span>{adminSelectedCharacter.name.slice(0, 1)}</span>{/if}
        <div><p class="eyebrow">PLAYER MANAGEMENT</p><h1>{adminSelectedCharacter.name}</h1><p>{adminSelectedCharacter.nickname || '모험가'} · {adminSelectedCharacter.role_name || '역할 미등록'}</p></div>
      </div>
      <div class="character-workspace-counts">
        <span><small>ITEMS</small><strong>{adminInventory.length}</strong></span>
        <span><small>CARDS</small><strong>{adminCards.reduce((sum, card) => sum + Math.max(1, Number(card.quantity) || 1), 0)}</strong></span>
        <span><small>EQUIPPED</small><strong>{equippedItems.length}</strong></span>
      </div>
      <button class="danger-btn" type="button" on:click={deleteAdminCharacter}>캐릭터 삭제</button>
    </header>

    <nav class="character-workspace-tabs" aria-label="캐릭터 관리 메뉴">
      <button class:active={activeSection === 'summary'} type="button" on:click={() => openSection('summary')}><span>01</span><strong>기본·전투 정보</strong></button>
      <button class:active={activeSection === 'inventory'} type="button" on:click={() => openSection('inventory')}><span>02</span><strong>아이템</strong><b>{adminInventory.length}</b></button>
      <button class:active={activeSection === 'cards'} type="button" on:click={() => openSection('cards')}><span>03</span><strong>카드</strong><b>{adminCards.length}</b></button>
      <button class:active={activeSection === 'records'} type="button" on:click={() => openSection('records')}><span>04</span><strong>추가 기록</strong><b>{extraRecords.length}</b></button>
    </nav>

    <form class="character-workspace-form" on:submit|preventDefault={saveAdminCharacter}>
      {#if activeSection === 'summary'}
        <div class="workspace-section-grid">
          <section class="workspace-surface">
            <div class="workspace-surface-head"><div><p class="eyebrow">CHARACTER SHEET</p><h2>기본 정보</h2></div></div>
            <div class="field-grid"><label>캐릭터 이름<input bind:value={adminCharacterForm.name} /></label><label>역할명<input bind:value={adminCharacterForm.roleName} /></label><label>나이<input bind:value={adminCharacterForm.age} type="number" min="0" /></label><label>키 (cm)<input bind:value={adminCharacterForm.height} type="number" min="0" step="0.1" /></label><label>몸무게 (kg)<input bind:value={adminCharacterForm.weight} type="number" min="0" step="0.1" /></label><label class="field-wide">역할 특징<textarea bind:value={adminCharacterForm.roleTraits} rows="5"></textarea></label></div>
          </section>
          <section class="workspace-surface">
            <div class="workspace-surface-head"><div><p class="eyebrow">COMBAT STATUS</p><h2>전투 정보</h2></div></div>
            <div class="combat-grid">
              <label>레벨<input bind:value={adminCharacterForm.level} type="number" min="1" /></label>
              <label>돈<input bind:value={adminCharacterForm.money} type="number" min="0" /></label>
              <label>현재 HP<input bind:value={adminCharacterForm.hp} type="number" min="0" /></label>
              <label>최대 HP<input bind:value={adminCharacterForm.maxHp} type="number" min="0" /></label>
              <label class="field-wide admin-combat-notes-field">
                <span class="combat-notes-label">전투 메모</span>
                <small>플레이어의 전투 상태, 임시 효과, 다음 전투에 참고할 내용을 기록합니다.</small>
                <textarea bind:value={adminCharacterForm.combatNotes} rows="5" placeholder="예: 중독 2중첩 · 다음 턴 방어도 감소 · 보스 패턴 확인 필요"></textarea>
              </label>
            </div>
            <PersonalEnergyEditor value={adminCharacterForm.personalEnergy} disabled={adminCharacterSaving} onChange={value=>adminCharacterForm.personalEnergy=value} />
          </section>
          <section class="workspace-surface equipped-workspace-surface">
            <div class="workspace-surface-head"><div><p class="eyebrow">EQUIPPED LOADOUT</p><h2>장착 효과</h2></div><span>{equippedItems.length}개 적용 중</span></div>
            {#if equippedItems.length}<div class="workspace-equipped-grid">{#each equippedItems as item}<article><strong>{item.item_name}</strong><span>{item.item_type}</span><p>{item.item_effect || '등록된 효과가 없습니다.'}</p></article>{/each}</div>{:else}<div class="workspace-empty">장착된 장비 또는 유물이 없습니다.</div>{/if}
          </section>
        </div>
      {:else if activeSection === 'inventory'}
        <div class="admin-library-layout">
          <aside class="admin-library-sidebar">
            <div class="workspace-surface-head"><div><p class="eyebrow">OWNED ITEMS</p><h2>보유 아이템</h2></div><span>{filteredInventoryEntries.length} / {adminInventory.length}</span></div>
            <label class="workspace-search"><span>⌕</span><input bind:value={ownedItemSearch} type="search" placeholder="이름·효과 검색" /></label>
            <div class="workspace-filter-row">{#each itemTypes as type}<button class:active={itemTypeFilter === type} type="button" on:click={() => (itemTypeFilter = type)}>{type}</button>{/each}</div>
            {#if filteredInventoryEntries.length}
              <div class="admin-inventory-slot-grid">{#each filteredInventoryEntries as entry}<button class:selected={selectedInventoryIndex === entry.index} class:equipped={isEquippableItem(entry.item) && entry.item.is_equipped} type="button" title={entry.item.item_name} on:click={() => (selectedInventoryIndex = entry.index)}><span class="admin-slot-icon">{#if isImageIcon(getInventoryIcon(entry.item))}<img loading="lazy" decoding="async" src={getInventoryIcon(entry.item)} alt="" />{:else}{getInventoryIcon(entry.item)}{/if}</span><strong>{entry.item.item_name}</strong><small>× {entry.item.quantity}</small>{#if entry.item.is_equipped}<b>장착</b>{/if}</button>{/each}</div>
            {:else}<div class="workspace-empty">조건에 맞는 아이템이 없습니다.</div>{/if}
          </aside>

          <section class="admin-library-detail">
            {#if selectedInventoryItem}
              <div class="library-detail-heading"><div class="library-detail-icon">{#if isImageIcon(getInventoryIcon(selectedInventoryItem))}<img decoding="async" src={getInventoryIcon(selectedInventoryItem)} alt="" />{:else}{getInventoryIcon(selectedInventoryItem)}{/if}</div><div><p class="eyebrow">ITEM DETAIL</p><h2>{selectedInventoryItem.item_name}</h2><div><span class="tag">{selectedInventoryItem.grade}</span><span class="tag">{selectedInventoryItem.item_type}</span>{#if selectedInventoryItem.is_equipped}<span class="tag equipped">장착 중</span>{/if}</div></div></div>
              <div class="library-copy-block"><strong>효과</strong><p>{selectedInventoryItem.item_effect || '등록된 효과가 없습니다.'}</p></div>
              <div class="library-copy-block"><strong>설명</strong><p>{selectedInventoryItem.item_description || '등록된 설명이 없습니다.'}</p></div>
              <div class="library-control-row"><label>수량<input bind:value={selectedInventoryItem.quantity} type="number" min="1" /></label>{#if isEquippableItem(selectedInventoryItem)}<button class="equipment-toggle-btn" type="button" on:click={() => toggleInventoryEquipment(selectedInventoryItem, adminSelectedCharacter.id)} disabled={equipmentSaving}>{selectedInventoryItem.is_equipped ? '장착 해제' : '장착하기'}</button>{/if}<button class="danger-btn" type="button" on:click={removeSelectedInventoryItem}>인벤토리에서 제거</button></div>
            {:else}<div class="library-detail-empty"><span>◇</span><strong>아이템을 선택하세요</strong><p>왼쪽 슬롯에서 아이템을 선택하면 효과와 수량을 관리할 수 있습니다.</p></div>{/if}
          </section>

          <section class="catalog-add-panel">
            <div class="workspace-surface-head"><div><p class="eyebrow">ADD ITEM</p><h2>아이템 지급</h2></div></div>
            <label class="workspace-search"><span>⌕</span><input bind:value={inventorySearchTerm} type="search" placeholder="카탈로그에서 검색" /></label>
            {#if inventorySearchTerm.trim()}
              <div class="catalog-quick-list">{#each filteredInventoryCatalogItems as item}<button type="button" on:click={() => addCatalogItemToInventory(item)}><span class="admin-slot-icon small">{#if isImageIcon(getInventoryIcon(item))}<img loading="lazy" decoding="async" src={getInventoryIcon(item)} alt="" />{:else}{getInventoryIcon(item)}{/if}</span><span><strong>{item.name}</strong><small>{item.grade} · {item.item_type}</small></span><b>＋</b></button>{/each}</div>
            {:else}<p class="catalog-add-help">지급할 아이템 이름이나 효과를 검색하세요.</p>{/if}
          </section>
        </div>
      {:else if activeSection === 'cards'}
        <div class="admin-library-layout card-library-layout">
          <aside class="admin-library-sidebar">
            <div class="workspace-surface-head"><div><p class="eyebrow">CARD LIBRARY</p><h2>보유 카드</h2></div><button class="subtle-btn" type="button" on:click={addCardAndOpen}>+ 카드 추가</button></div>
            <label class="workspace-search"><span>⌕</span><input bind:value={cardSearch} type="search" placeholder="카드명·효과 검색" /></label>
            <div class="workspace-select-row"><label>타입<select bind:value={cardTypeFilter}><option>전체</option>{#each cardTypes as type}<option>{type}</option>{/each}</select></label><label>키워드<select bind:value={cardKeywordFilter}>{#each cardKeywordOptions as option}<option value={option.value}>{option.label}</option>{/each}</select></label></div>
            {#if filteredCardEntries.length}
              <div class="admin-card-compact-list">{#each filteredCardEntries as entry}<button class:selected={selectedCardIndex === entry.index} type="button" on:click={() => (selectedCardIndex = entry.index)}><span class="card-compact-energy">{entry.card.energy || 0}</span><span><strong>{entry.card.card_name || '이름 없는 카드'}</strong><small>{entry.card.card_type || '스킬'} · {entry.card.grade || '기본'} · ×{entry.card.quantity || 1}</small><em>{entry.card.card_target || '자신'}</em></span><span class="card-compact-keywords">{#if entry.card.card_retain}<i>유지</i>{/if}{#if entry.card.card_innate}<i>선천</i>{/if}{#if entry.card.card_ethereal}<i>에테리얼</i>{/if}{#if entry.card.combat_rule?.exhaust}<i>소멸</i>{/if}{#if entry.card.card_drop_count > 0}<i>+{entry.card.card_drop_count}</i>{/if}</span></button>{/each}</div>
            {:else}<div class="workspace-empty">조건에 맞는 카드가 없습니다.</div>{/if}
          </aside>

          <section class="admin-library-detail card-editor-detail">
            {#if selectedCard}
              <div class="workspace-surface-head"><div><p class="eyebrow">CARD EDITOR</p><h2>{selectedCard.card_name || '새 카드'}</h2></div><button class="danger-btn" type="button" on:click={removeSelectedCard}>카드 제거</button></div>
              <div class="card-editor-core"><label>카드명<input bind:value={selectedCard.card_name} placeholder="카드명" /></label><label>에너지<input bind:value={selectedCard.energy} type="number" min="0" /></label><label>수량<input bind:value={selectedCard.quantity} type="number" min="1" /></label><label>등급<select bind:value={selectedCard.grade}>{#each cardGrades as grade}<option>{grade}</option>{/each}</select></label><label>카드 타입<select bind:value={selectedCard.card_type}>{#each cardTypes as type}<option>{type}</option>{/each}</select></label><label>대표 대상 (효과에서 자동 반영)<input readonly value={representativeCardTarget(selectedCard.combat_rule) || selectedCard.card_target || '자신'} /></label></div>
              <div class="card-core-help"><span>카드 타입</span><EffectHelp label="카드 타입" text={KEYWORD_HELP.type} /><span>대표 대상</span><EffectHelp label="대표 대상" text={KEYWORD_HELP.target} /></div>
              {#key selectedCardIndex}
                <CardEffectEditor value={selectedCard.combat_rule} card={selectedCard} {catalogItems} personalEnergyName={adminCharacterForm.personalEnergy?.name} editCard optional disabled={adminCharacterSaving} onChange={setCardCombatRule} onCardChange={setCardField} />
              {/key}
            {:else}<div class="library-detail-empty"><span>▱</span><strong>카드를 선택하세요</strong><p>왼쪽 목록에서 카드를 선택하거나 새 카드를 추가하세요.</p></div>{/if}
          </section>
        </div>
      {:else}
        <section class="workspace-surface records-workspace">
          <div class="workspace-surface-head"><div><p class="eyebrow">PERSONAL NOTES</p><h2>추가 기록</h2></div><span>{extraRecords.length}개</span></div>
          <div class="record-compose workspace-record-compose"><input bind:value={extraRecordForm.title} placeholder="기록 제목" /><textarea bind:value={extraRecordForm.content} rows="4" placeholder="추가 기록을 작성해 주세요."></textarea><button class="primary-btn" type="button" on:click={saveExtraRecord} disabled={extraRecordSaving}>{extraRecordSaving ? '등록 중…' : '기록 등록'} <span>↗</span></button></div>
          {#if extraRecords.length}<div class="workspace-record-list">{#each extraRecords as record}<article><div><strong>{record.title}</strong><span>{record.authorName} · {new Date(record.created_at).toLocaleDateString('ko-KR')}</span></div><p>{record.content}</p><button class="record-delete" type="button" on:click={() => deleteExtraRecord(record)}>기록 삭제</button></article>{/each}</div>{:else}<div class="workspace-empty">등록된 추가 기록이 없습니다.</div>{/if}
        </section>
      {/if}

      <div class="character-workspace-savebar"><span>현재 탭의 변경사항을 포함해 캐릭터 정보를 저장합니다.</span><button class="primary-btn" type="submit" disabled={adminCharacterSaving}>{adminCharacterSaving ? '저장 중…' : '전체 변경사항 저장'} <b>↗</b></button></div>
    </form>
  </section>
{/if}

<style>
  .card-core-help { display:flex; flex-wrap:wrap; align-items:center; gap:8px; margin:12px 0; color:#b8c5d7; font-size:13px; }
</style>
