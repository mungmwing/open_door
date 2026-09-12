<script>
  export let label;
  export let text;
  let open = false;
</script>

<button class="effect-help-button" type="button" aria-label={`${label} 도움말`} aria-expanded={open} on:click={() => open = !open}>?</button>
{#if open}<span class="effect-help-text" role="note"><strong>{label}</strong> {text}</span>{/if}

<style>
  .effect-help-button { display:inline-flex; align-items:center; justify-content:center; flex:none; width:26px; height:26px; padding:0; border:1px solid #66758b; border-radius:50%; background:#192638; color:#ead6a0; font:600 14px/1 sans-serif; cursor:pointer; }
  .effect-help-button[aria-expanded="true"] { background:#384538; border-color:#d8bd75; }
  .effect-help-button:focus-visible { outline:2px solid #d8bd75; outline-offset:3px; }
  .effect-help-text { display:block; flex-basis:100%; padding:10px 12px; border-left:2px solid #c4af79; border-radius:4px; background:#101b29; color:#c7d1df; font-size:13px; font-weight:400; line-height:1.7; overflow-wrap:anywhere; }
  .effect-help-text strong { color:#e9d8af; font-size:inherit; }
</style>
