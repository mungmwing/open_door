-- Apply this migration after the original TRPG content migration.
-- These columns are used by the NPC profile form and inline image storage.
alter table public.posts add column if not exists image_url text;
alter table public.posts add column if not exists npc_name text;
alter table public.posts add column if not exists npc_age integer;
alter table public.posts add column if not exists npc_gender text;
alter table public.posts add column if not exists npc_height numeric(6,2);
alter table public.posts add column if not exists npc_race text;
alter table public.posts add column if not exists npc_role text;
alter table public.posts add column if not exists npc_traits text;
alter table public.posts add column if not exists npc_affiliation text;
alter table public.posts add column if not exists npc_personality text;

alter table public.character_cards add column if not exists energy integer not null default 0 check (energy >= 0);

-- Players may view their inventory and cards, but only administrators can change them.
drop policy if exists "inventory follows character access" on public.inventory_items;
drop policy if exists "inventory is visible to owner and admins" on public.inventory_items;
create policy "inventory is visible to owner and admins" on public.inventory_items for select to authenticated
using (exists (select 1 from public.characters c where c.id = character_id and (c.owner_id = auth.uid() or public.is_admin())));
drop policy if exists "admins manage inventory" on public.inventory_items;
create policy "admins manage inventory" on public.inventory_items for all to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists "cards follow character access" on public.character_cards;
drop policy if exists "cards are visible to owner and admins" on public.character_cards;
create policy "cards are visible to owner and admins" on public.character_cards for select to authenticated
using (exists (select 1 from public.characters c where c.id = character_id and (c.owner_id = auth.uid() or public.is_admin())));
drop policy if exists "admins manage cards" on public.character_cards;
create policy "admins manage cards" on public.character_cards for all to authenticated
using (public.is_admin()) with check (public.is_admin());
