<script>
  import { afterUpdate } from 'svelte';
  export let profile = null;
  export let character = null;
  export let characterError = '';
  export let characterLoading = false;
  export let profileSection = 'basic';
  export let characterForm = {};
  export let profileImagePreview = '';
  export let characterSaving = false;
  export let extraRecords = [];
  export let extraRecordForm = {};
  export let extraRecordSaving = false;
  export let relationships = [];
  export let relationshipForm = {};
  export let relationshipSaving = false;
  export let npcOptions = [];
  export let inventory = [];
  export let cards = [];
  export let selectedInventoryItem = null;
  export let equippedItems = [];
  export let equipmentSaving = false;
  export let user = null;
  export let isAdmin = false;
  export let accountForm = { newPassword: '', confirmPassword: '' };
  export let accountSettingsSaving = false;
  export let handleProfileImageChange = () => {};
  export let saveCharacter = () => {};
  export let saveExtraRecord = () => {};
  export let deleteExtraRecord = () => {};
  export let saveRelationship = () => {};
  export let deleteRelationship = () => {};
  export let selectInventoryItem = () => {};
  export let isEquippableItem = () => false;
  export let toggleInventoryEquipment = () => {};
  export let getInventoryIcon = () => '◆';
  export let isImageIcon = () => false;
  export let saveAccountPassword = () => {};

  function syncCardRuleBadges() {
    document.querySelectorAll('.readonly-collection .owned-card').forEach((element, index) => {
      const card = cards[index];
      if (!card) return;
      let badges = element.querySelector('.card-rule-badges');
      if (!badges) {
        badges = document.createElement('div');
        badges.className = 'card-rule-badges';
        element.querySelector('.owned-card-top')?.insertAdjacentElement('afterend', badges);
      }
      badges.replaceChildren();
      [card.card_type || '스킬', `대상: ${card.card_target || '자신'}`].forEach((text) => {
        const badge = document.createElement('span');
        badge.textContent = text;
        badges.appendChild(badge);
      });
      [['card_retain', '유지'], ['card_innate', '선천'], ['card_ethereal', '에테리얼']].forEach(([key, text]) => {
        if (!card[key]) return;
        const badge = document.createElement('span');
        badge.textContent = text;
        badge.className = key.replace('card_', '');
        badges.appendChild(badge);
      });
    });
  }

  afterUpdate(syncCardRuleBadges);
</script>

<section class="mypage panel"><div class="page-heading"><p class="eyebrow">ADVENTURER PROFILE</p><h1>마이페이지</h1><p>{profile?.nickname || '모험가'}님의 캐릭터와 소지품을 관리하는 공간입니다.</p></div>
  {#if characterError}<div class="error-box">캐릭터 테이블을 확인해 주세요: {characterError}</div>{/if}
  {#if characterLoading}<div class="empty-state"><span>◌</span><strong>캐릭터 정보를 불러오는 중이에요</strong></div>
  {:else}<div class="profile-layout"><aside class="profile-sidebar">{#each [['account', '비밀번호 변경', 'PASSWORD'], ['basic', '기본 정보', 'CHARACTER'], ['combat', '전투 정보', 'COMBAT'], ['extra', '추가 기록', 'EXTRA NOTES'], ['relationships', '관계', 'RELATIONSHIPS'], ['inventory', '인벤토리', 'INVENTORY'], ['cards', '보유 카드', 'CARDS']] as item}<button class:active={profileSection === item[0]} type="button" on:click={() => (profileSection = item[0])}>{item[1]}<span>{item[2]}</span></button>{/each}</aside>
    <form class="character-form profile-content" on:submit|preventDefault={saveCharacter}>
      {#if profileSection === 'account'}<div class="form-section account-settings-section"><div class="form-section-head"><div><p class="eyebrow">PASSWORD SETTINGS</p><h2>비밀번호 변경</h2></div></div><div class="account-setting-block"><div class="account-setting-head"><div><strong>새 비밀번호 설정</strong><p>새 비밀번호는 8자 이상 입력해 주세요.</p></div></div><div class="field-grid"><label>새 비밀번호<input bind:value={accountForm.newPassword} type="password" minlength="8" autocomplete="new-password" placeholder="새 비밀번호" /></label><label>새 비밀번호 확인<input bind:value={accountForm.confirmPassword} type="password" minlength="8" autocomplete="new-password" placeholder="새 비밀번호 다시 입력" /></label></div><div class="form-actions"><button class="primary-btn" type="button" on:click={saveAccountPassword} disabled={accountSettingsSaving}>{accountSettingsSaving ? '저장 중…' : '비밀번호 변경'} <span>↗</span></button></div></div></div>
      {:else if profileSection === 'basic'}<div class="form-section"><div class="form-section-head"><div><p class="eyebrow">CHARACTER SHEET</p><h2>캐릭터 기본 정보</h2></div></div><div class="profile-photo-row"><label class="profile-photo-field"><span>프로필 이미지</span><span class="profile-photo-preview">{#if profileImagePreview}<img decoding="async" src={profileImagePreview} alt="프로필 미리보기" />{:else}<span>사진을 선택해 주세요</span>{/if}</span><input type="file" accept="image/png,image/jpeg,image/webp" on:change={handleProfileImageChange} /></label><div class="field-grid profile-fields"><label>이름<input bind:value={characterForm.name} placeholder="캐릭터 이름" /></label><label>역할명<input bind:value={characterForm.roleName} placeholder="역할명" /></label><label>나이<input bind:value={characterForm.age} type="number" min="0" placeholder="예: 27" /></label><label>키 (cm)<input bind:value={characterForm.height} type="number" min="0" step="0.1" placeholder="예: 172" /></label><label>몸무게 (kg)<input bind:value={characterForm.weight} type="number" min="0" step="0.1" placeholder="예: 64" /></label><label class="field-wide">특징<textarea bind:value={characterForm.roleTraits} rows="3" placeholder="역할의 특징, 성격, 전투 방식"></textarea></label></div></div><div class="form-actions"><button class="primary-btn" type="submit" disabled={characterSaving}>{characterSaving ? '저장 중…' : '기본 정보 저장'} <span>↗</span></button></div></div>
      {:else if profileSection === 'combat'}<div class="form-section combat-section"><div class="form-section-head"><div><p class="eyebrow">COMBAT STATUS</p><h2>전투 정보</h2></div></div><div class="combat-grid"><label>레벨<input value={character?.level ?? 1} disabled /></label><label>돈<input value={character?.money ?? 0} disabled /></label><label>HP<input value={`${character?.hp ?? 0} / ${character?.max_hp ?? 0}`} disabled /></label></div><div class="equipped-effects-panel"><div class="equipped-effects-head"><div><p class="eyebrow">EQUIPPED LOADOUT</p><h3>장착 효과</h3></div><span>{equippedItems.length}개</span></div>{#if equippedItems.length}<div class="equipped-effects-list">{#each equippedItems as item}<article class="equipped-effect-item"><div><strong>{item.item_name}</strong><span>{item.item_type}</span></div><p>{item.item_effect || '등록된 효과가 없습니다.'}</p></article>{/each}</div>{:else}<p class="equipped-effects-empty">장착된 장비 또는 유물이 없습니다.</p>{/if}</div><p class="form-note">{character?.combat_notes || '등록된 전투 메모가 없습니다.'}</p></div>
      {:else if profileSection === 'extra'}<div class="form-section extra-record-section"><div class="form-section-head"><div><p class="eyebrow">PERSONAL NOTES</p><h2>추가 기록</h2></div><span class="form-hint">게시판형 기록</span></div>{#if extraRecords.length}<div class="record-board">{#each extraRecords as record}<article class="record-board-item"><div class="record-board-meta"><strong>{record.title}</strong><span>{record.authorName} · {new Date(record.created_at).toLocaleDateString('ko-KR')}</span></div><p>{record.content}</p>{#if isAdmin || record.author_id === user?.id}<button class="record-delete" type="button" on:click={() => deleteExtraRecord(record)}>기록 삭제</button>{/if}</article>{/each}</div>{:else}<div class="repeat-empty">등록된 추가 기록이 없습니다.</div>{/if}<div class="record-compose"><input bind:value={extraRecordForm.title} placeholder="기록 제목" /><textarea bind:value={extraRecordForm.content} rows="5" placeholder="소환수, 개인 특징, 장기 목표 등 기록할 내용을 작성해 주세요."></textarea><button class="primary-btn" type="button" on:click={saveExtraRecord} disabled={extraRecordSaving}>{extraRecordSaving ? '등록 중…' : '기록 등록'} <span>↗</span></button></div></div>
      {:else if profileSection === 'relationships'}<div class="form-section relationship-section"><div class="form-section-head"><div><p class="eyebrow">RELATIONSHIPS</p><h2>관계</h2></div><span class="form-hint">호감도 없이 메모로 관리</span></div>{#if relationships.length}<div class="relationship-list">{#each relationships as relationship}<article class="relationship-item"><div class="relationship-item-head"><strong>{relationship.relationship_name}</strong>{#if relationship.npc_post_id}<a href={'#post/' + relationship.npc_post_id}>{relationship.npcTitle || 'NPC 페이지 열기'} ↗</a>{/if}</div>{#if relationship.memo}<p>{relationship.memo}</p>{/if}<button class="record-delete" type="button" on:click={() => deleteRelationship(relationship)}>관계 삭제</button></article>{/each}</div>{:else}<div class="repeat-empty">등록된 관계가 없습니다.</div>{/if}<div class="relationship-compose"><input bind:value={relationshipForm.name} placeholder="관계 이름 (예: 아르델과의 관계)" /><select bind:value={relationshipForm.npcPostId}><option value="">NPC 링크 없음</option>{#each npcOptions as npc}<option value={npc.id}>{npc.title}</option>{/each}</select><textarea bind:value={relationshipForm.memo} rows="5" placeholder="관계 메모를 작성해 주세요."></textarea><button class="primary-btn" type="button" on:click={saveRelationship} disabled={relationshipSaving}>{relationshipSaving ? '등록 중…' : '관계 등록'} <span>↗</span></button></div></div>
      {:else if profileSection === 'inventory'}<div class="form-section readonly-collection"><div class="form-section-head"><div><p class="eyebrow">INVENTORY</p><h2>인벤토리</h2></div><span class="form-hint">장비와 유물은 장착할 수 있습니다</span></div>{#if inventory.length}<div class="inventory-game-layout"><div class="inventory-slots">{#each inventory as item}<button class:active={selectedInventoryItem?.id === item.id} class:equipped={isEquippableItem(item) && item.is_equipped} class="inventory-slot" type="button" on:click={() => selectInventoryItem(item)}><span class="slot-icon">{#if isImageIcon(getInventoryIcon(item))}<img src={getInventoryIcon(item)} alt="" />{:else}{getInventoryIcon(item)}{/if}</span><span class="slot-count">{item.quantity}</span>{#if isEquippableItem(item) && item.is_equipped}<span class="equipped-mark">장착</span>{/if}</button>{/each}</div>{#if selectedInventoryItem}<article class="inventory-detail"><div class="inventory-detail-icon">{#if isImageIcon(getInventoryIcon(selectedInventoryItem))}<img src={getInventoryIcon(selectedInventoryItem)} alt="" />{:else}{getInventoryIcon(selectedInventoryItem)}{/if}</div><div><p class="eyebrow">ITEM DETAIL</p><h3>{selectedInventoryItem.item_name}</h3><div class="item-copy-block"><strong>[효과]</strong><p>{selectedInventoryItem.item_effect || '등록된 효과가 없습니다.'}</p></div><div class="item-copy-block"><strong>[설명]</strong><p>{selectedInventoryItem.item_description || '등록된 설명이 없습니다.'}</p></div><div><span class="tag">{selectedInventoryItem.grade}</span><span class="tag">{selectedInventoryItem.item_type}</span>{#if selectedInventoryItem.item_type === '장비'}<span class="tag">{selectedInventoryItem.equipment_slot || '부위 미지정'}</span>{/if}<span class="inventory-quantity">× {selectedInventoryItem.quantity}</span></div>{#if isEquippableItem(selectedInventoryItem)}<div class="inventory-equipment-actions"><button class="equipment-toggle-btn" type="button" on:click={() => toggleInventoryEquipment(selectedInventoryItem, character?.id)} disabled={equipmentSaving || (!selectedInventoryItem.is_equipped && selectedInventoryItem.item_type === '장비' && !selectedInventoryItem.equipment_slot)}>{selectedInventoryItem.is_equipped ? '장착 해제' : selectedInventoryItem.item_type === '장비' && !selectedInventoryItem.equipment_slot ? '부위 지정 필요' : '장착하기'}</button></div>{/if}</div></article>{:else}<div class="inventory-detail empty"><span>아이템을 선택하세요</span></div>{/if}</div>{:else}<div class="repeat-empty">등록된 아이템이 없습니다.</div>{/if}</div>
      {:else}<div class="form-section readonly-collection"><div class="form-section-head"><div><p class="eyebrow">CARDS</p><h2>보유 카드</h2></div></div>{#if cards.length}<div class="cards-grid">{#each cards as card}<article class="owned-card"><div class="owned-card-top"><strong>{card.card_name}</strong><span>{card.energy || 0} energy</span></div><div class="card-effect-copy"><strong>기본 효과</strong><p>{card.card_effect || '등록된 효과가 없습니다.'}</p></div>{#if card.card_exhaust_effect}<div class="card-effect-copy exhaust"><strong>소멸</strong><p>{card.card_exhaust_effect}</p></div>{/if}{#if card.card_drop_effect}<div class="card-effect-copy drop"><strong>추가 드롭</strong><p>{card.card_drop_effect}</p></div>{/if}<div><span class="tag">{card.grade}</span><span class="inventory-quantity">× {card.quantity}</span></div></article>{/each}</div>{:else}<div class="repeat-empty">등록된 카드가 없습니다.</div>{/if}</div>{/if}
    </form>
  </div>{/if}
</section>
