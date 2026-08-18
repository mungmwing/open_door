-- Character combat values are visible to players but editable only by admins.
alter table public.characters add column if not exists money integer not null default 0 check (money >= 0);
alter table public.characters add column if not exists level integer not null default 1 check (level >= 1);
alter table public.characters add column if not exists hp integer not null default 0 check (hp >= 0);
alter table public.characters add column if not exists max_hp integer not null default 0 check (max_hp >= 0);
alter table public.characters add column if not exists mp integer not null default 0 check (mp >= 0);
alter table public.characters add column if not exists max_mp integer not null default 0 check (max_mp >= 0);
alter table public.characters add column if not exists attack integer not null default 0 check (attack >= 0);
alter table public.characters add column if not exists defense integer not null default 0 check (defense >= 0);
alter table public.characters add column if not exists combat_notes text not null default '';
alter table public.characters add column if not exists extra_info text not null default '';

create or replace function public.prevent_player_combat_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() and (
    new.money is distinct from old.money or
    new.level is distinct from old.level or
    new.hp is distinct from old.hp or
    new.max_hp is distinct from old.max_hp or
    new.mp is distinct from old.mp or
    new.max_mp is distinct from old.max_mp or
    new.attack is distinct from old.attack or
    new.defense is distinct from old.defense or
    new.combat_notes is distinct from old.combat_notes
  ) then
    raise exception '전투 정보는 관리자만 수정할 수 있습니다.';
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_player_combat_changes on public.characters;
create trigger prevent_player_combat_changes
before update on public.characters
for each row execute function public.prevent_player_combat_changes();
