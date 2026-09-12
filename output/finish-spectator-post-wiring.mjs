import {readFile,writeFile} from 'node:fs/promises';
let app=await readFile('src/App.svelte','utf8');
const start=app.indexOf('  async function loadPostDetail(id) {');const end=app.indexOf('  async function loadEngagement(postId) {',start);
if(start<0||end<0)throw new Error('Missing post loader');
app=app.slice(0,start)+`  async function loadPostDetail(id) {
    detailController?.abort();
    const requestId=++detailRequestId;
    const controller=new AbortController();detailController=controller;
    const current=()=>requestId===detailRequestId && currentRoute===\`post/\${id}\`;
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

`+app.slice(end);
app=app.replace("    currentRoute = nextRoute;", "    detailController?.abort();detailRequestId++;detailError='';detailLoading=false;\n    currentRoute = nextRoute;");
app=app.replace('async function hydratePostAvatars(postList)', 'async function hydratePostAvatars(postList,signal)');
app=app.replace('async function hydrateSessionAccentColors(post)', 'async function hydrateSessionAccentColors(post,signal)');
// Cancellation for auxiliary reads too; undefined signals are valid fetch options.
const a=app.indexOf('  async function hydratePostAvatars('),b=app.indexOf('  async function startEditing(',a);
let hydration=app.slice(a,b).replaceAll(".in('id', ids)",".in('id', ids).abortSignal(signal)").replaceAll(".in('owner_id', ids)",".in('owner_id', ids).abortSignal(signal)").replaceAll(".in('id', characterIds)",".in('id', characterIds).abortSignal(signal)").replaceAll(".in('id', ownerIds)",".in('id', ownerIds).abortSignal(signal)");
app=app.slice(0,a)+hydration+app.slice(b);
app=app.replace('      detailComments = rows.map', "      if(currentRoute!==\`post/\${postId}\` || detailPost?.id!==postId)return;\n      detailComments = rows.map");
app=app.replace('    if (!likeResult.error) detailLiked', "    if(currentRoute!==\`post/\${postId}\` || detailPost?.id!==postId)return;\n    if (!likeResult.error) detailLiked");
app=app.replace('         {detailLoading}\n','         {detailLoading}\n         {detailError}\n         retryDetail={()=>loadPostDetail(currentRoute.slice(5))}\n');
// CRLF sources may not match the LF-only prop anchor.
if(!app.includes('retryDetail={()=>loadPostDetail'))app=app.replace('         {detailLoading}\r\n','         {detailLoading}\r\n         {detailError}\r\n         retryDetail={()=>loadPostDetail(currentRoute.slice(5))}\r\n');
await writeFile('src/App.svelte',app);
let combat=await readFile('src/pages/CombatPage.svelte','utf8');
combat=combat.replaceAll('{#each players as player (player.id)}','{#each displayPlayers as player, playerIndex (player.id)}');
combat=combat.replace('<strong>{player.name} {player.owner_id', '<strong>플레이어 {playerIndex+1} · {player.name} {player.owner_id');
combat=combat.replace('<strong>{player.name}{player.owner_id', '<strong>플레이어 {playerIndex+1} · {player.name}{player.owner_id');
combat=combat.replace("      {#if user}<button class=\"subtle-btn\"", "      {#if spectating}<span class=\"battle-tag\">관전 중</span><button class=\"subtle-btn\" disabled={busy} on:click={()=>watchRoom(room,false)}>관전 나가기</button>{/if}\n      {#if user}<button class=\"subtle-btn\"");
combat=combat.replace('{#if isAdmin && item.created_by === user.id && isCompletedRoom(item)}','{#if !item.is_member && item.created_by!==user.id}<button class="primary-btn" disabled={busy} on:click={()=>watchRoom(item)}>관전하기</button>{/if}\n              {#if isAdmin && item.created_by === user.id && isCompletedRoom(item)}');
combat=combat.replace("        {#if invitation?.status === 'waiting'}", "        {#if invitation}<button class=\"subtle-btn\" disabled={busy} on:click={()=>watchRoom(invitation)}>관전하기</button>{/if}\n        {#if invitation?.status === 'waiting'}");
combat=combat.replace('방장으로 전투를 관전하고 있습니다.',"{host ? '방장으로 전투를 관전하고 있습니다.' : '전투를 관전하고 있습니다. 전투 행동은 참가자만 할 수 있습니다.'}");
combat=combat.replace("{ROOM_STATUS[room.status]} · {players.length}/6명", "{ROOM_STATUS[room.status]} · {players.length}/6명");
await writeFile('src/pages/CombatPage.svelte',combat);
