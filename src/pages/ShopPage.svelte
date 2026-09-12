<script>
  export let authReady = false;
  export let user = null;
  export let shopLoading = false;
  export let shopError = '';
  export let shopListings = [];
  export let shopBalance = null;
  export let shopPurchaseQuantities = {};
  export let shopPurchaseSaving = false;
  export let isAdmin = false;
  export let setShopPurchaseQuantity = () => {};
  export let purchaseShopItem = () => {};
  export let requestLogin = () => {};
  export let getInventoryIcon = () => '◆';
  export let isImageIcon = () => false;

  let selectedShopItem = null;

  function isSoldOut(listing) {
    return listing.total_limit !== null && listing.sold_count >= listing.total_limit;
  }

  function stockLabel(listing) {
    if (listing.total_limit === null) return '재고 제한 없음';
    return `${Math.max(0, listing.total_limit - listing.sold_count)}개 남음`;
  }

  function personalStockLabel(listing) {
    if (listing.personal_limit === null) return '개인 제한 없음';
    return `개인 ${listing.personal_purchased || 0}/${listing.personal_limit}`;
  }

  function isPersonalLimitReached(listing) {
    return listing.personal_limit !== null && (listing.personal_purchased || 0) >= listing.personal_limit;
  }

  function purchaseMax(listing) {
    const limits = [];
    if (listing.total_limit !== null) limits.push(Math.max(0, listing.total_limit - listing.sold_count));
    if (listing.personal_limit !== null) limits.push(Math.max(0, listing.personal_limit - (listing.personal_purchased || 0)));
    return limits.length ? Math.max(1, Math.min(...limits)) : undefined;
  }

  function openShopItem(listing) {
    selectedShopItem = listing;
  }

  function closeShopItem() {
    selectedShopItem = null;
  }
</script>

<section class="shop-page panel">
  <div class="shop-hero"><div><p class="eyebrow">OPEN DOOR MERCHANTS</p><h1>모험가 상점</h1><p>캠페인에 필요한 아이템을 G로 교환하세요.<br />판매 중인 상품은 인벤토리로 바로 지급됩니다.</p></div><div class="shop-wallet"><span>MY WALLET</span><strong>{shopBalance === null ? '—' : `${shopBalance.toLocaleString()} G`}</strong><small>{user ? '현재 캐릭터 보유 G' : '로그인 후 잔액 확인'}</small></div></div>
  {#if !authReady}<div class="empty-state shop-state"><span>◌</span><strong>상점을 준비하는 중이에요</strong></div>
  {:else if !user}<div class="shop-login-state"><span class="shop-state-mark">G</span><h2>회원 전용 상점</h2><p>상품을 둘러보고 구매하려면 먼저 로그인해 주세요.</p><button class="primary-btn" type="button" on:click={requestLogin}>로그인하고 입장 <span>→</span></button></div>
  {:else if shopLoading}<div class="empty-state shop-state"><span>◌</span><strong>상품을 불러오는 중이에요</strong></div>
  {:else if shopError}<div class="error-box shop-error">{shopError}</div>
  {:else if !shopListings.length}<div class="shop-empty"><span>◇</span><h2>아직 진열된 상품이 없습니다</h2><p>관리자가 새로운 상품을 준비하고 있습니다.</p></div>
  {:else}
    <div class="shop-toolbar"><div><p class="eyebrow">TODAY'S STOCK</p><strong>진열 상품 <b>{shopListings.length}</b></strong></div><span>G로 구매한 아이템은 인벤토리로 바로 지급됩니다.</span></div>
    <div class="shop-grid">
      {#each shopListings as listing}
        <article class:shop-sold-out={isSoldOut(listing)} class:shop-not-selling={!listing.is_active} class="shop-card">
          <button class="shop-card-open" type="button" aria-label={`${listing.item_name} 상세 보기`} on:click={() => openShopItem(listing)}>
            <div class="shop-card-icon">{#if isImageIcon(getInventoryIcon(listing.item))}<img loading="lazy" decoding="async" src={getInventoryIcon(listing.item)} alt="" />{:else}<span>{getInventoryIcon(listing.item)}</span>{/if}</div>
            <div class="shop-card-copy">
              <div class="shop-card-grade">
                <span class="tag">{listing.grade}</span>
                <span class="shop-item-badge">{#if isSoldOut(listing)}SOLD OUT{:else if !listing.is_active}판매 준비중{:else}{listing.item_type || '기타'}{/if}</span>
                <span class="shop-stock-label">{stockLabel(listing)}</span>
                <span class="shop-personal-stock-label">{personalStockLabel(listing)}</span>
              </div>
              <h2>{listing.item_name}</h2>
              <small class="shop-card-detail-hint">아이템을 눌러 상세 확인</small>
            </div>
          </button>
          <div class="shop-card-footer">
            <div class="shop-price"><span>PRICE</span><strong>{listing.price_g.toLocaleString()} G</strong></div>
            {#if listing.personal_limit !== null}<small class="shop-personal-limit">개인 {listing.personal_purchased || 0}/{listing.personal_limit}</small>{/if}
            {#if listing.is_active && !isSoldOut(listing) && !isPersonalLimitReached(listing)}
              <div class="shop-buy-row"><input type="number" min="1" max={purchaseMax(listing)} value={shopPurchaseQuantities[listing.id] || 1} on:input={(event) => setShopPurchaseQuantity(listing.id, event.currentTarget.value)} aria-label={`${listing.item_name} 구매 수량`} /><button class="primary-btn" type="button" on:click={() => purchaseShopItem(listing.id, Number(shopPurchaseQuantities[listing.id] || 1))} disabled={shopPurchaseSaving}>구매하기 <span>↗</span></button></div>
            {:else}
              <div class="shop-unavailable">{isSoldOut(listing) ? '모든 수량이 판매되었습니다' : isPersonalLimitReached(listing) ? '개인 구매 한도에 도달했습니다' : '현재 판매하지 않는 상품입니다'}</div>
            {/if}
          </div>
        </article>
      {/each}
    </div>
  {/if}
  {#if isAdmin && user}<div class="shop-admin-link"><a class="subtle-btn" href="#admin/shop">상점 상품 관리 ↗</a></div>{/if}
</section>

{#if selectedShopItem}
  <div class="shop-detail-overlay">
    <div class="shop-detail-modal" role="dialog" aria-modal="true" aria-labelledby="shop-item-detail-title">
      <button class="shop-detail-close" type="button" aria-label="아이템 상세 닫기" on:click={closeShopItem}>×</button>
      <div class="shop-detail-icon">{#if isImageIcon(getInventoryIcon(selectedShopItem.item))}<img decoding="async" src={getInventoryIcon(selectedShopItem.item)} alt="" />{:else}<span>{getInventoryIcon(selectedShopItem.item)}</span>{/if}</div>
      <div class="shop-detail-copy"><p class="eyebrow">ITEM DETAIL</p><h2 id="shop-item-detail-title">{selectedShopItem.item_name}</h2><div><span class="tag">{selectedShopItem.grade}</span><span class="tag">{selectedShopItem.item_type}</span></div><div class="item-copy-block"><strong>[효과]</strong><p>{selectedShopItem.item_effect || '등록된 효과가 없습니다.'}</p></div><div class="item-copy-block"><strong>[설명]</strong><p>{selectedShopItem.item_description || '등록된 설명이 없습니다.'}</p></div></div>
    </div>
  </div>
{/if}
