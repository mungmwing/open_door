<script>
  import { onMount } from 'svelte';
  import { supabase } from '../supabaseClient';
  import CardEffectEditor from '../components/CardEffectEditor.svelte';
  import BattleExtras from '../components/BattleExtras.svelte';
  import { STATUS_KINDS, EFFECTS, playersForViewer } from '../lib/combat';
  import BattleConsumables from '../components/BattleConsumables.svelte';
  import { ROOM_STATUS, effectText, cardCost, targetSide, uniqueCards, enemyIntent, combatError, emptyCombatRule, validateCombatRule, cardDestination, extraCardDraw, personalCost, resourceName, canPayCard } from '../lib/combat';
  export let user = null;
  export let authReady = false;
  export let profileLoading = false;
  export let isAdmin = false;
  export let currentRoute = 'combat';
  export let requestLogin = () => {};

  let mounted = false;
  let contextKey = '';
  let epoch = 0;
  let roomId = '';
  let room = null;
  let rooms = [];
  let loading = true;
  let busy = false;
  let error = '';
  let syncError = '';
  let connection = '연결 중';
  let lastSync = '';
  let channel;
  let timer;
  let activeFetch = null;
  let roomName = '';
  let enemyDraft = [{ name: '문지기', hp: 80, attack: 6, guard: 8 }];
  let seededRoom = '';
  let editId = '';
  let ruleDraft = { playable: true, exhaust: false, effects: [], on_exhaust: [] };
  let selectedCardId = '';
  let selectedTarget = '';
  let confirmClose = false;
  let copied = false;
  let availableConsumables = [];
  let consumableCatalog = [];
  let resourceError = '';
  let monsterCatalog = [];
  let monsterError = '';
  let monsterId = '';
  async function loadMonsters(at=epoch) { try { const r=await supabase.from('combat_monsters').select('*').order('name');if(at!==epoch)return;monsterCatalog=r.data||[];monsterError=r.error ? (['PGRST205','42P01'].includes(r.error.code) ? '몬스터 기능은 add_combat_monsters_relics.sql 적용 후 사용할 수 있습니다.' : r.error.message) : ''; } catch(e){if(at===epoch)monsterError=e.message;} }
  function addMonster() {const m=monsterCatalog.find(m=>m.id===monsterId);if(m && enemyDraft.length<6)enemyDraft=[...enemyDraft,{...structuredClone(m),catalog_id:m.id}];}
  const statusLabels = STATUS_KINDS.map(key=>[key,EFFECTS[key]]);
  const activeStatuses = (unit) => statusLabels.filter(([key]) => unit[key]);
  async function loadResources(at=epoch) {
    if(!supabase || !user) return;
    try {
      const [available,catalog] = await Promise.all([supabase.rpc('combat_available_consumables'),supabase.from('items').select('*').eq('item_type','소비')]);
      if(at!==epoch) return;
      resourceError = available.error ? (available.error.code === 'PGRST202' || available.error.code === '42883' ? '소비 아이템 기능을 사용하려면 add_combat_consumables_energy.sql을 적용해 주세요.' : available.error.message) : catalog.error?.message || '';
      availableConsumables=available.data || []; consumableCatalog=catalog.data || [];
    } catch (problem) {
      if(at===epoch) resourceError = problem.message || '소비 아이템 목록을 불러오지 못했습니다. 다시 새로고침해 주세요.';
    }
  }

  $: players = room?.state?.players || [];
  $: displayPlayers = playersForViewer(players,user?.id);
  $: spectating = !!room && !me && !host && room.spectator_ids?.includes(user?.id);
  $: enemies = room?.state?.enemies || [];
  $: allies = [...players,...(room?.state?.summons || [])];
  $: selectableTargets = selectedSide === 'players' ? allies : enemies;
  $: rules = room?.state?.rules || {};
  $: host = !!room && room.created_by === user?.id && isAdmin;
  $: me = players.find((p) => p.owner_id === user?.id);
  $: allCards = uniqueCards(players);
  $: missingRules = allCards.filter((c) => !rules[c.id]).length;
  $: readyCount = players.filter((p) => p.ready).length;
  $: round = room?.state?.round || 1;
  $: selectedCard = me?.hand.find((c) => c.instance_id === selectedCardId);
  $: selectedRule = selectedCard && rules[selectedCard.id];
  $: selectedSide = targetSide(selectedRule);
  $: targetValid = !selectedSide || selectableTargets.some((p) => p.id === selectedTarget && p.hp > 0);
  $: canAct = room?.status === 'active' && me?.hp > 0 && !me?.ended;
  $: invitation = rooms.find((r) => r.id === roomId);
  $: if (mounted) connect(currentRoute, user?.id);
  $: if (room && seededRoom !== room.id) {
    seededRoom = room.id;
    if (room.state.enemies.length) enemyDraft = room.state.enemies.map((e) => ({ name: e.name, hp: e.max_hp, attack: e.attack, guard: e.guard, initial_powers:e.initial_powers || [], actions:e.actions || [] }));
  }

  function accept(next) {
    if (next && next.id === roomId && (!room || next.version >= room.version)) room = next;
  }
  async function watchRoom(target=room,watch=true) {
    if(!target || busy || !supabase) return;
    busy=true;error='';const at=epoch;
    try {
      const result=await supabase.rpc('combat_watch_room',{p_room_id:target.id,p_watch:watch});
      if(result.error)throw result.error;
      if(at!==epoch)return;
      if(!watch){window.location.hash='#combat';return;}
      if(roomId!==target.id)window.location.hash=`#combat/${target.id}`;
      else accept(result.data);
    } catch(e){if(at===epoch)error=['PGRST202','42883','42703'].includes(e.code)?'관전 기능은 add_combat_spectators.sql 적용 후 사용할 수 있습니다.':combatError(e);}
    finally{if(at===epoch)busy=false;}
  }
  async function sync(at = epoch) {
    if (!supabase || !user || at !== epoch) return;
    if (activeFetch?.epoch === at) return activeFetch.promise;
    const fetch = async () => {
      try {
        if (roomId) {
          const result = await supabase.from('combat_rooms').select('*').eq('id', roomId).maybeSingle();
          if (result.error) throw result.error;
          if (at !== epoch) return;
          accept(result.data);
          if (!result.data) {
            room = null;
            const list = await supabase.rpc('combat_list_rooms');
            if (list.error) throw list.error;
            if (at !== epoch) return;
            rooms = list.data || [];
          }
        } else {
          const result = await supabase.rpc('combat_list_rooms');
          if (result.error) throw result.error;
          if (at !== epoch) return;
          rooms = result.data || [];
        }
        syncError = '';
        lastSync = new Date().toLocaleTimeString('ko-KR');
      } catch (e) { if (at === epoch) syncError = combatError(e); }
      finally { if (at === epoch) loading = false; }
    };
    const promise = fetch();
    activeFetch = { epoch: at, promise };
    try { await promise; } finally { if (activeFetch?.promise === promise) activeFetch = null; }
  }
  function cleanup() {
    clearInterval(timer);
    if (channel) { void supabase?.removeChannel(channel); channel = null; }
  }
  function connect(route, uid) {
    const key = `${route}:${uid || ''}`;
    if (key === contextKey) return;
    contextKey = key;
    cleanup();
    const at = ++epoch;
    roomId = route.startsWith('combat/') ? route.slice(7) : '';
    room = null; rooms = []; error = ''; syncError = ''; loading = true; busy = false;
    availableConsumables = []; consumableCatalog = []; resourceError = '';
    monsterCatalog=[];monsterError='';monsterId='';
    if(uid) void loadMonsters(at);
    selectedCardId = ''; selectedTarget = ''; editId = ''; seededRoom = ''; confirmClose = false;
    if (!uid) { loading = false; return; }
    if (!supabase) { syncError = '서버 연결 설정이 없습니다. 관리자에게 문의해 주세요.'; loading = false; return; }
    if (roomId && !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(roomId)) {
      syncError = '올바르지 않은 방 주소입니다.'; loading = false; return;
    }
    void sync(at); void loadResources(at);
    timer = setInterval(() => { if (!document.hidden) void sync(at); }, 3000);
    connection = roomId ? '실시간 연결 중' : '3초마다 갱신';
    if (roomId) channel = supabase.channel(`combat:${roomId}:${uid}:${at}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'combat_rooms', filter: `id=eq.${roomId}` }, ({ new: next }) => {
        if (at === epoch) { accept(next); void sync(at); }
      }).subscribe((status) => {
        if (at !== epoch) return;
        connection = status === 'SUBSCRIBED' ? '실시간 연결됨' : '3초마다 재확인';
        if (status === 'SUBSCRIBED') void sync(at);
      });
  }
  onMount(() => {
    mounted = true;
    const refresh = () => { if (!document.hidden) void sync(); };
    window.addEventListener('online', refresh);
    document.addEventListener('visibilitychange', refresh);
    return () => { mounted = false; epoch++; cleanup(); window.removeEventListener('online', refresh); document.removeEventListener('visibilitychange', refresh); };
  });
  async function createRoom() {
    if (busy || !roomName.trim()) return;
    const at = epoch; busy = true; error = '';
    try {
      const { data, error: problem } = await supabase.rpc('combat_create_room', { p_name: roomName.trim() });
      if (problem) throw problem;
      if (at === epoch) location.hash = `combat/${data.id}`;
    } catch (e) { if (at === epoch) error = combatError(e); }
    finally { if (at === epoch) busy = false; }
  }
  function isCompletedRoom(targetRoom) {
    return !!targetRoom && ['victory', 'defeat', 'closed'].includes(targetRoom.status);
  }
  async function deleteCombatRoom(targetRoom) {
    if (busy || !supabase || !isAdmin || targetRoom?.created_by !== user?.id || !isCompletedRoom(targetRoom)) return;
    if (!confirm(`'${targetRoom.name}' 전투 기록을 삭제할까요?\n삭제한 기록은 복구할 수 없습니다.`)) return;
    const at = epoch;
    busy = true;
    error = '';
    try {
      const { error: problem } = await supabase.rpc('combat_delete_room', { p_room_id: targetRoom.id });
      if (problem) throw problem;
      if (at !== epoch) return;
      rooms = rooms.filter((item) => item.id !== targetRoom.id);
      if (roomId === targetRoom.id) location.hash = 'combat';
    } catch (problem) {
      if (at === epoch) {
        error = ['PGRST202', '42883'].includes(problem?.code) || /Could not find the function|schema cache/i.test(problem?.message || '')
          ? '전투 기록 삭제 기능의 데이터베이스 설정이 필요합니다. add_combat_room_delete.sql을 적용한 뒤 새로고침해 주세요.'
          : combatError(problem);
      }
    } finally {
      if (at === epoch) busy = false;
    }
  }
  async function act(action, payload = {}, targetRoom = room) {
    if (busy || !targetRoom || !supabase) return false;
    const at = epoch; busy = true; error = '';
    try {
      const { data, error: problem } = await supabase.rpc('combat_room_action', {
        p_room_id: targetRoom.id, p_version: targetRoom.version, p_action: action, p_payload: payload
      });
      if (problem) throw problem;
      if (at !== epoch) return false;
      accept(data);
      if (action === 'join') location.hash = `combat/${data.id}`;
      if (action === 'leave') location.hash = 'combat';
      if (['join','loadout','use_item'].includes(action)) await loadResources(at);
      return true;
    } catch (e) { if (at === epoch) { error = combatError(e); await sync(at); } return false; }
    finally { if (at === epoch) busy = false; }
  }
  function editRule(id) {
    editId = id;
    ruleDraft = structuredClone(rules[id] || emptyCombatRule());
  }
  async function playSelected() {
    if (!selectedCard || !canAct || !targetValid || !selectedRule?.playable || !canPayCard(me, selectedCard, selectedRule)) return;
    if (await act('play', { instance_id: selectedCard.instance_id, target_id: selectedTarget || null })) { selectedCardId = ''; selectedTarget = ''; }
  }
  function chooseCard(card) { selectedCardId = card.instance_id; selectedTarget = ''; }
  async function copyInvite() {
    try { await navigator.clipboard.writeText(location.href); copied = true; }
    catch { error = '주소를 복사하지 못했습니다. 브라우저 주소창의 방 주소를 공유해 주세요.'; }
  }
</script>

<section class="battle-page panel" class:in-battle={room && room.status !== 'waiting'}>
  <header class="battle-heading">
    <div><p class="eyebrow">CO-OP CARD BATTLE</p><h1>{room?.name || '전투 대기실'}</h1><p>{room ? `${ROOM_STATUS[room.status]} · ${players.length}/6명` : '보유 카드로 함께 싸우는 협동 전투'}</p></div>
    <div class="battle-actions">
      {#if roomId}<a class="subtle-btn" href="#combat">방 목록</a>{/if}
      {#if room}<button class="subtle-btn" on:click={copyInvite}>{copied ? '주소 복사됨' : '초대 주소 복사'}</button>{/if}
      {#if host && isCompletedRoom(room)}<button class="danger-btn" disabled={busy} on:click={() => deleteCombatRoom(room)}>전투 기록 삭제</button>{/if}
      {#if spectating}<span class="battle-tag">관전 중</span><button class="subtle-btn" disabled={busy} on:click={()=>watchRoom(room,false)}>관전 나가기</button>{/if}
      {#if user}<button class="subtle-btn" disabled={loading || busy} on:click={() => sync()}>새로고침</button>{/if}
    </div>
  </header>

  {#if !authReady || profileLoading}
    <div class="battle-empty">접속 정보를 확인하고 있습니다.</div>
  {:else if !user}
    <div class="battle-empty"><span class="battle-emblem">⚔</span><h2>파티와 함께 전투에 참가하세요</h2><p>로그인하면 참가 가능한 방과 내 전투를 확인할 수 있습니다.</p><button class="primary-btn" on:click={requestLogin}>로그인하고 참가하기</button></div>
  {:else}
    {#if error}<div class="battle-alert" role="alert">{error}<button aria-label="알림 닫기" on:click={() => error = ''}>×</button></div>{/if}
    {#if syncError}<div class="battle-alert" role="alert">{syncError}</div>{/if}
    {#if loading}<div class="battle-empty">전투방을 불러오고 있습니다.</div>
    {:else if !room && !roomId}
      {#if isAdmin}
        <form class="battle-create" on:submit|preventDefault={createRoom}>
          <label>새 전투방<input bind:value={roomName} maxlength="80" required placeholder="예: 잿빛 성문 돌파" /></label>
          <button class="primary-btn" disabled={busy || !!syncError || !roomName.trim()}>방 만들기 <span>＋</span></button>
        </form>
      {/if}
      <div class="battle-room-list">
        {#each rooms as item (item.id)}
          <article class="battle-room-row"><span class="battle-room-icon">⚔</span><div><span class="battle-tag">{ROOM_STATUS[item.status]}</span><h2>{item.name}</h2><p>{item.player_count}/6명 {item.created_by === user.id ? '· 내가 만든 방' : item.is_member ? '· 참가 중' : ''}</p></div>
            <div class="battle-room-actions">{#if item.is_member || item.created_by === user.id}<a class="primary-btn" href={`#combat/${item.id}`}>방 열기 →</a>
              {:else}<button class="subtle-btn" disabled={busy || item.status !== 'waiting' || item.player_count >= 6} on:click={() => act('join', {}, item)}>{item.status === 'waiting' ? '내 캐릭터로 참가' : '전투 진행 중'}</button>{/if}
              {#if !item.is_member && item.created_by!==user.id}<button class="primary-btn" disabled={busy} on:click={()=>watchRoom(item)}>관전하기</button>{/if}
              {#if isAdmin && item.created_by === user.id && isCompletedRoom(item)}<button class="danger-btn" type="button" disabled={busy} on:click={() => deleteCombatRoom(item)}>기록 삭제</button>{/if}</div>
          </article>
        {:else}<div class="battle-empty"><span class="battle-emblem">◇</span><h2>{syncError ? '전투방을 불러올 수 없습니다' : '아직 열린 전투방이 없습니다'}</h2><p>{isAdmin ? '방을 만들고 적을 설정한 뒤 플레이어를 초대하세요.' : '관리자가 방을 만들면 이곳에 표시됩니다.'}</p></div>{/each}
      </div>
    {:else if !room}
      <div class="battle-empty"><h2>{invitation?.name || '방에 입장할 수 없습니다'}</h2><p>{invitation ? `${ROOM_STATUS[invitation.status]} · ${invitation.player_count}/6명` : '방 주소와 참가 권한을 확인해 주세요.'}</p>
        {#if invitation}<button class="subtle-btn" disabled={busy} on:click={()=>watchRoom(invitation)}>관전하기</button>{/if}
        {#if invitation?.status === 'waiting'}<button class="primary-btn" disabled={busy || invitation.player_count >= 6} on:click={() => act('join', {}, invitation)}>내 캐릭터로 참가하기</button>{/if}
      </div>
    {:else if room.status === 'waiting'}
      <div class="battle-setup-grid">
        <section class="battle-box">
          <div class="battle-section-head"><h2>참가자 <span>{players.length}/6</span></h2>{#if !me}<button class="subtle-btn" disabled={busy || players.length >= 6} on:click={() => act('join')}>내 캐릭터로 참가</button>{/if}</div>
          {#each displayPlayers as player, playerIndex (player.id)}
            <div class="battle-member"><span class="battle-avatar">{#if player.avatar_url}<img src={player.avatar_url} alt="" />{:else}{player.name.slice(0,1)}{/if}</span><div><strong>플레이어 {playerIndex+1} · {player.name} {player.owner_id === user.id ? '(나)' : ''}</strong><small>HP {player.hp}/{player.max_hp} · 보유 덱 {player.cards.length}장{player.personal_config?.name ? ` · ${resourceName(player)} ${player.personal_energy}/${player.personal_config.max}` : ''}</small></div><span class:ready={player.ready} class="battle-tag">{player.ready ? '준비 완료' : '준비 중'}</span></div>
          {:else}<p class="battle-muted">초대 주소를 공유하고 플레이어의 참가를 기다려 주세요.</p>{/each}
          {#if me}<div class="battle-actions"><button class="primary-btn" disabled={busy || missingRules > 0 || !enemies.length} on:click={() => act('ready')}>{me.ready ? '준비 취소' : '준비 완료'}</button><button class="subtle-btn" disabled={busy} on:click={() => act('leave')}>대기실 나가기</button></div>{/if}
          <p class="battle-help">참가 시점의 HP와 보유 덱을 사용합니다. 덱을 갱신하려면 나갔다가 다시 참가하세요.</p>
        </section>
        <section class="battle-box">
          <div class="battle-section-head"><h2>적 편성</h2><span class="battle-tag">{enemies.length}명 저장됨</span></div>
          {#if host}
            <div class="battle-monster-picker"><label>등록된 몬스터<select bind:value={monsterId}><option value="">몬스터 선택</option>{#each monsterCatalog as monster}<option value={monster.id}>{monster.name} · HP {monster.hp}</option>{/each}</select></label><button class="subtle-btn" disabled={busy || !monsterId || enemyDraft.length>=6} on:click={addMonster}>편성에 추가</button><button class="subtle-btn" disabled={busy} on:click={()=>loadMonsters()}>목록 새로고침</button><a href="#admin/monsters" target="_blank" rel="noopener">몬스터 관리</a>{#if monsterError}<p class="battle-help">{monsterError}</p>{/if}</div>
            <form on:submit|preventDefault={() => act('configure', { enemies: enemyDraft })}>
              {#each enemyDraft as enemy, i}<div class="battle-enemy-editor">
                <label>이름<input disabled={!!enemy.catalog_id} bind:value={enemy.name} required maxlength="60" /></label><label>HP<input type="number" disabled={!!enemy.catalog_id} bind:value={enemy.hp} min="1" max="99999" step="1" required /></label><label>공격<input type="number" disabled={!!enemy.catalog_id} bind:value={enemy.attack} min="0" max="999" step="1" required /></label><label>방어<input type="number" disabled={!!enemy.catalog_id} bind:value={enemy.guard} min="0" max="999" step="1" required /></label>
                <button class="battle-icon-btn" type="button" aria-label={`적 ${i + 1} 삭제`} disabled={enemyDraft.length === 1 || busy} on:click={() => enemyDraft = enemyDraft.filter((_, n) => i !== n)}>×</button>
              </div>{#if enemy.catalog_id || enemy.actions?.length || enemy.initial_powers?.length}<p class="battle-help">시작 파워 {(enemy.powers || enemy.initial_powers || []).map(effectText).join(' / ') || '없음'} · 행동 {enemy.actions?.map(a=>a.name).join(' → ') || '기본 순환'}</p>{/if}{/each}
              <div class="battle-actions"><button class="subtle-btn" type="button" disabled={enemyDraft.length >= 6 || busy} on:click={() => enemyDraft = [...enemyDraft, { name: '추종자', hp: 30, attack: 4, guard: 5 }]}>적 추가</button><button class="primary-btn" disabled={busy}>적 편성 저장</button></div>
            </form>
          {:else}{#each enemies as enemy}<p>{enemy.name} · HP {enemy.max_hp} · 공격 {enemy.attack} · 방어 {enemy.guard}</p>{:else}<p class="battle-muted">방장이 적을 편성하고 있습니다.</p>{/each}{/if}
          <p class="battle-help">행동을 따로 설정한 몬스터는 등록된 순서로 반복합니다. 기본 몬스터는 공격 → 방어 → 강타(공격 ×2)를 순환합니다. 저장 시 등록된 몬스터의 최신 설정을 복사합니다.</p>
        </section>
      </div>
      {#if me}<BattleConsumables player={me} players={allies} {enemies} waiting {busy} available={availableConsumables} error={resourceError} onAct={act} onRefresh={()=>loadResources()} />{/if}
      <section class="battle-box battle-rules">
        <div class="battle-section-head"><h2>보유 카드의 전투 효과</h2><span class="battle-tag">{allCards.length - missingRules}/{allCards.length} 설정됨</span></div>
        <p class="battle-muted">{host ? '카드 설정에서 저장한 전투 효과는 참가 시 자동 적용됩니다. 미설정 카드는 효과를 지정하세요. 적·카드·참가자가 바뀌면 준비가 해제됩니다.' : '설정된 카드 효과를 확인하고 준비 완료를 눌러 주세요.'}</p>
        <div class="battle-rule-layout"><div class="battle-rule-list">
          {#each allCards as card (card.id)}<button class:chosen={editId === card.id} class="battle-rule-item" on:click={() => editRule(card.id)}><span>{card.card_name}<small>{card.ownerName} · 에너지 {cardCost(card)}</small></span><b>{rules[card.id] ? '✓' : '미설정'}</b></button>{:else}<p class="battle-muted">참가자가 들어오면 보유 카드가 표시됩니다.</p>{/each}
        </div>
        {#if allCards.find((c) => c.id === editId)}
          {@const card = allCards.find((c) => c.id === editId)}
          <div class="battle-rule-detail"><h3>{card.card_name}</h3><blockquote>{card.card_effect || '기본 효과 설명 없음'}{#if card.card_exhaust_effect}<br />소멸 시 설명: {card.card_exhaust_effect}{/if}{#if card.card_drop_effect || card.card_drop_count}<br />추가 드로우 {card.card_drop_count || ''}: {card.card_drop_effect || ''}{/if}</blockquote>
            <p class="battle-help">{card.card_type || '스킬'} · {card.card_target || '자신'} {card.card_innate ? '· 선천' : ''} {card.card_retain ? '· 유지' : ''} {card.card_ethereal ? '· 에테리얼' : ''}</p>
            {#if card.combat_rule}<p class="battle-help">카드 설정 페이지에 사전 설정이 있는 카드입니다. 참가 시 불러온 효과를 이 방에서 수정할 수 있습니다.</p>{/if}
            {#if host}<form on:submit|preventDefault={() => { const problem = validateCombatRule(ruleDraft); if (problem) error = problem; else act('rule', { card_id: editId, rule: ruleDraft }); }}>
              <CardEffectEditor value={ruleDraft} {card} catalogItems={consumableCatalog} personalEnergyName={players.find(p=>p.cards.some(c=>c.id===card.id))?.personal_config?.name} disabled={busy} onChange={(value) => ruleDraft = value} />
              <p class="battle-help">이곳에서 저장한 효과는 현재 전투방에만 적용됩니다.</p><button class="primary-btn" disabled={busy || !!validateCombatRule(ruleDraft)}>이 카드 효과 저장</button>
            </form>{:else}{#if rules[card.id]}<p>{rules[card.id].playable ? '사용 가능' : '사용 불가'} · {cardDestination(card, rules[card.id])}</p>{#each rules[card.id].effects as effect}<p>{effectText(effect)}</p>{/each}{#each rules[card.id].on_exhaust as effect}<p>소멸 시 발동: {effectText(effect)}</p>{/each}{:else}<p>방장이 효과를 설정하고 있습니다.</p>{/if}{/if}
          </div>
        {:else}<div class="battle-rule-detail battle-muted">카드를 선택하면 원문과 전투 효과를 확인할 수 있습니다.</div>{/if}</div>
      </section>
      <div class="battle-start-bar"><div><strong>준비 완료 {readyCount}/{players.length}명</strong><p>{missingRules ? `카드 ${missingRules}종의 효과 설정이 남았습니다.` : '매 턴 에너지 3 · 카드 5장 · 손패 최대 10장'}</p></div>{#if host}<button class="primary-btn" disabled={busy || !players.length || !enemies.length || missingRules > 0 || readyCount !== players.length} on:click={() => act('start')}>전투 시작 ⚔</button>{/if}</div>
    {:else}
      {#if room.status !== 'active'}<div class="battle-result" data-status={room.status}><span>{room.status === 'victory' ? '✦' : '◇'}</span><h2>{ROOM_STATUS[room.status]}</h2><p>{room.status === 'victory' ? '파티가 모든 적을 쓰러뜨렸습니다.' : room.status === 'defeat' ? '파티가 모두 쓰러졌습니다.' : '방장이 전투를 종료했습니다.'}</p></div>{/if}
      <div class="battle-round-bar"><strong>ROUND {round}</strong><span>{room.status === 'active' ? '플레이어 턴' : '전투 결과'}</span><p>{room.status === 'active' ? `턴 종료 ${players.filter(p => p.hp > 0 && p.ended).length}/${players.filter(p => p.hp > 0).length} · 모두 종료하면 적이 행동합니다` : '최종 전투 상태'}</p></div>
      <section class="battle-arena" aria-label="전장">
        <div class="battle-field-label"><span>ENEMIES <b>{enemies.filter(e => e.hp > 0).length}</b></span><small>다음 행동 예고 · 좌우로 넘겨 확인</small></div>
        <div class="battle-enemies">
          {#each enemies as enemy, i (enemy.id)}
            {@const intent = enemyIntent(enemy, i, round, allies)}
            <button class="battle-unit battle-enemy" class:fallen={enemy.hp <= 0} class:targeted={selectedTarget === enemy.id && selectedSide === 'enemies'} disabled={!canAct || busy || selectedSide !== 'enemies' || enemy.hp <= 0} on:click={() => selectedTarget = enemy.id} aria-pressed={selectedTarget === enemy.id && selectedSide === 'enemies'}>
              <span class="battle-intent" class:guarding={intent.label === '방어'}>{enemy.hp <= 0 ? '처치됨' : `${intent.label === '방어' ? '⬡' : '⚔'} ${intent.label} ${intent.amount ?? ''}`}</span>
              <span class="battle-intent-target">{enemy.hp > 0 && intent.target ? `→ ${intent.target}` : '　'}</span>
              <span class="battle-enemy-symbol" aria-hidden="true"><svg viewBox="0 0 100 90" fill="none"><ellipse cx="50" cy="82" rx="35" ry="6" fill="currentColor" opacity=".15"/>{#if i % 3 === 0}<path d="M25 72 30 36 20 16 40 25 50 12 60 25 80 16 70 36 75 72 50 82Z" fill="currentColor" opacity=".7"/><path d="m34 41 10 4m12 0 10-4M42 62l8 5 8-5" stroke="#ffe4b2" stroke-width="4"/>{:else if i % 3 === 1}<path d="M15 77 25 48 36 23 50 10 64 23 75 48 85 77 62 72 50 81 38 72Z" fill="currentColor" opacity=".65"/><path d="m33 43 17-15 17 15-6 20H39Z" fill="#181923"/><path d="M39 47h7m8 0h7" stroke="#ffe4b2" stroke-width="4"/>{:else}<path d="m20 75 7-35 12-7 3-18h16l3 18 12 7 7 35-30 8Z" fill="currentColor" opacity=".7"/><path d="m32 44 18-8 18 8-4 19-14 8-14-8Z" stroke="#ffe4b2" stroke-width="3"/><path d="M43 49h14" stroke="#ffe4b2" stroke-width="4"/>{/if}</svg></span>
              <strong>{enemy.name}</strong><div class="battle-health"><span style={`width:${enemy.hp / enemy.max_hp * 100}%`}></span></div><span class="battle-vitals">{enemy.hp}/{enemy.max_hp} <b>⬡ {enemy.block}</b></span>
              <span class="battle-statuses">{#each activeStatuses(enemy) as [key, label]}<small>{label} {enemy[key]}</small>{/each}</span>
            </button>
          {/each}
        </div>
        <p class="battle-target-hint" role="status">{room.status !== 'active' ? '최종 전장 상태입니다.' : !me ? '전투 진행 상황을 관전하고 있습니다.' : selectedSide === 'enemies' ? '⌖ 효과를 적용할 적을 선택하세요' : selectedSide === 'players' ? '⌖ 효과를 적용할 아군을 선택하세요' : '카드를 선택하고 대상을 지정하세요'}</p>
        <div class="battle-party">{#each displayPlayers as player, playerIndex (player.id)}
          <div class="battle-party-wrap"><button class="battle-unit battle-player" class:fallen={player.hp <= 0} class:targeted={selectedTarget === player.id && selectedSide === 'players'} class:mine={player.owner_id === user.id} disabled={!canAct || busy || selectedSide !== 'players' || player.hp <= 0} aria-pressed={selectedTarget === player.id && selectedSide === 'players'} on:click={() => selectedTarget = player.id}>
            <span class="battle-player-identity"><span class="battle-avatar">{#if player.avatar_url}<img src={player.avatar_url} alt="" />{:else}{player.name.slice(0,1)}{/if}</span><strong>플레이어 {playerIndex+1} · {player.name}{player.owner_id === user.id ? ' (나)' : ''}</strong><span class="battle-tag">{player.hp <= 0 ? '쓰러짐' : room.status !== 'active' ? '종료' : player.ended ? '턴 종료' : '행동 중'}</span></span><div class="battle-health"><span style={`width:${player.hp / player.max_hp * 100}%`}></span></div><span class="battle-vitals">HP {player.hp}/{player.max_hp} <b>⬡ {player.block}</b></span><span class="battle-player-resources">에너지 {player.energy} · 손패 {player.hand.length}{#if player.personal_config?.name}<span class="personal-resource"> · {resourceName(player)} {player.personal_energy}/{player.personal_config.max}</span>{/if}</span><span class="battle-statuses">{#each activeStatuses(player) as [key, label]}<small>{label} {player[key]}</small>{/each}</span>
          </button>{#if host && room.status === 'active' && !player.ended && player.hp > 0}<button class="battle-force" disabled={busy} on:click={() => act('force_end', { player_id: player.id })}>{player.name} 턴 대신 종료</button>{/if}</div>
        {/each}</div>
      </section>
      <BattleExtras state={room.state} {host} active={room.status==='active'} {busy} {canAct} {selectedSide} {selectedTarget} onTarget={id=>selectedTarget=id} onAct={act} />
      {#if me}<section class="battle-hand-section">
        <div class="battle-section-head"><h2>내 손패 <span>{me.hand.length}/10</span></h2><div class="battle-actions"><span class="battle-energy">에너지 <b>{me.energy}</b></span>{#if me.personal_config?.name}<span class="battle-energy personal-resource">{resourceName(me)} <b>{me.personal_energy}/{me.personal_config.max}</b></span>{/if}<button class="primary-btn" disabled={busy || !canAct} on:click={() => act('end')}>{room.status !== 'active' ? '전투 종료' : me.hp <= 0 ? '전투 불능' : me.ended ? '다른 플레이어를 기다리는 중' : '턴 종료 →'}</button></div></div>
        <div class="battle-hand">{#each me.hand as card (card.instance_id)}
          {@const rule = rules[card.id]}
          <button class="battle-card" data-type={card.card_type || '스킬'} class:selected={selectedCardId === card.instance_id} class:unaffordable={!canPayCard(me,card,rule)} disabled={busy || !canAct} on:click={() => chooseCard(card)} aria-pressed={selectedCardId === card.instance_id}>
            <span class="battle-card-top"><span>{card.card_type || '스킬'} · {card.grade || '기본'}</span><b>{cardCost(card)}</b></span><strong>{card.card_name}</strong><span class="battle-card-sigil" aria-hidden="true">{card.card_type === '공격' ? '⚔' : card.card_type === '파워' ? '✦' : '⬡'}</span>{#if personalCost(rule)}<small>{resourceName(me)} {personalCost(rule)} 소모</small>{/if}<span class="battle-card-effects">{#each (rule?.effects || []).slice(0, 2) as effect}<span>{effectText(effect)}</span>{:else}<span>사용 효과 없음</span>{/each}{#if rule?.effects?.length > 2}<small>외 {rule.effects.length - 2}개 효과 · 선택하여 확인</small>{/if}</span>
            {#if extraCardDraw(card)}<small>사용 후 자신 · 추가 드로우 {extraCardDraw(card)}장</small>{/if}<span class="battle-card-keywords">{card.card_innate ? '선천 · ' : ''}{card.card_retain ? '유지 · ' : ''}{card.card_ethereal ? '에테리얼 · ' : ''}{cardDestination(card, rule)}{!rule?.playable ? ' · 사용 불가' : ''}</span>{#each rule?.on_exhaust || [] as effect}<small>소멸 시 발동: {effectText(effect)}</small>{/each}{#each rule?.on_turn_end || [] as effect}<small>손에 남으면 턴 종료: {effectText(effect)}</small>{/each}
          </button>
        {:else}<p class="battle-muted">손패가 비었습니다. 턴을 종료하면 다음 턴에 카드를 뽑습니다.</p>{/each}</div>
        {#if selectedCard && canAct}<details class="battle-card-detail"><summary>{selectedCard.card_name} · 전체 효과 / 설명</summary><p>{selectedCard.card_effect || '설명 없음'}</p>{#each selectedRule?.effects || [] as effect}<p>{effectText(effect)}</p>{/each}</details><div class="battle-play-bar"><div><strong>{selectedCard.card_name}</strong><p>{!selectedRule?.playable ? '사용할 수 없는 카드입니다.' : !canPayCard(me,selectedCard,selectedRule) ? '카드 사용에 필요한 에너지가 부족합니다.' : selectedSide ? (targetValid ? `대상: ${selectableTargets.find((p) => p.id === selectedTarget)?.name}` : '대상을 선택하세요.') : '지정된 대상에게 효과 적용'}</p></div>{#if selectedSide}<label class="battle-quick-target"><span>카드 대상</span><select bind:value={selectedTarget}><option value="">대상 선택</option>{#each selectableTargets.filter((p) => p.hp > 0) as unit}<option value={unit.id}>{unit.name} · HP {unit.hp}</option>{/each}</select></label>{/if}<button class="primary-btn" disabled={busy || !selectedRule?.playable || !targetValid || !canPayCard(me,selectedCard,selectedRule)} on:click={playSelected}>사용 · {cardCost(selectedCard)} 에너지{personalCost(selectedRule) ? ` + ${resourceName(me)} ${personalCost(selectedRule)}` : ''}</button><button class="subtle-btn" on:click={() => selectedCardId = ''}>취소</button></div>{/if}
        <div class="battle-piles">{#each [['draw','뽑기 더미'],['discard','버림 더미'],['exhaust','소멸 더미'],['powers','사용한 파워']] as [key,label]}<details><summary>{label} <b>{(me[key] || []).length}</b></summary><p>{(me[key] || []).map((c) => c.card_name).sort().join(' · ') || '비어 있음'}</p></details>{/each}</div>
      </section><details class="battle-inventory"><summary>⚗ 소비 아이템 <b>{(me.consumables || []).filter(Boolean).length}/3</b><span>펼쳐서 사용</span></summary><BattleConsumables player={me} players={allies} {enemies} {busy} {canAct} onAct={act} /></details>{:else}<p class="battle-muted">{host ? '방장으로 전투를 관전하고 있습니다.' : '전투를 관전하고 있습니다. 전투 행동은 참가자만 할 수 있습니다.'}</p>{/if}
    {/if}
    {#if room?.status==='waiting'}<BattleExtras state={room.state} />{/if}
    {#if room}<details class="battle-log"><summary>전투 기록 <span>최근 100개</span></summary><ol>{#each [...room.state.log].reverse() as line}<li>{line}</li>{:else}<li>전투 준비를 시작하세요.</li>{/each}</ol></details>
      {#if host && ['waiting','active'].includes(room.status)}<div class="battle-close">{#if confirmClose}<span>참가자 모두의 전투를 종료할까요?</span><button class="subtle-btn" disabled={busy} on:click={async () => { if (await act('close')) confirmClose = false; }}>전투 종료 확인</button><button class="subtle-btn" disabled={busy} on:click={() => confirmClose = false}>취소</button>{:else}<button class="subtle-btn" on:click={() => confirmClose = true}>방 종료</button>{/if}</div>{/if}
    {/if}
    <footer class="battle-connection" role="status"><span>{syncError ? '연결 확인 필요' : connection}</span>{#if lastSync}<span>마지막 확인 {lastSync}</span>{/if}{#if busy}<span>행동 처리 중…</span>{/if}</footer>
  {/if}
  <details class="battle-guide"><summary>전투 규칙 보기</summary><p>매 턴 에너지 3과 카드 5장을 받습니다. 손패는 최대 10장입니다. 뽑기 더미가 비면 버림 더미를 섞습니다. 선천 카드는 첫 손패에 우선 배치되며 5장보다 많으면 최대 10장까지 첫 손패를 늘립니다.</p><p>턴이 끝나면 에테리얼 카드는 소멸하고, 유지 카드를 제외한 손패를 버립니다. 방어도는 자기 진영의 다음 턴 시작에 사라집니다. 파워 카드는 사용 후 파워 영역으로 이동하며 소멸 시 발동 효과를 실행하지 않습니다. 사용 후 소멸을 직접 켠 카드는 소멸을 우선합니다.</p><p>힘은 공격 피해를 늘리고 약화는 공격을 25% 낮춥니다. 취약은 받는 공격을 50% 늘립니다(소수점 버림). 중독은 자기 진영 턴 시작에 방어를 무시하는 피해를 주고 1 감소합니다. 약화·취약은 자기 턴 종료 시 1 감소합니다.</p><p>회복은 생존자에게만 적용됩니다. 쓰러진 플레이어의 턴은 건너뜁니다. 중독·소멸 효과를 포함한 행동 처리가 끝나면 승패를 판정합니다. 동시 전멸은 승리로 처리합니다. 종료 시 소멸 효과로 뽑은 카드는 다음 턴까지 남습니다.</p><p>사용 효과 다음에 카드의 추가 드로우 개수만큼 자신이 뽑습니다. 효과에 넣은 드로우와 합산되며 손패는 최대 10장입니다. 설명문은 자동 해석하지 않습니다. 효과는 방장이 설정한 순서대로 적용합니다. 장비 효과와 캐릭터의 공격·방어 수치는 자동 적용되지 않습니다. 필요한 효과는 카드의 힘·방어도 등으로 설정하세요. 전투는 보유 덱의 복사본을 사용하며 원본 HP와 카드 수량은 바뀌지 않습니다.</p></details>
</section>

<style>
  .battle-monster-picker { display:flex; flex-wrap:wrap; gap:10px; align-items:end; margin-bottom:18px; }
  .battle-monster-picker label { flex:1; min-width:160px; }
  .personal-resource {color:#d9c0fa;}
  .battle-room-actions {display:flex;align-items:center;justify-content:flex-end;gap:8px;flex-wrap:wrap;}
  .battle-page .danger-btn {display:inline-flex;align-items:center;justify-content:center;min-height:42px;margin:0;padding:9px 13px;font-size:14px;text-decoration:none;}
  @media(max-width:560px){.battle-room-actions{width:100%}.battle-room-actions>a,.battle-room-actions>button{flex:1}}
  .battle-page{padding:clamp(18px,3vw,36px);font-size:16px;color:#eceef4;min-width:0}.battle-page h1,.battle-page h2,.battle-page h3,.battle-page p{margin:0}.battle-page h1{font-size:clamp(26px,3vw,38px);overflow-wrap:anywhere}.battle-page h2{font-size:20px}.battle-page h3{font-size:20px;margin-bottom:12px}.battle-page .eyebrow{margin-bottom:8px}.battle-heading{display:flex;justify-content:space-between;gap:20px;align-items:center;margin-bottom:28px}.battle-heading p:not(.eyebrow){color:#a8b3c5;margin-top:8px}.battle-actions{display:flex;align-items:center;flex-wrap:wrap;gap:10px}.battle-page .primary-btn,.battle-page .subtle-btn{display:inline-flex;align-items:center;justify-content:center;gap:12px;font-size:14px;min-height:42px;white-space:normal;text-decoration:none}.battle-page button:disabled{cursor:default;opacity:.48}.battle-page button:focus-visible,.battle-page a:focus-visible,.battle-page summary:focus-visible{outline:2px solid #ead08e;outline-offset:4px}.battle-empty{text-align:center;padding:48px 16px;display:grid;justify-items:center;gap:16px;border:1px dashed #364153;border-radius:16px}.battle-emblem{font-size:42px;color:#d8bd75}.battle-empty p,.battle-muted{color:#a8b3c5;line-height:1.8}.battle-alert{display:flex;justify-content:space-between;gap:12px;padding:15px 18px;border:1px solid #bc6d6d;background:#3c2026;border-radius:10px;margin-bottom:18px;overflow-wrap:anywhere}.battle-alert button{background:none;color:inherit;border:0;font-size:24px}.battle-create{display:flex;align-items:end;gap:16px;padding:22px;background:#182230;border:1px solid #374257;border-radius:14px;margin-bottom:24px}.battle-create label{flex:1}.battle-page label{display:grid;gap:6px;color:#bec9d8;font-size:14px}.battle-page input:not([type=checkbox]),.battle-page select{width:100%;min-width:0;min-height:42px;border:1px solid #47536a;background:#0e1724;color:#f3f4f7;border-radius:7px;padding:9px 11px;font:inherit}.battle-page input:focus,.battle-page select:focus{outline:2px solid #d8bd75;outline-offset:1px}.battle-room-list{display:grid;gap:12px}.battle-room-row{display:flex;gap:20px;align-items:center;padding:20px;border:1px solid #344155;border-radius:12px;background:#111d2b}.battle-room-row>div{flex:1;min-width:0}.battle-room-row h2{margin:6px 0;overflow-wrap:anywhere}.battle-room-row p{color:#a8b3c5;font-size:14px}.battle-room-icon{font-size:32px;color:#d8bd75}.battle-tag{display:inline-block;font-size:13px;color:#bdcbe0;background:#223149;padding:4px 8px;border-radius:6px;white-space:nowrap}.battle-tag.ready{background:#173b35;color:#98e4c0}.battle-setup-grid{display:grid;grid-template-columns:1fr 1.2fr;gap:18px}.battle-box{padding:22px;border:1px solid #354256;background:#111c2a;border-radius:14px;min-width:0}.battle-section-head{display:flex;align-items:center;justify-content:space-between;gap:14px;margin-bottom:18px;flex-wrap:wrap}.battle-section-head h2 span{color:#b4bed0;font-size:15px;margin-left:8px}.battle-member{display:flex;align-items:center;gap:12px;margin-bottom:18px}.battle-member>div{flex:1;min-width:0;overflow-wrap:anywhere}.battle-member small{display:block;font-size:14px;color:#a8b3c5;margin-top:4px}.battle-avatar{width:44px;height:44px;flex:none;display:grid;place-items:center;background:#24354b;border:1px solid #617089;border-radius:12px;font-size:22px;color:#eed59e;overflow:hidden}.battle-avatar img{width:100%;height:100%;object-fit:cover}.battle-help{font-size:14px;color:#a8b3c5;line-height:1.7;margin-top:16px!important}.battle-enemy-editor{display:grid;grid-template-columns:1.5fr 1fr 1fr 1fr 28px;gap:8px;align-items:end;margin-bottom:12px}.battle-icon-btn{border:0;background:none;color:#d8a6a6;min-height:40px;font-size:24px}.battle-rules{margin-top:18px}.battle-rule-layout{display:grid;grid-template-columns:minmax(180px,1fr) minmax(0,2fr);gap:22px;margin-top:20px}.battle-rule-list{display:flex;flex-direction:column;gap:8px;max-height:560px;overflow:auto}.battle-rule-item{display:flex;justify-content:space-between;align-items:center;gap:12px;text-align:left;border:1px solid #38465b;background:#142234;color:#edf0f7;border-radius:8px;padding:12px;font-size:15px}.battle-rule-item.chosen{border-color:#d8bd75;background:#30302a}.battle-rule-item span{overflow-wrap:anywhere}.battle-rule-item small{display:block;color:#acb8cb;font-size:13px;margin-top:4px}.battle-rule-item b{color:#d8bd75;font-size:13px;white-space:nowrap}.battle-rule-detail{padding:20px;background:#0d1622;border:1px solid #303f53;border-radius:10px;min-width:0}.battle-rule-detail blockquote{margin:0;border-left:2px solid #d8bd75;padding-left:12px;color:#c4cedc;white-space:pre-wrap;overflow-wrap:anywhere}.battle-rule-detail form{margin-top:18px}.battle-start-bar,.battle-play-bar{display:flex;align-items:center;gap:18px;justify-content:space-between;background:#282921;border:1px solid #766b47;padding:20px;border-radius:12px;margin-top:20px}.battle-start-bar p,.battle-play-bar p{color:#c8c7b6;margin-top:5px;font-size:14px}.battle-start-bar>div,.battle-play-bar>div{flex:1}.battle-round-bar{display:flex;gap:18px;align-items:center;padding:14px 0;margin-bottom:18px;border-bottom:1px solid #39475c}.battle-round-bar strong{font-family:'DM Mono',monospace;color:#dfc786}.battle-round-bar p{font-size:14px;color:#acb9cc;margin-left:auto}.battle-arena{padding:24px 20px;background:radial-gradient(ellipse at 50% 0%,#302438 0%,#14202e 60%,#101b28 100%);border:1px solid #46526a;border-radius:16px}.battle-enemies{display:flex;justify-content:center;gap:18px;flex-wrap:wrap}.battle-unit{display:flex;flex-direction:column;align-items:center;gap:8px;color:#f0f1f7;background:#1b2637;border:1px solid #536075;border-radius:12px;padding:18px;text-align:center;min-width:0}.battle-unit:disabled{opacity:1!important}.battle-unit:not(:disabled):hover{border-color:#ffe0a0}.battle-unit.targeted{outline:3px solid #e8c983;outline-offset:3px;background:#35352a}.battle-unit.fallen{opacity:.48!important;filter:grayscale(1)}.battle-unit strong{font-size:18px;overflow-wrap:anywhere}.battle-unit>span:not(.battle-avatar):not(.battle-intent):not(.battle-enemy-symbol){font-size:14px}.battle-unit small{font-size:13px;color:#aebcd1}.battle-enemy{flex:0 1 250px;background:#251f30;border-color:#70576b}.battle-intent{font-size:14px;color:#f3b4a6;background:#432a34;border-radius:8px;padding:6px 10px;min-height:32px}.battle-enemy-symbol{font-size:64px;line-height:1.25;color:#d4a4ac}.battle-health{width:100%;height:8px;border-radius:10px;overflow:hidden;background:#0b111a;margin-top:4px}.battle-health>span{display:block;height:100%;background:#d7797d;transition:width .25s}.battle-target-hint{text-align:center;padding:22px 0;color:#dbcca3;font-size:15px}.battle-party{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:14px}.battle-party-wrap{min-width:0}.battle-player{width:100%;height:100%;height:auto}.battle-player.mine{border-color:#d8bd75}.battle-player .battle-health>span{background:#71b3b3}.battle-force{width:100%;border:0;background:transparent;color:#c3ad85;font-size:13px;padding:10px 4px}.battle-hand-section{margin-top:28px}.battle-energy{color:#e6ce90;font-size:15px}.battle-energy b{font-family:'DM Mono',monospace;font-size:24px;margin-left:4px}.battle-hand{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px}.battle-card{display:flex;flex-direction:column;gap:14px;text-align:left;min-height:270px;padding:16px;color:#f4f0e5;background:linear-gradient(155deg,#334252,#182331);border:1px solid #697788;border-radius:14px 14px 9px 9px;transition:transform .15s,border-color .15s;min-width:0}.battle-card:not(:disabled):hover{transform:translateY(-4px);border-color:#eed08c}.battle-card.selected{outline:2px solid #e8c983;outline-offset:2px;transform:translateY(-5px)}.battle-card.unaffordable{opacity:.5}.battle-card-top{display:flex;align-items:center;justify-content:space-between;gap:6px;font-size:13px;color:#bac7d7}.battle-card-top b{display:grid;place-items:center;flex:none;width:32px;height:32px;border:1px solid #d8bd75;border-radius:50%;background:#49432d;color:#ffe3a4;font-size:18px}.battle-card>strong{font-size:20px;overflow-wrap:anywhere}.battle-card-effects{display:grid;gap:5px;font-size:15px;color:#ffe2a0}.battle-card-keywords{margin-top:auto;font-size:13px;color:#d1c29d}.battle-card small{font-size:13px;color:#c3aed4}.battle-piles{display:flex;gap:12px;margin-top:18px;flex-wrap:wrap}.battle-piles details{flex:1;min-width:150px;padding:12px;background:#182536;border:1px solid #3c4e63;border-radius:8px;font-size:14px}.battle-piles p{margin-top:10px;overflow-wrap:anywhere}.battle-page summary{cursor:pointer}.battle-piles b{float:right;color:#e6ce90}.battle-result{text-align:center;padding:28px;background:#2e2429;border:1px solid #755256;border-radius:14px;margin-bottom:22px}.battle-result[data-status=victory]{background:#2e3022;border-color:#ad9a59}.battle-result>span{font-size:36px;color:#e5cc8c}.battle-result h2{font-size:30px;margin:8px 0}.battle-log{margin-top:22px;padding:18px;border:1px solid #344259;border-radius:10px;background:#101a27}.battle-log summary{font-size:16px}.battle-log summary span{color:#a8b3c5;font-size:13px;margin-left:8px}.battle-log ol{list-style:none;max-height:220px;overflow:auto;margin:16px 0 0;padding:0}.battle-log li{font-size:14px;color:#b9c6d7;line-height:1.8;border-bottom:1px solid #202d40;padding:6px}.battle-close{display:flex;justify-content:flex-end;align-items:center;gap:10px;margin-top:18px;flex-wrap:wrap}.battle-connection{display:flex;gap:16px;flex-wrap:wrap;color:#aab8cc;font-size:13px;padding-top:20px}.battle-guide{margin-top:24px;border-top:1px solid #344259;padding-top:18px;color:#bdc7d5;font-size:14px}.battle-guide p{margin-top:12px;line-height:1.8}
  @media(max-width:950px){.battle-setup-grid{grid-template-columns:1fr}.battle-rule-layout{grid-template-columns:1fr}.battle-rule-list{max-height:240px}.battle-round-bar{flex-wrap:wrap}.battle-round-bar p{width:100%;margin:0}.battle-hand{grid-template-columns:repeat(auto-fit,minmax(170px,1fr))}.battle-heading{align-items:flex-start;flex-direction:column}}
  @media(max-width:560px){.battle-create{align-items:stretch;flex-direction:column;padding:16px}.battle-room-row{gap:12px;flex-wrap:wrap}.battle-box{padding:16px}.battle-enemy-editor{grid-template-columns:repeat(3,1fr) 28px}.battle-enemy-editor>label:first-child{grid-column:1/-1}.battle-rule-detail{padding:14px}.battle-start-bar,.battle-play-bar{flex-wrap:wrap}.battle-play-bar>div{flex-basis:100%}.battle-enemy{flex-basis:100%}.battle-arena{padding:16px 12px}.battle-party{grid-template-columns:1fr}.battle-hand{grid-template-columns:1fr 1fr;gap:10px}.battle-card{padding:12px;min-height:250px}.battle-card>strong{font-size:18px}.battle-card-top{flex-wrap:wrap}.battle-member{flex-wrap:wrap}.battle-heading .battle-actions{gap:8px}}
  .battle-page{backdrop-filter:none;background:#0d131d}.battle-quick-target{min-width:180px}.battle-play-bar{position:fixed;left:50%;transform:translateX(-50%);width:min(1100px,calc(100vw - 36px));bottom:12px;z-index:30;box-shadow:0 10px 30px #0008}.battle-hand-section:has(.battle-play-bar){padding-bottom:180px}
  @media(min-width:951px){.battle-arena{padding:16px}.battle-unit{gap:5px;padding:12px}.battle-enemy-symbol{font-size:42px}.battle-target-hint{padding:12px 0}.battle-player .battle-avatar{width:32px;height:32px;font-size:18px}.battle-heading{margin-bottom:18px}.battle-round-bar{margin-bottom:12px}.battle-hand-section{margin-top:20px}}
  @media(max-width:560px){.battle-quick-target{width:100%}.battle-play-bar{bottom:6px;padding:14px;gap:10px}.battle-hand-section:has(.battle-play-bar){padding-bottom:280px}}
  @media(prefers-reduced-motion:reduce){.battle-card,.battle-health>span{transition:none}.battle-card:not(:disabled):hover,.battle-card.selected{transform:none}}

  /* The battlefield and hand each stay in a single horizontal lane. */
  .in-battle { padding:24px; border-color:#62543d; border-radius:18px; background:radial-gradient(ellipse at 50% 0%,#29233366,transparent 55%),#11151b; }
  .in-battle .battle-heading { margin-bottom:12px; gap:12px; }
  .in-battle .battle-heading h1 { font-size:24px; color:#f0dfb8; }
  .in-battle .battle-heading .eyebrow { font-size:9px; color:#b8a479; margin-bottom:4px; }
  .in-battle .battle-heading p:not(.eyebrow) { margin-top:3px; font-size:12px; }
  .in-battle .primary-btn { border:1px solid #e0bb6e; border-radius:7px; color:#fff0c8; background:linear-gradient(#806236,#4e3826); box-shadow:inset 0 1px #ffe5a54d,0 3px 0 #211c18; }
  .in-battle .subtle-btn { border-color:#675b48; color:#d1c4aa; background:#201f20; }
  .battle-round-bar { gap:12px; margin-bottom:0; padding:10px 0; border-color:#695a3b66; font-size:12px; }
  .battle-round-bar strong { font-size:13px; letter-spacing:.08em; }
  .battle-round-bar > span { color:#a4d1bf; }
  .battle-round-bar p { font-size:12px; }
  .battle-arena { position:relative; padding:14px 18px 12px; border-color:#72604466; border-radius:12px 12px 0 0; background:radial-gradient(ellipse at 50% 15%,#64504455,transparent 65%),repeating-linear-gradient(90deg,transparent 0 110px,#0e131b66 110px 124px),linear-gradient(#242431,#141d28 76%,#323034 77%,#171c25); }
  .battle-field-label { display:flex; justify-content:space-between; align-items:center; gap:8px; margin-bottom:4px; color:#c7b38d; }
  .battle-field-label > span { font:10px 'DM Mono',monospace; letter-spacing:.15em; }
  .battle-field-label b { margin-left:6px; color:#e8c492; }
  .battle-field-label small { font-size:11px; color:#afa79b; }
  .battle-enemies { flex-wrap:nowrap; justify-content:safe center; gap:14px; overflow-x:auto; padding:8px 5px 10px; scroll-snap-type:x proximity; }
  .battle-enemy { position:relative; flex:0 0 154px; gap:3px; padding:8px 10px; border:1px solid transparent; border-radius:10px; background:transparent; scroll-snap-align:center; }
  .battle-enemy:not(:disabled) { border-color:#a68b5766; background:#d8bd7509; cursor:crosshair; }
  .battle-unit.targeted { outline:2px solid #f5d77e; outline-offset:1px; background:#e8c98315; box-shadow:0 0 20px #e8c98322; }
  .battle-enemy-symbol { display:block; width:88px; height:70px; color:#be8995; filter:drop-shadow(0 6px 8px #0008); }
  .battle-enemy:nth-child(3n+2) .battle-enemy-symbol { color:#a89bc6; }
  .battle-enemy:nth-child(3n+3) .battle-enemy-symbol { color:#b8a079; }
  .battle-enemy-symbol svg { width:100%; height:100%; }
  .battle-intent { min-height:0; padding:3px 9px; border:1px solid #aa615866; border-radius:20px; background:#44272c; color:#ffd1b9; font-size:12px; font-weight:700; }
  .battle-intent.guarding { color:#b7e4ee; border-color:#69aaba77; background:#233b48; }
  .battle-unit > .battle-intent-target { max-width:100%; font-size:10px!important; line-height:1.35; color:#d5b4ad; overflow-wrap:anywhere; }
  .battle-unit strong { font-size:14px; line-height:1.35; }
  .battle-health { height:7px; margin-top:4px; border:1px solid #080c12; background:#080c12; box-shadow:0 1px #ffffff16; }
  .battle-health > span { background:linear-gradient(90deg,#943e49,#e2847a); }
  .battle-unit > .battle-vitals { display:flex; width:100%; align-items:center; justify-content:space-between; gap:6px; color:#ebd9cf; font-size:11px!important; font-variant-numeric:tabular-nums; }
  .battle-vitals b { color:#a9d5e5; font-weight:500; }
  .battle-unit > .battle-statuses { display:flex; flex-wrap:wrap; gap:3px; justify-content:center; }
  .battle-statuses:empty { display:none; }
  .battle-statuses small { padding:1px 4px; border-radius:3px; background:#101620; color:#d3c2e1; font-size:10px; }
  .battle-target-hint { padding:7px 0; color:#d5c59e; font-size:12px; border-top:1px solid #b8a47922; }
  .battle-party { display:flex; gap:8px; overflow-x:auto; padding:4px 3px; scroll-snap-type:x proximity; }
  .battle-party-wrap { flex:1 0 192px; max-width:260px; scroll-snap-align:start; }
  .battle-player { gap:4px; padding:10px; border-color:#77766d55; border-radius:8px; background:#151d26d9; }
  .battle-player.mine { border-color:#b6a066; background:linear-gradient(125deg,#49402a55,#151d26); }
  .battle-player-identity { display:flex; align-items:center; width:100%; gap:7px; text-align:left; }
  .battle-player-identity strong { flex:1; font-size:12px; }
  .battle-player .battle-avatar { width:26px; height:26px; border-radius:6px; font-size:13px; }
  .battle-player .battle-tag { padding:2px 5px; background:#31413e; color:#bbd6c4; font-size:10px; }
  .battle-unit > .battle-player-resources { align-self:flex-start; text-align:left; color:#b6bbc4; font-size:10px!important; }
  .battle-force { padding:6px 2px; font-size:11px; min-height:32px; }
  .battle-hand-section { margin-top:0; padding:14px 14px 12px; border:1px solid #72604466; border-top:0; border-radius:0 0 12px 12px; background:radial-gradient(ellipse at 50% 100%,#66513833,transparent 70%),#131a22; }
  .battle-hand-section .battle-section-head { margin-bottom:5px; gap:8px; }
  .battle-hand-section h2 { font-size:15px; }
  .battle-hand-section h2 span { font-size:12px; }
  .battle-hand-section .battle-actions { gap:10px; }
  .battle-hand-section .battle-energy { display:flex; align-items:center; gap:4px; font-size:11px; }
  .battle-energy:not(.personal-resource) b { display:grid; place-items:center; width:36px; height:36px; margin:0; border-radius:50%; border:2px solid #e1c36d; background:radial-gradient(circle at 35% 28%,#d4b35f,#5c4524 70%); color:#fff5d6; font-size:20px; box-shadow:0 0 13px #ebc77933,inset 0 0 0 2px #302c25; }
  .battle-energy.personal-resource b { font-size:15px; }
  .battle-hand { display:flex; gap:12px; overflow-x:auto; align-items:stretch; padding:12px 5px 10px; scroll-snap-type:x proximity; }
  .battle-card { --card-accent:#8caab8; position:relative; flex:0 0 174px; min-height:240px; gap:8px; padding:12px; border:2px solid var(--card-accent); border-radius:12px 12px 8px 8px; background:linear-gradient(155deg,#334956,#17212d 70%); box-shadow:inset 0 0 0 3px #111b2566,0 5px 10px #0006; scroll-snap-align:center; }
  .battle-card[data-type='공격'] { --card-accent:#c18b7a; background:linear-gradient(155deg,#623e3b,#2b2028 70%); }
  .battle-card[data-type='파워'] { --card-accent:#bca1d3; background:linear-gradient(155deg,#544567,#282335 70%); }
  .battle-card-top { flex-wrap:nowrap; font-size:10px; color:#e1d4c2; }
  .battle-card-top b { width:28px; height:28px; font-size:16px; box-shadow:0 2px 4px #0007; }
  .battle-card > strong { font-size:16px; text-align:center; color:#fff0d3; }
  .battle-card-sigil { display:grid; place-items:center; height:43px; border-block:1px solid #efdfb31c; color:var(--card-accent); background:radial-gradient(ellipse,#ffffff0d,transparent 75%); font-size:30px; }
  .battle-card-effects { gap:3px; font-size:12px; line-height:1.5; color:#f1dfb8; overflow-wrap:anywhere; }
  .battle-card small,.battle-card-keywords { font-size:10px; line-height:1.4; overflow-wrap:anywhere; }
  .battle-card.selected { border-color:#ffe19c; outline-color:#ffe19c; box-shadow:0 0 22px #e8c98333; }
  .battle-card.unaffordable { opacity:.65; }
  .battle-card-detail { margin:6px 0; padding:10px; border:1px solid #72604466; border-radius:6px; color:#dacdaf; font-size:12px; }
  .battle-card-detail p { margin-top:8px; white-space:pre-wrap; overflow-wrap:anywhere; }
  .battle-piles { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:6px; margin-top:8px; }
  .battle-piles details { min-width:0; padding:8px; border-color:#675b484d; background:#191e25; font-size:11px; }
  .battle-inventory { margin-top:12px; border:1px solid #52635e77; border-radius:8px; background:#17211f66; }
  .battle-inventory > summary { padding:12px; color:#c9d4bc; font-size:13px; }
  .battle-inventory summary b { margin-left:6px; color:#dfc98d; }
  .battle-inventory summary > span { float:right; color:#acb6a6; font-size:11px; }
  .in-battle .battle-log { margin-top:10px; padding:12px; }
  .in-battle .battle-log summary { font-size:13px; }
  .in-battle .battle-connection { padding-top:12px; font-size:11px; }
  .in-battle .battle-guide { margin-top:12px; padding-top:12px; font-size:12px; }
  .battle-play-bar { gap:12px; padding:12px 16px; border-color:#b99b5e; background:#23251ff5; bottom:max(12px,env(safe-area-inset-bottom)); }
  .battle-play-bar > div { min-width:0; }
  .battle-play-bar strong { font-size:14px; overflow-wrap:anywhere; }
  .battle-play-bar p { font-size:12px; }
  .battle-quick-target { min-width:140px; }
  .battle-quick-target > span { position:absolute; width:1px; height:1px; overflow:hidden; clip-path:inset(50%); }
  .in-battle:has(.battle-play-bar) { padding-bottom:150px; }
  .battle-hand-section:has(.battle-play-bar) { padding-bottom:12px; }
  @media(max-width:950px) {
    .in-battle .battle-heading { flex-direction:row; }
    .in-battle .battle-heading > .battle-actions { justify-content:flex-end; gap:5px; max-width:50%; }
    .in-battle .battle-heading .subtle-btn { min-height:34px; padding:6px 8px; font-size:11px; }
    .battle-round-bar p { width:auto; margin-left:auto; }
  }
  @media(max-width:600px) {
    .in-battle { padding:12px 10px; border-radius:12px; }
    .in-battle .battle-heading h1 { font-size:18px; }
    .in-battle .battle-heading .eyebrow { font-size:8px; letter-spacing:.1em; }
    .in-battle .battle-heading p:not(.eyebrow) { font-size:10px; }
    .battle-round-bar { gap:8px; padding:8px 0; }
    .battle-round-bar p { flex-basis:100%; margin:0; font-size:10px; }
    .battle-arena { padding:8px 6px; }
    .battle-field-label { padding:0 3px; }
    .battle-field-label small { font-size:9px; }
    .battle-enemies { gap:6px; padding:5px 3px 8px; }
    .battle-enemy { flex-basis:112px; padding:6px; gap:2px; }
    .battle-enemy-symbol { width:62px; height:46px; }
    .battle-enemy strong { font-size:12px; }
    .battle-intent { padding:2px 7px; font-size:11px; }
    .battle-enemy .battle-vitals { font-size:10px!important; }
    .battle-target-hint { font-size:11px; padding:6px 0; }
    .battle-party-wrap { flex:1 0 172px; }
    .battle-player { padding:7px; gap:3px; }
    .battle-player .battle-avatar { width:23px; height:23px; }
    .battle-player-identity { gap:5px; }
    .battle-player-identity strong { font-size:11px; }
    .battle-player .battle-tag { font-size:9px; }
    .battle-hand-section { padding:8px 6px; }
    .battle-hand-section .battle-section-head { gap:4px; }
    .battle-hand-section h2 { font-size:13px; }
    .battle-hand-section h2 span { margin-left:3px; font-size:10px; }
    .battle-hand-section .battle-actions { gap:6px; }
    .battle-hand-section .battle-actions > .primary-btn { min-height:36px; padding:6px 9px; font-size:12px; max-width:150px; }
    .battle-energy:not(.personal-resource) b { width:30px; height:30px; font-size:18px; }
    .battle-hand { gap:9px; padding:10px 4px; }
    .battle-card { flex-basis:142px; min-height:216px; padding:9px; gap:6px; }
    .battle-card > strong { font-size:14px; }
    .battle-card-sigil { height:34px; font-size:25px; }
    .battle-card-effects { font-size:11px; }
    .battle-piles { grid-template-columns:repeat(2,minmax(0,1fr)); }
    .battle-piles details { padding:7px; }
    .battle-play-bar { display:grid; grid-template-columns:minmax(0,1fr) auto; width:calc(100vw - 20px); gap:8px; padding:10px; bottom:max(6px,env(safe-area-inset-bottom)); }
    .battle-play-bar > div { grid-column:1; }
    .battle-play-bar > .subtle-btn { grid-column:2; grid-row:1; min-height:36px; }
    .battle-quick-target { width:auto; min-width:0; }
    .battle-play-bar .primary-btn { padding:8px 10px; font-size:12px; }
    .in-battle:has(.battle-play-bar) { padding-bottom:210px; }
  }
</style>
