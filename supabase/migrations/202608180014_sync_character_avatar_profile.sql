-- Backfill existing player profiles and keep their public post avatar in sync.
-- Administrator profile photos remain managed directly from profiles.avatar_url.
update public.profiles as p
set avatar_url = c.avatar_url
from public.characters as c
where c.owner_id = p.id
  and coalesce(p.role, '') <> 'admin'
  and c.avatar_url is not null
  and c.avatar_url <> ''
  and p.avatar_url is distinct from c.avatar_url;

create or replace function public.sync_character_avatar_to_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
  set avatar_url = new.avatar_url
  where id = new.owner_id
    and coalesce(role, '') <> 'admin';
  return new;
end;
$$;

drop trigger if exists characters_sync_profile_avatar on public.characters;
create trigger characters_sync_profile_avatar
after insert or update of avatar_url on public.characters
for each row
execute function public.sync_character_avatar_to_profile();
