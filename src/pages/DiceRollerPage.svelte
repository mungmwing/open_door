<script>
  let d20Result = null;
  let d20Rolling = false;
  let diceCount = 2;
  let diceSides = 6;
  let customResult = null;
  let customRolling = false;
  let rollHistory = [];

  const d20Ranges = [
    { range: '1', label: '대실패', tone: 'critical-fail' },
    { range: '2–5', label: '실패', tone: 'fail' },
    { range: '6–10', label: '부분 성공', tone: 'partial' },
    { range: '11–15', label: '성공', tone: 'success' },
    { range: '16–19', label: '큰 성공', tone: 'great-success' },
    { range: '20', label: '대성공', tone: 'critical-success' }
  ];

  const dicePresets = [4, 6, 8, 10, 12, 20, 100];

  function randomDie(sides) {
    return Math.floor(Math.random() * sides) + 1;
  }

  function getD20Outcome(value) {
    if (value === 1) return { label: '대실패', message: '운명이 등을 돌렸습니다.', tone: 'critical-fail' };
    if (value <= 5) return { label: '실패', message: '시도는 원하는 결과에 닿지 못했습니다.', tone: 'fail' };
    if (value <= 10) return { label: '부분 성공', message: '성과는 있지만 대가나 문제가 뒤따릅니다.', tone: 'partial' };
    if (value <= 15) return { label: '성공', message: '의도한 행동을 무사히 해냅니다.', tone: 'success' };
    if (value <= 19) return { label: '큰 성공', message: '기대보다 훌륭한 결과를 얻습니다.', tone: 'great-success' };
    return { label: '대성공', message: '운명적인 최고의 결과입니다!', tone: 'critical-success' };
  }

  function addHistory(entry) {
    rollHistory = [{ ...entry, id: `${Date.now()}-${Math.random()}` }, ...rollHistory].slice(0, 8);
  }

  function rollD20() {
    if (d20Rolling) return;
    d20Rolling = true;
    d20Result = null;
    window.setTimeout(() => {
      const value = randomDie(20);
      const outcome = getD20Outcome(value);
      d20Result = { value, ...outcome };
      addHistory({ notation: '1D20 판정', total: value, detail: outcome.label, tone: outcome.tone });
      d20Rolling = false;
    }, 420);
  }

  function normalizeCustomDice() {
    diceCount = Math.min(20, Math.max(1, Math.floor(Number(diceCount) || 1)));
    diceSides = Math.min(1000, Math.max(2, Math.floor(Number(diceSides) || 2)));
  }

  function rollCustomDice() {
    if (customRolling) return;
    normalizeCustomDice();
    customRolling = true;
    customResult = null;
    window.setTimeout(() => {
      const values = Array.from({ length: diceCount }, () => randomDie(diceSides));
      const total = values.reduce((sum, value) => sum + value, 0);
      customResult = { values, total, notation: `${diceCount}D${diceSides}` };
      addHistory({ notation: `${diceCount}D${diceSides}`, total, detail: values.join(' + '), tone: 'custom' });
      customRolling = false;
    }, 360);
  }

  function usePreset(sides) {
    diceSides = sides;
  }
</script>

<section class="minigames-page dice-detail-page panel">
  <div class="minigames-hero dice-detail-hero">
    <a class="back-link" href="#minigames">← 미니게임 목록으로 돌아가기</a>
    <p class="eyebrow">MINI GAME / DICE ROLLER</p>
    <h1>주사위 굴리기</h1>
    <p>기본 D20 판정을 하거나 주사위 개수와 면 수를 직접 설정하세요.</p>
  </div>

  <div class="minigames-content dice-detail-content">
    <section class="dice-lab" aria-labelledby="dice-lab-title">
      <div class="dice-lab-heading">
        <div><p class="eyebrow">DICE ROLLER</p><h2 id="dice-lab-title">판정 도구</h2><p>D20 판정과 자유 주사위를 한곳에서 사용할 수 있습니다.</p></div>
        <span class="dice-lab-mark">D20</span>
      </div>

      <div class="dice-tools-grid">
        <article class="dice-tool-card d20-tool">
          <div class="dice-tool-title"><div><span>QUICK CHECK</span><h3>D20 기본 판정</h3></div><small>1D20</small></div>
          <div class:dice-spinning={d20Rolling} class="d20-stage" aria-live="polite">
            {#if d20Rolling}
              <div class="d20-face"><small>ROLL</small><strong>?</strong></div>
              <p>운명을 굴리는 중...</p>
            {:else if d20Result}
              <div class={`d20-face ${d20Result.tone}`}><small>D20</small><strong>{d20Result.value}</strong></div>
              <div class={`d20-outcome ${d20Result.tone}`}><strong>{d20Result.label}</strong><p>{d20Result.message}</p></div>
            {:else}
              <div class="d20-face idle"><small>D20</small><strong>20</strong></div>
              <p>버튼을 눌러 판정하세요.</p>
            {/if}
          </div>
          <button class="primary-btn dice-roll-button" type="button" on:click={rollD20} disabled={d20Rolling}>{d20Rolling ? '굴리는 중…' : 'D20 굴리기'} <span>↗</span></button>
          <div class="d20-range-list" aria-label="D20 판정 구간">
            {#each d20Ranges as item}<div class={item.tone}><b>{item.range}</b><span>{item.label}</span></div>{/each}
          </div>
        </article>

        <article class="dice-tool-card custom-dice-tool">
          <div class="dice-tool-title"><div><span>CUSTOM ROLL</span><h3>자유 주사위</h3></div><small>{Math.max(1, Number(diceCount) || 1)}D{Math.max(2, Number(diceSides) || 2)}</small></div>
          <div class="custom-dice-form">
            <label><span>주사위 개수</span><input bind:value={diceCount} type="number" min="1" max="20" on:blur={normalizeCustomDice} /><small>최대 20개</small></label>
            <span class="dice-form-d">D</span>
            <label><span>주사위 면 수</span><input bind:value={diceSides} type="number" min="2" max="1000" on:blur={normalizeCustomDice} /><small>2면–1000면</small></label>
          </div>
          <div class="dice-presets" aria-label="주사위 면 수 빠른 선택">
            {#each dicePresets as sides}<button class:active={Number(diceSides) === sides} type="button" on:click={() => usePreset(sides)}>D{sides}</button>{/each}
          </div>
          <div class:rolling={customRolling} class="custom-result" aria-live="polite">
            {#if customRolling}
              <span class="custom-result-placeholder">주사위를 굴리는 중...</span>
            {:else if customResult}
              <div class="custom-result-total"><small>{customResult.notation} 합계</small><strong>{customResult.total}</strong></div>
              <div class="custom-dice-values">{#each customResult.values as value, index}<span aria-label={`${index + 1}번째 주사위 ${value}`}>{value}</span>{/each}</div>
            {:else}
              <span class="custom-result-placeholder">결과가 여기에 표시됩니다.</span>
            {/if}
          </div>
          <button class="primary-btn dice-roll-button custom" type="button" on:click={rollCustomDice} disabled={customRolling}>{customRolling ? '굴리는 중…' : `${Math.max(1, Number(diceCount) || 1)}D${Math.max(2, Number(diceSides) || 2)} 굴리기`} <span>↗</span></button>
        </article>
      </div>

      <section class="dice-history" aria-labelledby="dice-history-title">
        <div class="dice-history-head"><div><p class="eyebrow">RECENT ROLLS</p><h3 id="dice-history-title">최근 결과</h3></div>{#if rollHistory.length}<button type="button" on:click={() => (rollHistory = [])}>기록 지우기</button>{/if}</div>
        {#if rollHistory.length}
          <div class="dice-history-list">{#each rollHistory as roll}<article><span class={`history-dot ${roll.tone}`}></span><strong>{roll.notation}</strong><p>{roll.detail}</p><b>{roll.total}</b></article>{/each}</div>
        {:else}
          <p class="dice-history-empty">아직 굴린 주사위가 없습니다.</p>
        {/if}
      </section>
    </section>
  </div>
</section>
