<script>
  export let notices = [];
  export let categories = [];
  export let filteredPosts = [];
  export let pagedFilteredPosts = [];
  export let filteredPageCount = 1;
  export let activeCategory = '전체';
  export let searchTerm = '';
  export let sortBy = 'latest';
  export let currentPage = 1;
  export let user = null;
  export let openProfile = () => {};
  export let requestLogin = () => {};
  export let startWriting = () => {};
  export let changePage = () => {};

  $: activeBoardCount = categories.filter((category) => category.slug !== 'all' && category.count > 0).length;
</script>

<section class="hero">
  <div class="hero-copy">
    <p class="eyebrow">LONG-FORM TRPG CAMPAIGN</p>
    <h1>문이 열리면,<br /><em>모험이 시작됩니다</em></h1>
    <p class="lead">세계관을 함께 읽고, 캐릭터를 만들고, 한 번의 세션을 오래 기억하세요.<br class="desktop-only" /> open door는 장기 TRPG 캠페인을 위한 기록 공간입니다.</p>
    <div class="hero-cta">
      <button class="primary-btn" on:click={(event) => user ? openProfile(event) : requestLogin()}>{user ? '마이페이지' : '로그인하기'} <span>↗</span></button>
      <a class="text-link" href="#board/sessions">세션 기록 보기 <span>→</span></a>
    </div>
    <div class="hero-signals"><span>세계관</span><span>캐릭터</span><span>세션 로그</span><span>유저 기록</span></div>
  </div>
  <div class="hero-side">
    <div class="hero-side-head"><span class="live-mark">LIVE</span><span>campaign archive</span><span class="spark">✦</span></div>
    <div class="pulse-orbit" aria-hidden="true"><span class="orbit-dot one"></span><span class="orbit-dot two"></span><span class="orbit-dot three"></span><div class="pulse-core">✦<br />TRPG</div></div>
  </div>
</section>

<section class="home-stats" aria-label="캠페인 현황">
  <div class="home-stat"><span class="home-stat-icon gold">✦</span><div><small>전체 게시글</small><strong>{filteredPosts.length}<em> POSTS</em></strong></div></div>
  <div class="home-stat"><span class="home-stat-icon blue">⌁</span><div><small>활동 중인 게시판</small><strong>{activeBoardCount}<em> BOARDS</em></strong></div></div>
  <div class="home-stat"><span class="home-stat-icon pink">◌</span><div><small>최근 공지</small><strong>{notices.length}<em> NOTICES</em></strong></div></div>
  <div class="home-stat-note"><span>“</span><p>기록은 다음 모험을<br /><em>이어주는 지도</em>가 됩니다.</p></div>
</section>

<section class="content-grid">
  <section class="notice-panel panel">
    <div class="section-head"><div><p class="eyebrow">KEEP IN MIND</p><h2>공지사항</h2></div><a href="#board/notices">전체 보기 <span>→</span></a></div>
    <div class="notice-list">
      {#if notices.length}
        {#each notices as item}
          <a class="notice-item" href="#board/notices"><span class={`badge ${item.tone}`}>{item.tag}</span><div class="notice-copy"><h3>{item.title}</h3><p>{item.body}</p></div><div class="notice-meta"><span>{item.meta}</span><b>→</b></div></a>
        {/each}
      {:else}<div class="notice-empty">아직 등록된 공지사항이 없습니다.</div>{/if}
    </div>
  </section>
  <aside class="home-spotlight panel">
    <div class="spotlight-kicker"><span class="live-mark">OPEN DOOR</span><span>field guide</span></div>
    <p class="eyebrow">KEEP EXPLORING</p>
    <h2>오늘의 기록을<br /><em>한 장면</em> 남겨보세요.</h2>
    <p>세계관 자료를 읽거나, 캐릭터를 다듬거나, 방금 끝난 세션의 한 줄을 남겨보세요.</p>
    <div class="spotlight-links"><a href="#board/world">세계관 둘러보기 <span>↗</span></a><a href="#board/users">유저 게시판 열기 <span>↗</span></a></div>
  </aside>
</section>

<section class="posts panel">
  <div class="section-head posts-head"><div><p class="eyebrow">FROM THE CAMPAIGN</p><h2>최근 게시글</h2></div><div class="head-actions"><span class="result-count">총 {filteredPosts.length}개의 글</span><select bind:value={sortBy} aria-label="게시글 정렬"><option value="latest">최신순</option><option value="popular">인기순</option></select></div></div>
  <div class="toolbar"><div class="category-tabs" role="tablist" aria-label="게시글 카테고리">{#each categories as category}<button class:active={activeCategory === category.name} class="category-tab" type="button" on:click={() => (activeCategory = category.name)}>{category.name}<span>{category.count}</span></button>{/each}</div><label class="search"><span aria-hidden="true">⌕</span><input bind:value={searchTerm} type="search" placeholder="게시글 검색" aria-label="게시글 검색" /></label></div>
  <div class="post-list" aria-live="polite">
    {#if filteredPosts.length}
      {#each pagedFilteredPosts as post}
        <a class="post-row" href={`#post/${post.id}`}>{#if post.avatarUrl}<img class="avatar avatar-image" loading="lazy" decoding="async" width="38" height="38" src={post.avatarUrl} alt={`${post.author} 프로필 사진`} />{:else}<span class={`avatar ${post.color}`}>{post.avatar}</span>{/if}<span class="post-main"><span class="post-meta"><b>{post.category}</b><span>{post.date} · {post.time}</span></span><strong>{post.title}</strong><small>{post.excerpt}</small></span><span class="post-author"><b>{post.author}</b><small>작성자</small></span><span class="post-stats"><span>댓글 {post.comments}</span><span>좋아요 {post.likes}</span></span><span class="post-arrow">→</span></a>
      {/each}
    {:else}<div class="empty-state"><span>⌕</span><strong>아직 등록된 글이 없어요</strong><p>로그인 후 첫 번째 이야기를 작성해 보세요.</p></div>{/if}
  </div>
  <div class="pagination">{#each Array(filteredPageCount) as _, index}<button class:active={currentPage === index + 1} type="button" on:click={() => changePage(index + 1)}>{index + 1}</button>{/each}</div>
  <div class="load-more"><button on:click={() => startWriting('users')}>새 글 작성 <span>↗</span></button></div>
</section>
