<script>
  import { afterUpdate } from 'svelte';
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

  function syncCardDropCountControls() {
    document.querySelectorAll('.admin-card-editor').forEach((editor, index) => {
      const card = adminCards[index];
      if (!card) return;
      const existingInput = editor.querySelector('.card-drop-count-control input');
      if (existingInput) {
        existingInput.value = String(card.card_drop_count || 0);
        existingInput.cardRef = card;
        return;
      }
      const label = document.createElement('label');
      label.className = 'card-drop-count-control';
      label.textContent = '추가 드롭 개수';
      const input = document.createElement('input');
      input.type = 'number';
      input.min = '0';
      input.step = '1';
      input.value = String(card.card_drop_count || 0);
      input.cardRef = card;
      input.addEventListener('input', () => { input.cardRef.card_drop_count = Math.max(0, Number(input.value) || 0); });
      label.appendChild(input);
      editor.querySelector('.admin-item-meta')?.appendChild(label);
    });
  }

  function syncCardRuleControls() {
    const cardTypes = ['공격', '스킬', '파워', '상태', '저주'];
    const cardTargets = ['자신', '적 1명', '전체 적', '무작위 적', '아군 1명', '전체 아군'];
    document.querySelectorAll('.admin-card-editor').forEach((editor, index) => {
      const card = adminCards[index];
      if (!card) return;
      let panel = editor.querySelector('.card-rule-controls');
      if (!panel) {
        panel = document.createElement('div');
        panel.className = 'card-rule-controls';
        const keywordLabels = [['card_retain', '유지'], ['card_innate', '선천'], ['card_ethereal', '에테리얼']];
        keywordLabels.forEach(([key, labelText]) => {
          const label = document.createElement('label');
          const input = document.createElement('input');
          input.type = 'checkbox';
          input.cardKey = key;
          input.addEventListener('change', () => { input.cardRef[input.cardKey] = input.checked; });
          label.append(input, labelText);
          panel.appendChild(label);
        });
        const typeLabel = document.createElement('label');
        typeLabel.textContent = '카드 타입';
        const typeSelect = document.createElement('select');
        typeSelect.className = 'card-type-control';
        cardTypes.forEach((value) => { const option = document.createElement('option'); option.value = value; option.textContent = value; typeSelect.appendChild(option); });
        typeSelect.addEventListener('change', () => { typeSelect.cardRef.card_type = typeSelect.value; });
        typeLabel.appendChild(typeSelect);
        panel.appendChild(typeLabel);
        const targetLabel = document.createElement('label');
        targetLabel.textContent = '대상';
        const targetSelect = document.createElement('select');
        targetSelect.className = 'card-target-control';
        cardTargets.forEach((value) => { const option = document.createElement('option'); option.value = value; option.textContent = value; targetSelect.appendChild(option); });
        targetSelect.addEventListener('change', () => { targetSelect.cardRef.card_target = targetSelect.value; });
        targetLabel.appendChild(targetSelect);
        panel.appendChild(targetLabel);
        editor.querySelector('.card-effect-field')?.before(panel);
      }
      panel.querySelectorAll('input[type="checkbox"]').forEach((input) => { input.cardRef = card; input.checked = Boolean(card[input.cardKey]); });
      const typeSelect = panel.querySelector('.card-type-control');
      const targetSelect = panel.querySelector('.card-target-control');
      if (typeSelect) { typeSelect.cardRef = card; typeSelect.value = card.card_type || '스킬'; }
      if (targetSelect) { targetSelect.cardRef = card; targetSelect.value = card.card_target || '자신'; }
    });
  }

  afterUpdate(() => { syncCardDropCountControls(); syncCardRuleControls(); });
</script>

{#if !authReady || profileLoading || adminDetailLoading}<section class="character-detail-page panel"><div class="empty-state"><span>◌</span><strong>캐릭터 상세 정보를 불러오는 중이에요</strong></div></section>
{:else if !isAdmin || !adminSelectedCharacter}<section class="about-page panel"><p class="eyebrow">ACCESS RESTRICTED</p><h1>관리자 권한이<br /><em>필요합니다</em></h1><p class="about-lead">이 페이지는 캠페인 관리자만 이용할 수 있습니다.</p><a class="primary-btn about-button" href="#admin">관리자 페이지로 돌아가기 <span>→</span></a></section>
{:else}<section class="character-detail-page panel"><a class="back-link" href="#admin">← 관리자 관리 페이지로 돌아가기</a><div class="admin-detail-header">{#if adminSelectedCharacter.avatar_url}<img src={adminSelectedCharacter.avatar_url} alt={`${adminSelectedCharacter.name} 프로필 사진`} />{:else}<span class="admin-detail-avatar">{adminSelectedCharacter.name.slice(0, 1)}</span>{/if}<div><p class="eyebrow">CHARACTER PROFILE</p><h1>{adminSelectedCharacter.name}</h1><p>{adminSelectedCharacter.nickname || '모험가'} · {adminSelectedCharacter.role_name || '역할 미등록'}</p></div><button class="danger-btn" type="button" on:click={deleteAdminCharacter}>캐릭터 삭제</button></div><form class="character-form" on:submit|preventDefault={saveAdminCharacter}><div class="form-section admin-detail-section"><div class="form-section-head"><div><p class="eyebrow">CHARACTER SHEET</p><h2>기본 정보</h2></div></div><div class="field-grid"><label>캐릭터 이름<input bind:value={adminCharacterForm.name} /></label><label>역할명<input bind:value={adminCharacterForm.roleName} /></label><label>나이<input bind:value={adminCharacterForm.age} type="number" min="0" /></label><label>키 (cm)<input bind:value={adminCharacterForm.height} type="number" min="0" step="0.1" /></label><label>몸무게 (kg)<input bind:value={adminCharacterForm.weight} type="number" min="0" step="0.1" /></label><label class="field-wide">역할 특징<textarea bind:value={adminCharacterForm.roleTraits} rows="5"></textarea></label></div></div><div class="form-section admin-detail-section"><div class="form-section-head"><div><p class="eyebrow">COMBAT STATUS</p><h2>전투 정보</h2></div></div><div class="combat-grid"><label>레벨<input bind:value={adminCharacterForm.level} type="number" min="1" /></label><label>돈<input bind:value={adminCharacterForm.money} type="number" min="0" /></label><label>현재 HP<input bind:value={adminCharacterForm.hp} type="number" min="0" /></label><label>최대 HP<input bind:value={adminCharacterForm.maxHp} type="number" min="0" /></label><label class="field-wide">전투 메모<textarea bind:value={adminCharacterForm.combatNotes} rows="3"></textarea></label></div><div class="equipped-effects-panel"><div class="equipped-effects-head"><div><p class="eyebrow">EQUIPPED LOADOUT</p><h3>장착 효과</h3></div><span>{equippedItems.length}개</span></div>{#if equippedItems.length}<div class="equipped-effects-list">{#each equippedItems as item}<article class="equipped-effect-item"><div><strong>{item.item_name}</strong><span>{item.item_type}</span></div><p>{item.item_effect || '등록된 효과가 없습니다.'}</p></article>{/each}</div>{:else}<p class="equipped-effects-empty">장착된 장비 또는 유물이 없습니다.</p>{/if}</div></div><div class="form-section extra-record-section"><div class="form-section-head"><div><p class="eyebrow">PERSONAL NOTES</p><h2>추가 기록</h2></div><span class="form-hint">관리자는 모든 기록을 삭제할 수 있습니다.</span></div>{#if extraRecords.length}{#each extraRecords as record}<article class="record-board-item"><div class="record-board-meta"><strong>{record.title}</strong><span>{record.authorName} · {new Date(record.created_at).toLocaleDateString('ko-KR')}</span></div><p>{record.content}</p>{#if isAdmin}<button class="record-delete" type="button" on:click={() => deleteExtraRecord(record)}>기록 삭제</button>{/if}</article>{/each}{:else}<div class="repeat-empty">등록된 추가 기록이 없습니다.</div>{/if}<div class="record-compose"><input bind:value={extraRecordForm.title} placeholder="기록 제목" /><textarea bind:value={extraRecordForm.content} rows="4" placeholder="추가 기록을 작성해 주세요."></textarea><button class="primary-btn" type="button" on:click={saveExtraRecord} disabled={extraRecordSaving}>기록 등록 <span>↗</span></button></div></div><div class="form-section inventory-picker-section"><div class="form-section-head"><div><p class="eyebrow">INVENTORY</p><h2>인벤토리</h2></div></div><label class="inventory-search"><span aria-hidden="true">⌕</span><input bind:value={inventorySearchTerm} type="search" placeholder="아이템 이름 또는 효과 검색" /></label>{#if inventorySearchTerm.trim()}{#each filteredInventoryCatalogItems as catalogItem}<button class="inventory-search-item" type="button" on:click={() => addCatalogItemToInventory(catalogItem)}><strong>{catalogItem.name}</strong><small><span>[효과]</span> {catalogItem.item_effect || '등록된 효과가 없습니다.'}<br /><span>[설명]</span> {catalogItem.item_description || '등록된 설명이 없습니다.'}</small></button>{/each}{/if}{#if adminInventory.length}{#each adminInventory as item, index}<article class:equipped={isEquippableItem(item) && item.is_equipped} class="admin-inventory-card"><div class="admin-item-icon">{#if isImageIcon(getInventoryIcon(item))}<img src={getInventoryIcon(item)} alt="" />{:else}{getInventoryIcon(item)}{/if}</div><div class="admin-item-fields"><strong>{item.item_name}</strong>{#if isEquippableItem(item)}<div class="inventory-equipment-control"><span class="equipment-status">{item.is_equipped ? '장착 중' : '미장착'}</span><button class="equipment-toggle-btn" type="button" on:click={() => toggleInventoryEquipment(item, adminSelectedCharacter.id)} disabled={equipmentSaving}>{item.is_equipped ? '장착 해제' : '장착하기'}</button></div>{/if}<div class="item-copy-block"><strong>[효과]</strong><p>{item.item_effect || '등록된 효과가 없습니다.'}</p></div><div class="item-copy-block"><strong>[설명]</strong><p>{item.item_description || '등록된 설명이 없습니다.'}</p></div><label>수량<input bind:value={item.quantity} type="number" min="1" /></label></div><button class="icon-btn" type="button" on:click={() => removeAdminInventory(index)} aria-label="아이템 삭제">×</button></article>{/each}{:else}<div class="repeat-empty">등록된 아이템이 없습니다.</div>{/if}</div><div class="form-section admin-detail-section"><div class="form-section-head"><div><p class="eyebrow">CARDS</p><h2>보유 카드</h2></div><button class="subtle-btn" type="button" on:click={newAdminCard}>+ 카드 추가</button></div>{#each adminCards as card, index}<article class="admin-card-editor"><div class="owned-card-top"><input bind:value={card.card_name} placeholder="카드명" /><span>{card.energy || 0} energy</span></div><label class="card-effect-field">기본 효과<textarea bind:value={card.card_effect} rows="3" placeholder="카드를 사용했을 때의 기본 효과"></textarea></label><div class="card-effect-grid"><label>소멸 효과<textarea bind:value={card.card_exhaust_effect} rows="2" placeholder="소멸될 때 적용되는 효과"></textarea></label><label>드롭 효과<textarea bind:value={card.card_drop_effect} rows="2" placeholder="추가로 드롭할 카드나 처리"></textarea></label></div><div class="admin-item-meta"><input bind:value={card.quantity} type="number" min="1" aria-label="수량" /><input bind:value={card.energy} type="number" min="0" aria-label="에너지" /><select bind:value={card.grade} aria-label="등급">{#each cardGrades as grade}<option>{grade}</option>{/each}</select><button class="icon-btn" type="button" on:click={() => removeAdminCard(index)} aria-label="카드 삭제">×</button></div></article>{/each}</div><div class="form-actions"><button class="primary-btn" type="submit" disabled={adminCharacterSaving}>{adminCharacterSaving ? '저장 중…' : '변경사항 저장'} <span>↗</span></button></div></form></section>{/if}
