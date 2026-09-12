<script>
  export let authReady = false;
  export let profileLoading = false;
  export let isAdmin = false;
  export let currentRoute = 'admin/combat-test';
  export let adminLoading = false;
  export let adminCharacters = [];
  export let selectedCharacterIds = [];
  export let combatTestPlayers = [];
  export let combatTestLoading = false;
  export let combatTestStarted = false;
  export let combatTestTurn = 0;
  export let toggleCombatTestCharacter = () => {};
  export let startCombatTest = () => {};
  export let nextCombatTestTurn = () => {};
  export let playCombatTestCard = () => {};
  export let copyCombatTestCards = () => {};
  export let copyCombatTestPlayerCards = () => {};
  export let resetCombatTest = () => {};
</script>

{#if !authReady || profileLoading}
  <section class="admin-page panel">
    <div class="empty-state"><span>◌</span><strong>관리자 권한을 확인하는 중이에요</strong></div>
  </section>
{:else if !isAdmin}
  <section class="about-page panel">
    <p class="eyebrow">ACCESS RESTRICTED</p>
    <h1>관리자 권한이<br /><em>필요합니다</em></h1>
    <p class="about-lead">이 페이지는 캠페인 관리자만 이용할 수 있습니다.</p>
    <a class="primary-btn about-button" href="#home">홈으로 돌아가기 <span>→</span></a>
  </section>
{:else}
  <section class="admin-page panel">
    <div class="admin-shell">
      <nav class="admin-sidebar" aria-label="관리자 메뉴">
        <div class="admin-sidebar-brand"><span class="eyebrow">CONTROL ROOM</span><strong>관리자 메뉴</strong></div>
        <a class:active={currentRoute === 'admin'} href="#admin"><span>◌</span><span><strong>플레이어 계정 생성</strong><small>ACCOUNTS &amp; CHARACTERS</small></span></a>
        <a href="#admin/monsters"><span>♟</span><span><strong>몬스터 관리</strong><small>MONSTER CATALOG</small></span></a><a class:active={currentRoute === 'admin/items'} href="#admin/items"><span>◇</span><span><strong>아이템 관리</strong><small>ITEM CATALOG</small></span></a>
        <a class:active={currentRoute === 'admin/shop'} href="#admin/shop"><span>G</span><span><strong>상점 상품 관리</strong><small>SHOP INVENTORY</small></span></a>
        <a class:active={currentRoute === 'admin/combat-test'} href="#admin/combat-test"><span>⚔</span><span><strong>전투 테스트</strong><small>CARD DRAW LAB</small></span></a>
        <a href="#combat"><span>⚔</span><span><strong>실시간 전투방</strong><small>CO-OP CARD BATTLE</small></span></a><div class="admin-sidebar-foot">운영 도구<br /><span>CAMPAIGN ADMIN</span></div>
      </nav>

      <div class="admin-shell-main combat-test-page">
        <div class="page-heading combat-test-heading">
          <div>
            <p class="eyebrow">CARD DRAW LAB</p>
            <h1>전투 테스트</h1>
            <p>플레이어별 보유 카드 덱에서 매 턴 5장을 무작위로 뽑아 봅니다.</p>
          </div>
          {#if combatTestStarted}
            <div class="combat-test-heading-actions">
              <button class="subtle-btn combat-copy-button" type="button" on:click={copyCombatTestCards}>카드 목록 복사</button>
              <div class="combat-test-turn"><span>TURN</span><strong>{combatTestTurn}</strong></div>
            </div>
          {/if}
        </div>

        <section class="admin-card combat-test-setup">
          <div class="form-section-head">
            <div><p class="eyebrow">PARTY SELECT</p><h2>플레이어 선택</h2></div>
            <span class="form-hint">{selectedCharacterIds.length}명 선택됨</span>
          </div>
          {#if adminLoading}
            <div class="repeat-empty">플레이어 목록을 불러오는 중이에요.</div>
          {:else if adminCharacters.length}
            <div class="combat-player-selector">
              {#each adminCharacters as character}
                <label class:selected={selectedCharacterIds.includes(character.id)}>
                  <input
                    type="checkbox"
                    checked={selectedCharacterIds.includes(character.id)}
                    disabled={combatTestStarted}
                    on:change={() => toggleCombatTestCharacter(character.id)}
                  />
                  <span class="combat-player-avatar">
                    {#if character.avatar_url}<img loading="lazy" decoding="async" src={character.avatar_url} alt="" />{:else}{character.name.slice(0, 1)}{/if}
                  </span>
                  <span><strong>{character.name}</strong><small>{character.nickname || '모험가'} · {character.role_name || '역할 미등록'}</small></span>
                  <b>{selectedCharacterIds.includes(character.id) ? 'SELECTED' : 'SELECT'}</b>
                </label>
              {/each}
            </div>
          {:else}
            <div class="repeat-empty">등록된 플레이어 캐릭터가 없습니다.</div>
          {/if}

          <div class="combat-test-setup-actions">
            {#if combatTestStarted}
              <button class="subtle-btn" type="button" on:click={resetCombatTest}>플레이어 다시 선택</button>
              <button class="primary-btn combat-next-turn" type="button" on:click={nextCombatTestTurn}>턴 넘기기 <span>→</span></button>
            {:else}
              <button class="primary-btn" type="button" on:click={startCombatTest} disabled={combatTestLoading || !selectedCharacterIds.length}>
                {combatTestLoading ? '덱 준비 중…' : '전투 테스트 시작'} <span>↗</span>
              </button>
            {/if}
          </div>
        </section>

        {#if combatTestStarted}
          <div class="combat-test-board">
            {#each combatTestPlayers as player (player.characterId)}
              <section class="combat-player-board">
                <div class="combat-player-board-head">
                  <div class="combat-player-identity">
                    <span class="combat-player-avatar large">
                      {#if player.avatarUrl}<img loading="lazy" decoding="async" src={player.avatarUrl} alt="" />{:else}{player.name.slice(0, 1)}{/if}
                    </span>
                    <div><p class="eyebrow">PLAYER HAND</p><h2>{player.name} <button class="combat-player-copy-button" type="button" on:click={() => copyCombatTestPlayerCards(player)}>복사</button></h2><span>{player.nickname || '모험가'}</span></div>
                  </div>
                  <div class="combat-deck-status"><span class="combat-player-hp">HP <strong>{player.hp} / {player.maxHp}</strong></span><span>전체 덱 <strong>{player.deckCards.length}</strong></span><span>뽑기 더미 <strong>{player.drawPile.length}</strong></span><span>소멸 <strong>{player.exhaustedCards.length}</strong></span><span>현재 손패 <strong>{player.hand.length}</strong></span></div>
                </div>

                <div class="combat-equipped-effects">
                  <div class="combat-equipped-effects-head"><span>✦</span><strong>장착 효과</strong><small>{player.equippedEffects.length}개</small></div>
                  {#if player.equippedEffects.length}
                    <ul>{#each player.equippedEffects as effect}<li>{effect}</li>{/each}</ul>
                  {:else}
                    <p>적용 중인 장착 효과가 없습니다.</p>
                  {/if}
                </div>

                {#if player.hand.length}
                  <div class="combat-card-hand">
                    {#each player.hand as card (card.drawId)}
                      <article class="combat-test-card" data-grade={card.grade}>
                        <div class="combat-card-top"><span>{card.grade || '기본'}</span><b>{card.energy || 0}</b></div>
                        <div class="combat-card-rules"><span>{card.card_type || '스킬'}</span><span>대상: {card.card_target || '자신'}</span>{#if card.card_retain}<span>유지</span>{/if}{#if card.card_innate}<span>선천</span>{/if}{#if card.card_ethereal}<span>에테리얼</span>{/if}</div>
                        <h3>{card.card_name}</h3>
                        <div class="combat-card-effects">
                          <div><span>기본</span><p>{card.card_effect || '등록된 카드 효과가 없습니다.'}</p></div>
                          {#if card.card_exhaust_effect}<div class="exhaust"><span>소멸 시 설명</span><p>{card.card_exhaust_effect}</p></div>{/if}
                          {#if card.card_drop_count > 0 || card.card_drop_effect}<div class="drop"><span>추가 드로우 {card.card_drop_count > 0 ? `${card.card_drop_count}장` : ''}</span><p>{card.card_drop_effect || '추가 드로우'}</p></div>{/if}
                        </div>
                        <button class="combat-card-play-button" type="button" on:click={() => playCombatTestCard(player.characterId, card.drawId)}>카드 사용</button>
                        <small>ENERGY</small>
                      </article>
                    {/each}
                  </div>
                {:else}
                  <div class="combat-empty-deck"><span>◇</span><strong>보유 카드가 없습니다</strong><p>캐릭터 상세 페이지에서 카드를 지급한 뒤 다시 시작해 주세요.</p></div>
                {/if}
              </section>
            {/each}
          </div>
        {:else}
          <div class="combat-test-guide">
            <span>01</span><p>플레이어를 한 명 이상 선택합니다.</p>
            <span>02</span><p>시작하면 각 플레이어의 카드 5장을 뽑습니다.</p>
            <span>03</span><p>턴을 넘길 때마다 남은 더미에서 새 손패를 뽑고, 부족하면 전체 덱을 다시 섞습니다.</p>
            <span>04</span><p>이 화면은 손패 테스트입니다. 피해·방어·소멸 시 발동 효과의 자동 판정은 상단 전투 메뉴에서 진행하세요.</p>
          </div>
        {/if}
      </div>
    </div>
  </section>
{/if}
