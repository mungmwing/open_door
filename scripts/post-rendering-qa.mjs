import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {marked} from 'marked';
import {renderSafePostMarkdown} from '../src/lib/postRendering.js';
let passed=0;const test=(name,fn)=>{fn();passed++;console.log('PASS '+name)};
test('일반 Markdown 제목·링크·한 줄 개행 보존',()=>{
  const md='# 제목\n\n첫 줄\n다음 줄\n\n[링크](https://example.test)';assert.equal(renderSafePostMarkdown(md,s=>s),marked.parse(md,{breaks:true}));
});
test('3MB 이미지 3개는 작은 토큰으로 파싱하고 원래 URL 복구',()=>{
  const url='data:image/png;base64,'+'A'.repeat(3_425_000);const input=`# 이미지\n\n![하나](${url})\n\n![둘](${url})\n\n![셋](${url})`;
  let sanitized=false;const html=renderSafePostMarkdown(input,s=>{sanitized=true;return s},(md,opts)=>{assert.ok(md.length<400);return marked.parse(md,opts)});
  assert.equal((html.match(/data:image\/png;base64,/g)||[]).length,3);assert.ok(html.includes('alt="셋"'));assert.ok(sanitized);assert.ok(!html.includes('open-door.invalid'));
});
test('코드 블록의 이미지 문자열·예약 토큰 충돌에도 내용 보존',()=>{
  const image='data:image/jpeg;base64,AAAA';const input='https://open-door.invalid/__embedded_image_0/0__\n\n```text\n'+image+'\n```';
  const html=renderSafePostMarkdown(input,s=>s);assert.equal(html,marked.parse(input,{breaks:true}));assert.ok(html.includes(image));assert.ok(html.includes('<code class="language-text">'));
});
test('파서 실패 시 HTML을 이스케이프한 원문 표시 후 소독',()=>{
  let sanitized=false;const html=renderSafePostMarkdown('<img src=x onerror=alert(1)> & text',s=>{sanitized=true;return s},()=>{throw new RangeError('stack')});
  assert.ok(html.includes('&lt;img'));assert.ok(!html.includes('<img'));assert.ok(html.includes('&amp;'));assert.ok(html.includes('원문으로 표시'));assert.ok(sanitized);
});
test('복구한 이미지와 일반 HTML을 모두 최종 소독기로 전달',()=>{
  const html=renderSafePostMarkdown('![사진](data:image/png;base64,AAAA)\n\n<script>bad()</script>',s=>{assert.ok(s.includes('data:image/png;base64,AAAA'));assert.ok(s.includes('<script>'));return 'sanitized';});assert.equal(html,'sanitized');
});
try {
  const post=JSON.parse(await readFile('output/post-loading-fixture.json','utf8'));
  test('문제 게시물 실제 본문의 이미지 3개와 원문 보존',()=>{
    // App.formatPost removes its legacy NPC metadata before rendering the body.
    const content=post.content.replace(/^<!--OPEN_DOOR_NPC:[A-Za-z0-9+/=]+-->/,'');
    const html=renderSafePostMarkdown(content,s=>s,(md,opts)=>{assert.ok(md.length<10000);return marked.parse(md,opts)});assert.equal((html.match(/<img /g)||[]).length,3);assert.ok(html.length>9_000_000);assert.ok(!html.includes('원문으로 표시'));
  });
}catch(e){if(e.code!=='ENOENT')throw e;}
console.log(`\n${passed} post rendering checks passed.`);
