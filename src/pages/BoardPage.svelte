<script>
  export let currentBoard = { slug: 'all', name: '게시판', description: '' };
  export let boardPagePosts = [];
  export let pagedBoardPosts = [];
  export let boardPageCount = 1;
  export let isAdmin = false;
  export let sortBy = 'latest';
  export let searchTerm = '';
  export let noticeTypeFilter = 'all';
  export let sessionPlayerFilter = '';
  export let sessionPlayerFilterOptions = [];
  export let currentPage = 1;
  export let startWriting = () => {};
  export let changePage = () => {};
</script>

<section class="board-page panel">
  <div class="board-page-hero"><a class="back-link" href="#home">← 홈으로 돌아가기</a><p class="eyebrow">BOARD / {currentBoard.slug.toUpperCase()}</p><h1>{currentBoard.name}</h1><p>{currentBoard.description}.</p>{#if isAdmin || currentBoard.slug === 'users'}<button class="primary-btn" on:click={() => startWriting(currentBoard.slug)}>새 글 작성 <span>↗</span></button>{/if}</div>
  <div class="board-page-content">
    <div class="section-head board-page-head"><div><p class="eyebrow">{currentBoard.name.toUpperCase()}</p><h2>게시글 목록</h2></div><div class="head-actions"><span class="result-count">총 {boardPagePosts.length}개의 글</span><select bind:value={sortBy} aria-label="게시글 정렬"><option value="latest">최신순</option><option value="popular">인기순</option></select></div></div>
    <div class="board-toolbar"><label class="notice-filter" class:hidden={currentBoard.slug !== 'notices'}>분류<select bind:value={noticeTypeFilter}><option value="all">전체</option><option value="notice">공지</option><option value="patch">패치</option><option value="event">이벤트</option></select></label><label class="session-player-filter" class:hidden={currentBoard.slug !== 'sessions'}>플레이어<select bind:value={sessionPlayerFilter}><option value="">전체 플레이어</option>{#each sessionPlayerFilterOptions as player}<option value={player.value}>{player.label}</option>{/each}</select></label><label class="search"><span aria-hidden="true">⌕</span><input bind:value={searchTerm} type="search" placeholder="이 게시판에서 검색" aria-label="이 게시판에서 검색" /></label></div>
    <div class="post-list board-post-list" aria-live="polite">
      {#if boardPagePosts.length}
        {#each pagedBoardPosts as post}
          <a class="post-row" href={`#post/${post.id}`}>{#if post.avatarUrl}<img class="avatar avatar-image" loading="lazy" decoding="async" width="38" height="38" src={post.avatarUrl} alt={`${post.author} 프로필 사진`} />{:else}<span class={`avatar ${post.color}`}>{post.avatar}</span>{/if}<span class="post-main"><span class="post-meta"><b>{post.category}</b><span>{post.date} · {post.time}</span></span><strong>{post.title}</strong><small>{post.excerpt}</small></span><span class="post-author"><b>{post.author}</b><small>작성자</small></span><span class="post-stats"><span>댓글 {post.comments}</span><span>좋아요 {post.likes}</span></span><span class="post-arrow">→</span></a>
        {/each}
      {:else}<div class="empty-state"><span>⌕</span><strong>아직 등록된 글이 없어요</strong><p>첫 번째 이야기를 작성해 보세요.</p></div>{/if}
    </div>
    <div class="pagination">{#each Array(boardPageCount) as _, index}<button class:active={currentPage === index + 1} type="button" on:click={() => changePage(index + 1)}>{index + 1}</button>{/each}</div>
  </div>
</section>
