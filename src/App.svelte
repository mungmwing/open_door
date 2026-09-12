<script>
  import { onMount, afterUpdate, tick } from 'svelte';
  import { supabase, supabaseConfig } from './supabaseClient';
  import { renderSafePostMarkdown } from './lib/postRendering';
  import { plainNpcName, mergeSessionReferences } from './lib/sessionReferences';
  import DOMPurify from 'dompurify';
  import HomePage from './pages/HomePage.svelte';
  import { defaultPersonalEnergy, prepareResourceSave, prepareConsumableSave } from './lib/combatResources';
  import { buildAdminCardRows, normalizeOwnedCard, prepareCardSave } from './lib/cardPersistence';
  import { prepareRelicSave } from './lib/combatExpansion';
  import { formatCombatTestCards } from './lib/combatTest';

  let BoardPage;
  let PostDetailPage;
  let AdminItemsPage;
  let AdminMonstersPage;
  let WritePage;
  let MyPage;
  let AdminMypage;
  let AdminPage;
  let AdminCharacterPage;
  let ShopPage;
  let AdminShopPage;
  let AdminCombatTestPage;
  let CombatPage;
  let MiniGamesPage;
  let DiceRollerPage;
  const routeComponentPromises = new Map();

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
  const inventoryTypes = ['유물', '장비', '소비', '상자', '기타'];
  const cardGrades = ['기본', '일반', '고급', '희귀', '특수'];

  let showLogin = false;
  let notice = '';
  let loginId = '';
  let loginPassword = '';
  let session = null;
  let user = null;
  let profile = null;
  let profileAccentColor = '#d8bd75';
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
  let databaseLoadedAt = 0;
  let databaseLoadPromise;
  let categories = fallbackCategories;
  let notices = [];
  let posts = [];
  let sessionMetadataLoaded = false;
  let sessionMetadataPromise;
  let detailPost = null;
  let detailHtml = '';
  let privatePostUnlocked = false;
  let privatePostError = '';
  let detailRequestId = 0;
  let detailLoading = false;
  let detailError = '';
  let detailController;
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
  let draggedSessionEntryId = '';
  let sessionDragPointerY = 0;
  let sessionDragScrollFrame = 0;
  let sessionDragEventsReady = false;
  let sessionParticipants = [];
  let sessionActorParticipants = [];
  let sessionBgmIds = [];
  let selectedInventoryItem = null;
  let equipmentSaving = false;
  let profileImageFile = null;
  let profileImagePreview = '';
  let inventory = [];
  let equippedInventory = [];
  let cards = [];
  let adminCharacters = [];
  let adminSelectedCharacter = null;
  let adminCharacterForm = { name: '', roleName: '', roleTraits: '', age: '', height: '', weight: '', money: '0', level: 1, hp: 0, maxHp: 0, mp: 0, maxMp: 0, attack: 0, defense: 0, combatNotes: '' };
  let adminCharacterSaving = false;
  let adminInventory = [];
  let adminInventoryBaseline = '';
  let adminInventoryVersion = null;
  let adminEquippedInventory = [];
  let adminCards = [];
  let adminDetailLoading = false;
  let catalogItems = [];
  let catalogLoading = false;
  let catalogLoadedAt = 0;
  let catalogLoadPromise;
  let catalogSearchTerm = '';
  let inventorySearchTerm = '';
  let itemForm = { id: '', name: '', item_effect: '', item_description: '', grade: '일반', item_type: '기타', equipment_slot: '', icon_url: '', chest_reward_item_ids: [], chest_reward_count: 1, combat_effects:null, relic_effects:null };
  let shopListings = [];
  let shopLoading = false;
  let shopError = '';
  let shopBalance = null;
  let shopPurchaseQuantities = {};
  let shopPurchaseSaving = false;
  let adminShopListings = [];
  let adminShopLoading = false;
  let shopAdminSaving = false;
  let shopForm = { id: '', item_id: '', price_g: 0, personal_limit: '', total_limit: '', sold_count: 0, is_active: false };
  let combatTestSelectedCharacterIds = [];
  let combatTestPlayers = [];
  let combatTestLoading = false;
  let combatTestStarted = false;
  let combatTestTurn = 0;
  let itemFormImageFile = null;
  let itemFormImagePreview = '';
  let itemSaving = false;
  let openingChest = false;
  let chestOpeningDone = false;
  let chestOpeningReady = false;
  let chestOpeningRewards = [];
  let chestOpeningTiles = [];
  let rouletteTrackStyle = '';
  let characterRequestId = 0;
  let characterLoadedAt = 0;
  let characterLoadedKey = '';
  const characterLoadPromises = new Map();
  let accountSaving = false;
  let accountSettingsSaving = false;
  let accountForm = { newPassword: '', confirmPassword: '' };
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

  let postForm = { title: '', content: '', postType: 'notice', isPrivate: false, privatePassword: '', npcName: '', npcAge: '', npcGender: '', npcHeight: '', npcRace: '', npcRole: '', npcTraits: '', npcAffiliation: '', npcPersonality: '', bgmCategory: 'map', bgmUrl: '', bgmFile: null, imageFile: null };
  let editingPostId = null;
  let editingPostAuthorId = null;
  let editLoading = false;
  let editRequestId = 0;
  let npcImagePreview = '';
  let npcOriginalImageUrl = '';
  let richEditorElement;
  let richEditor;
  let richEditorLoader;
  let richEditorSyncTimer;
  let richEditorSyncing = false;
  let decorationFingerprint = '';
  let writeBoardSlug = 'users';
  let characterForm = { name: '', roleName: '', roleTraits: '', age: '', height: '', weight: '' };
  let adminForm = {
    loginId: '', password: '', nickname: '',
    character: { name: '', roleName: '', roleTraits: '', age: '', height: '', weight: '', money: '0' }
  };

  $: filteredPosts = posts
    .filter((post) => activeCategory === '전체' || post.category === activeCategory)
    .filter((post) => `${post.title} ${post.excerpt} ${post.author}`.toLowerCase().includes(searchTerm.toLowerCase().trim()))
    .sort((a, b) => sortBy === 'popular' ? b.views - a.views : posts.indexOf(a) - posts.indexOf(b));
  $: filteredPageCount = Math.max(1, Math.ceil(filteredPosts.length / pageSize));
  $: pagedFilteredPosts = filteredPosts.slice((currentPage - 1) * pageSize, currentPage * pageSize);
  $: isBoardPage = currentRoute.startsWith('board/');
  $: isMiniGamesPage = currentRoute === 'minigames';
  $: isDiceRollerPage = currentRoute === 'minigames/dice';
  $: isPostPage = currentRoute.startsWith('post/');
  $: isWritePage = currentRoute.startsWith('write/');
  $: isEditPage = currentRoute.startsWith('edit/');
  $: isMyPage = currentRoute === 'mypage';
  $: isAdminPage = currentRoute === 'admin';
  $: isAdminMonstersPage = currentRoute === 'admin/monsters';
  $: isAdminItemsPage = currentRoute === 'admin/items';
  $: isShopPage = currentRoute === 'shop';
  $: isAdminShopPage = currentRoute === 'admin/shop';
  $: isAdminCombatTestPage = currentRoute === 'admin/combat-test';
  $: isCombatPage = currentRoute === 'combat' || currentRoute.startsWith('combat/');
  $: isAdminShellPage = isAdminMonstersPage || isAdminPage || isAdminItemsPage || isAdminShopPage || isAdminCombatTestPage;
  $: isAdminMypage = currentRoute === 'admin-mypage';
  $: isAdminCharacterPage = currentRoute.startsWith('admin-character/');
  $: currentBoard = categories.find((board) => board.slug === currentRoute.replace('board/', '')) || categories[0];
  $: writeBoard = categories.find((board) => board.slug === writeBoardSlug) || categories.find((board) => board.slug === 'users') || categories[0];
  $: sessionPlayerFilterOptions = buildSessionPlayerFilterOptions(posts, adminCharacters);
  $: sessionActorParticipants = buildSessionActorParticipants(sessionParticipants);
  $: boardPagePosts = posts
    .filter((post) => currentBoard.slug === 'all' || post.category === currentBoard.name)
    .filter((post) => `${post.title} ${post.excerpt} ${post.author}`.toLowerCase().includes(searchTerm.toLowerCase().trim()))
    .filter((post) => currentBoard.slug !== 'notices' || noticeTypeFilter === 'all' || post.postType === noticeTypeFilter)
    .filter((post) => currentBoard.slug !== 'sessions' || sessionPostHasPlayer(post, sessionPlayerFilter))
    .sort((a, b) => sortBy === 'popular' ? b.views - a.views : posts.indexOf(a) - posts.indexOf(b));
  $: boardPageCount = Math.max(1, Math.ceil(boardPagePosts.length / pageSize));
  $: pagedBoardPosts = boardPagePosts.slice((currentPage - 1) * pageSize, currentPage * pageSize);
  $: filteredCatalogItems = catalogItems.filter((item) => `${item.name} ${item.item_effect} ${item.item_description} ${item.item_type} ${item.equipment_slot || ''} ${item.grade}`.toLowerCase().includes(catalogSearchTerm.toLowerCase().trim()));
  $: filteredInventoryCatalogItems = catalogItems.filter((item) => `${item.name} ${item.item_effect} ${item.item_description}`.toLowerCase().includes(inventorySearchTerm.toLowerCase().trim())).slice(0, 12);
  $: equippedInventory = getEquippedInventory(inventory);
  $: adminEquippedInventory = getEquippedInventory(adminInventory);

  function showNotice(message) {
    notice = message;
    setTimeout(() => (notice = ''), 2800);
  }

  function loadRouteComponent(key, loader, assign) {
    if (routeComponentPromises.has(key)) return routeComponentPromises.get(key);
    const promise = loader()
      .then((module) => {
        assign(module.default);
        decorationFingerprint = '';
      })
      .catch(() => showNotice('페이지 구성 요소를 불러오지 못했습니다. 새로고침해 주세요.'));
    routeComponentPromises.set(key, promise);
    return promise;
  }

  function ensureRouteComponent(route) {
    if (route === 'combat' || route.startsWith('combat/')) return loadRouteComponent('combat', () => import('./pages/CombatPage.svelte'), (component) => (CombatPage = component));
    if (route.startsWith('board/')) return loadRouteComponent('board', () => import('./pages/BoardPage.svelte'), (component) => (BoardPage = component));
    if (route === 'minigames') return loadRouteComponent('minigames', () => import('./pages/MiniGamesPage.svelte'), (component) => (MiniGamesPage = component));
    if (route === 'minigames/dice') return loadRouteComponent('dice', () => import('./pages/DiceRollerPage.svelte'), (component) => (DiceRollerPage = component));
    if (route.startsWith('post/')) return loadRouteComponent('post', () => import('./pages/PostDetailPage.svelte'), (component) => (PostDetailPage = component));
    if (route === 'shop') return loadRouteComponent('shop', () => import('./pages/ShopPage.svelte'), (component) => (ShopPage = component));
    if (route === 'admin/combat-test') return loadRouteComponent('admin-combat', () => import('./pages/AdminCombatTestPage.svelte'), (component) => (AdminCombatTestPage = component));
    if (route === 'admin/monsters') return loadRouteComponent('admin-monsters', () => import('./pages/AdminMonstersPage.svelte'), (component) => (AdminMonstersPage = component));
    if (route === 'admin/items') return loadRouteComponent('admin-items', () => import('./pages/AdminItemsPage.svelte'), (component) => (AdminItemsPage = component));
    if (route.startsWith('write/') || route.startsWith('edit/')) return loadRouteComponent('write', () => import('./pages/WritePage.svelte'), (component) => (WritePage = component));
    if (route === 'admin-mypage') return loadRouteComponent('admin-mypage', () => import('./pages/AdminMypage.svelte'), (component) => (AdminMypage = component));
    if (route === 'admin/shop') return loadRouteComponent('admin-shop', () => import('./pages/AdminShopPage.svelte'), (component) => (AdminShopPage = component));
    if (route === 'mypage') return loadRouteComponent('mypage', () => import('./pages/MyPage.svelte'), (component) => (MyPage = component));
    if (route.startsWith('admin-character/')) return loadRouteComponent('admin-character', () => import('./pages/AdminCharacterWorkspace.svelte'), (component) => (AdminCharacterPage = component));
    if (route === 'admin') return loadRouteComponent('admin', () => import('./pages/AdminPage.svelte'), (component) => (AdminPage = component));
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

  const publicPostListSelect = 'id, board_slug, title, excerpt, status, views, created_at, author_id, is_private, image_url, bgm_url, bgm_category, post_type, npc_name, npc_role, author_nickname, author_avatar_url, author_accent_color, comment_count, like_count';
  const publicPostDetailSelect = 'id, board_slug, title, content, excerpt, status, views, created_at, author_id, is_private, image_url, youtube_url, bgm_url, bgm_category, post_type, npc_name, npc_age, npc_gender, npc_height, npc_race, npc_role, npc_traits, npc_affiliation, npc_personality, author_nickname, author_avatar_url, author_accent_color, comment_count, like_count';

  function readEmbeddedNpcData(content = '') {
    const match = content.match(/^<!--OPEN_DOOR_NPC:([A-Za-z0-9+/=]+)-->/);
    if (!match) return { content };
    try {
      const data = JSON.parse(decodeURIComponent(escape(atob(match[1]))));
      return { ...data, content: content.slice(match[0].length) };
    } catch { return { content }; }
  }

  function formatPost(post, boardMap) {
    const sessionData = post.board_slug === 'sessions' ? readEmbeddedSessionData(post.content || '') : { content: post.content || '', entries: [] };
    const bgmData = post.board_slug === 'bgm' ? readEmbeddedBgmData(sessionData.content) : { content: sessionData.content };
    const embedded = readEmbeddedNpcData(bgmData.content);
    post = { ...post, content: embedded.content, image_url: post.image_url || embedded.image_url, bgm_url: post.bgm_url || bgmData.bgm_url, bgm_category: post.bgm_category || bgmData.bgm_category, npc_name: post.npc_name || embedded.npc_name, npc_age: post.npc_age ?? embedded.npc_age, npc_gender: post.npc_gender || embedded.npc_gender, npc_height: post.npc_height ?? embedded.npc_height, npc_race: post.npc_race || embedded.npc_race, npc_role: post.npc_role || embedded.npc_role, npc_traits: post.npc_traits || embedded.npc_traits, npc_affiliation: post.npc_affiliation || embedded.npc_affiliation, npc_personality: post.npc_personality || embedded.npc_personality };
    const profileData = Array.isArray(post.profiles) ? post.profiles[0] : post.profiles || { nickname: post.author_nickname, avatar_url: post.author_avatar_url, accent_color: post.author_accent_color };
    const commentRelation = post.post_comments || post.comments;
    const likeRelation = post.post_likes || post.likes;
    const commentCount = post.comment_count ?? (Array.isArray(commentRelation) ? commentRelation[0]?.count || 0 : 0);
    const likeCount = post.like_count ?? (Array.isArray(likeRelation) ? likeRelation[0]?.count || 0 : 0);
    const date = formatDate(post.created_at);
    const nickname = profileData?.nickname || '모험가';
    return {
      id: post.id, boardSlug: post.board_slug, category: boardMap.get(post.board_slug)?.name || post.board_slug,
      title: post.board_slug === 'npc' && post.npc_role && post.npc_name ? `[${post.npc_role}] ${post.npc_name}` : post.title, content: post.content || '',
      excerpt: post.is_private ? '비밀글입니다. 비밀번호를 입력하면 내용을 확인할 수 있습니다.' : post.excerpt || post.content?.replace(/\s+/g, ' ').slice(0, 140) || '아직 요약이 등록되지 않은 게시글입니다.',
      author: nickname, authorId: post.author_id, date: date.date, time: date.time,
      views: post.views || 0, comments: commentCount, likes: likeCount, avatar: nickname.slice(0, 1).toUpperCase(), avatarUrl: profileData?.avatar_url || '',
      color: ['lavender', 'mint', 'peach', 'yellow', 'blue'][nickname.charCodeAt(0) % 5], authorColor: getReadableAccentColor(profileData?.accent_color),
      imageUrl: post.image_url || '', npcName: post.npc_name || '', npcAge: post.npc_age ?? '', npcGender: post.npc_gender || '',
      npcHeight: post.npc_height ?? '', npcRace: post.npc_race || '', npcRole: post.npc_role || '', npcTraits: post.npc_traits || '',
      npcAffiliation: post.npc_affiliation || '', npcPersonality: post.npc_personality || '', postType: post.post_type || 'notice', isPrivate: Boolean(post.is_private), privatePassword: post.private_password || '', youtubeUrl: post.youtube_url || '', bgmUrl: post.bgm_url || '', bgmCategory: post.bgm_category || 'map', sessionEntries: sessionData.entries, sessionParticipants: Array.isArray(sessionData.participants) ? sessionData.participants : [], sessionBgms: Array.isArray(sessionData.bgms) ? sessionData.bgms : []
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
    // Keep a single Enter as a visible line break in the published post.
    return renderSafePostMarkdown(markdown,html=>DOMPurify.sanitize(html));
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

  function getReadableAccentColor(value) {
    const raw = String(value || '').trim();
    return /^#[0-9a-f]{6}$/i.test(raw) ? raw : '#d8bd75';
  }

  function sessionAccentStyle(value) {
    return ` style="--session-accent:${escapeSessionHtml(getReadableAccentColor(value))}"`;
  }

  async function saveProfileAccentColor(value) {
    if (!supabase || !user) return;
    const accentColor = getReadableAccentColor(value);
    const { error } = await supabase.from('profiles').update({ accent_color: accentColor }).eq('id', user.id);
    if (error) return showNotice(`프로필 색상 저장에 실패했습니다: ${error.message}`);
    profile = { ...profile, accent_color: accentColor };
    profileAccentColor = accentColor;
  }

  function resolveSessionAccent(entryColor, postColor) {
    const entryAccent = getReadableAccentColor(entryColor);
    const postAccent = getReadableAccentColor(postColor);
    return entryAccent === '#d8bd75' && postAccent !== '#d8bd75' ? postAccent : entryAccent;
  }

  function renderBgmContent(post) {
    const category = { map: 'MAP BGM', character: 'CHARACTER BGM', scene: 'SCENE BGM', etc: 'ETC' }[post.bgmCategory] || 'BGM';
    const player = post.bgmUrl ? `<div class="bgm-detail-player"><span>${category}</span><audio controls preload="metadata" src="${escapeSessionHtml(post.bgmUrl)}"></audio></div>` : '';
    return `${player}${renderPostContent(post.content)}`;
  }

  function renderSessionEntries(entries = [], participants = [], bgms = [], postAccentColor = '') {
    const participantHtml = participants.length ? `<section class="session-log-participants"><strong>세션 참여자</strong><div>${participants.map((participant) => `<span>${escapeSessionHtml(participant.name || '이름 없음')}</span>`).join('')}</div></section>` : '';
    const bgmHtml = bgms.length ? `<section class="session-log-bgms"><strong>세션 BGM</strong><div>${bgms.map((bgm) => `<article><span>${escapeSessionHtml(bgm.title || 'BGM')} · ${escapeSessionHtml(({ map: '맵', character: '캐릭터', scene: '장면', etc: '기타' }[bgm.category] || 'BGM'))}</span><audio controls preload="metadata" src="${escapeSessionHtml(bgm.url || '')}"></audio></article>`).join('')}</div></section>` : '';
    const html = entries.map((entry) => {
      if (entry.type === 'image') return `<figure class="session-log-image"><img loading="lazy" decoding="async" src="${escapeSessionHtml(entry.imageUrl || '')}" alt="세션 장면" />${entry.caption ? `<figcaption>${escapeSessionHtml(entry.caption)}</figcaption>` : ''}</figure>`;
      if (entry.type === 'dialogue') {
        const speakerName = entry.speakerName || '???';
        const speakerImage = sessionEntrySpeakerAvatar(entry);
        const avatar = speakerImage
          ? `<img class="session-dialogue-avatar-image" loading="lazy" decoding="async" src="${escapeSessionHtml(speakerImage)}" alt="${escapeSessionHtml(speakerName)} 사진" />`
          : `<span class="session-dialogue-avatar-placeholder">${escapeSessionHtml(speakerName.slice(0, 1))}</span>`;
        return `<div class="session-log-dialogue"${sessionAccentStyle(resolveSessionAccent(entry.accentColor, postAccentColor))}><div class="session-dialogue-avatar">${avatar}</div><div class="session-dialogue-copy"><strong>${escapeSessionHtml(speakerName)}</strong><p>&quot;${escapeSessionHtml(entry.text || '')}&quot;</p></div></div>`;
      }
      return `<div class="session-log-narration"${sessionAccentStyle(resolveSessionAccent(entry.accentColor, postAccentColor))}>${entry.actorName ? `<small>${escapeSessionHtml(entry.actorName)}</small>` : ''}<p>${escapeSessionHtml(entry.text || '')}</p></div>`;
    }).join('');
    return DOMPurify.sanitize(`<div class="session-log-body">${participantHtml}${bgmHtml}${html}</div>`);
  }

  function normalizeRichEditorMarkdown(content = '') {
    return content.replace(/\\(\*{1,2}|_{1,2})/g, '$1');
  }

  function hasInlineMarkdownFormat(content = '') {
    return /(\*{1,2}|_{1,2})\S[\s\S]*?\1/.test(content);
  }

  async function loadDatabase(force = false) {
    if (!supabase || !supabaseConfig.url || !supabaseConfig.hasPublishableKey) {
      dbStatus = 'missing'; dbError = 'Supabase 환경변수가 없습니다.'; return;
    }
    if (!force && dbStatus === 'connected' && Date.now() - databaseLoadedAt < 30000) return;
    if (databaseLoadPromise) return databaseLoadPromise;
    databaseLoadPromise = (async () => {
      try {
      const [boardsResult, postsResult, bgmResult] = await Promise.all([
        supabase.from('boards').select('slug, name, description, sort_order, is_public').eq('is_public', true).order('sort_order', { ascending: true }),
        supabase.from('posts_public').select(publicPostListSelect).eq('status', 'published').order('created_at', { ascending: false }).limit(100),
        supabase.from('posts_public').select('id, title, content, bgm_url, bgm_category').eq('status', 'published').eq('board_slug', 'bgm').order('created_at', { ascending: false }).limit(500)
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
      posts = remotePosts.map((post) => formatPost(post, boardMap));
      sessionMetadataLoaded = false;
      sessionMetadataPromise = null;
      if (currentRoute === 'board/sessions') await loadSessionPostMetadata();
      npcOptions = posts.filter((post) => post.boardSlug === 'npc');
      const loadedBgmOptions = bgmResult.error
        ? posts.filter((post) => post.boardSlug === 'bgm' && post.bgmUrl)
        : (bgmResult.data || []).map((post) => {
          const embedded = readEmbeddedBgmData(post.content || '');
          return {
            id: post.id,
            title: post.title,
            bgmUrl: post.bgm_url || embedded.bgm_url || '',
            bgmCategory: post.bgm_category || embedded.bgm_category || 'map'
          };
        }).filter((post) => post.bgmUrl);
      bgmOptions = loadedBgmOptions;
      notices = posts.filter((post) => post.boardSlug === 'notices').slice(0, 3).map((post, index) => ({ tag: { patch: '패치', event: '이벤트', notice: '공지' }[post.postType] || '공지', title: post.title, meta: `${post.date} ${post.time}`, body: post.excerpt, tone: ['gold', 'blue', 'pink'][index] || 'gold' }));
        dbStatus = 'connected'; dbError = ''; databaseLoadedAt = Date.now();
      } catch (error) {
        dbStatus = 'error'; dbError = error instanceof Error ? error.message : 'Supabase 연결에 실패했습니다.';
      } finally {
        databaseLoadPromise = null;
      }
    })();
    return databaseLoadPromise;
  }

  async function loadProfile(activeUser = user) {
    if (!supabase || !activeUser) return;
    profileLoading = true;
    try {
      let profileQuery = supabase.from('profiles').select('id, nickname, role, avatar_url, accent_color').eq('id', activeUser.id).maybeSingle();
      let profileResult = await Promise.race([
        profileQuery,
        new Promise((_, reject) => setTimeout(() => reject(new Error('프로필 조회 시간이 초과되었습니다.')), 10000))
      ]);
      if (profileResult.error && /accent_color|column|schema cache/i.test(profileResult.error.message)) {
        profileQuery = supabase.from('profiles').select('id, nickname, role, avatar_url').eq('id', activeUser.id).maybeSingle();
        profileResult = await profileQuery;
      }
      const { data, error } = profileResult;
      profile = data || null;
      profileAccentColor = getReadableAccentColor(data?.accent_color);
      isAdmin = !error && data?.role === 'admin';
      accountForm = { newPassword: '', confirmPassword: '' };
      if (isAdmin) {
        adminProfileForm = { ...adminProfileForm, nickname: data?.nickname || '' };
        adminProfileImagePreview = data?.avatar_url || '';
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
      const routeLoads = [];
      if (routeNeedsCharacterData(currentRoute)) routeLoads.push(loadCharacterData());
      if (currentRoute.startsWith('admin-character/')) routeLoads.push(loadAdminCharacterDetail(currentRoute.replace('admin-character/', '')));
      if (currentRoute === 'shop' || currentRoute === 'admin/shop') routeLoads.push(loadShopData());
      if (currentRoute === 'admin/shop' || currentRoute === 'admin/items') routeLoads.push(loadCatalogItems());
      await Promise.all(routeLoads);
    } else {
      profile = null; profileLoading = false; isAdmin = false; character = null; inventory = []; cards = [];
      characterLoadedKey = ''; characterLoadedAt = 0; characterRequestId += 1;
    }
    authReady = true;
  }

  async function loadSessionPostMetadata() {
    if (!supabase || sessionMetadataLoaded) return;
    if (sessionMetadataPromise) return sessionMetadataPromise;
    sessionMetadataPromise = (async () => {
      const result = await supabase
        .from('posts_public')
        .select('id, content')
        .eq('status', 'published')
        .eq('board_slug', 'sessions')
        .order('created_at', { ascending: false })
        .limit(100);
      if (result.error) return;
      const contentById = new Map((result.data || []).map((post) => [post.id, post.content || '']));
      posts = posts.map((post) => {
        if (post.boardSlug !== 'sessions' || !contentById.has(post.id)) return post;
        const sessionData = readEmbeddedSessionData(contentById.get(post.id));
        return {
          ...post,
          content: sessionData.content || '',
          sessionEntries: sessionData.entries || [],
          sessionParticipants: Array.isArray(sessionData.participants) ? sessionData.participants : [],
          sessionBgms: Array.isArray(sessionData.bgms) ? sessionData.bgms : []
        };
      });
      sessionMetadataLoaded = true;
    })().finally(() => {
      sessionMetadataPromise = null;
    });
    return sessionMetadataPromise;
  }

  function routeNeedsCharacterData(route) {
    return route === 'mypage'
      || route === 'admin'
      || route === 'admin/combat-test'
      || (isAdmin && (route.startsWith('write/sessions') || route.startsWith('edit/sessions')));
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
    accountForm = { newPassword: '', confirmPassword: '' };
    profileLoading = false;
    isAdmin = false;
    character = null;
    characterLoadedKey = '';
    characterLoadedAt = 0;
    characterRequestId += 1;
    extraRecords = [];
    relationships = [];
    extraRecordCharacterId = null;
    inventory = [];
    cards = [];
    shopListings = [];
    adminShopListings = [];
    shopBalance = null;
    combatTestSelectedCharacterIds = [];
    combatTestPlayers = [];
    combatTestStarted = false;
    combatTestTurn = 0;
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
      try { avatarUrl = await uploadProfileImage(adminProfileImageFile); } catch (error) { adminProfileSaving = false; return showNotice(error instanceof Error ? error.message : '프로필 이미지를 처리하지 못했습니다.'); }
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

  async function saveAccountPassword() {
    if (!requireLogin() || !supabase) return;
    const { newPassword, confirmPassword } = accountForm;
    if (!newPassword) return showNotice('새 비밀번호를 입력해 주세요.');
    if (newPassword.length < 8) return showNotice('비밀번호는 8자 이상 입력해 주세요.');
    if (newPassword !== confirmPassword) return showNotice('새 비밀번호가 일치하지 않습니다.');
    accountSettingsSaving = true;
    const { error } = await supabase.auth.updateUser({ password: newPassword });
    accountSettingsSaving = false;
    if (error) return showNotice(`비밀번호 변경 실패: ${error.message}`);
    accountForm = { ...accountForm, newPassword: '', confirmPassword: '' };
    showNotice('비밀번호를 변경했습니다.');
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
    detailController?.abort();detailRequestId++;detailError='';detailLoading=false;
    currentRoute = nextRoute; activeCategory = '전체'; searchTerm = ''; sortBy = 'latest'; noticeTypeFilter = 'all'; sessionPlayerFilter = ''; currentPage = 1; detailPost = null; detailHtml = ''; privatePostUnlocked = false; privatePostError = '';
    ensureRouteComponent(nextRoute);
    if (nextRoute === 'admin') { adminSelectedCharacter = null; adminInventory = []; adminCards = []; }
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
    if (nextRoute === 'board/sessions' && dbStatus === 'connected') loadSessionPostMetadata();
    if (nextRoute.startsWith('admin-character/')) loadAdminCharacterDetail(nextRoute.replace('admin-character/', ''));
    if (routeNeedsCharacterData(nextRoute)) loadCharacterData();
    if (nextRoute === 'admin/items') loadCatalogItems();
    if (nextRoute === 'shop' || nextRoute === 'admin/shop') loadShopData();
    if (nextRoute === 'admin/shop') loadCatalogItems();
  }

  function navigateTo(hash) {
    const nextHash = hash.startsWith('#') ? hash : `#${hash}`;
    if (window.location.hash === nextHash) {
      syncRoute();
      return;
    }
    window.location.hash = nextHash;
  }

  function renderPostDetailHtml(post) {
    return post.boardSlug === 'sessions' && (post.sessionEntries.length || post.sessionParticipants.length || post.sessionBgms.length)
      ? renderSessionEntries(post.sessionEntries, post.sessionParticipants, post.sessionBgms, post.authorColor)
      : post.boardSlug === 'bgm' ? renderBgmContent(post) : renderPostContent(post.content);
  }

  function renderPrivatePostLock() {
    return `<section class="private-post-lock"><span class="private-post-lock-icon">▣</span><p class="eyebrow">PRIVATE RECORD</p><h2>비밀글입니다</h2><p>작성자와 운영자만 바로 볼 수 있습니다.<br />비밀번호를 입력하면 내용을 확인할 수 있어요.</p><form data-private-unlock-form><label>비밀번호<input data-private-password type="password" autocomplete="off" placeholder="비밀글 비밀번호" required /></label><button class="primary-btn" type="submit">내용 확인 <span>↗</span></button><small data-private-error></small></form></section>`;
  }

  async function unlockPrivatePost(password) {
    if (!detailPost?.isPrivate) return;
    const { data, error } = await supabase.rpc('open_private_post', { p_post_id: detailPost.id, p_password: String(password || '') });
    if (error || !data) {
      privatePostError = '비밀번호가 올바르지 않습니다.';
      return false;
    }
    const privateData = Array.isArray(data) ? data[0] : data;
    if (!privateData) {
      privatePostError = '비밀번호가 올바르지 않습니다.';
      return false;
    }
    const boardMap = new Map(categories.map((board) => [board.slug, board]));
    detailPost = (await hydratePostAvatars([formatPost({ ...privateData, profiles: { nickname: detailPost.author, avatar_url: detailPost.avatarUrl, accent_color: detailPost.authorColor }, post_comments: [{ count: detailPost.comments }], post_likes: [{ count: detailPost.likes }] }, boardMap)]))[0];
    if (detailPost.boardSlug === 'sessions') detailPost = await hydrateSessionAccentColors(detailPost);
    privatePostError = '';
    privatePostUnlocked = true;
    detailHtml = renderPostDetailHtml(detailPost);
    await loadEngagement(detailPost.id);
    return true;
  }

  async function loadPostDetail(id) {
    detailController?.abort();
    const requestId=++detailRequestId;
    const controller=new AbortController();detailController=controller;
    const current=()=>requestId===detailRequestId && currentRoute===`post/${id}`;
    detailLoading=true;detailError='';detailComments=[];commentText='';detailLiked=false;privatePostUnlocked=false;privatePostError='';
    const timeout=setTimeout(()=>controller.abort(),20000);
    try {
      if(!supabase || !id)throw new Error('게시글 연결 설정을 확인해 주세요.');
      const {data,error}=await supabase.from('posts_public').select(publicPostDetailSelect).eq('id',id).abortSignal(controller.signal).maybeSingle();
      if(!current())return;
      if(error)throw error;
      if(!data)throw new Error('게시글이 없거나 열람할 수 없습니다.');
      let detailData=data;
      if(data.is_private && (isAdmin || user?.id===data.author_id)) {
        const owner=await supabase.rpc('get_post_for_edit',{p_post_id:id}).abortSignal(controller.signal);
        if(owner.error)throw owner.error;
        if(owner.data)detailData={...data,...(Array.isArray(owner.data)?owner.data[0]:owner.data)};
      }
      let post=formatPost(detailData,new Map(categories.map(board=>[board.slug,board])));
      // Optional profile styling must not prevent the post body from loading.
      try { post=(await hydratePostAvatars([post],controller.signal))[0];if(post.boardSlug==='sessions')post=await hydrateSessionAccentColors(post,controller.signal); }
      catch { /* Render with the author information already included in the post. */ }
      if(!current())return;
      const unlocked=!post.isPrivate || isAdmin || user?.id===post.authorId;
      const html=unlocked ? renderPostDetailHtml(post) : renderPrivatePostLock();
      if(!current())return;
      detailPost=post;privatePostUnlocked=unlocked;detailHtml=html;
    } catch(error) {
      if(current()) { detailPost=null;detailHtml='';detailError=controller.signal.aborted?'게시글 요청 시간이 초과되었습니다. 다시 불러와 주세요.':error instanceof Error ? error.message : '게시글을 불러오지 못했습니다. 다시 시도해 주세요.'; }
    } finally {
      clearTimeout(timeout);if(current())detailLoading=false;
    }
    if(current() && detailPost) {
      if(privatePostUnlocked)void loadEngagement(id).catch(()=>{});
      void supabase.rpc('increment_post_views',{post_id_input:id}).then(()=>{}).catch(()=>{});
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
      if(currentRoute!==`post/${postId}` || detailPost?.id!==postId)return;
      detailComments = rows.map((comment) => ({ ...comment, nickname: authors.get(comment.author_id)?.nickname || '모험가', avatarUrl: authors.get(comment.author_id)?.avatar_url || '' }));
    }
    if (!user) {
      detailLiked = false;
      return;
    }
    const likeResult = await supabase.from('post_likes').select('post_id').eq('post_id', postId).eq('user_id', user.id).maybeSingle();
    if(currentRoute!==`post/${postId}` || detailPost?.id!==postId)return;
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

  function sessionParticipantActorValue(participant) {
    if (!participant) return '';
    const participantType = participant.participantType || 'custom';
    const participantId = participantType === 'custom' ? participant.id || '' : participant.participantId || '';
    return `${participantType}:${participantId}`;
  }

  function buildSessionActorParticipants(participants = []) {
    const seen = new Set();
    return participants.filter((participant) => {
      const value = sessionParticipantActorValue(participant);
      if (!value || value.endsWith(':') || (participant.participantType === 'custom' && !participant.participantName?.trim()) || seen.has(value)) return false;
      seen.add(value);
      return true;
    });
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
    const participant = actorType === 'custom' && actorId
      ? sessionParticipants.find((item) => item.participantType === 'custom' && item.id === actorId)
      : null;
    entry.actorType = actorType;
    entry.actorId = actorId;
    entry.actorName = participant ? sessionParticipantName(participant) : '';
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
    return plainNpcName(npc);
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
    if (entry.actorType === 'custom' && entry.actorId) {
      const participant = sessionParticipants.find((item) => item.participantType === 'custom' && item.id === entry.actorId);
      if (participant) return sessionParticipantName(participant);
    }
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

  function dialogueSpeakerFromNarration(entry) {
    if (entry.actorType === 'character' && entry.actorId) {
      return { speakerType: 'character', speakerId: entry.actorId, speakerName: sessionCharacterName(entry.actorId), speakerImageUrl: sessionCharacterAvatar(entry.actorId) };
    }
    if (entry.actorType === 'npc' && entry.actorId) {
      return { speakerType: 'npc', speakerId: entry.actorId, speakerName: sessionNpcName(entry.actorId), speakerImageUrl: sessionNpcAvatar(entry.actorId) };
    }
    if (entry.actorType === 'custom' && entry.actorName?.trim()) {
      return { speakerType: 'custom', speakerId: '', speakerName: entry.actorName.trim(), speakerImageUrl: '' };
    }
    return { speakerType: 'anonymous', speakerId: '', speakerName: '???', speakerImageUrl: '' };
  }

  function splitNarrationQuotes(entry) {
    const text = entry.text?.trim() || '';
    // Match straight quotes and smart quotes as pairs so `“대사”` is
    // converted in the same way as `"대사"`.
    const quotePattern = /“([\s\S]*?)”|"([\s\S]*?)"/g;
    const segments = [];
    let foundQuote = false;
    let cursor = 0;
    let match;
    while ((match = quotePattern.exec(text))) {
      foundQuote = true;
      const narrationBefore = text.slice(cursor, match.index).trim();
      if (narrationBefore) segments.push({ type: 'narration', actorType: entry.actorType || 'none', actorId: entry.actorId || '', actorName: sessionActorName(entry), text: narrationBefore });
      const dialogueText = (match[1] ?? match[2]).trim();
      if (dialogueText) segments.push({ type: 'dialogue', ...dialogueSpeakerFromNarration(entry), text: dialogueText });
      cursor = match.index + match[0].length;
    }
    const narrationAfter = text.slice(cursor).trim();
    if (narrationAfter) segments.push({ type: 'narration', actorType: entry.actorType || 'none', actorId: entry.actorId || '', actorName: sessionActorName(entry), text: narrationAfter });
    return foundQuote ? segments : null;
  }

  function encodeSessionContent(entries, participants, bgms) {
    const data = btoa(unescape(encodeURIComponent(JSON.stringify({ version: 1, participants, bgms, entries }))));
    return `<!--OPEN_DOOR_SESSION:${data}-->`;
  }

  async function prepareSessionEntries() {
    const prepared = [];
    const accentColor = getReadableAccentColor(profileAccentColor);
    for (const entry of sessionEntries) {
      if (entry.type === 'image') {
        let imageUrl = entry.imageUrl || '';
        if (entry.imageFile) imageUrl = await imageFileToDataUrl(entry.imageFile, { maxSide: 1600, quality: .8, maxBytes: 2_000_000 });
        if (!imageUrl) throw new Error('사진 항목에 이미지를 선택해 주세요.');
        prepared.push({ type: 'image', imageUrl, caption: entry.caption?.trim() || '' });
      } else if (entry.type === 'dialogue') {
        if (!entry.text?.trim()) throw new Error('대사 내용을 입력해 주세요.');
        const speakerImageUrl = sessionSpeakerAvatar(entry);
        prepared.push({ type: 'dialogue', speakerType: entry.speakerType || 'anonymous', speakerId: entry.speakerId || '', speakerName: sessionSpeakerName(entry), speakerImageUrl: speakerImageUrl && !speakerImageUrl.startsWith('data:') ? speakerImageUrl : '', accentColor, text: entry.text.trim() });
      } else {
        if (!entry.text?.trim()) throw new Error('지문 내용을 입력해 주세요.');
        const splitEntries = splitNarrationQuotes(entry);
        if (splitEntries) prepared.push(...splitEntries.map((splitEntry) => ({ ...splitEntry, accentColor })));
        else prepared.push({ type: 'narration', actorType: entry.actorType || 'none', actorId: entry.actorId || '', actorName: sessionActorName(entry), accentColor, text: entry.text.trim() });
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
    npcOriginalImageUrl = '';
    sessionEntries = [];
    sessionParticipants = [];
    sessionBgmIds = [];
    postForm = { title: '', content: '', postType: 'notice', isPrivate: false, privatePassword: '', npcName: '', npcAge: '', npcGender: '', npcHeight: '', npcRace: '', npcRole: '', npcTraits: '', npcAffiliation: '', npcPersonality: '', bgmCategory: 'map', bgmUrl: '', bgmFile: null, imageFile: null };
    editingPostId = null;
    editingPostAuthorId = null;
    editLoading = false;
    if (richEditor) richEditor.setMarkdown('', false);
  }

  async function hydratePostAvatars(postList,signal) {
    if (!supabase || !postList.length) return postList;
    const ids = [...new Set(postList.map((post) => post.authorId).filter(Boolean))];
    if (!ids.length) return postList;
    let [profileResult, characterResult] = await Promise.all([
      supabase.from('profiles').select('id, avatar_url, accent_color').in('id', ids).abortSignal(signal),
      supabase.from('characters').select('owner_id, avatar_url').in('owner_id', ids).abortSignal(signal)
    ]);
    if (profileResult.error && /accent_color|column|schema cache/i.test(profileResult.error.message)) {
      profileResult = await supabase.from('profiles').select('id, avatar_url').in('id', ids).abortSignal(signal);
    }
    const characterRows = characterResult.data || [];
    const profileRows = profileResult.data || [];
    const profileAvatars = new Map((profileRows || []).map((item) => [item.id, item.avatar_url || '']));
    const profileColors = new Map((profileRows || []).map((item) => [item.id, item.accent_color || '']));
    const characterAvatars = new Map((characterRows || []).map((item) => [item.owner_id, item.avatar_url || '']).filter(([, url]) => url));
    return postList.map((post) => ({ ...post, avatarUrl: profileAvatars.get(post.authorId) || characterAvatars.get(post.authorId) || post.avatarUrl || '', authorColor: getReadableAccentColor(profileColors.get(post.authorId) || post.authorColor) }));
  }

  async function hydrateSessionAccentColors(post,signal) {
    if (!supabase || !post) return post;
    const references = [...(post.sessionParticipants || []), ...(post.sessionEntries || []).map(entry => ({ participantType: entry.type === 'dialogue' ? entry.speakerType : entry.actorType, participantId: entry.type === 'dialogue' ? entry.speakerId : entry.actorId }))];
    const characterIds = [...new Set(references.filter(item => item.participantType === 'character' && item.participantId).map(item => item.participantId))];
    const npcIds = [...new Set(references.filter(item => item.participantType === 'npc' && item.participantId).map(item => item.participantId))];
    let [characterResult, npcResult] = await Promise.all([
      characterIds.length ? supabase.from('characters').select('id, owner_id, name, avatar_url').in('id', characterIds).abortSignal(signal) : { data: [] },
      npcIds.length ? supabase.from('posts_public').select('id, title, npc_name, image_url').in('id', npcIds).abortSignal(signal) : { data: [] }
    ]);
    if (npcResult.error && npcIds.length) npcResult = await supabase.from('posts_public').select('id, title, image_url').in('id', npcIds).abortSignal(signal);
    const characterRows = characterResult.error ? [] : characterResult.data || [];
    const npcRows = npcResult.error ? [] : npcResult.data || [];
    const ownerIds = [...new Set(characterRows.map(character => character.owner_id).filter(Boolean))];
    const profileResult = ownerIds.length ? await supabase.from('profiles').select('id, accent_color').in('id', ownerIds).abortSignal(signal) : { data: [] };
    const ownerColors = new Map((profileResult.error ? [] : profileResult.data || []).map(profile => [profile.id, getReadableAccentColor(profile.accent_color)]));
    return mergeSessionReferences(post, characterRows, npcRows, ownerColors);
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
    const [publicResult, editResult] = await Promise.all([
      supabase.from('posts_public').select(publicPostDetailSelect).eq('id', id).maybeSingle(),
      supabase.rpc('get_post_for_edit', { p_post_id: id })
    ]);
    const editData = Array.isArray(editResult.data) ? editResult.data[0] : editResult.data;
    const data = publicResult.data && editData
      ? { ...publicResult.data, ...editData, image_url: editData.image_url || publicResult.data.image_url }
      : editData || publicResult.data;
    const error = publicResult.error || editResult.error;
    if (requestId !== editRequestId || !currentRoute.startsWith('edit/')) return;
    if (error || !data) { editLoading = false; editingPostId = null; return showNotice('수정할 게시글을 불러오지 못했습니다.'); }
    const post = formatPost(data, new Map(categories.map((board) => [board.slug, board])));
    if (!user || post.authorId !== user.id) { editLoading = false; editingPostId = null; return navigateTo(`#post/${id}`); }
    writeBoardSlug = post.boardSlug;
    editingPostAuthorId = post.authorId;
    postForm = { title: post.title, content: post.content, postType: post.postType || 'notice', isPrivate: post.isPrivate, privatePassword: post.privatePassword || '', npcName: post.npcName, npcAge: post.npcAge, npcGender: post.npcGender, npcHeight: post.npcHeight, npcRace: post.npcRace, npcRole: post.npcRole, npcTraits: post.npcTraits, npcAffiliation: post.npcAffiliation, npcPersonality: post.npcPersonality, bgmCategory: post.bgmCategory || 'map', bgmUrl: post.bgmUrl || '', bgmFile: null, imageFile: null };
    sessionParticipants = post.boardSlug === 'sessions' ? post.sessionParticipants.map((participant) => ({ ...participant, participantName: participant.participantName || participant.name || '', id: participant.id || (crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`) })) : [];
    sessionBgmIds = post.boardSlug === 'sessions' ? post.sessionBgms.map((bgm) => bgm.id).filter(Boolean) : [];
    sessionEntries = post.boardSlug === 'sessions' && post.sessionEntries.length ? post.sessionEntries.map((entry) => ({ ...entry, id: entry.id || (crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`), imageFile: null })) : post.boardSlug === 'sessions' && post.content ? [{ ...createSessionEntry('narration'), text: post.content }] : [];
    npcOriginalImageUrl = post.imageUrl || '';
    npcImagePreview = npcOriginalImageUrl;
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

  async function setupRichEditor() {
    if (richEditor || !richEditorElement) return;
    if (!richEditorLoader) {
      richEditorLoader = Promise.all([
        import('@toast-ui/editor'),
        import('@toast-ui/editor/dist/toastui-editor.css')
      ]);
    }
    const [{ default: Editor }] = await richEditorLoader;
    if (richEditor || !richEditorElement || (!isWritePage && !isEditPage) || writeBoardSlug !== 'users') return;
    const mobileEditor = window.matchMedia('(max-width: 760px)').matches;
    const editorOptions = {
      el: richEditorElement,
      height: mobileEditor ? '100%' : '600px',
      initialEditType: 'wysiwyg',
      previewStyle: 'tab',
      autofocus: false,
      initialValue: postForm.content || '',
      placeholder: '내용을 자유롭게 작성해 주세요.',
      usageStatistics: false,
      events: { change: handleRichEditorInput }
    };
    if (mobileEditor) {
      editorOptions.toolbarItems = [
        ['bold', 'italic'],
        ['ul', 'ol'],
        ['link', 'image']
      ];
      editorOptions.hideModeSwitch = true;
    }
    richEditor = new Editor(editorOptions);
    richEditorElement.querySelector('[contenteditable="true"]')?.setAttribute('aria-label', '내용');
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

  function getDecorationFingerprint() {
    const visiblePosts = isBoardPage ? pagedBoardPosts : pagedFilteredPosts;
    return JSON.stringify({
      route: currentRoute,
      section: profileSection,
      writeBoard: writeBoardSlug,
      user: user?.id || '',
      componentReady: currentRoute === 'home' || Boolean(
        (isBoardPage && BoardPage) || (isPostPage && PostDetailPage) || ((isWritePage || isEditPage) && WritePage)
        || (isMyPage && MyPage) || (isAdminPage && AdminPage) || (isAdminMypage && AdminMypage)
        || (isAdminCharacterPage && AdminCharacterPage) || (isAdminItemsPage && AdminItemsPage) || (isAdminMonstersPage && AdminMonstersPage)
        || (isShopPage && ShopPage) || (isAdminShopPage && AdminShopPage)
        || (isAdminCombatTestPage && AdminCombatTestPage) || (isMiniGamesPage && MiniGamesPage)
        || (isDiceRollerPage && DiceRollerPage) || (isCombatPage && CombatPage)
      ),
      visiblePosts: visiblePosts.map((post) => [post.id, post.avatarUrl]),
      detail: [detailPost?.id, detailPost?.avatarUrl, detailPost?.isPrivate, privatePostUnlocked],
      comments: detailComments.map((comment) => [comment.id, comment.parent_id, comment.avatarUrl]),
      profile: [adminProfileImagePreview, profileAccentColor],
      character: [adminSelectedCharacter?.id, character?.id, character?.money, profileSection, selectedInventoryItem?.id],
      relationships: relationships.map((item) => [item.id, item.relationship_name, item.npc_post_id, item.memo]),
      sessionEntries: sessionEntries.map((entry) => entry.id),
      editor: Boolean(richEditor)
    });
  }

  afterUpdate(() => {
    if ((isWritePage || isEditPage) && writeBoardSlug === 'users') setupRichEditor();
    else if (richEditor) { richEditor.destroy(); richEditor = null; richEditorElement = null; }
    const nextFingerprint = getDecorationFingerprint();
    if (nextFingerprint === decorationFingerprint) return;
    decorationFingerprint = nextFingerprint;
    decorateCommunityUi();
  });

  function reorderSessionEntry(sourceId, targetId, position = 'before') {
    if (!sourceId || !targetId || sourceId === targetId) return;
    const sourceIndex = sessionEntries.findIndex((entry) => entry.id === sourceId);
    const targetIndex = sessionEntries.findIndex((entry) => entry.id === targetId);
    if (sourceIndex < 0 || targetIndex < 0) return;
    const nextEntries = [...sessionEntries];
    const [movedEntry] = nextEntries.splice(sourceIndex, 1);
    let insertIndex = targetIndex + (position === 'after' ? 1 : 0);
    if (sourceIndex < insertIndex) insertIndex -= 1;
    nextEntries.splice(insertIndex, 0, movedEntry);
    sessionEntries = nextEntries;
  }

  function stopSessionDragAutoScroll() {
    sessionDragPointerY = 0;
    if (sessionDragScrollFrame) cancelAnimationFrame(sessionDragScrollFrame);
    sessionDragScrollFrame = 0;
  }

  function sessionDragScrollLoop() {
    if (!draggedSessionEntryId || !sessionDragPointerY) return stopSessionDragAutoScroll();
    const edgeSize = 110;
    const maxStep = 22;
    const viewportHeight = window.innerHeight;
    let step = 0;
    if (sessionDragPointerY < edgeSize) step = -Math.ceil((edgeSize - sessionDragPointerY) / edgeSize * maxStep);
    else if (sessionDragPointerY > viewportHeight - edgeSize) step = Math.ceil((sessionDragPointerY - (viewportHeight - edgeSize)) / edgeSize * maxStep);
    if (step) window.scrollBy(0, step);
    sessionDragScrollFrame = requestAnimationFrame(sessionDragScrollLoop);
  }

  function updateSessionDragAutoScroll(clientY) {
    if (!draggedSessionEntryId) return;
    sessionDragPointerY = clientY;
    if (!sessionDragScrollFrame) sessionDragScrollFrame = requestAnimationFrame(sessionDragScrollLoop);
  }

  function setupSessionDragAutoScroll() {
    if (sessionDragEventsReady) return;
    sessionDragEventsReady = true;
    window.addEventListener('dragover', (event) => updateSessionDragAutoScroll(event.clientY));
    window.addEventListener('drop', stopSessionDragAutoScroll);
  }

  function decorateSessionDragAndDrop() {
    setupSessionDragAutoScroll();
    document.querySelectorAll('.session-entry').forEach((entryElement) => {
      const handle = entryElement.querySelector('.session-entry-top');
      if (!handle || handle.dataset.dragHandleReady) return;
      const entryId = sessionEntries[Number(entryElement.querySelector('.session-entry-number')?.textContent || 0) - 1]?.id;
      if (!entryId) return;
      handle.dataset.dragHandleReady = 'true';
      handle.draggable = true;
      entryElement.dataset.sessionEntryId = entryId;
      handle.addEventListener('dragstart', (event) => {
        draggedSessionEntryId = entryId;
        sessionDragPointerY = event.clientY;
        entryElement.classList.add('session-entry-dragging');
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData('text/plain', entryId);
      });
      handle.addEventListener('dragend', () => {
        draggedSessionEntryId = '';
        stopSessionDragAutoScroll();
        document.querySelectorAll('.session-entry-dragging, .session-entry-drag-over').forEach((element) => element.classList.remove('session-entry-dragging', 'session-entry-drag-over'));
      });
      entryElement.addEventListener('dragover', (event) => {
        if (!draggedSessionEntryId || draggedSessionEntryId === entryId) return;
        event.preventDefault();
        updateSessionDragAutoScroll(event.clientY);
        event.dataTransfer.dropEffect = 'move';
        document.querySelectorAll('.session-entry-drag-over').forEach((element) => element.classList.remove('session-entry-drag-over'));
        entryElement.classList.add('session-entry-drag-over');
        entryElement.dataset.dropPosition = event.clientY > entryElement.getBoundingClientRect().top + entryElement.getBoundingClientRect().height / 2 ? 'after' : 'before';
      });
      entryElement.addEventListener('drop', (event) => {
        event.preventDefault();
        reorderSessionEntry(draggedSessionEntryId || event.dataTransfer.getData('text/plain'), entryId, entryElement.dataset.dropPosition || 'before');
        draggedSessionEntryId = '';
        stopSessionDragAutoScroll();
        entryElement.classList.remove('session-entry-drag-over');
        delete entryElement.dataset.dropPosition;
      });
    });
  }

  function decorateCommunityUi() {
    const privateUnlockForm = document.querySelector('[data-private-unlock-form]');
    if (privateUnlockForm && !privateUnlockForm.dataset.ready) {
      privateUnlockForm.dataset.ready = 'true';
      privateUnlockForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        const passwordInput = privateUnlockForm.querySelector('[data-private-password]');
        const errorElement = privateUnlockForm.querySelector('[data-private-error]');
        const submitButton = privateUnlockForm.querySelector('button[type="submit"]');
        if (submitButton) submitButton.disabled = true;
        const unlocked = await unlockPrivatePost(passwordInput?.value || '');
        if (submitButton) submitButton.disabled = false;
        if (!unlocked && errorElement) errorElement.textContent = privatePostError;
      });
    }
    const privateContentLocked = Boolean(detailPost?.isPrivate && !privatePostUnlocked);
    document.querySelector('.detail-actions')?.classList.toggle('private-content-locked', privateContentLocked);
    document.querySelector('.comments-section')?.classList.toggle('private-content-locked', privateContentLocked);
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
      adminPreview.innerHTML = adminProfileImagePreview ? `<img decoding="async" src="${adminProfileImagePreview}" alt="프로필 미리보기" />` : '<span>사진을 선택해 주세요</span>';
    }
    decorateAdminCharacterDetail();
    decorateAdminAccountMoneyField();
    decorateMoneyControls();
    decorateProfileColorPicker();
    decorateSessionDragAndDrop();
    document.querySelectorAll('.detail-footer').forEach((element) => element.remove());
    detailComments.forEach((comment, index) => {
      const item = document.querySelectorAll('.comment-item')[index];
      if (item && comment.parent_id) item.classList.add('comment-reply');
      if (item && user && !item.querySelector('[data-reply-button]')) {
        const button = document.createElement('button'); button.className = 'comment-action-btn comment-reply-btn'; button.type = 'button'; button.textContent = '답글'; button.dataset.replyButton = 'true';
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
    document.querySelectorAll('img').forEach((image) => {
      if (!image.hasAttribute('loading')) image.loading = 'lazy';
      if (!image.hasAttribute('decoding')) image.decoding = 'async';
    });
  }

  function decorateProfileColorPicker() {
    const fields = document.querySelector('.mypage .profile-fields');
    if (!fields || fields.querySelector('[data-profile-color]')) return;
    const label = document.createElement('label');
    label.dataset.profileColor = 'true';
    label.textContent = '나의 테마 색상';
    const input = document.createElement('input');
    input.className = 'accent-color-input';
    input.type = 'color';
    input.value = getReadableAccentColor(profileAccentColor);
    input.setAttribute('aria-label', '나의 테마 색상 선택');
    const applyColor = (value) => document.querySelector('.profile-photo-preview')?.style.setProperty('--profile-accent', getReadableAccentColor(value));
    applyColor(input.value);
    input.addEventListener('input', (event) => {
      profileAccentColor = event.currentTarget.value;
      applyColor(profileAccentColor);
    });
    input.addEventListener('change', (event) => saveProfileAccentColor(event.currentTarget.value));
    label.append(input);
    fields.append(label);
  }

  function positionEditorPopup() {
    if (!window.matchMedia('(max-width: 760px)').matches) return;
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

  function decorateMoneyControls() {
    const adminInput = document.querySelector('.character-detail-page .combat-grid label:nth-child(2) input');
    if (adminInput) {
      const label = adminInput.parentElement;
      if (label?.firstChild?.nodeType === Node.TEXT_NODE) label.firstChild.nodeValue = '보유 돈 (G)';
      adminInput.type = 'text';
      adminInput.inputMode = 'numeric';
      adminInput.pattern = '[0-9]*';
      adminInput.min = '';
      adminInput.max = '';
      if (!adminInput.dataset.moneyReady) {
        adminInput.dataset.moneyReady = 'true';
        adminInput.addEventListener('input', updateAdminCharacterMoney);
      }
      adminInput.value = sanitizeMoneyInput(adminCharacterForm.money);
    }

    const playerInput = document.querySelector('.mypage .combat-grid label:nth-child(2) input');
    if (playerInput) {
      const label = playerInput.parentElement;
      if (label?.firstChild?.nodeType === Node.TEXT_NODE) label.firstChild.nodeValue = '보유 돈 (G)';
      playerInput.type = 'text';
      playerInput.value = formatMoney(character?.money);
    }
  }

  function decorateAdminAccountMoneyField() {
    const form = [...document.querySelectorAll('.admin-layout form')].find((candidate) => candidate.querySelector('input[placeholder="플레이어 아이디"]'));
    const fields = form?.querySelector('.field-grid');
    if (!form || !fields) return;
    let input = form.querySelector('[data-admin-starting-money]');
    if (!input) {
      const label = document.createElement('label');
      label.textContent = '보유 돈 (G)';
      input = document.createElement('input');
      input.type = 'text';
      input.inputMode = 'numeric';
      input.pattern = '[0-9]*';
      input.placeholder = '0';
      input.dataset.adminStartingMoney = 'true';
      input.addEventListener('input', updateAdminFormMoney);
      label.append(input);
      fields.append(label);
    }
    input.value = sanitizeMoneyInput(adminForm.character.money);
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

  async function resizeImage(file, { maxSide = 1000, quality = .82, maxBytes = 2_000_000 } = {}) {
    const sourceUrl = URL.createObjectURL(file);
    try {
      const image = new Image();
      image.src = sourceUrl;
      await new Promise((resolve, reject) => { image.onload = resolve; image.onerror = reject; });
      const scale = Math.min(1, maxSide / Math.max(image.naturalWidth, image.naturalHeight));
      const canvas = document.createElement('canvas');
      canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
      canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
      canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
      const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', quality));
      if (!blob) throw new Error('이미지를 변환하지 못했습니다.');
      if (blob.size > maxBytes) throw new Error('이미지를 조금 더 작은 파일로 올려 주세요.');
      return blob;
    } finally {
      URL.revokeObjectURL(sourceUrl);
    }
  }

  const resizeProfileImage = file => resizeImage(file, { maxSide: 480, quality: .76, maxBytes: 600_000 });

  async function imageFileToDataUrl(file, options) {
    const blob = await resizeImage(file, options);
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result || ''));
      reader.onerror = () => reject(new Error('이미지를 읽지 못했습니다.'));
      reader.readAsDataURL(blob);
    });
  }

  async function uploadProfileImage(file) {
    if (!file || !supabase || !user) return '';
    const blob = await resizeProfileImage(file);
    const fileId = crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`;
    const path = `${user.id}/${fileId}.jpg`;
    const { error } = await supabase.storage.from('profile-images').upload(path, blob, { contentType: 'image/jpeg', upsert: false });
    if (error) {
      if (/bucket|not found|row-level security|policy/i.test(error.message)) throw new Error('프로필 이미지 저장소 설정이 필요합니다. 새 SQL 파일을 먼저 실행해 주세요.');
      throw new Error(`프로필 이미지 업로드 실패: ${error.message}`);
    }
    return supabase.storage.from('profile-images').getPublicUrl(path).data.publicUrl;
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
    if (postForm.isPrivate && postForm.privatePassword.trim().length < 4) return showNotice('비밀글 비밀번호는 4자 이상 입력해 주세요.');
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
        imageUrl = await imageFileToDataUrl(postForm.imageFile, { maxSide: 640, quality: .76, maxBytes: 700_000 });
      } catch (error) {
        postSaving = false;
        return showNotice(error instanceof Error ? error.message : '이미지를 처리하지 못했습니다.');
      }
    }
    const privacyPayload = { is_private: Boolean(postForm.isPrivate), private_password: postForm.isPrivate ? postForm.privatePassword.trim() : null };
    const npcImageUrl = imageUrl || npcImagePreview || npcOriginalImageUrl || null;
    const payload = { board_slug: boardSlug, title: postTitle, content: postContent, excerpt: (sessionExcerpt || postContent || postTitle).replace(/\s+/g, ' ').slice(0, 140), status: 'published', author_id: editingPostId ? editingPostAuthorId : user.id, ...privacyPayload, image_url: boardSlug === 'npc' ? npcImageUrl : null, youtube_url: null, bgm_url: boardSlug === 'bgm' ? bgmUrl || null : null, bgm_category: boardSlug === 'bgm' ? postForm.bgmCategory : null, post_type: boardSlug === 'notices' ? postForm.postType : null, npc_name: boardSlug === 'npc' ? postForm.npcName.trim() : null, npc_age: boardSlug === 'npc' ? numberOrNull(postForm.npcAge) : null, npc_gender: boardSlug === 'npc' ? postForm.npcGender.trim() : null, npc_height: boardSlug === 'npc' ? numberOrNull(postForm.npcHeight) : null, npc_race: boardSlug === 'npc' ? postForm.npcRace.trim() : null, npc_role: boardSlug === 'npc' ? postForm.npcRole.trim() : null, npc_traits: boardSlug === 'npc' ? postForm.npcTraits.trim() : null, npc_affiliation: boardSlug === 'npc' ? postForm.npcAffiliation.trim() : null, npc_personality: boardSlug === 'npc' ? postForm.npcPersonality.trim() : null };
    let { data, error } = editingPostId
      ? await supabase.from('posts').update(payload).eq('id', editingPostId).select('id').single()
      : await supabase.from('posts').insert(payload).select('id').single();
    if (error && /is_private|private_password/i.test(error.message)) {
      postSaving = false;
      return showNotice('비밀글 기능을 사용하려면 안내된 DB 쿼리를 먼저 실행해 주세요.');
    }
    if (error && /column|schema cache|image_url|npc_|bgm_/i.test(error.message)) {
      const fallbackData = { image_url: boardSlug === 'npc' ? npcImageUrl : null, npc_name: postForm.npcName.trim(), npc_age: numberOrNull(postForm.npcAge), npc_gender: postForm.npcGender.trim(), npc_height: numberOrNull(postForm.npcHeight), npc_race: postForm.npcRace.trim(), npc_role: postForm.npcRole.trim(), npc_traits: postForm.npcTraits.trim(), npc_affiliation: postForm.npcAffiliation.trim(), npc_personality: postForm.npcPersonality.trim() };
      const encoded = btoa(unescape(encodeURIComponent(JSON.stringify(fallbackData))));
      const bgmFallback = btoa(unescape(encodeURIComponent(JSON.stringify({ bgm_url: bgmUrl || null, bgm_category: postForm.bgmCategory }))));
      const legacyContent = boardSlug === 'sessions' ? postContent : boardSlug === 'bgm' ? `<!--OPEN_DOOR_BGM:${bgmFallback}-->${postContent}` : `<!--OPEN_DOOR_NPC:${encoded}-->${postContent}`;
      const legacyPayload = { board_slug: boardSlug, title: postTitle, content: legacyContent, excerpt: (sessionExcerpt || postContent || postTitle).replace(/\s+/g, ' ').slice(0, 140), status: 'published', author_id: editingPostId ? editingPostAuthorId : user.id, ...privacyPayload };
      ({ data, error } = editingPostId
        ? await supabase.from('posts').update(legacyPayload).eq('id', editingPostId).select('id').single()
        : await supabase.from('posts').insert(legacyPayload).select('id').single());
    }
    postSaving = false;
    if (error) return showNotice(`글 저장 실패: ${error.message}`);
    if (postForm.isPrivate && data?.id) {
      const privacyCheck = await supabase.from('posts_public').select('id, is_private').eq('id', data.id).maybeSingle();
      if (privacyCheck.error) {
        return showNotice(`비밀글 저장 확인 실패: ${privacyCheck.error.message}`);
      }
      if (!privacyCheck.data?.is_private) {
        return showNotice('저장 결과가 비밀글로 확인되지 않았습니다. DB 컬럼과 저장 정책을 확인해 주세요.');
      }
    }
    if (npcImagePreview) URL.revokeObjectURL(npcImagePreview);
    sessionEntries.forEach((entry) => entry.imageUrl?.startsWith('blob:') && URL.revokeObjectURL(entry.imageUrl));
    npcImagePreview = '';
    npcOriginalImageUrl = '';
    sessionEntries = [];
    sessionParticipants = [];
    sessionBgmIds = [];
    postForm = { title: '', content: '', postType: 'notice', isPrivate: false, privatePassword: '', npcName: '', npcAge: '', npcGender: '', npcHeight: '', npcRace: '', npcRole: '', npcTraits: '', npcAffiliation: '', npcPersonality: '', bgmCategory: 'map', bgmUrl: '', bgmFile: null, imageFile: null }; editingPostId = null; await loadDatabase(true); showNotice(wasEditing ? '게시글을 수정했습니다.' : '게시글을 등록했습니다.'); navigateTo(`#post/${data.id}`);
  }

  async function deletePost(post) {
    if (!requireLogin() || !supabase || !(isAdmin || post.authorId === user.id) || !confirm('게시글을 삭제할까요?')) return;
    const deleteQuery = supabase.from('posts').delete().eq('id', post.id);
    if (!isAdmin) deleteQuery.eq('author_id', user.id);
    const { error } = await deleteQuery;
    if (error) return showNotice(`게시글 삭제 실패: ${error.message}`);
    await loadDatabase(true); showNotice('게시글을 삭제했습니다.'); navigateTo('#home');
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
  function selectInventoryItem(item) { selectedInventoryItem = resolveInventoryItem(item); }
  function resolveInventoryItem(item) {
    if (!item) return item;
    const catalog = Array.isArray(item.items) ? item.items[0] : item.items;
    if (catalog) {
      return {
        ...item,
        item_id: item.item_id || catalog.id,
        item_name: catalog.name,
        item_effect: catalog.item_effect,
        item_description: catalog.item_description || item.item_description || '',
        grade: catalog.grade,
        item_type: catalog.item_type,
        equipment_slot: catalog.equipment_slot || item.equipment_slot || '',
        icon_url: catalog.icon_url || item.icon_url || '',
        is_equipped: Boolean(item.is_equipped),
        chest_reward_item_ids: catalog.chest_reward_item_ids || [],
        chest_reward_count: catalog.chest_reward_count || 1
      };
    }
    return { ...item, is_equipped: Boolean(item.is_equipped) };
  }
  function getInventoryIcon(item) {
    const resolved = resolveInventoryItem(item);
    if (resolved?.icon_url) return resolved.icon_url;
    if (resolved?.item_type === '소비' || /물약|포션|bottle|potion/i.test(resolved?.item_name || '')) return '/icons/round-potion.png';
    return { 유물: '✦', 장비: '⚔', 소비: '✚', 상자: '▣', 기타: '◆' }[resolved?.item_type] || '◆';
  }
  function isEquippableItem(item) { return ['장비', '유물'].includes(resolveInventoryItem(item)?.item_type); }
  function getEquippedInventory(items = []) { return items.map((item) => resolveInventoryItem(item)).filter((item) => isEquippableItem(item) && Boolean(item.is_equipped)); }
  async function toggleInventoryEquipment(item, characterId = character?.id) {
    if (!requireLogin() || !supabase || !characterId || !item?.id || !isEquippableItem(item) || equipmentSaving) return;
    const resolvedItem = resolveInventoryItem(item);
    const isEquipped = !Boolean(item.is_equipped);
    if (isEquipped && resolvedItem.item_type === '장비' && !resolvedItem.equipment_slot) return showNotice('장비 부위가 지정되지 않았습니다. 관리자 아이템 관리에서 부위를 먼저 설정해 주세요.');
    equipmentSaving = true;
    const { error } = await supabase.rpc('set_inventory_item_equipped', { p_inventory_item_id: item.id, p_equipped: isEquipped });
    equipmentSaving = false;
    if (error) {
      if (/set_inventory_item_equipped|equipment_slot|is_equipped|function|column|schema cache/i.test(error.message)) return showNotice('부위별 장착을 사용하려면 supabase/queries/add_equipment_slots.sql을 먼저 실행해 주세요.');
      return showNotice(`장착 상태 변경 실패: ${error.message}`);
    }
    const { itemsResult } = await loadCharacterCollections(characterId);
    if (!itemsResult.error) {
      const refreshedItems = itemsResult.data || [];
      if (character?.id === characterId) inventory = refreshedItems;
      if (adminSelectedCharacter?.id === characterId) adminInventory = refreshedItems;
      if (selectedInventoryItem) selectedInventoryItem = refreshedItems.find((inventoryItem) => inventoryItem.id === selectedInventoryItem.id) || null;
    }
    showNotice(isEquipped ? `'${resolvedItem.item_name}'을(를) 장착했습니다.` : `'${resolvedItem.item_name}'의 장착을 해제했습니다.`);
  }
  function isChestItem(item) { return item?.item_type === '상자'; }
  function buildRouletteSequence(source, count) {
    if (!source.length || count < 1) return [];
    const sequence = [];
    while (sequence.length < count) {
      const block = [...source].sort(() => Math.random() - 0.5);
      if (sequence.length && block.length > 1 && block[0].id === sequence[sequence.length - 1].id) {
        [block[0], block[1]] = [block[1], block[0]];
      }
      sequence.push(...block);
      // A rare repeated tile breaks the predictable 1-2-1-2 rhythm with two candidates.
      if (source.length > 1 && Math.random() < 0.28 && sequence.length < count) {
        sequence.push(source[Math.floor(Math.random() * source.length)]);
      }
    }
    return sequence.slice(0, count);
  }
  async function openInventoryChest() {
    if (!requireLogin() || !supabase || !character?.id || !selectedInventoryItem?.id || !isChestItem(selectedInventoryItem)) return;
    openingChest = true;
    chestOpeningDone = false;
    chestOpeningReady = false;
    chestOpeningRewards = [];
    chestOpeningTiles = [];
    rouletteTrackStyle = '';
    const openingStartedAt = Date.now();
    const rewardIds = selectedInventoryItem.chest_reward_item_ids || [];
    const openingPromise = supabase.rpc('open_inventory_chest', { p_inventory_item_id: selectedInventoryItem.id, p_character_id: character.id });
    const previewResult = await supabase.from('items').select('id, name, item_effect, item_description, grade, item_type, icon_url').in('id', rewardIds);
    const previewItems = previewResult.data || [];
    if (previewItems.length) {
      // Keep cycling through the configured candidates while the server resolves the draw.
      const loopTiles = buildRouletteSequence(previewItems, 18);
      chestOpeningTiles = [...loopTiles, ...loopTiles];
      chestOpeningReady = true;
      await tick();
    }
    const { data, error } = await openingPromise;
    if (error) {
      const remainingErrorTime = Math.max(0, 6000 - (Date.now() - openingStartedAt));
      if (remainingErrorTime) await new Promise((resolve) => setTimeout(resolve, remainingErrorTime));
      openingChest = false;
      return showNotice(`상자를 열지 못했습니다: ${error.message}`);
    }
    const rewards = data || [];
    const tileSource = previewItems.length ? previewItems : rewards;
    const targetReward = rewards[Math.floor(Math.random() * rewards.length)] || tileSource[0];
    const targetIndex = 72;
    chestOpeningTiles = tileSource.length
      ? [...buildRouletteSequence(tileSource, targetIndex), targetReward, ...buildRouletteSequence(tileSource, 10)]
      : [];
    chestOpeningRewards = rewards;
    chestOpeningReady = true;
    await tick();
    const rouletteTile = document.querySelector('.roulette-tile');
    const rouletteWindow = document.querySelector('.roulette-window');
    if (rouletteTile && rouletteWindow) {
      const tileWidth = rouletteTile.getBoundingClientRect().width;
      const stopPosition = rouletteWindow.getBoundingClientRect().width / 2 - (targetIndex * tileWidth) - tileWidth / 2;
      rouletteTrackStyle = `--roulette-stop: ${stopPosition}px`;
    }
    const remainingSpinTime = Math.max(0, 6800 - (Date.now() - openingStartedAt));
    if (remainingSpinTime) await new Promise((resolve) => setTimeout(resolve, remainingSpinTime));
    await loadCharacterData(true);
    selectedInventoryItem = null;
    chestOpeningDone = true;
  }
  function closeChestOpening() {
    openingChest = false;
    chestOpeningDone = false;
    chestOpeningReady = false;
    const names = chestOpeningRewards.map((item) => item.item_name).join(', ');
    chestOpeningRewards = [];
    chestOpeningTiles = [];
    showNotice(names ? `상자를 열어 ${names}을(를) 획득했습니다.` : '상자에서 획득한 아이템이 없습니다.');
  }
  function isImageIcon(value) { return typeof value === 'string' && /^(\/|data:image\/|https?:\/\/)/.test(value); }
  function resetItemForm() {
    itemForm = { id: '', name: '', item_effect: '', item_description: '', grade: '일반', item_type: '기타', equipment_slot: '', icon_url: '', chest_reward_item_ids: [], chest_reward_count: 1, combat_effects:null, relic_effects:null };
    itemFormImageFile = null;
    if (itemFormImagePreview?.startsWith('blob:')) URL.revokeObjectURL(itemFormImagePreview);
    itemFormImagePreview = '';
  }
  function editCatalogItem(item) {
    itemForm = { id: item.id, name: item.name, item_effect: item.item_effect || '', item_description: item.item_description || '', grade: item.grade, item_type: item.item_type, equipment_slot: item.equipment_slot || '', icon_url: item.icon_url || '', chest_reward_item_ids: item.chest_reward_item_ids || [], chest_reward_count: item.chest_reward_count || 1, combat_effects:item.combat_effects ?? null, relic_effects:item.relic_effects ?? null };
    itemFormImageFile = null;
    if (itemFormImagePreview?.startsWith('blob:')) URL.revokeObjectURL(itemFormImagePreview);
    itemFormImagePreview = item.icon_url || '';
  }
  function handleItemFormImageChange(event) {
    const file = event.currentTarget.files?.[0] || null;
    if (!file) return;
    if (!['image/png', 'image/jpeg', 'image/webp'].includes(file.type)) return showNotice('PNG, JPG, WEBP 이미지만 업로드할 수 있어요.');
    if (file.size > 5 * 1024 * 1024) return showNotice('이미지는 5MB 이하로 업로드해 주세요.');
    itemFormImageFile = file;
    if (itemFormImagePreview?.startsWith('blob:')) URL.revokeObjectURL(itemFormImagePreview);
    itemFormImagePreview = URL.createObjectURL(file);
  }
  function normalizeShopListing(row) {
    const item = Array.isArray(row?.items) ? row.items[0] : row?.items;
    return {
      ...row,
      item: item || { id: row?.item_id, name: '삭제된 아이템', item_effect: '', item_description: '', grade: '기타', item_type: '기타', icon_url: '' },
      item_name: item?.name || '삭제된 아이템',
      item_effect: item?.item_effect || '',
      item_description: item?.item_description || '',
      grade: item?.grade || '기타',
      item_type: item?.item_type || '기타',
      price_g: Number(row?.price_g) || 0,
      personal_limit: row?.personal_limit ?? null,
      total_limit: row?.total_limit ?? null,
      sold_count: Number(row?.sold_count) || 0,
      personal_purchased: Number(row?.personal_purchased) || 0,
      is_active: Boolean(row?.is_active)
    };
  }
  async function loadShopData() {
    if (!supabase || !user) {
      shopListings = [];
      adminShopListings = [];
      shopBalance = null;
      shopLoading = false;
      adminShopLoading = false;
      return;
    }
    shopLoading = true;
    adminShopLoading = isAdminShopPage;
    shopError = '';
    const result = await supabase.from('shop_listings').select('id, item_id, price_g, personal_limit, total_limit, sold_count, is_active, created_at, updated_at, items(id, name, item_effect, item_description, grade, item_type, icon_url)').order('created_at', { ascending: false });
    if (result.error) {
      shopListings = [];
      adminShopListings = [];
      shopError = /shop_listings|relation|schema cache|column/i.test(result.error.message)
        ? '상점 테이블이 아직 준비되지 않았습니다. 제공된 create_shop.sql을 Supabase SQL Editor에서 실행해 주세요.'
        : result.error.message;
      shopLoading = false;
      adminShopLoading = false;
      return;
    }
    const balanceResult = await supabase.from('characters').select('id, money').eq('owner_id', user.id).maybeSingle();
    shopBalance = balanceResult.error ? null : (balanceResult.data?.money ?? 0);
    let rows = (result.data || []).map(normalizeShopListing);
    if (balanceResult.data?.id && rows.length) {
      const purchaseResult = await supabase.from('shop_purchases').select('listing_id, quantity').eq('character_id', balanceResult.data.id);
      const purchasedByListing = (purchaseResult.data || []).reduce((counts, purchase) => ({ ...counts, [purchase.listing_id]: Number(purchase.quantity) || 0 }), {});
      rows = rows.map((listing) => ({ ...listing, personal_purchased: purchasedByListing[listing.id] || 0 }));
    }
    shopListings = rows;
    adminShopListings = isAdmin ? rows : [];
    shopLoading = false;
    adminShopLoading = false;
  }
  function setShopPurchaseQuantity(listingId, value) {
    shopPurchaseQuantities = { ...shopPurchaseQuantities, [listingId]: Math.max(1, Math.floor(Number(value) || 1)) };
  }
  async function purchaseShopItem(listingId, quantity = 1) {
    if (!requireLogin('상점에서 구매하려면 로그인해 주세요.') || !supabase || shopPurchaseSaving) return;
    const safeQuantity = Math.max(1, Math.floor(Number(quantity) || 1));
    shopPurchaseSaving = true;
    const result = await supabase.rpc('purchase_shop_item', { p_listing_id: listingId, p_quantity: safeQuantity });
    shopPurchaseSaving = false;
    if (result.error) return showNotice(`구매 실패: ${result.error.message}`);
    const purchase = result.data || {};
    shopBalance = purchase.remaining_balance ?? shopBalance;
    await loadCharacterData(true);
    await loadShopData();
    showNotice(`${purchase.item_name || '상품'} ${purchase.quantity || safeQuantity}개를 구매했습니다.`);
  }
  function resetShopForm() {
    shopForm = { id: '', item_id: '', price_g: 0, personal_limit: '', total_limit: '', sold_count: 0, is_active: false };
  }
  function editShopListing(listing) {
    shopForm = { id: listing.id, item_id: listing.item_id, price_g: listing.price_g, personal_limit: listing.personal_limit ?? '', total_limit: listing.total_limit ?? '', sold_count: listing.sold_count || 0, is_active: listing.is_active };
  }
  async function saveShopListing() {
    if (!isAdmin || !supabase) return;
    if (!shopForm.item_id) return showNotice('판매할 아이템을 선택해 주세요.');
    const payload = {
      item_id: shopForm.item_id,
      price_g: Math.max(0, Math.floor(Number(shopForm.price_g) || 0)),
      personal_limit: shopForm.personal_limit === '' || shopForm.personal_limit === null ? null : Math.max(1, Math.floor(Number(shopForm.personal_limit) || 1)),
      total_limit: shopForm.total_limit === '' || shopForm.total_limit === null ? null : Math.max(1, Math.floor(Number(shopForm.total_limit) || 1)),
      is_active: Boolean(shopForm.is_active)
    };
    shopAdminSaving = true;
    const result = shopForm.id
      ? await supabase.from('shop_listings').update(payload).eq('id', shopForm.id).select().single()
      : await supabase.from('shop_listings').insert(payload).select().single();
    shopAdminSaving = false;
    if (result.error) return showNotice(`상점 상품 저장 실패: ${result.error.message}`);
    resetShopForm();
    await loadShopData();
    showNotice('상점 상품을 저장했습니다.');
  }
  async function deleteShopListing(listing) {
    if (!isAdmin || !supabase || !listing?.id || !confirm(`'${listing.item_name}' 상품을 상점에서 삭제할까요?`)) return;
    const result = await supabase.from('shop_listings').delete().eq('id', listing.id);
    if (result.error) return showNotice(`상점 상품 삭제 실패: ${result.error.message}`);
    if (shopForm.id === listing.id) resetShopForm();
    await loadShopData();
    showNotice('상점 상품을 삭제했습니다.');
  }
  async function loadCatalogItems(force = false) {
    if (!supabase || !isAdmin) return;
    if (!force && catalogLoadedAt && Date.now() - catalogLoadedAt < 60000) return;
    if (catalogLoadPromise) return catalogLoadPromise;
    catalogLoading = true;
    catalogLoadPromise = (async () => {
      let result = await supabase.from('items').select('*').order('name');
      if (result.error && /equipment_slot|chest_reward|column|schema cache/i.test(result.error.message)) {
        result = await supabase.from('items').select('id, name, item_effect, grade, item_type, icon_url, created_at').order('name');
      }
      if (result.error && /items|relation|schema cache/i.test(result.error.message)) {
        catalogItems = [];
        return;
      }
      if (result.error) return showNotice(`아이템 목록 조회 실패: ${result.error.message}`);
      catalogItems = result.data || [];
      catalogLoadedAt = Date.now();
    })().finally(() => {
      catalogLoading = false;
      catalogLoadPromise = null;
    });
    return catalogLoadPromise;
  }
  async function saveCatalogItem() {
    if (!isAdmin || !supabase) return;
    const name = itemForm.name.trim();
    if (!name) return showNotice('아이템 이름을 입력해 주세요.');
    if (itemForm.item_type === '장비' && !itemForm.equipment_slot) return showNotice('장비 부위를 선택해 주세요.');
    const itemRule = itemForm.item_type === '소비' ? itemForm.combat_effects : null;
    const relicRule = itemForm.item_type === '유물' ? itemForm.relic_effects : null;
    let hasRelicSchema;
    try { hasRelicSchema = await prepareRelicSave(supabase,relicRule); }
    catch(problem) { return showNotice(problem.message || '유물 효과를 확인하지 못했습니다.'); }
    let hasItemCombatSchema;
    try { hasItemCombatSchema = await prepareConsumableSave(supabase,itemRule); }
    catch(problem) { return showNotice(problem.message || '아이템 효과 설정을 확인하지 못했습니다.'); }
    itemSaving = true;
    let iconUrl = itemForm.icon_url || null;
    if (itemFormImageFile) {
      try { iconUrl = await imageFileToDataUrl(itemFormImageFile, { maxSide: 256, quality: .76, maxBytes: 250_000 }); } catch (error) {
        itemSaving = false;
        return showNotice(error instanceof Error ? error.message : '아이템 이미지를 처리하지 못했습니다.');
      }
    }
    const payload = { name, item_effect: itemForm.item_effect.trim(), item_description: itemForm.item_description.trim(), grade: itemForm.grade, item_type: itemForm.item_type, equipment_slot: itemForm.item_type === '장비' ? itemForm.equipment_slot : null, icon_url: iconUrl, chest_reward_item_ids: itemForm.item_type === '상자' ? itemForm.chest_reward_item_ids : [], chest_reward_count: itemForm.item_type === '상자' ? Math.max(1, Number(itemForm.chest_reward_count) || 1) : 1, ...(hasItemCombatSchema ? {combat_effects:itemRule} : {}), ...(hasRelicSchema ? {relic_effects:relicRule} : {}) };
    let result = itemForm.id
      ? await supabase.from('items').update(payload).eq('id', itemForm.id).select().single()
      : await supabase.from('items').insert(payload).select().single();
    if (result.error && /equipment_slot/i.test(result.error.message)) {
      itemSaving = false;
      return showNotice('장비 부위를 저장하려면 supabase/queries/add_equipment_slots.sql을 먼저 실행해 주세요.');
    }
    if (result.error && /item_description|column|schema cache/i.test(result.error.message)) {
      const { item_description, ...legacyPayload } = payload;
      result = itemForm.id
        ? await supabase.from('items').update(legacyPayload).eq('id', itemForm.id).select().single()
        : await supabase.from('items').insert(legacyPayload).select().single();
      if (!result.error && item_description) showNotice('아이템은 저장했지만 설명 컬럼이 없어 설명은 저장되지 않았습니다. 제공된 SQL을 먼저 실행해 주세요.');
    }
    itemSaving = false;
    if (result.error) return showNotice(`아이템 저장 실패: ${result.error.message}`);
    const wasEdit = Boolean(itemForm.id);
    resetItemForm();
    await loadCatalogItems(true);
    showNotice(wasEdit ? '아이템을 수정했습니다.' : '아이템을 등록했습니다.');
  }
  async function deleteCatalogItem(item) {
    if (!isAdmin || !supabase || !item?.id || !confirm(`'${item.name}' 아이템을 삭제할까요?`)) return;
    const { error } = await supabase.from('items').delete().eq('id', item.id);
    if (error) return showNotice(`아이템 삭제 실패: ${error.message}`);
    if (itemForm.id === item.id) resetItemForm();
    await loadCatalogItems(true);
    showNotice('아이템을 삭제했습니다.');
  }
  function addCatalogItemToInventory(catalogItem) {
    if (!catalogItem?.id) return;
    const existingIndex = adminInventory.findIndex((item) => item.item_id === catalogItem.id);
    if (existingIndex >= 0) {
      adminInventory = adminInventory.map((item, index) => index === existingIndex ? { ...item, quantity: Math.max(1, Number(item.quantity) || 1) + 1 } : item);
      showNotice(`'${catalogItem.name}' 수량을 1 증가시켰습니다.`);
      return;
    }
    adminInventory = [...adminInventory, {
      item_id: catalogItem.id,
      item_name: catalogItem.name,
      item_effect: catalogItem.item_effect || '',
      item_description: catalogItem.item_description || '',
      grade: catalogItem.grade,
      item_type: catalogItem.item_type,
      equipment_slot: catalogItem.equipment_slot || '',
      icon_url: catalogItem.icon_url || '',
      quantity: 1,
      is_equipped: false
    }];
    inventorySearchTerm = '';
    showNotice(`'${catalogItem.name}'을(를) 인벤토리에 추가했습니다.`);
  }

  async function handleAdminInventoryImage(event, index) {
    showNotice('아이템 정보는 아이템 관리 페이지에서 수정해 주세요.');
  }
  function newInventoryItem() { inventory = [...inventory, { item_name: '', item_effect: '', item_description: '', quantity: 1, grade: '일반', item_type: '기타', is_equipped: false }]; }
  function newCard() { cards = [...cards, { card_name: '', card_effect: '', card_exhaust_effect: '', card_drop_effect: '', card_drop_count: 0, card_retain: false, card_innate: false, card_ethereal: false, card_type: '스킬', card_target: '자신', quantity: 1, energy: 0, grade: '기본' }]; }
  function removeInventory(index) { inventory = inventory.filter((_, itemIndex) => itemIndex !== index); }
  function removeCard(index) { cards = cards.filter((_, cardIndex) => cardIndex !== index); }
  function setCharacterForm(data) {
    characterForm = { name: data?.name || '', roleName: data?.role_name || '', roleTraits: data?.role_traits || '', age: data?.age ?? '', height: data?.height ?? '', weight: data?.weight ?? '' };
  }

  function sanitizeMoneyInput(value) {
    return String(value ?? '').replace(/[^0-9]/g, '');
  }

  function normalizeMoney(value) {
    const parsed = Number(sanitizeMoneyInput(value));
    return Number.isFinite(parsed) ? Math.min(Math.floor(parsed), 2147483647) : 0;
  }

  function formatMoney(value) {
    return `${new Intl.NumberFormat('ko-KR').format(normalizeMoney(value))} G`;
  }

  function updateAdminFormMoney(event) {
    const money = sanitizeMoneyInput(event.currentTarget.value);
    event.currentTarget.value = money;
    adminForm = { ...adminForm, character: { ...adminForm.character, money } };
  }

  function updateAdminCharacterMoney(event) {
    const money = sanitizeMoneyInput(event.currentTarget.value);
    event.currentTarget.value = money;
    adminCharacterForm = { ...adminCharacterForm, money };
  }

  function selectAdminCharacter(data) {
    adminSelectedCharacter = data;
    adminCharacterForm = { name: data?.name || '', roleName: data?.role_name || data?.class_name || '', roleTraits: data?.role_traits || data?.content || '', age: data?.age ?? '', height: data?.height ?? '', weight: data?.weight ?? '', money: String(data?.money ?? 0), level: data?.level ?? 1, hp: data?.hp ?? 0, maxHp: data?.max_hp ?? 0, mp: data?.mp ?? 0, maxMp: data?.max_mp ?? 0, attack: data?.attack ?? 0, defense: data?.defense ?? 0, combatNotes: data?.combat_notes || '', personalEnergy: {...defaultPersonalEnergy(),...(data?.personal_energy || {})} };
    navigateTo(`#admin-character/${data.id}`);
  }

  function selectAdminCharacterState(data) {
    adminSelectedCharacter = data;
    adminCharacterForm = { name: data?.name || '', roleName: data?.role_name || data?.class_name || '', roleTraits: data?.role_traits || data?.content || '', age: data?.age ?? '', height: data?.height ?? '', weight: data?.weight ?? '', money: String(data?.money ?? 0), level: data?.level ?? 1, hp: data?.hp ?? 0, maxHp: data?.max_hp ?? 0, mp: data?.mp ?? 0, maxMp: data?.max_mp ?? 0, attack: data?.attack ?? 0, defense: data?.defense ?? 0, combatNotes: data?.combat_notes || '', personalEnergy: {...defaultPersonalEnergy(),...(data?.personal_energy || {})} };
  }

  async function loadAdminCharacterDetail(id) {
    if (!isAdmin || !supabase || !id) return;
    adminDetailLoading = true;
    // Read the revision before inventory rows so any concurrent consumption makes a later save stale.
    const characterResult = await supabase.from('characters').select('*').eq('id', id).maybeSingle();
    const [collections] = await Promise.all([
      loadCharacterCollections(id),
      loadCatalogItems(),
      loadCharacterRecords(id)
    ]);
    if (characterResult.error || !characterResult.data) { adminDetailLoading = false; return showNotice('캐릭터 상세 정보를 불러오지 못했습니다.'); }
    selectAdminCharacterState(characterResult.data);
    const { itemsResult, cardsResult } = collections;
    if (itemsResult.error || cardsResult.error) { adminDetailLoading = false; return showNotice('인벤토리 또는 카드 정보를 불러오지 못했습니다.'); }
    adminInventory = (itemsResult.data || []).map((item) => resolveInventoryItem(item));
    adminInventoryBaseline = JSON.stringify(adminInventory);
    adminInventoryVersion = characterResult.data.inventory_version ?? null;
    adminCards = cardsResult.data || [];
    adminDetailLoading = false;
  }

  async function saveAdminCharacter() {
    if (!isAdmin || !supabase || !adminSelectedCharacter || adminCharacterSaving) return;
    if (!adminCharacterForm.name.trim() || !adminCharacterForm.roleName.trim()) return showNotice('캐릭터 이름과 역할명을 입력해 주세요.');
    adminCharacterSaving = true;
    try {
      const characterId = adminSelectedCharacter.id;
      const cards = buildAdminCardRows(adminCards, characterId);
      const hasPresetSchema = await prepareCardSave(supabase, cards);
      const energyConfig = {...defaultPersonalEnergy(),...adminCharacterForm.personalEnergy};
      const hasResourceSchema = await prepareResourceSave(supabase, energyConfig, cards);
      const inventoryChanged = JSON.stringify(adminInventory) !== adminInventoryBaseline;
      const expectedInventoryVersion = adminInventoryVersion;
      const payload = { name: adminCharacterForm.name.trim(), class_name: adminCharacterForm.roleName.trim(), content: adminCharacterForm.roleTraits.trim(), role_name: adminCharacterForm.roleName.trim(), role_traits: adminCharacterForm.roleTraits.trim(), age: numberOrNull(adminCharacterForm.age), height: numberOrNull(adminCharacterForm.height), weight: numberOrNull(adminCharacterForm.weight), money: normalizeMoney(adminCharacterForm.money), level: Math.max(1, Number(adminCharacterForm.level) || 1), hp: Math.max(0, Number(adminCharacterForm.hp) || 0), max_hp: Math.max(0, Number(adminCharacterForm.maxHp) || 0), mp: Math.max(0, Number(adminCharacterForm.mp) || 0), max_mp: Math.max(0, Number(adminCharacterForm.maxMp) || 0), attack: Math.max(0, Number(adminCharacterForm.attack) || 0), defense: Math.max(0, Number(adminCharacterForm.defense) || 0), combat_notes: adminCharacterForm.combatNotes.trim(), ...(hasResourceSchema ? {personal_energy:energyConfig.name.trim() ? {...energyConfig,name:energyConfig.name.trim()} : {}} : {}) };
      let characterResult = await supabase.from('characters').update(payload).eq('id', adminSelectedCharacter.id).select().single();
      if (characterResult.error && /money/i.test(characterResult.error.message)) {
        adminCharacterSaving = false;
        return showNotice('보유 돈을 저장하려면 characters.money 컬럼 SQL을 먼저 실행해 주세요.');
      }
      if (characterResult.error && /level|max_hp|combat_notes|extra_info|column|schema cache/i.test(characterResult.error.message)) {
        const { money, level, hp, max_hp, mp, max_mp, attack, defense, combat_notes, ...legacyPayload } = payload;
        characterResult = await supabase.from('characters').update(legacyPayload).eq('id', adminSelectedCharacter.id).select().single();
      }
      if (characterResult.error) return showNotice(`캐릭터 수정 실패: ${characterResult.error.message}`);
      selectAdminCharacterState({ ...adminSelectedCharacter, ...characterResult.data });
      const usesSeparateCardEffects = cards.some((card) => card.card_exhaust_effect || card.card_drop_effect || card.card_drop_count > 0 || card.card_retain || card.card_innate || card.card_ethereal || card.card_type !== '스킬' || card.card_target !== '자신');
      if (usesSeparateCardEffects) {
        const cardEffectsSchema = await supabase.from('character_cards').select('card_exhaust_effect, card_drop_effect, card_drop_count, card_retain, card_innate, card_ethereal, card_type, card_target').limit(0);
        if (cardEffectsSchema.error) {
          adminCharacterSaving = false;
          return showNotice('카드 키워드·타입·대상 컬럼을 저장하려면 새 SQL을 먼저 실행해 주세요.');
        }
      }
      if (hasPresetSchema) {
        const { data: savedCards, error: saveError } = await supabase.rpc('combat_save_character_cards', { p_character_id: characterId, p_cards: cards });
        if (saveError) return showNotice(`카드 저장 실패: ${saveError.code === 'PGRST202' ? 'add_card_combat_presets.sql 전체를 적용해 주세요.' : saveError.message}`);
        adminCards = (savedCards || []).map(normalizeOwnedCard);
      }
      const deleteItems = hasResourceSchema ? {error:null} : await supabase.from('inventory_items').delete().eq('character_id', characterId);
      const deleteCards = hasPresetSchema ? { error: null } : await supabase.from('character_cards').delete().eq('character_id', characterId);
      if (deleteItems.error || deleteCards.error) { adminCharacterSaving = false; return showNotice('인벤토리 또는 카드 정리 중 오류가 발생했습니다.'); }
      const items = adminInventory
        .filter((item) => item.item_id || item.item_name?.trim())
        .map((item) => ({
          ...(hasResourceSchema && item.id ? {id:item.id} : {}),
          character_id: characterId,
          item_id: item.item_id || null,
          item_name: item.item_name?.trim() || '',
          item_effect: item.item_effect?.trim() || '',
          item_description: item.item_description?.trim() || '',
          quantity: Math.max(1, Number(item.quantity) || 1),
          is_equipped: isEquippableItem(item) ? Boolean(item.is_equipped) : false,
          grade: item.grade,
          item_type: item.item_type,
          icon_url: item.icon_url || null
        }));
      const itemSaveError = hasResourceSchema ? (inventoryChanged ? (await supabase.rpc('combat_save_inventory',{p_character_id:characterId,p_expected_version:expectedInventoryVersion,p_items:items})).error : null) : await saveInventoryWithIconFallback(items);
      if (itemSaveError) { adminCharacterSaving = false; return showNotice(`인벤토리 저장 실패: ${itemSaveError.message}`); }
      const cardSaveError = hasPresetSchema ? null : await saveCardsWithEnergyFallback(cards.map(({ id, combat_rule, ...card }) => card));
      if (cardSaveError) { adminCharacterSaving = false; return showNotice(`카드 저장 실패: ${cardSaveError.message}`); }
      await loadCharacterData(true);
      await loadAdminCharacterDetail(characterId);
      showNotice('캐릭터 정보를 수정했습니다.');
    } catch (error) {
      showNotice(error.message || '캐릭터 정보를 저장하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      adminCharacterSaving = false;
    }
  }

  async function deleteAdminCharacter() {
    if (!isAdmin || !supabase || !adminSelectedCharacter || !confirm(`'${adminSelectedCharacter.name}' 캐릭터를 삭제할까요?`)) return;
    const { error } = await supabase.from('characters').delete().eq('id', adminSelectedCharacter.id);
    if (error) return showNotice(`캐릭터 삭제 실패: ${error.message}`);
    adminSelectedCharacter = null;
    adminInventory = [];
    adminCards = [];
    navigateTo('#admin');
    await loadCharacterData(true);
    showNotice('캐릭터를 삭제했습니다.');
  }

  function newAdminInventoryItem() {
    if (!catalogItems.length) {
      showNotice('먼저 아이템 관리 페이지에서 아이템을 등록해 주세요.');
      navigateTo('#admin/items');
      return;
    }
    inventorySearchTerm = '';
    showNotice('아래 검색창에서 아이템을 검색해 인벤토리에 추가해 주세요.');
  }
  function removeAdminInventory(index) { adminInventory = adminInventory.filter((_, itemIndex) => itemIndex !== index); }
  function newAdminCard() { adminCards = [...adminCards, { card_name: '', card_effect: '', card_exhaust_effect: '', card_drop_effect: '', card_drop_count: 0, card_retain: false, card_innate: false, card_ethereal: false, card_type: '스킬', card_target: '자신', quantity: 1, energy: 0, grade: '기본' }]; }
  function removeAdminCard(index) { adminCards = adminCards.filter((_, cardIndex) => cardIndex !== index); }

  async function loadCharacterCollections(characterId) {
    const loadItems = async () => {
      let result = await supabase.from('inventory_items').select('id, item_id, item_name, item_effect, item_description, quantity, grade, item_type, icon_url, is_equipped, items(id, name, item_effect, item_description, grade, item_type, equipment_slot, icon_url, chest_reward_item_ids, chest_reward_count)').eq('character_id', characterId).order('created_at');
      if (result.error && /items|item_id|relation|schema cache/i.test(result.error.message)) {
        result = await supabase.from('inventory_items').select('id, item_name, item_effect, quantity, grade, item_type, icon_url, is_equipped').eq('character_id', characterId).order('created_at');
      }
      if (result.error) {
        const legacyResult = await supabase.from('inventory_items').select('id, item_name, item_effect, quantity, grade, item_type').eq('character_id', characterId).order('created_at');
        if (!legacyResult.error) result = { ...legacyResult, data: (legacyResult.data || []).map((item) => ({ ...item, icon_url: '', item_id: null })) };
      }
      return result.error ? result : { ...result, data: (result.data || []).map((item) => resolveInventoryItem(item)) };
    };

    const loadCards = async () => {
      const result = await supabase.from('character_cards').select('*').eq('character_id', characterId).order('created_at');
      return result.error ? result : { ...result, data: (result.data || []).map(normalizeOwnedCard) };
    };

    const [itemsResult, cardsResult] = await Promise.all([loadItems(), loadCards()]);
    return { itemsResult, cardsResult };
  }

  function toggleCombatTestCharacter(characterId) {
    if (combatTestStarted || !characterId) return;
    combatTestSelectedCharacterIds = combatTestSelectedCharacterIds.includes(characterId)
      ? combatTestSelectedCharacterIds.filter((id) => id !== characterId)
      : [...combatTestSelectedCharacterIds, characterId];
  }

  function shuffleCombatTestCards(cards = []) {
    const shuffled = [...cards];
    for (let index = shuffled.length - 1; index > 0; index -= 1) {
      const targetIndex = Math.floor(Math.random() * (index + 1));
      [shuffled[index], shuffled[targetIndex]] = [shuffled[targetIndex], shuffled[index]];
    }
    return shuffled;
  }

  function createCombatTestDrawPile(deckCards = []) {
    return shuffleCombatTestCards(deckCards.map((card) => ({
      ...card,
      drawId: crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`
    })));
  }

  function drawCombatTestCards(player, count = 1) {
    let drawPile = [...(player.drawPile || [])];
    const exhaustedIds = new Set((player.exhaustedCards || []).map((card) => card.instanceId));
    const retainedIds = new Set((player.hand || []).filter((card) => card.card_retain).map((card) => card.instanceId));
    const availableDeckCards = (player.deckCards || []).filter((card) => !exhaustedIds.has(card.instanceId) && !retainedIds.has(card.instanceId));
    const drawnCards = [];
    while (drawnCards.length < count) {
      if (!drawPile.length) {
        if (!availableDeckCards.length) break;
        drawPile = createCombatTestDrawPile(availableDeckCards);
      }
      const drawCount = Math.min(count - drawnCards.length, drawPile.length);
      drawnCards.push(...drawPile.splice(0, drawCount));
    }
    return { ...player, hand: [...(player.hand || []), ...drawnCards], drawPile };
  }

  function drawCombatTestHand(player, count = 5) {
    return drawCombatTestCards(player, count);
  }

  function drawCombatTestOpeningHand(player, count = 5) {
    const exhaustedIds = new Set((player.exhaustedCards || []).map((card) => card.instanceId));
    const availableDeckCards = (player.deckCards || []).filter((card) => !exhaustedIds.has(card.instanceId));
    const innateCards = shuffleCombatTestCards(availableDeckCards.filter((card) => card.card_innate));
    const openingHand = innateCards.slice(0, count);
    const openingIds = new Set(openingHand.map((card) => card.instanceId));
    const remainingCards = availableDeckCards.filter((card) => !openingIds.has(card.instanceId));
    const playerWithOpeningHand = { ...player, hand: [], drawPile: createCombatTestDrawPile(remainingCards) };
    return { ...playerWithOpeningHand, hand: createCombatTestDrawPile(openingHand) };
  }

  async function startCombatTest() {
    if (!isAdmin || !supabase || combatTestLoading) return;
    if (!combatTestSelectedCharacterIds.length) return showNotice('전투 테스트에 참여할 플레이어를 선택해 주세요.');
    combatTestLoading = true;
    let cardsResult = await supabase.from('character_cards').select('*').in('character_id', combatTestSelectedCharacterIds).order('created_at');
    if (cardsResult.error && /energy|card_exhaust_effect|card_drop_effect|card_drop_count|card_retain|card_innate|card_ethereal|card_type|card_target|column|schema cache/i.test(cardsResult.error.message)) {
      cardsResult = await supabase.from('character_cards').select('id, character_id, card_name, card_effect, card_exhaust_effect, card_drop_effect, card_drop_count, card_retain, card_innate, card_ethereal, card_type, card_target, quantity, grade').in('character_id', combatTestSelectedCharacterIds).order('created_at');
    }
    if (cardsResult.error && /card_exhaust_effect|card_drop_effect|card_drop_count|card_retain|card_innate|card_ethereal|card_type|card_target|column|schema cache/i.test(cardsResult.error.message)) {
      cardsResult = await supabase.from('character_cards').select('id, character_id, card_name, card_effect, quantity, grade').in('character_id', combatTestSelectedCharacterIds).order('created_at');
    }
    let equipmentResult = await supabase.from('inventory_items').select('id, character_id, item_effect, is_equipped, items(item_effect)').in('character_id', combatTestSelectedCharacterIds).eq('is_equipped', true);
    if (equipmentResult.error && /items|relation|schema cache/i.test(equipmentResult.error.message)) {
      equipmentResult = await supabase.from('inventory_items').select('id, character_id, item_effect, is_equipped').in('character_id', combatTestSelectedCharacterIds).eq('is_equipped', true);
    }
    combatTestLoading = false;
    if (cardsResult.error) return showNotice(`카드 덱을 불러오지 못했습니다: ${cardsResult.error.message}`);
    if (equipmentResult.error) {
      if (/is_equipped|column|schema cache/i.test(equipmentResult.error.message)) return showNotice('장착 효과를 불러오려면 add_inventory_equipment.sql을 먼저 실행해 주세요.');
      return showNotice(`장착 효과를 불러오지 못했습니다: ${equipmentResult.error.message}`);
    }

    const cardsByCharacter = new Map();
    for (const card of cardsResult.data || []) {
      const quantity = Math.max(1, Number(card.quantity) || 1);
      const copies = Array.from({ length: quantity }, (_, copyIndex) => ({ ...card, card_exhaust_effect: card.card_exhaust_effect || '', card_drop_effect: card.card_drop_effect || '', card_drop_count: Math.max(0, Number(card.card_drop_count) || 0), card_retain: Boolean(card.card_retain), card_innate: Boolean(card.card_innate), card_ethereal: Boolean(card.card_ethereal), card_type: card.card_type || '스킬', card_target: card.card_target || '자신', energy: Number(card.energy) || 0, copyIndex, instanceId: crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}` }));
      cardsByCharacter.set(card.character_id, [...(cardsByCharacter.get(card.character_id) || []), ...copies]);
    }
    const effectsByCharacter = new Map();
    for (const item of equipmentResult.data || []) {
      const catalog = Array.isArray(item.items) ? item.items[0] : item.items;
      const effect = String(catalog?.item_effect || item.item_effect || '').trim();
      if (!effect) continue;
      const effects = effectsByCharacter.get(item.character_id) || [];
      if (!effects.includes(effect)) effectsByCharacter.set(item.character_id, [...effects, effect]);
    }

    combatTestPlayers = combatTestSelectedCharacterIds
      .map((characterId) => adminCharacters.find((character) => character.id === characterId))
      .filter(Boolean)
      .map((character) => {
        const deckCards = cardsByCharacter.get(character.id) || [];
        return drawCombatTestOpeningHand({
          characterId: character.id,
          name: character.name,
          nickname: character.nickname,
          avatarUrl: character.avatar_url || '',
          hp: Number(character.hp) || 0,
          maxHp: Number(character.max_hp) || 0,
          equippedEffects: effectsByCharacter.get(character.id) || [],
          deckCards,
          drawPile: createCombatTestDrawPile(deckCards),
          exhaustedCards: [],
          hand: []
        });
      });
    combatTestTurn = 1;
    combatTestStarted = true;
  }

  function nextCombatTestTurn() {
    if (!combatTestStarted || !combatTestPlayers.length) return;
    combatTestPlayers = combatTestPlayers.map((player) => {
      const etherealCards = (player.hand || []).filter((card) => card.card_ethereal);
      const retainedCards = (player.hand || []).filter((card) => card.card_retain && !card.card_ethereal);
      return drawCombatTestHand({ ...player, hand: retainedCards, exhaustedCards: [...(player.exhaustedCards || []), ...etherealCards] }, Math.max(0, 5 - retainedCards.length));
    });
    combatTestTurn += 1;
  }

  function playCombatTestCard(characterId, drawId) {
    if (!combatTestStarted || !characterId || !drawId) return;
    const player = combatTestPlayers.find((candidate) => candidate.characterId === characterId);
    const card = player?.hand?.find((candidate) => candidate.drawId === drawId);
    if (!player || !card) return;
    const hand = player.hand.filter((candidate) => candidate.drawId !== drawId);
    const isExhausted = Boolean(card.combat_rule?.exhaust);
    const leavesDeck = isExhausted || card.card_type === '파워';
    const nextPlayer = {
      ...player,
      hand,
      exhaustedCards: leavesDeck ? [...(player.exhaustedCards || []), card] : [...(player.exhaustedCards || [])]
    };
    const dropCount = Math.max(0, Number(card.card_drop_count) || 0);
    const updatedPlayer = dropCount ? drawCombatTestCards(nextPlayer, dropCount) : nextPlayer;
    combatTestPlayers = combatTestPlayers.map((candidate) => candidate.characterId === characterId ? updatedPlayer : candidate);
    const actionText = [isExhausted ? '소멸' : leavesDeck ? '파워 사용' : '버림', dropCount ? `추가 ${dropCount}장 드로우` : ''].filter(Boolean).join(' · ');
    showNotice(`${card.card_name || '카드'} 사용: ${actionText}`);
  }

  async function writeCombatTestClipboard(copyText) {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(copyText);
      return;
    }
    const textarea = document.createElement('textarea');
    textarea.value = copyText;
    textarea.setAttribute('readonly', '');
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);
    textarea.select();
    const copied = document.execCommand('copy');
    textarea.remove();
    if (!copied) throw new Error('copy command failed');
  }

  async function copyCombatTestCards() {
    if (!combatTestStarted || !combatTestPlayers.length) return showNotice('복사할 카드 목록이 없습니다.');
    try {
      await writeCombatTestClipboard(formatCombatTestCards(combatTestPlayers, combatTestTurn, true));
      showNotice('모든 플레이어의 드롭 카드 목록을 복사했습니다.');
    } catch {
      showNotice('카드 목록을 복사하지 못했습니다.');
    }
  }

  async function copyCombatTestPlayerCards(player) {
    if (!combatTestStarted || !player) return showNotice('복사할 카드 목록이 없습니다.');
    try {
      await writeCombatTestClipboard(formatCombatTestCards([player], combatTestTurn, true));
      showNotice(`${player.name}의 카드 목록을 복사했습니다.`);
    } catch {
      showNotice('카드 목록을 복사하지 못했습니다.');
    }
  }

  function resetCombatTest() {
    combatTestPlayers = [];
    combatTestStarted = false;
    combatTestTurn = 0;
  }

  async function loadCharacterRecords(characterId) {
    extraRecordCharacterId = characterId;
    extraRecords = [];
    relationships = [];
    const [recordsResult, relationshipsResult] = await Promise.all([
      supabase.from('character_extra_records').select('id, title, content, author_id, created_at, profiles(nickname)').eq('character_id', characterId).order('created_at', { ascending: false }),
      supabase.from('character_relationships').select('id, relationship_name, memo, npc_post_id, created_at, posts(id, title, board_slug)').eq('character_id', characterId).order('created_at', { ascending: false })
    ]);
    if (!recordsResult.error) {
      extraRecords = (recordsResult.data || []).map((record) => ({ ...record, authorName: record.profiles?.nickname || '모험가' }));
    }
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
    let fallbackRows = rows;
    let result = await supabase.from('character_cards').insert(rows);
    if (result.error && /card_exhaust_effect|card_drop_effect|card_drop_count|card_retain|card_innate|card_ethereal|card_type|card_target|column|schema cache/i.test(result.error.message)) {
      if (rows.some((card) => card.card_exhaust_effect || card.card_drop_effect || card.card_drop_count > 0 || card.card_retain || card.card_innate || card.card_ethereal || card.card_type !== '스킬' || card.card_target !== '자신')) return new Error('카드 키워드·타입·대상 컬럼이 없습니다. 새 SQL을 실행한 뒤 다시 저장해 주세요.');
      fallbackRows = rows.map(({ card_exhaust_effect, card_drop_effect, card_drop_count, card_retain, card_innate, card_ethereal, card_type, card_target, ...card }) => card);
      result = await supabase.from('character_cards').insert(fallbackRows);
    }
    if (result.error && /energy|column|schema cache/i.test(result.error.message)) {
      fallbackRows = fallbackRows.map(({ energy, ...card }) => card);
      result = await supabase.from('character_cards').insert(fallbackRows);
    }
    return result.error || null;
  }

  async function saveInventoryWithIconFallback(rows) {
    if (!rows.length) return null;
    let result = await supabase.from('inventory_items').insert(rows);
    if (result.error && /item_id|icon_url|item_description|is_equipped|column|schema cache/i.test(result.error.message)) {
      result = await supabase.from('inventory_items').insert(rows.map(({ item_id, icon_url, item_description, is_equipped, ...item }) => item));
    }
    return result.error || null;
  }

  async function loadCharacterData(force = false) {
    if (!supabase || !user) {
      characterLoading = false;
      adminLoading = false;
      return;
    }

    const mode = isAdmin
      ? (currentRoute === 'admin' ? 'admin-list' : 'admin-rich')
      : 'player';
    const loadKey = `${user.id}:${mode}`;
    if (!force && characterLoadedKey === loadKey && Date.now() - characterLoadedAt < 30000) return;
    if (!force && characterLoadPromises.has(loadKey)) return characterLoadPromises.get(loadKey);

    const requestId = ++characterRequestId;

    characterLoading = true;
    adminLoading = isAdmin;
    characterError = '';

    const loadPromise = (async () => {
      try {
        const adminSelect = mode === 'admin-list'
          ? 'id, owner_id, name, role_name, age, created_at'
          : 'id, owner_id, name, role_name, age, avatar_url, hp, max_hp, created_at';
        const characterQuery = isAdmin
          ? supabase.from('characters').select(adminSelect).order('created_at', { ascending: false })
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
        } else {
          if (requestId !== characterRequestId) return;
          character = data || null;
          profileImagePreview = character?.avatar_url || '';
          setCharacterForm(character);
          await syncCharacterAvatarToProfile(character?.avatar_url || null);
          if (!character) {
            inventory = [];
            cards = [];
          } else {
            const { itemsResult, cardsResult } = await loadCharacterCollections(character.id);
            if (itemsResult.error) throw new Error(itemsResult.error.message);
            if (cardsResult.error) throw new Error(cardsResult.error.message);
            inventory = (itemsResult.data || []).map((item) => resolveInventoryItem(item));
            cards = cardsResult.data || [];
            await loadCharacterRecords(character.id);
          }
        }
        if (requestId === characterRequestId) {
          characterLoadedKey = loadKey;
          characterLoadedAt = Date.now();
        }
      } catch (error) {
        if (requestId === characterRequestId) characterError = error instanceof Error ? error.message : '캐릭터 정보를 불러오지 못했습니다.';
      } finally {
        if (requestId === characterRequestId) {
          characterLoading = false;
          adminLoading = false;
        }
      }
    })().finally(() => characterLoadPromises.delete(loadKey));
    characterLoadPromises.set(loadKey, loadPromise);
    return loadPromise;
  }

  async function saveCharacter() {
    if (!requireLogin() || !supabase) return;
    if (!characterForm.name.trim() || !characterForm.roleName.trim()) return showNotice('캐릭터 이름과 역할명을 입력해 주세요.');
    characterSaving = true;
    let profileImageUrl = profileImagePreview && !profileImagePreview.startsWith('blob:') ? profileImagePreview : '';
    if (profileImageFile) {
      try { profileImageUrl = await uploadProfileImage(profileImageFile); } catch (error) { characterSaving = false; return showNotice(error instanceof Error ? error.message : '프로필 이미지를 처리하지 못했습니다.'); }
    }
    const payload = { owner_id: user.id, name: characterForm.name.trim(), class_name: characterForm.roleName.trim(), content: characterForm.roleTraits.trim(), status: 'published', role_name: characterForm.roleName.trim(), role_traits: characterForm.roleTraits.trim(), age: numberOrNull(characterForm.age), height: numberOrNull(characterForm.height), weight: numberOrNull(characterForm.weight), avatar_url: profileImageUrl || null };
    let characterResult = character?.id ? await supabase.from('characters').update(payload).eq('id', character.id).select().single() : await supabase.from('characters').insert(payload).select().single();
    if (characterResult.error && /avatar_url|column|schema cache/i.test(characterResult.error.message)) {
      const { avatar_url, ...legacyPayload } = payload;
      characterResult = character?.id ? await supabase.from('characters').update(legacyPayload).eq('id', character.id).select().single() : await supabase.from('characters').insert(legacyPayload).select().single();
    }
    if (characterResult.error) { characterSaving = false; return showNotice(`캐릭터 저장 실패: ${characterResult.error.message}`); }
    character = characterResult.data;
    const accentColor = getReadableAccentColor(profileAccentColor);
    const profileColorResult = await supabase.from('profiles').update({ accent_color: accentColor }).eq('id', user.id);
    if (profileColorResult.error && !/accent_color|column|schema cache/i.test(profileColorResult.error.message)) showNotice(`프로필 색상 저장에 실패했습니다: ${profileColorResult.error.message}`);
    profile = { ...profile, accent_color: accentColor };
    profileAccentColor = accentColor;
    const avatarSynced = await syncCharacterAvatarToProfile(character?.avatar_url || null, true);
    profileImageFile = null; characterSaving = false;
    if (avatarSynced !== false) showNotice('캐릭터 기본 정보와 프로필 사진을 저장했습니다.');
    await loadCharacterData(true);
  }

  async function createPlayerAccount() {
    if (!isAdmin || !supabase) return;
    if (!adminForm.loginId.trim() || !adminForm.password || !adminForm.nickname.trim()) return showNotice('아이디, 비밀번호, 표시 이름을 입력해 주세요.');
    accountSaving = true;
    const { error } = await supabase.functions.invoke('admin-create-user', { body: { loginId: adminForm.loginId.trim(), password: adminForm.password, nickname: adminForm.nickname.trim(), character: adminForm.character } });
    accountSaving = false;
    if (error) return showNotice(`계정 생성 실패: ${error.message}`);
    adminForm = { loginId: '', password: '', nickname: '', character: { name: '', roleName: '', roleTraits: '', age: '', height: '', weight: '', money: '0' } }; showNotice('플레이어 계정과 캐릭터를 생성했습니다.'); await loadCharacterData(true);
  }

  onMount(() => {
    syncRoute();

    // Register routing before the remote database/auth boot sequence. A slow
    // Supabase request must never prevent hash links from changing the page.
    window.addEventListener('hashchange', syncRoute);
    let authSubscription;
    const updateWritingViewport = () => {
      const viewportHeight = window.visualViewport?.height || window.innerHeight;
      document.documentElement.style.setProperty('--writing-viewport-height', `${Math.round(viewportHeight)}px`);
    };
    updateWritingViewport();
    window.addEventListener('resize', updateWritingViewport);
    window.visualViewport?.addEventListener('resize', updateWritingViewport);

    const initialize = async () => {
      const databasePromise = loadDatabase();
      if (!supabase) { await databasePromise; authReady = true; return; }
      if (currentRoute === 'admin') profileLoading = true;
      const { data } = await supabase.auth.getSession();
      await Promise.all([databasePromise, applySession(data.session)]);
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
      window.removeEventListener('resize', updateWritingViewport);
      window.visualViewport?.removeEventListener('resize', updateWritingViewport);
      document.documentElement.style.removeProperty('--writing-viewport-height');
    };
  });
</script>

<svelte:head><title>open door — 장기 TRPG 캠페인 기록소</title><meta name="description" content="세계관, 캐릭터, 세션 기록을 함께 쌓아가는 open door 장기 TRPG 캠페인 사이트입니다." /></svelte:head>
<div class="site" class:writing-mode={isWritePage}><div class="bg-grid" aria-hidden="true"></div><div class="bg-glow bg-glow-a" aria-hidden="true"></div><div class="bg-glow bg-glow-b" aria-hidden="true"></div>
  <header class="header"><a class="brand" href="#home" aria-label="open door 홈"><span class="brand-mark">od</span><span class="brand-copy"><strong>open door</strong><small>long-form TRPG campaign</small></span></a>
     <nav class="main-nav" aria-label="주요 메뉴"><a class:active={currentRoute === 'home'} href="#home">홈</a><div class="nav-item nav-dropdown"><a class:active={currentRoute === 'board/notices' || currentRoute === 'board/sessions'} href="#board/notices" aria-haspopup="true">공지사항</a><div class="dropdown-menu" aria-label="공지사항 메뉴"><a href="#board/notices"><strong>공지사항</strong><small>운영 안내 · 업데이트 · 이벤트</small></a><a href="#board/sessions"><strong>세션 로그</strong><small>플레이 기록 · 후기 · 다음화 예고</small></a></div></div><div class="nav-item nav-dropdown"><a class:active={['board/npc', 'board/world', 'board/continents', 'board/system', 'board/bgm'].includes(currentRoute)} href="#board/world" aria-haspopup="true">세계관</a><div class="dropdown-menu" aria-label="세계관 메뉴"><a href="#board/npc"><strong>NPC 게시판</strong><small>NPC 초상화 · 성격 · 관계 · 특징</small></a><a href="#board/world"><strong>세계관 자료실</strong><small>세계관 · 국가 · 역사 · 설정 자료</small></a><a href="#board/continents"><strong>대륙 게시판</strong><small>대륙 · 지형 · 도시 · 주요 장소</small></a><a href="#board/system"><strong>시스템 게시판</strong><small>규칙 · 전투 · 판정 · 캠페인 시스템</small></a><a href="#board/bgm"><strong>BGM 게시판</strong><small>맵 · 캐릭터 · 장면별 배경음악</small></a></div></div><div class="nav-item nav-dropdown"><a class:active={currentRoute === 'board/users' || isMiniGamesPage || isDiceRollerPage} href="#board/users" aria-haspopup="true">유저게시판</a><div class="dropdown-menu" aria-label="유저게시판 메뉴"><a href="#board/users"><strong>유저 게시글</strong><small>질문 · 잡담 · 파티 모집</small></a><a href="#minigames"><strong>미니게임</strong><small>주사위 굴리기 · 간단한 놀이</small></a></div></div><a class:active={isCombatPage} href="#combat">전투</a><a class:active={isShopPage} href="#shop">상점</a>{#if user}<a class:active={isMyPage || isAdminPage || isAdminMypage} href={isAdmin ? '#admin-mypage' : '#mypage'} on:click={openProfile}>마이페이지</a>{/if}</nav>
    <div class="header-actions">{#if user}<button class="login logged-in" on:click={handleLogout}>로그아웃</button>{:else}<button class="login" on:click={() => (showLogin = true)}>로그인</button>{/if}</div>
  </header>

   <main id="home" class:wide-admin={isAdminItemsPage} class="layout">
    {#key currentRoute}
     {#if currentRoute === 'home'}
       <HomePage
         {notices}
         {categories}
         {filteredPosts}
         {pagedFilteredPosts}
         {filteredPageCount}
         bind:activeCategory
         bind:searchTerm
         bind:sortBy
         {currentPage}
         {user}
         {openProfile}
         requestLogin={() => (showLogin = true)}
         {startWriting}
         changePage={(page) => (currentPage = page)}
       />
     {:else if isBoardPage && BoardPage}
       <svelte:component this={BoardPage}
         {currentBoard}
         {boardPagePosts}
         {pagedBoardPosts}
         {boardPageCount}
         {isAdmin}
         bind:sortBy
         bind:searchTerm
         bind:noticeTypeFilter
         bind:sessionPlayerFilter
         {sessionPlayerFilterOptions}
         {currentPage}
         {startWriting}
         changePage={(page) => (currentPage = page)}
       />
      {:else if isMiniGamesPage && MiniGamesPage}
        <svelte:component this={MiniGamesPage} />
      {:else if isDiceRollerPage && DiceRollerPage}
        <svelte:component this={DiceRollerPage} />
      {:else if isPostPage && PostDetailPage}
        <svelte:component this={PostDetailPage}
         {detailLoading}
         {detailError}
         retryDetail={()=>loadPostDetail(currentRoute.slice(5))}
         {detailPost}
         {detailHtml}
         {detailComments}
         bind:commentText
         {detailLiked}
         {detailLikeSaving}
         {commentSaving}
         {user}
         {formatDate}
         {deletePost}
         {toggleLike}
         {addComment}
          {deleteComment}
        />
      {:else if isShopPage && ShopPage}
        <svelte:component this={ShopPage}
          {authReady}
          {user}
          {shopLoading}
          {shopError}
          {shopListings}
          {shopBalance}
          {shopPurchaseQuantities}
          {shopPurchaseSaving}
          {isAdmin}
          {setShopPurchaseQuantity}
          {purchaseShopItem}
          requestLogin={() => (showLogin = true)}
          {getInventoryIcon}
          {isImageIcon}
        />
      {:else if isCombatPage && CombatPage}
        {#key user?.id}
          <svelte:component this={CombatPage} {user} {authReady} {profileLoading} {isAdmin} {currentRoute} requestLogin={() => (showLogin = true)} />
        {/key}
      {:else if isAdminCombatTestPage && AdminCombatTestPage}
        <svelte:component this={AdminCombatTestPage}
          {authReady}
          {profileLoading}
          {isAdmin}
          {currentRoute}
          {adminLoading}
          {adminCharacters}
          selectedCharacterIds={combatTestSelectedCharacterIds}
          {combatTestPlayers}
          {combatTestLoading}
          {combatTestStarted}
          {combatTestTurn}
          {toggleCombatTestCharacter}
          {startCombatTest}
          {nextCombatTestTurn}
          {playCombatTestCard}
          {copyCombatTestCards}
          {copyCombatTestPlayerCards}
          {resetCombatTest}
        />
      {:else if isAdminMonstersPage && AdminMonstersPage}
        <svelte:component this={AdminMonstersPage} {authReady} {profileLoading} {isAdmin} />
      {:else if isAdminItemsPage && AdminItemsPage}
       <svelte:component this={AdminItemsPage}
         {authReady}
         {profileLoading}
         {isAdmin}
         {currentRoute}
         bind:itemForm
         {itemFormImagePreview}
         {itemSaving}
         {catalogItems}
         {filteredCatalogItems}
         {catalogLoading}
         bind:catalogSearchTerm
         {resetItemForm}
         {saveCatalogItem}
         {editCatalogItem}
         {deleteCatalogItem}
         {handleItemFormImageChange}
         {getInventoryIcon}
         {isImageIcon}
       />
     {:else if (isWritePage || isEditPage) && WritePage}
       <svelte:component this={WritePage}
         {isEditPage}
         {writeBoard}
         bind:writeBoardSlug
         {categories}
         {isAdmin}
         {editingPostId}
         bind:postForm
         {npcImagePreview}
         {postSaving}
         {editLoading}
         bind:richEditorElement
         {sessionEntries}
         {sessionParticipants}
         {sessionBgmIds}
         {adminCharacters}
         {npcOptions}
         {bgmOptions}
         {sessionParticipantValue}
         {sessionParticipantName}
         {sessionActorParticipants}
         {sessionParticipantActorValue}
         {setSessionParticipant}
         {addSessionParticipant}
         {removeSessionParticipant}
         {addSessionBgm}
         {setSessionBgm}
         {removeSessionBgm}
         {addSessionEntry}
         {removeSessionEntry}
         {moveSessionEntry}
         {sessionActorValue}
         {setSessionActor}
         {sessionSpeakerValue}
         {setSessionSpeaker}
         {handleSessionImageChange}
         {handleNpcImageChange}
         {handleBgmFileChange}
         {createPost}
       />
      {:else if isAdminMypage && AdminMypage}
        <svelte:component this={AdminMypage} {authReady} {profileLoading} {isAdmin} bind:adminProfileForm {adminProfileSaving} {saveAdminProfile} />
      {:else if isAdminShopPage && AdminShopPage}
        <svelte:component this={AdminShopPage}
          {authReady}
          {profileLoading}
          {isAdmin}
          {currentRoute}
          {adminShopLoading}
          {adminShopListings}
          {catalogItems}
          bind:shopForm
          {shopAdminSaving}
          {resetShopForm}
          {editShopListing}
          {saveShopListing}
          {deleteShopListing}
          {getInventoryIcon}
          {isImageIcon}
        />
      {:else if isMyPage && MyPage}
       <svelte:component this={MyPage} {profile} {character} {characterError} {characterLoading} bind:profileSection bind:characterForm {profileImagePreview} {characterSaving} {extraRecords} bind:extraRecordForm {extraRecordSaving} {relationships} bind:relationshipForm {relationshipSaving} {npcOptions} {inventory} equippedItems={equippedInventory} {cards} {selectedInventoryItem} {equipmentSaving} {user} {isAdmin} {accountForm} {accountSettingsSaving} {handleProfileImageChange} {saveCharacter} {saveExtraRecord} {deleteExtraRecord} {saveRelationship} {deleteRelationship} {selectInventoryItem} {isEquippableItem} {toggleInventoryEquipment} {getInventoryIcon} {isImageIcon} {saveAccountPassword} />
     {:else if isAdminCharacterPage && AdminCharacterPage}
       <svelte:component this={AdminCharacterPage} {authReady} {profileLoading} {adminDetailLoading} {isAdmin} {adminSelectedCharacter} bind:adminCharacterForm {adminCharacterSaving} {extraRecords} bind:extraRecordForm {extraRecordSaving} {adminInventory} equippedItems={adminEquippedInventory} {equipmentSaving} {adminCards} {catalogItems} {filteredInventoryCatalogItems} bind:inventorySearchTerm {cardGrades} {saveAdminCharacter} {deleteAdminCharacter} {saveExtraRecord} {deleteExtraRecord} {addCatalogItemToInventory} {removeAdminInventory} {isEquippableItem} {toggleInventoryEquipment} {newAdminCard} {removeAdminCard} {getInventoryIcon} {isImageIcon} />
      {:else if isAdminPage && AdminPage}
        <svelte:component this={AdminPage} {authReady} {profileLoading} {isAdmin} {currentRoute} bind:adminForm {accountSaving} {createPlayerAccount} {adminLoading} {adminCharacters} {selectAdminCharacter} />
      {:else}
        <section class="panel route-loading"><div class="empty-state"><span>◌</span><strong>페이지를 준비하는 중이에요</strong><p>필요한 화면만 빠르게 불러오고 있습니다.</p></div></section>
      {/if}
      {/key}
      {#if isMyPage && profileSection === 'inventory' && selectedInventoryItem && isChestItem(selectedInventoryItem)}
        <section class="chest-open-panel panel" aria-label="상자 열기">
          <div><p class="eyebrow">CHEST REWARD</p><strong>{selectedInventoryItem.item_name}</strong><span>무작위 보상 {selectedInventoryItem.chest_reward_count || 1}개</span></div>
          <button class="primary-btn" type="button" on:click={openInventoryChest} disabled={openingChest || !selectedInventoryItem.chest_reward_item_ids?.length}>{openingChest ? '상자 여는 중…' : '상자 열기'} <span>↗</span></button>
        </section>
      {/if}
    </main>
    {#if openingChest}
      <div class="chest-overlay" role="dialog" aria-modal="true" aria-label="상자 열기 연출">
        <div class:revealed={chestOpeningDone} class="chest-opening-modal">
          <div class="chest-opening-heading"><p class="eyebrow">MYSTERY CHEST</p><h2>{chestOpeningDone ? '보상 획득!' : '상자를 여는 중'}</h2><span>{chestOpeningDone ? '운명의 보상이 도착했습니다.' : '어떤 아이템이 나올까요?'}</span></div>
          {#if chestOpeningDone}
            <div class="chest-reward-list">{#each chestOpeningRewards as reward}<article><span class="chest-reward-icon">{#if isImageIcon(getInventoryIcon(reward))}<img src={getInventoryIcon(reward)} alt="" />{:else}{getInventoryIcon(reward)}{/if}</span><div><strong>{reward.item_name}</strong><small>{reward.grade} · {reward.item_type}</small></div><b>+1</b></article>{/each}</div>
            <button class="primary-btn chest-result-button" type="button" on:click={closeChestOpening}>보상 확인 <span>↗</span></button>
          {:else if chestOpeningReady}
            <div class="roulette-stage"><span class="roulette-pointer">▼</span><div class="roulette-window"><div class="roulette-track" style={rouletteTrackStyle}>{#each chestOpeningTiles as tile}<div class="roulette-tile" aria-hidden="true">{#if isImageIcon(getInventoryIcon(tile))}<img src={getInventoryIcon(tile)} alt="" />{:else}<span>{getInventoryIcon(tile)}</span>{/if}</div>{/each}</div></div></div>
            <div class="chest-opening-status"><span class="status-pulse"></span> 보상 목록을 섞는 중 <b>· · ·</b></div>
          {:else}
            <div class="chest-loading-stage"><span class="chest-loading-orb">▣</span><strong>상자 잠금 해제 중</strong><span>보상 테이블을 불러오고 있습니다</span></div>
            <div class="chest-opening-status"><span class="status-pulse"></span> 보상 목록을 준비하는 중 <b>· · ·</b></div>
          {/if}
        </div>
      </div>
    {/if}
  {#if isAdminCharacterPage && adminSelectedCharacter?.avatar_url}<section class="admin-profile-photo panel"><p class="eyebrow">PLAYER PROFILE PHOTO</p><img src={adminSelectedCharacter.avatar_url} alt={`${adminSelectedCharacter.name} 프로필 사진`} /><strong>{adminSelectedCharacter.name}</strong></section>{/if}
  {#if isMyPage && profileSection === 'inventory'}<section class="inventory-game-panel panel"><div class="section-head"><div><p class="eyebrow">INVENTORY SLOTS</p><h2>인벤토리</h2></div><span class="form-hint">아이콘을 클릭하면 상세 정보가 표시됩니다</span></div>{#if inventory.length}<div class="inventory-game-layout"><div class="inventory-slots">{#each inventory as item}<button class:active={selectedInventoryItem?.id === item.id} class="inventory-slot" type="button" on:click={() => selectInventoryItem(item)}><span class="slot-icon">{#if isImageIcon(getInventoryIcon(item)) }<img src={getInventoryIcon(item)} alt="" />{:else}{getInventoryIcon(item)}{/if}</span><span class="slot-count">{item.quantity}</span></button>{/each}</div>{#if selectedInventoryItem}<article class="inventory-detail"><div class="inventory-detail-icon">{#if isImageIcon(getInventoryIcon(selectedInventoryItem)) }<img src={getInventoryIcon(selectedInventoryItem)} alt="" />{:else}{getInventoryIcon(selectedInventoryItem)}{/if}</div><div><p class="eyebrow">ITEM DETAIL</p><h3>{selectedInventoryItem.item_name}</h3><div class="item-copy-block"><strong>[효과]</strong><p>{selectedInventoryItem.item_effect || '등록된 효과가 없습니다.'}</p></div><div class="item-copy-block"><strong>[설명]</strong><p>{selectedInventoryItem.item_description || '등록된 설명이 없습니다.'}</p></div><div><span class="tag">{selectedInventoryItem.grade}</span><span class="tag">{selectedInventoryItem.item_type}</span><span class="inventory-quantity">× {selectedInventoryItem.quantity}</span></div></div></article>{:else}<div class="inventory-detail empty"><span>아이템을 선택하세요</span></div>{/if}</div>{:else}<div class="repeat-empty">등록된 아이템이 없습니다.</div>{/if}</section>{/if}
  <footer class="footer"><div class="footer-brand"><span class="brand-mark">od</span><span>open door</span></div><span>장기 TRPG 캠페인을 위한 세계관 기록소</span><span>아이콘: Caro Asercion / game-icons.net</span><span>© 2026 OPEN DOOR</span></footer>
</div>

{#if notice}<div class="toast" role="status"><span>✓</span>{notice}</div>{/if}
{#if showLogin && !user}<div class="backdrop" role="presentation" on:click={() => (showLogin = false)}><dialog open class="modal" aria-labelledby="login-title" on:click|stopPropagation><button class="close" on:click={() => (showLogin = false)} aria-label="닫기">×</button><div class="modal-mark">od</div><p class="eyebrow">ADVENTURER ACCESS</p><h2 id="login-title">모험가 계정으로<br />입장하기</h2><p class="modal-intro">관리자에게 발급받은 아이디와 비밀번호로<br />캠페인 기록소에 입장할 수 있습니다.</p><form class="login-form" on:submit|preventDefault={handleLogin}><label>아이디<input bind:value={loginId} type="text" placeholder="adventurer_01" autocomplete="username" /></label><label>비밀번호<input bind:value={loginPassword} type="password" placeholder="••••••••" autocomplete="current-password" /></label><button class="submit" type="submit">입장하기 <span>→</span></button></form><p class="modal-note">계정 발급 및 변경은 캠페인 관리자에게 문의해 주세요.</p></dialog></div>{/if}
