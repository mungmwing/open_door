import {readFile,writeFile,readdir} from 'node:fs/promises';
let app=await readFile('src/App.svelte','utf8');
app=app.replace("  let AdminItemsPage;", "  let AdminItemsPage;\n  let AdminMonstersPage;");
app=app.replace("  import { formatCombatTestCards }", "  import { prepareRelicSave } from './lib/combatExpansion';\n  import { formatCombatTestCards }");
app=app.replaceAll('combat_effects:null }','combat_effects:null, relic_effects:null }');
app=app.replace('combat_effects:item.combat_effects ?? null }','combat_effects:item.combat_effects ?? null, relic_effects:item.relic_effects ?? null }');
app=app.replace("  $: isAdminItemsPage =", "  $: isAdminMonstersPage = currentRoute === 'admin/monsters';\n  $: isAdminItemsPage =");
app=app.replace('isAdminShellPage = isAdminPage ||','isAdminShellPage = isAdminMonstersPage || isAdminPage ||');
app=app.replace("    if (route === 'admin/items')", "    if (route === 'admin/monsters') return loadRouteComponent('admin-monsters', () => import('./pages/AdminMonstersPage.svelte'), (component) => (AdminMonstersPage = component));\n    if (route === 'admin/items')");
app=app.replace('(isAdminItemsPage && AdminItemsPage)','(isAdminItemsPage && AdminItemsPage) || (isAdminMonstersPage && AdminMonstersPage)');
app=app.replace('      {:else if isAdminItemsPage && AdminItemsPage}', '      {:else if isAdminMonstersPage && AdminMonstersPage}\n        <svelte:component this={AdminMonstersPage} {authReady} {profileLoading} {isAdmin} />\n      {:else if isAdminItemsPage && AdminItemsPage}');
app=app.replace('    let hasItemCombatSchema;', "    const relicRule = itemForm.item_type === '유물' ? itemForm.relic_effects : null;\n    let hasRelicSchema;\n    try { hasRelicSchema = await prepareRelicSave(supabase,relicRule); }\n    catch(problem) { return showNotice(problem.message || '유물 효과를 확인하지 못했습니다.'); }\n    let hasItemCombatSchema;");
app=app.replace('...(hasItemCombatSchema ? {combat_effects:itemRule} : {})','...(hasItemCombatSchema ? {combat_effects:itemRule} : {}), ...(hasRelicSchema ? {relic_effects:relicRule} : {})');
await writeFile('src/App.svelte',app);
for(const name of await readdir('src/pages')){
  if(!name.endsWith('.svelte'))continue;
  let code=await readFile('src/pages/'+name,'utf8');
  const needle='<a class:active={currentRoute === \'admin/items\'}';
  if(code.includes(needle))code=code.replace(needle, '<a href="#admin/monsters"><span>♟</span><span><strong>몬스터 관리</strong><small>MONSTER CATALOG</small></span></a>'+needle);
  if(name==='AdminItemsPage.svelte'){
    code=code.replace("  import CardEffectEditor", "  import RelicEffectEditor from '../components/RelicEffectEditor.svelte';\n  import CardEffectEditor");
    code=code.replace('<div class="form-actions">{#if itemForm.id}', '{#if itemForm.item_type === \'유물\'}<RelicEffectEditor disabled={itemSaving} value={itemForm.relic_effects} onChange={effects=>itemForm.relic_effects=effects} />{/if}\n              <div class="form-actions">{#if itemForm.id}');
  }
  await writeFile('src/pages/'+name,code);
}
