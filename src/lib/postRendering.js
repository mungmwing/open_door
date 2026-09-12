import { marked } from 'marked';

const escapeHtml = text => text.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

// Marked's block regexes can overflow the browser stack on multi-megabyte
// embedded image URLs. Parse short opaque URLs, then restore before sanitizing.
// Only the image data payload is replaced; Markdown structure stays intact.
export function renderSafePostMarkdown(content='',sanitize,parse=marked.parse) {
  const markdown=String(content ?? '');
  let suffix=0;
  while(markdown.includes(`https://open-door.invalid/__embedded_image_${suffix}/`)) suffix++;
  const prefix=`https://open-door.invalid/__embedded_image_${suffix}/`;
  const images=[];
  const compact=markdown.replace(/data:image\/(?:png|jpeg|jpg|gif|webp|avif|bmp);base64,[A-Za-z0-9+/=]+/gi,url=>{
    const index=images.push(url)-1;
    return `${prefix}${index}__`;
  });
  let html;
  try { html=parse(compact,{breaks:true,async:false}); }
  catch {
    // Malformed/very deeply nested Markdown must never leave the page loading.
    html='<p class="post-render-note" role="note">일부 서식을 해석하지 못해 원문으로 표시합니다.</p><div class="post-plain-text">'+escapeHtml(compact)+'</div>';
  }
  const marker=new RegExp(`https://open-door\\.invalid/__embedded_image_${suffix}/(\\d+)__`,'g');
  return sanitize(html.replace(marker,(token,index)=>images[Number(index)] ?? token));
}
