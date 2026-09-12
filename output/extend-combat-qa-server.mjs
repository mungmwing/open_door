import {readFile,writeFile} from 'node:fs/promises';
let code=await readFile('scripts/combat-qa-server.mjs','utf8');
function replace(old,next){if(!code.includes(old))throw new Error('missing '+old);code=code.replace(old,()=>next);}
replace("await db.exec(await readFile('supabase/queries/add_combat_consumables_energy.sql','utf8'));", "await db.exec(await readFile('supabase/queries/add_combat_consumables_energy.sql','utf8'));\nawait db.exec(await readFile('supabase/queries/add_combat_monsters_relics.sql','utf8'));\nawait db.exec('grant insert,delete on items to authenticated');");
replace("const dir = resolve('output/combat-qa/ui');", `await db.exec(\`insert into combat_monsters(id,name,hp,attack,guard,powers,actions) values('00000000-0000-0000-0000-000000000080','수호 늑대',30,5,3,'[{"kind":"thorns","amount":2,"target":"self"}]','[{"name":"물기","effects":[{"kind":"damage","amount":5,"target":"enemy"}]}]');
insert into items(id,name,item_type) values('00000000-0000-0000-0000-000000000081','전투 유물','유물');
insert into inventory_items(character_id,item_id,item_name,quantity,item_type,is_equipped) values('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000081','전투 유물',1,'유물',true);\`);
const dir = resolve('output/combat-qa/expansion-ui');`);
code=code.replaceAll('/output/combat-qa/ui/','/output/combat-qa/expansion-ui/').replaceAll('localhost:5181','localhost:5182').replace('port:5181','port:5182');
replace("import { onMount } from 'svelte'; import CombatPage", "import { onMount } from 'svelte'; import AdminMonstersPage from '/src/pages/AdminMonstersPage.svelte'; import CombatPage");
replace('<a href="#cards">카드 설정 QA</a>', '<a href="#admin/monsters">몬스터 관리 QA</a> · <a href="#cards">카드 설정 QA</a>');
replace("{#if route==='items' && name==='admin'}", "{#if route==='admin/monsters' && name==='admin'}<AdminMonstersPage authReady={true} isAdmin={true} />{:else if route==='items' && name==='admin'}");
const adapterStart=code.indexOf("await writeFile(resolve(dir,'adapter.js')");
const adapterEnd=code.indexOf('let queue=Promise.resolve();',adapterStart);
code=code.slice(0,adapterStart)+`await writeFile(resolve(dir,'adapter.js'), \`const user=new URLSearchParams(location.search).get('user')||'admin';
async function api(body){try{return await (await fetch('/__combat_qa',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({...body,user})})).json()}catch(e){return {data:null,error:{message:e.message}}}}
function from(table){const args={table,operation:'select',filters:[]};const builder={select(columns='*'){args.columns=columns;return this},eq(key,value){args.filters.push([key,value]);return this},order(key){args.order=key;return this},limit(n){args.limit=n;return this},single(){args.single=true;return this},maybeSingle(){args.single=true;return this},insert(data){args.operation='insert';args.data=data;return this},update(data){args.operation='update';args.data=data;return this},delete(){args.operation='delete';return this},then(ok,bad){return api({name:'qa_table',args}).then(ok,bad)}};return builder;}
export const supabase={rpc:(name,args)=>api({name,args}),from,channel:()=>({on(){return this},subscribe(cb){cb('CHANNEL_ERROR');return this}}),removeChannel:async()=>{}};\`);
`+code.slice(adapterEnd);
replace("if(source==='../supabaseClient'&&importer?.replaceAll('\\\\','/').endsWith('/src/pages/CombatPage.svelte'))", "if(source==='../supabaseClient')");
replace("        let data;if(name==='room')", `        let data;
        if(name==='qa_table') {
          if(!['combat_rooms','combat_monsters','items','characters','character_cards'].includes(args.table))throw new Error('Unknown QA table');
          const params=[];const quote=key=>{if(!/^[a-z_]+$/.test(key))throw new Error('Invalid column');return '"'+key+'"'};
          const filter=()=>args.filters.length?' where '+args.filters.map(([key,value])=>{params.push(value);return quote(key)+'=$'+params.length}).join(' and '):'';
          let query;
          if(args.operation==='select')query='select * from '+args.table+filter()+(args.order?' order by '+quote(args.order):'')+(args.limit===0?' limit 0':'');
          else if(!['items','combat_monsters'].includes(args.table)||user!=='admin')throw new Error('Admin QA catalog only');
          else if(args.operation==='delete')query='delete from '+args.table+filter()+' returning *';
          else {
            const entries=Object.entries(args.data);const keys=entries.map(([key])=>quote(key));for(const [key,value] of entries)params.push(['powers','actions','combat_effects','relic_effects'].includes(key)&&value!=null?JSON.stringify(value):value);
            if(args.operation==='insert')query='insert into '+args.table+'('+keys.join(',')+') values('+params.map((_,i)=>'$'+(i+1)).join(',')+') returning *';
            else query='update '+args.table+' set '+keys.map((key,i)=>key+'=$'+(i+1)).join(',')+filter()+' returning *';
          }
          const rows=(await db.query(query,params)).rows;data=args.single?rows[0]||null:rows;
        }
        else if(name==='room')`);
replace("'update items set name=$2,combat_effects=$3 where id=$1 returning *',[args.item.id,args.item.name,JSON.stringify(args.item.combat_effects)]", "'update items set name=$2,combat_effects=$3,relic_effects=$4,item_type=$5 where id=$1 returning *',[args.item.id,args.item.name,JSON.stringify(args.item.combat_effects ?? null),JSON.stringify(args.item.relic_effects ?? null),args.item.item_type]");
await writeFile('scripts/combat-expansion-qa-server.mjs',code);
