<script>
  import { onMount } from 'svelte';
  import { supabase, supabaseConfig } from './supabaseClient';

  const fallbackCategories = [
    { name: '전체', slug: 'all', count: 0, description: '모든 게시글 모아보기' },
    { name: '공지사항', slug: 'notices', count: 0, description: '운영 안내 · 업데이트 · 이벤트' },
    { name: '세계관 자료실', slug: 'world', count: 0, description: '세계관 · NPC · 대륙 · 국가' },
    { name: '유저 게시판', slug: 'users', count: 0, description: '질문 · 잡담 · 파티 모집' },
    { name: '세션 로그', slug: 'sessions', count: 0, description: '플레이 기록 · 후기 · 다음화 예고' }
  ];
  const inventoryGrades = ['일반', '고급', '희귀', '영웅', '전설', '신화'];
  const inventoryTypes = ['유물', '장비', '소비', '기타'];
  const cardGrades = ['기본', '일반', '고급', '희귀', '특수'];

  let audio;
  let muted = false;
  let volume = 0.4;
  let showLogin = false;
  let notice = '';
  let loginId = '';
  let loginPassword = '';
  let session = null;
  let user = null;
  let profile = null;
  let profileLoading = false;
  let isAdmin = false;
  let activeCategory = '전체';
  let searchTerm = '';
  let sortBy = 'latest';
  let currentRoute = 'home';
  let dbStatus = 'loading';
  let dbError = '';
  let categories = fallbackCategories;
  let notices = [];
  let posts = [];
  let detailPost = null;
  let detailLoading = false;
  let postSaving = false;
  let characterLoading = false;
  let characterSaving = false;
  let characterError = '';
  let character = null;
  let inventory = [];
  let cards = [];
  let adminCharacters = [];
  let characterRequestId = 0;
  let accountSaving = false;
  let detailComments = [];
  let commentText = '';
  let commentSaving = false;
  let detailLiked = false;
  let detailLikeSaving = false;

  let postForm = { title: '', content: '' };
  let writeBoardSlug = 'users';
  let characterForm = { name: '', roleName: '', roleTraits: '', age: '', height: '', weight: '' };
  let adminForm = {
    loginId: '', password: '', nickname: '',
    character: { name: '', roleName: '', roleTraits: '', age: '', height: '', weight: '' }
  };

  $: filteredPosts = posts
    .filter((post) => activeCategory === '전체' || post.category === activeCategory)
    .filter((post) => `${post.title} ${post.excerpt} ${post.author}`.toLowerCase().includes(searchTerm.toLowerCase().trim()))
    .sort((a, b) => sortBy === 'popular' ? b.views - a.views : posts.indexOf(a) - posts.indexOf(b));
  $: isBoardPage = currentRoute.startsWith('board/');
  $: isPostPage = currentRoute.startsWith('post/');
  $: isWritePage = currentRoute.startsWith('write/');
  $: isMyPage = currentRoute === 'mypage';
  $: isAdminPage = currentRoute === 'admin';
  $: currentBoard = categories.find((board) => board.slug === currentRoute.replace('board/', '')) || categories[0];
  $: writeBoard = categories.find((board) => board.slug === writeBoardSlug) || categories.find((board) => board.slug === 'users') || categories[0];
  $: boardPagePosts = posts
    .filter((post) => currentBoard.slug === 'all' || post.category === currentBoard.name)
    .filter((post) => `${post.title} ${post.excerpt} ${post.author}`.toLowerCase().includes(searchTerm.toLowerCase().trim()))
    .sort((a, b) => sortBy === 'popular' ? b.views - a.views : posts.indexOf(a) - posts.indexOf(b));

  function showNotice(message) {
    notice = message;
    setTimeout(() => (notice = ''), 2800);
  }

  function normalizeLoginId(value) {
    return value.trim().toLowerCase();
  }

  async function getInternalAuthEmail(loginValue) {
    const bytes = new TextEncoder().encode(normalizeLoginId(loginValue));
    const digest = await crypto.subtle.digest('SHA-256', bytes);
    const hash = Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, '0')).join('');
    return `id-${hash}@open-door.local`;
  }

  function formatDate(value) {
    const date = value ? new Date(value) : new Date();
    const pad = (number) => String(number).padStart(2, '0');
    return { date: `${pad(date.getMonth() + 1)}.${pad(date.getDate())}`, time: `${pad(date.getHours())}:${pad(date.getMinutes())}` };
  }

  function formatPost(post, boardMap) {
    const profileData = Array.isArray(post.profiles) ? post.profiles[0] : post.profiles;
    const commentRelation = post.post_comments || post.comments;
    const likeRelation = post.post_likes || post.likes;
    const commentCount = Array.isArray(commentRelation) ? commentRelation[0]?.count || 0 : 0;
    const likeCount = Array.isArray(likeRelation) ? likeRelation[0]?.count || 0 : 0;
    const date = formatDate(post.created_at);
    const nickname = profileData?.nickname || '모험가';
    return {
      id: post.id, boardSlug: post.board_slug, category: boardMap.get(post.board_slug)?.name || post.board_slug,
      title: post.title, content: post.content || '',
      excerpt: post.excerpt || post.content?.replace(/\s+/g, ' ').slice(0, 140) || '아직 요약이 등록되지 않은 게시글입니다.',
      author: nickname, authorId: post.author_id, date: date.date, time: date.time,
      views: post.views || 0, comments: commentCount, likes: likeCount, avatar: nickname.slice(0, 1).toUpperCase(),
      color: ['lavender', 'mint', 'peach', 'yellow', 'blue'][nickname.charCodeAt(0) % 5]
    };
  }

  async function loadDatabase() {
    if (!supabase || !supabaseConfig.url || !supabaseConfig.hasPublishableKey) {
      dbStatus = 'missing'; dbError = 'Supabase 환경변수가 없습니다.'; return;
    }
    try {
      const [boardsResult, postsResult] = await Promise.all([
        supabase.from('boards').select('slug, name, description, sort_order, is_public').eq('is_public', true).order('sort_order', { ascending: true }),
        supabase.from('posts').select('id, board_slug, title, content, excerpt, status, views, created_at, author_id, profiles(nickname, avatar_url), post_comments(count), post_likes(count)').eq('status', 'published').order('created_at', { ascending: false }).limit(100)
      ]);
      if (boardsResult.error) throw new Error(`게시판 조회 실패: ${boardsResult.error.message}`);
      if (postsResult.error) throw new Error(`게시글 조회 실패: ${postsResult.error.message}`);
      const remoteBoards = (boardsResult.data || []).filter((board) => board.slug !== 'characters');
      const boardMap = new Map(remoteBoards.map((board) => [board.slug, board]));
      const remotePosts = postsResult.data || [];
      const counts = remotePosts.reduce((map, post) => map.set(post.board_slug, (map.get(post.board_slug) || 0) + 1), new Map());
      categories = [{ name: '전체', slug: 'all', count: remotePosts.length, description: '모든 게시글 모아보기' }, ...remoteBoards.map((board) => ({ ...board, count: counts.get(board.slug) || 0 }))];
      posts = remotePosts.map((post) => formatPost(post, boardMap));
      notices = posts.filter((post) => post.boardSlug === 'notices').slice(0, 3).map((post, index) => ({ tag: ['필독', '세계관', '세션'][index] || '공지', title: post.title, meta: `${post.date} ${post.time}`, body: post.excerpt, tone: ['gold', 'blue', 'pink'][index] || 'gold' }));
      dbStatus = 'connected'; dbError = '';
    } catch (error) {
      dbStatus = 'error'; dbError = error instanceof Error ? error.message : 'Supabase 연결에 실패했습니다.';
    }
  }

  async function loadProfile(activeUser = user) {
    if (!supabase || !activeUser) return;
    profileLoading = true;
    try {
      const profileQuery = supabase.from('profiles').select('id, nickname, role, avatar_url').eq('id', activeUser.id).maybeSingle();
      const { data, error } = await Promise.race([
        profileQuery,
        new Promise((_, reject) => setTimeout(() => reject(new Error('프로필 조회 시간이 초과되었습니다.')), 10000))
      ]);
      profile = data || null;
      isAdmin = !error && data?.role === 'admin';
      if (isAdmin && (currentRoute === 'mypage' || currentRoute === 'admin')) navigateTo('#admin');
    } catch (error) {
      profile = null;
      isAdmin = false;
    } finally {
      profileLoading = false;
    }
  }

  async function applySession(nextSession) {
    session = nextSession; user = nextSession?.user || null;
    if (user) {
      profile = null;
      isAdmin = false;
      await loadProfile(user);
      await loadCharacterData();
    } else {
      profile = null; profileLoading = false; isAdmin = false; character = null; inventory = []; cards = [];
    }
  }

  async function handleLogin() {
    const normalizedId = normalizeLoginId(loginId);
    if (!normalizedId || !loginPassword) return showNotice('아이디와 비밀번호를 입력해 주세요.');
    if (!supabase) return showNotice('로그인 설정을 확인해 주세요.');
    const internalEmail = await getInternalAuthEmail(normalizedId);
    let result = await supabase.auth.signInWithPassword({ email: internalEmail, password: loginPassword });
    // Keep the first administrator account, created before the flexible ID
    // scheme, compatible with the new login flow.
    if (result.error) result = await supabase.auth.signInWithPassword({ email: `${normalizedId}@open-door.local`, password: loginPassword });
    if (result.error) return showNotice('아이디 또는 비밀번호를 확인해 주세요.');
    session = result.data.session;
    user = result.data.user;
    showLogin = false;
    loginId = '';
    loginPassword = '';
    showNotice('캠페인 기록소에 입장했습니다.');
  }

  async function handleLogout() {
    // Update the interface first; network cleanup should not delay the button.
    session = null;
    user = null;
    profile = null;
    profileLoading = false;
    isAdmin = false;
    character = null;
    inventory = [];
    cards = [];
    showNotice('로그아웃되었습니다.');
    navigateTo('#home');
    if (supabase) await supabase.auth.signOut();
  }

  function toggleSound() { muted = !muted; if (audio) audio.muted = muted; }
  function updateVolume(event) {
    volume = Number(event.currentTarget.value); if (audio) audio.volume = volume;
    if (volume > 0 && muted) { muted = false; if (audio) audio.muted = false; }
  }

  function syncRoute() {
    const nextRoute = window.location.hash.replace(/^#/, '') || 'home';
    if (nextRoute === 'about') {
      navigateTo('#home');
      return;
    }
    if (nextRoute === 'board/characters') {
      navigateTo(user ? '#mypage' : '#home');
      return;
    }
    currentRoute = nextRoute; activeCategory = '전체'; searchTerm = ''; sortBy = 'latest'; detailPost = null;
    if (nextRoute.startsWith('write/')) writeBoardSlug = nextRoute.replace('write/', '') || 'users';
    window.scrollTo({ top: 0, behavior: 'instant' });
    if (nextRoute.startsWith('post/')) loadPostDetail(nextRoute.replace('post/', ''));
    if (nextRoute === 'mypage' || nextRoute === 'admin') loadCharacterData();
  }

  function navigateTo(hash) {
    const nextHash = hash.startsWith('#') ? hash : `#${hash}`;
    if (window.location.hash === nextHash) {
      syncRoute();
      return;
    }
    window.location.hash = nextHash;
    syncRoute();
  }

  async function loadPostDetail(id) {
    if (!supabase || !id) return;
    detailLoading = true;
    detailComments = [];
    commentText = '';
    detailLiked = false;
    const { data, error } = await supabase.from('posts').select('id, board_slug, title, content, excerpt, status, views, created_at, author_id, profiles(nickname, avatar_url), post_comments(count), post_likes(count)').eq('id', id).maybeSingle();
    if (error || !data) { detailLoading = false; return showNotice('게시글을 불러오지 못했습니다.'); }
    const boardMap = new Map(categories.map((board) => [board.slug, board])); detailPost = formatPost(data, boardMap); detailLoading = false;
    await loadEngagement(id);
    await supabase.rpc('increment_post_views', { post_id_input: id });
  }

  async function loadEngagement(postId) {
    if (!supabase || !postId) return;
    const commentsResult = await supabase.from('post_comments').select('id, content, created_at, author_id').eq('post_id', postId).order('created_at', { ascending: true });
    if (!commentsResult.error) {
      const rows = commentsResult.data || [];
      const authorIds = [...new Set(rows.map((comment) => comment.author_id).filter(Boolean))];
      const profilesResult = authorIds.length ? await supabase.from('profiles').select('id, nickname').in('id', authorIds) : { data: [] };
      const names = new Map((profilesResult.data || []).map((item) => [item.id, item.nickname]));
      detailComments = rows.map((comment) => ({ ...comment, nickname: names.get(comment.author_id) || '모험가' }));
    }
    if (!user) {
      detailLiked = false;
      return;
    }
    const likeResult = await supabase.from('post_likes').select('post_id').eq('post_id', postId).eq('user_id', user.id).maybeSingle();
    if (!likeResult.error) detailLiked = Boolean(likeResult.data);
  }

  function requireLogin(message = '로그인 후 이용할 수 있어요.') {
    if (user) return true; showNotice(message); showLogin = true; return false;
  }
  function openProfile(event) {
    event?.preventDefault();
    navigateTo(isAdmin ? '#admin' : '#mypage');
  }
  function startWriting(slug = currentBoard.slug) {
    if (!requireLogin()) return; navigateTo(`#write/${slug === 'all' ? 'users' : slug}`);
  }

  async function createPost() {
    if (!requireLogin() || !supabase) return;
    if (!postForm.title.trim() || !postForm.content.trim()) return showNotice('제목과 내용을 모두 입력해 주세요.');
    postSaving = true;
    const boardSlug = writeBoardSlug === 'all' ? 'users' : writeBoardSlug;
    const payload = { board_slug: boardSlug, title: postForm.title.trim(), content: postForm.content.trim(), excerpt: postForm.content.trim().replace(/\s+/g, ' ').slice(0, 140), status: 'published', author_id: user.id };
    const { data, error } = await supabase.from('posts').insert(payload).select('id').single(); postSaving = false;
    if (error) return showNotice(`글 저장 실패: ${error.message}`);
    postForm = { title: '', content: '' }; await loadDatabase(); showNotice('게시글을 등록했습니다.'); navigateTo(`#post/${data.id}`);
  }

  async function addComment() {
    if (!requireLogin('댓글을 작성하려면 로그인해 주세요.') || !supabase || !detailPost) return;
    const content = commentText.trim();
    if (!content) return showNotice('댓글 내용을 입력해 주세요.');
    commentSaving = true;
    const { error } = await supabase.from('post_comments').insert({ post_id: detailPost.id, author_id: user.id, content });
    commentSaving = false;
    if (error) return showNotice(`댓글 저장 실패: ${error.message}`);
    commentText = '';
    detailPost = { ...detailPost, comments: detailPost.comments + 1 };
    await loadEngagement(detailPost.id);
    showNotice('댓글을 등록했습니다.');
  }

  async function toggleLike() {
    if (!requireLogin('좋아요는 로그인 후 이용할 수 있어요.') || !supabase || !detailPost || detailLikeSaving) return;
    detailLikeSaving = true;
    const result = detailLiked
      ? await supabase.from('post_likes').delete().eq('post_id', detailPost.id).eq('user_id', user.id)
      : await supabase.from('post_likes').insert({ post_id: detailPost.id, user_id: user.id });
    detailLikeSaving = false;
    if (result.error) return showNotice(`좋아요 처리 실패: ${result.error.message}`);
    detailLiked = !detailLiked;
    detailPost = { ...detailPost, likes: Math.max(0, detailPost.likes + (detailLiked ? 1 : -1)) };
  }

  function numberOrNull(value) { return value === '' || value === null || value === undefined ? null : Number(value); }
  function newInventoryItem() { inventory = [...inventory, { item_name: '', item_effect: '', quantity: 1, grade: '일반', item_type: '기타' }]; }
  function newCard() { cards = [...cards, { card_name: '', card_effect: '', quantity: 1, grade: '기본' }]; }
  function removeInventory(index) { inventory = inventory.filter((_, itemIndex) => itemIndex !== index); }
  function removeCard(index) { cards = cards.filter((_, cardIndex) => cardIndex !== index); }
  function setCharacterForm(data) {
    characterForm = { name: data?.name || '', roleName: data?.role_name || '', roleTraits: data?.role_traits || '', age: data?.age ?? '', height: data?.height ?? '', weight: data?.weight ?? '' };
  }

  async function loadCharacterData() {
    const requestId = ++characterRequestId;
    if (!supabase || !user) {
      characterLoading = false;
      adminLoading = false;
      return;
    }

    characterLoading = true;
    adminLoading = isAdmin;
    characterError = '';

    try {
      const characterQuery = isAdmin
        ? supabase.from('characters').select('*').order('created_at', { ascending: false })
        : supabase.from('characters').select('*').eq('owner_id', user.id).maybeSingle();
      const { data, error } = await Promise.race([
        characterQuery,
        new Promise((_, reject) => setTimeout(() => reject(new Error('캐릭터 정보 조회 시간이 초과되었습니다.')), 10000))
      ]);
      if (error) throw new Error(error.message);

      if (isAdmin) {
        const rows = data || [];
        const ids = [...new Set(rows.map((row) => row.owner_id))];
        const profilesResult = ids.length ? await supabase.from('profiles').select('id, nickname').in('id', ids) : { data: [] };
        if (profilesResult.error) throw new Error(profilesResult.error.message);
        const names = new Map((profilesResult.data || []).map((item) => [item.id, item.nickname]));
        if (requestId === characterRequestId) adminCharacters = rows.map((row) => ({ ...row, nickname: names.get(row.owner_id) || '모험가' }));
        return;
      }

      if (requestId !== characterRequestId) return;
      character = data || null;
      setCharacterForm(character);
      if (!character) {
        inventory = [];
        cards = [];
        return;
      }
      const [itemsResult, cardsResult] = await Promise.all([
        supabase.from('inventory_items').select('id, item_name, item_effect, quantity, grade, item_type').eq('character_id', character.id).order('created_at'),
        supabase.from('character_cards').select('id, card_name, card_effect, quantity, grade').eq('character_id', character.id).order('created_at')
      ]);
      if (itemsResult.error) throw new Error(itemsResult.error.message);
      if (cardsResult.error) throw new Error(cardsResult.error.message);
      inventory = itemsResult.data || [];
      cards = cardsResult.data || [];
    } catch (error) {
      if (requestId === characterRequestId) characterError = error instanceof Error ? error.message : '캐릭터 정보를 불러오지 못했습니다.';
    } finally {
      if (requestId === characterRequestId) {
        characterLoading = false;
        adminLoading = false;
      }
    }
  }

  async function saveCharacter() {
    if (!requireLogin() || !supabase) return;
    if (!characterForm.name.trim() || !characterForm.roleName.trim()) return showNotice('캐릭터 이름과 역할명을 입력해 주세요.');
    characterSaving = true;
    const payload = { owner_id: user.id, name: characterForm.name.trim(), class_name: characterForm.roleName.trim(), content: characterForm.roleTraits.trim(), status: 'published', role_name: characterForm.roleName.trim(), role_traits: characterForm.roleTraits.trim(), age: numberOrNull(characterForm.age), height: numberOrNull(characterForm.height), weight: numberOrNull(characterForm.weight) };
    const characterResult = character?.id ? await supabase.from('characters').update(payload).eq('id', character.id).select().single() : await supabase.from('characters').insert(payload).select().single();
    if (characterResult.error) { characterSaving = false; return showNotice(`캐릭터 저장 실패: ${characterResult.error.message}`); }
    const characterId = characterResult.data.id;
    const deleteItems = await supabase.from('inventory_items').delete().eq('character_id', characterId); const deleteCards = await supabase.from('character_cards').delete().eq('character_id', characterId);
    if (deleteItems.error || deleteCards.error) { characterSaving = false; return showNotice('인벤토리 또는 카드 정리 중 오류가 발생했습니다.'); }
    const items = inventory.filter((item) => item.item_name?.trim()).map((item) => ({ character_id: characterId, item_name: item.item_name.trim(), item_effect: item.item_effect?.trim() || '', quantity: Math.max(1, Number(item.quantity) || 1), grade: item.grade, item_type: item.item_type }));
    const cardRows = cards.filter((card) => card.card_name?.trim()).map((card) => ({ character_id: characterId, card_name: card.card_name.trim(), card_effect: card.card_effect?.trim() || '', quantity: Math.max(1, Number(card.quantity) || 1), grade: card.grade }));
    if (items.length) await supabase.from('inventory_items').insert(items); if (cardRows.length) await supabase.from('character_cards').insert(cardRows);
    character = characterResult.data; characterSaving = false; showNotice('캐릭터 시트를 저장했습니다.'); await loadCharacterData();
  }

  async function createPlayerAccount() {
    if (!isAdmin || !supabase) return;
    if (!adminForm.loginId.trim() || !adminForm.password || !adminForm.nickname.trim()) return showNotice('아이디, 비밀번호, 표시 이름을 입력해 주세요.');
    accountSaving = true;
    const { error } = await supabase.functions.invoke('admin-create-user', { body: { loginId: adminForm.loginId.trim(), password: adminForm.password, nickname: adminForm.nickname.trim(), character: adminForm.character } });
    accountSaving = false;
    if (error) return showNotice(`계정 생성 실패: ${error.message}`);
    adminForm = { loginId: '', password: '', nickname: '', character: { name: '', roleName: '', roleTraits: '', age: '', height: '', weight: '' } }; showNotice('플레이어 계정과 캐릭터를 생성했습니다.'); await loadCharacterData();
  }

  onMount(() => {
    if (audio) { audio.volume = volume; audio.muted = muted; }
    audio?.play().catch(() => {});
    syncRoute();

    // Register routing before the remote database/auth boot sequence. A slow
    // Supabase request must never prevent hash links from changing the page.
    window.addEventListener('hashchange', syncRoute);
    let authSubscription;

    const initialize = async () => {
      await loadDatabase();
      if (!supabase) return;
      const { data } = await supabase.auth.getSession();
      await applySession(data.session);
      const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => {
        // Supabase advises deferring database calls from this callback so the
        // auth lock can finish before profiles/characters are queried.
        setTimeout(() => {
          applySession(nextSession).catch((error) => {
            profileLoading = false;
            characterLoading = false;
            adminLoading = false;
            characterError = error instanceof Error ? error.message : '세션 정보를 불러오지 못했습니다.';
          });
        }, 0);
      });
      authSubscription = listener.subscription;
    };

    initialize().catch((error) => {
      dbStatus = 'error';
      dbError = error instanceof Error ? error.message : '앱 초기화에 실패했습니다.';
    });

    return () => {
      authSubscription?.unsubscribe();
      window.removeEventListener('hashchange', syncRoute);
    };
  });
</script>

<svelte:head><title>open door — 장기 TRPG 캠페인 기록소</title><meta name="description" content="세계관, 캐릭터, 세션 기록을 함께 쌓아가는 open door 장기 TRPG 캠페인 사이트입니다." /></svelte:head>
<audio bind:this={audio} loop src="/pixel-shrine-drift.mp3"></audio>

<div class="site"><div class="bg-grid" aria-hidden="true"></div><div class="bg-glow bg-glow-a" aria-hidden="true"></div><div class="bg-glow bg-glow-b" aria-hidden="true"></div>
  <header class="header"><a class="brand" href="#home" aria-label="open door 홈"><span class="brand-mark">od</span><span class="brand-copy"><strong>open door</strong><small>long-form TRPG campaign</small></span></a>
     <nav class="main-nav" aria-label="주요 메뉴"><a class:active={currentRoute === 'home'} href="#home">홈</a><div class="nav-item nav-dropdown"><a class:active={isBoardPage} href="#board/all" aria-haspopup="true">게시판 <span class="nav-caret">⌄</span></a><div class="dropdown-menu" aria-label="게시판 세부 메뉴">{#each categories.slice(1) as board}<a href={`#board/${board.slug}`}><strong>{board.name}</strong><small>{board.description}</small></a>{/each}</div></div><a class:active={currentRoute === 'board/notices'} href="#board/notices">공지사항</a>{#if user}<a class:active={isMyPage || isAdminPage} href={isAdmin ? '#admin' : '#mypage'} on:click={openProfile}>마이페이지</a>{/if}</nav>
    <div class="header-actions"><div class="audio-pill" role="group" aria-label="사운드 설정"><button class="audio-toggle" on:click={toggleSound} aria-pressed={muted}><span class="audio-icon" aria-hidden="true">{muted ? '×' : '♪'}</span><span>{muted ? 'Muted' : 'Sound'}</span></button><input class="audio-slider" type="range" min="0" max="1" step="0.01" value={volume} on:input={updateVolume} aria-label="볼륨 조절" /></div>{#if user}<button class="login logged-in" on:click={handleLogout}>로그아웃</button>{:else}<button class="login" on:click={() => (showLogin = true)}>로그인</button>{/if}</div>
  </header>

   <main id="home" class="layout">
    {#key currentRoute}
    {#if currentRoute === 'home'}
      <section class="hero"><div class="hero-copy"><div class="status-line"><span class="status-dot"></span> 장기 TRPG 캠페인의 기록을 이어가고 있어요</div><p class="eyebrow">LONG-FORM TRPG CAMPAIGN</p><h1>문이 열리면,<br /><em>모험이 시작됩니다</em></h1><p class="lead">세계관을 함께 읽고, 캐릭터를 만들고, 한 번의 세션을 오래 기억하세요.<br class="desktop-only" /> open door는 장기 TRPG 캠페인을 위한 기록 공간입니다.</p><div class="hero-cta"><button class="primary-btn" on:click={(event) => user ? openProfile(event) : (showLogin = true)}>마이페이지 <span>↗</span></button><a class="text-link" href="#board/sessions">세션 기록 보기 <span>→</span></a></div></div><div class="hero-side"><div class="hero-side-head"><span class="live-mark">LIVE</span><span>campaign archive</span><span class="spark">✦</span></div><div class="pulse-orbit" aria-hidden="true"><span class="orbit-dot one"></span><span class="orbit-dot two"></span><span class="orbit-dot three"></span><div class="pulse-core">✦<br />TRPG</div></div></div></section>
      <section class="board-directory panel" aria-labelledby="board-directory-title"><div class="section-head board-directory-head"><div><p class="eyebrow">CHOOSE YOUR PATH</p><h2 id="board-directory-title">게시판 안내</h2></div><div class="directory-meta"><p class="section-caption">세계관을 읽고, 캐릭터를 만들고,<br class="desktop-only" /> 함께 모험을 기록해 보세요.</p><span class={`data-status ${dbStatus}`}><i></i>{dbStatus === 'connected' ? 'LIVE DATABASE' : dbStatus === 'loading' ? '데이터 불러오는 중' : 'DB 연결 확인 필요'}</span></div></div><div class="board-grid">{#each categories.slice(1) as category, index}<a class="board-card" class:featured={index === 1} href={`#board/${category.slug}`}><span class="board-number">0{index + 1}</span><span class="board-copy"><strong>{category.name}</strong><small>{category.description}</small></span><span class="board-arrow">↗</span></a>{/each}</div></section>
      <section class="content-grid"><section class="notice-panel panel"><div class="section-head"><div><p class="eyebrow">KEEP IN MIND</p><h2>공지사항</h2></div><a href="#board/notices">전체 보기 <span>→</span></a></div><div class="notice-list">{#if notices.length}{#each notices as item}<a class="notice-item" href="#board/notices"><span class={`badge ${item.tone}`}>{item.tag}</span><div class="notice-copy"><h3>{item.title}</h3><p>{item.body}</p></div><div class="notice-meta"><span>{item.meta}</span><b>→</b></div></a>{/each}{:else}<div class="notice-empty">아직 등록된 공지사항이 없습니다.</div>{/if}</div></section></section>
       <section class="posts panel"><div class="section-head posts-head"><div><p class="eyebrow">FROM THE CAMPAIGN</p><h2>최근 게시글</h2></div><div class="head-actions"><span class="result-count">총 {filteredPosts.length}개의 글</span><select bind:value={sortBy} aria-label="게시글 정렬"><option value="latest">최신순</option><option value="popular">인기순</option></select></div></div><div class="toolbar"><div class="category-tabs" role="tablist" aria-label="게시글 카테고리">{#each categories as category}<button class:active={activeCategory === category.name} class="category-tab" type="button" on:click={() => (activeCategory = category.name)}>{category.name}<span>{category.count}</span></button>{/each}</div><label class="search"><span aria-hidden="true">⌕</span><input bind:value={searchTerm} type="search" placeholder="게시글 검색" aria-label="게시글 검색" /></label></div><div class="post-list" aria-live="polite">{#if filteredPosts.length}{#each filteredPosts as post}<a class="post-row" href={`#post/${post.id}`}><span class={`avatar ${post.color}`}>{post.avatar}</span><span class="post-main"><span class="post-meta"><b>{post.category}</b><span>{post.date} · {post.time}</span></span><strong>{post.title}</strong><small>{post.excerpt}</small></span><span class="post-author"><b>{post.author}</b><small>작성자</small></span><span class="post-stats"><span>댓글 {post.comments}</span><span>좋아요 {post.likes}</span></span><span class="post-arrow">→</span></a>{/each}{:else}<div class="empty-state"><span>⌕</span><strong>아직 등록된 글이 없어요</strong><p>로그인 후 첫 번째 이야기를 작성해 보세요.</p></div>{/if}</div><div class="load-more"><button on:click={() => startWriting('users')}>새 글 작성 <span>↗</span></button></div></section>
    {:else if isBoardPage}
       <section class="board-page panel"><div class="board-page-hero"><a class="back-link" href="#home">← 홈으로 돌아가기</a><p class="eyebrow">BOARD / {currentBoard.slug.toUpperCase()}</p><h1>{currentBoard.name}</h1><p>{currentBoard.description}.<br />이곳에서 캠페인의 이야기를 차곡차곡 쌓아 보세요.</p><button class="primary-btn" on:click={() => startWriting(currentBoard.slug)}>새 글 작성 <span>↗</span></button></div><div class="board-page-content"><div class="section-head board-page-head"><div><p class="eyebrow">{currentBoard.name.toUpperCase()}</p><h2>게시글 목록</h2></div><div class="head-actions"><span class="result-count">총 {boardPagePosts.length}개의 글</span><select bind:value={sortBy} aria-label="게시글 정렬"><option value="latest">최신순</option><option value="popular">인기순</option></select></div></div><div class="board-toolbar"><label class="search"><span aria-hidden="true">⌕</span><input bind:value={searchTerm} type="search" placeholder="이 게시판에서 검색" aria-label="이 게시판에서 검색" /></label><a href="#board/all">전체 게시판 보기 <span>→</span></a></div><div class="post-list board-post-list" aria-live="polite">{#if boardPagePosts.length}{#each boardPagePosts as post}<a class="post-row" href={`#post/${post.id}`}><span class={`avatar ${post.color}`}>{post.avatar}</span><span class="post-main"><span class="post-meta"><b>{post.category}</b><span>{post.date} · {post.time}</span></span><strong>{post.title}</strong><small>{post.excerpt}</small></span><span class="post-author"><b>{post.author}</b><small>작성자</small></span><span class="post-stats"><span>댓글 {post.comments}</span><span>좋아요 {post.likes}</span></span><span class="post-arrow">→</span></a>{/each}{:else}<div class="empty-state"><span>⌕</span><strong>아직 등록된 글이 없어요</strong><p>첫 번째 이야기를 작성해 보세요.</p></div>{/if}</div></div></section>
    {:else if isPostPage}
       <section class="detail-page panel">{#if detailLoading}<div class="empty-state"><span>◌</span><strong>게시글을 불러오는 중이에요</strong></div>{:else if detailPost}<a class="back-link" href={`#board/${detailPost.boardSlug}`}>← {detailPost.category}로 돌아가기</a><div class="detail-meta"><span class="badge gold">{detailPost.category}</span><span>{detailPost.date} · {detailPost.time}</span><span>조회 {detailPost.views}</span></div><h1>{detailPost.title}</h1><div class="detail-author"><span class={`avatar ${detailPost.color}`}>{detailPost.avatar}</span><b>{detailPost.author}</b><span>작성자</span></div><div class="detail-body">{detailPost.content}</div><div class="detail-actions"><button class:liked={detailLiked} class="like-button" type="button" on:click={toggleLike} disabled={detailLikeSaving}>♥ 좋아요 {detailPost.likes}</button><span>댓글 {detailPost.comments}개</span></div><section class="comments-section" aria-labelledby="comments-title"><div class="comments-heading"><h2 id="comments-title">댓글</h2><span>{detailComments.length}개</span></div>{#if detailComments.length}{#each detailComments as comment}<article class="comment-item"><div class="comment-author"><span class="avatar mint">{comment.nickname.slice(0, 1)}</span><strong>{comment.nickname}</strong><time>{formatDate(comment.created_at).date}</time></div><p>{comment.content}</p></article>{/each}{:else}<div class="comments-empty">아직 댓글이 없습니다. 첫 번째 의견을 남겨 보세요.</div>{/if}<form class="comment-form" on:submit|preventDefault={addComment}><textarea bind:value={commentText} rows="3" placeholder={user ? '이 모험에 대한 생각을 남겨 주세요.' : '로그인 후 댓글을 작성할 수 있어요.'} disabled={!user}></textarea><button class="primary-btn" type="submit" disabled={commentSaving}>{commentSaving ? '등록 중…' : '댓글 등록'} <span>↗</span></button></form></section><div class="detail-footer"><a href={`#write/${detailPost.boardSlug}`}>이 게시판에 글쓰기 <span>↗</span></a><span>모험의 기록을 함께 이어가요</span></div>{:else}<div class="empty-state"><span>?</span><strong>게시글을 찾을 수 없어요</strong><a class="text-link" href="#home">홈으로 돌아가기 →</a></div>{/if}</section>
    {:else if isWritePage}
      <section class="write-page panel"><a class="back-link" href={`#board/${writeBoard.slug}`}>← {writeBoard.name}로 돌아가기</a><p class="eyebrow">NEW CAMPAIGN RECORD</p><h1>새 이야기 작성</h1><p class="page-lead">게시판을 선택하고 모험의 기록을 작성해 주세요.</p><form class="editor-form" on:submit|preventDefault={createPost}><label>게시판<select bind:value={writeBoardSlug}>{#each categories.slice(1) as board}<option value={board.slug}>{board.name}</option>{/each}</select></label><label>제목<input bind:value={postForm.title} maxlength="120" placeholder="글 제목을 입력해 주세요" /></label><label>내용<textarea bind:value={postForm.content} rows="14" placeholder="모험의 기록을 남겨 주세요"></textarea></label><div class="form-actions"><a class="text-link" href={`#board/${writeBoard.slug}`}>취소</a><button class="primary-btn" type="submit" disabled={postSaving}>{postSaving ? '저장 중…' : '게시글 등록'} <span>↗</span></button></div></form></section>
    {:else if isMyPage}
      <section class="mypage panel"><div class="page-heading"><p class="eyebrow">ADVENTURER PROFILE</p><h1>마이페이지</h1><p>{profile?.nickname || '모험가'}님의 캐릭터와 소지품을 관리하는 공간입니다.</p></div>{#if characterError}<div class="error-box">캐릭터 테이블을 확인해 주세요: {characterError}</div>{/if}{#if characterLoading}<div class="empty-state"><span>◌</span><strong>캐릭터 정보를 불러오는 중이에요</strong></div>{:else}<form class="character-form" on:submit|preventDefault={saveCharacter}><div class="form-section"><div class="form-section-head"><div><p class="eyebrow">CHARACTER SHEET</p><h2>캐릭터 기본 정보</h2></div><span class="form-hint">{character ? '저장된 캐릭터 수정' : '새 캐릭터 등록'}</span></div><div class="field-grid"><label>이름<input bind:value={characterForm.name} placeholder="캐릭터 이름" /></label><label>역할명<input bind:value={characterForm.roleName} placeholder="역할명" /></label><label class="field-wide">특징<textarea bind:value={characterForm.roleTraits} rows="3" placeholder="역할의 특징, 성격, 전투 방식"></textarea></label><label>나이<input bind:value={characterForm.age} type="number" min="0" placeholder="예: 27" /></label><label>키 (cm)<input bind:value={characterForm.height} type="number" min="0" step="0.1" placeholder="예: 172" /></label><label>몸무게 (kg)<input bind:value={characterForm.weight} type="number" min="0" step="0.1" placeholder="예: 64" /></label></div></div><div class="form-section"><div class="form-section-head"><div><p class="eyebrow">INVENTORY</p><h2>인벤토리</h2></div><button class="subtle-btn" type="button" on:click={newInventoryItem}>+ 아이템 추가</button></div>{#if inventory.length}{#each inventory as item, index}<div class="repeat-row"><input bind:value={item.item_name} placeholder="아이템명" /><input bind:value={item.item_effect} placeholder="아이템 효과" /><input bind:value={item.quantity} type="number" min="1" placeholder="개수" /><select bind:value={item.grade}>{#each inventoryGrades as grade}<option>{grade}</option>{/each}</select><select bind:value={item.item_type}>{#each inventoryTypes as type}<option>{type}</option>{/each}</select><button class="icon-btn" type="button" on:click={() => removeInventory(index)} aria-label="아이템 삭제">×</button></div>{/each}{:else}<div class="repeat-empty">등록된 아이템이 없습니다. + 아이템 추가로 기록을 시작하세요.</div>{/if}</div><div class="form-section"><div class="form-section-head"><div><p class="eyebrow">CARDS</p><h2>보유 카드</h2></div><button class="subtle-btn" type="button" on:click={newCard}>+ 카드 추가</button></div>{#if cards.length}{#each cards as card, index}<div class="repeat-row card-row"><input bind:value={card.card_name} placeholder="카드명" /><input bind:value={card.card_effect} placeholder="카드 효과" /><input bind:value={card.quantity} type="number" min="1" placeholder="개수" /><select bind:value={card.grade}>{#each cardGrades as grade}<option>{grade}</option>{/each}</select><button class="icon-btn" type="button" on:click={() => removeCard(index)} aria-label="카드 삭제">×</button></div>{/each}{:else}<div class="repeat-empty">등록된 카드가 없습니다. + 카드 추가로 기록을 시작하세요.</div>{/if}</div><div class="form-actions"><button class="primary-btn" type="submit" disabled={characterSaving}>{characterSaving ? '저장 중…' : '캐릭터 시트 저장'} <span>↗</span></button></div></form>{/if}</section>
    {:else if isAdminPage && profileLoading}
      <section class="about-page panel"><p class="eyebrow">CHECKING ACCESS</p><h1>관리자 권한을<br /><em>확인하는 중입니다</em></h1><p class="about-lead">잠시만 기다려 주세요.</p></section>
    {:else if isAdminPage && isAdmin}
      <section class="admin-page panel"><div class="page-heading"><p class="eyebrow">CAMPAIGN ADMIN</p><h1>관리자 마이페이지</h1><p>플레이어 계정을 발급하고 전체 캐릭터 시트를 확인합니다.</p></div><div class="admin-layout"><section class="admin-card"><div class="form-section-head"><div><p class="eyebrow">ADVENTURER ACCOUNTS</p><h2>플레이어 계정 · 캐릭터 생성</h2></div></div><form class="editor-form" on:submit|preventDefault={createPlayerAccount}><div class="field-grid"><label>로그인 아이디<input bind:value={adminForm.loginId} placeholder="플레이어 아이디" /></label><label>초기 비밀번호<input bind:value={adminForm.password} type="password" minlength="8" placeholder="8자 이상" /></label><label>표시 이름<input bind:value={adminForm.nickname} placeholder="플레이어 이름" /></label><label>캐릭터 이름<input bind:value={adminForm.character.name} placeholder="캐릭터 이름" /></label><label>역할명<input bind:value={adminForm.character.roleName} placeholder="역할명" /></label><label>나이<input bind:value={adminForm.character.age} type="number" min="0" placeholder="나이" /></label><label class="field-wide">역할 특징<textarea bind:value={adminForm.character.roleTraits} rows="3" placeholder="역할의 특징"></textarea></label><label>키 (cm)<input bind:value={adminForm.character.height} type="number" min="0" step="0.1" /></label><label>몸무게 (kg)<input bind:value={adminForm.character.weight} type="number" min="0" step="0.1" /></label></div><button class="primary-btn" type="submit" disabled={accountSaving}>{accountSaving ? '생성 중…' : '계정과 캐릭터 생성'} <span>↗</span></button></form><p class="form-note">로그인 아이디는 이메일 형식이나 영문·숫자 형식으로 제한하지 않습니다. 비밀번호만 8자 이상 입력해 주세요.</p></section><section class="admin-card"><div class="form-section-head"><div><p class="eyebrow">CHARACTER ROSTER</p><h2>전체 캐릭터 목록</h2></div></div>{#if adminLoading}<div class="repeat-empty">목록을 불러오는 중이에요.</div>{:else if adminCharacters.length}{#each adminCharacters as item}<div class="character-list-item"><span class="avatar mint">{item.name.slice(0, 1)}</span><div><strong>{item.name}</strong><p>{item.nickname} · {item.role_name || '역할 미등록'}</p></div><span class="character-age">{item.age ? `${item.age}세` : '나이 미등록'}</span></div>{/each}{:else}<div class="repeat-empty">아직 등록된 캐릭터가 없습니다.</div>{/if}</section></div></section>
    {:else if isAdminPage}
      <section class="about-page panel"><p class="eyebrow">ACCESS RESTRICTED</p><h1>관리자 권한이<br /><em>필요합니다</em></h1><p class="about-lead">이 페이지는 캠페인 관리자만 이용할 수 있습니다.</p><a class="primary-btn about-button" href={user ? '#mypage' : '#home'}>{user ? '마이페이지로 돌아가기' : '홈으로 돌아가기'} <span>→</span></a></section>
     {/if}
     {/key}
   </main>
  <footer class="footer"><div class="footer-brand"><span class="brand-mark">od</span><span>open door</span></div><span>장기 TRPG 캠페인을 위한 세계관 기록소</span><span>© 2026 OPEN DOOR</span></footer>
</div>

{#if notice}<div class="toast" role="status"><span>✓</span>{notice}</div>{/if}
{#if showLogin && !user}<div class="backdrop" role="presentation" on:click={() => (showLogin = false)}><dialog open class="modal" aria-labelledby="login-title" on:click|stopPropagation><button class="close" on:click={() => (showLogin = false)} aria-label="닫기">×</button><div class="modal-mark">od</div><p class="eyebrow">ADVENTURER ACCESS</p><h2 id="login-title">모험가 계정으로<br />입장하기</h2><p class="modal-intro">관리자에게 발급받은 아이디와 비밀번호로<br />캠페인 기록소에 입장할 수 있습니다.</p><form class="login-form" on:submit|preventDefault={handleLogin}><label>아이디<input bind:value={loginId} type="text" placeholder="adventurer_01" autocomplete="username" /></label><label>비밀번호<input bind:value={loginPassword} type="password" placeholder="••••••••" autocomplete="current-password" /></label><button class="submit" type="submit">입장하기 <span>→</span></button></form><p class="modal-note">계정 발급 및 변경은 캠페인 관리자에게 문의해 주세요.</p></dialog></div>{/if}
