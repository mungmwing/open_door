<script>
  export let isEditPage = false;
  export let writeBoard = { slug: 'users', name: '유저 게시판' };
  export let writeBoardSlug = 'users';
  export let categories = [];
  export let isAdmin = false;
  export let editingPostId = null;
  export let postForm = {};
  export let npcImagePreview = '';
  export let postSaving = false;
  export let editLoading = false;
  export let richEditorElement;
  export let sessionEntries = [];
  export let sessionParticipants = [];
  export let sessionBgmIds = [];
  export let adminCharacters = [];
  export let npcOptions = [];
  export let bgmOptions = [];
  export let sessionParticipantValue = () => '';
  export let sessionParticipantName = () => '';
  export let sessionActorParticipants = [];
  export let sessionParticipantActorValue = () => '';
  export let setSessionParticipant = () => {};
  export let addSessionParticipant = () => {};
  export let removeSessionParticipant = () => {};
  export let addSessionBgm = () => {};
  export let setSessionBgm = () => {};
  export let removeSessionBgm = () => {};
  export let addSessionEntry = () => {};
  export let removeSessionEntry = () => {};
  export let moveSessionEntry = () => {};
  export let sessionActorValue = () => '';
  export let setSessionActor = () => {};
  export let sessionSpeakerValue = () => '';
  export let setSessionSpeaker = () => {};
  export let handleSessionImageChange = () => {};
  export let handleNpcImageChange = () => {};
  export let handleBgmFileChange = () => {};
  export let createPost = () => {};

  let titleInput;
  let validationAttempted = false;

  $: titleError = validationAttempted && writeBoardSlug === 'users' && !(postForm.title || '').trim() ? '제목을 입력해 주세요.' : '';
  $: contentError = validationAttempted && writeBoardSlug === 'users' && !(postForm.content || '').trim() ? '내용을 입력해 주세요.' : '';

  function submitWithValidation() {
    validationAttempted = true;
    if (writeBoardSlug === 'users' && !(postForm.title || '').trim()) {
      titleInput?.focus();
      return;
    }
    if (writeBoardSlug === 'users' && !(postForm.content || '').trim()) {
      richEditorElement?.querySelector('[contenteditable="true"]')?.focus();
      return;
    }
    createPost();
  }

  function confirmCancel(event) {
    if (writeBoardSlug !== 'users') return;
    const hasWrittenContent = Boolean((postForm.title || '').trim() || (postForm.content || '').trim() || (postForm.privatePassword || '').trim());
    if (hasWrittenContent && !confirm('작성 중인 내용이 사라집니다. 작성을 취소할까요?')) event.preventDefault();
  }
</script>

<section class="write-page panel" class:user-editor={writeBoardSlug === 'users'}>
  {#if isEditPage}<h1>{writeBoardSlug === 'sessions' ? '세션 기록 수정' : '게시글 수정'}</h1>{:else}<header class="write-brand-header" aria-label="open door"><span class="brand-mark" aria-hidden="true">od</span><span class="brand-copy"><strong>open door</strong><small>long-form TRPG campaign</small></span></header>{/if}
  {#if isEditPage}<p class="page-lead">등록된 기록을 같은 편집기에서 수정해 주세요.</p>{/if}
  <form class="editor-form" on:submit|preventDefault={submitWithValidation}>
    <label>게시판<select bind:value={writeBoardSlug} disabled={isEditPage}>{#each categories.slice(1).filter((board) => isAdmin || board.slug === 'users' || (isEditPage && editingPostId && board.slug === writeBoardSlug)) as board}<option value={board.slug}>{board.name}</option>{/each}</select></label>
    {#if writeBoardSlug === 'notices'}<label>공지 유형<select bind:value={postForm.postType}><option value="notice">공지</option><option value="patch">패치</option><option value="event">이벤트</option></select></label>{/if}
    {#if writeBoardSlug === 'npc'}
      <div class="npc-form-section"><p class="form-hint">NPC PROFILE</p><div class="field-grid"><label>이름<input bind:value={postForm.npcName} placeholder="예: 아르델" /></label><label>나이<input bind:value={postForm.npcAge} type="number" min="0" placeholder="예: 32" /></label><label>성별<input bind:value={postForm.npcGender} placeholder="예: 여성" /></label><label>키 (cm)<input bind:value={postForm.npcHeight} type="number" min="0" step="0.1" placeholder="예: 168" /></label><label>종족<input bind:value={postForm.npcRace} placeholder="예: 인간" /></label><label>역할/직업<input bind:value={postForm.npcRole} placeholder="예: 국경 수비대장" /></label><label>소속<input bind:value={postForm.npcAffiliation} placeholder="예: 북부 연합" /></label><label>성격<input bind:value={postForm.npcPersonality} placeholder="예: 냉정하지만 약자를 돕는다" /></label><label class="field-wide">NPC 특징<textarea bind:value={postForm.npcTraits} rows="4" placeholder="외형, 능력, 말투, 관계, TRPG 진행에 필요한 특징"></textarea></label><label class="npc-photo-field field-wide"><span>프로필 이미지</span><span class="npc-photo-preview">{#if npcImagePreview}<img src={npcImagePreview} alt="NPC 미리보기" />{:else}<span class="npc-photo-empty">사진을 선택하면 여기에 미리보기됩니다</span>{/if}</span><input type="file" accept="image/png,image/jpeg,image/webp" on:change={handleNpcImageChange} /></label></div></div>
    {/if}
    {#if writeBoardSlug === 'bgm'}<div class="bgm-form-section"><p class="form-hint">BGM LIBRARY</p><div class="field-grid"><label>BGM 분류<select bind:value={postForm.bgmCategory}><option value="map">맵 BGM</option><option value="character">캐릭터 BGM</option><option value="scene">장면 BGM</option><option value="etc">기타 BGM</option></select></label><label class="field-wide">오디오 URL (선택)<input bind:value={postForm.bgmUrl} type="url" placeholder="https://example.com/theme.mp3" /></label><label class="bgm-file-field field-wide">오디오 파일 (선택)<input type="file" accept="audio/mpeg,audio/ogg,audio/wav,audio/x-wav,audio/mp4,audio/aac" on:change={handleBgmFileChange} />{#if postForm.bgmFile}<span>{postForm.bgmFile.name} · 업로드 예정</span>{/if}</label></div><p class="form-note">URL 또는 파일 중 하나를 등록해 주세요. 파일은 BGM 게시판에 업로드되어 세션에서 선택할 수 있습니다.</p></div>{/if}
    {#if writeBoardSlug !== 'npc'}<label class:field-invalid={Boolean(titleError)}><input bind:this={titleInput} bind:value={postForm.title} maxlength="120" placeholder="글 제목을 입력해 주세요" aria-label="제목" aria-invalid={titleError ? 'true' : 'false'} aria-describedby={titleError ? 'post-title-error' : undefined} />{#if titleError}<small class="field-error" id="post-title-error">{titleError}</small>{/if}</label>{/if}
    <div class="private-post-settings"><label class="private-post-toggle"><input type="checkbox" bind:checked={postForm.isPrivate} /><span><strong>비밀글</strong></span></label>{#if postForm.isPrivate}<label><input bind:value={postForm.privatePassword} type={isEditPage ? 'text' : 'password'} minlength="4" autocomplete="off" placeholder="비밀번호를 입력해 주세요" aria-label="비밀글 비밀번호" />{#if isEditPage}<small class="private-post-edit-note">수정 페이지에서만 기존 비밀번호가 표시됩니다.</small>{/if}</label>{/if}</div>
    {#if writeBoardSlug === 'sessions'}
      <div class="editor-field"><span>내용</span><div class="session-composer"><div class="session-composer-head"><div><p class="eyebrow">SESSION LOG BUILDER</p><h2>플레이 기록</h2><p>+ 버튼으로 지문, 대사, 사진을 원하는 순서대로 쌓아 보세요.</p></div><div class="session-add-menu"><span>+ 항목 추가</span><button type="button" on:click={() => addSessionEntry('narration')}>지문</button><button type="button" on:click={() => addSessionEntry('dialogue')}>대사</button><button type="button" on:click={() => addSessionEntry('image')}>사진</button></div></div>
        <div class="session-participants"><div class="session-participants-head"><div><strong>세션 참여자</strong><span>이번 세션에 등장한 캐릭터와 NPC를 추가해 주세요.</span></div><button class="subtle-btn" type="button" on:click={addSessionParticipant}>+ 참여자 추가</button></div>{#if sessionParticipants.length}<div class="session-participant-list">{#each sessionParticipants as participant, participantIndex (participant.id)}<div class="session-participant-row"><select value={sessionParticipantValue(participant)} on:change={(event) => setSessionParticipant(participant, event.currentTarget.value)}><option value="custom:">직접 입력</option>{#if adminCharacters.length}<optgroup label="캐릭터">{#each adminCharacters as character}<option value={'character:' + character.id}>{character.name}</option>{/each}</optgroup>{/if}{#if npcOptions.length}<optgroup label="NPC">{#each npcOptions as npc}<option value={'npc:' + npc.id}>{npc.npcName || npc.title}</option>{/each}</optgroup>{/if}</select>{#if participant.participantType === 'custom'}<input bind:value={participant.participantName} placeholder="참여자 이름" />{:else}<span>{sessionParticipantName(participant)}</span>{/if}<button class="icon-btn" type="button" on:click={() => removeSessionParticipant(participantIndex)} aria-label="참여자 삭제">×</button></div>{/each}</div>{:else}<p class="session-participants-empty">등록된 참여자가 없습니다.</p>{/if}</div>
        <div class="session-bgms"><div class="session-participants-head"><div><strong>세션 BGM</strong><span>이번 세션에서 사용할 등록된 BGM을 선택해 주세요.</span></div><button class="subtle-btn" type="button" on:click={addSessionBgm}>+ BGM 추가</button></div>{#if bgmOptions.length}{#if sessionBgmIds.length}<div class="session-bgm-list">{#each sessionBgmIds as bgmId, bgmIndex}<div class="session-bgm-row"><select value={bgmId} on:change={(event) => setSessionBgm(bgmIndex, event.currentTarget.value)}><option value="">BGM을 선택해 주세요</option>{#each bgmOptions as bgm}<option value={bgm.id}>{bgm.title} · {({ map: '맵', character: '캐릭터', scene: '장면', etc: '기타' })[bgm.bgmCategory] || 'BGM'}</option>{/each}</select><button class="icon-btn" type="button" on:click={() => removeSessionBgm(bgmIndex)} aria-label="BGM 삭제">×</button></div>{/each}</div>{:else}<p class="session-participants-empty">등록된 BGM이 없습니다. + BGM 추가를 눌러 선택해 주세요.</p>{/if}{:else}<p class="session-participants-empty">등록된 BGM이 없습니다. <a href="#board/bgm">BGM 게시판에서 먼저 등록해 주세요.</a></p>{/if}</div>
        <div class="session-entry-list">{#if sessionEntries.length}{#each sessionEntries as entry, index (entry.id)}<article class={'session-entry session-entry-' + entry.type}><div class="session-entry-top"><span class="session-entry-number">{String(index + 1).padStart(2, '0')}</span><strong>{entry.type === 'narration' ? '지문' : entry.type === 'dialogue' ? '대사' : '사진'}</strong><div class="session-entry-actions"><button class="icon-btn" type="button" disabled={index === 0} on:click={() => moveSessionEntry(index, -1)} aria-label="위로 이동">↑</button><button class="icon-btn" type="button" disabled={index === sessionEntries.length - 1} on:click={() => moveSessionEntry(index, 1)} aria-label="아래로 이동">↓</button><button class="icon-btn" type="button" on:click={() => removeSessionEntry(index)} aria-label="항목 삭제">×</button></div></div>{#if entry.type === 'narration'}<div class="session-entry-meta"><label>지문의 주체<select value={sessionActorValue(entry)} on:change={(event) => setSessionActor(entry, event.currentTarget.value)}>{#if sessionActorParticipants.length}<optgroup label="세션 참여자">{#each sessionActorParticipants as participant (sessionParticipantActorValue(participant))}<option value={sessionParticipantActorValue(participant)}>{sessionParticipantName(participant)}</option>{/each}</optgroup>{/if}<option value="none:">없음</option><option value="custom:">직접 입력</option>{#if adminCharacters.length}<optgroup label="전체 캐릭터">{#each adminCharacters as character}{#if !sessionActorParticipants.some((participant) => participant.participantType === 'character' && participant.participantId === character.id)}<option value={'character:' + character.id}>{character.name}</option>{/if}{/each}</optgroup>{/if}{#if npcOptions.length}<optgroup label="전체 NPC">{#each npcOptions as npc}{#if !sessionActorParticipants.some((participant) => participant.participantType === 'npc' && participant.participantId === npc.id)}<option value={'npc:' + npc.id}>{npc.npcName || npc.title}</option>{/if}{/each}</optgroup>{/if}</select></label>{#if entry.actorType === 'custom'}<label>이름<input bind:value={entry.actorName} placeholder="지문을 묘사하는 이름" /></label>{/if}</div>{:else if entry.type === 'dialogue'}<div class="session-entry-meta"><label>말한 사람<select value={sessionSpeakerValue(entry)} on:change={(event) => setSessionSpeaker(entry, event.currentTarget.value)}><option value="anonymous:">??? (얼굴 없는 대사)</option><option value="custom:">직접 입력</option>{#each adminCharacters as character}<option value={'character:' + character.id}>{character.name}</option>{/each}{#each npcOptions as npc}<option value={'npc:' + npc.id}>{npc.npcName || npc.title}</option>{/each}</select></label>{#if entry.speakerType === 'custom'}<label>이름<input bind:value={entry.speakerName} placeholder="대사 이름" /></label>{/if}</div>{:else}<label class="session-image-picker">사진<input type="file" accept="image/png,image/jpeg,image/webp" on:change={(event) => handleSessionImageChange(event, index)} />{#if entry.imageUrl}<img src={entry.imageUrl} alt="세션 사진 미리보기" />{:else}<span>사진을 선택해 주세요</span>{/if}</label><label>사진 설명 (선택)<input bind:value={entry.caption} placeholder="장면 설명이나 사진 캡션" /></label>{/if}{#if entry.type !== 'image'}<label class="session-entry-text">{entry.type === 'narration' ? '지문 내용' : '대사 내용'}<textarea bind:value={entry.text} rows="4" placeholder={entry.type === 'narration' ? '행동, 분위기, 상황을 적어 주세요.' : '캐릭터 또는 NPC의 대사를 적어 주세요.'}></textarea></label>{/if}</article>{/each}{:else}<div class="session-entry-empty"><strong>아직 항목이 없습니다</strong><span>위의 + 항목 추가에서 지문, 대사, 사진을 골라 주세요.</span></div>{/if}</div>
      </div></div>
    {:else}<div class="editor-field" class:user-rich-editor={writeBoardSlug === 'users'} class:field-invalid={Boolean(contentError)}>{#if writeBoardSlug !== 'users'}<span>{writeBoardSlug === 'npc' ? '상세 설명' : '내용'}</span>{/if}{#if writeBoardSlug === 'users'}<div class="rich-editor-host" bind:this={richEditorElement}></div>{#if contentError}<small class="field-error" id="post-content-error">{contentError}</small>{/if}{:else}<textarea bind:value={postForm.content} rows="14" placeholder={writeBoardSlug === 'npc' ? 'TRPG 진행에 필요한 추가 설명을 작성해 주세요' : '모험의 기록을 남겨 주세요'}></textarea>{/if}</div>{/if}
    <div class="form-actions"><a class="text-link" href={'#board/' + writeBoard.slug} on:click={confirmCancel}>취소</a><button class="primary-btn" type="submit" disabled={postSaving || (isEditPage && editLoading)}>{postSaving ? '저장 중…' : editLoading ? '기존 내용 불러오는 중…' : editingPostId ? (writeBoardSlug === 'sessions' ? '세션 기록 수정' : '게시글 수정') : '게시글 등록'} <span>↗</span></button></div>
  </form>
</section>
