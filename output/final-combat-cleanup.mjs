import {readFile,writeFile} from 'node:fs/promises';
let combat=await readFile('src/pages/CombatPage.svelte','utf8');
combat=combat.replaceAll('<BattleConsumables player={me} {players} {enemies}', '<BattleConsumables player={me} players={allies} {enemies}');
combat=combat.replace('.battle-target-hint small{display:block;color:#a8b3c5;font-size:13px;margin-top:5px}','');
combat=combat.replace('.battle-card-description{font-size:14px;color:#bdc8d6;white-space:pre-wrap;overflow-wrap:anywhere}','');
await writeFile('src/pages/CombatPage.svelte',combat);
let monsters=await readFile('src/pages/AdminMonstersPage.svelte','utf8');monsters=monsters.replace('.monster-page input,.monster-page select,.monster-page textarea','.monster-page input,.monster-page textarea');await writeFile('src/pages/AdminMonstersPage.svelte',monsters);
let css=await readFile('src/app.css','utf8');css+='\n/* Safe readable fallback for malformed Markdown. */\n.post-plain-text { white-space:pre-wrap; overflow-wrap:anywhere; }\n.post-render-note { padding:12px; border:1px solid #8c7854; border-radius:8px; color:#e0c98f; }\n';await writeFile('src/app.css',css);
