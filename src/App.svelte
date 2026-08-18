<script>
  import { onMount, afterUpdate } from 'svelte';
  import { supabase, supabaseConfig } from './supabaseClient';
  import { marked } from 'marked';
  import DOMPurify from 'dompurify';
  import Editor from '@toast-ui/editor';
  import '@toast-ui/editor/dist/toastui-editor.css';

  const fallbackCategories = [
    { name: '전체', slug: 'all', count: 0, description: '모든 게시글 모아보기' },
    { name: '공지사항', slug: 'notices', count: 0, description: '운영 안내 · 업데이트 · 이벤트' },
    { name: '세계관 자료실', slug: 'world', count: 0, description: '세계관 · 대륙 · 국가' },
    { name: '시스템 게시판', slug: 'system', count: 0, description: '규칙 · 전투 · 판정 · 캠페인 시스템' },
    { name: 'NPC 게시판', slug: 'npc', count: 0, description: 'NPC 초상화 · 성격 · 관계 · 특징' },
    { name: '대륙 게시판', slug: 'continents', count: 0, description: '대륙 · 지형 · 도시 · 주요 장소' },
    { name: '유저 게시판', slug: 'users', count: 0, description: '질문 · 잡담 · 파티 모집' },
    { name: '세션 로그', slug: 'sessions', count: 0, description: '플레이 기록 · 후기 · 다음화 예고' },
    { name: 'BGM 게시판', slug: 'bgm', count: 0, description: '맵 · 캐릭터 · 장면별 배경음악' }
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
  let adminProfileForm = { nickname: '', newPassword: '', confirmPassword: '' };
  let adminProfileImageFile = null;
  let adminProfileImagePreview = '';
  let adminProfileSaving = false;
  let authReady = false;
  let isAdmin = false;
  let adminLoading = false;
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
  let detailHtml = '';
  let detailRequestId = 0;
  let detailLoading = false;
  let postSaving = false;
  let characterLoading = false;
  let characterSaving = false;
  let characterError = '';
  let character = null;
  let profileSection = 'basic';
  let extraRecords = [];
  let extraRecordForm = { title: '', content: '' };
  let extraRecordSaving = false;
  let extraRecordCharacterId = null;
  let relationships = [];
  let relationshipForm = { name: '', npcPostId: '', memo: '' };
  let relationshipSaving = false;
  let npcOptions = [];
  let bgmOptions = [];
  let sessionEntries = [];
  let sessionParticipants = [];
  let sessionBgmIds = [];
  let selectedInventoryItem = null;
  let profileImageFile = null;
  let profileImagePreview = '';
  let inventory = [];
  let cards = [];
  let adminCharacters = [];
  let adminSelectedCharacter = null;
  let adminCharacterForm = { name: '', roleName: '', roleTraits: '', age: '', height: '', weight: '', money: 0, level: 1, hp: 0, maxHp: 0, mp: 0, maxMp: 0, attack: 0, defense: 0, combatNotes: '' };
  let adminCharacterSaving = false;
  let adminInventory = [];
  let adminCards = [];
  let itemCatalog = [];
  let itemCatalogLoading = false;
  let itemCatalogError = '';
  let itemForm = { id: null, name: '', effect: '', grade: '일반', item_type: '기타', icon_url: '' };
  let itemSaving = false;
  let itemSearch = '';
  let inventorySearch = '';
  let adminDetailLoading = false;
  let characterRequestId = 0;
  let accountSaving = false;
  let detailComments = [];
  let commentText = '';
  let commentReplyTo = null;
  let commentSaving = false;
  let detailLiked = false;
  let detailLikeSaving = false;
  let noticeTypeFilter = 'all';
  let sessionPlayerFilter = '';
  let sessionPlayerFilterOptions = [];
  let currentPage = 1;
  const pageSize = 10;

  let postForm = { title: '', content: '', postType: 'notice', npcName: '', npcAge: '', npcGender: '', npcHeight: '', npcRace: '', npcRole: '', npcTraits: '', npcAffiliation: '', npcPersonality: '', bgmCategory: 'map', bgmUrl: '', bgmFile: null, imageFile: null };
  let editingPostId = null;
  let editingPostAuthorId = null;
  let editLoading = false;
  let editRequestId = 0;
  let npcImagePreview = '';
  let richEditorElement;
  let richEditor;
  let richEditorSyncTimer;
  let richEditorSyncing = false;
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
  $: filteredPageCount = Math.max(1, Math.ceil(filteredPosts.length / pageSize));
  $: pagedFilteredPosts = filteredPosts.slice((currentPage - 1) * pageSize, currentPage * pageSize);
  $: isBoardPage = currentRoute.startsWith('board/');
  $: isPostPage = currentRoute.startsWith('post/');
  $: isWritePage = currentRoute.startsWith('write/');
  $: isEditPage = currentRoute.startsWith('edit/');
  $: isMyPage = currentRoute === 'mypage';
  $: isAdminPage = currentRoute === 'admin';
  $: isAdminItemsPage = currentRoute === 'admin-items';
  $: isAdminMypage = currentRoute === 'admin-mypage';
  $: isAdminCharacterPage = currentRoute.startsWith('admin-character/');
  $: currentBoard = categories.find((board) => board.slug === currentRoute.replace('board/', '')) || categories[0];
  $: writeBoard = categories.find((board) => board.slug === writeBoardSlug) || categories.find((board) => board.slug === 'users') || categories[0];
  $: sessionPlayerFilterOptions = buildSessionPlayerFilterOptions(posts, adminCharacters);
  $: filteredItemCatalog = filterItemCatalog(itemCatalog, itemSearch);
  $: inventorySearchResults = inventorySearch.trim() ? filterItemCatalog(itemCatalog, inventorySearch).slice(0, 8) : [];
  $: boardPagePosts = posts
    .filter((post) => currentBoard.slug === 'all' || post.category === currentBoard.name)
    .filter((post) => `${post.title} ${post.excerpt} ${post.author}`.toLowerCase().includes(searchTerm.toLowerCase().trim()))
    .filter((post) => currentBoard.slug !== 'notices' || noticeTypeFilter === 'all' || post.postType === noticeTypeFilter)
    .filter((post) => currentBoard.slug !== 'sessions' || sessionPostHasPlayer(post, sessionPlayerFilter))
    .sort((a, b) => sortBy === 'popular' ? b.views - a.views : posts.indexOf(a) - posts.indexOf(b));
  $: boardPageCount = Math.max(1, Math.ceil(boardPagePosts.length / pageSize));
  $: pagedBoardPosts = boardPagePosts.slice((currentPage - 1) * pageSize, currentPage * pageSize);

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

  const basePostSelect = 'id, board_slug, title, content, excerpt, status, views, created_at, author_id, profiles(nickname, avatar_url), post_comments(count), post_likes(count)';
  const extendedPostSelect = 'id, board_slug, title, content, excerpt, status, views, created_at, author_id, image_url, youtube_url, bgm_url, bgm_category, post_type, npc_name, npc_age, npc_gender, npc_height, npc_race, npc_role, npc_traits, npc_affiliation, npc_personality, profiles(nickname, avatar_url), post_comments(count), post_likes(count)';
  const bgmPostSelect = 'id, board_slug, title, content, excerpt, status, views, created_at, author_id, bgm_url, bgm_category, profiles(nickname, avatar_url), post_comments(count), post_likes(count)';

  function readEmbeddedNpcData(content = '') {
    const match = content.match(/^<!--OPEN_DOOR_NPC:([A-Za-z0-9+/=]+)-->/);
    if (!match) return { content };
    try {
      const data = JSON.parse(decodeURIComponent(escape(atob(match[1]))));
      return { ...data, content: content.slice(match[0].length) };
    } catch { return { content }; }
  }

  async function loadPostsQuery(queryBuilder) {
    const extended = await queryBuilder(extendedPostSelect);
    if (!extended.error) return extended;
    const withBgm = await queryBuilder(bgmPostSelect);
    if (!withBgm.error) return withBgm;
    return queryBuilder(basePostSelect);
  }

  function formatPost(post, boardMap) {
    const sessionData = post.board_slug === 'sessions' ? readEmbeddedSessionData(post.content || '') : { content: post.content || '', entries: [] };
    const bgmData = post.board_slug === 'bgm' ? readEmbeddedBgmData(sessionData.content) : { content: sessionData.content };
    const embedded = readEmbeddedNpcData(bgmData.content);
    post = { ...post, content: embedded.content, image_url: post.image_url || embedded.image_url, bgm_url: post.bgm_url || bgmData.bgm_url, bgm_category: post.bgm_category || bgmData.bgm_category, npc_name: post.npc_name || embedded.npc_name, npc_age: post.npc_age ?? embedded.npc_age, npc_gender: post.npc_gender || embedded.npc_gender, npc_height: post.npc_height ?? embedded.npc_height, npc_race: post.npc_race || embedded.npc_race, npc_role: post.npc_role || embedded.npc_role, npc_traits: post.npc_traits || embedded.npc_traits, npc_affiliation: post.npc_affiliation || embedded.npc_affiliation, npc_personality: post.npc_personality || embedded.npc_personality };
    const profileData = Array.isArray(post.profiles) ? post.profiles[0] : post.profiles;
    const commentRelation = post.post_comments || post.comments;
    const likeRelation = post.post_likes || post.likes;
    const commentCount = Array.isArray(commentRelation) ? commentRelation[0]?.count || 0 : 0;
    const likeCount = Array.isArray(likeRelation) ? likeRelation[0]?.count || 0 : 0;
    const date = formatDate(post.created_at);
    const nickname = profileData?.nickname || '모험가';
    return {
      id: post.id, boardSlug: post.board_slug, category: boardMap.get(post.board_slug)?.name || post.board_slug,
      title: post.board_slug === 'npc' && post.npc_role && post.npc_name ? `[${post.npc_role}] ${post.npc_name}` : post.title, content: post.content || '',
      excerpt: post.excerpt || post.content?.replace(/\s+/g, ' ').slice(0, 140) || '아직 요약이 등록되지 않은 게시글입니다.',
      author: nickname, authorId: post.author_id, date: date.date, time: date.time,
      views: post.views || 0, comments: commentCount, likes: likeCount, avatar: nickname.slice(0, 1).toUpperCase(), avatarUrl: profileData?.avatar_url || '',
      color: ['lavender', 'mint', 'peach', 'yellow', 'blue'][nickname.charCodeAt(0) % 5],
      imageUrl: post.image_url || '', npcName: post.npc_name || '', npcAge: post.npc_age ?? '', npcGender: post.npc_gender || '',
      npcHeight: post.npc_height ?? '', npcRace: post.npc_race || '', npcRole: post.npc_role || '', npcTraits: post.npc_traits || '',
      npcAffiliation: post.npc_affiliation || '', npcPersonality: post.npc_personality || '', postType: post.post_type || 'notice', youtubeUrl: post.youtube_url || '', bgmUrl: post.bgm_url || '', bgmCategory: post.bgm_category || 'map', sessionEntries: sessionData.entries, sessionParticipants: Array.isArray(sessionData.participants) ? sessionData.participants : [], sessionBgms: Array.isArray(sessionData.bgms) ? sessionData.bgms : []
    };
  }

  function buildSessionPlayerFilterOptions(postList = [], playerList = []) {
    const players = new Map();
    playerList.forEach((player) => {
      if (!player.id) return;
      players.set(`character:${player.id}`, { value: `character:${player.id}`, label: player.nickname ? `${player.nickname} · ${player.name}` : player.name });
    });
    postList.filter((post) => post.boardSlug === 'sessions').forEach((post) => {
      (post.sessionParticipants || []).forEach((participant) => {
        if (participant.participantType === 'npc' || !participant.name) return;
        if (participant.participantType === 'character' && participant.participantId) {
          if (!players.has(`character:${participant.participantId}`)) players.set(`character:${participant.participantId}`, { value: `character:${participant.participantId}`, label: participant.name || '플레이어' });
          return;
        }
        players.set(`name:${participant.name}`, { value: `name:${participant.name}`, label: participant.name });
      });
    });
    return [...players.values()].sort((left, right) => left.label.localeCompare(right.label, 'ko'));
  }

  function sessionPostHasPlayer(post, filterValue) {
    if (!filterValue) return true;
    if (filterValue.startsWith('character:')) {
      const playerId = filterValue.slice('character:'.length);
      return (post.sessionParticipants || []).some((participant) => participant.participantType === 'character' && participant.participantId === playerId);
    }
    const playerName = filterValue.slice('name:'.length);
    return (post.sessionParticipants || []).some((participant) => participant.participantType !== 'npc' && participant.name === playerName);
  }

  function renderPostContent(content = '') {
    const markdown = normalizeRichEditorMarkdown(content);
    return DOMPurify.sanitize(marked.parse(markdown));
  }

  function readEmbeddedBgmData(content = '') {
    const match = content.match(/^<!--OPEN_DOOR_BGM:([A-Za-z0-9+/=]+)-->/);
    if (!match) return { content };
    try {
      const data = JSON.parse(decodeURIComponent(escape(atob(match[1]))));
      return { ...data, content: content.slice(match[0].length) };
    } catch { return { content }; }
  }

  function escapeSessionHtml(value = '') {
    return String(value).replace(/[&<>"']/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character]));
  }

  function renderBgmContent(post) {
    const category = { map: 'MAP BGM', character: 'CHARACTER BGM', scene: 'SCENE BGM', etc: 'ETC' }[post.bgmCategory] || 'BGM';
    const player = post.bgmUrl ? `<div class="bgm-detail-player"><span>${category}</span><audio controls preload="metadata" src="${escapeSessionHtml(post.bgmUrl)}"></audio></div>` : '';
    return `${player}${renderPostContent(post.content)}`;
  }

  function renderSessionEntries(entries = [], participants = [], bgms = []) {
    const participantHtml = participants.length ? `<section class="session-log-participants"><strong>세션 참여자</strong><div>${participants.map((participant) => `<span>${escapeSessionHtml(participant.name || '이름 없음')}</span>`).join('')}</div></section>` : '';
    const bgmHtml = bgms.length ? `<section class="session-log-bgms"><strong>세션 BGM</strong><div>${bgms.map((bgm) => `<article><span>${escapeSessionHtml(bgm.title || 'BGM')} · ${escapeSessionHtml(({ map: '맵', character: '캐릭터', scene: '장면', etc: '기타' }[bgm.category] || 'BGM'))}</span><audio controls preload="metadata" src="${escapeSessionHtml(bgm.url || '')}"></audio></article>`).join('')}</div></section>` : '';
    const html = entries.map((entry) => {
      if (entry.type === 'image') return `<figure class="session-log-image"><img src="${escapeSessionHtml(entry.imageUrl || '')}" alt="세션 장면" />${entry.caption ? `<figcaption>${escapeSessionHtml(entry.caption)}</figcaption>` : ''}</figure>`;
      if (entry.type === 'dialogue') {
        const speakerName = entry.speakerName || '???';
        const speakerImage = sessionEntrySpeakerAvatar(entry);
        const avatar = speakerImage
          ? `<img class="session-dialogue-avatar-image" src="${escapeSessionHtml(speakerImage)}" alt="${escapeSessionHtml(speakerName)} 사진" />`
          : `<span class="session-dialogue-avatar-placeholder">${escapeSessionHtml(speakerName.slice(0, 1))}</span>`;
        return `<div class="session-log-dialogue"><div class="session-dialogue-avatar">${avatar}</div><div class="session-dialogue-copy"><strong>${escapeSessionHtml(speakerName)}</strong><p>&quot;${escapeSessionHtml(entry.text || '')}&quot;</p></div></div>`;
      }
      return `<div class="session-log-narration">${entry.actorName ? `<small>${escapeSessionHtml(entry.actorName)}</small>` : ''}<p>${escapeSessionHtml(entry.text || '')}</p></div>`;
    }).join('');
    return DOMPurify.sanitize(`<div class="session-log-body">${participantHtml}${bgmHtml}${html}</div>`);
  }

  function normalizeRichEditorMarkdown(content = '') {
    return content.replace(/\\(\*{1,2}|_{1,2})/g, '$1');
  }

  function hasInlineMarkdownFormat(content = '') {
    return /(\*{1,2}|_{1,2})\S[\s\S]*?\1/.test(content);
  }

  async function loadDatabase() {
    if (!supabase || !supabaseConfig.url || !supabaseConfig.hasPublishableKey) {
      dbStatus = 'missing'; dbError = 'Supabase 환경변수가 없습니다.'; return;
    }
    try {
      const [boardsResult, postsResult] = await Promise.all([
        supabase.from('boards').select('slug, name, description, sort_order, is_public').eq('is_public', true).order('sort_order', { ascending: true }),
        loadPostsQuery((columns) => supabase.from('posts').select(columns).eq('status', 'published').order('created_at', { ascending: false }).limit(100))
      ]);
      if (boardsResult.error) throw new Error(`게시판 조회 실패: ${boardsResult.error.message}`);
      if (postsResult.error) throw new Error(`게시글 조회 실패: ${postsResult.error.message}`);
      const remoteBoards = (boardsResult.data || []).filter((board) => board.slug !== 'characters');
      const remoteSlugs = new Set(remoteBoards.map((board) => board.slug));
      const missingBoards = fallbackCategories.slice(1).filter((board) => !remoteSlugs.has(board.slug));
      const visibleBoards = [...remoteBoards, ...missingBoards];
      const boardMap = new Map(visibleBoards.map((board) => [board.slug, board]));
      const remotePosts = postsResult.data || [];
      const counts = remotePosts.reduce((map, post) => map.set(post.board_slug, (map.get(post.board_slug) || 0) + 1), new Map());
      categories = [{ name: '전체', slug: 'all', count: remotePosts.length, description: '모든 게시글 모아보기' }, ...visibleBoards.map((board) => ({ ...board, count: counts.get(board.slug) || 0 }))];
      posts = await hydratePostAvatars(remotePosts.map((post) => formatPost(post, boardMap)));
      npcOptions = posts.filter((post) => post.boardSlug === 'npc');
      bgmOptions = posts.filter((post) => post.boardSlug === 'bgm' && post.bgmUrl);
      notices = posts.filter((post) => post.boardSlug === 'notices').slice(0, 3).map((post, index) => ({ tag: { patch: '패치노트', event: '이벤트', notice: '공지사항' }[post.postType] || '공지', title: post.title, meta: `${post.date} ${post.time}`, body: post.excerpt, tone: ['gold', 'blue', 'pink'][index] || 'gold' }));
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
      if (isAdmin) {
        adminProfileForm = { ...adminProfileForm, nickname: data?.nickname || '' };
        adminProfileImagePreview = data?.avatar_url || '';
        if (currentRoute === 'admin-items' || currentRoute.startsWith('admin-character/')) loadItemCatalog();
        if (currentRoute === 'mypage') navigateTo('#admin-mypage');
      }
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
    authReady = true;
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
    extraRecords = [];
    relationships = [];
    extraRecordCharacterId = null;
    inventory = [];
    cards = [];
    showNotice('로그아웃되었습니다.');
    navigateTo('#home');
    if (supabase) await supabase.auth.signOut();
  }

  async function saveAdminProfile() {
    if (!isAdmin || !supabase || !user) return;
    const nickname = adminProfileForm.nickname.trim();
    const newPassword = adminProfileForm.newPassword;
    if (!nickname) return showNotice('표시명을 입력해 주세요.');
    if (newPassword && newPassword.length < 8) return showNotice('비밀번호는 8자 이상 입력해 주세요.');
    if (newPassword !== adminProfileForm.confirmPassword) return showNotice('새 비밀번호가 일치하지 않습니다.');
    adminProfileSaving = true;
    let avatarUrl = profile?.avatar_url || null;
    if (adminProfileImageFile) {
      try { avatarUrl = await imageFileToDataUrl(adminProfileImageFile); } catch (error) { adminProfileSaving = false; return showNotice(error instanceof Error ? error.message : '프로필 이미지를 처리하지 못했습니다.'); }
    }
    const profileResult = await supabase.from('profiles').update({ nickname, avatar_url: avatarUrl }).eq('id', user.id);
    if (profileResult.error) { adminProfileSaving = false; return showNotice(`표시명 변경 실패: ${profileResult.error.message}`); }
    if (newPassword) {
      const passwordResult = await supabase.auth.updateUser({ password: newPassword });
      if (passwordResult.error) { adminProfileSaving = false; return showNotice(`비밀번호 변경 실패: ${passwordResult.error.message}`); }
    }
    profile = { ...profile, nickname, avatar_url: avatarUrl };
    adminProfileImageFile = null;
    adminProfileForm = { nickname, newPassword: '', confirmPassword: '' };
    adminProfileSaving = false;
    showNotice('관리자 계정 정보를 저장했습니다.');
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
    currentRoute = nextRoute; activeCategory = '전체'; searchTerm = ''; sortBy = 'latest'; noticeTypeFilter = 'all'; sessionPlayerFilter = ''; currentPage = 1; detailPost = null; detailHtml = '';
    if (nextRoute === 'admin') { adminSelectedCharacter = null; adminInventory = []; adminCards = []; }
    if (nextRoute === 'admin-items') { resetItemForm(); itemSearch = ''; }
    if (nextRoute.startsWith('write/')) { writeBoardSlug = nextRoute.replace('write/', '') || 'users'; editingPostId = null; editLoading = false; }
    if (!nextRoute.startsWith('edit/')) editLoading = false;
    if (nextRoute.startsWith('edit/')) {
      const editParts = nextRoute.replace(/^edit\/?/, '').split('/').filter(Boolean);
      const editBoardSlug = editParts.length > 1 ? editParts.shift() : '';
      const editPostId = editParts.join('/');
      if (editBoardSlug) writeBoardSlug = editBoardSlug;
      loadPostForEdit(editPostId, editBoardSlug);
    }
    window.scrollTo({ top: 0, behavior: 'instant' });
    if (nextRoute.startsWith('post/')) loadPostDetail(nextRoute.replace('post/', ''));
    if (nextRoute.startsWith('admin-character/')) loadAdminCharacterDetail(nextRoute.replace('admin-character/', ''));
    if (nextRoute === 'mypage' || nextRoute === 'admin' || nextRoute === 'admin-mypage') loadCharacterData();
    if (nextRoute === 'admin-items' || nextRoute.startsWith('admin-character/')) loadItemCatalog();
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
    const requestId = ++detailRequestId;
    detailLoading = true;
    detailComments = [];
    commentText = '';
    detailLiked = false;
    const { data, error } = await loadPostsQuery((columns) => supabase.from('posts').select(columns).eq('id', id).maybeSingle());
    if (requestId !== detailRequestId || currentRoute !== `post/${id}`) return;
    if (error || !data) { detailLoading = false; return showNotice('게시글을 불러오지 못했습니다.'); }
    const boardMap = new Map(categories.map((board) => [board.slug, board]));
    detailPost = (await hydratePostAvatars([formatPost(data, boardMap)]))[0];
    detailHtml = detailPost.boardSlug === 'sessions' && (detailPost.sessionEntries.length || detailPost.sessionParticipants.length || detailPost.sessionBgms.length) ? renderSessionEntries(detailPost.sessionEntries, detailPost.sessionParticipants, detailPost.sessionBgms) : detailPost.boardSlug === 'bgm' ? renderBgmContent(detailPost) : renderPostContent(detailPost.content);
    detailLoading = false;
    await loadEngagement(id);
    if (requestId === detailRequestId && currentRoute === `post/${id}`) {
      await supabase.rpc('increment_post_views', { post_id_input: id });
    }
  }

  async function loadEngagement(postId) {
    if (!supabase || !postId) return;
    const commentsResult = await supabase.from('post_comments').select('id, content, created_at, author_id, parent_id').eq('post_id', postId).order('created_at', { ascending: true });
    if (!commentsResult.error) {
      const rows = commentsResult.data || [];
      const authorIds = [...new Set(rows.map((comment) => comment.author_id).filter(Boolean))];
      const profilesResult = authorIds.length ? await supabase.from('profiles').select('id, nickname, avatar_url').in('id', authorIds) : { data: [] };
      const authors = new Map((profilesResult.data || []).map((item) => [item.id, item]));
      detailComments = rows.map((comment) => ({ ...comment, nickname: authors.get(comment.author_id)?.nickname || '모험가', avatarUrl: authors.get(comment.author_id)?.avatar_url || '' }));
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
    navigateTo(isAdmin ? '#admin-mypage' : '#mypage');
  }
  function startWriting(slug = currentBoard.slug) {
    const boardSlug = slug === 'all' ? 'users' : slug;
    if (!requireLogin()) return;
    if (!isAdmin && boardSlug !== 'users') return showNotice('이 게시판은 관리자만 작성할 수 있어요.');
    resetPostForm();
    navigateTo(`#write/${boardSlug}`);
  }

  async function syncCharacterAvatarToProfile(avatarUrl, announceFailure = false) {
    if (!supabase || !user || isAdmin) return;
    const normalizedAvatarUrl = avatarUrl || null;
    const updateLocalAvatars = () => {
      profile = { ...profile, avatar_url: normalizedAvatarUrl };
      posts = posts.map((post) => post.authorId === user.id ? { ...post, avatarUrl: normalizedAvatarUrl || post.avatarUrl || '' } : post);
      if (detailPost?.authorId === user.id) detailPost = { ...detailPost, avatarUrl: normalizedAvatarUrl || detailPost.avatarUrl || '' };
      detailComments = detailComments.map((comment) => comment.author_id === user.id ? { ...comment, avatarUrl: normalizedAvatarUrl || comment.avatarUrl || '' } : comment);
    };
    if (profile?.avatar_url === normalizedAvatarUrl) {
      updateLocalAvatars();
      return true;
    }
    const { error } = await supabase.from('profiles').update({ avatar_url: normalizedAvatarUrl }).eq('id', user.id);
    if (error) {
      if (announceFailure) showNotice(`캐릭터 사진은 저장했지만 프로필 사진 반영에 실패했습니다: ${error.message}`);
      return false;
    }
    updateLocalAvatars();
    return true;
  }

  function createSessionEntry(type) {
    const id = crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`;
    if (type === 'image') return { id, type, imageUrl: '', imageFile: null, caption: '' };
    if (type === 'dialogue') return { id, type, speakerType: 'anonymous', speakerId: '', speakerName: '', text: '' };
    return { id, type: 'narration', actorType: 'none', actorId: '', actorName: '', text: '' };
  }

  function createSessionParticipant() {
    const id = crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`;
    return { id, participantType: 'character', participantId: '', participantName: '' };
  }

  function addSessionParticipant() {
    sessionParticipants = [...sessionParticipants, createSessionParticipant()];
  }

  function removeSessionParticipant(index) {
    sessionParticipants = sessionParticipants.filter((_, participantIndex) => participantIndex !== index);
  }

  function sessionParticipantValue(participant) {
    return `${participant.participantType || 'custom'}:${participant.participantId || ''}`;
  }

  function setSessionParticipant(participant, value) {
    const [participantType, participantId = ''] = value.split(':');
    participant.participantType = participantType;
    participant.participantId = participantId;
    participant.participantName = '';
    sessionParticipants = [...sessionParticipants];
  }

  function sessionParticipantName(participant) {
    if (participant.participantName) return participant.participantName;
    if (participant.participantType === 'character') return sessionCharacterName(participant.participantId) || '캐릭터';
    if (participant.participantType === 'npc') return sessionNpcName(participant.participantId) || 'NPC';
    return '이름 없음';
  }

  function prepareSessionParticipants() {
    return sessionParticipants.map((participant) => {
      if (participant.participantType === 'custom' && !participant.participantName?.trim()) throw new Error('직접 입력한 참여자의 이름을 입력해 주세요.');
      return { participantType: participant.participantType || 'custom', participantId: participant.participantId || '', name: sessionParticipantName(participant) };
    });
  }

  function prepareSessionBgms() {
    return sessionBgmIds.map((id) => bgmOptions.find((bgm) => bgm.id === id)).filter(Boolean).map((bgm) => ({ id: bgm.id, title: bgm.title, url: bgm.bgmUrl, category: bgm.bgmCategory }));
  }

  function addSessionBgm() {
    if (!bgmOptions.length) return showNotice('먼저 BGM 게시판에 BGM을 등록해 주세요.');
    sessionBgmIds = [...sessionBgmIds, ''];
  }

  function setSessionBgm(index, value) {
    sessionBgmIds = sessionBgmIds.map((id, itemIndex) => itemIndex === index ? value : id);
  }

  function removeSessionBgm(index) {
    sessionBgmIds = sessionBgmIds.filter((_, itemIndex) => itemIndex !== index);
  }

  function addSessionEntry(type) {
    sessionEntries = [...sessionEntries, createSessionEntry(type)];
  }

  function removeSessionEntry(index) {
    const entry = sessionEntries[index];
    if (entry?.imageUrl?.startsWith('blob:')) URL.revokeObjectURL(entry.imageUrl);
    sessionEntries = sessionEntries.filter((_, entryIndex) => entryIndex !== index);
  }

  function moveSessionEntry(index, direction) {
    const targetIndex = index + direction;
    if (targetIndex < 0 || targetIndex >= sessionEntries.length) return;
    const nextEntries = [...sessionEntries];
    [nextEntries[index], nextEntries[targetIndex]] = [nextEntries[targetIndex], nextEntries[index]];
    sessionEntries = nextEntries;
  }

  function setSessionSpeaker(entry, value) {
    const [speakerType, speakerId = ''] = value.split(':');
    entry.speakerType = speakerType;
    entry.speakerId = speakerId;
    entry.speakerName = speakerType === 'anonymous' ? '???' : '';
    sessionEntries = [...sessionEntries];
  }

  function setSessionActor(entry, value) {
    const [actorType, actorId = ''] = value.split(':');
    entry.actorType = actorType;
    entry.actorId = actorId;
    entry.actorName = '';
    sessionEntries = [...sessionEntries];
  }

  function sessionSpeakerValue(entry) {
    return `${entry.speakerType || 'anonymous'}:${entry.speakerId || ''}`;
  }

  function sessionActorValue(entry) {
    return `${entry.actorType || 'none'}:${entry.actorId || ''}`;
  }

  function handleSessionImageChange(event, index) {
    const file = event.currentTarget.files?.[0] || null;
    if (!file) return;
    if (!['image/png', 'image/jpeg', 'image/webp'].includes(file.type)) return showNotice('PNG, JPG, WEBP 이미지만 업로드할 수 있어요.');
    if (file.size > 5 * 1024 * 1024) return showNotice('이미지는 5MB 이하로 업로드해 주세요.');
    const entry = sessionEntries[index];
    if (entry?.imageUrl?.startsWith('blob:')) URL.revokeObjectURL(entry.imageUrl);
    entry.imageFile = file;
    entry.imageUrl = URL.createObjectURL(file);
    sessionEntries = [...sessionEntries];
  }

  function sessionCharacterName(id) {
    return adminCharacters.find((character) => character.id === id)?.name || '';
  }

  function sessionNpcName(id) {
    const npc = npcOptions.find((option) => option.id === id);
    return npc?.npcName || npc?.title || '';
  }

  function sessionCharacterAvatar(id) {
    return adminCharacters.find((character) => character.id === id)?.avatar_url || '';
  }

  function sessionNpcAvatar(id) {
    return npcOptions.find((option) => option.id === id)?.imageUrl || '';
  }

  function sessionSpeakerAvatar(entry) {
    if (entry.speakerType === 'character') return sessionCharacterAvatar(entry.speakerId);
    if (entry.speakerType === 'npc') return sessionNpcAvatar(entry.speakerId);
    return '';
  }

  function sessionEntrySpeakerAvatar(entry) {
    return entry.speakerImageUrl || sessionSpeakerAvatar(entry);
  }

  function sessionActorName(entry) {
    if (entry.actorName) return entry.actorName;
    if (entry.actorType === 'character') return sessionCharacterName(entry.actorId) || '캐릭터';
    if (entry.actorType === 'npc') return sessionNpcName(entry.actorId) || 'NPC';
    if (entry.actorType === 'custom') return entry.actorName || '이름 없음';
    return '';
  }

  function sessionSpeakerName(entry) {
    if (entry.speakerType === 'anonymous') return '???';
    if (entry.speakerName) return entry.speakerName;
    if (entry.speakerType === 'character') return sessionCharacterName(entry.speakerId) || '캐릭터';
    if (entry.speakerType === 'npc') return sessionNpcName(entry.speakerId) || 'NPC';
    return '이름 없음';
  }

  function encodeSessionContent(entries, participants, bgms) {
    const data = btoa(unescape(encodeURIComponent(JSON.stringify({ version: 1, participants, bgms, entries }))));
    return `<!--OPEN_DOOR_SESSION:${data}-->`;
  }

  async function prepareSessionEntries() {
    const prepared = [];
    for (const entry of sessionEntries) {
      if (entry.type === 'image') {
        let imageUrl = entry.imageUrl || '';
        if (entry.imageFile) imageUrl = await imageFileToDataUrl(entry.imageFile);
        if (!imageUrl) throw new Error('사진 항목에 이미지를 선택해 주세요.');
        prepared.push({ type: 'image', imageUrl, caption: entry.caption?.trim() || '' });
      } else if (entry.type === 'dialogue') {
        if (!entry.text?.trim()) throw new Error('대사 내용을 입력해 주세요.');
        prepared.push({ type: 'dialogue', speakerType: entry.speakerType || 'anonymous', speakerId: entry.speakerId || '', speakerName: sessionSpeakerName(entry), speakerImageUrl: sessionSpeakerAvatar(entry), text: entry.text.trim() });
      } else {
        if (!entry.text?.trim()) throw new Error('지문 내용을 입력해 주세요.');
        prepared.push({ type: 'narration', actorType: entry.actorType || 'none', actorId: entry.actorId || '', actorName: sessionActorName(entry), text: entry.text.trim() });
      }
    }
    return prepared;
  }

  function readEmbeddedSessionData(content = '') {
    const match = content.match(/^<!--OPEN_DOOR_SESSION:([A-Za-z0-9+/=]+)-->/);
    if (!match) return { content, entries: [] };
    try {
      const data = JSON.parse(decodeURIComponent(escape(atob(match[1]))));
      return { ...data, content: content.slice(match[0].length), entries: Array.isArray(data.entries) ? data.entries : [] };
    } catch { return { content, entries: [] }; }
  }

  function resetPostForm() {
    if (npcImagePreview?.startsWith('blob:')) URL.revokeObjectURL(npcImagePreview);
    sessionEntries.forEach((entry) => entry.imageUrl?.startsWith('blob:') && URL.revokeObjectURL(entry.imageUrl));
    npcImagePreview = '';
    sessionEntries = [];
    sessionParticipants = [];
    sessionBgmIds = [];
    postForm = { title: '', content: '', postType: 'notice', npcName: '', npcAge: '', npcGender: '', npcHeight: '', npcRace: '', npcRole: '', npcTraits: '', npcAffiliation: '', npcPersonality: '', bgmCategory: 'map', bgmUrl: '', bgmFile: null, imageFile: null };
    editingPostId = null;
    editingPostAuthorId = null;
    editLoading = false;
    if (richEditor) richEditor.setMarkdown('', false);
  }

  async function hydratePostAvatars(postList) {
    if (!supabase || !postList.length) return postList;
    const ids = [...new Set(postList.map((post) => post.authorId).filter(Boolean))];
    if (!ids.length) return postList;
    const [{ data: profileRows }, { data: characterRows }] = await Promise.all([
      supabase.from('profiles').select('id, avatar_url').in('id', ids),
      supabase.from('characters').select('owner_id, avatar_url').in('owner_id', ids)
    ]);
    const profileAvatars = new Map((profileRows || []).map((item) => [item.id, item.avatar_url || '']));
    const characterAvatars = new Map((characterRows || []).map((item) => [item.owner_id, item.avatar_url || '']).filter(([, url]) => url));
    return postList.map((post) => ({ ...post, avatarUrl: profileAvatars.get(post.authorId) || characterAvatars.get(post.authorId) || post.avatarUrl || '' }));
  }

  async function startEditing(post) {
    if (!requireLogin() || !supabase || post.authorId !== user.id) return showNotice('게시글 작성자만 수정할 수 있어요.');
    navigateTo(`#edit/${post.boardSlug}/${post.id}`);
  }

  async function loadPostForEdit(id, routeBoardSlug = '') {
    if (!supabase || !id || editingPostId === id) return;
    const requestId = ++editRequestId;
    if (routeBoardSlug) writeBoardSlug = routeBoardSlug;
    editingPostId = id;
    editLoading = true;
    const { data, error } = await loadPostsQuery((columns) => supabase.from('posts').select(columns).eq('id', id).maybeSingle());
    if (requestId !== editRequestId || !currentRoute.startsWith('edit/')) return;
    if (error || !data) { editLoading = false; editingPostId = null; return showNotice('수정할 게시글을 불러오지 못했습니다.'); }
    const post = formatPost(data, new Map(categories.map((board) => [board.slug, board])));
    if (!user || post.authorId !== user.id) { editLoading = false; editingPostId = null; return navigateTo(`#post/${id}`); }
    writeBoardSlug = post.boardSlug;
    editingPostAuthorId = post.authorId;
    postForm = { title: post.title, content: post.content, postType: post.postType || 'notice', npcName: post.npcName, npcAge: post.npcAge, npcGender: post.npcGender, npcHeight: post.npcHeight, npcRace: post.npcRace, npcRole: post.npcRole, npcTraits: post.npcTraits, npcAffiliation: post.npcAffiliation, npcPersonality: post.npcPersonality, bgmCategory: post.bgmCategory || 'map', bgmUrl: post.bgmUrl || '', bgmFile: null, imageFile: null };
    sessionParticipants = post.boardSlug === 'sessions' ? post.sessionParticipants.map((participant) => ({ ...participant, participantName: participant.participantName || participant.name || '', id: participant.id || (crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`) })) : [];
    sessionBgmIds = post.boardSlug === 'sessions' ? post.sessionBgms.map((bgm) => bgm.id).filter(Boolean) : [];
    sessionEntries = post.boardSlug === 'sessions' && post.sessionEntries.length ? post.sessionEntries.map((entry) => ({ ...entry, id: entry.id || (crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`), imageFile: null })) : post.boardSlug === 'sessions' && post.content ? [{ ...createSessionEntry('narration'), text: post.content }] : [];
    npcImagePreview = post.imageUrl || '';
    if (richEditor) richEditor.setMarkdown(post.content || '', false);
    editLoading = false;
  }

  function handleNpcImageChange(event) {
    const file = event.currentTarget.files?.[0] || null;
    if (!file) return;
    if (!['image/png', 'image/jpeg', 'image/webp'].includes(file.type)) return showNotice('PNG, JPG, WEBP 이미지만 업로드할 수 있어요.');
    if (file.size > 5 * 1024 * 1024) return showNotice('이미지는 5MB 이하로 업로드해 주세요.');
    if (npcImagePreview) URL.revokeObjectURL(npcImagePreview);
    postForm = { ...postForm, imageFile: file };
    npcImagePreview = URL.createObjectURL(file);
  }

  function handleBgmFileChange(event) {
    const file = event.currentTarget.files?.[0] || null;
    if (!file) return;
    if (!['audio/mpeg', 'audio/ogg', 'audio/wav', 'audio/x-wav', 'audio/mp4', 'audio/aac'].includes(file.type)) return showNotice('MP3, OGG, WAV, M4A, AAC 오디오만 업로드할 수 있어요.');
    if (file.size > 30 * 1024 * 1024) return showNotice('BGM 파일은 30MB 이하로 업로드해 주세요.');
    postForm = { ...postForm, bgmFile: file };
  }

  async function uploadBgmFile(file) {
    if (!file || !supabase || !user) return '';
    const extension = file.name.split('.').pop()?.toLowerCase() || 'mp3';
    const path = `${user.id}/${crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`}.${extension}`;
    const { error } = await supabase.storage.from('bgm-audio').upload(path, file, { contentType: file.type, upsert: false });
    if (error) throw new Error(`BGM 업로드 실패: ${error.message}`);
    return supabase.storage.from('bgm-audio').getPublicUrl(path).data.publicUrl;
  }

  function setupRichEditor() {
    if (richEditor || !richEditorElement) return;
    richEditor = new Editor({
      el: richEditorElement,
      height: 'auto',
      initialEditType: 'wysiwyg',
      previewStyle: 'tab',
      autofocus: false,
      initialValue: postForm.content || '',
      placeholder: '내용을 자유롭게 작성해 주세요.',
      events: { change: handleRichEditorInput }
    });
  }

  function handleRichEditorInput() {
    if (!richEditor || richEditorSyncing) return;
    const markdown = richEditor.getMarkdown();
    postForm = { ...postForm, content: markdown };
    if (hasInlineMarkdownFormat(normalizeRichEditorMarkdown(markdown))) {
      clearTimeout(richEditorSyncTimer);
      richEditorSyncTimer = setTimeout(applyRichEditorMarkdownFormatting, 0);
    }
  }

  function applyRichEditorMarkdownFormatting() {
    if (!richEditor || richEditorSyncing) return;
    const markdown = richEditor.getMarkdown();
    const normalized = normalizeRichEditorMarkdown(markdown);
    if (normalized === markdown || !hasInlineMarkdownFormat(normalized)) return;
    richEditorSyncing = true;
    richEditor.setMarkdown(normalized, false);
    postForm = { ...postForm, content: normalized };
    richEditorSyncing = false;
  }

  afterUpdate(() => {
    if ((isWritePage || isEditPage) && writeBoardSlug === 'users') setupRichEditor();
    else if (richEditor) { richEditor.destroy(); richEditor = null; richEditorElement = null; }
    decorateCommunityUi();
  });

  function decorateCommunityUi() {
    const editorHost = document.querySelector('.rich-editor-host');
    if (editorHost && !editorHost.dataset.popupPositioning) {
      editorHost.dataset.popupPositioning = 'true';
      editorHost.addEventListener('click', () => setTimeout(positionEditorPopup, 0));
    }
    positionEditorPopup();
    const adminForm = document.querySelector('.admin-profile-form');
    if (adminForm && !adminForm.querySelector('[data-admin-profile-photo]')) {
      const field = document.createElement('label'); field.dataset.adminProfilePhoto = 'true'; field.textContent = '프로필 사진';
      const preview = document.createElement('span'); preview.className = 'admin-profile-photo-preview';
      const input = document.createElement('input'); input.type = 'file'; input.accept = 'image/png,image/jpeg,image/webp'; input.addEventListener('change', handleAdminProfileImageChange);
      field.append(preview, input); adminForm.insertBefore(field, adminForm.querySelector('.form-actions'));
    }
    const adminPreview = document.querySelector('.admin-profile-photo-preview');
    if (adminPreview) {
      adminPreview.innerHTML = adminProfileImagePreview ? `<img src="${adminProfileImagePreview}" alt="프로필 미리보기" />` : '<span>사진을 선택해 주세요</span>';
    }
    decorateAdminCharacterDetail();
    document.querySelectorAll('.detail-footer').forEach((element) => element.remove());
    const replaceAvatar = (element, url, alt = '') => {
      if (!element || !url || element.dataset.avatarUrl === url) return;
      const image = document.createElement('img');
      image.className = 'avatar avatar-image'; image.src = url; image.alt = alt; image.dataset.avatarUrl = url;
      element.replaceWith(image);
    };
    document.querySelectorAll('.post-row').forEach((row, index) => {
      const post = (isBoardPage ? pagedBoardPosts : pagedFilteredPosts)[index];
      replaceAvatar(row.querySelector('.avatar'), post?.avatarUrl, `${post?.author || ''} 프로필 사진`);
    });
    replaceAvatar(document.querySelector('.detail-author .avatar'), detailPost?.avatarUrl, `${detailPost?.author || ''} 프로필 사진`);
    detailComments.forEach((comment, index) => {
      const item = document.querySelectorAll('.comment-item')[index];
      replaceAvatar(item?.querySelector('.avatar'), comment.avatarUrl, `${comment.nickname} 프로필 사진`);
      if (item && comment.parent_id) item.classList.add('comment-reply');
      if (item && user && !item.querySelector('[data-reply-button]')) {
        const button = document.createElement('button'); button.className = 'subtle-btn'; button.type = 'button'; button.textContent = '답글'; button.dataset.replyButton = 'true';
        button.addEventListener('click', () => setReplyTarget(comment));
        item.querySelector('.comment-author')?.append(button);
      }
      if (item && !user) item.querySelectorAll('[data-reply-button]').forEach((button) => button.remove());
    });
    const author = document.querySelector('.detail-author');
    if (author && detailPost && user && user.id === detailPost.authorId && !author.querySelector('[data-edit-post]')) {
      const button = document.createElement('button'); button.className = 'subtle-btn'; button.type = 'button'; button.textContent = '게시글 수정'; button.dataset.editPost = 'true'; button.addEventListener('click', () => startEditing(detailPost));
      author.append(button);
    }
  }

  function positionEditorPopup() {
    if (!window.matchMedia('(max-width: 640px)').matches) return;
    return;
    const host = document.querySelector('.rich-editor-host');
    const toolbar = host?.querySelector('.toastui-editor-defaultUI-toolbar');
    if (!host || !toolbar) return;
    const toolbarRect = toolbar.getBoundingClientRect();
    document.querySelectorAll('.toastui-editor-dropdown-toolbar, .toastui-editor-popup').forEach((popup) => {
      if (getComputedStyle(popup).display === 'none' || getComputedStyle(popup).visibility === 'hidden') return;
      popup.style.top = `${Math.round(toolbarRect.bottom + 6)}px`;
      popup.style.left = '12px';
      popup.style.right = 'auto';
      popup.style.transform = 'none';
      popup.style.maxWidth = 'calc(100vw - 24px)';
      if (popup.classList.contains('toastui-editor-popup') && !popup.classList.contains('toastui-editor-popup-add-table')) popup.style.width = 'calc(100vw - 24px)';
    });
  }

  function decorateAdminCharacterDetail() {
    const form = document.querySelector('.character-detail-page .character-form');
    if (!form) return;
    const combatLabel = [...form.querySelectorAll('label')].find((label) => label.textContent.includes('전투 메모'));
    combatLabel?.classList.add('admin-combat-notes-field');
    let section = form.querySelector('[data-admin-relationships]');
    if (!section) {
      section = document.createElement('section');
      section.dataset.adminRelationships = 'true';
      section.className = 'form-section admin-detail-section admin-relationships-section';
      const actions = form.querySelector('.form-actions');
      form.insertBefore(section, actions || null);
    }
    section.innerHTML = '';
    const heading = document.createElement('div'); heading.className = 'form-section-head';
    heading.innerHTML = '<div><p class="eyebrow">RELATIONSHIPS</p><h2>플레이어 관계 설정</h2></div><span class="form-hint">플레이어가 마이페이지에서 기록한 관계</span>';
    section.append(heading);
    if (!relationships.length) {
      const empty = document.createElement('div'); empty.className = 'repeat-empty'; empty.textContent = '등록된 관계가 없습니다.'; section.append(empty); return;
    }
    const list = document.createElement('div'); list.className = 'relationship-list admin-relationship-list';
    relationships.forEach((relationship) => {
      const item = document.createElement('article'); item.className = 'relationship-item';
      const itemHead = document.createElement('div'); itemHead.className = 'relationship-item-head';
      const title = document.createElement('strong'); title.textContent = relationship.relationship_name; itemHead.append(title);
      if (relationship.npc_post_id) { const link = document.createElement('a'); link.href = `#post/${relationship.npc_post_id}`; link.textContent = `${relationship.npcTitle || 'NPC 페이지 열기'} ↗`; itemHead.append(link); }
      item.append(itemHead);
      if (relationship.memo) { const memo = document.createElement('p'); memo.textContent = relationship.memo; item.append(memo); }
      list.append(item);
    });
    section.append(list);
  }

  function setReplyTarget(comment) {
    commentReplyTo = comment.id;
    const form = document.querySelector('.comment-form');
    const textarea = form?.querySelector('textarea');
    if (!form || !textarea) return;
    form.classList.add('reply-active');
    let indicator = form.querySelector('[data-reply-indicator]');
    if (!indicator) {
      indicator = document.createElement('div');
      indicator.dataset.replyIndicator = 'true';
      indicator.className = 'reply-indicator';
      form.insertBefore(indicator, textarea);
    }
    indicator.textContent = `${comment.nickname}님에게 답글 작성 중`;
    const cancel = document.createElement('button');
    cancel.type = 'button'; cancel.className = 'reply-cancel'; cancel.textContent = '답글 취소';
    cancel.addEventListener('click', clearReplyComposer);
    indicator.append(cancel);
    textarea.placeholder = `${comment.nickname}님에게 답글을 남겨 주세요.`;
    textarea.focus();
  }

  function clearReplyComposer() {
    commentReplyTo = null;
    const form = document.querySelector('.comment-form');
    const textarea = form?.querySelector('textarea');
    form?.classList.remove('reply-active');
    form?.querySelector('[data-reply-indicator]')?.remove();
    if (textarea) textarea.placeholder = user ? '이 모험에 대한 생각을 남겨 주세요.' : '로그인 후 댓글을 작성할 수 있어요.';
  }

  function handleProfileImageChange(event) {
    const file = event.currentTarget.files?.[0] || null;
    if (!file) return;
    if (!['image/png', 'image/jpeg', 'image/webp'].includes(file.type)) return showNotice('PNG, JPG, WEBP 이미지만 업로드할 수 있어요.');
    if (file.size > 5 * 1024 * 1024) return showNotice('이미지는 5MB 이하로 업로드해 주세요.');
    if (profileImagePreview?.startsWith('blob:')) URL.revokeObjectURL(profileImagePreview);
    profileImageFile = file;
    profileImagePreview = URL.createObjectURL(file);
  }

  function handleAdminProfileImageChange(event) {
    const file = event.currentTarget.files?.[0] || null;
    if (!file) return;
    if (!['image/png', 'image/jpeg', 'image/webp'].includes(file.type)) return showNotice('PNG, JPG, WEBP 이미지만 업로드할 수 있어요.');
    if (file.size > 5 * 1024 * 1024) return showNotice('이미지는 5MB 이하로 업로드해 주세요.');
    if (adminProfileImagePreview?.startsWith('blob:')) URL.revokeObjectURL(adminProfileImagePreview);
    adminProfileImageFile = file;
    adminProfileImagePreview = URL.createObjectURL(file);
  }

  async function imageFileToDataUrl(file) {
    const sourceUrl = URL.createObjectURL(file);
    try {
      const image = new Image();
      image.src = sourceUrl;
      await new Promise((resolve, reject) => { image.onload = resolve; image.onerror = reject; });
      const maxSide = 1000;
      const scale = Math.min(1, maxSide / Math.max(image.naturalWidth, image.naturalHeight));
      const canvas = document.createElement('canvas');
      canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
      canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
      canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
      const dataUrl = canvas.toDataURL('image/jpeg', 0.82);
      if (dataUrl.length > 2_000_000) throw new Error('이미지를 조금 더 작은 파일로 올려 주세요.');
      return dataUrl;
    } finally {
      URL.revokeObjectURL(sourceUrl);
    }
  }

  async function createPost() {
    applyRichEditorMarkdownFormatting();
    handleRichEditorInput();
    if (!requireLogin() || !supabase) return;
    if (postSaving || (isEditPage && editLoading)) return;
    const boardSlug = writeBoardSlug === 'all' ? 'users' : writeBoardSlug;
    const isEditingOwnPost = Boolean(editingPostId && editingPostAuthorId === user.id);
    if (!isAdmin && boardSlug !== 'users' && !isEditingOwnPost) return showNotice('이 게시판은 관리자만 작성할 수 있어요.');
    if (boardSlug === 'npc' && (!postForm.npcName.trim() || !postForm.npcRole.trim())) return showNotice('NPC 이름과 역할/직업을 입력해 주세요.');
    if (boardSlug !== 'npc' && !postForm.title.trim()) return showNotice('제목을 입력해 주세요.');
    if (boardSlug === 'sessions' && !sessionEntries.length) return showNotice('+ 버튼으로 지문, 대사 또는 사진을 추가해 주세요.');
    if (boardSlug !== 'sessions' && boardSlug !== 'bgm' && !postForm.content.trim()) return showNotice('내용을 입력해 주세요.');
    if (boardSlug === 'bgm' && !postForm.bgmUrl.trim() && !postForm.bgmFile) return showNotice('BGM URL을 입력하거나 오디오 파일을 선택해 주세요.');
    postSaving = true;
    const wasEditing = Boolean(editingPostId);
    const postTitle = boardSlug === 'npc' ? `[${postForm.npcRole.trim()}] ${postForm.npcName.trim()}` : postForm.title.trim();
    let postContent = postForm.content.trim();
    let sessionExcerpt = '';
    let bgmUrl = boardSlug === 'bgm' ? postForm.bgmUrl.trim() : '';
    if (boardSlug === 'sessions') {
      try {
        const preparedParticipants = prepareSessionParticipants();
        const preparedBgms = prepareSessionBgms();
        const preparedEntries = await prepareSessionEntries();
        postContent = encodeSessionContent(preparedEntries, preparedParticipants, preparedBgms);
        sessionExcerpt = preparedEntries.map((entry) => entry.type === 'image' ? `[사진] ${entry.caption}` : `${entry.type === 'dialogue' ? sessionSpeakerName(entry) : sessionActorName(entry)} ${entry.text}`).join(' ').replace(/\s+/g, ' ').slice(0, 140);
      } catch (error) {
        postSaving = false;
        return showNotice(error instanceof Error ? error.message : '세션 로그를 확인해 주세요.');
      }
    }
    if (boardSlug === 'bgm' && postForm.bgmFile) {
      try { bgmUrl = await uploadBgmFile(postForm.bgmFile); } catch (error) { postSaving = false; return showNotice(error instanceof Error ? error.message : 'BGM을 업로드하지 못했습니다.'); }
    }
    let imageUrl = '';
    if (postForm.imageFile) {
      if (postForm.imageFile.size > 5 * 1024 * 1024) { postSaving = false; return showNotice('이미지는 5MB 이하로 업로드해 주세요.'); }
      try {
        imageUrl = await imageFileToDataUrl(postForm.imageFile);
      } catch (error) {
        postSaving = false;
        return showNotice(error instanceof Error ? error.message : '이미지를 처리하지 못했습니다.');
      }
    }
    const payload = { board_slug: boardSlug, title: postTitle, content: postContent, excerpt: (sessionExcerpt || postContent || postTitle).replace(/\s+/g, ' ').slice(0, 140), status: 'published', author_id: editingPostId ? editingPostAuthorId : user.id, image_url: boardSlug === 'npc' ? imageUrl || npcImagePreview || null : null, youtube_url: null, bgm_url: boardSlug === 'bgm' ? bgmUrl || null : null, bgm_category: boardSlug === 'bgm' ? postForm.bgmCategory : null, post_type: boardSlug === 'notices' ? postForm.postType : null, npc_name: boardSlug === 'npc' ? postForm.npcName.trim() : null, npc_age: boardSlug === 'npc' ? numberOrNull(postForm.npcAge) : null, npc_gender: boardSlug === 'npc' ? postForm.npcGender.trim() : null, npc_height: boardSlug === 'npc' ? numberOrNull(postForm.npcHeight) : null, npc_race: boardSlug === 'npc' ? postForm.npcRace.trim() : null, npc_role: boardSlug === 'npc' ? postForm.npcRole.trim() : null, npc_traits: boardSlug === 'npc' ? postForm.npcTraits.trim() : null, npc_affiliation: boardSlug === 'npc' ? postForm.npcAffiliation.trim() : null, npc_personality: boardSlug === 'npc' ? postForm.npcPersonality.trim() : null };
    let { data, error } = editingPostId
      ? await supabase.from('posts').update(payload).eq('id', editingPostId).select('id').single()
      : await supabase.from('posts').insert(payload).select('id').single();
    if (error && /column|schema cache|image_url|npc_|bgm_/i.test(error.message)) {
      const fallbackData = { image_url: imageUrl || null, npc_name: postForm.npcName.trim(), npc_age: numberOrNull(postForm.npcAge), npc_gender: postForm.npcGender.trim(), npc_height: numberOrNull(postForm.npcHeight), npc_race: postForm.npcRace.trim(), npc_role: postForm.npcRole.trim(), npc_traits: postForm.npcTraits.trim(), npc_affiliation: postForm.npcAffiliation.trim(), npc_personality: postForm.npcPersonality.trim() };
      const encoded = btoa(unescape(encodeURIComponent(JSON.stringify(fallbackData))));
      const bgmFallback = btoa(unescape(encodeURIComponent(JSON.stringify({ bgm_url: bgmUrl || null, bgm_category: postForm.bgmCategory }))));
      const legacyContent = boardSlug === 'sessions' ? postContent : boardSlug === 'bgm' ? `<!--OPEN_DOOR_BGM:${bgmFallback}-->${postContent}` : `<!--OPEN_DOOR_NPC:${encoded}-->${postContent}`;
      const legacyPayload = { board_slug: boardSlug, title: postTitle, content: legacyContent, excerpt: (sessionExcerpt || postContent || postTitle).replace(/\s+/g, ' ').slice(0, 140), status: 'published', author_id: editingPostId ? editingPostAuthorId : user.id };
      ({ data, error } = editingPostId
        ? await supabase.from('posts').update(legacyPayload).eq('id', editingPostId).select('id').single()
        : await supabase.from('posts').insert(legacyPayload).select('id').single());
    }
    postSaving = false;
    if (error) return showNotice(`글 저장 실패: ${error.message}`);
    if (npcImagePreview) URL.revokeObjectURL(npcImagePreview);
    sessionEntries.forEach((entry) => entry.imageUrl?.startsWith('blob:') && URL.revokeObjectURL(entry.imageUrl));
    npcImagePreview = '';
    sessionEntries = [];
    sessionParticipants = [];
    sessionBgmIds = [];
    postForm = { title: '', content: '', postType: 'notice', npcName: '', npcAge: '', npcGender: '', npcHeight: '', npcRace: '', npcRole: '', npcTraits: '', npcAffiliation: '', npcPersonality: '', bgmCategory: 'map', bgmUrl: '', bgmFile: null, imageFile: null }; editingPostId = null; await loadDatabase(); showNotice(wasEditing ? '게시글을 수정했습니다.' : '게시글을 등록했습니다.'); navigateTo(`#post/${data.id}`);
  }

  async function deletePost(post) {
    if (!requireLogin() || !supabase || !(isAdmin || post.authorId === user.id) || !confirm('게시글을 삭제할까요?')) return;
    const deleteQuery = supabase.from('posts').delete().eq('id', post.id);
    if (!isAdmin) deleteQuery.eq('author_id', user.id);
    const { error } = await deleteQuery;
    if (error) return showNotice(`게시글 삭제 실패: ${error.message}`);
    await loadDatabase(); showNotice('게시글을 삭제했습니다.'); navigateTo('#home');
  }

  async function addComment() {
    if (!requireLogin('댓글을 작성하려면 로그인해 주세요.') || !supabase || !detailPost) return;
    const content = commentText.trim();
    if (!content) return showNotice('댓글 내용을 입력해 주세요.');
    commentSaving = true;
    const { error } = await supabase.from('post_comments').insert({ post_id: detailPost.id, author_id: user.id, content, parent_id: commentReplyTo || null });
    commentSaving = false;
    if (error) return showNotice(`댓글 저장 실패: ${error.message}`);
    commentText = '';
    clearReplyComposer();
    detailPost = { ...detailPost, comments: detailPost.comments + 1 };
    await loadEngagement(detailPost.id);
    showNotice('댓글을 등록했습니다.');
  }

  async function deleteComment(comment) {
    if (!requireLogin() || !supabase || comment.author_id !== user.id || !confirm('내 댓글을 삭제할까요?')) return;
    const { error } = await supabase.from('post_comments').delete().eq('id', comment.id).eq('author_id', user.id);
    if (error) return showNotice(`댓글 삭제 실패: ${error.message}`);
    detailComments = detailComments.filter((item) => item.id !== comment.id);
    if (detailPost) detailPost = { ...detailPost, comments: Math.max(0, detailPost.comments - 1) };
    showNotice('댓글을 삭제했습니다.');
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
  function selectInventoryItem(item) { selectedInventoryItem = item; }

  function filterItemCatalog(catalog = [], keyword = '') {
    const term = keyword.trim().toLowerCase();
    if (!term) return catalog;
    return catalog.filter((item) => `${item.name} ${item.effect} ${item.grade} ${item.item_type}`.toLowerCase().includes(term));
  }

  async function loadItemCatalog() {
    if (!supabase) return;
    itemCatalogLoading = true;
    itemCatalogError = '';
    const { data, error } = await supabase.from('items').select('id, name, effect, grade, item_type, icon_url').order('name');
    itemCatalogLoading = false;
    if (error) { itemCatalogError = error.message; return; }
    itemCatalog = data || [];
  }

  function resetItemForm() { itemForm = { id: null, name: '', effect: '', grade: '일반', item_type: '기타', icon_url: '' }; }
  function editItem(item) { itemForm = { id: item.id, name: item.name, effect: item.effect || '', grade: item.grade, item_type: item.item_type, icon_url: item.icon_url || '' }; }

  async function handleItemIconChange(event) {
    const file = event.currentTarget.files?.[0] || null;
    if (!file) return;
    if (!['image/png', 'image/jpeg', 'image/webp'].includes(file.type)) return showNotice('PNG, JPG, WEBP 이미지만 업로드할 수 있어요.');
    if (file.size > 5 * 1024 * 1024) return showNotice('이미지는 5MB 이하로 업로드해 주세요.');
    try { itemForm = { ...itemForm, icon_url: await imageFileToDataUrl(file) }; }
    catch (error) { showNotice(error instanceof Error ? error.message : '아이템 이미지를 처리하지 못했습니다.'); }
  }

  async function saveItem() {
    if (!isAdmin || !supabase) return;
    if (!itemForm.name.trim()) return showNotice('아이템 이름을 입력해 주세요.');
    itemSaving = true;
    const payload = { name: itemForm.name.trim(), effect: itemForm.effect.trim(), grade: itemForm.grade, item_type: itemForm.item_type, icon_url: itemForm.icon_url || null };
    const result = itemForm.id
      ? await supabase.from('items').update(payload).eq('id', itemForm.id)
      : await supabase.from('items').insert(payload);
    itemSaving = false;
    if (result.error) return showNotice(`아이템 저장 실패: ${result.error.message}`);
    showNotice(itemForm.id ? '아이템을 수정했습니다.' : '아이템을 등록했습니다.');
    resetItemForm();
    await loadItemCatalog();
  }

  async function deleteItem(item) {
    if (!isAdmin || !supabase || !confirm(`'${item.name}' 아이템을 삭제할까요?`)) return;
    const { error } = await supabase.from('items').delete().eq('id', item.id);
    if (error) return showNotice(`아이템 삭제 실패: ${error.message}`);
    if (itemForm.id === item.id) resetItemForm();
    await loadItemCatalog();
    showNotice('아이템을 삭제했습니다.');
  }

  function addCatalogItemToInventory(item) {
    const existingIndex = adminInventory.findIndex((entry) => entry.item_id === item.id);
    if (existingIndex >= 0) {
      adminInventory = adminInventory.map((entry, index) => index === existingIndex ? { ...entry, quantity: Math.max(1, Number(entry.quantity) || 1) + 1 } : entry);
    } else {
      adminInventory = [...adminInventory, { item_id: item.id, item_name: item.name, item_effect: item.effect || '', quantity: 1, grade: item.grade, item_type: item.item_type, icon_url: item.icon_url || '' }];
    }
    inventorySearch = '';
    showNotice(`'${item.name}'을(를) 인벤토리에 담았습니다. 저장해야 반영됩니다.`);
  }
  function getInventoryIcon(item) {
    if (item?.icon_url) return item.icon_url;
    if (item?.item_type === '소비' || /물약|포션|bottle|potion/i.test(item?.item_name || '')) return '/icons/round-potion.png';
    return { 유물: '✦', 장비: '⚔', 소비: '✚', 기타: '◆' }[item?.item_type] || '◆';
  }
  function isImageIcon(value) { return typeof value === 'string' && /^(\/|data:image\/|https?:\/\/)/.test(value); }
  function catalogItemIcon(item) { return getInventoryIcon({ ...item, item_name: item?.name || '' }); }

  async function handleAdminInventoryImage(event, index) {
    const file = event.currentTarget.files?.[0] || null;
    if (!file) return;
    if (!['image/png', 'image/jpeg', 'image/webp'].includes(file.type)) return showNotice('PNG, JPG, WEBP 이미지만 업로드할 수 있어요.');
    if (file.size > 5 * 1024 * 1024) return showNotice('이미지는 5MB 이하로 업로드해 주세요.');
    try {
      const iconUrl = await imageFileToDataUrl(file);
      adminInventory = adminInventory.map((item, itemIndex) => itemIndex === index ? { ...item, icon_url: iconUrl } : item);
    } catch (error) { showNotice(error instanceof Error ? error.message : '아이템 이미지를 처리하지 못했습니다.'); }
  }
  function newInventoryItem() { inventory = [...inventory, { item_name: '', item_effect: '', quantity: 1, grade: '일반', item_type: '기타' }]; }
  function newCard() { cards = [...cards, { card_name: '', card_effect: '', quantity: 1, energy: 0, grade: '기본' }]; }
  function removeInventory(index) { inventory = inventory.filter((_, itemIndex) => itemIndex !== index); }
  function removeCard(index) { cards = cards.filter((_, cardIndex) => cardIndex !== index); }
  function setCharacterForm(data) {
    characterForm = { name: data?.name || '', roleName: data?.role_name || '', roleTraits: data?.role_traits || '', age: data?.age ?? '', height: data?.height ?? '', weight: data?.weight ?? '' };
  }

  function selectAdminCharacter(data) {
    adminSelectedCharacter = data;
    adminCharacterForm = { name: data?.name || '', roleName: data?.role_name || data?.class_name || '', roleTraits: data?.role_traits || data?.content || '', age: data?.age ?? '', height: data?.height ?? '', weight: data?.weight ?? '', money: data?.money ?? 0, level: data?.level ?? 1, hp: data?.hp ?? 0, maxHp: data?.max_hp ?? 0, mp: data?.mp ?? 0, maxMp: data?.max_mp ?? 0, attack: data?.attack ?? 0, defense: data?.defense ?? 0, combatNotes: data?.combat_notes || '' };
    navigateTo(`#admin-character/${data.id}`);
  }

  function selectAdminCharacterState(data) {
    adminSelectedCharacter = data;
    adminCharacterForm = { name: data?.name || '', roleName: data?.role_name || data?.class_name || '', roleTraits: data?.role_traits || data?.content || '', age: data?.age ?? '', height: data?.height ?? '', weight: data?.weight ?? '', money: data?.money ?? 0, level: data?.level ?? 1, hp: data?.hp ?? 0, maxHp: data?.max_hp ?? 0, mp: data?.mp ?? 0, maxMp: data?.max_mp ?? 0, attack: data?.attack ?? 0, defense: data?.defense ?? 0, combatNotes: data?.combat_notes || '' };
  }

  async function loadAdminCharacterDetail(id) {
    if (!isAdmin || !supabase || !id) return;
    adminDetailLoading = true;
    const characterResult = await supabase.from('characters').select('*').eq('id', id).maybeSingle();
    if (characterResult.error || !characterResult.data) { adminDetailLoading = false; return showNotice('캐릭터 상세 정보를 불러오지 못했습니다.'); }
    selectAdminCharacterState(characterResult.data);
    const { itemsResult, cardsResult } = await loadCharacterCollections(id);
    if (itemsResult.error || cardsResult.error) { adminDetailLoading = false; return showNotice('인벤토리 또는 카드 정보를 불러오지 못했습니다.'); }
    adminInventory = itemsResult.data || [];
    adminCards = cardsResult.data || [];
    await loadCharacterRecords(id);
    adminDetailLoading = false;
  }

  async function saveAdminCharacter() {
    if (!isAdmin || !supabase || !adminSelectedCharacter) return;
    if (!adminCharacterForm.name.trim() || !adminCharacterForm.roleName.trim()) return showNotice('캐릭터 이름과 역할명을 입력해 주세요.');
    adminCharacterSaving = true;
    const payload = { name: adminCharacterForm.name.trim(), class_name: adminCharacterForm.roleName.trim(), content: adminCharacterForm.roleTraits.trim(), role_name: adminCharacterForm.roleName.trim(), role_traits: adminCharacterForm.roleTraits.trim(), age: numberOrNull(adminCharacterForm.age), height: numberOrNull(adminCharacterForm.height), weight: numberOrNull(adminCharacterForm.weight), money: Math.max(0, Number(adminCharacterForm.money) || 0), level: Math.max(1, Number(adminCharacterForm.level) || 1), hp: Math.max(0, Number(adminCharacterForm.hp) || 0), max_hp: Math.max(0, Number(adminCharacterForm.maxHp) || 0), mp: Math.max(0, Number(adminCharacterForm.mp) || 0), max_mp: Math.max(0, Number(adminCharacterForm.maxMp) || 0), attack: Math.max(0, Number(adminCharacterForm.attack) || 0), defense: Math.max(0, Number(adminCharacterForm.defense) || 0), combat_notes: adminCharacterForm.combatNotes.trim() };
    let characterResult = await supabase.from('characters').update(payload).eq('id', adminSelectedCharacter.id).select().single();
    if (characterResult.error && /money|level|max_hp|combat_notes|extra_info|column|schema cache/i.test(characterResult.error.message)) {
      const { money, level, hp, max_hp, mp, max_mp, attack, defense, combat_notes, ...legacyPayload } = payload;
      characterResult = await supabase.from('characters').update(legacyPayload).eq('id', adminSelectedCharacter.id).select().single();
    }
    adminCharacterSaving = false;
    if (characterResult.error) return showNotice(`캐릭터 수정 실패: ${characterResult.error.message}`);
    selectAdminCharacterState({ ...adminSelectedCharacter, ...characterResult.data });
    const characterId = adminSelectedCharacter.id;
    const deleteItems = await supabase.from('inventory_items').delete().eq('character_id', characterId);
    const deleteCards = await supabase.from('character_cards').delete().eq('character_id', characterId);
    if (deleteItems.error || deleteCards.error) { adminCharacterSaving = false; return showNotice('인벤토리 또는 카드 정리 중 오류가 발생했습니다.'); }
    const items = adminInventory.filter((item) => item.item_name?.trim()).map((item) => ({ character_id: characterId, item_id: item.item_id || null, item_name: item.item_name.trim(), item_effect: item.item_effect?.trim() || '', quantity: Math.max(1, Number(item.quantity) || 1), grade: item.grade, item_type: item.item_type, icon_url: item.icon_url || null }));
    const cards = adminCards.filter((card) => card.card_name?.trim()).map((card) => ({ character_id: characterId, card_name: card.card_name.trim(), card_effect: card.card_effect?.trim() || '', quantity: Math.max(1, Number(card.quantity) || 1), energy: Math.max(0, Number(card.energy) || 0), grade: card.grade }));
    const itemSaveError = await saveInventoryWithIconFallback(items);
    if (itemSaveError) { adminCharacterSaving = false; return showNotice(`인벤토리 저장 실패: ${itemSaveError.message}`); }
    const cardSaveError = await saveCardsWithEnergyFallback(cards);
    if (cardSaveError) { adminCharacterSaving = false; return showNotice(`카드 저장 실패: ${cardSaveError.message}`); }
    await loadCharacterData();
    await loadAdminCharacterDetail(characterId);
    showNotice('캐릭터 정보를 수정했습니다.');
  }

  async function deleteAdminCharacter() {
    if (!isAdmin || !supabase || !adminSelectedCharacter || !confirm(`'${adminSelectedCharacter.name}' 캐릭터를 삭제할까요?`)) return;
    const { error } = await supabase.from('characters').delete().eq('id', adminSelectedCharacter.id);
    if (error) return showNotice(`캐릭터 삭제 실패: ${error.message}`);
    adminSelectedCharacter = null;
    adminInventory = [];
    adminCards = [];
    navigateTo('#admin');
    await loadCharacterData();
    showNotice('캐릭터를 삭제했습니다.');
  }

  function newAdminInventoryItem() { adminInventory = [...adminInventory, { item_id: null, item_name: '', item_effect: '', quantity: 1, grade: '일반', item_type: '기타', icon_url: '' }]; }
  function removeAdminInventory(index) { adminInventory = adminInventory.filter((_, itemIndex) => itemIndex !== index); }
  function newAdminCard() { adminCards = [...adminCards, { card_name: '', card_effect: '', quantity: 1, energy: 0, grade: '기본' }]; }
  function removeAdminCard(index) { adminCards = adminCards.filter((_, cardIndex) => cardIndex !== index); }

  async function loadCharacterCollections(characterId) {
    let itemsResult = await supabase.from('inventory_items').select('id, item_id, item_name, item_effect, quantity, grade, item_type, icon_url').eq('character_id', characterId).order('created_at');
    if (itemsResult.error) {
      const withoutItemId = await supabase.from('inventory_items').select('id, item_name, item_effect, quantity, grade, item_type, icon_url').eq('character_id', characterId).order('created_at');
      itemsResult = withoutItemId.error ? itemsResult : { ...withoutItemId, data: (withoutItemId.data || []).map((item) => ({ ...item, item_id: null })) };
    }
    if (itemsResult.error) {
      const legacyItemsResult = await supabase.from('inventory_items').select('id, item_name, item_effect, quantity, grade, item_type').eq('character_id', characterId).order('created_at');
      if (!legacyItemsResult.error) itemsResult = { ...legacyItemsResult, data: (legacyItemsResult.data || []).map((item) => ({ ...item, item_id: null, icon_url: '' })) };
    }
    let cardsResult = await supabase.from('character_cards').select('id, card_name, card_effect, quantity, energy, grade').eq('character_id', characterId).order('created_at');
    // Older databases do not have the optional energy column yet.
    if (cardsResult.error) {
      const legacyCardsResult = await supabase.from('character_cards').select('id, card_name, card_effect, quantity, grade').eq('character_id', characterId).order('created_at');
      if (!legacyCardsResult.error) cardsResult = { ...legacyCardsResult, data: (legacyCardsResult.data || []).map((card) => ({ ...card, energy: 0 })) };
    }
    return { itemsResult, cardsResult };
  }

  async function loadCharacterRecords(characterId) {
    extraRecordCharacterId = characterId;
    extraRecords = [];
    relationships = [];
    const recordsResult = await supabase.from('character_extra_records').select('id, title, content, author_id, created_at, profiles(nickname)').eq('character_id', characterId).order('created_at', { ascending: false });
    if (!recordsResult.error) {
      extraRecords = (recordsResult.data || []).map((record) => ({ ...record, authorName: record.profiles?.nickname || '모험가' }));
    }
    const relationshipsResult = await supabase.from('character_relationships').select('id, relationship_name, memo, npc_post_id, created_at, posts(id, title, board_slug)').eq('character_id', characterId).order('created_at', { ascending: false });
    if (!relationshipsResult.error) {
      relationships = (relationshipsResult.data || []).map((relationship) => ({ ...relationship, npcTitle: relationship.posts?.title || '' }));
    }
  }

  async function saveExtraRecord() {
    if (!requireLogin() || !supabase || !extraRecordCharacterId) return;
    if (!extraRecordForm.title.trim() || !extraRecordForm.content.trim()) return showNotice('추가 기록 제목과 내용을 입력해 주세요.');
    extraRecordSaving = true;
    const { error } = await supabase.from('character_extra_records').insert({ character_id: extraRecordCharacterId, author_id: user.id, title: extraRecordForm.title.trim(), content: extraRecordForm.content.trim() });
    extraRecordSaving = false;
    if (error) return showNotice(`추가 기록 저장 실패: ${error.message}`);
    extraRecordForm = { title: '', content: '' };
    await loadCharacterRecords(extraRecordCharacterId);
    showNotice('추가 기록을 등록했습니다.');
  }

  async function deleteExtraRecord(record) {
    if (!requireLogin() || !supabase || !record?.id || !confirm(`'${record.title}' 기록을 삭제할까요?`)) return;
    const { error } = await supabase.from('character_extra_records').delete().eq('id', record.id);
    if (error) return showNotice(`추가 기록 삭제 실패: ${error.message}`);
    await loadCharacterRecords(extraRecordCharacterId);
    showNotice('추가 기록을 삭제했습니다.');
  }

  async function saveRelationship() {
    if (!requireLogin() || !supabase || !extraRecordCharacterId) return;
    if (!relationshipForm.name.trim()) return showNotice('관계 이름을 입력해 주세요.');
    relationshipSaving = true;
    const { error } = await supabase.from('character_relationships').insert({ character_id: extraRecordCharacterId, npc_post_id: relationshipForm.npcPostId || null, relationship_name: relationshipForm.name.trim(), memo: relationshipForm.memo.trim() });
    relationshipSaving = false;
    if (error) return showNotice(`관계 저장 실패: ${error.message}`);
    relationshipForm = { name: '', npcPostId: '', memo: '' };
    await loadCharacterRecords(extraRecordCharacterId);
    showNotice('관계를 등록했습니다.');
  }

  async function deleteRelationship(relationship) {
    if (!requireLogin() || !supabase || !relationship?.id || !confirm(`'${relationship.relationship_name}' 관계를 삭제할까요?`)) return;
    const { error } = await supabase.from('character_relationships').delete().eq('id', relationship.id);
    if (error) return showNotice(`관계 삭제 실패: ${error.message}`);
    await loadCharacterRecords(extraRecordCharacterId);
    showNotice('관계를 삭제했습니다.');
  }

  async function saveCardsWithEnergyFallback(rows) {
    if (!rows.length) return null;
    let result = await supabase.from('character_cards').insert(rows);
    if (result.error && /energy|column|schema cache/i.test(result.error.message)) {
      result = await supabase.from('character_cards').insert(rows.map(({ energy, ...card }) => card));
    }
    return result.error || null;
  }

  async function saveInventoryWithIconFallback(rows) {
    if (!rows.length) return null;
    let result = await supabase.from('inventory_items').insert(rows);
    if (result.error && /item_id|column|schema cache/i.test(result.error.message)) {
      result = await supabase.from('inventory_items').insert(rows.map(({ item_id, ...item }) => item));
    }
    if (result.error && /icon_url|column|schema cache/i.test(result.error.message)) {
      result = await supabase.from('inventory_items').insert(rows.map(({ item_id, icon_url, ...item }) => item));
    }
    return result.error || null;
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
      profileImagePreview = character?.avatar_url || '';
      setCharacterForm(character);
      await syncCharacterAvatarToProfile(character?.avatar_url || null);
      if (!character) {
        inventory = [];
        cards = [];
        return;
      }
      const { itemsResult, cardsResult } = await loadCharacterCollections(character.id);
      if (itemsResult.error) throw new Error(itemsResult.error.message);
      if (cardsResult.error) throw new Error(cardsResult.error.message);
      inventory = itemsResult.data || [];
      cards = cardsResult.data || [];
      await loadCharacterRecords(character.id);
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
    let profileImageUrl = profileImagePreview && !profileImagePreview.startsWith('blob:') ? profileImagePreview : '';
    if (profileImageFile) {
      try { profileImageUrl = await imageFileToDataUrl(profileImageFile); } catch (error) { characterSaving = false; return showNotice(error instanceof Error ? error.message : '프로필 이미지를 처리하지 못했습니다.'); }
    }
    const payload = { owner_id: user.id, name: characterForm.name.trim(), class_name: characterForm.roleName.trim(), content: characterForm.roleTraits.trim(), status: 'published', role_name: characterForm.roleName.trim(), role_traits: characterForm.roleTraits.trim(), age: numberOrNull(characterForm.age), height: numberOrNull(characterForm.height), weight: numberOrNull(characterForm.weight), avatar_url: profileImageUrl || null };
    let characterResult = character?.id ? await supabase.from('characters').update(payload).eq('id', character.id).select().single() : await supabase.from('characters').insert(payload).select().single();
    if (characterResult.error && /avatar_url|column|schema cache/i.test(characterResult.error.message)) {
      const { avatar_url, ...legacyPayload } = payload;
      characterResult = character?.id ? await supabase.from('characters').update(legacyPayload).eq('id', character.id).select().single() : await supabase.from('characters').insert(legacyPayload).select().single();
    }
    if (characterResult.error) { characterSaving = false; return showNotice(`캐릭터 저장 실패: ${characterResult.error.message}`); }
    character = characterResult.data;
    const avatarSynced = await syncCharacterAvatarToProfile(character?.avatar_url || null, true);
    profileImageFile = null; characterSaving = false;
    if (avatarSynced !== false) showNotice('캐릭터 기본 정보와 프로필 사진을 저장했습니다.');
    await loadCharacterData();
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
      if (!supabase) { authReady = true; return; }
      if (currentRoute === 'admin') profileLoading = true;
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
      authReady = true;
      profileLoading = false;
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

<div class="site" class:writing-mode={isWritePage}><div class="bg-grid" aria-hidden="true"></div><div class="bg-glow bg-glow-a" aria-hidden="true"></div><div class="bg-glow bg-glow-b" aria-hidden="true"></div>
  <header class="header"><a class="brand" href="#home" aria-label="open door 홈"><span class="brand-mark">od</span><span class="brand-copy"><strong>open door</strong><small>long-form TRPG campaign</small></span></a>
     <nav class="main-nav" aria-label="주요 메뉴"><a class:active={currentRoute === 'home'} href="#home">홈</a><div class="nav-item nav-dropdown"><a class:active={currentRoute === 'board/notices' || currentRoute === 'board/sessions'} href="#board/notices" aria-haspopup="true">공지사항</a><div class="dropdown-menu" aria-label="공지사항 메뉴"><a href="#board/notices"><strong>공지사항</strong><small>운영 안내 · 업데이트 · 이벤트</small></a><a href="#board/sessions"><strong>세션 로그</strong><small>플레이 기록 · 후기 · 다음화 예고</small></a></div></div><div class="nav-item nav-dropdown"><a class:active={['board/npc', 'board/world', 'board/continents', 'board/system', 'board/bgm'].includes(currentRoute)} href="#board/world" aria-haspopup="true">세계관</a><div class="dropdown-menu" aria-label="세계관 메뉴"><a href="#board/npc"><strong>NPC 게시판</strong><small>NPC 초상화 · 성격 · 관계 · 특징</small></a><a href="#board/world"><strong>세계관 자료실</strong><small>세계관 · 국가 · 역사 · 설정 자료</small></a><a href="#board/continents"><strong>대륙 게시판</strong><small>대륙 · 지형 · 도시 · 주요 장소</small></a><a href="#board/system"><strong>시스템 게시판</strong><small>규칙 · 전투 · 판정 · 캠페인 시스템</small></a><a href="#board/bgm"><strong>BGM 게시판</strong><small>맵 · 캐릭터 · 장면별 배경음악</small></a></div></div><a class:active={currentRoute === 'board/users'} href="#board/users">유저게시판</a>{#if user}<a class:active={isMyPage || isAdminPage || isAdminMypage} href={isAdmin ? '#admin-mypage' : '#mypage'} on:click={openProfile}>마이페이지</a>{/if}</nav>
    <div class="header-actions"><div class="audio-pill" role="group" aria-label="사운드 설정"><button class="audio-toggle" on:click={toggleSound} aria-pressed={muted}><span class="audio-icon" aria-hidden="true">{muted ? '×' : '♪'}</span><span>{muted ? 'Muted' : 'Sound'}</span></button><input class="audio-slider" type="range" min="0" max="1" step="0.01" value={volume} on:input={updateVolume} aria-label="볼륨 조절" /></div>{#if user}<button class="login logged-in" on:click={handleLogout}>로그아웃</button>{:else}<button class="login" on:click={() => (showLogin = true)}>로그인</button>{/if}</div>
  </header>

   <main id="home" class="layout">
    {#key currentRoute}
    {#if currentRoute === 'home'}
      <section class="hero"><div class="hero-copy"><p class="eyebrow">LONG-FORM TRPG CAMPAIGN</p><h1>문이 열리면,<br /><em>모험이 시작됩니다</em></h1><p class="lead">세계관을 함께 읽고, 캐릭터를 만들고, 한 번의 세션을 오래 기억하세요.<br class="desktop-only" /> open door는 장기 TRPG 캠페인을 위한 기록 공간입니다.</p><div class="hero-cta"><button class="primary-btn" on:click={(event) => user ? openProfile(event) : (showLogin = true)}>마이페이지 <span>↗</span></button><a class="text-link" href="#board/sessions">세션 기록 보기 <span>→</span></a></div></div><div class="hero-side"><div class="hero-side-head"><span class="live-mark">LIVE</span><span>campaign archive</span><span class="spark">✦</span></div><div class="pulse-orbit" aria-hidden="true"><span class="orbit-dot one"></span><span class="orbit-dot two"></span><span class="orbit-dot three"></span><div class="pulse-core">✦<br />TRPG</div></div></div></section>
      <!-- 게시판 안내 섹션은 필요할 때 복원할 수 있도록 임시 보관합니다.
      <section class="board-directory panel" aria-labelledby="board-directory-title"><div class="section-head board-directory-head"><div><p class="eyebrow">CHOOSE YOUR PATH</p><h2 id="board-directory-title">게시판 안내</h2></div><div class="directory-meta"><p class="section-caption">세계관을 읽고, 캐릭터를 만들고,<br class="desktop-only" /> 함께 모험을 기록해 보세요.</p><span class={`data-status ${dbStatus}`}><i></i>{dbStatus === 'connected' ? 'LIVE DATABASE' : dbStatus === 'loading' ? '데이터 불러오는 중' : 'DB 연결 확인 필요'}</span></div></div><div class="board-grid">{#each categories.slice(1) as category, index}<a class="board-card" class:featured={index === 1} href={`#board/${category.slug}`}><span class="board-number">0{index + 1}</span><span class="board-copy"><strong>{category.name}</strong><small>{category.description}</small></span><span class="board-arrow">↗</span></a>{/each}</div></section>
      -->
      <section class="content-grid"><section class="notice-panel panel"><div class="section-head"><div><p class="eyebrow">KEEP IN MIND</p><h2>공지사항</h2></div><a href="#board/notices">전체 보기 <span>→</span></a></div><div class="notice-list">{#if notices.length}{#each notices as item}<a class="notice-item" href="#board/notices"><span class={`badge ${item.tone}`}>{item.tag}</span><div class="notice-copy"><h3>{item.title}</h3><p>{item.body}</p></div><div class="notice-meta"><span>{item.meta}</span><b>→</b></div></a>{/each}{:else}<div class="notice-empty">아직 등록된 공지사항이 없습니다.</div>{/if}</div></section></section>
       <section class="posts panel"><div class="section-head posts-head"><div><p class="eyebrow">FROM THE CAMPAIGN</p><h2>최근 게시글</h2></div><div class="head-actions"><span class="result-count">총 {filteredPosts.length}개의 글</span><select bind:value={sortBy} aria-label="게시글 정렬"><option value="latest">최신순</option><option value="popular">인기순</option></select></div></div><div class="toolbar"><div class="category-tabs" role="tablist" aria-label="게시글 카테고리">{#each categories as category}<button class:active={activeCategory === category.name} class="category-tab" type="button" on:click={() => (activeCategory = category.name)}>{category.name}<span>{category.count}</span></button>{/each}</div><label class="search"><span aria-hidden="true">⌕</span><input bind:value={searchTerm} type="search" placeholder="게시글 검색" aria-label="게시글 검색" /></label></div><div class="post-list" aria-live="polite">{#if filteredPosts.length}{#each pagedFilteredPosts as post}<a class="post-row" href={`#post/${post.id}`}>{#if post.avatarUrl}<img class="avatar avatar-image" src={post.avatarUrl} alt={`${post.author} 프로필 사진`} />{:else}<span class={`avatar ${post.color}`}>{post.avatar}</span>{/if}<span class="post-main"><span class="post-meta"><b>{post.category}</b><span>{post.date} · {post.time}</span></span><strong>{post.title}</strong><small>{post.excerpt}</small></span><span class="post-author"><b>{post.author}</b><small>작성자</small></span><span class="post-stats"><span>댓글 {post.comments}</span><span>좋아요 {post.likes}</span></span><span class="post-arrow">→</span></a>{/each}{:else}<div class="empty-state"><span>⌕</span><strong>아직 등록된 글이 없어요</strong><p>로그인 후 첫 번째 이야기를 작성해 보세요.</p></div>{/if}</div><div class="pagination">{#each Array(filteredPageCount) as _, index}<button class:active={currentPage === index + 1} type="button" on:click={() => (currentPage = index + 1)}>{index + 1}</button>{/each}</div><div class="load-more"><button on:click={() => startWriting('users')}>새 글 작성 <span>↗</span></button></div></section>
    {:else if isBoardPage}
       <section class="board-page panel"><div class="board-page-hero"><a class="back-link" href="#home">← 홈으로 돌아가기</a><p class="eyebrow">BOARD / {currentBoard.slug.toUpperCase()}</p><h1>{currentBoard.name}</h1><p>{currentBoard.description}.</p>{#if isAdmin || currentBoard.slug === 'users'}<button class="primary-btn" on:click={() => startWriting(currentBoard.slug)}>새 글 작성 <span>↗</span></button>{/if}</div><div class="board-page-content"><div class="section-head board-page-head"><div><p class="eyebrow">{currentBoard.name.toUpperCase()}</p><h2>게시글 목록</h2></div><div class="head-actions"><span class="result-count">총 {boardPagePosts.length}개의 글</span><select bind:value={sortBy} aria-label="게시글 정렬"><option value="latest">최신순</option><option value="popular">인기순</option></select></div></div><div class="board-toolbar"><label class="notice-filter" class:hidden={currentBoard.slug !== 'notices'}>분류<select bind:value={noticeTypeFilter}><option value="all">전체</option><option value="notice">공지사항</option><option value="patch">패치노트</option><option value="event">이벤트</option></select></label><label class="session-player-filter" class:hidden={currentBoard.slug !== 'sessions'}>플레이어<select bind:value={sessionPlayerFilter}><option value="">전체 플레이어</option>{#each sessionPlayerFilterOptions as player}<option value={player.value}>{player.label}</option>{/each}</select></label><label class="search"><span aria-hidden="true">⌕</span><input bind:value={searchTerm} type="search" placeholder="이 게시판에서 검색" aria-label="이 게시판에서 검색" /></label></div><div class="post-list board-post-list" aria-live="polite">{#if boardPagePosts.length}{#each pagedBoardPosts as post}<a class="post-row" href={`#post/${post.id}`}>{#if post.avatarUrl}<img class="avatar avatar-image" src={post.avatarUrl} alt={`${post.author} 프로필 사진`} />{:else}<span class={`avatar ${post.color}`}>{post.avatar}</span>{/if}<span class="post-main"><span class="post-meta"><b>{post.category}</b><span>{post.date} · {post.time}</span></span><strong>{post.title}</strong><small>{post.excerpt}</small></span><span class="post-author"><b>{post.author}</b><small>작성자</small></span><span class="post-stats"><span>댓글 {post.comments}</span><span>좋아요 {post.likes}</span></span><span class="post-arrow">→</span></a>{/each}{:else}<div class="empty-state"><span>⌕</span><strong>아직 등록된 글이 없어요</strong><p>첫 번째 이야기를 작성해 보세요.</p></div>{/if}</div><div class="pagination">{#each Array(boardPageCount) as _, index}<button class:active={currentPage === index + 1} type="button" on:click={() => (currentPage = index + 1)}>{index + 1}</button>{/each}</div></div></section>
    {:else if isPostPage}
      <section class="detail-page panel">{#if detailLoading}<div class="empty-state"><span>◌</span><strong>게시글을 불러오는 중이에요</strong></div>{:else if detailPost}<a class="back-link" href={`#board/${detailPost.boardSlug}`}>← {detailPost.category}로 돌아가기</a><div class="detail-meta"><span class="badge gold">{detailPost.category}</span><span>{detailPost.date} · {detailPost.time}</span><span>조회 {detailPost.views}</span></div><h1>{detailPost.title}</h1><div class="detail-author"><span class={`avatar ${detailPost.color}`}>{detailPost.avatar}</span><b>{detailPost.author}</b><span>작성자</span>{#if user?.id === detailPost.authorId}<button class="danger-btn" type="button" on:click={() => deletePost(detailPost)}>게시글 삭제</button>{/if}</div>{#if detailPost.boardSlug === 'npc'}<div class="npc-detail-grid">{#if detailPost.imageUrl}<img src={detailPost.imageUrl} alt={`${detailPost.title} 이미지`} />{:else}<div class="npc-detail-placeholder">이미지 없음</div>{/if}<div><dl><dt>이름</dt><dd>{detailPost.npcName || '미등록'}</dd><dt>나이</dt><dd>{detailPost.npcAge || '미등록'}</dd><dt>성별</dt><dd>{detailPost.npcGender || '미등록'}</dd><dt>키</dt><dd>{detailPost.npcHeight ? `${detailPost.npcHeight}cm` : '미등록'}</dd><dt>종족</dt><dd>{detailPost.npcRace || '미등록'}</dd><dt>역할/직업</dt><dd>{detailPost.npcRole || '미등록'}</dd><dt>소속</dt><dd>{detailPost.npcAffiliation || '미등록'}</dd><dt>성격</dt><dd>{detailPost.npcPersonality || '미등록'}</dd><dt>특징</dt><dd>{detailPost.npcTraits || '미등록'}</dd></dl></div></div>{/if}<div class="detail-body">{@html detailHtml}</div>{#if detailPost.youtubeUrl}<div class="youtube-embed"><iframe src={detailPost.youtubeUrl} title="YouTube 영상" allowfullscreen></iframe></div>{/if}<div class="detail-actions"><button class:liked={detailLiked} class="like-button" type="button" on:click={toggleLike} disabled={detailLikeSaving}>♥ 좋아요 {detailPost.likes}</button><span>댓글 {detailPost.comments}개</span></div><section class="comments-section" aria-labelledby="comments-title"><div class="comments-heading"><h2 id="comments-title">댓글</h2><span>{detailComments.length}개</span></div>{#if detailComments.length}{#each detailComments as comment}<article class="comment-item"><div class="comment-author"><span class="avatar mint">{comment.nickname.slice(0, 1)}</span><strong>{comment.nickname}</strong><time>{formatDate(comment.created_at).date}</time>{#if user?.id === comment.author_id}<button class="danger-btn" type="button" on:click={() => deleteComment(comment)}>삭제</button>{/if}</div><p>{comment.content}</p></article>{/each}{:else}<div class="comments-empty">아직 댓글이 없습니다. 첫 번째 의견을 남겨 보세요.</div>{/if}<form class="comment-form" on:submit|preventDefault={addComment}><textarea bind:value={commentText} rows="3" placeholder={user ? '이 모험에 대한 생각을 남겨 주세요.' : '로그인 후 댓글을 작성할 수 있어요.'} disabled={!user}></textarea><button class="primary-btn" type="submit" disabled={commentSaving}>{commentSaving ? '등록 중…' : '댓글 등록'} <span>↗</span></button></form></section><div class="detail-footer"><a href={`#write/${detailPost.boardSlug}`}>이 게시판에 글쓰기 <span>↗</span></a><span>모험의 기록을 함께 이어가요</span></div>{:else}<div class="empty-state"><span>?</span><strong>게시글을 찾을 수 없어요</strong><a class="text-link" href="#home">홈으로 돌아가기 →</a></div>{/if}</section>
    {:else if isWritePage || isEditPage}
      <section class="write-page panel">
        <a class="back-link" href={'#board/' + writeBoard.slug}>← {writeBoard.name}로 돌아가기</a>
        <p class="eyebrow">{isEditPage ? 'EDIT CAMPAIGN RECORD' : 'NEW CAMPAIGN RECORD'}</p>
        <h1>{isEditPage ? (writeBoardSlug === 'sessions' ? '세션 기록 수정' : '게시글 수정') : '새 이야기 작성'}</h1>
        <p class="page-lead">{isEditPage ? '등록된 기록을 같은 편집기에서 수정해 주세요.' : '게시판을 선택하고 모험의 기록을 작성해 주세요.'}</p>
        <form class="editor-form" on:submit|preventDefault={createPost}>
          <label>게시판<select bind:value={writeBoardSlug} disabled={isEditPage}>{#each categories.slice(1).filter((board) => isAdmin || board.slug === 'users' || (isEditPage && editingPostId && board.slug === writeBoardSlug)) as board}<option value={board.slug}>{board.name}</option>{/each}</select></label>
          {#if writeBoardSlug === 'notices'}<label>공지 유형<select bind:value={postForm.postType}><option value="notice">공지사항</option><option value="patch">패치노트</option><option value="event">이벤트</option></select></label>{/if}
          {#if writeBoardSlug === 'npc'}
            <div class="npc-form-section"><p class="form-hint">NPC PROFILE</p><div class="field-grid"><label>이름<input bind:value={postForm.npcName} placeholder="예: 아르델" /></label><label>나이<input bind:value={postForm.npcAge} type="number" min="0" placeholder="예: 32" /></label><label>성별<input bind:value={postForm.npcGender} placeholder="예: 여성" /></label><label>키 (cm)<input bind:value={postForm.npcHeight} type="number" min="0" step="0.1" placeholder="예: 168" /></label><label>종족<input bind:value={postForm.npcRace} placeholder="예: 인간" /></label><label>역할/직업<input bind:value={postForm.npcRole} placeholder="예: 국경 수비대장" /></label><label>소속<input bind:value={postForm.npcAffiliation} placeholder="예: 북부 연합" /></label><label>성격<input bind:value={postForm.npcPersonality} placeholder="예: 냉정하지만 약자를 돕는다" /></label><label class="field-wide">NPC 특징<textarea bind:value={postForm.npcTraits} rows="4" placeholder="외형, 능력, 말투, 관계, TRPG 진행에 필요한 특징"></textarea></label><label class="npc-photo-field field-wide"><span>프로필 이미지</span><span class="npc-photo-preview">{#if npcImagePreview}<img src={npcImagePreview} alt="NPC 미리보기" />{:else}<span class="npc-photo-empty">사진을 선택하면 여기에 미리보기됩니다</span>{/if}</span><input type="file" accept="image/png,image/jpeg,image/webp" on:change={handleNpcImageChange} /></label></div></div>
          {/if}
          {#if writeBoardSlug === 'bgm'}
            <div class="bgm-form-section"><p class="form-hint">BGM LIBRARY</p><div class="field-grid"><label>BGM 분류<select bind:value={postForm.bgmCategory}><option value="map">맵 BGM</option><option value="character">캐릭터 BGM</option><option value="scene">장면 BGM</option><option value="etc">기타 BGM</option></select></label><label class="field-wide">오디오 URL (선택)<input bind:value={postForm.bgmUrl} type="url" placeholder="https://example.com/theme.mp3" /></label><label class="bgm-file-field field-wide">오디오 파일 (선택)<input type="file" accept="audio/mpeg,audio/ogg,audio/wav,audio/x-wav,audio/mp4,audio/aac" on:change={handleBgmFileChange} />{#if postForm.bgmFile}<span>{postForm.bgmFile.name} · 업로드 예정</span>{/if}</label></div><p class="form-note">URL 또는 파일 중 하나를 등록해 주세요. 파일은 BGM 게시판에 업로드되어 세션에서 선택할 수 있습니다.</p></div>
          {/if}
          {#if writeBoardSlug !== 'npc'}<label>제목<input bind:value={postForm.title} maxlength="120" placeholder="글 제목을 입력해 주세요" /></label>{/if}
          {#if writeBoardSlug === 'sessions'}
            <div class="editor-field">
              <span>내용</span>
              <div class="session-composer">
                <div class="session-composer-head"><div><p class="eyebrow">SESSION LOG BUILDER</p><h2>플레이 기록</h2><p>+ 버튼으로 지문, 대사, 사진을 원하는 순서대로 쌓아 보세요.</p></div><div class="session-add-menu"><span>+ 항목 추가</span><button type="button" on:click={() => addSessionEntry('narration')}>지문</button><button type="button" on:click={() => addSessionEntry('dialogue')}>대사</button><button type="button" on:click={() => addSessionEntry('image')}>사진</button></div></div>
                <div class="session-participants">
                  <div class="session-participants-head"><div><strong>세션 참여자</strong><span>이번 세션에 등장한 캐릭터와 NPC를 추가해 주세요.</span></div><button class="subtle-btn" type="button" on:click={addSessionParticipant}>+ 참여자 추가</button></div>
                  {#if sessionParticipants.length}
                    <div class="session-participant-list">
                      {#each sessionParticipants as participant, participantIndex (participant.id)}
                        <div class="session-participant-row"><select value={sessionParticipantValue(participant)} on:change={(event) => setSessionParticipant(participant, event.currentTarget.value)}><option value="custom:">직접 입력</option>{#if adminCharacters.length}<optgroup label="캐릭터">{#each adminCharacters as character}<option value={'character:' + character.id}>{character.name}</option>{/each}</optgroup>{/if}{#if npcOptions.length}<optgroup label="NPC">{#each npcOptions as npc}<option value={'npc:' + npc.id}>{npc.npcName || npc.title}</option>{/each}</optgroup>{/if}</select>{#if participant.participantType === 'custom'}<input bind:value={participant.participantName} placeholder="참여자 이름" />{:else}<span>{sessionParticipantName(participant)}</span>{/if}<button class="icon-btn" type="button" on:click={() => removeSessionParticipant(participantIndex)} aria-label="참여자 삭제">×</button></div>
                      {/each}
                    </div>
                  {:else}<p class="session-participants-empty">등록된 참여자가 없습니다.</p>{/if}
                </div>
                <div class="session-bgms">
                  <div class="session-participants-head"><div><strong>세션 BGM</strong><span>이번 세션에서 사용할 등록된 BGM을 선택해 주세요.</span></div><button class="subtle-btn" type="button" on:click={addSessionBgm}>+ BGM 추가</button></div>
                  {#if bgmOptions.length}
                    {#if sessionBgmIds.length}<div class="session-bgm-list">{#each sessionBgmIds as bgmId, bgmIndex}<div class="session-bgm-row"><select value={bgmId} on:change={(event) => setSessionBgm(bgmIndex, event.currentTarget.value)}><option value="">BGM을 선택해 주세요</option>{#each bgmOptions as bgm}<option value={bgm.id}>{bgm.title} · {{ map: '맵', character: '캐릭터', scene: '장면', etc: '기타' }[bgm.bgmCategory] || 'BGM'}</option>{/each}</select><button class="icon-btn" type="button" on:click={() => removeSessionBgm(bgmIndex)} aria-label="BGM 삭제">×</button></div>{/each}</div>{:else}<p class="session-participants-empty">등록된 BGM이 없습니다. + BGM 추가를 눌러 선택해 주세요.</p>{/if}
                  {:else}<p class="session-participants-empty">등록된 BGM이 없습니다. <a href="#board/bgm">BGM 게시판에서 먼저 등록해 주세요.</a></p>{/if}
                </div>
                <div class="session-entry-list">
                  {#if sessionEntries.length}
                    {#each sessionEntries as entry, index (entry.id)}
                      <article class={'session-entry session-entry-' + entry.type}>
                        <div class="session-entry-top"><span class="session-entry-number">{String(index + 1).padStart(2, '0')}</span><strong>{entry.type === 'narration' ? '지문' : entry.type === 'dialogue' ? '대사' : '사진'}</strong><div class="session-entry-actions"><button class="icon-btn" type="button" disabled={index === 0} on:click={() => moveSessionEntry(index, -1)} aria-label="위로 이동">↑</button><button class="icon-btn" type="button" disabled={index === sessionEntries.length - 1} on:click={() => moveSessionEntry(index, 1)} aria-label="아래로 이동">↓</button><button class="icon-btn" type="button" on:click={() => removeSessionEntry(index)} aria-label="항목 삭제">×</button></div></div>
                        {#if entry.type === 'narration'}
                          <div class="session-entry-meta"><label>지문의 주체<select value={sessionActorValue(entry)} on:change={(event) => setSessionActor(entry, event.currentTarget.value)}><option value="none:">없음</option><option value="custom:">직접 입력</option>{#if adminCharacters.length}<optgroup label="캐릭터">{#each adminCharacters as character}<option value={'character:' + character.id}>{character.name}</option>{/each}</optgroup>{/if}{#if npcOptions.length}<optgroup label="NPC">{#each npcOptions as npc}<option value={'npc:' + npc.id}>{npc.npcName || npc.title}</option>{/each}</optgroup>{/if}</select></label>{#if entry.actorType === 'custom'}<label>이름<input bind:value={entry.actorName} placeholder="지문을 묘사하는 이름" /></label>{/if}</div>
                        {:else if entry.type === 'dialogue'}
                          <div class="session-entry-meta"><label>말한 사람<select value={sessionSpeakerValue(entry)} on:change={(event) => setSessionSpeaker(entry, event.currentTarget.value)}><option value="anonymous:">??? (얼굴 없는 대사)</option><option value="custom:">직접 입력</option>{#if adminCharacters.length}<optgroup label="캐릭터">{#each adminCharacters as character}<option value={'character:' + character.id}>{character.name}</option>{/each}</optgroup>{/if}{#if npcOptions.length}<optgroup label="NPC">{#each npcOptions as npc}<option value={'npc:' + npc.id}>{npc.npcName || npc.title}</option>{/each}</optgroup>{/if}</select></label>{#if entry.speakerType === 'custom'}<label>이름<input bind:value={entry.speakerName} placeholder="대사 이름" /></label>{/if}</div>
                        {:else}
                          <label class="session-image-picker">사진<input type="file" accept="image/png,image/jpeg,image/webp" on:change={(event) => handleSessionImageChange(event, index)} />{#if entry.imageUrl}<img src={entry.imageUrl} alt="세션 사진 미리보기" />{:else}<span>사진을 선택해 주세요</span>{/if}</label>
                          <label>사진 설명 (선택)<input bind:value={entry.caption} placeholder="장면 설명이나 사진 캡션" /></label>
                        {/if}
                        {#if entry.type !== 'image'}<label class="session-entry-text">{entry.type === 'narration' ? '지문 내용' : '대사 내용'}<textarea bind:value={entry.text} rows="4" placeholder={entry.type === 'narration' ? '행동, 분위기, 상황을 적어 주세요.' : '캐릭터 또는 NPC의 대사를 적어 주세요.'}></textarea></label>{/if}
                      </article>
                    {/each}
                  {:else}<div class="session-entry-empty"><strong>아직 항목이 없습니다</strong><span>위의 + 항목 추가에서 지문, 대사, 사진을 골라 주세요.</span></div>{/if}
                </div>
              </div>
            </div>
          {:else}
            <div class="editor-field"><span>{writeBoardSlug === 'npc' ? '상세 설명' : '내용'}</span>{#if writeBoardSlug === 'users'}<div class="rich-editor-host" bind:this={richEditorElement}></div>{:else}<textarea bind:value={postForm.content} rows="14" placeholder={writeBoardSlug === 'npc' ? 'TRPG 진행에 필요한 추가 설명을 작성해 주세요' : '모험의 기록을 남겨 주세요'}></textarea>{/if}</div>
          {/if}
          <div class="form-actions"><a class="text-link" href={'#board/' + writeBoard.slug}>취소</a><button class="primary-btn" type="submit" disabled={postSaving || (isEditPage && editLoading)}>{postSaving ? '저장 중…' : editLoading ? '기존 내용 불러오는 중…' : editingPostId ? (writeBoardSlug === 'sessions' ? '세션 기록 수정' : '게시글 수정') : '게시글 등록'} <span>↗</span></button></div>
        </form>
      </section>
    {:else if isAdminMypage && (!authReady || profileLoading)}
      <section class="admin-mypage panel"><div class="empty-state"><span>◌</span><strong>관리자 정보를 불러오는 중이에요</strong></div></section>
    {:else if isAdminMypage && isAdmin}
      <section class="admin-mypage panel"><div class="page-heading"><p class="eyebrow">ADMIN ACCOUNT</p><h1>관리자 마이페이지</h1><p>관리자 표시명과 로그인 비밀번호를 변경할 수 있습니다.</p></div><form class="editor-form admin-profile-form" on:submit|preventDefault={saveAdminProfile}><label>표시명<input bind:value={adminProfileForm.nickname} maxlength="40" placeholder="표시명" /></label><label>새 비밀번호<input bind:value={adminProfileForm.newPassword} type="password" minlength="8" autocomplete="new-password" placeholder="변경할 때만 입력" /></label><label>새 비밀번호 확인<input bind:value={adminProfileForm.confirmPassword} type="password" minlength="8" autocomplete="new-password" placeholder="새 비밀번호를 다시 입력" /></label><div class="form-actions"><button class="primary-btn" type="submit" disabled={adminProfileSaving}>{adminProfileSaving ? '저장 중…' : '계정 정보 저장'} <span>↗</span></button></div></form><div class="admin-mypage-links"><a class="text-link" href="#admin">관리자 페이지로 이동 <span>→</span></a></div></section>
    {:else if isAdminMypage}
      <section class="about-page panel"><p class="eyebrow">ACCESS RESTRICTED</p><h1>관리자 권한이<br /><em>필요합니다</em></h1><p class="about-lead">이 페이지는 관리자 계정만 이용할 수 있습니다.</p><a class="primary-btn about-button" href="#home">홈으로 돌아가기 <span>→</span></a></section>
    {:else if isMyPage}
      <section class="mypage panel"><div class="page-heading"><p class="eyebrow">ADVENTURER PROFILE</p><h1>마이페이지</h1><p>{profile?.nickname || '모험가'}님의 캐릭터와 소지품을 관리하는 공간입니다.</p></div>{#if characterError}<div class="error-box">캐릭터 테이블을 확인해 주세요: {characterError}</div>{/if}{#if characterLoading}<div class="empty-state"><span>◌</span><strong>캐릭터 정보를 불러오는 중이에요</strong></div>{:else}<div class="profile-layout"><aside class="profile-sidebar"><button class:active={profileSection === 'basic'} type="button" on:click={() => (profileSection = 'basic')}>기본 정보<span>CHARACTER</span></button><button class:active={profileSection === 'combat'} type="button" on:click={() => (profileSection = 'combat')}>전투 정보<span>COMBAT</span></button><button class:active={profileSection === 'extra'} type="button" on:click={() => (profileSection = 'extra')}>추가 기록<span>EXTRA NOTES</span></button><button class:active={profileSection === 'relationships'} type="button" on:click={() => (profileSection = 'relationships')}>관계<span>RELATIONSHIPS</span></button><button class:active={profileSection === 'inventory'} type="button" on:click={() => (profileSection = 'inventory')}>인벤토리<span>INVENTORY</span></button><button class:active={profileSection === 'cards'} type="button" on:click={() => (profileSection = 'cards')}>보유 카드<span>CARDS</span></button></aside><form class="character-form profile-content" on:submit|preventDefault={saveCharacter}>{#if profileSection === 'basic'}<div class="form-section"><div class="form-section-head"><div><p class="eyebrow">CHARACTER SHEET</p><h2>캐릭터 기본 정보</h2></div></div><div class="profile-photo-row"><label class="profile-photo-field"><span>프로필 이미지</span><span class="profile-photo-preview">{#if profileImagePreview}<img src={profileImagePreview} alt="프로필 미리보기" />{:else}<span>사진을 선택해 주세요</span>{/if}</span><input type="file" accept="image/png,image/jpeg,image/webp" on:change={handleProfileImageChange} /></label><div class="field-grid profile-fields"><label>이름<input bind:value={characterForm.name} placeholder="캐릭터 이름" /></label><label>역할명<input bind:value={characterForm.roleName} placeholder="역할명" /></label><label>나이<input bind:value={characterForm.age} type="number" min="0" placeholder="예: 27" /></label><label>키 (cm)<input bind:value={characterForm.height} type="number" min="0" step="0.1" placeholder="예: 172" /></label><label>몸무게 (kg)<input bind:value={characterForm.weight} type="number" min="0" step="0.1" placeholder="예: 64" /></label><label class="field-wide">특징<textarea bind:value={characterForm.roleTraits} rows="3" placeholder="역할의 특징, 성격, 전투 방식"></textarea></label></div></div><div class="form-actions"><button class="primary-btn" type="submit" disabled={characterSaving}>{characterSaving ? '저장 중…' : '기본 정보 저장'} <span>↗</span></button></div></div>{:else if profileSection === 'combat'}<div class="form-section combat-section"><div class="form-section-head"><div><p class="eyebrow">COMBAT STATUS</p><h2>전투 정보</h2></div></div><div class="combat-grid"><label>레벨<input value={character?.level ?? 1} disabled /></label><label>돈<input value={character?.money ?? 0} disabled /></label><label>HP<input value={`${character?.hp ?? 0} / ${character?.max_hp ?? 0}`} disabled /></label></div><p class="form-note">{character?.combat_notes || '등록된 전투 메모가 없습니다.'}</p></div>{:else if profileSection === 'extra'}<div class="form-section extra-record-section"><div class="form-section-head"><div><p class="eyebrow">PERSONAL NOTES</p><h2>추가 기록</h2></div><span class="form-hint">게시판형 기록</span></div>{#if extraRecords.length}<div class="record-board">{#each extraRecords as record}<article class="record-board-item"><div class="record-board-meta"><strong>{record.title}</strong><span>{record.authorName} · {new Date(record.created_at).toLocaleDateString('ko-KR')}</span></div><p>{record.content}</p>{#if isAdmin || record.author_id === user?.id}<button class="record-delete" type="button" on:click={() => deleteExtraRecord(record)}>기록 삭제</button>{/if}</article>{/each}</div>{:else}<div class="repeat-empty">등록된 추가 기록이 없습니다.</div>{/if}<div class="record-compose"><input bind:value={extraRecordForm.title} placeholder="기록 제목" /><textarea bind:value={extraRecordForm.content} rows="5" placeholder="소환수, 개인 특징, 장기 목표 등 기록할 내용을 작성해 주세요."></textarea><button class="primary-btn" type="button" on:click={saveExtraRecord} disabled={extraRecordSaving}>{extraRecordSaving ? '등록 중…' : '기록 등록'} <span>↗</span></button></div></div>{:else if profileSection === 'relationships'}<div class="form-section relationship-section"><div class="form-section-head"><div><p class="eyebrow">RELATIONSHIPS</p><h2>관계</h2></div><span class="form-hint">호감도 없이 메모로 관리</span></div>{#if relationships.length}<div class="relationship-list">{#each relationships as relationship}<article class="relationship-item"><div class="relationship-item-head"><strong>{relationship.relationship_name}</strong>{#if relationship.npc_post_id}<a href={'#post/' + relationship.npc_post_id}>{relationship.npcTitle || 'NPC 페이지 열기'} ↗</a>{/if}</div>{#if relationship.memo}<p>{relationship.memo}</p>{/if}<button class="record-delete" type="button" on:click={() => deleteRelationship(relationship)}>관계 삭제</button></article>{/each}</div>{:else}<div class="repeat-empty">등록된 관계가 없습니다.</div>{/if}<div class="relationship-compose"><input bind:value={relationshipForm.name} placeholder="관계 이름 (예: 아르델과의 관계)" /><select bind:value={relationshipForm.npcPostId}><option value="">NPC 링크 없음</option>{#each npcOptions as npc}<option value={npc.id}>{npc.title}</option>{/each}</select><textarea bind:value={relationshipForm.memo} rows="5" placeholder="관계 메모를 작성해 주세요."></textarea><button class="primary-btn" type="button" on:click={saveRelationship} disabled={relationshipSaving}>{relationshipSaving ? '등록 중…' : '관계 등록'} <span>↗</span></button></div></div>{:else if profileSection === 'inventory'}<div class="form-section readonly-collection"><div class="form-section-head"><div><p class="eyebrow">INVENTORY</p><h2>인벤토리</h2></div></div>{#if inventory.length}<div class="inventory-game-layout"><div class="inventory-slots">{#each inventory as item}<button class:active={selectedInventoryItem?.id === item.id} class="inventory-slot" type="button" on:click={() => selectInventoryItem(item)}><span class="slot-icon">{#if isImageIcon(getInventoryIcon(item)) }<img src={getInventoryIcon(item)} alt="" />{:else}{getInventoryIcon(item)}{/if}</span><span class="slot-count">{item.quantity}</span></button>{/each}</div>{#if selectedInventoryItem}<article class="inventory-detail"><div class="inventory-detail-icon">{#if isImageIcon(getInventoryIcon(selectedInventoryItem)) }<img src={getInventoryIcon(selectedInventoryItem)} alt="" />{:else}{getInventoryIcon(selectedInventoryItem)}{/if}</div><div><p class="eyebrow">ITEM DETAIL</p><h3>{selectedInventoryItem.item_name}</h3><p>{selectedInventoryItem.item_effect || '등록된 효과가 없습니다.'}</p><div><span class="tag">{selectedInventoryItem.grade}</span><span class="tag">{selectedInventoryItem.item_type}</span><span class="inventory-quantity">× {selectedInventoryItem.quantity}</span></div></div></article>{:else}<div class="inventory-detail empty"><span>아이템을 선택하세요</span></div>{/if}</div>{:else}<div class="repeat-empty">등록된 아이템이 없습니다.</div>{/if}</div>{:else}<div class="form-section readonly-collection"><div class="form-section-head"><div><p class="eyebrow">CARDS</p><h2>보유 카드</h2></div></div>{#if cards.length}<div class="cards-grid">{#each cards as card}<article class="owned-card"><div class="owned-card-top"><strong>{card.card_name}</strong><span>{card.energy || 0} energy</span></div><p>{card.card_effect || '등록된 효과가 없습니다.'}</p><div><span class="tag">{card.grade}</span><span class="inventory-quantity">× {card.quantity}</span></div></article>{/each}</div>{:else}<div class="repeat-empty">등록된 카드가 없습니다.</div>{/if}</div>{/if}</form></div>{/if}</section>
    {:else if isAdminCharacterPage && (!authReady || profileLoading || adminDetailLoading)}
      <section class="character-detail-page panel"><div class="empty-state"><span>◌</span><strong>캐릭터 상세 정보를 불러오는 중이에요</strong></div></section>
    {:else if isAdminCharacterPage && isAdmin && adminSelectedCharacter}
      <section class="character-detail-page panel"><a class="back-link" href="#admin">← 관리자 관리 페이지로 돌아가기</a><div class="admin-detail-header">{#if adminSelectedCharacter.avatar_url}<img src={adminSelectedCharacter.avatar_url} alt={`${adminSelectedCharacter.name} 프로필 사진`} />{:else}<span class="admin-detail-avatar">{adminSelectedCharacter.name.slice(0, 1)}</span>{/if}<div><p class="eyebrow">CHARACTER PROFILE</p><h1>{adminSelectedCharacter.name}</h1><p>{adminSelectedCharacter.nickname || '모험가'} · {adminSelectedCharacter.role_name || '역할 미등록'}</p></div><button class="danger-btn" type="button" on:click={deleteAdminCharacter}>캐릭터 삭제</button></div><form class="character-form" on:submit|preventDefault={saveAdminCharacter}><div class="form-section admin-detail-section"><div class="form-section-head"><div><p class="eyebrow">CHARACTER SHEET</p><h2>기본 정보</h2></div></div><div class="field-grid"><label>캐릭터 이름<input bind:value={adminCharacterForm.name} /></label><label>역할명<input bind:value={adminCharacterForm.roleName} /></label><label>나이<input bind:value={adminCharacterForm.age} type="number" min="0" /></label><label>키 (cm)<input bind:value={adminCharacterForm.height} type="number" min="0" step="0.1" /></label><label>몸무게 (kg)<input bind:value={adminCharacterForm.weight} type="number" min="0" step="0.1" /></label><label class="field-wide">역할 특징<textarea bind:value={adminCharacterForm.roleTraits} rows="5"></textarea></label></div></div><div class="form-section admin-detail-section"><div class="form-section-head"><div><p class="eyebrow">COMBAT STATUS</p><h2>전투 정보</h2></div></div><div class="combat-grid"><label>레벨<input bind:value={adminCharacterForm.level} type="number" min="1" /></label><label>돈<input bind:value={adminCharacterForm.money} type="number" min="0" /></label><label>현재 HP<input bind:value={adminCharacterForm.hp} type="number" min="0" /></label><label>최대 HP<input bind:value={adminCharacterForm.maxHp} type="number" min="0" /></label><label class="field-wide">전투 메모<textarea bind:value={adminCharacterForm.combatNotes} rows="3"></textarea></label></div></div><div class="form-section admin-detail-section extra-record-section"><div class="form-section-head"><div><p class="eyebrow">PERSONAL NOTES</p><h2>추가 기록</h2></div><span class="form-hint">게시판형 기록</span></div>{#if extraRecords.length}<div class="record-board">{#each extraRecords as record}<article class="record-board-item"><div class="record-board-meta"><strong>{record.title}</strong><span>{record.authorName} · {new Date(record.created_at).toLocaleDateString('ko-KR')}</span></div><p>{record.content}</p>{#if isAdmin || record.author_id === user?.id}<button class="record-delete" type="button" on:click={() => deleteExtraRecord(record)}>기록 삭제</button>{/if}</article>{/each}</div>{:else}<div class="repeat-empty">등록된 추가 기록이 없습니다.</div>{/if}<div class="record-compose"><input bind:value={extraRecordForm.title} placeholder="기록 제목" /><textarea bind:value={extraRecordForm.content} rows="5" placeholder="소환수, 개인 특징, 장기 목표 등 기록할 내용을 작성해 주세요."></textarea><button class="primary-btn" type="button" on:click={saveExtraRecord} disabled={extraRecordSaving}>{extraRecordSaving ? '등록 중…' : '기록 등록'} <span>↗</span></button></div></div><div class="form-section admin-detail-section"><div class="form-section-head"><div><p class="eyebrow">INVENTORY</p><h2>인벤토리</h2></div><div class="form-head-actions"><a class="subtle-btn" href="#admin-items">아이템 테이블 관리</a><button class="subtle-btn" type="button" on:click={newAdminInventoryItem}>+ 직접 입력</button></div></div><div class="inventory-picker"><input bind:value={inventorySearch} placeholder="아이템 테이블에서 검색해 인벤토리에 추가" />{#if itemCatalogError}<div class="repeat-empty">아이템 목록을 불러오지 못했습니다: {itemCatalogError}</div>{:else if itemCatalogLoading}<div class="repeat-empty">아이템 목록을 불러오는 중이에요.</div>{:else if inventorySearch.trim()}{#if inventorySearchResults.length}<div class="inventory-picker-results">{#each inventorySearchResults as catalogItem}<button class="inventory-picker-result" type="button" on:click={() => addCatalogItemToInventory(catalogItem)}><span class="admin-item-icon">{#if isImageIcon(catalogItemIcon(catalogItem))}<img src={catalogItemIcon(catalogItem)} alt="" />{:else}{catalogItemIcon(catalogItem)}{/if}</span><span class="inventory-picker-copy"><strong>{catalogItem.name}</strong><small>{catalogItem.grade} · {catalogItem.item_type}</small></span><span class="inventory-picker-add">+ 담기</span></button>{/each}</div>{:else}<div class="repeat-empty">검색 결과가 없습니다. 아이템 추가 페이지에서 먼저 등록해 주세요.</div>{/if}{/if}</div>{#if adminInventory.length}<div class="admin-inventory-grid">{#each adminInventory as item, index}<article class="admin-inventory-card"><div class="admin-item-icon">{#if isImageIcon(getInventoryIcon(item))}<img src={getInventoryIcon(item)} alt="" />{:else}{getInventoryIcon(item)}{/if}</div><div class="admin-item-fields"><input bind:value={item.item_name} placeholder="아이템명" /><textarea bind:value={item.item_effect} rows="3" placeholder="아이템 효과"></textarea><div class="admin-item-meta"><input bind:value={item.quantity} type="number" min="1" placeholder="개수" /><select bind:value={item.grade}>{#each inventoryGrades as grade}<option>{grade}</option>{/each}</select><select bind:value={item.item_type}>{#each inventoryTypes as type}<option>{type}</option>{/each}</select></div><label class="item-image-picker">아이콘 이미지<input type="file" accept="image/png,image/jpeg,image/webp" on:change={(event) => handleAdminInventoryImage(event, index)} /></label></div><button class="icon-btn" type="button" on:click={() => removeAdminInventory(index)} aria-label="아이템 삭제">×</button></article>{/each}</div>{:else}<div class="repeat-empty">등록된 아이템이 없습니다.</div>{/if}</div><div class="form-section admin-detail-section"><div class="form-section-head"><div><p class="eyebrow">CARDS</p><h2>보유 카드</h2></div><button class="subtle-btn" type="button" on:click={newAdminCard}>+ 카드 추가</button></div>{#if adminCards.length}<div class="admin-cards-grid">{#each adminCards as card, index}<article class="admin-card-editor"><div class="owned-card-top"><input bind:value={card.card_name} placeholder="카드명" /><span>{card.energy || 0} energy</span></div><textarea bind:value={card.card_effect} rows="4" placeholder="카드 효과"></textarea><div class="admin-item-meta"><input bind:value={card.quantity} type="number" min="1" placeholder="개수" /><input bind:value={card.energy} type="number" min="0" placeholder="사용 에너지" /><select bind:value={card.grade}>{#each cardGrades as grade}<option>{grade}</option>{/each}</select><button class="icon-btn" type="button" on:click={() => removeAdminCard(index)} aria-label="카드 삭제">×</button></div></article>{/each}</div>{:else}<div class="repeat-empty">등록된 카드가 없습니다.</div>{/if}</div><div class="form-actions admin-detail-actions"><button class="primary-btn" type="submit" disabled={adminCharacterSaving}>{adminCharacterSaving ? '저장 중…' : '변경사항 저장'} <span>↗</span></button></div></form></section>
    {:else if isAdminPage && (!authReady || profileLoading)}
      <section class="about-page panel"><p class="eyebrow">CHECKING ACCESS</p><h1>관리자 권한을<br /><em>확인하는 중입니다</em></h1><p class="about-lead">잠시만 기다려 주세요.</p></section>
    {:else if isAdminPage && isAdmin}
      <section class="admin-page panel"><div class="page-heading"><p class="eyebrow">CAMPAIGN ADMIN</p><h1>관리자 관리 페이지</h1><p>플레이어 계정과 캐릭터 정보를 관리합니다.</p></div><div class="admin-shell"><aside class="profile-sidebar admin-sidebar"><a class="active" href="#admin">사용자 관리<span>PLAYERS</span></a><a href="#admin-items">아이템 추가<span>ITEMS</span></a></aside><div class="admin-shell-content"><div class="admin-layout"><section class="admin-card"><div class="form-section-head"><div><p class="eyebrow">ADVENTURER ACCOUNTS</p><h2>플레이어 계정 · 캐릭터 생성</h2></div></div><form class="editor-form" on:submit|preventDefault={createPlayerAccount}><div class="field-grid"><label>로그인 아이디<input bind:value={adminForm.loginId} placeholder="플레이어 아이디" /></label><label>초기 비밀번호<input bind:value={adminForm.password} type="password" minlength="8" placeholder="8자 이상" /></label><label>표시 이름<input bind:value={adminForm.nickname} placeholder="플레이어 이름" /></label><label>캐릭터 이름<input bind:value={adminForm.character.name} placeholder="캐릭터 이름" /></label><label>역할명<input bind:value={adminForm.character.roleName} placeholder="역할명" /></label><label>나이<input bind:value={adminForm.character.age} type="number" min="0" placeholder="나이" /></label><label class="field-wide">역할 특징<textarea bind:value={adminForm.character.roleTraits} rows="3" placeholder="역할의 특징"></textarea></label><label>키 (cm)<input bind:value={adminForm.character.height} type="number" min="0" step="0.1" /></label><label>몸무게 (kg)<input bind:value={adminForm.character.weight} type="number" min="0" step="0.1" /></label></div><button class="primary-btn" type="submit" disabled={accountSaving}>{accountSaving ? '생성 중…' : '계정과 캐릭터 생성'} <span>↗</span></button></form><p class="form-note">로그인 아이디는 이메일 형식이나 영문·숫자 형식으로 제한하지 않습니다. 비밀번호만 8자 이상 입력해 주세요.</p></section><section class="admin-card"><div class="form-section-head"><div><p class="eyebrow">마이페이지 관리</p><h2>전체 캐릭터 목록</h2></div></div>{#if adminLoading}<div class="repeat-empty">목록을 불러오는 중이에요.</div>{:else if adminCharacters.length}{#each adminCharacters as item}<div class="character-list-item"><span class="avatar mint">{item.name.slice(0, 1)}</span><div><strong>{item.name}</strong><p>{item.nickname} · {item.role_name || '역할 미등록'}</p></div><span class="character-age">{item.age ? `${item.age}세` : '나이 미등록'}</span><button class="subtle-btn character-view-btn" type="button" on:click={() => selectAdminCharacter(item)}>상세보기</button></div>{/each}{:else}<div class="repeat-empty">아직 등록된 캐릭터가 없습니다.</div>{/if}</section><section class="admin-card character-detail-card">{#if adminSelectedCharacter}<div class="form-section-head"><div><p class="eyebrow">CHARACTER DETAIL</p><h2>{adminSelectedCharacter.name}</h2></div><button class="danger-btn" type="button" on:click={deleteAdminCharacter}>캐릭터 삭제</button></div><form class="editor-form" on:submit|preventDefault={saveAdminCharacter}><div class="field-grid"><label>캐릭터 이름<input bind:value={adminCharacterForm.name} /></label><label>역할명<input bind:value={adminCharacterForm.roleName} /></label><label class="field-wide">역할 특징<textarea bind:value={adminCharacterForm.roleTraits} rows="5"></textarea></label><label>나이<input bind:value={adminCharacterForm.age} type="number" min="0" /></label><label>키 (cm)<input bind:value={adminCharacterForm.height} type="number" min="0" step="0.1" /></label><label>몸무게 (kg)<input bind:value={adminCharacterForm.weight} type="number" min="0" step="0.1" /></label></div><div class="form-actions"><button class="primary-btn" type="submit" disabled={adminCharacterSaving}>{adminCharacterSaving ? '저장 중…' : '캐릭터 정보 저장'} <span>↗</span></button></div></form>{:else}<div class="character-detail-empty"><span>✦</span><strong>캐릭터를 선택해 주세요</strong><p>목록에서 상세보기를 누르면 정보를 수정하거나 삭제할 수 있습니다.</p></div>{/if}</section></div></div></div></section>
    {:else if isAdminPage}
      <section class="about-page panel"><p class="eyebrow">ACCESS RESTRICTED</p><h1>관리자 권한이<br /><em>필요합니다</em></h1><p class="about-lead">이 페이지는 캠페인 관리자만 이용할 수 있습니다.</p><a class="primary-btn about-button" href={user ? '#mypage' : '#home'}>{user ? '마이페이지로 돌아가기' : '홈으로 돌아가기'} <span>→</span></a></section>
    {:else if isAdminItemsPage && (!authReady || profileLoading)}
      <section class="about-page panel"><p class="eyebrow">CHECKING ACCESS</p><h1>관리자 권한을<br /><em>확인하는 중입니다</em></h1><p class="about-lead">잠시만 기다려 주세요.</p></section>
    {:else if isAdminItemsPage && isAdmin}
      <section class="admin-page panel"><div class="page-heading"><p class="eyebrow">ITEM CATALOG</p><h1>아이템 추가</h1><p>아이템을 아이템 테이블에 등록하면 캐릭터 인벤토리에서 검색해 담을 수 있습니다.</p></div><div class="admin-shell"><aside class="profile-sidebar admin-sidebar"><a href="#admin">사용자 관리<span>PLAYERS</span></a><a class="active" href="#admin-items">아이템 추가<span>ITEMS</span></a></aside><div class="admin-shell-content"><div class="admin-layout"><section class="admin-card"><div class="form-section-head"><div><p class="eyebrow">{itemForm.id ? 'EDIT ITEM' : 'NEW ITEM'}</p><h2>{itemForm.id ? '아이템 수정' : '아이템 등록'}</h2></div>{#if itemForm.id}<button class="subtle-btn" type="button" on:click={resetItemForm}>새 아이템 작성</button>{/if}</div><form class="editor-form" on:submit|preventDefault={saveItem}><div class="field-grid"><label>아이템 이름<input bind:value={itemForm.name} placeholder="예: 치유 물약" /></label><label>등급<select bind:value={itemForm.grade}>{#each inventoryGrades as grade}<option>{grade}</option>{/each}</select></label><label>종류<select bind:value={itemForm.item_type}>{#each inventoryTypes as type}<option>{type}</option>{/each}</select></label><label class="item-image-picker">아이콘 이미지<input type="file" accept="image/png,image/jpeg,image/webp" on:change={handleItemIconChange} /></label><label class="field-wide">아이템 효과<textarea bind:value={itemForm.effect} rows="4" placeholder="아이템 효과와 설명"></textarea></label></div><div class="item-form-preview"><span class="admin-item-icon">{#if isImageIcon(catalogItemIcon(itemForm))}<img src={catalogItemIcon(itemForm)} alt="" />{:else}{catalogItemIcon(itemForm)}{/if}</span><span>{itemForm.name || '아이템 미리보기'}</span></div><div class="form-actions"><button class="primary-btn" type="submit" disabled={itemSaving}>{itemSaving ? '저장 중…' : itemForm.id ? '아이템 수정' : '아이템 등록'} <span>↗</span></button></div></form></section><section class="admin-card"><div class="form-section-head"><div><p class="eyebrow">ITEM LIST</p><h2>등록된 아이템</h2></div><span class="form-hint">{itemCatalog.length}개</span></div><input class="item-search" bind:value={itemSearch} placeholder="아이템 이름 · 효과 검색" />{#if itemCatalogLoading}<div class="repeat-empty">아이템 목록을 불러오는 중이에요.</div>{:else if itemCatalogError}<div class="error-box">아이템 테이블을 확인해 주세요: {itemCatalogError}</div>{:else if filteredItemCatalog.length}<div class="item-catalog-list">{#each filteredItemCatalog as item}<article class="item-catalog-row"><span class="admin-item-icon">{#if isImageIcon(catalogItemIcon(item))}<img src={catalogItemIcon(item)} alt="" />{:else}{catalogItemIcon(item)}{/if}</span><div class="item-catalog-copy"><strong>{item.name}</strong><small>{item.grade} · {item.item_type}</small><p>{item.effect || '등록된 효과가 없습니다.'}</p></div><div class="item-catalog-actions"><button class="subtle-btn" type="button" on:click={() => editItem(item)}>수정</button><button class="danger-btn" type="button" on:click={() => deleteItem(item)}>삭제</button></div></article>{/each}</div>{:else}<div class="repeat-empty">등록된 아이템이 없습니다.</div>{/if}</section></div></div></div></section>
    {:else if isAdminItemsPage}
      <section class="about-page panel"><p class="eyebrow">ACCESS RESTRICTED</p><h1>관리자 권한이<br /><em>필요합니다</em></h1><p class="about-lead">이 페이지는 캠페인 관리자만 이용할 수 있습니다.</p><a class="primary-btn about-button" href={user ? '#mypage' : '#home'}>{user ? '마이페이지로 돌아가기' : '홈으로 돌아가기'} <span>→</span></a></section>
     {/if}
     {/key}
   </main>
  {#if isAdminCharacterPage && adminSelectedCharacter?.avatar_url}<section class="admin-profile-photo panel"><p class="eyebrow">PLAYER PROFILE PHOTO</p><img src={adminSelectedCharacter.avatar_url} alt={`${adminSelectedCharacter.name} 프로필 사진`} /><strong>{adminSelectedCharacter.name}</strong></section>{/if}
  {#if isMyPage && profileSection === 'inventory'}<section class="inventory-game-panel panel"><div class="section-head"><div><p class="eyebrow">INVENTORY SLOTS</p><h2>인벤토리</h2></div><span class="form-hint">아이콘을 클릭하면 상세 정보가 표시됩니다</span></div>{#if inventory.length}<div class="inventory-game-layout"><div class="inventory-slots">{#each inventory as item}<button class:active={selectedInventoryItem?.id === item.id} class="inventory-slot" type="button" on:click={() => selectInventoryItem(item)}><span class="slot-icon">{#if isImageIcon(getInventoryIcon(item)) }<img src={getInventoryIcon(item)} alt="" />{:else}{getInventoryIcon(item)}{/if}</span><span class="slot-count">{item.quantity}</span></button>{/each}</div>{#if selectedInventoryItem}<article class="inventory-detail"><div class="inventory-detail-icon">{#if isImageIcon(getInventoryIcon(selectedInventoryItem)) }<img src={getInventoryIcon(selectedInventoryItem)} alt="" />{:else}{getInventoryIcon(selectedInventoryItem)}{/if}</div><div><p class="eyebrow">ITEM DETAIL</p><h3>{selectedInventoryItem.item_name}</h3><p>{selectedInventoryItem.item_effect || '등록된 효과가 없습니다.'}</p><div><span class="tag">{selectedInventoryItem.grade}</span><span class="tag">{selectedInventoryItem.item_type}</span><span class="inventory-quantity">× {selectedInventoryItem.quantity}</span></div></div></article>{:else}<div class="inventory-detail empty"><span>아이템을 선택하세요</span></div>{/if}</div>{:else}<div class="repeat-empty">등록된 아이템이 없습니다.</div>{/if}</section>{/if}
  <footer class="footer"><div class="footer-brand"><span class="brand-mark">od</span><span>open door</span></div><span>장기 TRPG 캠페인을 위한 세계관 기록소</span><span>아이콘: Caro Asercion / game-icons.net</span><span>© 2026 OPEN DOOR</span></footer>
</div>

{#if notice}<div class="toast" role="status"><span>✓</span>{notice}</div>{/if}
{#if showLogin && !user}<div class="backdrop" role="presentation" on:click={() => (showLogin = false)}><dialog open class="modal" aria-labelledby="login-title" on:click|stopPropagation><button class="close" on:click={() => (showLogin = false)} aria-label="닫기">×</button><div class="modal-mark">od</div><p class="eyebrow">ADVENTURER ACCESS</p><h2 id="login-title">모험가 계정으로<br />입장하기</h2><p class="modal-intro">관리자에게 발급받은 아이디와 비밀번호로<br />캠페인 기록소에 입장할 수 있습니다.</p><form class="login-form" on:submit|preventDefault={handleLogin}><label>아이디<input bind:value={loginId} type="text" placeholder="adventurer_01" autocomplete="username" /></label><label>비밀번호<input bind:value={loginPassword} type="password" placeholder="••••••••" autocomplete="current-password" /></label><button class="submit" type="submit">입장하기 <span>→</span></button></form><p class="modal-note">계정 발급 및 변경은 캠페인 관리자에게 문의해 주세요.</p></dialog></div>{/if}
