<script>
  export let detailLoading = false;
  export let detailError = '';
  export let retryDetail = () => {};
  export let detailPost = null;
  export let detailHtml = '';
  export let detailComments = [];
  export let commentText = '';
  export let detailLiked = false;
  export let detailLikeSaving = false;
  export let commentSaving = false;
  export let user = null;
  export let formatDate = (value) => ({ date: value || '', time: '' });
  export let deletePost = () => {};
  export let toggleLike = () => {};
  export let addComment = () => {};
  export let deleteComment = () => {};

  function getDetailBadge(post) {
    if (post?.boardSlug !== 'notices') return post?.category || '';
    return { notice: '공지', patch: '패치', event: '이벤트' }[post.postType] || '공지';
  }
</script>

<section class="detail-page panel">
  {#if detailLoading}<div class="empty-state"><span>◌</span><strong>게시글을 불러오는 중이에요</strong></div>
  {:else if detailError}<div class="empty-state" role="alert"><span>!</span><strong>{detailError}</strong><button class="primary-btn" type="button" on:click={retryDetail}>다시 불러오기</button><a class="text-link" href="#home">홈으로 돌아가기 →</a></div>
  {:else if detailPost}
    <a class="back-link" href={`#board/${detailPost.boardSlug}`}>← {detailPost.category}로 돌아가기</a>
    <div class="detail-meta"><span class="badge gold">{getDetailBadge(detailPost)}</span><span>{detailPost.date} · {detailPost.time}</span><span>조회 {detailPost.views}</span></div>
    <h1>{detailPost.title}</h1>
    <div class="detail-author">{#if detailPost.avatarUrl}<img class="avatar avatar-image" loading="lazy" decoding="async" width="38" height="38" src={detailPost.avatarUrl} alt={`${detailPost.author} 프로필 사진`} />{:else}<span class={`avatar ${detailPost.color}`}>{detailPost.avatar}</span>{/if}<b>{detailPost.author}</b><span>작성자</span>{#if user?.id === detailPost.authorId}<button class="danger-btn" type="button" on:click={() => deletePost(detailPost)}>게시글 삭제</button>{/if}</div>
    {#if detailPost.boardSlug === 'npc'}<div class="npc-detail-grid">{#if detailPost.imageUrl}<img src={detailPost.imageUrl} alt={`${detailPost.title} 이미지`} />{:else}<div class="npc-detail-placeholder">이미지 없음</div>{/if}<div><dl><dt>이름</dt><dd>{detailPost.npcName || '미등록'}</dd><dt>나이</dt><dd>{detailPost.npcAge || '미등록'}</dd><dt>성별</dt><dd>{detailPost.npcGender || '미등록'}</dd><dt>키</dt><dd>{detailPost.npcHeight ? `${detailPost.npcHeight}cm` : '미등록'}</dd><dt>종족</dt><dd>{detailPost.npcRace || '미등록'}</dd><dt>역할/직업</dt><dd>{detailPost.npcRole || '미등록'}</dd><dt>소속</dt><dd>{detailPost.npcAffiliation || '미등록'}</dd><dt>성격</dt><dd>{detailPost.npcPersonality || '미등록'}</dd><dt>특징</dt><dd>{detailPost.npcTraits || '미등록'}</dd></dl></div></div>{/if}
    <div class="detail-body">{@html detailHtml}</div>
    {#if detailPost.youtubeUrl}<div class="youtube-embed"><iframe src={detailPost.youtubeUrl} title="YouTube 영상" allowfullscreen></iframe></div>{/if}
    <div class="detail-actions"><button class:liked={detailLiked} class="like-button" type="button" on:click={toggleLike} disabled={detailLikeSaving}>♥ 좋아요 {detailPost.likes}</button><span>댓글 {detailPost.comments}개</span></div>
    <section class="comments-section" aria-labelledby="comments-title"><div class="comments-heading"><h2 id="comments-title">댓글</h2><span>{detailComments.length}개</span></div>{#if detailComments.length}{#each detailComments as comment}<article class="comment-item"><div class="comment-author">{#if comment.avatarUrl}<img class="avatar avatar-image" loading="lazy" decoding="async" width="36" height="36" src={comment.avatarUrl} alt={`${comment.nickname} 프로필 사진`} />{:else}<span class="avatar mint">{comment.nickname.slice(0, 1)}</span>{/if}<strong>{comment.nickname}</strong><time>{formatDate(comment.created_at).date}</time>{#if user?.id === comment.author_id}<button class="comment-action-btn comment-delete-btn" type="button" on:click={() => deleteComment(comment)}>삭제</button>{/if}</div><p>{comment.content}</p></article>{/each}{:else}<div class="comments-empty">아직 댓글이 없습니다. 첫 번째 의견을 남겨 보세요.</div>{/if}<form class="comment-form" on:submit|preventDefault={addComment}><textarea bind:value={commentText} rows="3" placeholder={user ? '이 모험에 대한 생각을 남겨 주세요.' : '로그인 후 댓글을 작성할 수 있어요.'} disabled={!user}></textarea><button class="primary-btn" type="submit" disabled={commentSaving}>{commentSaving ? '등록 중…' : '댓글 등록'} <span>↗</span></button></form></section>
    <div class="detail-footer"><a href={`#write/${detailPost.boardSlug}`}>이 게시판에 글쓰기 <span>↗</span></a><span>모험의 기록을 함께 이어가요</span></div>
  {:else}<div class="empty-state"><span>?</span><strong>게시글을 찾을 수 없어요</strong><a class="text-link" href="#home">홈으로 돌아가기 →</a></div>{/if}
</section>
