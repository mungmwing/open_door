<script>
  export let authReady = false;
  export let profileLoading = false;
  export let isAdmin = false;
  export let adminProfileForm = {};
  export let adminProfileSaving = false;
  export let saveAdminProfile = () => {};
</script>

{#if !authReady || profileLoading}<section class="admin-mypage panel"><div class="empty-state"><span>◌</span><strong>관리자 정보를 불러오는 중이에요</strong></div></section>
{:else if !isAdmin}<section class="about-page panel"><p class="eyebrow">ACCESS RESTRICTED</p><h1>관리자 권한이<br /><em>필요합니다</em></h1><p class="about-lead">이 페이지는 관리자 계정만 이용할 수 있습니다.</p><a class="primary-btn about-button" href="#home">홈으로 돌아가기 <span>→</span></a></section>
{:else}<section class="admin-mypage panel"><div class="page-heading"><p class="eyebrow">ADMIN ACCOUNT</p><h1>관리자 마이페이지</h1><p>관리자 표시명과 로그인 비밀번호를 변경할 수 있습니다.</p></div><form class="editor-form admin-profile-form" on:submit|preventDefault={saveAdminProfile}><label>표시명<input bind:value={adminProfileForm.nickname} maxlength="40" placeholder="표시명" /></label><label>새 비밀번호<input bind:value={adminProfileForm.newPassword} type="password" minlength="8" autocomplete="new-password" placeholder="변경할 때만 입력" /></label><label>새 비밀번호 확인<input bind:value={adminProfileForm.confirmPassword} type="password" minlength="8" autocomplete="new-password" placeholder="새 비밀번호를 다시 입력" /></label><div class="form-actions"><button class="primary-btn" type="submit" disabled={adminProfileSaving}>{adminProfileSaving ? '저장 중…' : '계정 정보 저장'} <span>↗</span></button></div></form><div class="admin-mypage-links"><a class="text-link" href="#admin">관리자 페이지로 이동 <span>→</span></a></div></section>{/if}
