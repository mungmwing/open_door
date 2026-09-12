import {loadEnv} from 'vite';
import {writeFile} from 'node:fs/promises';
import {marked} from 'marked';
const env=loadEnv('development',process.cwd(),'VITE_');
const url=new URL('/rest/v1/posts_public',env.VITE_SUPABASE_URL);
url.searchParams.set('select','id,board_slug,content');url.searchParams.set('id','eq.b352d7d4-882b-4119-80a4-98f72a043c25');
const response=await fetch(url,{headers:{apikey:env.VITE_SUPABASE_PUBLISHABLE_KEY},signal:AbortSignal.timeout(15000)});
if(!response.ok)throw new Error('Read-only post request: '+response.status);
const [post]=await response.json();if(!post)throw new Error('Public post unavailable');
await writeFile('output/post-loading-fixture.json',JSON.stringify(post));
const text=post.content||'';const images=[...text.matchAll(/data:image\/[^;]+;base64,([A-Za-z0-9+/=]+)/g)];
console.log({board:post.board_slug,length:text.length,longestLine:text.split('\n').reduce((max,line)=>Math.max(max,line.length),0),embeddedImages:images.length,imageLengths:images.map(m=>m[0].length)});
try{marked.parse(text,{breaks:true});console.log('raw markdown parse succeeded')}catch(e){console.log('raw parse error: '+e.message)}
const short=text.replace(/data:image\/[^;]+;base64,[A-Za-z0-9+/=]+/g,'https://example.test/image.png');
try{marked.parse(short,{breaks:true});console.log('replacing embedded image data resolves parse')}catch(e){console.log('short parse error: '+e.message)}
