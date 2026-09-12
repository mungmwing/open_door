-- 수동 실행 전용. create_realtime_combat.sql 이후 적용합니다.
-- 몬스터·유물 확장과 함께 사용할 때는 확장 SQL 뒤에 이 파일을 적용하세요.
-- 일반 로그인 이용자가 관전 버튼을 눌러 읽기 권한을 얻습니다. 전투 행동 권한은 추가하지 않습니다.
begin;
alter table public.combat_rooms add column if not exists spectator_ids uuid[] not null default '{}';
drop policy if exists combat_room_read on public.combat_rooms;
create policy combat_room_read on public.combat_rooms for select to authenticated
using (created_by=(select auth.uid()) or (select auth.uid())=any(member_ids) or (select auth.uid())=any(spectator_ids));

create or replace function public.combat_watch_room(p_room_id uuid,p_watch boolean default true)
returns public.combat_rooms language plpgsql security definer set search_path='' as $$
declare r public.combat_rooms; uid uuid:=auth.uid();
begin
  if uid is null then raise exception '관전하려면 로그인해 주세요.';end if;
  if p_watch is null then raise exception '관전 설정을 확인해 주세요.';end if;
  select * into r from public.combat_rooms where id=p_room_id for update;
  if not found then raise exception '방을 찾을 수 없습니다.';end if;
  if p_watch then
    if uid=r.created_by or uid=any(r.member_ids) or uid=any(r.spectator_ids) then return r;end if;
    if r.status not in ('waiting','active') then raise exception '대기 중이거나 진행 중인 전투만 새로 관전할 수 있습니다.';end if;
    if cardinality(r.spectator_ids)>=100 then raise exception '관전자는 최대 100명입니다.';end if;
    update public.combat_rooms set spectator_ids=array_append(spectator_ids,uid) where id=r.id returning * into r;
  else
    if uid<>r.created_by and not uid=any(r.member_ids) and not uid=any(r.spectator_ids) then raise exception '관전 중인 방이 아닙니다.';end if;
    update public.combat_rooms set spectator_ids=array_remove(spectator_ids,uid) where id=r.id returning * into r;
  end if;
  -- 관전 출입은 카드 요청 버전·준비 상태·라운드·수정 시각을 변경하지 않습니다.
  return r;
end; $$;

create or replace function public.combat_list_rooms()
returns table(id uuid,name text,status text,player_count integer,created_by uuid,is_member boolean,updated_at timestamptz,version integer)
language sql stable security definer set search_path='' as $$
  select r.id,r.name,r.status,cardinality(r.member_ids),r.created_by,auth.uid()=any(r.member_ids),r.updated_at,r.version
  from public.combat_rooms r
  where auth.uid() is not null and (r.status in ('waiting','active') or r.created_by=auth.uid() or auth.uid()=any(r.member_ids) or auth.uid()=any(r.spectator_ids))
  order by r.updated_at desc limit 100;
$$;
revoke all on function public.combat_watch_room(uuid,boolean) from public,anon;
grant execute on function public.combat_watch_room(uuid,boolean) to authenticated;
revoke all on function public.combat_list_rooms() from public,anon;
grant execute on function public.combat_list_rooms() to authenticated;
notify pgrst,'reload schema';
commit;
